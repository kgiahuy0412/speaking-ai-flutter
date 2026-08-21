from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

from lxml import etree


W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W}


def main() -> None:
    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    records: list[dict[str, object]] = []

    with zipfile.ZipFile(source) as archive:
        parts = sorted(
            name
            for name in archive.namelist()
            if name == "word/document.xml"
            or name.startswith("word/header") and name.endswith(".xml")
            or name.startswith("word/footer") and name.endswith(".xml")
        )
        for part in parts:
            root = etree.fromstring(archive.read(part))
            for index, paragraph in enumerate(root.xpath(".//w:p", namespaces=NS)):
                nodes = paragraph.xpath(".//w:t", namespaces=NS)
                texts = [node.text or "" for node in nodes]
                full_text = "".join(texts)
                if not full_text.strip():
                    continue
                style_nodes = paragraph.xpath("./w:pPr/w:pStyle/@w:val", namespaces=NS)
                hyperlinks = paragraph.xpath(".//w:hyperlink", namespaces=NS)
                records.append(
                    {
                        "part": part,
                        "paragraph_index": index,
                        "style": style_nodes[0] if style_nodes else None,
                        "full_text": full_text,
                        "text_nodes": texts,
                        "has_hyperlink": bool(hyperlinks),
                    }
                )

    output.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"paragraphs={len(records)} output={output}")


if __name__ == "__main__":
    main()

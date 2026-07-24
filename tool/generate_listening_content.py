from __future__ import annotations

import argparse
import json
import math
import re
import unicodedata
from pathlib import Path
from typing import Iterator

from docx import Document
from docx.document import Document as DocumentType
from docx.oxml.table import CT_Tbl
from docx.oxml.text.paragraph import CT_P
from docx.table import Table
from docx.text.paragraph import Paragraph


def ascii_text(value: str) -> str:
    value = value.replace("\u2013", "-").replace("\u0110", "D").replace("\u0111", "d")
    return unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")


def iter_blocks(document: DocumentType) -> Iterator[Paragraph | Table]:
    for child in document.element.body.iterchildren():
        if isinstance(child, CT_P):
            yield Paragraph(child, document)
        elif isinstance(child, CT_Tbl):
            yield Table(child, document)


def split_bilingual_title(text: str) -> tuple[str, str]:
    body = text[text.find(".") + 1 :].strip()
    split_at = body.rfind(" (")
    if split_at < 0 or not body.endswith(")"):
        return body, ""
    return body[:split_at].strip(), body[split_at + 2 : -1].strip()


def build_catalog(source: Path) -> dict[str, object]:
    document = Document(source)
    groups: list[dict[str, object]] = []
    group: dict[str, object] | None = None
    topic: dict[str, object] | None = None
    lesson: dict[str, object] | None = None

    for block in iter_blocks(document):
        if isinstance(block, Paragraph):
            text = " ".join(block.text.split())
            normalized = ascii_text(text)

            match = re.match(
                r"PHAN\s+(\d+)\.\s+NHOM\s+(\d+)-(\d+)\s+tuoi",
                normalized,
                re.IGNORECASE,
            )
            if match:
                group = {
                    "startAge": int(match.group(2)),
                    "endAge": int(match.group(3)),
                    "topics": [],
                }
                groups.append(group)
                topic = None
                lesson = None
                continue

            match = re.match(
                r"Chu de\s+(\d+)\.\s+(.+?)\s+\((.+)\)$",
                normalized,
                re.IGNORECASE,
            )
            if match and group is not None:
                number = int(match.group(1))
                title_vi, title_en = split_bilingual_title(text)
                topic = {
                    "id": f"age-{group['startAge']}-{group['endAge']}-topic-{number}",
                    "number": number,
                    "titleVi": title_vi,
                    "titleEn": title_en,
                    "lessons": [],
                }
                group["topics"].append(topic)
                lesson = None
                continue

            match = re.match(
                r"Bai\s+(\d+)\.\s+(.+?)\s+\((.+)\)$",
                normalized,
                re.IGNORECASE,
            )
            if match and topic is not None:
                number = int(match.group(1))
                title_vi, title_en = split_bilingual_title(text)
                lesson = {
                    "id": f"{topic['id']}-lesson-{number}",
                    "number": number,
                    "titleVi": title_vi,
                    "titleEn": title_en,
                    "intro": "",
                    "outro": "",
                    "estimatedMinutes": 3,
                    "introAudioUrl": None,
                    "outroAudioUrl": None,
                    "sentences": [],
                }
                topic["lessons"].append(lesson)
                continue

        elif lesson is not None:
            rows = [[cell.text.strip() for cell in row.cells] for row in block.rows]
            if len(rows) == 1 and len(rows[0]) == 1:
                value = rows[0][0]
                normalized = ascii_text(value)
                if normalized.startswith("Loi mo dau tu dong:"):
                    lesson["intro"] = value.split(":", 1)[1].strip()
                elif normalized.startswith("Loi ket tu dong:"):
                    lesson["outro"] = value.split(":", 1)[1].strip()
            elif rows and len(rows[0]) >= 3 and ascii_text(rows[0][0]).upper() == "STT":
                sentences: list[dict[str, object]] = lesson["sentences"]
                for row in rows[1:]:
                    if len(row) < 3 or not row[1].strip():
                        continue
                    sentences.append(
                        {
                            "number": len(sentences) + 1,
                            "english": row[1].strip(),
                            "vietnamese": row[2].strip(),
                            "audioUrl": None,
                            "vietnameseAudioUrl": None,
                        }
                    )
                lesson["estimatedMinutes"] = max(3, math.ceil(len(sentences) * 0.35))

    catalog = {
        "schemaVersion": 1,
        "source": source.name,
        "audioProvider": "cloudinary",
        "groups": groups,
    }
    validate_catalog(catalog)
    return catalog


def validate_catalog(catalog: dict[str, object]) -> None:
    groups = catalog["groups"]
    topics = [topic for group in groups for topic in group["topics"]]
    lessons = [lesson for topic in topics for lesson in topic["lessons"]]
    sentences = [sentence for lesson in lessons for sentence in lesson["sentences"]]
    counts = (len(groups), len(topics), len(lessons), len(sentences))
    if counts != (5, 50, 111, 836):
        raise ValueError(
            "Unexpected content counts: "
            f"groups={counts[0]}, topics={counts[1]}, lessons={counts[2]}, sentences={counts[3]}"
        )
    if any(not lesson["intro"] or not lesson["outro"] for lesson in lessons):
        raise ValueError("Every lesson must include automatic intro and outro copy.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    catalog = build_catalog(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()

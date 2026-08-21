from __future__ import annotations

import hashlib
import json
import sys
import zipfile
from pathlib import Path


def main() -> None:
    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    records: list[dict[str, object]] = []
    with zipfile.ZipFile(source) as archive:
        for info in sorted(archive.infolist(), key=lambda item: item.filename):
            data = archive.read(info.filename)
            records.append(
                {
                    "path": info.filename,
                    "size": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
            )
    output.write_text(json.dumps(records, indent=2), encoding="utf-8")
    print(f"parts={len(records)} output={output}")


if __name__ == "__main__":
    main()

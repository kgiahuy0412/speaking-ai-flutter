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


EXPECTED = {
    (3, 5): (10, 21, 116, 6, 39, 0),
    (6, 7): (10, 20, 118, 3, 18, 0),
    (8, 10): (10, 20, 120, 2, 12, 11),
    (11, 12): (10, 20, 140, 0, 0, 14),
    (13, 15): (10, 20, 140, 0, 0, 12),
}

REVIEW_PAUSE_MS = {(3, 5): 1000, (6, 7): 900, (8, 10): 800, (11, 12): 700, (13, 15): 600}
AUTO_ADVANCE_MS = {(3, 5): 2750, (6, 7): 2500, (8, 10): 2000, (11, 12): 1750, (13, 15): 1250}
OUTROS = {
    (3, 5): "Con hoàn thành rồi! Làm tốt lắm! Hẹn gặp con ở bài tiếp theo!",
    (6, 7): "Con hoàn thành bài rồi! Làm tốt lắm! Hẹn gặp lại!",
    (8, 10): "Great work! Con hoàn thành bài rồi! Hẹn gặp bài sau!",
    (11, 12): "Lesson complete! Well done! Hẹn gặp bài tiếp theo!",
    (13, 15): "Lesson complete. Great work! Keep practicing!",
}


def ascii_text(value: str) -> str:
    value = value.replace("\u2013", "-").replace("\u0110", "D").replace("\u0111", "d")
    return unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")


def clean(value: str) -> str:
    return " ".join(value.replace("\xa0", " ").split())


def iter_blocks(document: DocumentType) -> Iterator[Paragraph | Table]:
    for child in document.element.body.iterchildren():
        if isinstance(child, CT_P):
            yield Paragraph(child, document)
        elif isinstance(child, CT_Tbl):
            yield Table(child, document)


def split_bilingual_title(text: str) -> tuple[str, str]:
    body = text[text.find(".") + 1 :].strip() if "." in text else text.strip()
    split_at = body.rfind(" (")
    if split_at < 0 or not body.endswith(")"):
        return body, ""
    return body[:split_at].strip(), body[split_at + 2 : -1].strip()


def first_prefixed(values: list[str], prefix: str) -> str | None:
    normalized_prefix = ascii_text(prefix).lower()
    for value in values:
        normalized = ascii_text(value).lower()
        if normalized.startswith(normalized_prefix):
            return value.split(":", 1)[1].strip() if ":" in value else value
    return None


def table_values(table: Table) -> list[list[str]]:
    return [[clean(cell.text) for cell in row.cells] for row in table.rows]


def parse_sentence_rows(
    rows: list[list[str]],
    item: dict[str, object],
) -> None:
    for row_index, row in enumerate(rows):
        normalized = [ascii_text(value).lower() for value in row]
        english_index = next(
            (i for i, value in enumerate(normalized) if value in {"cau tieng anh", "loi tieng anh"}),
            None,
        )
        vietnamese_index = next(
            (
                i
                for i, value in enumerate(normalized)
                if value in {"nghia tieng viet", "loi viet theo nhip"}
            ),
            None,
        )
        if english_index is None or vietnamese_index is None:
            continue
        voice_index = next(
            (i for i, value in enumerate(normalized) if value == "giong"),
            None,
        )
        sentences: list[dict[str, object]] = item["sentences"]  # type: ignore[assignment]
        code = str(item.get("code") or item["id"])
        for values in rows[row_index + 1 :]:
            if max(english_index, vietnamese_index) >= len(values):
                continue
            english = values[english_index].strip()
            vietnamese = values[vietnamese_index].strip()
            if not english:
                continue
            number = len(sentences) + 1
            sentence_code = f"{code}_S{number:02d}"
            voice = ""
            if voice_index is not None and voice_index < len(values):
                voice = values[voice_index].strip()
            sentences.append(
                {
                    "id": sentence_code,
                    "number": number,
                    "voice": voice,
                    "english": english,
                    "vietnamese": vietnamese,
                    "englishAudioId": f"{sentence_code}_EN",
                    "vietnameseAudioId": f"{sentence_code}_VI",
                    "audioUrl": None,
                    "vietnameseAudioUrl": None,
                }
            )
        return


def make_item(
    *,
    item_id: str,
    number: int,
    title_vi: str,
    title_en: str,
    lesson_type: str,
    ages: tuple[int, int],
) -> dict[str, object]:
    return {
        "id": item_id,
        "code": "",
        "number": number,
        "titleVi": title_vi,
        "titleEn": title_en,
        "lessonType": lesson_type,
        "intro": "",
        "outro": OUTROS[ages],
        "estimatedMinutes": 3,
        "reviewPauseMs": REVIEW_PAUSE_MS[ages],
        "autoAdvanceMs": AUTO_ADVANCE_MS[ages],
        "introAudioUrl": None,
        "outroAudioUrl": None,
        "fullAudioId": None,
        "fullAudioUrl": None,
        "sentences": [],
    }


def build_catalog(source: Path) -> dict[str, object]:
    document = Document(source)
    groups: list[dict[str, object]] = []
    group: dict[str, object] | None = None
    topic: dict[str, object] | None = None
    item: dict[str, object] | None = None
    in_content = False

    for block in iter_blocks(document):
        if isinstance(block, Paragraph):
            text = clean(block.text)
            normalized = ascii_text(text)
            if normalized.startswith("9. Noi dung chi tiet"):
                in_content = True
                continue
            if normalized.startswith("10. Yeu cau ky thuat"):
                break
            if not in_content or not text:
                continue

            group_match = re.match(r"^(\d+)-(\d+)\s+tuoi\s+-\s+(.+)$", normalized, re.IGNORECASE)
            if group_match:
                ages = (int(group_match.group(1)), int(group_match.group(2)))
                group = {
                    "startAge": ages[0],
                    "endAge": ages[1],
                    "label": text,
                    "reviewPauseMs": REVIEW_PAUSE_MS[ages],
                    "autoAdvanceMs": AUTO_ADVANCE_MS[ages],
                    "topics": [],
                }
                groups.append(group)
                topic = None
                item = None
                continue

            topic_match = re.match(r"^Chu de\s+(\d+)\.\s+", normalized, re.IGNORECASE)
            if topic_match and group is not None:
                number = int(topic_match.group(1))
                title_vi, title_en = split_bilingual_title(text)
                topic = {
                    "id": f"age-{group['startAge']}-{group['endAge']}-topic-{number}",
                    "number": number,
                    "titleVi": title_vi,
                    "titleEn": title_en,
                    "lessons": [],
                    "songs": [],
                }
                group["topics"].append(topic)  # type: ignore[index]
                item = None
                continue

            lesson_match = re.match(r"^Bai\s+(\d+)\.\s+", normalized, re.IGNORECASE)
            if lesson_match and topic is not None and group is not None:
                number = int(lesson_match.group(1))
                title_vi, title_en = split_bilingual_title(text)
                ages = (int(group["startAge"]), int(group["endAge"]))
                item = make_item(
                    item_id=f"{topic['id']}-lesson-{number}",
                    number=number,
                    title_vi=title_vi,
                    title_en=title_en,
                    lesson_type="standard",
                    ages=ages,
                )
                topic["lessons"].append(item)  # type: ignore[index]
                continue

            if normalized.lower().startswith("bai hat/chant:") and topic is not None and group is not None:
                songs: list[dict[str, object]] = topic["songs"]  # type: ignore[assignment]
                title_vi, title_en = split_bilingual_title(text.replace("Bài hát/Chant:", "", 1))
                ages = (int(group["startAge"]), int(group["endAge"]))
                item = make_item(
                    item_id=f"{topic['id']}-song-{len(songs) + 1}",
                    number=len(songs) + 1,
                    title_vi=title_vi,
                    title_en=title_en,
                    lesson_type="song",
                    ages=ages,
                )
                songs.append(item)
                continue

            if item is not None and normalized.lower().startswith("ghi chu trien khai:"):
                if "hoi thoai hoan chinh" in normalized.lower():
                    item["lessonType"] = "dialogue"
                    code = str(item.get("code") or item["id"])
                    item["fullAudioId"] = f"{code}_FULL_EN"
                continue

        elif in_content and item is not None:
            rows = table_values(block)
            flattened = [value for row in rows for value in row if value]
            code = first_prefixed(flattened, "Mã bài") or first_prefixed(flattened, "Mã")
            if code:
                item["code"] = code
                item["id"] = code.lower()
                if item["lessonType"] == "song":
                    item["fullAudioId"] = f"{code}_FULL_EN"
            lesson_type = first_prefixed(flattened, "Loại bài")
            if lesson_type and "hội thoại" in lesson_type.lower():
                item["lessonType"] = "dialogue"
                if code:
                    item["fullAudioId"] = f"{code}_FULL_EN"
            intro = (
                first_prefixed(flattened, "Lời mở đầu cần tạo audio")
                or first_prefixed(flattened, "Lời mở đầu bài hát/chant cần tạo audio")
            )
            if intro:
                item["intro"] = intro
            parse_sentence_rows(rows, item)
            sentences: list[dict[str, object]] = item["sentences"]  # type: ignore[assignment]
            item["estimatedMinutes"] = max(2, math.ceil(len(sentences) * 0.45))

    catalog = {
        "schemaVersion": 2,
        "source": source.name,
        "audioProvider": "cloudinary",
        "groups": groups,
    }
    validate_catalog(catalog)
    return catalog


def validate_catalog(catalog: dict[str, object]) -> None:
    groups: list[dict[str, object]] = catalog["groups"]  # type: ignore[assignment]
    all_ids: list[str] = []
    for group in groups:
        topics: list[dict[str, object]] = group["topics"]  # type: ignore[assignment]
        lessons = [lesson for topic in topics for lesson in topic["lessons"]]
        songs = [song for topic in topics for song in topic["songs"]]
        sentences = [sentence for lesson in lessons for sentence in lesson["sentences"]]
        song_lines = [sentence for song in songs for sentence in song["sentences"]]
        dialogues = sum(lesson["lessonType"] == "dialogue" for lesson in lessons)
        ages = (int(group["startAge"]), int(group["endAge"]))
        actual = (len(topics), len(lessons), len(sentences), len(songs), len(song_lines), dialogues)
        if actual != EXPECTED[ages]:
            raise ValueError(f"Unexpected counts for {ages}: expected={EXPECTED[ages]} actual={actual}")
        items = lessons + songs
        if any(not item["intro"] or not item["outro"] for item in items):
            raise ValueError(f"Every lesson/song must include intro and outro for {ages}.")
        all_ids.extend(str(item["id"]) for item in items)
        all_ids.extend(str(sentence["id"]) for item in items for sentence in item["sentences"])
    if len(all_ids) != len(set(all_ids)):
        raise ValueError("Lesson, song and sentence IDs must be globally unique.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    catalog = build_catalog(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

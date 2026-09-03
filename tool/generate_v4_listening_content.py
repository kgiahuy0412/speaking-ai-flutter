"""Generate the checked-in V4 listening catalog from the authored V4 spec.

The source document is intentionally kept outside the app bundle.  This tool
turns its line-oriented IT/TTS export into deterministic runtime data, an audio
manifest, and an ASR/assistant lexicon.  It never invents questions: every
Challenge and Mission comes from the authored bank in the source file.

Usage (from the repository root):
  python tool/generate_v4_listening_content.py \
    "C:\\Users\\Windows\\Downloads\\AIV0_HOMI_Spec_..._V4_...txt"
"""

from __future__ import annotations

import argparse
import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = ROOT / "assets" / "data" / "listening_lessons.json"
AUDIO_MANIFEST_PATH = ROOT / "assets" / "data" / "listening_audio_manifest_v4.json"
LEXICON_PATH = ROOT / "assets" / "data" / "listening_ai_lexicon_v4.json"

EXPECTED_COUNTS = {
    "courses": 5,
    "levels": 15,
    "topics": 50,
    "lessons": 109,
    "targets": 601,
    "challenges": 872,
    "missions": 180,
}

AGE_LABELS = {
    (3, 5): "3–5 tuổi – Làm quen tiếng Anh",
    (6, 7): "6–7 tuổi – Nền tảng giao tiếp",
    (8, 10): "8–10 tuổi – Giao tiếp tình huống",
    (11, 12): "11–12 tuổi – Tư duy và ứng dụng",
    (13, 15): "13–15 tuổi – Giao tiếp độc lập",
}

LEVEL_TITLES = {
    1: "Xây nền",
    2: "Kết hợp",
    3: "Ứng dụng",
}

SYSTEM_AUDIO = (
    ("LEVEL_INTRO", "vi-VN", "Bắt đầu Level [số] nhé."),
    ("TOPIC_INTRO", "vi-VN", "Chủ đề [số]: [Tên Chủ đề]."),
    ("FIRST_LESSON", "vi-VN", "Bài đầu tiên là [Tên Bài]."),
    ("NEXT_LESSON", "vi-VN", "Bài này là [Tên Bài]."),
    ("OVERVIEW_CUE", "vi-VN", "Bạn nghe qua nội dung trước nhé."),
    ("DETAIL_TRANSITION", "vi-VN", "Bây giờ mình học từng phần nhé."),
    ("REPEAT_TARGET", "vi-VN", "Bạn nói lại tiếng Anh nhé."),
    (
        "SONG_PREALERT",
        "vi-VN",
        "Tiếp theo là hai câu thử thách. Xong rồi mình nghe bài hát [SONG_TITLE] nhé.",
    ),
    ("SONG_START_CUE", "vi-VN", "Bây giờ cùng nghe [SONG_TITLE] nhé."),
    ("MISSION_CUE", "vi-VN", "Tiếp theo là Nhiệm vụ cuối Level."),
    ("MISSION_REMEDIATE", "vi-VN", "Mình luyện nhanh vài phần rồi thử lại nhé."),
    ("MISSION_RETRY", "vi-VN", "Xong rồi. Mình thử lại Nhiệm vụ cuối Level nhé."),
    ("RESUME_LESSON", "vi-VN", "Mình học tiếp bài [Tên Bài] nhé."),
    ("RESUME_ROLE_PLAY", "vi-VN", "Mình tiếp tục đoạn hội thoại nhé."),
    ("RESUME_CHALLENGE", "vi-VN", "Mình làm lại phần thử thách nhé."),
    ("RESUME_MISSION", "vi-VN", "Mình tiếp tục Nhiệm vụ cuối Level nhé."),
    ("FULL_TARGET_REQUIRED", "vi-VN", "Bạn nói đầy đủ câu nhé."),
)


# These are authored role-plays from section 3 of the V4 production spec.
# Lesson codes are the join key. Titles are not unique across the curriculum
# (for example, "Make a Plan" appears in a non-role-play lesson too).
ROLE_PLAYS: dict[str, dict[str, Any]] = {
    "C810-L1-T02-B02": {
        "scenarioVi": "Bạn đang ở trước cửa lớp.",
        "openingHint": "Can I...",
        "turns": [
            ("child", "Can I come in?", "Mình có thể vào lớp không?"),
            ("homi", "Yes, come in.", "Được, vào đi."),
            ("child", "Thank you.", "Cảm ơn bạn."),
        ],
    },
    "C810-L2-T04-B03": {
        "scenarioVi": "Bạn cần tìm thư viện.",
        "openingHint": "Where's...",
        "turns": [
            ("child", "Where's the library?", "Thư viện ở đâu?"),
            ("homi", "Go straight.", "Đi thẳng."),
            ("child", "Thank you.", "Cảm ơn bạn."),
        ],
    },
    "C810-L3-T07-B02": {
        "scenarioVi": "Bạn muốn hỏi giá món đồ.",
        "openingHint": "How much...",
        "turns": [
            ("child", "How much?", "Bao nhiêu tiền?"),
            ("homi", "Five dollars.", "Năm đô-la."),
            ("child", "It's cheap.", "Nó rẻ."),
        ],
    },
    "C810-L3-T08-B02": {
        "scenarioVi": "Bạn của bạn trông không vui.",
        "turns": [
            ("homi", "Are you okay?", "Bạn ổn không?"),
            ("child", "I'm sad.", "Mình buồn."),
            ("homi", "Can I help?", "Mình giúp được không?"),
            ("child", "Yes, please.", "Có, giúp mình nhé."),
        ],
    },
    "C1112-L3-T07-B02": {
        "scenarioVi": "Bạn và một người bạn đang chọn ngày gặp nhau.",
        "turns": [
            ("homi", "Are you free Saturday?", "Thứ Bảy bạn rảnh không?"),
            ("child", "How about Sunday?", "Chủ nhật thì sao?"),
            ("homi", "Let's meet at three.", "Mình gặp lúc ba giờ nhé."),
            ("child", "See you there.", "Gặp bạn ở đó nhé."),
        ],
    },
    "C1112-L3-T08-B02": {
        "scenarioVi": "Bạn đang ở cửa hàng và muốn hỏi giá.",
        "openingHint": "How much...",
        "turns": [
            ("child", "How much is this?", "Cái này bao nhiêu tiền?"),
            ("homi", "It's twenty dollars.", "Nó giá hai mươi đô-la."),
            ("child", "Is there a cheaper one?", "Có cái nào rẻ hơn không?"),
        ],
    },
    "C1315-L1-T03-B01": {
        "scenarioVi": "Bạn và HOMI đang trao đổi ý kiến.",
        "turns": [
            ("homi", "What do you think?", "Bạn nghĩ sao?"),
            ("child", "I'm not sure.", "Mình chưa chắc."),
            ("homi", "I think it's useful.", "Mình nghĩ nó hữu ích."),
            ("child", "I agree.", "Mình đồng ý."),
        ],
    },
    "C1315-L3-T07-B02": {
        "scenarioVi": "Bạn đang ở nhà ga và cần hỏi thông tin.",
        "openingHint": "Which...",
        "turns": [
            ("child", "Which platform?", "Sân ga nào?"),
            ("homi", "Platform three.", "Sân ga số ba."),
            ("child", "What time does it leave?", "Mấy giờ tàu chạy?"),
            ("homi", "At five thirty.", "Lúc năm giờ rưỡi."),
        ],
    },
    "C1315-L3-T08-B02": {
        "scenarioVi": "Bạn đang gọi món tại nhà hàng.",
        "turns": [
            ("homi", "Ready to order?", "Bạn sẵn sàng gọi món chưa?"),
            ("child", "I'd like noodles.", "Mình muốn gọi mì."),
            ("homi", "Anything to drink?", "Bạn uống gì không?"),
            ("child", "Water, please.", "Cho mình nước nhé."),
            ("homi", "Anything else?", "Bạn cần thêm gì không?"),
            ("child", "That's all, thanks.", "Vậy thôi, cảm ơn."),
        ],
    },
    "C1315-L3-T09-B02": {
        "scenarioVi": "Bạn đang chọn giữa hai lựa chọn.",
        "turns": [
            ("homi", "Which one do you prefer?", "Bạn thích cái nào hơn?"),
            ("child", "I prefer this one.", "Mình thích cái này hơn."),
            ("homi", "Why?", "Tại sao?"),
            ("child", "It's more useful.", "Nó hữu ích hơn."),
        ],
    },
}


COURSE_RE = re.compile(r"^=== KHÓA (\d+)-(\d+) TUỔI ===$")
LEVEL_RE = re.compile(r"^-- LEVEL (\d+) --$")
TOPIC_RE = re.compile(r"^Chủ đề (\d+): (.+) \((.+)\)$")
LESSON_RE = re.compile(r"^Bài (\d+): (.+) \[([A-Z0-9-]+)]$")
ENTRY_RE = re.compile(r"^Cách mở Bài=(.+?):\s*(.+)$")
SONG_RE = re.compile(r"^Bài hát:\s*(.+)$")
TARGET_RE = re.compile(
    r"^([A-Z0-9-]+-T\d+) \| Tiếng Anh=(.+?) \| Nghĩa tiếng Việt=(.+)$"
)
CHALLENGE_RE = re.compile(
    r"^([A-Z0-9-]+-Q\d+) \| Dạng=(.+?) \| Câu hỏi=(.+?) "
    r"\| Lựa chọn=(.+?) \|\| (.+?) \| Đáp án đúng=(.+?) "
    r"\| Nghĩa đáp án=(.+?) \| Target kiểm tra=([A-Z0-9-]+-T\d+)$"
)
MISSION_HEADER_RE = re.compile(r"^=== (\d+)-(\d+) / LEVEL (\d+) ===$")
MISSION_RE = re.compile(
    r"^([A-Z0-9-]+-M\d+) \| Topic (\d+) \| ([A-Z_]+) \| (.+?) "
    r"\| choices=(.+?) \|\| (.+?) \| correct=(.+?) \| coverage=([A-Z0-9-]+-T\d+)$"
)


def compact(value: str) -> str:
    return " ".join(value.replace("\u00a0", " ").split())


def clean_title(value: str) -> str:
    return value.strip().replace("  ", " ")


def slug(value: str) -> str:
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", ascii_value.lower()).strip("-")


def normalized_phrase(value: str) -> str:
    value = value.replace("’", "'").strip().lower()
    contractions = {
        "i'm": "i am",
        "you're": "you are",
        "he's": "he is",
        "she's": "she is",
        "it's": "it is",
        "we're": "we are",
        "they're": "they are",
        "that's": "that is",
        "what's": "what is",
        "where's": "where is",
        "let's": "let us",
        "i'll": "i will",
        "i'd": "i would",
        "can't": "cannot",
        "don't": "do not",
        "doesn't": "does not",
        "isn't": "is not",
        "aren't": "are not",
        "won't": "will not",
    }
    for left, right in contractions.items():
        value = re.sub(rf"\b{re.escape(left)}\b", right, value)
    return " ".join(re.sub(r"[^a-z0-9]+", " ", value).split())


def recognition_variants(value: str) -> list[str]:
    """Return exact, meaning-preserving ASR spellings only.

    The app's matcher canonicalizes apostrophes too, but surfacing both forms
    to a remote recognizer makes the context explicit without accepting a
    different target or a partial Alphabet answer.
    """

    variants = {value}
    substitutions = {
        "I'm": "I am",
        "You're": "You are",
        "He's": "He is",
        "She's": "She is",
        "It's": "It is",
        "We're": "We are",
        "They're": "They are",
        "That's": "That is",
        "What's": "What is",
        "Where's": "Where is",
        "Let's": "Let us",
        "I'll": "I will",
        "I'd": "I would",
        "can't": "cannot",
        "don't": "do not",
        "doesn't": "does not",
        "isn't": "is not",
        "aren't": "are not",
        "won't": "will not",
    }
    for left, right in substitutions.items():
        if left.lower() in value.lower():
            variants.add(re.sub(re.escape(left), right, value, flags=re.IGNORECASE))
    return sorted(variants, key=lambda item: (item != value, item))


def make_role_play(code: str) -> dict[str, Any] | None:
    spec = ROLE_PLAYS.get(code)
    if spec is None:
        return None
    return {
        "scenarioVi": spec["scenarioVi"],
        "openingHint": spec.get("openingHint"),
        "turns": [
            {"speaker": speaker, "english": english, "vietnamese": vietnamese}
            for speaker, english, vietnamese in spec["turns"]
        ],
    }


def make_lesson(
    *,
    number: int,
    title: str,
    code: str,
    age_range: tuple[int, int],
) -> dict[str, Any]:
    return {
        "id": code.lower(),
        "code": code,
        "number": number,
        # V4 deliberately keeps lesson names English for audio-first delivery.
        "titleVi": title,
        "titleEn": title,
        "lessonType": "standard",
        "intro": "",
        "outro": "",
        "estimatedMinutes": 4,
        "reviewPauseMs": 2000,
        "autoAdvanceMs": 2000,
        "introAudioUrl": None,
        "outroAudioUrl": None,
        "fullAudioId": None,
        "fullAudioUrl": None,
        "overviewAudioId": f"{code}_OVERVIEW_EN" if age_range[0] >= 11 else None,
        "overviewAudioUrl": None,
        "entry": None,
        "overviewMode": "englishOnly" if age_range[0] >= 11 else "bilingual",
        "challengeBank": [],
        "rolePlay": make_role_play(code),
        "songTitle": None,
        "sentences": [],
    }


def parse_spec(source: Path) -> dict[str, Any]:
    groups: list[dict[str, Any]] = []
    group: dict[str, Any] | None = None
    level: dict[str, Any] | None = None
    topic: dict[str, Any] | None = None
    lesson: dict[str, Any] | None = None
    in_missions = False
    target_translation: dict[str, str] = {}

    for raw_line in source.read_text(encoding="utf-8-sig").splitlines():
        line = compact(raw_line)
        if not line:
            continue
        if line == "14. MISSION BANKS":
            in_missions = True
            group = None
            level = None
            topic = None
            lesson = None
            continue

        if in_missions:
            header = MISSION_HEADER_RE.match(line)
            if header:
                ages = (int(header.group(1)), int(header.group(2)))
                level_number = int(header.group(3))
                group = next(
                    item
                    for item in groups
                    if (item["startAge"], item["endAge"]) == ages
                )
                level = next(
                    item for item in group["levels"] if item["number"] == level_number
                )
                continue
            mission_match = MISSION_RE.match(line)
            if mission_match:
                if level is None:
                    raise ValueError(f"Mission without a level: {line}")
                (
                    question_id,
                    topic_number,
                    question_format,
                    prompt,
                    choice_a,
                    choice_b,
                    correct,
                    coverage_target_id,
                ) = mission_match.groups()
                level["missionBank"].append(
                    {
                        "id": question_id,
                        "topicNumber": int(topic_number),
                        "format": question_format,
                        "prompt": prompt,
                        "choices": [choice_a, choice_b],
                        "correctAnswer": correct,
                        "coverageTargetId": coverage_target_id,
                    }
                )
            continue

        course_match = COURSE_RE.match(line)
        if course_match:
            ages = (int(course_match.group(1)), int(course_match.group(2)))
            group = {
                "startAge": ages[0],
                "endAge": ages[1],
                "label": AGE_LABELS[ages],
                "levels": [],
                "topics": [],
            }
            groups.append(group)
            level = None
            topic = None
            lesson = None
            continue

        level_match = LEVEL_RE.match(line)
        if level_match:
            if group is None:
                raise ValueError(f"Level without course: {line}")
            number = int(level_match.group(1))
            level = {
                "id": f"C{group['startAge']}{group['endAge']}-L{number}",
                "number": number,
                "titleVi": LEVEL_TITLES[number],
                "topicNumbers": [],
                "missionBank": [],
            }
            group["levels"].append(level)
            topic = None
            lesson = None
            continue

        topic_match = TOPIC_RE.match(line)
        if topic_match:
            if group is None or level is None:
                raise ValueError(f"Topic without level: {line}")
            number, title_en, title_vi = topic_match.groups()
            number = int(number)
            topic = {
                "id": f"c{group['startAge']}{group['endAge']}-l{level['number']}-t{number:02d}",
                "number": number,
                "levelNumber": level["number"],
                "titleVi": clean_title(title_vi),
                "titleEn": clean_title(title_en),
                "lessons": [],
                "songs": [],
            }
            group["topics"].append(topic)
            level["topicNumbers"].append(number)
            lesson = None
            continue

        lesson_match = LESSON_RE.match(line)
        if lesson_match:
            if group is None or topic is None:
                raise ValueError(f"Lesson without topic: {line}")
            number, title, code = lesson_match.groups()
            lesson = make_lesson(
                number=int(number),
                title=clean_title(title),
                code=code,
                age_range=(group["startAge"], group["endAge"]),
            )
            topic["lessons"].append(lesson)
            continue

        if lesson is None:
            continue

        entry_match = ENTRY_RE.match(line)
        if entry_match:
            raw_kind, text = entry_match.groups()
            lesson["entry"] = {
                "kind": "hook" if "HOOK" in raw_kind else "microObjective",
                "text": text,
            }
            lesson["intro"] = text
            continue

        song_match = SONG_RE.match(line)
        if song_match:
            lesson["songTitle"] = song_match.group(1)
            # V4 tracks songs as a separate source-audio handoff. This is
            # deliberately not the legacy lesson `fullAudioUrl` field.
            lesson["songAudioId"] = f"{lesson['code']}_SONG"
            continue

        target_match = TARGET_RE.match(line)
        if target_match:
            target_id, english, vietnamese = target_match.groups()
            number = len(lesson["sentences"]) + 1
            is_alphabet = (
                topic["number"] == 1
                and group is not None
                and (group["startAge"], group["endAge"]) in {(3, 5), (6, 7)}
            )
            lesson["sentences"].append(
                {
                    "id": target_id,
                    "number": number,
                    "voice": "",
                    "english": english,
                    "vietnamese": vietnamese,
                    "englishAudioId": f"{target_id}_EN",
                    "vietnameseAudioId": f"{target_id}_VI",
                    "audioUrl": None,
                    "vietnameseAudioUrl": None,
                    "recognitionVariants": recognition_variants(english),
                    "requiresAllExpectedTokens": is_alphabet,
                }
            )
            target_translation[target_id] = vietnamese
            continue

        challenge_match = CHALLENGE_RE.match(line)
        if challenge_match:
            (
                question_id,
                question_format,
                prompt,
                choice_a,
                choice_b,
                correct,
                correct_vietnamese,
                target_id,
            ) = challenge_match.groups()
            lesson["challengeBank"].append(
                {
                    "id": question_id,
                    "format": question_format.split(" ", 1)[0],
                    "prompt": prompt,
                    "choices": [choice_a, choice_b],
                    "correctAnswer": correct,
                    "correctVietnamese": correct_vietnamese,
                    "targetId": target_id,
                }
            )

    for current_group in groups:
        for current_level in current_group["levels"]:
            for mission in current_level["missionBank"]:
                coverage = mission["coverageTargetId"]
                mission["correctVietnamese"] = target_translation.get(coverage, "")
            if len(current_level["missionBank"]) != 12:
                raise ValueError(
                    f"{current_level['id']} has {len(current_level['missionBank'])} mission questions, expected 12."
                )

    catalog = {
        "schemaVersion": 4,
        "contentVersion": "4.0",
        "source": source.name,
        "audioProvider": "v4-tts-manifest-pending",
        "groups": groups,
    }
    validate_catalog(catalog)
    return catalog


def iter_lessons(catalog: dict[str, Any]):
    for group in catalog["groups"]:
        for topic in group["topics"]:
            for lesson in topic["lessons"]:
                yield group, topic, lesson


def validate_catalog(catalog: dict[str, Any]) -> None:
    groups = catalog["groups"]
    levels = [level for group in groups for level in group["levels"]]
    topics = [topic for group in groups for topic in group["topics"]]
    lessons = [lesson for _, _, lesson in iter_lessons(catalog)]
    targets = [sentence for lesson in lessons for sentence in lesson["sentences"]]
    challenges = [question for lesson in lessons for question in lesson["challengeBank"]]
    missions = [question for level in levels for question in level["missionBank"]]
    actual = {
        "courses": len(groups),
        "levels": len(levels),
        "topics": len(topics),
        "lessons": len(lessons),
        "targets": len(targets),
        "challenges": len(challenges),
        "missions": len(missions),
    }
    if actual != EXPECTED_COUNTS:
        raise ValueError(f"V4 count mismatch: expected {EXPECTED_COUNTS}, got {actual}")
    if any(len(lesson["challengeBank"]) != 8 for lesson in lessons):
        raise ValueError("Every V4 lesson must contain exactly eight authored Challenge questions.")
    if any(len(question["choices"]) != 2 for question in challenges + missions):
        raise ValueError("Every authored V4 question must contain exactly two choices.")
    target_ids = {sentence["id"] for sentence in targets}
    for question in challenges:
        if question["targetId"] not in target_ids:
            raise ValueError(f"Challenge has unknown target: {question['id']}")
    for question in missions:
        if question["coverageTargetId"] not in target_ids:
            raise ValueError(f"Mission has unknown target: {question['id']}")


def build_audio_manifest(catalog: dict[str, Any]) -> dict[str, Any]:
    entries: list[dict[str, Any]] = [
        {
            "audioId": audio_id,
            "kind": "systemPrompt",
            "locale": locale,
            "sourceText": text,
            "qaStatus": "PENDING_TTS",
        }
        for audio_id, locale, text in SYSTEM_AUDIO
    ]
    for group, topic, lesson in iter_lessons(catalog):
        prefix = {
            "course": f"{group['startAge']}-{group['endAge']}",
            "level": lesson["code"].split("-")[1],
            "topic": topic["number"],
            "lessonCode": lesson["code"],
        }
        entry = lesson.get("entry")
        if entry:
            entries.append(
                {
                    "audioId": f"{lesson['code']}_ENTRY",
                    "kind": entry["kind"],
                    "locale": "vi-VN",
                    "sourceText": entry["text"],
                    "qaStatus": "PENDING_TTS",
                    **prefix,
                }
            )
        if lesson["overviewMode"] == "englishOnly":
            entries.append(
                {
                    "audioId": lesson["overviewAudioId"],
                    "kind": "overviewEnglishOnly",
                    "locale": "en-US",
                    "sourceText": " ".join(
                        sentence["english"] for sentence in lesson["sentences"]
                    ),
                    "qaStatus": "PENDING_TTS",
                    **prefix,
                }
            )
        for sentence in lesson["sentences"]:
            entries.extend(
                [
                    {
                        "audioId": sentence["englishAudioId"],
                        "kind": "coreEnglish",
                        "locale": "en-US",
                        "sourceText": sentence["english"],
                        "targetId": sentence["id"],
                        "qaStatus": "PENDING_TTS",
                        **prefix,
                    },
                    {
                        "audioId": sentence["vietnameseAudioId"],
                        "kind": "coreVietnamese",
                        "locale": "vi-VN",
                        "sourceText": sentence["vietnamese"],
                        "targetId": sentence["id"],
                        "qaStatus": "PENDING_TTS",
                        **prefix,
                    },
                ]
            )
        for question in lesson["challengeBank"]:
            entries.append(
                {
                    "audioId": f"{question['id']}_PROMPT",
                    "kind": "challengePrompt",
                    "locale": "vi-VN",
                    "sourceText": question["prompt"],
                    "questionId": question["id"],
                    "targetId": question["targetId"],
                    "qaStatus": "PENDING_TTS",
                    **prefix,
                }
            )
        role_play = lesson.get("rolePlay")
        if role_play:
            for index, turn in enumerate(role_play["turns"], start=1):
                entries.append(
                    {
                        "audioId": f"{lesson['code']}_ROLEPLAY_{index:02d}",
                        "kind": f"rolePlay{turn['speaker'].title()}",
                        "locale": "en-US",
                        "sourceText": turn["english"],
                        "qaStatus": "PENDING_TTS",
                        **prefix,
                    }
                )
        song_title = lesson.get("songTitle")
        if song_title:
            # The V4 source names the five song placements but deliberately
            # does not provide lyrics or a canonical recording. Keep a
            # separately traceable record for the music-production handoff;
            # generating TTS from a title would create the wrong asset.
            entries.append(
                {
                    "audioId": f"{lesson['code']}_SONG",
                    "kind": "songReference",
                    "locale": "en-US",
                    "sourceText": song_title,
                    "qaStatus": "PENDING_SOURCE_AUDIO",
                    **prefix,
                }
            )
    for group in catalog["groups"]:
        for level in group["levels"]:
            for question in level["missionBank"]:
                entries.append(
                    {
                        "audioId": f"{question['id']}_PROMPT",
                        "kind": "missionPrompt",
                        "locale": "vi-VN",
                        "sourceText": question["prompt"],
                        "questionId": question["id"],
                        "targetId": question["coverageTargetId"],
                        "course": f"{group['startAge']}-{group['endAge']}",
                        "level": level["number"],
                        "qaStatus": "PENDING_TTS",
                    }
                )
    return {
        "schemaVersion": 1,
        "contentVersion": catalog["contentVersion"],
        "source": catalog["source"],
        "entries": entries,
    }


def build_lexicon(catalog: dict[str, Any]) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    token_index: dict[str, set[str]] = defaultdict(set)
    for group, topic, lesson in iter_lessons(catalog):
        for sentence in lesson["sentences"]:
            normalized = normalized_phrase(sentence["english"])
            entry = {
                "id": sentence["id"],
                "kind": "coreTarget",
                "lessonCode": lesson["code"],
                "topicNumber": topic["number"],
                "course": f"{group['startAge']}-{group['endAge']}",
                "english": sentence["english"],
                "vietnamese": sentence["vietnamese"],
                "normalized": normalized,
                "acceptedVariants": sentence["recognitionVariants"],
                "requiresAllExpectedTokens": sentence["requiresAllExpectedTokens"],
            }
            entries.append(entry)
            for token in normalized.split():
                if token:
                    token_index[token].add(sentence["id"])
        role_play = lesson.get("rolePlay")
        if role_play:
            for index, turn in enumerate(role_play["turns"], start=1):
                if turn["speaker"] != "child":
                    continue
                phrase = turn["english"]
                normalized = normalized_phrase(phrase)
                item_id = f"{lesson['code']}-RP{index:02d}"
                entries.append(
                    {
                        "id": item_id,
                        "kind": "rolePlayChildTurn",
                        "lessonCode": lesson["code"],
                        "topicNumber": topic["number"],
                        "course": f"{group['startAge']}-{group['endAge']}",
                        "english": phrase,
                        "vietnamese": turn["vietnamese"],
                        "normalized": normalized,
                        "acceptedVariants": recognition_variants(phrase),
                        "requiresAllExpectedTokens": False,
                    }
                )
                for token in normalized.split():
                    if token:
                        token_index[token].add(item_id)
    return {
        "schemaVersion": 1,
        "contentVersion": catalog["contentVersion"],
        "source": catalog["source"],
        "entries": entries,
        "terms": [
            {"term": term, "entryIds": sorted(entry_ids)}
            for term, entry_ids in sorted(token_index.items())
        ],
    }


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="V4 Vietnamese IT/TTS text export")
    parser.add_argument("--catalog-out", type=Path, default=CATALOG_PATH)
    parser.add_argument("--audio-manifest-out", type=Path, default=AUDIO_MANIFEST_PATH)
    parser.add_argument("--lexicon-out", type=Path, default=LEXICON_PATH)
    arguments = parser.parse_args()

    catalog = parse_spec(arguments.source)
    write_json(arguments.catalog_out, catalog)
    write_json(arguments.audio_manifest_out, build_audio_manifest(catalog))
    write_json(arguments.lexicon_out, build_lexicon(catalog))
    print(json.dumps(EXPECTED_COUNTS, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()

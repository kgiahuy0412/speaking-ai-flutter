from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


STANDARD_COLUMNS = (
    "record_id",
    "batch_id",
    "sentence_code",
    "source_vi",
    "expected_en",
    "draft_filename",
    "official_filename",
    "local_audio_path",
    "audio_id",
    "audio_hash",
    "audio_version",
    "upload_status",
    "uploaded_at",
    "test_result",
    "error_categories",
    "observed_result",
    "repair_suggestion",
    "repair_status",
    "reviewer",
    "reviewed_at",
    "note",
)


def utc_now_text() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _version(value: Any) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError):
        return 0


@dataclass(slots=True)
class AudioRecord:
    record_id: str
    batch_id: str = ""
    sentence_code: str = ""
    source_vi: str = ""
    expected_en: str = ""
    draft_filename: str = ""
    official_filename: str = ""
    local_audio_path: str = ""
    audio_id: str = ""
    audio_hash: str = ""
    audio_version: int = 0
    upload_status: str = "Chưa ghép audio"
    uploaded_at: str = ""
    test_result: str = "Chưa kiểm thử"
    error_categories: str = ""
    observed_result: str = ""
    repair_suggestion: str = ""
    repair_status: str = "Chưa xử lý"
    reviewer: str = ""
    reviewed_at: str = ""
    note: str = ""
    extra: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_mapping(cls, values: dict[str, Any]) -> "AudioRecord":
        known = {name: values.get(name) for name in STANDARD_COLUMNS}
        extra = {key: value for key, value in values.items() if key not in STANDARD_COLUMNS}
        return cls(
            record_id=_text(known["record_id"]),
            batch_id=_text(known["batch_id"]),
            sentence_code=_text(known["sentence_code"]),
            source_vi=_text(known["source_vi"]),
            expected_en=_text(known["expected_en"]),
            draft_filename=_text(known["draft_filename"]),
            official_filename=_text(known["official_filename"]),
            local_audio_path=_text(known["local_audio_path"]),
            audio_id=_text(known["audio_id"]),
            audio_hash=_text(known["audio_hash"]),
            audio_version=_version(known["audio_version"]),
            upload_status=_text(known["upload_status"]) or "Chưa ghép audio",
            uploaded_at=_text(known["uploaded_at"]),
            test_result=_text(known["test_result"]) or "Chưa kiểm thử",
            error_categories=_text(known["error_categories"]),
            observed_result=_text(known["observed_result"]),
            repair_suggestion=_text(known["repair_suggestion"]),
            repair_status=_text(known["repair_status"]) or "Chưa xử lý",
            reviewer=_text(known["reviewer"]),
            reviewed_at=_text(known["reviewed_at"]),
            note=_text(known["note"]),
            extra=extra,
        )

    def to_mapping(self) -> dict[str, Any]:
        values: dict[str, Any] = {
            "record_id": self.record_id,
            "batch_id": self.batch_id,
            "sentence_code": self.sentence_code,
            "source_vi": self.source_vi,
            "expected_en": self.expected_en,
            "draft_filename": self.draft_filename,
            "official_filename": self.official_filename,
            "local_audio_path": self.local_audio_path,
            "audio_id": self.audio_id,
            "audio_hash": self.audio_hash,
            "audio_version": self.audio_version,
            "upload_status": self.upload_status,
            "uploaded_at": self.uploaded_at,
            "test_result": self.test_result,
            "error_categories": self.error_categories,
            "observed_result": self.observed_result,
            "repair_suggestion": self.repair_suggestion,
            "repair_status": self.repair_status,
            "reviewer": self.reviewer,
            "reviewed_at": self.reviewed_at,
            "note": self.note,
        }
        values.update(self.extra)
        return values


@dataclass(slots=True)
class AuditEntry:
    timestamp: str
    record_id: str
    action: str
    old_value: str = ""
    new_value: str = ""
    detail: str = ""

    @classmethod
    def create(
        cls,
        record_id: str,
        action: str,
        old_value: str = "",
        new_value: str = "",
        detail: str = "",
    ) -> "AuditEntry":
        return cls(utc_now_text(), record_id, action, old_value, new_value, detail)

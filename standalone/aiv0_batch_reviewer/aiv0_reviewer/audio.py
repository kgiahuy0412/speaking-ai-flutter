from __future__ import annotations

import hashlib
import re
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

from .models import AudioRecord, utc_now_text


AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".aac", ".ogg", ".flac"}


def normalize_key(value: str) -> str:
    folded = value.casefold().replace("đ", "d")
    decomposed = unicodedata.normalize("NFKD", folded)
    ascii_text = "".join(char for char in decomposed if not unicodedata.combining(char))
    return re.sub(r"[^a-z0-9]+", "", ascii_text)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


@dataclass(slots=True)
class MatchSummary:
    matched: dict[str, Path] = field(default_factory=dict)
    missing_record_ids: list[str] = field(default_factory=list)
    unmatched_files: list[Path] = field(default_factory=list)
    ambiguous_files: list[Path] = field(default_factory=list)
    duplicate_hashes: dict[str, list[Path]] = field(default_factory=dict)


def scan_audio_files(folder: str | Path) -> list[Path]:
    root = Path(folder)
    return sorted(
        (path for path in root.rglob("*") if path.is_file() and path.suffix.casefold() in AUDIO_EXTENSIONS),
        key=lambda path: str(path).casefold(),
    )


def _candidate_keys(record: AudioRecord) -> set[str]:
    values = {
        record.record_id,
        record.sentence_code,
        Path(record.draft_filename).stem if record.draft_filename else "",
        Path(record.official_filename).stem if record.official_filename else "",
    }
    return {normalize_key(value) for value in values if value}


def match_audio_folder(records: list[AudioRecord], folder: str | Path) -> MatchSummary:
    files = scan_audio_files(folder)
    summary = MatchSummary()
    key_to_records: dict[str, list[AudioRecord]] = {}
    for record in records:
        for key in _candidate_keys(record):
            key_to_records.setdefault(key, []).append(record)

    assigned: set[str] = set()
    file_hashes: dict[str, list[Path]] = {}
    for path in files:
        file_key = normalize_key(path.stem)
        candidates = key_to_records.get(file_key, [])
        if not candidates:
            record_matches = [
                record
                for record in records
                if normalize_key(record.record_id) and normalize_key(record.record_id) in file_key
            ]
            candidates = record_matches
        candidates = [record for record in candidates if record.record_id not in assigned]
        if len(candidates) != 1:
            target = summary.ambiguous_files if len(candidates) > 1 else summary.unmatched_files
            target.append(path)
            continue

        record = candidates[0]
        digest = file_sha256(path)
        file_hashes.setdefault(digest, []).append(path)
        old_hash = record.audio_hash
        if digest != old_hash:
            record.audio_version = max(1, record.audio_version + 1)
        elif record.audio_version == 0:
            record.audio_version = 1
        record.official_filename = path.name
        record.local_audio_path = str(path.resolve())
        record.audio_hash = digest
        if not record.audio_id or record.audio_id.startswith("local_"):
            record.audio_id = f"local_{digest[:16]}"
        record.upload_status = "Đã ghép cục bộ"
        record.uploaded_at = utc_now_text()
        assigned.add(record.record_id)
        summary.matched[record.record_id] = path

    summary.missing_record_ids = [record.record_id for record in records if record.record_id not in assigned]
    summary.duplicate_hashes = {digest: paths for digest, paths in file_hashes.items() if len(paths) > 1}
    return summary

from __future__ import annotations

from dataclasses import dataclass

from .models import AudioRecord, utc_now_text


TEST_RESULTS = ("Chưa kiểm thử", "Đạt", "Không đạt", "Kiểm thử lại")

ERROR_CATEGORIES = (
    "Phát âm không chuẩn",
    "Giọng vùng miền",
    "Nghe không rõ",
    "Khó nghe",
    "Nói quá nhanh",
    "Nói quá nhỏ",
    "Tạp âm nền",
    "Âm thanh bị rè",
    "Mất đầu hoặc cuối câu",
    "Nội dung không đúng câu mẫu",
    "ASR nhận dạng sai",
    "Dịch sai nghĩa",
    "Không có kết quả",
    "File audio lỗi",
    "Khác",
)

REPAIR_STATUSES = (
    "Chưa xử lý",
    "Không cần sửa",
    "Đã đề xuất",
    "Đang sửa",
    "Đã sửa",
    "Cần thu lại",
    "Không thể sửa",
)


def split_categories(value: str) -> list[str]:
    return [item.strip() for item in value.split(";") if item.strip()]


def join_categories(values: list[str]) -> str:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        cleaned = value.strip()
        if cleaned and cleaned.casefold() not in seen:
            seen.add(cleaned.casefold())
            result.append(cleaned)
    return "; ".join(result)


@dataclass(slots=True)
class BulkRepairChange:
    record_id: str
    old_status: str
    new_status: str


def apply_bulk_repair(
    records: list[AudioRecord],
    category: str,
    repair_status: str,
    proposal: str,
    move_to_retest: bool = True,
) -> list[BulkRepairChange]:
    changes: list[BulkRepairChange] = []
    proposal = proposal.strip()
    for record in records:
        if record.test_result != "Không đạt" or category not in split_categories(record.error_categories):
            continue
        old_status = record.repair_status
        record.repair_status = repair_status
        if proposal:
            existing_lines = {line.strip().casefold() for line in record.repair_suggestion.splitlines() if line.strip()}
            if proposal.casefold() not in existing_lines:
                record.repair_suggestion = "\n".join(
                    value for value in (record.repair_suggestion.strip(), proposal) if value
                )
        if move_to_retest:
            record.test_result = "Kiểm thử lại"
        record.reviewed_at = utc_now_text()
        changes.append(BulkRepairChange(record.record_id, old_status, repair_status))
    return changes

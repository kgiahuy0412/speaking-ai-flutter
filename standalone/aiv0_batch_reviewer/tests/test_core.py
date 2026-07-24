from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from aiv0_reviewer.audio import match_audio_folder, normalize_key
from aiv0_reviewer.models import AuditEntry, AudioRecord
from aiv0_reviewer.review import apply_bulk_repair, join_categories, split_categories
from aiv0_reviewer.uploader import extract_json_path
from aiv0_reviewer.workbook import create_template, load_records, save_workbook


class CoreTests(unittest.TestCase):
    def test_normalize_key_handles_vietnamese_and_separators(self) -> None:
        self.assertEqual(normalize_key("CV26-ĐỢT-001.mp3"), "cv26dot001mp3")

    def test_template_contains_207_stable_records(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "template.xlsx"
            create_template(path)
            records = load_records(path)
            self.assertEqual(len(records), 207)
            self.assertEqual(records[0].record_id, "CV26-TEEN-001")
            self.assertEqual(records[-1].record_id, "CV26-TEEN-207")

    def test_match_audio_updates_id_hash_and_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audio = root / "CV26-TEEN-001.mp3"
            audio.write_bytes(b"fake mp3 content")
            record = AudioRecord(record_id="CV26-TEEN-001")
            summary = match_audio_folder([record], root)
            self.assertIn(record.record_id, summary.matched)
            self.assertTrue(record.audio_id.startswith("local_"))
            self.assertEqual(record.audio_version, 1)
            self.assertEqual(record.upload_status, "Đã ghép cục bộ")

            match_audio_folder([record], root)
            self.assertEqual(record.audio_version, 1)
            audio.write_bytes(b"new official audio")
            match_audio_folder([record], root)
            self.assertEqual(record.audio_version, 2)

    def test_workbook_round_trip_preserves_upload_data_and_audit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.xlsx"
            record = AudioRecord(record_id="R001", audio_id="aud_123", audio_version=2, extra={"owner": "QA"})
            save_workbook(path, [record], [AuditEntry.create("R001", "UPLOAD_SUCCESS")])
            loaded = load_records(path)
            self.assertEqual(loaded[0].audio_id, "aud_123")
            self.assertEqual(loaded[0].audio_version, 2)
            self.assertEqual(loaded[0].extra["owner"], "QA")

    def test_extract_nested_audio_id(self) -> None:
        payload = {"data": {"audio": {"id": "aud_456"}}}
        self.assertEqual(extract_json_path(payload, "data.audio.id"), "aud_456")
        self.assertIsNone(extract_json_path(payload, "data.missing.id"))

    def test_error_categories_are_stable_and_unique(self) -> None:
        value = join_categories(["Nghe không rõ", "Khó nghe", "nghe không rõ"])
        self.assertEqual(value, "Nghe không rõ; Khó nghe")
        self.assertEqual(split_categories(value), ["Nghe không rõ", "Khó nghe"])

    def test_bulk_repair_only_updates_failed_records_in_category(self) -> None:
        matching = AudioRecord(
            record_id="R001",
            test_result="Không đạt",
            error_categories="Phát âm không chuẩn; Khó nghe",
        )
        other_category = AudioRecord(
            record_id="R002",
            test_result="Không đạt",
            error_categories="Giọng vùng miền",
        )
        passed = AudioRecord(
            record_id="R003",
            test_result="Đạt",
            error_categories="Phát âm không chuẩn",
        )
        changes = apply_bulk_repair(
            [matching, other_category, passed],
            "Phát âm không chuẩn",
            "Đã sửa",
            "Thu lại và hướng dẫn phát âm.",
        )
        self.assertEqual([change.record_id for change in changes], ["R001"])
        self.assertEqual(matching.test_result, "Kiểm thử lại")
        self.assertEqual(matching.repair_status, "Đã sửa")
        self.assertEqual(matching.repair_suggestion, "Thu lại và hướng dẫn phát âm.")
        self.assertEqual(other_category.repair_status, "Chưa xử lý")


if __name__ == "__main__":
    unittest.main()

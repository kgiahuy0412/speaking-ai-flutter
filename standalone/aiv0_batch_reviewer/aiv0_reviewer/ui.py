from __future__ import annotations

import sys
from pathlib import Path

from PySide6.QtCore import QThread, Qt, QUrl, Signal
from PySide6.QtGui import QDesktopServices
from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer
from PySide6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QButtonGroup,
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QFrame,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QScrollArea,
    QSlider,
    QSplitter,
    QStyle,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .audio import MatchSummary, match_audio_folder
from .models import AuditEntry, AudioRecord, utc_now_text
from .review import (
    ERROR_CATEGORIES,
    REPAIR_STATUSES,
    TEST_RESULTS,
    apply_bulk_repair,
    join_categories,
    split_categories,
)
from .uploader import UploadConfig, upload_audio
from .workbook import create_template, load_records, save_workbook


class UploadWorker(QThread):
    completed = Signal(object)

    def __init__(self, records: list[AudioRecord], config: UploadConfig) -> None:
        super().__init__()
        self.records = records
        self.config = config

    def run(self) -> None:
        results: list[tuple[AudioRecord, str | None, str | None]] = []
        for record in self.records:
            try:
                result = upload_audio(record, self.config)
                results.append((record, result.audio_id, None))
            except Exception as error:
                results.append((record, None, str(error)))
        self.completed.emit(results)


class ApiConfigDialog(QDialog):
    def __init__(self, config: UploadConfig, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Cấu hình API upload")
        self.setMinimumWidth(540)
        layout = QVBoxLayout(self)
        form = QFormLayout()
        form.setVerticalSpacing(12)
        self.endpoint = QLineEdit(config.endpoint)
        self.endpoint.setPlaceholderText("https://example.com/api/audio/upload")
        self.token = QLineEdit(config.token)
        self.token.setEchoMode(QLineEdit.EchoMode.Password)
        self.file_field = QLineEdit(config.file_field)
        self.id_path = QLineEdit(config.id_json_path)
        form.addRow("API endpoint", self.endpoint)
        form.addRow("Bearer token", self.token)
        form.addRow("Tên trường file", self.file_field)
        form.addRow("JSON path của audio ID", self.id_path)
        layout.addLayout(form)
        note = QLabel("Token chỉ được giữ trong bộ nhớ của phiên chạy hiện tại.")
        note.setObjectName("muted")
        layout.addWidget(note)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def value(self) -> UploadConfig:
        return UploadConfig(
            endpoint=self.endpoint.text().strip(),
            token=self.token.text(),
            file_field=self.file_field.text().strip() or "file",
            id_json_path=self.id_path.text().strip() or "audio_id",
        )


class BulkRepairDialog(QDialog):
    def __init__(self, records: list[AudioRecord], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.records = records
        self.setWindowTitle("Sửa hàng loạt theo loại lỗi")
        self.setMinimumSize(620, 430)
        layout = QVBoxLayout(self)
        form = QFormLayout()
        form.setVerticalSpacing(12)
        self.category = QComboBox()
        self.category.addItems(ERROR_CATEGORIES)
        self.repair_status = QComboBox()
        self.repair_status.addItems(REPAIR_STATUSES)
        self.repair_status.setCurrentText("Đã sửa")
        self.proposal = QPlainTextEdit()
        self.proposal.setPlaceholderText("Ví dụ: Thu lại audio và hướng dẫn phát âm chậm, rõ từng từ.")
        self.proposal.setMaximumHeight(120)
        self.move_to_retest = QCheckBox("Chuyển các mẫu đã áp dụng sang Kiểm thử lại")
        self.move_to_retest.setChecked(True)
        form.addRow("Loại lỗi cần xử lý", self.category)
        form.addRow("Trạng thái sửa mới", self.repair_status)
        form.addRow("Đề xuất áp dụng chung", self.proposal)
        layout.addLayout(form)
        layout.addWidget(self.move_to_retest)
        self.match_count = QLabel()
        self.match_count.setObjectName("bulkCount")
        layout.addWidget(self.match_count)
        note = QLabel("Chỉ các mẫu Không đạt có đúng loại lỗi đã chọn mới được cập nhật.")
        note.setObjectName("muted")
        layout.addWidget(note)
        layout.addStretch()
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Apply | QDialogButtonBox.StandardButton.Cancel)
        buttons.button(QDialogButtonBox.StandardButton.Apply).setText("Áp dụng hàng loạt")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)
        self.category.currentTextChanged.connect(self._update_count)
        self._update_count()

    def _update_count(self) -> None:
        category = self.category.currentText()
        count = sum(
            record.test_result == "Không đạt" and category in split_categories(record.error_categories)
            for record in self.records
        )
        self.match_count.setText(f"{count} audio sẽ được cập nhật")


class StatPanel(QFrame):
    def __init__(self, label: str) -> None:
        super().__init__()
        self.setObjectName("statPanel")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 10, 16, 10)
        layout.setSpacing(1)
        self.value = QLabel("0")
        self.value.setObjectName("statValue")
        name = QLabel(label)
        name.setObjectName("muted")
        layout.addWidget(self.value)
        layout.addWidget(name)


class BatchReviewerWindow(QMainWindow):
    TABLE_FIELDS = (
        "record_id",
        "sentence_code",
        "source_vi",
        "test_result",
        "error_categories",
        "repair_status",
        "official_filename",
        "audio_version",
    )
    TABLE_HEADERS = (
        "Record ID",
        "Mã câu",
        "Câu tiếng Việt",
        "Kết quả",
        "Loại lỗi",
        "Trạng thái sửa",
        "Audio",
        "Phiên bản",
    )

    def __init__(self) -> None:
        super().__init__()
        self.records: list[AudioRecord] = []
        self.audit_entries: list[AuditEntry] = []
        self.source_path: Path | None = None
        self.api_config = UploadConfig(endpoint="")
        self.upload_worker: UploadWorker | None = None
        self.detail_fields: dict[str, QLineEdit] = {}
        self.current_audio_path = ""
        self.audio_output = QAudioOutput(self)
        self.audio_output.setVolume(0.8)
        self.player = QMediaPlayer(self)
        self.player.setAudioOutput(self.audio_output)
        self.player.positionChanged.connect(self._on_audio_position)
        self.player.durationChanged.connect(self._on_audio_duration)
        self.player.playbackStateChanged.connect(self._on_playback_state)
        self.player.errorOccurred.connect(self._on_audio_error)
        self.setWindowTitle("AIV0 Batch Audio Reviewer")
        self.resize(1540, 900)
        self.setMinimumSize(1180, 720)
        self._build_ui()

    def _icon(self, icon: QStyle.StandardPixmap):
        return self.style().standardIcon(icon)

    def _button(self, text: str, icon: QStyle.StandardPixmap, slot, primary: bool = False) -> QPushButton:
        button = QPushButton(self._icon(icon), text)
        if primary:
            button.setObjectName("primaryButton")
        button.clicked.connect(slot)
        return button

    def _build_ui(self) -> None:
        central = QWidget()
        self.setCentralWidget(central)
        outer = QVBoxLayout(central)
        outer.setContentsMargins(22, 16, 22, 10)
        outer.setSpacing(10)

        heading = QHBoxLayout()
        title_group = QVBoxLayout()
        title_group.setSpacing(1)
        title = QLabel("AIV0 Batch Audio Reviewer")
        title.setObjectName("title")
        subtitle = QLabel("Kiểm thử và xử lý audio nội bộ")
        subtitle.setObjectName("muted")
        title_group.addWidget(title)
        title_group.addWidget(subtitle)
        heading.addLayout(title_group)
        heading.addStretch()
        heading.addWidget(self._button("Mở bảng", QStyle.StandardPixmap.SP_DialogOpenButton, self.open_table))
        heading.addWidget(self._button("Tạo mẫu 207", QStyle.StandardPixmap.SP_FileIcon, self.create_207_template))
        heading.addWidget(self._button("Ghép audio", QStyle.StandardPixmap.SP_DirOpenIcon, self.match_folder, True))
        heading.addWidget(self._button("Sửa hàng loạt", QStyle.StandardPixmap.SP_FileDialogDetailedView, self.bulk_repair))
        heading.addWidget(self._button("Xuất Excel", QStyle.StandardPixmap.SP_DialogSaveButton, self.export_table))
        outer.addLayout(heading)

        stats_layout = QHBoxLayout()
        stats_layout.setSpacing(8)
        self.stats = [
            StatPanel("Tổng bản ghi"),
            StatPanel("Đạt"),
            StatPanel("Không đạt"),
            StatPanel("Kiểm thử lại"),
        ]
        for panel in self.stats:
            stats_layout.addWidget(panel)
        outer.addLayout(stats_layout)

        controls = QHBoxLayout()
        controls.addWidget(QLabel("Tìm kiếm"))
        self.search = QLineEdit()
        self.search.setPlaceholderText("Record ID, mã câu, tên file...")
        self.search.setMaximumWidth(300)
        self.search.textChanged.connect(self.refresh_table)
        controls.addWidget(self.search)
        controls.addSpacing(6)
        controls.addWidget(QLabel("Kết quả"))
        self.result_filter = QComboBox()
        self.result_filter.addItems(["Tất cả kết quả", *TEST_RESULTS])
        self.result_filter.currentTextChanged.connect(self.refresh_table)
        controls.addWidget(self.result_filter)
        controls.addSpacing(6)
        controls.addWidget(QLabel("Loại lỗi"))
        self.category_filter = QComboBox()
        self.category_filter.addItems(["Tất cả loại lỗi", *ERROR_CATEGORIES])
        self.category_filter.currentTextChanged.connect(self.refresh_table)
        controls.addWidget(self.category_filter)
        controls.addStretch()
        controls.addWidget(self._button("Cấu hình API", QStyle.StandardPixmap.SP_ComputerIcon, self.configure_api))
        controls.addWidget(self._button("Upload đã chọn", QStyle.StandardPixmap.SP_ArrowUp, self.upload_selected))
        outer.addLayout(controls)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.setChildrenCollapsible(False)
        splitter.addWidget(self._build_table())
        splitter.addWidget(self._build_detail())
        splitter.setStretchFactor(0, 4)
        splitter.setStretchFactor(1, 2)
        splitter.setSizes([1030, 470])
        outer.addWidget(splitter, 1)

        footer = QHBoxLayout()
        self.status_label = QLabel("Sẵn sàng")
        self.status_label.setObjectName("muted")
        version = QLabel("V0.2 • Dữ liệu lưu cục bộ")
        version.setObjectName("muted")
        footer.addWidget(self.status_label)
        footer.addStretch()
        footer.addWidget(version)
        outer.addLayout(footer)

    def _build_table(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("surface")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(1, 1, 1, 1)
        self.table = QTableWidget(0, len(self.TABLE_FIELDS))
        self.table.setHorizontalHeaderLabels(self.TABLE_HEADERS)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setAlternatingRowColors(True)
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(34)
        header = self.table.horizontalHeader()
        for column in range(len(self.TABLE_FIELDS)):
            mode = QHeaderView.ResizeMode.Stretch if column in (2, 4, 6) else QHeaderView.ResizeMode.ResizeToContents
            header.setSectionResizeMode(column, mode)
        self.table.itemSelectionChanged.connect(self._on_selection)
        layout.addWidget(self.table)
        return frame

    def _build_detail(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("surface")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(14, 14, 14, 12)
        layout.setSpacing(8)
        heading = QLabel("Kiểm thử audio")
        heading.setObjectName("sectionTitle")
        layout.addWidget(heading)

        audio_row = QHBoxLayout()
        self.play_button = QPushButton(self._icon(QStyle.StandardPixmap.SP_MediaPlay), "")
        self.play_button.setToolTip("Phát hoặc tạm dừng audio")
        self.play_button.setFixedSize(38, 34)
        self.play_button.clicked.connect(self.toggle_audio)
        self.audio_name = QLabel("Chưa chọn audio")
        self.audio_name.setObjectName("audioName")
        self.audio_name.setMinimumWidth(120)
        self.audio_time = QLabel("00:00 / 00:00")
        self.audio_time.setObjectName("muted")
        external = QPushButton(self._icon(QStyle.StandardPixmap.SP_TitleBarNormalButton), "")
        external.setToolTip("Mở bằng trình phát mặc định")
        external.setFixedSize(38, 34)
        external.clicked.connect(self.open_audio)
        audio_row.addWidget(self.play_button)
        audio_row.addWidget(self.audio_name, 1)
        audio_row.addWidget(self.audio_time)
        audio_row.addWidget(external)
        layout.addLayout(audio_row)
        self.audio_slider = QSlider(Qt.Orientation.Horizontal)
        self.audio_slider.setRange(0, 0)
        self.audio_slider.sliderMoved.connect(self.player.setPosition)
        layout.addWidget(self.audio_slider)

        tabs = QTabWidget()
        tabs.addTab(self._build_review_tab(), "Kiểm thử")
        tabs.addTab(self._build_data_tab(), "Dữ liệu")
        layout.addWidget(tabs, 1)
        actions = QHBoxLayout()
        actions.addWidget(self._button("Lưu", QStyle.StandardPixmap.SP_DialogApplyButton, self.save_detail, True))
        actions.addWidget(self._button("Lưu và tiếp", QStyle.StandardPixmap.SP_ArrowForward, self.save_and_next))
        layout.addLayout(actions)
        return frame

    def _build_review_tab(self) -> QScrollArea:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(8, 10, 8, 8)
        layout.setSpacing(7)
        layout.addWidget(QLabel("Kết quả kiểm thử"))
        result_row = QHBoxLayout()
        self.result_group = QButtonGroup(self)
        self.result_group.setExclusive(True)
        self.result_buttons: dict[str, QPushButton] = {}
        result_specs = (
            ("Đạt", "passButton"),
            ("Không đạt", "failButton"),
            ("Kiểm thử lại", "retestButton"),
        )
        for index, (label, object_name) in enumerate(result_specs):
            button = QPushButton(label)
            button.setCheckable(True)
            button.setObjectName(object_name)
            self.result_group.addButton(button, index)
            self.result_buttons[label] = button
            result_row.addWidget(button)
        layout.addLayout(result_row)

        layout.addWidget(QLabel("Phân loại lỗi (có thể chọn nhiều)"))
        self.category_list = QListWidget()
        self.category_list.setMinimumHeight(220)
        for category in ERROR_CATEGORIES:
            item = QListWidgetItem(category)
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(Qt.CheckState.Unchecked)
            self.category_list.addItem(item)
        layout.addWidget(self.category_list)

        form = QFormLayout()
        form.setVerticalSpacing(8)
        self.observed_text = QPlainTextEdit()
        self.observed_text.setMinimumHeight(68)
        self.observed_text.setMaximumHeight(70)
        self.observed_text.setPlaceholderText("Ghi lại điều thực tế nghe được hoặc kết quả sai.")
        self.repair_text = QPlainTextEdit()
        self.repair_text.setMinimumHeight(78)
        self.repair_text.setMaximumHeight(80)
        self.repair_text.setPlaceholderText("Đề xuất thu lại, sửa dữ liệu, sửa ASR hoặc xử lý khác.")
        self.repair_status = QComboBox()
        self.repair_status.addItems(REPAIR_STATUSES)
        self.reviewer = QLineEdit()
        self.reviewer.setPlaceholderText("Tên hoặc mã người kiểm thử")
        form.addRow("Kết quả thực tế", self.observed_text)
        form.addRow("Đề xuất sửa", self.repair_text)
        form.addRow("Trạng thái sửa", self.repair_status)
        form.addRow("Người kiểm thử", self.reviewer)
        layout.addLayout(form)
        layout.addWidget(QLabel("Ghi chú"))
        self.note_text = QPlainTextEdit()
        self.note_text.setMinimumHeight(62)
        self.note_text.setMaximumHeight(64)
        layout.addWidget(self.note_text)
        layout.addStretch()
        scroll.setWidget(page)
        return scroll

    def _build_data_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(8, 10, 8, 8)
        form = QFormLayout()
        form.setVerticalSpacing(8)
        labels = (
            ("record_id", "Record ID"),
            ("batch_id", "Mã đợt"),
            ("sentence_code", "Mã câu"),
            ("draft_filename", "File bản nháp"),
            ("official_filename", "File chính thức"),
            ("audio_id", "Audio ID"),
            ("upload_status", "Trạng thái upload"),
        )
        for field, label in labels:
            editor = QLineEdit()
            if field == "record_id":
                editor.setReadOnly(True)
            self.detail_fields[field] = editor
            form.addRow(label, editor)
        layout.addLayout(form)
        layout.addWidget(QLabel("Câu tiếng Việt"))
        self.source_text = QPlainTextEdit()
        self.source_text.setMaximumHeight(110)
        layout.addWidget(self.source_text)
        layout.addStretch()
        return page

    def open_table(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Chọn bảng dữ liệu", "", "Bảng dữ liệu (*.xlsx *.csv *.tsv);;Tất cả file (*.*)"
        )
        if not path:
            return
        try:
            self.records = load_records(path)
        except Exception as error:
            QMessageBox.critical(self, "Không mở được bảng", str(error))
            return
        self.source_path = Path(path)
        self.audit_entries = []
        self.status_label.setText(f"Đã mở {len(self.records)} bản ghi từ {self.source_path.name}")
        self.refresh_table()

    def create_207_template(self) -> None:
        path, _ = QFileDialog.getSaveFileName(
            self, "Lưu bảng mẫu 207 bản ghi", "AIV0_207_audio_template.xlsx", "Excel (*.xlsx)"
        )
        if not path:
            return
        try:
            create_template(path, 207)
            self.records = load_records(path)
            self.source_path = Path(path)
            self.audit_entries = []
            self.refresh_table()
            self.status_label.setText(f"Đã tạo bảng mẫu: {Path(path).name}")
        except Exception as error:
            QMessageBox.critical(self, "Không tạo được bảng", str(error))

    def match_folder(self) -> None:
        if not self.records:
            QMessageBox.information(self, "Chưa có dữ liệu", "Hãy mở bảng hoặc tạo mẫu 207 trước.")
            return
        folder = QFileDialog.getExistingDirectory(self, "Chọn thư mục chứa audio chính thức")
        if not folder:
            return
        before = {record.record_id: (record.audio_id, record.audio_hash) for record in self.records}
        try:
            summary = match_audio_folder(self.records, folder)
        except Exception as error:
            QMessageBox.critical(self, "Không ghép được audio", str(error))
            return
        for record_id, path in summary.matched.items():
            old_id, old_hash = before[record_id]
            record = self._record_by_id(record_id)
            self.audit_entries.append(
                AuditEntry.create(
                    record_id,
                    "MATCH_LOCAL_AUDIO",
                    old_id,
                    record.audio_id,
                    f"{path.name}; old_hash={old_hash}; new_hash={record.audio_hash}",
                )
            )
        self.refresh_table()
        self._show_match_summary(summary)

    def _show_match_summary(self, summary: MatchSummary) -> None:
        self.status_label.setText(
            f"Ghép {len(summary.matched)} file • Thiếu {len(summary.missing_record_ids)} • "
            f"Không khớp {len(summary.unmatched_files)} • Mơ hồ {len(summary.ambiguous_files)}"
        )
        QMessageBox.information(
            self,
            "Kết quả ghép audio",
            f"Đã ghép: {len(summary.matched)}\n"
            f"Bản ghi chưa có file: {len(summary.missing_record_ids)}\n"
            f"File không khớp: {len(summary.unmatched_files)}\n"
            f"File khớp nhiều dòng: {len(summary.ambiguous_files)}\n"
            f"Nội dung file trùng nhau: {len(summary.duplicate_hashes)}",
        )

    def bulk_repair(self) -> None:
        if not self.records:
            QMessageBox.information(self, "Chưa có dữ liệu", "Hãy mở bảng trước khi sửa hàng loạt.")
            return
        dialog = BulkRepairDialog(self.records, self)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        category = dialog.category.currentText()
        changes = apply_bulk_repair(
            self.records,
            category,
            dialog.repair_status.currentText(),
            dialog.proposal.toPlainText(),
            dialog.move_to_retest.isChecked(),
        )
        for change in changes:
            self.audit_entries.append(
                AuditEntry.create(
                    change.record_id,
                    "BULK_REPAIR",
                    change.old_status,
                    change.new_status,
                    f"category={category}",
                )
            )
        self.refresh_table()
        self.status_label.setText(f"Đã cập nhật hàng loạt {len(changes)} audio thuộc lỗi: {category}")
        QMessageBox.information(self, "Đã sửa hàng loạt", f"Đã cập nhật {len(changes)} audio.")

    def configure_api(self) -> None:
        dialog = ApiConfigDialog(self.api_config, self)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            self.api_config = dialog.value()
            self.status_label.setText("Đã cập nhật cấu hình API trong phiên chạy hiện tại")

    def upload_selected(self) -> None:
        selected_ids = self._selected_record_ids()
        if not selected_ids:
            QMessageBox.information(self, "Chưa chọn bản ghi", "Chọn một hoặc nhiều dòng cần upload.")
            return
        if not self.api_config.endpoint:
            QMessageBox.information(self, "Chưa có API", "Hãy nhập endpoint trong Cấu hình API trước.")
            return
        records = [self._record_by_id(record_id) for record_id in selected_ids]
        missing = [record.record_id for record in records if not Path(record.local_audio_path).is_file()]
        if missing:
            QMessageBox.critical(self, "Thiếu file audio", f"Các bản ghi chưa có file: {', '.join(missing[:10])}")
            return
        self.status_label.setText(f"Đang upload {len(records)} audio...")
        self.upload_worker = UploadWorker(records, self.api_config)
        self.upload_worker.completed.connect(self._finish_upload)
        self.upload_worker.start()

    def _finish_upload(self, results: list[tuple[AudioRecord, str | None, str | None]]) -> None:
        success = 0
        errors: list[str] = []
        for record, audio_id, error in results:
            if error:
                record.upload_status = "Upload lỗi"
                record.note = f"{record.note}\n{error}".strip()
                errors.append(f"{record.record_id}: {error}")
                self.audit_entries.append(AuditEntry.create(record.record_id, "UPLOAD_ERROR", detail=error))
                continue
            old_id = record.audio_id
            record.audio_id = audio_id or old_id
            record.upload_status = "Đã upload"
            record.uploaded_at = utc_now_text()
            success += 1
            self.audit_entries.append(AuditEntry.create(record.record_id, "UPLOAD_SUCCESS", old_id, record.audio_id))
        self.refresh_table()
        self.status_label.setText(f"Upload thành công {success}/{len(results)}")
        if errors:
            QMessageBox.warning(self, "Upload có lỗi", "\n".join(errors[:8]))
        else:
            QMessageBox.information(self, "Upload hoàn tất", f"Đã nhận audio ID cho {success} bản ghi.")
        self.upload_worker = None

    def export_table(self) -> None:
        if not self.records:
            QMessageBox.information(self, "Chưa có dữ liệu", "Không có dữ liệu để xuất.")
            return
        name = f"{self.source_path.stem}_updated.xlsx" if self.source_path else "AIV0_audio_updated.xlsx"
        path, _ = QFileDialog.getSaveFileName(self, "Xuất bảng đã cập nhật", name, "Excel (*.xlsx)")
        if not path:
            return
        try:
            save_workbook(path, self.records, self.audit_entries)
            self.status_label.setText(f"Đã xuất {Path(path).name}")
            QMessageBox.information(self, "Đã xuất Excel", path)
        except Exception as error:
            QMessageBox.critical(self, "Không xuất được bảng", str(error))

    def refresh_table(self) -> None:
        selected = set(self._selected_record_ids())
        query = self.search.text().strip().casefold()
        result_filter = self.result_filter.currentText()
        category_filter = self.category_filter.currentText()
        self.table.setUpdatesEnabled(False)
        self.table.setRowCount(0)
        for record in self.records:
            searchable = " ".join(
                (
                    record.record_id,
                    record.batch_id,
                    record.sentence_code,
                    record.source_vi,
                    record.official_filename,
                    record.audio_id,
                    record.error_categories,
                    record.repair_suggestion,
                )
            ).casefold()
            if query and query not in searchable:
                continue
            if result_filter != "Tất cả kết quả" and record.test_result != result_filter:
                continue
            if category_filter != "Tất cả loại lỗi" and category_filter not in split_categories(record.error_categories):
                continue
            row = self.table.rowCount()
            self.table.insertRow(row)
            values = (
                record.record_id,
                record.sentence_code,
                record.source_vi,
                record.test_result,
                record.error_categories,
                record.repair_status,
                record.official_filename,
                str(record.audio_version),
            )
            for column, value in enumerate(values):
                item = QTableWidgetItem(value)
                item.setData(Qt.ItemDataRole.UserRole, record.record_id)
                self.table.setItem(row, column, item)
            if record.record_id in selected:
                self.table.selectRow(row)
        self.table.setUpdatesEnabled(True)
        self._update_stats()

    def _update_stats(self) -> None:
        values = (
            len(self.records),
            sum(record.test_result == "Đạt" for record in self.records),
            sum(record.test_result == "Không đạt" for record in self.records),
            sum(record.test_result == "Kiểm thử lại" for record in self.records),
        )
        for panel, value in zip(self.stats, values):
            panel.value.setText(str(value))

    def _selected_record_ids(self) -> list[str]:
        ids: list[str] = []
        if not hasattr(self, "table"):
            return ids
        for index in self.table.selectionModel().selectedRows():
            item = self.table.item(index.row(), 0)
            if item:
                ids.append(str(item.data(Qt.ItemDataRole.UserRole)))
        return ids

    def _on_selection(self) -> None:
        selected = self._selected_record_ids()
        if not selected:
            return
        record = self._record_by_id(selected[0])
        for field, editor in self.detail_fields.items():
            editor.setText(str(getattr(record, field)))
        self.source_text.setPlainText(record.source_vi)
        self.observed_text.setPlainText(record.observed_result)
        self.repair_text.setPlainText(record.repair_suggestion)
        self.note_text.setPlainText(record.note)
        self.repair_status.setCurrentText(record.repair_status)
        self.reviewer.setText(record.reviewer)
        self.result_group.setExclusive(False)
        for button in self.result_buttons.values():
            button.setChecked(False)
        self.result_group.setExclusive(True)
        if record.test_result in self.result_buttons:
            self.result_buttons[record.test_result].setChecked(True)
        selected_categories = set(split_categories(record.error_categories))
        for index in range(self.category_list.count()):
            item = self.category_list.item(index)
            item.setCheckState(
                Qt.CheckState.Checked if item.text() in selected_categories else Qt.CheckState.Unchecked
            )
        self._load_audio(record)

    def _checked_result(self) -> str:
        button = self.result_group.checkedButton()
        return button.text() if button else "Chưa kiểm thử"

    def _checked_categories(self) -> list[str]:
        result: list[str] = []
        for index in range(self.category_list.count()):
            item = self.category_list.item(index)
            if item.checkState() == Qt.CheckState.Checked:
                result.append(item.text())
        return result

    def save_detail(self) -> bool:
        return self._save_detail(move_next=False)

    def save_and_next(self) -> None:
        self._save_detail(move_next=True)

    def _save_detail(self, move_next: bool) -> bool:
        selected = self._selected_record_ids()
        if not selected:
            QMessageBox.information(self, "Chưa chọn bản ghi", "Chọn một dòng cần kiểm thử.")
            return False
        current_row = self.table.currentRow()
        record = self._record_by_id(selected[0])
        result = self._checked_result()
        categories = self._checked_categories()
        if result == "Không đạt" and not categories:
            QMessageBox.warning(self, "Thiếu loại lỗi", "Mẫu Không đạt cần ít nhất một loại lỗi.")
            return False
        old_result = record.test_result
        old_id = record.audio_id
        for field, editor in self.detail_fields.items():
            if field != "record_id":
                setattr(record, field, editor.text().strip())
        record.source_vi = self.source_text.toPlainText().strip()
        record.test_result = result
        record.error_categories = "" if result == "Đạt" else join_categories(categories)
        record.observed_result = self.observed_text.toPlainText().strip()
        record.repair_suggestion = self.repair_text.toPlainText().strip()
        record.repair_status = "Không cần sửa" if result == "Đạt" else self.repair_status.currentText()
        if result == "Không đạt" and record.repair_suggestion and record.repair_status == "Chưa xử lý":
            record.repair_status = "Đã đề xuất"
        record.reviewer = self.reviewer.text().strip()
        record.reviewed_at = utc_now_text()
        record.note = self.note_text.toPlainText().strip()
        self.audit_entries.append(
            AuditEntry.create(
                record.record_id,
                "REVIEW_AUDIO",
                old_result,
                record.test_result,
                f"categories={record.error_categories}; old_audio_id={old_id}; new_audio_id={record.audio_id}",
            )
        )
        self.refresh_table()
        self.status_label.setText(f"Đã lưu kiểm thử cho {record.record_id}")
        if move_next and self.table.rowCount():
            next_row = min(max(current_row, 0) + 1, self.table.rowCount() - 1)
            self.table.selectRow(next_row)
            self.table.setCurrentCell(next_row, 0)
            self.table.scrollToItem(self.table.item(next_row, 0))
        return True

    def _load_audio(self, record: AudioRecord) -> None:
        path = Path(record.local_audio_path)
        if not path.is_file():
            self.player.stop()
            self.player.setSource(QUrl())
            self.current_audio_path = ""
            self.audio_name.setText("Chưa ghép audio")
            self.audio_slider.setRange(0, 0)
            self.audio_time.setText("00:00 / 00:00")
            return
        resolved = str(path.resolve())
        self.audio_name.setText(path.name)
        self.audio_name.setToolTip(resolved)
        if resolved != self.current_audio_path:
            self.player.stop()
            self.player.setSource(QUrl.fromLocalFile(resolved))
            self.current_audio_path = resolved

    def toggle_audio(self) -> None:
        if not self.current_audio_path:
            QMessageBox.information(self, "Chưa có audio", "Bản ghi này chưa được ghép file audio cục bộ.")
            return
        if self.player.playbackState() == QMediaPlayer.PlaybackState.PlayingState:
            self.player.pause()
        else:
            self.player.play()

    def _on_playback_state(self, state: QMediaPlayer.PlaybackState) -> None:
        icon = QStyle.StandardPixmap.SP_MediaPause if state == QMediaPlayer.PlaybackState.PlayingState else QStyle.StandardPixmap.SP_MediaPlay
        self.play_button.setIcon(self._icon(icon))

    def _on_audio_position(self, position: int) -> None:
        if not self.audio_slider.isSliderDown():
            self.audio_slider.setValue(position)
        self.audio_time.setText(f"{self._format_time(position)} / {self._format_time(self.player.duration())}")

    def _on_audio_duration(self, duration: int) -> None:
        self.audio_slider.setRange(0, duration)
        self.audio_time.setText(f"{self._format_time(self.player.position())} / {self._format_time(duration)}")

    def _on_audio_error(self, _error: QMediaPlayer.Error, error_text: str) -> None:
        if error_text:
            self.status_label.setText(f"Lỗi phát audio: {error_text}")

    @staticmethod
    def _format_time(milliseconds: int) -> str:
        seconds = max(0, milliseconds // 1000)
        return f"{seconds // 60:02d}:{seconds % 60:02d}"

    def open_audio(self) -> None:
        selected = self._selected_record_ids()
        if not selected:
            return
        path = Path(self._record_by_id(selected[0]).local_audio_path)
        if not path.is_file():
            QMessageBox.information(self, "Chưa có audio", "Bản ghi này chưa được ghép file audio cục bộ.")
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))

    def _record_by_id(self, record_id: str) -> AudioRecord:
        for record in self.records:
            if record.record_id == record_id:
                return record
        raise KeyError(record_id)


APP_STYLESHEET = """
QWidget {
    background: #F4F7F9;
    color: #17212B;
    font-family: "Segoe UI";
    font-size: 10pt;
}
QLabel#title { font-size: 20pt; font-weight: 600; }
QLabel#sectionTitle { font-size: 11pt; font-weight: 600; }
QLabel#muted { color: #5E6B78; }
QLabel#audioName { font-weight: 600; }
QLabel#bulkCount { color: #176B5B; font-size: 14pt; font-weight: 600; padding: 8px 0; }
QFrame#surface, QFrame#statPanel {
    background: #FFFFFF;
    border: 1px solid #D9E0E7;
    border-radius: 6px;
}
QLabel#statValue { background: transparent; font-size: 18pt; font-weight: 600; }
QFrame#statPanel QLabel { background: transparent; }
QPushButton {
    background: #FFFFFF;
    border: 1px solid #C8D2DA;
    border-radius: 5px;
    padding: 7px 11px;
    font-weight: 600;
}
QPushButton:hover { background: #EDF2F5; }
QPushButton#primaryButton { background: #176B5B; border-color: #176B5B; color: #FFFFFF; }
QPushButton#primaryButton:hover { background: #105247; }
QPushButton#passButton:checked { background: #DDF2E8; border-color: #2B7A61; color: #15513F; }
QPushButton#failButton:checked { background: #F8E1E1; border-color: #B54A4A; color: #862D2D; }
QPushButton#retestButton:checked { background: #FFF0D8; border-color: #B8781D; color: #7C4C08; }
QLineEdit, QComboBox, QPlainTextEdit, QListWidget {
    background: #FFFFFF;
    border: 1px solid #C8D2DA;
    border-radius: 4px;
    padding: 6px;
    selection-background-color: #B9DDD4;
}
QListWidget::item { min-height: 25px; }
QTableWidget {
    background: #FFFFFF;
    alternate-background-color: #F8FAFB;
    border: 0;
    gridline-color: #E2E7EB;
    selection-background-color: #CFE7E1;
    selection-color: #17212B;
}
QHeaderView::section {
    background: #E9EEF2;
    border: 0;
    border-right: 1px solid #D2DADF;
    border-bottom: 1px solid #CDD6DC;
    padding: 8px;
    font-weight: 600;
}
QTabWidget::pane { border: 1px solid #D9E0E7; background: #FFFFFF; }
QTabBar::tab { background: #E9EEF2; padding: 7px 14px; margin-right: 2px; }
QTabBar::tab:selected { background: #FFFFFF; color: #176B5B; font-weight: 600; }
QSlider::groove:horizontal { height: 5px; background: #D9E0E7; border-radius: 2px; }
QSlider::handle:horizontal { width: 14px; margin: -5px 0; background: #176B5B; border-radius: 7px; }
QSplitter::handle { background: #D9E0E7; width: 5px; }
"""


def run_app() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName("AIV0 Batch Audio Reviewer")
    app.setStyle("Fusion")
    app.setStyleSheet(APP_STYLESHEET)
    window = BatchReviewerWindow()
    window.show()
    sys.exit(app.exec())

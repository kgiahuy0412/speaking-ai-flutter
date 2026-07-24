import fs from "node:fs/promises";
import crypto from "node:crypto";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const audioDir = String.raw`C:\Users\Windows\Documents\AI-SPEAKING-APP\k9sxg2twv4-4\mp3`;
const outputDir = String.raw`C:\Users\Windows\Documents\ai-speaking-flutter-app\outputs\aiv0-pilot-01`;
const qaDir = path.join(outputDir, "qa");
const outputPath = path.join(outputDir, "AIV0_PILOT_01_207_audio_ready.xlsx");

const headers = [
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
];

async function sha256(filePath) {
  const bytes = await fs.readFile(filePath);
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

const entries = (await fs.readdir(audioDir, { withFileTypes: true }))
  .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".mp3"))
  .map((entry) => entry.name)
  .sort((a, b) => a.localeCompare(b, "en", { numeric: true, sensitivity: "base" }));

if (entries.length < 207) {
  throw new Error(`Can it nhat 207 file MP3, nhung chi tim thay ${entries.length}.`);
}

const selected = entries.slice(0, 207);
const generatedAt = new Date();
const rows = [];

for (let index = 0; index < selected.length; index += 1) {
  const filename = selected[index];
  const localPath = path.join(audioDir, filename);
  const hash = await sha256(localPath);
  const ordinal = String(index + 1).padStart(3, "0");

  rows.push([
    `AIV0-P01-${ordinal}`,
    "AIV0-PILOT-01",
    `S${ordinal}`,
    "",
    "",
    filename,
    filename,
    localPath,
    `local_${hash.slice(0, 16)}`,
    hash,
    1,
    "Đã ghép cục bộ",
    generatedAt,
    "Chưa kiểm thử",
    "",
    "",
    "",
    "Chưa xử lý",
    "",
    null,
    "Audio bản nháp - chờ bản chính",
  ]);
}

const workbook = Workbook.create();
const samples = workbook.worksheets.add("Samples");
const instructions = workbook.worksheets.add("Instructions");
const uploadLog = workbook.worksheets.add("Upload Log");

const navy = "#16324F";
const teal = "#0F766E";
const paleTeal = "#E6F5F2";
const paleBlue = "#EAF1F8";
const paleAmber = "#FFF4D6";
const paleRed = "#FDECEC";
const paleGreen = "#E9F6EE";
const border = "#D6DEE8";
const text = "#243447";
const muted = "#5F6F7F";

for (const sheet of [samples, instructions, uploadLog]) {
  sheet.showGridLines = false;
}

const lastRow = rows.length + 1;
samples.getRange(`A1:U${lastRow}`).values = [headers, ...rows];
samples.freezePanes.freezeRows(1);
samples.freezePanes.freezeColumns(3);
samples.getRange(`A1:U${lastRow}`).format.font = { name: "Aptos", size: 10, color: text };
samples.getRange("A1:U1").format = {
  fill: navy,
  font: { name: "Aptos Display", size: 10, bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  wrapText: true,
  borders: { preset: "outside", style: "thin", color: navy },
};
samples.getRange("A1:U1").format.rowHeight = 34;
samples.getRange(`A2:U${lastRow}`).format.rowHeight = 22;
samples.getRange(`A2:C${lastRow}`).format.fill = paleBlue;
samples.getRange(`H2:M${lastRow}`).format.fill = "#F7FAFC";
samples.getRange(`N2:R${lastRow}`).format.fill = "#FFFCF2";
samples.getRange(`A2:U${lastRow}`).format.borders = {
  insideHorizontal: { style: "thin", color: "#EDF1F5" },
  bottom: { style: "thin", color: border },
};
samples.getRange(`A2:C${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`I2:N${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`R2:T${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`K2:K${lastRow}`).format.numberFormat = "0";
samples.getRange(`M2:M${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";
samples.getRange(`T2:T${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";

const widths = [18, 18, 14, 28, 28, 42, 42, 68, 25, 66, 12, 18, 22, 16, 30, 32, 36, 16, 18, 22, 30];
for (let column = 0; column < widths.length; column += 1) {
  samples.getRangeByIndexes(0, column, lastRow, 1).format.columnWidth = widths[column];
}

samples.getRange(`N2:N${lastRow}`).dataValidation = {
  rule: { type: "list", values: ["Chưa kiểm thử", "Đạt", "Không đạt", "Kiểm thử lại"] },
};
samples.getRange(`R2:R${lastRow}`).dataValidation = {
  rule: { type: "list", values: ["Chưa xử lý", "Không cần sửa", "Đã đề xuất", "Đang sửa", "Đã sửa", "Cần thu lại", "Không thể sửa"] },
};

const resultRange = samples.getRange(`N2:N${lastRow}`);
resultRange.conditionalFormats.addCustom('=$N2="Đạt"', { fill: paleGreen, font: { color: "#146C43", bold: true } });
resultRange.conditionalFormats.addCustom('=$N2="Không đạt"', { fill: paleRed, font: { color: "#B42318", bold: true } });
resultRange.conditionalFormats.addCustom('=$N2="Kiểm thử lại"', { fill: paleAmber, font: { color: "#8A5700", bold: true } });

const repairRange = samples.getRange(`R2:R${lastRow}`);
repairRange.conditionalFormats.addCustom('=$R2="Đã sửa"', { fill: paleGreen, font: { color: "#146C43", bold: true } });
repairRange.conditionalFormats.addCustom('=$R2="Đang sửa"', { fill: paleAmber, font: { color: "#8A5700", bold: true } });

const samplesTable = samples.tables.add(`A1:U${lastRow}`, true, "SamplesTable");
samplesTable.style = "TableStyleMedium2";
samplesTable.showBandedColumns = false;
samplesTable.showFilterButton = true;

instructions.mergeCells("A1:H1");
instructions.getRange("A1").values = [["AIV0 PILOT 01 - 207 AUDIO ĐÃ GHÉP SẴN"]];
instructions.getRange("A1:H1").format = {
  fill: navy,
  font: { name: "Aptos Display", size: 18, bold: true, color: "#FFFFFF" },
  horizontalAlignment: "left",
  verticalAlignment: "center",
};
instructions.getRange("A1:H1").format.rowHeight = 42;
instructions.getRange("A3:B7").values = [
  ["Batch ID", "AIV0-PILOT-01"],
  ["Số record", 207],
  ["Thư mục audio", audioDir],
  ["Phạm vi", "207 file MP3 đầu tiên theo tên file"],
  ["Chế độ", "Chỉ lưu đường dẫn, không nhúng audio vào Excel"],
];
instructions.getRange("A3:A7").format = {
  fill: paleTeal,
  font: { bold: true, color: teal },
  verticalAlignment: "center",
};
instructions.getRange("B3:B7").format = { fill: "#FFFFFF", font: { color: text }, wrapText: true };
instructions.getRange("A3:B7").format.borders = { preset: "outside", style: "thin", color: border };
instructions.getRange("A3:A7").format.columnWidth = 22;
instructions.getRange("B3:B7").format.columnWidth = 90;
instructions.getRange("A3:B7").format.rowHeight = 25;

instructions.mergeCells("A9:H9");
instructions.getRange("A9").values = [["QUY TRÌNH SỬ DỤNG VỚI V0.2"]];
instructions.getRange("A9:H9").format = {
  fill: teal,
  font: { bold: true, color: "#FFFFFF" },
  verticalAlignment: "center",
};
instructions.getRange("A9:H9").format.rowHeight = 28;

const steps = [
  "1. Mở AIV0-Batch-Audio-Reviewer-v0.2.exe và chọn file Excel này.",
  "2. Chọn một dòng trong bảng; audio sẽ phát từ local_audio_path, không cần quét lại thư mục lớn.",
  "3. Đánh giá Đạt/Không đạt, chọn nhóm lỗi, ghi kết quả nghe và đề xuất sửa.",
  "4. Dùng sửa hàng loạt theo error_categories khi nhiều record có cùng loại lỗi.",
  "5. Xuất workbook mới sau khi đánh giá; không đổi record_id khi thay audio bản chính.",
];
for (let index = 0; index < steps.length; index += 1) {
  const row = 10 + index;
  instructions.mergeCells(`A${row}:H${row}`);
  instructions.getRange(`A${row}`).values = [[steps[index]]];
  instructions.getRange(`A${row}:H${row}`).format = {
    fill: index % 2 === 0 ? "#FFFFFF" : "#F7FAFC",
    font: { color: text },
    verticalAlignment: "center",
    wrapText: true,
    borders: { bottom: { style: "thin", color: "#EDF1F5" } },
  };
  instructions.getRange(`A${row}:H${row}`).format.rowHeight = 28;
}

instructions.mergeCells("A16:H16");
instructions.getRange("A16").values = [["NHÓM LỖI GỢI Ý"]];
instructions.getRange("A16:H16").format = { fill: paleAmber, font: { bold: true, color: "#8A5700" } };
instructions.getRange("A17:B21").values = [
  ["Phát âm không chuẩn", "Sai âm, sai trọng âm hoặc phát âm không đúng mẫu"],
  ["Giọng vùng miền", "Giọng địa phương ảnh hưởng mục tiêu đánh giá"],
  ["Nghe không rõ", "Không xác định được nội dung hoặc từ quan trọng"],
  ["Khó nghe", "Vẫn nghe được nhưng cần tập trung cao"],
  ["Tạp âm / chất lượng thu", "Rè, vỡ tiếng, âm lượng quá nhỏ hoặc nhiều tiếng nền"],
];
instructions.getRange("A17:A21").format = { fill: paleBlue, font: { bold: true, color: navy } };
instructions.getRange("A17:B21").format.wrapText = true;
instructions.getRange("A17:B21").format.borders = { preset: "outside", style: "thin", color: border };
instructions.getRange("A17:B21").format.rowHeight = 30;

uploadLog.getRange("A1:F2").values = [
  ["timestamp", "record_id", "action", "old_value", "new_value", "detail"],
  [generatedAt, "BATCH", "WORKBOOK_CREATED", "", "207 records", "Pre-linked local MP3 paths and SHA-256 identifiers"],
];
uploadLog.freezePanes.freezeRows(1);
uploadLog.getRange("A1:F1").format = {
  fill: navy,
  font: { bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center",
  verticalAlignment: "center",
};
uploadLog.getRange("A1:F1").format.rowHeight = 28;
uploadLog.getRange("A2:F2").format = { font: { color: text }, fill: "#FFFFFF" };
uploadLog.getRange("A2:A2").format.numberFormat = "yyyy-mm-dd hh:mm";
const logWidths = [22, 20, 24, 24, 24, 60];
for (let column = 0; column < logWidths.length; column += 1) {
  uploadLog.getRangeByIndexes(0, column, 2, 1).format.columnWidth = logWidths[column];
}
uploadLog.tables.add("A1:F2", true, "UploadLogTable").style = "TableStyleMedium2";

await fs.mkdir(qaDir, { recursive: true });

const sampleStartPreview = await workbook.render({ sheetName: "Samples", range: "A1:H12", scale: 1, format: "png" });
await fs.writeFile(path.join(qaDir, "samples_start.png"), new Uint8Array(await sampleStartPreview.arrayBuffer()));
const sampleReviewPreview = await workbook.render({ sheetName: "Samples", range: "N1:U12", scale: 1, format: "png" });
await fs.writeFile(path.join(qaDir, "samples_review.png"), new Uint8Array(await sampleReviewPreview.arrayBuffer()));
const instructionsPreview = await workbook.render({ sheetName: "Instructions", range: "A1:H21", scale: 1, format: "png" });
await fs.writeFile(path.join(qaDir, "instructions.png"), new Uint8Array(await instructionsPreview.arrayBuffer()));
const logPreview = await workbook.render({ sheetName: "Upload Log", range: "A1:F3", scale: 1, format: "png" });
await fs.writeFile(path.join(qaDir, "upload_log.png"), new Uint8Array(await logPreview.arrayBuffer()));

const startCheck = await workbook.inspect({
  kind: "table",
  range: "Samples!A1:U6",
  include: "values,formulas",
  tableMaxRows: 6,
  tableMaxCols: 21,
});
const endCheck = await workbook.inspect({
  kind: "table",
  range: "Samples!A204:U208",
  include: "values,formulas",
  tableMaxRows: 5,
  tableMaxCols: 21,
});
const formulaErrors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan",
});

await fs.mkdir(outputDir, { recursive: true });
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

console.log(JSON.stringify({
  outputPath,
  sourceMp3Count: entries.length,
  selectedCount: selected.length,
  firstFile: selected[0],
  lastFile: selected[selected.length - 1],
}));
console.log(startCheck.ndjson);
console.log(endCheck.ndjson);
console.log(formulaErrors.ndjson);

import fs from "node:fs/promises";
import crypto from "node:crypto";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const sourceRoot = String.raw`C:\Users\Windows\Documents\DOCUMENTS DỰ ÁN SPEAKING AI\ÂM THANH SPEAKING AI`;
const outputDir = String.raw`C:\Users\Windows\Documents\ai-speaking-flutter-app\outputs\aiv0-three-groups`;
const qaDir = path.join(outputDir, "qa");
const outputPath = path.join(outputDir, "AIV0_3_NHOM_60_AUDIO_REVIEW.xlsx");

const groups = [
  {
    folder: "gái-6tuoi-m.nam",
    code: "F06-S",
    batchId: "AIV0-F06-SOUTH",
    label: "Nữ 6 tuổi - Miền Nam",
    gender: "Nữ",
    age: 6,
    region: "Miền Nam",
  },
  {
    folder: "trai-6tuoi-bac",
    code: "M06-N",
    batchId: "AIV0-M06-NORTH",
    label: "Nam 6 tuổi - Miền Bắc",
    gender: "Nam",
    age: 6,
    region: "Miền Bắc",
  },
  {
    folder: "trai-7tuoi-bac",
    code: "M07-N",
    batchId: "AIV0-M07-NORTH",
    label: "Nam 7 tuổi - Miền Bắc",
    gender: "Nam",
    age: 7,
    region: "Miền Bắc",
  },
];

const standardHeaders = [
  "record_id", "batch_id", "sentence_code", "source_vi", "expected_en",
  "draft_filename", "official_filename", "local_audio_path", "audio_id", "audio_hash",
  "audio_version", "upload_status", "uploaded_at", "test_result", "error_categories",
  "observed_result", "repair_suggestion", "repair_status", "reviewer", "reviewed_at", "note",
];
const extraHeaders = [
  "speaker_group", "gender", "age_years", "region", "question_number", "source_folder",
  "normalized_filename", "file_extension", "file_size_kb", "modified_at", "path_check",
];
const headers = [...standardHeaders, ...extraHeaders];

async function listFilesRecursive(folderPath) {
  const result = [];
  const entries = await fs.readdir(folderPath, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(folderPath, entry.name);
    if (entry.isDirectory()) result.push(...await listFilesRecursive(fullPath));
    else if (entry.isFile()) result.push(fullPath);
  }
  return result;
}

const generatedAt = new Date();
const rows = [];
const groupStats = [];
const seenIds = new Set();
let totalBytes = 0;
let invalidHeaders = 0;
let zeroBytes = 0;

for (const group of groups) {
  const groupRoot = path.join(sourceRoot, group.folder);
  const files = (await listFilesRecursive(groupRoot))
    .filter((filePath) => path.extname(filePath).toLowerCase() === ".m4a")
    .map((filePath) => {
      const match = path.basename(filePath, path.extname(filePath)).match(/(\d+)/);
      if (!match) throw new Error(`Không nhận diện được số câu: ${filePath}`);
      return { filePath, question: Number(match[1]) };
    })
    .sort((a, b) => a.question - b.question);

  const uniqueQuestions = new Set(files.map((item) => item.question));
  const missingQuestions = Array.from({ length: 20 }, (_, index) => index + 1)
    .filter((question) => !uniqueQuestions.has(question));
  if (files.length !== 20 || uniqueQuestions.size !== 20 || missingQuestions.length) {
    throw new Error(`${group.folder}: cần đủ 20 câu duy nhất, thiếu ${missingQuestions.join(", ") || "không rõ"}.`);
  }

  let groupBytes = 0;
  for (const { filePath, question } of files) {
    const stat = await fs.stat(filePath);
    const bytes = await fs.readFile(filePath);
    const validHeader = bytes.length >= 12 && bytes.toString("ascii", 4, 8) === "ftyp";
    const hash = crypto.createHash("sha256").update(bytes).digest("hex");
    const qCode = `Q${String(question).padStart(3, "0")}`;
    const recordId = `AIV0-${group.code}-${qCode}`;
    if (seenIds.has(recordId)) throw new Error(`Trùng record_id: ${recordId}`);
    seenIds.add(recordId);

    if (stat.size === 0) zeroBytes += 1;
    if (!validHeader) invalidHeaders += 1;
    totalBytes += stat.size;
    groupBytes += stat.size;

    rows.push([
      recordId,
      group.batchId,
      qCode,
      "",
      "",
      path.basename(filePath),
      path.basename(filePath),
      filePath,
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
      "",
      group.label,
      group.gender,
      group.age,
      group.region,
      question,
      path.relative(sourceRoot, path.dirname(filePath)),
      `${group.code}-${qCode}.m4a`,
      ".m4a",
      Math.round((stat.size / 1024) * 10) / 10,
      stat.mtime,
      stat.size > 0 && validHeader ? "Sẵn sàng" : "Cần kiểm tra",
    ]);
  }

  groupStats.push({ ...group, count: files.length, sizeMB: groupBytes / 1024 / 1024 });
}

const workbook = Workbook.create();
const summary = workbook.worksheets.add("Summary");
const samples = workbook.worksheets.add("Samples");
const instructions = workbook.worksheets.add("Instructions");
const uploadLog = workbook.worksheets.add("Upload Log");

const navy = "#17324D";
const teal = "#147D75";
const paleBlue = "#EAF2F8";
const paleTeal = "#E5F4F1";
const paleAmber = "#FFF3D6";
const paleGreen = "#E8F5ED";
const paleRed = "#FDECEC";
const border = "#D6DEE7";
const text = "#243447";

for (const sheet of [summary, samples, instructions, uploadLog]) sheet.showGridLines = false;

const lastRow = rows.length + 1;
samples.getRange(`A1:AF${lastRow}`).values = [headers, ...rows];
samples.freezePanes.freezeRows(1);
samples.freezePanes.freezeColumns(3);
samples.getRange("A1:AF1").format = {
  fill: navy,
  font: { name: "Aptos", size: 10, bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  wrapText: true,
};
samples.getRange("A1:AF1").format.rowHeight = 34;
samples.getRange(`A2:AF${lastRow}`).format.font = { name: "Aptos", size: 10, color: text };
samples.getRange(`A2:AF${lastRow}`).format.rowHeight = 22;
samples.getRange(`A2:C${lastRow}`).format.fill = paleBlue;
samples.getRange(`N2:R${lastRow}`).format.fill = "#FFFCF3";
samples.getRange(`V2:AF${lastRow}`).format.fill = "#F7FAFC";
samples.getRange(`A2:AF${lastRow}`).format.borders = {
  insideHorizontal: { style: "thin", color: "#EDF1F5" },
  bottom: { style: "thin", color: border },
};
samples.getRange(`A2:C${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`I2:N${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`R2:AF${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`K2:K${lastRow}`).format.numberFormat = "0";
samples.getRange(`M2:M${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";
samples.getRange(`T2:T${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";
samples.getRange(`X2:X${lastRow}`).format.numberFormat = "0";
samples.getRange(`Z2:Z${lastRow}`).format.numberFormat = "0";
samples.getRange(`AD2:AD${lastRow}`).format.numberFormat = "0.0";
samples.getRange(`AE2:AE${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm:ss";

const widths = [24, 22, 14, 24, 24, 20, 20, 72, 25, 66, 11, 18, 22, 16, 28, 30, 34, 16, 17, 22, 24, 28, 12, 10, 14, 14, 44, 22, 12, 14, 22, 16];
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

const samplesTable = samples.tables.add(`A1:AF${lastRow}`, true, "ThreeGroupsAudioTable");
samplesTable.style = "TableStyleMedium2";
samplesTable.showFilterButton = true;

summary.mergeCells("A1:H1");
summary.getRange("A1").values = [["AIV0 - 3 NHÓM ÂM THANH SPEAKING AI"]];
summary.getRange("A1:H1").format = {
  fill: navy,
  font: { name: "Aptos Display", size: 18, bold: true, color: "#FFFFFF" },
  verticalAlignment: "center",
};
summary.getRange("A1:H1").format.rowHeight = 42;

summary.getRange("A3:B9").values = [
  ["Chỉ số", "Giá trị"],
  ["Tổng audio", null],
  ["Tổng nhóm giọng", null],
  ["Số câu mỗi nhóm", 20],
  ["Định dạng", "M4A"],
  ["Tổng dung lượng (MB)", null],
  ["File cần kiểm tra", null],
];
summary.getRange("B4").formulas = [[`=COUNTA('Samples'!A2:A${lastRow})`]];
summary.getRange("B5").values = [[groups.length]];
summary.getRange("B8").formulas = [[`=SUM('Samples'!AD2:AD${lastRow})/1024`]];
summary.getRange("B9").formulas = [[`=COUNTIF('Samples'!AF2:AF${lastRow},"<>Sẵn sàng")`]];
summary.getRange("B4:B7").format.numberFormat = "#,##0";
summary.getRange("B8").format.numberFormat = "0.00";
summary.getRange("B9").format.numberFormat = "#,##0";
summary.getRange("A3:B3").format = { fill: teal, font: { bold: true, color: "#FFFFFF" } };
summary.getRange("A4:A9").format = { fill: paleTeal, font: { bold: true, color: teal } };
summary.getRange("A3:B9").format.borders = { preset: "outside", style: "thin", color: border };
summary.getRange("A3:A9").format.columnWidth = 28;
summary.getRange("B3:B9").format.columnWidth = 22;
summary.getRange("A3:B9").format.rowHeight = 26;

summary.getRange("D3:H3").values = [["Nhóm giọng", "Batch ID", "Số file", "Dung lượng MB", "Dải câu"]];
summary.getRange("D4:H6").values = groupStats.map((group) => [
  group.label,
  group.batchId,
  group.count,
  Math.round(group.sizeMB * 100) / 100,
  "Q001 - Q020",
]);
summary.getRange("D3:H3").format = { fill: navy, font: { bold: true, color: "#FFFFFF" } };
summary.getRange("D4:H6").format = { fill: "#FFFFFF", font: { color: text } };
summary.getRange("D3:H6").format.borders = { preset: "all", style: "thin", color: border };
summary.getRange("D3:D6").format.columnWidth = 28;
summary.getRange("E3:E6").format.columnWidth = 23;
summary.getRange("F3:F6").format.columnWidth = 14;
summary.getRange("G3:G6").format.columnWidth = 18;
summary.getRange("H3:H6").format.columnWidth = 18;
summary.getRange("F4:F6").format.numberFormat = "#,##0";
summary.getRange("G4:G6").format.numberFormat = "0.00";

summary.mergeCells("A11:H11");
summary.getRange("A11").values = [["KIỂM TRA NGUỒN"]];
summary.getRange("A11:H11").format = { fill: paleAmber, font: { bold: true, color: "#8A5700" } };
summary.getRange("A12:B16").values = [
  ["Thư mục gốc", sourceRoot],
  ["File 0 byte", zeroBytes],
  ["Header M4A không hợp lệ", invalidHeaders],
  ["Tên lệch đã nhận diện", "trai-6tuoi-bac: Câu4.m4a → Q004"],
  ["Cách liên kết", "Lưu đường dẫn cục bộ; không nhúng audio vào Excel"],
];
summary.getRange("A12:A16").format = { fill: paleBlue, font: { bold: true, color: navy } };
summary.getRange("A12:B16").format.borders = { preset: "outside", style: "thin", color: border };
summary.getRange("B12:B16").format.columnWidth = 92;
summary.getRange("A12:B16").format.rowHeight = 27;

instructions.mergeCells("A1:H1");
instructions.getRange("A1").values = [["HƯỚNG DẪN KIỂM THỬ 3 NHÓM AUDIO"]];
instructions.getRange("A1:H1").format = { fill: navy, font: { size: 18, bold: true, color: "#FFFFFF" }, verticalAlignment: "center" };
instructions.getRange("A1:H1").format.rowHeight = 42;
instructions.mergeCells("A3:H3");
instructions.getRange("A3").values = [["QUY TRÌNH KHUYẾN NGHỊ"]];
instructions.getRange("A3:H3").format = { fill: teal, font: { bold: true, color: "#FFFFFF" } };
const steps = [
  "1. Mở workbook bằng AIV0-Batch-Audio-Reviewer-v0.2.exe.",
  "2. Lọc batch_id để làm lần lượt từng nhóm giọng; mỗi nhóm có 20 câu.",
  "3. Chọn dòng để nghe file M4A từ local_audio_path; không cần ghép lại thư mục.",
  "4. Với mẫu Không đạt: chọn loại lỗi, ghi kết quả thực tế và đề xuất sửa.",
  "5. Dùng Sửa hàng loạt cho các mẫu Không đạt có cùng error_categories.",
  "6. Khi thay audio: giữ nguyên record_id, cập nhật file/path/hash và tăng audio_version.",
];
for (let index = 0; index < steps.length; index += 1) {
  const row = 4 + index;
  instructions.mergeCells(`A${row}:H${row}`);
  instructions.getRange(`A${row}`).values = [[steps[index]]];
  instructions.getRange(`A${row}:H${row}`).format = {
    fill: index % 2 === 0 ? "#FFFFFF" : "#F7FAFC",
    font: { color: text },
    wrapText: true,
    verticalAlignment: "center",
    borders: { bottom: { style: "thin", color: "#EDF1F5" } },
  };
  instructions.getRange(`A${row}:H${row}`).format.rowHeight = 29;
}

instructions.mergeCells("A11:H11");
instructions.getRange("A11").values = [["NHÓM LỖI CÓ SẴN TRONG V0.2"]];
instructions.getRange("A11:H11").format = { fill: paleAmber, font: { bold: true, color: "#8A5700" } };
const categories = [
  ["Phát âm không chuẩn", "Giọng vùng miền", "Nghe không rõ"],
  ["Khó nghe", "Nói quá nhanh", "Nói quá nhỏ"],
  ["Tạp âm nền", "Âm thanh bị rè", "Mất đầu hoặc cuối câu"],
  ["Nội dung không đúng câu mẫu", "ASR nhận dạng sai", "Dịch sai nghĩa"],
  ["Không có kết quả", "File audio lỗi", "Khác"],
];
instructions.getRange("A12:C16").values = categories;
instructions.getRange("A12:C16").format = {
  fill: paleBlue,
  font: { bold: true, color: navy },
  wrapText: true,
  borders: { preset: "all", style: "thin", color: border },
};
instructions.getRange("A12:C16").format.rowHeight = 30;
instructions.getRange("A1:A16").format.columnWidth = 34;
instructions.getRange("B1:B16").format.columnWidth = 34;
instructions.getRange("C1:C16").format.columnWidth = 34;

uploadLog.getRange("A1:F2").values = [
  ["timestamp", "record_id", "action", "old_value", "new_value", "detail"],
  [generatedAt, "ALL", "WORKBOOK_CREATED", "", `${rows.length} records`, "Linked 3 local M4A folders and calculated SHA-256"],
];
uploadLog.freezePanes.freezeRows(1);
uploadLog.getRange("A1:F1").format = { fill: navy, font: { bold: true, color: "#FFFFFF" }, horizontalAlignment: "center" };
uploadLog.getRange("A1:F1").format.rowHeight = 28;
uploadLog.getRange("A2:A2").format.numberFormat = "yyyy-mm-dd hh:mm";
const logWidths = [22, 20, 24, 22, 22, 60];
for (let column = 0; column < logWidths.length; column += 1) {
  uploadLog.getRangeByIndexes(0, column, 2, 1).format.columnWidth = logWidths[column];
}
uploadLog.tables.add("A1:F2", true, "ThreeGroupsLogTable").style = "TableStyleMedium2";

await fs.mkdir(qaDir, { recursive: true });
const previews = [
  ["summary.png", { sheetName: "Summary", range: "A1:H16", scale: 1, format: "png" }],
  ["samples_ids.png", { sheetName: "Samples", range: "A1:H12", scale: 1, format: "png" }],
  ["samples_review.png", { sheetName: "Samples", range: "N1:AF12", scale: 1, format: "png" }],
  ["instructions.png", { sheetName: "Instructions", range: "A1:H16", scale: 1, format: "png" }],
  ["upload_log.png", { sheetName: "Upload Log", range: "A1:F3", scale: 1, format: "png" }],
];
for (const [filename, options] of previews) {
  const preview = await workbook.render(options);
  await fs.writeFile(path.join(qaDir, filename), new Uint8Array(await preview.arrayBuffer()));
}

const firstCheck = await workbook.inspect({ kind: "table", range: "Samples!A1:AF6", include: "values,formulas", tableMaxRows: 6, tableMaxCols: 32 });
const lastCheck = await workbook.inspect({ kind: "table", range: `Samples!A${lastRow - 4}:AF${lastRow}`, include: "values,formulas", tableMaxRows: 5, tableMaxCols: 32 });
const summaryCheck = await workbook.inspect({ kind: "table", range: "Summary!A1:H16", include: "values,formulas", tableMaxRows: 16, tableMaxCols: 8 });
const formulaErrors = await workbook.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, summary: "final formula error scan" });

await fs.mkdir(outputDir, { recursive: true });
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

console.log(JSON.stringify({
  outputPath,
  records: rows.length,
  uniqueIds: seenIds.size,
  totalMB: Number((totalBytes / 1024 / 1024).toFixed(2)),
  zeroBytes,
  invalidHeaders,
  groups: groupStats.map(({ label, batchId, count }) => ({ label, batchId, count })),
}));
console.log(firstCheck.ndjson);
console.log(lastCheck.ndjson);
console.log(summaryCheck.ndjson);
console.log(formulaErrors.ndjson);

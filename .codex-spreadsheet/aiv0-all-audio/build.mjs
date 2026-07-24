import fs from "node:fs/promises";
import crypto from "node:crypto";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const audioDir = String.raw`C:\Users\Windows\Documents\AI-SPEAKING-APP\k9sxg2twv4-4\mp3`;
const outputDir = String.raw`C:\Users\Windows\Documents\ai-speaking-flutter-app\outputs\aiv0-all-audio`;
const qaDir = path.join(outputDir, "qa");
const outputPath = path.join(outputDir, "AIV0_ALL_25921_audio_index.xlsx");
const batchSize = 500;

const standardHeaders = [
  "record_id", "batch_id", "sentence_code", "source_vi", "expected_en",
  "draft_filename", "official_filename", "local_audio_path", "audio_id", "audio_hash",
  "audio_version", "upload_status", "uploaded_at", "test_result", "error_categories",
  "observed_result", "repair_suggestion", "repair_status", "reviewer", "reviewed_at", "note",
];
const extraHeaders = ["source_group", "source_index", "file_size_kb", "modified_at", "path_check", "hash_status"];
const headers = [...standardHeaders, ...extraHeaders];

function parseFilename(filename) {
  let match = filename.match(/^FPTOpenSpeechData_(Set\d+)_V([\d.]+)_(\d+)\.mp3$/i);
  if (match) {
    const sourceGroup = match[1][0].toUpperCase() + match[1].slice(1).toLowerCase();
    const sourceIndex = Number(match[3]);
    const shortGroup = sourceGroup.replace("Set", "S").padEnd(4, "0");
    const firstIndex = sourceGroup === "Set001" ? 4 : 1;
    const batchNumber = Math.floor((sourceIndex - firstIndex) / batchSize) + 1;
    return {
      sourceGroup,
      sourceIndex,
      recordId: `AIV0-${shortGroup}-${String(sourceIndex).padStart(6, "0")}`,
      sentenceCode: `${shortGroup}-${String(sourceIndex).padStart(6, "0")}`,
      batchId: `AIV0-${shortGroup}-B${String(batchNumber).padStart(3, "0")}`,
    };
  }

  match = filename.match(/^(CV26-TEEN)-(\d+)\.mp3$/i);
  if (match) {
    const sourceIndex = Number(match[2]);
    return {
      sourceGroup: "CV26-TEEN",
      sourceIndex,
      recordId: `AIV0-CV26-TEEN-${String(sourceIndex).padStart(3, "0")}`,
      sentenceCode: `CV26-TEEN-${String(sourceIndex).padStart(3, "0")}`,
      batchId: "AIV0-CV26-TEEN-B001",
    };
  }

  const fallback = crypto.createHash("sha256").update(filename.toLowerCase()).digest("hex").slice(0, 12);
  return {
    sourceGroup: "OTHER",
    sourceIndex: null,
    recordId: `AIV0-OTHER-${fallback}`,
    sentenceCode: "",
    batchId: "AIV0-OTHER-B001",
  };
}

const filenames = (await fs.readdir(audioDir, { withFileTypes: true }))
  .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".mp3"))
  .map((entry) => entry.name)
  .sort((a, b) => a.localeCompare(b, "en", { numeric: true, sensitivity: "base" }));

const metadata = [];
for (let offset = 0; offset < filenames.length; offset += 256) {
  const chunk = filenames.slice(offset, offset + 256);
  const stats = await Promise.all(chunk.map(async (filename) => {
    const fullPath = path.join(audioDir, filename);
    const stat = await fs.stat(fullPath);
    return { filename, fullPath, stat };
  }));
  metadata.push(...stats);
  if (offset % 2560 === 0) {
    console.log(`metadata ${Math.min(offset + chunk.length, filenames.length)}/${filenames.length}`);
  }
}

if (metadata.length === 0) {
  throw new Error("Không tìm thấy file MP3 trong thư mục nguồn.");
}

const generatedAt = new Date();
const ids = new Set();
let totalBytes = 0;
let zeroByteCount = 0;
const groupCounts = new Map();
const batchCounts = new Map();

const rows = metadata.map(({ filename, fullPath, stat }) => {
  const parsed = parseFilename(filename);
  if (ids.has(parsed.recordId)) {
    throw new Error(`Trùng record_id: ${parsed.recordId}`);
  }
  ids.add(parsed.recordId);
  totalBytes += stat.size;
  if (stat.size === 0) zeroByteCount += 1;
  groupCounts.set(parsed.sourceGroup, (groupCounts.get(parsed.sourceGroup) ?? 0) + 1);
  batchCounts.set(parsed.batchId, (batchCounts.get(parsed.batchId) ?? 0) + 1);

  const localId = crypto.createHash("sha256").update(filename.toLowerCase()).digest("hex").slice(0, 16);
  return [
    parsed.recordId,
    parsed.batchId,
    parsed.sentenceCode,
    "",
    "",
    filename,
    filename,
    fullPath,
    `local_${localId}`,
    "",
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
    parsed.sourceGroup,
    parsed.sourceIndex,
    Math.round((stat.size / 1024) * 10) / 10,
    stat.mtime,
    stat.size > 0 ? "Sẵn sàng" : "File rỗng",
    "Chưa tính",
  ];
});

for (const [batchId, count] of batchCounts) {
  if (count > batchSize) throw new Error(`Batch ${batchId} vượt quá ${batchSize} audio.`);
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
const muted = "#617181";

for (const sheet of [summary, samples, instructions, uploadLog]) sheet.showGridLines = false;

const lastRow = rows.length + 1;
samples.getRange(`A1:AA${lastRow}`).values = [headers, ...rows];
samples.freezePanes.freezeRows(1);
samples.freezePanes.freezeColumns(3);
samples.getRange("A1:AA1").format = {
  fill: navy,
  font: { name: "Aptos", size: 10, bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  wrapText: true,
};
samples.getRange("A1:AA1").format.rowHeight = 34;
samples.getRange(`A2:AA${lastRow}`).format.font = { name: "Aptos", size: 10, color: text };
samples.getRange(`A2:AA${lastRow}`).format.rowHeight = 21;
samples.getRange(`A2:C${lastRow}`).format.fill = paleBlue;
samples.getRange(`N2:R${lastRow}`).format.fill = "#FFFCF3";
samples.getRange(`V2:AA${lastRow}`).format.fill = "#F7FAFC";
samples.getRange(`A2:AA${lastRow}`).format.borders = {
  insideHorizontal: { style: "thin", color: "#EDF1F5" },
  bottom: { style: "thin", color: border },
};
samples.getRange(`A2:C${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`I2:N${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`R2:AA${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`K2:K${lastRow}`).format.numberFormat = "0";
samples.getRange(`M2:M${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";
samples.getRange(`T2:T${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";
samples.getRange(`W2:W${lastRow}`).format.numberFormat = "0";
samples.getRange(`X2:X${lastRow}`).format.numberFormat = "0.0";
samples.getRange(`Y2:Y${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm:ss";

const widths = [25, 22, 22, 24, 24, 42, 42, 68, 25, 20, 11, 18, 22, 16, 28, 30, 34, 16, 17, 22, 24, 16, 14, 14, 22, 15, 14];
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

const samplesTable = samples.tables.add(`A1:AA${lastRow}`, true, "AllAudioTable");
samplesTable.style = "TableStyleMedium2";
samplesTable.showFilterButton = true;

summary.mergeCells("A1:H1");
summary.getRange("A1").values = [["AIV0 - CHỈ MỤC TOÀN BỘ AUDIO"]];
summary.getRange("A1:H1").format = {
  fill: navy,
  font: { name: "Aptos Display", size: 18, bold: true, color: "#FFFFFF" },
  verticalAlignment: "center",
};
summary.getRange("A1:H1").format.rowHeight = 42;
summary.getRange("A3:B8").values = [
  ["Chỉ số", "Giá trị"],
  ["Tổng audio", null],
  ["Tổng dung lượng (GB)", null],
  ["Số nhóm nguồn", null],
  ["Số batch kiểm thử", null],
  ["Batch tối đa", batchSize],
];
summary.getRange("B4").formulas = [[`=COUNTA('Samples'!A2:A${lastRow})`]];
summary.getRange("B5").formulas = [[`=SUM('Samples'!X2:X${lastRow})/1024/1024`]];
summary.getRange("B6").values = [[groupCounts.size]];
summary.getRange("B7").values = [[batchCounts.size]];
summary.getRange("B4:B8").format.numberFormat = "#,##0";
summary.getRange("B5").format.numberFormat = "0.000";
summary.getRange("A3:B3").format = { fill: teal, font: { bold: true, color: "#FFFFFF" } };
summary.getRange("A4:A8").format = { fill: paleTeal, font: { bold: true, color: teal } };
summary.getRange("A3:B8").format.borders = { preset: "outside", style: "thin", color: border };
summary.getRange("A3:A8").format.columnWidth = 28;
summary.getRange("B3:B8").format.columnWidth = 24;
summary.getRange("A3:B8").format.rowHeight = 26;

summary.getRange("D3:F3").values = [["Nhóm nguồn", "Số audio", "Khoảng chỉ số"]];
summary.getRange("D4:F6").values = [
  ["CV26-TEEN", groupCounts.get("CV26-TEEN") ?? 0, "001 - 003"],
  ["Set001", groupCounts.get("Set001") ?? 0, "000004 - 014122"],
  ["Set002", groupCounts.get("Set002") ?? 0, "000001 - 011799"],
];
summary.getRange("D3:F3").format = { fill: navy, font: { bold: true, color: "#FFFFFF" } };
summary.getRange("D4:F6").format = { fill: "#FFFFFF", font: { color: text } };
summary.getRange("D3:F6").format.borders = { preset: "outside", style: "thin", color: border };
summary.getRange("D3:D6").format.columnWidth = 20;
summary.getRange("E3:E6").format.columnWidth = 16;
summary.getRange("F3:F6").format.columnWidth = 24;
summary.getRange("E4:E6").format.numberFormat = "#,##0";

summary.mergeCells("A10:H10");
summary.getRange("A10").values = [["KIỂM TRA NGUỒN"]];
summary.getRange("A10:H10").format = { fill: paleAmber, font: { bold: true, color: "#8A5700" } };
summary.getRange("A11:B14").values = [
  ["Thư mục", audioDir],
  ["File 0 byte", zeroByteCount],
  ["Tổng dung lượng thực", `${(totalBytes / 1024 / 1024 / 1024).toFixed(3)} GB`],
  ["Cách liên kết", "Lưu đường dẫn cục bộ; không nhúng MP3 vào Excel"],
];
summary.getRange("A11:A14").format = { fill: paleBlue, font: { bold: true, color: navy } };
summary.getRange("A11:B14").format.borders = { preset: "outside", style: "thin", color: border };
summary.getRange("B11:B14").format.columnWidth = 88;
summary.getRange("A11:B14").format.rowHeight = 26;

instructions.mergeCells("A1:H1");
instructions.getRange("A1").values = [["HƯỚNG DẪN KIỂM THỬ 25.921 AUDIO"]];
instructions.getRange("A1:H1").format = { fill: navy, font: { size: 18, bold: true, color: "#FFFFFF" }, verticalAlignment: "center" };
instructions.getRange("A1:H1").format.rowHeight = 42;
instructions.mergeCells("A3:H3");
instructions.getRange("A3").values = [["QUY TRÌNH KHUYẾN NGHỊ"]];
instructions.getRange("A3:H3").format = { fill: teal, font: { bold: true, color: "#FFFFFF" } };
const steps = [
  "1. Mở workbook bằng AIV0-Batch-Audio-Reviewer-v0.2.exe.",
  "2. Chọn một batch_id trong bộ lọc trước khi đánh giá; mỗi batch có tối đa 500 audio.",
  "3. Chọn dòng để nghe từ local_audio_path. Không cần ghép lại thư mục 25.921 file.",
  "4. Với mẫu Không đạt: chọn loại lỗi, ghi kết quả thực tế và đề xuất sửa.",
  "5. Dùng Sửa hàng loạt cho các mẫu Không đạt có cùng error_categories.",
  "6. Khi có audio bản chính: giữ nguyên record_id, thay đường dẫn/file và tăng audio_version.",
  "7. Chỉ tính audio_hash khi cần đối chiếu nội dung; bản này để trống hash để xử lý thư mục lớn nhanh hơn.",
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
  instructions.getRange(`A${row}:H${row}`).format.rowHeight = 28;
}

instructions.mergeCells("A12:H12");
instructions.getRange("A12").values = [["NHÓM LỖI CÓ SẴN TRONG V0.2"]];
instructions.getRange("A12:H12").format = { fill: paleAmber, font: { bold: true, color: "#8A5700" } };
const errorCategories = [
  "Phát âm không chuẩn", "Giọng vùng miền", "Nghe không rõ", "Khó nghe", "Nói quá nhanh",
  "Nói quá nhỏ", "Tạp âm nền", "Âm thanh bị rè", "Mất đầu hoặc cuối câu",
  "Nội dung không đúng câu mẫu", "ASR nhận dạng sai", "Dịch sai nghĩa", "Không có kết quả",
  "File audio lỗi", "Khác",
];
const categoryRows = [];
for (let index = 0; index < errorCategories.length; index += 3) {
  categoryRows.push([errorCategories[index] ?? "", errorCategories[index + 1] ?? "", errorCategories[index + 2] ?? ""]);
}
instructions.getRange(`A13:C${12 + categoryRows.length}`).values = categoryRows;
instructions.getRange(`A13:C${12 + categoryRows.length}`).format = {
  fill: paleBlue,
  font: { bold: true, color: navy },
  wrapText: true,
  borders: { preset: "all", style: "thin", color: border },
};
instructions.getRange(`A13:C${12 + categoryRows.length}`).format.rowHeight = 30;
instructions.getRange("A1:A20").format.columnWidth = 34;
instructions.getRange("B1:B20").format.columnWidth = 34;
instructions.getRange("C1:C20").format.columnWidth = 34;

uploadLog.getRange("A1:F2").values = [
  ["timestamp", "record_id", "action", "old_value", "new_value", "detail"],
  [generatedAt, "ALL", "WORKBOOK_CREATED", "", `${rows.length} records`, "Linked local MP3 paths; content hash deferred"],
];
uploadLog.freezePanes.freezeRows(1);
uploadLog.getRange("A1:F1").format = { fill: navy, font: { bold: true, color: "#FFFFFF" }, horizontalAlignment: "center" };
uploadLog.getRange("A1:F1").format.rowHeight = 28;
uploadLog.getRange("A2:A2").format.numberFormat = "yyyy-mm-dd hh:mm";
const logWidths = [22, 20, 24, 22, 22, 58];
for (let column = 0; column < logWidths.length; column += 1) {
  uploadLog.getRangeByIndexes(0, column, 2, 1).format.columnWidth = logWidths[column];
}
uploadLog.tables.add("A1:F2", true, "AllAudioLogTable").style = "TableStyleMedium2";

await fs.mkdir(qaDir, { recursive: true });

const previews = [
  ["summary.png", { sheetName: "Summary", range: "A1:H14", scale: 1, format: "png" }],
  ["samples_ids.png", { sheetName: "Samples", range: "A1:H12", scale: 1, format: "png" }],
  ["samples_review.png", { sheetName: "Samples", range: "N1:AA12", scale: 1, format: "png" }],
  ["instructions.png", { sheetName: "Instructions", range: "A1:H17", scale: 1, format: "png" }],
  ["upload_log.png", { sheetName: "Upload Log", range: "A1:F3", scale: 1, format: "png" }],
];
for (const [filename, options] of previews) {
  const preview = await workbook.render(options);
  await fs.writeFile(path.join(qaDir, filename), new Uint8Array(await preview.arrayBuffer()));
}

const firstCheck = await workbook.inspect({ kind: "table", range: "Samples!A1:AA6", include: "values,formulas", tableMaxRows: 6, tableMaxCols: 27 });
const lastCheck = await workbook.inspect({ kind: "table", range: `Samples!A${lastRow - 4}:AA${lastRow}`, include: "values,formulas", tableMaxRows: 5, tableMaxCols: 27 });
const summaryCheck = await workbook.inspect({ kind: "table", range: "Summary!A1:H14", include: "values,formulas", tableMaxRows: 14, tableMaxCols: 8 });
const formulaErrors = await workbook.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, summary: "final formula error scan" });

await fs.mkdir(outputDir, { recursive: true });
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

console.log(JSON.stringify({
  outputPath,
  recordCount: rows.length,
  uniqueIds: ids.size,
  groupCounts: Object.fromEntries(groupCounts),
  batchCount: batchCounts.size,
  largestBatch: Math.max(...batchCounts.values()),
  zeroByteCount,
  totalGB: Number((totalBytes / 1024 / 1024 / 1024).toFixed(3)),
  firstFile: metadata[0].filename,
  lastFile: metadata[metadata.length - 1].filename,
}));
console.log(firstCheck.ndjson);
console.log(lastCheck.ndjson);
console.log(summaryCheck.ndjson);
console.log(formulaErrors.ndjson);

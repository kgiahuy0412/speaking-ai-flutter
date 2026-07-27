import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const inputPath = String.raw`C:\Users\Windows\Documents\ai-speaking-flutter-app\outputs\aiv0-ai-precheck\ai_precheck_results.json`;
const outputDir = String.raw`C:\Users\Windows\Documents\ai-speaking-flutter-app\outputs\aiv0-ai-precheck`;
const qaDir = path.join(outputDir, "qa");
const outputPath = path.join(outputDir, "AIV0_AI_PRECHECK_3_NHOM_MOI_60_AUDIO.xlsx");

const payload = JSON.parse(await fs.readFile(inputPath, "utf8"));
const records = payload.records;

const standardHeaders = [
  "record_id", "batch_id", "sentence_code", "source_vi", "expected_en",
  "draft_filename", "official_filename", "local_audio_path", "audio_id", "audio_hash",
  "audio_version", "upload_status", "uploaded_at", "test_result", "error_categories",
  "observed_result", "repair_suggestion", "repair_status", "reviewer", "reviewed_at", "note",
];
const extraHeaders = [
  "speaker_group", "gender", "age_years", "region", "question_number", "source_folder",
  "normalized_filename", "file_extension", "file_size_kb", "modified_at", "path_check",
  "ai_transcript", "ai_similarity", "ai_word_coverage", "ai_avg_logprob", "ai_no_speech_prob",
  "duration_sec", "rms_dbfs", "peak_dbfs", "clipping_ratio", "silence_ratio", "sample_rate_hz",
  "channels", "decode_ok",
];
const headers = [...standardHeaders, ...extraHeaders];

const rows = records.map((record) => headers.map((header) => {
  if (["uploaded_at", "reviewed_at", "modified_at"].includes(header) && record[header]) {
    return new Date(record[header]);
  }
  return record[header] ?? "";
}));

const workbook = Workbook.create();
const samples = workbook.worksheets.add("Samples");
const summary = workbook.worksheets.add("Summary");
const sentenceGuide = workbook.worksheets.add("Sentence Guide");
const uploadLog = workbook.worksheets.add("Upload Log");
const instructions = workbook.worksheets.add("Instructions");

const navy = "#17324D";
const teal = "#147D75";
const paleBlue = "#EAF2F8";
const paleTeal = "#E5F4F1";
const paleAmber = "#FFF3D6";
const paleGreen = "#E8F5ED";
const paleRed = "#FDECEC";
const border = "#D6DEE7";
const text = "#243447";

for (const sheet of [samples, summary, sentenceGuide, uploadLog, instructions]) sheet.showGridLines = false;

const lastRow = rows.length + 1;
samples.getRange(`A1:AS${lastRow}`).values = [headers, ...rows];
samples.freezePanes.freezeRows(1);
samples.freezePanes.freezeColumns(3);
samples.getRange("A1:AS1").format = {
  fill: navy,
  font: { name: "Aptos", size: 10, bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  wrapText: true,
};
samples.getRange("A1:AS1").format.rowHeight = 36;
samples.getRange(`A2:AS${lastRow}`).format.font = { name: "Aptos", size: 10, color: text };
samples.getRange(`A2:AS${lastRow}`).format.rowHeight = 32;
samples.getRange(`A2:C${lastRow}`).format.fill = paleBlue;
samples.getRange(`N2:R${lastRow}`).format.fill = "#FFFCF3";
samples.getRange(`V2:AF${lastRow}`).format.fill = "#F7FAFC";
samples.getRange(`AG2:AS${lastRow}`).format.fill = "#F1F7F6";
samples.getRange(`A2:AS${lastRow}`).format.borders = {
  insideHorizontal: { style: "thin", color: "#EDF1F5" },
  bottom: { style: "thin", color: border },
};
samples.getRange(`D2:D${lastRow}`).format.wrapText = true;
samples.getRange(`O2:Q${lastRow}`).format.wrapText = true;
samples.getRange(`U2:U${lastRow}`).format.wrapText = true;
samples.getRange(`AG2:AG${lastRow}`).format.wrapText = true;
samples.getRange(`A2:C${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`I2:N${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`R2:AS${lastRow}`).format.horizontalAlignment = "center";
samples.getRange(`K2:K${lastRow}`).format.numberFormat = "0";
samples.getRange(`M2:M${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";
samples.getRange(`T2:T${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";
samples.getRange(`X2:X${lastRow}`).format.numberFormat = "0";
samples.getRange(`Z2:Z${lastRow}`).format.numberFormat = "0";
samples.getRange(`AD2:AD${lastRow}`).format.numberFormat = "0.0";
samples.getRange(`AE2:AE${lastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm:ss";
samples.getRange(`AH2:AI${lastRow}`).format.numberFormat = "0.0%";
samples.getRange(`AJ2:AK${lastRow}`).format.numberFormat = "0.000";
samples.getRange(`AL2:AN${lastRow}`).format.numberFormat = "0.00";
samples.getRange(`AO2:AP${lastRow}`).format.numberFormat = "0.00%";
samples.getRange(`AQ2:AR${lastRow}`).format.numberFormat = "#,##0";

const widths = [24, 22, 14, 42, 12, 20, 20, 70, 25, 64, 11, 18, 22, 16, 30, 52, 48, 16, 34, 22, 58, 28, 12, 10, 14, 14, 46, 22, 12, 14, 22, 16, 48, 14, 16, 16, 16, 14, 14, 14, 14, 14, 16, 12, 12];
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

const samplesTable = samples.tables.add(`A1:AS${lastRow}`, true, "AiPrecheckTable");
samplesTable.style = "TableStyleMedium2";
samplesTable.showFilterButton = true;

summary.mergeCells("A1:I1");
summary.getRange("A1").values = [["AIV0 - KẾT QUẢ AI PRECHECK ĐỘC LẬP"]];
summary.getRange("A1:I1").format = {
  fill: navy,
  font: { name: "Aptos Display", size: 18, bold: true, color: "#FFFFFF" },
  verticalAlignment: "center",
};
summary.getRange("A1:I1").format.rowHeight = 42;
summary.getRange("A3:B9").values = [
  ["Chỉ số", "Giá trị"],
  ["Tổng audio", null],
  ["AI đánh giá Đạt", null],
  ["AI yêu cầu kiểm thử lại", null],
  ["AI đánh giá Không đạt", null],
  ["Mô hình", payload.model],
  ["Chính sách chấm", payload.scoring_policy ?? "conservative-ai-precheck-v2"],
];
summary.getRange("B4").formulas = [[`=COUNTA('Samples'!A2:A${lastRow})`]];
summary.getRange("B5").formulas = [[`=COUNTIF('Samples'!N2:N${lastRow},"Đạt")`]];
summary.getRange("B6").formulas = [[`=COUNTIF('Samples'!N2:N${lastRow},"Kiểm thử lại")`]];
summary.getRange("B7").formulas = [[`=COUNTIF('Samples'!N2:N${lastRow},"Không đạt")`]];
summary.getRange("B4:B7").format.numberFormat = "#,##0";
summary.getRange("A3:B3").format = { fill: teal, font: { bold: true, color: "#FFFFFF" } };
summary.getRange("A4:A9").format = { fill: paleTeal, font: { bold: true, color: teal } };
summary.getRange("A3:B9").format.borders = { preset: "all", style: "thin", color: border };
summary.getRange("A3:A9").format.columnWidth = 30;
summary.getRange("B3:B9").format.columnWidth = 34;
summary.getRange("A3:B9").format.rowHeight = 27;

const groupRows = [
  ["Nữ 14 tuổi - Miền Nam", "AIV0-F14-SOUTH"],
  ["Nam 4 tuổi - Miền Bắc", "AIV0-M04-NORTH"],
  ["Nữ 4 tuổi - Miền Nam", "AIV0-F04-SOUTH"],
];
summary.getRange("D3:I3").values = [["Nhóm giọng", "Batch ID", "Tổng", "Đạt", "Kiểm thử lại", "Không đạt"]];
summary.getRange("D4:E6").values = groupRows;
for (let index = 0; index < groupRows.length; index += 1) {
  const row = 4 + index;
  summary.getRange(`F${row}`).formulas = [[`=COUNTIF('Samples'!B2:B${lastRow},E${row})`]];
  summary.getRange(`G${row}`).formulas = [[`=COUNTIFS('Samples'!B2:B${lastRow},E${row},'Samples'!N2:N${lastRow},"Đạt")`]];
  summary.getRange(`H${row}`).formulas = [[`=COUNTIFS('Samples'!B2:B${lastRow},E${row},'Samples'!N2:N${lastRow},"Kiểm thử lại")`]];
  summary.getRange(`I${row}`).formulas = [[`=COUNTIFS('Samples'!B2:B${lastRow},E${row},'Samples'!N2:N${lastRow},"Không đạt")`]];
}
summary.getRange("D3:I3").format = { fill: navy, font: { bold: true, color: "#FFFFFF" } };
summary.getRange("D4:I6").format = { fill: "#FFFFFF", font: { color: text } };
summary.getRange("D3:I6").format.borders = { preset: "all", style: "thin", color: border };
summary.getRange("D3:D6").format.columnWidth = 28;
summary.getRange("E3:E6").format.columnWidth = 23;
summary.getRange("F3:I6").format.columnWidth = 16;
summary.getRange("F4:I6").format.numberFormat = "#,##0";

summary.mergeCells("A11:I11");
summary.getRange("A11").values = [["LƯU Ý QUAN TRỌNG"]];
summary.getRange("A11:I11").format = { fill: paleAmber, font: { bold: true, color: "#8A5700" } };
summary.mergeCells("A12:I12");
summary.getRange("A12").values = [["Đây là kết quả AI sơ bộ. Hãy nghe xác nhận từng dòng, đặc biệt các mẫu Kiểm thử lại; không xóa audio chỉ dựa trên điểm AI."]];
summary.getRange("A12:I12").format = { wrapText: true, font: { color: text }, fill: "#FFFFFF" };
summary.getRange("A12:I12").format.rowHeight = 40;

const guideRows = payload.guide.map((item) => [
  item.sentence_code,
  item.sentence_code === "Q002" ? "Con [tuổi thực tế] tuổi." : item.source_vi,
  item.method,
  item.evaluation_note,
]);
sentenceGuide.getRange("A1:D21").values = [["sentence_code", "Câu hỏi / câu trẻ nói", "Cách thực hiện", "Ghi chú đánh giá"], ...guideRows];
sentenceGuide.freezePanes.freezeRows(1);
sentenceGuide.getRange("A1:D1").format = { fill: navy, font: { bold: true, color: "#FFFFFF" }, horizontalAlignment: "center", wrapText: true };
sentenceGuide.getRange("A1:D1").format.rowHeight = 34;
sentenceGuide.getRange("A2:A21").format = { fill: paleBlue, font: { bold: true, color: navy }, horizontalAlignment: "center" };
sentenceGuide.getRange("B2:D21").format = { wrapText: true, font: { color: text }, verticalAlignment: "center" };
sentenceGuide.getRange("A2:D21").format.borders = { insideHorizontal: { style: "thin", color: "#E1E7EE" }, bottom: { style: "thin", color: border } };
sentenceGuide.getRange("A1:A21").format.columnWidth = 16;
sentenceGuide.getRange("B1:B21").format.columnWidth = 48;
sentenceGuide.getRange("C1:C21").format.columnWidth = 38;
sentenceGuide.getRange("D1:D21").format.columnWidth = 62;
sentenceGuide.getRange("A2:D21").format.rowHeight = 36;
sentenceGuide.tables.add("A1:D21", true, "AiSentenceGuideTable").style = "TableStyleMedium2";

const logRows = records.map((record) => [
  new Date(record.reviewed_at),
  record.record_id,
  "AI_PRECHECK",
  "Chưa kiểm thử",
  record.test_result,
  `transcript=${record.ai_transcript}; similarity=${Math.round(record.ai_similarity * 100)}%; categories=${record.error_categories}`,
]);
uploadLog.getRange(`A1:F${logRows.length + 1}`).values = [
  ["timestamp", "record_id", "action", "old_value", "new_value", "detail"],
  ...logRows,
];
uploadLog.freezePanes.freezeRows(1);
uploadLog.getRange("A1:F1").format = { fill: navy, font: { bold: true, color: "#FFFFFF" }, horizontalAlignment: "center" };
uploadLog.getRange("A1:F1").format.rowHeight = 28;
uploadLog.getRange(`A2:A${logRows.length + 1}`).format.numberFormat = "yyyy-mm-dd hh:mm";
const logWidths = [22, 24, 20, 18, 18, 88];
for (let column = 0; column < logWidths.length; column += 1) {
  uploadLog.getRangeByIndexes(0, column, logRows.length + 1, 1).format.columnWidth = logWidths[column];
}
uploadLog.tables.add(`A1:F${logRows.length + 1}`, true, "AiPrecheckLogTable").style = "TableStyleMedium2";

instructions.getRange("A1:A8").values = [
  ["AIV0 AI Precheck - Hướng dẫn kiểm thử lại"],
  ["1. Mở sheet Samples hoặc mở workbook bằng V0.2."],
  ["2. Lọc test_result = Kiểm thử lại trước và nghe xác nhận từng audio."],
  ["3. observed_result chứa bản chép lời, điểm khớp, độ tin cậy, thời lượng và âm lượng."],
  ["4. Đạt chỉ được AI gán khi câu khớp rất rõ; kết quả vẫn cần người kiểm thử xác nhận."],
  ["5. Không đạt thường là nội dung lệch mạnh hoặc AI không nhận dạng được câu."],
  ["6. Không coi khác biệt giọng miền Nam/Miền Bắc là lỗi."],
  ["7. Không xóa audio trước khi người kiểm thử hoàn tất xác nhận."],
];
instructions.getRange("A1").format = { fill: navy, font: { size: 16, bold: true, color: "#FFFFFF" } };
instructions.getRange("A2:A8").format = { wrapText: true, font: { color: text } };
instructions.getRange("A1:A8").format.columnWidth = 110;
instructions.getRange("A1").format.rowHeight = 36;
instructions.getRange("A2:A8").format.rowHeight = 26;

await fs.mkdir(qaDir, { recursive: true });
const previews = [
  ["summary.png", { sheetName: "Summary", range: "A1:I12", scale: 1, format: "png" }],
  ["samples_main.png", { sheetName: "Samples", range: "A1:U12", scale: 1, format: "png" }],
  ["samples_ai.png", { sheetName: "Samples", range: "N1:AS12", scale: 1, format: "png" }],
  ["guide.png", { sheetName: "Sentence Guide", range: "A1:D21", scale: 1, format: "png" }],
  ["log.png", { sheetName: "Upload Log", range: "A1:F10", scale: 1, format: "png" }],
  ["instructions.png", { sheetName: "Instructions", range: "A1:A8", scale: 1, format: "png" }],
];
for (const [filename, options] of previews) {
  const preview = await workbook.render(options);
  await fs.writeFile(path.join(qaDir, filename), new Uint8Array(await preview.arrayBuffer()));
}

const sampleCheck = await workbook.inspect({ kind: "table", range: "Samples!A1:AS8", include: "values,formulas", tableMaxRows: 8, tableMaxCols: 45 });
const summaryCheck = await workbook.inspect({ kind: "table", range: "Summary!A1:I12", include: "values,formulas", tableMaxRows: 12, tableMaxCols: 9 });
const formulaErrors = await workbook.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, summary: "final formula error scan" });

await fs.mkdir(outputDir, { recursive: true });
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

console.log(JSON.stringify({ outputPath, records: records.length, summary: payload.summary, model: payload.model }));
console.log(sampleCheck.ndjson);
console.log(summaryCheck.ndjson);
console.log(formulaErrors.ndjson);

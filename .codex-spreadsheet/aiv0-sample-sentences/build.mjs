import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = String.raw`C:\Users\Windows\Documents\DOCUMENTS DỰ ÁN SPEAKING AI\ÂM THANH SPEAKING AI\AIV0_3_NHOM_60_AUDIO_REVIEW_updated.xlsx`;
const outputDir = String.raw`C:\Users\Windows\Documents\ai-speaking-flutter-app\outputs\aiv0-sample-sentences`;
const qaDir = path.join(outputDir, "qa");
const outputPath = path.join(outputDir, "AIV0_3_NHOM_60_AUDIO_REVIEW_with_samples.xlsx");
const mode = process.argv[2] ?? "build";

const guide = [
  ["Q001", "Con tên là Bé Mây.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q002", "Con 4 tuổi.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q003", "Hôm nay con rất vui.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q004", "Con muốn uống nước.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q005", "Con thích màu đỏ.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q006", "Con thích ăn cơm.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q007", "Con muốn chơi với bạn.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q008", "Con không hiểu.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q009", "Cô/chú nói chậm lại nhé.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q010", "Con muốn nghe lại.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q011", "Ở nhà, con gọi ba của con là gì?", "Phụ huynh hỏi; trẻ trả lời tự nhiên", "Chấp nhận ba/bố hoặc cách gọi quen thuộc; không sửa giọng địa phương"],
  ["Q012", "Ở chỗ con, mọi người hay nói ngô hay bắp?", "Phụ huynh hỏi; trẻ trả lời tự nhiên", "Chấp nhận ngô/bắp hoặc cách gọi quen thuộc; không sửa giọng địa phương"],
  ["Q013", "Con thấy con mèo.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q014", "Con có một quả bóng.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q015", "Con muốn đi chơi.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q016", "Mẹ ơi, con cần giúp.", "Nói theo câu mẫu", "Đối chiếu nội dung và độ rõ"],
  ["Q017", "Con muốn uống nước.", "Bật quạt mức vừa", "Đánh giá độ rõ khi có tiếng quạt nền"],
  ["Q018", "Con không hiểu.", "Bật TV nhỏ", "Đánh giá độ rõ khi có tiếng TV nền"],
  ["Q019", "Cô/chú nói chậm lại nhé.", "Người lớn nói từ khoảng cách xa hơn", "Đánh giá khả năng nghe và phản hồi"],
  ["Q020", "Con muốn chơi với bạn.", "Lật sách hoặc đi lại nhẹ", "Đánh giá độ rõ khi có tiếng động nhẹ"],
];

await fs.mkdir(qaDir, { recursive: true });
const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);

if (mode === "inspect") {
  const existing = await workbook.inspect({
    kind: "workbook,sheet,table",
    maxChars: 5000,
    tableMaxRows: 5,
    tableMaxCols: 8,
  });
  const preview = await workbook.render({ sheetName: "Samples", range: "A1:U12", scale: 1, format: "png" });
  await fs.writeFile(path.join(qaDir, "before_samples.png"), new Uint8Array(await preview.arrayBuffer()));
  console.log(existing.ndjson);
  process.exit(0);
}

const samples = workbook.worksheets.getItem("Samples");
const sampleRows = samples.getRange("A2:AF61").values;
const guideByCode = new Map(guide.map((row) => [row[0], row]));
const sourceValues = [];
const noteValues = [];
const statusBefore = new Map();

for (const row of sampleRows) {
  const code = String(row[2] ?? "").trim();
  const item = guideByCode.get(code);
  if (!item) throw new Error(`Không tìm thấy câu mẫu cho ${code}.`);
  const existingNote = String(row[20] ?? "").trim();
  const guideNote = `Cách thực hiện: ${item[2]}. Ghi chú: ${item[3]}.`;
  sourceValues.push([item[1]]);
  noteValues.push([existingNote ? `${existingNote} | ${guideNote}` : guideNote]);
  const status = String(row[13] ?? "").trim();
  statusBefore.set(status, (statusBefore.get(status) ?? 0) + 1);
}

samples.getRange("D2:D61").values = sourceValues;
samples.getRange("U2:U61").values = noteValues;
samples.getRange("D2:D61").format.wrapText = true;
samples.getRange("U2:U61").format.wrapText = true;
samples.getRange("D1:D61").format.columnWidth = 44;
samples.getRange("U1:U61").format.columnWidth = 58;
samples.getRange("A2:AF61").format.rowHeight = 34;

const sentenceGuide = workbook.worksheets.add("Sentence Guide");
sentenceGuide.showGridLines = false;
sentenceGuide.getRange("A1:D21").values = [
  ["sentence_code", "Câu hỏi / câu trẻ nói", "Cách thực hiện", "Ghi chú đánh giá"],
  ...guide,
];
sentenceGuide.freezePanes.freezeRows(1);
sentenceGuide.getRange("A1:D1").format = {
  fill: "#17324D",
  font: { name: "Aptos", size: 11, bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  wrapText: true,
};
sentenceGuide.getRange("A1:D1").format.rowHeight = 34;
sentenceGuide.getRange("A2:A21").format = {
  fill: "#EAF2F8",
  font: { bold: true, color: "#17324D" },
  horizontalAlignment: "center",
};
sentenceGuide.getRange("B2:D21").format = {
  font: { color: "#243447" },
  wrapText: true,
  verticalAlignment: "center",
};
sentenceGuide.getRange("A2:D21").format.borders = {
  insideHorizontal: { style: "thin", color: "#E1E7EE" },
  bottom: { style: "thin", color: "#D6DEE7" },
};
sentenceGuide.getRange("A1:A21").format.columnWidth = 16;
sentenceGuide.getRange("B1:B21").format.columnWidth = 48;
sentenceGuide.getRange("C1:C21").format.columnWidth = 38;
sentenceGuide.getRange("D1:D21").format.columnWidth = 62;
sentenceGuide.getRange("A2:D21").format.rowHeight = 36;
const guideTable = sentenceGuide.tables.add("A1:D21", true, "SentenceGuideTable");
guideTable.style = "TableStyleMedium2";
guideTable.showFilterButton = true;

const uploadLog = workbook.worksheets.getItem("Upload Log");
const logValues = uploadLog.getUsedRange(true).values;
const logAppendRow = logValues.length + 1;
uploadLog.getRange(`A${logAppendRow}:F${logAppendRow}`).values = [[
  new Date(),
  "ALL",
  "SAMPLE_TEXT_ADDED",
  "source_vi empty",
  "Q001-Q020 populated",
  "Added 20 reference sentences and test conditions",
]];
uploadLog.getRange(`A${logAppendRow}:A${logAppendRow}`).format.numberFormat = "yyyy-mm-dd hh:mm";

const previews = [
  ["after_samples.png", { sheetName: "Samples", range: "A1:U12", scale: 1, format: "png" }],
  ["after_instructions.png", { sheetName: "Instructions", range: "A1:H16", scale: 1, format: "png" }],
  ["after_log.png", { sheetName: "Upload Log", range: "A58:F65", scale: 1, format: "png" }],
  ["after_guide.png", { sheetName: "Sentence Guide", range: "A1:D21", scale: 1, format: "png" }],
];
for (const [filename, options] of previews) {
  const preview = await workbook.render(options);
  await fs.writeFile(path.join(qaDir, filename), new Uint8Array(await preview.arrayBuffer()));
}

const sampleCheck = await workbook.inspect({
  kind: "table",
  range: "Samples!A1:U14",
  include: "values,formulas",
  tableMaxRows: 14,
  tableMaxCols: 21,
});
const guideCheck = await workbook.inspect({
  kind: "table",
  range: "Sentence Guide!A1:D21",
  include: "values,formulas",
  tableMaxRows: 21,
  tableMaxCols: 4,
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
  recordsUpdated: sampleRows.length,
  guideRows: guide.length,
  statusBefore: Object.fromEntries(statusBefore),
}));
console.log(sampleCheck.ndjson);
console.log(guideCheck.ndjson);
console.log(formulaErrors.ndjson);

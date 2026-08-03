import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = "C:/Users/Windows/Downloads/tong_hop_check_am_thanh_cloudflare.xlsx";
const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);
const sheet = workbook.worksheets.getItem("Tổng hợp");
const values = sheet.getUsedRange(true).values;
const headers = values[0].map(String);
const col = Object.fromEntries(headers.map((h, i) => [h, i]));
const rows = values.slice(1).map((row, index) => ({
  excelRow: index + 2,
  row,
  get(name) { return row[col[name]]; },
}));

const text = (v) => (v == null ? "" : String(v).trim());
const number = (v) => (typeof v === "number" ? v : Number(v));
const dialect = (name) => {
  const v = text(name).toUpperCase();
  if (v.includes("MIEN-BAC")) return "Miền Bắc";
  if (v.includes("MIEN-TRUNG")) return "Miền Trung";
  if (v.includes("MIEN-NAM")) return "Miền Nam";
  return "Không rõ";
};
const quantile = (numbers, q) => {
  const a = numbers.filter(Number.isFinite).sort((x, y) => x - y);
  if (!a.length) return null;
  const pos = (a.length - 1) * q;
  const base = Math.floor(pos);
  const rest = pos - base;
  return Math.round(a[base] + (a[base + 1] == null ? 0 : rest * (a[base + 1] - a[base])));
};
const stats = (group) => {
  const total = group.length;
  const errors = group.filter((r) => text(r.get("Đánh giá")).toLowerCase() !== "đúng").length;
  const asr = group.map((r) => number(r.get("ASR (ms)")));
  const latency = group.map((r) => number(r.get("Tổng thời gian (ms)")));
  return {
    total,
    correct: total - errors,
    errors,
    errorRatePct: total ? Number((errors * 100 / total).toFixed(1)) : null,
    asrP50Ms: quantile(asr, 0.5),
    asrP95Ms: quantile(asr, 0.95),
    totalP50Ms: quantile(latency, 0.5),
    totalP95Ms: quantile(latency, 0.95),
    totalMaxMs: latency.filter(Number.isFinite).length ? Math.max(...latency.filter(Number.isFinite)) : null,
  };
};
const groupBy = (keyFn) => {
  const map = new Map();
  for (const r of rows) {
    const key = keyFn(r);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(r);
  }
  return Object.fromEntries([...map].map(([k, group]) => [k, stats(group)]));
};
const countBy = (keyFn) => {
  const out = {};
  for (const r of rows) {
    const key = keyFn(r) || "(trống)";
    out[key] = (out[key] || 0) + 1;
  }
  return Object.fromEntries(Object.entries(out).sort((a, b) => b[1] - a[1]));
};

const hallucinationPatterns = [
  /subscribe|đăng ký|kênh|video|cảm ơn các bạn|hẹn gặp lại/i,
  /phụ đề|amara|lalaschool/i,
];
const suspicious = rows.filter((r) => hallucinationPatterns.some((p) => p.test(text(r.get("Tiếng Việt nhận diện")))));
const errorRows = rows.filter((r) => text(r.get("Đánh giá")).toLowerCase() !== "đúng");

const result = {
  workbook: { sheet: "Tổng hợp", range: "A1:P561", dataRows: rows.length },
  overall: stats(rows),
  byDialect: groupBy((r) => dialect(r.get("Tên file"))),
  bySourceFile: groupBy((r) => text(r.get("File nguồn"))),
  byEvaluation: countBy((r) => text(r.get("Đánh giá"))),
  byErrorType: Object.fromEntries(
    Object.entries(countBy((r) => text(r.get("Loại lỗi")))).filter(([k]) => k !== "(trống)"),
  ),
  byProcessingStatus: countBy((r) => text(r.get("Trạng thái xử lý"))),
  byMode: countBy((r) => text(r.get("Chế độ"))),
  byModeStats: groupBy((r) => text(r.get("Chế độ")) || "(trống)"),
  byExtension: groupBy((r) => {
    const name = text(r.get("Tên file")).toLowerCase();
    return name.includes(".") ? `.${name.split(".").pop()}` : "(không rõ)";
  }),
  byChunkCount: countBy((r) => text(r.get("Số chunks"))),
  technicalErrors: Object.fromEntries(
    Object.entries(countBy((r) => text(r.get("Lỗi kỹ thuật")))).filter(([k]) => k !== "(trống)"),
  ),
  suspiciousTranscriptCount: suspicious.length,
  suspiciousRatePct: Number((suspicious.length * 100 / rows.length).toFixed(1)),
  suspiciousByDialect: Object.fromEntries(
    [...new Set(rows.map((r) => dialect(r.get("Tên file"))))].map((name) => [
      name,
      suspicious.filter((r) => dialect(r.get("Tên file")) === name).length,
    ]),
  ),
  suspiciousTranscripts: suspicious.slice(0, 30).map((r) => ({
    row: r.excelRow,
    dialect: dialect(r.get("Tên file")),
    file: r.get("Tên file"),
    evaluation: r.get("Đánh giá"),
    errorType: r.get("Loại lỗi"),
    vi: r.get("Tiếng Việt nhận diện"),
    en: r.get("Tiếng Anh"),
    asrMs: r.get("ASR (ms)"),
    totalMs: r.get("Tổng thời gian (ms)"),
    conversationId: r.get("Conversation ID"),
  })),
  errorRows: errorRows.slice(0, 200).map((r) => ({
    row: r.excelRow,
    source: r.get("File nguồn"),
    dialect: dialect(r.get("Tên file")),
    file: r.get("Tên file"),
    evaluation: r.get("Đánh giá"),
    errorType: r.get("Loại lỗi"),
    status: r.get("Trạng thái xử lý"),
    vi: r.get("Tiếng Việt nhận diện"),
    en: r.get("Tiếng Anh"),
    asrMs: r.get("ASR (ms)"),
    totalMs: r.get("Tổng thời gian (ms)"),
    chunks: r.get("Số chunks"),
    bytes: r.get("Dung lượng (byte)"),
    technicalError: r.get("Lỗi kỹ thuật"),
    conversationId: r.get("Conversation ID"),
  })),
};

if (process.env.SUMMARY_ONLY === "1") {
  const { suspiciousTranscripts, errorRows, ...summary } = result;
  process.stdout.write(JSON.stringify(summary, null, 2));
} else {
  process.stdout.write(JSON.stringify(result, null, 2));
}

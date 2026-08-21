import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const input = await FileBlob.load(
  "C:/Users/Windows/Documents/ai-speaking-flutter-app/outputs/assistant_prompt_inventory_20260821/Danh_muc_cau_thoai_tro_ly_AI_va_fallback.xlsx",
);
const workbook = await SpreadsheetFile.importXlsx(input);

const overview = await workbook.inspect({
  kind: "region",
  sheetId: "Tổng quan",
  range: "A1:H24",
  include: "values,formulas",
  tableMaxRows: 30,
  tableMaxCols: 10,
  maxChars: 12000,
});
console.log(overview.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
});
console.log(errors.ndjson);


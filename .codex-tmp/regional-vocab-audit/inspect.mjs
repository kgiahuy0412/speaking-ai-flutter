import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const path = "C:/Users/Windows/Downloads/tu-vung-toan-dan-co-bien-the-3-mien-mo-rong.xlsx";
const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(path));

const overview = await workbook.inspect({
  kind: "workbook,sheet,table,region",
  maxChars: 12000,
  tableMaxRows: 8,
  tableMaxCols: 16,
  tableMaxCellChars: 160,
});

console.log(overview.ndjson);

for (let index = 0; ; index += 1) {
  let sheet;
  try {
    sheet = workbook.worksheets.getItemAt(index);
  } catch {
    break;
  }
  const used = sheet.getUsedRange(true);
  if (!used) continue;
  const values = used.values;
  const nonEmptyRows = values.filter((row) => row.some((value) => value !== null && value !== ""));
  console.log(JSON.stringify({
    kind: "sheet-summary",
    name: sheet.name,
    rows: values.length,
    columns: Math.max(0, ...values.map((row) => row.length)),
    nonEmptyRows: nonEmptyRows.length,
    headers: values[0] ?? [],
    sampleRows: values.slice(1, 7),
  }));
}

import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = "C:/Users/Windows/Downloads/tong_hop_check_am_thanh_cloudflare.xlsx";
const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);

const summary = await workbook.inspect({
  kind: "workbook,sheet,table,region",
  maxChars: 30000,
  tableMaxRows: 20,
  tableMaxCols: 20,
  tableMaxCellChars: 240,
});
process.stdout.write(summary.ndjson);

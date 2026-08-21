# HOMI App iOS report - Simplified Chinese translation contract

## Reference

- User source: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\documents\Bao_cao_HOMI_App_iOS_App_Store_2026-08-21.docx`
- Read-only snapshot (same 1,955,594-byte content, taken because the source is open in Word): `C:\Users\Windows\Documents\ai-speaking-flutter-app\tmp\documents\homi_zh_20260821\reference_snapshot.docx`
- Snapshot SHA-256: `180EB5D63E9CAC7E223267403F990A755093CA8C494EA3DEFAE88F4F3EFEB328`
- Page count: 6 pages when exported by Microsoft Word.
- Section count: 1.
- Evidence: `reference_render/page-1.png` through `page-6.png`, `reference_style_evidence.json`, `reference_text.json`, and `reference_package_inventory.json`.

## Page system

- US Letter portrait, 8.5 x 11 inches.
- Margins: 1 inch on all sides; usable width 9,360 DXA.
- Header and footer distance: 0.4917 inch.
- Single section, no first-page/even-page variants.
- Source pagination pattern: title and summary on page 1; completed work on page 2; Apple account decision on page 3; child/AI policy risk across pages 4-5; approval matrix on page 6.

## Typography and recurring components

- Normal: Calibri, dark navy `#182230`, 1.1 line spacing, 6 pt after.
- Heading 1: 16 pt, bold, blue `#2E74B5`, 16 pt before and 8 pt after.
- Heading 2: 13 pt, bold, blue `#2E74B5`, 12 pt before.
- Retain source title sizing, uppercase treatment, icon, callout fills/borders, warning colors, and table styling exactly.
- Header: `HOMI APP | iOS release report`; footer: localized page-number prefix plus the existing PAGE field.
- Use Microsoft YaHei as the East Asian fallback for Simplified Chinese without changing Latin typography.

## Lists and tables

- Preserve every source numbering/bullet definition and list indent; translate only visible text nodes.
- Preserve all 8 tables and their geometry. Key grids: 1,800/3,720/3,840 DXA for the Apple account comparison and 700/3,900/2,900/1,860 DXA for the approval matrix.
- Preserve cell margins, borders, fills, repeating behavior, status colors, and vertical alignment.

## Editable slot map

- `word/document.xml`: translate every Vietnamese title, heading, paragraph, bullet, callout, label, and table cell into professional Simplified Chinese. Preserve names, dates, product names, Apple/Codemagic terms, identifiers, and code-like strings when translation would change meaning.
- `word/header1.xml`: translate the report descriptor only; preserve `HOMI APP` and punctuation.
- `word/footer1.xml`: translate the page prefix only; preserve the PAGE field and number formatting.
- `word/styles.xml`: only the Normal-style East Asian font fallback may change from Calibri to Microsoft YaHei.
- Preserve the HOMI icon, relationships, content types, numbering, section settings, drawing anchors, and all other package parts byte-for-byte.

## Content flow and translation rules

- Keep the same five numbered sections and the same order, emphasis, risk framing, legal caveat, and decision deadlines.
- Translate `Individual` and `Organization` contextually as `个人` and `组织`, while retaining Apple product names, TestFlight, App Review, Bundle ID, Kids Category, Privacy Policy, Terms, Support, and technical identifiers where needed for operational clarity.
- Use Simplified Chinese punctuation and terminology; do not introduce new facts or advice.
- Keep `Gia Huy Trần Nguyễn`, `HOMI App`, `com.innotrik.aispeaking`, `com.homiapp.aispeaking`, and `homi_app_store_connect` unchanged.

## Package preservation and fidelity gates

- Baseline package inventory contains 20 parts in `reference_package_inventory.json`.
- Intended modified parts: `word/document.xml`, `word/header1.xml`, `word/footer1.xml`, and optionally the single Normal-font declaration in `word/styles.xml`.
- All other package parts and relationships must match the baseline SHA-256 exactly.
- Final geometry must remain one Letter portrait section with 1-inch margins and the same 8 table grids.
- Render the final DOCX through Microsoft Word, rasterize every page to PNG, and inspect all pages at 100% for missing Chinese glyphs, clipping, overlap, table overflow, orphaned headings, and broken header/footer fields.
- The original source and the snapshot must retain their recorded bytes and SHA-256.

# Template execution contract — V1 implementation plan

- Reference: `C:\Users\Windows\Downloads\Ke_hoach_trien_khai_V1_3_tuan_da_chinh_sua.docx`
- SHA-256: `1F39E7E2B6A39A1F714F8A247815204D732CC5D6F5A0033873448FC7630ED116`
- Size: 1,419,322 bytes
- Page count: unresolved because LibreOffice/soffice is unavailable; Word/PDF render will be attempted after translation.
- Sections: 1; US Letter portrait (8.5 x 11 in); margins 1 in on all sides; different first page enabled.
- Evidence: `style-evidence.json`, section/style/heading/image/field audit output, and package inventory from `inspect_doc.py`.

## Typography and components

- Source document is the visual authority. Preserve its Normal, Heading 1, Heading 2, title, metadata, callout, list and caption formatting in place.
- Direct formatting is intentional in callout labels, metadata labels, example labels, bold budget values and the final approval callout.
- Header: `KẾ HOẠCH TRIỂN KHAI V1\tFlutter Android + Next.js`; translate only the Vietnamese text and retain the tab stop.
- Footer: PAGE field plus surrounding page label; translate the label and preserve the PAGE field.
- One inline image (`word/media/image1.png`, approximately 6.35 x 4.76 in) and its drawing relationship must remain unchanged.
- One cost table with three columns and five rows; translate cell text in place and preserve the source table geometry, borders, fills and row behavior.
- No TOC. One PAGE field in `word/footer1.xml` must remain a live field.

## Editable slot map

- Translate every non-empty body paragraph in `word/document.xml` from Vietnamese to Simplified Chinese.
- Preserve English examples, model IDs, file formats, acronyms, product names, code-like identifiers and numeric values unless Chinese explanatory text surrounds them.
- Translate all table cells in the single cost table.
- Translate the Vietnamese header/footer labels without altering the tab or PAGE field.
- Preserve blank paragraphs, paragraph ordering, styles, numbering text, bookmarks, relationships, images, footnotes/endnotes parts and all section geometry.
- Multi-run paragraphs must keep their original run count and emphasis roles. For headings split across numeric runs, preserve the number runs and translate only the descriptive run.

## Package preservation and fidelity gates

- Work from a byte copy of the reference, never from a blank document.
- Preserve all package parts and relationships except text nodes in `word/document.xml`, `word/header1.xml`, `word/footer1.xml` and the document metadata language/font additions needed for Chinese rendering.
- Final checks: same section count, table count, image count, live PAGE field count, all source non-empty slots translated, no remaining Vietnamese diacritics in user-facing content, all expected numbers/technical identifiers retained, and output opens successfully with python-docx.
- Visual fidelity gate: render every page when an available Word/LibreOffice renderer can be used. If no renderer is available, disclose that visual QA could not be completed and rely on structural comparison.

# Feature: DOCX OOXML Output

**PRD refs**: REQ-05, REQ-16
**Status**: Approved

## Description

Generate a Word .docx file using the OOXML (Office Open XML) format. The .docx is a ZIP archive containing XML files. Charts use native DrawingML markup (rendered natively by Word/LibreOffice).

## File Structure Inside .docx ZIP

```
[Content_Types].xml
_rels/.rels
word/document.xml
word/styles.xml
word/_rels/document.xml.rels
word/charts/chart1.xml     (timeline line chart)
word/charts/chart2.xml     (pie chart)
```

## Implementation

- ZIP creation via bundled minizip (zlib contrib) or a minimal ZIP writer using raw zlib deflate
- All XML is generated programmatically in C using snprintf into dynamic buffers
- XML content is escaped via `secure_xml_escape()` to prevent injection
- Charts use `<c:chartSpace>` / `<c:lineChart>` / `<c:pieChart>` DrawingML elements
- Tables in document.xml use `<w:tbl>` / `<w:tr>` / `<w:tc>` elements

## Acceptance Criteria

- Generated .docx opens in Microsoft Word 2016+ and LibreOffice 7+
- `unzip -l output.docx` shows all expected XML files
- Charts render with correct data points
- All text content is properly XML-escaped

# ADR-0005: Native OOXML DrawingML Charts

**Status**: Accepted
**Date**: 2026-03-22

## Context

The report requires a timeline line chart and a pie chart inside a .docx file. Options: (A) embed charts as raster images, (B) use native OOXML DrawingML chart XML.

## Decision

Use **native OOXML DrawingML charts** (`<c:chartSpace>`, `<c:lineChart>`, `<c:pieChart>`).

## Rationale

- Charts are rendered natively by Word and LibreOffice — crisp at any zoom level
- No image-generation library needed (no libpng, cairo, etc.)
- Chart data is embedded in XML — editable in Word after generation
- The OOXML chart XML schema is verbose but regular and predictable for programmatic generation

## Consequences

- Chart XML generation is ~500 lines of C (chart_xml.c)
- Charts may render slightly differently between Word and LibreOffice
- No chart preview possible without opening the .docx in an office suite

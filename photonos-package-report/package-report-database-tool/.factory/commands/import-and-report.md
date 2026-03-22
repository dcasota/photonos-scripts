Import scan files and generate the report:

1. `cd` to `package-report-database-tool/`
2. Run `./photon-report-db --db photon-scans.db --import ../scans/ --report report.docx`
3. Report how many files were imported, skipped, errored
4. Verify report.docx with `unzip -l report.docx`

# SnykAnalysis

A set of PowerShell scripts for running [Snyk](https://snyk.io/) code analysis across multiple project directories, parsing the results into a SQLite database, and generating summary reports.

## Prerequisites

- **PowerShell** (5.1+ or PowerShell 7+)
- **Snyk CLI** installed and authenticated (`snyk auth`)
- **sqlite3** command-line tool

## Scripts

### Run-SnykOnSubdirs.ps1

Loops through all immediate subdirectories of a given base directory and runs `snyk code test` on each one. Output is redirected to timestamped log files placed alongside the subdirectories.

```powershell
./Run-SnykOnSubdirs.ps1 -BaseDir /path/to/projects
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `BaseDir` | Yes | Path to the base directory containing project subdirectories |

**Output:** One `<subdirname>_snyk_<datetime>.log` file per subdirectory.

### Parse-SnykLogs.ps1

Parses `*_snyk*.log` files (produced by `Run-SnykOnSubdirs.ps1`) and stores the parsed issues into per-file tables in a SQLite database.

```powershell
./Parse-SnykLogs.ps1 -Directory /path/to/logs -Database snyk_issues.db
```

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `Directory` | No | `.` | Directory to scan for log files |
| `Database` | No | `snyk_issues.db` | SQLite database file path |
| `Recursive` | No | `$true` | Whether to scan subdirectories recursively |

**Output:** A SQLite database with one table per log file, each containing parsed issue records (priority, title, finding ID, path, line number, info, and summary counts).

### Generate-SnykReport.ps1

Generates a structured text report from the SQLite database, including category breakdowns (with a crypto-related filter), summary statistics, and a per-package overview based on the latest run of each source package.

```powershell
./Generate-SnykReport.ps1 -Database snyk_issues.db
```

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `Database` | No | `snyk_issues.db` | SQLite database file path |
| `ReportFile` | No | `SnykReport_<datetime>.txt` | Output report file path |

**Output:** A text report containing:
- Top 10 HIGH-priority issue categories (with and without "crypto" in the title)
- Top 10 MEDIUM-priority issue categories
- Summary counts by severity
- Top 10 source packages ranked by total issues

## Typical Workflow

```powershell
# 1. Run Snyk on all project subdirectories
./Run-SnykOnSubdirs.ps1 -BaseDir /path/to/projects

# 2. Parse the generated log files into a database
./Parse-SnykLogs.ps1 -Directory /path/to/projects

# 3. Generate a summary report
./Generate-SnykReport.ps1
```

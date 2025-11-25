# Installer Scripts Version Control

## Date: 2025-11-25

## Purpose

This directory contains versioned backups of all installer scripts and subscripts to preserve old features and enable rollback if needed.

---

## Directory Structure

```
/root/photonos-scripts/docsystem/archive/
├── VERSION_CONTROL_README.md       # This file
├── extract_versions_fixed.sh       # Script to extract versions from git
└── versions/                       # Versioned backup files
    ├── installer_v1_commit*.sh
    ├── installer_v2_commit*.sh
    ├── installer_v3_commit*.sh
    ├── installer_v*_YYYYMMDD_HHMMSS.sh
    └── ... (all subscripts with same naming pattern)
```

---

## Naming Convention

### Git-based versions (Last 3 commits)
```
<script-name>_v<number>_commit<hash>.sh
```

**Examples:**
- `installer_v1_commit5343fb8.sh` - Most recent commit version
- `installer_v2_commit2f941b8.sh` - Second most recent
- `installer_v3_commit3de1ced.sh` - Third most recent

### Timestamp-based versions (Current working copy)
```
<script-name>_v<YYYYMMDD_HHMMSS>.sh
```

**Example:**
- `installer_v20251125_155723.sh` - Snapshot taken on Nov 25, 2025 at 15:57:23

---

## Versioned Scripts

### 1. Main Installer
- **installer.sh** (341 lines)
  - v1: commit 5343fb8 - "fix(installer): Remove duplicate params.versions entries in config.toml"
  - v2: commit 2f941b8 - "fix(installer): Complete fix for TOML quote escaping and commit info updates"
  - v3: commit 3de1ced - "fix(installer): Escape double quotes in commit messages for TOML compatibility"
  - Current: v20251125_155723

### 2. Console Backend
- **installer-consolebackend.sh** (354 lines)
  - v1: commit 1a841e0 - Latest git version
  - v2: commit c60a303 - Previous version
  - Current: v20251125_155723

### 3. GitHub Interconnection
- **installer-ghinterconnection.sh** (328 lines)
  - v1: commit 1a841e0 - Latest git version
  - v2: commit 0486263 - "Fix formatting issues in installer-ghinterconnection.sh"
  - v3: commit f45e9fe - Earlier version
  - Current: v20251125_155723

### 4. Search Backend
- **installer-searchbackend.sh** (293 lines)
  - v1: commit 1a841e0 - Latest git version
  - v2: commit c60a303 - Previous version
  - Current: v20251125_155723

### 5. Site Build
- **installer-sitebuild.sh** (252 lines)
  - v1: commit 5612284 - Latest git version
  - v2: commit 1a841e0 - Previous version
  - v3: commit b863319 - Earlier version
  - Current: v20251125_155723

### 6. Web Link Fixes
- **installer-weblinkfixes.sh** (683 lines - largest script)
  - v1: commit d2a4df1 - "fix(docsystem): Prevent menu deletion in installer-weblinkfixes.sh"
  - v2: commit 1a841e0 - Previous version
  - v3: commit 65f1687 - Earlier version (552 lines - significant changes)
  - Current: v20251125_155723

---

## How to Use

### Restore a Previous Version

1. **Identify the version you need:**
   ```bash
   cd /root/photonos-scripts/docsystem/archive/versions
   ls -lh installer*.sh
   ```

2. **Compare versions:**
   ```bash
   diff installer_v1_commit5343fb8.sh installer_v2_commit2f941b8.sh
   ```

3. **Restore a specific version:**
   ```bash
   cp installer_v2_commit2f941b8.sh ../../installer.sh
   ```

4. **Verify the restoration:**
   ```bash
   head -20 ../../installer.sh
   ```

### Extract New Versions

To create new versioned backups after making changes:

```bash
cd /root/photonos-scripts
bash docsystem/archive/extract_versions_fixed.sh
```

This will:
- Extract the last 3 commits for each script from git
- Create timestamped snapshots of current versions
- Preserve all files in `archive/versions/`

### Create Manual Snapshot

To create a quick timestamped backup:

```bash
cd /root/photonos-scripts/docsystem
DATE=$(date +%Y%m%d_%H%M%S)
cp installer.sh archive/versions/installer_manual_${DATE}.sh
```

---

## Version History Summary

### installer.sh
| Version | Commit | Date | Key Changes |
|---------|--------|------|-------------|
| v1 | 5343fb8 | 2025-11-23 | Remove duplicate params.versions |
| v2 | 2f941b8 | 2025-11-23 | Fix TOML quote escaping |
| v3 | 3de1ced | 2025-11-23 | Escape double quotes in commit messages |

### installer-weblinkfixes.sh (Most Active)
| Version | Commit | Lines | Date | Key Changes |
|---------|--------|-------|------|-------------|
| v1 | d2a4df1 | 683 | 2025-11-23 | Prevent menu deletion |
| v2 | 1a841e0 | 675 | 2025-11-23 | Multiple fixes |
| v3 | 65f1687 | 552 | 2025-11-23 | Earlier version (131 lines added) |

### installer-sitebuild.sh
| Version | Commit | Lines | Date | Key Changes |
|---------|--------|-------|------|-------------|
| v1 | 5612284 | 252 | 2025-11-24 | Latest updates |
| v2 | 1a841e0 | 251 | 2025-11-23 | Previous version |
| v3 | b863319 | 250 | 2025-11-23 | Earlier version |

---

## Important Notes

1. **Git Commits Preserved**: All versions are linked to actual git commits, allowing full diff and history tracking

2. **Working Directory Snapshots**: Timestamp versions capture the exact state at backup time, including uncommitted changes

3. **No Data Loss**: All versions are preserved independently - restoring one version doesn't delete others

4. **File Sizes**: 
   - Smallest: installer-searchbackend.sh (~8.4K)
   - Largest: installer-weblinkfixes.sh (~44K)
   - Total archive size: ~350K

5. **Execution Permissions**: All versioned scripts maintain executable permissions for easy testing

6. **Safe Restoration**: Always test restored versions in a non-production environment first

---

## Maintenance

### Recommended Schedule

- **Daily**: Create timestamp snapshots before major changes
- **Weekly**: Extract latest 3 git versions
- **Monthly**: Review and archive old versions (optional compression)

### Cleanup Policy

- Keep all git-based versions indefinitely (small size, important history)
- Keep timestamp versions for 30 days
- Compress versions older than 90 days (gzip)

### Disk Usage

```bash
# Check archive size
du -sh /root/photonos-scripts/docsystem/archive/

# List by size
ls -lhS /root/photonos-scripts/docsystem/archive/versions/
```

---

## Recovery Scenarios

### Scenario 1: Feature Regression

**Problem**: New installer version breaks existing functionality

**Solution**:
```bash
cd /root/photonos-scripts/docsystem
cp archive/versions/installer_v2_commit2f941b8.sh installer.sh
# Test the installation
bash installer.sh
```

### Scenario 2: Need Specific Old Feature

**Problem**: Old version had a feature that was removed

**Solution**:
```bash
# Find the feature in old versions
cd /root/photonos-scripts/docsystem/archive/versions
grep -n "FEATURE_NAME" installer_v*.sh

# Extract the relevant code section
sed -n '100,150p' installer_v3_commit3de1ced.sh

# Manually merge into current version
```

### Scenario 3: Compare Implementation Changes

**Problem**: Need to understand what changed between versions

**Solution**:
```bash
cd /root/photonos-scripts/docsystem/archive/versions

# Side-by-side diff
diff -y installer_v2_commit2f941b8.sh installer_v1_commit5343fb8.sh | less

# Unified diff
diff -u installer_v2_commit2f941b8.sh installer_v1_commit5343fb8.sh > changes.diff
```

---

## Automation Script

The `extract_versions_fixed.sh` script automates the backup process:

```bash
#!/bin/bash
# Extract last 3 versions of each installer script from git
# Must be run from /root/photonos-scripts (parent directory)

cd /root/photonos-scripts
bash docsystem/archive/extract_versions_fixed.sh
```

**Features:**
- Automatically finds last 3 commits for each script
- Extracts files from git history
- Sets executable permissions
- Validates file contents (skips empty files)
- Provides detailed progress output
- Generates summary statistics

---

## Contact & Support

For questions about version control or to request restoration of a specific version:

1. Review this README
2. Check git history: `git log --follow <script-name>`
3. Compare versions using diff
4. Test in isolated environment before production use

---

## Changelog

### 2025-11-25
- **Initial version control system established**
- Backed up 6 installer scripts
- Extracted last 3 commits for each script (18 versions)
- Created current timestamp snapshots (6 versions)
- Total: 22 versioned backup files
- Created automated extraction script
- Documented recovery procedures

---

## Quick Reference Commands

```bash
# List all versions
ls -lh /root/photonos-scripts/docsystem/archive/versions/

# Extract new versions
cd /root/photonos-scripts && bash docsystem/archive/extract_versions_fixed.sh

# Compare two versions
diff archive/versions/installer_v1*.sh archive/versions/installer_v2*.sh

# Restore a version
cp archive/versions/installer_v2_commit*.sh installer.sh

# View git history
git log --oneline --follow installer.sh

# Search for feature in all versions
grep -r "FEATURE_NAME" archive/versions/
```

---

**Status**: ✅ Active and Maintained  
**Last Updated**: 2025-11-25 15:57:23 UTC  
**Total Versions Preserved**: 22 files (~350KB)

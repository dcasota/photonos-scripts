# Hardcoded Replaces Plugin

**Version:** 1.1.0  
**FIX_ID:** 3  
**Requires LLM:** No

## Description

Fixes known typos and errors using a static list of hardcoded replacements.
Supports two types of replacements:

1. **STRUCTURAL_REPLACEMENTS** - Applied BEFORE code block protection (modify code block structure)
2. **REPLACEMENTS** - Applied AFTER code block protection (regular text fixes)

## Two-Phase Replacement Process

### Phase 1: Structural Replacements

Applied to raw content before code blocks are protected. Used for:
- Fixing unclosed code blocks
- Converting malformed inline code to proper code blocks
- Fixing code block structure issues
- Correcting duplicate numbered list items within code sections

Example structural fix for `build-the-iso.md`:
```markdown
# Before (malformed inline code)
5. Clone the Photon project:
    `git clone https://github.com/vmware/photon.git`
     `cd $HOME/workspaces/photon`
6. Make ISO as follows:
   ` sudo make iso`

# After (proper code block)
5. Clone the Photon project:
    ```
    git clone https://github.com/vmware/photon.git
    cd $HOME/workspaces/photon
    ```
6. Make ISO as follows:
   `sudo make iso`
```

### Phase 2: Regular Replacements

Applied after code blocks are protected, ensuring code content is preserved:
- Typo corrections
- Grammar fixes
- VMware/Broadcom branding updates
- URL text replacements

## Issues Detected

Common typos and errors including:
- `setttings` -> `settings`
- `the the` -> `the`
- `followng` -> `following`
- `on a init.d-based` -> `on an init.d-based`
- `VMWare` -> `VMware`
- `[VMware Photon Packages]` -> `[Broadcom Photon OS Packages]`
- And 30+ more specific replacements

## Code Block Protection

Regular replacements use `protect_code_blocks()` to ensure fenced code blocks are never modified:

```python
# Phase 1: Structural replacements on raw content
for original, fixed in STRUCTURAL_REPLACEMENTS:
    result = result.replace(original, fixed)

# Phase 2: Protect code blocks, then apply regular replacements
protected_content, code_blocks = protect_code_blocks(result)
for original, fixed in REPLACEMENTS:
    protected_content = protected_content.replace(original, fixed)
final_content = restore_code_blocks(protected_content, code_blocks)
```

## Example Fixes

**Text Fix:**
```markdown
# Before
Check the setttings page for the the configuration.

# After
Check the settings page for the configuration.
```

**Branding Fix:**
```markdown
# Before
[VMware Photon Packages](https://packages.vmware.com/photon)

# After
[Broadcom Photon OS Packages](https://packages.broadcom.com/photon)
```

## Adding New Replacements

### For Regular Text Replacements

Edit the `REPLACEMENTS` list in `hardcoded_replaces.py`:

```python
REPLACEMENTS = [
    ("original text", "fixed text"),
    # Add new entries here
]
```

### For Structural Replacements (Code Block Fixes)

Edit the `STRUCTURAL_REPLACEMENTS` list:

```python
STRUCTURAL_REPLACEMENTS = [
    # Multiline patterns must match exact whitespace
    ("malformed content\n    `inline code`",
     "fixed content\n    ```\n    code block\n    ```"),
]
```

**Note:** Structural patterns must match exact byte-for-byte content including whitespace and newlines.

## Configuration

No configuration required.

## Changes History

### Version 1.1.0
- Added STRUCTURAL_REPLACEMENTS for code block structure fixes
- Added two-phase replacement process
- Added fixes for build-the-iso.md, build-cloud-images.md, build-ova.md
- Added VMware/Broadcom full markdown link replacements
- Improved code block protection logic

### Version 1.0.0
- Initial release with basic text replacements
- Code block protection using protect_code_blocks()

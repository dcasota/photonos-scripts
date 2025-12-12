# Install Tools Module

**Version:** 1.0.0

## Description

Provides functionality to install required dependencies for the documentation
lecturer on Photon OS systems.

## Requirements

- **Administrative privileges** (root or sudo)
- **Photon OS** with tdnf package manager

## Installed Components

### Java (OpenJDK 21)

Required by LanguageTool for grammar checking:

```bash
tdnf install -y openjdk21
```

Minimum version: Java 17

### Python Package: language-tool-python

Grammar and spelling detection library:

```bash
pip install language-tool-python
```

## Key Functions

### install_tools()

Main installation function:

```python
def install_tools() -> int:
    """Install required tools.
    
    Returns:
        0 on success, 1 on failure
    """
```

### check_admin_privileges()

Verifies root/sudo access:

```python
def check_admin_privileges() -> bool:
    return os.geteuid() == 0
```

## Installation Steps

1. Check administrative privileges
2. Check existing Java version
3. Install OpenJDK 21 if needed (via tdnf)
4. Ensure pip is available
5. Install language-tool-python

## Usage

### From Command Line

```bash
sudo python3 photonos-docs-lecturer.py install-tools
```

### Programmatic

```python
from plugins.install_tools import install_tools

exit_code = install_tools()
if exit_code != 0:
    print("Installation failed")
```

## Error Handling

- Missing privileges: Returns error with sudo instructions
- tdnf failure: Logs error, continues to next step
- pip failure: Attempts ensurepip first

## Output

```
photonos-docs-lecturer.py v2.4 - Install Tools

[INFO] Running with administrative privileges

[STEP 1/3] Installing Java >= 17 (required for LanguageTool)...
[OK] Java 21 is installed (meets requirement >= 17)

[STEP 2/3] Ensuring pip is available...
[OK] pip is available

[STEP 3/3] Installing language-tool-python...
[OK] language-tool-python installed successfully
```

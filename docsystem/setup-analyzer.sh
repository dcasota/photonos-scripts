#!/bin/bash
#
# Setup script for Photon OS Documentation Analyzer
# Installs all required dependencies on Photon OS
#

set -e

echo "=========================================="
echo "Photon OS Documentation Analyzer Setup"
echo "=========================================="
echo

# Check if running on Photon OS
if [ -f /etc/photon-release ]; then
    echo "✓ Detected Photon OS"
    cat /etc/photon-release
else
    echo "⚠ Warning: Not running on Photon OS. Continuing anyway..."
fi
echo

# Check Python version
echo "Checking Python version..."
PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
echo "✓ Python version: $PYTHON_VERSION"

# Extract major and minor version numbers for proper comparison
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

# Check if Python >= 3.8 (compare as integers, not decimals!)
if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 8 ]); then
    echo "✗ Error: Python 3.8+ required (found $PYTHON_VERSION)"
    exit 1
fi
echo

# Install system dependencies
echo "Installing system dependencies..."
if command -v tdnf &> /dev/null; then
    # Photon OS
    tdnf install -y python3-pip python3-devel openjdk21 || {
        echo "⚠ Warning: Some packages may have failed to install"
    }
elif command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    apt-get update
    apt-get install -y python3-pip python3-dev default-jre
elif command -v yum &> /dev/null; then
    # RHEL/CentOS
    yum install -y python3-pip python3-devel java-11-openjdk
else
    echo "⚠ Warning: Unknown package manager. Please install pip and Java manually."
fi
echo "✓ System dependencies installed"
echo

# Upgrade pip
echo "Upgrading pip..."
python3 -m pip install --upgrade pip --quiet
echo "✓ pip upgraded"
echo

# Install Python dependencies
echo "Installing Python dependencies..."
echo "  - requests (HTTP client)"
echo "  - beautifulsoup4 (HTML parser)"
echo "  - lxml (XML parser for BeautifulSoup)"
echo "  - language-tool-python (grammar checker)"
echo "  - Pillow (image analysis)"
echo "  - tqdm (progress bar)"
echo

python3 -m pip install requests beautifulsoup4 lxml language-tool-python Pillow tqdm

if [ $? -eq 0 ]; then
    echo "✓ Python dependencies installed successfully"
else
    echo "✗ Error: Failed to install Python dependencies"
    exit 1
fi
echo

# Verify installations
echo "Verifying installations..."
python3 -c "import requests; print('✓ requests:', requests.__version__)"
python3 -c "import bs4; print('✓ beautifulsoup4:', bs4.__version__)"
python3 -c "import language_tool_python; print('✓ language-tool-python: OK')"
python3 -c "from PIL import Image; print('✓ Pillow: OK')"
echo

# Test Java
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -n 1)
    echo "✓ Java: $JAVA_VERSION"
else
    echo "⚠ Warning: Java not found. LanguageTool may not work properly."
fi
echo

# Make analyzer.py executable
if [ -f "analyzer.py" ]; then
    chmod +x analyzer.py
    echo "✓ Made analyzer.py executable"
else
    echo "⚠ Warning: analyzer.py not found in current directory"
fi
echo

# Test LanguageTool initialization (downloads JAR on first run)
echo "Initializing LanguageTool (this may take a minute on first run)..."
python3 -c "
import language_tool_python
import sys
try:
    tool = language_tool_python.LanguageTool('en-US')
    test = tool.check('This is a test sentence.')
    tool.close()
    print('✓ LanguageTool initialized successfully')
    sys.exit(0)
except Exception as e:
    print(f'✗ LanguageTool initialization failed: {e}')
    sys.exit(1)
"

if [ $? -ne 0 ]; then
    echo "⚠ Warning: LanguageTool may not be fully functional"
fi
echo

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo
echo "Usage examples:"
echo "  python3 analyzer.py --url https://127.0.0.1"
echo "  python3 analyzer.py --url https://127.0.0.1 --docs-release docs-v4"
echo "  python3 analyzer.py --help"
echo
echo "For more information, see ANALYZER_README.md"
echo

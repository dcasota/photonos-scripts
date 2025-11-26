#!/bin/bash

# Usage: sudo ./installer.sh
# All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS.

# Check if GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then
    echo 'GITHUB_TOKEN is not set. Please enter your GitHub token as environment variable EXPORT GITHUB_TOKEN="..."'
    exit 1
else
    echo "GITHUB_TOKEN is set."
fi

# Check if GITHUB_USERNAME is set
if [ -z "$GITHUB_USERNAME" ]; then
    echo "GITHUB_USERNAME is not set. Please enter your GitHub username as environment variable GITHUB_TOKEN."
    exit 1
else
    echo "GITHUB_USERNAME is set."
fi

if [ -z "$PHOTON_FORK_REPOSITORY" ]; then
    echo "PHOTON_FORK_REPOSITORY is not set. Please enter your Photon OS fork repository as environment variable PHOTON_FORK_REPOSITORY."
    exit 1
else
    echo "PHOTON_FORK_REPOSITORY is set."
fi

if [ -z "$PHOTON_FORK_REPOSITORY" ]; then
    echo "PHOTON_FORK_REPOSITORY is not set. Please enter your Photon OS fork repository as environment variable EXPORT PHOTON_FORK_REPOSITORY."
    exit 1
else
    echo "PHOTON_FORK_REPOSITORY is set."
fi

export START_DIR=$(dirname "$(readlink -f "$0")")
export BASE_DIR="/var/www"
export INSTALL_DIR="$BASE_DIR/photon-site"
export SITE_DIR="$INSTALL_DIR/public"  # Where built static files go
export HUGO_VERSION="0.152.2"  # Latest version as of November 10, 2025
export LOGFILE="/var/log/installer.log"

echo "All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS." 
echo "All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS." 1>$LOGFILE 2>&1
date 1>>$LOGFILE 2>&1

# Install required packages
echo "Installing required packages..."
echo "Installing required packages..." 1>>$LOGFILE 2>&1
tdnf install -y git wget unzip curl tar iproute2 gzip nodejs nginx openssl iptables docker cronie  1>>$LOGFILE 2>&1
systemctl enable --now docker 1>>$LOGFILE 2>&1
systemctl enable --now nginx 1>>$LOGFILE 2>&1
systemctl enable --now crond 1>>$LOGFILE 2>&1

# Dynamically retrieve DHCP IP address
export IP_ADDRESS=$(ip addr show | grep -oP 'inet \K[\d.]+(?=/)' | grep -v '127.0.0.1' | head -n 1)
if [ -z "$IP_ADDRESS" ]; then
  export IP_ADDRESS=$(hostname -I | awk '{print $1}' | grep -v '127.0.0.1')
fi
if [ -z "$IP_ADDRESS" ]; then
  echo "Error: Could not detect DHCP IP."
  echo "Error: Could not detect DHCP IP." 1>>$LOGFILE 2>&1
  exit 1
fi
echo "Detected IP address: $IP_ADDRESS"
echo "Detected IP address: $IP_ADDRESS" 1>>$LOGFILE 2>&1

# Dynamically retrieve latest COMMIT_HASH from photon-hugo branch (for logging)
COMMIT_HASH=$(git ls-remote $PHOTON_FORK_REPOSITORY.git refs/heads/photon-hugo 2>/dev/null | cut -f 1)
if [ -z "$COMMIT_HASH" ]; then
  echo "Warning: Could not fetch latest commit hash. Using placeholder."
  echo "Warning: Could not fetch latest commit hash. Using placeholder." 1>>$LOGFILE 2>&1
  COMMIT_HASH="0000000000000000000000000000000000000000"
fi
echo "Using latest commit hash for reference: $COMMIT_HASH"
echo "Using latest commit hash for reference: $COMMIT_HASH" 1>>$LOGFILE 2>&1

# Clean up log files before starting
echo "Cleaning up log files..."
echo "Cleaning up log files..." 1>>$LOGFILE 2>&1
truncate -s 0 $LOGFILE 2>/dev/null || rm -f $LOGFILE
truncate -s 0 /var/log/nginx/error.log 2>/dev/null || rm -f /var/log/nginx/error.log
truncate -s 0 /var/log/nginx/photon-site-error.log 2>/dev/null || rm -f /var/log/nginx/photon-site-error.log
truncate -s 0 $INSTALL_DIR/hugo_build.log 2>/dev/null || rm -f $INSTALL_DIR/hugo_build.log
truncate -s 0 $INSTALL_DIR/malformed_urls.log 2>/dev/null || rm -f $INSTALL_DIR/malformed_urls.log

# Ensure /usr/local/bin exists
mkdir -p /usr/local/bin 1>>$LOGFILE 2>&1

# Install Hugo if not present or wrong version
if ! command -v hugo &> /dev/null || ! hugo version | grep -q "v${HUGO_VERSION}"; then
  echo "Installing or updating Hugo to v${HUGO_VERSION}"
  echo "Installing or updating Hugo to v${HUGO_VERSION}" 1>>$LOGFILE 2>&1
  wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz 1>>$LOGFILE 2>&1
  tar -xvf hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz hugo 1>>$LOGFILE 2>&1
  mv hugo /usr/local/bin/ 1>>$LOGFILE 2>&1
  chmod +x /usr/local/bin/hugo 1>>$LOGFILE 2>&1
  rm -f hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz LICENSE README.md 1>>$LOGFILE 2>&1
else
  echo "Hugo v${HUGO_VERSION} already installed."
  echo "Hugo v${HUGO_VERSION} already installed." 1>>$LOGFILE 2>&1
fi

# Ensure parent directory /var/www and $INSTALL_DIR have correct permissions
mkdir -p /var/www 1>>$LOGFILE 2>&1
chown -R nginx:nginx /var/www 1>>$LOGFILE 2>&1
chmod -R 755 /var/www 1>>$LOGFILE 2>&1

# Clone repo
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "Fetch and merge repo"
  echo "Fetch and merge repo" 1>>$LOGFILE 2>&1
  cd "$INSTALL_DIR" 1>>$LOGFILE 2>&1
  git config --global --add safe.directory "$INSTALL_DIR" 1>>$LOGFILE 2>&1
  git fetch 1>>$LOGFILE 2>&1
  git merge 1>>$LOGFILE 2>&1
else
  # Clean up existing directory if it's not a git repo (to avoid conflicts)
  rm -rf "$INSTALL_DIR" 
  echo "Cloning repo"
  echo "Cloning repo" 1>>$LOGFILE 2>&1 
  if git clone --branch photon-hugo --single-branch $PHOTON_FORK_REPOSITORY "$INSTALL_DIR" 1>>$LOGFILE 2>&1; then
      cd "$INSTALL_DIR" 1>>$LOGFILE 2>&1
      # Check if theme exists, if not download Docsy as fallback
      if [ ! -d "$INSTALL_DIR/themes/photon-theme" ]; then
         echo "Theme 'photon-theme' not found. Downloading Docsy as fallback..."
         echo "Theme 'photon-theme' not found. Downloading Docsy as fallback..." 1>>$LOGFILE 2>&1
         mkdir -p $INSTALL_DIR/themes/photon-theme
         wget -O $INSTALL_DIR/docsy.zip "https://github.com/google/docsy/archive/refs/heads/master.zip" 1>>$LOGFILE 2>&1
         unzip -q $INSTALL_DIR/docsy.zip -d $INSTALL_DIR/themes/ 1>>$LOGFILE 2>&1
         if [ -d "$INSTALL_DIR/themes/docsy-main" ]; then
            mv $INSTALL_DIR/themes/docsy-main/* $INSTALL_DIR/themes/photon-theme/
            rmdir $INSTALL_DIR/themes/docsy-main
         elif [ -d "$INSTALL_DIR/themes/docsy-master" ]; then
            mv $INSTALL_DIR/themes/docsy-master/* $INSTALL_DIR/themes/photon-theme/
            rmdir $INSTALL_DIR/themes/docsy-master
         fi
         rm $INSTALL_DIR/docsy.zip
      fi
  else
      echo "Git clone failed."
      exit
  fi
fi

# Extract commit details and add to config.toml
if [ -d $INSTALL_DIR/.git ]; then
    COMMIT_DATE=$(git log -1 --format=%cd --date=short)
    COMMIT_HASH_SHORT=$(echo $COMMIT_HASH | cut -c1-7)
    # Escape double quotes in commit message for TOML compatibility
    # Use double backslash to survive shell interpolation
    COMMIT_MESSAGE=$(git log -1 --format=%s | sed 's/"/\\\\"/g')
    COMMIT_FULL_HASH=$COMMIT_HASH
else
    COMMIT_DATE=$(date +%Y-%m-%d)
    COMMIT_HASH_SHORT="zip"
    COMMIT_FULL_HASH="zip-download"
    COMMIT_MESSAGE="Downloaded from ZIP"
fi

# Remove existing commit info to ensure fresh values on every run
sed -i '/^last_commit_date = /d' $INSTALL_DIR/config.toml
sed -i '/^last_commit_hash = /d' $INSTALL_DIR/config.toml
sed -i '/^last_commit_full_hash = /d' $INSTALL_DIR/config.toml
sed -i '/^last_commit_message = /d' $INSTALL_DIR/config.toml

# Add fresh commit info
if grep -q "^\[params\]$" $INSTALL_DIR/config.toml; then
  sed -i '/^\[params\]$/a last_commit_date = "'"$COMMIT_DATE"'"' $INSTALL_DIR/config.toml
  sed -i '/^\[params\]$/a last_commit_hash = "'"$COMMIT_HASH_SHORT"'"' $INSTALL_DIR/config.toml
  sed -i '/^\[params\]$/a last_commit_full_hash = "'"$COMMIT_FULL_HASH"'"' $INSTALL_DIR/config.toml
  sed -i '/^\[params\]$/a last_commit_message = "'"$COMMIT_MESSAGE"'"' $INSTALL_DIR/config.toml
else
  cat >> $INSTALL_DIR/config.toml <<EOF_CONFIGTOML

[params]
last_commit_date = "$COMMIT_DATE"
last_commit_hash = "$COMMIT_HASH_SHORT"
last_commit_full_hash = "$COMMIT_FULL_HASH"
last_commit_message = "$COMMIT_MESSAGE"
EOF_CONFIGTOML
fi

# Enable dark mode in config.toml
echo "Enabling dark mode in config.toml..."
sed -i 's/^darkmode = false$/darkmode = true/' $INSTALL_DIR/config.toml
if grep -q '^darkmode = true$' $INSTALL_DIR/config.toml; then
  : # Do nothing, already enabled
else
  if grep -q "^\[params\]$" $INSTALL_DIR/config.toml; then
    sed -i '/^\[params\]$/a darkmode = true' $INSTALL_DIR/config.toml
  else
    cat >> $INSTALL_DIR/config.toml <<EOF_DARKMODE
[params]
darkmode = true
EOF_DARKMODE
  fi
fi

if [ -z "DEBUG" ]; then
# Add UI configuration for navbar logo if not present
if ! grep -q "^\[params\.ui\]" $INSTALL_DIR/config.toml; then
  if grep -q "^\[params\]$" $INSTALL_DIR/config.toml; then
    # Add after [params] section
    sed -i '/^\[params\]$/a \n# UI configuration\n[params.ui]\n# Enable navbar logo\nnavbar_logo = true' $INSTALL_DIR/config.toml
  fi
fi

# Add version selector configuration to [params] section if not present
if ! grep -q "version_menu" $INSTALL_DIR/config.toml; then
  if grep -q "^\[params\]$" $INSTALL_DIR/config.toml; then
    echo "Adding version selector parameters to [params] section..."
    sed -i '/^\[params\]$/a version_menu = "Release"' $INSTALL_DIR/config.toml
    sed -i '/^\[params\]$/a version = "v5"' $INSTALL_DIR/config.toml
    sed -i '/^\[params\]$/a url_latest_version = "/docs/"' $INSTALL_DIR/config.toml
  fi
fi

# Add menu configuration if not present
# Remove any existing menu.main entries to ensure clean configuration
if grep -q "^\[\[menu\.main\]\]" $INSTALL_DIR/config.toml; then
  echo "Removing existing menu configuration..."
  # Use awk to remove all [[menu.main]] blocks and the menu configuration header
  # Skip from "# Menu configuration" until we hit a line that starts with [[ but is not [[menu.main]]
  # or until we hit another section marker (line starting with #)
  awk '
    /^# Menu configuration$/ { in_menu=1; next }
    in_menu && /^\[\[menu\.main\]\]/ { in_block=1; next }
    in_menu && in_block && /^(name|weight|url|identifier|pre|post) *=/ { next }
    in_menu && in_block && /^$/ { in_block=0; next }
    in_menu && !in_block && (/^#/ || /^\[/) { in_menu=0 }
    !in_menu || (!in_block && !/^\[\[menu\.main\]\]/)
  ' $INSTALL_DIR/config.toml > $INSTALL_DIR/config.toml.tmp
  mv $INSTALL_DIR/config.toml.tmp $INSTALL_DIR/config.toml
fi

# Now add the proper menu configuration matching the reference site
echo "Adding menu configuration (Home, Blog, Features, Contribute, Docs, Github)..."
cat >> $INSTALL_DIR/config.toml <<'EOF_MENU'

# Menu configuration
[[menu.main]]
name = "Home"
weight = 10
url = "/"

[[menu.main]]
name = "Blog"
weight = 20
url = "/blog/"

[[menu.main]]
name = "Features"
weight = 30
url = "/#features"

[[menu.main]]
name = "Contribute"
weight = 40
url = "/#contributing"

[[menu.main]]
name = "Docs"
weight = 50
url = "/docs/"

[[menu.main]]
name = "Github"
weight = 60
url = "https://github.com/vmware/photon"
EOF_MENU

# Remove any existing params.versions entries to ensure clean configuration
if grep -q "^\[\[params\.versions\]\]" $INSTALL_DIR/config.toml; then
  echo "Removing existing version selector configuration..."
  # Remove the "# Version selector configuration" comment line
  sed -i '/^# Version selector configuration$/d' $INSTALL_DIR/config.toml
  # Use awk to remove ALL [[params.versions]] blocks (handles multiple duplicates)
  awk '
    /^\[\[params\.versions\]\]/ { in_block=1; next }
    in_block && /^[[:space:]]*(version|url) *=/ { next }
    in_block && /^[[:space:]]*$/ { next }
    in_block && (/^\[/ || /^[a-zA-Z]/) { in_block=0 }
    !in_block
  ' $INSTALL_DIR/config.toml > $INSTALL_DIR/config.toml.tmp
  mv $INSTALL_DIR/config.toml.tmp $INSTALL_DIR/config.toml
fi

# Add version selector configuration
echo "Adding version selector configuration (Release dropdown with all doc versions)..."
cat >> $INSTALL_DIR/config.toml <<'EOF_VERSIONS'

# Version selector configuration
[[params.versions]]
  version = "latest"
  url = "/docs/"

[[params.versions]]
  version = "v5"
  url = "/docs-v5/"

[[params.versions]]
  version = "v4"
  url = "/docs-v4/"

[[params.versions]]
  version = "v3"
  url = "/docs-v3/"

[[params.versions]]
  version = "v3 (old)"
  url = "/assets/files/html/3.0/"

[[params.versions]]
  version = "v2 and v1"
  url = "/assets/files/html/1.0-2.0/"
EOF_VERSIONS
fi


# Initialize submodules (e.g., for Docsy theme)
if [ -d $INSTALL_DIR/.git ]; then
    git submodule update --init --recursive 1>>$LOGFILE 2>&1
fi

# Install npm dependencies for theme
if [ -f $INSTALL_DIR/package.json ]; then
  npm install --legacy-peer-deps 1>>$LOGFILE 2>&1
  npm audit fix 1>>$LOGFILE 2>&1
fi
if [ -d $INSTALL_DIR/themes/docsy ] && [ -f $INSTALL_DIR/themes/docsy/package.json ]; then
  cd $INSTALL_DIR/themes/docsy
  npm install --legacy-peer-deps 1>>$LOGFILE 2>&1
  npm audit fix 1>>$LOGFILE 2>&1
  cd ../..
fi

$START_DIR/installer-weblinkfixes.sh
$START_DIR/installer-consolebackend.sh
$START_DIR/installer-searchbackend.sh
$START_DIR/installer-sitebuild.sh
$START_DIR/installer-ghinterconnection.sh

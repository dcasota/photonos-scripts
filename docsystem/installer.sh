#!/bin/bash

# Usage: sudo ./installer.sh
# All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS.

# Check if GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then
    echo "GITHUB_TOKEN is not set. Please enter your GitHub token:"
    read -s GITHUB_TOKEN
    echo  # Print a newline after input
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "Error: No token provided. Exiting."
        exit 1
    fi
    export GITHUB_TOKEN
    echo "GITHUB_TOKEN has been set."
else
    echo "GITHUB_TOKEN is already set."
fi

# Check if GITHUB_USERNAME is set
if [ -z "$GITHUB_USERNAME" ]; then
    echo "GITHUB_USERNAME is not set. Please enter your GitHub username:"
    read -s GITHUB_USERNAME
    echo  # Print a newline after input
    if [ -z "$GITHUB_USERNAME" ]; then
        echo "Error: No token provided. Exiting."
        exit 1
    fi
    export GITHUB_USERNAME
    echo "GITHUB_USERNAME has been set."
else
    echo "GITHUB_USERNAME is already set."
fi

export START_DIR=$(dirname "$(readlink -f "$0")")
export BASE_DIR="/var/www"
export INSTALL_DIR="$BASE_DIR/photon-site"
export SITE_DIR="$INSTALL_DIR/public"  # Where built static files go
export HUGO_VERSION="0.152.2"  # Latest version as of November 10, 2025
export PHOTON_FORK_REPOSITORY="https://www.github.com/dcasota/photon"
export LOGFILE="/var/log/installer.log"

echo "All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS." 
echo "All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS." 1>$LOGFILE 2>&1
date 1>>$LOGFILE 2>&1


# Dynamically retrieve DHCP IP address
tdnf install -y iproute2 1>>$LOGFILE 2>&1
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
tdnf install -y git 1>>$LOGFILE 2>&1
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
truncate -s 0 /var/log/nginx/error.log 2>/dev/null || rm -f /var/log/nginx/error.log
truncate -s 0 /var/log/nginx/photon-site-error.log 2>/dev/null || rm -f /var/log/nginx/photon-site-error.log
truncate -s 0 $INSTALL_DIR/hugo_build.log 2>/dev/null || rm -f $INSTALL_DIR/hugo_build.log
truncate -s 0 $INSTALL_DIR/malformed_urls.log 2>/dev/null || rm -f $INSTALL_DIR/malformed_urls.log

# Install required packages
echo "Installing required packages..."
echo "Installing required packages..." 1>>$LOGFILE 2>&1
tdnf install -y wget unzip curl tar gzip nodejs nginx openssl iptables docker cronie  1>>$LOGFILE 2>&1
systemctl enable --now docker 1>>$LOGFILE 2>&1
systemctl enable --now nginx 1>>$LOGFILE 2>&1
systemctl enable --now crond 1>>$LOGFILE 2>&1

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
  else
      echo "Git clone failed. Attempting ZIP download..."
      echo "Git clone failed. Attempting ZIP download..." 1>>$LOGFILE 2>&1
      mkdir -p "$INSTALL_DIR"
      wget -O "$INSTALL_DIR/repo.zip" "$PHOTON_FORK_REPOSITORY/archive/refs/heads/photon-hugo.zip" 1>>$LOGFILE 2>&1
      unzip -q "$INSTALL_DIR/repo.zip" -d "$INSTALL_DIR" 1>>$LOGFILE 2>&1
      # Move files from extracted dir to INSTALL_DIR (handle variable directory name)
      EXTRACTED_DIR=$(find "$INSTALL_DIR" -maxdepth 1 -type d -name "photon-*" | head -n 1)
      if [ -n "$EXTRACTED_DIR" ]; then
          mv "$EXTRACTED_DIR"/* "$INSTALL_DIR"/ 2>/dev/null
          rmdir "$EXTRACTED_DIR"
      fi
      rm "$INSTALL_DIR/repo.zip"
      cd "$INSTALL_DIR" 1>>$LOGFILE 2>&1
      
      # Check if theme exists, if not download Docsy as fallback
      if [ ! -d "themes/photon-theme" ]; then
         echo "Theme 'photon-theme' not found. Downloading Docsy as fallback..."
         echo "Theme 'photon-theme' not found. Downloading Docsy as fallback..." 1>>$LOGFILE 2>&1
         mkdir -p themes/photon-theme
         wget -O docsy.zip "https://github.com/google/docsy/archive/refs/heads/master.zip" 1>>$LOGFILE 2>&1
         unzip -q docsy.zip -d themes/ 1>>$LOGFILE 2>&1
         if [ -d "themes/docsy-main" ]; then
            mv themes/docsy-main/* themes/photon-theme/
            rmdir themes/docsy-main
         elif [ -d "themes/docsy-master" ]; then
            mv themes/docsy-master/* themes/photon-theme/
            rmdir themes/docsy-master
         fi
         rm docsy.zip
      fi
  fi
fi

# Extract commit details and add to config.toml
if [ -d .git ]; then
    COMMIT_DATE=$(git log -1 --format=%cd --date=short)
    COMMIT_HASH_SHORT=$(echo $COMMIT_HASH | cut -c1-7)
    COMMIT_MESSAGE=$(git log -1 --format=%s)
    COMMIT_FULL_HASH=$COMMIT_HASH
else
    COMMIT_DATE=$(date +%Y-%m-%d)
    COMMIT_HASH_SHORT="zip"
    COMMIT_FULL_HASH="zip-download"
    COMMIT_MESSAGE="Downloaded from ZIP"
fi

if ! grep -q "last_commit_date" $INSTALL_DIR/config.toml; then
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
fi

# Add UI configuration for navbar logo if not present
if ! grep -q "^\[params\.ui\]" $INSTALL_DIR/config.toml; then
  if grep -q "^\[params\]$" $INSTALL_DIR/config.toml; then
    # Add after [params] section
    sed -i '/^\[params\]$/a \n# UI configuration\n[params.ui]\n# Enable navbar logo\nnavbar_logo = true' $INSTALL_DIR/config.toml
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

# Initialize submodules (e.g., for Docsy theme)
if [ -d .git ]; then
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




#!/bin/bash

# Usage: sudo ./installer.sh
# All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS.

export LOGFILE="/var/log/installer.log"
echo "All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS." 
echo "All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS." 1>$LOGFILE 2>&1
echo "====================================================================================================="
date 1>>$LOGFILE 2>&1

export START_DIR=$(dirname "$(readlink -f "$0")")
export BASE_DIR="/var/www"
export INSTALL_DIR="$BASE_DIR/photon-site"
export SITE_DIR="$INSTALL_DIR/public"  # Where built static files go
export HUGO_VERSION="0.152.2"  # Latest version as of November 10, 2025

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

# Initialize submodules (e.g., for Docsy theme)
if [ -d $INSTALL_DIR/.git ]; then
    git submodule update --init --recursive 1>>$LOGFILE 2>&1
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
fi

# $START_DIR/installer-weblinkfixes.sh
# $START_DIR/installer-consolebackend.sh
# $START_DIR/installer-searchbackend.sh
$START_DIR/installer-sitebuild.sh
$START_DIR/installer-ghinterconnection.sh

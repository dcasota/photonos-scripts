#!/bin/bash

# Usage: sudo ./installer.sh <install_directory>
# All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS.
# Uses fixed versions: Hugo v0.151.2 (latest as of Nov 2025), repo latest commit on photon-hugo branch.
# Assumes Photon OS (uses tdnf for packages).
# Includes all components: clones repo from GitHub, installs Hugo binary, builds site, sets up Nginx.
# Designed to be idempotent/reinstallable: checks for existing installations and updates/resets as needed.
# Requires root for tdnf and Nginx.
# Extended to allow access via VM's DHCP IP: opens port 80 in iptables firewall and makes Nginx listen on all interfaces.
# Fixes: Initializes submodules for themes, sets baseURL to "/" for self-hosting at root, fixes deprecated configs.
# Added: Installs nodejs and runs npm install for Docsy theme dependencies (PostCSS, etc.).
# Integrated: Replaces deprecated .Site.IsServer with hugo.IsServer in templates to fix build errors.
# Added: Nginx config test before restart; makes site dir readable.
# Added: Sets up self-signed HTTPS with openssl; redirects HTTP to HTTPS; opens port 443.
# Fixes: Adds googleAnalytics to config.toml; removes GA check from conditions to avoid evaluation errors.
# Fixes: Sets safe.directory for Git to avoid dubious ownership errors; ensures nginx ownership before Git ops.
# Fixes: Sets permissions on /var/www and checks SELinux to resolve Nginx 404 (Permission denied) errors.
# Fixes: Sets uglyURLs=false in config.toml to ensure subpaths like /docs-v5/ work correctly.
# Added: Cleans up /var/log/nginx/error.log, /var/log/nginx/photon-site-error.log, and hugo_build.log before installation.
# Fixes: Moves languages.en.description to [languages.en.params] for Hugo v0.129.0+ compatibility.
# Fixes: Patches render-link.html to skip urls.Parse and use safeURL directly to avoid parse errors.
# Added: Dynamically retrieves DHCP IP from local system for self-signed cert and output instructions.
# Added: Ensures subdirectories blog, docs-v3, docs-v4, docs-v5 are generated in public/.
# Added: Dynamically fetches latest COMMIT_HASH from photon-hugo branch for repo checkout.
# Fixes: Removes /etc/nginx/html/* to prevent Nginx welcome screen.
# Fixes: Runs npm audit fix after npm install; removes maxdepth from subpath list.
# Fixes: Corrects sed expression for URL cleanup to handle parentheses around URLs; ensures single [permalinks] section to fix config error.
# For subpath hosting (e.g., /photon-site): Rerun with modified baseURL and Nginx location/alias as per comments.
# Note: Self-signed cert will cause browser warnings; for production, use cert.
# Fix: Checks out branch instead of hash to avoid detached HEAD, ensuring proper Git info for Hugo.
# Added: Overrides page-meta-lastmod.html with site-wide last change for consistent footer.
# Fix: Patches head.html to use modern Google Analytics internal template instead of deprecated async version.
# Added: Patch docs-v* _index.md to use docs layout for sidebar on main pages.
# Fix: Updated patching to remove existing layout and insert new layout: docs after opening frontmatter to avoid duplication in content.
# Modification: Extract commit details from HEAD after checkout and add to config.toml as params. Update template to use these params for footer instead of GitInfo to ensure consistent and correct display matching the branch.
# Fix: Add params only if not already present to avoid duplicate key errors in TOML.
# Added: Patch docs-v* _index.md to set type: docs for sidebar and menu on main pages.
# Fix: Updated patching to remove existing type and insert new type: docs after opening frontmatter to avoid duplication.
# Fix: Use correct i18n key 'post_last_mod' in page-meta-lastmod.html for proper translation.
# Fix: Use '%-d' in git date format to remove zero-padding on day.
# Fix: Add space after "modified" in footer via i18n translation.
# Added: Flatten redundant nested docs-vX subdirs to fix double path URLs (e.g., /docs-v5/docs-v5/).
# Added: Clean up duplicated permalinks from existing content.
# Fix: Use :sections in permalink config to handle hierarchy without duplicates; remove frontmatter permalink setting; fix internal links.
# Added: Override render-image.html to disable lazy loading for printview image display fix.
# Updated: Modified render-image.html to use root-relative absolute paths for images to fix wrong relative paths in printview.
# Added: Patch quick-start-links _index.md to fix orphaned links with correct absolute paths for all versions (v3, v4, v5).
# Fix: Replaced Slack logo and link with Broadcom in footer by modifying config.toml params.links.user and patching templates to handle image URLs in icon fields.
# Fix: Updated to use local Broadcom logo and change name to "Broadcom Community".
# Fix: Removed indentation in added TOML sections to fix unmarshal error in config.toml validation.
# Modification (2025-11-11): Replaced per-page sandbox with global console feature in menu; console is draggable, resizable, with reset/reconnect options; uses same backend.
# Fix (2025-11-11): Removed escaping backslashes in render-image.html to fix Hugo parse error. Changed navbar patch path to photon-theme.
# Modification: Added "Chat" menu entry with icon; opens static chat box, draggable/resizable.
# Modification: Extended console to persist open state, position, size across pages using localStorage; session preserved for 5 min inactivity with backend timeout.
# Modification: Preserve console buffer content across page switches by saving to localStorage on beforeunload and restoring on init; send \r on reconnect to redraw prompt.
# Modification (2025-11-11): Use tmux in backend for persistent terminal state, including buffer and cursor position; remove frontend buffer save/restore; remove auto-open on load to require user click; remove repeated messages.
# Modification (2025-11-11): Reengineer console to embed as a fixed bottom panel like Azure Cloud Shell; remove draggable; make vertically resizable; add welcome overlay on first open.
# Modification (2025-11-11): Preserve open state of console across page navigations using localStorage; auto-open if previously open; persist welcome shown state.
# Modification (2025-11-11): Add term.focus() to ensure cursor focus on open; clean detach on beforeunload by sending prefix-d to tmux.
# Modification (2025-11-11): Track unfinished input in frontend and re-send on reconnect to preserve typed characters and set cursor at end.
# Modification (2025-11-11): Move detach sequence to backend on ws.close for reliability; add short delay before stream.end().
# Modification: Added cronie installation and cron job for periodic Docker container prune to clean up stopped sandboxes.
# Modification: On re-attach, capture and send current tmux pane content to show initial state.
# Added: Integrated search overlay with Lunr.js client-side search, matching the Factory.ai style (transparent input panel, blurred background).
# Fix: Added mkdir -p for static/js to prevent file creation errors.
# Fix: Patched head.html to replace deprecated _internal/google_analytics_async.html with _internal/google_analytics.html.
# Fix: Patched head-css.html to replace .Site.IsServer with hugo.IsServer.
# Fix: Fixed backend terminal-server.js to use console.log instead of undefined server.listen.
# Fix: Added npm init and install for backend dependencies.
# Fix (2025-11-17): Set TERM=xterm-256color in Docker container and tmux exec environments to resolve "missing or unsuitable terminal: xterm" error.
# Fix (2025-11-17): Added ncurses-terminfo to Dockerfile to provide terminfo entries for xterm and xterm-256color.
# Fix (2025-11-17): Fixed tmux "no sessions" error by using default shell in new-session (avoids non-interactive bash exit), added -e TERM=xterm-256color to new-session, and corrected session ID persistence by sending session.id instead of param.

BASE_DIR="/var/www"
INSTALL_DIR="$BASE_DIR/photon-site"
SITE_DIR="$INSTALL_DIR/public"  # Where built static files go
HUGO_VERSION="0.152.2"  # Latest version as of November 10, 2025
PHOTON_FORK_REPOSITORY="https://www.github.com/dcasota/photon"

# Dynamically retrieve DHCP IP address
tdnf install -y iproute2
IP_ADDRESS=$(ip addr show | grep -oP 'inet \K[\d.]+(?=/)' | grep -v '127.0.0.1' | head -n 1)
if [ -z "$IP_ADDRESS" ]; then
  IP_ADDRESS=$(hostname -I | awk '{print $1}' | grep -v '127.0.0.1')
fi
if [ -z "$IP_ADDRESS" ]; then
  IP_ADDRESS="localhost"
  echo "Warning: Could not detect DHCP IP. Using 'localhost' for certificate. Set IP manually if needed."
  exit 1
fi
echo "Detected IP address: $IP_ADDRESS"

# Dynamically retrieve latest COMMIT_HASH from photon-hugo branch (for logging)
tdnf install -y git
COMMIT_HASH=$(git ls-remote https://github.com/vmware/photon.git refs/heads/photon-hugo | cut -f 1)
if [ -z "$COMMIT_HASH" ]; then
  echo "Error: Could not fetch latest commit hash from photon-hugo branch."
  exit 1
fi
echo "Using latest commit hash for reference: $COMMIT_HASH"

# Clean up log files before starting
echo "Cleaning up log files..."
truncate -s 0 /var/log/nginx/error.log 2>/dev/null || rm -f /var/log/nginx/error.log
truncate -s 0 /var/log/nginx/photon-site-error.log 2>/dev/null || rm -f /var/log/nginx/photon-site-error.log
truncate -s 0 $INSTALL_DIR/hugo_build.log 2>/dev/null || rm -f $INSTALL_DIR/hugo_build.log
truncate -s 0 $INSTALL_DIR/malformed_urls.log 2>/dev/null || rm -f $INSTALL_DIR/malformed_urls.log

# Install required packages
echo "Installing required packages..."
tdnf install -y wget unzip curl tar gzip nodejs nginx openssl iptables docker cronie
systemctl enable --now docker
systemctl enable --now nginx
systemctl enable --now crond

# Ensure /usr/local/bin exists
mkdir -p /usr/local/bin

# Install Hugo if not present or wrong version
if ! command -v hugo &> /dev/null || ! hugo version | grep -q "v${HUGO_VERSION}"; then
  echo "Installing or updating Hugo to v${HUGO_VERSION}"
  wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz
  tar -xvf hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz hugo
  mv hugo /usr/local/bin/
  chmod +x /usr/local/bin/hugo
  rm -f hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz LICENSE README.md
else
  echo "Hugo v${HUGO_VERSION} already installed."
fi

# Ensure parent directory /var/www and $INSTALL_DIR have correct permissions
mkdir -p /var/www
chown -R nginx:nginx /var/www
chmod -R 755 /var/www

# Clone repo
if [ -d "$INSTALL_DIR" ]; then
  cd "$INSTALL_DIR"
  git config --global --add safe.directory "$INSTALL_DIR"
  git fetch
  git merge
fi
echo "Cloning repo"
git clone --branch photon-hugo --single-branch $PHOTON_FORK_REPOSITORY "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Extract commit details and add to config.toml
COMMIT_DATE=$(git log -1 --format=%cd --date=short)
COMMIT_HASH_SHORT=$(echo $COMMIT_HASH | cut -c1-7)
COMMIT_MESSAGE=$(git log -1 --format=%s)
COMMIT_FULL_HASH=$COMMIT_HASH

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

# Initialize submodules (e.g., for Docsy theme)
git submodule update --init --recursive

# Install npm dependencies for theme
if [ -f $INSTALL_DIR/package.json ]; then
  npm install --legacy-peer-deps 1>NUL 2>&1
  npm audit fix 1>NUL 2>&1
fi
if [ -d $INSTALL_DIR/themes/docsy ] && [ -f $INSTALL_DIR/themes/docsy/package.json ]; then
  cd $INSTALL_DIR/themes/docsy
  npm install --legacy-peer-deps 1>NUL 2>&1
  npm audit fix 1>NUL 2>&1
  cd ../..
fi

# Download Broadcom logo locally to static/img
if [ ! -f $INSTALL_DIR/static/img/broadcom-logo.png ]; then
	mkdir -p $INSTALL_DIR/static/img
	wget -O $INSTALL_DIR/static/img/broadcom-logo.png "https://www.broadcom.com/img/broadcom-logo.png"
fi

# Setup favicons directory with placeholder icons
mkdir -p $INSTALL_DIR/static/favicons
# Create basic placeholder favicons (use existing site icon if available, otherwise create minimal)
if [ -f $INSTALL_DIR/static/img/photon-logo.png ]; then
  for size in 36 48 72 96 144 192 180; do
    cp $INSTALL_DIR/static/img/photon-logo.png $INSTALL_DIR/static/favicons/android-${size}x${size}.png 2>/dev/null || touch static/favicons/android-${size}x${size}.png
  done
  cp $INSTALL_DIR/static/img/photon-logo.png $INSTALL_DIR/static/favicons/apple-touch-icon-180x180.png 2>/dev/null || touch static/favicons/apple-touch-icon-180x180.png
else
  # Create minimal placeholder files
  for size in 36 48 72 96 144 192 180; do
    touch $INSTALL_DIR/static/favicons/android-${size}x${size}.png
  done
  touch $INSTALL_DIR/static/favicons/apple-touch-icon-180x180.png
fi

# Fix redundant nested docs-vX subdirs
for ver in docs-v3 docs-v4 docs-v5; do
  NESTED_DIR="$INSTALL_DIR/content/en/$ver/$ver"
  if [ -d "$NESTED_DIR" ]; then
    echo "Flattening redundant /$ver/$ver/ nested dir..."
    mv "$NESTED_DIR"/* "$INSTALL_DIR/content/en/$ver/" 2>/dev/null || true
    rmdir "$NESTED_DIR" 2>/dev/null || true
    rm -f "$NESTED_DIR/_index.md" 2>/dev/null
  fi
done

# Fix incorrect relative links in markdown source (root cause of path duplication)
echo "====================================================="
echo "Fixing incorrect relative links in markdown files..."
echo "====================================================="

# Fix 1: troubleshooting-guide/network-troubleshooting links
echo "1. Fixing network-troubleshooting links..."
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/network-troubleshooting/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/network-troubleshooting/|(./|g' \
  -e 's|(\./administration-guide/|(../../administration-guide/|g' \
  {} \;

# Fix 2: troubleshooting-guide/kernel-problems-and-boot-and-login-errors links
echo "2. Fixing kernel-problems-and-boot-and-login-errors links..."
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/kernel-problems-and-boot-and-login-errors/|(./|g' \
  {} \;

# Fix 3: administration-guide/photon-rpm-ostree/* relative links
echo "3. Fixing photon-rpm-ostree relative links..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-rpm-ostree/introduction/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/|(../../../troubleshooting-guide/|g' \
  -e 's|(\./administration-guide/photon-rpm-ostree/|(../|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-rpm-ostree/installing-a-host-against-default-server-repository/_index.md" -exec sed -i \
  -e 's|(\./installation-guide/|(../../../installation-guide/|g' \
  -e 's|(\./administration-guide/photon-rpm-ostree/|(../|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-rpm-ostree/concepts-in-action/_index.md" -exec sed -i \
  -e 's|(\./administration-guide/photon-rpm-ostree/|(../|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-rpm-ostree/creating-a-rpm-ostree-server/_index.md" -exec sed -i \
  -e 's|(\./administration-guide/photon-rpm-ostree/|(../|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-rpm-ostree/installing-a-host-against-custom-server-repository/_index.md" -exec sed -i \
  -e 's|(\./administration-guide/photon-rpm-ostree/|(../|g' \
  -e 's|(\./user-guide/|(../../../user-guide/|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-rpm-ostree/package-oriented-server-operations/_index.md" -exec sed -i \
  -e 's|(\./administration-guide/photon-rpm-ostree/|(../|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-rpm-ostree/remotes/_index.md" -exec sed -i \
  -e 's|(\./administration-guide/photon-rpm-ostree/|(../|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-rpm-ostree/install-or-rebase-to-photon-os-4/_index.md" -exec sed -i \
  -e 's|(\./administration-guide/photon-rpm-ostree/|(../|g' \
  {} \;

# Fix 4: administration-guide/managing-network-configuration/using-the-network-configuration-manager
echo "4. Fixing network-configuration-manager links..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/managing-network-configuration/using-the-network-configuration-manager/_index.md" -exec sed -i \
  -e 's|(\./command-line-reference/command-line-interfaces/|(../../../../command-line-reference/command-line-interfaces/|g' \
  -e 's|(\./administration-guide/managing-network-configuration/|(../|g' \
  {} \;

# Fix 5: administration-guide/photon-management-daemon/available-apis
echo "5. Fixing photon-management-daemon links..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-management-daemon/available-apis/_index.md" -exec sed -i \
  -e 's|(\./administration-guide/|(../../|g' \
  {} \;

# Fix 6: security-policy and firewall links
echo "6. Fixing security-policy links..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/security-policy/default-firewall-settings/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/|(../../../troubleshooting-guide/|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/network-troubleshooting/checking-firewall-rules/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/|(../../|g' \
  {} \;

# Fix 7: Cross-directory references
echo "7. Fixing cross-directory references..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|(\./installation-guide/administration-guide/|(../../administration-guide/|g' \
  -e 's|(\./user-guide/kubernetes-on-photon-os/)|(../../administration-guide/containers/kubernetes/)|g' \
  {} \;

# Fix 8: Remove .md extensions from all links
echo "8. Removing .md extensions from links..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  's|\(]\)(\([^)]*\)\.md)|\1(\2)|g' \
  {} \;

# Fix 9: Fix remaining cross-directory link issues
echo "9. Fixing remaining cross-directory issues..."
# Fix quick-start-links
find "$INSTALL_DIR/content/en" -path "*/quick-start-links/_index.md" -exec sed -i \
  -e 's|(\.\./\.\./installation-guide/|(../installation-guide/|g' \
  {} \;

# Fix installation-guide paths that reference administration-guide
find "$INSTALL_DIR/content/en" -path "*/installation-guide/building-images/build-other-images/_index.md" -exec sed -i \
  -e 's|(\./administration-guide/|(../../../administration-guide/|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/installation-guide/run-photon-on-gce/installing-photon-os-on-google-compute-engine/_index.md" -exec sed -i \
  -e 's|(\./installation-guide/|(.../../|g' \
  {} \;

# Fix user-guide working-with-kickstart references
find "$INSTALL_DIR/content/en" -type f -name "*.md" -path "*/user-guide/setting-up-network-pxe-boot/*" -exec sed -i \
  -e 's|(\./working-with-kickstart/)|(../working-with-kickstart/)|g' \
  {} \;

# Fix administration-guide security/firewall relative links
find "$INSTALL_DIR/content/en" -path "*/administration-guide/security-policy/default-firewall-settings/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/|(../../../troubleshooting-guide/|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/network-troubleshooting/checking-firewall-rules/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/|(../../|g' \
  {} \;

# Fix troubleshooting-guide/kernel-problems internal links
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/_index.md" -exec sed -i \
  -e 's|(\./investigating-strange-behavior/)|(./investigating-strange-behavior/)|g' \
  {} \;

# Fix mounting-remote-file-systems links
find "$INSTALL_DIR/content/en" -path "*/administration-guide/managing-network-configuration/mounting-a-network-file-system/_index.md" -exec sed -i \
  -e 's|(\.\./\.\./user-guide/|(../../../user-guide/|g' \
  {} \;

# Fix cloud-images references
find "$INSTALL_DIR/content/en" -path "*/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2/_index.md" -exec sed -i \
  -e 's|(\./installation-guide/|(../../../installation-guide/|g' \
  {} \;

# Fix internal links to remove double paths in absolute URLs
echo "Fixing internal links to remove double paths..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i 's|/docs-v3/docs-v3/|/docs-v3/|g' {} \;
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i 's|/docs-v4/docs-v4/|/docs-v4/|g' {} \;
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i 's|/docs-v5/docs-v5/|/docs-v5/|g' {} \;

# Patch docs-v* _index.md to set type: docs for sidebar and menu on main pages
for ver in docs-v3 docs-v4 docs-v5; do
  if [ -f "$INSTALL_DIR/content/en/$ver/_index.md" ]; then
    sed -i '/^type\s*:/d' "$INSTALL_DIR/content/en/$ver/_index.md"
    sed -i '1s/^---$/---\ntype: docs/' "$INSTALL_DIR/content/en/$ver/_index.md"
  fi
done



cd "$INSTALL_DIR"

# Fix deprecated disableKinds in config.toml
sed -i 's/[Tt]axonomy[Tt]erm/taxonomy/g' $INSTALL_DIR/config.toml

# Fix deprecated languages.en.description
if grep -q "^description.*=" $INSTALL_DIR/config.toml; then
  DESCRIPTION=$(grep "^description.*=" $INSTALL_DIR/config.toml | sed 's/description *= *"\(.*\)"/\1/')
  sed -i '/^description.*=/d' $INSTALL_DIR/config.toml
  if ! grep -q "\[languages.en.params\]" config.toml; then
    echo -e "\n[languages.en.params]\ndescription = \"$DESCRIPTION\"" >> $INSTALL_DIR/config.toml
  else
    sed -i "/\[languages.en.params\]/a description = \"$DESCRIPTION\"" $INSTALL_DIR/config.toml
  fi
fi

# Robust fix for deprecated .Site.GoogleAnalytics (removed entirely from Hugo ~0.94+; accessing it now panics)
# We replace it with the modern safe map access .Site.Params.googleAnalytics everywhere.
# Since we have no GA ID, leaving the param unset makes it evaluate to "" / false → any conditional GA code is skipped safely.
echo "Applying robust patch for deprecated .Site.GoogleAnalytics → .Site.Params.googleAnalytics in ALL template files..."
find "$INSTALL_DIR" -type f \( -name "*.html" -o -name "*.tmpl" \) -print0 | xargs -0 sed -i 's|\.Site\.GoogleAnalytics|.Site.Params.googleAnalytics|g'

# Remove existing googleAnalytics and uglyURLs
sed -i '/^googleAnalytics/d' $INSTALL_DIR/config.toml
sed -i '/^uglyURLs/d' $INSTALL_DIR/config.toml

# Add uglyURLs to config.toml
echo -e "\nuglyURLs = false" >> config.toml

# Add googleAnalytics to config.toml if not present (for completeness, even if template is patched)
if ! grep -q "^googleAnalytics" config.toml; then
  echo "googleAnalytics = \"G-XXXXXXXXXX\"" >> config.toml  # Replace with actual ID or leave placeholder
fi

# Fix malformed external links caused by extra '(' immediately after ']' (common copy-paste typo)
echo "Fixing malformed external links with extra '('..."
find "$INSTALL_DIR/content" -type f -name "*.md" -exec sed -i 's/]\((https\?:\/\/\)/](https?:\/\//g' {} \;
# Specific fix for the Vagrant link (in case the general one needs help on that line)
sed -i 's/]\((https:\/\/app\.vagrantup\.com\/vmware\/boxes\/photon\))/](https:\/\/app\.vagrantup\.com\/vmware\/boxes\/photon\))/g' "$INSTALL_DIR/content/en/docs-v5/user-guide/packer-examples/_index.md" 2>/dev/null || true

# Install correct, fully safe render-link.html override (fixes BOTH urls.Parse errors AND the ".Title in type string" error forever)
echo "Installing bullet-proof safe render-link.html override..."
mkdir -p "$INSTALL_DIR/layouts/_default/_markup"
cat > "$INSTALL_DIR/layouts/_default/_markup/render-link.html" <<'EOF_RENDERLINK'
<a href="{{ .Destination | safeURL }}"
   {{ with .Title }} title="{{ . | safeHTMLAttr }}"{{ end }}
   {{ if or (strings.HasPrefix .Destination "http://") (strings.HasPrefix .Destination "https://") }} target="_blank" rel="noopener noreferrer"{{ end }}>
  {{ .Text | safeHTML }}
</a>
EOF_RENDERLINK

# Fix render-link.html to use safeURL
if [ -f $INSTALL_DIR/layouts/partials/render-link.html ]; then
  sed -i 's/urls\.Parse \([^ ]*\)/\1 | safeURL/g' $INSTALL_DIR/layouts/partials/render-link.html
fi

# Patch render-link.html to fix parse errors
if [ -f $INSTALL_DIR/layouts/_default/_markup/render-link.html ]; then
  sed -i 's/urls\.Parse \([^ ]*\)/\1 | safeURL/g' $INSTALL_DIR/layouts/_default/_markup/render-link.html
fi

# Patch head.html to fix deprecated Google Analytics template
HEAD_FILE="$INSTALL_DIR/layouts/partials/head.html"
if [ -f "$HEAD_FILE" ]; then
  echo "Patching head.html for Google Analytics template..."
  sed -i 's/_internal\/google_analytics_async.html/_internal\/google_analytics.html/g' "$HEAD_FILE"
fi
# Also check in theme if not in layouts
THEME_HEAD="$INSTALL_DIR/themes/photon-theme/layouts/partials/head.html"
if [ -f "$THEME_HEAD" ] && [ ! -f "$HEAD_FILE" ]; then
  sed -i 's/_internal\/google_analytics_async.html/_internal\/google_analytics.html/g' "$THEME_HEAD"
fi

# Patch head-css.html to fix deprecated .Site.IsServer
HEAD_CSS_FILE="$INSTALL_DIR/themes/photon-theme/layouts/partials/head-css.html"
if [ -f "$HEAD_CSS_FILE" ]; then
  echo "Patching head-css.html for .Site.IsServer..."
  sed -i 's/\.Site\.IsServer/hugo.IsServer/g' "$HEAD_CSS_FILE"
fi
# Also check in layouts if not in theme
LAYOUT_HEAD_CSS="$INSTALL_DIR/layouts/partials/head-css.html"
if [ -f "$LAYOUT_HEAD_CSS" ] && [ ! -f "$HEAD_CSS_FILE" ]; then
  sed -i 's/\.Site\.IsServer/hugo.IsServer/g' "$LAYOUT_HEAD_CSS"
fi

# Fix for deprecated .Site.IsServer (replaced by hugo.IsServer in recent Hugo versions)
echo "Patching deprecated .Site.IsServer → hugo.IsServer in all template files..."
find "$INSTALL_DIR" -type f \( -name "*.html" -o -name "*.tmpl" \) -print0 | xargs -0 sed -i 's|\.Site\.IsServer|hugo.IsServer|g'

# Remove existing duplicated permalinks
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i '/^permalink: \/docs-v[3-5]\/docs-v[3-5]\//d' {} \;

# Ensure single [permalinks] section and set paths using :sections to handle hierarchy without duplicates
if grep -q "\[permalinks\]" $INSTALL_DIR/config.toml; then
  sed -i '/\[permalinks\]/,/^[\[a-zA-Z]\|^$/d' $INSTALL_DIR/config.toml
fi
cat >> $INSTALL_DIR/config.toml <<EOF_PERMALINKS

[permalinks]
blog = "/blog/:year/:month/:day/:slug/"
docs-v3 = "/:sections/:slug/"
docs-v4 = "/:sections/:slug/"
docs-v5 = "/:sections/:slug/"
EOF_PERMALINKS

# Verify no duplicate [permalinks]
if [ $(grep -c "\[permalinks\]" $INSTALL_DIR/config.toml) -gt 1 ]; then
  echo "Error: Multiple [permalinks] sections found in config.toml."
  exit 1
fi

# Add search outputs to config.toml for Lunr index generation
if ! grep -q "\[outputs\]" $INSTALL_DIR/config.toml; then
  cat >> $INSTALL_DIR/config.toml <<EOF_OUTPUTS

[outputs]
home = ["HTML", "RSS", "JSON"]
EOF_OUTPUTS
else
  sed -i '/\[outputs\]/,/^$/s/home = \["HTML", "RSS"\]/home = ["HTML", "RSS", "JSON"]/' $INSTALL_DIR/config.toml
fi

echo "====================================================="
echo "Markdown link fixes complete!"
echo "====================================================="


# Create search index template for Hugo
mkdir -p $INSTALL_DIR/layouts/_default
cat > $INSTALL_DIR/layouts/_default/index.json <<'EOF_SEARCH_INDEX'
{{- $index := slice -}}
{{- range where .Site.RegularPages "Type" "ne" "json" -}}
  {{- $item := dict "title" .Title "tags" (.Params.tags | default slice) "contents" (.Plain | plainify) "permalink" .Permalink "summary" (.Summary | plainify) -}}
  {{- $index = $index | append $item -}}
{{- end -}}
{{- $index | jsonify -}}
EOF_SEARCH_INDEX

# === CONSOLE BACKEND SETUP ===
# Create backend/terminal-server.js
mkdir -p $INSTALL_DIR/backend
cat > $INSTALL_DIR/backend/terminal-server.js <<'EOF_BACKENDTERMINALSERVER'
const WebSocket = require('ws');
const Docker = require('dockerode');
const docker = new Docker();

const sessions = new Map();
const TIMEOUT = 5 * 60 * 1000; // 5 min

function resetTimeout(session) {
  clearTimeout(session.timeout);
  session.timeout = setTimeout(() => {
    if (session.ws.length === 0) {
      session.container.kill();
      sessions.delete(session.id);
    }
  }, TIMEOUT);
}

const wss = new WebSocket.Server({ port: 3000 });
console.log('Terminal server on port 3000');

wss.on('connection', async (ws, req) => {
  const urlParams = new URLSearchParams(req.url.slice(4));
  const sessionId = urlParams.get('session');
  let session = sessions.get(sessionId);
  let isNewSession = false;

  if (!session) {
    isNewSession = true;
    session = {
      id: `session-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      ws: [],
      container: null,
      lastActivity: Date.now(),
      timeout: null
    };
    sessions.set(session.id, session);

    try {
      const container = await docker.createContainer({
        Image: 'photon-builder',
        Tty: true,
        AttachStdin: true,
        AttachStdout: true,
        AttachStderr: true,
        Env: ['TERM=xterm-256color'],
        HostConfig: { Memory: 536870912, NanoCpus: 1000000000 } // 512MB, 1 CPU
      });
      session.container = container;
      await container.start();

      // Create tmux session with default shell and explicit TERM
      const execNew = await container.exec({
        Cmd: ['tmux', 'new-session', '-d', '-s', session.id, '-e', 'TERM=xterm-256color'],
        Env: ['TERM=xterm-256color'],
        AttachStdin: false,
        AttachStdout: false,
        AttachStderr: false,
      });
      await execNew.start();

      // Wait briefly for session to initialize
      await new Promise(resolve => setTimeout(resolve, 500));

      // Disable status bar to prevent leak into stream
      try {
        const execStatusOff = await container.exec({
          Cmd: ['tmux', 'set-option', '-gq', 'status', 'off'],
          AttachStdin: false,
          AttachStdout: false,
          AttachStderr: false,
        });
        await execStatusOff.start({ Detach: true });

        const execWindowStatusOff = await container.exec({
          Cmd: ['tmux', 'set-window-option', '-gq', '-t', session.id, 'status', 'off'],
          AttachStdin: false,
          AttachStdout: false,
          AttachStderr: false,
        });
        await execWindowStatusOff.start({ Detach: true });
      } catch (err) {
        console.log('Failed to disable tmux status bar:', err.message);
      }
    } catch (err) {
      ws.send(`Error: ${err.message}`);
      ws.close();
      return;
    }
  }

  try {
    // Attach to tmux session
    const execAttach = await session.container.exec({
      Cmd: ['tmux', 'attach-session', '-t', session.id],
      Env: ['TERM=xterm-256color'],
      AttachStdin: true,
      AttachStdout: true,
      AttachStderr: true,
      Tty: true
    });
    const stream = await execAttach.start({ hijack: true, stdin: true });
    session.ws.push({ ws, stream });

    stream.on('data', (chunk) => {
      const data = chunk.toString();
      session.ws.forEach(client => {
        if (client.ws.readyState === WebSocket.OPEN) client.ws.send(data);
      });
    });

    ws.on('message', (message) => {
      stream.write(message);
      session.lastActivity = Date.now();
      resetTimeout(session);
    });

    ws.on('close', () => {
      const client = session.ws.find(client => client.ws === ws);
      if (client) {
        client.stream.write('\x02d');
        setTimeout(() => {
          client.stream.end();
        }, 100); // Delay to allow detach to process
        session.ws = session.ws.filter(c => c !== client);
      }
      if (session.ws.length === 0) {
        resetTimeout(session);
      }
    });

    if (isNewSession) {
      ws.send(JSON.stringify({ type: 'session', id: session.id }));
    } else {
      // Send current pane content for re-attach (clean from top, no status)
      const execCapture = await session.container.exec({
        Cmd: ['tmux', 'capture-pane', '-t', session.id, '-p', '-S', '-'],
        Env: ['TERM=xterm-256color'],
        AttachStdout: true,
        AttachStderr: false
      });
      const captureStream = await execCapture.start({ hijack: false });
      let buffer = '';
      captureStream.on('data', chunk => buffer += chunk.toString());
      captureStream.on('end', () => {
        ws.send(buffer + '\r\n');  // Ensure clean line after buffer
      });
    }
    resetTimeout(session);
  } catch (err) {
    ws.send(`Error: ${err.message}`);
    ws.close();
  }
});
EOF_BACKENDTERMINALSERVER

# Install backend dependencies
cd $INSTALL_DIR/backend
npm init -y 1>/dev/null 2>&1
npm install ws dockerode 1>/dev/null 2>&1
cd $INSTALL_DIR

nohup node $INSTALL_DIR/backend/terminal-server.js > /var/log/terminal-server.log 2>&1 &

# Build console image
cat > $INSTALL_DIR/backend/Dockerfile <<EOF_DOCKERFILE
FROM photon:5.0
RUN sed -i 's/packages.vmware.com/packages-prod.broadcom.com/g' /etc/yum.repos.d/*
RUN tdnf install -y git build-essential tmux ncurses-terminfo
RUN mkdir -p /workspace/photon
WORKDIR /workspace/photon
CMD ["/bin/bash"]
EOF_DOCKERFILE
cd $INSTALL_DIR/backend/
docker build -t photon-builder .

# Download xterm.js and addons
echo "Downloading xterm.js and addons to static/js/xterm..."
mkdir -p $INSTALL_DIR/static/js/xterm
curl -o $INSTALL_DIR/static/js/xterm/xterm.js https://cdn.jsdelivr.net/npm/xterm@4.19.0/lib/xterm.js
curl -o $INSTALL_DIR/static/js/xterm/xterm.css https://cdn.jsdelivr.net/npm/xterm@4.19.0/css/xterm.css
curl -o $INSTALL_DIR/static/js/xterm/xterm-addon-fit.js https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.5.0/lib/xterm-addon-fit.js

# Create console.js external file
mkdir -p $INSTALL_DIR/static/js
cat > $INSTALL_DIR/static/js/console.js <<'EOF_JS'
let term = null;
let socket = null;
let isOpen = false;
let fitAddon = null;
let currentInput = '';

function toggleConsole() {
  const win = document.getElementById('console-window');
  if (isOpen) {
    win.style.display = 'none';
    if (socket) socket.close();
    if (term) term.dispose();
    term = null;
    fitAddon = null;
    isOpen = false;
    // Removed: localStorage.setItem('consoleOpen', 'false');
  } else {
    win.style.display = 'block';
    initConsole();
    isOpen = true;
    // Removed: localStorage.setItem('consoleOpen', 'true');
    if (localStorage.getItem('consoleWelcomeShown') !== 'true') {
      showWelcomeOverlay();
      localStorage.setItem('consoleWelcomeShown', 'true');
    }
  }
}

function initConsole() {
  if (!term) {
    term = new Terminal({ theme: { background: "#1e1e1e" } });
    fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);
    term.open(document.getElementById('terminal'));
    fitAddon.fit();
    term.focus();
    term.onData((data) => {
      if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(data);
      }
      updateCurrentInput(data);
    });
  }
  connectWS();
}

function updateCurrentInput(data) {
  if (data.length === 1 && data.charCodeAt(0) >= 32 && data.charCodeAt(0) <= 126) {
    currentInput += data;
  } else if (data === '\b') {
    if (currentInput.length > 0) currentInput = currentInput.slice(0, -1);
  } else if (data === '\r') {
    currentInput = '';
  } // ignore others like arrows for simplicity
}

function connectWS() {
  if (socket && socket.readyState !== WebSocket.CLOSED) socket.close();
  const sessionID = localStorage.getItem('consoleSessionID');
  const wsUrl = sessionID ? `wss://${location.host}/ws/?session=${sessionID}` : `wss://${location.host}/ws/`;
  socket = new WebSocket(wsUrl);
  socket.onopen = () => {
    currentInput = localStorage.getItem('consoleCurrentInput') || '';
    if (currentInput) {
      socket.send(currentInput);
    }
  };
  socket.onmessage = (event) => {
    try {
      const json = JSON.parse(event.data);
      if (json.type === 'session') {
        localStorage.setItem('consoleSessionID', json.id);
        return;
      }
    } catch (e) {}
    term.write(event.data);
  };
  socket.onclose = () => { term.writeln('Connection closed.'); };
  socket.onerror = () => { term.writeln('Error: Could not connect to server.'); };
}

function resetConsole() {
  if (term) term.reset();
}

function reconnectConsole() {
  connectWS();
}

function showWelcomeOverlay() {
  const overlay = document.createElement('div');
  overlay.id = 'console-welcome';
  overlay.style.position = 'absolute';
  overlay.style.top = '50%';
  overlay.style.left = '50%';
  overlay.style.transform = 'translate(-50%, -50%)';
  overlay.style.background = '#fff';
  overlay.style.padding = '20px';
  overlay.style.borderRadius = '5px';
  overlay.style.boxShadow = '0 0 10px rgba(0,0,0,0.5)';
  overlay.style.zIndex = '1001';
  overlay.innerHTML = `
    <h3>Welcome to Photon OS Console</h3>
    <p>This is an embedded console for Photon OS documentation.</p>
    <p>Start typing commands below.</p>
    <button onclick="this.parentElement.remove()">OK</button>
  `;
  document.getElementById('console-window').appendChild(overlay);
}

// Save currentInput on unload
window.addEventListener('beforeunload', () => {
  localStorage.setItem('consoleCurrentInput', currentInput);
});

// Resize handling
const win = document.getElementById('console-window');
win.addEventListener('resize', () => {
  localStorage.setItem('consoleHeight', win.style.height);
  if (fitAddon) fitAddon.fit();
});

// Resize observer for terminal
new ResizeObserver(() => {
  if (term && isOpen && fitAddon) {
    fitAddon.fit();
  }
}).observe(document.getElementById('terminal'));

// Persist on load (height only, no auto-open)
window.addEventListener('load', () => {
  const win = document.getElementById('console-window');
  win.style.height = localStorage.getItem('consoleHeight') || '300px';
  // Removed auto-toggle: No if (localStorage.getItem('consoleOpen') === 'true') { toggleConsole(); }
});
EOF_JS

# === SEARCH OVERLAY SETUP ===
echo "Setting up search overlay with Lunr.js..."

mkdir -p $INSTALL_DIR/static/js
wget -O $INSTALL_DIR/static/js/lunr.min.js https://unpkg.com/lunr@2.3.9/lunr.min.js || echo "Warning: Failed to download Lunr.js."

mkdir -p $INSTALL_DIR/static/css
cat > $INSTALL_DIR/static/css/search-overlay.css <<'EOF_SEARCH_CSS'
/* Search Button removed - using original Docsy search input */

/* Overlay */
.search-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  z-index: 9999;
  opacity: 0;
  visibility: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: opacity 0.3s ease, visibility 0.3s ease;
}

.search-overlay.active {
  opacity: 1;
  visibility: visible;
}

/* Search Panel */
.search-panel {
  background: rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 12px;
  padding: 2rem;
  max-width: 600px;
  width: 90%;
  max-height: 80vh;
  overflow-y: auto;
  position: relative;
  box-shadow: 0 20px 40px rgba(0,0,0,0.1);
}

.search-close {
  position: absolute;
  top: 1rem;
  right: 1rem;
  background: none;
  border: none;
  color: inherit;
  cursor: pointer;
  padding: 0.5rem;
  border-radius: 50%;
  transition: background-color 0.2s;
}

#search-input {
  width: 100%;
  padding: 1rem;
  border: none;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.2);
  color: inherit;
  font-size: 1.2rem;
  outline: none;
  backdrop-filter: blur(10px);
}

#search-input::placeholder {
  color: rgba(255, 255, 255, 0.7);
}

.search-results {
  margin-top: 1rem;
  color: inherit;
}

.search-results ul {
  list-style: none;
  padding: 0;
}

.search-results li {
  margin-bottom: 1rem;
}

.search-results a {
  color: inherit;
  text-decoration: none;
}

.search-results a:hover {
  text-decoration: underline;
}
EOF_SEARCH_CSS

cat > $INSTALL_DIR/static/js/search.js <<'EOF_SEARCH_JS'
let searchIndex = null;
let documents = {};

document.addEventListener('DOMContentLoaded', function() {
  const overlay = document.getElementById('search-overlay');
  const close = document.getElementById('search-close');
  const input = document.getElementById('search-input');
  const results = document.getElementById('search-results');

  // Load search index
  async function loadIndex() {
    try {
      const response = await fetch('/index.json');
      const pages = await response.json();
      documents = {};
      pages.forEach(doc => documents[doc.permalink] = doc);

      if (typeof lunr !== 'undefined') {
        searchIndex = lunr(function () {
          this.ref('permalink');
          this.field('title', { boost: 10 });
          this.field('tags', { boost: 5 });
          this.field('contents');
          this.field('summary', { boost: 2 });
          pages.forEach(page => this.add(page));
        });
      }
    } catch (e) {
      console.error('Search index load failed', e);
    }
  }

  loadIndex();

  // Open / close
  function openSearch() {
    overlay.classList.add('active');
    document.body.classList.add('search-open');
    input.focus();
  }

  function closeSearch() {
    overlay.classList.remove('active');
    document.body.classList.remove('search-open');
    input.value = '';
    results.innerHTML = '';
    if (originalSearchInput) originalSearchInput.value = '';
  }

  if (close) close.addEventListener('click', closeSearch);
  overlay.addEventListener('click', function(e) {
    if (e.target === overlay) closeSearch();
  });

  // Search functionality
  input.addEventListener('input', function(e) {
    const query = e.target.value.trim();
    if (originalSearchInput) originalSearchInput.value = query;
    if (query.length < 2) {
      results.innerHTML = '';
      return;
    }
    if (!searchIndex) {
      results.innerHTML = '<p>Loading search...</p>';
      return;
    }
    const searchResults = searchIndex.search(query);
    let html = '<ul>';
    searchResults.forEach(r => {
      const doc = documents[r.ref];
      if (doc) {
        html += `<li><a href="${doc.permalink}">${doc.title}</a><br><small>${doc.summary || ''}</small></li>`;
      }
    });
    html += '</ul>';
    if (searchResults.length === 0) {
      html = '<p>No results found.</p>';
    }
    results.innerHTML = html;
  });

  // Close on Escape key
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && overlay.classList.contains('active')) {
      closeSearch();
    }
  });

  // === Hook to original Docsy sidebar search input ===
  const originalSearchInput = document.querySelector('input[placeholder*="Search this site"]');
  if (originalSearchInput) {
    // Hide any original results dropdowns
    ['.td-search-results', '.search-results', '#search-results', '#results'].forEach(sel => {
      const res = document.querySelector(sel);
      if (res) res.style.display = 'none';
    });

    // Open overlay on focus
    originalSearchInput.addEventListener('focus', function() {
      openSearch();
      input.value = this.value || '';
      input.dispatchEvent(new Event('input'));
    });

    // Sync typing from original to overlay
    originalSearchInput.addEventListener('input', function(e) {
      input.value = e.target.value;
      input.dispatchEvent(new Event('input'));
    });
  }

  // Sync typing from overlay to original
  if (input && originalSearchInput) {
    input.addEventListener('input', function(e) {
      originalSearchInput.value = e.target.value;
    });
  }
});
EOF_SEARCH_JS

# Add console and search window HTML/JS to body-end partial
mkdir -p $INSTALL_DIR/layouts/partials/hooks
cat > $INSTALL_DIR/layouts/partials/hooks/body-end.html <<'EOF_BODY_END'
<div id="console-window" style="display: none; position: fixed; bottom: 0; left: 0; right: 0; height: 300px; background: #fff; border-top: 1px solid #000; z-index: 1000; resize: vertical; overflow: hidden; box-shadow: 0 -2px 10px rgba(0,0,0,0.2);">
  <div id="console-header" style="background: #ddd; padding: 5px; display: flex; justify-content: space-between; align-items: center;">
    <span>Photon OS Console</span>
    <div>
      <button onclick="resetConsole()">Reset</button>
      <button onclick="reconnectConsole()">Reconnect</button>
      <button onclick="toggleConsole()">Close</button>
    </div>
  </div>
  <div id="terminal" style="width: 100%; height: calc(100% - 30px); background: #1e1e1e;"></div>
</div>

<!-- Search Overlay HTML -->
<div id="search-overlay" class="search-overlay" role="dialog" aria-modal="true" aria-labelledby="search-input">
  <div class="search-panel">
    <button id="search-close" class="search-close" aria-label="Close search">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor">
        <line x1="18" y1="6" x2="6" y2="18"></line>
        <line x1="6" y1="6" x2="18" y2="18"></line>
      </svg>
    </button>
    <input type="search" id="search-input" placeholder="Search..." autofocus>
    <div id="search-results" class="search-results">
      <!-- Results will be populated by JS -->
    </div>
  </div>
</div>

<link rel="stylesheet" href="/css/search-overlay.css">
<script src="/js/lunr.min.js"></script>
<link rel="stylesheet" href="/js/xterm/xterm.css">
<script src="/js/xterm/xterm.js"></script>
<script src="/js/xterm/xterm-addon-fit.js"></script>
<script src="/js/console.js"></script>
<script src="/js/search.js"></script>
EOF_BODY_END

# Patch navbar to add console icon in menu
NAVBAR_FILE="$INSTALL_DIR/themes/photon-theme/layouts/partials/navbar.html"
if [ -f "$NAVBAR_FILE" ]; then
  sed -i '/<\/ul>/i <li class="nav-item"><a class="nav-link" href="#" onclick="toggleConsole(); return false;" title="Console"><i class="fas fa-terminal"></i></a></li>' "$NAVBAR_FILE"
else
  echo "Warning: navbar.html not found. Console not added."
fi
# === END OF CONSOLE SETUP ===


# Set up cron job for Docker cleanup
echo "Setting up cron job for Docker container cleanup..."
mkdir -p /etc/cron.d
cat > /etc/cron.d/photon-cleanup <<EOF
*/5 * * * * root docker container prune -f
EOF
chmod 644 /etc/cron.d/photon-cleanup

# Build site with Hugo
echo "Building site with Hugo..."
cd $INSTALL_DIR
set -o pipefail
/usr/local/bin/hugo --minify --baseURL "/" --logLevel debug --enableGitInfo -d public 2>&1 | tee $INSTALL_DIR/hugo_build.log
if [ $? -ne 0 ]; then
  echo "Hugo build failed. Check hugo_build.log."
  exit 1
fi

# Make site dir readable by nginx
mkdir -p "$SITE_DIR"
chown -R nginx:nginx "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"

# Check SELinux
if command -v getenforce &> /dev/null && [ "$(getenforce)" = "Enforcing" ]; then
  echo "Warning: SELinux is in Enforcing mode, which may cause permission issues."
  echo "To disable temporarily, run: setenforce 0"
  echo "To disable permanently, edit /etc/selinux/config and set SELINUX=disabled, then reboot."
fi

# Debug permissions
echo "Directory permissions for Nginx:"
ls -ld "$BASE_DIR" "$INSTALL_DIR" "$SITE_DIR"
ls -l "$SITE_DIR/index.html" || echo "index.html not found"

# Check site files
if [ -f "$SITE_DIR/index.html" ]; then
  echo "Build successful: index.html exists."
else
  echo "Error: Build failed - index.html not found in $SITE_DIR. Check hugo_build.log."
  exit 1
fi
echo "Site files present: $(ls -l $SITE_DIR | grep index.html)"


# Added: Patch quick-start-links index.html to fix orphaned links with correct absolute paths for all versions (POST-BUILD, STATIC FIX)
for ver in docs-v3 docs-v4 docs-v5; do
  QL_FILE="$SITE_DIR/$ver/quick-start-links/index.html"
  if [ -f "$QL_FILE" ]; then
    echo "Patching quick-start-links index.html for $ver to fix orphaned links..."
    sed -i 's|<a href=..\/..\/overview\/>Overview</a>|<a href=..\/overview\/>Overview</a>|g' $QL_FILE
    sed -i 's|<a href=..\/..\/installation-guide\/downloading-photon\/>Downloading Photon OS</a>|<a href=..\/installation-guide\/downloading-photon\/>Downloading Photon OS</a>|g' $QL_FILE
    sed -i 's|<a href=..\/..\/installation-guide\/building-images\/build-iso-from-source\/>Build an ISO from the source code for Photon OS</a>|<a href=..\/installation-guide\/building-images\/build-iso-from-source\/>Build an ISO from the source code for Photon OS</a>|g' $QL_FILE
  fi
done

# Debug content structure
echo "Content structure in content/en/:"
find "$INSTALL_DIR/content/en" -type f -name "_index.md"

# Analyze subpaths
echo "Generated subpaths in public/:"
find "$SITE_DIR" -type d

# Ensure Nginx conf.d directory exists
mkdir -p /etc/nginx/conf.d

# Remove default HTML
rm -rf /etc/nginx/html/* /usr/share/nginx/html/* /var/www/html/*

# Replace nginx.conf
cat > /etc/nginx/nginx.conf <<EOF_NGINX
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    keepalive_timeout 65;

    include /etc/nginx/conf.d/*.conf;
}
EOF_NGINX

# Set up self-signed cert
mkdir -p /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/selfsigned.crt ] || [ -f /etc/nginx/ssl/selfsigned.key ]; then
  echo "Generating self-signed certificate for ${IP_ADDRESS}..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt -subj "/CN=${IP_ADDRESS}"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to generate self-signed certificate."
    exit 1
  fi
  chmod 600 /etc/nginx/ssl/selfsigned.key /etc/nginx/ssl/selfsigned.crt
  chown nginx:nginx /etc/nginx/ssl/selfsigned.key /etc/nginx/ssl/selfsigned.crt
else
  echo "Self-signed certificate already exists, skipping generation."
fi

# Configure Nginx with WS proxy AND redirect rules
NGINX_CONF="/etc/nginx/conf.d/photon-site.conf"
echo "Configuring Nginx with redirect rules (overwriting if exists)"
cat > "${NGINX_CONF}" <<EOF_PHOTON
server {
    listen 0.0.0.0:80 default_server;
    server_name _;

    return 301 https://\$host\$request_uri;
}

server {
    listen 0.0.0.0:443 ssl default_server;
    server_name _;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    root $SITE_DIR;
    index index.html;

    # ========== REDIRECTS FOR BROKEN LINKS ==========
    
    # Typo fix: downloading-photon -> downloading-photon-os
    rewrite ^/docs-v3/installation-guide/downloading-photon/?\$ /docs-v3/installation-guide/downloading-photon-os/ permanent;
    rewrite ^/docs-v4/installation-guide/downloading-photon/?\$ /docs-v4/installation-guide/downloading-photon-os/ permanent;
    rewrite ^/docs-v5/installation-guide/downloading-photon/?\$ /docs-v5/installation-guide/downloading-photon-os/ permanent;
    rewrite ^/installation-guide/downloading-photon/?\$ /docs-v5/installation-guide/downloading-photon-os/ permanent;
    rewrite ^/downloading-photon/?\$ /docs-v5/installation-guide/downloading-photon-os/ permanent;
    
    # Missing version prefix redirects
    rewrite ^/overview/?\$ /docs-v5/overview/ permanent;
    rewrite ^/installation-guide/(.*)\$ /docs-v5/installation-guide/\$1 permanent;
    rewrite ^/administration-guide/(.*)\$ /docs-v5/administration-guide/\$1 permanent;
    rewrite ^/user-guide/(.*)\$ /docs-v5/user-guide/\$1 permanent;
    rewrite ^/troubleshooting-guide/(.*)\$ /docs-v5/troubleshooting-guide/\$1 permanent;
    rewrite ^/command-line-reference/(.*)\$ /docs-v5/command-line-reference/\$1 permanent;
    
    # Short-path redirects
    rewrite ^/deploying-a-containerized-application-in-photon-os/?\$ /docs-v5/installation-guide/deploying-a-containerized-application-in-photon-os/ permanent;
    rewrite ^/working-with-kickstart/?\$ /docs-v5/user-guide/working-with-kickstart/ permanent;
    rewrite ^/run-photon-on-gce/?\$ /docs-v5/installation-guide/run-photon-on-gce/ permanent;
    rewrite ^/run-photon-aws-ec2/?\$ /docs-v5/installation-guide/run-photon-aws-ec2/ permanent;
    
    # Image path consolidation
    rewrite ^/docs-v3/(.*)images/(.+)\$ /docs-v3/images/\$2 permanent;
    rewrite ^/docs-v4/(.*)images/(.+)\$ /docs-v4/images/\$2 permanent;
    rewrite ^/docs-v5/(.*)images/(.+)\$ /docs-v5/images/\$2 permanent;
    rewrite ^/docs/images/(.+)\$ /docs-v4/images/\$1 permanent;
    
    # Nested printview redirects
    rewrite ^/printview/docs-v3/(.*)\$ /docs-v3/\$1 permanent;
    rewrite ^/printview/docs-v4/(.*)\$ /docs-v4/\$1 permanent;
    rewrite ^/printview/docs-v5/(.*)\$ /docs-v5/\$1 permanent;
    rewrite ^/printview/(.*)\$ /docs-v5/\$1 permanent;
    
    # Legacy HTML .md extension removal
    rewrite ^(/assets/files/html/.*)\\.md\$ \$1 permanent;
    
    # ========== END REDIRECTS ==========

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /ws/ {
        proxy_pass http://localhost:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    error_log /var/log/nginx/photon-site-error.log warn;
    access_log /var/log/nginx/photon-site-access.log main;
}
EOF_PHOTON

# Remove default Nginx configs
rm -f /etc/nginx/conf.d/default.conf /etc/nginx/default.d/*.conf /etc/nginx/sites-enabled/default /etc/nginx/nginx.conf.bak

# List Nginx configs
echo "Nginx configs present:"
ls -l /etc/nginx/ /etc/nginx/conf.d/

# Test and restart Nginx
nginx -t
if [ $? -ne 0 ]; then
  echo "Nginx config test failed."
  exit 1
fi
systemctl restart nginx
if [ $? -ne 0 ]; then
  echo "Nginx restart failed. Check /var/log/nginx/error.log and /var/log/nginx/photon-site-error.log."
  exit 1
fi

# Enable Nginx on boot
systemctl enable nginx

# Open firewall ports
mkdir -p /etc/systemd/scripts
if ! iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 80 -j ACCEPT
fi
if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 443 -j ACCEPT
fi
iptables-save > /etc/systemd/scripts/ip4save

# Verify build and access
if [ -f "$SITE_DIR/index.html" ]; then
  echo "Build successful: index.html exists."
	for subdir in blog docs-v3 docs-v4 docs-v5; do
	  if [ -d "$SITE_DIR/$subdir" ] && [ -f "$SITE_DIR/$subdir/index.html" ]; then
		echo "Subpath /$subdir/ found with index.html."
	  else
		echo "Warning: Subpath /$subdir/ missing or incomplete. Check $SITE_DIR/$subdir/ and hugo_build.log."
		exit 1
	  fi
	done  
else
  echo "Error: Build failed - index.html not found in $SITE_DIR. Check hugo_build.log."
  exit 1
fi


# Verify search index generated
if [ -f "$SITE_DIR/index.json" ]; then
  echo "Search index generated successfully."
else
  echo "Warning: Search index not generated. Check Hugo build logs."
fi

echo "Installation complete! Access the Photon site at https://${IP_ADDRESS}/ (HTTP redirects to HTTPS)."
#!/bin/bash

# Usage: sudo ./migrator.sh
# All-in-one migration script for moving the Photon OS documentation web app from Hugo to Docusaurus 3.9.2 on Photon OS.
# Assumes Photon OS (uses tdnf for packages).
# Idempotent: Checks for existing installations and updates/resets as needed.
# Requires root for tdnf, Nginx, and firewall.
# Enforces website on port 8080 (HTTP) and 8443 (HTTPS) via Nginx; opens ports 8080/8443 in iptables.
# Migrates content, sets up versioning, configures navbar/footer, builds site, sets up Nginx with HTTPS.
# Fixes: Handles Broadcom branding, commit info in footer, GA4 placeholder, correct prism-react-renderer theme imports (bundled in v2.x).
# Note: Self-signed cert will cause browser warnings; replace with real cert for production.
# For subpath hosting, modify baseUrl in docusaurus.config.js and Nginx alias.
# Modified: Added archiveBasePath: null to blog options to disable archive page generation, fixing build error from null date in posts.
# Modified: Added feedOptions: { type: null } to blog options to disable feed generation, fixing invalid time value error in Atom feed creation.

BASE_DIR="/var/www"
INSTALL_DIR="$BASE_DIR/photon-site-docusaurus"
SITE_DIR="$INSTALL_DIR/build"  # Where built static files go
DOCUSAURUS_VERSION="3.9.2"
TMP_REPO="/tmp/photon-hugo"
MAX_RETRIES=3

# Dynamically retrieve DHCP IP address
tdnf install -y iproute2
IP_ADDRESS=$(ip addr show | grep -oP 'inet \K[\d.]+(?=/)' | grep -v '127.0.0.1' | head -n 1)
if [ -z "$IP_ADDRESS" ]; then
  IP_ADDRESS=$(hostname -I | awk '{print $1}' | grep -v '127.0.0.1')
fi
if [ -z "$IP_ADDRESS" ]; then
  IP_ADDRESS="localhost"
  echo "Warning: Could not detect DHCP IP. Using 'localhost' for certificate. Set IP manually if needed."
fi
echo "Detected IP address: $IP_ADDRESS"

# Install dependencies if not present
tdnf install -y wget curl nginx tar iptables nodejs openssl git awk

# Clean up log files before starting
echo "Cleaning up log files..."
truncate -s 0 /var/log/nginx/error.log 2>/dev/null || rm -f /var/log/nginx/error.log
truncate -s 0 /var/log/nginx/photon-site-error.log 2>/dev/null || rm -f /var/log/nginx/photon-site-error.log
rm -f "$INSTALL_DIR/build.log" "$INSTALL_DIR/npm_install.log"

# Clone repo to tmp for content migration
if [ -d "$TMP_REPO" ]; then
  rm -rf "$TMP_REPO"
fi
echo "Cloning repo for content migration"
git clone --branch photon-hugo --single-branch https://github.com/vmware/photon.git "$TMP_REPO"
cd "$TMP_REPO"

# Get commit details
COMMIT_HASH=$(git rev-parse HEAD)
COMMIT_ABBREV=$(git log -1 --format=%h)
# Escape special characters in commit message for JavaScript/HTML compatibility
COMMIT_MESSAGE=$(git log -1 --format=%s | sed "s/'/\\\\'/g" | sed 's/"/\\"/g')
COMMIT_DATE=$(git log -1 --format=%cd --date=format:'%B %-d, %Y')
echo "Checked out commit: $COMMIT_HASH"
echo "Commit date: $COMMIT_DATE"
echo "Commit message: $COMMIT_MESSAGE"
echo "Abbreviated hash: $COMMIT_ABBREV"

# Download Broadcom logo if not in static
mkdir -p "$TMP_REPO/static/img"
if [ ! -f "$TMP_REPO/static/img/broadcom-logo.png" ]; then
  wget -O "$TMP_REPO/static/img/broadcom-logo.png" "https://www.broadcom.com/img/broadcom-logo.png"
fi

# Create or reset Docusaurus project
if [ -d "$INSTALL_DIR" ]; then
  echo "Deleting existing Docusaurus project"
  rm -rf "$INSTALL_DIR"
fi
echo "Creating Docusaurus project v${DOCUSAURUS_VERSION}"
npx create-docusaurus@${DOCUSAURUS_VERSION} "$INSTALL_DIR" classic --javascript --skip-install
cd "$INSTALL_DIR"

# Clear npm cache and node_modules, then install dependencies with retries
echo "Clearing npm cache and node_modules..."
npm cache clean --force > npm_install.log 2>&1
rm -rf node_modules package-lock.json
echo "Installing npm dependencies including prism-react-renderer@2.3.1..."
for ((i=1; i<=MAX_RETRIES; i++)); do
  echo "Attempt $i of $MAX_RETRIES..."
  npm install --legacy-peer-deps prism-react-renderer@2.3.1 @docusaurus/plugin-google-gtag >> npm_install.log 2>&1
  if [ $? -eq 0 ]; then
    break
  fi
  if [ $i -eq $MAX_RETRIES ]; then
    echo "Error: npm install failed after $MAX_RETRIES attempts. Check $INSTALL_DIR/npm_install.log."
    exit 1
  fi
  sleep 5
done

# Verify prism-react-renderer installation
if [ ! -d "node_modules/prism-react-renderer" ]; then
  echo "Error: prism-react-renderer not installed. Check $INSTALL_DIR/npm_install.log."
  exit 1
else
  echo "prism-react-renderer installed successfully."
  echo "Checking prism-react-renderer contents..." >> npm_install.log
  ls -lR node_modules/prism-react-renderer >> npm_install.log 2>&1
  echo "Checking package.json for prism-react-renderer..." >> npm_install.log
  cat node_modules/prism-react-renderer/package.json >> npm_install.log 2>&1
fi

# Enable globstar for recursive copy
shopt -s globstar

# Migrate static assets
rm -rf static/*
cp -r "$TMP_REPO/static/"* static/ 2>/dev/null || true
cp -r "$TMP_REPO/content/en/**/images/"* static/img/ 2>/dev/null || true
cp -r "$TMP_REPO/content/en/**/img/"* static/img/ 2>/dev/null || true

# Copy all image files recursively
find "$TMP_REPO" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.svg" -o -name "*.gif" \) -exec cp --no-clobber {} static/img/ \;

# Migrate blog
rm -rf blog/*
mkdir -p blog
cp -r "$TMP_REPO/content/en/blog/"* blog/ 2>/dev/null || true
rm -f blog/_index.md  # Remove Hugo's blog index (not a post; causes date=null in Docusaurus archive)
# Fix blog frontmatter dates if needed
find blog -type f -name "*.md" -exec sed -i 's/date: \([0-9-]\+\(T[0-9:+-]\+\)\?\)/date: "\1"/g' {} \;

# Ensure all blog posts have a date in frontmatter; derive from filename if missing
for file in $(find blog -type f -name "*.md"); do
  if [ -f "$file" ]; then
    if ! grep -q '^date:' "$file"; then
      base=$(basename "$file" .md)
      date_str=$(echo "$base" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
      if [ -z "$date_str" ]; then
        date_str="2020-01-01"
      fi
      if head -n 1 "$file" | grep -q '^---$'; then
        # Insert date after first ---
        sed -i "/^---$/a date: \"${date_str}\"" "$file"
      else
        # Add full frontmatter
        sed -i "1i ---" "$file"
        sed -i "2i date: \"${date_str}\""
        sed -i "3i ---"
      fi
    fi
  fi
done

# Validate and fix invalid dates in blog frontmatter
for file in $(find blog -type f -name "*.md"); do
  date_line=$(grep '^date:' "$file" | head -1)
  if [ -n "$date_line" ]; then
    date_str=$(echo "$date_line" | sed 's/date: *"\?//' | sed 's/"\?$//' | awk '{print $1}')
    if [ -z "$date_str" ] || ! date -d "$date_str" >/dev/null 2>&1; then
      sed -i "s/^date: .*/date: \"2020-01-01\"/g" "$file"
    fi
  fi
done

# Migrate docs with versioning (oldest first)
rm -rf docs/*
mkdir -p docs
# Version 3.0
cp -r "$TMP_REPO/content/en/docs-v3/"* docs/ 2>/dev/null || true
npx docusaurus docs:version 3.0
# Version 4.0
rm -rf docs/*
cp -r "$TMP_REPO/content/en/docs-v4/"* docs/ 2>/dev/null || true
npx docusaurus docs:version 4.0
# Version 5.0
rm -rf docs/*
cp -r "$TMP_REPO/content/en/docs-v5/"* docs/ 2>/dev/null || true
npx docusaurus docs:version 5.0

# Migrate home and other top-level pages
mkdir -p src/pages
if [ -f "$TMP_REPO/content/en/_index.md" ]; then
  cp "$TMP_REPO/content/en/_index.md" src/pages/index.md
  rm -f src/pages/index.js # Remove default index.js to avoid duplicate route
else
  echo "No home _index.md found; using default Docusaurus landing page."
fi
# Copy other potential pages (e.g., features.md, contribute.md)
find "$TMP_REPO/content/en" -maxdepth 1 -type f -name "*.md" -not -name "_index.md" -exec cp {} src/pages/ \;

# Fix links and frontmatter across all content
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|/docs-v[3-5]/|/docs/|g' {} \;  # Adjust versioned links
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/type: docs//g' {} \;  # Remove Hugo-specific
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/permalink: .*//g' {} \;  # Remove permalinks

# Fix typo in downloading photon link
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/downloading-photon\.md/downloading-photon-os.md/g' {} \;

# Fix specific broken links by using absolute paths
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/downloading-photon-os.md/\/docs\/downloading-photon-os/ig' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/upgrading-the-kernel-version-requires-grub-changes-for-aws-and-gce-images.md/\/docs\/upgrading-the-kernel-version-requires-grub-changes-for-aws-and-gce-images/ig' {} \;

# Fix broken images by adjusting paths
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|../../../images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|../../images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|../images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|./images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|/docs/images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|../../../docs/images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|../../docs/images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|./installation-guide/images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|installation-guide/images|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|installation-gui/img|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|do/img|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|/do/img|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|../../../do/img|/img|g' {} \;

# Additional image path fixes
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|../../img|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|\./\/img|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|\.\./\.\./\.\./\/img|/img|g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|//img|/img|g' {} \;

# Fix image path with .././img
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|.././img|/img|g' {} \;

# Fix MDX parsing issues: Replace <br> with \n to avoid HTML in tables
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/<br \/>/\n/g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/<br\/>/\n/g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/<br>/\n/g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/<br >/\n/g' {} \;

# Replace Hugo highlight shortcodes with Docusaurus fenced code blocks
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/{{\s*<\s*highlight\s*\(\w+\)\s*>}}/``` \1/g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/{{\s*<\s*/highlight\s*>}}/``` /g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/{{<\s*/endhighlight\s*>}} /```/g' {} \;

# Remove remaining Hugo shortcodes
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/{{<[^>]*>}}//g' {} \;

# Remove <!DOCTYPE lines case-insensitively
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i '/<!doctype/dI' {} \;

# Fix HTML comments to MDX comments
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/<!\--/{/* /g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/-->/ */}/g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/<!---/{/* /g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/--->/ */}/g' {} \;

# Escape < and > selectively, avoiding code blocks
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i -r 's/<([a-zA-Z0-9_-]+)/\&lt;\1/g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i -r 's/([a-zA-Z0-9_-]+)>/\1\&gt;/g' {} \;
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i -r 's|</([a-zA-Z0-9_-]+)>|\&lt;/\1\&gt;|g' {} \;

# Additional escape for < not followed by alphanumeric
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i -r 's/<([^a-zA-Z0-9_-])/\&lt;\1/g' {} \;

# Escape & to &amp; in all MD files
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/&/\&amp;/g' {} \;

# Selectively escape { and } outside of fenced code blocks to prevent Acorn errors
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec awk -i inplace 'BEGIN { in_code = 0 } /^```/ { in_code = !in_code; print; next } { if (in_code == 0) { gsub(/\{/, "\\{"); gsub(/\}/, "\\}") } print }' {} \;

# Add language to code blocks to prevent Acorn parsing errors
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i '/^```$/s/^```$/```text/' {} \;

# Add language to XML code block in adding-a-new-repository.md for all versions
for dir in docs versioned_docs/version-4.0 versioned_docs/version-3.0 versioned_docs/version-5.0; do
  file="$INSTALL_DIR/$dir/administration-guide/managing-packages-with-tdnf/adding-a-new-repository.md"
  if [ -f "$file" ]; then
    sed -i '/cat metalink/{n; s/```/```xml/}' "$file"
  fi
done

# Specific fix for here-doc in adding-a-new-repository.md
for dir in docs versioned_docs/version-3.0 versioned_docs/version-4.0 versioned_docs/version-5.0; do
  file="$INSTALL_DIR/$dir/administration-guide/managing-packages-with-tdnf/adding-a-new-repository.md"
  if [ -f "$file" ]; then
    sed -i '/cat > \/etc\/yum.repos.d\/apps.repo << "EOF"/i ```bash' "$file"
    sed -i '/EOF/a ```' "$file"
  fi
done

# Configure docusaurus.config.js with correct bundled theme imports
RANDOM_ID=$(cat /dev/urandom | tr -dc 'A-Z0-9' | fold -w 10 | head -n 1)
cat > docusaurus.config.js <<EOF
const { themes } = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Photon OS',
  tagline: 'A VMware By Broadcom backed Project',
  favicon: 'img/favicon.ico',
  url: 'https://${IP_ADDRESS}:8443',
  baseUrl: '/',
  organizationName: 'vmware',
  projectName: 'photon',
  onBrokenLinks: 'ignore',
  i18n: { defaultLocale: 'en', locales: ['en'] },
  plugins: [
    [
      '@docusaurus/plugin-google-gtag',
      {
        trackingID: 'G-${RANDOM_ID}',
        anonymizeIP: true,
      },
    ],
  ],
  presets: [
    ['classic', {
      docs: {
        sidebarPath: './sidebars.js',
        routeBasePath: '/docs',
        versions: { current: { label: '5.0' }, '4.0': { label: '4.0' }, '3.0': { label: '3.0' } },
        lastVersion: 'current',
      },
      blog: { showReadingTime: true, path: 'blog', onInlineAuthors: 'ignore', onUntruncatedBlogPosts: 'ignore', archiveBasePath: null, feedOptions: { type: null } },
      theme: { customCss: './src/css/custom.css' },
    }],
  ],
  themeConfig: {
    image: 'img/broadcom-logo.png',
    navbar: {
      title: 'Photon OS',
      logo: { alt: 'Broadcom Logo', src: 'img/broadcom-logo.png' },
      items: [
        { to: '/', label: 'Home', position: 'left' },
        { to: '/blog', label: 'Blog', position: 'left' },
        { type: 'docSidebar', sidebarId: 'tutorialSidebar', position: 'left', label: 'Docs' },
        { type: 'docsVersionDropdown', position: 'right' },
        { href: 'https://github.com/vmware/photon', label: 'GitHub', position: 'right' },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        { title: 'Community', items: [{ label: 'Broadcom Community', href: 'https://community.broadcom.com/tanzu/communities/tanzucommunityhomeblogs?CommunityKey=a70674e4-ccb6-46a3-ae94-7ecf16c06e24' }] },
        { title: 'More', items: [{ label: 'GitHub', href: 'https://github.com/vmware/photon' }, { label: 'Privacy Policy', href: 'https://www.broadcom.com/company/legal/privacy' }] },
      ],
      copyright: \`Last modified ${COMMIT_DATE}: <a href="https://github.com/vmware/photon/commit/${COMMIT_HASH}">${COMMIT_MESSAGE} (${COMMIT_ABBREV})</a> | A VMware By Broadcom backed Project\`,
    },
    prism: {
      theme: themes.github,
      darkTheme: themes.dracula,
    },
    colorMode: { defaultMode: 'light' },
    docs: { versionPersistence: 'localStorage' },
  },
  markdown: {
    mdx1Compat: {
      comments: true,
      admonitions: true,
      headingIds: true
    },
    hooks: {
      onBrokenMarkdownLinks: 'ignore',
      onBrokenMarkdownImages: 'ignore'
    }
  },
};
module.exports = config;
EOF
echo "Generated placeholder GA4 ID: G-${RANDOM_ID} (replace with real ID for production)"

# Build site
echo "Building site with Docusaurus..."
npm run build > build.log 2>&1
if [ $? -ne 0 ]; then
  echo "Build failed. Check $INSTALL_DIR/build.log and $INSTALL_DIR/npm_install.log."
  exit 1
fi

# Set permissions
chown -R nginx:nginx "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"

# Verify build
if [ -f "$SITE_DIR/index.html" ]; then
  echo "Build successful: index.html exists."
else
  echo "Error: Build failed - index.html not found."
  exit 1
fi
for subdir in blog docs; do
  if [ -d "$SITE_DIR/$subdir" ]; then
    echo "Subpath /$subdir/ found."
  else
    echo "Warning: Subpath /$subdir/ missing."
  fi
done

# Set up self-signed cert
mkdir -p /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/selfsigned.crt ] || [ ! -f /etc/nginx/ssl/selfsigned.key ]; then
  echo "Generating self-signed certificate for ${IP_ADDRESS}..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt -subj "/CN=${IP_ADDRESS}"
  chmod 600 /etc/nginx/ssl/selfsigned.*
  chown nginx:nginx /etc/nginx/ssl/selfsigned.*
fi

# Configure Nginx
mkdir -p /etc/nginx/conf.d
rm -rf /etc/nginx/html/* /usr/share/nginx/html/* /var/www/html/*
cat > /etc/nginx/nginx.conf <<EOF
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
EOF

NGINX_CONF="/etc/nginx/conf.d/photon-site.conf"
cat > "${NGINX_CONF}" <<EOF
server {
    listen 0.0.0.0:8080 default_server;
    server_name _;

    return 301 https://\$host:8443\$request_uri;
}

server {
    listen 0.0.0.0:8443 ssl default_server;
    server_name _;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    root $SITE_DIR;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    error_log /var/log/nginx/photon-site-error.log warn;
    access_log /var/log/nginx/photon-site-access.log main;
}
EOF

rm -f /etc/nginx/conf.d/default.conf

# Test and restart Nginx
nginx -t
if [ $? -ne 0 ]; then
  echo "Nginx config test failed."
  exit 1
fi
systemctl restart nginx
systemctl enable nginx

# Open firewall ports and clean up old rules
iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
if ! iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
fi
if ! iptables -C INPUT -p tcp --dport 8443 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
fi
iptables-save > /etc/systemd/scripts/ip4save

echo "Migration complete! Access the Photon site at https://${IP_ADDRESS}:8443/ (HTTP on 8080 redirects to HTTPS)."

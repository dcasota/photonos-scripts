#!/bin/bash

if [ -z "$INSTALL_DIR" ]; then
  echo "Error: Variable INSTALL_DIR is not set. This sub-script must be called by installer.sh"
  exit 1
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
echo "======================================================="
echo "Fixing incorrect relative links in markdown files ..."
echo "======================================================="

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

# Fix 10: installation-guide paths that reference administration-guide
echo "10: Fixing installation-guide paths that reference administration-guide ..."
find "$INSTALL_DIR/content/en" -path "*/installation-guide/building-images/build-other-images/_index.md" -exec sed -i \
  -e 's|(\./administration-guide/|(../../../administration-guide/|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/installation-guide/run-photon-on-gce/installing-photon-os-on-google-compute-engine/_index.md" -exec sed -i \
  -e 's|(\./installation-guide/|(.../../|g' \
  {} \;

# Fix 11: user-guide working-with-kickstart references
echo "11: Fixing user-guide working-with-kickstart references ..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -path "*/user-guide/setting-up-network-pxe-boot/*" -exec sed -i \
  -e 's|(\./working-with-kickstart/)|(../working-with-kickstart/)|g' \
  {} \;

# Fix 12: administration-guide security/firewall relative links
echo "12: Fixing administration-guide security/firewall relative links ..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/security-policy/default-firewall-settings/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/|(../../../troubleshooting-guide/|g' \
  {} \;

find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/network-troubleshooting/checking-firewall-rules/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/|(../../|g' \
  {} \;

# Fix 13: troubleshooting-guide/kernel-problems internal links
echo "13: Fixing troubleshooting-guide/kernel-problems internal links ..."
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/_index.md" -exec sed -i \
  -e 's|(\./investigating-strange-behavior/)|(./investigating-strange-behavior/)|g' \
  {} \;

# Fix 14: mounting-remote-file-systems links
echo "14: Fixing mounting-remote-file-systems links ..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/managing-network-configuration/mounting-a-network-file-system/_index.md" -exec sed -i \
  -e 's|(\.\./\.\./user-guide/|(../../../user-guide/|g' \
  {} \;

# Fix 15: cloud-images references
echo "15: Fixing cloud-images references ..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2/_index.md" -exec sed -i \
  -e 's|(\./installation-guide/|(../../../installation-guide/|g' \
  {} \;

# Fix 16: internal links to remove double paths in absolute URLs
echo "16: Fixing internal links to remove double paths in absolute URLs ..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i 's|/docs-v3/docs-v3/|/docs-v3/|g' {} \;
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i 's|/docs-v4/docs-v4/|/docs-v4/|g' {} \;
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i 's|/docs-v5/docs-v5/|/docs-v5/|g' {} \;

# Fix 17: Patch docs-v* _index.md to set type: docs for sidebar and menu on main pages
echo "17: Patching docs-v* _index.md to set type: docs for sidebar and menu on main pages ..."
for ver in docs-v3 docs-v4 docs-v5; do
  if [ -f "$INSTALL_DIR/content/en/$ver/_index.md" ]; then
    sed -i '/^type\s*:/d' "$INSTALL_DIR/content/en/$ver/_index.md"
    sed -i '1s/^---$/---\ntype: docs/' "$INSTALL_DIR/content/en/$ver/_index.md"
  fi
done

# Fix 18: deprecated disableKinds/taxonomy in config.toml
echo "18: Fixing deprecated disableKinds/taxonomy in config.toml"
sed -i 's/[Tt]axonomy[Tt]erm/taxonomy/g' $INSTALL_DIR/config.toml

# Fix 19: deprecated languages.en.description
echo "19: Fixing deprecated languages.en.description ..."
if grep -q "^description.*=" $INSTALL_DIR/config.toml; then
  DESCRIPTION=$(grep "^description.*=" $INSTALL_DIR/config.toml | sed 's/description *= *"\(.*\)"/\1/')
  sed -i '/^description.*=/d' $INSTALL_DIR/config.toml
  if ! grep -q "\[languages.en.params\]" $INSTALL_DIR/config.toml; then
    echo -e "\n[languages.en.params]\ndescription = \"$DESCRIPTION\"" >> $INSTALL_DIR/config.toml
  else
    sed -i "/\[languages.en.params\]/a description = \"$DESCRIPTION\"" $INSTALL_DIR/config.toml
  fi
fi

# Fix 20: Fix for deprecated .Site.GoogleAnalytics (removed entirely from Hugo ~0.94+; accessing it now panics)
# We replace it with the modern safe map access .Site.Params.googleAnalytics everywhere.
# Since we have no GA ID, leaving the param unset makes it evaluate to "" / false → any conditional GA code is skipped safely.
echo "20: Applying robust patch for deprecated .Site.GoogleAnalytics → .Site.Params.googleAnalytics in ALL html and template files..."
find "$INSTALL_DIR" -type f \( -name "*.html" -o -name "*.tmpl" \) -print0 | xargs -0 sed -i 's|\.Site\.GoogleAnalytics|.Site.Params.googleAnalytics|g'

# Fix 21: Patch head.html to fix deprecated Google Analytics template
echo "21: Patching head.html to fix deprecated Google Analytics template ..."
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

# Fix 22: Remove existing googleAnalytics and uglyURLs and add googleAnalytics to config.toml
echo "22: Removing existing googleAnalytics and uglyURLs and add googleAnalytics to config.toml if not present ..."
sed -i '/^googleAnalytics/d' $INSTALL_DIR/config.toml
echo "googleAnalytics = \"G-XXXXXXXXXX\"" >>$INSTALL_DIR/config.toml
sed -i '/^uglyURLs/d' $INSTALL_DIR/config.toml
echo -e "\nuglyURLs = false" >>$INSTALL_DIR/config.toml


# Fix 23: Fix malformed external links caused by extra '(' immediately after ']'
echo "23: Fixing malformed external links caused by extra '(' immediately after ']' ..."
find "$INSTALL_DIR/content" -type f -name "*.md" -exec sed -i 's/]\((https\?:\/\/\)/](https:\/\//g' {} \;
# Specific fix for the Vagrant link (in case the general one needs help on that line)
sed -i 's/]\((https:\/\/app\.vagrantup\.com\/vmware\/boxes\/photon\))/](https:\/\/app\.vagrantup\.com\/vmware\/boxes\/photon\))/g' "$INSTALL_DIR/content/en/docs-v5/user-guide/packer-examples/_index.md" 2>/dev/null || true

# Fix 24: Install correct, fully safe render-link.html override (fixes BOTH urls.Parse errors AND the ".Title in type string" error forever)
echo "24: Installing bullet-proof safe render-link.html override..."
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

# Fix 25: Patch deprecated .Site.IsServer
echo "25: Patching deprecated .Site.IsServer ..."
HEAD_CSS_FILE="$INSTALL_DIR/themes/photon-theme/layouts/partials/head-css.html"
if [ -f "$HEAD_CSS_FILE" ]; then
  sed -i 's/\.Site\.IsServer/hugo.IsServer/g' "$HEAD_CSS_FILE"
fi
# Also check in layouts if not in theme
LAYOUT_HEAD_CSS="$INSTALL_DIR/layouts/partials/head-css.html"
if [ -f "$LAYOUT_HEAD_CSS" ] && [ ! -f "$HEAD_CSS_FILE" ]; then
  sed -i 's/\.Site\.IsServer/hugo.IsServer/g' "$LAYOUT_HEAD_CSS"
fi
# for deprecated .Site.IsServer (replaced by hugo.IsServer in recent Hugo versions)
find "$INSTALL_DIR" -type f \( -name "*.html" -o -name "*.tmpl" \) -print0 | xargs -0 sed -i 's|\.Site\.IsServer|hugo.IsServer|g'


# Fix 26: duplicated permalinks
echo "26: Fixing duplicated permalinks ..."
find "$INSTALL_DIR/content/" -type f -name "*.md" -exec sed -i '/^permalink: \/docs-v[3-5]\/docs-v[3-5]\//d' {} \;
# Ensure single [permalinks] section and set paths using :sections to handle hierarchy without duplicates
if grep -q "\[permalinks\]" $INSTALL_DIR/config.toml; then
  # Remove existing [permalinks] section (assuming it is at the end or we want to replace it entirely)
  sed -i '/^\[permalinks\]/,$d' $INSTALL_DIR/config.toml
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

# Fix 27: Add github_repo to config.toml to fix /commit/ links in theme
echo "27: Adding github_repo to config.toml..."
if ! grep -q "github_repo" "$INSTALL_DIR/config.toml"; then
    echo "Adding github_repo to config.toml..."
    # Check if [params] exists
    if grep -q "\[params\]" "$INSTALL_DIR/config.toml"; then
        sed -i '/\[params\]/a github_repo = "https://github.com/vmware/photon"' "$INSTALL_DIR/config.toml"
    else
        echo "" >> "$INSTALL_DIR/config.toml"
        echo "[params]" >> "$INSTALL_DIR/config.toml"
        echo 'github_repo = "https://github.com/vmware/photon"' >> "$INSTALL_DIR/config.toml"
    fi
fi

# Fix 28: Regex-induced https?:// links in markdown
echo "28: Fixing regex-induced https?:// links in markdown..."
find "$INSTALL_DIR/content" -type f -name "*.md" -exec sed -i 's/https?:\/\//https:\/\//g' {} +

echo "======================================================="
echo "Fixing incorrect relative links in markdown files done."
echo "======================================================="

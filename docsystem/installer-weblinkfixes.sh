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
# Fix: Replace Slack with Broadcom in config.toml
sed -i 's/name = "Slack"/name = "Broadcom Community"/g' $INSTALL_DIR/config.toml
sed -i 's/url = "https:\/\/vmwarecode.slack.com"/url = "https:\/\/community.broadcom.com\/tanzu\/communities\/tanzucommunityhomeblogs?CommunityKey=a70674e4-ccb6-46a3-ae94-7ecf16c06e24"/g' $INSTALL_DIR/config.toml
sed -i 's/icon = "fab fa-slack"/icon = "fas fa-comment-dots"/g' $INSTALL_DIR/config.toml
sed -i 's/desc = "Join the VMware {code} Slack community!"/desc = "Broadcom Community for Photon OS"/g' $INSTALL_DIR/config.toml
# Fix: Patch templates to handle image URLs in icon fields for social links
find $INSTALL_DIR/layouts $INSTALL_DIR/themes -type f -name "*.html" -exec sed -i 's/<i class="{{ .icon }}"[^>]*>\&nbsp;<\/i>/{{ if or (hasPrefix .icon "http:\/\/") (hasPrefix .icon "https:\/\/") (hasPrefix .icon "\/") }}<img src="{{ .icon }}" alt="{{ .name }}" style="height:1em; width:auto; vertical-align:middle;">\&nbsp;{{ else }}<i class="{{ .icon }}" aria-hidden="true">\&nbsp;<\/i>{{ end }}/g' {} \;
# Fix footer text to "a VMware By Broadcom backed Project"
sed -i 's/A VMware Backed Project/a VMware By Broadcom backed Project/gi' $INSTALL_DIR/config.toml
find $INSTALL_DIR/layouts $INSTALL_DIR/themes -type f -name "*.html" -exec sed -i 's/A VMware Backed Project/a VMware By Broadcom backed Project/gi' {} \;
# Fix VMware logo to Broadcom logo
find $INSTALL_DIR/layouts $INSTALL_DIR/themes -type f -name "*.html" -exec sed -i 's/vmware-logo.png/broadcom-logo.png/g' {} \;
find $INSTALL_DIR/layouts $INSTALL_DIR/themes -type f -name "*.html" -exec sed -i 's/vmware.png/broadcom-logo.png/g' {} \;
find $INSTALL_DIR/layouts $INSTALL_DIR/themes -type f -name "*.html" -exec sed -i 's/vmware-logo.svg/broadcom-logo.png/g' {} \;
# Fix VMware link to Broadcom
find $INSTALL_DIR/layouts $INSTALL_DIR/themes -type f -name "*.html" -exec sed -i 's/https:\/\/www.vmware.com/https:\/\/www.broadcom.com/g' {} \;
sed -i 's/https:\/\/www.vmware.com/https:\/\/www.broadcom.com/g' $INSTALL_DIR/config.toml
# Additional fixes for config.toml links post-Broadcom acquisition
sed -i 's/vmw_link = "https:\/\/www.vmware.com"/vmw_link = "https:\/\/www.broadcom.com"/g' $INSTALL_DIR/config.toml
sed -i 's/privacy_policy = "https:\/\/vmware.com\/help\/privacy"/privacy_policy = "https:\/\/www.broadcom.com\/company\/legal\/privacy"/g' $INSTALL_DIR/config.toml
# Fix specific footer link from vmware.github.io to broadcom.com
sed -i 's/https:\/\/vmware.github.io/https:\/\/www.broadcom.com/g' $INSTALL_DIR/config.toml
find $INSTALL_DIR/layouts $INSTALL_DIR/themes -type f -name "*.html" -exec sed -i 's/https:\/\/vmware.github.io/https:\/\/www.broadcom.com/g' {} \;

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

# Fix 0: Rename directories with spaces to use hyphens (CRITICAL - prevents redirect loops)
echo "0. Renaming directories with spaces to use hyphens..."
for ver in docs-v3 docs-v4 docs-v5; do
  SPACE_DIR="$INSTALL_DIR/content/en/$ver/installation-guide/building images"
  HYPHEN_DIR="$INSTALL_DIR/content/en/$ver/installation-guide/building-images"
  if [ -d "$SPACE_DIR" ]; then
    echo "  Renaming: $SPACE_DIR -> $HYPHEN_DIR"
    mv "$SPACE_DIR" "$HYPHEN_DIR"
  fi
done

# Validate no directories with spaces remain
DIRS_WITH_SPACES=$(find "$INSTALL_DIR/content" -type d -name "* *" 2>/dev/null | wc -l)
if [ "$DIRS_WITH_SPACES" -gt 0 ]; then
  echo "WARNING: Found $DIRS_WITH_SPACES directories with spaces:"
  find "$INSTALL_DIR/content" -type d -name "* *" 2>/dev/null
fi

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
# Fix quick-start-links (photon-quickstart.md) - fixing both relative path and typo
find "$INSTALL_DIR/content/en" -path "*/Introduction/photon-quickstart.md" -exec sed -i \
  -e 's|(\.\./\.\./overview/)|(../overview/)|g' \
  -e 's|(\.\./\.\./installation-guide/downloading-photon/)|(../installation-guide/downloading-photon-os/)|g' \
  -e 's|(\.\./\.\./installation-guide/building-images/build-iso-from-source/)|(../installation-guide/building-images/build-iso-from-source/)|g' \
  {} \;

# Also fix quick-start-links index if exists
find "$INSTALL_DIR/content/en" -path "*/quick-start-links/_index.md" -exec sed -i \
  -e 's|(\.\./\.\./installation-guide/|(../installation-guide/|g' \
  -e 's|(\.\./\.\./overview/)|(../overview/)|g' \
  -e 's|downloading-photon/|downloading-photon-os/|g' \
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
  # Remove existing [permalinks] section without deleting everything after it
  # Use awk to remove only the [permalinks] section and its content
  awk '
    /^\[permalinks\]$/ { in_perma=1; next }
    in_perma && /^$/ { next }
    in_perma && /^[a-zA-Z0-9_-]+ *=/ { next }
    in_perma && (/^#/ || /^\[/) { in_perma=0 }
    !in_perma { print }
  ' $INSTALL_DIR/config.toml > $INSTALL_DIR/config.toml.tmp
  mv $INSTALL_DIR/config.toml.tmp $INSTALL_DIR/config.toml
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

# Fix 27: Add github_repo and Broadcom configuration to config.toml
echo "27: Adding github_repo and Broadcom configuration to config.toml..."
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

# Add copyright and Broadcom community links
if ! grep -q "copyright =" "$INSTALL_DIR/config.toml"; then
    echo "Adding copyright and community links to config.toml..."
    sed -i '/github_repo/a copyright = "VMware"' "$INSTALL_DIR/config.toml"
    
    # Add community links section
    cat >> "$INSTALL_DIR/config.toml" <<'EOF_LINKS'

# Community and support links
[[params.links.user]]
name = "GitHub"
url = "https://github.com/vmware/photon"
icon = "fab fa-github"

[[params.links.user]]
name = "Broadcom Community"
url = "https://community.broadcom.com/"
icon = "fas fa-users"
EOF_LINKS
fi

# Fix 28: Regex-induced https?:// links in markdown
echo "28: Fixing regex-induced https?:// links in markdown..."
find "$INSTALL_DIR/content" -type f -name "*.md" -exec sed -i 's/https?:\/\//https:\/\//g' {} +

# Fix 29: Fix Slug for mounting-remote-file-systems to match filename
echo "29: Fixing Slug for mounting-remote-file-systems..."
find "$INSTALL_DIR/content/en" -name "mounting-remote-file-systems.md" -exec sed -i '/^slug: mounting-remote-file-systems.*/d' {} \;
find "$INSTALL_DIR/content/en" -name "mounting-remote-file-systems.md" -exec sed -i '/^weight: .*/a slug: mounting-remote-file-systems' {} \;

# Fix 30: Fix Slug for inspecting-network-links-with-networkctl
echo "30: Fixing Slug for inspecting-network-links-with-networkctl..."
find "$INSTALL_DIR/content/en" -name "inspecting-network-links-with-networkctl.md" -exec sed -i '/^slug: inspecting-network-links-with-networkctl.*/d' {} \;
find "$INSTALL_DIR/content/en" -name "inspecting-network-links-with-networkctl.md" -exec sed -i '/^weight: .*/a slug: inspecting-network-links-with-networkctl' {} \;

# Fix 31: Fix Packer Examples Link
echo "31: Fixing Packer Examples Link..."
sed -i 's|\[vmware/photon\]: (https://app.vagrantup.com/vmware/boxes/photon)|[vmware/photon]: https://app.vagrantup.com/vmware/boxes/photon|g' "$INSTALL_DIR/content/en/docs-v5/user-guide/packer-examples/_index.md"

# Fix 32: Fix Kubernetes Link in administration-guide
echo "32: Fixing Kubernetes Link..."
find "$INSTALL_DIR/content/en" -name "kubernetes.md" -path "*/administration-guide/containers/*" -exec sed -i 's|(\.\./\.\./administration-guide/containers/kubernetes/)|(../../user-guide/kubernetes-on-photon-os/running-kubernetes-on-photon-os/)|g' {} \;

# Fix 33: Fix Blog Post Link
echo "33: Fixing Blog Post Link..."
sed -i 's|/docs/overview/whats-new/|/docs-v4/whats-new/|g' "$INSTALL_DIR/content/en/blog/releases/photon4-ga.md"

# Fix 34: Fix GCE Prerequisite missing link
echo "34: Removing dead link to kernel upgrade in GCE prerequisites..."
find "$INSTALL_DIR/content/en" -name "prerequisites-for-photon-os-on-gce.md" -exec sed -i '/Upgrading the Kernel Version Requires Grub Changes/d' {} \;

# Fix 35: Fix Kubernetes Link in administration-guide (Correct Path)
echo "35: Fixing Kubernetes Link in administration-guide (Correct Path)..."
find "$INSTALL_DIR/content/en" -name "kubernetes.md" -path "*/administration-guide/containers/*" -exec sed -i 's|(\.\./\.\./administration-guide/containers/kubernetes/)|(../../../user-guide/kubernetes-on-photon-os/running-kubernetes-on-photon-os/)|g' {} \;
find "$INSTALL_DIR/content/en" -name "kubernetes.md" -path "*/administration-guide/containers/*" -exec sed -i 's|(\.\./\.\./user-guide/kubernetes-on-photon-os/running-kubernetes-on-photon-os/)|(../../../user-guide/kubernetes-on-photon-os/running-kubernetes-on-photon-os/)|g' {} \;

# Fix 36: Fix cloud-images link in administration-guide
echo "36: Fixing cloud-images link in administration-guide..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2.md" -exec sed -i 's|(\.\./\.\./\.\./installation-guide/cloud-images/)|(../../../installation-guide/compatible-cloud-images/)|g' {} \;
find "$INSTALL_DIR/content/en" -path "*/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2.md" -exec sed -i 's|(\.\./\.\./installation-guide/cloud-images/)|(../../../installation-guide/compatible-cloud-images/)|g' {} \;

# Fix 37: Fix broken link in installing-photon-os-on-google-compute-engine
echo "37: Fixing broken link in installing-photon-os-on-google-compute-engine..."
find "$INSTALL_DIR/content/en" -path "*/installation-guide/run-photon-on-gce/installing-photon-os-on-gce.md" -exec sed -i 's|(\./installation-guide/deploying-a-containerized-application-in-photon-os/)|(../../deploying-a-containerized-application-in-photon-os/)|g' {} \;

# Fix 38: Fix broken link in default-firewall-settings
echo "38: Fixing broken link in default-firewall-settings..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/security-policy/default-firewall-settings.md" -exec sed -i 's|(\.\./\.\./troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh/)|(../../../troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh/)|g' {} \;

# Fix 39: Fix broken link in checking-firewall-rules
echo "39: Fixing broken link in checking-firewall-rules..."
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/network-troubleshooting/checking-firewall-rules.md" -exec sed -i 's|(\.\./\.\./troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh/)|(../../solutions-to-common-problems/permitting-root-login-with-ssh/)|g' {} \;
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/network-troubleshooting/checking-firewall-rules.md" -exec sed -i 's|(\./troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh/)|(../../solutions-to-common-problems/permitting-root-login-with-ssh/)|g' {} \;

# Fix 40: Fix broken link in troubleshooting/network-troubleshooting for tcpdump
echo "40: Fixing broken link in troubleshooting/network-troubleshooting for tcpdump..."
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/network-troubleshooting/_index.md" -exec sed -i 's|(\.\./\.\./administration-guide/managing-network-configuration/installing-the-packages-for-tcpdump-and-netcat-with-tdnf/)|(../../administration-guide/managing-network-configuration/installing-packages-for-tcpdump-and-netcat/)|g' {} \;

# Fix 41: Fix broken link in installing-a-host-against-custom-server-repository
echo "41: Fixing broken link in installing-a-host-against-custom-server-repository..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-rpm-ostree/installing-a-host-against-custom-server-repository/_index.md" -exec sed -i 's|(\.\./\.\./user-guide/working-with-kickstart/)|(../../../user-guide/working-with-kickstart/)|g' {} \;

# Fix 42: Fix broken link in troubleshooting/performance-issues
echo "42: Fixing broken link in troubleshooting/performance-issues..."
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/performance-issues/_index.md" -exec sed -i 's|(general_performance_guidelines)|(general-performance-guidelines)|g' {} \;
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/performance-issues/_index.md" -exec sed -i 's|(throughput_performance)|(throughput-performance)|g' {} \;
# Legacy wrong fix removal just in case
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/performance-issues/_index.md" -exec sed -i 's|(\.\./troubleshooting-guide/performance-issues/general_performance_guidelines)|(general-performance-guidelines)|g' {} \;

# Fix 43: Fix broken link in troubleshooting/kernel-problems
echo "43: Fixing broken link in troubleshooting/kernel-problems..."
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/_index.md" -exec sed -i 's|(\./investigating-strange-behavior/)|(./investigating-unexpected-behavior/)|g' {} \;
# Remove trailing slash from markdown file links (causes 404 in Hugo)
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/_index.md" -exec sed -i 's|(\./troubleshooting-linux-kernel/)|(./troubleshooting-linux-kernel)|g' {} \;
# Fix incorrect nested paths in kernel-problems index
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/_index.md" -exec sed -i \
  -e 's|(\./troubleshooting-guide/kernel-problems-and-boot-and-login-errors/kernel-overview/)|(./kernel-overview/)|g' \
  -e 's|(\./troubleshooting-guide/kernel-problems-and-boot-and-login-errors/boot-process-overview/)|(./boot-process-overview/)|g' \
  -e 's|(\./troubleshooting-guide/kernel-problems-and-boot-and-login-errors/blank-screen-on-reboot/)|(./blank-screen-on-reboot/)|g' \
  -e 's|(\./troubleshooting-guide/kernel-problems-and-boot-and-login-errors/investigating-unexpected-behavior/)|(./investigating-unexpected-behavior/)|g' \
  -e 's|(\./troubleshooting-guide/kernel-problems-and-boot-and-login-errors/investigating-the-guest-kernel/)|(./investigating-the-guest-kernel/)|g' \
  -e 's|(\./troubleshooting-guide/kernel-problems-and-boot-and-login-errors/kernel-log-replication-with-vprobes/)|(./kernel-log-replication-with-vprobes/)|g' \
  {} \;

# Fix 44: Fix blog link for whats-new (remove double slash)
echo "44: Fixing blog link for whats-new..."
# Remove double slash from whats-new link
sed -i 's|/docs-v4/whats-new//|/docs-v4/whats-new/|g' "$INSTALL_DIR/content/en/blog/releases/photon4-ga.md"

# Fix 45: Fix incorrect relative path in firewall settings SSH link
echo "45: Fixing firewall settings SSH link..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/security-policy/default-firewall-settings.md" -exec sed -i \
  's|(\./troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh/)|(../../../troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh/)|g' \
  {} \;

# Fix 46: Update footer template to include Broadcom logo
echo "46: Updating footer template to include Broadcom logo..."
FOOTER_FILE="$INSTALL_DIR/themes/photon-theme/layouts/partials/footer.html"
if [ -f "$FOOTER_FILE" ]; then
    # Check if Broadcom logo is already in footer
    if ! grep -q "broadcom-logo.png" "$FOOTER_FILE"; then
        echo "Adding Broadcom logo to footer..."
        # Replace the footer logo section
        sed -i '/<div class="text-right">/,/<\/div>/{
            /<div class="text-right">/ {
                c\<div class="text-right d-flex align-items-center justify-content-end">
            }
            /vmware-logo.svg/ {
                c\  <a href="https://vmware.github.io" class="mr-3"> <img class="vmw-footer-logo" src="/img/vmware-logo.svg" alt="VMware" /></a>\n  <a href="https://www.broadcom.com" target="_blank"> <img class="vmw-footer-logo" src="/img/broadcom-logo.png" alt="Broadcom" style="max-height: 40px;" /></a>
            }
        }' "$FOOTER_FILE"
    fi
fi

# Fix 47: Update i18n translation for Broadcom branding
echo "47: Updating i18n translation for Broadcom branding..."
I18N_FILE="$INSTALL_DIR/themes/photon-theme/i18n/en.toml"
if [ -f "$I18N_FILE" ]; then
    # Update footer text to include Broadcom
    if grep -q 'other = "A VMware Backed Project"' "$I18N_FILE"; then
        echo "Updating footer text to include Broadcom..."
        sed -i 's/other = "A VMware Backed Project"/other = "A VMware By Broadcom Backed Project"/' "$I18N_FILE"
    fi
fi

# Fix 48: Fix blog and cross-reference links to whats-new (Hugo slugifies title to "what-is-new-in-photon-os-4")
echo "48. Fixing links to whats-new pages (Hugo slug generation)..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|(docs-v3/whats-new/)|(docs-v3/overview/what-is-new-in-photon-os/)|g' \
  -e 's|(/docs-v3/whats-new/)|(/docs-v3/overview/what-is-new-in-photon-os/)|g' \
  -e 's|(docs-v4/whats-new/)|(docs-v4/what-is-new-in-photon-os-4/)|g' \
  -e 's|(/docs-v4/whats-new/)|(/docs-v4/what-is-new-in-photon-os-4/)|g' \
  -e 's|(docs-v5/whats-new/)|(docs-v5/what-is-new-in-photon-os-5/)|g' \
  -e 's|(/docs-v5/whats-new/)|(/docs-v5/what-is-new-in-photon-os-5/)|g' \
  {} \;

# Fix 49: Fix kickstart links (Hugo slugifies title "Kickstart Support" to "kickstart-support-in-photon-os")
echo "49. Fixing kickstart links to match Hugo slug generation..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|(/docs-v3/user-guide/working-with-kickstart/)|(/docs-v3/user-guide/kickstart-support-in-photon-os/)|g' \
  -e 's|(/docs-v4/user-guide/working-with-kickstart/)|(/docs-v4/user-guide/kickstart-support-in-photon-os/)|g' \
  -e 's|(/docs-v5/user-guide/working-with-kickstart/)|(/docs-v5/user-guide/kickstart-support-in-photon-os/)|g' \
  -e 's|(../../user-guide/working-with-kickstart/)|(../../user-guide/kickstart-support-in-photon-os/)|g' \
  -e 's|(../../../user-guide/working-with-kickstart/)|(../../../user-guide/kickstart-support-in-photon-os/)|g' \
  {} \;

# Fix 50: Fix troubleshooting-linux-kernel link (Hugo generates as "linux-kernel", not "troubleshooting-linux-kernel")
echo "50. Fixing troubleshooting-linux-kernel links..."
find "$INSTALL_DIR/content/en" -path "*/kernel-problems-and-boot-and-login-errors/_index.md" -exec sed -i \
  -e 's|(./troubleshooting-linux-kernel)|(./linux-kernel/)|g' \
  -e 's|(troubleshooting-linux-kernel)|(linux-kernel/)|g' \
  {} \;

# Fix 51: Fix kickstart relative path links (Hugo slugifies "Working with Kickstart" to "kickstart-support-in-photon-os")
echo "51. Fixing kickstart relative path links in PXE boot documentation..."
find "$INSTALL_DIR/content/en" -name "setting-up-network-pxe-boot.md" -exec sed -i \
  -e 's|(../working-with-kickstart/)|(../kickstart-support-in-photon-os/)|g' \
  -e 's|(working-with-kickstart/)|(kickstart-support-in-photon-os/)|g' \
  {} \;

# Fix 52: Fix whats-new relative path in upgrading documentation (use absolute path to avoid Hugo relative path confusion)
echo "52. Fixing whats-new relative path links..."
find "$INSTALL_DIR/content/en" -name "*upgrading-to-photon-os*.md" -exec sed -i \
  -e 's|(\.\./what-is-new-in-photon-os-4/)|(/docs-v4/what-is-new-in-photon-os-4/)|g' \
  -e 's|(what-is-new-in-photon-os-4/)|(/docs-v4/what-is-new-in-photon-os-4/)|g' \
  -e 's|(./whats-new/)|(../../what-is-new-in-photon-os-4/)|g' \
  -e 's|(whats-new/)|(../../what-is-new-in-photon-os-4/)|g' \
  -e 's|(/docs-v4/installation-guide/upgrading-to-photon-os-4.0/whats-new/)|(/docs-v4/what-is-new-in-photon-os-4/)|g' \
  {} \;

# Fix 53: Fix netmgr and PMD API links to use actual Hugo slugs
echo "53. Fixing netmgr and PMD API links to match actual Hugo-generated page slugs..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|photon-management-daemon-cli/)|photon-management-daemon-command-line-interface-pmd-cli/)|g' \
  -e 's|netmgr\.c/)|network-configuration-manager-c-api/)|g' \
  -e 's|netmgr\.python/)|network-configuration-manager-python-api/)|g' \
  -e 's|(/docs-v4/administration-guide/managing-network-configuration/using-the-network-configuration-manager/command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|(/docs-v4/command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|g' \
  -e 's|(/docs-v4/administration-guide/managing-network-configuration/using-the-network-configuration-manager/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|g' \
  -e 's|(/docs-v4/administration-guide/managing-network-configuration/using-the-network-configuration-manager/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|g' \
  -e 's|(/docs-v4/administration-guide/photon-management-daemon/available-apis/administration-guide/network-configuration-manager-python-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|g' \
  -e 's|(/docs-v4/administration-guide/photon-management-daemon/available-apis/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|g' \
  {} \;

# Fix 54: Fix troubleshooting packages duplicate path segment
echo "54. Fixing troubleshooting packages duplicate path segment..."
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/troubleshooting-packages*.md" -exec sed -i \
  -e 's|(/docs-v4/troubleshooting-guide/troubleshooting-packages/administration-guide/)|(/docs-v4/administration-guide/)|g' \
  -e 's|(./administration-guide/)|(../../administration-guide/)|g' \
  {} \;

# Fix 55: Fix remaining paths to use absolute URLs (avoid Hugo relative path confusion)
echo "55. Fixing remaining paths to use absolute URLs..."
find "$INSTALL_DIR/content/en" -path "*/administration-guide/photon-management-daemon/available-apis*.md" -exec sed -i \
  -e 's|(./administration-guide/network-configuration-manager-python-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|g' \
  -e 's|(./administration-guide/network-configuration-manager-c-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|g' \
  -e 's|(/docs-v4/administration-guide/photon-management-daemon/available-apis/administration-guide/network-configuration-manager-python-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|g' \
  {} \;
find "$INSTALL_DIR/content/en" -path "*/administration-guide/managing-network-configuration/using-the-network-configuration-manager.md" -exec sed -i \
  -e 's|(../../command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|(/docs-v4/command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|g' \
  -e 's|(../../managing-network-configuration/network-configuration-manager-c-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|g' \
  -e 's|(../../managing-network-configuration/network-configuration-manager-python-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|g' \
  -e 's|(/docs-v4/administration-guide/command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|(/docs-v4/command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|g' \
  {} \;

# Fix 56: Fix docs-v4 broken API links (from weblinkchecker.sh report)
echo "56. Fixing docs-v4 broken API links with duplicated path segments..."
# These links have duplicated path segments causing 404 errors
find "$INSTALL_DIR/content/en/docs-v4" -type f -name "*.md" -exec sed -i \
  -e 's|(./command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|(/docs-v4/command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|g' \
  -e 's|(./administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|g' \
  -e 's|(./administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|g' \
  -e 's|(../administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|g' \
  -e 's|(../administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|(/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|g' \
  {} \;

# Additional fix for available-apis page specifically
if [ -f "$INSTALL_DIR/content/en/docs-v4/administration-guide/photon-management-daemon/available-apis.md" ]; then
  echo "  Fixing available-apis.md specifically..."
  sed -i \
    -e 's|\[netmgr\.c\](./administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|[netmgr.c](/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|g' \
    -e 's|\[netmgr\.python\](./administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|[netmgr.python](/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|g' \
    "$INSTALL_DIR/content/en/docs-v4/administration-guide/photon-management-daemon/available-apis.md"
fi

# Additional fix for using-the-network-configuration-manager page
if [ -f "$INSTALL_DIR/content/en/docs-v4/administration-guide/managing-network-configuration/using-the-network-configuration-manager.md" ]; then
  echo "  Fixing using-the-network-configuration-manager.md specifically..."
  sed -i \
    -e 's|\[pmd-cli\](../../command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|[pmd-cli](/docs-v4/command-line-reference/command-line-interfaces/photon-management-daemon-command-line-interface-pmd-cli/)|g' \
    -e 's|\[netmgr\.c API\](../../managing-network-configuration/network-configuration-manager-c-api/)|[netmgr.c API](/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-c-api/)|g' \
    -e 's|\[netmgr\.python API\](../../managing-network-configuration/network-configuration-manager-python-api/)|[netmgr.python API](/docs-v4/administration-guide/managing-network-configuration/network-configuration-manager-python-api/)|g' \
    "$INSTALL_DIR/content/en/docs-v4/administration-guide/managing-network-configuration/using-the-network-configuration-manager.md"
fi

# Fix 57: Fix image paths in installation-guide subdirectories (../../images/ -> ../images/)
echo "57. Fixing image paths in installation-guide subdirectories..."
# Files in /installation-guide/run-photon-*/ subdirectories incorrectly use ../../images/
# which goes to /docs-v5/images/ instead of /docs-v5/installation-guide/images/
# The images are actually in /installation-guide/images/, so should use ../images/
for ver in docs-v3 docs-v4 docs-v5; do
  echo "  Processing $ver..."
  # Fix in all run-photon-* subdirectories
  find "$INSTALL_DIR/content/en/$ver/installation-guide/run-photon-"* -type f -name "*.md" -exec sed -i \
    -e 's|(\.\./\.\./images/|(../images/|g' \
    -e 's|](../../images/|](../images/|g' \
    {} \; 2>/dev/null || true
  
  # Fix in building-images subdirectories (but not building-images itself)
  find "$INSTALL_DIR/content/en/$ver/installation-guide/building-images" -mindepth 2 -type f -name "*.md" -exec sed -i \
    -e 's|(\.\./\.\./images/|(../images/|g' \
    -e 's|](../../images/|](../images/|g' \
    {} \; 2>/dev/null || true
done

# Fix 58: Fix administration-guide paths in build-other-images
echo "58. Fixing administration-guide paths in build-other-images..."
# Files in /installation-guide/building-images/build-other-images/ use ../../administration-guide/
# which goes to /installation-guide/administration-guide/ (WRONG)
# Should be ../../../administration-guide/ to reach /docs-vX/administration-guide/
for ver in docs-v3 docs-v4 docs-v5; do
  find "$INSTALL_DIR/content/en/$ver/installation-guide/building-images/build-other-images" -type f -name "*.md" -exec sed -i \
    -e 's|(\.\./\.\./administration-guide/|(../../../administration-guide/|g' \
    -e 's|](../../administration-guide/|](../../../administration-guide/|g' \
    {} \; 2>/dev/null || true
done

# Fix 59: Fix typo in docs-v4 fusion OVA image path (..images -> ../images)
echo "59. Fixing typo in docs-v4 fusion OVA image path..."
find "$INSTALL_DIR/content/en/docs-v4/installation-guide/run-photon-on-fusion" -type f -name "*.md" -exec sed -i \
  -e 's|(\.\.\.\./images/|(../images/|g' \
  -e 's|](\.\.\.\.images/|](../images/|g' \
  -e 's|](\.\.images/|](../images/|g' \
  -e 's|\.\.images/|../images/|g' \
  {} \; 2>/dev/null || true

# Fix 60: Fix absolute image paths in troubleshooting/fsck-fails (/docs/images -> /docs-v4/images)
echo "60. Fixing absolute image paths in troubleshooting fsck-fails..."
find "$INSTALL_DIR/content/en/docs-v4/troubleshooting-guide/file-system-troubleshooting" -type f -name "*.md" -exec sed -i \
  -e 's|(/docs/images/|(/docs-v4/images/|g' \
  {} \; 2>/dev/null || true
# Also fix for all versions to be consistent
for ver in docs-v3 docs-v5; do
  find "$INSTALL_DIR/content/en/$ver/troubleshooting-guide/file-system-troubleshooting" -type f -name "*.md" -exec sed -i \
    -e 's|(/docs/images/|](/$ver/images/)|g' \
    {} \; 2>/dev/null || true
done

# Fix 61: Copy missing images from installation-guide/images to top-level images directory
echo "61. Ensuring all installation images are accessible from top-level images directory..."
for ver in docs-v3 docs-v4 docs-v5; do
  SRC_DIR="$INSTALL_DIR/content/en/$ver/installation-guide/images"
  DEST_DIR="$INSTALL_DIR/content/en/$ver/images"
  
  if [ -d "$SRC_DIR" ] && [ -d "$DEST_DIR" ]; then
    echo "  Copying missing images for $ver..."
    # Copy only if files don't exist in destination (preserve existing files)
    rsync -a --ignore-existing "$SRC_DIR/" "$DEST_DIR/" 2>/dev/null || cp -rn "$SRC_DIR"/* "$DEST_DIR"/ 2>/dev/null || true
  fi
done

# Fix 62: Copy troubleshooting images from docs-v5 to docs-v4 (missing in v4)
echo "62. Copying missing troubleshooting images from docs-v5 to docs-v4..."
if [ -f "$INSTALL_DIR/content/en/docs-v5/images/fsck-fails.png" ]; then
  cp -n "$INSTALL_DIR/content/en/docs-v5/images/fsck-fails.png" "$INSTALL_DIR/content/en/docs-v4/images/" 2>/dev/null || true
fi
if [ -f "$INSTALL_DIR/content/en/docs-v5/images/lsblk-command.png" ]; then
  cp -n "$INSTALL_DIR/content/en/docs-v5/images/lsblk-command.png" "$INSTALL_DIR/content/en/docs-v4/images/" 2>/dev/null || true
fi

# Fix 63: Replace dark mode toggle with simple moon/sun icon button
echo "63. Replacing dark mode toggle with moon/sun icon button..."
TOGGLE_FILE="$INSTALL_DIR/themes/photon-theme/layouts/partials/toggle.html"
if [ -f "$TOGGLE_FILE" ]; then
  cat > "$TOGGLE_FILE" << 'EOF_TOGGLE'
<!-- Simple Moon/Sun Toggle Button -->
<button id="theme-toggle" class="btn btn-link nav-link" aria-label="Toggle dark mode" style="padding: 0.5rem;">
  <i id="theme-icon" class="fas fa-moon" style="font-size: 1.2rem;"></i>
</button>
EOF_TOGGLE
  echo "  Replaced toggle.html with simple moon/sun icon button"
fi

# Fix 64: Update navbar.html - place console and dark mode after version selector (avoid duplicates)
NAVBAR_FILE="$INSTALL_DIR/themes/photon-theme/layouts/partials/navbar.html"
if [ -f "$NAVBAR_FILE" ]; then
  echo "  Cleaning up navbar.html - removing ALL console and dark mode duplicates..."
  
  # Remove the old toggle.html partial reference (this shows the checkbox toggle)
  sed -i '/{{ if  \.Site\.Params\.darkmode }}/{N;N;N;N;/{{ partial "toggle\.html"/d;}' "$NAVBAR_FILE"
  
  # Remove ALL lines containing console button or dark mode toggle
  sed -i '/toggleConsole/d' "$NAVBAR_FILE"
  sed -i '/theme-toggle/d' "$NAVBAR_FILE"
  sed -i '/<!-- Console Button -->/d' "$NAVBAR_FILE"
  sed -i '/<!-- Dark Mode Toggle -->/d' "$NAVBAR_FILE"
  sed -i '/<!-- dark mode toolbar -->/d' "$NAVBAR_FILE"
  sed -i '/<!-- End of dark mode toggle in navbar -->/d' "$NAVBAR_FILE"
  
  # Now add them ONCE after the version selector closing {{ end }}
  # Find the line with version selector's {{ end }} and add console + dark mode after it
  sed -i '/{{ if and (eq .Type "docs") .Site.Params.versions }}/,/{{ end }}/{
    /{{ end }}/a\
\t\t<!-- Console Button -->\n\t\t<li class="nav-item d-inline-block">\n\t\t\t<a class="nav-link" href="#" onclick="toggleConsole(); return false;" title="Console">\n\t\t\t\t<i class="fas fa-terminal"></i>\n\t\t\t</a>\n\t\t</li>\n\t\t\n\t\t<!-- Dark Mode Toggle -->\n\t\t{{ if .Site.Params.darkmode }}\n\t\t<li class="nav-item d-inline-block">\n\t\t\t<button id="theme-toggle" class="btn btn-link nav-link" aria-label="Toggle dark mode" style="padding: 0.375rem 0.75rem; margin: 0;">\n\t\t\t\t<i id="theme-icon" class="fas fa-moon"></i>\n\t\t\t</button>\n\t\t</li>\n\t\t{{ end }}
  }' "$NAVBAR_FILE"
  
  echo "  Updated navbar.html: Single console and dark mode after Release dropdown"
fi

# Fix 65: Fix kernel-problems-and-boot-and-login-errors internal links (investigating-strange-behavior -> investigating-unexpected-behavior)
echo "65. Fixing kernel-problems investigating-strange-behavior links..."
find "$INSTALL_DIR/content/en" -path "*/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/_index.md" -exec sed -i \
  -e 's|(investigating-strange-behavior)|(investigating-unexpected-behavior)|g' \
  -e 's|(./investigating-strange-behavior/)|(./investigating-unexpected-behavior/)|g' \
  -e 's|(investigating-strange-behavior/)|(investigating-unexpected-behavior/)|g' \
  {} \;

# Fix 66: Fix Troubleshooting-linuxkernel typo (capitalization and hyphen)
echo "66. Fixing Troubleshooting-linuxkernel link..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|(Troubleshooting-linuxkernel)|(linux-kernel/)|g' \
  -e 's|(Troubleshooting-linux-kernel)|(linux-kernel/)|g' \
  {} \;

# Fix 67: Fix netmgr link in troubleshooting (netmgr -> using-the-network-configuration-manager)
echo "67. Fixing netmgr link in troubleshooting..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|troubleshooting-guide/network-troubleshooting/netmgr|administration-guide/managing-network-configuration/using-the-network-configuration-manager|g' \
  {} \;

# Fix 68: Fix photon_admin paths (old documentation path style)
echo "68. Fixing photon_admin paths..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|photon_admin/installing-the-packages-for-tcpdump-and-netcat-with-tdnf|administration-guide/managing-network-configuration/installing-packages-for-tcpdump-and-netcat|g' \
  {} \;

# Fix 69: Fix Downloading-Photon capitalization issue
echo "69. Fixing Downloading-Photon capitalization..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|/Downloading-Photon|/downloading-photon-os|g' \
  -e 's|(Downloading-Photon)|(downloading-photon-os)|g' \
  {} \;

# Fix 70: Fix upgrading-to-photon-os-3 path (missing trailing slash or .0 suffix)
echo "70. Fixing upgrading-to-photon-os-3 path..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|upgrading-to-photon-os-3.0/|upgrading-to-photon-os-3/|g' \
  -e 's|upgrading-to-photon-os-4.0/|upgrading-to-photon-os-4/|g' \
  {} \;

# Fix 71: Fix build-iso-from-source path (should be under building-images)
echo "71. Fixing build-iso-from-source path..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|installation-guide/build-iso-from-source/|installation-guide/building-images/build-iso-from-source/|g' \
  {} \;

# Fix 72: Fix commnad-line-interfaces typo
echo "72. Fixing commnad-line-interfaces typo..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i \
  -e 's|commnad-line-interfaces|command-line-interfaces|g' \
  {} \;

# Fix 73: Fix Vagrant box link format issue
echo "73. Fixing Vagrant box link format..."
find "$INSTALL_DIR/content/en" -name "packer-examples" -type d -exec find {} -name "*.md" -exec sed -i \
  -e 's|\[vmware/photon\]: (https://app.vagrantup.com/vmware/boxes/photon)|[vmware/photon](https://app.vagrantup.com/vmware/boxes/photon)|g' \
  -e 's|(%28https://app.vagrantup.com/vmware/boxes/photon%29)|https://app.vagrantup.com/vmware/boxes/photon|g' \
  {} \; 2>/dev/null || true

# Fix 74: Copy missing troubleshooting images
echo "74. Copying missing troubleshooting images..."
for ver in docs-v3 docs-v4 docs-v5; do
  DEST_DIR="$INSTALL_DIR/content/en/$ver/images"
  mkdir -p "$DEST_DIR"
  
  # Copy specific images that are referenced but may be missing
  for img in watchcmd.png top-in-photon-os.png resetpw.png grub-edit-menu-orig.png grub-edit-menu-changepw.png; do
    # Try to find and copy from any version that has it
    for srcver in docs-v5 docs-v4 docs-v3; do
      SRC="$INSTALL_DIR/content/en/$srcver/images/$img"
      if [ -f "$SRC" ] && [ ! -f "$DEST_DIR/$img" ]; then
        cp "$SRC" "$DEST_DIR/" 2>/dev/null || true
        break
      fi
    done
  done
done

echo "======================================================="
echo "Fixing incorrect relative links in markdown files done."
echo "======================================================="

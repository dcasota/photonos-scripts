#!/bin/bash

if [ -z "$INSTALL_DIR" ]; then
  echo "Error: Variable INSTALL_DIR is not set. This sub-script must be called by installer.sh"
  exit 1
fi

# Install custom enhancements before building
echo "Installing custom site enhancements (console, dark mode, code buttons)..."

# Create directories if they don't exist
mkdir -p "$INSTALL_DIR/layouts/partials/hooks"
mkdir -p "$INSTALL_DIR/layouts/shortcodes"
mkdir -p "$INSTALL_DIR/static/js/xterm"
mkdir -p "$INSTALL_DIR/static/css"

# Install body-end.html (console + code block enhancement)
cat > "$INSTALL_DIR/layouts/partials/hooks/body-end.html" << 'EOF_BODYEND'
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

<link rel="stylesheet" href="/css/dark-mode.css">
<link rel="stylesheet" href="/js/xterm/xterm.css">
<script src="/js/xterm/xterm.js"></script>
<script src="/js/xterm/xterm-addon-fit.js"></script>
<script src="/js/console.js"></script>
<script src="/js/dark-mode.js"></script>
<style>
.code-wrapper {
  position: relative;
  margin: 20px 0;
}
.code-button-container {
  position: absolute;
  top: 5px;
  right: -70px;
  display: flex;
  flex-direction: column;
  gap: 5px;
  z-index: 10;
}
.code-button-container button {
  width: 60px;
  padding: 4px 8px;
  font-size: 12px;
  border: none;
  border-radius: 3px;
  cursor: pointer;
  color: white;
}
.code-button-container .run-btn {
  background: #007bff;
}
.code-button-container .copy-btn {
  background: #28a745;
}
</style>
<script>
// Enhance code blocks with Run and Copy buttons (positioned outside)
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('pre code').forEach(codeBlock => {
    const text = codeBlock.textContent.trim();
    const lines = text.split('\n');
    
    // Skip if too many lines or has shebang
    if (lines.length > 5 || text.startsWith('#!')) return;
    
    const pre = codeBlock.parentElement;
    if (pre.parentElement && pre.parentElement.classList.contains('code-wrapper')) return;
    
    // Wrap pre in a container
    const wrapper = document.createElement('div');
    wrapper.className = 'code-wrapper';
    pre.parentNode.insertBefore(wrapper, pre);
    wrapper.appendChild(pre);
    
    // Create button container
    const container = document.createElement('div');
    container.className = 'code-button-container';
    
    // Run button
    const runBtn = document.createElement('button');
    runBtn.textContent = 'Run';
    runBtn.className = 'run-btn';
    runBtn.addEventListener('click', () => sendCommand(text));
    
    // Copy button
    const copyBtn = document.createElement('button');
    copyBtn.textContent = 'Copy';
    copyBtn.className = 'copy-btn';
    copyBtn.addEventListener('click', () => {
      navigator.clipboard.writeText(text).then(() => {
        const originalText = copyBtn.textContent;
        copyBtn.textContent = '✓';
        setTimeout(() => copyBtn.textContent = originalText, 2000);
      });
    });
    
    container.appendChild(runBtn);
    container.appendChild(copyBtn);
    wrapper.appendChild(container);
  });
});
</script>
EOF_BODYEND

# Install command-box shortcode
cat > "$INSTALL_DIR/layouts/shortcodes/command-box.html" << 'EOF_CMDBOX'
<div class="command-box" style="position: relative; margin: 20px 0;">
  <pre style="background: #f5f5f5; padding: 15px; border-radius: 5px; position: relative;"><code>{{ .Inner }}</code></pre>
  <div style="position: absolute; top: 10px; right: 10px; display: flex; gap: 5px;">
    <button class="run-in-console-btn" data-command="{{ .Inner | htmlUnescape }}" 
            style="background: #007bff; color: white; border: none; padding: 5px 10px; cursor: pointer; border-radius: 3px;">
      Run
    </button>
    <button class="copy-command-btn" data-command="{{ .Inner | htmlUnescape }}"
            style="background: #28a745; color: white; border: none; padding: 5px 10px; cursor: pointer; border-radius: 3px;">
      Copy
    </button>
  </div>
</div>
EOF_CMDBOX

# Install dark-mode.js
cat > "$INSTALL_DIR/static/js/dark-mode.js" << 'EOF_DARKJS'
(function() {
  const STORAGE_KEY = 'theme-preference';
  const THEME_ATTR = 'data-theme';
  
  function getTheme() {
    return localStorage.getItem(STORAGE_KEY) || 'light';
  }
  
  function saveTheme(theme) {
    localStorage.setItem(STORAGE_KEY, theme);
  }
  
  function updateIcon(theme) {
    const icon = document.getElementById('theme-icon');
    if (icon) {
      icon.className = theme === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
    }
  }
  
  function applyTheme(theme) {
    document.documentElement.setAttribute(THEME_ATTR, theme);
    updateIcon(theme);
  }
  
  function toggleTheme(e) {
    if (e) e.preventDefault();
    const currentTheme = getTheme();
    const newTheme = currentTheme === 'light' ? 'dark' : 'light';
    saveTheme(newTheme);
    applyTheme(newTheme);
  }
  
  function init() {
    const savedTheme = getTheme();
    applyTheme(savedTheme);
    
    const toggleButton = document.getElementById('theme-toggle');
    if (toggleButton) {
      toggleButton.addEventListener('click', toggleTheme);
    }
  }
  
  const savedTheme = getTheme();
  applyTheme(savedTheme);
  
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
EOF_DARKJS

# Install dark-mode.css
cat > "$INSTALL_DIR/static/css/dark-mode.css" << 'EOF_DARKCSS'
:root {
  --bg-color: #ffffff;
  --text-color: #212529;
  --link-color: #007bff;
  --border-color: #dee2e6;
  --code-bg: #f8f9fa;
  --navbar-bg: #ffffff;
  --navbar-text: #212529;
  --card-bg: #ffffff;
  --shadow-color: rgba(0, 0, 0, 0.1);
}

[data-theme="dark"] {
  --bg-color: #1a1a1a;
  --text-color: #e0e0e0;
  --link-color: #66b3ff;
  --border-color: #444;
  --code-bg: #2d2d2d;
  --navbar-bg: #212529;
  --navbar-text: #e0e0e0;
  --card-bg: #2d2d2d;
  --shadow-color: rgba(0, 0, 0, 0.5);
}

[data-theme="dark"] body {
  background-color: var(--bg-color);
  color: var(--text-color);
}

[data-theme="dark"] .navbar {
  background-color: var(--navbar-bg) !important;
  color: var(--navbar-text) !important;
}

[data-theme="dark"] .nav-link {
  color: var(--navbar-text) !important;
}

[data-theme="dark"] pre {
  background-color: var(--code-bg) !important;
  color: var(--text-color) !important;
}

[data-theme="dark"] code {
  background-color: var(--code-bg) !important;
  color: var(--text-color) !important;
}
EOF_DARKCSS

# Copy xterm files from photon-site if they exist
if [ -d "/var/www/photon-site/static/js/xterm" ]; then
  cp -r /var/www/photon-site/static/js/xterm/* "$INSTALL_DIR/static/js/xterm/"
fi

# Copy console.js from photon-site if it exists
if [ -f "/var/www/photon-site/static/js/console.js" ]; then
  cp /var/www/photon-site/static/js/console.js "$INSTALL_DIR/static/js/"
fi

echo "Custom enhancements installed successfully."

# Build site with Hugo
echo "Building site with Hugo..."
cd $INSTALL_DIR
set -o pipefail
/usr/local/bin/hugo --minify --baseURL "/" --logLevel debug --enableGitInfo -d public
if [ $? -ne 0 ]; then
  echo "Hugo build failed."
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
  exit 1
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
# Note: This is a fallback fix if markdown source wasn't fixed properly. Primary fix is in installer-weblinkfixes.sh
for ver in docs-v3 docs-v4 docs-v5; do
  QL_FILE="$SITE_DIR/$ver/quick-start-links/index.html"
  if [ -f "$QL_FILE" ]; then
    echo "Patching quick-start-links index.html for $ver to fix orphaned links..."
    sed -i 's|<a href=..\/..\/overview\/>Overview</a>|<a href=..\/overview\/>Overview</a>|g' $QL_FILE
    sed -i 's|<a href=..\/..\/installation-guide\/downloading-photon\/>Downloading Photon OS</a>|<a href=..\/installation-guide\/downloading-photon-os\/>Downloading Photon OS</a>|g' $QL_FILE
    sed -i 's|<a href=..\/..\/installation-guide\/downloading-photon-os\/>Downloading Photon OS</a>|<a href=..\/installation-guide\/downloading-photon-os\/>Downloading Photon OS</a>|g' $QL_FILE
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
    
    # Image path consolidation (FIXED - more specific regex to prevent false matches)
    # Only redirect actual paths containing /images/ subdirectory, not directory names ending in "images"
    rewrite ^/docs-v3/(.*)/images/(.+\.(png|jpg|jpeg|gif|svg|webp|ico))\$ /docs-v3/images/\$2 permanent;
    rewrite ^/docs-v4/(.*)/images/(.+\.(png|jpg|jpeg|gif|svg|webp|ico))\$ /docs-v4/images/\$2 permanent;
    rewrite ^/docs-v5/(.*)/images/(.+\.(png|jpg|jpeg|gif|svg|webp|ico))\$ /docs-v5/images/\$2 permanent;
    rewrite ^/docs/images/(.+)\$ /docs-v4/images/\$1 permanent;
    
    # Nested printview redirects - DISABLED to enable print functionality
    # These redirects were preventing the "Print entire section" feature from working
    # rewrite ^/printview/docs-v3/(.*)\$ /docs-v3/\$1 permanent;
    # rewrite ^/printview/docs-v4/(.*)\$ /docs-v4/\$1 permanent;
    # rewrite ^/printview/docs-v5/(.*)\$ /docs-v5/\$1 permanent;
    # rewrite ^/printview/(.*)\$ /docs-v5/\$1 permanent;
    
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
		echo "Error: Subpath /$subdir/ missing or incomplete. Check $SITE_DIR/$subdir/ and hugo_build.log."
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
  echo "Error: Search index not generated. Check Hugo build logs."
  exit 1
fi

echo "Installation complete! Access the Photon site at https://${IP_ADDRESS}/ (HTTP redirects to HTTPS)."

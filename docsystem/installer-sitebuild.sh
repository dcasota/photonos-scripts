#!/bin/bash

if [ -z "$INSTALL_DIR" ]; then
  echo "Error: Variable INSTALL_DIR is not set. This sub-script must be called by installer.sh."
  exit 1
fi

if [ -z "$SITE_DIR" ]; then
  echo "Error: Variable SITE_DIR is not set. This sub-script must be called by installer.sh."
  exit 1
fi

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

# Ensure Nginx conf.d directory exists
mkdir -p /etc/nginx/conf.d
# Remove default HTML
rm -rf /etc/nginx/html/* /usr/share/nginx/html/* /var/www/html/*
# Remove default Nginx configs
rm -f /etc/nginx/conf.d/default.conf /etc/nginx/default.d/*.conf /etc/nginx/sites-enabled/default /etc/nginx/nginx.conf.bak

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
    rewrite ^/overview/whats-new/?\$ /docs-v5/overview/what-is-new-in-photon-os-5/ permanent;
    rewrite ^/installation-guide/(.*)\$ /docs-v5/installation-guide/\$1 permanent;
    rewrite ^/administration-guide/(.*)\$ /docs-v5/administration-guide/\$1 permanent;
    rewrite ^/user-guide/(.*)\$ /docs-v5/user-guide/\$1 permanent;
    rewrite ^/troubleshooting-guide/(.*)\$ /docs-v5/troubleshooting-guide/\$1 permanent;
    rewrite ^/command-line-reference/(.*)\$ /docs-v5/command-line-reference/\$1 permanent;
    
    # Short-path redirects
    rewrite ^/deploying-a-containerized-application-in-photon-os/?\$ /docs-v5/installation-guide/deploying-a-containerized-application-in-photon-os/ permanent;
    rewrite ^/working-with-kickstart/?\$ /docs-v5/user-guide/kickstart-support-in-photon-os/ permanent;
    rewrite ^/kickstart-support-in-photon-os/?\$ /docs-v5/user-guide/kickstart-support-in-photon-os/ permanent;
    rewrite ^/run-photon-on-gce/?\$ /docs-v5/installation-guide/run-photon-on-gce/ permanent;
    rewrite ^/run-photon-aws-ec2/?\$ /docs-v5/installation-guide/run-photon-aws-ec2/ permanent;
    rewrite ^/what-is-new-in-photon-os-4/?\$ /docs-v4/what-is-new-in-photon-os-4/ permanent;
    rewrite ^/what-is-new-in-photon-os-5/?\$ /docs-v5/overview/what-is-new-in-photon-os-5/ permanent;
    rewrite ^/managing-packages-with-tdnf/?\$ /docs-v5/administration-guide/managing-packages-with-tdnf/ permanent;
    rewrite ^/solutions-to-common-problems/(.*)\$ /docs-v5/troubleshooting-guide/solutions-to-common-problems/\$1 permanent;
    
    # Photon RPM-OSTree short path redirects
    rewrite ^/installing-a-host-against-default-server-repository/?\$ /docs-v5/administration-guide/photon-rpm-ostree/installing-a-host-against-default-server-repository/ permanent;
    rewrite ^/installing-a-host-against-custom-server-repository/?\$ /docs-v5/administration-guide/photon-rpm-ostree/installing-a-host-against-custom-server-repository/ permanent;
    rewrite ^/host-updating-operations/?\$ /docs-v5/administration-guide/photon-rpm-ostree/host-updating-operations/ permanent;
    rewrite ^/creating-a-rpm-ostree-server/?\$ /docs-v5/administration-guide/photon-rpm-ostree/creating-a-rpm-ostree-server/ permanent;
    rewrite ^/package-oriented-server-operations/?\$ /docs-v5/administration-guide/photon-rpm-ostree/package-oriented-server-operations/ permanent;
    rewrite ^/file-oriented-server-operations/?\$ /docs-v5/administration-guide/photon-rpm-ostree/file-oriented-server-operations/ permanent;
    rewrite ^/remotes/?\$ /docs-v5/administration-guide/photon-rpm-ostree/remotes/ permanent;
    rewrite ^/concepts-in-action/?\$ /docs-v5/administration-guide/photon-rpm-ostree/concepts-in-action/ permanent;
    rewrite ^/install-or-rebase-to-photon-os-4/?\$ /docs-v4/administration-guide/photon-rpm-ostree/install-or-rebase-to-photon-os-4/ permanent;
    rewrite ^/install-or-rebase-to-photon-os-3/?\$ /docs-v3/administration-guide/photon-rpm-ostree/install-or-rebase-to-photon-os-3/ permanent;
    
    # Network configuration API redirects
    rewrite ^/network-configuration-manager-c-api/?\$ /docs-v5/administration-guide/managing-network-configuration/network-configuration-manager-c-api/ permanent;
    rewrite ^/network-configuration-manager-python-api/?\$ /docs-v5/administration-guide/managing-network-configuration/network-configuration-manager-python-api/ permanent;
    
    # Image path consolidation (FIXED - more specific regex to prevent false matches)
    # Only redirect actual paths containing /images/ subdirectory, not directory names ending in "images"
    rewrite ^/docs-v3/(.*)/images/(.+\.(png|jpg|jpeg|gif|svg|webp|ico))\$ /docs-v3/images/\$2 permanent;
    rewrite ^/docs-v4/(.*)/images/(.+\.(png|jpg|jpeg|gif|svg|webp|ico))\$ /docs-v4/images/\$2 permanent;
    rewrite ^/docs-v5/(.*)/images/(.+\.(png|jpg|jpeg|gif|svg|webp|ico))\$ /docs-v5/images/\$2 permanent;
    rewrite ^/docs/images/(.+)\$ /docs-v4/images/\$1 permanent;
    
    # Root-level images redirect (for paths like /images/xyz.png)
    rewrite ^/images/(.+\.(png|jpg|jpeg|gif|svg|webp|ico))\$ /docs-v5/images/\$1 permanent;
    
    # ========== PRINTVIEW REDIRECTS ==========
    # Fix broken paths in printview - redirect to actual content
    
    # Printview images - redirect to docs version images
    rewrite ^/printview/images/(.+)\$ /docs-v5/images/\$1 permanent;
    rewrite ^/printview/docs-v3/images/(.+)\$ /docs-v3/images/\$1 permanent;
    rewrite ^/printview/docs-v4/images/(.+)\$ /docs-v4/images/\$1 permanent;
    rewrite ^/printview/docs-v5/images/(.+)\$ /docs-v5/images/\$1 permanent;
    
    # Printview short paths - redirect to actual docs content
    rewrite ^/printview/overview/?\$ /docs-v5/overview/ permanent;
    rewrite ^/printview/overview/whats-new/?\$ /docs-v5/overview/what-is-new-in-photon-os-5/ permanent;
    rewrite ^/printview/installation-guide/(.*)\$ /docs-v5/installation-guide/\$1 permanent;
    rewrite ^/printview/administration-guide/(.*)\$ /docs-v5/administration-guide/\$1 permanent;
    rewrite ^/printview/user-guide/(.*)\$ /docs-v5/user-guide/\$1 permanent;
    rewrite ^/printview/troubleshooting-guide/(.*)\$ /docs-v5/troubleshooting-guide/\$1 permanent;
    rewrite ^/printview/command-line-reference/(.*)\$ /docs-v5/command-line-reference/\$1 permanent;
    
    # Printview Photon RPM-OSTree paths
    rewrite ^/printview/installing-a-host-against-default-server-repository/?\$ /docs-v5/administration-guide/photon-rpm-ostree/installing-a-host-against-default-server-repository/ permanent;
    rewrite ^/printview/installing-a-host-against-custom-server-repository/?\$ /docs-v5/administration-guide/photon-rpm-ostree/installing-a-host-against-custom-server-repository/ permanent;
    rewrite ^/printview/host-updating-operations/?\$ /docs-v5/administration-guide/photon-rpm-ostree/host-updating-operations/ permanent;
    rewrite ^/printview/creating-a-rpm-ostree-server/?\$ /docs-v5/administration-guide/photon-rpm-ostree/creating-a-rpm-ostree-server/ permanent;
    rewrite ^/printview/package-oriented-server-operations/?\$ /docs-v5/administration-guide/photon-rpm-ostree/package-oriented-server-operations/ permanent;
    rewrite ^/printview/file-oriented-server-operations/?\$ /docs-v5/administration-guide/photon-rpm-ostree/file-oriented-server-operations/ permanent;
    rewrite ^/printview/remotes/?\$ /docs-v5/administration-guide/photon-rpm-ostree/remotes/ permanent;
    rewrite ^/printview/concepts-in-action/?\$ /docs-v5/administration-guide/photon-rpm-ostree/concepts-in-action/ permanent;
    rewrite ^/printview/install-or-rebase-to-photon-os-4/?\$ /docs-v4/administration-guide/photon-rpm-ostree/install-or-rebase-to-photon-os-4/ permanent;
    rewrite ^/printview/install-or-rebase-to-photon-os-3/?\$ /docs-v3/administration-guide/photon-rpm-ostree/install-or-rebase-to-photon-os-3/ permanent;
    
    # Printview misc paths
    rewrite ^/printview/what-is-new-in-photon-os-4/?\$ /docs-v4/what-is-new-in-photon-os-4/ permanent;
    rewrite ^/printview/what-is-new-in-photon-os-5/?\$ /docs-v5/overview/what-is-new-in-photon-os-5/ permanent;
    rewrite ^/printview/managing-packages-with-tdnf/?\$ /docs-v5/administration-guide/managing-packages-with-tdnf/ permanent;
    rewrite ^/printview/kickstart-support-in-photon-os/?\$ /docs-v5/user-guide/kickstart-support-in-photon-os/ permanent;
    rewrite ^/printview/run-photon-on-gce/?\$ /docs-v5/installation-guide/run-photon-on-gce/ permanent;
    rewrite ^/printview/run-photon-aws-ec2/?\$ /docs-v5/installation-guide/run-photon-aws-ec2/ permanent;
    rewrite ^/printview/upgrading-to-photon-os-3/?\$ /docs-v3/installation-guide/upgrading-to-photon-os-3/ permanent;
    rewrite ^/printview/solutions-to-common-problems/(.*)\$ /docs-v5/troubleshooting-guide/solutions-to-common-problems/\$1 permanent;
    rewrite ^/printview/network-configuration-manager-c-api/?\$ /docs-v5/administration-guide/managing-network-configuration/network-configuration-manager-c-api/ permanent;
    rewrite ^/printview/network-configuration-manager-python-api/?\$ /docs-v5/administration-guide/managing-network-configuration/network-configuration-manager-python-api/ permanent;
    rewrite ^/printview/photon_admin/(.*)\$ /docs-v5/administration-guide/\$1 permanent;
    
    # ========== DOUBLE-PATH FIX ==========
    # Fix double nested paths like /docs-v3/docs-v3/
    rewrite ^/docs-v3/docs-v3/(.*)\$ /docs-v3/\$1 permanent;
    rewrite ^/docs-v4/docs-v4/(.*)\$ /docs-v4/\$1 permanent;
    rewrite ^/docs-v5/docs-v5/(.*)\$ /docs-v5/\$1 permanent;
    
    # Fix double slashes in paths
    rewrite ^(.*)//+(.*)\$ \$1/\$2 permanent;
    
    # ========== STATIC ASSETS REDIRECTS ==========
    # Redirect docs-v3 static assets to top-level assets
    rewrite ^/docs-v3/favicons/(.*)\$ /favicons/\$1 permanent;
    rewrite ^/docs-v3/img/(.*)\$ /img/\$1 permanent;
    rewrite ^/docs-v3/css/(.*)\$ /css/\$1 permanent;
    rewrite ^/docs-v3/js/(.*)\$ /js/\$1 permanent;
    rewrite ^/docs-v3/fonts/(.*)\$ /fonts/\$1 permanent;
    rewrite ^/docs-v3/scss/(.*)\$ /scss/\$1 permanent;
    rewrite ^/docs-v3/assets/(.*)\$ /assets/\$1 permanent;
    
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

if [ "$DEBUGYES" ]; then
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
fi

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
	# Verify search index generated
	if [ -f "$SITE_DIR/index.json" ]; then
	  echo "Search index generated successfully."
	else
	  echo "Error: Search index not generated. Check Hugo build logs."
	  exit 1
	fi	
else
  echo "Error: Build failed - index.html not found in $SITE_DIR. Check hugo_build.log."
  exit 1
fi

# Open firewall ports
mkdir -p /etc/systemd/scripts
if ! iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 80 -j ACCEPT
fi
if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 443 -j ACCEPT
fi
iptables-save > /etc/systemd/scripts/ip4save


echo "Installation complete! Access the Photon site at https://${IP_ADDRESS}/ (HTTP redirects to HTTPS)."

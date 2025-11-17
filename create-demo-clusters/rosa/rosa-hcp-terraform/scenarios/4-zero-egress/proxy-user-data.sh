x#!/bin/bash
# HTTP Proxy (Squid) setup script

set -e

# Install Squid
dnf install -y squid

# Configure Squid
cat > /etc/squid/squid.conf << 'EOF'
# Squid configuration for ROSA cluster

# Ports
http_port 3128

# Access Control Lists
acl localnet src 10.0.0.0/8
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

# Deny requests to certain unsafe ports
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# Allow localhost and local network
http_access allow localhost
http_access allow localnet

# Deny all other access
http_access deny all

# Cache settings
cache deny all

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log

# No proxy for
acl no_proxy dstdomain ${no_proxy}
always_direct allow no_proxy

# DNS settings
dns_nameservers 169.254.169.253

# Coredump directory
coredump_dir /var/spool/squid
EOF

# Start and enable Squid
systemctl enable squid
systemctl start squid

# Configure firewall
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --add-port=3128/tcp
firewall-cmd --reload

echo "HTTP Proxy setup complete" > /var/log/proxy-setup-complete.log
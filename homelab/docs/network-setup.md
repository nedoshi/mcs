# Network Setup for OpenShift Home Lab

Complete guide for designing and implementing network infrastructure for your OpenShift home lab.

## Network Architecture Overview

```
Internet
  │
  ├─ ISP Router/Modem (bridge mode)
  │
  └─ pfSense/OPNsense (192.168.1.1)
      │
      ├─ VLAN 10: Management (192.168.10.0/24)
      │   ├─ Jump/Bastion Host (192.168.10.10)
      │   ├─ Ansible Tower (192.168.10.11)
      │   └─ Network Management (192.168.10.20)
      │
      ├─ VLAN 100: OpenShift Cluster (192.168.100.0/24)
      │   ├─ Load Balancer VIP (192.168.100.10)
      │   ├─ Bootstrap (192.168.100.20) - temporary
      │   ├─ Control Plane 1 (192.168.100.101)
      │   ├─ Control Plane 2 (192.168.100.102)
      │   ├─ Control Plane 3 (192.168.100.103)
      │   ├─ Worker 1 (192.168.100.111)
      │   └─ Worker 2 (192.168.100.112)
      │
      ├─ VLAN 200: Storage (192.168.200.0/24)
      │   ├─ NAS/TrueNAS (192.168.200.10)
      │   └─ Backup Server (192.168.200.20)
      │
      └─ VLAN 300: Services (192.168.300.0/24)
          ├─ DNS/Pi-hole (192.168.300.10)
          ├─ DHCP/TFTP (192.168.300.11)
          ├─ Keycloak (192.168.300.20)
          └─ Container Registry (192.168.300.30)
```

## DNS Requirements

OpenShift **requires** proper DNS configuration. This is the most critical network component.

### Required DNS Records

#### Forward Records

```dns
; API and API-INT
api.ocp.lab.example.com.         IN  A  192.168.100.10
api-int.ocp.lab.example.com.     IN  A  192.168.100.10

; Ingress (Wildcard)
*.apps.ocp.lab.example.com.      IN  A  192.168.100.10

; Control Plane Nodes (Etcd)
etcd-0.ocp.lab.example.com.      IN  A  192.168.100.101
etcd-1.ocp.lab.example.com.      IN  A  192.168.100.102
etcd-2.ocp.lab.example.com.      IN  A  192.168.100.103

; SRV Records for Etcd
_etcd-server-ssl._tcp.ocp.lab.example.com.  86400  IN  SRV  0  10  2380  etcd-0.ocp.lab.example.com.
_etcd-server-ssl._tcp.ocp.lab.example.com.  86400  IN  SRV  0  10  2380  etcd-1.ocp.lab.example.com.
_etcd-server-ssl._tcp.ocp.lab.example.com.  86400  IN  SRV  0  10  2380  etcd-2.ocp.lab.example.com.

; Individual Node Records
bootstrap.ocp.lab.example.com.   IN  A  192.168.100.20
master-0.ocp.lab.example.com.    IN  A  192.168.100.101
master-1.ocp.lab.example.com.    IN  A  192.168.100.102
master-2.ocp.lab.example.com.    IN  A  192.168.100.103
worker-0.ocp.lab.example.com.    IN  A  192.168.100.111
worker-1.ocp.lab.example.com.    IN  A  192.168.100.112
```

#### Reverse Records (PTR)

```dns
; Reverse zone: 100.168.192.in-addr.arpa
10.100.168.192.in-addr.arpa.     IN  PTR  api.ocp.lab.example.com.
20.100.168.192.in-addr.arpa.     IN  PTR  bootstrap.ocp.lab.example.com.
101.100.168.192.in-addr.arpa.    IN  PTR  master-0.ocp.lab.example.com.
102.100.168.192.in-addr.arpa.    IN  PTR  master-1.ocp.lab.example.com.
103.100.168.192.in-addr.arpa.    IN  PTR  master-2.ocp.lab.example.com.
111.100.168.192.in-addr.arpa.    IN  PTR  worker-0.ocp.lab.example.com.
112.100.168.192.in-addr.arpa.    IN  PTR  worker-1.ocp.lab.example.com.
```

### DNS Implementation Options

#### Option 1: Dnsmasq (Simple, Recommended for Small Labs)

```bash
# Install dnsmasq
sudo yum install dnsmasq -y

# Edit /etc/dnsmasq.conf
cat <<EOF >> /etc/dnsmasq.conf
# Listen on cluster network interface
interface=eth0
bind-interfaces

# Domain
domain=lab.example.com
local=/lab.example.com/

# Upstream DNS
server=8.8.8.8
server=8.8.4.4

# DHCP range (optional, for PXE)
dhcp-range=192.168.100.50,192.168.100.99,12h

# Static DNS entries
address=/api.ocp.lab.example.com/192.168.100.10
address=/api-int.ocp.lab.example.com/192.168.100.10
address=/.apps.ocp.lab.example.com/192.168.100.10

# Individual hosts
host-record=bootstrap.ocp.lab.example.com,192.168.100.20
host-record=master-0.ocp.lab.example.com,192.168.100.101
host-record=master-1.ocp.lab.example.com,192.168.100.102
host-record=master-2.ocp.lab.example.com,192.168.100.103
host-record=worker-0.ocp.lab.example.com,192.168.100.111
host-record=worker-1.ocp.lab.example.com,192.168.100.112

# Etcd SRV records
srv-host=_etcd-server-ssl._tcp.ocp.lab.example.com,etcd-0.ocp.lab.example.com,2380,0,10
srv-host=_etcd-server-ssl._tcp.ocp.lab.example.com,etcd-1.ocp.lab.example.com,2380,0,10
srv-host=_etcd-server-ssl._tcp.ocp.lab.example.com,etcd-2.ocp.lab.example.com,2380,0,10

# CNAME for etcd
cname=etcd-0.ocp.lab.example.com,master-0.ocp.lab.example.com
cname=etcd-1.ocp.lab.example.com,master-1.ocp.lab.example.com
cname=etcd-2.ocp.lab.example.com,master-2.ocp.lab.example.com
EOF

# Enable and start
sudo systemctl enable --now dnsmasq
```

#### Option 2: BIND9 (Advanced, Full-Featured)

```bash
# Install BIND
sudo yum install bind bind-utils -y

# Configure zones in /etc/named.conf
# See official BIND documentation for detailed setup
```

#### Option 3: Pi-hole (DNS + Ad Blocking)

```bash
# Install Pi-hole
curl -sSL https://install.pi-hole.net | bash

# Add local DNS records via Pi-hole web UI
# http://pi.hole/admin
# Local DNS > Add new domain/IP

# Or via CLI
echo "192.168.100.10 api.ocp.lab.example.com" | sudo tee -a /etc/pihole/custom.list
echo "192.168.100.10 api-int.ocp.lab.example.com" | sudo tee -a /etc/pihole/custom.list
# ... add all records

# Restart DNS
pihole restartdns
```

### Testing DNS

```bash
# Test forward resolution
dig api.ocp.lab.example.com
dig test-app.apps.ocp.lab.example.com  # Should resolve to 192.168.100.10

# Test reverse resolution
dig -x 192.168.100.101

# Test SRV records
dig _etcd-server-ssl._tcp.ocp.lab.example.com SRV

# Test from OpenShift nodes
nslookup api.ocp.lab.example.com
nslookup api-int.ocp.lab.example.com
```

## DHCP Configuration

DHCP is optional but recommended for easier management and PXE boot support.

### Dnsmasq DHCP

```bash
# Add to /etc/dnsmasq.conf

# DHCP range
dhcp-range=192.168.100.50,192.168.100.99,12h

# Static reservations (match MAC addresses)
dhcp-host=52:54:00:00:01:01,master-0,192.168.100.101
dhcp-host=52:54:00:00:01:02,master-1,192.168.100.102
dhcp-host=52:54:00:00:01:03,master-2,192.168.100.103
dhcp-host=52:54:00:00:02:01,worker-0,192.168.100.111
dhcp-host=52:54:00:00:02:02,worker-1,192.168.100.112

# Default gateway
dhcp-option=3,192.168.100.1

# DNS server
dhcp-option=6,192.168.100.1

# Domain search
dhcp-option=15,lab.example.com

# PXE boot (for UPI installations)
dhcp-boot=pxelinux.0
enable-tftp
tftp-root=/var/lib/tftpboot
```

## Load Balancer Setup

Required for multi-node clusters. Options:

### Option 1: HAProxy (Recommended)

```bash
# Install HAProxy
sudo yum install haproxy -y

# Edit /etc/haproxy/haproxy.cfg
cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log         127.0.0.1 local2
    maxconn     4000
    daemon

defaults
    mode                    tcp
    log                     global
    option                  tcplog
    option                  dontlognull
    option                  redispatch
    retries                 3
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    maxconn                 3000

# API Server (6443)
frontend api
    bind *:6443
    default_backend api

backend api
    balance roundrobin
    option tcp-check
    server bootstrap 192.168.100.20:6443 check
    server master-0 192.168.100.101:6443 check
    server master-1 192.168.100.102:6443 check
    server master-2 192.168.100.103:6443 check

# Machine Config Server (22623)
frontend machine-config
    bind *:22623
    default_backend machine-config

backend machine-config
    balance roundrobin
    option tcp-check
    server bootstrap 192.168.100.20:22623 check
    server master-0 192.168.100.101:22623 check
    server master-1 192.168.100.102:22623 check
    server master-2 192.168.100.103:22623 check

# Ingress HTTP (80)
frontend ingress-http
    bind *:80
    default_backend ingress-http

backend ingress-http
    balance roundrobin
    option tcp-check
    server worker-0 192.168.100.111:80 check
    server worker-1 192.168.100.112:80 check

# Ingress HTTPS (443)
frontend ingress-https
    bind *:443
    default_backend ingress-https

backend ingress-https
    balance roundrobin
    option tcp-check
    server worker-0 192.168.100.111:443 check
    server worker-1 192.168.100.112:443 check
EOF

# Enable and start
sudo systemctl enable --now haproxy
```

### Option 2: Nginx (Alternative)

```bash
# Install Nginx
sudo yum install nginx nginx-mod-stream -y

# Edit /etc/nginx/nginx.conf
# Add stream block for TCP load balancing
```

### Option 3: MetalLB (In-Cluster Load Balancer)

For SNO or when you don't want external load balancer.

```bash
# Deploy MetalLB after cluster installation
# See: https://metallb.universe.tf/
```

## Firewall Configuration

### pfSense/OPNsense Rules

```
# Allow from Management VLAN to Cluster VLAN
Source: 192.168.10.0/24
Destination: 192.168.100.0/24
Action: Allow

# Allow from Cluster VLAN to Internet (for image pulls)
Source: 192.168.100.0/24
Destination: Any
Action: Allow

# Allow from home network to ingress (for accessing apps)
Source: 192.168.1.0/24
Destination: 192.168.100.10:80,443
Action: Allow

# Block everything else
Source: Any
Destination: 192.168.100.0/24
Action: Deny
```

### Linux Firewall (firewalld)

```bash
# On DNS/DHCP server
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --permanent --add-service=dhcp
sudo firewall-cmd --reload

# On load balancer
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=22623/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload

# On OpenShift nodes (if using host firewall)
# Usually disable host firewall on OpenShift nodes
sudo systemctl stop firewalld
sudo systemctl disable firewalld
```

## VLAN Configuration

### On Managed Switch

```bash
# VLAN 10 - Management
- Tagged on trunk port to firewall
- Untagged on port 1-4 (management devices)

# VLAN 100 - Cluster
- Tagged on trunk port to firewall
- Untagged on port 5-12 (OpenShift nodes)

# VLAN 200 - Storage
- Tagged on trunk port to firewall
- Untagged on port 13-16 (storage devices)

# VLAN 300 - Services
- Tagged on trunk port to firewall
- Untagged on port 17-20 (service VMs)
```

### On pfSense

```bash
# Interface > Assignments > VLANs
- Add VLAN 10 on LAN interface
- Add VLAN 100 on LAN interface
- Add VLAN 200 on LAN interface
- Add VLAN 300 on LAN interface

# Interface > Assignments
- Add new interfaces for each VLAN
- Enable and configure IP addresses
```

## Network Validation Checklist

Before starting OpenShift installation:

- [ ] DNS forward resolution works for all required records
- [ ] DNS reverse resolution works for all node IPs
- [ ] DNS SRV records for etcd are correct
- [ ] DHCP assigns correct IPs (if using DHCP)
- [ ] Load balancer responds on ports 6443, 22623, 80, 443
- [ ] Nodes can reach internet (or mirror registry)
- [ ] Nodes can reach each other
- [ ] Time synchronization (NTP) configured
- [ ] Firewall rules allow required traffic

## Testing Network Setup

```bash
# From a node, test DNS
dig api.ocp.lab.example.com
dig api-int.ocp.lab.example.com
dig test.apps.ocp.lab.example.com
dig _etcd-server-ssl._tcp.ocp.lab.example.com SRV

# Test load balancer
curl -k https://api.ocp.lab.example.com:6443/version
# Should return 404 or connection refused (expected before install)

# Test internet connectivity
curl -I https://quay.io
curl -I https://registry.redhat.io

# Test node-to-node communication
ping 192.168.100.101
nc -zv 192.168.100.101 22
```

## Common Network Issues

### Issue: DNS Not Resolving

```bash
# Check DNS server is running
systemctl status dnsmasq

# Check DNS from OpenShift node
dig @192.168.100.1 api.ocp.lab.example.com

# Check /etc/resolv.conf on nodes
cat /etc/resolv.conf
# Should point to your DNS server
```

### Issue: Load Balancer Not Working

```bash
# Check HAProxy status
systemctl status haproxy

# Check HAProxy logs
journalctl -u haproxy -f

# Test backend connectivity
nc -zv 192.168.100.101 6443
```

### Issue: Nodes Can't Reach Internet

```bash
# Check NAT/routing on firewall
# Check firewall rules
# Test from node
curl -I https://google.com
```

## Next Steps

1. Verify all DNS records are configured
2. Test load balancer (if multi-node)
3. Verify internet connectivity from cluster network
4. Proceed to [Installation Walkthrough](installation-walkthrough.md)

## References

- [OpenShift Networking Requirements](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal-network-customizations.html)
- [HAProxy Documentation](http://www.haproxy.org/)
- [Dnsmasq Documentation](http://www.thekelleys.org.uk/dnsmasq/doc.html)

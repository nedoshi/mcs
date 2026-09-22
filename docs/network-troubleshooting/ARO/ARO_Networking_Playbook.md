# ARO Networking Playbook

A complete guide to networking in Azure Red Hat OpenShift (ARO). This document takes you from zero networking knowledge through packet-level understanding of every traffic flow.

---

## Table of Contents

1. [Introduction & How to Read This Document](#1-introduction--how-to-read-this-document)
2. [Networking Fundamentals](#2-networking-fundamentals)
3. [Azure Networking Fundamentals](#3-azure-networking-fundamentals)
4. [Azure Virtualization & Accelerated Networking](#4-azure-virtualization--accelerated-networking)
5. [Kubernetes Networking Fundamentals](#5-kubernetes-networking-fundamentals)
6. [OpenShift Networking Layer](#6-openshift-networking-layer)
7. [ARO Architecture — The Complete Picture](#7-aro-architecture--the-complete-picture)
8. [How Apps Are Exposed in ARO](#8-how-apps-are-exposed-in-aro)
9. [IP Address Architecture](#9-ip-address-architecture)
10. [BGP and Hybrid Networking with ExpressRoute](#10-bgp-and-hybrid-networking-with-expressroute)
11. [DNS Architecture in ARO](#11-dns-architecture-in-aro)
12. [Security Architecture](#12-security-architecture)
13. [Scenario Matrix & Traffic Exposure Table](#13-scenario-matrix--traffic-exposure-table)
14. [Complete Command Reference](#14-complete-command-reference)
15. [Troubleshooting Decision Tree](#15-troubleshooting-decision-tree)

---

## 1. Introduction & How to Read This Document

### Who This Is For

This playbook serves three audiences:

| Audience | Start At | Goal |
|----------|----------|------|
| **Beginner** — no networking experience | Section 2 | Understand what a packet is, what an IP address does, and how traffic moves |
| **Intermediate** — knows TCP/IP, new to Azure/K8s | Section 3 | Understand how Azure and Kubernetes networking layers compose |
| **Advanced** — knows K8s, needs ARO depth | Section 7 | Packet-level understanding of every ARO traffic flow |

### Learning Path

```text
Section 2: Networking Fundamentals
    "What is a packet? What is an IP address?"
        |
        v
Section 3: Azure Networking Fundamentals
    "What is a VNet? What is an NSG?"
        |
        v
Section 4: Azure Virtualization & Accelerated Networking
    "How does a physical server become a virtual machine?"
        |
        v
Section 5: Kubernetes Networking
    "How do pods get IPs? How do Services work?"
        |
        v
Section 6: OpenShift Networking
    "What does OVN add? What is Geneve?"
        |
        v
Section 7: ARO Architecture
    "How do master and worker nodes connect? What does the ARO RP do?"
        |
        v
Section 8: How Apps Are Exposed
    "Show me the packet path from a user's browser to my pod"
        |
        v
Sections 9-15: Deep Dives
    "BGP, DNS, Security, Troubleshooting"
```

### Conventions Used

- **WHY blocks** explain why a component exists — not just what it does
- **ASCII diagrams** show packet-level flows with IP address transformations
- **Command blocks** are copy-paste ready for ARO clusters
- Arrows in diagrams: `-->` means "packet travels to", `==>` means "encapsulated tunnel"

---

## 2. Networking Fundamentals

This section is for readers who are new to networking. If you already understand TCP/IP, subnets, and routing, skip to Section 3.

### 2.1 What Is a Network?

A network is a group of computers that can send data to each other. Your home Wi-Fi is a network. The internet is a network of networks.

Every device on a network needs two things:
1. **An address** — so other devices can find it (like a mailing address)
2. **A way to send data** — a physical or virtual connection (like a road)

> **WHY:** ARO runs your applications on virtual machines (Azure VMs) inside Microsoft's data centers. These VMs need to talk to each other, to the ARO resource provider, and to the internet. Understanding networking is understanding how that communication happens.

### 2.2 IP Addresses

An IP (Internet Protocol) address is a number assigned to every device on a network. Think of it as a phone number for computers.

**IPv4 format:** Four numbers separated by dots, each between 0 and 255.

```text
Example: 10.0.1.42

  10  .   0  .   1  .  42
  |       |       |      |
  First   Second  Third  Fourth
  octet   octet   octet  octet
```

Each octet is 8 bits, so an IPv4 address is 32 bits total. That gives us about 4.3 billion possible addresses.

**Two types of IP addresses:**

| Type | Range Examples | Who Can See It |
|------|---------------|----------------|
| **Public** | 20.102.35.120 | Everyone on the internet |
| **Private** | 10.0.1.42, 172.16.0.5, 192.168.1.1 | Only devices on the same private network |

**Private IP ranges (RFC 1918):**

| Range | Size | Common Use |
|-------|------|-----------|
| 10.0.0.0 – 10.255.255.255 | 16 million addresses | Cloud VNets, large networks |
| 172.16.0.0 – 172.31.255.255 | 1 million addresses | Medium networks |
| 192.168.0.0 – 192.168.255.255 | 65,000 addresses | Home networks |

> **WHY:** ARO uses private IP addresses for everything inside the VNet — master nodes, worker nodes, pods, services. Public IPs are only assigned to load balancers that need to accept traffic from the internet. Understanding which IPs are private vs. public tells you what can be reached from where.

### 2.3 Subnets and CIDR Notation

A **subnet** is a smaller section of a network. Think of a network as a city and subnets as neighborhoods.

**CIDR notation** is shorthand for describing a range of IP addresses:

```text
10.0.1.0/24

  10.0.1.0  = the starting address (network address)
  /24       = the first 24 bits are fixed, the last 8 bits can vary

  This means: 10.0.1.0 through 10.0.1.255 (256 addresses)
```

**How to read CIDR:**

| CIDR | Fixed Bits | Available IPs | Example Range |
|------|-----------|---------------|---------------|
| /32 | All 32 | 1 (single host) | 10.0.1.42/32 = just 10.0.1.42 |
| /24 | First 24 | 256 | 10.0.1.0/24 = 10.0.1.0 – 10.0.1.255 |
| /16 | First 16 | 65,536 | 10.0.0.0/16 = 10.0.0.0 – 10.0.255.255 |
| /8 | First 8 | 16,777,216 | 10.0.0.0/8 = 10.0.0.0 – 10.255.255.255 |

The smaller the number after the slash, the bigger the network.

> **WHY:** ARO uses multiple CIDR ranges for different purposes. The VNet might be 10.0.0.0/16, the master subnet 10.0.0.0/27, the worker subnet 10.0.1.0/24, the pod network 10.128.0.0/14, and the service network 172.30.0.0/16. If these overlap, packets get misrouted and things break. Understanding CIDR tells you whether two ranges conflict.

### 2.4 The TCP/IP Stack

When your browser loads a web page, the data doesn't teleport. It passes through a stack of layers, each adding its own envelope (called a header) around the data.

```text
Layer 7 — Application    HTTP request: "GET /index.html"
    |                         |
    v                         v
Layer 4 — Transport       TCP header added: source port 54321, dest port 443
    |                         |
    v                         v
Layer 3 — Network         IP header added: source 10.0.1.42, dest 20.102.35.120
    |                         |
    v                         v
Layer 2 — Data Link       Ethernet header added: source MAC, dest MAC
    |                         |
    v                         v
Layer 1 — Physical        Electrical signals on the wire / radio waves
```

**Each layer does one job:**

**Layer 1 — Physical:** The actual cables, radio waves, or fiber optics that carry signals.

> **WHY:** In Azure, you never touch Layer 1. Microsoft owns the physical hardware. But the performance of your network (bandwidth, latency) is determined by the physical infrastructure underneath.

**Layer 2 — Data Link:** Handles communication between devices on the same local network segment using MAC addresses (hardware addresses burned into every network card).

> **WHY:** Inside an Azure data center, Layer 2 is how the physical servers communicate on the same rack. ARO's overlay network (Geneve) creates a virtual Layer 2 on top of the physical Layer 3, so pods think they're on the same local network even when they're on different physical servers.

**Layer 3 — Network (IP):** Handles routing packets between different networks using IP addresses. This is where routing decisions happen — "which way should this packet go?"

> **WHY:** This is the most important layer for ARO. Every routing decision — pod to pod, pod to internet, pod to on-prem database — happens at Layer 3. NSGs, UDRs, Azure Firewall, NAT Gateways, and ExpressRoute gateways all operate at Layer 3.

**Layer 4 — Transport (TCP/UDP):** Handles reliable delivery (TCP) or fast delivery (UDP) between specific applications using port numbers. Port 443 = HTTPS, Port 80 = HTTP, Port 5432 = PostgreSQL.

> **WHY:** NSGs in Azure filter by port number, which is a Layer 4 concept. When you create an NSG rule allowing port 443, you're making a Layer 4 decision. Kubernetes Services map one port to another (e.g., external port 80 → pod port 8080), which is also Layer 4.

**Layer 7 — Application (HTTP, gRPC, DNS):** The actual application data — web pages, API calls, database queries.

> **WHY:** OpenShift Routes operate at Layer 7. The HAProxy router reads the HTTP Host header to decide which backend pod should receive the request. This is more intelligent than Layer 4 load balancing because it can route based on URLs, headers, and cookies.

### 2.5 What Is a Packet?

A **packet** is a small chunk of data with addressing information wrapped around it. When you send a 1 MB file, it gets broken into many packets (usually around 1500 bytes each), sent individually across the network, and reassembled at the destination.

```text
+------------------------------------------------------+
|                     PACKET                            |
+------------------------------------------------------+
| Ethernet Header | IP Header | TCP Header | Data      |
| (14 bytes)      | (20 bytes)| (20 bytes) | (payload) |
|                 |           |            |           |
| Dest MAC        | Dest IP   | Dest Port  | "GET /"   |
| Source MAC       | Source IP  | Source Port |           |
| EtherType       | TTL, Proto | Seq/Ack #  |           |
+------------------------------------------------------+

Total Maximum Size (MTU) = 1500 bytes typically
    Azure supports jumbo frames in some configurations
```

> **WHY:** Every time a packet passes through an ARO component — an NSG, a load balancer, an Azure Firewall, an OVN router — the headers get inspected and possibly modified. Understanding packet structure is understanding what each component can see and change.

### 2.6 How Routing Works

When a computer sends a packet, it checks its **routing table** — a list of rules that say "if the destination is in this range, send the packet this way."

```text
Example Routing Table:
+-------------------+-------------+-------------------+
| Destination       | Gateway     | Interface         |
+-------------------+-------------+-------------------+
| 10.0.1.0/24       | direct      | eth0 (local)      |
| 10.0.0.0/16       | 10.0.1.1    | eth0 (via router) |
| 0.0.0.0/0         | 10.0.1.1    | eth0 (default)    |
+-------------------+-------------+-------------------+

When sending to 10.0.1.50:
  → Matches 10.0.1.0/24 → send directly on local network

When sending to 10.0.2.50:
  → Matches 10.0.0.0/16 → send to gateway 10.0.1.1

When sending to 8.8.8.8:
  → Matches 0.0.0.0/0 (default route) → send to gateway 10.0.1.1
```

The **most specific route wins**. If a destination matches both 10.0.0.0/16 and 10.0.1.0/24, the /24 wins because it's more specific (longer prefix).

> **WHY:** Azure route tables, ExpressRoute advertised routes, and the Linux routing table inside every pod all work this way. When troubleshooting "why can't pod A reach service B," the answer is almost always in a routing table somewhere. ARO has routing tables at the Azure level (UDRs), the node level (Linux), and the overlay level (OVN).

### 2.7 DNS Fundamentals

**DNS (Domain Name System)** translates human-readable names (like `google.com`) into IP addresses (like `142.250.80.46`). Without DNS, you'd have to memorize IP addresses for every website.

```text
DNS Resolution Flow:

  Your Computer                DNS Resolver              Root DNS
  "what is google.com?"  --->  "let me check"  ------>  "ask .com server"
                                    |                        |
                                    v                        |
                               .com DNS Server  <------------+
                               "ask google's DNS"
                                    |
                                    v
                               Google's DNS Server
                               "142.250.80.46"
                                    |
                                    v
  Your Computer  <-----------  "142.250.80.46"
```

**DNS Record Types:**

| Type | Purpose | Example |
|------|---------|---------|
| **A** | Name → IPv4 address | `app.example.com → 10.0.1.42` |
| **AAAA** | Name → IPv6 address | `app.example.com → 2001:db8::1` |
| **CNAME** | Name → another name (alias) | `www.example.com → app.example.com` |
| **SRV** | Service discovery | `_http._tcp.example.com → port 80 on app.example.com` |

> **WHY:** ARO uses DNS everywhere. Inside the cluster, CoreDNS resolves service names (my-service.my-namespace.svc.cluster.local) to ClusterIP addresses. Outside the cluster, Azure DNS resolves *.apps.cluster.example.com to the load balancer's IP. Private ARO clusters use Azure DNS Private Zones so the same name resolves differently depending on whether you're inside or outside the VNet.

### 2.8 Load Balancing Concepts

A **load balancer** distributes incoming traffic across multiple backend servers. Instead of clients connecting directly to one server (which could get overwhelmed), they connect to the load balancer, which picks a healthy server.

```text
Without Load Balancer:               With Load Balancer:

Client ---> Server 1 (overloaded!)    Client ---> Load Balancer --+--> Server 1
Client ---> Server 1 (overloaded!)                                +--> Server 2
Client ---> Server 1 (crash!)                                     +--> Server 3
```

**Types of load balancing:**

| Type | Layer | What It Sees | Decision Based On |
|------|-------|-------------|-------------------|
| **L4 (Network)** | Layer 4 | IP + Port | Connection round-robin, least connections |
| **L7 (Application)** | Layer 7 | Full HTTP request | URL path, Host header, cookies |

> **WHY:** ARO uses both types. The Azure Load Balancer (Standard SKU) does L4 load balancing — it sees IP addresses and ports but not HTTP headers. The OpenShift router (HAProxy) does L7 load balancing — it reads the HTTP Host header to route requests to the correct application. These work together: Azure LB → HAProxy Router → Application Pod.

### 2.9 Encryption and TLS

**TLS (Transport Layer Security)** encrypts data in transit so attackers can't read it. When you see HTTPS (instead of HTTP), TLS is in use.

```text
Without TLS:                        With TLS:
Client: "password=secret123"        Client: "x7$kQ!m@#..."
    |                                   |
    v (attacker can read!)              v (attacker sees garbage)
Server receives "password=secret123" Server decrypts to "password=secret123"
```

**TLS Termination** — where the encryption gets decrypted:

| Strategy | Where TLS Ends | Pod Sees |
|----------|---------------|----------|
| **Edge** | At the load balancer/router | Unencrypted HTTP |
| **Passthrough** | At the application pod | The pod decrypts |
| **Re-encrypt** | Decrypted at router, re-encrypted to pod | Two TLS sessions |

> **WHY:** ARO OpenShift Routes support all three TLS strategies. Edge termination is simplest — the router handles certificates. Passthrough is required when the application must control its own certificates (e.g., mutual TLS). Re-encrypt adds defense-in-depth — traffic is encrypted even inside the cluster network.

---

## 3. Azure Networking Fundamentals

This section explains every Azure networking component that ARO uses. Each component has a WHY block explaining its role in an ARO cluster.

### 3.1 VNet (Virtual Network)

A **VNet** is your own private network inside Azure. It's logically isolated — no other Azure customer can see or access your VNet's resources unless you explicitly allow it.

```text
+---------------------------------------------------------------+
|                      Azure Region (eastus)                     |
|                                                                |
|  +----------------------------------------------------------+ |
|  |                   Your VNet (10.0.0.0/16)                 | |
|  |                                                           | |
|  |  You control:                                             | |
|  |    - IP address range (CIDR)                              | |
|  |    - Subnets                                              | |
|  |    - Route tables (UDRs)                                  | |
|  |    - Network Security Groups (NSGs)                       | |
|  |    - Service Endpoints                                    | |
|  |    - Private Endpoints                                    | |
|  |                                                           | |
|  +----------------------------------------------------------+ |
|                                                                |
|  +----------------------------------------------------------+ |
|  |           Someone Else's VNet (172.16.0.0/16)             | |
|  |           (completely isolated from yours)                | |
|  +----------------------------------------------------------+ |
|                                                                |
+---------------------------------------------------------------+
```

> **WHY:** ARO deploys both master nodes and worker nodes inside a VNet you own (or provide). This gives you full control over network isolation, IP addressing, and connectivity. Unlike ROSA HCP (where the control plane is in Red Hat's account), ARO puts everything in your Azure subscription. The trade-off is you pay for the master node VMs, but you get full VNet-level control over the entire cluster.

### 3.2 Subnets (Master and Worker)

A **subnet** is a partition of your VNet's IP range. ARO requires two dedicated subnets:

**Master subnet:** Holds the 3 control plane (master) nodes.
**Worker subnet:** Holds all worker nodes that run your application pods.

```text
+------------------------------------------------------------------+
|                    VNet: 10.0.0.0/16                              |
|                                                                   |
|  +----------------------------+   +----------------------------+  |
|  | Master Subnet              |   | Worker Subnet              |  |
|  | 10.0.0.0/27                |   | 10.0.1.0/24                |  |
|  | (minimum /27 = 32 IPs)     |   | (minimum /27 = 32 IPs)     |  |
|  |                            |   |                            |  |
|  | Master 1: 10.0.0.4         |   | Worker 1: 10.0.1.4         |  |
|  | Master 2: 10.0.0.5         |   | Worker 2: 10.0.1.5         |  |
|  | Master 3: 10.0.0.6         |   | Worker 3: 10.0.1.6         |  |
|  |                            |   | Worker 4: 10.0.1.7         |  |
|  | API Server LB: 10.0.0.10   |   |                            |  |
|  | (internal LB frontend)     |   | Ingress LB: 10.0.1.10      |  |
|  |                            |   | (or public IP)             |  |
|  +----------------------------+   +----------------------------+  |
|                                                                   |
|  Note: Azure reserves 5 IPs per subnet:                          |
|    .0 (network), .1 (gateway), .2 (DNS), .3 (DNS), .255 (bcast)  |
|                                                                   |
|  Master subnet /27 = 32 IPs - 5 reserved = 27 usable             |
|  Worker subnet /24 = 256 IPs - 5 reserved = 251 usable           |
+------------------------------------------------------------------+
```

> **WHY:** ARO requires two separate subnets because master and worker nodes have different security profiles. Master nodes run the API server, etcd, and controllers — they need stricter access controls. Worker nodes run application pods — they need more IPs for scaling. Separating them allows different NSG rules per subnet. The master subnet can be small (/27) because there are always exactly 3 masters. The worker subnet should be larger to accommodate scaling.

### 3.3 NSG (Network Security Group)

An **NSG** is a virtual firewall that contains security rules controlling inbound and outbound traffic. In ARO, NSGs are applied at the **subnet level** (not the individual NIC level, as is common in other Azure setups).

```text
Inbound Rules (applied to worker subnet):
+----------+----------+-----------+-----------+---------------------+
| Priority | Protocol | Port      | Source    | Description         |
+----------+----------+-----------+-----------+---------------------+
| 100      | TCP      | 6443      | VNet      | API server access   |
| 110      | TCP      | 10250     | VNet      | Kubelet from CP     |
| 120      | TCP      | 30000-32767| AzureLB  | NodePort via LB     |
| 130      | UDP      | 6081      | VNet      | Geneve overlay      |
| 140      | TCP      | 9000-9999 | VNet      | Node-to-node        |
| 4096     | Any      | Any       | VNet      | Allow VNet intra    |
| 65500    | Any      | Any       | Any       | Deny all default    |
+----------+----------+-----------+-----------+---------------------+

Outbound Rules:
+----------+----------+-----------+-----------+---------------------+
| Priority | Protocol | Port      | Dest      | Description         |
+----------+----------+-----------+-----------+---------------------+
| 100      | Any      | Any       | Any       | Allow all outbound  |
+----------+----------+-----------+-----------+---------------------+
```

**NSGs are stateful — just like AWS Security Groups:**

```text
1. Pod sends request to internet (outbound)
   Packet: src=10.0.1.4:54321 → dst=93.184.216.34:443
   NSG checks OUTBOUND rules → ALLOWED

2. Internet sends response (inbound)
   Packet: src=93.184.216.34:443 → dst=10.0.1.4:54321
   NSG sees this is a RESPONSE to #1 → AUTOMATICALLY ALLOWED
   (no inbound rule needed for return traffic)
```

> **WHY:** NSGs are the primary network firewall for ARO nodes. ARO creates default NSGs during cluster installation that allow control plane communication (port 6443 for API, port 10250 for kubelet), overlay traffic (UDP 6081 for Geneve), and node-to-node communication. If you modify NSG rules incorrectly, the control plane loses contact with workers and the cluster goes unhealthy. Critical difference from AWS: in ARO, NSGs are typically applied at the subnet level (one NSG per subnet), not per-NIC.

### 3.4 UDR (User Defined Routes) / Route Tables

A **UDR** is a custom route that overrides Azure's default system routes. Azure provides built-in routes (VNet traffic stays in VNet, internet goes to Azure's internet gateway), but you can add your own.

```text
Default System Routes (auto-created by Azure):
+-------------------+-------------------+
| Destination       | Next Hop          |
+-------------------+-------------------+
| 10.0.0.0/16       | VNet (local)      |
| 0.0.0.0/0         | Internet          |
+-------------------+-------------------+

After Adding UDRs:
+-------------------+-------------------+----------------------------+
| Destination       | Next Hop          | Why                        |
+-------------------+-------------------+----------------------------+
| 10.0.0.0/16       | VNet (local)      | System route (cannot change)|
| 192.168.0.0/16    | VNet Gateway      | Route to on-prem via ER    |
| 0.0.0.0/0         | Azure Firewall    | Force-tunnel all traffic   |
|                   | (10.0.2.4)        | through firewall           |
+-------------------+-------------------+----------------------------+
```

> **WHY:** UDRs control where packets go after leaving a node's NIC. The most common use in ARO is **forced tunneling** — routing all outbound traffic through an Azure Firewall or NVA (Network Virtual Appliance) for inspection and logging. Without UDRs, all internet traffic goes directly through Azure's internet gateway, bypassing any security inspection. For private clusters or regulated environments, UDRs are essential.

### 3.5 Azure Private Link / Private Endpoints

**Private Link** creates a private connection to an Azure service (or another VNet's service) that stays on Microsoft's backbone network, never crossing the internet.

A **Private Endpoint** is a network interface (NIC) created in your VNet that connects to a Private Link service.

```text
Without Private Link:                   With Private Link:
Pod → Node → Internet →                 Pod → Node → Private Endpoint NIC →
Azure Storage (public endpoint)          Azure Storage (private, stays on backbone)

Risk: Traffic crosses internet           Risk: None — traffic never leaves Azure
```

```text
ARO uses Private Link for the ARO Resource Provider:

+----------------------------------+       +----------------------------------+
| Microsoft/Red Hat Managed        |       | Your Azure Subscription          |
|                                  |       |                                  |
| ARO Resource Provider (RP)       |       | Your VNet                        |
|                                  |       |                                  |
| "I need to manage your cluster"  |       | Private Endpoint (NIC)           |
|         |                        |       |   10.0.0.20                      |
|         v                        |       |         |                        |
| Private Link Service             |------>| Routes to cluster API            |
| (provider side)                  |  PL   | server on master nodes           |
+----------------------------------+       +----------------------------------+
```

> **WHY:** The ARO Resource Provider (RP) — managed jointly by Microsoft and Red Hat — needs to manage your cluster (upgrades, monitoring, support access). Private Link provides this access without requiring public API endpoints. For private ARO clusters, the API server has no public IP; the RP reaches it exclusively via Private Link. This is a critical security boundary — the RP can manage the cluster but never touches your application workloads directly.

### 3.6 Azure Load Balancer (Standard SKU)

Azure Load Balancer distributes traffic across backend VMs. ARO uses the **Standard SKU** which supports both public and internal (private) configurations.

```text
Public Load Balancer:                    Internal Load Balancer:

Internet                                 Corporate Network
    |                                        |
    v                                        v
+-------------------+                   +-------------------+
| Azure LB          |                   | Azure LB          |
| Frontend:         |                   | Frontend:         |
|  20.102.35.120    |                   |  10.0.1.10        |
|  (Public IP)      |                   |  (Private IP)     |
+---+------+--------+                   +---+------+--------+
    |      |                                |      |
    v      v                                v      v
  Node1  Node2                            Node1  Node2
```

ARO creates two load balancers:
1. **API LB** — for the Kubernetes API server (port 6443), either public or private
2. **Ingress LB** — for application traffic (ports 80/443), either public or private

> **WHY:** The Azure LB is the entry point for all traffic into the ARO cluster. The API LB routes `oc` commands and API calls to the master nodes. The Ingress LB routes application HTTP/HTTPS traffic to the router pods on worker nodes. Standard SKU is required (not Basic) because it supports Availability Zones, NSG integration, and outbound rules that ARO depends on.

### 3.7 Azure Front Door / Application Gateway

**Application Gateway** is Azure's L7 load balancer (similar to AWS ALB). **Azure Front Door** is a global L7 load balancer with WAF and CDN capabilities.

```text
Azure Front Door / Application Gateway in front of ARO:

Internet
    |
    v
+---------------------+
| Azure Front Door    |
| or App Gateway      |
|                     |
| - WAF rules         |
| - TLS termination   |
| - URL-based routing |
| - Client cert auth  |
+----------+----------+
           |
           v
+---------------------+
| ARO Ingress LB      |
| (public or internal) |
+----------+----------+
           |
           v
     Router Pods → App Pods
```

> **WHY:** ARO's built-in ingress (HAProxy router behind Azure LB) handles basic routing and TLS. But enterprises often need WAF protection, geographic routing, or client certificate authentication that the built-in ingress doesn't provide. Azure Front Door or Application Gateway sits in front of the ARO load balancer to add these L7 features. This is the "custom front door" pattern.

### 3.8 ExpressRoute

**ExpressRoute** is a dedicated private connection between your on-premises network and Azure, provided by a connectivity partner (like Equinix, AT&T, or Megaport). It does NOT go over the public internet.

```text
Without ExpressRoute:                    With ExpressRoute:

On-Prem → Internet → Azure               On-Prem → Partner Edge → Azure
(encrypted VPN tunnel)                    (dedicated fiber, private peering)

Bandwidth: Limited by ISP                Bandwidth: 50 Mbps to 100 Gbps
Latency: Variable                        Latency: Consistent, low
SLA: Best effort                         SLA: 99.95% uptime
```

> **WHY:** ExpressRoute is how production ARO clusters connect to on-premises data centers. If your pods need to reach on-prem databases, Active Directory, monitoring systems, or file shares, ExpressRoute provides a reliable, high-bandwidth, low-latency private connection. It's the Azure equivalent of AWS Direct Connect. ExpressRoute supports BGP for dynamic route exchange — your on-prem router advertises its networks to Azure, and Azure advertises VNet routes back.

### 3.9 Azure Firewall / NVA

**Azure Firewall** is a managed cloud-native network security service. An **NVA (Network Virtual Appliance)** is a third-party firewall running as a VM (e.g., Palo Alto, Fortinet, Check Point).

```text
ARO with Azure Firewall (forced tunneling):

Pod → Node → UDR routes to Azure Firewall → Internet
                        |
                        v
              +-------------------+
              | Azure Firewall    |
              |                   |
              | Application Rules:|
              | Allow: *.quay.io  |
              | Allow: *.redhat.io|
              | Allow: arosvc.*   |
              | Deny: *           |
              |                   |
              | Network Rules:    |
              | Allow: 443/tcp    |
              | Allow: 6443/tcp   |
              +-------------------+
```

> **WHY:** In regulated environments, all outbound traffic must be inspected and logged. Azure Firewall (or an NVA) provides FQDN-based filtering — you can say "allow *.quay.io" instead of trying to list all IP addresses that Quay uses (which change constantly). For ARO, the firewall must allow specific FQDNs that the cluster needs for image pulls, updates, and management. Blocking required FQDNs breaks the cluster.

### 3.10 Service Endpoints vs. Private Endpoints

Both provide private connectivity to Azure PaaS services, but they work differently:

| Feature | Service Endpoint | Private Endpoint |
|---------|-----------------|-----------------|
| How it works | Optimized route in route table | NIC with private IP in your subnet |
| IP seen by service | Your subnet's IP range | Private Endpoint NIC's IP |
| DNS changes needed? | No | Yes (private DNS zone) |
| Works with Private Link? | No (different mechanism) | Yes (this IS Private Link) |
| Works from on-prem? | No (VNet traffic only) | Yes (via peering/ER) |
| Cost | Free | Hourly + data processing |

```text
Service Endpoint (route optimization):
Pod → Node → Azure backbone (shortcut) → Azure Storage
    VNet-scoped access, no NIC created

Private Endpoint (NIC-based):
Pod → Node → Private Endpoint NIC (10.0.1.50) → Azure Storage
    Has its own private IP, works from on-prem via ER
```

> **WHY:** For ARO, Service Endpoints are simpler and free — useful for securing access to Azure Container Registry (ACR) and Storage from within the VNet. Private Endpoints are more flexible — they work from on-prem and have their own DNS resolution — but cost more. For private ARO clusters that need ACR access from both the cluster and on-prem build pipelines, Private Endpoints are the right choice.

### 3.11 Azure DNS Private Zones

**Azure DNS Private Zones** provide DNS resolution within your VNets without exposing records to the public internet.

```text
Public DNS Zone:                        Private DNS Zone:
apps.example.com                        aroapp.privatelink.eastus.azmosa.io
  Visible to everyone                     Only visible to linked VNets
  on the internet

From internet:                          From within linked VNet:
  dig app.apps.example.com               dig api.aroapp.privatelink.eastus.azmosa.io
  → 20.102.35.120 (public IP)            → 10.0.0.10 (private IP)

From on-prem (no VNet link):            From on-prem (with DNS forwarder):
  dig app.apps.example.com               Configure conditional forward to
  → 20.102.35.120 (public IP)            Azure DNS resolver → resolves private IP
```

ARO creates two private DNS zones:
1. **API zone**: `<cluster-id>.privatelink.<region>.azmosa.io` — resolves API server hostname to internal LB IP
2. **Apps zone**: `*.apps.<domain>` — resolves application hostnames to ingress LB IP

> **WHY:** Private DNS zones are how private ARO clusters make the API server and applications reachable by name without public IPs. Without private DNS zones, you'd have to use IP addresses directly (which is fragile and doesn't work with TLS certificate validation). The zones are linked to your VNet so all VMs and pods in the VNet can resolve the names.

### 3.12 NAT Gateway (Azure)

An Azure **NAT Gateway** provides outbound internet connectivity for resources in private subnets, using a predictable, static public IP address.

```text
Pod (10.128.0.15) sends request to pypi.org:
                                                             Internet
                                                                ^
Step 1: Pod → Node                                              |
  src: 10.128.0.15:54321                                   +---------+
  dst: 151.101.0.223:443                                   | NAT GW  |
         |                                                 | PIP:    |
         v                                                 | 20.x.y.z|
Step 2: OVN SNATs pod IP to node IP                        +---------+
  src: 10.0.1.4:54321      (node's private IP)                 ^
  dst: 151.101.0.223:443                                       |
         |                                              +-------------+
         v                                              | Worker      |
Step 3: NAT Gateway SNATs node IP to public IP          | Subnet      |
  src: 20.x.y.z:12345     (NAT GW's public IP)         | 10.0.1.0/24 |
  dst: 151.101.0.223:443                                +-------------+
         |
         +--- goes to internet
```

> **WHY:** By default, ARO uses the Azure Load Balancer's outbound rules for SNAT (source NAT). This works but the public IP used for SNAT can change and is shared with inbound traffic. An Azure NAT Gateway gives you a dedicated, static public IP for all outbound traffic — making it predictable for firewall allowlisting on external services. The NAT Gateway is associated with the worker subnet and takes precedence over the LB's outbound rules.

---

## 4. Azure Virtualization & Accelerated Networking

This section explains how Azure turns physical hardware into the virtual machines that run ARO nodes. Understanding this layer helps you reason about network performance and how packets actually move.

### 4.1 The Azure Hypervisor

Azure's hypervisor is a customized version of **Hyper-V** — Microsoft's bare-metal hypervisor. It runs directly on the physical hardware (not inside an operating system) and divides the server into isolated VMs.

```text
Physical Server in Azure Data Center:
+------------------------------------------------------------------+
|                                                                    |
|  +---------------------------+   +----------------------------+   |
|  | Root Partition             |   | VM 1 (your ARO node)      |   |
|  | (Host OS - minimal)       |   |                            |   |
|  |                           |   | Guest OS: RHCOS            |   |
|  | Manages VMs               |   | OpenShift components       |   |
|  | Storage I/O               |   | Your pods                  |   |
|  | Network management        |   |                            |   |
|  +---------------------------+   +----------------------------+   |
|                                                                    |
|  +---------------------------+   +----------------------------+   |
|  | VM 2 (another customer)   |   | VM 3 (another customer)   |   |
|  | (completely isolated)     |   | (completely isolated)      |   |
|  +---------------------------+   +----------------------------+   |
|                                                                    |
|  +---------------------------+   +----------------------------+   |
|  | Physical Memory (RAM)     |   | Physical NIC               |   |
|  | Divided among VMs         |   | Connected to Azure fabric  |   |
|  +---------------------------+   +----------------------------+   |
|                                                                    |
+------------------------------------------------------------------+
```

> **WHY:** ARO master and worker nodes are VMs running on Azure's Hyper-V hypervisor. The hypervisor provides hardware-level isolation between your VMs and other customers' VMs on the same physical server. The Guest OS is Red Hat CoreOS (RHCOS), which is an immutable operating system designed specifically for running OpenShift.

### 4.2 Azure VM Sizes for ARO

ARO supports specific VM sizes for master and worker nodes:

| Role | Common VM Sizes | vCPUs | RAM | Network Bandwidth |
|------|----------------|-------|-----|-------------------|
| **Master** | Standard_D8s_v3, Standard_E8s_v5 | 8 | 32-64 GB | 4 Gbps |
| **Worker** | Standard_D4s_v3 (default) | 4 | 16 GB | 2 Gbps |
| **Worker** | Standard_D8s_v3 | 8 | 32 GB | 4 Gbps |
| **Worker** | Standard_D16s_v3 | 16 | 64 GB | 8 Gbps |
| **Worker** | Standard_E16s_v5 | 16 | 128 GB | 12.5 Gbps |

> **WHY:** The VM size determines network throughput, which directly affects how fast pods can communicate. D-series VMs are general-purpose (balanced CPU/memory). E-series VMs are memory-optimized (good for databases, caches). The "s" suffix means premium storage support. The network bandwidth limit is per-VM — if your ARO pods push high network throughput (e.g., data streaming, large file transfers), you need a larger VM size.

### 4.3 Accelerated Networking (SR-IOV / Mellanox VF)

**Accelerated Networking** uses **SR-IOV (Single Root I/O Virtualization)** to give each VM direct access to a slice of the physical NIC, bypassing the hypervisor for data-plane traffic.

```text
Without Accelerated Networking:       With Accelerated Networking (what ARO uses):

  VM1    VM2    VM3                   VM1    VM2    VM3
   |      |      |                    |      |      |
   v      v      v                    v      v      v
+------------------------+          +---+  +---+  +---+
|    Hyper-V             |          | VF|  | VF|  | VF|  Virtual Functions
|    (software vSwitch - |          +---+  +---+  +---+  (Mellanox ConnectX)
|     CPU heavy, latency)|            |      |      |
+------------------------+          +------------------------+
         |                          |   Physical NIC (PF)    |
+------------------------+          |   (Mellanox ConnectX-5) |
|   Physical NIC         |          +------------------------+
+------------------------+

VF = Virtual Function (hardware slice of the NIC)
PF = Physical Function (the physical NIC itself)
```

With Accelerated Networking:
- Each VM gets a hardware **Virtual Function (VF)** — a real slice of the Mellanox NIC
- Data-plane packets go directly from the VF to the VM (bypassing the hypervisor's software vSwitch)
- Control-plane operations (NIC creation, NSG programming) still go through the hypervisor
- Latency drops to ~10 microseconds (vs. ~100 microseconds without)

> **WHY:** ARO enables Accelerated Networking by default on supported VM sizes. This is critical for performance — pods making high-frequency API calls or processing streaming data benefit from the reduced latency. The Mellanox VF maps directly to the `eth0` interface inside the VM. NSG rules are applied in the hypervisor's vSwitch (for control) and the Mellanox NIC firmware (for fast path), so they have near-zero CPU overhead.

### 4.4 VNet NIC → eth0 Mapping

From Azure's perspective, you see a **VNet NIC** (Network Interface). From inside the VM, you see **eth0**. They're the same thing:

```text
Azure Perspective:                      Linux Perspective (inside VM):
+-------------------+                   +-------------------+
| VNet NIC          |                   | $ ip addr show    |
| nic-worker1       |                   | eth0:             |
| IP: 10.0.1.4     | <================>|   10.0.1.4/24     |
| MAC: 00:0d:3a:... |                  |   MAC: 00:0d:3a:..|
| NSG: worker-nsg   |                  |                   |
| Subnet: worker    |                   | $ ip route show   |
| AccelNet: enabled |                   | default via       |
+-------------------+                   |   10.0.1.1 eth0   |
                                        +-------------------+
```

When Accelerated Networking is enabled, `eth0` is actually the Mellanox VF (mlx5_core driver), not a synthetic NIC:

```text
$ ethtool -i eth0
driver: mlx5_core        ← hardware VF, not synthetic hv_netvsc
firmware-version: ...
bus-info: ...
```

> **WHY:** Every ARO node (master and worker) has a VNet NIC. The NIC determines the node's IP address, which subnet it's in, and which NSG applies. When a pod sends a packet that leaves the node, it exits through eth0 (the VNet NIC). Understanding the NIC is understanding the boundary between the overlay network (Kubernetes/OVN) and the underlay network (Azure VNet).

### 4.5 Packet Flow: Physical NIC to Pod

Here is the complete path a packet takes from the Azure physical network to a pod running in ARO:

```text
INBOUND PACKET (from internet to pod):

+-------------+     +------------------+     +------------------+
| Azure Fabric| --> | Host vSwitch     | --> | Mellanox VF      |
| Network     |     | (Hyper-V)        |     | (SR-IOV)         |
|             |     |                  |     |                  |
| (fiber,     |     | 1. NSG evaluation|     | 2. Direct to VM  |
|  switches)  |     |    (fast path)   |     |    (bypass       |
+-------------+     +------------------+     |     hypervisor)  |
                                             +------------------+
                                                      |
                                              +-------v--------+
                                              | eth0           |
                                              | (mlx5_core     |
                                              |  driver)       |
                                              |                |
                                              | 3. Linux kernel|
                                              |    receives    |
                                              |    packet      |
                                              +-------+--------+
                                                      |
                                              +-------v--------+
                                              | OVN-Kubernetes  |
                                              | (br-int bridge) |
                                              |                |
                                              | 4. Matches     |
                                              |    OVN flow    |
                                              |    rules       |
                                              |                |
                                              | 5. Forwards to |
                                              |    pod's veth  |
                                              +-------+--------+
                                                      |
                                              +-------v--------+
                                              | Pod (veth pair)|
                                              | eth0 inside pod|
                                              |                |
                                              | 6. Application |
                                              |    receives    |
                                              |    packet      |
                                              +----------------+
```

Detailed breakdown:

1. **Azure fabric**: Packet arrives at the physical NIC on the Azure server via the data center's network fabric
2. **Host vSwitch + NSG**: The Hyper-V virtual switch evaluates NSG rules. If denied, packet is dropped here. With Accelerated Networking, the fast path offloads this to the NIC firmware
3. **Mellanox VF (eth0)**: Packet is delivered directly to the VM via the SR-IOV Virtual Function, bypassing the hypervisor's software data path
4. **Linux kernel routing**: The kernel's routing table determines where the packet goes next. For pod-bound traffic, it goes to the OVN bridge (br-int)
5. **OVN bridge (br-int)**: OVN's OpenFlow rules match the destination IP to a specific pod and forward to the correct veth pair
6. **Pod**: The packet arrives on the pod's eth0 interface (one end of a veth pair; the other end is on br-int)

> **WHY:** This is the complete chain that determines latency, throughput, and where security filtering happens. If a packet is blocked, understanding this chain tells you where to look: NSG at the vSwitch? Linux iptables rules? OVN flow rules? NetworkPolicy enforcement in OVN? Each layer can be independently diagnosed.

---

## 5. Kubernetes Networking Fundamentals

Kubernetes has a specific networking model with guarantees that every network implementation must satisfy. This section explains that model and how it maps to ARO.

### 5.1 The Pod Networking Model

Kubernetes makes three fundamental guarantees about networking:

1. **Every pod gets its own IP address** — pods don't share IPs with other pods
2. **Pods can communicate with any other pod without NAT** — a pod's IP is routable to all other pods
3. **Agents on a node (kubelet, node-exporter) can communicate with all pods on that node**

```text
Node 1 (10.0.1.4)                     Node 2 (10.0.1.5)
+-----------------------------+        +-----------------------------+
| Pod A: 10.128.0.15          |        | Pod C: 10.128.2.33          |
| Pod B: 10.128.0.16          |        | Pod D: 10.128.2.34          |
+-----------------------------+        +-----------------------------+

Pod A (10.128.0.15) can directly reach Pod C (10.128.2.33)
    without any NAT — the source IP stays 10.128.0.15
    all the way to Pod C.

How? The CNI plugin (OVN-Kubernetes) handles the routing.
    On the same node: bridging via br-int
    Cross-node: Geneve tunnel encapsulation
```

> **WHY:** This flat networking model simplifies application development — applications don't need to know whether they're talking to a pod on the same node or a different node. It also makes NetworkPolicies possible because every pod has a unique identity (its IP). ARO uses OVN-Kubernetes as the CNI plugin to implement this model using Geneve tunnels between nodes.

### 5.2 Services

A **Service** is a stable virtual IP address (called a **ClusterIP**) that load-balances traffic across a set of pods. Pods come and go (scaling, crashes, deployments), but the Service IP stays the same.

```text
Without Services:                    With Services:
                                     Service: my-app-svc (172.30.45.67)
Client must track every pod IP:           |
  10.128.0.15 (might die!)               v
  10.128.0.16 (might die!)          +----------+
  10.128.2.33 (might die!)          | OVN LB   |  load-balancer
                                    +----+-----+
                                         |
                               +---------+---------+
                               |         |         |
                             Pod A     Pod B     Pod C
                          10.128.0.15 10.128.0.16 10.128.2.33
```

**Service types:**

| Type | What It Does | Accessible From |
|------|-------------|-----------------|
| **ClusterIP** | Virtual IP only reachable inside the cluster | Inside cluster only |
| **NodePort** | Opens a port (30000-32767) on every node's IP | Anyone who can reach a node IP + that port |
| **LoadBalancer** | Creates an Azure LB that points to NodePorts | The internet (or VNet, if internal) |

> **WHY:** Services are how ARO applications find each other. Instead of hard-coding pod IPs (which change constantly), applications connect to service names (which resolve to ClusterIPs via DNS). The OpenShift router itself runs behind a LoadBalancer-type Service — that's how external traffic enters the cluster.

### 5.3 Ingress and Ingress Controllers

**Ingress** is a Kubernetes API object that defines rules for routing external HTTP/HTTPS traffic to Services inside the cluster. An **Ingress Controller** reads Ingress objects and implements the routing.

> **WHY:** In ARO, OpenShift **Routes** serve the same purpose as Ingress objects (and are actually older). The default Ingress Controller is the OpenShift Router (HAProxy). When you create a Route, the router configures HAProxy to accept traffic for that hostname and forward it to the correct Service. External traffic reaches the router because the router runs behind an Azure Load Balancer (LoadBalancer Service). ARO also supports Kubernetes Ingress objects — they're translated to Routes internally.

### 5.4 Network Policies

A **NetworkPolicy** is a Kubernetes API object that controls which pods can talk to which other pods. By default, all pods can communicate with all other pods. NetworkPolicies add firewall rules.

```text
Default (no policies):           With default-deny policy:

Pod A <---> Pod B                Pod A --X--> Pod B (blocked!)
Pod A <---> Pod C                Pod A --X--> Pod C (blocked!)
Pod B <---> Pod C                Pod B --X--> Pod C (blocked!)

  All pods can talk to all.        Nothing can talk to anything.
```

> **WHY:** NetworkPolicies implement zero-trust networking inside the cluster. Without them, any compromised pod can talk to every other pod — including pods in other namespaces. In ARO, OVN-Kubernetes enforces NetworkPolicies in OVN logical flows at the virtual switch level, not iptables. This is efficient and scales to thousands of rules.

### 5.5 CNI (Container Network Interface)

**CNI** is a standard that defines how container runtimes (CRI-O in ARO) set up networking for pods. The CNI plugin is the implementation that creates network interfaces, assigns IPs, and sets up routing.

```text
When a new pod starts:

1. Kubelet tells CRI-O to create the pod
2. CRI-O creates the pod's network namespace
3. CRI-O calls the CNI plugin (OVN-Kubernetes)
4. OVN-Kubernetes:
   a. Creates a veth pair
   b. Puts one end in the pod (becomes pod's eth0)
   c. Puts other end on br-int (OVN's integration bridge)
   d. Assigns an IP from the node's pod CIDR allocation
   e. Programs OVN flows to route to this pod
5. Pod's eth0 is now live with an IP address
```

> **WHY:** ARO uses OVN-Kubernetes as its CNI plugin. This is not optional and cannot be changed. OVN-Kubernetes was chosen because it integrates tightly with OpenShift's networking features (Routes, EgressIPs, multicast) and provides hardware-accelerated flow processing via Open vSwitch (OVS).

### 5.6 kube-proxy, iptables, and OVN Load Balancing

In standard Kubernetes, kube-proxy programs iptables rules for Service load balancing. In ARO with OVN-Kubernetes, kube-proxy is replaced by OVN's native load balancing.

```text
Standard Kubernetes (iptables):          ARO (OVN):

Client pod                              Client pod
    |                                        |
    v                                        v
iptables/nftables rules                  OVN logical flow rules
(programmed by kube-proxy)               (programmed by OVN controller)
    |                                        |
    v                                        v
DNAT: 172.30.45.67 → 10.128.0.15       DNAT: 172.30.45.67 → 10.128.0.15
(Service IP → Pod IP)                   (Service IP → Pod IP)
```

The Service ClusterIP (172.30.45.67) never appears on any real interface — it exists only as a DNAT rule.

> **WHY:** ARO uses OVN for Service load balancing instead of kube-proxy/iptables because OVN handles it in the OVS datapath (kernel module), which is faster than iptables rule chains. At scale (thousands of Services), iptables performance degrades because rules are evaluated linearly. OVN uses flow tables with O(1) lookup.

### 5.7 DNS in Kubernetes (CoreDNS)

**CoreDNS** runs as pods inside the cluster and provides DNS resolution for all Kubernetes names.

Every Service gets a DNS name automatically:

```text
Service "my-api" in namespace "production":

DNS name: my-api.production.svc.cluster.local
    |        |          |       |
    |        |          |       +-- cluster domain
    |        |          +-- "svc" = it's a Service
    |        +-- namespace
    +-- service name

Resolves to: 172.30.45.67 (the ClusterIP)
```

For external names (google.com), CoreDNS forwards to upstream DNS servers (Azure DNS resolver at 168.63.129.16).

> **WHY:** Without CoreDNS, pods would need to know the ClusterIP of every Service. CoreDNS lets pods use human-readable names. The Azure DNS resolver (168.63.129.16) is a special well-known IP that provides DNS resolution for VNet resources, Azure Private DNS zones, and public DNS — it's the upstream for all non-cluster queries.

---

## 6. OpenShift Networking Layer

OpenShift builds on Kubernetes networking with additional components. This section explains what OpenShift adds and how it works in ARO.

### 6.1 OVN-Kubernetes Architecture

**OVN (Open Virtual Network)** is a virtual networking system built on top of **OVS (Open vSwitch)**. OVN-Kubernetes is the CNI plugin that integrates OVN with Kubernetes.

```text
Architecture Overview:

Master Nodes (in your VNet):
+------------------------------------------+
| OVN Northbound DB                        |
| (stores logical network configuration)   |
|     - Logical switches                   |
|     - Logical routers                    |
|     - ACLs (NetworkPolicies)             |
|                                          |
| OVN Southbound DB                        |
| (stores physical bindings)               |
|     - Which chassis (node) has which     |
|       logical port (pod)                 |
|     - Tunnel endpoints                   |
+------------------------------------------+

Worker Nodes (in your VNet):
+------------------------------------------+
| Node 1                                   |
|                                          |
| ovn-controller (daemon)                  |
|   Reads Southbound DB                    |
|   Programs OVS flow rules               |
|                                          |
| OVS (Open vSwitch)                       |
|   br-int    (integration bridge)         |
|     Connects all local pods              |
|     Applies flow rules                   |
|   br-ex     (external bridge)            |
|     Connects to eth0 / physical network  |
|                                          |
| Pods:                                    |
|   veth ---- br-int ---- Geneve tunnel    |
+------------------------------------------+
```

> **WHY:** Unlike ROSA HCP where the OVN databases run in Red Hat's VPC, in ARO the OVN Northbound and Southbound DBs run on the master nodes in YOUR VNet. This means all OVN control-plane traffic stays within your VNet — there's no cross-account PrivateLink for OVN data. This is a key architectural difference.

### 6.2 Geneve Tunneling

**Geneve (Generic Network Virtualization Encapsulation)** wraps pod-to-pod packets inside regular node-to-node UDP packets. This lets pod traffic traverse the VNet, which only knows about node IPs.

```text
Pod A (10.128.0.15 on Node 1) sends to Pod C (10.128.2.33 on Node 2):

ORIGINAL PACKET (what Pod A sends):
+-----------------------------------------------+
| Src IP: 10.128.0.15  |  Dst IP: 10.128.2.33  |
| Src Port: 54321       |  Dst Port: 8080       |
| Data: "GET /api"                              |
+-----------------------------------------------+

ENCAPSULATED PACKET (what actually goes on the VNet):
+------------------------------------------------------------------+
| OUTER Ethernet | OUTER IP Header    | OUTER UDP   | Geneve Header|
| Dst MAC: Node2 | Src: 10.0.1.4      | Src: random | VNI (network |
| Src MAC: Node1 | Dst: 10.0.1.5      | Dst: 6081   | identifier)  |
+-----------------+--------------------+-------------+--------------+
| INNER Packet (original, unchanged):                               |
| Src IP: 10.128.0.15  |  Dst IP: 10.128.2.33                     |
| Data: "GET /api"                                                  |
+------------------------------------------------------------------+

The VNet only sees: 10.0.1.4 → 10.0.1.5 (node-to-node UDP on port 6081)
The VNet doesn't know about pod IPs at all.
```

> **WHY:** VNet networking only knows about node IPs (10.0.x.x). Pod IPs (10.128.x.x) are invisible to the VNet — they exist only in the overlay network. Geneve tunneling bridges this gap. NSGs must allow UDP port 6081 between worker nodes or cross-node pod communication breaks completely.

### 6.3 Logical Switches and Routers in OVN

OVN creates a virtual network topology using logical constructs:

```text
OVN Logical Topology:

                    +--------------------+
                    | Cluster Router     |
                    | (ovn_cluster_router)|
                    |                    |
                    | Routes between:    |
                    | - Node subnets     |
                    | - Service network  |
                    | - External network |
                    +----+------+--------+
                         |      |
              +----------+      +----------+
              |                            |
    +---------v----------+     +-----------v--------+
    | Node 1 Switch      |     | Node 2 Switch      |
    | (node1_switch)     |     | (node2_switch)      |
    | Subnet: 10.128.0/24|     | Subnet: 10.128.2/24|
    |                    |     |                     |
    | Ports:             |     | Ports:              |
    |  Pod A: 10.128.0.15|     |  Pod C: 10.128.2.33|
    |  Pod B: 10.128.0.16|     |  Pod D: 10.128.2.34|
    +--------------------+     +---------------------+
```

- **Logical Switch**: One per node. All pods on a node are ports on that node's logical switch.
- **Cluster Router**: Connects all logical switches. Routes traffic between pods on different nodes. Handles SNAT for external traffic and DNAT for Services.

> **WHY:** This logical topology is how OVN decides which tunnel to use for each packet. When Pod A sends to Pod C, the Cluster Router routes from Node 1's switch to Node 2's switch, and OVN translates that to a Geneve tunnel between the physical nodes.

### 6.4 Pod CIDR Allocation Per Node

OVN-Kubernetes divides the cluster's pod CIDR range into smaller subnets and assigns one to each node:

```text
Cluster Pod CIDR: 10.128.0.0/14 (262,144 addresses)

Node 1 allocation: 10.128.0.0/23 (512 addresses)
  Pod A: 10.128.0.15
  Pod B: 10.128.0.16

Node 2 allocation: 10.128.2.0/23 (512 addresses)
  Pod C: 10.128.2.33
  Pod D: 10.128.2.34

Node 3 allocation: 10.128.4.0/23 (512 addresses)
  ...
```

> **WHY:** This allocation scheme means OVN can determine which node hosts a pod just by looking at its IP address. 10.128.2.x is always on Node 2. Each node assigns IPs locally without consulting a central IPAM server, which speeds up pod startup.

### 6.5 OpenShift Routes vs. Kubernetes Ingress

| Feature | OpenShift Route | Kubernetes Ingress |
|---------|----------------|-------------------|
| TLS Termination | Edge, Passthrough, Re-encrypt | Depends on Ingress Controller |
| Wildcard routes | Supported | Depends on controller |
| Route weights | Supported (for blue-green/canary) | Not standard |
| Implementation | HAProxy-based router | Varies by controller |
| ARO support | Native, default | Supported (translated to Routes) |

> **WHY:** Routes are the primary way applications are exposed in ARO. When you create a Route with `host: my-app.apps.mycluster.example.com`, the router adds an HAProxy configuration entry that matches the HTTP Host header and forwards to the correct backend. The `*.apps` wildcard DNS record is pre-configured to point to the router's load balancer.

### 6.6 The OpenShift Router (HAProxy)

The OpenShift Router is a set of HAProxy pods running in the `openshift-ingress` namespace.

```text
External Traffic Flow Through the Router:

Internet Client
    |
    v
Azure Load Balancer (LoadBalancer Service)
    |  Backend pool: Worker node IPs on NodePort 30080/30443
    v
Node's eth0 (OVN intercepts)
    |  DNAT to router pod IP
    v
Router Pod (HAProxy) in openshift-ingress namespace
    |
    | HAProxy config (auto-generated from Route objects):
    |   if Host == "app1.apps.cluster.com" → backend app1-svc:8080
    |   if Host == "app2.apps.cluster.com" → backend app2-svc:8080
    |
    v
Application Pod
```

> **WHY:** The router is the single entry point for all HTTP/HTTPS application traffic in ARO. If router pods are unhealthy, all external application traffic stops flowing.

### 6.7 Multus CNI

**Multus** is a "meta-CNI" that allows pods to have multiple network interfaces. The primary interface (eth0) is always managed by OVN-Kubernetes. Multus can add additional interfaces.

> **WHY:** Multus is used in ARO for specialized networking — most commonly with OpenShift Virtualization (KubeVirt), where VMs need a direct connection to a VLAN or SR-IOV interface for high-performance networking.

---

## 7. ARO Architecture — The Complete Picture

This section brings everything together to explain how ARO's architecture works at a network level.

### 7.1 What Makes ARO Different from ROSA HCP

| Feature | ARO | ROSA HCP |
|---------|-----|----------|
| **Control plane location** | In YOUR VNet (3 master VMs) | In Red Hat's VPC |
| **Control plane cost** | You pay for 3 master VMs | Red Hat manages; no master cost |
| **Control plane network** | Same VNet as workers | Different VPC, via PrivateLink |
| **Master nodes** | Visible VMs in your subscription | Invisible, managed by Red Hat |
| **API server access** | Public IP or Private Link (internal LB) | Always via PrivateLink |
| **Worker nodes** | In your VNet | In your VPC |
| **OVN DBs location** | On master nodes (your VNet) | In Red Hat's VPC |
| **Cloud provider** | Azure | AWS |
| **Managed by** | Microsoft + Red Hat jointly | Red Hat |

```text
ARO:                                   ROSA HCP:

Your VNet (everything here):            Your VPC (workers only):
+---------------------+                +---------------------+
| Master 1 (D8s_v3)  |                | (no master nodes!)  |
| Master 2 (D8s_v3)  |                |                     |
| Master 3 (D8s_v3)  |                | Worker 1            |
|                     |                | Worker 2            |
| Worker 1            |                | Worker 3            |
| Worker 2            |                +----------+----------+
| Worker 3            |                           |
+---------------------+                 PrivateLink|
                                                   |
                                        Red Hat's VPC:
                                        +---------------------+
                                        | API Server, etcd    |
                                        +---------------------+
```

> **WHY:** ARO puts everything in your VNet — masters, workers, load balancers, all of it. This means you have full VNet-level visibility and control. The trade-off is cost (you pay for 3 master VMs) and operational responsibility (you manage the VNet). The ARO Resource Provider (RP) manages the cluster lifecycle (upgrades, patches) via Private Link.

### 7.2 ARO Resource Provider (RP) Architecture

The ARO RP is a managed service operated jointly by Microsoft and Red Hat. It handles cluster creation, upgrades, monitoring, and support access.

```text
+----------------------------------+       +----------------------------------+
| Microsoft/Red Hat Managed Infra  |       | Your Azure Subscription          |
|                                  |       |                                  |
| ARO Resource Provider (RP)       |       | Your VNet                        |
|                                  |       |                                  |
| Responsibilities:                |       | +----------------------------+   |
| - Cluster provisioning           |       | | Master Subnet              |   |
| - OpenShift upgrades             |       | |                            |   |
| - Monitoring & alerting          |       | | Master 1: API Server       |   |
| - Support access (SRE)           |       | | Master 2: etcd             |   |
|         |                        |       | | Master 3: Controllers      |   |
|         v                        |       | |                            |   |
| Private Link Service             |------>| | Private Endpoint           |   |
| (provider side)                  |  PL   | | (NIC: 10.0.0.20)           |   |
|                                  |       | +----------------------------+   |
|                                  |       |                                  |
|                                  |       | +----------------------------+   |
|                                  |       | | Worker Subnet              |   |
|                                  |       | | Worker 1, 2, 3...          |   |
|                                  |       | +----------------------------+   |
+----------------------------------+       +----------------------------------+
```

The RP communicates with the cluster API server via Private Link. This is how:
1. Cluster upgrades are initiated
2. SRE (Site Reliability Engineering) teams access the cluster for support
3. Health monitoring data flows back to Microsoft/Red Hat

> **WHY:** The RP uses Private Link so it can manage the cluster without requiring a public API endpoint. For private clusters, the API server has no public IP at all — the RP is the only external entity that can reach it (besides your own VNet/connected networks). This is a critical security property.

### 7.3 Full Blackboard-Style Architecture Diagram

```text
+=============================================================================+
|                           ARO COMPLETE ARCHITECTURE                          |
+=============================================================================+

  Internet
     |
     | (public traffic, only if public cluster)
     v
+=============================================================================+
| YOUR VNET (10.0.0.0/16)                                                     |
|                                                                              |
| MASTER SUBNET (10.0.0.0/27)                                                 |
| +-----------------------------------------------------------------------+   |
| |                                                                       |   |
| | +-------------------------------------------------------------------+ |   |
| | | Master Node 1 (Standard_D8s_v3)                                   | |   |
| | | VNet NIC: nic-master1 (10.0.0.4)                                  | |   |
| | | NSG: aro-master-nsg                                                | |   |
| | | +---------------------------------------------------------------+| |   |
| | | | RHCOS (Red Hat CoreOS)                                         || |   |
| | | | eth0: 10.0.0.4 (Mellanox VF — Accelerated Networking)         || |   |
| | | |                                                               || |   |
| | | | kube-apiserver (port 6443)                                    || |   |
| | | | etcd (port 2379/2380)                                         || |   |
| | | | kube-controller-manager                                       || |   |
| | | | kube-scheduler                                                || |   |
| | | | OVN Northbound DB + Southbound DB                             || |   |
| | | +---------------------------------------------------------------+| |   |
| | +-------------------------------------------------------------------+ |   |
| |                                                                       |   |
| | Master 2 (10.0.0.5), Master 3 (10.0.0.6) — similar layout           |   |
| |                                                                       |   |
| | Azure Load Balancer (API):                                            |   |
| |   Public:  20.102.35.120:6443 → Masters pool                         |   |
| |   Private: 10.0.0.10:6443 → Masters pool (private cluster only)      |   |
| |                                                                       |   |
| | Private Endpoint (ARO RP access):                                     |   |
| |   NIC: 10.0.0.20 → ARO Resource Provider (Microsoft/Red Hat)         |   |
| +-----------------------------------------------------------------------+   |
|                                                                              |
| WORKER SUBNET (10.0.1.0/24)                                                 |
| +-----------------------------------------------------------------------+   |
| |                                                                       |   |
| | +-------------------------------------------------------------------+ |   |
| | | Worker Node 1 (Standard_D4s_v3)                                   | |   |
| | | VNet NIC: nic-worker1 (10.0.1.4)                                  | |   |
| | | NSG: aro-worker-nsg                                                | |   |
| | | +---------------------------------------------------------------+| |   |
| | | | RHCOS                                                          || |   |
| | | | eth0: 10.0.1.4 (Mellanox VF)                                   || |   |
| | | |                                                               || |   |
| | | | kubelet (port 10250)                                          || |   |
| | | | CRI-O (container runtime)                                     || |   |
| | | |                                                               || |   |
| | | | OVS br-int (integration bridge)                               || |   |
| | | |   |          |            |                                   || |   |
| | | |   v          v            v                                   || |   |
| | | | +------+  +------+  +----------+                             || |   |
| | | | |Pod A |  |Pod B |  |Router Pod|                             || |   |
| | | | |app   |  |app   |  |(HAProxy) |                             || |   |
| | | | |10.128|  |10.128|  |10.128    |                             || |   |
| | | | |.0.15 |  |.0.16 |  |.0.20    |                             || |   |
| | | | +------+  +------+  +----------+                             || |   |
| | | +---------------------------------------------------------------+| |   |
| | +-------------------------------------------------------------------+ |   |
| |                                                                       |   |
| | Worker 2 (10.0.1.5), Worker 3 (10.0.1.6) — similar layout           |   |
| |                                                                       |   |
| | Azure Load Balancer (Ingress):                                        |   |
| |   Public:  20.103.44.55:443 → Workers pool (NodePort 30443)          |   |
| |   Private: 10.0.1.10:443 → Workers pool (private cluster only)       |   |
| |                                                                       |   |
| +-----------------------------------------------------------------------+   |
|                                                                              |
| Optional Components:                                                         |
| - Azure Firewall (10.0.2.4) — for forced tunneling via UDR                  |
| - NAT Gateway — for predictable outbound IP                                 |
| - ExpressRoute Gateway — for on-prem connectivity                           |
| - Service Endpoints — for ACR, Storage                                      |
|                                                                              |
| Route Tables (UDRs):                                                         |
| - Default: 0.0.0.0/0 → Internet (or Azure Firewall if forced tunneling)     |
| - VNet:    10.0.0.0/16 → VNet (system route)                                |
| - On-prem: 192.168.0.0/16 → VNet Gateway (if ExpressRoute configured)       |
|                                                                              |
+=============================================================================+
     |  Private Link (ARO RP management)
     v
+=============================================================================+
| MICROSOFT / RED HAT MANAGED INFRASTRUCTURE                                  |
|                                                                              |
| +----------------------------------+                                         |
| | ARO Resource Provider (RP)       |                                         |
| |                                  |                                         |
| | - Cluster lifecycle management   |                                         |
| | - OpenShift upgrades             |                                         |
| | - SRE monitoring & alerting      |                                         |
| | - Support access                 |                                         |
| +----------------------------------+                                         |
|                                                                              |
+=============================================================================+
```

### 7.4 How the API Server Communicates with Kubelets

```text
1. User runs: oc get pods
                |
2. oc CLI   -->| HTTPS to API server (port 6443)
                |  Resolves to: 20.102.35.120 (public) or 10.0.0.10 (private)
                v
3. API Server (Master node in YOUR VNet)
   Processes request, returns pod list from etcd
                |
4. Response  <--| back same path
                v
5. oc CLI displays pod list

---

6. User runs: oc logs my-pod
                |
7. oc CLI   -->| HTTPS to API server
                v
8. API Server on Master 1 needs logs from Worker 1
   API server --| within the same VNet
                |  to worker node's kubelet (port 10250)
                v
9. Kubelet on Worker 1
   Reads logs from CRI-O
                |
10. Logs     <--| back to API server, then to oc CLI
```

> **WHY:** In ARO, master and worker nodes are in the SAME VNet, so API server → kubelet communication is direct VNet traffic — no PrivateLink hops needed. This is faster than ROSA HCP (which traverses PrivateLink in both directions). The trade-off is you're responsible for the VNet and pay for master node VMs.

---

## 8. How Apps Are Exposed in ARO

This is the core section. It explains, at the packet level, how traffic reaches your applications.

### 8.1 Public Ingress Path — Packet-Level Walkthrough

A user on the internet accesses `https://my-app.apps.mycluster.example.com`:

```text
STEP 1: DNS Resolution
========================
User's browser: "What is the IP of my-app.apps.mycluster.example.com?"
    |
    v
DNS Resolver → Azure DNS (or public DNS)
    |
    | Azure DNS has a wildcard record:
    | *.apps.mycluster.example.com → A record → 20.103.44.55
    | (Ingress Azure LB public IP)
    |
    v
Browser gets IP: 20.103.44.55


STEP 2: TCP Connection + TLS Handshake
=======================================
Browser → 20.103.44.55:443 (TCP SYN)
    |
    | Packet:
    | Src IP: 203.0.113.50 (user's public IP)
    | Dst IP: 20.103.44.55 (Azure LB's public IP)
    | Dst Port: 443
    |
    v
Azure Load Balancer receives on frontend IP
    |
    | Azure LB is Layer 4 — it does NOT terminate TLS
    | Azure LB distributes to backend pool:
    |   Hash-based selection → Worker Node 1 (10.0.1.4:30443)
    |
    | Azure LB performs DNAT:
    |   Original dst: 20.103.44.55:443
    |   New dst: 10.0.1.4:30443 (Node 1's IP + router NodePort)
    |
    | NSG check on worker subnet:
    |   Rule: Allow TCP 30000-32767 from AzureLoadBalancer → PASS
    |
    v
Packet on VNet:
    Src IP: 203.0.113.50 (preserved — Azure LB supports DSR)
    Dst IP: 10.0.1.4 (worker node)
    Dst Port: 30443 (NodePort for router)


STEP 3: Node Receives Packet
==============================
Worker Node 1's VNet NIC (nic-worker1) receives the packet
    |
    | Mellanox VF delivers to eth0
    |
    v
Linux kernel (eth0) receives packet
    |
    | OVN intercepts packets to NodePort 30443
    | DNAT to router pod IP:
    |   Original dst: 10.0.1.4:30443
    |   New dst: 10.128.0.20:443 (router pod)
    |
    v
OVS br-int forwards to router pod's veth


STEP 4: Router Pod (HAProxy)
==============================
Router pod (10.128.0.20) receives TCP connection
    |
    | TLS termination (for edge Routes):
    |   Decrypts TLS using the Route's certificate
    |   Reads HTTP Host header: "my-app.apps.mycluster.example.com"
    |
    | HAProxy config lookup:
    |   Host "my-app.apps.mycluster.example.com"
    |   → backend: my-app-svc.production.svc (172.30.45.67:8080)
    |
    | HAProxy opens new connection to backend:
    |   Src IP: 10.128.0.20 (router pod)
    |   Dst IP: 172.30.45.67 (Service ClusterIP)
    |   Dst Port: 8080
    |
    v
OVN intercepts packet to ClusterIP (172.30.45.67)
    |
    | OVN load balancing (DNAT):
    |   Original dst: 172.30.45.67:8080
    |   New dst: 10.128.0.15:8080 (selected backend pod)
    |
    v
Packet delivered to app pod


STEP 5: Application Pod Processes Request
==========================================
App pod (10.128.0.15) receives:
    Src IP: 10.128.0.20 (router pod — original client IP in X-Forwarded-For)
    Dst IP: 10.128.0.15 (itself)
    Dst Port: 8080

App processes request, sends response back.
Response follows reverse path:
    App pod → OVN → Router pod → OVN → Node → Azure LB → Internet → User


COMPLETE IP TRANSFORMATION CHAIN:
===================================
User:        203.0.113.50:54321  →  20.103.44.55:443     (to Azure LB public IP)
Azure LB:    203.0.113.50:54321  →  10.0.1.4:30443       (to Node's NodePort)
OVN DNAT:    203.0.113.50:54321  →  10.128.0.20:443      (to Router pod)
HAProxy:     10.128.0.20:xxxxx   →  172.30.45.67:8080    (to Service ClusterIP)
OVN DNAT:    10.128.0.20:xxxxx   →  10.128.0.15:8080     (to App pod)
```

> **WHY:** Understanding this chain is essential for debugging "my app is unreachable" problems. The packet passes through 5 components (DNS, Azure LB, Node/OVN, Router, OVN again), and a misconfiguration at ANY point breaks the flow. The most common issues: DNS not resolving (Azure DNS misconfigured), LB backend unhealthy (NSG blocking NodePort range), router pod not running, Service selector not matching pods.

### 8.2 Private Ingress Path — Packet-Level Walkthrough

For private ARO clusters, the ingress LB has no public IP. Traffic enters from the corporate network via ExpressRoute, VPN, or VNet peering.

```text
Corporate User (192.168.1.100) accesses private app:

STEP 1: DNS Resolution
========================
Corporate DNS server resolves:
    my-app.apps.mycluster.internal.com → 10.0.1.10 (Internal LB private IP)

    Note: This uses Azure DNS Private Zones:
    - From internet: *.apps.mycluster... → NXDOMAIN (doesn't exist)
    - From linked VNet/on-prem: *.apps.mycluster... → internal LB IP


STEP 2: Traffic Path
=====================
Corp user (192.168.1.100)
    |
    v
Corporate Router / Firewall
    |
    v
ExpressRoute Circuit (dedicated fiber)
    |
    v
ExpressRoute Gateway (in your VNet or hub VNet)
    |
    | VNet route table:
    |   10.0.0.0/16 → VNet (local)
    |
    v
Internal Azure LB receives packet:
    Src IP: 192.168.1.100
    Dst IP: 10.0.1.10 (Internal LB frontend)
    Dst Port: 443


STEP 3: Internal LB
======================
Internal LB (private IP only, no public IP)
    |
    | DNAT:
    |   Dst: 10.0.1.10:443 → 10.0.1.4:30443 (Node NodePort)
    |
    v
Same flow as public ingress from Step 3 onward:
    Node → OVN → Router Pod → Service → App Pod


COMPLETE IP TRANSFORMATION CHAIN:
===================================
Corp User:   192.168.1.100:54321  →  10.0.1.10:443       (to internal LB)
Azure LB:    192.168.1.100:54321  →  10.0.1.4:30443      (to Node NodePort)
OVN DNAT:    192.168.1.100:54321  →  10.128.0.20:443     (to Router pod)
HAProxy:     10.128.0.20:xxxxx    →  172.30.45.67:8080    (to Service ClusterIP)
OVN DNAT:    10.128.0.20:xxxxx    →  10.128.0.15:8080     (to App pod)
```

> **WHY:** Private ingress is the standard for production ARO workloads. The key difference from public ingress: DNS must be configured on the corporate side to resolve *.apps to the internal LB IP, typically via Azure DNS Private Zones linked to the VNet, with on-prem DNS forwarding to Azure DNS resolver.

### 8.3 Egress Path — Packet-Level Walkthrough

A pod calls an external API (e.g., `https://api.stripe.com`):

```text
STEP 1: Pod Sends Packet
==========================
App pod (10.128.0.15):
    curl https://api.stripe.com
    |
    | DNS: api.stripe.com → 54.187.174.169
    |
    | Packet:
    | Src IP: 10.128.0.15 (pod IP)
    | Dst IP: 54.187.174.169
    | Dst Port: 443

STEP 2: OVN Processing
========================
OVN cluster router checks destination:
    54.187.174.169 is NOT in:
    - Pod CIDR (10.128.0.0/14) — not a pod
    - Service CIDR (172.30.0.0/16) — not a service
    - VNet CIDR (10.0.0.0/16) — not a VNet host
    → Must go to external network

OVN SNAT (Source NAT):
    Original src: 10.128.0.15 (pod IP)
    New src: 10.0.1.4 (node IP)
    
    WHY: The VNet doesn't know about pod IPs (10.128.x.x).
    If OVN didn't SNAT, the VNet would drop the packet.


STEP 3: VNet Routing
=====================
Packet on VNet:
    Src IP: 10.0.1.4 (node IP after OVN SNAT)
    Dst IP: 54.187.174.169
    Dst Port: 443

Route table lookup (depends on configuration):

  Option A: Default (Azure LB outbound rules)
    → Azure LB provides SNAT using its public IP
    → Source becomes LB's public IP

  Option B: NAT Gateway attached to worker subnet
    → NAT GW SNATs: src becomes NAT GW's public IP (20.x.y.z)

  Option C: UDR to Azure Firewall (forced tunneling)
    → UDR: 0.0.0.0/0 → Azure Firewall (10.0.2.4)
    → Azure Firewall inspects, then SNATs to its public IP


STEP 4: Internet
==================
Packet on the internet (example with NAT Gateway):
    Src IP: 20.x.y.z (NAT GW's public IP)
    Dst IP: 54.187.174.169
    Dst Port: 443


DOUBLE SNAT SUMMARY (with NAT Gateway):
========================================
Pod sends:  src=10.128.0.15  (pod IP)
OVN SNAT:   src=10.0.1.4     (node IP)     ← first translation
NAT GW:     src=20.x.y.z     (public IP)   ← second translation
Internet sees: 20.x.y.z                     ← what external services log
```

> **WHY:** Egress goes through double SNAT. When you look at external service logs, the source IP will be the NAT Gateway's public IP (or the Azure LB's public IP if no NAT Gateway is configured). If you need to allowlist your cluster's outbound IP in an external firewall, you need to know which SNAT method is in use. Azure LB SNAT is problematic because the IP can be shared and may change. NAT Gateway gives you a dedicated, static IP.

### 8.4 Pod-to-Pod Traffic — Same Node vs. Cross-Node

**Same node (no tunnel needed):**

```text
Pod A (10.128.0.15) → Pod B (10.128.0.16), both on Node 1:

Pod A eth0 (veth pair)
    |
    v
br-int (OVS integration bridge)
    |
    | OVN flow rule:
    | dst 10.128.0.16 → output to Pod B's port on br-int
    |
    v
Pod B eth0 (veth pair)

No encapsulation. No SNAT. Direct switching on br-int.
Latency: < 0.1ms
```

**Cross-node (Geneve tunnel):**

```text
Pod A (10.128.0.15, Node 1) → Pod C (10.128.2.33, Node 2):

Pod A eth0 (veth pair)
    |
    v
br-int on Node 1
    |
    | OVN flow rule:
    | dst 10.128.2.33 → encapsulate in Geneve → send to Node 2
    |
    v
Geneve encapsulation:
+------------------------------------------------------------------+
| OUTER: Src=10.0.1.4 Dst=10.0.1.5 UDP DstPort=6081               |
| GENEVE HDR: VNI=0x1                                               |
| INNER: Src=10.128.0.15 Dst=10.128.2.33 TCP DstPort=8080          |
+------------------------------------------------------------------+
    |
    v
eth0 on Node 1 → VNet NIC → VNet
    |
    | VNet sees: 10.0.1.4 → 10.0.1.5 (just a UDP packet)
    | NSG: Allow UDP 6081 from VNet → PASS
    |
    v
eth0 on Node 2 → OVS receives on Geneve port
    |
    v
br-int on Node 2 → decapsulate → deliver to Pod C
```

> **WHY:** Cross-node pod traffic uses Geneve encapsulation. NSGs must allow UDP 6081 between worker nodes. Same-node traffic skips encapsulation entirely.

### 8.5 Pod-to-Service Traffic

```text
Pod A (10.128.0.15) calls Service "my-api" (ClusterIP 172.30.45.67:8080):

Pod A: curl http://my-api.production.svc.cluster.local:8080
    |
    v
CoreDNS resolves: → 172.30.45.67
    |
    v
OVN intercepts (172.30.0.0/16 = Service CIDR):
    |
    | OVN load balancer: selects backend pod
    | DNAT: 172.30.45.67:8080 → 10.128.2.33:8080
    |
    v
Packet is now pod-to-pod (10.128.0.15 → 10.128.2.33)
    → follows cross-node or same-node path
```

> **WHY:** The ClusterIP (172.30.45.67) never appears on any network interface — it's a virtual construct existing only as DNAT rules in OVN. When troubleshooting, check `oc get endpoints my-api -n production` to verify backends exist.

---

## 9. IP Address Architecture

### 9.1 The Five IP Ranges in ARO

Every ARO cluster uses five distinct IP ranges that must not overlap:

```text
+---------------------------------------------------------------+
|                    ARO IP Architecture                         |
+---------------------------------------------------------------+
|                                                               |
|  1. VNet CIDR: 10.0.0.0/16                                   |
|     Used for: Node IPs, LB IPs, gateway IPs                  |
|     Size: 65,536 addresses                                    |
|     YOU configure this when creating the VNet                 |
|                                                               |
|  2. Master Subnet CIDR: 10.0.0.0/27                          |
|     Used for: 3 master nodes + API LB + PE                    |
|     Minimum: /27 (32 IPs, 27 usable after Azure reservations)|
|     Must be within VNet CIDR                                  |
|                                                               |
|  3. Worker Subnet CIDR: 10.0.1.0/24                          |
|     Used for: Worker nodes + Ingress LB                       |
|     Minimum: /27, but /24 recommended for scaling             |
|     Must be within VNet CIDR                                  |
|                                                               |
|  4. Pod CIDR (Cluster Network): 10.128.0.0/14                |
|     Used for: Pod IP addresses                                |
|     Size: 262,144 addresses                                   |
|     Default host prefix: /23 (512 pods per node)              |
|     Managed internally by OVN (overlay)                       |
|                                                               |
|  5. Service CIDR (Service Network): 172.30.0.0/16             |
|     Used for: Kubernetes Service ClusterIPs                   |
|     Size: 65,536 addresses                                    |
|     Virtual only — never appears on a wire                    |
|                                                               |
+---------------------------------------------------------------+

These ranges MUST NOT overlap with:
  - Each other
  - On-prem networks (if using ExpressRoute/VPN)
  - Other VNets (if using peering)
  - Azure reserved ranges (168.63.129.16/32, 169.254.0.0/16)
  - Docker default bridge: 172.17.0.0/16
```

### 9.2 How IPs Are Allocated to Pods

```text
Cluster Pod CIDR: 10.128.0.0/14

When Node 1 joins the cluster:
    OVN allocates: 10.128.0.0/23 to Node 1
    
When a pod starts on Node 1:
    OVN assigns next available IP from 10.128.0.0/23
    Pod A: 10.128.0.2 (first usable)
    Pod B: 10.128.0.3
    ...

When Node 2 joins:
    OVN allocates: 10.128.2.0/23 to Node 2
```

> **WHY:** Hierarchical allocation means you can tell which node a pod is on from its IP. The /14 cluster network supports up to 512 nodes with /23 host prefix.

### 9.3 SNAT — When and Why Pod IPs Become Node IPs

OVN performs SNAT on pod traffic in specific situations:

| Traffic Type | SNAT? | Source IP at Destination |
|-------------|-------|------------------------|
| Pod → Pod (same cluster) | No | Pod IP (10.128.x.x) |
| Pod → Service (same cluster) | No | Pod IP (10.128.x.x) |
| Pod → Node IP (same cluster) | Yes | Node IP (10.0.x.x) |
| Pod → VNet resource (Azure SQL, etc.) | Yes | Node IP (10.0.x.x) |
| Pod → Internet (via LB/NAT GW) | Yes (double) | LB/NAT GW public IP |
| Pod → On-prem (via ExpressRoute) | Yes | Node IP (10.0.x.x) |

```text
Why SNAT happens for external traffic:

The VNet routing table only has routes for VNet CIDRs (10.0.0.0/16).
Pod CIDRs (10.128.0.0/14) have NO route in the VNet.

If a pod sent a packet with src=10.128.0.15 to Azure SQL:
    Azure SQL receives packet from 10.128.0.15
    Azure SQL sends response to 10.128.0.15
    VNet routing: "Where is 10.128.0.15?" → NO ROUTE → DROPPED!

With SNAT (src becomes 10.0.1.4):
    Azure SQL receives packet from 10.0.1.4
    Response routes back to 10.0.1.4 (within VNet)
    OVN conntrack: reverse SNAT → delivered to pod
```

> **WHY:** Pods talking to Azure PaaS services, VNet resources, or on-prem systems appear as node IPs. Configure service endpoint ACLs and on-prem firewalls using the worker subnet CIDR (10.0.1.0/24), not pod CIDR.

### 9.4 Outbound IP Options

```text
Option A: Azure LB Outbound Rules (default)
    - Uses LB's public IP for SNAT
    - IP may be shared with inbound traffic
    - Limited SNAT ports per VM

Option B: NAT Gateway (recommended for production)
    - Dedicated public IP(s) for outbound
    - Static, predictable
    - 64,000 SNAT ports per IP
    - Associate with worker subnet

Option C: Azure Firewall (for regulated environments)
    - UDR routes 0.0.0.0/0 to firewall
    - Firewall inspects + logs + SNATs
    - FQDN-based filtering
    - Uses firewall's public IP

External service firewall allowlist depends on your choice:
    Option A: LB public IP (may change if LB is recreated)
    Option B: NAT GW public IP (static)
    Option C: Azure Firewall public IP (static)
```

> **WHY:** Knowing your outbound IP is critical for external allowlisting. Default LB SNAT is problematic at scale (SNAT port exhaustion). NAT Gateway or Azure Firewall provide predictable, scalable outbound.

---

## 10. BGP and Hybrid Networking with ExpressRoute

### 10.1 BGP Fundamentals

**BGP (Border Gateway Protocol)** is the routing protocol that runs the internet. It's also used to connect corporate networks to Azure via ExpressRoute.

```text
BGP in one sentence:
    "I am AS 65010. I can reach networks 192.168.0.0/16 and 172.16.0.0/12.
     Let me tell my neighbors so they can route traffic to me."
```

**Key concepts:**

| Concept | What It Is | Example |
|---------|-----------|---------|
| **AS (Autonomous System)** | A network under one administrative control | Your company = AS 65010, Azure = AS 12076 |
| **ASN (AS Number)** | Unique number identifying an AS | 65010 (private: 64512-65534) |
| **Prefix** | A network (CIDR) that an AS announces | "I have 192.168.0.0/16" |
| **Peer** | A BGP neighbor you exchange routes with | ExpressRoute peers with your router |
| **Route Advertisement** | Telling your peer about a network you can reach | "Route to 10.0.0.0/16 via me" |

> **WHY:** BGP is how ARO pods reach on-premises resources. Without BGP, the VNet wouldn't know that 192.168.0.0/16 is reachable through the ExpressRoute gateway. BGP dynamically learns and propagates routes.

### 10.2 ExpressRoute Architecture

```text
Complete Hybrid Architecture with ExpressRoute:

+-------------------------------------------------------------------+
|                          Azure Region                              |
|                                                                    |
|  +-------------------+         +-------------------+               |
|  | ARO VNet          |         | ExpressRoute      |               |
|  | 10.0.0.0/16       |         | Gateway           |               |
|  |                   |         | (VNet Gateway)     |               |
|  | Master Nodes      |         |                   |               |
|  | Worker Nodes      |-------->| GW Subnet         |               |
|  | 10.0.1.4,5,6      | peered  | 10.0.255.0/27     |               |
|  |                   |         |                   |               |
|  | Route Table:      |         | BGP Peering:       |               |
|  | 192.168.0.0/16    |         | Azure ASN: 12076   |               |
|  |   → VNet GW       |         | Your ASN: 65010   |               |
|  +-------------------+         +---+---------------+               |
|                                    |                                |
|                                    | ExpressRoute Circuit           |
|                                    | (dedicated fiber via partner)  |
|                                    | Peering: Private               |
|                                    |                                |
+------------------------------------+--------------------------------+
                                     |
                                     v
                    +----------------------------+
                    | Connectivity Partner       |
                    | (Equinix, AT&T, Megaport)  |
                    +----------------------------+
                                     |
                                     v
                    +----------------------------+
                    | On-Prem Border Router      |
                    | (AS 65010)                  |
                    |                            |
                    | BGP Neighbor: Azure peer    |
                    | Advertises: 192.168.0.0/16 |
                    | Learns:     10.0.0.0/16    |
                    +----------------------------+
                                |
                                v
                    +----------------------------+
                    | On-Prem Network             |
                    | 192.168.0.0/16             |
                    |                            |
                    | Database: 192.168.10.50    |
                    | Active Directory: 192.168.1.10 |
                    +----------------------------+
```

### 10.3 ExpressRoute Peering Types

| Peering Type | What It Connects | Use Case |
|-------------|-----------------|----------|
| **Private Peering** | On-prem ↔ Azure VNets | ARO pods reaching on-prem databases |
| **Microsoft Peering** | On-prem ↔ Microsoft services (M365, Azure PaaS public IPs) | Accessing Azure PaaS services from on-prem without internet |

> **WHY:** For ARO hybrid networking, you need **Private Peering**. This exchanges BGP routes between your on-prem network and your Azure VNets, allowing pods to reach on-prem resources. Microsoft Peering is for reaching Azure's public-facing services from on-prem — it's not commonly needed for ARO workloads.

### 10.4 BGP Route Exchange with ExpressRoute

```text
BGP Route Exchange:

Your On-Prem Router (AS 65010)          Azure ExpressRoute (AS 12076)
+----------------------------+          +----------------------------+
| "I have:                   |          | "I have:                   |
|   192.168.0.0/16 (corp)    | <------> |   10.0.0.0/16 (ARO VNet)  |
|   172.16.0.0/12 (DC2)     |   BGP    |                            |
|                            | session  |                            |
| I learned from Azure:      |          | I learned from on-prem:    |
|   10.0.0.0/16             |          |   192.168.0.0/16           |
|                            |          |   172.16.0.0/12            |
+----------------------------+          +----------------------------+
```

Route propagation:
1. On-prem router advertises 192.168.0.0/16 via BGP
2. ExpressRoute gateway learns this route
3. Azure automatically adds it to the VNet's effective routes
4. Worker nodes now have a route: 192.168.0.0/16 → VNet Gateway
5. Pods can reach on-prem (after OVN SNAT to node IP)

```text
Verify learned routes:
$ az network vnet-gateway list-learned-routes \
    --resource-group myRG \
    --name myERGateway \
    --output table

Network          NextHop        Origin    AsPath    Weight
192.168.0.0/16   10.0.255.4     EBgp      65010     32768
172.16.0.0/12    10.0.255.4     EBgp      65010     32768
```

### 10.5 VPN Gateway as Alternative

If ExpressRoute is too expensive, a VPN Gateway provides encrypted tunnels over the public internet:

```bash
# Create VPN Gateway (takes ~30 minutes)
az network vnet-gateway create \
  --name aro-vpn-gw \
  --resource-group myRG \
  --vnet myVNet \
  --gateway-type Vpn \
  --vpn-type RouteBased \
  --sku VpnGw2 \
  --generation Generation2 \
  --asn 65515

# Create Local Network Gateway (represents on-prem)
az network local-gateway create \
  --name onprem-lng \
  --resource-group myRG \
  --gateway-ip-address YOUR_ONPREM_PUBLIC_IP \
  --local-address-prefixes 192.168.0.0/16 \
  --asn 65010 \
  --bgp-peering-address 192.168.1.1

# Create VPN Connection with BGP
az network vpn-connection create \
  --name aro-to-onprem \
  --resource-group myRG \
  --vnet-gateway1 aro-vpn-gw \
  --local-gateway2 onprem-lng \
  --shared-key "YourSharedKey123!" \
  --enable-bgp true
```

> **WHY:** VPN Gateway is cheaper than ExpressRoute but has lower bandwidth (up to 10 Gbps vs. 100 Gbps) and higher latency (internet-dependent). It supports BGP just like ExpressRoute. For development/staging ARO clusters or low-throughput hybrid scenarios, VPN Gateway is often sufficient.

### 10.6 UDR for Forced Tunneling

Forced tunneling routes ALL outbound internet traffic from ARO through your on-prem network or an Azure Firewall:

```text
Without Forced Tunneling:                With Forced Tunneling:

Pod → Node → Azure internet → Internet    Pod → Node → UDR →
                                           ExpressRoute → On-Prem Firewall →
                                           Internet

or:                                       Pod → Node → UDR →
                                           Azure Firewall → Internet
```

> **WHY:** Regulated industries (finance, healthcare) require all internet-bound traffic to be inspected and logged. Forced tunneling via UDR ensures nothing leaves the network without going through a firewall. ARO supports this but you must ensure the firewall allows required ARO FQDNs (see Security section).

---

## 11. DNS Architecture in ARO

### 11.1 DNS Layers in ARO

```text
DNS Resolution Hierarchy (from inside a pod):

1. Pod's /etc/resolv.conf:
     nameserver 172.30.0.10  (CoreDNS Service ClusterIP)
     search production.svc.cluster.local svc.cluster.local cluster.local
         |
         v
2. CoreDNS pods (in openshift-dns namespace):
     Handles: *.svc.cluster.local (Services)
              *.pod.cluster.local (Pods)
              *.cluster.local
         |
         | For non-cluster domains:
         v
3. Azure DNS Resolver (168.63.129.16):
     Handles: Azure DNS Private Zones
              Azure public DNS zones
              External domains
         |
         v
4. Public DNS:
     Handles: Everything else (google.com, github.com, etc.)
```

> **WHY:** The Azure DNS resolver at 168.63.129.16 is a special "magic IP" — it's always available from any Azure VM and resolves both Azure Private DNS zones and public DNS. CoreDNS forwards non-cluster queries to this IP. Understanding this chain is essential for debugging DNS issues in ARO.

### 11.2 CoreDNS Inside the Cluster

CoreDNS runs as a DaemonSet in `openshift-dns` with one pod per node:

```text
CoreDNS Architecture:

+--------------------+
| dns-default Service|
| 172.30.0.10:53     |
+--------+-----------+
         |
         | (Pod resolv.conf points here)
         |
+--------v-----------+     +--------------------+     +--------------------+
| CoreDNS Pod (Node1)|     | CoreDNS Pod (Node2)|     | CoreDNS Pod (Node3)|
| (DaemonSet)        |     | (DaemonSet)        |     | (DaemonSet)        |
+--------+-----------+     +--------+-----------+     +--------+-----------+
         |                          |                          |
         v                          v                          v
+--------------------+     +--------------------+
| Kubernetes API     |     | Upstream DNS:      |
| (for svc.cluster.  |     | 168.63.129.16      |
|  local lookups)    |     | (for external names)|
+--------------------+     +--------------------+
```

> **WHY:** CoreDNS is deployed as a DaemonSet (one per node) so DNS queries don't cross the network — a pod's DNS query goes to CoreDNS on the same node, avoiding Geneve tunnel overhead.

### 11.3 Azure DNS Private Zones for ARO

ARO creates two private DNS zones for private clusters:

```text
Private DNS Zone 1 (API):
+-------------------------------------------------------+
| Zone: <cluster-id>.privatelink.<region>.azmosa.io     |
|                                                       |
| api.<cluster-domain>                                  |
|   → A record → 10.0.0.10 (internal API LB IP)        |
|                                                       |
| Linked to: ARO VNet                                   |
+-------------------------------------------------------+

Private DNS Zone 2 (Apps):
+-------------------------------------------------------+
| Zone: <cluster-domain>                                |
|                                                       |
| *.apps.<cluster-domain>                               |
|   → A record → 10.0.1.10 (internal ingress LB IP)    |
|                                                       |
| Linked to: ARO VNet                                   |
+-------------------------------------------------------+
```

### 11.4 Split-Horizon DNS for Private Clusters

```text
Private Cluster DNS:

From the internet:
    dig my-app.apps.mycluster.example.com
    → NXDOMAIN (doesn't exist in public DNS)

From inside the VNet (or connected network):
    dig my-app.apps.mycluster.example.com
    → 10.0.1.10 (internal ingress LB IP)

How this works:
    Azure DNS Private Zone:
    - Linked to the ARO VNet
    - *.apps.mycluster.example.com → internal LB
    - Only visible to DNS resolvers inside linked VNets
```

```text
Private DNS Flow (from on-prem):

On-Prem User: "resolve my-app.apps.mycluster.example.com"
    |
    v
On-Prem DNS Server
    |
    | Conditional forwarder:
    | *.apps.mycluster.example.com → 168.63.129.16
    | (via ExpressRoute/VPN to Azure DNS resolver)
    |
    v
Azure DNS Resolver (168.63.129.16)
    |
    v
Azure DNS Private Zone
    |
    | *.apps.mycluster.example.com → 10.0.1.10
    |
    v
Response: 10.0.1.10
    |
    v
On-prem user connects to 10.0.1.10 via ExpressRoute
```

> **WHY:** Split-horizon DNS is essential for private clusters. For on-prem resolution, you need a DNS forwarder that routes queries for the cluster's domain to Azure's DNS resolver (168.63.129.16) via the ExpressRoute/VPN connection. Alternatively, use Azure DNS Private Resolver (a dedicated DNS forwarding service) deployed in a VNet linked to the private zone.

### 11.5 Custom DNS Configuration

If your VNet uses a custom DNS server (not Azure's default 168.63.129.16):

```bash
# Check VNet DNS settings
az network vnet show --resource-group myRG --name myVNet \
  --query "dhcpOptions.dnsServers"

# If custom DNS servers are set, they MUST forward to 168.63.129.16
# for Azure Private DNS Zone resolution to work.
```

> **WHY:** If you configure custom DNS servers on the VNet, Azure's built-in Private DNS resolution breaks unless those servers forward to 168.63.129.16. This is a common pitfall — your custom DNS server handles corporate zones but must forward Azure-specific queries (like *.privatelink.*.azmosa.io) to Azure's resolver.

---

## 12. Security Architecture

### 12.1 S1 — Private ARO Cluster Security Bundle

This bundle locks down a private ARO cluster.

#### NSG Rules for Master Subnet

```bash
MASTER_NSG="aro-master-nsg"
RG="myResourceGroup"

# Rule 1: Allow API server access from VNet (port 6443)
az network nsg rule create \
  --resource-group $RG \
  --nsg-name $MASTER_NSG \
  --name AllowAPIServer \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes VirtualNetwork \
  --destination-port-ranges 6443
```

> **WHY:** Port 6443 is the Kubernetes API server port on master nodes. Worker nodes' kubelets connect here for watch, status updates, and API calls. `oc` commands also target this port. Restricting source to `VirtualNetwork` ensures only VNet traffic (including ExpressRoute-learned routes) can reach the API.

```bash
# Rule 2: Allow etcd traffic between masters (ports 2379-2380)
az network nsg rule create \
  --resource-group $RG \
  --nsg-name $MASTER_NSG \
  --name AllowEtcd \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.0.0.0/27 \
  --destination-port-ranges 2379-2380
```

> **WHY:** etcd is the cluster's key-value store — it holds all cluster state. Ports 2379 (client) and 2380 (peer) must be open between master nodes only. Restricting source to the master subnet CIDR ensures only masters can talk to etcd. If etcd is unreachable between masters, the cluster loses quorum and becomes unavailable.

```bash
# Rule 3: Allow Geneve overlay (UDP 6081)
az network nsg rule create \
  --resource-group $RG \
  --nsg-name $MASTER_NSG \
  --name AllowGeneve \
  --priority 120 \
  --direction Inbound \
  --access Allow \
  --protocol Udp \
  --source-address-prefixes VirtualNetwork \
  --destination-port-ranges 6081
```

> **WHY:** UDP 6081 is the Geneve tunnel port for OVN overlay networking. Master nodes also run pods (though typically only system pods), so they participate in the overlay network. Blocking this breaks cross-node pod communication.

#### NSG Rules for Worker Subnet

```bash
WORKER_NSG="aro-worker-nsg"

# Rule 1: Allow kubelet communication from masters (port 10250)
az network nsg rule create \
  --resource-group $RG \
  --nsg-name $WORKER_NSG \
  --name AllowKubelet \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.0.0.0/27 \
  --destination-port-ranges 10250
```

> **WHY:** Port 10250 is the kubelet API. The API server on master nodes calls kubelets for `oc logs`, `oc exec`, and health checks. Source is restricted to master subnet. Without this, `oc logs` and `oc exec` fail.

```bash
# Rule 2: Allow NodePort range from Azure LB
az network nsg rule create \
  --resource-group $RG \
  --nsg-name $WORKER_NSG \
  --name AllowNodePorts \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes AzureLoadBalancer \
  --destination-port-ranges 30000-32767
```

> **WHY:** The Azure LB distributes ingress traffic to NodePorts on worker nodes. The router's NodePort (30080/30443) must be reachable from the LB. Using `AzureLoadBalancer` as source restricts to Azure's LB health probes and forwarded traffic only.

```bash
# Rule 3: Allow Geneve overlay (UDP 6081)
az network nsg rule create \
  --resource-group $RG \
  --nsg-name $WORKER_NSG \
  --name AllowGeneve \
  --priority 120 \
  --direction Inbound \
  --access Allow \
  --protocol Udp \
  --source-address-prefixes VirtualNetwork \
  --destination-port-ranges 6081
```

> **WHY:** Same as master subnet — Geneve overlay must be allowed for pod networking.

```bash
# Rule 4: Allow node-to-node metrics (TCP 9000-9999)
az network nsg rule create \
  --resource-group $RG \
  --nsg-name $WORKER_NSG \
  --name AllowNodeMetrics \
  --priority 130 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes VirtualNetwork \
  --destination-port-ranges 9000-9999
```

> **WHY:** Ports 9000-9999 are used by OpenShift node-level services: node-exporter (9100), OVN metrics (9105), and other monitoring endpoints. Required for Prometheus scraping and cluster health monitoring.

#### UDR for Forced Tunneling Through Azure Firewall

```bash
# Create Azure Firewall
az network firewall create \
  --name aro-firewall \
  --resource-group $RG \
  --location eastus

# Get firewall private IP
FW_PRIVATE_IP=$(az network firewall show \
  --name aro-firewall \
  --resource-group $RG \
  --query "ipConfigurations[0].privateIpAddress" -o tsv)

# Create Route Table with UDR
az network route-table create \
  --name aro-udr \
  --resource-group $RG \
  --disable-bgp-route-propagation false

az network route-table route create \
  --route-table-name aro-udr \
  --resource-group $RG \
  --name DefaultToFirewall \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address $FW_PRIVATE_IP

# Associate UDR with worker subnet
az network vnet subnet update \
  --resource-group $RG \
  --vnet-name myVNet \
  --name worker-subnet \
  --route-table aro-udr
```

#### Azure Firewall Required FQDN Rules for ARO

```bash
# Application Rules (FQDN-based)
az network firewall application-rule create \
  --firewall-name aro-firewall \
  --resource-group $RG \
  --collection-name aro-required \
  --name aro-management \
  --priority 100 \
  --action Allow \
  --protocols Https=443 \
  --source-addresses "10.0.1.0/24" \
  --target-fqdns \
    "arosvc.${LOCATION}.data.azurecr.io" \
    "management.azure.com" \
    "login.microsoftonline.com" \
    "gcs.prod.monitoring.core.windows.net" \
    "*.blob.core.windows.net" \
    "*.servicebus.windows.net" \
    "*.table.core.windows.net"

az network firewall application-rule create \
  --firewall-name aro-firewall \
  --resource-group $RG \
  --collection-name aro-registries \
  --name container-registries \
  --priority 110 \
  --action Allow \
  --protocols Https=443 \
  --source-addresses "10.0.1.0/24" \
  --target-fqdns \
    "quay.io" \
    "*.quay.io" \
    "registry.redhat.io" \
    "*.registry.redhat.io" \
    "sso.redhat.com" \
    "registry.access.redhat.com" \
    "mirror.openshift.com" \
    "*.openshift.com"

# Network Rules (port-based)
az network firewall network-rule create \
  --firewall-name aro-firewall \
  --resource-group $RG \
  --collection-name aro-network \
  --name aro-api \
  --priority 100 \
  --action Allow \
  --protocols Tcp \
  --source-addresses "10.0.1.0/24" \
  --destination-ports 443 6443 \
  --destination-addresses "*"
```

> **WHY:** The Azure Firewall must allow specific FQDNs that ARO needs: `arosvc.*` for the ARO RP, container registries (quay.io, registry.redhat.io) for image pulls, and Azure management APIs for cluster operations. Blocking ANY required FQDN can break cluster functionality — from failed image pulls to blocked upgrades.

#### Service Endpoints for ACR and Storage

```bash
# Enable Service Endpoints on worker subnet
az network vnet subnet update \
  --resource-group $RG \
  --vnet-name myVNet \
  --name worker-subnet \
  --service-endpoints Microsoft.ContainerRegistry Microsoft.Storage
```

> **WHY:** Service Endpoints route traffic to Azure Container Registry (ACR) and Azure Storage directly over the Azure backbone instead of through the internet or firewall. This is faster, free, and more secure. If your cluster pulls images from a private ACR, Service Endpoints ensure the traffic stays private.

#### Default Deny NetworkPolicy

```bash
cat <<'EOF' | oc apply -n private-app -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
```

```bash
# Allow ingress from router pods only
cat <<'EOF' | oc apply -n private-app -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-openshift-ingress
spec:
  podSelector:
    matchLabels:
      app: hello-private
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          network.openshift.io/policy-group: ingress
  policyTypes:
  - Ingress
EOF
```

```bash
# Allow DNS egress (CRITICAL — without this, all DNS breaks)
cat <<'EOF' | oc apply -n private-app -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
spec:
  podSelector: {}
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  policyTypes:
  - Egress
EOF
```

> **WHY:** If you have a default-deny egress policy but forget to allow DNS (port 53), every DNS lookup fails. This is the most common NetworkPolicy mistake.

#### RBAC

```bash
cat <<'EOF' | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: network-viewer
rules:
- apiGroups: [""]
  resources: ["pods","services","endpoints","nodes"]
  verbs: ["get","list","watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies","ingresses"]
  verbs: ["get","list","watch"]
- apiGroups: ["route.openshift.io"]
  resources: ["routes"]
  verbs: ["get","list","watch"]
EOF
```

> **WHY:** Least-privilege access. Network ops teams need read-only access to networking resources for troubleshooting.

### 12.2 S2 — Hybrid ARO Security Bundle

This bundle secures an ARO cluster with connectivity to on-premises networks via ExpressRoute.

#### ExpressRoute/VPN Security

```text
Security layers for hybrid connectivity:

1. ExpressRoute: private fiber (not internet), but NOT encrypted by default
   → Add MACsec (Layer 2 encryption) for ExpressRoute Direct
   → Or use VPN over ExpressRoute for IPsec encryption

2. NSG on worker subnet: controls which on-prem CIDRs can reach workers
3. UDR: controls which on-prem CIDRs are routable from the VNet
4. On-prem firewall: controls what the ARO cluster can reach
5. NetworkPolicy: controls which pods can reach on-prem
```

#### NSG Rules for Hybrid Traffic

```bash
# Allow on-prem DB access from worker subnet only
az network nsg rule create \
  --resource-group $RG \
  --nsg-name $WORKER_NSG \
  --name AllowOnPremDB \
  --priority 200 \
  --direction Outbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.0.1.0/24 \
  --destination-address-prefixes 192.168.10.50/32 \
  --destination-port-ranges 5432
```

> **WHY:** Restrict outbound to the specific on-prem database IP and port. Don't allow broad access to 192.168.0.0/16 unless necessary.

#### On-Prem Firewall Rules

```text
# On your on-prem firewall, allow only specific traffic:

# Allow ARO worker nodes to reach the database
allow src 10.0.1.0/24 dst 192.168.10.50/32 port 5432 proto tcp

# Allow ARO worker nodes to reach monitoring
allow src 10.0.1.0/24 dst 192.168.20.10/32 port 9090 proto tcp

# Deny everything else from ARO
deny src 10.0.0.0/16 dst any

# Note: Source is 10.0.1.0/24 (worker subnet), not 10.128.0.0/14 (pod CIDR),
# because OVN SNATs pod IPs to node IPs before they leave the node.
```

> **WHY:** On-prem firewall rules must use the worker subnet CIDR (node IPs) as source, not pod CIDR. OVN SNATs pod traffic to node IPs before it leaves the node.

#### NetworkPolicy for DB Egress

```bash
cat <<'EOF' | oc apply -n hybrid-app -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-db-egress-only
spec:
  podSelector:
    matchLabels:
      app: db-client
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 192.168.10.50/32
    ports:
    - protocol: TCP
      port: 5432
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF
```

> **WHY:** Limits db-client pods to only reach the database (192.168.10.50:5432) and DNS. If compromised, the attacker can only reach the database, not the internet, not other on-prem systems.

#### mTLS with Service Mesh

```bash
# Label namespace for sidecar injection
oc label namespace hybrid-app istio-injection=enabled

# Enforce strict mTLS
cat <<'EOF' | oc apply -n hybrid-app -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
spec:
  mtls:
    mode: STRICT
EOF

# Authorization policy: identity-based access
cat <<'EOF' | oc apply -n hybrid-app -f -
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: db-proxy-access
spec:
  selector:
    matchLabels:
      app: db-proxy
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/hybrid-app/sa/db-client"]
    to:
    - operation:
        ports: ["5432"]
EOF
```

> **WHY:** mTLS encrypts all pod-to-pod traffic. AuthorizationPolicy adds identity-based access on top of NetworkPolicies — defense in depth.

---

## 13. Scenario Matrix & Traffic Exposure Table

### 13.1 Scenario Matrix

| # | Scenario | App Use Case | Traffic Type | Ingress Path | Egress Path | Exposure Level |
|---|----------|-------------|-------------|-------------|-------------|---------------|
| 1 | **Public App** | Public websites, SaaS APIs | HTTP/HTTPS | Internet → Azure DNS → Public LB → Router → Pod | Pod → OVN SNAT → LB SNAT/NAT GW → Internet | Public LB with PIP, internet-routable |
| 2 | **Private App** | Internal corporate apps | HTTP/HTTPS | Corp → ER/VPN → Internal LB → Router → Pod | Pod → OVN SNAT → NAT GW/Firewall → Internet | No public IPs, reachable only from connected networks |
| 3 | **Zero-Egress** | Regulated (HIPAA, PCI) | HTTP/TCP | Same as Private | Pod → Service Endpoints only (no internet) | No outbound internet |
| 4 | **Hybrid App** | Apps with on-prem DB | TCP | Public or Private | Pod → OVN SNAT → VNet route → ER GW → On-prem | Node IP visible to on-prem, BGP-routed |
| 5 | **Service Mesh** | Microservices with mTLS | gRPC/mTLS | Mesh gateway | Sidecar → OVN → NAT/ER | L7-enforced, encrypted pod-to-pod |
| 6 | **Custom Front Door** | WAF, client cert auth | HTTPS | Internet → AFD/AppGW → ARO LB → Router → Pod | Same as Public | TLS at AFD, re-encrypted to ARO |
| 7 | **Inter-Cluster** | Multi-region, DR | gRPC/mTLS | Cluster A → VNet Peering/VPN → Cluster B LB → Pod | Same path, reverse | L3 routed between VNets |
| 8 | **Registry Heavy** | CI/CD pipelines | HTTPS | N/A | Pod → Service Endpoint/NAT GW → ACR/Quay | Outbound HTTPS only |
| 9 | **Observability** | Logs, metrics, traces | OTLP/HTTP | N/A | Pod → NAT GW → Datadog/Splunk/etc | Outbound only |
| 10 | **Node-to-Node** | SDN overlay | Geneve/UDP 6081 | N/A | N/A | L2.5 overlay, never leaves VNet |
| 11 | **Control Plane** | API server ↔ kubelet | HTTPS | Same VNet (direct) | Same VNet (direct) | Intra-VNet, private |

### 13.2 Traffic Exposure Table

| Traffic Flow | Source IP Seen by Destination | Encryption | Azure Components Traversed | K8s Components Traversed |
|-------------|------------------------------|-----------|--------------------------|------------------------|
| Internet → App | Client's public IP (X-Forwarded-For) | TLS (edge at router) | Azure LB | OVN, Router, Service, Pod |
| Corp → Private App | Corp client IP | TLS | ER/VPN GW, Internal LB | OVN, Router, Service, Pod |
| Pod → Internet | LB/NAT GW/Firewall public IP | TLS (app-initiated) | OVN SNAT, LB/NAT GW/FW | OVN SNAT |
| Pod → On-prem DB | Node IP (OVN SNAT) | Optional (app-level) | OVN SNAT, ER GW | OVN SNAT |
| Pod → Pod (same node) | Pod IP (no SNAT) | None (unless mesh) | None | OVS br-int |
| Pod → Pod (cross node) | Pod IP (no SNAT) | None (unless mesh) | Geneve over VNet | OVS, Geneve tunnel |
| Pod → Service | Pod IP | None (unless mesh) | None | OVN DNAT, OVS |
| Pod → Azure PaaS (SE) | Node IP (OVN SNAT) | TLS | OVN SNAT, Service Endpoint | OVN SNAT |
| Pod → Azure PaaS (PE) | Private Endpoint NIC IP | TLS | OVN SNAT, Private Endpoint | OVN SNAT |
| API Server → Kubelet | Master node IP | TLS (mutual) | VNet (direct) | Kubelet |
| ARO RP → API Server | Private Link NIC IP | TLS | Private Link | API Server |

### 13.3 Port Reference

| Port | Protocol | Purpose | Used By |
|------|---------|---------|---------|
| 6443 | TCP | Kubernetes API server | oc, kubelets, controllers |
| 10250 | TCP | Kubelet API | API server (for logs/exec) |
| 2379-2380 | TCP | etcd client + peer | Master nodes (cluster state) |
| 6081 | UDP | Geneve overlay tunnels | OVN-Kubernetes (cross-node pod traffic) |
| 30000-32767 | TCP | NodePort range | Services (LB backends) |
| 443 | TCP | HTTPS (general) | Everything external |
| 80 | TCP | HTTP (redirects to 443) | Router |
| 53 | UDP/TCP | DNS | CoreDNS |
| 9000-9999 | TCP | Node metrics/health | Prometheus, node-exporter |
| 5432 | TCP | PostgreSQL | Example on-prem DB |

---

## 14. Complete Command Reference

### 14.1 Cluster Creation

#### Public ARO Cluster

```bash
# Login
az login

# Register providers (one-time)
az provider register -n Microsoft.RedHatOpenShift --wait
az provider register -n Microsoft.Compute --wait
az provider register -n Microsoft.Storage --wait
az provider register -n Microsoft.Authorization --wait

# Create resource group
az group create --name aro-rg --location eastus

# Create VNet
az network vnet create \
  --resource-group aro-rg \
  --name aro-vnet \
  --address-prefixes 10.0.0.0/16

# Create master subnet (disable private link policies)
az network vnet subnet create \
  --resource-group aro-rg \
  --vnet-name aro-vnet \
  --name master-subnet \
  --address-prefixes 10.0.0.0/27 \
  --private-link-service-network-policies Disabled

# Create worker subnet
az network vnet subnet create \
  --resource-group aro-rg \
  --vnet-name aro-vnet \
  --name worker-subnet \
  --address-prefixes 10.0.1.0/24

# Create ARO cluster (public)
az aro create \
  --resource-group aro-rg \
  --name my-aro-cluster \
  --vnet aro-vnet \
  --master-subnet master-subnet \
  --worker-subnet worker-subnet \
  --pull-secret @pull-secret.txt

# Get cluster credentials
az aro list-credentials \
  --resource-group aro-rg \
  --name my-aro-cluster

# Get API server URL
az aro show \
  --resource-group aro-rg \
  --name my-aro-cluster \
  --query "apiserverProfile.url" -o tsv

# Login to cluster
API_URL=$(az aro show -g aro-rg -n my-aro-cluster --query "apiserverProfile.url" -o tsv)
KUBEADMIN_PASS=$(az aro list-credentials -g aro-rg -n my-aro-cluster --query "kubeadminPassword" -o tsv)
oc login $API_URL -u kubeadmin -p $KUBEADMIN_PASS
```

#### Private ARO Cluster

```bash
az aro create \
  --resource-group aro-rg \
  --name my-private-aro \
  --vnet aro-vnet \
  --master-subnet master-subnet \
  --worker-subnet worker-subnet \
  --apiserver-visibility Private \
  --ingress-visibility Private \
  --pull-secret @pull-secret.txt
```

> **WHY:** `--apiserver-visibility Private` creates the API LB with no public IP. `--ingress-visibility Private` creates the ingress LB with no public IP. You need VPN/ExpressRoute/bastion access to the VNet to use `oc` commands or reach applications.

### 14.2 Ingress Configuration

```bash
# Check current ingress controller
oc get ingresscontroller default -n openshift-ingress-operator -o yaml

# Check router pods
oc get pods -n openshift-ingress -o wide

# Check router service (shows LB type and external IP)
oc get svc router-default -n openshift-ingress

# Create an edge-terminated Route
oc create route edge my-app \
  --service=my-app-svc \
  --hostname=my-app.apps.mycluster.example.com

# Create a passthrough Route
oc create route passthrough my-tls-app \
  --service=my-tls-app-svc \
  --hostname=my-tls-app.apps.mycluster.example.com
```

### 14.3 Network Policy Examples

```bash
# List all network policies
oc get networkpolicy -A

# Default deny all
cat <<'EOF' | oc apply -n my-namespace -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Allow from monitoring namespace
cat <<'EOF' | oc apply -n my-namespace -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-monitoring
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: openshift-monitoring
  policyTypes:
  - Ingress
EOF

# Allow egress to specific external CIDR + DNS
cat <<'EOF' | oc apply -n my-namespace -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-api
spec:
  podSelector:
    matchLabels:
      app: api-caller
  egress:
  - to:
    - ipBlock:
        cidr: 54.0.0.0/8
    ports:
    - protocol: TCP
      port: 443
  - to: []
    ports:
    - protocol: UDP
      port: 53
  policyTypes:
  - Egress
EOF
```

### 14.4 Troubleshooting Commands

```bash
# Check node status and IPs
oc get nodes -o wide

# Check all pods in openshift-ingress
oc get pods -n openshift-ingress -o wide

# Check OVN pods
oc get pods -n openshift-ovn-kubernetes -o wide

# Check DNS pods
oc get pods -n openshift-dns -o wide

# Test DNS resolution from a pod
oc run dns-test --image=registry.access.redhat.com/ubi9/ubi-minimal --rm -it --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local

# Test external connectivity from a pod
oc run net-test --image=registry.access.redhat.com/ubi9/ubi --rm -it --restart=Never -- \
  curl -sI --connect-timeout 5 https://www.redhat.com

# Check Service endpoints
oc get endpoints my-service -n my-namespace

# Check OVN flows on a node
oc debug node/<node-name> -- chroot /host ovs-ofctl dump-flows br-int

# Check OVN SNAT rules
oc debug node/<node-name> -- chroot /host ovn-nbctl lr-nat-list ovn_cluster_router

# Check Azure LB health
az network lb show --resource-group aro-rg --name <lb-name>

# Check backend pool health
az network lb probe show --resource-group aro-rg --lb-name <lb-name> --name <probe-name>

# Check NSG rules
az network nsg rule list --resource-group aro-rg --nsg-name aro-worker-nsg --output table

# Check effective routes on a NIC
az network nic show-effective-route-table \
  --resource-group aro-rg \
  --name <worker-nic-name> --output table

# Check VNet peering status
az network vnet peering list --resource-group aro-rg --vnet-name aro-vnet --output table

# Packet capture on a node
oc debug node/<node-name> -- chroot /host tcpdump -i any -c 100 port 6081

# Collect must-gather
oc adm must-gather --dest-dir=/tmp/network-debug -- /usr/bin/gather_network_logs
```

### 14.5 Security Validation Commands

```bash
# Verify NSG rules
az network nsg rule list --resource-group aro-rg --nsg-name aro-worker-nsg --output table

# Check effective NSG on a NIC
az network nic list-effective-nsg \
  --resource-group aro-rg \
  --name <worker-nic-name>

# Verify UDRs on subnet
az network route-table route list \
  --resource-group aro-rg \
  --route-table-name aro-udr --output table

# Check Service Endpoints on subnet
az network vnet subnet show \
  --resource-group aro-rg \
  --vnet-name aro-vnet \
  --name worker-subnet \
  --query "serviceEndpoints[].service"

# Test that NetworkPolicies are enforced
oc exec blocked-pod -- curl -s --connect-timeout 3 http://sensitive-service:8080 \
  && echo "FAIL: should be blocked" || echo "OK: blocked as expected"

# Check ExpressRoute circuit status
az network express-route show \
  --resource-group aro-rg \
  --name my-er-circuit \
  --query "{state:serviceProviderProvisioningState,peeringState:peerings[0].state}"

# Verify Azure Firewall allows required FQDNs
az network firewall application-rule list \
  --firewall-name aro-firewall \
  --resource-group aro-rg --output table
```

---

## 15. Troubleshooting Decision Tree

### 15.1 Pods Can't Reach the Internet

```text
Symptom: oc exec my-pod -- curl -sI https://google.com → timeout

Q: Can the pod resolve DNS?
├── NO: oc exec my-pod -- nslookup google.com
│   ├── Fails? → Check CoreDNS pods: oc get pods -n openshift-dns
│   │   ├── CoreDNS pods not running? → Check DaemonSet: oc get ds -n openshift-dns
│   │   └── CoreDNS running but not resolving?
│   │       → Check CoreDNS logs: oc logs -n openshift-dns -l dns.operator.openshift.io/daemonset-dns
│   │       → Check NetworkPolicy blocking port 53 egress
│   └── Resolves OK? → DNS is fine, problem is routing/NAT
│
└── YES: DNS works but connection times out
    ├── Check outbound path: what's the default route?
    │   ├── Azure LB SNAT: check LB outbound rules
    │   │   → az network lb outbound-rule list --lb-name <lb> -g aro-rg
    │   ├── NAT Gateway: check NAT GW status
    │   │   → az network nat gateway show -g aro-rg -n <natgw>
    │   └── Azure Firewall (UDR): check firewall rules
    │       → az network firewall application-rule list --firewall-name <fw> -g aro-rg
    │       → Is the target FQDN allowed?
    │
    ├── Check NSG outbound rules:
    │   → az network nsg rule list -g aro-rg --nsg-name aro-worker-nsg
    │   ├── Outbound denied? → Fix NSG
    │   └── Outbound allowed? → NSG is fine
    │
    └── Check NetworkPolicy egress:
        ├── Default-deny egress? → Need allow rule for target
        └── No egress policy? → Problem is at Azure layer
```

### 15.2 External Users Can't Reach the App

```text
Symptom: curl https://my-app.apps.mycluster.example.com → timeout

Q: Does DNS resolve?
├── NO: dig my-app.apps.mycluster.example.com
│   ├── NXDOMAIN? → Check Azure DNS for *.apps wildcard record
│   │   → Private cluster? DNS only resolves from within VNet
│   └── Wrong IP? → Check LB public IP, update DNS
│
└── YES: DNS resolves to LB IP
    ├── Check LB health: az network lb probe show ...
    │   ├── All backends unhealthy? → NSG blocking LB health probes
    │   │   → Check: NSG allows AzureLoadBalancer source on NodePort range
    │   └── Some healthy? → LB is fine
    │
    ├── Check router pods: oc get pods -n openshift-ingress
    │   ├── Not running? → Check deployment
    │   └── Running? → Router is fine
    │
    ├── Check Route: oc get route my-app -n my-namespace
    │   ├── Not found? → Create the Route
    │   └── Exists? → Route is fine
    │
    ├── Check Service endpoints: oc get endpoints my-app-svc
    │   ├── No endpoints? → Pods not running or labels don't match
    │   └── Endpoints exist? → Service is fine
    │
    └── Check pod health: oc get pods -l app=my-app
        ├── CrashLoopBackOff? → Check pod logs
        └── Running and Ready? → Check if app binds to correct port
```

### 15.3 Pod-to-Pod Communication Fails

```text
Symptom: oc exec pod-a -- curl http://pod-b-ip:8080 → timeout

Q: Are pods on the same node?
├── YES (same node):
│   ├── Check OVS: oc debug node/NODE -- chroot /host ovs-vsctl show
│   ├── Check NetworkPolicy: oc get networkpolicy -n my-namespace
│   └── Check pod is listening: oc exec pod-b -- ss -tlnp
│
└── NO (cross-node):
    ├── Check NSG allows UDP 6081 (most common issue!):
    │   → az network nsg rule list -g aro-rg --nsg-name aro-worker-nsg
    │   → Look for rule allowing UDP 6081 from VirtualNetwork
    ├── Check OVN pods: oc get pods -n openshift-ovn-kubernetes -o wide
    └── Check MTU: oc exec pod-a -- ip link show eth0 | grep mtu
        → Pod MTU should be ~1400 (Geneve adds overhead)
```

### 15.4 Pod Can't Reach On-Prem Database

```text
Symptom: oc exec db-client -- nc -zv 192.168.10.50 5432 → timeout

Q: Can the node reach on-prem?
├── Test: oc debug node/NODE -- chroot /host curl -s telnet://192.168.10.50:5432
│
├── NO (node can't reach on-prem):
│   ├── Check effective routes: az network nic show-effective-route-table ...
│   │   └── Route to 192.168.0.0/16 exists → VNet Gateway/ER?
│   │       Missing? → Add route or check ExpressRoute/VPN
│   ├── Check ExpressRoute: az network express-route show ...
│   │   └── Peering state != "Connected"? → Circuit issue
│   ├── Check on-prem firewall: allows src 10.0.1.0/24 dst 192.168.10.50:5432?
│   └── Check NSG outbound: allows TCP 5432 to on-prem?
│
└── YES (node reaches on-prem, pod doesn't):
    ├── Check OVN SNAT: oc debug node/NODE -- chroot /host ovn-nbctl lr-nat-list ovn_cluster_router
    ├── Check NetworkPolicy egress: allows 192.168.10.50:5432?
    └── Remember: pods appear as NODE IP (10.0.1.x) due to SNAT
```

### 15.5 Cluster API Unreachable

```text
Symptom: oc get pods → connection refused / timeout

For Private Clusters:
├── Are you connected to the VNet? (VPN/ExpressRoute/bastion)
│   └── NO → Cannot reach a private API from the internet
│
├── Check DNS: dig api.<cluster-domain>
│   └── Resolves to internal LB IP? → DNS is fine
│       Does NOT resolve? → Check Azure DNS Private Zone + VNet link
│
├── Check NSG on master subnet: allows TCP 6443?
│   └── Blocked? → Fix NSG
│
└── Check cluster status: az aro show -g aro-rg -n my-aro --query "provisioningState"
    └── Not "Succeeded"? → Contact support

For Public Clusters:
├── Check DNS: dig api.<cluster-domain>
│   └── Resolves to public LB IP? → DNS fine
│
├── Check connectivity: curl -sI https://api.<cluster-domain>:6443
│   └── Connection refused? → API server issue
│       Timeout? → Network issue (firewall, proxy)
│
└── Check cluster: az aro show -g aro-rg -n my-aro
    └── provisioningState = "Failed"? → Contact support
```

---

## Appendix A: Key Differences from ROSA HCP

| Feature | ARO | ROSA HCP |
|---------|-----|----------|
| Control plane | In YOUR VNet (3 master VMs) | In Red Hat's VPC (no master cost) |
| OVN DBs | On master nodes | In Red Hat's VPC |
| API Server → Kubelet | Same VNet (direct) | PrivateLink (cross-VPC) |
| Cloud firewall | NSG (subnet-level, stateful) | Security Groups (ENI-level, stateful) |
| Route tables | UDR + system routes | VPC route tables |
| Hybrid connectivity | ExpressRoute (Azure) | Direct Connect (AWS) |
| DNS resolver | 168.63.129.16 | VPC CIDR + 2 (e.g., 10.0.0.2) |
| NAT for egress | Azure LB SNAT / NAT Gateway / Firewall | NAT Gateway |
| L7 LB | Application Gateway / Front Door | ALB |
| L4 LB | Azure Load Balancer (Standard) | NLB |
| Azure ASN | 12076 | 64512 (AWS) |
| Managed by | Microsoft + Red Hat | Red Hat |

---

## Appendix B: Glossary Quick Reference

| Term | Layer | One-Line Definition |
|------|-------|-------------------|
| AccelNet | HW | Azure Accelerated Networking — SR-IOV for near-native NIC performance |
| AFD | L7 | Azure Front Door — global L7 load balancer with WAF and CDN |
| AppGW | L7 | Azure Application Gateway — regional L7 load balancer with WAF |
| ASN | BGP | Unique number identifying an autonomous system (network) |
| Azure FW | L3-L7 | Azure Firewall — managed cloud-native firewall with FQDN filtering |
| BGP | L3 | Routing protocol for exchanging routes between networks |
| br-int | OVS | OVN's integration bridge connecting all local pods |
| CIDR | L3 | Notation for IP ranges (e.g., 10.0.0.0/16) |
| ClusterIP | K8s | Virtual IP for a Kubernetes Service, exists only as DNAT rules |
| CNI | K8s | Standard interface between container runtime and network plugin |
| CoreDNS | K8s | DNS server inside the cluster resolving service names |
| CRI-O | K8s | Container runtime used by OpenShift |
| DNAT | L3 | Destination NAT — rewriting the destination IP of a packet |
| ER | Azure | ExpressRoute — dedicated private connection to Azure |
| eth0 | Linux | Primary network interface inside a Linux system |
| Geneve | L2.5 | Tunnel encapsulation protocol for overlay networks (UDP 6081) |
| HAProxy | L7 | The reverse proxy that powers the OpenShift router |
| kubelet | K8s | Agent on each node that manages pods |
| Mellanox VF | HW | Virtual Function from Mellanox ConnectX NIC (SR-IOV) |
| MTU | L2 | Maximum Transmission Unit — max packet size (usually 1500) |
| Multus | K8s | Meta-CNI for attaching multiple networks to a pod |
| NAT GW | Azure | NAT Gateway — dedicated outbound internet with static IP |
| NodePort | K8s | Port opened on every node for external Service access |
| NSG | Azure | Network Security Group — stateful subnet/NIC-level firewall |
| NVA | Azure | Network Virtual Appliance — third-party firewall as a VM |
| OVN | SDN | Open Virtual Network — virtual networking for OpenShift |
| OVS | SDN | Open vSwitch — virtual switch in the Linux kernel |
| PE | Azure | Private Endpoint — NIC with private IP connecting to PaaS |
| PL | Azure | Private Link — private connection that stays on Azure backbone |
| RHCOS | OS | Red Hat CoreOS — immutable OS for OpenShift nodes |
| Route | OCP | OpenShift object defining hostname → Service mapping |
| RP | Azure | ARO Resource Provider — manages cluster lifecycle |
| SE | Azure | Service Endpoint — optimized route to Azure PaaS services |
| SG | AWS | Security Group (AWS equivalent of NSG) |
| SNAT | L3 | Source NAT — rewriting the source IP of a packet |
| SR-IOV | HW | Hardware virtualization of network cards for near-native perf |
| TLS | L6 | Transport Layer Security — encrypts data in transit |
| UDR | Azure | User Defined Route — custom route in Azure route table |
| veth | Linux | Virtual ethernet pair — connects pod namespace to bridge |
| VNet | Azure | Virtual Network — your isolated network in Azure |
| VNet NIC | Azure | Virtual network interface attached to a VM |

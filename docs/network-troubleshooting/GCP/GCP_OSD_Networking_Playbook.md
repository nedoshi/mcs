# GCP OpenShift Dedicated (OSD) Networking Playbook

A complete guide to networking in OpenShift Dedicated on Google Cloud Platform. This document takes you from zero networking knowledge through packet-level understanding of every traffic flow.

---

## Table of Contents

1. [Introduction & How to Read This Document](#1-introduction--how-to-read-this-document)
2. [Networking Fundamentals](#2-networking-fundamentals)
3. [GCP Networking Fundamentals](#3-gcp-networking-fundamentals)
4. [Compute Engine Virtualization & Andromeda](#4-compute-engine-virtualization--andromeda)
5. [Kubernetes Networking Fundamentals](#5-kubernetes-networking-fundamentals)
6. [OpenShift Networking Layer](#6-openshift-networking-layer)
7. [OSD on GCP Architecture — The Complete Picture](#7-osd-on-gcp-architecture--the-complete-picture)
8. [How Apps Are Exposed in OSD on GCP](#8-how-apps-are-exposed-in-osd-on-gcp)
9. [IP Address Architecture](#9-ip-address-architecture)
10. [BGP and Hybrid Networking](#10-bgp-and-hybrid-networking)
11. [DNS Architecture in OSD on GCP](#11-dns-architecture-in-osd-on-gcp)
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
| **Intermediate** — knows TCP/IP, new to GCP/K8s | Section 3 | Understand how GCP and Kubernetes networking layers compose |
| **Advanced** — knows K8s, needs OSD on GCP depth | Section 7 | Packet-level understanding of every OSD on GCP traffic flow |

### Learning Path

```text
Section 2: Networking Fundamentals
    "What is a packet? What is an IP address?"
        |
        v
Section 3: GCP Networking Fundamentals
    "What is a VPC Network? What are Firewall Rules?"
        |
        v
Section 4: Compute Engine Virtualization & Andromeda
    "How does a physical server become a virtual machine in GCP?"
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
Section 7: OSD on GCP Architecture
    "How are master and worker nodes deployed?"
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
- **Command blocks** are copy-paste ready for OSD on GCP clusters
- Arrows in diagrams: `-->` means "packet travels to", `==>` means "encapsulated tunnel"

---

## 2. Networking Fundamentals

This section is for readers who are new to networking. If you already understand TCP/IP, subnets, and routing, skip to Section 3.

### 2.1 What Is a Network?

A network is a group of computers that can send data to each other. Your home Wi-Fi is a network. The internet is a network of networks.

Every device on a network needs two things:
1. **An address** — so other devices can find it (like a mailing address)
2. **A way to send data** — a physical or virtual connection (like a road)

> **WHY:** OSD on GCP runs your applications on Compute Engine virtual machines inside Google's data centers. These VMs need to talk to each other, to the OpenShift control plane, and to the internet. Understanding networking is understanding how that communication happens.

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
| **Public** | 35.201.100.5 | Everyone on the internet |
| **Private** | 10.0.1.42, 172.16.0.5, 192.168.1.1 | Only devices on the same private network |

**Private IP ranges (RFC 1918):**

| Range | Size | Common Use |
|-------|------|-----------|
| 10.0.0.0 – 10.255.255.255 | 16 million addresses | Cloud VPCs, large networks |
| 172.16.0.0 – 172.31.255.255 | 1 million addresses | Medium networks |
| 192.168.0.0 – 192.168.255.255 | 65,000 addresses | Home networks |

> **WHY:** OSD on GCP uses private IP addresses for everything inside the VPC — worker nodes, master nodes, pods, services. Public IPs are only assigned to load balancers that need to accept traffic from the internet. Understanding which IPs are private vs. public tells you what can be reached from where.

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

> **WHY:** OSD on GCP uses multiple CIDR ranges for different purposes. The node subnet might be 10.0.0.0/24, the pod network might be 10.128.0.0/14, and the service network might be 172.30.0.0/16. If these overlap, packets get misrouted and things break. Understanding CIDR tells you whether two ranges conflict.

### 2.4 The TCP/IP Stack

When your browser loads a web page, the data doesn't teleport. It passes through a stack of layers, each adding its own envelope (called a header) around the data. This is like putting a letter in an envelope, then putting that in a shipping package, then putting that in a mailbag.

```text
Layer 7 — Application    HTTP request: "GET /index.html"
    |                         |
    v                         v
Layer 4 — Transport       TCP header added: source port 54321, dest port 443
    |                         |
    v                         v
Layer 3 — Network         IP header added: source 10.0.1.42, dest 35.201.100.5
    |                         |
    v                         v
Layer 2 — Data Link       Ethernet header added: source MAC, dest MAC
    |                         |
    v                         v
Layer 1 — Physical        Electrical signals on the wire / radio waves
```

**Each layer does one job:**

**Layer 1 — Physical:** The actual cables, radio waves, or fiber optics that carry signals.

> **WHY:** In GCP, you never touch Layer 1. Google owns the physical hardware. But the performance of your network (bandwidth, latency) is determined by the physical infrastructure underneath — and Google's Jupiter network fabric is one of the fastest in the world.

**Layer 2 — Data Link:** Handles communication between devices on the same local network segment using MAC addresses (hardware addresses burned into every network card).

> **WHY:** Inside a GCP data center, Layer 2 is how the physical servers communicate on the same rack. OSD's overlay network (Geneve) creates a virtual Layer 2 on top of the physical Layer 3, so pods think they're on the same local network even when they're on different physical servers.

**Layer 3 — Network (IP):** Handles routing packets between different networks using IP addresses. This is where routing decisions happen — "which way should this packet go?"

> **WHY:** This is the most important layer for OSD on GCP. Every routing decision — pod to pod, pod to internet, pod to on-prem database — happens at Layer 3. Firewall rules, routes, Cloud NAT, and Cloud Router all operate at Layer 3.

**Layer 4 — Transport (TCP/UDP):** Handles reliable delivery (TCP) or fast delivery (UDP) between specific applications using port numbers. Port 443 = HTTPS, Port 80 = HTTP, Port 5432 = PostgreSQL.

> **WHY:** GCP firewall rules filter by port number, which is a Layer 4 concept. When you create a firewall rule allowing port 443, you're making a Layer 4 decision. Kubernetes Services map one port to another (e.g., external port 80 → pod port 8080), which is also Layer 4.

**Layer 7 — Application (HTTP, gRPC, DNS):** The actual application data — web pages, API calls, database queries.

> **WHY:** OpenShift Routes operate at Layer 7. The HAProxy router reads the HTTP Host header to decide which backend pod should receive the request. This is more intelligent than Layer 4 load balancing because it can route based on URLs, headers, and cookies. GCP's HTTP(S) Load Balancer also operates at Layer 7.

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

Total Maximum Size (MTU) = 1460 bytes for GCP default
    GCP supports MTU of 1500 or 8896 (jumbo frames)
```

> **WHY:** Every time a packet passes through an OSD on GCP component — a firewall rule, a Cloud NAT, a load balancer, an OVN router — the headers get inspected and possibly modified. Understanding packet structure is understanding what each component can see and change.

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

> **WHY:** VPC routes, Cloud Router learned routes, and the Linux routing table inside every pod all work this way. When troubleshooting "why can't pod A reach service B," the answer is almost always in a routing table somewhere. OSD on GCP has routing tables at the VPC level (GCP), the node level (Linux), and the overlay level (OVN).

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

> **WHY:** OSD on GCP uses DNS everywhere. Inside the cluster, CoreDNS resolves service names (my-service.my-namespace.svc.cluster.local) to ClusterIP addresses. Outside the cluster, Cloud DNS resolves *.apps.cluster.example.com to the load balancer's IP. Private OSD clusters use split-horizon DNS so the same name resolves differently depending on whether you're inside or outside the VPC.

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

> **WHY:** OSD on GCP uses both types. The GCP TCP/Network Load Balancer does L4 load balancing — it sees IP addresses and ports but not HTTP headers. The OpenShift router (HAProxy) does L7 load balancing — it reads the HTTP Host header to route requests to the correct application. These work together: GCP LB → HAProxy Router → Application Pod.

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

> **WHY:** OSD on GCP OpenShift Routes support all three TLS strategies. Edge termination is simplest — the router handles certificates. Passthrough is required when the application must control its own certificates (e.g., mutual TLS). Re-encrypt adds defense-in-depth — traffic is encrypted even inside the cluster network.

---

## 3. GCP Networking Fundamentals

This section explains every GCP networking component that OSD on GCP uses. Each component has a WHY block explaining its role.

### 3.1 VPC Network (Global)

A **VPC Network** in GCP is a global resource — unlike AWS where a VPC is regional, a GCP VPC spans all regions. It's logically isolated — no other GCP customer can see or access your VPC's resources unless you explicitly allow it.

```text
+---------------------------------------------------------------+
|              GCP Project: my-osd-project                       |
|                                                                |
|  +----------------------------------------------------------+ |
|  |              Your VPC Network (my-osd-vpc)                | |
|  |              GLOBAL — spans all regions                   | |
|  |                                                           | |
|  |  You control:                                             | |
|  |    - Subnets (regional, you pick the CIDR)                | |
|  |    - Firewall rules (VPC-level, priority-based)           | |
|  |    - Routes (system-generated + custom)                   | |
|  |    - Cloud NAT (regional, per-subnet)                     | |
|  |    - Private Google Access                                | |
|  |                                                           | |
|  |  Key difference from AWS:                                 | |
|  |    VPC itself has NO CIDR — subnets have CIDRs            | |
|  |    VPC is global, subnets are regional                    | |
|  +----------------------------------------------------------+ |
|                                                                |
|  +----------------------------------------------------------+ |
|  |         Someone Else's VPC Network                        | |
|  |         (completely isolated from yours)                  | |
|  +----------------------------------------------------------+ |
|                                                                |
+---------------------------------------------------------------+
```

> **WHY:** OSD on GCP deploys all cluster resources (master and worker nodes) inside a VPC Network you own (or one Red Hat manages on your behalf). The global nature of GCP VPCs means subnets in different regions can communicate without peering — but OSD clusters are deployed in a single region. The VPC provides network isolation, firewall boundaries, and routing control.

### 3.2 Subnets (Regional)

A **subnet** in GCP is a regional resource with a specific IP range. Unlike the VPC (which is global and has no CIDR), subnets carry the actual IP allocations.

GCP subnets support two special features for Kubernetes:
- **Primary IP range:** Used for node (VM) IPs
- **Secondary IP ranges:** Used for pod IPs and service IPs (alias IPs)

```text
+------------------------------------------------------------------+
|                    VPC Network: my-osd-vpc                        |
|                    (global — no CIDR on the VPC itself)           |
|                                                                   |
|  Region: us-central1                                              |
|  +--------------------------------------------------------------+ |
|  | Subnet: osd-node-subnet                                      | |
|  | Primary Range: 10.0.0.0/24 (node IPs)                        | |
|  |                                                               | |
|  | Secondary Ranges:                                             | |
|  |   "pods":     10.128.0.0/14 (pod IPs — alias IPs)            | |
|  |   "services": 172.30.0.0/16 (service IPs — alias IPs)        | |
|  |                                                               | |
|  | Zone: us-central1-a                                           | |
|  |   Master Node 1 (10.0.0.10)                                  | |
|  |   Worker Node 1 (10.0.0.20)                                  | |
|  |   Worker Node 2 (10.0.0.21)                                  | |
|  |                                                               | |
|  | Zone: us-central1-b                                           | |
|  |   Master Node 2 (10.0.0.11)                                  | |
|  |   Worker Node 3 (10.0.0.22)                                  | |
|  |   Worker Node 4 (10.0.0.23)                                  | |
|  |                                                               | |
|  | Zone: us-central1-c                                           | |
|  |   Master Node 3 (10.0.0.12)                                  | |
|  |   Worker Node 5 (10.0.0.24)                                  | |
|  +--------------------------------------------------------------+ |
|                                                                   |
|  Region: europe-west1                                             |
|  +--------------------------------------------------------------+ |
|  | (no OSD resources here — but same VPC can be used)            | |
|  +--------------------------------------------------------------+ |
+------------------------------------------------------------------+
```

> **WHY:** GCP's subnet model is different from AWS. In AWS, public and private subnets are defined by route table associations. In GCP, all subnets are "private" by default (no automatic public IPs), and you control internet access through Cloud NAT, external IPs, and firewall rules. OSD uses a single subnet for both master and worker nodes. The secondary ranges for pods and services allow GCP to be aware of pod IPs (via alias IPs), which improves routing efficiency and enables native VPC routing to pods.

### 3.3 Firewall Rules (VPC-Level, Priority-Based)

GCP **Firewall Rules** are applied at the VPC level and evaluated per-VM. They are fundamentally different from AWS Security Groups:

| Feature | GCP Firewall Rules | AWS Security Groups |
|---------|-------------------|-------------------|
| Scope | VPC-wide (all VMs) | Per-ENI (per instance) |
| Targeting | Network tags or service accounts | Attached to ENI |
| Priority | Numeric priority (0-65535, lowest wins) | All rules evaluated |
| Default | Implied deny-all ingress, allow-all egress | Deny-all ingress, allow-all egress |
| Stateful? | Yes | Yes |
| Allow/Deny | Both | Allow only |
| Direction | Separate ingress and egress rules | Separate |

```text
GCP Firewall Rule Evaluation:

Packet arrives at VM
    |
    v
Match against ALL firewall rules for this VPC
    |
    | Rules matched by:
    |   1. Direction (ingress or egress)
    |   2. Target (network tag, service account, or all instances)
    |   3. Source/Dest (IP range, tag, or service account)
    |   4. Protocol + port
    |
    | If multiple rules match:
    |   → Lowest priority number wins (0 = highest priority)
    |   → If same priority, DENY wins over ALLOW
    |
    v
Final verdict: ALLOW or DENY

Example rules for an OSD worker node (tag: osd-worker):

Priority  Direction  Action  Source/Dest         Proto  Ports       Target Tag
1000      ingress    allow   tag:osd-master      TCP    6443,10250  osd-worker
1000      ingress    allow   tag:osd-worker      UDP    6081        osd-worker
1000      ingress    allow   tag:osd-worker      TCP    9000-9999   osd-worker
2000      ingress    allow   health-check ranges  TCP    30000-32767 osd-worker
65535     ingress    deny    0.0.0.0/0           all    all         (implied)
```

> **WHY:** GCP firewall rules are the primary network firewall for OSD nodes. Unlike AWS where you attach a security group to an instance, in GCP you define rules at the VPC level and target them using **network tags** (labels applied to VMs). OSD applies tags like `osd-master` and `osd-worker` to its VMs. If you add a firewall rule with a target tag `osd-worker`, it applies to all current and future worker nodes automatically. The priority system lets you create catch-all deny rules at high priority numbers and specific allow rules at lower numbers.

### 3.4 Cloud Router

A **Cloud Router** is a fully distributed, software-defined router that provides dynamic routing using BGP. It connects your VPC to external networks (on-prem, other clouds) via Cloud VPN or Cloud Interconnect.

```text
+-------------------------+           +-------------------------+
| Your VPC                |           | On-Prem Network         |
|                         |           |                         |
| Cloud Router            |           | On-Prem Router          |
| (AS 65010)              |           | (AS 65020)              |
|                         |           |                         |
| Learns routes:          |<-- BGP -->| Advertises:             |
|   192.168.0.0/16        |  session  |   192.168.0.0/16        |
|                         |           |                         |
| Advertises:             |           | Learns routes:          |
|   10.0.0.0/24 (subnet)  |           |   10.0.0.0/24           |
+-------------------------+           +-------------------------+
```

Cloud Router is also required by Cloud NAT — it provides the control plane for NAT configuration.

> **WHY:** Cloud Router is essential for hybrid OSD deployments where pods need to reach on-prem databases or services. It dynamically exchanges routes via BGP, so when on-prem networks change, the VPC routing table updates automatically. Cloud Router also manages Cloud NAT — without a Cloud Router, you can't configure Cloud NAT for outbound internet access.

### 3.5 Cloud NAT

**Cloud NAT** provides outbound internet access for VMs without external IP addresses. It's a managed, regional resource that runs on GCP's Andromeda SDN (not as a VM or appliance).

```text
Pod (10.128.0.15) sends request to pypi.org:
                                                              Internet
                                                                 ^
Step 1: Pod → Node                                               |
  src: 10.128.0.15:54321                                    +--------+
  dst: 151.101.0.223:443                                    | Cloud  |
         |                                                  | NAT    |
         v                                                  | (EIP:  |
Step 2: OVN SNATs pod IP to node IP                         | 35.x.y)|
  src: 10.0.0.20:54321    (node's private IP)               +--------+
  dst: 151.101.0.223:443                                         ^
         |                                                       |
         v                                                       |
Step 3: Cloud NAT SNATs node IP to external IP              +--------+
  src: 35.x.y.z:12345     (Cloud NAT's external IP)        | Subnet |
  dst: 151.101.0.223:443                                    | Worker:|
         |                                                  | 10.0.  |
         +--- goes to internet                              | 0.20   |
                                                            +--------+
```

Key differences from AWS NAT Gateway:
- Cloud NAT is **software-defined** (runs on Andromeda) — there's no NAT "instance" or ENI
- Cloud NAT scales automatically — no per-AZ deployment needed
- You can assign **automatic or manual** external IPs
- Cloud NAT requires a Cloud Router (for configuration, not for BGP)

> **WHY:** OSD worker nodes do not have external IP addresses. Pods need to pull container images from registries (quay.io, gcr.io), download dependencies, and call external APIs. Cloud NAT provides this outbound internet access while keeping worker nodes unreachable from the internet. Cloud NAT can also be configured to NAT traffic only for specific subnets or IP ranges, giving fine-grained control over which traffic gets NATed.

### 3.6 Cloud Load Balancing

GCP offers multiple load balancer types. OSD on GCP primarily uses two:

```text
GCP Load Balancer Types:

+----------------------------------------------------------------------+
| Type           | Layer | Scope    | Use in OSD                       |
|----------------|-------|----------|----------------------------------|
| External TCP/  | L4    | Regional | Default ingress — external NLB   |
|  Network LB    |       |          | for OpenShift router pods        |
|                |       |          |                                  |
| Internal TCP   | L4    | Regional | Private ingress — internal LB    |
|  Network LB    |       |          | for private clusters             |
|                |       |          |                                  |
| External       | L7    | Global   | Optional — for WAF, URL-based    |
|  HTTP(S) LB    |       |          | routing, CDN integration         |
|                |       |          |                                  |
| Internal       | L7    | Regional | Optional — for internal L7       |
|  HTTP(S) LB    |       |          | routing                          |
+----------------------------------------------------------------------+
```

```text
GCP External TCP Load Balancer (default OSD ingress):

Internet Client
    |
    v
Anycast VIP: 35.201.100.5 (same IP from anywhere in the world)
    |
    | GCP's global network routes to nearest POP
    | then to the regional backend
    |
    v
+--------------------+
| TCP Network LB     |
| (regional)         |
|                    |
| Health checks:     |
| TCP to NodePort    |
| on each worker     |
|                    |
| Backend: instance  |
| group (workers)    |
+--------+-----------+
         |
         | Forwards to worker node IP:NodePort
         |
         v
    Worker Node (10.0.0.20:30443)
         |
         v
    Router Pod (HAProxy)
```

**GCP-specific: Anycast VIPs**

Unlike AWS NLBs that have per-AZ IPs, GCP external load balancers use **Anycast** — the same IP address is advertised from every Google Point of Presence worldwide. Users automatically connect to the nearest one.

> **WHY:** The TCP Network Load Balancer is the primary entry point for external traffic to OSD on GCP. It uses Anycast VIPs, meaning a single IP address works globally — users in Tokyo and London connect to the same IP but are routed to the nearest Google edge. This means fewer DNS records to manage and built-in geographic performance optimization. For private clusters, the Internal TCP LB provides the same function but only within the VPC or connected networks.

### 3.7 Cloud DNS

**Cloud DNS** is Google's managed authoritative DNS service. It provides both public and private DNS zones.

```text
Cloud DNS Zone Types:

Public Zone:
  example.com → visible to the entire internet
  *.apps.osd-cluster.example.com → resolves to LB external IP

Private Zone:
  internal.example.com → visible only within associated VPCs
  *.apps.osd-cluster.internal.com → resolves to internal LB IP
```

> **WHY:** OSD on GCP uses Cloud DNS for the `*.apps` wildcard record that routes all application traffic to the ingress load balancer. For private clusters, Cloud DNS private zones provide split-horizon DNS — the same hostname resolves to different IPs depending on whether the query comes from inside or outside the VPC.

### 3.8 Cloud Interconnect

**Cloud Interconnect** provides a dedicated physical connection between your on-premises network and Google's network. It's the GCP equivalent of AWS Direct Connect.

| Type | Bandwidth | Connection |
|------|----------|-----------|
| **Dedicated Interconnect** | 10 Gbps or 100 Gbps | Physical cross-connect at a Google colocation facility |
| **Partner Interconnect** | 50 Mbps – 50 Gbps | Through a supported service provider |

```text
+------------------+    Dedicated Link    +------------------+
| On-Prem Data     |----(10/100 Gbps)----| Google Edge       |
| Center           |                      | (colocation)     |
|                  |                      |                  |
| Your Router      |<---- BGP session --->| Cloud Router     |
| AS 65020         |                      | AS 65010         |
+------------------+                      +------------------+
                                                  |
                                                  v
                                          +------------------+
                                          | Your VPC         |
                                          | OSD Cluster      |
                                          +------------------+
```

> **WHY:** Cloud Interconnect provides low-latency, high-bandwidth, private connectivity between your data center and the OSD cluster. This is critical for hybrid workloads where pods need to access on-prem databases or where large data transfers (backups, CI/CD artifacts) need to happen without traversing the public internet. Dedicated Interconnect provides the lowest latency and highest bandwidth, while Partner Interconnect is more accessible for organizations without a colocation presence.

### 3.9 Cloud VPN

**Cloud VPN** creates encrypted tunnels between your VPC and external networks over the public internet.

| Type | Tunnels | SLA | Use Case |
|------|---------|-----|---------|
| **HA VPN** | 2 tunnels per gateway, 99.99% SLA | Active-active | Production hybrid connectivity |
| **Classic VPN** | 1 tunnel per gateway, 99.9% SLA | Active-passive | Dev/test, lower cost |

```text
HA VPN Topology:

Your VPC                           On-Prem
+------------------+               +------------------+
| HA VPN Gateway   |               | VPN Peer Gateway |
|                  |               |                  |
| Interface 0 -----+--- Tunnel 0 --+----- Interface 0 |
| (35.x.x.1)      |    (IPsec)    |    (203.0.113.1) |
|                  |               |                  |
| Interface 1 -----+--- Tunnel 1 --+----- Interface 1 |
| (35.x.x.2)      |    (IPsec)    |    (203.0.113.2) |
|                  |               |                  |
| Cloud Router     |<--- BGP ---->| On-Prem Router   |
| (AS 65010)       |  (over both  | (AS 65020)       |
|                  |   tunnels)   |                  |
+------------------+               +------------------+
```

> **WHY:** Cloud VPN is the most common way to connect OSD on GCP to on-premises networks for hybrid workloads. HA VPN provides 99.99% SLA with active-active tunnels and automatic failover. It uses BGP (via Cloud Router) to dynamically exchange routes, so when you add a new subnet on-prem, it's automatically available to OSD pods.

### 3.10 Private Google Access

**Private Google Access** allows VMs without external IP addresses to reach Google APIs and services (like Cloud Storage, Container Registry, BigQuery) using internal IP addresses.

```text
Without Private Google Access:        With Private Google Access:

Pod → Node → Cloud NAT →              Pod → Node → VPC routing →
Internet → storage.googleapis.com      restricted.googleapis.com
                                       (resolves to 199.36.153.4/30
                                        or a Private Service Connect
                                        endpoint in your VPC)

Cost: NAT processing fees             Cost: Free (no NAT involved)
Path: Traverses internet               Path: Stays on Google's backbone
```

> **WHY:** OSD on GCP worker nodes pull container images from Container Registry (gcr.io) or Artifact Registry, and interact with GCP APIs (Compute Engine, IAM, Cloud DNS). Without Private Google Access, all this traffic would go through Cloud NAT and the public internet, incurring cost and latency. With it enabled, traffic to Google APIs goes directly over Google's backbone network — faster, cheaper, and more secure. For fully private clusters, Private Google Access is mandatory.

### 3.11 VPC Peering

**VPC Network Peering** connects two VPC networks so resources in each can communicate using internal IP addresses.

```text
+-------------------+         +-------------------+
| VPC: osd-cluster  |         | VPC: shared-svcs  |
| 10.0.0.0/24       |         | 10.1.0.0/24       |
|                   |<--peer->|                   |
| OSD worker nodes  |         | Shared DB, cache  |
| 10.0.0.20         |         | 10.1.0.50 (Redis) |
+-------------------+         +-------------------+

Routes are automatically exchanged.
No transitive routing (A↔B, B↔C does NOT mean A↔C).
```

> **WHY:** VPC Peering is used when your OSD cluster needs to access shared services (databases, caches, message queues) running in a separate VPC. OSD on GCP may use VPC Peering between the cluster VPC and a Red Hat managed VPC for certain managed service configurations. VPC Peering does not support transitive routing — if VPC A peers with VPC B and B peers with C, A cannot reach C through B.

### 3.12 Shared VPC

**Shared VPC** allows an organization to share a VPC across multiple projects. A host project owns the VPC, and service projects use its subnets.

```text
+---------------------------------------------------------------+
| Organization                                                   |
|                                                                |
| Host Project (owns VPC)                                        |
| +------------------------------------------------------------+|
| | Shared VPC Network                                         ||
| | Subnet A: 10.0.0.0/24 (for OSD)                           ||
| | Subnet B: 10.1.0.0/24 (for other workloads)               ||
| | Firewall rules, Cloud NAT, Cloud Router                    ||
| +------------------------------------------------------------+|
|                                                                |
| Service Project 1 (OSD cluster)     Service Project 2 (other) |
| +---------------------------+       +-------------------------+|
| | Uses Subnet A             |       | Uses Subnet B           ||
| | OSD master + worker VMs   |       | Other workloads         ||
| +---------------------------+       +-------------------------+|
+---------------------------------------------------------------+
```

> **WHY:** Shared VPC centralizes network management. The networking team manages firewall rules, routes, and NAT in the host project, while the OSD cluster runs in a service project with access to the shared subnets. This is common in enterprises where network governance requires centralized control. OSD supports deploying into a Shared VPC.

### 3.13 Private Service Connect

**Private Service Connect** is GCP's equivalent of AWS PrivateLink. It creates private endpoints for Google services or your own services, accessible via internal IP addresses.

```text
+----------------------------+       +----------------------------+
| Producer VPC               |       | Consumer VPC (OSD)         |
| (e.g., a managed DB)      |       |                            |
|                            |       |                            |
| Service Attachment          |       | PSC Endpoint              |
| (backed by ILB)            |       | (internal IP: 10.0.0.100) |
|         |                  |       |         |                  |
|         +------ PSC -------+-------+         |                  |
|                            |       |         v                  |
| DB instance                |       | Pod connects to            |
| (10.5.0.50)                |       | 10.0.0.100:5432            |
+----------------------------+       +----------------------------+
```

> **WHY:** Private Service Connect lets OSD pods access services in other VPCs (or Google-managed services) through a private internal IP, without VPC Peering, public internet, or NAT. It's unidirectional (consumer initiates), so the producer can't probe your VPC. This is used for accessing managed databases (Cloud SQL), third-party SaaS services, or any service published via a Service Attachment.

### 3.14 Network Tags and Service Account-Based Firewall Rules

GCP firewall rules can target VMs using two mechanisms:

**Network Tags** — labels applied to VM instances:

```text
VM: osd-worker-1
  Tags: ["osd-worker", "my-cluster"]

Firewall Rule:
  Target: tag "osd-worker"
  → Applies to osd-worker-1 (and any future VM with this tag)
```

**Service Accounts** — identity-based targeting:

```text
VM: osd-worker-1
  Service Account: osd-worker@my-project.iam.gserviceaccount.com

Firewall Rule:
  Target: service account "osd-worker@my-project.iam..."
  → Applies to any VM running as this service account
```

| Targeting Method | Advantages | Disadvantages |
|-----------------|-----------|--------------|
| **Network Tags** | Simple, visible in console | Tags are user-controlled — any project member with compute.instances.setTags can change them |
| **Service Accounts** | IAM-controlled (harder to tamper with) | Less visible, requires IAM understanding |

> **WHY:** OSD on GCP uses network tags to identify master and worker nodes for firewall rules. Tags like `osd-<cluster-id>-master` and `osd-<cluster-id>-worker` are applied during provisioning. This means firewall rules automatically apply to new nodes when the cluster scales up. Service account-based rules are more secure (can't be bypassed by adding a tag) and are recommended for production environments where you want tighter control.

---

## 4. Compute Engine Virtualization & Andromeda

This section explains how GCP turns physical hardware into the virtual machines that run OSD nodes. Understanding this layer helps you reason about network performance and how packets actually move.

### 4.1 GCP's Hypervisor (KVM-Based)

GCP uses a custom, security-hardened **KVM-based hypervisor** to create virtual machines. Unlike AWS (which uses the custom Nitro hardware), GCP's virtualization is primarily software-based with hardware acceleration via SR-IOV.

```text
Physical Server in Google Data Center:
+------------------------------------------------------------------+
|                                                                    |
|  +---------------------------+   +----------------------------+   |
|  | Host CPU (Intel/AMD)      |   | Physical NIC               |   |
|  |                           |   | (connected to Jupiter      |   |
|  | Runs GCP hypervisor (KVM) |   |  network fabric)           |   |
|  |                           |   |                            |   |
|  | Guest VMs (instances):    |   | Handles:                   |   |
|  |   VM 1 (osd-master-1)    |   |  - Network I/O             |   |
|  |   VM 2 (osd-worker-1)    |   |  - Andromeda SDN forwarding |   |
|  |   VM 3 (other tenant)    |   |  - Firewall rule evaluation |   |
|  +---------------------------+   +----------------------------+   |
|                                                                    |
|  +---------------------------+   +----------------------------+   |
|  | Physical Memory (RAM)     |   | Persistent Disk Controller |   |
|  | Divided among VMs         |   | (networked storage)        |   |
|  +---------------------------+   +----------------------------+   |
|                                                                    |
+------------------------------------------------------------------+
```

> **WHY:** OSD worker and master nodes are Compute Engine VMs running on this hypervisor. The hypervisor provides isolation between tenants (your VMs can't see other customers' VMs) and manages resource allocation. GCP's hypervisor enforces firewall rules before packets reach the VM, similar to AWS Nitro.

### 4.2 Andromeda — GCP's Software-Defined Networking

**Andromeda** is Google's Software-Defined Networking (SDN) platform. It handles all VPC networking — packet forwarding, firewall rules, load balancing, and Cloud NAT — in software running on the physical hosts.

```text
Andromeda Architecture:

+--------------------+     +--------------------+
| Physical Host A    |     | Physical Host B    |
|                    |     |                    |
| +--------+         |     | +--------+         |
| | VM 1   |         |     | | VM 3   |         |
| | eth0   |         |     | | eth0   |         |
| +---+----+         |     | +---+----+         |
|     |               |     |     |               |
| +---v--------------+|     | +---v--------------+|
| | Andromeda         ||     | | Andromeda         ||
| | (on-host agent)   ||     | | (on-host agent)   ||
| |                   ||     | |                   ||
| | - Firewall eval   ||     | | - Firewall eval   ||
| | - NAT (Cloud NAT) ||     | | - Packet delivery  ||
| | - Encapsulation   ||     | | - Decapsulation   ||
| | - Load balancing  ||     | | - Route lookup     ||
| +---+---------------+|     | +---+---------------+|
|     |                |     |     |                |
+-----+----------------+     +-----+----------------+
      |                             |
      +--- Jupiter Network Fabric --+
           (spine-leaf, petabit)
```

Key characteristics:
- Andromeda runs on **every physical host** (distributed control plane)
- Firewall rules are evaluated **before** packets reach the VM
- Cloud NAT runs **inside Andromeda** (not as a separate VM or appliance)
- Andromeda handles encapsulation for VPC traffic between hosts

> **WHY:** Andromeda is why GCP networking "just works" — Cloud NAT doesn't need a separate instance per zone (unlike AWS NAT Gateway), firewall rules have near-zero performance cost (evaluated in the SDN layer), and load balancing is distributed across all hosts. For OSD, this means Cloud NAT scales automatically, firewall rules don't bottleneck network throughput, and cross-zone traffic within a region is handled efficiently.

### 4.3 Virtio-Net and gVNIC

Inside a Compute Engine VM, the network interface (eth0) is backed by one of two virtual NIC technologies:

**Virtio-Net** — the default paravirtualized NIC:

```text
VM → virtio-net driver → KVM hypervisor → Andromeda → Physical NIC
```

**gVNIC (Google Virtual NIC)** — Google's custom virtual NIC for higher performance:

```text
VM → gVNIC driver → Direct path to Andromeda → Physical NIC
                     (bypasses some hypervisor overhead)
```

| Feature | Virtio-Net | gVNIC |
|---------|-----------|-------|
| Max bandwidth | Up to 32 Gbps | Up to 100 Gbps |
| Jumbo frames | 1460 MTU default | 8896 MTU supported |
| Required for | All instance types | C3, H3, and Tier_1 networking |
| Performance | Good | Better (lower latency, higher PPS) |

> **WHY:** OSD worker nodes use one of these virtual NIC types (typically Virtio-Net for n2-standard instances). The virtual NIC is what appears as `eth0` inside the VM's Linux OS. Understanding the NIC type helps when troubleshooting performance — if you need higher throughput, switching to an instance type with gVNIC support may help. MTU settings must also match: if gVNIC is set to jumbo frames (8896) but OVN is set to 1400, packets won't be fragmented efficiently.

### 4.4 VPC NIC to eth0 Mapping

From the outside (GCP), you see a network interface attached to a VM. From the inside (Linux), you see eth0. They're the same thing:

```text
GCP Perspective:                    Linux Perspective (inside VM):
+-----------------+                 +-------------------+
| Network Interface|                | $ ip addr show    |
| nic0             |                | eth0:             |
| IP: 10.0.0.20   | <==============>|   10.0.0.20/24    |
| Network: my-vpc |                |                   |
| Subnet: us-c1   |                | $ ip route show   |
| Tags: osd-worker|                | default via       |
+-----------------+                 |   10.0.0.1 eth0   |
                                    +-------------------+
```

GCP VMs can have up to 8 network interfaces (each in a different VPC). The primary interface is always `nic0` / `eth0`.

> **WHY:** Every OSD node has a primary network interface (nic0/eth0) with a private IP from the subnet. This is the interface through which all node-level traffic flows — kubelet communication, Geneve tunnels, Cloud NAT egress. The interface's IP determines which subnet the node is in, which firewall rules apply (via network tags), and where Cloud NAT is configured. Alias IPs (for pods) are also associated with this interface.

### 4.5 Packet Flow: Physical NIC to Pod

Here is the complete path a packet takes from the GCP physical network to a pod running in OSD:

```text
INBOUND PACKET (from internet to pod):

+-------------+     +------------------+     +------------------+
| Jupiter     | --> | Andromeda SDN    | --> | Virtual NIC      |
| Network     |     | (on-host agent)  |     | (nic0 / eth0)    |
| Fabric      |     |                  |     |                  |
|             |     | 1. Receives      |     | 2. Firewall rule |
| (spine-leaf |     |    packet from   |     |    evaluation    |
|  switches)  |     |    fabric        |     |    (stateful)    |
+-------------+     +------------------+     +------------------+
                                                      |
                                              +-------v--------+
                                              | eth0           |
                                              | (virtio/gVNIC) |
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

1. **Jupiter fabric**: Packet arrives at the physical NIC on the GCP server via Google's Jupiter network fabric (petabit-scale spine-leaf topology)
2. **Andromeda SDN**: Evaluates firewall rules in the SDN layer. If the packet is denied, it's dropped here — the VM CPU never sees it
3. **Virtual NIC (eth0)**: The packet appears on the Linux network interface eth0 inside the VM
4. **Linux kernel routing**: The kernel's routing table determines where the packet goes next. For pod-bound traffic, it goes to the OVN bridge (br-int)
5. **OVN bridge (br-int)**: OVN's OpenFlow rules match the destination IP to a specific pod and forward the packet to the correct veth pair
6. **Pod**: The packet arrives on the pod's eth0 interface (which is one end of a veth pair; the other end is on br-int)

> **WHY:** This is the complete chain that determines latency, throughput, and where security filtering happens. If a packet is blocked, understanding this chain tells you where to look: firewall rule in Andromeda? Linux iptables rules? OVN flow rules? Network Policy enforcement in OVN? Each layer can be independently diagnosed.

---

## 5. Kubernetes Networking Fundamentals

Kubernetes has a specific networking model with guarantees that every network implementation must satisfy. This section explains that model and how it maps to OSD on GCP.

### 5.1 The Pod Networking Model

Kubernetes makes three fundamental guarantees about networking:

1. **Every pod gets its own IP address** — pods don't share IPs with other pods
2. **Pods can communicate with any other pod without NAT** — a pod's IP is routable to all other pods
3. **Agents on a node (kubelet, node-exporter) can communicate with all pods on that node**

```text
Node 1 (10.0.0.20)                    Node 2 (10.0.0.21)
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

> **WHY:** This flat networking model simplifies application development — applications don't need to know whether they're talking to a pod on the same node or a different node. It also makes NetworkPolicies possible, because every pod has a unique identity (its IP). OSD on GCP uses OVN-Kubernetes as the CNI plugin to implement this model using Geneve tunnels between nodes.

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
| **LoadBalancer** | Creates a GCP LB that points to NodePorts | The internet (or VPC, if internal) |

> **WHY:** Services are how OSD applications find each other. Instead of hard-coding pod IPs (which change constantly), applications connect to service names (which resolve to ClusterIPs via DNS). When a Deployment scales from 3 to 10 pods, the Service automatically includes the new pods. The OpenShift router itself runs behind a LoadBalancer-type Service — that's how external traffic enters the cluster.

### 5.3 Ingress and Ingress Controllers

**Ingress** is a Kubernetes API object that defines rules for routing external HTTP/HTTPS traffic to Services inside the cluster. An **Ingress Controller** is the component that reads Ingress objects and actually implements the routing.

```text
Ingress Object (YAML):                    What happens:

apiVersion: networking.k8s.io/v1
kind: Ingress                             Client: "GET /api HTTP/1.1"
spec:                                     Host: api.example.com
  rules:                                        |
  - host: api.example.com                       v
    http:                                 Ingress Controller
      paths:                              (reads Ingress object)
      - path: /api                              |
        backend:                                v
          service:                        Routes to: api-service:8080
            name: api-service                   |
            port:                               v
              number: 8080                api-service ClusterIP
                                                |
                                                v
                                          Pod running API
```

> **WHY:** In OSD on GCP, OpenShift **Routes** serve the same purpose as Ingress objects (and are actually older — Routes predate Kubernetes Ingress). The default Ingress Controller is the OpenShift Router (HAProxy). When you create a Route, the router configures HAProxy to accept traffic for that hostname and forward it to the correct Service. External traffic reaches the router because the router runs behind a GCP Load Balancer (LoadBalancer Service). OSD also supports Kubernetes Ingress objects — they're translated to Routes internally.

### 5.4 Network Policies

A **NetworkPolicy** is a Kubernetes API object that controls which pods can talk to which other pods. By default, all pods can communicate with all other pods (the flat network). NetworkPolicies add firewall rules.

```text
Default (no policies):           With default-deny policy:

Pod A <---> Pod B                Pod A --X--> Pod B (blocked!)
Pod A <---> Pod C                Pod A --X--> Pod C (blocked!)
Pod B <---> Pod C                Pod B --X--> Pod C (blocked!)

  All pods can talk to all.        Nothing can talk to anything.

With selective allow:

Pod A ----> Pod B (allowed by policy)
Pod A --X-> Pod C (blocked by default deny)
```

```yaml
# Default deny all traffic in a namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: my-app
spec:
  podSelector: {}      # applies to all pods in namespace
  policyTypes:
  - Ingress
  - Egress
  # no ingress or egress rules = deny all
```

> **WHY:** NetworkPolicies implement zero-trust networking inside the cluster. Without them, any compromised pod can talk to every other pod — including pods in other namespaces running different applications. In OSD on GCP, OVN-Kubernetes enforces NetworkPolicies in the OVN logical flows, which means enforcement happens at the virtual switch level, not iptables. This is efficient and scales to thousands of rules.

### 5.5 CNI (Container Network Interface)

**CNI** is a standard that defines how container runtimes (CRI-O in OSD) set up networking for pods. The CNI plugin is the actual implementation that creates network interfaces, assigns IPs, and sets up routing.

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

> **WHY:** OSD on GCP uses OVN-Kubernetes as its CNI plugin. This is not optional and cannot be changed. OVN-Kubernetes was chosen because it integrates tightly with OpenShift's networking features (Routes, EgressIPs, multicast) and provides hardware-accelerated flow processing via Open vSwitch (OVS).

### 5.6 kube-proxy, iptables, and OVN Load Balancing

In standard Kubernetes, **kube-proxy** runs on every node and programs iptables rules to implement Service load balancing. In OSD on GCP with OVN-Kubernetes, kube-proxy is replaced by OVN's native load balancing.

```text
Standard Kubernetes (iptables):          OSD on GCP (OVN):

Client pod                              Client pod
    |                                        |
    v                                        v
iptables/nftables rules                  OVN logical flow rules
(programmed by kube-proxy)               (programmed by OVN controller)
    |                                        |
    v                                        v
DNAT: 172.30.45.67 → 10.128.0.15       DNAT: 172.30.45.67 → 10.128.0.15
(Service IP → Pod IP)                   (Service IP → Pod IP)
    |                                        |
    v                                        v
Packet forwarded to pod                  Packet forwarded to pod
```

In both cases, the Service ClusterIP (172.30.45.67) is never assigned to any real interface — it exists only as a DNAT rule. When a packet is sent to 172.30.45.67, it's intercepted and rewritten to a real pod IP before being delivered.

> **WHY:** OSD on GCP uses OVN for Service load balancing instead of kube-proxy/iptables because OVN handles it in the OVS datapath (kernel module), which is faster than iptables rule chains. At scale (thousands of Services), iptables performance degrades because rules are evaluated linearly. OVN uses flow tables with O(1) lookup time, maintaining performance regardless of the number of Services.

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

```text
Pod DNS Resolution Flow:

Pod sends DNS query for "my-api.production.svc.cluster.local"
    |
    v
CoreDNS pod (10.128.x.x, exposed via Service 172.30.0.10:53)
    |
    | Looks up in Kubernetes API:
    |   "Is there a Service named my-api in namespace production?"
    |   Yes → ClusterIP is 172.30.45.67
    |
    v
Response: A record → 172.30.45.67
```

For external names (google.com), CoreDNS forwards the query to upstream DNS servers. In GCP, the upstream is the metadata server at 169.254.169.254, which forwards to Cloud DNS or Google's public DNS.

> **WHY:** Without CoreDNS, pods would need to know the ClusterIP of every Service they connect to. CoreDNS lets pods use human-readable names. This is essential for OSD because pods constantly discover and communicate with other services — the API server, the OAuth server, the image registry, monitoring endpoints, and your own application services.

---

## 6. OpenShift Networking Layer

OpenShift builds on Kubernetes networking with additional components. This section explains what OpenShift adds and how it works in OSD on GCP.

### 6.1 OVN-Kubernetes Architecture

**OVN (Open Virtual Network)** is a virtual networking system built on top of **OVS (Open vSwitch)**. OVN-Kubernetes is the CNI plugin that integrates OVN with Kubernetes.

```text
Architecture Overview:

Control Plane Nodes (master VMs in your VPC):
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

Worker Nodes (worker VMs in your VPC):
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

> **WHY:** OVN provides a single virtual network that spans all nodes (master and worker). Without it, pods on different nodes couldn't communicate — they'd be isolated in their own node's network namespace. OVN creates a virtual overlay network (using Geneve tunnels) that makes all pods appear to be on the same flat network, regardless of which physical VM they're running on.

### 6.2 Geneve Tunneling

**Geneve (Generic Network Virtualization Encapsulation)** is a tunneling protocol that wraps a pod-to-pod packet inside a regular node-to-node UDP packet. This lets pod traffic traverse the VPC network, which only knows about node IPs.

```text
Pod A (10.128.0.15 on Node 1) sends to Pod C (10.128.2.33 on Node 2):

ORIGINAL PACKET (what Pod A sends):
+-----------------------------------------------+
| Src IP: 10.128.0.15  |  Dst IP: 10.128.2.33  |
| Src Port: 54321       |  Dst Port: 8080       |
| Data: "GET /api"                              |
+-----------------------------------------------+

ENCAPSULATED PACKET (what actually goes on the VPC network):
+------------------------------------------------------------------+
| OUTER Ethernet | OUTER IP Header    | OUTER UDP   | Geneve Header|
| Dst MAC: Node2 | Src: 10.0.0.20     | Src: random | VNI (network |
| Src MAC: Node1 | Dst: 10.0.0.21     | Dst: 6081   | identifier)  |
+-----------------+--------------------+-------------+--------------+
| INNER Packet (original, unchanged):                               |
| Src IP: 10.128.0.15  |  Dst IP: 10.128.2.33                     |
| Data: "GET /api"                                                  |
+------------------------------------------------------------------+

The VPC only sees: 10.0.0.20 → 10.0.0.21 (node-to-node UDP on port 6081)
The VPC doesn't know about pod IPs at all.
```

Step by step:

1. Pod A sends a packet to 10.128.2.33
2. OVN on Node 1 looks up 10.128.2.33 in the Southbound DB and finds it's on Node 2 (10.0.0.21)
3. OVS encapsulates the original packet in a Geneve tunnel:
   - Outer source IP = Node 1's IP (10.0.0.20)
   - Outer destination IP = Node 2's IP (10.0.0.21)
   - Outer destination port = UDP 6081 (Geneve)
4. The encapsulated packet traverses the VPC network as a normal node-to-node UDP packet
5. Node 2's OVS receives the packet on port 6081, strips the Geneve header
6. The original packet is delivered to Pod C's veth interface

> **WHY:** VPC networking only knows about node IPs (10.0.0.x). Pod IPs (10.128.x.x) exist in the overlay network. Geneve tunneling bridges this gap. Firewall rules must allow UDP port 6081 between worker nodes or cross-node pod communication will break completely.

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
- **Cluster Router**: Connects all logical switches. Routes traffic between pods on different nodes. Also handles SNAT for external traffic and DNAT for Services.

> **WHY:** This logical topology is how OVN decides which tunnel to use for each packet. When Pod A (on Node 1's switch) sends to Pod C (on Node 2's switch), the Cluster Router routes the packet from Node 1's switch to Node 2's switch, and OVN translates that to a Geneve tunnel between the physical nodes.

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

> **WHY:** This allocation scheme means OVN can determine which node hosts a pod just by looking at its IP address. 10.128.2.x is always on Node 2. This makes routing efficient — one entry per node instead of one entry per pod. Each node assigns IPs locally without a central IPAM server.

### 6.5 OpenShift Routes vs. Kubernetes Ingress

| Feature | OpenShift Route | Kubernetes Ingress |
|---------|----------------|-------------------|
| TLS Termination | Edge, Passthrough, Re-encrypt | Depends on Ingress Controller |
| Wildcard routes | Supported | Depends on controller |
| Route weights | Supported (for blue-green/canary) | Not standard |
| Implementation | HAProxy-based router | Varies by controller |
| OSD on GCP support | Native, default | Supported (translated to Routes) |

> **WHY:** Routes are the primary way applications are exposed in OSD on GCP. The OpenShift router (HAProxy) reads Route objects, configures TLS termination, and routes traffic to backend Services. The `*.apps` wildcard DNS record is pre-configured to point to the router's load balancer.

### 6.6 The OpenShift Router (HAProxy)

The OpenShift Router is a set of HAProxy pods running in the `openshift-ingress` namespace:

```text
External Traffic Flow Through the Router:

Internet Client
    |
    v
GCP TCP Network Load Balancer
    |  Target: Node IPs on NodePort 30080/30443
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

> **WHY:** The router is the single entry point for all HTTP/HTTPS application traffic in OSD. Without it, external users cannot reach your applications. It's where TLS certificates are applied, where hostname-based routing happens, and where connection limits and timeouts are enforced.

### 6.7 Multus CNI

**Multus** is a "meta-CNI" that allows pods to have multiple network interfaces. The primary interface (eth0) is always managed by OVN-Kubernetes. Multus can add additional interfaces.

> **WHY:** Multus is used in OSD on GCP for specialized networking requirements — most commonly with OpenShift Virtualization (KubeVirt), where VMs need multiple network interfaces for data-plane and control-plane separation.

---

## 7. OSD on GCP Architecture — The Complete Picture

This section brings everything together to explain how OSD on GCP's architecture works at a network level.

### 7.1 What Makes OSD on GCP Different

| Feature | Self-Managed OpenShift | OSD on GCP |
|---------|----------------------|-----------|
| **Control plane** | You manage master nodes | Red Hat manages master nodes |
| **Worker nodes** | You manage | You manage (scaling, machine sets) |
| **Master node location** | Your VPC | Your VPC (or Red Hat managed project) |
| **API server access** | You configure | Public or private endpoint |
| **Cluster provisioning** | Manual or IPI | Red Hat SRE automated |
| **Networking (CNI)** | Choice of CNI | OVN-Kubernetes (fixed) |
| **Billing** | Infrastructure only | Subscription + infrastructure |

Key architectural point: Unlike ROSA HCP (where the control plane is in Red Hat's VPC), **OSD on GCP runs the control plane in the same VPC as the workers**. There is no PrivateLink separation — master and worker nodes communicate directly over the VPC network.

```text
OSD on GCP vs. ROSA HCP:

OSD on GCP:                            ROSA HCP:

Your VPC:                              Your VPC:
+---------------------+               +---------------------+
| Master 1            |               | (no master nodes!)  |
| Master 2            |               |                     |
| Master 3            |               | Worker 1            |
|                     |               | Worker 2            |
| Worker 1            |               | Worker 3            |
| Worker 2            |               +----------+----------+
| Worker 3            |                          |
+---------------------+               PrivateLink|
                                                 |
Everything in ONE VPC,                 Red Hat's VPC:
no PrivateLink needed.                 +---------------------+
                                       | API Server          |
                                       | etcd                |
                                       +---------------------+
```

> **WHY:** Having master and worker nodes in the same VPC simplifies networking — no PrivateLink, no cross-VPC tunneling, direct node-to-node communication. But it means you're responsible for the VPC infrastructure (subnets, firewall rules, Cloud NAT, routes). Red Hat manages the master node VMs and OpenShift software, but the network infrastructure is your responsibility (or managed via Red Hat's automation).

### 7.2 Control Plane Architecture

```text
OSD on GCP Control Plane:

+------------------------------------------------------------------+
| Your VPC (or Red Hat managed VPC)                                |
|                                                                   |
| Region: us-central1                                               |
|                                                                   |
| +----------------------------+  +----------------------------+   |
| | Zone: us-central1-a        |  | Zone: us-central1-b        |  |
| |                            |  |                            |  |
| | Master 1 (n2-standard-4)  |  | Master 2 (n2-standard-4)  |  |
| | 10.0.0.10                  |  | 10.0.0.11                  |  |
| |  - kube-apiserver          |  |  - kube-apiserver          |  |
| |  - etcd                    |  |  - etcd                    |  |
| |  - kube-controller-mgr     |  |  - kube-controller-mgr     |  |
| |  - kube-scheduler          |  |  - kube-scheduler          |  |
| |  - OVN northbound DB       |  |  - OVN northbound DB       |  |
| |  - OVN southbound DB       |  |  - OVN southbound DB       |  |
| +----------------------------+  +----------------------------+   |
|                                                                   |
| +----------------------------+                                    |
| | Zone: us-central1-c        |                                    |
| |                            |                                    |
| | Master 3 (n2-standard-4)  |                                    |
| | 10.0.0.12                  |                                    |
| |  - kube-apiserver          |                                    |
| |  - etcd                    |                                    |
| |  - ...                     |                                    |
| +----------------------------+                                    |
|                                                                   |
| API Server exposed via:                                           |
|   Public:  External TCP LB → master nodes:6443                   |
|   Private: Internal TCP LB → master nodes:6443                   |
+------------------------------------------------------------------+
```

> **WHY:** Three master nodes spread across three zones provide high availability. etcd (the cluster database) runs as a 3-member Raft cluster requiring 2 of 3 members to be healthy for writes. If one zone goes down, the control plane continues operating from the other two. The OVN control plane databases also run on master nodes for the same HA reason.

### 7.3 Full Blackboard-Style Architecture Diagram

```text
+=============================================================================+
|                    OSD ON GCP COMPLETE ARCHITECTURE                          |
+=============================================================================+

  Internet
     |
     | (public traffic)
     v
+=============================================================================+
| YOUR VPC NETWORK (global, no VPC-level CIDR)                                |
|                                                                              |
| Region: us-central1                                                          |
| Subnet: osd-subnet (10.0.0.0/24)                                           |
| Pod Secondary Range: 10.128.0.0/14                                          |
| Service Secondary Range: 172.30.0.0/16                                      |
|                                                                              |
| LOAD BALANCERS                                                               |
| +-----------------------------------------------------------------------+   |
| |                                                                       |   |
| | External TCP LB          Internal TCP LB (private clusters)           |   |
| | VIP: 35.201.100.5        VIP: 10.0.0.100                             |   |
| | (Anycast — global)       (regional — VPC only)                        |   |
| |                                                                       |   |
| | Target: instance group   Target: instance group                       |   |
| | (worker nodes)           (worker nodes)                               |   |
| | Port: 80, 443 →          Port: 80, 443 →                             |   |
| |   NodePort 30080/30443     NodePort 30080/30443                       |   |
| |                                                                       |   |
| | API LB (TCP LB)                                                       |   |
| | VIP: 35.201.200.10 (public) or 10.0.0.101 (private)                  |   |
| | Target: master nodes:6443                                             |   |
| +-----------------------------------------------------------------------+   |
|                                                                              |
| COMPUTE ENGINE VMs                                                           |
| +-----------------------------------------------------------------------+   |
| |                                                                       |   |
| | Zone: us-central1-a                                                   |   |
| | +-------------------------------------------------------------------+ |   |
| | | Master 1 (n2-standard-4)           Worker 1 (n2-standard-8)       | |   |
| | | 10.0.0.10, tag: osd-master          10.0.0.20, tag: osd-worker    | |   |
| | | nic0/eth0: 10.0.0.10               nic0/eth0: 10.0.0.20          | |   |
| | |                                                                   | |   |
| | |                                    +-----------------------------+| |   |
| | | kube-apiserver:6443                | Linux OS                    || |   |
| | | etcd:2379/2380                     | kubelet:10250               || |   |
| | | OVN NB/SB DB                       | CRI-O                       || |   |
| | |                                    |                             || |   |
| | |                                    | OVS br-int                  || |   |
| | |                                    |   |        |        |       || |   |
| | |                                    |   v        v        v       || |   |
| | |                                    | +----+  +----+  +------+   || |   |
| | |                                    | |PodA|  |PodB|  |Router|   || |   |
| | |                                    | |app |  |app |  |HAProx|   || |   |
| | |                                    | |.0.15| |.0.16| |.0.20 |   || |   |
| | |                                    | +----+  +----+  +------+   || |   |
| | |                                    +-----------------------------+| |   |
| | +-------------------------------------------------------------------+ |   |
| |                                                                       |   |
| | Zone: us-central1-b (similar layout with Master 2, Workers)          |   |
| | Zone: us-central1-c (similar layout with Master 3, Workers)          |   |
| +-----------------------------------------------------------------------+   |
|                                                                              |
| NETWORKING                                                                   |
| +-----------------------------------------------------------------------+   |
| |                                                                       |   |
| | Cloud NAT (regional, managed by Cloud Router)                         |   |
| |   External IPs: 35.x.x.1, 35.x.x.2 (auto-allocated)                |   |
| |   Applies to: osd-subnet (all VMs without external IPs)              |   |
| |                                                                       |   |
| | Cloud Router (regional, AS 65010)                                     |   |
| |   Manages Cloud NAT                                                   |   |
| |   (optional) BGP peering with on-prem via VPN/Interconnect           |   |
| |                                                                       |   |
| | Firewall Rules:                                                       |   |
| |   allow-master-to-worker: tag:osd-master → tag:osd-worker TCP 10250 |   |
| |   allow-geneve: tag:osd-worker → tag:osd-worker UDP 6081            |   |
| |   allow-api: 0.0.0.0/0 → tag:osd-master TCP 6443 (public cluster)  |   |
| |   allow-health-check: GCP health check ranges → all TCP 30000-32767 |   |
| |                                                                       |   |
| | Routes:                                                               |   |
| |   0.0.0.0/0 → default internet gateway                              |   |
| |   10.0.0.0/24 → subnet route (auto)                                 |   |
| |   (optional) 192.168.0.0/16 → Cloud VPN/Interconnect next hop       |   |
| +-----------------------------------------------------------------------+   |
|                                                                              |
+=============================================================================+
```

### 7.4 How Master and Worker Nodes Communicate

```text
1. User runs: oc get pods
                |
2. oc CLI   -->| HTTPS to API server LB (35.201.200.10:6443 or 10.0.0.101:6443)
                |
                v
3. GCP TCP LB routes to one of the master nodes:
   Master 1 (10.0.0.10:6443)
   Processes request, reads from etcd, returns pod list
                |
4. Response  <--| back through LB
                v
5. oc CLI displays pod list

---

6. User runs: oc logs my-pod
                |
7. oc CLI   -->| HTTPS to API server (10.0.0.10:6443)
                v
8. API Server needs actual logs from kubelet on worker node
   API server --> worker node kubelet (10.0.0.20:10250)
   (DIRECT connection — same VPC, no PrivateLink needed)
                |
                v
9. Kubelet on worker node reads logs from CRI-O
                |
10. Logs     <--| directly back to API server
                v
11. API Server relays logs back to oc CLI
```

> **WHY:** Because master and worker nodes are in the same VPC, control plane communication is direct — no PrivateLink, no cross-VPC tunneling. This makes `oc logs`, `oc exec`, and `oc port-forward` faster than in ROSA HCP. The trade-off is that the master nodes consume IPs and resources in your VPC.

---

## 8. How Apps Are Exposed in OSD on GCP

This is the core section. It explains, at the packet level, how traffic reaches your applications.

### 8.1 Public Ingress Path — Packet-Level Walkthrough

A user on the internet accesses `https://my-app.apps.osd-cluster.example.com`:

```text
STEP 1: DNS Resolution
========================
User's browser: "What is the IP of my-app.apps.osd-cluster.example.com?"
    |
    v
DNS Resolver → Cloud DNS
    |
    | Cloud DNS has a wildcard record:
    | *.apps.osd-cluster.example.com → A → 35.201.100.5 (LB Anycast VIP)
    |
    | GCP Anycast: same IP advertised from every Google POP
    | User connects to nearest Google edge automatically
    |
    v
Browser gets IP: 35.201.100.5


STEP 2: TCP Connection + TLS Handshake
=======================================
Browser → 35.201.100.5:443 (TCP SYN)
    |
    | Packet:
    | Src IP: 203.0.113.50 (user's public IP)
    | Dst IP: 35.201.100.5 (LB's Anycast VIP)
    | Dst Port: 443
    |
    v
GCP External TCP Network LB receives connection
    |
    | TCP LB is Layer 4 — it does NOT terminate TLS
    | LB selects a healthy backend (worker node)
    |
    | Performs DNAT:
    |   Original dst: 35.201.100.5:443
    |   New dst: 10.0.0.20:30443 (Worker Node 1's IP + router NodePort)
    |
    | GCP LBs preserve the original source IP by default
    |
    v
Packet on VPC network:
    Src IP: 203.0.113.50 (preserved!)
    Dst IP: 10.0.0.20 (worker node)
    Dst Port: 30443 (NodePort for router)


STEP 3: Node Receives Packet
==============================
Worker Node 1's nic0/eth0 receives the packet
    |
    | Firewall rule check (in Andromeda SDN):
    |   Rule: Allow TCP 30000-32767 from GCP health check ranges → PASS
    |
    v
Linux kernel (eth0) receives packet
    |
    | OVN intercepts packets to NodePort 30443
    | DNAT to router pod IP:
    |   Original dst: 10.0.0.20:30443
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
    |   Reads HTTP Host header: "my-app.apps.osd-cluster.example.com"
    |
    | HAProxy config lookup:
    |   Host "my-app.apps.osd-cluster.example.com"
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
    App pod → OVN → Router pod → OVN → Node → LB → Internet → User


COMPLETE IP TRANSFORMATION CHAIN:
===================================
User:        203.0.113.50:54321  →  35.201.100.5:443     (to LB Anycast VIP)
LB DNAT:     203.0.113.50:54321  →  10.0.0.20:30443      (to Node's NodePort)
OVN DNAT:    203.0.113.50:54321  →  10.128.0.20:443      (to Router pod)
HAProxy:     10.128.0.20:xxxxx   →  172.30.45.67:8080    (to Service ClusterIP)
OVN DNAT:    10.128.0.20:xxxxx   →  10.128.0.15:8080     (to App pod)
```

> **WHY:** Understanding this chain is essential for debugging "my app is unreachable" problems. The packet passes through 5 different components (DNS, GCP LB, Node/OVN, Router, OVN again), and a misconfiguration at ANY point breaks the flow. The most common issues: DNS not resolving (Cloud DNS misconfigured), LB target unhealthy (firewall rule blocking NodePort range), router pod not running, Service selector not matching pods.

### 8.2 Private Ingress Path — Packet-Level Walkthrough

For private OSD clusters, there's no public LB. Traffic enters from the corporate network via VPN or Cloud Interconnect.

```text
Corporate User (192.168.1.100) accesses private app:

STEP 1: DNS Resolution
========================
Corporate DNS server resolves:
    my-app.apps.osd-cluster.internal.com → 10.0.0.100 (Internal LB VIP)

    Note: This uses split-horizon DNS:
    - From internet: *.apps.osd-cluster... → NXDOMAIN (doesn't exist)
    - From corp network: *.apps.osd-cluster... → internal LB VIP


STEP 2: Traffic Path
=====================
Corp user (192.168.1.100)
    |
    v
Corporate Router / Firewall
    |
    v
Cloud VPN Tunnel or Cloud Interconnect
    |
    v
Cloud Router learns route to VPC subnet
    |
    v
VPC receives packet:
    Src IP: 192.168.1.100
    Dst IP: 10.0.0.100 (Internal LB VIP)
    Dst Port: 443


STEP 3: Internal TCP LB
=========================
Internal LB (no public IP, VPC-internal only)
    |
    | DNAT:
    |   Dst: 10.0.0.100:443 → 10.0.0.20:30443 (Node NodePort)
    |
    v
Same flow as public ingress from Step 3 onward:
    Node → OVN → Router Pod → Service → App Pod


COMPLETE IP TRANSFORMATION CHAIN:
===================================
Corp User:   192.168.1.100:54321  →  10.0.0.100:443      (to internal LB VIP)
LB DNAT:     192.168.1.100:54321  →  10.0.0.20:30443     (to Node NodePort)
OVN DNAT:    192.168.1.100:54321  →  10.128.0.20:443     (to Router pod)
HAProxy:     10.128.0.20:xxxxx    →  172.30.45.67:8080    (to Service ClusterIP)
OVN DNAT:    10.128.0.20:xxxxx    →  10.128.0.15:8080     (to App pod)
```

> **WHY:** Private ingress is the standard for production workloads in regulated industries. The key difference from public ingress is that DNS must be configured on the corporate side to resolve *.apps to the internal LB VIP, typically via Cloud DNS private zones or on-prem DNS forwarding.

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
    - VPC subnet (10.0.0.0/24) — not a VPC host
    → Must go to external network

OVN SNAT (Source NAT):
    Original src: 10.128.0.15 (pod IP)
    New src: 10.0.0.20 (node IP)
    
    WHY: The VPC doesn't know about pod IPs (10.128.x.x).
    It only knows about node IPs (10.0.0.x). If OVN
    didn't SNAT, the VPC would drop the packet.


STEP 3: VPC Routing
=====================
Packet on VPC network:
    Src IP: 10.0.0.20 (node IP after OVN SNAT)
    Dst IP: 54.187.174.169
    Dst Port: 443

VPC route lookup:
    54.187.174.169 doesn't match 10.0.0.0/24 (subnet)
    54.187.174.169 matches 0.0.0.0/0 → default internet gateway
    → Forward to Cloud NAT (because VM has no external IP)


STEP 4: Cloud NAT SNAT
========================
Cloud NAT (in Andromeda SDN) processes packet:
    Src IP: 10.0.0.20 (node's private IP)
    Dst IP: 54.187.174.169

Cloud NAT SNAT:
    Original src: 10.0.0.20
    New src: 35.x.y.z (Cloud NAT's external IP)
    
    Cloud NAT records this translation in its connection table:
    35.x.y.z:12345 ↔ 10.0.0.20:54321


STEP 5: Internet
==================
Packet on the internet:
    Src IP: 35.x.y.z (Cloud NAT's external IP — this is what Stripe sees)
    Dst IP: 54.187.174.169 (Stripe's server)
    Dst Port: 443


STEP 6: Response (reverse path)
================================
Stripe responds:
    Src IP: 54.187.174.169
    Dst IP: 35.x.y.z (Cloud NAT's external IP)

Cloud NAT reverse SNAT:
    Dst IP: 35.x.y.z → 10.0.0.20 (looked up in connection table)

VPC routes to node 10.0.0.20

OVN reverse SNAT:
    Dst IP: 10.0.0.20 → 10.128.0.15 (looked up in conntrack)

Packet delivered to pod.


DOUBLE SNAT SUMMARY:
=====================
Pod sends:     src=10.128.0.15  (pod IP)
OVN SNAT:      src=10.0.0.20    (node IP)     ← first translation
Cloud NAT:     src=35.x.y.z     (external IP)  ← second translation
Internet sees: 35.x.y.z                       ← what external services log

Response reverses both translations automatically.
```

> **WHY:** Egress goes through double SNAT. When you look at external service logs, the source IP will be the Cloud NAT's external IP — not the pod IP or node IP. If your company's firewall must allowlist specific source IPs, you provide the Cloud NAT external IPs. Cloud NAT can be configured with manual external IPs for predictable addresses.

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
| OUTER: Src=10.0.0.20 Dst=10.0.0.21 UDP DstPort=6081             |
| GENEVE HDR: VNI=0x1                                              |
| INNER: Src=10.128.0.15 Dst=10.128.2.33 TCP DstPort=8080         |
+------------------------------------------------------------------+
    |
    v
eth0 on Node 1 → nic0 → VPC network
    |
    | VPC sees: 10.0.0.20 → 10.0.0.21 (just a UDP packet)
    | Firewall rule: Allow UDP 6081 from tag:osd-worker → PASS
    |
    v
eth0 on Node 2 → OVS receives on Geneve port
    |
    v
br-int on Node 2 → decapsulate → deliver to Pod C's veth

Pod C receives:
    Src: 10.128.0.15, Dst: 10.128.2.33
    (original IPs preserved — no SNAT for pod-to-pod)
```

> **WHY:** Cross-node pod traffic uses Geneve encapsulation because the VPC network doesn't know about pod IPs. Firewall rules must allow UDP 6081 between worker nodes — blocking it breaks all cross-node pod communication. Same-node traffic skips encapsulation entirely. Cross-zone traffic within a GCP region has no additional bandwidth cost (unlike some AWS inter-AZ charges).

### 8.5 Pod-to-Service Traffic

```text
Pod A (10.128.0.15) calls Service "my-api" (ClusterIP 172.30.45.67:8080):

Pod A:
    curl http://my-api.production.svc.cluster.local:8080
    |
    v
CoreDNS resolves: my-api.production.svc.cluster.local → 172.30.45.67
    |
    v
Pod A sends packet:
    Src: 10.128.0.15
    Dst: 172.30.45.67:8080 (ClusterIP — not a real IP!)
    |
    v
OVN intercepts (ClusterIP is in Service CIDR 172.30.0.0/16):
    |
    | OVN load balancer lookup:
    | Service 172.30.45.67:8080 has endpoints:
    |   - 10.128.0.16:8080 (Pod B, same node)
    |   - 10.128.2.33:8080 (Pod C, different node)
    |
    | OVN selects: 10.128.2.33 (round-robin)
    |
    | DNAT:
    |   Original dst: 172.30.45.67:8080
    |   New dst: 10.128.2.33:8080
    |
    v
Packet is now pod-to-pod (10.128.0.15 → 10.128.2.33)
    → follows cross-node path (Geneve if different node)
```

> **WHY:** The ClusterIP (172.30.45.67) never appears on any network interface — it's a virtual construct that only exists as DNAT rules in OVN. When troubleshooting "Service not reachable," check `oc get endpoints my-api -n production` to verify OVN has backend pods to forward to.

---

## 9. IP Address Architecture

### 9.1 The Four IP Ranges in OSD on GCP

Every OSD on GCP cluster uses four distinct IP ranges that must not overlap:

```text
+---------------------------------------------------------------+
|                OSD on GCP IP Architecture                      |
+---------------------------------------------------------------+
|                                                               |
|  1. Node Subnet CIDR: 10.0.0.0/24                            |
|     Used for: Master and worker node IPs                      |
|     Size: 256 addresses (minus GCP reserved)                  |
|     YOU configure this (or Red Hat auto-creates)              |
|                                                               |
|  2. Pod CIDR (Cluster Network): 10.128.0.0/14                |
|     Used for: Pod IP addresses                                |
|     Size: 262,144 addresses                                   |
|     Default host prefix: /23 (512 pods per node)              |
|     Configured as secondary range on subnet                   |
|                                                               |
|  3. Service CIDR (Service Network): 172.30.0.0/16             |
|     Used for: Kubernetes Service ClusterIPs                   |
|     Size: 65,536 addresses                                    |
|     Virtual only — never appears on a wire                    |
|     Configured as secondary range on subnet                   |
|                                                               |
|  4. Master CIDR (for master nodes): 10.1.0.0/28              |
|     Used for: API server internal IPs (some configs)          |
|     May overlap with VPC in peered setups                     |
|                                                               |
+---------------------------------------------------------------+

These ranges MUST NOT overlap with:
  - Each other
  - On-prem networks (if using VPN/Interconnect)
  - Other VPCs (if using peering)
  - GCP reserved ranges (169.254.0.0/16, metadata server)
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
    Pod N: 10.128.1.254 (last usable in /23)

When Node 2 joins:
    OVN allocates: 10.128.2.0/23 to Node 2
    Pods on Node 2: 10.128.2.2, 10.128.2.3, ...
```

> **WHY:** This hierarchical allocation means you can tell which node a pod is on just from its IP address. Each node manages its own IP pool locally without coordinating with other nodes.

### 9.3 SNAT — When and Why Pod IPs Become Node IPs

OVN performs SNAT on pod traffic in specific situations:

| Traffic Type | SNAT? | Source IP at Destination |
|-------------|-------|------------------------|
| Pod → Pod (same cluster) | No | Pod IP (10.128.x.x) |
| Pod → Service (same cluster) | No | Pod IP (10.128.x.x) |
| Pod → Node IP (same cluster) | Yes | Node IP (10.0.0.x) |
| Pod → VPC resource (Cloud SQL, etc.) | Yes | Node IP (10.0.0.x) |
| Pod → Internet (via Cloud NAT) | Yes (double) | Cloud NAT external IP (35.x.x.x) |
| Pod → On-prem (via VPN/Interconnect) | Yes | Node IP (10.0.0.x) |

```text
Why SNAT happens for external traffic:

The VPC routing table only has routes for VPC subnet CIDRs (10.0.0.0/24).
Pod CIDRs (10.128.0.0/14) have NO route in the VPC (when using overlay).

If a pod sent a packet with src=10.128.0.15 to a Cloud SQL database:
    Cloud SQL receives packet from 10.128.0.15
    Cloud SQL sends response to 10.128.0.15
    VPC routing: "Where is 10.128.0.15?" → NO ROUTE → DROPPED!

With SNAT (src becomes 10.0.0.20):
    Cloud SQL receives packet from 10.0.0.20
    Cloud SQL sends response to 10.0.0.20
    VPC routing: "Where is 10.0.0.20?" → subnet route → delivered to Node 1
    Node 1's OVN conntrack: reverse SNAT to 10.128.0.15 → delivered to pod
```

> **WHY:** This is why pods talking to Cloud SQL, Memorystore (Redis), or any VPC resource appear as the node IP. If you set up firewall rules for a Cloud SQL private IP, you must allow the node IPs or the worker node network tag — not pod IPs, because those are invisible to the VPC.

### 9.4 Cloud NAT External IPs

```text
OSD on GCP cluster with Cloud NAT:

Cloud NAT is regional (not per-zone like AWS NAT GW).
A single Cloud NAT can serve the entire region.

Cloud NAT auto-allocates external IPs:
    IP 1: 35.10.1.1
    IP 2: 35.10.1.2 (allocated as connections scale)

All pods in the region exit with src = one of these IPs.

External service firewall allowlist:
    35.10.1.1, 35.10.1.2

For predictable IPs, use manual allocation:
    gcloud compute addresses create osd-nat-ip-1 --region=us-central1
    → then assign to Cloud NAT
```

> **WHY:** Unlike AWS where each AZ has its own NAT Gateway with its own EIP, GCP's Cloud NAT is regional. A single Cloud NAT configuration handles all zones in the region. For allowlisting, you need fewer IPs but should configure manual IP allocation for predictability.

---

## 10. BGP and Hybrid Networking

### 10.1 BGP Fundamentals

**BGP (Border Gateway Protocol)** is the routing protocol that runs the internet. It's also used to connect corporate networks to GCP.

```text
BGP in one sentence:
    "I am AS 65020. I can reach networks 192.168.0.0/16 and 172.16.0.0/12.
     Let me tell my neighbors so they can route traffic to me."
```

**Key concepts:**

| Concept | What It Is | Example |
|---------|-----------|---------|
| **AS (Autonomous System)** | A network under one administrative control | Your company = AS 65020, GCP = AS 65010 |
| **ASN (AS Number)** | Unique number identifying an AS | 65020 (private range: 64512-65534) |
| **Prefix** | A network (CIDR) that an AS announces | "I have 192.168.0.0/16" |
| **Peer** | A BGP neighbor you exchange routes with | Cloud Router peers with your on-prem router |
| **MED (Multi-Exit Discriminator)** | Preference value for choosing between paths | Lower MED = preferred path |

```text
BGP Route Exchange:

Your On-Prem Router (AS 65020)          GCP Cloud Router (AS 65010)
+----------------------------+          +----------------------------+
| "I have:                   |          | "I have:                   |
|   192.168.0.0/16 (corp)    | <------> |   10.0.0.0/24 (OSD subnet)|
|   172.16.0.0/12 (DC2)     |   BGP    |                            |
|                            | session  |                            |
| I learned from GCP:        |          | I learned from on-prem:    |
|   10.0.0.0/24             |          |   192.168.0.0/16           |
+----------------------------+          +----------------------------+
```

> **WHY:** BGP is how OSD on GCP pods reach on-premises resources. Without BGP, the VPC wouldn't know that 192.168.0.0/16 is reachable through the VPN tunnel or Interconnect. BGP dynamically learns and propagates routes.

### 10.2 Cloud Router BGP Configuration

```text
Complete Hybrid Architecture with BGP:

+-------------------------------------------------------------------+
|                       GCP Region: us-central1                      |
|                                                                    |
|  +-------------------+         +-------------------+               |
|  | VPC: osd-vpc      |         | Cloud Router      |               |
|  | 10.0.0.0/24       |         | (AS 65010)        |               |
|  |                   |         |                   |               |
|  | OSD worker nodes  |         | Advertises:       |               |
|  | 10.0.0.20         |         |   10.0.0.0/24     |               |
|  | 10.0.0.21         |         |                   |               |
|  |                   |         | Learns:            |               |
|  | VPC routes:       |         |   192.168.0.0/16  |               |
|  | 192.168.0.0/16    |         |   (from on-prem)  |               |
|  |   → VPN next hop  |         +---+---------------+               |
|  +-------------------+             |                                |
|                                    | HA VPN Tunnel                  |
|                                    | (IPsec encrypted)              |
|                                    | BGP over tunnel                |
+------------------------------------+--------------------------------+
                                     |
                                     v
                    +----------------------------+
                    | On-Prem Border Router      |
                    | (AS 65020)                  |
                    |                            |
                    | BGP Neighbor: Cloud Router  |
                    | Advertises: 192.168.0.0/16 |
                    | Learns:     10.0.0.0/24    |
                    +----------------------------+
                                |
                                v
                    +----------------------------+
                    | On-Prem Network             |
                    | 192.168.0.0/16             |
                    |                            |
                    | Database: 192.168.10.50    |
                    +----------------------------+
```

### 10.3 Setting Up HA VPN with BGP

```bash
# Step 1: Create Cloud Router
gcloud compute routers create osd-router \
  --network=osd-vpc \
  --asn=65010 \
  --region=us-central1

# Step 2: Create HA VPN Gateway
gcloud compute vpn-gateways create osd-vpn-gw \
  --network=osd-vpc \
  --region=us-central1

# Step 3: Create Peer (External) VPN Gateway
gcloud compute external-vpn-gateways create onprem-vpn-gw \
  --interfaces="0=203.0.113.1,1=203.0.113.2"

# Step 4: Create VPN Tunnels (two for HA)
gcloud compute vpn-tunnels create osd-tunnel-0 \
  --peer-external-gateway=onprem-vpn-gw \
  --peer-external-gateway-interface=0 \
  --vpn-gateway=osd-vpn-gw \
  --vpn-gateway-region=us-central1 \
  --ike-version=2 \
  --shared-secret="YOUR_SHARED_SECRET" \
  --router=osd-router \
  --vpn-gateway-interface=0

gcloud compute vpn-tunnels create osd-tunnel-1 \
  --peer-external-gateway=onprem-vpn-gw \
  --peer-external-gateway-interface=1 \
  --vpn-gateway=osd-vpn-gw \
  --vpn-gateway-region=us-central1 \
  --ike-version=2 \
  --shared-secret="YOUR_SHARED_SECRET" \
  --router=osd-router \
  --vpn-gateway-interface=1

# Step 5: Create Cloud Router Interfaces and BGP Peers
gcloud compute routers add-interface osd-router \
  --interface-name=vpn-if-0 \
  --vpn-tunnel=osd-tunnel-0 \
  --ip-address=169.254.0.1 \
  --mask-length=30 \
  --region=us-central1

gcloud compute routers add-bgp-peer osd-router \
  --peer-name=onprem-peer-0 \
  --interface=vpn-if-0 \
  --peer-ip-address=169.254.0.2 \
  --peer-asn=65020 \
  --region=us-central1

gcloud compute routers add-interface osd-router \
  --interface-name=vpn-if-1 \
  --vpn-tunnel=osd-tunnel-1 \
  --ip-address=169.254.1.1 \
  --mask-length=30 \
  --region=us-central1

gcloud compute routers add-bgp-peer osd-router \
  --peer-name=onprem-peer-1 \
  --interface=vpn-if-1 \
  --peer-ip-address=169.254.1.2 \
  --peer-asn=65020 \
  --region=us-central1

# Step 6: Verify BGP sessions
gcloud compute routers get-status osd-router \
  --region=us-central1
```

### 10.4 On-Prem Router BGP Configuration (Cisco IOS Example)

```text
router bgp 65020
 bgp router-id 192.168.1.1
 neighbor 169.254.0.1 remote-as 65010
 neighbor 169.254.0.1 description GCP-Cloud-Router-Tunnel0
 neighbor 169.254.1.1 remote-as 65010
 neighbor 169.254.1.1 description GCP-Cloud-Router-Tunnel1
 !
 address-family ipv4 unicast
  network 192.168.0.0 mask 255.255.0.0
  neighbor 169.254.0.1 activate
  neighbor 169.254.0.1 soft-reconfiguration inbound
  neighbor 169.254.1.1 activate
  neighbor 169.254.1.1 soft-reconfiguration inbound
 exit-address-family
```

> **WHY:** `network 192.168.0.0 mask 255.255.0.0` tells BGP to advertise this prefix to the Cloud Router. The Cloud Router learns this route and adds it to the VPC routing table as a dynamic route. Now pods on OSD worker nodes can send packets to 192.168.x.x addresses through the VPN tunnel.

### 10.5 Pod CIDR Advertisement Considerations

By default, the OSD pod CIDR (10.128.0.0/14) is NOT advertised via BGP. Pods appear as node IPs to on-prem due to OVN SNAT.

> **WHY:** Advertising pod CIDRs adds complexity — on-prem firewalls must handle a much larger set of source IPs, and pod IPs are ephemeral. The SNAT approach is simpler and sufficient for most use cases.

---

## 11. DNS Architecture in OSD on GCP

### 11.1 DNS Layers in OSD on GCP

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
3. GCP Metadata Server (169.254.169.254):
     Forwards to Cloud DNS
     Handles: Cloud DNS public/private hosted zones
              Google service endpoints
              External domains
         |
         | For external domains:
         v
4. Cloud DNS / Google Public DNS:
     Handles: Everything else (github.com, stripe.com, etc.)
```

### 11.2 CoreDNS Inside the Cluster

CoreDNS runs as a DaemonSet in `openshift-dns` (one pod per node for performance).

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
         v                         v                          v
+------------------+
| Kubernetes API   |     CoreDNS watches the K8s API for
| (watches         |     Service and Endpoint changes
|  Services,       |
|  Endpoints)      |
+------------------+
```

For external names, CoreDNS forwards to the GCP metadata server (169.254.169.254), which uses Cloud DNS resolution.

> **WHY:** CoreDNS is deployed as a DaemonSet (one per node) so DNS queries don't cross the network — a pod's DNS query goes to the CoreDNS on the same node, avoiding Geneve tunnel overhead. The upstream resolver is the GCP metadata server, which provides access to Cloud DNS private zones and Google's DNS infrastructure.

### 11.3 Cloud DNS and OSD on GCP

OSD creates Cloud DNS records automatically:

```text
Public Zone:
+-------------------------------------------------------+
| Zone: osd-cluster.example.com                         |
|                                                       |
| api.osd-cluster.example.com                           |
|   → A → 35.201.200.10 (API LB external IP)           |
|                                                       |
| *.apps.osd-cluster.example.com                        |
|   → A → 35.201.100.5 (Ingress LB external IP)        |
|   (This is how Routes are resolved!)                  |
+-------------------------------------------------------+

The wildcard record means:
  ANY-NAME.apps.osd-cluster.example.com
  all resolve to the same LB IP.
  
  The LB delivers to the OpenShift Router (HAProxy),
  which reads the Host header to pick the right backend.
```

### 11.4 Split-Horizon DNS for Private Clusters

For private OSD clusters, the same DNS name resolves differently based on source:

```text
Private Cluster DNS:

From the internet:
    dig my-app.apps.osd-cluster.internal.com
    → NXDOMAIN (doesn't exist in public DNS)

From inside the VPC (or connected network):
    dig my-app.apps.osd-cluster.internal.com
    → 10.0.0.100 (internal LB VIP)

How this works:
    Cloud DNS Private Zone:
    - Associated with the OSD VPC
    - *.apps.osd-cluster.internal.com → internal LB VIP
    - Only visible to VMs in the associated VPC

    To make it work from on-prem:
    - Configure Cloud DNS Inbound Server Policy
    - On-prem DNS forwards *.apps.osd-cluster.internal.com
      to the VPC's DNS forwarding IP (from Inbound Policy)
```

```text
Private DNS Flow (from on-prem):

On-Prem User: "resolve my-app.apps.osd-cluster.internal.com"
    |
    v
On-Prem DNS Server
    |
    | Conditional forwarder:
    | *.apps.osd-cluster.internal.com → 10.0.0.250
    | (Cloud DNS Inbound Policy forwarding IP)
    |
    v
Cloud DNS Inbound Policy (receives query in VPC)
    |
    v
Cloud DNS Private Zone
    |
    | *.apps.osd-cluster.internal.com → 10.0.0.100 (internal LB)
    |
    v
Response: 10.0.0.100
    |
    v
On-prem user connects to 10.0.0.100 via VPN/Interconnect
```

> **WHY:** Split-horizon DNS is essential for private clusters. Without it, on-prem users can't resolve cluster hostnames. Cloud DNS Inbound Server Policies create a DNS forwarding address in the VPC that on-prem DNS servers can forward queries to.

---

## 12. Security Architecture

### 12.1 S1 — Private OSD Cluster Security Bundle

This bundle locks down a private OSD on GCP cluster.

#### Firewall Rules for Master Nodes

```bash
# Rule 1: Allow API server access from within VPC
gcloud compute firewall-rules create osd-allow-api-internal \
  --network=osd-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:6443 \
  --source-ranges=10.0.0.0/24 \
  --target-tags=osd-master \
  --priority=1000
```

> **WHY:** Port 6443 is the Kubernetes API server. For private clusters, only VPC-internal traffic should reach the API. No public-facing rule needed.

```bash
# Rule 2: Allow etcd peering between masters
gcloud compute firewall-rules create osd-allow-etcd \
  --network=osd-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:2379-2380 \
  --source-tags=osd-master \
  --target-tags=osd-master \
  --priority=1000
```

> **WHY:** Ports 2379 (client) and 2380 (peer) are used by etcd for cluster consensus. Only master nodes should talk to etcd. Restricting source to `osd-master` tag ensures workers can't directly access etcd.

#### Firewall Rules for Worker Nodes

```bash
# Rule 3: Allow kubelet from masters
gcloud compute firewall-rules create osd-allow-kubelet \
  --network=osd-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:10250 \
  --source-tags=osd-master \
  --target-tags=osd-worker \
  --priority=1000
```

> **WHY:** Port 10250 is the kubelet API. The API server (on masters) calls kubelets for `oc logs`, `oc exec`, and health checks.

```bash
# Rule 4: Allow Geneve overlay between workers
gcloud compute firewall-rules create osd-allow-geneve \
  --network=osd-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=udp:6081 \
  --source-tags=osd-worker \
  --target-tags=osd-worker \
  --priority=1000
```

> **WHY:** UDP 6081 is the Geneve tunnel port. All cross-node pod communication is encapsulated in Geneve packets. Blocking this completely breaks pod-to-pod networking across nodes.

```bash
# Rule 5: Allow GCP health check ranges for load balancers
gcloud compute firewall-rules create osd-allow-health-checks \
  --network=osd-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:30000-32767 \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \
  --target-tags=osd-worker \
  --priority=1000
```

> **WHY:** GCP load balancers send health checks from these IP ranges. If blocked, the LB marks all backends as unhealthy and stops routing traffic. The NodePort range (30000-32767) includes the router's NodePorts.

```bash
# Rule 6: Allow node-to-node communication
gcloud compute firewall-rules create osd-allow-node-metrics \
  --network=osd-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:9000-9999 \
  --source-tags=osd-worker \
  --target-tags=osd-worker \
  --priority=1000
```

> **WHY:** Ports 9000-9999 are used by OpenShift node-level services: node-exporter (9100), OVN metrics (9105), and other monitoring endpoints.

#### Cloud NAT Configuration

```bash
# Create Cloud Router (required by Cloud NAT)
gcloud compute routers create osd-nat-router \
  --network=osd-vpc \
  --region=us-central1

# Create Cloud NAT with manual IPs for predictability
gcloud compute addresses create osd-nat-ip-1 \
  --region=us-central1

gcloud compute routers nats create osd-nat \
  --router=osd-nat-router \
  --region=us-central1 \
  --nat-all-subnet-ip-ranges \
  --nat-external-ip-pool=osd-nat-ip-1
```

> **WHY:** Manual IP allocation gives you predictable external IPs for allowlisting in corporate firewalls and external service ACLs.

#### Private Google Access

```bash
# Enable Private Google Access on the OSD subnet
gcloud compute networks subnets update osd-node-subnet \
  --region=us-central1 \
  --enable-private-google-access
```

> **WHY:** Private Google Access allows worker nodes (which have no external IPs) to reach Google APIs (Container Registry, Cloud Storage, IAM) without going through Cloud NAT. This is mandatory for private clusters — without it, the cluster can't pull images from gcr.io or interact with GCP APIs.

#### Required API Access

For private OSD clusters, ensure these APIs are enabled and accessible:

```bash
# Verify required APIs are enabled
gcloud services list --enabled --filter="
  name:compute.googleapis.com OR
  name:container.googleapis.com OR
  name:iam.googleapis.com OR
  name:dns.googleapis.com OR
  name:storage-api.googleapis.com OR
  name:containerregistry.googleapis.com OR
  name:artifactregistry.googleapis.com OR
  name:cloudresourcemanager.googleapis.com
"
```

> **WHY:** OSD on GCP requires access to Compute Engine (VM management), IAM (service account auth), Cloud DNS (record management), Storage (image layers), and Container/Artifact Registry (image pulls). Without API access, the cluster cannot scale, pull images, or manage DNS records.

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

> **WHY:** Blocks all traffic to and from every pod in the namespace by default. You then add specific allow rules.

```bash
# Allow ingress from router pods
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

> **WHY:** Only the OpenShift router pods can reach your app. No other pod in the cluster can directly access it.

```bash
# Allow DNS egress (essential!)
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

> **WHY:** If you have a default-deny egress policy but forget to allow DNS (port 53), every DNS lookup fails. This is the most common mistake when implementing network policies.

### 12.2 S2 — Hybrid OSD Security Bundle

This bundle secures an OSD on GCP cluster with connectivity to on-premises networks.

#### VPN/Interconnect Firewall Rules

```bash
# Allow on-prem to reach OSD nodes (specific services only)
gcloud compute firewall-rules create osd-allow-from-onprem \
  --network=osd-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:443 \
  --source-ranges=192.168.0.0/16 \
  --target-tags=osd-worker \
  --priority=1000

# Allow OSD nodes to reach on-prem DB
gcloud compute firewall-rules create osd-allow-to-onprem-db \
  --network=osd-vpc \
  --direction=EGRESS \
  --action=ALLOW \
  --rules=tcp:5432 \
  --destination-ranges=192.168.10.50/32 \
  --target-tags=osd-worker \
  --priority=1000
```

> **WHY:** Restrict traffic between OSD and on-prem to only the required flows. The egress rule limits which on-prem destinations worker nodes can reach.

#### On-Prem Firewall Rules

```text
# On your on-prem firewall, allow only the specific traffic:

# Allow OSD node IPs to reach the database
allow src 10.0.0.0/24 dst 192.168.10.50/32 port 5432 proto tcp

# Deny everything else from OSD
deny src 10.0.0.0/24 dst any

# Note: Source is 10.0.0.0/24 (VPC subnet), not 10.128.0.0/14 (pod CIDR),
# because OVN SNATs pod IPs to node IPs before they leave the node.
```

> **WHY:** On-prem firewall rules use the VPC subnet CIDR (node IPs) as the source, not the pod CIDR. OVN SNATs pod traffic to node IPs.

#### DB-Only Egress NetworkPolicy

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

> **WHY:** This policy allows db-client pods to only reach the on-prem database (192.168.10.50:5432) and DNS (port 53). All other egress is blocked.

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
```

> **WHY:** mTLS ensures all pod-to-pod traffic within the mesh is encrypted and authenticated, providing defense-in-depth on top of NetworkPolicies.

---

## 13. Scenario Matrix & Traffic Exposure Table

### 13.1 Scenario Matrix

| # | Scenario | App Use Case | Traffic Type | Ingress Path | Egress Path | Exposure Level |
|---|----------|-------------|-------------|-------------|-------------|---------------|
| 1 | **Public App** | Public websites, APIs | HTTP/HTTPS | Internet → Cloud DNS → External TCP LB (Anycast) → Router → Pod | Pod → OVN SNAT → Cloud NAT → Internet | Public LB with Anycast VIP |
| 2 | **Private App** | Internal corporate apps | HTTP/HTTPS | Corp → VPN/Interconnect → Internal TCP LB → Router → Pod | Pod → OVN SNAT → Cloud NAT or VPN/Interconnect | No public IPs, VPC-internal only |
| 3 | **Zero-Egress** | Regulated (HIPAA, PCI) | HTTP/TCP | Same as Private | Pod → Private Google Access only (no Cloud NAT) | No outbound internet |
| 4 | **Hybrid App** | Apps with on-prem DB | TCP | Public or Private | Pod → OVN SNAT → VPC route → VPN/Interconnect → On-prem | Node IP visible to on-prem, BGP-routed |
| 5 | **Service Mesh** | Microservices with mTLS | gRPC/mTLS | Mesh gateway | Sidecar → OVN → Cloud NAT/VPN | L7-enforced, encrypted pod-to-pod |
| 6 | **Custom Front Door** | WAF, CDN | HTTPS | Internet → Cloud Armor/CDN → HTTP(S) LB → OSD LB → Router → Pod | Same as Public | TLS at Google's edge, WAF protection |
| 7 | **Inter-Cluster** | Multi-region, DR | gRPC/mTLS | Cluster A → VPN/Peering → Cluster B LB → Router → Pod | Reverse path | L3 routed between VPCs |
| 8 | **Registry Heavy** | CI/CD pipelines | HTTPS | N/A | Pod → Private Google Access → gcr.io/Artifact Registry | Outbound HTTPS to Google APIs |
| 9 | **Observability** | Logs, metrics, traces | OTLP/HTTP | N/A | Pod → Cloud NAT → Datadog/Splunk | Outbound only |
| 10 | **Node-to-Node** | SDN overlay | Geneve/UDP 6081 | N/A | N/A | L2.5 overlay, never leaves VPC |
| 11 | **Control Plane** | API server ↔ kubelet | HTTPS | Direct VPC communication | Direct VPC | Same VPC, no tunneling |

### 13.2 Traffic Exposure Table

| Traffic Flow | Source IP Seen by Destination | Encryption | GCP Components Traversed | K8s Components Traversed |
|-------------|------------------------------|-----------|------------------------|------------------------|
| Internet → App | Client's public IP (X-Forwarded-For) | TLS (edge at router) | External TCP LB | OVN, Router, Service, Pod |
| Corp → Private App | Corp client IP | TLS | VPN/Interconnect, Internal LB | OVN, Router, Service, Pod |
| Pod → Internet | Cloud NAT external IP | TLS (app-initiated) | OVN SNAT, Cloud NAT | OVN SNAT |
| Pod → On-prem DB | Node IP (OVN SNAT) | Optional (app-level) | OVN SNAT, VPN/Interconnect | OVN SNAT |
| Pod → Pod (same node) | Pod IP (no SNAT) | None (unless mesh) | None | OVS br-int |
| Pod → Pod (cross node) | Pod IP (no SNAT) | None (unless mesh) | Geneve over VPC | OVS br-int, Geneve tunnel |
| Pod → Service | Pod IP | None (unless mesh) | None | OVN DNAT, OVS |
| Pod → Google API (w/ PGA) | Node IP (OVN SNAT) | TLS | OVN SNAT, Private Google Access | OVN SNAT |
| Pod → Google API (w/o PGA) | Cloud NAT external IP | TLS | OVN SNAT, Cloud NAT | OVN SNAT |
| API Server → Kubelet | Master node IP | TLS (mutual) | Direct VPC | Kubelet |
| oc CLI → API Server | User's IP → LB | TLS | TCP LB | API Server |

### 13.3 Port Reference

| Port | Protocol | Purpose | Used By |
|------|---------|---------|---------|
| 6443 | TCP | Kubernetes API server | oc, kubelets, controllers |
| 10250 | TCP | Kubelet API | API server (for logs/exec) |
| 2379-2380 | TCP | etcd client and peer | Master nodes (etcd cluster) |
| 6081 | UDP | Geneve overlay tunnels | OVN-Kubernetes (cross-node pod traffic) |
| 30000-32767 | TCP | NodePort range | Services (LB targets) |
| 443 | TCP | HTTPS (general) | Everything external |
| 80 | TCP | HTTP (redirects to 443) | Router |
| 53 | UDP/TCP | DNS | CoreDNS |
| 9000-9999 | TCP | Node metrics/health | Prometheus, node-exporter |
| 5432 | TCP | PostgreSQL | Example on-prem DB |

---

## 14. Complete Command Reference

### 14.1 Cluster Information

```bash
# Get cluster details
ocm describe cluster <cluster-name>

# Get cluster credentials
ocm get credentials --cluster=<cluster-id>

# Login to cluster
oc login https://api.osd-cluster.example.com:6443 \
  --username cluster-admin --password '<password>'
```

### 14.2 GCP Infrastructure Inspection

```bash
# List VMs in the project
gcloud compute instances list --filter="tags.items:osd-"

# Get VM details (including network interface)
gcloud compute instances describe <instance-name> \
  --zone=us-central1-a \
  --format="yaml(networkInterfaces)"

# List firewall rules
gcloud compute firewall-rules list --filter="network:osd-vpc"

# Describe a specific firewall rule
gcloud compute firewall-rules describe osd-allow-geneve

# List routes
gcloud compute routes list --filter="network:osd-vpc"

# Check Cloud NAT status
gcloud compute routers nats describe osd-nat \
  --router=osd-nat-router \
  --region=us-central1

# List Cloud NAT external IPs
gcloud compute routers get-nat-mapping-info osd-nat-router \
  --region=us-central1

# Check Cloud Router BGP status
gcloud compute routers get-status osd-router \
  --region=us-central1

# Check VPN tunnel status
gcloud compute vpn-tunnels describe osd-tunnel-0 \
  --region=us-central1

# List load balancers
gcloud compute forwarding-rules list

# Check load balancer health
gcloud compute backend-services get-health <backend-service-name> \
  --global
```

### 14.3 Ingress Configuration

```bash
# Check current ingress controller
oc get ingresscontroller default -n openshift-ingress-operator -o yaml

# Create an edge-terminated Route
oc create route edge my-app \
  --service=my-app-svc \
  --hostname=my-app.apps.osd-cluster.example.com \
  --cert=tls.crt \
  --key=tls.key

# Create a passthrough Route
oc create route passthrough my-tls-app \
  --service=my-tls-app-svc \
  --hostname=my-tls-app.apps.osd-cluster.example.com

# Make ingress internal-only
oc -n openshift-ingress annotate service router-default \
  cloud.google.com/load-balancer-type="Internal" \
  --overwrite
```

### 14.4 Network Policy Examples

```bash
# List all network policies
oc get networkpolicy -A

# Default deny
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

# Allow ingress from monitoring
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

# Allow egress to specific CIDR + DNS
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

### 14.5 Troubleshooting Commands

```bash
# Check node status and IPs
oc get nodes -o wide

# Check router pods
oc get pods -n openshift-ingress -o wide

# Check OVN pods
oc get pods -n openshift-ovn-kubernetes -o wide

# Check DNS pods
oc get pods -n openshift-dns -o wide

# Test DNS from a pod
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

# Packet capture on a node
oc debug node/<node-name> -- chroot /host tcpdump -i any -c 100 port 6081

# Collect must-gather for networking
oc adm must-gather --dest-dir=/tmp/network-debug -- /usr/bin/gather_network_logs
```

### 14.6 Security Validation Commands

```bash
# Verify firewall rules
gcloud compute firewall-rules list --filter="network:osd-vpc" \
  --format="table(name,direction,priority,sourceRanges,targetTags,allowed)"

# Verify Cloud NAT is operational
gcloud compute routers nats describe osd-nat \
  --router=osd-nat-router \
  --region=us-central1

# Verify Private Google Access
gcloud compute networks subnets describe osd-node-subnet \
  --region=us-central1 \
  --format="get(privateIpGoogleAccess)"

# Test Google API connectivity from a pod
oc run api-test --image=registry.access.redhat.com/ubi9/ubi --rm -it --restart=Never -- \
  curl -sI https://storage.googleapis.com

# Verify NetworkPolicies
oc get networkpolicy -n my-namespace -o yaml

# Check BGP routes (if hybrid)
gcloud compute routers get-status osd-router \
  --region=us-central1 \
  --format="yaml(result.bgpPeerStatus)"

# Check VPN tunnel status
gcloud compute vpn-tunnels list --filter="region:us-central1" \
  --format="table(name,status,detailedStatus)"
```

---

## 15. Troubleshooting Decision Tree

Use this section as a flowchart. Start at the symptom, follow the branches.

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
│   └── Resolves external names OK? → DNS is fine, problem is routing/NAT
│
└── YES: DNS works but connection times out
    ├── Check Cloud NAT:
    │   gcloud compute routers nats describe osd-nat --router=osd-nat-router --region=us-central1
    │   ├── Status not healthy? → Cloud NAT misconfigured
    │   └── Status healthy? → Cloud NAT is fine
    │
    ├── Check routes:
    │   gcloud compute routes list --filter="network:osd-vpc"
    │   ├── Missing 0.0.0.0/0 → default-internet-gateway? → Route issue
    │   └── Default route exists? → Routes are fine
    │
    ├── Check firewall rules (egress):
    │   gcloud compute firewall-rules list --filter="network:osd-vpc AND direction:EGRESS"
    │   ├── Deny rules blocking outbound? → Fix firewall
    │   └── No blocking rules? → Firewall is fine
    │
    └── Check NetworkPolicy egress:
        ├── Default-deny egress without allow for 0.0.0.0/0:443? → Add allow rule
        └── No egress policy? → Problem is at GCP layer
```

### 15.2 External Users Can't Reach the App

```text
Symptom: curl https://my-app.apps.osd-cluster.example.com → timeout or error

Q: Does DNS resolve?
├── NO: dig my-app.apps.osd-cluster.example.com
│   ├── NXDOMAIN? → Check Cloud DNS for *.apps wildcard record
│   │   → Private cluster? DNS only resolves from within VPC
│   └── Wrong IP? → Check if LB IP changed, update Cloud DNS
│
└── YES: DNS resolves to LB IP
    ├── Check LB backend health:
    │   gcloud compute backend-services get-health <backend-svc> --global
    │   ├── All unhealthy? → Firewall rule blocking health check ranges
    │   │   → Check: allow 35.191.0.0/16 and 130.211.0.0/22 to NodePort range
    │   └── Some healthy? → LB is fine
    │
    ├── Check router pods: oc get pods -n openshift-ingress
    │   ├── Not running? → Check deployment
    │   └── Running? → Router is fine
    │
    ├── Check Route: oc get route my-app -n my-namespace
    │   ├── Not found? → Create the Route
    │   └── Route exists? → Check hostname matches
    │
    ├── Check Service endpoints: oc get endpoints my-app-svc -n my-namespace
    │   ├── No endpoints? → Pods aren't running or label mismatch
    │   └── Endpoints exist? → Service is fine
    │
    └── Check pod health: oc get pods -n my-namespace -l app=my-app
        ├── CrashLoopBackOff? → Check logs
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
    ├── Check Geneve firewall rule:
    │   gcloud compute firewall-rules describe osd-allow-geneve
    │   └── Missing or wrong? → Create rule for UDP 6081 between osd-worker tags
    │
    ├── Check OVN pods:
    │   oc get pods -n openshift-ovn-kubernetes -o wide
    │   └── ovnkube-node not running on either node? → OVN issue
    │
    └── Check MTU:
        └── Pod MTU should be ~1400 (Geneve adds overhead to 1460 GCP default)
            Check: oc exec pod-a -- ip link show eth0 | grep mtu
```

### 15.4 Pod Can't Reach On-Prem Database

```text
Symptom: oc exec db-client -- nc -zv 192.168.10.50 5432 → timeout

Q: Can the node reach on-prem?
├── Test from node: oc debug node/NODE -- chroot /host curl -s telnet://192.168.10.50:5432
│
├── NO (node can't reach on-prem either):
│   ├── Check VPC routes: gcloud compute routes list --filter="network:osd-vpc"
│   │   └── Missing route to 192.168.0.0/16? → Check Cloud Router / VPN
│   ├── Check VPN tunnel: gcloud compute vpn-tunnels describe osd-tunnel-0
│   │   └── Status != ESTABLISHED? → VPN tunnel issue
│   ├── Check BGP session: gcloud compute routers get-status osd-router
│   │   └── BGP status != UP? → Check on-prem BGP config
│   └── Check on-prem firewall: allows src 10.0.0.0/24 dst 192.168.10.50:5432?
│
└── YES (node reaches on-prem, but pod doesn't):
    ├── Check OVN SNAT:
    │   oc debug node/NODE -- chroot /host ovn-nbctl lr-nat-list ovn_cluster_router
    ├── Check NetworkPolicy egress:
    │   → Blocking 192.168.10.50:5432?
    └── Check on-prem firewall allows the node's source IP
        → Remember: pods appear as NODE IP due to SNAT
```

### 15.5 Cluster API Unreachable

```text
Symptom: oc get pods → connection refused / timeout

For Private Clusters:
├── Are you connected to the VPC? (VPN/Interconnect/bastion)
│   └── NO → You cannot reach a private API from the internet
│
├── Check DNS: dig api.osd-cluster.example.com
│   └── Resolves to internal LB VIP? → DNS is fine
│       Does NOT resolve? → Check Cloud DNS private zone
│
├── Check firewall rules:
│   └── Allow TCP 6443 from your source IP to tag:osd-master?
│
└── Check master node health:
    └── gcloud compute instances list --filter="tags.items:osd-master"
        └── All running? → Check API server pods on masters

For Public Clusters:
├── Check DNS: dig api.osd-cluster.example.com
│   └── Resolves? → DNS is fine
│
├── Check connectivity: curl -sI https://api.osd-cluster.example.com:6443
│   └── Connection refused? → API server issue
│       Timeout? → Network issue (firewall, proxy)
│
└── Check cluster status: ocm describe cluster <cluster-name>
    └── State = "error"? → Contact Red Hat support
```

---

## Appendix A: GCP vs. AWS Networking Comparison

For readers familiar with ROSA HCP / AWS networking:

| Concept | AWS (ROSA HCP) | GCP (OSD) |
|---------|---------------|----------|
| Virtual network | VPC (regional, has CIDR) | VPC Network (global, no VPC-level CIDR) |
| Network segment | Subnet (AZ-scoped) | Subnet (regional, spans zones) |
| Instance firewall | Security Group (per-ENI, stateful) | Firewall Rule (VPC-level, priority-based, tag-targeted) |
| Subnet firewall | NACL (stateless, per-subnet) | No equivalent (use firewall rules with IP ranges) |
| Virtual NIC | ENI (Elastic Network Interface) | nic0 (Network Interface) |
| NIC technology | ENA / SR-IOV / Nitro | Virtio-Net / gVNIC / Andromeda |
| Outbound NAT | NAT Gateway (per-AZ, separate resource) | Cloud NAT (regional, software-defined in Andromeda) |
| Dynamic routing | Transit Gateway (hub) | Cloud Router (distributed, per-VPC) |
| Dedicated link | Direct Connect | Cloud Interconnect |
| VPN | Site-to-Site VPN + TGW | HA VPN + Cloud Router |
| Private service access | PrivateLink (VPC Endpoint) | Private Service Connect |
| Managed DNS | Route 53 | Cloud DNS |
| Health check IPs | NLB checks from NLB subnet | 35.191.0.0/16 and 130.211.0.0/22 |
| Control plane model | In Red Hat's VPC (PrivateLink) | In your VPC (same network) |
| Cross-zone cost | Data transfer charges | Free within region |

---

## Appendix B: Glossary Quick Reference

| Term | Layer | One-Line Definition |
|------|-------|-------------------|
| Andromeda | SDN | Google's software-defined networking platform on every host |
| ASN | BGP | Unique number identifying an autonomous system (network) |
| BGP | L3 | Routing protocol for exchanging routes between networks |
| br-int | OVS | OVN's integration bridge connecting all local pods |
| CIDR | L3 | Notation for IP ranges (e.g., 10.0.0.0/16) |
| Cloud DNS | GCP | Google's managed DNS service (public and private zones) |
| Cloud Interconnect | GCP | Dedicated physical link to Google's network |
| Cloud NAT | GCP | Managed NAT service for outbound internet (runs on Andromeda) |
| Cloud Router | GCP | Software-defined router with BGP support |
| ClusterIP | K8s | Virtual IP for a Kubernetes Service, exists only as DNAT rules |
| CNI | K8s | Standard interface between container runtime and network plugin |
| CoreDNS | K8s | DNS server inside the cluster resolving service names |
| CRI-O | K8s | Container runtime used by OpenShift |
| DNAT | L3 | Destination NAT — rewriting the destination IP of a packet |
| eth0 | Linux | Primary network interface inside a Linux system |
| Geneve | L2.5 | Tunnel encapsulation protocol for overlay networks (UDP 6081) |
| gVNIC | GCP | Google Virtual NIC — high-performance virtual network adapter |
| HA VPN | GCP | High-availability VPN with 99.99% SLA |
| HAProxy | L7 | The reverse proxy that powers the OpenShift router |
| Jupiter | GCP | Google's petabit-scale data center network fabric |
| kubelet | K8s | Agent on each node that manages pods |
| MED | BGP | Multi-Exit Discriminator — preference value for path selection |
| MTU | L2 | Maximum Transmission Unit — max packet size |
| Multus | K8s | Meta-CNI for attaching multiple networks to a pod |
| Network Tag | GCP | Label applied to VMs for firewall rule targeting |
| nic0 | GCP | Primary network interface on a Compute Engine VM |
| NodePort | K8s | Port opened on every node for external Service access |
| OSD | Red Hat | OpenShift Dedicated — managed OpenShift service |
| OVN | SDN | Open Virtual Network — virtual networking for OpenShift |
| OVS | SDN | Open vSwitch — virtual switch in the Linux kernel |
| PGA | GCP | Private Google Access — access Google APIs without external IPs |
| PSC | GCP | Private Service Connect — private endpoints for services |
| Route | OCP | OpenShift object defining hostname → Service mapping |
| SG | GCP | N/A — GCP uses firewall rules instead of security groups |
| Shared VPC | GCP | VPC shared across multiple GCP projects |
| SNAT | L3 | Source NAT — rewriting the source IP of a packet |
| TLS | L6 | Transport Layer Security — encrypts data in transit |
| veth | Linux | Virtual ethernet pair — connects pod namespace to bridge |
| Virtio-Net | GCP | Default paravirtualized NIC driver for Compute Engine VMs |
| VPC Network | GCP | Virtual Private Cloud — global isolated network in GCP |
| VPC Peering | GCP | Direct connection between two VPC networks |

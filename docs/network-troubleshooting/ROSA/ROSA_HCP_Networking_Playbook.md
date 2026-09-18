# ROSA HCP Networking Playbook

A complete guide to networking in Red Hat OpenShift Service on AWS with Hosted Control Planes (ROSA HCP). This document takes you from zero networking knowledge through packet-level understanding of every traffic flow.

---

## Table of Contents

1. [Introduction & How to Read This Document](#1-introduction--how-to-read-this-document)
2. [Networking Fundamentals](#2-networking-fundamentals)
3. [AWS Networking Fundamentals](#3-aws-networking-fundamentals)
4. [EC2 Virtualization & The Nitro System](#4-ec2-virtualization--the-nitro-system)
5. [Kubernetes Networking Fundamentals](#5-kubernetes-networking-fundamentals)
6. [OpenShift Networking Layer](#6-openshift-networking-layer)
7. [ROSA HCP Architecture — The Complete Picture](#7-rosa-hcp-architecture--the-complete-picture)
8. [How Apps Are Exposed in ROSA HCP](#8-how-apps-are-exposed-in-rosa-hcp)
9. [IP Address Architecture](#9-ip-address-architecture)
10. [BGP and Hybrid Networking](#10-bgp-and-hybrid-networking)
11. [DNS Architecture in ROSA HCP](#11-dns-architecture-in-rosa-hcp)
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
| **Intermediate** — knows TCP/IP, new to AWS/K8s | Section 3 | Understand how AWS and Kubernetes networking layers compose |
| **Advanced** — knows K8s, needs ROSA HCP depth | Section 7 | Packet-level understanding of every ROSA HCP traffic flow |

### Learning Path

```text
Section 2: Networking Fundamentals
    "What is a packet? What is an IP address?"
        |
        v
Section 3: AWS Networking Fundamentals
    "What is a VPC? What is an ENI?"
        |
        v
Section 4: EC2 Virtualization & Nitro
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
Section 7: ROSA HCP Architecture
    "How does the hosted control plane connect to my workers?"
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
- **Command blocks** are copy-paste ready for ROSA HCP clusters
- Arrows in diagrams: `-->` means "packet travels to", `==>` means "encapsulated tunnel"

---

## 2. Networking Fundamentals

This section is for readers who are new to networking. If you already understand TCP/IP, subnets, and routing, skip to Section 3.

### 2.1 What Is a Network?

A network is a group of computers that can send data to each other. Your home Wi-Fi is a network. The internet is a network of networks.

Every device on a network needs two things:
1. **An address** — so other devices can find it (like a mailing address)
2. **A way to send data** — a physical or virtual connection (like a road)

> **WHY:** ROSA HCP runs your applications on computers (EC2 instances) inside Amazon's data centers. These computers need to talk to each other, to Red Hat's control plane, and to the internet. Understanding networking is understanding how that communication happens.

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
| **Public** | 54.23.100.5 | Everyone on the internet |
| **Private** | 10.0.1.42, 172.16.0.5, 192.168.1.1 | Only devices on the same private network |

**Private IP ranges (RFC 1918):**

| Range | Size | Common Use |
|-------|------|-----------|
| 10.0.0.0 – 10.255.255.255 | 16 million addresses | Cloud VPCs, large networks |
| 172.16.0.0 – 172.31.255.255 | 1 million addresses | Medium networks |
| 192.168.0.0 – 192.168.255.255 | 65,000 addresses | Home networks |

> **WHY:** ROSA HCP uses private IP addresses for everything inside the VPC — worker nodes, pods, services. Public IPs are only assigned to load balancers that need to accept traffic from the internet. Understanding which IPs are private vs. public tells you what can be reached from where.

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

> **WHY:** ROSA HCP uses multiple CIDR ranges for different purposes. The VPC might be 10.0.0.0/16, the pod network might be 10.128.0.0/14, and the service network might be 172.30.0.0/16. If these overlap, packets get misrouted and things break. Understanding CIDR tells you whether two ranges conflict.

### 2.4 The TCP/IP Stack

When your browser loads a web page, the data doesn't teleport. It passes through a stack of layers, each adding its own envelope (called a header) around the data. This is like putting a letter in an envelope, then putting that in a shipping package, then putting that in a mailbag.

```text
Layer 7 — Application    HTTP request: "GET /index.html"
    |                         |
    v                         v
Layer 4 — Transport       TCP header added: source port 54321, dest port 443
    |                         |
    v                         v
Layer 3 — Network         IP header added: source 10.0.1.42, dest 54.23.100.5
    |                         |
    v                         v
Layer 2 — Data Link       Ethernet header added: source MAC, dest MAC
    |                         |
    v                         v
Layer 1 — Physical        Electrical signals on the wire / radio waves
```

**Each layer does one job:**

**Layer 1 — Physical:** The actual cables, radio waves, or fiber optics that carry signals.

> **WHY:** In AWS, you never touch Layer 1. Amazon owns the physical hardware. But the performance of your network (bandwidth, latency) is determined by the physical infrastructure underneath.

**Layer 2 — Data Link:** Handles communication between devices on the same local network segment using MAC addresses (hardware addresses burned into every network card).

> **WHY:** Inside an AWS data center, Layer 2 is how the physical servers communicate on the same rack. ROSA HCP's overlay network (Geneve) creates a virtual Layer 2 on top of the physical Layer 3, so pods think they're on the same local network even when they're on different physical servers.

**Layer 3 — Network (IP):** Handles routing packets between different networks using IP addresses. This is where routing decisions happen — "which way should this packet go?"

> **WHY:** This is the most important layer for ROSA HCP. Every routing decision — pod to pod, pod to internet, pod to on-prem database — happens at Layer 3. Security groups, NACLs, route tables, NAT gateways, and transit gateways all operate at Layer 3.

**Layer 4 — Transport (TCP/UDP):** Handles reliable delivery (TCP) or fast delivery (UDP) between specific applications using port numbers. Port 443 = HTTPS, Port 80 = HTTP, Port 5432 = PostgreSQL.

> **WHY:** Security groups in AWS filter by port number, which is a Layer 4 concept. When you create a security group rule allowing port 443, you're making a Layer 4 decision. Kubernetes Services map one port to another (e.g., external port 80 → pod port 8080), which is also Layer 4.

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
    AWS supports jumbo frames of 9001 bytes within VPC
```

> **WHY:** Every time a packet passes through a ROSA HCP component — a security group, a NAT gateway, a load balancer, an OVN router — the headers get inspected and possibly modified. Understanding packet structure is understanding what each component can see and change.

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

> **WHY:** VPC route tables, TGW route tables, and the Linux routing table inside every pod all work this way. When troubleshooting "why can't pod A reach service B," the answer is almost always in a routing table somewhere. ROSA HCP has routing tables at the VPC level (AWS), the node level (Linux), and the overlay level (OVN).

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

> **WHY:** ROSA HCP uses DNS everywhere. Inside the cluster, CoreDNS resolves service names (my-service.my-namespace.svc.cluster.local) to ClusterIP addresses. Outside the cluster, Route 53 resolves *.apps.cluster.example.com to the load balancer's IP. Private ROSA HCP clusters use split-horizon DNS so the same name resolves differently depending on whether you're inside or outside the VPC.

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

> **WHY:** ROSA HCP uses both types. The AWS NLB (Network Load Balancer) does L4 load balancing — it sees IP addresses and ports but not HTTP headers. The OpenShift router (HAProxy) does L7 load balancing — it reads the HTTP Host header to route requests to the correct application. These work together: NLB → HAProxy Router → Application Pod.

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

> **WHY:** ROSA HCP OpenShift Routes support all three TLS strategies. Edge termination is simplest — the router handles certificates. Passthrough is required when the application must control its own certificates (e.g., mutual TLS). Re-encrypt adds defense-in-depth — traffic is encrypted even inside the cluster network.

---

## 3. AWS Networking Fundamentals

This section explains every AWS networking component that ROSA HCP uses. Each component has a WHY block explaining its role in a ROSA HCP cluster.

### 3.1 VPC (Virtual Private Cloud)

A **VPC** is your own private network inside AWS. It's logically isolated — no other AWS customer can see or access your VPC's resources unless you explicitly allow it.

```text
+---------------------------------------------------------------+
|                        AWS Region (us-east-1)                  |
|                                                                |
|  +----------------------------------------------------------+ |
|  |                    Your VPC (10.0.0.0/16)                 | |
|  |                                                           | |
|  |  You control:                                             | |
|  |    - IP address range (CIDR)                              | |
|  |    - Subnets                                              | |
|  |    - Route tables                                         | |
|  |    - Security groups                                      | |
|  |    - Network ACLs                                         | |
|  |    - Internet connectivity                                | |
|  |                                                           | |
|  +----------------------------------------------------------+ |
|                                                                |
|  +----------------------------------------------------------+ |
|  |              Someone Else's VPC (172.16.0.0/16)           | |
|  |              (completely isolated from yours)             | |
|  +----------------------------------------------------------+ |
|                                                                |
+---------------------------------------------------------------+
```

> **WHY:** ROSA HCP deploys your worker nodes inside a VPC you own. This gives you full control over network isolation, IP addressing, and connectivity. Red Hat's control plane runs in a separate VPC in Red Hat's AWS account — the two VPCs communicate only through PrivateLink, a tightly scoped private tunnel.

### 3.2 Subnets (Public vs. Private)

A **subnet** is a partition of your VPC's IP range, placed in a specific Availability Zone (data center).

**Public subnet:** Has a route to an Internet Gateway. Resources here can have public IPs.
**Private subnet:** No route to an Internet Gateway. Resources here are hidden from the internet.

```text
+------------------------------------------------------------------+
|                    VPC: 10.0.0.0/16                              |
|                                                                   |
|  Availability Zone: us-east-1a    Availability Zone: us-east-1b  |
|  +----------------------------+   +----------------------------+ |
|  | Public Subnet              |   | Public Subnet              | |
|  | 10.0.1.0/24                |   | 10.0.3.0/24                | |
|  |                            |   |                            | |
|  | - NLB (public IP)          |   | - NLB (public IP)          | |
|  | - NAT Gateway (public IP)  |   | - NAT Gateway (public IP)  | |
|  |                            |   |                            | |
|  | Route: 0.0.0.0/0 → IGW    |   | Route: 0.0.0.0/0 → IGW    | |
|  +----------------------------+   +----------------------------+ |
|                                                                   |
|  +----------------------------+   +----------------------------+ |
|  | Private Subnet             |   | Private Subnet             | |
|  | 10.0.2.0/24                |   | 10.0.4.0/24                | |
|  |                            |   |                            | |
|  | - Worker Node (10.0.2.10)  |   | - Worker Node (10.0.4.10)  | |
|  | - Worker Node (10.0.2.11)  |   | - Worker Node (10.0.4.11)  | |
|  |                            |   |                            | |
|  | Route: 0.0.0.0/0 → NAT GW |   | Route: 0.0.0.0/0 → NAT GW | |
|  +----------------------------+   +----------------------------+ |
+------------------------------------------------------------------+
```

> **WHY:** ROSA HCP worker nodes go in private subnets — they should never have public IPs or be directly reachable from the internet. Load balancers go in public subnets (for public clusters) because they need public IPs to accept traffic from the internet. NAT Gateways go in public subnets because they need public IPs to translate outbound traffic. This separation is a security boundary: even if a pod is compromised, the attacker can't directly reach the worker node from the internet.

### 3.3 ENI (Elastic Network Interface)

An **ENI** is a virtual network card. Every EC2 instance (including ROSA HCP worker nodes) has at least one ENI. The ENI is what connects the instance to the VPC network.

```text
+---------------------------+
|   EC2 Instance            |
|   (ROSA Worker Node)      |
|                           |
|   +-------------------+   |
|   | Linux OS          |   |       +------------------+
|   |                   |   |       |                  |
|   |  eth0 ==================== ENI eni-0abc123       |
|   |  (10.0.2.10)      |   |       | (10.0.2.10)      |
|   |                   |   |       | Subnet: 10.0.2.0 |
|   +-------------------+   |       | SG: sg-abc123    |
|                           |       +------------------+
+---------------------------+            |
                                         |
                                    VPC Network
                                    (10.0.0.0/16)
```

An ENI has:
- **One or more private IP addresses** from the subnet
- **A MAC address** (virtual)
- **One or more security groups** attached
- **Optional: a public IP or Elastic IP**

The Linux interface `eth0` inside the instance **is** the ENI — they're the same thing seen from different sides. From AWS's perspective, it's an ENI. From Linux's perspective, it's eth0.

> **WHY:** Every ROSA HCP worker node is an EC2 instance with an ENI. The ENI determines the node's IP address, which subnet it's in, and which security groups apply. When a pod sends a packet that leaves the node, it exits through the ENI. Understanding ENIs is understanding the boundary between the overlay network (Kubernetes) and the underlay network (AWS VPC). Each ENI can have multiple secondary IPs — this is used by some CNI plugins to assign IPs to pods directly from the VPC (though OVN-Kubernetes uses overlay addressing instead).

### 3.4 Security Groups

A **security group** is a virtual firewall attached to an ENI. It controls which traffic is allowed in (ingress) and out (egress). Security groups are **stateful** — if you allow traffic in, the response is automatically allowed out.

```text
Inbound Rules (Ingress):
+----------+-----------+----------+---------------------+
| Protocol | Port      | Source   | Description         |
+----------+-----------+----------+---------------------+
| TCP      | 6443      | sg-ctrl  | API server via PL   |
| TCP      | 10250     | sg-ctrl  | Kubelet from CP     |
| TCP      | 30000-32767| sg-nlb  | NodePort range      |
| TCP      | 4789      | self     | VXLAN overlay       |
| UDP      | 6081      | self     | Geneve overlay      |
| TCP      | 9000-9999 | self     | Node-to-node        |
+----------+-----------+----------+---------------------+

Outbound Rules (Egress):
+----------+-----------+----------+---------------------+
| Protocol | Port      | Dest     | Description         |
+----------+-----------+----------+---------------------+
| All      | All       | 0.0.0.0/0| Allow all outbound  |
+----------+-----------+----------+---------------------+
```

**Stateful means:**

```text
1. Pod sends request to internet (outbound)
   Packet: src=10.0.2.10:54321 → dst=93.184.216.34:443
   SG checks OUTBOUND rules → ALLOWED

2. Internet sends response (inbound)
   Packet: src=93.184.216.34:443 → dst=10.0.2.10:54321
   SG sees this is a RESPONSE to #1 → AUTOMATICALLY ALLOWED
   (no inbound rule needed for return traffic)
```

> **WHY:** Security groups are the primary network firewall for ROSA HCP worker nodes. Red Hat configures default security groups during cluster creation that allow control plane communication (port 6443 for API, port 10250 for kubelet), overlay traffic (UDP 6081 for Geneve), and node-to-node communication. If you tighten security group rules incorrectly, the control plane loses contact with workers and the cluster goes unhealthy.

### 3.5 Network ACLs (NACLs)

A **NACL** is a firewall at the subnet level (not the instance level). NACLs are **stateless** — you must write rules for both directions explicitly.

```text
Security Group vs. NACL:

                   +-------- NACL (subnet boundary) --------+
                   |                                         |
                   |    +---- SG (instance boundary) ----+   |
                   |    |                                |   |
  Packet ------->  NACL check -------> SG check -------> Instance
  (inbound)        Rule 100: ALLOW     Rule: ALLOW TCP 443
                   Rule *: DENY        (stateful: response auto-allowed)
                   (stateless: need
                    outbound rule too)
```

| Feature | Security Group | NACL |
|---------|---------------|------|
| Applies to | ENI (instance) | Subnet |
| Stateful? | Yes (return traffic auto-allowed) | No (must allow both directions) |
| Rules | Allow only | Allow and Deny |
| Evaluation | All rules evaluated | Rules evaluated in order (first match wins) |
| Default | Deny all inbound, allow all outbound | Allow all |

> **WHY:** NACLs add a second layer of defense. Even if a security group is misconfigured to be too permissive, a NACL can block traffic at the subnet boundary. For ROSA HCP private clusters, NACLs can enforce "no internet inbound" at the subnet level, providing defense-in-depth beyond security groups. In practice, most ROSA HCP deployments rely on security groups and leave NACLs at their default (allow all) because security groups are easier to manage (stateful).

### 3.6 Internet Gateway (IGW)

An **Internet Gateway** connects your VPC to the internet. It's the doorway between your private network and the public internet.

```text
Internet
    |
    v
+-------+
|  IGW  |  <--- Internet Gateway (attached to VPC)
+-------+
    |
    v
+------------------+
| Public Subnet    |
| (has route to    |
|  IGW for         |
|  0.0.0.0/0)      |
+------------------+

Private subnets do NOT have a route to the IGW.
That's what makes them private.
```

The IGW does two things:
1. Performs 1:1 NAT between public IPs and private IPs for instances with public IPs
2. Acts as the target in route tables for internet-bound traffic

> **WHY:** ROSA HCP public clusters need an IGW so load balancers in public subnets can accept traffic from the internet. Even private clusters need an IGW (indirectly) because the NAT Gateway in the public subnet uses the IGW to send outbound traffic to the internet. Without an IGW, nothing in the VPC can reach the internet in either direction.

### 3.7 NAT Gateway

A **NAT (Network Address Translation) Gateway** allows resources in private subnets to access the internet for outbound traffic, without allowing inbound connections from the internet.

```text
Pod (10.128.0.15) sends request to pypi.org:
                                                              Internet
                                                                 ^
Step 1: Pod → Node                                               |
  src: 10.128.0.15:54321                                    +--------+
  dst: 151.101.0.223:443                                    |  IGW   |
         |                                                  +--------+
         v                                                       ^
Step 2: OVN SNATs pod IP to node IP                              |
  src: 10.0.2.10:54321    (node's private IP)               +--------+
  dst: 151.101.0.223:443                                    | NAT GW |
         |                                                  | EIP:   |
         v                                                  | 54.x.y |
Step 3: NAT Gateway SNATs node IP to Elastic IP             +--------+
  src: 54.x.y.z:12345     (NAT GW's public IP)                  ^
  dst: 151.101.0.223:443                                         |
         |                                              +------------------+
         +--- goes to internet via IGW                  | Private Subnet   |
                                                        | Worker: 10.0.2.10|
                                                        +------------------+
```

The NAT Gateway replaces the source IP with its own Elastic IP. The response comes back to the NAT Gateway's Elastic IP, which reverse-translates back to the original private IP.

> **WHY:** ROSA HCP worker nodes are in private subnets (no public IPs). But pods need to pull container images from registries (quay.io, ECR), download dependencies, call external APIs, and send telemetry. The NAT Gateway provides this outbound internet access while keeping worker nodes unreachable from the internet. Without a NAT Gateway (and without VPC endpoints), a private ROSA HCP cluster can't pull images or reach any external service.

### 3.8 Route Tables

A **route table** is a set of rules that determine where network traffic goes. Every subnet is associated with exactly one route table.

```text
Public Subnet Route Table:
+-------------------+--------------+----------------------------+
| Destination       | Target       | Meaning                    |
+-------------------+--------------+----------------------------+
| 10.0.0.0/16       | local        | Stay in VPC                |
| 0.0.0.0/0         | igw-abc123   | Everything else → internet |
+-------------------+--------------+----------------------------+

Private Subnet Route Table:
+-------------------+--------------+----------------------------+
| Destination       | Target       | Meaning                    |
+-------------------+--------------+----------------------------+
| 10.0.0.0/16       | local        | Stay in VPC                |
| 192.168.0.0/16    | tgw-xyz789   | On-prem → Transit Gateway  |
| 0.0.0.0/0         | nat-def456   | Everything else → NAT GW   |
+-------------------+--------------+----------------------------+
```

The `local` route is automatically added and cannot be removed. It ensures all traffic within the VPC CIDR stays inside the VPC.

> **WHY:** Route tables determine the path every packet takes after it leaves a worker node's ENI. If a route to the NAT Gateway is missing, pods can't reach the internet. If a route to the Transit Gateway is missing, pods can't reach on-prem networks. Route table misconfiguration is one of the most common causes of connectivity failures in ROSA HCP.

### 3.9 Elastic IP (EIP)

An **Elastic IP** is a static public IPv4 address that you own until you release it. Unlike auto-assigned public IPs, an Elastic IP doesn't change when you stop and start an instance.

> **WHY:** NAT Gateways require an Elastic IP. This gives your ROSA HCP cluster a stable, predictable source IP for outbound internet traffic. If your company's firewall must allowlist specific source IPs (e.g., "only allow connections from our AWS cluster"), you provide the NAT Gateway's Elastic IP. Without a stable IP, firewall rules would break every time the NAT Gateway's address changed.

### 3.10 AWS PrivateLink

**PrivateLink** creates a private connection between two VPCs (or a VPC and an AWS service) that never traverses the public internet. Traffic stays on AWS's internal backbone network.

```text
+----------------------------------+       +----------------------------------+
| Red Hat's AWS Account            |       | Your AWS Account                 |
|                                  |       |                                  |
| Control Plane VPC                |       | Workload VPC                     |
|                                  |       |                                  |
|  +-----------+    +----------+   |       |  +----------+    +------------+  |
|  | API Server|--->| NLB      |   |       |  | VPC      |--->| Worker     |  |
|  | etcd      |    | (service |------PL------| Endpoint |    | Nodes      |  |
|  | Controllers|   | provider)|   |       |  | (ENI)    |    | (kubelets) |  |
|  +-----------+    +----------+   |       |  +----------+    +------------+  |
|                                  |       |                                  |
+----------------------------------+       +----------------------------------+

PL = PrivateLink connection
    - No public IPs involved
    - Traffic never leaves AWS backbone
    - Unidirectional: consumer initiates, provider responds
```

How it works:
1. Red Hat creates a **VPC Endpoint Service** (the provider) backed by an NLB in their VPC
2. Your VPC creates a **VPC Endpoint** (the consumer) — this creates an ENI in your subnet
3. Traffic from your VPC goes to the ENI, which tunnels it privately to Red Hat's NLB
4. Return traffic follows the same tunnel back

> **WHY:** This is the most critical networking component in ROSA HCP. The entire control plane (API server, etcd, controllers) runs in Red Hat's VPC, not yours. PrivateLink is how the control plane communicates with your worker nodes' kubelets. Without PrivateLink, `oc` commands would fail, pods wouldn't be scheduled, and the cluster would be non-functional. PrivateLink is preferred over VPC peering or public endpoints because it provides one-way access (Red Hat can reach your workers, but you can't poke around Red Hat's VPC) and doesn't require overlapping CIDR ranges to be avoided.

### 3.11 Transit Gateway (TGW)

A **Transit Gateway** is a network hub that connects multiple VPCs and on-premises networks. Think of it as a router in the cloud.

```text
                          +-------------+
                          | Transit     |
                +-------->| Gateway     |<--------+
                |         | (TGW)       |         |
                |         +------+------+         |
                |                |                |
                v                v                v
        +----------+     +----------+     +------------------+
        | VPC A    |     | VPC B    |     | On-Prem Network  |
        | ROSA HCP |     | Shared   |     | (via VPN or      |
        | Cluster  |     | Services |     |  Direct Connect) |
        +----------+     +----------+     +------------------+
```

> **WHY:** If your ROSA HCP pods need to reach on-premises databases, monitoring systems, or other internal services, a Transit Gateway provides that connectivity. It's also used to connect multiple VPCs (e.g., a ROSA cluster VPC to a shared services VPC). Without TGW, the only options are VPC Peering (which doesn't scale and doesn't support transitive routing) or going over the public internet (which is slower and less secure).

### 3.12 VPC Endpoints

A **VPC Endpoint** lets your VPC connect directly to AWS services (like S3, ECR, STS) without going through the NAT Gateway and internet.

**Two types:**

| Type | How It Works | Used For |
|------|-------------|----------|
| **Gateway Endpoint** | Entry in route table | S3, DynamoDB |
| **Interface Endpoint** | ENI in your subnet with private IP | ECR, STS, EC2, ELB, CloudWatch, etc. |

```text
Without VPC Endpoint:                    With VPC Endpoint:

Pod → Node → NAT GW → IGW →             Pod → Node → VPC Endpoint ENI →
Internet → S3 (public endpoint)          S3 (private, stays in AWS backbone)

Cost: NAT GW data processing fees       Cost: Endpoint hourly + data fees
Latency: Higher (internet round trip)    Latency: Lower (stays in AWS)
Security: Traverses internet             Security: Never leaves AWS network
```

> **WHY:** ROSA HCP worker nodes constantly pull container images from ECR (or Quay via the internet), call STS for IAM role assumption (used by the OIDC provider), and interact with EC2/ELB APIs for node and load balancer management. For private clusters without internet egress, VPC Endpoints for these services are mandatory — without them, the cluster cannot function. Even for clusters with NAT Gateway access, VPC Endpoints reduce costs (NAT GW charges per GB processed) and improve security (traffic stays on the AWS backbone).

---

## 4. EC2 Virtualization & The Nitro System

This section explains how AWS turns physical hardware into the virtual machines that run ROSA HCP worker nodes. Understanding this layer helps you reason about network performance and how packets actually move.

### 4.1 The Nitro System

AWS's **Nitro System** is the hardware and software platform that powers EC2 instances. It consists of custom-built hardware cards that offload networking, storage, and security from the main CPU.

```text
Physical Server in AWS Data Center:
+------------------------------------------------------------------+
|                                                                    |
|  +---------------------------+   +----------------------------+   |
|  | Main CPU (Intel/AMD/ARM)  |   | Nitro Card (custom ASIC)   |   |
|  |                           |   |                            |   |
|  | Runs your VMs (instances) |   | Handles:                   |   |
|  | and your code             |   |  - Network I/O (packets)   |   |
|  |                           |   |  - EBS storage I/O         |   |
|  |                           |   |  - Instance management     |   |
|  |                           |   |  - Security group filtering|   |
|  +---------------------------+   +----------------------------+   |
|                                            |                       |
|                                            |                       |
|  +---------------------------+   +----------------------------+   |
|  | Physical Memory (RAM)     |   | Physical NIC               |   |
|  | Divided among instances   |   | Connected to AWS network   |   |
|  +---------------------------+   +----------------------------+   |
|                                                                    |
+------------------------------------------------------------------+
```

**Key insight:** The Nitro card handles networking in hardware, not software. Security group rules are evaluated on the Nitro card before packets reach the instance's virtual CPU. This means security groups have near-zero performance cost.

> **WHY:** ROSA HCP worker nodes are EC2 instances running on Nitro. The Nitro card is what enforces security groups, processes VPC mirroring, and handles the ENI. When you see "packets per second" limits on an instance type, that's the Nitro card's throughput. Choosing the right EC2 instance type for your ROSA worker pool means understanding that network performance is determined by the Nitro hardware, not the CPU.

### 4.2 How ENI Maps to eth0

From the outside (AWS), you see an ENI. From the inside (Linux), you see eth0. They're the same thing:

```text
AWS Perspective:                    Linux Perspective (inside instance):
+-----------------+                 +-------------------+
| ENI             |                 | $ ip addr show    |
| eni-0abc123def  |                 | eth0:             |
| IP: 10.0.2.10  | <==============>|   10.0.2.10/24    |
| MAC: 02:ab:... |                 |   MAC: 02:ab:...  |
| SG: sg-abc123  |                 |                   |
| Subnet: sub-x  |                 | $ ip route show   |
+-----------------+                 | default via       |
                                    |   10.0.2.1 eth0   |
                                    +-------------------+
```

The Nitro hypervisor presents the ENI to the guest OS as a standard network interface using **SR-IOV** (Single Root I/O Virtualization) and the **ENA** (Elastic Network Adapter) driver.

### 4.3 SR-IOV and ENA

**SR-IOV (Single Root I/O Virtualization)** is a hardware technology that allows a single physical NIC to appear as multiple virtual NICs — one for each VM. This gives each VM near-direct access to the hardware, bypassing the hypervisor for data-plane traffic.

**ENA (Elastic Network Adapter)** is AWS's custom network driver that runs inside the instance to talk to the Nitro card via SR-IOV.

```text
Traditional Virtualization:           SR-IOV (what AWS uses):

  VM1    VM2    VM3                   VM1    VM2    VM3
   |      |      |                    |      |      |
   v      v      v                    v      v      v
+------------------------+          +---+  +---+  +---+
|    Hypervisor          |          | VF|  | VF|  | VF|  Virtual Functions
|    (software bridge -  |          +---+  +---+  +---+
|     SLOW, CPU heavy)   |            |      |      |
+------------------------+          +------------------------+
         |                          |   Physical NIC (PF)    |
+------------------------+          +------------------------+
|   Physical NIC         |
+------------------------+

VF = Virtual Function (hardware-partitioned slice of the NIC)
PF = Physical Function (the real NIC)
```

With SR-IOV:
- Each VM gets a hardware Virtual Function (VF) — a real slice of the physical NIC
- Packets go directly from the VF to the VM, bypassing the hypervisor
- The Nitro card acts as the PF (Physical Function), managing the VFs

> **WHY:** This is why ROSA HCP worker nodes can achieve high network throughput. The ENA driver and SR-IOV mean that network packets don't go through the hypervisor's software bridge — they go directly from the physical NIC to the instance. The Nitro card evaluates security group rules, handles VXLAN/Geneve encapsulation for VPC traffic between hosts, and manages ENI features, all in hardware. If you're troubleshooting performance, understanding that the Nitro card has per-instance throughput limits (based on instance type) is critical.

### 4.4 Packet Flow: Physical NIC to Pod

Here is the complete path a packet takes from the AWS physical network to a pod running in ROSA HCP:

```text
INBOUND PACKET (from internet to pod):

+-------------+     +------------------+     +------------------+
| AWS Physical| --> | Nitro Card       | --> | ENI              |
| Network     |     |                  |     | (eni-0abc123)    |
|             |     | 1. Receives      |     |                  |
| (fiber,     |     |    raw frames    |     | 2. SG evaluation |
|  switches)  |     |    from switch   |     |    (stateful)    |
+-------------+     +------------------+     +------------------+
                                                      |
                                              +-------v--------+
                                              | eth0           |
                                              | (ENA driver)   |
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

1. **Physical network**: Packet arrives at the physical NIC on the AWS server via the data center's network fabric (spine-leaf switches)
2. **Nitro card**: Evaluates security group rules in hardware. If the packet is denied by a SG rule, it's dropped here — the instance CPU never sees it
3. **ENA driver (eth0)**: The packet appears on the Linux network interface eth0 inside the instance
4. **Linux kernel routing**: The kernel's routing table determines where the packet goes next. For pod-bound traffic, it goes to the OVN bridge (br-int)
5. **OVN bridge (br-int)**: OVN's OpenFlow rules match the destination IP to a specific pod and forward the packet to the correct veth pair
6. **Pod**: The packet arrives on the pod's eth0 interface (which is one end of a veth pair; the other end is on br-int)

> **WHY:** This is the complete chain that determines latency, throughput, and where security filtering happens. If a packet is blocked, understanding this chain tells you where to look: SG on the Nitro card? Linux iptables rules? OVN flow rules? Network Policy enforcement in OVN? Each layer can be independently diagnosed.

---

## 5. Kubernetes Networking Fundamentals

Kubernetes has a specific networking model with guarantees that every network implementation must satisfy. This section explains that model and how it maps to ROSA HCP.

### 5.1 The Pod Networking Model

Kubernetes makes three fundamental guarantees about networking:

1. **Every pod gets its own IP address** — pods don't share IPs with other pods
2. **Pods can communicate with any other pod without NAT** — a pod's IP is routable to all other pods
3. **Agents on a node (kubelet, node-exporter) can communicate with all pods on that node**

```text
Node 1 (10.0.2.10)                    Node 2 (10.0.4.10)
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

> **WHY:** This flat networking model simplifies application development — applications don't need to know whether they're talking to a pod on the same node or a different node. It also makes NetworkPolicies possible, because every pod has a unique identity (its IP). ROSA HCP uses OVN-Kubernetes as the CNI plugin to implement this model using Geneve tunnels between nodes.

### 5.2 Services

A **Service** is a stable virtual IP address (called a **ClusterIP**) that load-balances traffic across a set of pods. Pods come and go (scaling, crashes, deployments), but the Service IP stays the same.

```text
Without Services:                    With Services:
                                     Service: my-app-svc (172.30.45.67)
Client must track every pod IP:           |
  10.128.0.15 (might die!)               v
  10.128.0.16 (might die!)          +----------+
  10.128.2.33 (might die!)          | kube-proxy|  or OVN load-balancer
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
| **LoadBalancer** | Creates an AWS NLB/ALB that points to NodePorts | The internet (or VPC, if internal) |

> **WHY:** Services are how ROSA HCP applications find each other. Instead of hard-coding pod IPs (which change constantly), applications connect to service names (which resolve to ClusterIPs via DNS). When a Deployment scales from 3 to 10 pods, the Service automatically includes the new pods. The OpenShift router itself runs behind a LoadBalancer-type Service — that's how external traffic enters the cluster.

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

> **WHY:** In ROSA HCP, OpenShift **Routes** serve the same purpose as Ingress objects (and are actually older — Routes predate Kubernetes Ingress). The default Ingress Controller is the OpenShift Router (HAProxy). When you create a Route, the router configures HAProxy to accept traffic for that hostname and forward it to the correct Service. External traffic reaches the router because the router runs behind an AWS NLB (LoadBalancer Service). ROSA HCP also supports Kubernetes Ingress objects — they're translated to Routes internally.

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

> **WHY:** NetworkPolicies implement zero-trust networking inside the cluster. Without them, any compromised pod can talk to every other pod — including pods in other namespaces running different applications. In ROSA HCP, OVN-Kubernetes enforces NetworkPolicies in the OVN logical flows, which means enforcement happens at the virtual switch level, not iptables. This is efficient and scales to thousands of rules.

### 5.5 CNI (Container Network Interface)

**CNI** is a standard that defines how container runtimes (CRI-O in ROSA) set up networking for pods. The CNI plugin is the actual implementation that creates network interfaces, assigns IPs, and sets up routing.

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

> **WHY:** ROSA HCP uses OVN-Kubernetes as its CNI plugin. This is not optional and cannot be changed (unlike self-managed OpenShift where you could choose Calico or Cilium). OVN-Kubernetes was chosen because it integrates tightly with OpenShift's networking features (Routes, EgressIPs, multicast) and provides hardware-accelerated flow processing via Open vSwitch (OVS).

### 5.6 kube-proxy, iptables, and OVN Load Balancing

In standard Kubernetes, **kube-proxy** runs on every node and programs iptables rules to implement Service load balancing. In ROSA HCP with OVN-Kubernetes, kube-proxy is replaced by OVN's native load balancing.

```text
Standard Kubernetes (iptables):          ROSA HCP (OVN):

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

> **WHY:** ROSA HCP uses OVN for Service load balancing instead of kube-proxy/iptables because OVN handles it in the OVS datapath (kernel module), which is faster than iptables rule chains. At scale (thousands of Services), iptables performance degrades because rules are evaluated linearly. OVN uses flow tables with O(1) lookup time, maintaining performance regardless of the number of Services.

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

For external names (google.com), CoreDNS forwards the query to upstream DNS servers (configured in the node's /etc/resolv.conf, which in AWS points to the VPC DNS resolver at VPC_CIDR_base + 2, e.g., 10.0.0.2).

> **WHY:** Without CoreDNS, pods would need to know the ClusterIP of every Service they connect to. CoreDNS lets pods use human-readable names. This is essential for ROSA HCP because pods constantly discover and communicate with other services — the API server, the OAuth server, the image registry, monitoring endpoints, and your own application services.

---

## 6. OpenShift Networking Layer

OpenShift builds on Kubernetes networking with additional components. This section explains what OpenShift adds and how it works in ROSA HCP.

### 6.1 OVN-Kubernetes Architecture

**OVN (Open Virtual Network)** is a virtual networking system built on top of **OVS (Open vSwitch)**. OVN-Kubernetes is the CNI plugin that integrates OVN with Kubernetes.

```text
Architecture Overview:

Control Plane (Red Hat's VPC in ROSA HCP):
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

Worker Nodes (Your VPC):
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

> **WHY:** OVN provides a single virtual network that spans all worker nodes. Without it, pods on different nodes couldn't communicate — they'd be isolated in their own node's network namespace. OVN creates a virtual overlay network (using Geneve tunnels) that makes all pods appear to be on the same flat network, regardless of which physical node they're running on.

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
| Dst MAC: Node2 | Src: 10.0.2.10     | Src: random | VNI (network |
| Src MAC: Node1 | Dst: 10.0.4.10     | Dst: 6081   | identifier)  |
+-----------------+--------------------+-------------+--------------+
| INNER Packet (original, unchanged):                               |
| Src IP: 10.128.0.15  |  Dst IP: 10.128.2.33                     |
| Data: "GET /api"                                                  |
+------------------------------------------------------------------+

The VPC only sees: 10.0.2.10 → 10.0.4.10 (node-to-node UDP on port 6081)
The VPC doesn't know about pod IPs at all.
```

Step by step:

1. Pod A sends a packet to 10.128.2.33
2. OVN on Node 1 looks up 10.128.2.33 in the Southbound DB and finds it's on Node 2 (10.0.4.10)
3. OVS encapsulates the original packet in a Geneve tunnel:
   - Outer source IP = Node 1's IP (10.0.2.10)
   - Outer destination IP = Node 2's IP (10.0.4.10)
   - Outer destination port = UDP 6081 (Geneve)
4. The encapsulated packet traverses the VPC network as a normal node-to-node UDP packet
5. Node 2's OVS receives the packet on port 6081, strips the Geneve header
6. The original packet is delivered to Pod C's veth interface

> **WHY:** VPC networking only knows about node IPs (10.0.x.x). Pod IPs (10.128.x.x) are invisible to the VPC — they exist only in the overlay network. Geneve tunneling bridges this gap. It's the mechanism that makes Kubernetes' "every pod gets a routable IP" guarantee work across multiple physical nodes. Security groups must allow UDP port 6081 between worker nodes or cross-node pod communication will break completely.

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

- **Logical Switch**: One per node. All pods on a node are ports on that node's logical switch (like being plugged into the same virtual switch).
- **Cluster Router**: Connects all logical switches. Routes traffic between pods on different nodes. Also handles SNAT for external traffic and DNAT for Services.

> **WHY:** This logical topology is how OVN decides which tunnel to use for each packet. When Pod A (on Node 1's switch) sends to Pod C (on Node 2's switch), the Cluster Router routes the packet from Node 1's switch to Node 2's switch, and OVN translates that to a Geneve tunnel between the physical nodes. The logical topology mirrors the physical topology but is independent of it — you can move pods between nodes and OVN updates the logical ports automatically.

### 6.4 Pod CIDR Allocation Per Node

OVN-Kubernetes divides the cluster's pod CIDR range into smaller subnets and assigns one to each node. Each node then assigns IPs from its subnet to pods.

```text
Cluster Pod CIDR: 10.128.0.0/14 (262,144 addresses)

Node 1 allocation: 10.128.0.0/23 (512 addresses)
  Pod A: 10.128.0.15
  Pod B: 10.128.0.16
  ...

Node 2 allocation: 10.128.2.0/23 (512 addresses)
  Pod C: 10.128.2.33
  Pod D: 10.128.2.34
  ...

Node 3 allocation: 10.128.4.0/23 (512 addresses)
  ...
```

The default host prefix for ROSA HCP is /23, which gives 512 IP addresses per node (enough for 500 pods, since a few are reserved).

> **WHY:** This allocation scheme means OVN can determine which node hosts a pod just by looking at its IP address. 10.128.2.x is always on Node 2. This makes routing table lookups efficient — instead of one entry per pod, you need one entry per node. It also means each node can assign IPs to new pods locally without consulting a central IPAM server, which speeds up pod startup.

### 6.5 OpenShift Routes vs. Kubernetes Ingress

| Feature | OpenShift Route | Kubernetes Ingress |
|---------|----------------|-------------------|
| TLS Termination | Edge, Passthrough, Re-encrypt | Depends on Ingress Controller |
| Wildcard routes | Supported | Depends on controller |
| Route weights | Supported (for blue-green/canary) | Not standard |
| Implementation | HAProxy-based router | Varies by controller |
| ROSA HCP support | Native, default | Supported (translated to Routes) |

```yaml
# OpenShift Route example
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: my-app
  namespace: production
spec:
  host: my-app.apps.mycluster.example.com
  to:
    kind: Service
    name: my-app-svc
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

> **WHY:** Routes are the primary way applications are exposed in ROSA HCP. The OpenShift router (HAProxy) reads Route objects, configures TLS termination, and routes traffic to backend Services. When you create a Route with `host: my-app.apps.mycluster.example.com`, the router adds an HAProxy configuration entry that matches the HTTP Host header and forwards to the correct backend. The `*.apps` wildcard DNS record is pre-configured to point to the router's load balancer.

### 6.6 The OpenShift Router (HAProxy)

The OpenShift Router is a set of HAProxy pods running in the `openshift-ingress` namespace. These pods are the L7 reverse proxy that handles all Route-based traffic.

```text
External Traffic Flow Through the Router:

Internet Client
    |
    v
AWS NLB (Load Balancer Service)
    |  Target: Node IPs on NodePort 30080/30443
    v
Node's eth0 (kube-proxy / OVN intercepts)
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

The router is deployed as a **Deployment** with 2 replicas (by default in ROSA HCP) spread across different nodes for high availability.

> **WHY:** The router is the single entry point for all HTTP/HTTPS application traffic in ROSA HCP. Without it, external users cannot reach your applications. It's where TLS certificates are applied (for edge termination), where hostname-based routing happens, and where connection limits and timeouts are enforced. If router pods are unhealthy, all external application traffic stops flowing.

### 6.7 Multus CNI

**Multus** is a "meta-CNI" that allows pods to have multiple network interfaces. The primary interface (eth0) is always managed by OVN-Kubernetes. Multus can add additional interfaces.

```text
Normal Pod (one interface):        Multus Pod (multiple interfaces):

+-------------------+              +-------------------+
| Pod               |              | Pod               |
|                   |              |                   |
| eth0 (OVN)       |              | eth0 (OVN)        |  ← cluster network
|  10.128.0.15      |              |  10.128.0.15      |
|                   |              |                   |
+-------------------+              | net1 (Multus)     |  ← additional network
                                   |  192.168.100.10   |
                                   |                   |
                                   +-------------------+
```

> **WHY:** Multus is used in ROSA HCP for specialized networking requirements — most commonly with OpenShift Virtualization (KubeVirt), where VMs need a direct connection to a VLAN or SR-IOV interface for high-performance networking. It's also used for network functions (CNFs) that need multiple interfaces for separation of data plane and control plane traffic.

---

## 7. ROSA HCP Architecture — The Complete Picture

This section brings everything together to explain how ROSA HCP's hosted control plane architecture works at a network level.

### 7.1 What Makes HCP Different from Classic ROSA

| Feature | Classic ROSA | ROSA HCP |
|---------|-------------|----------|
| **Control plane location** | In your VPC (3 master nodes) | In Red Hat's VPC (shared, multi-tenant) |
| **Control plane cost** | You pay for 3 master EC2 instances | Red Hat manages; you don't pay for master nodes |
| **Control plane network** | Same VPC as workers | Different VPC, connected via PrivateLink |
| **API server access** | Direct (public or private endpoint in your VPC) | Via PrivateLink (always private between VPCs) |
| **Worker nodes** | In your VPC | In your VPC (same as classic) |
| **Cluster provisioning** | ~40 minutes | ~15 minutes |
| **etcd** | Runs on your master nodes | Runs in Red Hat's VPC |
| **Networking (CNI)** | OVN-Kubernetes | OVN-Kubernetes |

```text
Classic ROSA:                           ROSA HCP:

Your VPC:                               Your VPC:
+---------------------+                 +---------------------+
| Master 1 (m5.xlarge)|                 | (no master nodes!)  |
| Master 2 (m5.xlarge)|                 |                     |
| Master 3 (m5.xlarge)|                 | Worker 1            |
|                     |                 | Worker 2            |
| Worker 1            |                 | Worker 3            |
| Worker 2            |                 +----------+----------+
| Worker 3            |                            |
+---------------------+                  PrivateLink|
                                                   |
                                         Red Hat's VPC:
                                         +---------------------+
                                         | API Server          |
                                         | etcd                |
                                         | Controllers         |
                                         | (multi-tenant,      |
                                         |  shared infra)      |
                                         +---------------------+
```

> **WHY:** HCP reduces cost (no master node EC2 charges), improves provisioning speed (15 min vs. 40 min), and simplifies the customer's VPC (fewer components to manage). The trade-off is that the control plane is not in your VPC, so all control plane ↔ worker communication must traverse PrivateLink.

### 7.2 PrivateLink Architecture in Detail

The PrivateLink connection between Red Hat's control plane and your worker nodes has two directions:

```text
Direction 1: Control Plane → Workers (API server to kubelets)

Red Hat's VPC:                        Your VPC:
+----------------------------+        +----------------------------+
| API Server (kube-apiserver)|        | PrivateLink Endpoint       |
|                            |        | (ENI: 10.0.2.200)          |
| "Get pod logs from node 1" |       |                            |
|         |                  |        |         |                  |
|         v                  |        |         v                  |
| NLB (Endpoint Service)    |        | Routes to worker node      |
| (provider side)            |------->| 10.0.2.10:10250            |
|                            |  PL    |         |                  |
+----------------------------+        |         v                  |
                                      | Worker Node 1 (kubelet)   |
                                      | Responds with pod logs     |
                                      +----------------------------+

Direction 2: Workers → Control Plane (kubelets to API server)

Your VPC:                             Red Hat's VPC:
+----------------------------+        +----------------------------+
| Worker Node 1              |        | PrivateLink Endpoint       |
| (kubelet, pods)            |        | (ENI in Red Hat's subnet)  |
|                            |        |                            |
| "kubectl get pods" or      |        |         |                  |
| kubelet → API registration  |       |         v                  |
|         |                  |        | NLB → API Server           |
|         v                  |        | (kube-apiserver:6443)      |
| PrivateLink Endpoint       |------->|                            |
| (ENI: 10.0.2.201)          |  PL    +----------------------------+
+----------------------------+
```

Both directions use separate PrivateLink connections. Each creates an ENI in the consumer's subnet with a private IP address.

> **WHY:** Two PrivateLink connections are needed because PrivateLink is unidirectional — the consumer initiates connections to the provider. The API server needs to reach kubelets (for logs, exec, port-forward) — that's one direction. Kubelets need to reach the API server (for registration, watch, status updates) — that's the other direction. Without both, the cluster cannot function.

### 7.3 Full Blackboard-Style Architecture Diagram

```text
+=============================================================================+
|                        ROSA HCP COMPLETE ARCHITECTURE                        |
+=============================================================================+

  Internet
     |
     | (public traffic)
     v
+----+----+
|   IGW   |  Internet Gateway
+----+----+
     |
     v
+=============================================================================+
| YOUR VPC (10.0.0.0/16)                                                      |
|                                                                              |
| PUBLIC SUBNETS                                                               |
| +-----------------------------------------------------------------------+   |
| |                                                                       |   |
| | +-------------------+  +-------------------+  +-------------------+  |   |
| | | AZ-1a: 10.0.1.0/24|  | AZ-1b: 10.0.3.0/24|  | AZ-1c: 10.0.5.0/24|  |   |
| | |                   |  |                   |  |                   |  |   |
| | | NLB               |  | NLB               |  | NLB               |  |   |
| | | (EIP: 54.x.x.x)  |  | (EIP: 54.y.y.y)  |  | (EIP: 54.z.z.z)  |  |   |
| | |                   |  |                   |  |                   |  |   |
| | | NAT GW            |  | NAT GW            |  | NAT GW            |  |   |
| | | (EIP: 52.a.a.a)  |  | (EIP: 52.b.b.b)  |  | (EIP: 52.c.c.c)  |  |   |
| | +-------------------+  +-------------------+  +-------------------+  |   |
| +-----------------------------------------------------------------------+   |
|                                                                              |
| PRIVATE SUBNETS                                                              |
| +-----------------------------------------------------------------------+   |
| |                                                                       |   |
| | +-------------------------------------------------------------------+ |   |
| | | AZ-1a: 10.0.2.0/24                                               | |   |
| | |                                                                   | |   |
| | | Worker Node 1 (m5.xlarge)                                         | |   |
| | | ENI: eni-abc (10.0.2.10)                                          | |   |
| | | SG: sg-worker                                                     | |   |
| | | +---------------------------------------------------------------+| |   |
| | | | Linux OS                                                      || |   |
| | | | eth0: 10.0.2.10                                               || |   |
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
| | +-------------------------------------------------------------------+ |   |
| | | AZ-1b: 10.0.4.0/24 (similar layout, Node 2)                      | |   |
| | +-------------------------------------------------------------------+ |   |
| |                                                                       |   |
| | PrivateLink Endpoints (ENIs in private subnets):                      |   |
| | - To CP API:   eni-pl1 (10.0.2.200) → Red Hat API Server             |   |
| | - From CP:     eni-pl2 (10.0.2.201) ← Red Hat reaches kubelets       |   |
| |                                                                       |   |
| | VPC Endpoints (ENIs for AWS services):                                |   |
| | - S3:          vpce-s3     (Gateway endpoint, route table entry)      |   |
| | - ECR API:     vpce-ecr1   (10.0.2.210)                              |   |
| | - ECR DKR:     vpce-ecr2   (10.0.2.211)                              |   |
| | - STS:         vpce-sts    (10.0.2.212)                               |   |
| | - EC2:         vpce-ec2    (10.0.2.213)                               |   |
| | - ELB:         vpce-elb    (10.0.2.214)                               |   |
| +-----------------------------------------------------------------------+   |
|                                                                              |
| Route Tables:                                                                |
| - Public:  0.0.0.0/0 → IGW                                                  |
| - Private: 0.0.0.0/0 → NAT GW, 10.0.0.0/16 → local                        |
| - (Optional) 192.168.0.0/16 → TGW (for hybrid/on-prem)                     |
|                                                                              |
+=============================================================================+
     |  PrivateLink (never traverses internet)
     v
+=============================================================================+
| RED HAT'S VPC (172.20.0.0/16) — Multi-Tenant Hosted Control Plane          |
|                                                                              |
| +----------------------------------+  +----------------------------------+  |
| | Your Cluster's Control Plane     |  | Other Customer's Control Plane   |  |
| |                                  |  | (isolated)                       |  |
| | kube-apiserver (port 6443)       |  |                                  |  |
| | etcd (clustered, encrypted)      |  |                                  |  |
| | kube-controller-manager          |  |                                  |  |
| | kube-scheduler                   |  |                                  |  |
| | openshift-controller-manager     |  |                                  |  |
| | cluster-version-operator         |  |                                  |  |
| | OVN control plane                |  |                                  |  |
| |   (northbound DB, southbound DB) |  |                                  |  |
| +----------------------------------+  +----------------------------------+  |
|                                                                              |
| NLB (Endpoint Service provider for PrivateLink)                              |
|                                                                              |
+=============================================================================+
```

### 7.4 How the API Server Communicates with Kubelets

```text
1. User runs: oc get pods
                |
2. oc CLI   -->| HTTPS to API server endpoint
                |  (resolves via PrivateLink endpoint ENI in your VPC)
                v
3. API Server (in Red Hat's VPC)
   Processes request, returns pod list from etcd
                |
4. Response  <--| back through PrivateLink
                v
5. oc CLI displays pod list

---

6. User runs: oc logs my-pod
                |
7. oc CLI   -->| HTTPS to API server
                v
8. API Server needs actual logs from kubelet
   API server --|  through PrivateLink (direction 2)
                |  to your worker node's kubelet (port 10250)
                v
9. Kubelet on worker node
   Reads logs from CRI-O for the specified pod
                |
10. Logs     <--| back through PrivateLink to API server
                v
11. API Server relays logs back to oc CLI
```

> **WHY:** This explains why `oc logs`, `oc exec`, and `oc port-forward` sometimes feel slower in ROSA HCP than in Classic ROSA — the data must traverse two PrivateLink hops (user → API server, API server → kubelet, kubelet → API server, API server → user). In Classic ROSA, the API server and kubelets are in the same VPC, so it's just local VPC traffic.

---

## 8. How Apps Are Exposed in ROSA HCP

This is the core section. It explains, at the packet level, how traffic reaches your applications.

### 8.1 Public Ingress Path — Packet-Level Walkthrough

A user on the internet accesses `https://my-app.apps.mycluster.example.com`:

```text
STEP 1: DNS Resolution
========================
User's browser: "What is the IP of my-app.apps.mycluster.example.com?"
    |
    v
DNS Resolver → Route 53
    |
    | Route 53 has a wildcard record:
    | *.apps.mycluster.example.com → ALIAS → NLB DNS name
    | NLB DNS name resolves to: 54.1.2.3, 54.4.5.6 (NLB public IPs)
    |
    v
Browser gets IP: 54.1.2.3


STEP 2: TCP Connection + TLS Handshake
=======================================
Browser → 54.1.2.3:443 (TCP SYN)
    |
    | Packet:
    | Src IP: 203.0.113.50 (user's public IP)
    | Dst IP: 54.1.2.3 (NLB's Elastic IP)
    | Dst Port: 443
    |
    v
NLB receives on public subnet
    |
    | NLB is Layer 4 — it does NOT terminate TLS
    | NLB performs DNAT:
    |   Original dst: 54.1.2.3:443
    |   New dst: 10.0.2.10:30443 (Node 1's IP + router NodePort)
    |
    | NLB also preserves the original source IP (with Proxy Protocol
    | or by operating in "target by instance" mode)
    |
    v
Packet on VPC network:
    Src IP: 203.0.113.50 (preserved!)
    Dst IP: 10.0.2.10 (worker node)
    Dst Port: 30443 (NodePort for router)


STEP 3: Node Receives Packet
==============================
Worker Node 1's ENI (eni-abc) receives the packet
    |
    | Security Group check (on Nitro card):
    |   Rule: Allow TCP 30000-32767 from NLB SG → PASS
    |
    v
Linux kernel (eth0) receives packet
    |
    | OVN/iptables intercepts packets to NodePort 30443
    | DNAT to router pod IP:
    |   Original dst: 10.0.2.10:30443
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
    Src IP: 10.128.0.20 (router pod — original client IP in X-Forwarded-For header)
    Dst IP: 10.128.0.15 (itself)
    Dst Port: 8080

App processes request, sends response back.
Response follows reverse path:
    App pod → OVN → Router pod → OVN → Node → NLB → Internet → User


COMPLETE IP TRANSFORMATION CHAIN:
===================================
User:        203.0.113.50:54321  →  54.1.2.3:443       (to NLB's public IP)
NLB DNAT:    203.0.113.50:54321  →  10.0.2.10:30443    (to Node's NodePort)
OVN DNAT:    203.0.113.50:54321  →  10.128.0.20:443    (to Router pod)
HAProxy:     10.128.0.20:xxxxx   →  172.30.45.67:8080  (to Service ClusterIP)
OVN DNAT:    10.128.0.20:xxxxx   →  10.128.0.15:8080   (to App pod)
```

> **WHY:** Understanding this chain is essential for debugging "my app is unreachable" problems. The packet passes through 5 different components (DNS, NLB, Node/OVN, Router, OVN again), and a misconfiguration at ANY point breaks the flow. The most common issues: DNS not resolving (Route 53 misconfigured), NLB target unhealthy (node security group blocking NodePort range), router pod not running (deployment scaled to 0), Service selector not matching pods (labels wrong).

### 8.2 Private Ingress Path — Packet-Level Walkthrough

For private ROSA HCP clusters, there's no public NLB. Traffic enters from the corporate network via VPN, Transit Gateway, or Direct Connect.

```text
Corporate User (192.168.1.100) accesses private app:

STEP 1: DNS Resolution
========================
Corporate DNS server resolves:
    my-app.apps.mycluster.internal.com → 10.0.2.50 (Internal NLB private IP)

    Note: This uses split-horizon DNS:
    - From internet: *.apps.mycluster... → NXDOMAIN (doesn't exist)
    - From corp network: *.apps.mycluster... → internal NLB IP


STEP 2: Traffic Path
=====================
Corp user (192.168.1.100)
    |
    v
Corporate Router / Firewall
    |
    v
VPN Tunnel or Direct Connect
    |
    v
Transit Gateway (TGW)
    |
    | TGW route table:
    |   10.0.0.0/16 → Attachment to ROSA VPC
    |
    v
VPC Route Table receives packet:
    Src IP: 192.168.1.100
    Dst IP: 10.0.2.50 (Internal NLB)
    Dst Port: 443


STEP 3: Internal NLB
======================
Internal NLB (no public IP, private subnet only)
    |
    | DNAT:
    |   Dst: 10.0.2.50:443 → 10.0.2.10:30443 (Node NodePort)
    |
    v
Same flow as public ingress from Step 3 onward:
    Node → OVN → Router Pod → Service → App Pod


COMPLETE IP TRANSFORMATION CHAIN:
===================================
Corp User:   192.168.1.100:54321  →  10.0.2.50:443     (to internal NLB)
NLB DNAT:    192.168.1.100:54321  →  10.0.2.10:30443   (to Node NodePort)
OVN DNAT:    192.168.1.100:54321  →  10.128.0.20:443   (to Router pod)
HAProxy:     10.128.0.20:xxxxx    →  172.30.45.67:8080  (to Service ClusterIP)
OVN DNAT:    10.128.0.20:xxxxx    →  10.128.0.15:8080   (to App pod)
```

> **WHY:** Private ingress is the standard for production workloads in regulated industries. The NLB annotation `service.beta.kubernetes.io/aws-load-balancer-internal: "true"` makes the NLB private. The key difference from public ingress is that DNS must be configured on the corporate side to resolve *.apps to the internal NLB IP, typically via Route 53 private hosted zones associated with the VPC.

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
    - VPC CIDR (10.0.0.0/16) — not a VPC host
    → Must go to external network

OVN SNAT (Source NAT):
    Original src: 10.128.0.15 (pod IP)
    New src: 10.0.2.10 (node IP)
    
    WHY: The VPC doesn't know about pod IPs (10.128.x.x).
    It only knows about node IPs (10.0.x.x). If OVN
    didn't SNAT, the VPC would drop the packet because
    10.128.0.15 has no route in the VPC routing table.


STEP 3: VPC Routing
=====================
Packet on VPC network:
    Src IP: 10.0.2.10 (node IP after OVN SNAT)
    Dst IP: 54.187.174.169
    Dst Port: 443

VPC route table lookup:
    54.187.174.169 doesn't match 10.0.0.0/16 (local)
    54.187.174.169 matches 0.0.0.0/0 → NAT Gateway
    → Forward to NAT GW


STEP 4: NAT Gateway SNAT
==========================
NAT Gateway receives packet:
    Src IP: 10.0.2.10 (node's private IP)
    Dst IP: 54.187.174.169

NAT Gateway SNAT:
    Original src: 10.0.2.10
    New src: 52.a.a.a (NAT GW's Elastic IP)
    
    NAT GW records this translation in its connection table:
    52.a.a.a:12345 ↔ 10.0.2.10:54321


STEP 5: Internet
==================
Packet on the internet:
    Src IP: 52.a.a.a (NAT GW's Elastic IP — this is what Stripe sees)
    Dst IP: 54.187.174.169 (Stripe's server)
    Dst Port: 443


STEP 6: Response (reverse path)
================================
Stripe responds:
    Src IP: 54.187.174.169
    Dst IP: 52.a.a.a (NAT GW's Elastic IP)

NAT GW reverse SNAT:
    Dst IP: 52.a.a.a → 10.0.2.10 (looked up in connection table)

VPC routes to node 10.0.2.10

OVN reverse SNAT:
    Dst IP: 10.0.2.10 → 10.128.0.15 (looked up in conntrack)

Packet delivered to pod.


DOUBLE SNAT SUMMARY:
=====================
Pod sends:  src=10.128.0.15  (pod IP)
OVN SNAT:   src=10.0.2.10    (node IP)     ← first translation
NAT GW:     src=52.a.a.a     (Elastic IP)  ← second translation
Internet sees: 52.a.a.a                    ← what external services log

Response reverses both translations automatically (conntrack/connection table).
```

> **WHY:** Egress goes through double SNAT. This is important because when you look at external service logs (Stripe, GitHub, etc.), the source IP will be the NAT Gateway's Elastic IP — not the pod IP or node IP. If you need to allowlist your cluster's outbound IP in an external firewall, you provide the NAT Gateway's Elastic IP addresses. For multi-AZ clusters, each AZ's NAT Gateway has a different Elastic IP, so you must allowlist all of them.

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
| OUTER: Src=10.0.2.10 Dst=10.0.4.10 UDP DstPort=6081             |
| GENEVE HDR: VNI=0x1, Options: {src-port=10.128.0.15, ...}       |
| INNER: Src=10.128.0.15 Dst=10.128.2.33 TCP DstPort=8080         |
+------------------------------------------------------------------+
    |
    v
eth0 on Node 1 → ENI → VPC network
    |
    | VPC sees: 10.0.2.10 → 10.0.4.10 (just a UDP packet)
    | Security Group: Allow UDP 6081 from self → PASS
    |
    v
eth0 on Node 2 → OVS receives on Geneve port
    |
    v
br-int on Node 2
    |
    | Decapsulate Geneve header
    | Deliver inner packet to Pod C's veth
    |
    v
Pod C eth0 (veth pair) receives:
    Src: 10.128.0.15, Dst: 10.128.2.33
    (original IPs preserved — no SNAT for pod-to-pod)
```

> **WHY:** Cross-node pod traffic uses Geneve encapsulation because the VPC network doesn't know about pod IPs. The outer packet uses node IPs (which the VPC can route), and the inner packet carries the original pod IPs. This is why Security Groups must allow UDP 6081 between worker nodes — blocking it breaks all cross-node pod communication. Same-node traffic skips encapsulation entirely, which is why co-locating communicating pods on the same node reduces latency.

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
    |   - 10.128.2.34:8080 (Pod D, different node)
    |
    | OVN selects: 10.128.2.33 (round-robin or random)
    |
    | DNAT:
    |   Original dst: 172.30.45.67:8080
    |   New dst: 10.128.2.33:8080
    |
    v
Packet is now pod-to-pod (10.128.0.15 → 10.128.2.33)
    → follows cross-node path (Geneve if different node)
    → follows same-node path (br-int if same node)
```

> **WHY:** The ClusterIP (172.30.45.67) never appears on any network interface — it's a virtual construct that only exists as DNAT rules in OVN. When troubleshooting "Service not reachable," the issue is almost always that OVN's load balancer has no endpoints (pods aren't running or labels don't match the Service selector). Check with `oc get endpoints my-api -n production`.

---

## 9. IP Address Architecture

### 9.1 The Four IP Ranges in ROSA HCP

Every ROSA HCP cluster uses four distinct IP ranges that must not overlap:

```text
+---------------------------------------------------------------+
|                    ROSA HCP IP Architecture                    |
+---------------------------------------------------------------+
|                                                               |
|  1. VPC CIDR: 10.0.0.0/16                                    |
|     Used for: Node IPs, ENIs, load balancers, VPC endpoints   |
|     Size: 65,536 addresses                                    |
|     YOU configure this when creating the VPC                  |
|                                                               |
|  2. Machine CIDR: (same as or subset of VPC CIDR)             |
|     Used for: Worker node primary IPs                         |
|     Must be within the VPC CIDR                               |
|                                                               |
|  3. Pod CIDR (Cluster Network): 10.128.0.0/14                |
|     Used for: Pod IP addresses                                |
|     Size: 262,144 addresses                                   |
|     Default host prefix: /23 (512 pods per node)              |
|     ROSA manages this internally (OVN overlay)                |
|                                                               |
|  4. Service CIDR (Service Network): 172.30.0.0/16             |
|     Used for: Kubernetes Service ClusterIPs                   |
|     Size: 65,536 addresses                                    |
|     Virtual only — never appears on a wire                    |
|     ROSA manages this internally                              |
|                                                               |
+---------------------------------------------------------------+

These ranges MUST NOT overlap with:
  - Each other
  - On-prem networks (if using TGW/VPN)
  - Other VPCs (if using peering/TGW)
  - AWS reserved ranges (169.254.0.0/16, 100.64.0.0/10)
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

When Node 3 joins:
    OVN allocates: 10.128.4.0/23 to Node 3
    ...
```

> **WHY:** This hierarchical allocation means you can tell which node a pod is on just from its IP. It also means each node manages its own IP pool without coordinating with other nodes. The /14 cluster network supports up to 512 nodes with /23 host prefix (14 network bits - 9 host prefix bits = 512 subnets, but some are reserved). If you need more nodes, choose a larger cluster network or a shorter host prefix.

### 9.3 SNAT — When and Why Pod IPs Become Node IPs

OVN performs SNAT on pod traffic in specific situations:

| Traffic Type | SNAT? | Source IP at Destination |
|-------------|-------|------------------------|
| Pod → Pod (same cluster) | No | Pod IP (10.128.x.x) |
| Pod → Service (same cluster) | No | Pod IP (10.128.x.x) |
| Pod → Node IP (same cluster) | Yes | Node IP (10.0.x.x) |
| Pod → VPC resource (RDS, etc.) | Yes | Node IP (10.0.x.x) |
| Pod → Internet (via NAT GW) | Yes (double) | NAT GW EIP (52.x.x.x) |
| Pod → On-prem (via TGW) | Yes | Node IP (10.0.x.x) |

```text
Why SNAT happens for external traffic:

The VPC routing table only has routes for VPC CIDRs (10.0.0.0/16).
Pod CIDRs (10.128.0.0/14) have NO route in the VPC.

If a pod sent a packet with src=10.128.0.15 to an RDS database:
    RDS receives packet from 10.128.0.15
    RDS sends response to 10.128.0.15
    VPC routing: "Where is 10.128.0.15?" → NO ROUTE → DROPPED!

With SNAT (src becomes 10.0.2.10):
    RDS receives packet from 10.0.2.10
    RDS sends response to 10.0.2.10
    VPC routing: "Where is 10.0.2.10?" → local → delivered to Node 1
    Node 1's OVN conntrack: reverse SNAT to 10.128.0.15 → delivered to pod
```

> **WHY:** This is why pods talking to RDS, ElastiCache, or any VPC resource appear as the node IP. If you set up RDS security group rules, you must allow the node IPs or the worker node security group — not pod IPs, because those are invisible to the VPC. For internet-bound traffic, the source IP becomes the NAT Gateway's Elastic IP after the second SNAT.

### 9.4 Elastic IPs on NAT Gateways

```text
Multi-AZ ROSA HCP cluster:

AZ us-east-1a:
    NAT Gateway → Elastic IP: 52.10.1.1
    Pods on nodes in this AZ exit with src=52.10.1.1

AZ us-east-1b:
    NAT Gateway → Elastic IP: 52.10.2.2
    Pods on nodes in this AZ exit with src=52.10.2.2

AZ us-east-1c:
    NAT Gateway → Elastic IP: 52.10.3.3
    Pods on nodes in this AZ exit with src=52.10.3.3

External service firewall allowlist:
    52.10.1.1, 52.10.2.2, 52.10.3.3
```

> **WHY:** In a multi-AZ deployment, each AZ has its own NAT Gateway with its own Elastic IP. The exit IP depends on which AZ the pod's node is in. When allowlisting, you must include all NAT Gateway EIPs. If you add a new AZ, you must update external allowlists.

---

## 10. BGP and Hybrid Networking

### 10.1 BGP Fundamentals

**BGP (Border Gateway Protocol)** is the routing protocol that runs the internet. It's also used to connect corporate networks to AWS.

```text
BGP in one sentence:
    "I am AS 65010. I can reach networks 192.168.0.0/16 and 172.16.0.0/12.
     Let me tell my neighbors so they can route traffic to me."
```

**Key concepts:**

| Concept | What It Is | Example |
|---------|-----------|---------|
| **AS (Autonomous System)** | A network under one administrative control | Your company = AS 65010, AWS = AS 64512 |
| **ASN (AS Number)** | Unique number identifying an AS | 65010 (private range: 64512-65534) |
| **Prefix** | A network (CIDR) that an AS announces | "I have 192.168.0.0/16" |
| **Peer** | A BGP neighbor you exchange routes with | TGW peers with your on-prem router |
| **Route Advertisement** | Telling your peer about a network you can reach | "Route to 10.0.0.0/16 via me" |
| **Route Propagation** | Automatically adding learned BGP routes to route tables | TGW learned 192.168.0.0/16, adds it to VPC route table |

```text
BGP Route Exchange:

Your On-Prem Router (AS 65010)          AWS Transit Gateway (AS 64512)
+----------------------------+          +----------------------------+
| "I have:                   |          | "I have:                   |
|   192.168.0.0/16 (corp)    | <------> |   10.0.0.0/16 (ROSA VPC)  |
|   172.16.0.0/12 (DC2)     |   BGP    |   10.1.0.0/16 (shared)    |
|                            | session  |                            |
| I learned from AWS:        |          | I learned from on-prem:    |
|   10.0.0.0/16             |          |   192.168.0.0/16           |
|   10.1.0.0/16             |          |   172.16.0.0/12            |
+----------------------------+          +----------------------------+
```

> **WHY:** BGP is how ROSA HCP pods reach on-premises resources. Without BGP, the VPC wouldn't know that 192.168.0.0/16 is reachable through the Transit Gateway. BGP dynamically learns and propagates routes, so if your on-prem network changes (adds a new subnet), BGP automatically advertises it to AWS — no manual route table updates needed.

### 10.2 Transit Gateway BGP Peering

```text
Complete Hybrid Architecture with BGP:

+-------------------------------------------------------------------+
|                          AWS Region                                |
|                                                                    |
|  +-------------------+         +-------------------+               |
|  | ROSA VPC          |         | Transit Gateway   |               |
|  | 10.0.0.0/16       |         | (AS 64512)        |               |
|  |                   |         |                   |               |
|  | Worker Nodes      |-------->| TGW Attachment    |               |
|  | 10.0.2.10         | attach  | (in ROSA VPC)     |               |
|  | 10.0.4.10         |         |                   |               |
|  |                   |         | Route Table:       |               |
|  | Route Table:      |         | 10.0.0.0/16→VPC   |               |
|  | 192.168.0.0/16    |         | 192.168.0.0/16    |               |
|  |   → TGW           |         |   → VPN/DX        |               |
|  +-------------------+         +---+---------------+               |
|                                    |                                |
|                                    | VPN Tunnel or                  |
|                                    | Direct Connect                 |
|                                    | (BGP session)                  |
|                                    |                                |
+------------------------------------+--------------------------------+
                                     |
                                     v
                    +----------------------------+
                    | On-Prem Border Router      |
                    | (AS 65010)                  |
                    |                            |
                    | BGP Neighbor: TGW peer IP   |
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
                    | Monitoring: 192.168.20.10  |
                    +----------------------------+
```

### 10.3 Route Propagation Configuration

```bash
# Step 1: Create Transit Gateway
TGW_ID=$(aws ec2 create-transit-gateway \
  --description "ROSA-to-OnPrem" \
  --options "AmazonSideAsn=64512,AutoAcceptSharedAttachments=enable,DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable,DnsSupport=enable" \
  --query 'TransitGateway.TransitGatewayId' \
  --output text)
echo "TGW ID: $TGW_ID"

# Step 2: Attach ROSA VPC to TGW
ROSA_VPC_ID="vpc-0abc123def"
PRIVATE_SUBNET_IDS="subnet-1a subnet-1b"

aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id $TGW_ID \
  --vpc-id $ROSA_VPC_ID \
  --subnet-ids $PRIVATE_SUBNET_IDS

# Step 3: Create VPN connection with BGP
CGW_ID=$(aws ec2 create-customer-gateway \
  --bgp-asn 65010 \
  --public-ip "YOUR_ONPREM_PUBLIC_IP" \
  --type ipsec.1 \
  --query 'CustomerGateway.CustomerGatewayId' \
  --output text)

aws ec2 create-vpn-connection \
  --type ipsec.1 \
  --customer-gateway-id $CGW_ID \
  --transit-gateway-id $TGW_ID \
  --options '{"StaticRoutesOnly":false}'

# Step 4: Enable route propagation to ROSA VPC route table
ROSA_RT_ID="rtb-0abc123"
TGW_ATTACH_ID="tgw-attach-0abc123"

aws ec2 enable-transit-gateway-route-table-propagation \
  --transit-gateway-route-table-id $TGW_RT_ID \
  --transit-gateway-attachment-id $TGW_ATTACH_ID

# Step 5: Add route in ROSA VPC route table pointing to TGW
aws ec2 create-route \
  --route-table-id $ROSA_RT_ID \
  --destination-cidr-block 192.168.0.0/16 \
  --transit-gateway-id $TGW_ID
```

### 10.4 On-Prem Router BGP Configuration (Cisco IOS Example)

```text
router bgp 65010
 bgp router-id 192.168.1.1
 neighbor 169.254.100.1 remote-as 64512
 neighbor 169.254.100.1 description AWS-TGW-Tunnel1
 !
 address-family ipv4 unicast
  network 192.168.0.0 mask 255.255.0.0
  neighbor 169.254.100.1 activate
  neighbor 169.254.100.1 soft-reconfiguration inbound
 exit-address-family
```

> **WHY:** `network 192.168.0.0 mask 255.255.0.0` tells BGP to advertise this prefix to the TGW. The TGW learns this route and (with route propagation enabled) adds it to the VPC route table. Now pods on ROSA worker nodes can send packets to 192.168.x.x addresses and they'll be routed through the TGW to on-prem. Without this advertisement, the VPC route table has no entry for 192.168.0.0/16 and packets to on-prem are dropped.

### 10.5 Pod CIDR Advertisement Considerations

By default, the ROSA pod CIDR (10.128.0.0/14) is NOT advertised via BGP. This means on-prem services see pod traffic as coming from node IPs (because of OVN SNAT).

**If you need on-prem to reach pods directly** (e.g., for pod-level firewall rules or service mesh spanning on-prem and cloud):

1. You must advertise 10.128.0.0/14 from AWS to on-prem via BGP
2. On-prem routers must have routes for 10.128.0.0/14 pointing back to the TGW/VPN
3. OVN SNAT must be disabled for traffic to on-prem (using EgressIP or custom masquerade rules)

This is an advanced configuration and most deployments avoid it by relying on SNAT (pods appear as node IPs to on-prem).

> **WHY:** Advertising pod CIDRs adds complexity — on-prem firewalls must handle a much larger set of source IPs (up to 262,144 pod IPs vs. a handful of node IPs), and pod IPs are ephemeral (they change as pods are rescheduled). The SNAT approach is simpler and sufficient for most use cases.

---

## 11. DNS Architecture in ROSA HCP

### 11.1 DNS Layers in ROSA HCP

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
3. VPC DNS Resolver (10.0.0.2 — VPC CIDR base + 2):
     Handles: Route 53 public/private hosted zones
              AWS service endpoints (*.amazonaws.com)
              External domains
         |
         | For external domains:
         v
4. Route 53 / Public DNS:
     Handles: Everything else (google.com, github.com, etc.)
```

### 11.2 CoreDNS Inside the Cluster

CoreDNS runs as a Deployment in `openshift-dns` with a DaemonSet for the DNS pods (one per node for performance).

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
         |  +-----------------------+                          |
         |  |                                                  |
         v  v                                                  |
+--------+--------+                                            |
| Kubernetes API   |  <-----------------------------------------+
| (watches         |
|  Services,       |     CoreDNS watches the K8s API for Service
|  Endpoints,      |     and Endpoint changes. When a new Service
|  Pods)           |     is created, CoreDNS immediately knows its
+------------------+     ClusterIP and starts resolving it.
```

CoreDNS Corefile (simplified):

```text
.:5353 {
    bufsize 512
    errors
    health {
        lameduck 20s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
    }
    forward . /etc/resolv.conf {
        policy sequential
    }
    cache 900 {
        denial 9984 30
    }
    reload
}
```

> **WHY:** CoreDNS is deployed as a DaemonSet (one per node) so DNS queries don't cross the network — a pod's DNS query goes to the CoreDNS on the same node, avoiding Geneve tunnel overhead. The `kubernetes` plugin watches the API server and serves authoritative answers for cluster-internal names. The `forward` plugin sends non-cluster queries to the VPC resolver. The `cache` plugin reduces load on both the API server and upstream resolvers.

### 11.3 Route 53 and ROSA HCP

ROSA HCP creates Route 53 records automatically:

```text
Public Hosted Zone (if cluster has public endpoint):
+-------------------------------------------------------+
| Zone: mycluster.abcd.p1.openshiftapps.com             |
|                                                       |
| api.mycluster.abcd.p1.openshiftapps.com               |
|   → ALIAS to PrivateLink NLB DNS name                |
|                                                       |
| *.apps.mycluster.abcd.p1.openshiftapps.com            |
|   → ALIAS to Ingress NLB DNS name                    |
|   (This is how Routes are resolved!)                  |
+-------------------------------------------------------+

The wildcard record means:
  ANY-NAME.apps.mycluster.abcd.p1.openshiftapps.com
  all resolve to the same NLB IP(s).
  
  The NLB delivers to the OpenShift Router (HAProxy),
  which reads the Host header to pick the right backend.
```

### 11.4 Split-Horizon DNS for Private Clusters

For private ROSA HCP clusters, the same DNS name resolves to different IPs depending on where you're querying from:

```text
Private Cluster DNS:

From the internet:
    dig my-app.apps.mycluster.internal.com
    → NXDOMAIN (doesn't exist in public DNS)

From inside the VPC (or connected network):
    dig my-app.apps.mycluster.internal.com
    → 10.0.2.50 (internal NLB private IP)

How this works:
    Route 53 Private Hosted Zone:
    - Associated with the ROSA VPC
    - *.apps.mycluster.internal.com → internal NLB
    - Only visible to DNS resolvers inside the associated VPCs

    To make it work from on-prem:
    - Configure Route 53 Resolver Endpoints (inbound)
    - On-prem DNS conditionally forwards *.apps.mycluster.internal.com
      to the Route 53 inbound endpoint IPs
```

```text
Private DNS Flow (from on-prem):

On-Prem User: "resolve my-app.apps.mycluster.internal.com"
    |
    v
On-Prem DNS Server
    |
    | Conditional forwarder:
    | *.apps.mycluster.internal.com → 10.0.2.250, 10.0.4.250
    | (Route 53 Inbound Resolver Endpoint IPs)
    |
    v
Route 53 Inbound Resolver (ENI in your VPC)
    |
    v
Route 53 Private Hosted Zone
    |
    | *.apps.mycluster.internal.com → 10.0.2.50 (internal NLB)
    |
    v
Response: 10.0.2.50
    |
    v
On-prem user connects to 10.0.2.50 via TGW/VPN
```

> **WHY:** Split-horizon DNS is essential for private clusters. Without it, on-prem users can't resolve cluster hostnames. The Route 53 Inbound Resolver Endpoints must be created in VPC subnets and their IPs provided to the on-prem DNS team for conditional forwarding rules.

---

## 12. Security Architecture

### 12.1 S1 — Private Cluster Security Bundle

This bundle locks down a private ROSA HCP cluster with no internet-facing components.

#### Worker Node Security Group

```bash
WORKER_SG_ID="sg-worker"

# Rule 1: Allow API server via PrivateLink (port 6443)
aws ec2 authorize-security-group-ingress \
  --group-id $WORKER_SG_ID \
  --ip-permissions '[
    {
      "IpProtocol": "tcp",
      "FromPort": 6443,
      "ToPort": 6443,
      "UserIdGroupPairs": [{"GroupId": "sg-privatelink"}]
    }
  ]'
```

> **WHY:** Port 6443 is the Kubernetes API server port. The control plane (in Red Hat's VPC) communicates with worker nodes via PrivateLink. The PrivateLink endpoint creates an ENI with security group `sg-privatelink`. This rule allows only traffic from that PrivateLink ENI to reach port 6443 on workers, preventing any other source from hitting the API port.

```bash
# Rule 2: Allow kubelet communication from control plane (port 10250)
aws ec2 authorize-security-group-ingress \
  --group-id $WORKER_SG_ID \
  --ip-permissions '[
    {
      "IpProtocol": "tcp",
      "FromPort": 10250,
      "ToPort": 10250,
      "UserIdGroupPairs": [{"GroupId": "sg-privatelink"}]
    }
  ]'
```

> **WHY:** Port 10250 is the kubelet API port. The API server calls kubelets for `oc logs`, `oc exec`, and health checks. Without this rule, the control plane can't retrieve logs or execute commands in pods.

```bash
# Rule 3: Allow Geneve overlay traffic between workers (UDP 6081)
aws ec2 authorize-security-group-ingress \
  --group-id $WORKER_SG_ID \
  --ip-permissions '[
    {
      "IpProtocol": "udp",
      "FromPort": 6081,
      "ToPort": 6081,
      "UserIdGroupPairs": [{"GroupId": "'$WORKER_SG_ID'"}]
    }
  ]'
```

> **WHY:** UDP 6081 is the Geneve tunnel port. All cross-node pod communication is encapsulated in Geneve packets. Blocking this port completely breaks pod-to-pod networking across nodes. The `self` reference (same security group) ensures only worker nodes can send Geneve traffic to each other.

```bash
# Rule 4: Allow NodePort range from internal NLB (TCP 30000-32767)
aws ec2 authorize-security-group-ingress \
  --group-id $WORKER_SG_ID \
  --ip-permissions '[
    {
      "IpProtocol": "tcp",
      "FromPort": 30000,
      "ToPort": 32767,
      "IpRanges": [{"CidrIp": "10.0.0.0/16"}]
    }
  ]'
```

> **WHY:** The internal NLB sends traffic to NodePort services (including the router's NodePort for ingress). Restricting the source to the VPC CIDR ensures only the internal NLB (and not the internet) can reach NodePorts.

```bash
# Rule 5: Allow node-to-node communication (TCP 9000-9999)
aws ec2 authorize-security-group-ingress \
  --group-id $WORKER_SG_ID \
  --ip-permissions '[
    {
      "IpProtocol": "tcp",
      "FromPort": 9000,
      "ToPort": 9999,
      "UserIdGroupPairs": [{"GroupId": "'$WORKER_SG_ID'"}]
    }
  ]'
```

> **WHY:** Ports 9000-9999 are used by various OpenShift node-level services: node-exporter (9100), OVN metrics (9105), and other monitoring/health endpoints. These are internal cluster operations that should only be accessible from other worker nodes.

#### VPC Endpoints (Required for Private Clusters)

Private clusters without internet egress need VPC Endpoints for AWS services:

```bash
# S3 Gateway Endpoint (free, no hourly charge)
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids $PRIVATE_RT_ID \
  --vpc-endpoint-type Gateway
```

> **WHY:** ROSA uses S3 for container image layers (from ECR), cluster backups, and OIDC configuration. Without this endpoint, the cluster cannot pull images or authenticate with IAM.

```bash
# ECR API Interface Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.ecr.api \
  --subnet-ids $PRIVATE_SUBNET_IDS \
  --security-group-ids $VPCE_SG_ID \
  --vpc-endpoint-type Interface \
  --private-dns-enabled

# ECR Docker Registry Interface Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.ecr.dkr \
  --subnet-ids $PRIVATE_SUBNET_IDS \
  --security-group-ids $VPCE_SG_ID \
  --vpc-endpoint-type Interface \
  --private-dns-enabled
```

> **WHY:** ECR API (ecr.api) handles authentication and image manifest retrieval. ECR Docker (ecr.dkr) handles image layer downloads. Both are needed for the cluster to pull container images from ECR. Without these, pods will be stuck in `ImagePullBackOff`.

```bash
# STS Interface Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.sts \
  --subnet-ids $PRIVATE_SUBNET_IDS \
  --security-group-ids $VPCE_SG_ID \
  --vpc-endpoint-type Interface \
  --private-dns-enabled
```

> **WHY:** STS (Security Token Service) is how ROSA HCP assumes IAM roles. The cluster's OIDC provider uses STS to get temporary credentials for pods (via IRSA — IAM Roles for Service Accounts). Without STS access, the cluster cannot authenticate to AWS services.

```bash
# EC2 Interface Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.ec2 \
  --subnet-ids $PRIVATE_SUBNET_IDS \
  --security-group-ids $VPCE_SG_ID \
  --vpc-endpoint-type Interface \
  --private-dns-enabled

# ELB Interface Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.elasticloadbalancing \
  --subnet-ids $PRIVATE_SUBNET_IDS \
  --security-group-ids $VPCE_SG_ID \
  --vpc-endpoint-type Interface \
  --private-dns-enabled
```

> **WHY:** EC2 endpoint is needed for the machine-api operator to manage worker nodes (scaling, health checks). ELB endpoint is needed for the ingress operator to create and manage load balancers. Without these, the cluster cannot scale workers or create Services of type LoadBalancer.

```bash
# Security group for VPC Endpoints
VPCE_SG_ID=$(aws ec2 create-security-group \
  --group-name "rosa-vpce-sg" \
  --description "SG for ROSA VPC Endpoints" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $VPCE_SG_ID \
  --ip-permissions '[
    {
      "IpProtocol": "tcp",
      "FromPort": 443,
      "ToPort": 443,
      "IpRanges": [{"CidrIp": "10.0.0.0/16"}]
    }
  ]'
```

> **WHY:** VPC Endpoint interfaces create ENIs in your subnets. These ENIs need a security group that allows HTTPS (port 443) from the VPC CIDR, since all AWS API calls use HTTPS.

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

> **WHY:** This blocks all traffic to and from every pod in the namespace by default. You then add specific allow rules for the traffic patterns you need (next step). Without a default-deny, any pod in the namespace can talk to any other pod in the cluster — violating the principle of least privilege.

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

> **WHY:** This allows only the OpenShift router pods (in the `openshift-ingress` namespace) to reach your application. No other pod in the cluster can directly access your app — they must go through the router (which enforces TLS, rate limits, and access logs).

```bash
# Allow DNS egress (essential for any pod that needs name resolution)
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

> **WHY:** If you have a default-deny egress policy but forget to allow DNS (port 53), every DNS lookup fails. Pods can't resolve service names, external hostnames, or anything. This is one of the most common mistakes when implementing network policies.

#### RBAC

```bash
# Read-only role for operations team
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

cat <<'EOF' | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: network-viewer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: network-viewer
subjects:
- kind: Group
  name: network-ops
  apiGroup: rbac.authorization.k8s.io
EOF
```

> **WHY:** Least-privilege access. Network operations teams need to see pods, services, endpoints, and network policies for troubleshooting, but they shouldn't be able to create or modify them. This role gives read-only access to all networking-relevant resources.

### 12.2 S2 — Hybrid Cluster Security Bundle

This bundle secures a ROSA HCP cluster with connectivity to on-premises networks via Transit Gateway.

#### Route Table Controls (NOT Security Groups on TGW)

**Important correction:** Transit Gateway attachments do NOT have security groups. You cannot attach a SG to a TGW attachment. Instead, you control TGW traffic using:

1. **VPC route tables** — which destination CIDRs are routed to the TGW
2. **TGW route tables** — which attachments receive which routes
3. **Security groups on worker nodes** — which traffic workers accept
4. **NACLs on subnets** — which traffic enters/leaves subnets

```bash
# Restrict VPC route table: only route specific on-prem CIDRs to TGW
# DO NOT add a default route (0.0.0.0/0) to TGW unless you want
# all internet traffic to go through on-prem.

# Only route the database subnet to TGW
aws ec2 create-route \
  --route-table-id $PRIVATE_RT_ID \
  --destination-cidr-block 192.168.10.0/24 \
  --transit-gateway-id $TGW_ID

# Only route the monitoring subnet to TGW
aws ec2 create-route \
  --route-table-id $PRIVATE_RT_ID \
  --destination-cidr-block 192.168.20.0/24 \
  --transit-gateway-id $TGW_ID
```

> **WHY:** By routing only specific on-prem subnets (not all of 192.168.0.0/16), you limit the blast radius. If the TGW connection is compromised, only the explicitly routed subnets are reachable from the VPC. Do not route broad CIDRs unless necessary.

```bash
# TGW route table: control which attachments see which routes
# This prevents other VPCs attached to the same TGW from reaching ROSA

TGW_RT_ID=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=transit-gateway-id,Values=$TGW_ID" \
  --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
  --output text)

# Create a static route: ROSA VPC CIDR → ROSA VPC attachment only
aws ec2 create-transit-gateway-route \
  --transit-gateway-route-table-id $TGW_RT_ID \
  --destination-cidr-block 10.0.0.0/16 \
  --transit-gateway-attachment-id $ROSA_TGW_ATTACH_ID
```

#### On-Prem Firewall Rules

```text
# On your on-prem firewall, allow only the specific traffic pattern:

# Allow ROSA worker nodes to reach the database
allow src 10.0.0.0/16 dst 192.168.10.50/32 port 5432 proto tcp

# Allow ROSA worker nodes to reach monitoring
allow src 10.0.0.0/16 dst 192.168.20.10/32 port 9090 proto tcp

# Deny everything else from ROSA
deny src 10.0.0.0/16 dst any

# Note: Source is 10.0.0.0/16 (VPC CIDR), not 10.128.0.0/14 (pod CIDR),
# because OVN SNATs pod IPs to node IPs before they leave the node.
```

> **WHY:** On-prem firewall rules use the VPC CIDR (node IPs) as the source, not the pod CIDR. Remember: OVN SNATs pod traffic to node IPs. If you write rules allowing 10.128.0.0/14 on your on-prem firewall, they won't match any traffic because by the time packets reach on-prem, the source is a node IP in 10.0.0.0/16.

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

> **WHY:** This policy allows db-client pods to only reach the on-prem database (192.168.10.50:5432) and DNS (port 53 for name resolution). All other egress is blocked. If the pod is compromised, the attacker can only reach the database — not the internet, not other on-prem systems, not other pods.

#### mTLS with Service Mesh (Optional Hardening)

```bash
# Install OpenShift Service Mesh operator first (via OperatorHub)

# Label namespace for sidecar injection
oc label namespace hybrid-app istio-injection=enabled

# Enforce strict mTLS for all traffic in the namespace
cat <<'EOF' | oc apply -n hybrid-app -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
spec:
  mtls:
    mode: STRICT
EOF

# Authorization policy: only allow db-client to call the database proxy
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

> **WHY:** mTLS ensures all pod-to-pod traffic within the mesh is encrypted and authenticated. Even if an attacker gains access to the node network, they can't read or inject traffic between pods because it's encrypted. The AuthorizationPolicy adds identity-based access control — only the db-client service account can connect to the db-proxy. This is defense-in-depth on top of NetworkPolicies.

---

## 13. Scenario Matrix & Traffic Exposure Table

### 13.1 Scenario Matrix

| # | Scenario | App Use Case | Traffic Type | Ingress Path | Egress Path | Exposure Level |
|---|----------|-------------|-------------|-------------|-------------|---------------|
| 1 | **Public App** | Public websites, SaaS APIs | HTTP/HTTPS | Internet → Route 53 → Public NLB → Router → Pod | Pod → OVN SNAT → NAT GW → IGW → Internet | Public LB with Elastic IPs, internet-routable |
| 2 | **Private App** | Internal corporate apps | HTTP/HTTPS | Corp → VPN/TGW/DX → Internal NLB → Router → Pod | Pod → OVN SNAT → NAT GW → Internet (or TGW → on-prem) | No public IPs, reachable only from connected networks |
| 3 | **Zero-Egress** | Regulated (HIPAA, PCI) | HTTP/TCP | Same as Private | Pod → VPC Endpoints only (no NAT GW, no internet) | No outbound internet at all |
| 4 | **Hybrid App** | Apps with on-prem DB | TCP | Public or Private | Pod → OVN SNAT → VPC route → TGW → On-prem | Node IP visible to on-prem, BGP-routed |
| 5 | **Service Mesh** | Microservices with mTLS | gRPC/mTLS | Mesh gateway (Istio) | Sidecar → OVN → NAT/TGW | L7-enforced, encrypted pod-to-pod |
| 6 | **Custom Front Door** | WAF, client cert auth | HTTPS | Internet → Customer ALB/WAF → ROSA NLB → Router → Pod | Same as Public | TLS terminated at customer's ALB, re-encrypted to ROSA |
| 7 | **Inter-Cluster** | Multi-region, DR | gRPC/mTLS | Cluster A → TGW/VPN → Cluster B NLB → Router → Pod | Same path, reverse direction | L3 routed between VPCs, typically private |
| 8 | **Registry Heavy** | CI/CD pipelines | HTTPS | N/A | Pod → NAT GW/VPC Endpoint → ECR/Quay | Outbound HTTPS only, high bandwidth |
| 9 | **Observability** | Logs, metrics, traces | OTLP/HTTP | N/A | Pod → NAT GW → Datadog/Splunk/etc | Outbound only, high volume |
| 10 | **Node-to-Node** | SDN overlay | Geneve/UDP 6081 | N/A | N/A | L2.5 overlay, never leaves VPC |
| 11 | **Control Plane** | API server ↔ kubelet | HTTPS | PrivateLink (bidirectional) | PrivateLink | L3 private tunnel, never traverses internet |

### 13.2 Traffic Exposure Table

| Traffic Flow | Source IP Seen by Destination | Encryption | AWS Components Traversed | K8s Components Traversed |
|-------------|------------------------------|-----------|------------------------|------------------------|
| Internet → App | Client's public IP (in X-Forwarded-For) | TLS (edge terminated at router) | IGW, NLB | OVN, Router, Service, Pod |
| Corp → Private App | Corp client IP | TLS | TGW/VPN, Internal NLB | OVN, Router, Service, Pod |
| Pod → Internet | NAT GW Elastic IP | TLS (app-initiated) | OVN SNAT, NAT GW, IGW | OVN SNAT |
| Pod → On-prem DB | Node IP (OVN SNAT) | Optional (app-level) | OVN SNAT, TGW/VPN | OVN SNAT |
| Pod → Pod (same node) | Pod IP (no SNAT) | None (unless mesh) | None | OVS br-int |
| Pod → Pod (cross node) | Pod IP (no SNAT) | None (unless mesh) | Geneve over VPC | OVS br-int, Geneve tunnel |
| Pod → Service | Pod IP | None (unless mesh) | None | OVN DNAT, OVS |
| Pod → AWS Service (w/ VPCE) | Node IP (OVN SNAT) | TLS | OVN SNAT, VPC Endpoint ENI | OVN SNAT |
| Pod → AWS Service (w/o VPCE) | NAT GW Elastic IP | TLS | OVN SNAT, NAT GW, IGW | OVN SNAT |
| API Server → Kubelet | PrivateLink ENI IP | TLS (mutual) | PrivateLink | Kubelet |
| oc CLI → API Server | User's IP → PrivateLink ENI | TLS | PrivateLink | API Server |

### 13.3 Port Reference

| Port | Protocol | Purpose | Used By |
|------|---------|---------|---------|
| 6443 | TCP | Kubernetes API server | oc, kubelets, controllers |
| 10250 | TCP | Kubelet API | API server (for logs/exec) |
| 6081 | UDP | Geneve overlay tunnels | OVN-Kubernetes (cross-node pod traffic) |
| 30000-32767 | TCP | NodePort range | Services (NLB targets) |
| 443 | TCP | HTTPS (general) | Everything external |
| 80 | TCP | HTTP (redirects to 443) | Router |
| 53 | UDP/TCP | DNS | CoreDNS |
| 9000-9999 | TCP | Node metrics/health | Prometheus, node-exporter |
| 4789 | UDP | VXLAN (legacy, not default) | Not used in OVN mode |
| 5432 | TCP | PostgreSQL | Example on-prem DB |

---

## 14. Complete Command Reference

### 14.1 Cluster Creation

#### Public ROSA HCP Cluster

```bash
# Login
rosa login --token="${ROSA_TOKEN}"

# Create account roles
rosa create account-roles --mode auto --yes

# Create OIDC config
OIDC_ID=$(rosa create oidc-config --mode auto --yes --output json | jq -r '.id')

# Create operator roles
rosa create operator-roles --oidc-config-id $OIDC_ID --installer-role-arn arn:aws:iam::role/ManagedOpenShift-Installer-Role --mode auto --yes

# Create cluster
rosa create cluster \
  --cluster-name my-public-hcp \
  --sts \
  --hosted-cp \
  --region us-east-1 \
  --subnet-ids "subnet-pub1,subnet-pub2,subnet-priv1,subnet-priv2" \
  --oidc-config-id $OIDC_ID \
  --mode auto \
  --yes

# Wait for cluster to be ready
rosa logs install --cluster my-public-hcp --watch

# Create admin user
rosa create admin --cluster my-public-hcp
```

#### Private ROSA HCP Cluster

```bash
rosa create cluster \
  --cluster-name my-private-hcp \
  --sts \
  --hosted-cp \
  --region us-east-1 \
  --private \
  --subnet-ids "subnet-priv1,subnet-priv2" \
  --oidc-config-id $OIDC_ID \
  --mode auto \
  --yes
```

> **WHY:** The `--private` flag creates the cluster with no public API endpoint and an internal-only ingress controller. The API server is accessible only via PrivateLink, and the default ingress uses an internal NLB. You need VPN/TGW/Direct Connect access to the VPC to use `oc` commands.

### 14.2 Ingress Configuration

```bash
# Check current ingress controller configuration
oc get ingresscontroller default -n openshift-ingress-operator -o yaml

# Make ingress internal-only (annotation on the router Service)
oc -n openshift-ingress annotate service router-default \
  service.beta.kubernetes.io/aws-load-balancer-internal="true" \
  --overwrite

# Verify the NLB is internal
oc get svc router-default -n openshift-ingress -o jsonpath='{.metadata.annotations}'

# Create an edge-terminated Route
oc create route edge my-app \
  --service=my-app-svc \
  --hostname=my-app.apps.mycluster.example.com \
  --cert=tls.crt \
  --key=tls.key \
  --ca-cert=ca.crt

# Create a passthrough Route
oc create route passthrough my-tls-app \
  --service=my-tls-app-svc \
  --hostname=my-tls-app.apps.mycluster.example.com
```

### 14.3 Network Policy Examples

```bash
# List all network policies in all namespaces
oc get networkpolicy -A

# Default deny all traffic in a namespace
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

# Allow ingress from specific namespace
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

# Allow egress to specific external CIDR
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

# Check all pods in openshift-ingress (router pods)
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

# Test cross-node pod connectivity
POD1_IP=$(oc get pod pod1 -o jsonpath='{.status.podIP}')
oc exec pod2 -- ping -c 3 $POD1_IP

# Check Service endpoints
oc get endpoints my-service -n my-namespace

# Check OVN flows on a node
oc debug node/ip-10-0-2-10.ec2.internal -- chroot /host ovs-ofctl dump-flows br-int

# Check OVN SNAT rules
oc debug node/ip-10-0-2-10.ec2.internal -- chroot /host ovn-nbctl lr-nat-list ovn_cluster_router

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-abc123 \
  --query 'SecurityGroups[0].IpPermissions'

# Check VPC route table
aws ec2 describe-route-tables --route-table-ids rtb-abc123

# Check NAT Gateway status
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[*].[NatGatewayId,State,PublicIp]'

# Check VPC Endpoints
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[*].[ServiceName,State,VpcEndpointType]' --output table

# Check load balancer health
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# Packet capture on a node
oc debug node/ip-10-0-2-10.ec2.internal -- chroot /host tcpdump -i any -c 100 port 6081

# Collect must-gather for networking
oc adm must-gather --dest-dir=/tmp/network-debug -- /usr/bin/gather_network_logs
```

### 14.5 Security Validation Commands

```bash
# Verify security group rules are correct
aws ec2 describe-security-groups --group-ids $WORKER_SG_ID \
  --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[*].CidrIp,UserIdGroupPairs[*].GroupId]' \
  --output table

# Verify NACLs are not blocking traffic
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkAcls[*].[NetworkAclId,IsDefault,Entries[*].[RuleNumber,Protocol,RuleAction,CidrBlock,Egress]]' \
  --output json

# Verify VPC Endpoints are operational
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[*].[ServiceName,State]' --output table

# Test VPC Endpoint connectivity from a pod
oc run vpce-test --image=registry.access.redhat.com/ubi9/ubi --rm -it --restart=Never -- \
  curl -sI https://sts.us-east-1.amazonaws.com

# Verify NetworkPolicies are enforced
oc get networkpolicy -n my-namespace -o yaml

# Check if pods can communicate that shouldn't
oc exec blocked-pod -- curl -s --connect-timeout 3 http://sensitive-service:8080 && echo "FAIL: should be blocked" || echo "OK: blocked as expected"

# Verify TGW routes
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $TGW_RT_ID \
  --filters "Name=type,Values=static,propagated" \
  --query 'Routes[*].[DestinationCidrBlock,Type,TransitGatewayAttachments[0].ResourceType]' \
  --output table
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
    ├── Check NAT Gateway: aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID"
    │   ├── State != "available" → NAT GW is down, recreate it
    │   └── State = "available" → NAT GW is fine
    │
    ├── Check route table: aws ec2 describe-route-tables --route-table-ids $RT_ID
    │   ├── Missing 0.0.0.0/0 → nat-xxx route? → Add it:
    │   │   aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID
    │   └── Route exists? → Route table is fine
    │
    ├── Check Security Group egress rules:
    │   ├── Egress to 0.0.0.0/0 allowed? → SG is fine
    │   └── Egress restricted? → Add: allow all outbound (or specific ports)
    │
    ├── Check NACL outbound rules:
    │   ├── Explicit DENY matching the traffic? → Fix NACL
    │   └── ALLOW rules present? → NACL is fine
    │
    └── Check NetworkPolicy egress:
        ├── Default-deny egress in place? → Need allow rule for 0.0.0.0/0:443
        └── No egress policy? → Problem is at AWS layer, not K8s layer
```

### 15.2 External Users Can't Reach the App

```text
Symptom: curl https://my-app.apps.mycluster.example.com → timeout or error

Q: Does DNS resolve?
├── NO: dig my-app.apps.mycluster.example.com
│   ├── NXDOMAIN? → Check Route 53 for *.apps wildcard record
│   │   → Private cluster? DNS only resolves from within VPC/connected networks
│   └── Wrong IP? → Check if NLB changed, update Route 53
│
└── YES: DNS resolves to NLB IP
    ├── Check NLB health: aws elbv2 describe-target-health --target-group-arn $TG_ARN
    │   ├── All targets "unhealthy"? → SG blocking NLB → Node health check port
    │   │   → Check: worker node SG allows NLB SG on port 30000-32767
    │   └── Some targets "healthy"? → NLB is fine
    │
    ├── Check router pods: oc get pods -n openshift-ingress
    │   ├── Not running? → Check router deployment: oc get deployment -n openshift-ingress
    │   └── Running? → Router is fine
    │
    ├── Check Route object: oc get route my-app -n my-namespace
    │   ├── Not found? → Create the Route
    │   ├── Host mismatch? → Fix the hostname in the Route spec
    │   └── Route exists with correct host? → Route is fine
    │
    ├── Check Service endpoints: oc get endpoints my-app-svc -n my-namespace
    │   ├── No endpoints? → Pods aren't running or labels don't match Service selector
    │   └── Endpoints exist? → Service is fine
    │
    └── Check pod health: oc get pods -n my-namespace -l app=my-app
        ├── CrashLoopBackOff? → App is crashing, check logs
        ├── Not Ready? → Readiness probe failing, check probe config
        └── Running and Ready? → App issue (check if it binds to correct port)
```

### 15.3 Pod-to-Pod Communication Fails

```text
Symptom: oc exec pod-a -- curl http://pod-b-ip:8080 → timeout

Q: Are pods on the same node?
├── YES (same node):
│   ├── Check OVS bridge: oc debug node/NODE -- chroot /host ovs-vsctl show
│   │   └── br-int exists with correct ports? → OVS is fine
│   ├── Check NetworkPolicy: oc get networkpolicy -n my-namespace
│   │   └── Default deny without allow rule? → Add allow rule
│   └── Check pod is listening: oc exec pod-b -- ss -tlnp
│
└── NO (cross-node):
    ├── Check Geneve tunnel:
    │   ├── SG allows UDP 6081 between workers? (most common issue!)
    │   │   → aws ec2 describe-security-groups --group-ids $WORKER_SG
    │   └── SG OK? → Check OVN pods: oc get pods -n openshift-ovn-kubernetes
    │
    ├── Check OVN controller on both nodes:
    │   ├── ovnkube-node pods running? → oc get pods -n openshift-ovn-kubernetes -o wide
    │   └── Logs show errors? → oc logs -n openshift-ovn-kubernetes ovnkube-node-XXXXX
    │
    └── Check MTU:
        └── Geneve adds 50-100 bytes overhead. If VPC MTU is 1500 and pod MTU is also 1500,
            encapsulated packets will be too large. Pod MTU should be ~1400.
            Check: oc exec pod-a -- ip link show eth0 | grep mtu
```

### 15.4 Pod Can't Reach On-Prem Database

```text
Symptom: oc exec db-client -- nc -zv 192.168.10.50 5432 → timeout

Q: Can the node reach on-prem?
├── Test from node: oc debug node/NODE -- chroot /host curl -s telnet://192.168.10.50:5432
│
├── NO (node can't reach on-prem either):
│   ├── Check VPC route table for 192.168.10.0/24 → TGW route exists?
│   │   └── Missing? → Add route: aws ec2 create-route ... --transit-gateway-id $TGW_ID
│   ├── Check TGW attachment: aws ec2 describe-transit-gateway-attachments
│   │   └── State != "available"? → TGW attachment issue
│   ├── Check BGP session: aws ec2 describe-vpn-connections (look for BGP status)
│   │   └── BGP DOWN? → Check on-prem router BGP config
│   └── Check on-prem firewall: does it allow src 10.0.0.0/16 dst 192.168.10.50:5432?
│
└── YES (node reaches on-prem, but pod doesn't):
    ├── Check OVN SNAT: oc debug node/NODE -- chroot /host ovn-nbctl lr-nat-list ovn_cluster_router
    │   └── SNAT rule for 10.128.0.0/14 → node IP exists? → OVN SNAT is fine
    ├── Check NetworkPolicy egress:
    │   └── Egress policy blocking 192.168.10.50:5432?
    │       → Add allow rule for that specific CIDR and port
    └── Check on-prem firewall allows the node's source IP
        → Remember: pods appear as NODE IP due to SNAT, not pod IP
```

### 15.5 Cluster API Unreachable

```text
Symptom: oc get pods → connection refused / timeout

For Private Clusters:
├── Are you connected to the VPC? (VPN/TGW/Direct Connect/bastion)
│   └── NO → You cannot reach a private API from the internet
│
├── Check PrivateLink endpoint: aws ec2 describe-vpc-endpoints
│   └── State != "available"? → PrivateLink issue, contact Red Hat support
│
├── Check DNS resolution: dig api.mycluster.abcd.p1.openshiftapps.com
│   └── Resolves to PrivateLink ENI IP? → DNS is fine
│       Does NOT resolve? → Check Route 53 private hosted zone association
│
└── Check Security Group on PrivateLink ENI:
    └── Allows TCP 6443 from your source? → SG is fine
        Blocks your source? → Update SG

For Public Clusters:
├── Check DNS: dig api.mycluster.abcd.p1.openshiftapps.com
│   └── Resolves? → DNS is fine
│
├── Check connectivity: curl -sI https://api.mycluster.abcd.p1.openshiftapps.com:6443
│   └── Connection refused? → API server issue (Red Hat side)
│       Timeout? → Network issue (your side — firewall, proxy)
│
└── Check cluster status: rosa describe cluster -c mycluster
    └── State = "error"? → Contact Red Hat support
```

---

## Appendix A: Glossary Quick Reference

| Term | Layer | One-Line Definition |
|------|-------|-------------------|
| ALB | L7 | AWS application load balancer, routes by HTTP headers/paths |
| ASN | BGP | Unique number identifying an autonomous system (network) |
| BGP | L3 | Routing protocol for exchanging routes between networks |
| br-int | OVS | OVN's integration bridge connecting all local pods |
| CIDR | L3 | Notation for IP ranges (e.g., 10.0.0.0/16) |
| ClusterIP | K8s | Virtual IP for a Kubernetes Service, exists only as DNAT rules |
| CNI | K8s | Standard interface between container runtime and network plugin |
| CoreDNS | K8s | DNS server inside the cluster resolving service names |
| CRI-O | K8s | Container runtime used by OpenShift (like Docker) |
| DNAT | L3 | Destination NAT — rewriting the destination IP of a packet |
| EIP | AWS | Elastic IP — a static public IPv4 address you own |
| ENA | AWS | Elastic Network Adapter — AWS's custom network driver |
| ENI | AWS | Elastic Network Interface — virtual NIC attached to instances |
| eth0 | Linux | Primary network interface inside a Linux system |
| Geneve | L2.5 | Tunnel encapsulation protocol for overlay networks (UDP 6081) |
| HAProxy | L7 | The reverse proxy that powers the OpenShift router |
| HCP | ROSA | Hosted Control Plane — control plane in Red Hat's VPC |
| IGW | AWS | Internet Gateway — connects VPC to the internet |
| kubelet | K8s | Agent on each node that manages pods |
| MTU | L2 | Maximum Transmission Unit — max packet size (usually 1500 bytes) |
| Multus | K8s | Meta-CNI for attaching multiple networks to a pod |
| NACL | AWS | Network ACL — stateless subnet-level firewall |
| NAT GW | AWS | NAT Gateway — outbound internet for private subnets |
| Nitro | AWS | Custom hardware platform powering EC2 instances |
| NLB | L4 | AWS network load balancer, routes by IP/port |
| NodePort | K8s | Port opened on every node for external Service access |
| OVN | SDN | Open Virtual Network — virtual networking for OpenShift |
| OVS | SDN | Open vSwitch — virtual switch in the Linux kernel |
| PrivateLink | AWS | Private connection between VPCs that stays on AWS backbone |
| Route | OCP | OpenShift object defining hostname → Service mapping |
| Route 53 | AWS | Amazon's DNS service |
| SG | AWS | Security Group — stateful instance-level firewall |
| SNAT | L3 | Source NAT — rewriting the source IP of a packet |
| SR-IOV | HW | Hardware virtualization of network cards for near-native performance |
| STS | AWS | Security Token Service — issues temporary IAM credentials |
| TGW | AWS | Transit Gateway — hub connecting VPCs and on-prem networks |
| TLS | L6 | Transport Layer Security — encrypts data in transit |
| veth | Linux | Virtual ethernet pair — connects pod namespace to bridge |
| VPC | AWS | Virtual Private Cloud — your isolated network in AWS |
| VPCE | AWS | VPC Endpoint — private access to AWS services |

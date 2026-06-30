---
date: '2025-02-05'
title: Accessing a Private ROSA Hosted Control Plane (HCP) Cluster with an AWS Network Load Balancer
tags: ["AWS", "ROSA"]
authors:
  - Nerav Doshi
  - Michael McNeill
---

## Overview

This guide walks through exposing the Kubernetes API of a **private** ROSA Hosted Control Plane (HCP) cluster to the Internet using an **internet-facing AWS Network Load Balancer (NLB)**. The NLB terminates TLS using an AWS Certificate Manager (ACM) certificate for your **public** API hostname and forwards traffic over TLS to the private IPs of the cluster's VPC endpoint network interfaces inside your AWS VPC.

The end-to-end traffic flow is:

```
Client (Internet)
  → DNS (api.nddemo.example.com)
  → Internet-facing NLB (TLS:443, ACM certificate for api.nddemo.example.com)
  → Target group (IP addresses, TLS:443)
  → Private IPs of ROSA HCP VPC endpoint ENIs
  → Cluster Kubernetes API
```

> Throughout this guide, **`nddemo`** is the example cluster name and **`api.nddemo.example.com`** is the example public API hostname. Replace both with your real values.

## Prerequisites

1. A **private** ROSA HCP cluster already running. See [Deploying ROSA HCP](https://docs.aws.amazon.com/rosa/latest/userguide/getting-started-hcp.html) if you need to create one.

1. **Microsoft Entra ID** configured as the external authentication provider for the cluster. See [Configuring Microsoft Entra ID as an external authentication provider](/experts/rosa/entra-external-auth/).

1. A **public domain** you control (for example `example.com`) with a **Route 53 public hosted zone** in the same AWS account. If your domain is elsewhere, see the note in the ACM validation section.

1. A way to **reach the cluster privately** for one discovery command (SSH into a jump host inside the VPC, or a VPN). If you need to create a jump host, follow [these instructions](/experts/rosa/hcp-private-nlb/rosa-private-nlb-jumphost/) before continuing.

---

## Step 1: Collect cluster information

Before touching anything in AWS, record three facts about your cluster. You will use all three throughout this guide.

### 1a. AWS Region

1. Sign in to the [Red Hat Hybrid Cloud Console](https://console.redhat.com).
1. Go to **OpenShift** → **Clusters** and open **`nddemo`**.
1. On the cluster detail page, find **Region** (for example **us-east-1**). Write it down.
1. For the rest of this guide, the AWS Management Console **Region selector** (top-right corner) must always be set to **this Region**.

### 1b. Private API hostname

1. On the same cluster detail page, find **API URL** (for example `https://api.nddemo.abcd1234.p3.openshiftapps.com`).
1. Copy only the **hostname** portion (everything after `https://` and before the first `/`). You will use this to find the private IPs in Step 2.

### 1c. Cluster VPC ID

1. In the **AWS Management Console**, confirm the Region is set correctly (Step 1a).
1. Open **VPC** → **Your VPCs**.
1. Find the VPC that belongs to cluster `nddemo`. The **Name** or tags often include the cluster name or the word **ROSA**. If unsure, open each VPC and look at its **Tags** for `red-hat-clustertype=rosa` or the cluster name.
1. Copy the **VPC ID** (for example `vpc-0abc1234def56789`). Write it down.

---

## Step 2: Discover the private target IP addresses

The NLB needs to forward traffic to **private IPv4 addresses** inside your VPC. For ROSA HCP private clusters these are the addresses of the **interface VPC endpoint** elastic network interfaces (ENIs) that front the cluster API.

> Run the `dig` command from a machine that has **private** network access to the cluster VPC (jump host, VPN-connected laptop, or AWS CloudShell scoped to the right VPC). It will not work from a machine on the public Internet.

1. On a host with private VPC connectivity, run the following command. Replace the hostname with the **private API hostname** from Step 1b.

   ```bash
   dig +short api.nddemo.abcd1234.p3.openshiftapps.com
   ```

1. The output is one or more **private** IPv4 addresses, for example:

   ```
   10.0.1.45
   10.0.2.78
   ```

1. Write down **every** IP address returned. You need all of them for the target group in Step 5.

**If `dig` returns nothing or a public address,** you may need to query from inside the VPC where split-horizon DNS is in effect, or the private hosted zone may not be attached to your jump host's VPC. Contact the team that installed the cluster for the correct private IPs.

**Alternatively, find the IPs in the AWS Console:**

1. Go to **EC2** → **Network Interfaces**.
1. In the **Filters** bar, choose **VPC** and paste the VPC ID from Step 1c.
1. Look for interfaces whose **Description** references an **ELB** for the cluster API or a **VPC endpoint**. The IPs you need are under **Primary private IPv4 address** on each relevant interface.

---

## Step 3: Decide your public API hostname

Choose the public hostname that Internet clients (and `oc`/`kubectl`) will use. It must be a name within the domain of your Route 53 public hosted zone.

For this guide the hostname is **`api.nddemo.example.com`** and the hosted zone is **`example.com`**. Replace both with your values.

---

## Step 4: Request an ACM certificate

The ACM certificate tells the NLB which TLS name to present to connecting clients.

1. In the AWS Management Console, open **Certificate Manager (ACM)**. Confirm the Region is correct (Step 1a).
1. Choose **Request certificate**.
1. Choose **Request a public certificate** → **Next**.
1. Under **Fully qualified domain name** enter: `api.nddemo.example.com`
1. Under **Validation method** choose **DNS validation**.
1. Leave all other settings at their defaults.
1. Choose **Request**.

ACM immediately creates the certificate in **Pending validation** status. Leave this page open and continue to Step 5 to complete validation.

---

## Step 5: Complete ACM DNS validation in Route 53

ACM proves you own the domain by checking for a specific **CNAME record** that it generates. You create that record in Route 53.

1. On the ACM certificate detail page, find the **Domains** section.
1. You will see a row for `api.nddemo.example.com` with two values:
   - **CNAME name** — a string beginning with `_` followed by a random token (for example `_a1b2c3d4e5f6.api.nddemo.example.com`)
   - **CNAME value** — a string ending with `acm-validations.aws.`
1. Choose **Create records in Route 53**. A dialog lists the hosted zone where AWS will insert the record.
1. Confirm the zone shown is the **public** hosted zone for `example.com` (not a private zone).
1. Choose **Create records**.
1. Return to the ACM certificate page and wait for **Status** to change from **Pending validation** to **Issued**. This normally takes two to five minutes. Refresh the page periodically.

> **If "Create records in Route 53" does not appear:** Your public hosted zone may be in a different account or the domain does not match. In that case, copy the **CNAME name** and **CNAME value** shown by ACM and manually create a **CNAME** record in whichever DNS system is authoritative for `example.com` on the public Internet. Once ACM detects the record it will issue the certificate.

> **If the certificate reaches a FAILED status:** ACM validation requests expire. Delete the failed certificate and start again from Step 4. The most common causes are: the CNAME was added to a **private** hosted zone instead of the **public** one, or the domain has a **CAA record** that does not allow Amazon to issue certificates (check by running `dig CAA example.com` and ensure it includes `amazon.com` or `amazontrust.com`, or is empty).

Once the certificate shows **Issued**, copy the **Certificate ARN** shown at the top of the detail page (for example `arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). You will need it in Step 8.

---

## Step 6: Create a security group for the NLB

1. In the AWS Console, go to **EC2** → **Security Groups** → **Create security group**.
1. Fill in the fields:
   - **Security group name:** `nddemo-public-nlb-sg`
   - **Description:** `Public NLB for nddemo API`
   - **VPC:** Select the **cluster VPC** from Step 1c.
1. Under **Inbound rules**, choose **Add rule** and fill in:
   - **Type:** `HTTPS`
   - **Protocol:** `TCP` (filled automatically)
   - **Port range:** `443`
   - **Source:** Choose **My IP** to restrict access to your current IP address for initial testing. For broader access, enter a specific CIDR range (for example `203.0.113.0/24`). Avoid `0.0.0.0/0` in production environments.
1. Leave **Outbound rules** at their defaults (allow all outbound traffic).
1. Choose **Create security group**.

---

## Step 7: Create a target group

1. Go to **EC2** → **Target Groups** → **Create target group**.

### Basic configuration

| Field | Value |
|-------|-------|
| **Choose a target type** | **IP addresses** |
| **Target group name** | `nddemo-api-tg` |
| **Protocol** | **TLS** |
| **Port** | `443` |
| **IP address type** | `IPv4` |
| **VPC** | Select the **cluster VPC** from Step 1c |
| **Protocol version** | `HTTP1` (default; leave as-is) |

### Health checks

Scroll to the **Health checks** section and set:

| Field | Value |
|-------|-------|
| **Health check protocol** | **TCP** |
| **Health check port** | **Traffic port** |

Leave all other health check settings at their defaults.

Choose **Next**.

### Register targets

1. Under **IP addresses**, in the **IPv4 address** box enter the **first** private IP from Step 2 (for example `10.0.1.45`).
1. Set **Port** to `443`.
1. Choose **Add IPv4 address** and repeat for each additional IP from Step 2.
1. Once all IPs appear in the table under **Review targets**, choose **Create target group**.

After creation, open the target group, go to the **Targets** tab, and check the **Health status** column. Targets will initially show **initial** and then move to **healthy** once the NLB exists and health checks begin. Continue to Step 8 now; you will verify health after the NLB is created.

---

## Step 8: Create the internet-facing Network Load Balancer

1. Go to **EC2** → **Load Balancers** → **Create load balancer**.
1. Under **Network Load Balancer**, choose **Create**.

### Basic configuration

| Field | Value |
|-------|-------|
| **Load balancer name** | `nddemo-public-api-nlb` |
| **Scheme** | **Internet-facing** |
| **IP address type** | **IPv4** |

### Network mapping

| Field | Value |
|-------|-------|
| **VPC** | Select the **cluster VPC** from Step 1c |
| **Mappings** | Enable **at least two** Availability Zones. For each enabled zone, open the **Subnet** dropdown and select the **public subnet** for that zone (a public subnet has a route to an Internet Gateway in its route table). If you do not have public subnets in the cluster VPC, you must create them before proceeding. |

### Security groups

Select **`nddemo-public-nlb-sg`** (created in Step 6). Remove any default security group if AWS adds one automatically.

### Listeners and routing

| Field | Value |
|-------|-------|
| **Protocol** | **TLS** |
| **Port** | `443` |
| **Default action** | **Forward to** `nddemo-api-tg` |

### Secure listener settings

1. Under **Security policy**, leave the default TLS policy (for example `ELBSecurityPolicy-TLS13-1-2-2021-06`) unless your organization requires a different policy.
1. Under **Default SSL/TLS server certificate**, choose **From ACM**.
1. In the certificate dropdown, select the certificate for **`api.nddemo.example.com`** (the one you created and validated in Steps 4 and 5).

Choose **Create load balancer**.

### After creation

1. Open **`nddemo-public-api-nlb`** from the load balancers list.
1. On the **Details** tab, copy the **DNS name** (for example `nddemo-public-api-nlb-1234567890.us-east-1.elb.amazonaws.com`). You need this in Step 9.
1. Now go back to **EC2 → Target Groups → `nddemo-api-tg` → Targets** tab. Within two to three minutes of the NLB being active, targets should show **healthy**. If they remain **unhealthy**, see the troubleshooting section at the end of this guide before continuing.

---

## Step 9: Create a Route 53 alias record

This step makes `api.nddemo.example.com` resolve to the NLB on the public Internet.

1. Open **Route 53** → **Hosted zones**.
1. Open the **public** hosted zone for **`example.com`**. Confirm it says **Public** in the **Type** column. Do not use a private hosted zone.
1. Choose **Create record**.
1. Fill in the fields:

| Field | Value |
|-------|-------|
| **Record name** | `api.nddemo` (Route 53 appends `.example.com` automatically since you are inside the `example.com` zone) |
| **Record type** | **A** |
| **Alias** | Toggle **on** |
| **Route traffic to** | **Alias to Network Load Balancer** |
| **Region** | Select the same Region as the NLB (Step 1a) |
| **Load balancer** | Select **`nddemo-public-api-nlb`** from the dropdown |
| **Routing policy** | **Simple routing** |
| **Evaluate target health** | **Yes** (default) |

5. Choose **Create records**.

DNS propagation typically completes within a minute or two because Route 53 Alias records resolve immediately for AWS resources. Verify with:

```bash
dig +short api.nddemo.example.com
```

The output should return the NLB's IP addresses (which change over time as AWS manages the fleet; this is normal for NLB DNS).

---

## Step 10: Validate the connection

### Validate TLS and API reachability

Run this from a laptop or workstation on the **public** Internet:

```bash
curl -v https://api.nddemo.example.com/version
```

Expected output (HTTP 200 with cluster version JSON, or HTTP 401/403 if unauthenticated access is blocked):

```json
{
  "major": "1",
  "minor": "30",
  "gitVersion": "v1.30.7",
  "gitCommit": "abc123",
  "gitTreeState": "clean",
  "buildDate": "2024-11-23T03:11:13Z",
  "goVersion": "go1.21.12",
  "compiler": "gc",
  "platform": "linux/amd64"
}
```

A successful TLS handshake with no certificate warning confirms:
- The ACM certificate for `api.nddemo.example.com` is attached to the NLB correctly.
- Route 53 is pointing to the NLB.
- The NLB is forwarding requests to the backend.

---

## Step 11: Configure `oc` to use the public endpoint

Create a kubeconfig file to authenticate against the cluster using the public NLB hostname and Entra ID OIDC.

1. Create a file named `rosa-auth.kubeconfig` with the following content. Replace `api.nddemo.example.com` with your real public hostname, and substitute your Entra ID `TENANT_ID`, `CLIENT_ID`, and `CLIENT_SECRET`.

   ```yaml
   apiVersion: v1
   clusters:
   - cluster:
       server: https://api.nddemo.example.com
     name: nddemo
   contexts:
   - context:
       cluster: nddemo
       namespace: default
       user: oidc
     name: nddemo
   current-context: nddemo
   kind: Config
   preferences: {}
   users:
   - name: oidc
     user:
       exec:
         apiVersion: client.authentication.k8s.io/v1
         command: kubectl
         args:
         - oidc-login
         - get-token
         - --oidc-issuer-url=https://login.microsoftonline.com/YOUR_TENANT_ID/v2.0
         - --oidc-client-id=YOUR_CLIENT_ID
         - --oidc-client-secret=YOUR_CLIENT_SECRET
         - --oidc-extra-scope=email
         - --oidc-extra-scope=openid
         env: null
         interactiveMode: Never
   ```

   > The `server` field must be a plain `https://` URL. Do not append `:443` — HTTPS already implies port 443.

1. Set the `KUBECONFIG` environment variable:

   ```bash
   export KUBECONFIG=$(pwd)/rosa-auth.kubeconfig
   ```

1. Verify cluster access:

   ```bash
   oc get nodes
   ```

   Expected output:

   ```
   NAME                         STATUS   ROLES    AGE     VERSION
   ip-10-0-0-170.ec2.internal   Ready    worker   3h29m   v1.30.7
   ip-10-0-1-171.ec2.internal   Ready    worker   3h30m   v1.30.7
   ip-10-0-2-161.ec2.internal   Ready    worker   3h29m   v1.30.7
   ```

1. Confirm the authenticated identity:

   ```bash
   oc auth whoami
   ```

   Expected output:

   ```
   ATTRIBUTE   VALUE
   Username    you@example.com
   Groups      [system:authenticated]
   ```

---

## Troubleshooting

### Targets show unhealthy

| Check | How to verify |
|-------|---------------|
| The IPs in the target group are the correct private addresses for the cluster API | Re-run `dig +short <private-api-hostname>` from inside the VPC and compare to the IPs registered in the target group |
| Security groups allow TCP 443 from NLB subnets to the target IPs | Open **EC2 → Network Interfaces**, find the ENI for each target IP, open its security group, and confirm TCP 443 inbound from the VPC CIDR or NLB subnets is allowed |
| The NLB subnets can route to the target IPs | Open the **Route Table** for each NLB public subnet and confirm there is a route for the cluster VPC CIDR (needed if the NLB uses a different subnet range than the targets) |
| Network ACLs on the target subnets allow return traffic | NACLs are stateless; confirm both inbound (TCP 443 from NLB subnets) and outbound (ephemeral ports back) are permitted |

### ACM certificate shows FAILED

1. Delete the failed certificate in ACM.
1. Check whether your domain has a **CAA** record that prevents Amazon from issuing: run `dig CAA example.com` (use your root domain). If a CAA record exists, it must include `0 issue "amazon.com"` or `0 issue "amazontrust.com"`.
1. Request a new certificate (Step 4) and complete validation promptly.

### curl returns a certificate name mismatch error

The ACM certificate and the Route 53 record must share the **same** hostname. Confirm:
- The certificate in ACM covers exactly `api.nddemo.example.com` (not a wildcard or different name).
- The Route 53 record name resolves to exactly `api.nddemo.example.com`.
- The certificate is attached to the **TLS listener** on the NLB (open **Load Balancers → `nddemo-public-api-nlb` → Listeners** and confirm the certificate ARN matches).

### DNS does not resolve

Confirm the Route 53 record was created in the **public** hosted zone. A private hosted zone is only resolvable inside the VPC. On the Route 53 **Hosted zones** page, the **Type** column must say **Public** for the zone where the record lives.

---

## Resource summary

| Resource | Name used in this guide |
|----------|------------------------|
| Cluster | `nddemo` |
| Public API hostname | `api.nddemo.example.com` |
| ACM certificate | For `api.nddemo.example.com` in the cluster Region |
| Security group | `nddemo-public-nlb-sg` |
| Target group | `nddemo-api-tg` (TLS:443, IP addresses) |
| Network Load Balancer | `nddemo-public-api-nlb` (internet-facing, TLS:443) |
| Route 53 record | Alias A for `api.nddemo.example.com` → NLB |

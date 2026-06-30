
# ROSA HCP Private Ingress to Public Access Troubleshooting Guide

This guide outlines steps to troubleshoot external connectivity to a ROSA Highly Available Control Plane (HCP) cluster when its default ingress is configured for private access (using AWS Network Load Balancers and VPC Endpoints), and then provides a solution to securely expose applications publicly.

## 1. Problem Statement

You can successfully connect to your sample application from an EC2 bastion host *within* your Virtual Private Cloud (VPC) that hosts the ROSA worker nodes. However, you cannot access the application from a web browser *outside* your VPC (e.g., from your local machine or the public internet). You have observed a Network Load Balancer (NLB) listed in Route 53 and VPC Endpoints within your VPC related to the cluster's ingress.

## 2. Understanding the Private Ingress Configuration

When you deployed your private ROSA HCP cluster, the ingress was likely configured using AWS PrivateLink, which creates:

* **AWS Network Load Balancer (NLB):** This NLB resides in your private subnets and acts as the internal entry point for traffic into your OpenShift Ingress Controller (Routers).

* **VPC Endpoints (Interface Endpoints):** These endpoints are established in your customer VPC, enabling secure, private communication from within your VPC to services hosted behind the NLB, without traffic leaving your private AWS network.

**Key Implication:** This setup is designed for **internal network access only**. To expose applications to the public internet, an *additional* public-facing load balancer or ingress mechanism is required.

## 3. Troubleshooting Existing Setup

Before implementing a solution, let's confirm the current configuration and internal connectivity.

### 3.1 Verify Your Cluster's Ingress Configuration

Determine how your ROSA cluster's ingress is specifically configured.

* **Check ROSA Cluster Details (using `rosa` CLI):**

  ```bash
  rosa describe cluster --cluster <your-cluster-name> -o json | jq '.ingress'
  rosa describe cluster --cluster <your-cluster-name> -o json | jq '.private_link'
  ```

  Look for fields like `private_link_ingress: true` or any other indications that the ingress is private.

* **Inspect OpenShift Ingress Controller (using `oc` CLI):**
  The `IngressController` resource defines the ingress behavior within OpenShift.

  ```bash
  oc get ingresscontroller default -n openshift-ingress-operator -o yaml
  ```

  Examine the `endpointPublishingStrategy` section:

  * If `type: LoadBalancerService` and `loadBalancer.scope: Internal`, this confirms an internal (private) load balancer.

  * If `loadBalancer.scope: External`, it would imply a public load balancer. ROSA HCP clusters typically default to an NLB for private ingress.

### 3.2 Confirm Internal Connectivity to NLB/VPC Endpoint

You've confirmed basic internal access. Let's trace it to the NLB.

* **Identify Private IP Addresses of the ROSA NLB:**
  You can find the private IP addresses associated with the NLB provisioned by ROSA. These NLB IPs reside in your private subnets.

  1. **Get the NLB Hostname from the OpenShift Service:**

     ```bash
     oc get service router-default -n openshift-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
     ```

     This will output the internal DNS name of the NLB.

  2. **Resolve the NLB Hostname to its Private IPs (from your bastion host):**

     ```bash
     dig +short <NLB_HOSTNAME_FROM_ABOVE_COMMAND>
     ```

     This will give you the private IP addresses of the NLB nodes in your VPC.

  3. **Test direct connectivity to NLB from bastion host:**
     From your bastion host, try to connect directly to these private IP addresses on the port your application listens on (e.g., 80 or 443).

     ```bash
     curl http://<NLB_PRIVATE_IP>:80/
     # or
     telnet <NLB_PRIVATE_IP> 80
     ```

     This verifies that traffic can reach the NLB's private IPs and that the NLB is forwarding to your OpenShift Ingress Controllers/Pods.

* **Check AWS VPC Endpoint Status and Security Groups:**

  1. In the AWS Management Console, navigate to **VPC > Endpoints**.

  2. Locate the VPC Endpoint(s) associated with your ROSA cluster's ingress.

  3. **Status:** Ensure the status is `Available`.

  4. **Security Groups:** Verify the security group(s) attached to the VPC Endpoint. They **must** allow inbound TCP traffic from your worker nodes' security group (or the CIDR range of your worker nodes) on the relevant ports (e.g., 80, 443, and any control plane ports if applicable, though ROSA manages control plane access separately).

## 4. Solution for Public Access: Chaining a Public ALB to the Private NLB

Since your ROSA cluster's ingress is private, the standard solution to expose applications publicly is to deploy a **public-facing AWS Application Load Balancer (ALB)** and configure it to forward traffic to the private NLB.

### 4.1 Prerequisites

* **Public Subnets:** Ensure you have dedicated public subnets in your VPC (with routes to an Internet Gateway). Your initial setup should have created these.

* **SSL/TLS Certificate (Optional but Recommended for HTTPS):** If you plan to serve HTTPS, you'll need an ACM certificate in the same region as your ALB.

### 4.2 Steps to Implement Public ALB Chaining

1. **Create a New Public Application Load Balancer (ALB):**

   * Go to the AWS EC2 console -> **Load Balancing** -> **Load Balancers**.

   * Click **Create Load Balancer**.

   * Choose **Application Load Balancer** and click **Create**.

   * **Basic configuration:**

     * **Load balancer name:** Give it a descriptive name (e.g., `my-app-public-alb`).

     * **Scheme:** Select `Internet-facing`.

     * **IP address type:** `IPv4`.

   * **Network mapping:**

     * **VPC:** Select the VPC where your ROSA cluster resides.

     * **Mappings:** Select **at least two of your public subnets** (e.g., `PUBLIC_SUBNET_ID_A`, `PUBLIC_SUBNET_ID_B`) across different Availability Zones.

   * **Security groups:**

     * Click **Create a new security group**.

     * **Security group name:** `my-public-alb-sg` (or similar).

     * **Description:** "Allows public HTTP/S access to ALB".

     * **Inbound rules:**

       * Add a rule: `Type: HTTP`, `Source: Anywhere-IPv4 (0.0.0.0/0)`.

       * (Optional) Add a rule: `Type: HTTPS`, `Source: Anywhere-IPv4 (0.0.0.0/0)` if you plan to use HTTPS.

     * Click **Create security group**, then select this new security group for your ALB.

   * **Listeners and routing:**

     * **Listener 1:**

       * **Protocol: Port:** `HTTP: 80`.

       * **Default action:** Select `Create target group`.

       * **Target group name:** `rosa-private-ingress-tg` (or similar).

       * **Target type:** Select `IP addresses`. **This is crucial.**

       * **Protocol: Port:** `TCP: 80` (or 443 if your NLB is configured for TLS).

       * **VPC:** Your ROSA cluster's VPC.

       * **Health checks:**

         * **Protocol:** `HTTP`

         * **Path:** `/` (or a specific health check path your Nginx app exposes).

         * Leave other health check settings as default or adjust as needed.

       * Click **Next** to create the target group.

       * **Register targets:** In the "Register targets" step, use the **private IP addresses of your ROSA NLB nodes** that you identified in Section 3.2. Add them to the target group.

     * (Optional) **Add another listener for HTTPS (port 443):**

       * **Protocol: Port:** `HTTPS: 443`.

       * **Default action:** Forward to the `rosa-private-ingress-tg` target group.

       * **Default SSL certificate:** Choose an existing certificate from AWS Certificate Manager (ACM) or import one.

   * Review and **Create load balancer**.

2. **Configure Security Group for your ROSA Private NLB/VPC Endpoint:**
   The security group(s) attached to the OpenShift-managed NLB (or the associated VPC Endpoint security groups that restrict access to the NLB) must allow inbound traffic from the **security group of your newly created public ALB**.

   * Go to **EC2 -> Security Groups**.

   * Find the security group(s) associated with the NLB/VPC Endpoint that ROSA created (often named similar to `sg-<cluster-id>-elb` or within the network interfaces of the NLB).

   * **Inbound rules:** Add a new rule:

     * **Type:** `Custom TCP` (or `HTTP`/`HTTPS` if specific).

     * **Port range:** `80` (and `443` if using HTTPS).

     * **Source:** Select the security group ID of your **newly created public ALB** (e.g., `sg-xxxxxxxxxxxxxxxxx` or search for `my-public-alb-sg`). This ensures only your public ALB can send traffic to the private NLB.

3. **Update DNS in Route 53:**

   * Go to the AWS Route 53 console -> **Hosted zones**.

   * Select the public hosted zone for your domain (e.g., `example.com`).

   * Click **Create record**.

   * **Routing policy:** `Simple routing`.

   * **Record name:** Enter the desired hostname for your application (e.g., `myapp`).

   * **Value/Route traffic to:** Select `Alias to Application and Classic Load Balancer`.

   * **Choose region:** Select your AWS region.

   * **Choose load balancer:** Select the **DNS name of your newly created public ALB**.

   * **Record type:** `A - Routes traffic to an IPv4 address and some AWS resources`.

   * Click **Create records**.

### 4.3 Access Your Application

After a few minutes for DNS propagation, you should now be able to access your application from a public browser using the URL you configured (e.g., `http://myapp.example.com`).

## 5. Advanced Tracing and Debugging

If the public access still fails after implementing the above solution, use these tools for deeper investigation:

### 5.1 AWS VPC Flow Logs

* **Enable Flow Logs:** Configure VPC Flow Logs for your VPC, focusing on the public subnets (where the public ALB resides) and the private subnets (where the private NLB and worker nodes are). Capture logs for all traffic.

* **Analyze Logs:** Review the logs in Amazon S3 or CloudWatch Logs. Look for:

  * Traffic from your public IP address reaching the public ALB's network interfaces.

  * Traffic flowing from the public ALB's network interfaces to the private NLB's network interfaces on the configured ports.

  * Traffic flowing from the private NLB's network interfaces to your OpenShift worker nodes (router pods).

  * Any `REJECT` actions, which indicate a security group or NACL is blocking traffic.

### 5.2 AWS CloudWatch Metrics

* **Public ALB Metrics:**

  * Navigate to **CloudWatch -> Metrics** and filter by `AWS/ApplicationELB`.

  * Check metrics for your public ALB: `HealthyHostCount`, `UnHealthyHostCount` (for its target group pointing to the private NLB), `HTTPCode_Target_5XX_Count`, `ClientTLSNegotiationErrorCount` (if HTTPS).

  * `TargetConnectionErrorCount` will be crucial if the ALB cannot connect to the private NLB.

* **Private NLB Metrics (ROSA Managed):**

  * Filter by `AWS/NetworkELB`. You might need to find the specific NLB provisioned by ROSA.

  * Check `HealthyHostCount`/`UnHealthyHostCount` (for its target group pointing to your router pods), `ActiveFlowCount`, `NewFlowCount`.

### 5.3 AWS CloudTrail

* Review CloudTrail logs in the AWS Console. Look for API calls related to:

  * `elbv2` (Elastic Load Balancing V2 - for ALBs and NLBs)

  * `ec2` (for security group, network interface, subnet changes)

  * `route53` (for DNS record updates)

  * Any `AccessDenied` errors or failed operations during cluster creation or subsequent modifications.

### 5.4 Packet Capture on OpenShift Nodes (`tcpdump`)

If VPC Flow Logs indicate traffic reaching your worker nodes but the application isn't responding, get a more granular view of traffic on the node itself.

1. **Identify a Worker Node:**

   ```bash
   oc get nodes
   ```

2. **Start a Debug Pod on the Node:**

   ```bash
   oc debug node/<worker-node-name>
   ```

3. **Change Root to Host Filesystem:**

   ```bash
   chroot /host
   ```

4. **Perform Packet Capture:**

   ```bash
   tcpdump -i any -nn port 80 or port 443 # Monitor traffic on the application ports
   ```

   While this is running, try to access your application from the public internet. Observe if packets arrive at the node and if the router pod responds.

5. **Exit Debug Session:**

   ```bash
   exit # Exit chroot
   exit # Exit the debug pod
   ```

By following these structured troubleshooting steps, you should be able to diagnose and resolve the external access issue for your ROSA HCP application.

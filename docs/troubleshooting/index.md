# **ROSA Cluster Troubleshooting Guide**

This guide provides detailed steps to troubleshoot common issues encountered with a new Red Hat OpenShift Service on AWS (ROSA) cluster, specifically focusing on connection timeouts when deploying from self-hosted GitLab and internal routing problems with DockerHub containers.

## **Table of Contents**

1. [General Troubleshooting Principles](#bookmark=id.9i043qurb7a5)  
2. [Issue 1: new-app from Self-Hosted GitLab \- Connection Timeout](#bookmark=id.h3bctwvxe1b7)  
   * [2.1 Verify Network Connectivity](#bookmark=id.m19evesix8h5)  
   * [2.2 DNS Resolution](#bookmark=id.ukh4f9hnqdrl)  
   * [2.3 TLS/SSL Certificates](#bookmark=id.eqp8cu1o50xc)  
   * [2.4 Proxy Configuration](#bookmark=id.ky7oj3vlaait)  
   * [2.5 GitLab Instance Health](#bookmark=id.l7i7r1m8gjtz)  
3. [Issue 2: DockerHub Container Deployment \- Internal Routing Not Working](#bookmark=id.3rah3awmyeza)  
   * [3.1 Missing or Incorrect Service](#bookmark=id.meltksph3yt5)  
   * [3.2 Missing or Incorrect Route](#bookmark=id.ag90zmybnxe4)  
   * [3.3 Pod Readiness Probes Failing](#bookmark=id.37qt2psohgpk)  
   * [3.4 Network Policy (if enabled)](#bookmark=id.nkuponbz7kko)  
   * [3.5 Internal DNS within the Cluster](#bookmark=id.dfsioryb9uck)  
   * [3.6 Ingress Controller Health](#bookmark=id.iq4b81f9v5bm)  
4. [AWS Network Configuration Deep Dive (Security Groups, NACLs, Route Tables)](#bookmark=id.ahpor1n2zbuk)  
   * [4.1 Identify ROSA VPC and Subnets](#bookmark=id.7z8kie79bjt9)  
   * [4.2 Inspect Security Groups](#bookmark=id.mdw7tomylu4n)  
   * [4.3 Inspect Network Access Control Lists (NACLs)](#bookmark=id.mf3e1t84nfxb)  
   * [4.4 Inspect Route Tables](#bookmark=id.5e43g34twxoy)  
   * [4.5 Check NAT Gateway (if used)](#bookmark=id.nvb3025kc8h4)

## **1\. General Troubleshooting Principles**

Before diving into specifics, remember these fundamental steps:

* **Check Logs First:** Application logs, build logs, and operator logs often contain explicit error messages.  
  * oc logs \<pod-name\> \-n \<namespace\>  
  * oc logs \--previous \<pod-name\> \-n \<namespace\> (for crashed pods)  
* **Describe Resources:** Get detailed information about your OpenShift objects.  
  * oc describe \<resource-type\>/\<resource-name\> \-n \<namespace\>  
* **Verify Status:** Check the status of your deployments, pods, and other OpenShift components.  
  * oc get all \-n \<namespace\>  
  * oc get co (ClusterOperators)  
* **Network Connectivity from Pods:** Test connectivity from inside a problematic pod or a dedicated test pod.

## **2\. Issue 1: new-app from Self-Hosted GitLab \- Connection Timeout**

A connection timeout during new-app from a self-hosted GitLab instance usually indicates a network blockage or a certificate trust issue preventing the OpenShift build process from reaching your GitLab server.

### **2.1 Verify Network Connectivity**

This is the most common culprit. Your ROSA cluster's worker nodes (where builds run) need outbound access to your GitLab.

1. Deploy a Test Pod:  
   Create a temporary pod in the same namespace where you are trying to run new-app.  
   oc run connectivity-test \--image=registry.access.redhat.com/ubi8/ubi-minimal \-- sleep 3600 \-n \<your-project-namespace\>

2. Test DNS Resolution from Pod:  
   Get inside the pod and check if it can resolve your GitLab hostname.  
   oc exec \-it connectivity-test \-n \<your-project-namespace\> \-- nslookup \<your-gitlab-hostname\>  
   \# Example: oc exec \-it connectivity-test \-n my-app-project \-- nslookup gitlab.mycompany.com

   * **Expected:** Returns the correct IP address(es) for your GitLab server.  
   * **If Fails:** DNS issue. Check your AWS VPC's DNS resolvers and custom DNS configurations.  
3. Test TCP Port Connectivity from Pod:  
   Attempt to connect to your GitLab instance on the required ports (e.g., 443 for HTTPS, 22 for SSH/Git).  
   * **For HTTPS (if using https:// Git URLs):**  
     oc exec \-it connectivity-test \-n \<your-project-namespace\> \-- curl \-vvv https://\<your-gitlab-hostname-or-ip\>:443

     * **Look For:** Connected to \<your-gitlab-hostname-or-ip\> (\<IP\>) port 443 (\#0).  
     * **If it hangs/times out:** Network blockage.  
     * **If you get a certificate error after connecting:** Connectivity is good, but a TLS/SSL certificate issue (see Section 2.3).  
   * **For SSH/Git (if using git@ Git URLs):**  
     oc exec \-it connectivity-test \-n \<your-project-namespace\> \-- bash \-c "yum install \-y nmap-ncat && nc \-vz \<your-gitlab-hostname-or-ip\> 22"  
     \# Or if curl is sufficient:  
     \# oc exec \-it connectivity-test \-n \<your-project-namespace\> \-- curl \-v telnet://\<your-gitlab-hostname-or-ip\>:22

     * **Look For:** "Connection to ... succeeded\!".  
     * **If it hangs/times out:** Network blockage.  
4. **Clean up the test pod:**  
   oc delete pod connectivity-test \-n \<your-project-namespace\>

### **2.2 DNS Resolution**

If nslookup failed in the previous step:

1. **VPC DHCP Option Sets:** In your AWS VPC, verify the DHCP Option Sets associated with your ROSA VPC have correct DNS server configurations.  
2. **Route 53 Private Hosted Zones:** If your GitLab hostname is resolved via a Private Hosted Zone in Route 53, ensure that it's correctly linked to your ROSA VPC.

### **2.3 TLS/SSL Certificates**

If curl connected but showed certificate errors (e.g., "SSL certificate problem: self-signed certificate in certificate chain"):

1. **Obtain GitLab CA Certificate:** Get the public CA certificate chain for your self-hosted GitLab instance. This might be a .crt file.  
2. **Create a ConfigMap in OpenShift:**  
   oc create configmap gitlab-ca \--from-file=ca.crt=/path/to/your/gitlab-ca.crt \-n openshift-config

   (Replace /path/to/your/gitlab-ca.crt with the actual path to your CA certificate file).  
3. Update Cluster-Wide Proxy (if applicable):  
   If you have a cluster-wide proxy configured, you might need to add the CA certificate to its trusted CAs.  
   oc edit proxy/cluster

   Add or modify the spec.trustedCA field to reference your ConfigMap:  
   apiVersion: config.openshift.io/v1  
   kind: Proxy  
   metadata:  
     name: cluster  
   spec:  
     \# ... other proxy settings  
     trustedCA:  
       name: gitlab-ca

4. **Update ImageStreams/BuildConfigs:** For new-app to trust the certificate during builds, ensure your ImageStream or BuildConfig references the additionalTrustedCA field. OpenShift builds typically use the cluster's trusted CA bundle. If the cluster-wide proxy update doesn't suffice, you might need to ensure your BuildConfig has something like this:  
   \# Example snippet for BuildConfig  
   apiVersion: build.openshift.io/v1  
   kind: BuildConfig  
   spec:  
     \# ...  
     source:  
       type: Git  
       git:  
         uri: 'https://\<your-gitlab-hostname\>/\<your-repo\>.git'  
       sourceSecret:  
         name: gitlab-credentials \# if you use credentials  
     \# Add this to trust your CA during the build  
     strategy:  
       type: Docker \# or Source  
       dockerStrategy:  
         from:  
           kind: DockerImage  
           name: 'registry.access.redhat.com/ubi8/nodejs-16:latest' \# Example base image  
         pullSecret:  
           name: pull-secret-for-registry \# if pulling from a private registry  
         \# This is key for adding trusted CA to the build environment  
         additionalTrustedCA:  
           name: gitlab-ca

   Alternatively, ensure your cluster-wide trustedCA in the Proxy object is properly applied, as it should inject the CA into builder pods automatically.

### **2.4 Proxy Configuration**

If your ROSA cluster operates behind an outbound proxy:

1. **Check Cluster Proxy Settings:**  
   oc get proxy/cluster \-o yaml

   Ensure httpProxy, httpsProxy, and noProxy are correctly configured to allow traffic to your GitLab instance. noProxy should include your GitLab's hostname and IP if it's internal.  
2. **Verify Operator Proxy Settings:** Some operators might need specific proxy environment variables. This is less common for new-app itself but good to keep in mind for other deployments.

### **2.5 GitLab Instance Health**

Ensure your self-hosted GitLab instance is operational and accessible from other networks.

1. **Basic Access:** Can you access your GitLab instance from a machine outside your ROSA cluster (e.g., your local workstation, a separate EC2 instance) using a web browser and Git commands?  
2. **Resource Utilization:** Check GitLab's server resources (CPU, Memory, Disk) to ensure it's not overloaded, which could cause timeouts.

## **3\. Issue 2: DockerHub Container Deployment \- Internal Routing Not Working**

This means your container deployed successfully, but traffic isn't reaching it inside the cluster or from external routes.

### **3.1 Missing or Incorrect Service**

An OpenShift Service object is essential for internal routing to your pods.

1. **Verify Service Existence:**  
   oc get svc \-n \<your-project-namespace\>

   Look for a Service matching your application name. If it's missing, you need to create one.  
   \# Example: Expose a Deployment as a Service  
   oc expose deployment/\<your-deployment-name\> \--port=\<container-port\> \--target-port=\<container-port\> \-n \<your-project-namespace\>

2. Check Service Selector:  
   The selector on your Service must match the labels on your application's pods.  
   * Get your Service details:  
     oc describe svc/\<your-service-name\> \-n \<your-project-namespace\>

     Look for Selector: app=\<your-app-label\> or similar.  
   * Get your Pod labels:  
     oc get pods \-l app=\<your-app-label\> \-n \<your-project-namespace\> \--show-labels

     * **Ensure:** The labels specified in the Service's selector precisely match the labels on your running pods. If they don't, the Service won't route traffic to those pods. Edit your Deployment/DeploymentConfig to add the correct labels.

### **3.2 Missing or Incorrect Route**

A Route exposes your Service to external (or internal, via the ingress controller) traffic.

1. **Verify Route Existence:**  
   oc get route \-n \<your-project-namespace\>

   Look for a Route matching your application. If it's missing, create one.  
   \# Example: Expose a Service as a Route  
   oc expose svc/\<your-service-name\> \--hostname=\<your-desired-hostname\> \-n \<your-project-namespace\>

2. **Check Route Target and TLS:**  
   * Get your Route details:  
     oc describe route/\<your-route-name\> \-n \<your-project-namespace\>

     * **Verify Service Name:** Ensure it points to the correct Service you verified in Section 3.1.  
     * **Check TLS Termination:** If you intend for HTTPS traffic, ensure TLS termination is configured (e.g., edge, passthrough, reencrypt). If your app handles its own TLS, use passthrough. If OpenShift terminates TLS, use edge or reencrypt.

### **3.3 Pod Readiness Probes Failing**

If your pods aren't marked as "Ready", the Service won't send traffic to them.

1. **Check Pod Status:**  
   oc get pods \-n \<your-project-namespace\>

   Look for pods that are not in a Running and Ready state (e.g., 0/1 Ready, CrashLoopBackOff, Pending).  
2. **Check Pod Events and Logs:**  
   * Examine pod events for startup issues:  
     oc describe pod/\<your-pod-name\> \-n \<your-project-namespace\>

   * Review pod logs for application-specific errors:  
     oc logs pod/\<your-pod-name\> \-n \<your-project-namespace\>

   * **Focus on:** Application startup errors, port binding issues (is your app listening on the container-port specified in the Deployment?), and failures related to environment variables or configuration.  
3. Review Readiness/Liveness Probes:  
   If your Deployment includes readinessProbe or livenessProbe, ensure they are correctly configured and the application is responding as expected on the probed path/port. A failing readiness probe will prevent the pod from receiving traffic.

### **3.4 Network Policy (if enabled)**

If Network Policies are active, they can restrict traffic flow between pods or from the ingress controller.

1. **List Network Policies:**  
   oc get networkpolicy \-n \<your-project-namespace\>

2. **Evaluate Policies:** Review any policies that apply to your application's pods.  
   * By default, NetworkPolicy mode might deny all ingress to pods unless explicitly allowed.  
   * You might need to create a Network Policy that allows ingress traffic from the openshift-ingress namespace (or openshift-ingress-operator) if your pods are intended to be accessible via Routes.  
   * Example allowing ingress from openshift-ingress and the same namespace:  
     apiVersion: networking.k8s.io/v1  
     kind: NetworkPolicy  
     metadata:  
       name: allow-app-traffic  
       namespace: \<your-project-namespace\>  
     spec:  
       podSelector:  
         matchLabels:  
           app: \<your-app-label\> \# Matches your application pods  
       ingress:  
       \- from:  
         \- podSelector: {} \# Allows traffic from other pods in the same namespace  
         \- namespaceSelector:  
             matchLabels:  
               network.openshift.io/policy-group: ingress \# Allows traffic from OpenShift Ingress Controller  
       policyTypes:  
       \- Ingress

### **3.5 Internal DNS within the Cluster**

If your DockerHub container needs to communicate with other services *within* the OpenShift cluster, verify internal DNS.

1. Test Internal Service Resolution:  
   From your application's pod (or the connectivity-test pod from 2.1):  
   oc exec \-it \<your-app-pod-name\> \-n \<your-project-namespace\> \-- nslookup \<target-service-name\>.\<target-namespace\>.svc.cluster.local  
   \# Example: oc exec \-it my-app-pod \-n my-app-project \-- nslookup database-service.default.svc.cluster.local

   * **Expected:** Returns the Cluster IP of the target service.  
   * **If Fails:** Investigate CoreDNS in openshift-dns namespace and ensure pod-to-pod networking is functional.

### **3.6 Ingress Controller Health**

While ROSA manages this, it's good to rule out issues with the cluster's ingress.

1. **Check Ingress Operator Status:**  
   oc get co ingress  
   oc describe co ingress

   Look for any Degraded or Progressing status conditions.  
2. **Check Router Pods:**  
   oc get pods \-n openshift-ingress \-l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default  
   oc logs \-n openshift-ingress \<router-pod-name\>

   Look for errors in the router logs that might indicate issues processing routes.

## **4\. AWS Network Configuration Deep Dive (Security Groups, NACLs, Route Tables)**

This section details how to check the underlying AWS network components that ROSA uses. **This is critical for both GitLab timeouts and external access to your DockerHub app.**

### **4.1 Identify ROSA VPC and Subnets**

1. **ROSA Console:** In the Red Hat OpenShift Cluster Manager, navigate to your cluster and find the associated VPC ID and Subnet IDs.  
2. **AWS EC2 Console:** Go to "Network Interfaces". Filter by the ROSA VPC ID. You'll see network interfaces for your Control Plane, Infrastructure, and Worker nodes. Note the Subnet IDs associated with your **worker nodes**.

### **4.2 Inspect Security Groups**

Security Groups act as a virtual firewall for EC2 instances and ENIs.

1. **Navigate:** Go to **AWS EC2 console \> Security Groups**.  
2. **Identify Worker Node Security Groups:** Find the security groups attached to the network interfaces of your ROSA worker nodes. ROSA creates specific security groups for this.  
3. **Check Outbound (Egress) Rules for Worker Nodes:**  
   * **For GitLab:** Ensure there's an **Egress Rule** allowing TCP traffic on ports 443 (HTTPS) and/or 22 (SSH) to your GitLab server's specific IP address/CIDR or 0.0.0.0/0 (all outbound traffic).  
   * **For DockerHub (Image Pulls):** Ensure there's an **Egress Rule** allowing TCP traffic on port 443 to 0.0.0.0/0 (internet). This is typically set by default.  
   * **Common Issue:** Overly restrictive egress rules. Ensure All Traffic or specific ports are open for the necessary destinations.  
4. **Inspect GitLab Server Security Group (if GitLab is in AWS):**  
   * **Check Inbound (Ingress) Rules:** Ensure there's an **Ingress Rule** allowing TCP traffic on ports 443 and/or 22 from the CIDR range of your ROSA worker node subnets. If your ROSA cluster uses a NAT Gateway for egress, you might need to allow traffic from the NAT Gateway's Elastic IP.

### **4.3 Inspect Network Access Control Lists (NACLs)**

NACLs are stateless firewalls at the subnet level. They process rules in order (lowest number first).

1. **Navigate:** Go to **AWS VPC console \> Network ACLs**.  
2. **Identify Subnet NACLs:** Find the NACLs associated with the **subnets where your ROSA worker nodes reside**.  
3. **Check Outbound Rules:**  
   * Ensure rules explicitly allow outbound TCP traffic on ports 443 and/or 22 to your GitLab IP/CIDR or 0.0.0.0/0.  
   * Also, ensure rules allow outbound traffic on **ephemeral ports** (typically 1024-65535) for return traffic from your GitLab server.  
4. **Check Inbound Rules:**  
   * Ensure rules explicitly allow inbound TCP traffic on **ephemeral ports** (1024-65535) from your GitLab server's IP/CIDR or 0.0.0.0/0.  
   * **Important:** Since NACLs are stateless, you need explicit rules for both directions for the same connection.  
5. **Inspect GitLab Server NACL (if GitLab is in AWS):**  
   * Verify inbound and outbound rules on GitLab's subnet NACL mirror the requirements for the ROSA worker node NACLs, allowing traffic from/to the ROSA cluster's IP ranges on the necessary ports.

### **4.4 Inspect Route Tables**

Route tables define how network traffic is routed from a subnet.

1. **Navigate:** Go to **AWS VPC console \> Route Tables**.  
2. **Identify Worker Node Subnet Route Tables:** Find the route tables associated with the **subnets where your ROSA worker nodes are deployed**.  
3. **Check Routes:**  
   * **For GitLab:** Ensure there's a route for your GitLab server's IP address or CIDR range pointing to the correct target (e.g., igw-xxxxxxxx, nat-xxxxxxxx, pcx-xxxxxxxx for VPC peering, vgw-xxxxxxxx for VPN Gateway, or tgw-xxxxxxxx for Transit Gateway).  
   * **For DockerHub (and general internet access):** There *must* be a default route (0.0.0.0/0) pointing to an Internet Gateway (igw-xxxxxxxx) if in a public subnet, or a NAT Gateway (nat-xxxxxxxx) if in a private subnet.

### **4.5 Check NAT Gateway (if used)**

If your ROSA worker nodes are in private subnets and use a NAT Gateway for outbound internet access (common for ROSA):

1. **Navigate:** Go to **AWS VPC console \> NAT Gateways**.  
2. **Verify Status:** Ensure the NAT Gateway is in Available status.  
3. **Elastic IP:** Note the Elastic IP associated with the NAT Gateway. This is the public IP that your ROSA cluster's outbound traffic will originate from. Ensure this IP isn't blocked by any external firewalls that might be protecting your GitLab instance.

By meticulously going through these steps in your AWS environment, you should be able to identify and resolve most network connectivity issues impacting your ROSA cluster's deployments.
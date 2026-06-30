
# OpenShift / Kubernetes Port Strategy – Avoiding NodePort Exhaustion
**Author:** ND
**Date:** November 17, 2025  
**Goal:** Eliminate or dramatically reduce NodePort usage for dozens of monitoring, security, and management tools across regions without hitting the ~2768 port limit.

## Why NodePort Is Not Viable Long-Term
- Default range: 30000–32767 → only 2768 ports
- Many enterprise tools require static ports (some need 5–20+ ports each)
- Cross-region communication forces large firewall openings
- Impossible to scale when you have 50+ tools

## Recommended Architecture (Use This Combination)

| Use Case                              | Recommended Solution                          | NodePorts Consumed | Cost / Complexity |
|---------------------------------------|-----------------------------------------------|--------------------|-------------------|
| Any HTTP/S tool (Observium, Octopus, Cloud Portal, etc.) | OpenShift Route or Kubernetes Ingress        | 0                  | Low               |
| Security scanners & non-HTTP tools (Nessus, Rapid7, Axonius, etc.) | Cloud Load Balancer (AWS NLB / Azure LB / GCP) + ExternalName for cross-region | 0                  | Medium (1 LB per tool/region) |
| 20–100 legacy or mixed-port tools     | Single HAProxy/Envoy DaemonSet with hostNetwork | < 50 total         | Medium            |
| On-prem or bare-metal environments    | MetalLB in Layer2 or BGP mode                 | 0                  | Medium            |
| Quick temporary relief                | Expand NodePort range (band-aid only)         | Still limited      | Low               |

## 1. OpenShift Route (HTTP/S tools) – ZERO NodePorts

```yaml
# File: route-observium.yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: observium
  namespace: monitoring
spec:
  host: observium.hylandcloud.com
  to:
    kind: Service
    name: observium-svc
  port:
    targetPort: 80
  tls:
    termination: Edge    # or Passthrough / Reencrypt
```

## 2. Cloud LoadBalancer Service (AWS NLB example)

```yaml
# File: svc-nessus-lb.yaml
apiVersion: v1
kind: Service
metadata:
  name: nessus-lb
  namespace: security
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
spec:
  type: LoadBalancer
  selector:
    app: nessus
  ports:
    - name: ui
      port: 8834
      targetPort: 8834
      protocol: TCP
    - name: agent
      port: 8835
      targetPort: 8835
      protocol: TCP
```

Cross-region access (in another cluster):

```yaml
# File: svc-nessus-cross-region.yaml
apiVersion: v1
kind: Service
metadata:
  name: nessus-us-east-1
  namespace: security
spec:
  type: ExternalName
  externalName: a1b2c3d4e5f6g7h8i9j0.us-east-1.elb.amazonaws.com
  ports:
    - port: 8834
    - port: 8835
```

## 3. Port-Multiplexing Proxy (HAProxy DaemonSet) – One daemonset for 50+ tools

```yaml
# File: ds-port-proxy.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: port-proxy
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: port-proxy
  template:
    metadata:
      labels:
        app: port-proxy
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      tolerations:
      - operator: Exists   # run on all nodes including masters if needed
      containers:
      - name: haproxy
        image: haproxy:2.9-alpine
        volumeMounts:
        - name: haproxy-config
          mountPath: /usr/local/etc/haproxy
        securityContext:
          capabilities:
            add: ["NET_BIND_SERVICE"]   # optional, for low ports
      volumes:
      - name: haproxy-config
        configMap:
          name: port-proxy-config
```

```yaml
# File: cm-port-proxy-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: port-proxy-config
  namespace: kube-system
data:
  haproxy.cfg: |
    global
      maxconn 20000
      log stdout format raw local0 info

    defaults
      mode tcp
      timeout connect 5s
      timeout client  1m
      timeout server  1m

    # Example entries – add as many as you need
    frontend nessus
      bind *:8834
      default_backend nessus-backend
    backend nessus-backend
      server nessus nessus-svc.security.svc.cluster.local:8834

    frontend rapid7
      bind *:443
      default_backend rapid7-backend
    backend rapid7-backend
      server rapid7 rapid7-svc.security.svc.cluster.local:443

    frontend axonius
      bind *:8080
      default_backend axonius-backend
    backend axonius-backend
      server axonius axonius-svc.security.svc.cluster.local:8080
```

## 4. Expand NodePort Range (Temporary Only)

```yaml
# File: network-config-expand.yaml
apiVersion: config.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  serviceNodePortRange: "9000-32767"   # ~23k ports instead of 2768
```

Apply with: `oc apply -f network-config-expand.yaml`

## 5. MetalLB (On-Prem or Cloud with Your Own IPs)

```yaml
# After MetalLB is installed
apiVersion: v1
kind: Service
metadata:
  name: rapid7-metallb
  namespace: security
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.100.51   # from your MetalLB address pool
  ports:
  - port: 443
    targetPort: 443
  selector:
    app: rapid7
```

## Quick Decision Matrix for Your Tools

| Tool              | Recommended Method                | Reason |
|-------------------|-----------------------------------|--------|
| Observium         | OpenShift Route                   | HTTP UI |
| Cloud Portal      | OpenShift Route                   | HTTPS |
| Octopus Deploy    | OpenShift Route                   | Web UI |
| Nessus            | Cloud NLB                         | 8834/8835 TCP |
| Rapid7 InsightVM  | Cloud NLB or HAProxy DaemonSet    | 443 + agent ports |
| Axonius           | Cloud NLB or HAProxy              | 8080 |
| Ivanti / WMI / RPC| HAProxy DaemonSet (or dedicated jump VM) | Needs 135,445,dynamic ports |
| Dynatrace         | Prefer outbound (SaaS) or Route   | Usually phones home |
| VDI broker        | OpenShift Route if web, else NLB  | Depends on protocol |

Save this file as `openshift-port-strategy.md` and keep it in your team’s Git repo – it will save you when the NodePort exhaustion fire drill happens (and it will).

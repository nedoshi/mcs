# Service Mesh with EntraID on ROSA HCP External Authentication

## Prerequisites

- ROSA HCP cluster with admin access
- Microsoft EntraID tenant with admin privileges
- OpenShift CLI (`oc`) installed and configured
- Sufficient cluster resources for service mesh components

## Step 1: Install OpenShift Service Mesh Operators

### 1.1 Install Required Operators

```bash
# Install Elasticsearch Operator
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: elasticsearch-operator
  namespace: openshift-operators-redhat
spec:
  channel: stable
  installPlanApproval: Automatic
  name: elasticsearch-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Install Jaeger Operator
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: jaeger-product
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: jaeger-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Install Kiali Operator
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kiali-ossm
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: kiali-ossm
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Install Service Mesh Operator
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: servicemeshoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### 1.2 Wait for Operators to be Ready

```bash
# Check operator status
oc get csv -n openshift-operators
oc get csv -n openshift-operators-redhat
```

## Step 2: Configure EntraID Application

### 2.1 Register Application in EntraID

1. Log into Azure Portal → EntraID → App registrations
2. Click "New registration"
3. Configure:
   - **Name**: `rosa-service-mesh-auth`
   - **Supported account types**: Accounts in this organizational directory only
   - **Redirect URI**: `https://oauth-openshift.apps.<cluster-domain>/oauth2callback/entraid`

### 2.2 Configure Application Settings

```bash
# Note down these values from your EntraID app:
# - Application (client) ID
# - Directory (tenant) ID
# - Client secret (create one in "Certificates & secrets")
```

### 2.3 Configure API Permissions

1. Go to "API permissions"
2. Add permission → Microsoft Graph → Delegated permissions
3. Add: `openid`, `profile`, `email`, `User.Read`
4. Grant admin consent

### 2.4 Configure Authentication

1. Go to "Authentication"
2. Under "Implicit grant and hybrid flows", enable:
   - Access tokens
   - ID tokens

## Step 3: Create Service Mesh Control Plane Namespace

```bash
# Create istio-system namespace
oc new-project istio-system
```

## Step 4: Configure External Authentication with EntraID

### 4.1 Create EntraID OAuth Configuration

```yaml
# Create oauth-config.yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: entraid
    mappingMethod: claim
    type: OpenID
    openID:
      clientID: "<YOUR_ENTRAID_CLIENT_ID>"
      clientSecret:
        name: entraid-client-secret
      ca:
        name: ""
      extraScopes:
      - email
      - profile
      extraAuthorizeParameters: {}
      claims:
        preferredUsername:
        - preferred_username
        - upn
        name:
        - name
        email:
        - email
      issuer: "https://login.microsoftonline.com/<YOUR_TENANT_ID>/v2.0"
```

### 4.2 Create Client Secret

```bash
# Create secret for EntraID client secret
oc create secret generic entraid-client-secret \
  --from-literal=clientSecret="<YOUR_ENTRAID_CLIENT_SECRET>" \
  -n openshift-config

# Apply OAuth configuration
oc apply -f oauth-config.yaml
```

## Step 5: Install Service Mesh Control Plane

### 5.1 Create ServiceMeshControlPlane

```yaml
# Create smcp.yaml
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: basic
  namespace: istio-system
spec:
  version: v2.4
  security:
    identity:
      type: ThirdParty
    dataPlane:
      mtls: true
    controlPlane:
      mtls: true
  tracing:
    type: Jaeger
    sampling: 10000
  general:
    logging:
      logAsJSON: true
  profiles:
    - default
  addons:
    grafana:
      enabled: true
      install:
        security:
          enabled: true
    jaeger:
      install:
        storage:
          type: Memory
    kiali:
      enabled: true
      install:
        dashboard:
          enableGrafana: true
          enableTracing: true
          enablePrometheusLink: true
    prometheus:
      enabled: true
  gateways:
    additionalIngress:
      oauth-gateway:
        enabled: true
        runtime:
          deployment:
            autoScaling:
              enabled: false
        service:
          type: ClusterIP
```

### 5.2 Apply Service Mesh Control Plane

```bash
oc apply -f smcp.yaml

# Wait for installation to complete
oc get smcp -n istio-system -w
```

## Step 6: Configure Authentication Policies

### 6.1 Create RequestAuthentication Policy

```yaml
# Create request-auth.yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: entraid-jwt
  namespace: istio-system
spec:
  jwtRules:
  - issuer: "https://login.microsoftonline.com/<YOUR_TENANT_ID>/v2.0"
    jwksUri: "https://login.microsoftonline.com/<YOUR_TENANT_ID>/discovery/v2.0/keys"
    audiences:
    - "<YOUR_ENTRAID_CLIENT_ID>"
    forwardOriginalToken: true
```

### 6.2 Create Authorization Policy

```yaml
# Create authz-policy.yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: entraid-authz
  namespace: istio-system
spec:
  rules:
  - from:
    - source:
        requestPrincipals: ["https://login.microsoftonline.com/<YOUR_TENANT_ID>/v2.0/*"]
  - to:
    - operation:
        methods: ["GET", "POST"]
```

### 6.3 Apply Authentication Policies

```bash
oc apply -f request-auth.yaml
oc apply -f authz-policy.yaml
```

## Step 7: Configure Service Mesh Member Roll

### 7.1 Create Application Namespaces

```bash
# Create application namespaces
oc new-project bookinfo
oc new-project app-namespace-2
```

### 7.2 Create ServiceMeshMemberRoll

```yaml
# Create smmr.yaml
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
  namespace: istio-system
spec:
  members:
  - bookinfo
  - app-namespace-2
```

```bash
oc apply -f smmr.yaml
```

## Step 8: Configure Gateway with EntraID Authentication

### 8.1 Create EntraID Authentication Gateway

```yaml
# Create auth-gateway.yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: entraid-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: entraid-gateway-certs
    hosts:
    - "*.apps.<your-cluster-domain>"
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*.apps.<your-cluster-domain>"
    tls:
      httpsRedirect: true
```

### 8.2 Create VirtualService with Auth

```yaml
# Create auth-virtualservice.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: entraid-vs
  namespace: istio-system
spec:
  hosts:
  - "app.apps.<your-cluster-domain>"
  gateways:
  - entraid-gateway
  http:
  - match:
    - uri:
        prefix: "/oauth2/"
    route:
    - destination:
        host: oauth2-proxy.istio-system.svc.cluster.local
        port:
          number: 4180
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: your-app-service.bookinfo.svc.cluster.local
        port:
          number: 8080
```

## Step 9: Deploy OAuth2 Proxy for EntraID Integration

### 9.1 Create OAuth2 Proxy Configuration

```yaml
# Create oauth2-proxy-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oauth2-proxy-config
  namespace: istio-system
data:
  oauth2-proxy.cfg: |
    provider = "oidc"
    oidc_issuer_url = "https://login.microsoftonline.com/<YOUR_TENANT_ID>/v2.0"
    redirect_url = "https://app.apps.<your-cluster-domain>/oauth2/callback"
    upstreams = ["http://your-app-service.bookinfo.svc.cluster.local:8080"]
    http_address = "0.0.0.0:4180"
    email_domains = ["*"]
    client_id = "<YOUR_ENTRAID_CLIENT_ID>"
    cookie_secret = "<GENERATE_32_CHAR_SECRET>"
    cookie_secure = true
    cookie_httponly = true
    set_xauthrequest = true
    pass_access_token = true
    pass_user_headers = true
```

### 9.2 Create OAuth2 Proxy Secret

```bash
oc create secret generic oauth2-proxy-secret \
  --from-literal=client-secret="<YOUR_ENTRAID_CLIENT_SECRET>" \
  -n istio-system
```

### 9.3 Deploy OAuth2 Proxy

```yaml
# Create oauth2-proxy-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy
  namespace: istio-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: oauth2-proxy
  template:
    metadata:
      labels:
        app: oauth2-proxy
    spec:
      containers:
      - name: oauth2-proxy
        image: quay.io/oauth2-proxy/oauth2-proxy:latest
        args:
        - --config=/etc/oauth2-proxy/oauth2-proxy.cfg
        - --client-secret-file=/etc/oauth2-proxy/client-secret
        ports:
        - containerPort: 4180
        volumeMounts:
        - name: config
          mountPath: /etc/oauth2-proxy
          readOnly: true
        - name: secret
          mountPath: /etc/oauth2-proxy
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: oauth2-proxy-config
      - name: secret
        secret:
          secretName: oauth2-proxy-secret
---
apiVersion: v1
kind: Service
metadata:
  name: oauth2-proxy
  namespace: istio-system
spec:
  selector:
    app: oauth2-proxy
  ports:
  - port: 4180
    targetPort: 4180
```

## Step 10: Configure TLS Certificates

### 10.1 Create TLS Certificate Secret

```bash
# If using Let's Encrypt or custom certificates
oc create secret tls entraid-gateway-certs \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem \
  -n istio-system
```

## Step 11: Apply All Configurations

```bash
# Apply all configurations
oc apply -f auth-gateway.yaml
oc apply -f auth-virtualservice.yaml
oc apply -f oauth2-proxy-config.yaml
oc apply -f oauth2-proxy-deployment.yaml
```

## Step 12: Configure Kiali with EntraID Authentication

### 12.1 Update ServiceMeshControlPlane for Kiali Auth

```yaml
# Update smcp.yaml to include Kiali authentication
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: basic
  namespace: istio-system
spec:
  version: v2.4
  security:
    identity:
      type: ThirdParty
    dataPlane:
      mtls: true
    controlPlane:
      mtls: true
  tracing:
    type: Jaeger
    sampling: 10000
  general:
    logging:
      logAsJSON: true
  profiles:
    - default
  addons:
    grafana:
      enabled: true
      install:
        security:
          enabled: true
    jaeger:
      install:
        storage:
          type: Memory
    kiali:
      enabled: true
      install:
        dashboard:
          enableGrafana: true
          enableTracing: true
          enablePrometheusLink: true
          auth:
            strategy: "openid"
            openid:
              client_id: "<YOUR_ENTRAID_CLIENT_ID>"
              issuer_uri: "https://login.microsoftonline.com/<YOUR_TENANT_ID>/v2.0"
              scopes: ["openid", "profile", "email"]
              username_claim: "preferred_username"
              api_proxy: "https://kiali.apps.<your-cluster-domain>/api"
              api_proxy_ca_data: ""
    prometheus:
      enabled: true
```

### 12.2 Create Kiali Secret for EntraID

```bash
# Create Kiali OIDC secret
oc create secret generic kiali-oidc-secret \
  --from-literal=oidc-secret="<YOUR_ENTRAID_CLIENT_SECRET>" \
  -n istio-system
```

### 12.3 Create Kiali Custom Resource with EntraID

```yaml
# Create kiali-cr.yaml
apiVersion: kiali.io/v1alpha1
kind: Kiali
metadata:
  name: kiali
  namespace: istio-system
spec:
  auth:
    strategy: "openid"
    openid:
      client_id: "<YOUR_ENTRAID_CLIENT_ID>"
      client_secret: "kiali-oidc-secret:oidc-secret"
      issuer_uri: "https://login.microsoftonline.com/<YOUR_TENANT_ID>/v2.0"
      scopes: ["openid", "profile", "email"]
      username_claim: "preferred_username"
      api_proxy: "https://kiali.apps.<your-cluster-domain>"
      api_proxy_ca_data: ""
      http_proxy: ""
      https_proxy: ""
      insecure_skip_verify_tls: false
      additional_request_params: {}
  deployment:
    accessible_namespaces: ["**"]
    image_name: "kiali/kiali"
    image_version: "latest"
    ingress_enabled: true
    namespace: "istio-system"
    verbose_mode: "3"
    view_only_mode: false
  external_services:
    custom_dashboards:
      enabled: true
    grafana:
      enabled: true
      in_cluster_url: "http://grafana.istio-system:3000"
      url: "https://grafana.apps.<your-cluster-domain>"
      auth:
        type: "bearer"
        use_kiali_token: true
    istio:
      component_status:
        components:
        - app_label: "istiod"
          is_core: true
          is_proxy: false
        enabled: true
      config_map_name: "istio"
      envoy_admin_local_port: 15000
      istio_identity_domain: "cluster.local"
      istio_injection_annotation: "sidecar.istio.io/inject"
      istio_sidecar_annotation: "sidecar.istio.io/status"
      url_service_version: "http://istiod.istio-system:15014/version"
    prometheus:
      url: "http://prometheus.istio-system:9090"
    tracing:
      enabled: true
      in_cluster_url: "http://jaeger-query.istio-system:16686"
      url: "https://jaeger.apps.<your-cluster-domain>"
      use_grpc: true
  server:
    port: 20001
    web_root: "/kiali"
```

### 12.4 Create Kiali Route with Authentication

```yaml
# Create kiali-route.yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kiali
  namespace: istio-system
  annotations:
    haproxy.router.openshift.io/hsts_header: "max-age=31536000;includeSubDomains;preload"
spec:
  host: kiali.apps.<your-cluster-domain>
  to:
    kind: Service
    name: kiali
    weight: 100
  port:
    targetPort: 20001-tcp
  tls:
    termination: reencrypt
    destinationCACertificate: |
      -----BEGIN CERTIFICATE-----
      # Add your CA certificate here
      -----END CERTIFICATE-----
  wildcardPolicy: None
```

### 12.5 Configure EntraID App for Kiali

In your EntraID application registration, add these additional redirect URIs:

```
https://kiali.apps.<your-cluster-domain>/kiali
https://kiali.apps.<your-cluster-domain>/api/auth/callback
```

### 12.6 Apply Kiali Configuration

```bash
# Apply the updated SMCP
oc apply -f smcp.yaml

# Apply Kiali custom resource
oc apply -f kiali-cr.yaml

# Apply Kiali route
oc apply -f kiali-route.yaml

# Wait for Kiali to be ready
oc get kiali -n istio-system -w
```

### 12.7 Configure Kiali RBAC

```yaml
# Create kiali-rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kiali-viewer
rules:
- apiGroups: [""]
  resources: ["configmaps", "endpoints", "pods", "services"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
- apiGroups: ["extensions", "apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list"]
- apiGroups: ["networking.istio.io", "security.istio.io", "config.istio.io"]
  resources: ["*"]
  verbs: ["get", "list"]
- apiGroups: ["route.openshift.io"]
  resources: ["routes"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kiali-viewer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kiali-viewer
subjects:
- kind: User
  name: "system:serviceaccount:istio-system:kiali-service-account"
  apiGroup: rbac.authorization.k8s.io
```

```bash
oc apply -f kiali-rbac.yaml
```

## Step 13: Verification and Testing

### 13.1 Check Service Mesh Status

```bash
# Check control plane status
oc get smcp -n istio-system

# Check member roll status
oc get smmr -n istio-system

# Check Kiali status
oc get kiali -n istio-system

# Check pods
oc get pods -n istio-system
```

### 13.2 Test Kiali Authentication Flow

```bash
# Get Kiali route URL
oc get route kiali -n istio-system

# Access Kiali dashboard - should redirect to EntraID login
# URL will be: https://kiali.apps.<your-cluster-domain>/kiali
```

### 13.3 Verify Kiali Integration

1. **Access Kiali Dashboard**: Navigate to the Kiali URL
2. **EntraID Login**: You'll be redirected to Microsoft login
3. **Dashboard Access**: After authentication, you should see the Kiali service mesh dashboard
4. **Service Graph**: Verify you can see the service topology
5. **Metrics**: Check that Prometheus metrics are displayed
6. **Tracing**: Verify Jaeger integration is working

### 13.4 Test Authentication Flow for Applications

```bash
# Get ingress gateway URL
oc get route -n istio-system

# Test authentication by accessing your application URL
# Should redirect to EntraID login
```

### 13.5 Verify JWT Token Validation

```bash
# Check request authentication policy
oc get requestauthentication -n istio-system

# Check authorization policy
oc get authorizationpolicy -n istio-system

# Check Kiali configuration
oc get kiali kiali -n istio-system -o yaml
```

## Troubleshooting

### Common Kiali Issues

1. **Kiali Authentication Issues**
   ```bash
   oc logs deployment/kiali -n istio-system
   oc describe kiali kiali -n istio-system
   ```

2. **OIDC Configuration Issues**
   ```bash
   # Check Kiali secret
   oc get secret kiali-oidc-secret -n istio-system -o yaml
   
   # Check Kiali configuration
   oc get configmap kiali -n istio-system -o yaml
   ```

3. **Route and TLS Issues**
   ```bash
   oc describe route kiali -n istio-system
   oc get service kiali -n istio-system
   ```

4. **RBAC Issues**
   ```bash
   # Check service account permissions
   oc auth can-i get pods --as=system:serviceaccount:istio-system:kiali-service-account
   
   # Check cluster role bindings
   oc get clusterrolebinding | grep kiali
   ```

### Kiali-Specific Troubleshooting

1. **Service Discovery Issues**
   ```bash
   # Check if Kiali can access Prometheus
   oc exec deployment/kiali -n istio-system -- curl -s http://prometheus.istio-system:9090/api/v1/query?query=up
   
   # Check Grafana connectivity
   oc exec deployment/kiali -n istio-system -- curl -s http://grafana.istio-system:3000/api/health
   ```

2. **Namespace Access Issues**
   ```bash
   # Verify accessible namespaces
   oc get kiali kiali -n istio-system -o jsonpath='{.spec.deployment.accessible_namespaces}'
   ```

### Common Issues

1. **OAuth Configuration Issues**
   ```bash
   oc get oauth cluster -o yaml
   oc logs deployment/oauth-openshift -n openshift-authentication
   ```

2. **Service Mesh Installation Issues**
   ```bash
   oc describe smcp basic -n istio-system
   oc get events -n istio-system
   ```

3. **Authentication Policy Issues**
   ```bash
   oc logs -l app=istiod -n istio-system
   oc logs -l app=oauth2-proxy -n istio-system
   ```

4. **Certificate Issues**
   ```bash
   oc describe secret entraid-gateway-certs -n istio-system
   ```

### Useful Commands

```bash
# Check mesh configuration
istioctl proxy-config cluster <pod-name> -n <namespace>

# Analyze mesh configuration
istioctl analyze

# Check proxy configuration
istioctl proxy-status
```

## Security Considerations

1. **Rotate secrets regularly**: Client secrets, cookie secrets, and certificates
2. **Use strong cookie secrets**: Generate random 32-character strings
3. **Enable RBAC**: Configure proper role-based access control
4. **Monitor access logs**: Set up proper logging and monitoring
5. **Use mTLS**: Ensure mutual TLS is enabled for service-to-service communication

## Next Steps

1. Configure monitoring and observability with Grafana, Jaeger, and Kiali
2. Set up proper RBAC policies for different user groups
3. Implement fine-grained authorization policies
4. Configure circuit breakers and retry policies
5. Set up proper backup and disaster recovery procedures
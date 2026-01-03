# Cilium CNI on Talos Linux (Matrix Cluster)

Cilium deployment guide for Talos Linux clusters on the Matrix Proxmox cluster.

## Overview

Cilium provides eBPF-based networking for Kubernetes on Talos. Benefits:

- **kube-proxy replacement** — eBPF load balancing instead of iptables
- **Gateway API** — Modern ingress with ALPN support
- **Network policies** — L3-L7 enforcement
- **Hubble** — Network observability

## Prerequisites

Before installing Cilium:

1. Talos cluster deployed via Omni with **kube-proxy disabled**
2. kubeconfig downloaded from Omni
3. Cilium CLI installed

## Disable kube-proxy (REQUIRED)

**Critical**: Must be done **before** cluster creation.

Our cluster template already includes this patch:

```yaml
# clusters/talos-prod-01.yaml
patches:
  - name: disable-default-cni
    inline:
      cluster:
        network:
          cni:
            name: none
        proxy:
          disabled: true
```

## Install Cilium CLI

### macOS

```bash
brew install cilium-cli
```

### Linux

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz{,.sha256sum}
```

Verify:

```bash
cilium version --client
```

## Installation

### Option 1: Basic (No Gateway API)

```bash
cilium install \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445
```

### Option 2: With Gateway API (Recommended)

```bash
# Install Gateway API CRDs first
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Install Cilium with Gateway API
cilium install \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set gatewayAPI.enabled=true \
    --set gatewayAPI.enableAlpn=true \
    --set gatewayAPI.enableAppProtocol=true
```

### Option 3: Full Stack (Gateway API + Hubble)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

cilium install \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set gatewayAPI.enabled=true \
    --set gatewayAPI.enableAlpn=true \
    --set gatewayAPI.enableAppProtocol=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true
```

## Talos-Specific Parameters Explained

| Parameter | Value | Why |
|-----------|-------|-----|
| `k8sServiceHost` | `localhost` | Talos API server binding |
| `k8sServicePort` | `7445` | Talos uses 7445, not 6443 |
| `cgroup.autoMount.enabled` | `false` | Talos manages cgroups |
| `cgroup.hostRoot` | `/sys/fs/cgroup` | Talos cgroup mount point |
| `securityContext.capabilities.*` | (list) | Required for Talos minimal kernel |

## Verify Installation

```bash
# Wait for Cilium to be ready
cilium status --wait

# Expected output shows all components OK:
#     /¯¯\
#  /¯¯\__/¯¯\    Cilium:             OK
#  \__/¯¯\__/    Operator:           OK
#  /¯¯\__/¯¯\    Envoy DaemonSet:    OK
#  \__/¯¯\__/    Hubble Relay:       disabled
#     \__/       ClusterMesh:        disabled

# Check nodes are Ready
kubectl get nodes

# Check Cilium pods (one per node)
kubectl get pods -n kube-system -l k8s-app=cilium

# Run connectivity test
cilium connectivity test
```

## Gateway API Setup

### Create GatewayClass

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium
spec:
  controllerName: io.cilium/gateway-controller
```

### Create Gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    port: 443
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: gateway-tls
```

### Create HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-route
  namespace: default
spec:
  parentRefs:
  - name: main-gateway
  hostnames:
  - "app.spaceships.work"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: my-service
      port: 80
```

## LoadBalancer IP Pool (Matrix Network)

For services that need external IPs on the Matrix management network:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: matrix-pool
spec:
  cidrs:
  - cidr: 192.168.3.200/29  # 192.168.3.200-207
```

## Hubble Observability

### Enable Hubble

```bash
cilium hubble enable --ui
```

### Access Hubble UI

```bash
cilium hubble ui
# Opens browser to http://localhost:12000
```

### Hubble CLI

```bash
# Install
brew install hubble  # macOS

# Port-forward relay
cilium hubble port-forward &

# Watch flows
hubble observe
hubble observe --verdict DROPPED --follow
hubble observe --pod my-pod
```

## Network Policies

### Default Deny (Recommended Starting Point)

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-deny
spec:
  endpointSelector: {}
  ingress:
  - fromEndpoints:
    - {}
  egress:
  - toEndpoints:
    - {}
  - toEntities:
    - kube-apiserver
```

### Allow DNS

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  endpointSelector: {}
  egress:
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s:k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
      rules:
        dns:
        - matchPattern: "*"
```

## Troubleshooting

### Cilium Pods Not Starting

```bash
kubectl logs -n kube-system -l k8s-app=cilium

# Common issues:
# - Wrong k8sServiceHost/Port (must be localhost:7445)
# - Missing capabilities
# - Incorrect cgroup config
```

### Connectivity Issues

```bash
cilium connectivity test
cilium status --all-nodes
cilium bpf lb list
cilium bpf endpoint list
```

### Gateway Not Working

```bash
kubectl get gateway -A
kubectl describe gateway <name>
kubectl get httproute -A
kubectl get pods -n kube-system -l k8s-app=cilium-envoy
```

## Upgrading Cilium

```bash
cilium version
cilium upgrade --version 1.15.0
cilium status
```

## Resources

- [Cilium Documentation](https://docs.cilium.io/)
- [Talos + Cilium Guide](https://www.talos.dev/v1.11/kubernetes-guides/network/deploying-cilium/)
- [Gateway API Docs](https://gateway-api.sigs.k8s.io/)
- [Hubble Documentation](https://docs.cilium.io/en/stable/gettingstarted/hubble/)

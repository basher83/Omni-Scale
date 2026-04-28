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

## MTU Configuration (REQUIRED)

Omni-managed Talos nodes carry a `siderolink` WireGuard tunnel at MTU 1280.
Without `--set MTU=1450` at Cilium install, pod networking ends up at 1280 and
Tailscale Ingress throughput drops to ~22 KB/s (commit `e0d5f5e`).

Verify siderolink MTU on a node:

```bash
talosctl -n <node-ip> get links siderolink -o yaml | grep -E "mtu|kind"
#   mtu: 1280
#   kind: wireguard
```

Verified 2026-04-16 on node 192.168.3.155 (Talos v1.12.1).

### Cilium MTU auto-detection

Cilium reads the MTU of the device the default route points to (Cilium PR
[#4687](https://github.com/cilium/cilium/pull/4687)). Not the lowest-MTU
interface — issue [#14339](https://github.com/cilium/cilium/issues/14339) shows
a 9000-MTU storage interface winning over a 1500-MTU external interface.

The exact selection that resolves to siderolink's 1280 on these Talos nodes is
not mapped in upstream sources. The outcome is observed; the selection path is
not.

### Install and verify

All install and upgrade commands in this guide carry `--set MTU=1450` (1500 NIC
minus 50 VXLAN overhead). The bootstrap runbook in
`mothership-gitops/README.md` also carries it. After install or upgrade:

```bash
kubectl get cm -n kube-system cilium-config -o jsonpath='{.data.mtu}'; echo
# Expect: 1450
```

### ConfigMap-only fixes do not survive reinstall

A direct `kubectl patch` on `cilium-config` is overwritten by a future
`cilium install`. The flag in the install commands is what makes the fix
durable.

Cilium on this cluster is installed imperatively, not via GitOps:

```bash
kubectl -n kube-system get cm cilium-config -o jsonpath='{.metadata.managedFields[*].manager}'
# → helm kubectl-patch

kubectl -n kube-system get ds cilium -o jsonpath='{.metadata.managedFields[*].manager}'
# → helm kubectl-rollout kube-controller-manager
```

No ArgoCD Application manages Cilium. GitOps management of Cilium is tracked in `docs/ROADMAP.md`.

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
    --set MTU=1450 \
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
    --set MTU=1450 \
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
    --set MTU=1450 \
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
| `MTU` | `1450` | Required override. Omni's `siderolink` WireGuard tunnel (MTU 1280) is present on every Talos node; without this flag, Cilium auto-detect produces sub-1500 pod networking. See MTU Configuration section. 1450 = 1500 NIC − 50 VXLAN overhead. |
| `k8sServiceHost` | `localhost` | Talos API server binding |
| `k8sServicePort` | `7445` | Talos uses 7445, not 6443 |
| `cgroup.autoMount.enabled` | `false` | Talos manages cgroups |
| `cgroup.hostRoot` | `/sys/fs/cgroup` | Talos cgroup mount point |
| `securityContext.capabilities.*` | (list) | Required for Talos minimal kernel |

## Gateway API Parameters Explained

| Parameter | Why |
|-----------|-----|
| `gatewayAPI.enabled` | Enable Gateway API support (requires CRDs installed first) |
| `gatewayAPI.enableAlpn` | **Required for gRPC/GRPCRoutes with TLS.** ALPN negotiates HTTP/2 between client and server. |
| `gatewayAPI.enableAppProtocol` | Enables appProtocol field support in Services |

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
cilium upgrade --version 1.15.0 --set MTU=1450
cilium status
```

### When `cilium upgrade` does not change the ConfigMap

In the 2026-04-06 fix session, `cilium upgrade --set MTU=1450` exited
successfully but did not update `cilium-config`. The AAR attributes this to a
server-side-apply field-manager conflict and hypothesizes CLI-version skew as
the cause.

Cluster and CLI versions (verified 2026-04-16):

```bash
kubectl get ds cilium -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'
# → quay.io/cilium/cilium:v1.18.6@sha256:42ec562a5ff6c8a860c0639f5a7611685e253fd9eb2d2fcdade693724c9166a4

cilium version
# cilium-cli: v0.19.2
# cilium image (default): v1.19.1
```

DaemonSet is v1.18.6; CLI defaults to v1.19.1. No upstream Cilium issue or PR I
located confirms CLI-version skew as the documented cause of SSA conflicts on
`cilium-config`. The version gap is verified; the causal link is the AAR's
hypothesis.

After any `cilium upgrade`, verify the ConfigMap directly:

```bash
kubectl get cm -n kube-system cilium-config -o jsonpath='{.data.mtu}'; echo
```

### `--helm-set upgrade.serverSideApply.force=true`

The AAR reports this flag was tried in the 2026-04-06 session and did not
resolve the conflict. No transcript of that command is in the record and no
upstream source confirms its effect on this failure mode. Trying it before
falling back to the ConfigMap patch is reasonable.

### `cilium upgrade` timeouts

The 2026-04-06 transcript shows `context deadline exceeded` errors during
`cilium upgrade`. The prior agent's note: "likely the Tailscale proxy
throughput issue (ironic) slowing down the Helm chart pull."

Whether the CLI routed through a Tailscale Ingress proxy, a Tailscale subnet
router, or directly to the API server at that moment is not recorded. The
timeouts are observed; the causal attribution is hypothesis.

The direct ConfigMap patch below works whether or not the CLI is timing out.

### Direct ConfigMap patch

Patch the ConfigMap, restart the Cilium DaemonSets, then restart the Tailscale
proxy StatefulSets. The Tailscale namespace is `tailscale-operator`:

```bash
kubectl patch configmap cilium-config -n kube-system --type merge -p '{"data":{"mtu":"1450"}}'
kubectl rollout restart daemonset/cilium -n kube-system
kubectl rollout restart daemonset/cilium-envoy -n kube-system

kubectl get statefulset -n tailscale-operator -o name | \
  xargs -I{} kubectl rollout restart {} -n tailscale-operator

kubectl get cm -n kube-system cilium-config -o jsonpath='{.data.mtu}'; echo
kubectl exec -n tailscale-operator <any-ts-pod> -- ip link show eth0 | grep mtu
```

Pod veth MTU is set at pod creation and does not change for the pod's lifetime.
Restarting the Tailscale StatefulSets forces veth recreation at the new MTU.

StatefulSet count (verified 2026-04-16):

```bash
kubectl get statefulset -A | grep -c tailscale-operator
# → 11
```

The count drifts as apps are added or removed.

### Pod MTU after the fix

Post-fix pod MTU sampled across two namespaces (verified 2026-04-16):

```bash
kubectl exec -n tailscale-operator ts-anthropic-oauth-proxy-mrcz2-0 -- ip link show eth0 | grep mtu
# → mtu 1450

kubectl exec -n longhorn-system <longhorn-manager-pod> -- ip link show eth0 | grep mtu
# → mtu 1450
```

This is consistent with cluster-wide CNI-level MTU configuration. No pre-fix pod
MTU sampling across namespaces exists in the record.

Other pods pick up the new MTU as they naturally roll. Restart latency-sensitive workloads explicitly if needed.

### The patch does not survive reinstall

A future `cilium install` recreates `cilium-config` from flags. The MTU override
is lost unless the install command carries `--set MTU=1450`. Both this guide
and `mothership-gitops/README.md` carry the flag.

## Resources

- [Cilium Documentation](https://docs.cilium.io/)
- [Talos + Cilium Guide](https://www.talos.dev/v1.11/kubernetes-guides/network/deploying-cilium/)
- [Gateway API Docs](https://gateway-api.sigs.k8s.io/)
- [Hubble Documentation](https://docs.cilium.io/en/stable/gettingstarted/hubble/)

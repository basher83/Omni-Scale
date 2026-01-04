# Deploying Talos Linux Kubernetes Clusters on Proxmox: Best Practices for 2024-2025

Talos Linux has emerged as the leading immutable operating system for Kubernetes deployments, combining API-driven management, security-first design, and operational simplicity. When deployed on Proxmox Virtual Environment, organizations gain flexible virtualization capabilities while maintaining production-grade Kubernetes infrastructure. This comprehensive analysis examines current best practices (2024-2025) for deploying Talos clusters on Proxmox, covering infrastructure architecture decisions, VM configuration optimization, and the critical trade-offs between production and resource-constrained homelab environments.

## Architecture Decisions: Strategic Trade-offs

### Storage Backend Selection

Storage architecture represents the most consequential decision for Talos on Proxmox, directly impacting etcd performance, cluster reliability, and operational complexity. The choice fundamentally shapes cluster behavior and must align with workload requirements and infrastructure constraints.

#### Control Plane Storage: etcd Performance Imperatives

etcd, the distributed key-value store backing Kubernetes, exhibits extreme sensitivity to disk write latency. The consensus protocol requires persistent metadata writes, with performance degrading significantly when fsync operations exceed 10ms. This sensitivity makes control plane storage selection critical.[^1]

**Local Storage (ZFS/LVM-thin) - Recommended for Control Planes**

Local storage on NVMe or SSD provides optimal etcd performance with sub-millisecond write latencies. ZFS offers superior data integrity through checksumming, snapshots, and ARC caching, while LVM-thin enables thin provisioning and snapshot capabilities. For control plane nodes, local storage eliminates network-induced latency variability that can trigger etcd elections and cluster instability.[^2][^3]

Official etcd documentation mandates minimum 50 sequential IOPS (7200 RPM disk equivalent) but recommends 500 sequential IOPS (local SSD) for heavily loaded clusters. Production environments should target NVMe storage delivering >10,000 IOPS with consistent sub-5ms latency. Sidero Labs' 2025 reference architecture explicitly recommends 40GB minimum disk for control planes (100GB for production), sized primarily for etcd database growth rather than OS requirements.[^4][^5][^1]

The trade-off: Local storage precludes live migration of control plane VMs and requires external backup strategies. However, Talos' immutable architecture and declarative configuration make control plane reconstruction straightforward—simply reapply the same machine configuration and restore etcd from backup.[^4]

**Ceph - Explicitly Discouraged for Control Planes**

While Ceph provides distributed storage with self-healing capabilities, its network-induced latency makes it unsuitable for etcd workloads. Even with 10GbE networking, Ceph RBD introduces 2-5ms additional latency compared to local storage. More critically, a kernel bug in Talos' Integrity Measurement Architecture (IMA) caused CephFS operations to be 6-60x slower than expected until kernel 6.12.27, as every file open triggered unnecessary SHA-512 hashing. Although patched, this illustrates Ceph's complexity and performance unpredictability.[^6][^7]

Community deployments confirm these challenges. Multiple sources report etcd timeout issues and election storms when running control planes on Ceph-backed storage. For small clusters (<5 nodes), Ceph's CPU and memory overhead can consume 20-30% of available resources solely for storage management.[^8][^9][^6]

**Storage Configuration Recommendations by Deployment Type:**

| Deployment Type | Control Plane Storage | Worker Node Storage | Rationale |
| :-- | :-- | :-- | :-- |
| **Homelab** (1-3 nodes) | Local ZFS (mirrored NVMe/SSD) | Local ZFS or LVM-thin | Optimal etcd performance, acceptable no-migration trade-off |
| **Small Production** (<10 nodes) | Local ZFS (mirrored enterprise SSD) | Local storage + external CSI (Longhorn) | Cost-effective, reliable, simple operations |
| **Large Production** (>10 nodes) | Local NVMe (RAID-1) | Ceph RBD (dedicated storage nodes) | Scale requires shared storage, isolate control plane from storage network |
| **Edge/Remote** | Local storage only | Local storage only | Network reliability concerns, minimal dependencies |

#### Worker Node Storage: Workload-Driven Selection

Worker nodes have different storage requirements than control planes, focusing on capacity, shared access, and stateful workload support rather than etcd's latency sensitivity.

**Local Storage with CSI Providers**

Longhorn represents the recommended approach for homelab and small production environments. This cloud-native distributed block storage system exports local filesystem storage as CSI volumes, providing 3-way replication for data redundancy. Longhorn's simplicity, intuitive web UI, and automated snapshot/backup capabilities make it ideal for clusters with <20 nodes. Performance matches local disk speeds for single-replica volumes while maintaining acceptable overhead for replicated storage.[^10][^4]

Critical Talos-specific consideration: Longhorn requires mounting `/var/lib/longhorn` with specific options in the Talos machine configuration, and upgrades before Talos v1.8 required the `--preserve` flag to prevent data loss. Modern Talos versions (v1.8+) automatically preserve ephemeral data during upgrades.[^11]

**Ceph via Rook-Ceph**

For clusters exceeding 20 nodes or requiring advanced storage features (erasure coding, multi-tenancy, S3-compatible object storage), Rook-Ceph provides enterprise-grade capabilities. Ceph excels when:[^12][^4]

- Worker node count exceeds 15 (enables proper replica distribution)
- Workloads require shared filesystem access (CephFS)
- Storage capacity needs exceed 100TB
- Dedicated 10GbE+ storage network exists

The trade-offs are substantial: Ceph requires dedicated CPU/memory resources (minimum 2 cores and 4GB RAM per OSD daemon), careful performance tuning for replica vs. erasure coding pools, and deep operational expertise for troubleshooting. The 2024-2025 best practice for Ceph deployments is running OSDs on dedicated storage nodes rather than co-locating with application workloads, isolating storage I/O impact from compute resources.[^9][^6][^4]

**Storage Configurations Explicitly Discouraged:**

- **Ceph for control plane nodes**: Network latency kills etcd performance
- **NAS/iSCSI for etcd**: Network latency variability causes election storms
- **VirtIO Block**: Deprecated in favor of VirtIO-SCSI, lacks modern features[^13][^14]
- **Directory storage on network shares**: No performance guarantees, complexity overhead

### Network Topology: Traffic Isolation vs. Simplicity

Network architecture decisions balance operational complexity against performance isolation and security segmentation. The choice between single-NIC and multi-NIC configurations with VLAN segmentation fundamentally affects cluster behavior under load.

#### Single-NIC Configuration

Single-NIC deployments minimize configuration complexity and hardware costs by routing all traffic—management API calls, pod-to-pod communication, and storage backend—through one interface. This approach suits homelabs and small production environments (<10 nodes) where network saturation is unlikely.[^15][^16]

**Configuration approach**: Use Proxmox's default Linux bridge (vmbr0) configured as VLAN-aware, assigning appropriate VLAN tags at the VM level rather than creating separate bridge interfaces. This provides VLAN segmentation flexibility without requiring multiple physical NICs.[^17][^18]

**When single-NIC is appropriate:**

- Homelab/testing clusters with <10 nodes
- 1GbE networking infrastructure
- Local storage (no storage network needed)
- Limited physical NIC availability on hosts

**Limitations recognized:**

- All traffic competes for single NIC bandwidth
- Storage replication (Longhorn, Ceph) contends with pod traffic
- No isolation between management plane and data plane
- Difficult to implement quality-of-service (QoS) traffic prioritization

#### Multi-NIC with VLAN Segmentation

Production deployments benefit from dedicated NICs for distinct traffic types, implemented through VLAN segmentation. The typical pattern segregates:

- **Management VLAN (e.g., VLAN 10)**: Talos API, Kubernetes API server, control plane communication
- **Pod Network VLAN (e.g., VLAN 20)**: CNI-managed pod-to-pod traffic (Cilium/Flannel)
- **Storage Backend VLAN (e.g., VLAN 30)**: Ceph replication, iSCSI traffic (if applicable)

**Implementation in Talos**: Multi-NIC configurations require explicit network interface definitions in machine configuration patches, specifying VLAN tags, IP addressing, and routing metrics. Talos supports assigning route priorities through metric values, enabling primary/failover NIC configurations where traffic prefers one interface but automatically fails over to secondary paths.[^19][^20]

**Multi-NIC best practices:**

1. **Control plane nodes**: Dual-NIC minimum (management + storage/pod network)
2. **Worker nodes with Ceph**: Dedicated storage NIC (10GbE minimum) separate from pod network
3. **Metric-based routing**: Assign lower metrics to preferred interfaces (e.g., 10GbE storage = 100, 1GbE management = 200)
4. **MTU alignment**: Ensure consistent MTU across VLAN path (typically 1500, or 9000 for jumbo frames on storage network)[^21][^22]

**VLAN configuration in Proxmox**: Enable VLAN awareness on the Linux bridge through GUI (Datacenter → Node → System → Network → Edit vmbr0 → VLAN aware checkbox) or directly in `/etc/network/interfaces`. Individual VM NICs then specify VLAN tags (1-4094), with Proxmox automatically handling 802.1Q tagging.[^18][^17]

**Multi-NIC trade-offs:**

- ✅ Traffic isolation prevents storage replication from saturating pod network
- ✅ Enables QoS policies and bandwidth guarantees
- ✅ Security segmentation aligns with zero-trust architectures
- ❌ Increased configuration complexity (multiple subnets, routing, switch configuration)
- ❌ Higher hardware costs (multiple NICs, managed switches)
- ❌ Difficult to retrofit into existing single-NIC deployments

#### Network Performance Optimization: VirtIO Multiqueue

VirtIO-net multiqueue enables parallel packet processing across multiple vCPUs, critical for network-intensive Kubernetes workloads. By default, VirtIO creates single TX/RX queue pairs, serializing all network operations and bottlenecking on single-core performance. Multiqueue creates dedicated queue pairs per vCPU, enabling true parallelization.[^23][^24]

**Enabling multiqueue in Proxmox**: Set `queues=N` where N equals vCPU count (maximum 8 recommended). Configuration example in VM config file:[^23]

```text
net0: virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr0,queues=4
```

**Performance impact**: Community benchmarks show 2-4x throughput improvement for multi-connection workloads (microservices, ingress traffic) when enabling multiqueue on VMs with 4+ vCPUs. Single-stream performance remains similar, but aggregate throughput scales with vCPU count.[^24]

**When multiqueue matters most:**

- Worker nodes handling ingress traffic (NGINX, Envoy, Traefik)
- Nodes running network-intensive applications (streaming, VPN gateways)
- VMs with 4+ vCPUs (parallelization benefit outweighs overhead)

**Critical consideration**: Enable multiqueue in guest OS after Proxmox configuration:

```bash
ethtool -L eth0 combined <N>  # Where N = number of queues
```

Talos automatically detects and configures available queues when VirtIO multiqueue is enabled at hypervisor level.[^24][^23]

## VM Configuration: Optimization Per Category

### CPU Configuration

CPU allocation and topology significantly impact Kubernetes scheduler efficiency and workload performance. Talos benefits from host CPU feature exposure for container-optimized instruction sets.

#### CPU Type: Host Passthrough Recommended

**Setting**: `cpu: host` in Proxmox VM configuration

The `host` CPU type exposes the physical CPU's full instruction set to guest VMs, including AES-NI (encryption), AVX/AVX2 (vectorized operations), and other extensions. Container workloads frequently leverage these instructions for cryptography (TLS), compression, and numerical computing. Hiding CPU features through generic CPU types (kvm64, qemu64) forces software fallbacks, degrading performance 10-30% for crypto-heavy workloads.[^25][^26]

**Trade-off**: `cpu: host` prevents live migration between heterogeneous CPU types (e.g., Intel to AMD). For homelab environments with uniform hardware, this limitation is irrelevant. Production environments with mixed CPU generations should use the newest common CPU type (e.g., `x86-64-v2-AES`) to balance features and migration flexibility.[^27]

**NUMA considerations**: For VMs spanning multiple NUMA nodes (>16 vCPUs on multi-socket hosts), explicitly configure NUMA topology in Proxmox to prevent cross-socket memory access penalties. Talos supports NUMA-aware CPU and memory managers when kubelet is configured with topology-manager policies. However, most Talos deployments use smaller VMs that fit within single NUMA nodes, making explicit NUMA configuration unnecessary.[^28][^29]

#### Core Allocation Sizing

**Control plane nodes:**

- Minimum: 2 cores (maintenance mode operation)
- Recommended homelab: 4 cores
- Recommended production: 4-8 cores (scale based on cluster API load)[^5][^25][^4]

**Worker nodes:**

- Workload-dependent; start with 4 cores minimum
- Over-provisioning acceptable with Kubernetes resource limits
- Under-provisioning causes CPU throttling and pod evictions

**Anti-pattern**: Assigning fractional cores (e.g., 1.5 cores) in Proxmox. Use whole cores exclusively for deterministic performance and simplified capacity planning.

### Memory Configuration

Memory management in virtualized Kubernetes presents unique challenges. Talos' aggressive caching and Kubernetes' memory-based workload placement require careful configuration.

#### Memory Ballooning: Disable for Kubernetes

**Critical setting**: Disable memory ballooning for all Talos VMs

Memory ballooning allows hypervisors to reclaim "unused" guest memory by dynamically resizing allocations. While useful for traditional VMs, ballooning conflicts fundamentally with Kubernetes' memory model. Kubernetes schedules pods based on available memory as reported by the kernel. When the hypervisor balloons memory away, the kernel's view diverges from actual available memory, causing OOMKills despite Kubernetes believing resources exist.[^30][^25][^27]

Talos explicitly documents that memory hot-plugging is unsupported and will cause installation failures. Disable ballooning in Proxmox VM config:[^25]

```text
balloon: 0
```

#### Hugepages: Performance Enhancement for Specific Workloads

Hugepages reduce TLB (Translation Lookaside Buffer) misses by using larger memory pages (2MB or 1GB instead of 4KB), improving performance for memory-intensive applications. Databases, Java applications, and in-memory data processing benefit significantly from hugepages.[^31][^30]

**Configuring hugepages in Proxmox**:

1. Reserve hugepages on host via kernel parameters in `/etc/default/grub`:

```text
GRUB_CMDLINE_LINUX="default_hugepagesz=1G hugepagesz=1G hugepages=16"
```

2. Update GRUB and reboot: `update-grub && reboot`
3. Verify: `cat /proc/meminfo | grep HugePages`

**Hugepage allocation considerations**:

- Reserve sufficient host memory for OS and non-hugepage workloads (minimum 1GB)
- For ZFS/Ceph hosts, reserve additional memory for cache (ZFS ARC, Ceph cache)[^31]
- Calculate total: `kube-reserved + system-reserved + eviction-hard = reserved hugepage memory`

**When to use hugepages:**

- High-memory workloads (>16GB per container)
- Databases (PostgreSQL, MongoDB, Redis)
- Java applications with large heaps
- Scientific computing / HPC workloads

**When to avoid hugepages:**

- General-purpose Kubernetes workloads
- Small VMs (<8GB RAM)
- Environments without performance-tuning requirements

#### Memory Sizing by Role

| Role | Minimum | Recommended Homelab | Recommended Production | Rationale |
| :-- | :-- | :-- | :-- | :-- |
| Control Plane | 2GB | 4GB | 8GB (<100 nodes) / 32GB (>100 nodes)[^4] | etcd, API server, scheduler, controller-manager |
| Worker | 1GB | 2-4GB | Workload-dependent | Container runtime, kubelet, CNI agents, pods |

**Production sizing methodology**: Monitor control plane resource usage during gradual workload scaling. When memory or CPU exceeds 60% capacity, scale resources vertically. This headroom prevents resource starvation during API load spikes (deployments, autoscaling events).[^4]

### Storage Configuration

Storage virtualization choices dramatically affect I/O performance, snapshot capabilities, and operational flexibility.

#### VirtIO-SCSI vs. VirtIO Block: Clear Winner

**Recommended**: VirtIO-SCSI controller with SCSI bus

VirtIO Block is deprecated and receives no new features. VirtIO-SCSI provides superior performance, supports SCSI command passthrough, and enables features like TRIM/discard. Community benchmarks show VirtIO-SCSI delivers 2-3x IOPS and 30-40% higher throughput compared to IDE/SATA, approaching bare-metal performance.[^32][^33][^14][^34][^13]

**Critical configuration detail**: Use `VirtIO-SCSI` controller, NOT `VirtIO-SCSI single`

A GitHub issue documents Talos installations hanging during bootstrap when using `VirtIO-SCSI single` controller. The `VirtIO-SCSI single` variant uses a single-threaded backend, eliminating parallelization benefits. Always select `VirtIO-SCSI` (multi-queue) in Proxmox VM hardware configuration.[^35]

**Proxmox configuration**:

```text
scsi0: local-lvm:vm-100-disk-0,discard=on,iothread=1,ssd=1
scsihw: virtio-scsi-pci
```

#### Cache Modes: Performance vs. Safety Trade-offs

Disk cache modes balance performance, data integrity, and migration compatibility. The choice affects fsync latency, which directly impacts etcd and database workloads.

**Cache mode comparison**:

| Mode | Write Performance | Data Safety | Live Migration | Use Case |
| :-- | :-- | :-- | :-- | :-- |
| `none` (O_DIRECT) | High (no host cache) | Safe (guest manages flushes) | ✅ Compatible | **Recommended for production** |
| `writeback` | Highest (deferred writes) | Risk (data loss on crash) | ❌ Unsafe | Performance testing, development |
| `writethrough` | Lowest (synchronous writes) | Safest (immediate persistence) | ✅ Compatible | Compliance/regulatory requirements |
| `directsync` | Very low | Safest | ✅ Compatible | Paranoid mode (unnecessary overhead) |

**Recommendation**: `cache=none` for production control planes[^36][^37]

The `none` cache mode bypasses host page cache, performing direct I/O between VM buffers and storage device. While this eliminates double-caching overhead, it requires the guest OS to explicitly send flush commands (which Talos does). Performance matches native disk speeds, particularly on NVMe where host caching provides minimal benefit.[^37]

**When to use `writeback`**: Development/testing environments where performance trumps data safety. Understand that host crashes can cause data loss even with proper guest-side flushing. Never use for production control planes.

#### TRIM/Discard: SSD Optimization

SSDs require TRIM commands to maintain performance by marking deleted blocks as available for garbage collection. Without TRIM, SSDs suffer write amplification and performance degradation over time.

**Enabling TRIM in Proxmox**:

1. Add `discard=on` to disk configuration:

```text
scsi0: local-lvm:vm-100-disk-0,discard=on,ssd=1
```

2. Verify guest OS (Talos) runs fstrim: `systemctl status fstrim.timer`

Talos enables fstrim by default, running weekly TRIM operations on supported storage. The `ssd=1` flag hints to the guest OS that storage is SSD-backed, enabling additional optimizations (scheduler tuning, reduced readahead).[^38]

**Critical for thin-provisioned storage**: TRIM is mandatory for LVM-thin and ZFS zvol storage backends to reclaim unused space. Without discard, thin-provisioned volumes grow to maximum size and never shrink, defeating the purpose of thin provisioning.[^39][^38]

**Storage backend TRIM support matrix**:

| Backend | TRIM Support | Configuration Required |
| :-- | :-- | :-- |
| Local LVM-thin | ✅ Yes | `discard=on` in VM config |
| Local ZFS | ✅ Yes | `discard=on` + automatic zvol trim |
| Ceph RBD | ⚠️ Partial | Encrypted volumes don't support TRIM[^40] |
| Directory (qcow2) | ✅ Yes | `discard=on` + qcow2 discard_granularity |

### Network Configuration

Network virtualization settings affect packet processing efficiency and latency.

#### VirtIO Network Adapter: Mandatory for Performance

**Recommended**: VirtIO network adapter with multiqueue enabled

VirtIO provides paravirtualized network drivers optimized for KVM, delivering near-native network performance. Alternative drivers (e1000, rtl8139) emulate physical hardware with 40-60% performance penalties.[^15][^23]

**Configuration**:

```text
net0: virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr0,firewall=1,queues=4
```

**Key parameters**:

- `queues=N`: Enable multiqueue (N should equal vCPU count, max 8)[^23][^24]
- `firewall=1`: Enable Proxmox firewall (if used)
- `mtu=9000`: Jumbo frames for storage network (requires end-to-end support)[^41][^21]

#### MTU Considerations

Default MTU (Maximum Transmission Unit) is 1500 bytes, suitable for most deployments. Jumbo frames (MTU 9000) reduce CPU overhead for large transfers but require consistent configuration across entire network path.[^21][^41]

**When to use jumbo frames**:

- Dedicated storage network with 10GbE switches supporting jumbo frames
- Ceph replication traffic
- Backup/restore operations to NAS/SAN

**Configuration in Talos machine config**:

```yaml
machine:
  network:
    interfaces:
      - interface: eth0
        mtu: 9000
```

**Critical**: MTU mismatch causes packet fragmentation and severe performance degradation. Verify MTU support on switches, Proxmox bridges, and Talos interfaces before enabling.[^21]

### Machine Type and Firmware

Modern VM machine types and firmware provide improved hardware support and security features.

#### Machine Type: Q35 Recommended

**Recommended**: `machine: q35`

The Q35 machine type emulates modern Intel chipsets with PCIe support, enabling advanced features like IOMMU for device passthrough and vIOMMU for nested virtualization. Legacy i440FX machine type lacks these capabilities.[^42][^43]

**Q35 benefits**:

- PCIe device topology (required for GPU passthrough)
- IOMMU support (required for VFIO device assignment)
- Better UEFI compatibility
- Modern device emulation

**Trade-off**: Q35 requires UEFI firmware (OVMF), which some older operating systems don't support. Talos fully supports UEFI boot and benefits from Secure Boot capabilities when configured.[^4]

#### BIOS/Firmware: OVMF (UEFI) Preferred

**Recommended**: `bios: ovmf` (UEFI firmware)

OVMF provides UEFI firmware for virtual machines, enabling Secure Boot, GPT partitioning, and modern boot workflows. Talos supports both UEFI and legacy BIOS boot, but UEFI aligns with modern security best practices.[^44][^45]

**Secure Boot considerations**: Talos supports Secure Boot when using factory-generated images with signed kernels. Secure Boot provides verified boot chain from firmware to userspace, protecting against boot-level malware. Enable Secure Boot in production environments with physical security concerns.[^4]

**When to use SeaBIOS (legacy BIOS)**:

- GPU passthrough with cards lacking UEFI vBIOS
- Compatibility testing with legacy systems
- Troubleshooting OVMF boot issues (rare hardware incompatibilities)[^45][^44]

**OVMF disk requirement**: UEFI VMs require an EFI disk (typically 4MB) to store NVRAM variables:

```text
Add: EFI Disk → Storage: local-lvm → Size: 4M
```

### Talos-Specific Configuration Flags

#### Machine Configuration Patches

Talos deployments benefit from specific machine configuration patches optimizing Proxmox integration:

**1. QEMU Guest Agent Extension**

Enables communication between Proxmox and guest VM for improved shutdown handling, IP address reporting, and management operations.[^16][^46]

**Installation**: Generate custom Talos image with qemu-guest-agent extension via factory.talos.dev or Image Factory.[^46][^16][^4]

**2. Disable Predictable Interface Naming**

Prevents systemd-style interface names (ens18, ens19) in favor of traditional naming (eth0, eth1), simplifying multi-NIC configuration.[^16][^15]

**Machine config patch**:

```yaml
machine:
  install:
    extraKernelArgs:
      - net.ifnames=0
```

**3. iSCSI Tools Extension**

Required only if using iSCSI storage backends for persistent volumes. Most deployments using Longhorn or Ceph CSI don't require this.[^46][^16]

**4. KubePrism: API Server Resilience**

KubePrism is a Talos-specific feature providing a local API server proxy on each node (listens on 127.0.0.1:7445). This enables nodes to reach the Kubernetes API even when external load balancers fail, critical for cluster stability.[^4]

**Enabled by default in Talos 1.9+**. Explicitly verify in machine configuration:

```yaml
cluster:
  proxy:
    disabled: false  # KubePrism enabled
```

## Production vs. Homelab Guidance

### Production Cluster Requirements

Production deployments demand high availability, predictable performance, and operational resilience. Key differentiators from homelab configurations:

**Infrastructure**:

- **Control plane count**: Exactly 3 nodes (odd number for etcd quorum)[^47][^4]
  - Never use even numbers (2 or 4) – reduces fault tolerance
  - Five control planes acceptable for extreme availability but impacts etcd performance (replication overhead)[^47]
- **Storage**: Local NVMe/SSD for control planes, Longhorn or Ceph for stateful workloads[^4]
- **Network**: Multi-NIC with VLAN segmentation, 10GbE for storage backend[^6]
- **Resource sizing**: Follow 60% utilization threshold for vertical scaling[^4]

**High Availability Patterns**:

- **External load balancer**: HAProxy, F5, cloud load balancer for Kubernetes API (never use Talos VIP for high API load)[^4]
- **Anti-affinity placement**: Distribute control plane VMs across separate Proxmox hosts to survive host failures[^8]
- **Backup strategy**: Automated etcd snapshots (minimum daily), stored off-cluster[^48]

**Security Enhancements**:

- **Secure Boot + TPM-based disk encryption**: Protects against physical access attacks[^4]
- **Ingress firewall**: OS-level traffic filtering (default-deny, allowlist control plane access)[^4]
- **External authentication**: OIDC/OAuth integration for API access (eliminate static kubeconfig credentials)[^4]

**Operational Standards**:

- **GitOps workflow**: ArgoCD or Flux for declarative application management[^48][^4]
- **Monitoring**: Prometheus/VictoriaMetrics + Grafana (system and application metrics)[^4]
- **Logging aggregation**: External log shipping (VictoriaLogs, Loki, or enterprise SIEM)[^4]

### Homelab / Resource-Constrained Configurations

Homelabs prioritize learning, experimentation, and cost efficiency over enterprise-grade availability.

**Minimum viable configurations**:

- **Single control plane**: 1 node, 2 cores, 4GB RAM (testing only, no HA)[^49][^27]
- **Three-node HA cluster**: 3 control planes (2 cores, 4GB RAM each), 0 dedicated workers[^49]
  - Control planes can run workloads by removing taints (discouraged for production)[^4]
- **Hybrid cluster**: 1 control plane + 2 workers (most common homelab pattern)[^50][^51]

**Resource optimization techniques**:

- **Overcommit memory**: Proxmox allows >100% memory allocation; acceptable for bursty workloads
- **Thin provisioning**: LVM-thin/ZFS zvol with thin provisioning to overcommit disk space
- **Single-NIC networking**: Acceptable for <10 nodes without storage network requirements
- **Local storage**: ZFS or LVM-thin, avoiding Ceph overhead entirely[^52][^27]

**Acceptable compromises**:

- **Single control plane**: No HA, but acceptable for learning/testing (manual restore from backups)
- **Smaller resource allocations**: 2GB RAM for control plane if workload count stays low
- **No external load balancer**: Use Talos VIP feature for simple API access[^53][^15]
- **Unmanaged networking**: DHCP instead of static IPs (adds complexity but acceptable for testing)

**Anti-patterns to avoid even in homelabs**:

- **Even number of control planes**: Always use odd numbers (1, 3, 5) for etcd quorum[^47][^49]
- **Ceph with <3 nodes**: Overhead exceeds benefits, use local storage + Longhorn[^54][^9]
- **Control plane on Ceph storage**: etcd latency kills stability[^9][^6]

### Migration Path: Homelab to Production

Organizations often prototype on homelab infrastructure before deploying production clusters. The migration path should preserve lessons learned while addressing production requirements:

**Phase 1: Homelab prototyping** (1-3 nodes)

- Single control plane OR 3 control planes (for HA testing)
- Local storage (ZFS/LVM-thin)
- Single-NIC configuration
- Manual backups

**Phase 2: Pre-production** (3-10 nodes)

- 3 control planes on separate Proxmox hosts
- Introduce Longhorn for stateful workloads
- Implement automated etcd snapshots
- Add basic monitoring (Prometheus)

**Phase 3: Production** (10+ nodes)

- External load balancer for API server
- Multi-NIC with VLAN segmentation
- Ceph for scale (if storage requirements exceed Longhorn capacity)
- Full observability stack (metrics, logs, traces)
- Security hardening (Secure Boot, ingress firewall, OIDC auth)

**Configuration preservation**: Leverage GitOps throughout all phases. Store Terraform/OpenTofu configuration and Talos machine configs in version control from day one, enabling repeatable cluster rebuilds as requirements evolve.[^55][^10][^15][^48]

## Summary: Decision Framework

### Storage Backend Selection (Quick Reference)

```text
IF cluster_size <= 10 AND storage_needs < 10TB:
  → Local ZFS + Longhorn

ELSE IF cluster_size > 10 AND shared_storage_required:
  → Local storage (control plane) + Ceph RBD (workers)
  → Requires: 10GbE storage network, dedicated storage nodes

ELSE IF air_gapped OR edge_deployment:
  → Local storage only (ZFS preferred)
```

### Network Configuration (Quick Reference)

```text
IF cluster_size <= 10 AND network_speed = 1GbE:
  → Single-NIC with VLAN-aware bridge

ELSE IF using_ceph OR cluster_size > 10:
  → Multi-NIC with dedicated storage network (10GbE)
  → VLAN segmentation (management, pod, storage)

ELSE:
  → Single-NIC acceptable, evaluate as cluster grows
```

### VM Resource Sizing (Quick Reference)

| Component | Homelab | Small Production | Large Production |
| :-- | :-- | :-- | :-- |
| **Control Plane** | 2C/4GB/20GB | 4C/8GB/40GB | 8C/32GB/100GB |
| **Worker Node** | 2C/2GB/20GB | 4C/8GB/100GB | Workload-dependent |
| **Control Plane Count** | 1 (testing) or 3 (HA) | 3 (always) | 3 (5 for extreme HA) |

### Critical Configuration Checklist

**Every Talos VM must have:**

- ✅ CPU type: `host` (or `x86-64-v2-AES` for migration flexibility)
- ✅ Memory: Ballooning disabled (`balloon: 0`)
- ✅ Storage: VirtIO-SCSI controller (NOT VirtIO-SCSI single)
- ✅ Storage: `discard=on` for SSD/NVMe
- ✅ Storage: `cache=none` for production, `writeback` acceptable for dev
- ✅ Network: VirtIO with multiqueue (`queues=<vCPU_count>`)
- ✅ Machine: Q35 machine type
- ✅ BIOS: OVMF (UEFI) preferred, SeaBIOS for compatibility

**Talos-specific:**

- ✅ qemu-guest-agent extension installed
- ✅ Disable predictable interface naming (`net.ifnames=0`)
- ✅ KubePrism enabled (API server resilience)
- ✅ iscsi-tools extension (only if using iSCSI storage)

## Conclusion

Deploying Talos Linux on Proxmox requires careful navigation of architecture decisions that fundamentally shape cluster behavior. Storage backend selection—particularly the explicit recommendation against Ceph for control planes due to etcd's latency sensitivity—represents the most consequential choice. Local NVMe/SSD storage delivers optimal control plane performance, while Longhorn provides pragmatic distributed storage for small-to-medium clusters. Ceph's complexity and resource overhead justify its use only in large deployments (>10 nodes) with dedicated storage infrastructure.

VM configuration optimization centers on VirtIO-SCSI storage (avoiding the deprecated VirtIO-SCSI single variant), host CPU passthrough for performance, and disabled memory ballooning to prevent Kubernetes scheduling conflicts. Network topology decisions balance simplicity (single-NIC for homelabs) against performance isolation (multi-NIC with VLAN segmentation for production), with clear guidance that storage networks demand 10GbE connectivity when using Ceph.

The critical distinction between production and homelab deployments lies not in absolute resource quantities but in operational maturity: production demands odd-numbered control plane counts (3 nodes minimum), external load balancers, and automated backup strategies, while homelabs can accept single control planes and manual procedures. Both benefit from GitOps workflows and infrastructure-as-code practices that enable repeatable deployments and smooth migration between environments.

Talos' immutable architecture and API-driven management eliminate traditional OS administration overhead, but success requires understanding the interplay between virtualization layer (Proxmox), operating system layer (Talos), and orchestration layer (Kubernetes). The guidance provided here synthesizes official documentation, community deployments, and real-world performance data to establish clear best practices for 2024-2025 deployments—from resource-constrained homelabs to production-grade clusters.
<span style="display:none">[^100][^101][^102][^103][^104][^105][^106][^107][^56][^57][^58][^59][^60][^61][^62][^63][^64][^65][^66][^67][^68][^69][^70][^71][^72][^73][^74][^75][^76][^77][^78][^79][^80][^81][^82][^83][^84][^85][^86][^87][^88][^89][^90][^91][^92][^93][^94][^95][^96][^97][^98][^99]</span>

<div align="center">⁂</div>

[^1]: https://etcd.io/docs/v3.3/op-guide/hardware/

[^2]: https://www.reddit.com/r/Proxmox/comments/1gk62ae/advice_on_storage_system_for_proxmox_server_lvm/

[^3]: https://koromatech.com/proxmox-storage-secrets-lvm-lvm-thin-zfs-directory-setup-made-easy/

[^4]: https://www.siderolabs.com/wp-content/uploads/2025/08/Kubernetes-Cluster-Reference-Architecture-with-Talos-Linux-for-2025-05.pdf

[^5]: https://docs.siderolabs.com/talos/v1.9/getting-started/system-requirements

[^6]: https://www.fairbanks.nl/building-a-sovereign-kubernetes-cluster-with-talos-linux-and-ceph-storage/

[^7]: https://github.com/siderolabs/talos/issues/11129

[^8]: https://www.plural.sh/blog/kubernetes-proxmox-guide/

[^9]: https://docs.siderolabs.com/kubernetes-guides/csi/storage

[^10]: https://kitemetric.com/blogs/proxmox-kubernetes-talos-gitops-automation

[^11]: https://documentation.suse.com/cloudnative/storage/1.10/en/installation-setup/os-distro/talos-linux.html

[^12]: https://vzilla.co.uk/vzilla-blog/building-a-resilient-kubernetes-cluster-with-talos-ceph-and-veeam-kasten

[^13]: https://www.reddit.com/r/Proxmox/comments/1ovweq0/virtio_scsi_single_bus_device_virtio_block_vs_scsi/

[^14]: https://www.reddit.com/r/Proxmox/comments/1iwdadi/controller_type_scsin_or_virtion/

[^15]: https://www.itguyjournals.com/deploying-ha-kubernetes-cluster-with-proxmox-terraform-and-talos-os/

[^16]: https://mentauro.com/blog/talos-proxmox-guide-part2/

[^17]: https://pve.proxmox.com/wiki/Network_Configuration

[^18]: https://forum.proxmox.com/threads/proper-vlan-setting-in-proxmox.121645/

[^19]: https://www.reddit.com/r/kubernetes/comments/1476hhy/prioritize_one_nic_over_another_with_talos/

[^20]: https://www.roosmaa.net/blog/2024/routing-talos-cluster-traffic-over-specific-nic/

[^21]: https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/advanced_networking/changing-cluster-network-mtu

[^22]: https://www.talos.dev/v1.12/reference/configuration/network/dummylinkconfig/

[^23]: https://www.linux-kvm.org/page/Multiqueue

[^24]: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_tuning_and_optimization_guide/sect-virtualization_tuning_optimization_guide-networking-techniques

[^25]: https://homelab.casaursus.net/talos-on-proxmox-3/

[^26]: https://jysk.tech/packer-and-talos-image-factory-on-proxmox-76d95e8dc316

[^27]: https://techdufus.com/tech/2025/06/30/building-a-talos-kubernetes-homelab-on-proxmox-with-terraform.html

[^28]: https://kubernetes.io/docs/tasks/administer-cluster/memory-manager/

[^29]: https://kubernetes.io/docs/tasks/administer-cluster/topology-manager/

[^30]: https://wael.nasreddine.com/proxmoxve/proxmoxve-vm-performance-tunin

[^31]: https://dev.to/sergelogvinov/proxmox-hugepages-for-vms-1fh3

[^32]: https://readyspace.com/proxmox-ide-vs-sata-vs-virtio-vs-scsi/

[^33]: https://forum.proxmox.com/threads/virtio-vs-scsi.52893/

[^34]: https://blog.joeplaa.com/benchmark-proxmox-virtual-disk-settings/

[^35]: https://github.com/siderolabs/talos/issues/11173

[^36]: https://doc.opensuse.org/documentation/leap/virtualization/html/book-virtualization/cha-cachemodes.html

[^37]: https://documentation.suse.com/sles/12-SP5/html/SLES-all/cha-cachemodes.html

[^38]: https://gist.github.com/hostberg/86bfaa81e50cc0666f1745e1897c0a56

[^39]: https://www.reddit.com/r/Proxmox/comments/11tmq3r/correct_ssd_and_discard_setting_for_proxmox_disks/

[^40]: https://github.com/longhorn/longhorn/issues/7836

[^41]: https://blog.ipspace.net/2022/01/mtu-virtual-devices/

[^42]: https://bbs.archlinux.org/viewtopic.php?id=216032

[^43]: https://lorimar.net/notes/proxmox-gpu-passthrough-q35-nic-issues/

[^44]: https://www.reddit.com/r/Proxmox/comments/j2ob53/seabios_vs_omvf/

[^45]: https://github.com/siderolabs/talos/issues/5797

[^46]: https://blog.dalydays.com/post/kubernetes-homelab-series-part-1-talos-linux-proxmox/

[^47]: https://docs.siderolabs.com/talos/v1.7/getting-started/prodnotes

[^48]: https://www.youtube.com/watch?v=EysSrwDyyb8

[^49]: https://joshrnoll.com/creating-a-kubernetes-cluster-with-talos-linux-on-tailscale/

[^50]: https://www.reddit.com/r/homelab/comments/1ozkbrf/i_built_an_automated_talos_proxmox_gitops_homelab/

[^51]: https://www.reddit.com/r/kubernetes/comments/1ozko1v/i_built_an_automated_talos_proxmox_gitops_homelab/

[^52]: https://github.com/hcavarsan/homelab

[^53]: https://www.virtualizationhowto.com/2024/01/proxmox-kubernetes-install-with-talos-linux/

[^54]: https://www.codecentric.de/en/knowledge-hub/blog/ceph-object-storage-fast-gets-benchmarking-ceph

[^55]: https://blog.stonegarden.dev/articles/2024/08/talos-proxmox-tofu/

[^56]: https://www.cloudzero.com/blog/kubernetes-best-practices/

[^57]: https://secsys.pages.dev/posts/talos/

[^58]: https://www.simplyblock.io/blog/proxmox-vs-talos/

[^59]: https://mentauro.com/blog/talos-proxmox-guide/

[^60]: https://www.youtube.com/watch?v=NOtCNRtPPHU

[^61]: https://www.youtube.com/watch?v=3VpOYn_GfAY

[^62]: https://global.moneyforward-dev.jp/2025/10/01/lets-build-our-own-kubernetes-cluster/

[^63]: https://dev.to/jorisvilardell/building-a-fortress-kubernetes-cluster-talos-linux-proxmox-and-network-isolation-1p4g

[^64]: https://www.youtube.com/watch?v=T2-sEgl-_ak

[^65]: https://www.linkedin.com/posts/horizoniq_kubernetes-on-proxmox-a-practical-guide-activity-7374412707304771585-sCji

[^66]: https://www.garrettlaman.com/Homelab/Deploying-a-Talos-k8s-cluster-on-Proxmox

[^67]: https://www.reddit.com/r/homelab/comments/1enccm8/talos_kubernetes_on_proxmox_using_opentofu/

[^68]: https://johanneskueber.com/posts/proxmox_passthrough_talos/

[^69]: https://blog.duckdefense.cc/kubernetes-gpu-passthrough/

[^70]: https://github.com/siderolabs/talos/issues/9852

[^71]: https://forum.proxmox.com/threads/memory-balooning-page-sharing.992/

[^72]: https://hoop.dev/blog/what-ceph-talos-actually-does-and-when-to-use-it/

[^73]: https://www.youtube.com/watch?v=stQzK0p59Fc

[^74]: https://docs.siderolabs.com/talos/v1.12/build-and-extend-talos/cluster-operations-and-maintenance/etcd-maintenance

[^75]: https://www.digitalocean.com/community/tutorials/how-to-set-up-a-ceph-cluster-within-kubernetes-using-rook

[^76]: https://www.youtube.com/watch?v=McdVvFOhHP0

[^77]: https://jysk.tech/3000-clusters-part-3-how-to-boot-talos-linux-nodes-with-cloud-init-and-nocloud-acdce36f60c0

[^78]: https://docs.siderolabs.com/talos/v1.7/networking/metal-network-configuration

[^79]: https://forum.proxmox.com/threads/can-not-startup-vm-with-q35-machine-type.166626/

[^80]: https://docs.siderolabs.com/talos/v1.9/platform-specific-installations/virtualized-platforms/proxmox

[^81]: http://docs.gcc.rug.nl/talos/storage/

[^82]: https://forums.lawrencesystems.com/t/proxmox-deployment-advice-designing-a-reliable-cost-effectiv/25362

[^83]: https://opensourcesecurity.io/2025/2025-09-talos-andrey-smirnov/

[^84]: https://datavirke.dk/posts/bare-metal-kubernetes-part-6-persistent-storage-with-rook-ceph/

[^85]: https://github.com/mitchross/talos-argocd-proxmox

[^86]: https://www.reddit.com/r/TalosLinux/comments/1oyp93s/new_to_talos_and_need_help_setting_up_storage/

[^87]: https://github.com/siderolabs/talos/issues/10974

[^88]: https://www.reddit.com/r/VFIO/comments/190ztul/extremely_slow_disk_speed_in_block_device_mode/

[^89]: https://forum.proxmox.com/threads/lvm-thin-lvm-or-dir.140300/

[^90]: https://www.youtube.com/watch?v=YxpCVAC_H1o

[^91]: https://falco.org/blog/deploy-falco-talos-cluster/

[^92]: https://joshrnoll.com/my-plan-for-homelab-as-code/

[^93]: https://github.com/kubebn/talos-proxmox-kaas/blob/main/README.md

[^94]: https://www.siderolabs.com/blog/air-gapped-kubernetes-with-talos-linux/

[^95]: https://github.com/nickclyde/homelab

[^96]: https://blog.yadutaf.fr/2024/03/14/introduction-to-talos-kubernetes-os/

[^97]: https://www.reddit.com/r/kubernetes/comments/1d5xsfk/talos_linux_you_dont_need_an_operating_system_you/

[^98]: https://www.talos.dev/v1.1/

[^99]: https://portal.nutanix.com/docs/AHV-Admin-Guide-v11_0:ahv-virtio-net-multi-queue-enable-t.html

[^100]: https://www.itguyjournals.com/installing-cilium-and-multus-on-talos-os-for-advanced-kubernetes-networking/

[^101]: https://github.com/siderolabs/talos/issues/10925

[^102]: https://github.com/siderolabs/talos/discussions/7844

[^103]: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/etcd/etcd-practices

[^104]: https://github.com/etcd-io/etcd/issues/13827

[^105]: https://ranchermanager.docs.rancher.com/how-to-guides/advanced-user-guides/tune-etcd-for-large-installs

[^106]: https://github.com/siderolabs/talos/issues/9121

[^107]: https://docs.siderolabs.com/talos/v1.9/build-and-extend-talos/cluster-operations-and-maintenance/cgroups-analysis

Sidero Omni on Proxmox: A Comprehensive Troubleshooting Guide

Introduction

The integration of Sidero Omni with Proxmox VE offers a powerful, declarative solution for managing the entire lifecycle of Talos Linux-based Kubernetes clusters. However, due to the beta status of the Proxmox infrastructure provider and the inherent complexities of the technology stack, engineers may encounter a specific set of failure modes. This guide provides a synthesized, authoritative set of solutions based on documented issues and community-sourced workarounds. The central theme connecting these issues is state reconciliation failure—the challenge of ensuring the desired state in Omni consistently matches the actual state in Proxmox.

This document is structured to help infrastructure engineers quickly identify symptoms, understand the underlying root causes, and apply proven, step-by-step resolutions for the most common integration challenges. By systematically addressing each failure scenario, this guide aims to minimize downtime and streamline the management of your Kubernetes infrastructure.

--------------------------------------------------------------------------------

1. Foundational Concepts and Diagnostic Tooling

A strategic understanding of core concepts and proficiency with the essential command-line tools are critical for efficient troubleshooting. Proactive diagnosis and a solid grasp of the control flow between Sidero Omni and Proxmox are paramount to minimizing downtime and resolving issues before they escalate.

The Role of Finalizers

A finalizer is a mechanism used by Kubernetes and Sidero Omni to block the deletion of a resource until specific cleanup tasks are completed. This pattern is a core concept inherited from Kubernetes's controller-runtime and Cluster API, upon which Omni is built. When a delete operation is initiated for a resource like a Machine, a finalizer key is added to its metadata. This signals to the system that a controller—in this case, the Omni Proxmox provider—must first perform actions in the underlying infrastructure, such as deleting the actual Proxmox VM.

The resource is not actually removed from the system until the controller confirms the cleanup is complete and removes the finalizer. Many "stuck" deletion issues are a direct result of the provider failing to signal this completion, often because the target VM is unreachable. This leaves the finalizer in place indefinitely, preventing the resource from being fully garbage-collected.

Essential CLI Toolset

A small set of command-line tools provides the necessary visibility and control to diagnose and resolve nearly all integration issues.

Tool    Primary Function    Key Diagnostic Commands
omnictl    Manages the Sidero Omni control plane, including clusters, machines, and infrastructure providers.    omnictl cluster status <name><br>omnictl get machines<br>omnictl delete machine <id> --force<br>omnictl infra provider reconcile <id>
talosctl    Interacts directly with individual Talos Linux nodes for low-level diagnostics and operations.    talosctl logs -n <IP><br>talosctl dmesg -n <IP><br>talosctl reset<br>talosctl get volumestatus
kubectl    Interacts directly with the Kubernetes API to manage cluster resources, including nodes and custom resources.    kubectl delete node <name><br>kubectl patch clustermachinestatus <machine-name> --type='merge' -p '{"metadata":{"finalizers":[]}}'<br>kubectl annotate machineset <machineset-name> cluster.sidero.dev/reconcile=true --overwrite

Mastering these tools is the first step toward effectively troubleshooting the complex interactions within the Sidero Omni and Proxmox environment.

--------------------------------------------------------------------------------

2. Scenario 1: VM Stuck in a Provisioning Reboot Loop

The VM reboot loop is a common and frustrating "day one" problem that can occur during the initial provisioning of a cluster. This issue almost always points to a fundamental mismatch between the Proxmox virtual machine's configuration and the strict hardware emulation requirements of the Talos Linux operating system.

Symptoms

* The VM enters a continuous reboot cycle after displaying the initial Linux splash screen.
* The Proxmox console displays critical boot errors such as "unexpected EOF" or "Wrong EFI loader signature".
* Running talosctl get volumestatus against the booting node reveals that the META and STATE volumes are "missing".

Root Cause Analysis

* Proxmox SCSI Controller Misconfiguration: Using the virtio-scsi-pci controller is a primary cause. It can introduce race conditions during Talos installation where a partition is detected but cannot be read correctly, triggering a fatal error and subsequent reboot.
* BIOS/Firmware Mismatch: Talos requires a modern firmware interface. The default SeaBIOS in Proxmox is often incompatible, whereas UEFI (OVMF) is required for a successful boot.
* Incompatible CPU Type: The Talos operating system requires a CPU with modern instruction sets, specifically x86-64-v2. Using older CPU models like kvm64 can lead to boot failures.
* Talos Version or Configuration Mismatch: A discrepancy between the Talos version defined in the Omni cluster template and the version on the boot media can prevent a node from successfully joining the cluster, causing it to reboot.
* Disk State and Partition Issues: Lingering data, corrupted GPT headers, or inconsistent partition tables from a prior failed installation attempt can prevent a clean installation and cause the initialization sequence to fail.

Resolution and Workarounds

1. Verify and Correct Proxmox VM Settings:
   * SCSI Controller: Change the scsi_hardware parameter from virtio-scsi-pci to virtio-scsi-single.
   * BIOS: Set the BIOS from SeaBIOS to UEFI (OVMF).
   * CPU Type: Change the CPU type from the default to host or a specific model that supports the x86-64-v2 instruction set.
2. Ensure Configuration Consistency:
   * Confirm that the Talos version specified in your Omni cluster template perfectly matches the version of the Talos ISO or boot media being used.
   * Ensure any cloud-init or join configurations are up-to-date and contain a valid cluster join token.
3. Perform a Clean Installation:
   * If a VM is stuck, completely wipe its disk to remove any lingering state. The talosctl reset command is the most effective tool for this controlled recovery:
4. Enable Advanced Logging:
   * To capture more detailed boot diagnostics, enable the serial console in both Proxmox and the Talos image. Add console=ttyS0 to the kernel arguments in your Talos image configuration to log the entire boot sequence for analysis.

Resolving these provisioning failures is the first step; next, we address operational failures such as the inability to delete a machine.

--------------------------------------------------------------------------------

3. Scenario 2: Machine or Cluster Stuck in "Destroying" State

A machine or an entire cluster becoming stuck in a "Destroying" state is a classic symptom of state desynchronization between Sidero Omni and the Proxmox infrastructure. This deadlock is typically caused by Omni's inability to communicate with an unreachable node, which prevents critical finalizers from being removed.

Symptoms

* A machine or cluster's status shows "Destroying" indefinitely in the Omni UI or CLI.
* The affected machine may be listed with a status of "UNKNOWN – Unreachable".
* omnictl delete commands either hang or appear to complete, but the resource is never actually removed.
* The associated MachineSet may also become stuck, preventing any further scaling operations.

Root Cause Analysis

* Unreachable Nodes: If a node is powered off or has lost network connectivity, Omni cannot send the necessary talosctl reset command to decommission it gracefully. This blocks the entire deletion workflow.
* Finalizer Deadlock: Kubernetes and Omni finalizers remain on the resource because the Proxmox provider cannot get confirmation that the underlying VM has been successfully deleted. This is exacerbated by the fact that some Omni versions have no built-in timeout or force-remove mechanism for a completely unreachable machine, causing the finalizer to remain indefinitely.
* API Timeouts: Sidero Omni may not correctly handle API timeouts when attempting to communicate with a powered-down or unresponsive node, causing the deletion process to stall.

Resolution and Recovery

1. Restart the Proxmox Infrastructure Provider: Restarting the omni-infra-provider-proxmox container is often the simplest and most effective first step. This forces the provider to re-establish its connection to the Proxmox API and re-evaluate the state of its managed resources, which can clear inconsistencies and allow the reconciliation to complete.
2. Toggle the "Workload Proxy": A community-discovered workaround involves toggling the "Workload Proxy" setting in the Omni UI for the affected cluster. This action appears to force a metadata refresh and connection reset that can flush out a stuck machine's state.
3. Attempt a Forceful Reset: If a node is intermittently reachable, you can manually trigger its cleanup process using talosctl:
4. Manually Remove Finalizers: As a last resort, you can directly interact with the Kubernetes API to remove the blocking finalizer. This is an advanced procedure that forces the system to garbage-collect the resource. The command targets the ClusterMachineStatus resource associated with the stuck machine:

The inability to delete resources is closely related to the failure of scaling operations, which depend on the same lifecycle management logic.

--------------------------------------------------------------------------------

4. Scenario 3: Scaling Operations Fail or Hang Indefinitely

Stuck scaling operations represent a critical failure that directly impacts a cluster's elasticity and high availability. This problem is often rooted in the infrastructure provider's inability to maintain reliable communication with the Proxmox API, especially during high-volume operations or when cluster members are unhealthy.

Symptoms

* The MachineSet replica count is changed in the UI, but the actual number of VMs in Proxmox does not change.
* During a scale-down, old machines remain stuck in the "Destroying" state.
* The Proxmox provider logs show errors like "connection refused" or indicate API throttling (HTTP 429).
* The cluster autoscaler fails to add or remove nodes as expected.

Root Cause Analysis

* Provider Connection Instability: The Proxmox provider may not correctly re-establish dropped connections to the Proxmox API. When this happens, subsequent API calls for creating or deleting VMs can fail silently.
* Proxmox API Limits: Proxmox has built-in limits on concurrent operations. During rapid scaling events, the provider can be throttled by the Proxmox API and may not correctly handle the rate-limiting responses.
* State Reconciliation Gaps: If Proxmox operations complete out-of-order, the provider can be left with an inconsistent and incorrect view of the infrastructure's state, causing it to halt further actions.
* Etcd Quorum Health: An unhealthy etcd prevents the cluster from reliably committing the state changes required for scaling. If the control plane cannot achieve quorum, any operation to add or remove nodes will fail to be persisted.

Resolution and Recovery

1. Restart the Proxmox Provider: As with stuck deletions, restarting the omni-infra-provider-proxmox container is the quickest way to clear a stale connection pool and force the provider to reconcile its state.
2. Force Reconcile the MachineSet: You can force Omni to re-evaluate the state of a MachineSet by adding an annotation via kubectl:
3. Manually Clean Up Stuck Machines: Identify individual machines that are stuck in the "Destroying" state and remove them one by one using a forceful delete command:
4. Investigate Proxmox-Level Issues: Check the Proxmox API limits (e.g., max_workers in datacenter.cfg) to ensure they are not being exceeded. Also, verify that there is stable network connectivity between the Omni provider and all Proxmox hosts.

These failures are typically managed within Omni's control loop, but the next scenario addresses failures caused by actions taken outside of its control.

--------------------------------------------------------------------------------

5. Scenario 4: State Drift from Out-of-Band VM Deletion

"State drift" occurs when the actual state of the infrastructure diverges from the declarative state recorded in the management plane. This is a critical problem in declarative systems like Sidero Omni. When a VM is deleted directly in the Proxmox UI—an "out-of-band" action—Omni's view of the world becomes incorrect, leading to a non-functional cluster that cannot self-heal.

Symptoms

* A VM is manually deleted or purged in the Proxmox UI.
* Sidero Omni continues to show the corresponding machine as "Running," "Ready," or "Unreachable."
* The cluster does not automatically provision a replacement VM to satisfy the MachineSet replica count.
* Machine health checks may fail, but Omni takes no corrective action.

Root Cause Analysis

* Lack of a Reconciliation Watch: The Omni Proxmox provider does not have a continuous watch mechanism to detect changes made directly in Proxmox. It relies on its own cached state and only polls Proxmox during explicit operations that it initiates. This design choice leads to a permanent state drift when an out-of-band change occurs.

Resolution and Recovery

1. Follow the Golden Rule: The primary preventative measure is simple: never delete Omni-managed VMs directly in Proxmox. All infrastructure lifecycle operations must be performed via the Sidero Omni UI or omnictl to ensure state remains synchronized.
2. Manually Delete the Machine in Omni: To correct the state drift, you must delete the corresponding Machine resource from Omni's side. This may require the force-deletion techniques described in Scenario 2 if Omni considers the now-nonexistent machine to be unreachable.
3. Trigger a Manual Reconciliation: Force the provider to re-scan its resources and reconcile its state with Proxmox by running:
4. Replace the Machine: Once the orphaned Machine object has been removed from Omni, scale the relevant MachineSet up to trigger the provisioning of a new, replacement VM.

This scenario highlights issues with VM state; the next focuses on the infrastructure provider itself.

--------------------------------------------------------------------------------

6. Scenario 5: Proxmox Provider Failures

The omni-infra-provider-proxmox component is the critical link between Sidero Omni's declarative state and the Proxmox hypervisor. Failures within this component, such as an expired API session, can halt all infrastructure operations, effectively freezing the cluster's ability to scale or self-heal.

Symptoms

* Attempts to create or delete machines fail with no apparent activity in Proxmox.
* The provider's logs reveal "not authorized to access endpoint" errors when communicating with the Proxmox API. For example: “machine provision failed… error:"not authorized to access endpoint".
* Provider logs may show "connection refused" during scaling operations, even with stable network connectivity.

Root Cause Analysis

* Expired API Session: The Proxmox API token used by the provider can expire after a long runtime. Older beta versions of the provider did not automatically re-authenticate, causing all subsequent API calls to fail.
* Provider Overload: The provider can become overloaded by too many concurrent requests, particularly during large-scale cluster operations, leading to connection failures and dropped requests.

Resolution and Recovery

* Primary Solution: Restart the Provider: The immediate and most effective workaround is to restart the omni-infra-provider-proxmox container or Kubernetes deployment. A restart forces the provider to re-initialize and establish a new, authenticated session with the Proxmox API.
* Long-Term Solution: Update the Provider: Always run the latest available version of the Proxmox provider. Bugs related to session handling and connection management are continuously being identified and fixed in newer releases.
* Configuration Tuning: If the Proxmox API is being overloaded, consider adjusting the provider's configuration to reduce its concurrency. This can be set via an environment variable or, for a more robust long-term solution, declaratively in the provider's configuration YAML.

These troubleshooting scenarios cover the most common failure modes, which are summarized below for quick reference.

--------------------------------------------------------------------------------

7. Summary of Issues and Fixes

This table synthesizes the discussed failure modes into a quick-reference guide for rapid diagnosis and resolution.

| Issue                        | Primary Symptom                                           | Dominant Root Cause                                             | Immediate Fix                                                                                 |
|------------------------------|----------------------------------------------------------|-----------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| VM Reboot Loop               | Continuous reboot with "unexpected EOF"                  | Proxmox SCSI controller or BIOS/UEFI misconfiguration           | Change `scsi_hardware` to `virtio-scsi-single` and set BIOS to UEFI (OVMF).                  |
| Machine Stuck in "Destroying"| "Unknown/Destroying" state indefinitely                  | Finalizer deadlock due to unreachable node                      | Restart the `omni-infra-provider-proxmox` container; manually patch finalizers if needed.    |
| Scaling Operations Fail      | Machines remain in "Destroying" state during scale-down  | Provider connection pool exhaustion or Proxmox API throttling   | Restart the provider; force reconcile the MachineSet via annotation.                         |
| State Drift from Manual Deletion | Omni shows "Running" for a VM deleted in Proxmox     | Provider lacks watch mechanism for out-of-band changes          | Manually delete the Machine in Omni; trigger a provider reconciliation.                      |
| Provider Authentication Failure | Operations fail with "not authorized" in provider logs| Expired Proxmox API token in older provider version             | Restart the `omni-infra-provider-proxmox` container and update to the latest version.        |

While the Sidero Omni and Proxmox integration is powerful, it demands careful configuration and a methodical approach to troubleshooting. Mastering this integration means mastering the detection and correction of state drift between the control plane and the infrastructure. Engineers who leverage detailed logging, adhere strictly to in-band lifecycle management, and keep all components updated will be best positioned to maintain a stable and resilient Kubernetes environment.

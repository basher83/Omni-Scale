#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "diagrams",
# ]
# ///
"""
Network Topology Diagram for Omni + Talos + Proxmox
Combines icons/data from baseline with the structured clarity of v4.
"""

from diagrams import Cluster, Diagram, Edge
# Icons from the baseline network_topology.py
from diagrams.onprem.container import Docker
from diagrams.onprem.network import Internet
from diagrams.k8s.controlplane import APIServer
from diagrams.k8s.compute import Pod
from diagrams.generic.network import VPN, Subnet
# Additional standard icon needed for physical infrastructure layer
from diagrams.onprem.compute import Server

# Set diagram attributes for a cleaner, structured look (from v4 methodology)
graph_attr = {
    "splines": "ortho",
    "compound": "true",
    "pad": "0.5",
    "fontsize": "14",
    "nodesep": "0.6",
    "ranksep": "0.75",
}

with Diagram(
    "Omni + Talos on Proxmox Infrastructure (Enhanced Topology)",
    filename="omni_talos_proxmox_enhanced",
    outformat="png",
    direction="TB",
    show=False,
    graph_attr=graph_attr,
):
    # --- External Access ---
    with Cluster("External Access"):
        dns_external = Internet("omni.spaceships.work\n(external DNS)")
        tailscale = VPN("Tailscale VPN\n100.x.y.z")

    # --- Internal Network Boundary ---
    with Cluster("Internal LAN (192.168.x.x)"):
        dns_internal = Subnet("omni.spaceships.work\n(internal DNS)")

        # 1. Management Layer (VMs running on Proxmox)
        # Using Docker icons and IPs from baseline
        with Cluster("Management Layer (VMs)"):
            omni_hub = Docker(
                "Omni Hub\n192.168.10.20\nManagement Plane & UI")
            
            # The Proxmox provider worker agent separated out for clarity
            proxmox_worker = Docker(
                "Proxmox Worker Agent\n192.168.3.10\nInfrastructure Provider")

        # 2. Physical Infrastructure Layer (Proxmox Bare Metal)
        # Using standard Server icons to represent physical hardware hosts
        with Cluster("Physical Infrastructure: Proxmox VE Cluster (Bare Metal)"):
            # Abstract representation of the Proxmox API endpoint
            pve_api = Server("Proxmox Cluster API\n(Hypervisor Management)")
            
            with Cluster("Physical Hypervisors"):
                pve_hosts = [
                    Server("PVE Host 1\n(HV)"),
                    Server("PVE Host 2\n(HV)"),
                    Server("PVE Host 3\n(HV)"),
                ]
                # Networking between physical hosts
                pve_hosts[0] - Edge(style="dashed", color="gray") - pve_hosts[1]
                pve_hosts[1] - Edge(style="dashed", color="gray") - pve_hosts[2]

        # 3. Workload Layer (Talos VMs)
        # Using K8s icons from baseline to represent the resulting cluster nodes
        with Cluster("Workload Layer: Talos Kubernetes Cluster (VMs)"):
            talos_cp = APIServer("Talos Control Plane\n(VM Node)")
            
            with Cluster("Worker Node Pool"):
                talos_workers = [
                    Pod("Talos Worker 1\n(VM Node)"),
                    Pod("Talos Worker 2\n(VM Node)"),
                    Pod("Talos Worker 3\n(VM Node)"),
                ]

    # --- Connections and Flows (The "Clarity" aspect) ---

    # Access Flows
    dns_external >> Edge(label="resolves to") >> tailscale
    tailscale >> Edge(label="VPN tunnel access", color="firebrick", style="bold") >> omni_hub
    dns_internal >> Edge(label="resolves local IP") >> omni_hub

    # Management & Provisioning Flow
    # 1. Omni Hub instructs the specific provider worker
    omni_hub >> Edge(label="instructs provider", color="blue") >> proxmox_worker
    
    # 2. The worker talks to the Proxmox physical API to create resources
    proxmox_worker >> Edge(
        label="Provisions VMs via API\n(ISO boot/image clone)", 
        color="forestgreen", 
        style="bold"
    ) >> pve_api
    
    # 3. The API results in VMs running on physical hardware
    pve_api >> Edge(
        label="spawns VM processes on", 
        style="dashed", 
        color="gray"
    ) >> pve_hosts[1]

    # Kubernetes Internal Flow
    talos_cp >> Edge(label="kubelet/CNI traffic", color="orange") >> talos_workers

    # Logical Hosting Relationship
    # Showing that physical hardware hosts the logical Talos VM nodes
    pve_hosts[2] >> Edge(
        label="physically hosts logical VMs", 
        style="dotted", 
        color="gray",
        minlen="2" # Force the arrow to span the layers visually
    ) >> talos_workers[1]
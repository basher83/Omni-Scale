#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "diagrams",
# ]
# ///
"""
Network Topology Diagram for Omni + Talos Infrastructure
Generates a PNG visualization using the diagrams library.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.onprem.compute import Server
from diagrams.onprem.container import Docker
from diagrams.onprem.network import Internet
from diagrams.k8s.controlplane import APIServer
from diagrams.k8s.compute import Pod
from diagrams.generic.network import VPN, Subnet


with Diagram(
    "Omni + Talos Infrastructure",
    filename="network_topology",
    outformat="png",
    direction="TB",
    show=False,
):
    # External access points
    with Cluster("External Access"):
        tailscale = VPN("Tailscale VPN\n100.x.y.z")
        dns_external = Internet("omni.spaceships.work\n(external)")

    # Internal network
    with Cluster("Internal LAN (192.168.x.x)"):
        dns_internal = Subnet("omni.spaceships.work\n(internal)")

        # Cluster A - Doggos
        with Cluster("Cluster A: Doggos"):
            with Cluster("omni-host"):
                omni_hub = Docker(
                    "Omni Hub\n192.168.10.20\nManagement Plane & UI")

        # Cluster B - Matrix
        with Cluster("Cluster B: Matrix"):
            with Cluster("proxmox-worker-matrix"):
                worker = Docker(
                    "Proxmox Worker\n192.168.3.10\nInfrastructure Provider")

            with Cluster("Talos Kubernetes Cluster"):
                talos_cp = APIServer("Control Plane\n(DHCP)")
                talos_workers = [
                    Pod("Worker Node 1"),
                    Pod("Worker Node 2"),
                    Pod("Woeker Node 3")
                ]

    # Connections - External
    dns_external >> Edge(label="resolves to") >> tailscale
    tailscale >> Edge(label="VPN tunnel", style="dashed") >> omni_hub

    # Connections - Internal
    dns_internal >> Edge(label="resolves to") >> omni_hub

    # Omni Hub manages the infrastructure
    omni_hub >> Edge(label="provisions", color="blue") >> worker
    worker >> Edge(label="deploys VMs", color="green") >> talos_cp

    # Talos cluster internal connections
    talos_cp >> Edge(label="schedules", color="orange") >> talos_workers

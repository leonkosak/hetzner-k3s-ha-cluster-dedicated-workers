# Architecture

## 1) Target model

- 3 control-plane nodes on VMs (same region, private network).
- 1 internal load balancer for Kubernetes API (`:6443`) in front of control planes.
- N worker nodes on dedicated servers (and optional VM workers).
- Optional GPU worker pool (tainted/labeled) for NVIDIA workloads.
- External management cluster (Rancher) manages this cluster remotely.

## 2) Provider-agnostic abstractions

Keep these abstractions stable when moving from Hetzner to another provider:

- `control_plane_endpoint` (VIP/LB DNS) used by all joins.
- `server` role vs `agent` role for k3s.
- `node_profile` labels/taints (`general`, `gpu`, `storage`).
- `bootstrap channel` (GitHub raw/release asset) for node scripts.
- `day2` workflows (upgrade, scale, drain, replacement) as playbooks/scripts.

Only provider adapters change:
- Terraform module for infra primitives
- inventory source and node address assignment

## 3) Network

- Dedicated private network/subnet for all k3s nodes.
- API endpoint reachable from joining nodes (private preferred).
- Restrictive firewall:
  - allow SSH from admin CIDRs only
  - allow `6443/tcp` from node networks/admin
  - allow CNI ranges as needed
- Disable public Kubernetes API exposure when possible.

## 4) Storage strategy

- Control plane: local disk is enough for etcd + system components (or external datastore by policy).
- Stateful workloads needing high IOPS/low latency: dedicated workers with local NVMe.
- Shared resilient volumes: network block storage classes.
- Do not resize in-place if provider/hardware makes this risky; prefer add-new-volume, replicate, cut-over.

## 5) GPU worker strategy

- Separate GPU nodes in dedicated pool.
- Add labels/taints in inventory:
  - `node.kubernetes.io/accelerator=nvidia`
  - taint example: `nvidia.com/gpu=true:NoSchedule`
- Install NVIDIA driver + container toolkit on those hosts only.
- Install NVIDIA device plugin or GPU Operator in-cluster.

## 6) OS baseline

Primary choice: openSUSE MicroOS.

Why:
- immutable/transactional host model with rollback capability
- low-maintenance node lifecycle for Kubernetes hosts
- suitable for both VM control planes and dedicated workers
- compatible with k3s and NVIDIA-enabled worker pools

## 7) Tooling boundaries

- Terraform owns infra resources and IDs.
- Ansible owns host config and k3s lifecycle.
- Bash scripts run on node and are fetched from GitHub for reproducibility.

No hidden automation layers (`k3sup`, wrapper projects) are required.

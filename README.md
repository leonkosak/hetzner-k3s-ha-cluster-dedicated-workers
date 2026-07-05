# HA k3s on Hetzner: VM Control Planes + Dedicated Workers (GPU-capable)

This repository defines a **manual-automation** approach for production k3s clusters where:
- control planes run on VMs
- workers run on dedicated servers (optionally with NVIDIA GPU, e.g. Hetzner GEX44)
- Rancher management is hosted in a **separate** cluster
- no `k3sup`, no `kube-hetzner` base is required

The automation split is:
- Terraform: infrastructure lifecycle (VM control planes, LB, private network, firewall)
- Ansible: OS baseline, k3s install/join/upgrade, operational tasks
- Bash: node-local bootstrap scripts fetched from GitHub

## Why this baseline (as of February 2026)

Recommended host OS for cluster nodes in this repository: **openSUSE MicroOS**.

Reasoning:
- transactional/immutable operating model with rollback
- low-maintenance host lifecycle for k3s nodes
- strong compatibility with k3s and container runtimes
- works for both VM control planes and dedicated workers when provisioned correctly

## Repository layout

- `docs/architecture.md`: provider-agnostic target architecture
- `docs/runbooks/hetzner-from-scratch.md`: complete setup procedure on Hetzner
- `docs/operations/day2-operations.md`: upgrades, scaling, storage resize, break/fix
- `automation/terraform/hetzner`: Terraform for Hetzner resources
- `automation/ansible`: Ansible inventory/playbooks/roles
- `automation/scripts`: Bash scripts executed on nodes

## Quick start (high level)

1. Create Hetzner API token and SSH key pair.
2. Provision control-plane infra with Terraform.
3. Install openSUSE MicroOS on dedicated worker servers (including GPU workers where needed).
4. Fill Ansible inventory with VM + dedicated server addresses.
5. Run Ansible playbooks:
   - `bootstrap-os.yml`
   - `install-k3s-servers.yml`
   - `install-k3s-agents.yml`
6. Verify cluster and install CNI/CSI/add-ons.
7. Optional: enable GPU runtime and NVIDIA device plugin for GPU workers.

Detailed commands are in `docs/runbooks/hetzner-from-scratch.md`.
The runbook is written as one continuous \"main thread\" from zero to finished cluster, including physical server setup and vSwitch coupling.

## Design constraints

- Provider-agnostic control plane workflow.
- Workers can be any mix: dedicated servers, cloud VMs, edge nodes.
- Node join/upgrade actions are explicit and auditable.
- GitHub-first operations: scripts are sourced from your repository.

## Sources

- openSUSE MicroOS portal: https://microos.opensuse.org/
- openSUSE MicroOS installation and combustion docs: https://en.opensuse.org/Portal:MicroOS
- k3s install/config docs: https://docs.k3s.io/installation/configuration
- NVIDIA Container Toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/
- NVIDIA GPU Operator: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/
- Hetzner hcloud Terraform provider: https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs

# Ansible

Ansible configures the OS and installs K3s on Hetzner servers. Normally you don't
run these playbooks manually — use `create-cluster.sh` (see `../scripts/00_START_HERE.md`)
which runs them automatically.

## How it fits together

```
create-cluster.sh
  ├─ Step 3 → bootstrap-os.yml          (install packages, kernel modules, sysctl)
  ├─ Step 4 → install-k3s-servers.yml   (K3s on masters, cluster-init)
  └─ Step 5 → install-k3s-agents.yml    (K3s on workers, join cluster)
```

## Inventory

The inventory file `../scripts/hcloud_servers_inventory.yml` is auto-generated
by `hcloud-create-servers.sh`. The `ansible.cfg` in this directory points to it,
so you can run playbooks from here without `-i`:

```bash
cd automation/ansible
ansible-playbook playbooks/bootstrap-os.yml
```

## Playbooks

| Playbook | What it does | Run manually? |
|----------|-------------|---------------|
| `bootstrap-os.yml` | Install base packages, kernel modules, sysctl — all nodes | Only if debugging |
| `install-k3s-servers.yml` | Install K3s on masters with `--cluster-init` | Only if debugging |
| `install-k3s-agents.yml` | Install K3s on workers, join the cluster | Only if debugging |
| `upgrade-k3s.yml` | Rolling upgrade of K3s across all nodes (safe, serial) | When upgrading K3s |
| `upgrade-os.yml` | Rolling OS update via `transactional-update` + reboot | Monthly or as needed |
| `install-nvidia-runtime.yml` | NVIDIA drivers & toolkit for GPU workers | Only for GPU nodes |

## Typical run order (manual)

If you need to run playbooks individually (e.g., debugging), the order is:

```bash
cd automation/ansible
ansible-playbook playbooks/bootstrap-os.yml
ansible-playbook playbooks/install-k3s-servers.yml
ansible-playbook playbooks/install-k3s-agents.yml
```

## Day-2 operations

```bash
# Upgrade K3s to a newer version (edit k3s_version in group_vars/all.yml first)
ansible-playbook playbooks/upgrade-k3s.yml

# Update the OS on all nodes (rolling, one at a time)
ansible-playbook playbooks/upgrade-os.yml

# Install GPU runtime on workers with gpu_enabled=true in inventory
ansible-playbook playbooks/install-nvidia-runtime.yml
```

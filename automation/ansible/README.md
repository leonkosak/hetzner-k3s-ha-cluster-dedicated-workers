# Ansible

## Inventory

```bash
cp inventories/production/hosts.example.yml inventories/production/hosts.yml
```

Edit node addresses, endpoint, and versions.
For this repository baseline, inventory and playbooks assume openSUSE MicroOS nodes.

## Playbooks

- `playbooks/bootstrap-os.yml`
- `playbooks/install-k3s-servers.yml`
- `playbooks/install-k3s-agents.yml`
- `playbooks/install-nvidia-runtime.yml`
- `playbooks/upgrade-os.yml`
- `playbooks/upgrade-k3s.yml`

## Typical run order

```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/bootstrap-os.yml
ansible-playbook -i inventories/production/hosts.yml playbooks/install-k3s-servers.yml
ansible-playbook -i inventories/production/hosts.yml playbooks/install-k3s-agents.yml
```

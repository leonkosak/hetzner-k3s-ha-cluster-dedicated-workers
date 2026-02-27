# Day-2 Operations

## Upgrades

### OS upgrade policy

- Use staged rings: `canary` -> `batch-a` -> `batch-b`.
- Never auto-upgrade all nodes simultaneously.
- For each node:
  1. `kubectl cordon <node>`
  2. `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`
  3. Apply OS updates and reboot via Ansible
  4. `kubectl uncordon <node>`

Runbook command:

```bash
ansible-playbook -i automation/ansible/inventories/production/hosts.yml automation/ansible/playbooks/upgrade-os.yml --limit canary
```

### k3s upgrade policy

Order:
1. Control-plane nodes one-by-one
2. Agent nodes in batches

Run:

```bash
ansible-playbook -i automation/ansible/inventories/production/hosts.yml automation/ansible/playbooks/upgrade-k3s.yml -e k3s_version=v1.32.3+k3s1
```

Validate after each step:

```bash
kubectl get nodes
kubectl get --raw /readyz?verbose
```

## Scale up/down

### Scale up control planes

1. Increase Terraform count and apply.
2. Add new host to inventory group `k3s_servers`.
3. Run server install playbook for new host only.
4. Verify etcd member health.

### Scale down control planes

1. Ensure odd quorum remains (3 or 5 preferred).
2. Cordon/drain target node.
3. Remove server from k3s membership.
4. Remove inventory entry.
5. Terraform destroy that VM instance.

### Scale up workers

1. Provision new worker host.
2. Add to `k3s_agents` group.
3. Run bootstrap + agent install.
4. Verify labels/taints and scheduling.

### Scale down workers

1. `kubectl cordon <node>`
2. `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`
3. Remove node from cluster and inventory.
4. Decommission host.

## Storage resize and migration

### Control-plane VM disk

Prefer replacement strategy over in-place risky changes:
1. Add new larger control-plane node.
2. Confirm healthy.
3. Remove old smaller node.

### Dedicated worker local NVMe

In-place expansion may require maintenance window depending on RAID/LVM/filesystem.
Safer pattern:
1. Add new larger worker node.
2. Replicate stateful data (operator/storage-native migration).
3. Drain and remove old worker.

### Network volumes (if used)

- Expand through provider API/Terraform when supported.
- Rescan and grow partition/filesystem on node using Ansible task.

## Backups and restore expectations

- etcd snapshots scheduled and off-node replicated.
- Persistent workload backups by Velero or app-native backup tooling.
- Test restore quarterly (management and runtime clusters separately).

## Drift management

- Terraform state is source of truth for infra resources.
- Ansible is source of truth for host config.
- Avoid manual one-off hotfixes without codifying them afterward.

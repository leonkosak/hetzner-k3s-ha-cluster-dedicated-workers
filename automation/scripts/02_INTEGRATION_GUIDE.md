# Hetzner K3S Automation — Integration Guide

> 💡 **You probably don't need this.** If you just want to create a cluster,
> read `00_START_HERE.md` and run `./create-cluster.sh`. This document explains
> the internals — useful for troubleshooting or custom setups.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│           K3S Cluster on Hetzner (Complete Flow)            │
└─────────────────────────────────────────────────────────────┘

1. INFRASTRUCTURE PREPARATION
   ├─ Create Hetzner project & API token
   ├─ Create SSH key in Hetzner
   ├─ Create private network (vSwitch for physical servers)
   └─ Create MicroOS snapshot image → 05_MICROOS_IMAGE_PREP.md

2. SERVER CREATION (hcloud-create-servers.sh)
   ├─ Create master nodes (control plane VMs)
   ├─ Create worker nodes (can be CPU or GPU)
   ├─ Attach to private network
   ├─ Export IP addresses
   └─ Servers boot with MicroOS

3. OS BASELINE CONFIGURATION (bootstrap-os.yml)
   ├─ Install kernel modules, sysctl, base packages
   └─ Nodes ready for K3S install

4. K3S INSTALLATION
   ├─ install-k3s-servers.yml → cluster-init, etcd, HA
   └─ install-k3s-agents.yml → join workers

5. CLUSTER VERIFICATION & NETWORKING
   ├─ kubectl get nodes (all Ready)
   ├─ Let's Encrypt on Traefik (HelmChartConfig)
   ├─ Rancher deployment (cert-manager + Helm)
   └─ Optional: NVIDIA GPU plugin, Hetzner CSI

6. OPERATIONS & SCALING
   ├─ Scale: Re-run hcloud-create-servers.sh with new counts
   ├─ Upgrade: upgrade-k3s.yml, upgrade-os.yml
   └─ Monitor: Rancher UI, kubectl
```

---

## Key Scripts

| Script | Purpose |
|--------|---------|
| `hcloud-create-servers.sh` | Create masters + workers on Hetzner |
| `fu-hcloud-create-server.sh` | Function library (auto-loaded) |
| `create-cluster.sh` | **One-command setup** — orchestrates everything |
| `create-k8s-api-lb.sh` | Hetzner Load Balancer for K8s API |
| `deploy-rancher.sh` | Rancher + cert-manager + Let's Encrypt |

Generated files:
| File | Contents |
|------|----------|
| `hcloud_server_ips.env` | Shell variables with all IPs |
| `hcloud_servers_inventory.yml` | Ansible inventory |
| `hcloud_create_servers_*.log` | Detailed execution log |

---

## Configuration Scenarios

### Development (1 master, 2 workers)
```bash
MASTER_COUNT=1
MASTER_TYPE="cx23"       # 2 vCPU, 4GB, €5.99/mo
WORKER_COUNT=2
WORKER_TYPE="cx23"
ATTACH_TO_NETWORK=0
```

### Production HA (3 masters, 3 workers)
```bash
MASTER_COUNT=3
MASTER_TYPE="cx33"       # 4 vCPU, 8GB, €8.99/mo
MASTER_ROTATE_LOCATIONS=1
WORKER_COUNT=3
WORKER_TYPE="cx33"
WORKER_ROTATE_LOCATIONS=1
ATTACH_TO_NETWORK=1
```

### GPU Workers (3 masters + GPU workers)
```bash
MASTER_COUNT=3
MASTER_TYPE="cx33"
WORKER_COUNT=2
WORKER_TYPE="gx211"      # NVIDIA L4
ATTACH_TO_NETWORK=1

# After cluster ready:
helm install nvidia-device-plugin nvidia/device-plugin --namespace kube-system
```

### Mixed CPU + GPU Workers
```bash
# Run twice with different configs:
WORKER_COUNT=3 WORKER_TYPE="cx32" ./hcloud-create-servers.sh
WORKER_COUNT=2 WORKER_TYPE="gx211" ./hcloud-create-servers.sh
```

---

## Advanced Operations

### Resize existing servers
```bash
# Edit hcloud-config.env
UPDATE=1
NEW_MASTER_TYPE="cx52"
NEW_WORKER_TYPE="cx52"
./hcloud-create-servers.sh
```

### Rebuild with a new image
```bash
UPDATE=1
NEW_IMAGE="microos-snapshot-v2"
./hcloud-create-servers.sh
```

### List all cluster servers
```bash
source fu-hcloud-create-server.sh
export CLUSTER_TAG="k3s-cluster"
hcloud_list_cluster_servers
```

### Delete entire cluster
```bash
source fu-hcloud-create-server.sh
export CLUSTER_TAG="k3s-cluster"
hcloud_delete_cluster

# Also delete the load balancer if you created one
./create-k8s-api-lb.sh --delete
```

---

## Scaling

### Add more workers
```bash
# Edit hcloud-config.env: WORKER_COUNT=5 (was 2)
./hcloud-create-servers.sh
source hcloud_server_ips.env

# Join new workers to the cluster
ansible-playbook -i hcloud_servers_inventory.yml \
  -l "k3s-worker-3,k3s-worker-4,k3s-worker-5" \
  ../ansible/playbooks/install-k3s-agents.yml
```

### Remove workers
```bash
kubectl drain k3s-worker-5 --ignore-daemonsets --delete-emptydir-data
hcloud server delete k3s-worker-5
```

---

## Troubleshooting

### Servers created but can't SSH
```bash
hcloud server list -o columns=name,public_net.ipv4.ip      # verify IPs
hcloud server describe k3s-master-1 | grep -i ssh           # check key
ssh -v root@$IP_MASTER_1 'echo OK'                          # verbose test
sleep 60 && ssh root@$IP_MASTER_1 'echo OK'                 # wait longer
```

### Ansible can't connect
```bash
ansible -i hcloud_servers_inventory.yml all -m ping
grep -i "ssh_private_key" hcloud_servers_inventory.yml      # verify key path
ansible -i hcloud_servers_inventory.yml all -m command -a 'whoami'
```

### K3S install fails
```bash
ansible all -m command -a 'cat /etc/sysctl.d/99-k3s.conf'   # bootstrap check
ssh root@$IP_MASTER_1 'journalctl -u k3s -n 50'             # K3S logs
ansible all -m command -a 'cat /etc/os-release | grep PRETTY_NAME'  # OS check
```

### HCLOUD_TOKEN validation failed
```bash
echo "$HCLOUD_TOKEN"
source ~/.config/hetzner/runtime.env
hcloud project list
```

### Image not found
```bash
hcloud image list --type system           # list available images
# Or create MicroOS snapshot → see 05_MICROOS_IMAGE_PREP.md
```

### Server stuck initializing / SSH times out
```bash
hcloud server describe k3s-master-1        # check status
hcloud server reboot k3s-master-1          # force reboot if stuck
```

### Resource unavailable (sold out)
Hetzner occasionally runs out of certain server types in specific locations.
Fix: enable `MASTER_ROTATE_LOCATIONS=1` or change `MASTER_TYPE`.

---

## Performance Tuning

```bash
# API rate limiting (if hitting rate limits)
API_RATE_LIMIT_DELAY=10    # slower/safer

# Server polling (for slow connections)
POLL_TIMEOUT=600
POLL_INTERVAL=10
```

---

## FAQ

**Q: Can I mix CPU and GPU workers?** Yes — create separate runs with different `WORKER_TYPE`.

**Q: How do I add servers to an existing cluster?** Increase `WORKER_COUNT` and re-run.

**Q: Works on Windows?** Yes, in WSL2 with hcloud CLI installed.

---

## Next Steps

- **Ansible playbooks:** `../ansible/README.md`
- **Full runbook:** `../../docs/runbooks/hetzner-from-scratch.md`
- **Day-2 operations:** `../../docs/operations/day2-operations.md`

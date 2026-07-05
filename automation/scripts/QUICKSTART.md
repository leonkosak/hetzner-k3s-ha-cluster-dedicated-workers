# Quick Reference: K3S Server Creation on Hetzner

## TL;DR - Get Started in 5 Minutes

### Prerequisites (One-Time Setup)
```bash
# 1. Install hcloud CLI
curl https://github.com/hetznercloud/cli/releases/download/v1.47.3/hcloud-linux-amd64.tar.gz -L | tar xz -C /usr/local/bin/

# 2. Get your Hetzner API token
#    → Go to https://console.hetzner.com/ → your project → Security → API Tokens
#    → Create a token with Read & Write permissions, copy it
mkdir -p ~/.config/hetzner
cat > ~/.config/hetzner/runtime.env << 'EOF'
export HCLOUD_TOKEN="paste-your-token-here"
EOF
chmod 600 ~/.config/hetzner/runtime.env
# The create-cluster.sh script auto-detects this file — no need to source it manually.

# 3. Create SSH key in Hetzner, upload your public key
hcloud ssh-key create --name k3s-admin --public-key ~/.ssh/id_ed25519_k3s.pub

# 4. Create MicroOS snapshot (see MICROOS_IMAGE_PREP.md)
```

### Create Your First Cluster
```bash
cd automation/scripts

# One-time: store your Hetzner token
mkdir -p ~/.config/hetzner
echo 'export HCLOUD_TOKEN="your-token"' > ~/.config/hetzner/runtime.env
chmod 600 ~/.config/hetzner/runtime.env

# Copy and customize config
cp hcloud-config.env.example hcloud-config.env
nano hcloud-config.env  # Set MASTER_COUNT, WORKER_COUNT, SSH_KEY, IMAGE
# For production: set CREATE_LB=1 and INSTALL_DASHBOARD=1

# Run — one script does everything
./create-cluster.sh
# Done. Run: kubectl get nodes
```

---

## File Guide

| File | Purpose |
|------|---------|
| `hcloud-create-servers.sh` | Main orchestration script - create/manage servers |
| `create-cluster.sh` | **One-command cluster setup** — servers + LB + K3s + dashboard |
| `fu-hcloud-create-server.sh` | Function library - individual server operations |
| `hcloud-config.env.example` | Configuration template - copy and customize |
| `MICROOS_IMAGE_PREP.md` | Bootable MicroOS image preparation for Hetzner Cloud |
| `HCLOUD_SERVER_CREATION.md` | Complete documentation with examples |
| `INTEGRATION_GUIDE.md` | How to integrate with Ansible & K3S |
| `README.md` (existing) | General scripts info |
| `deploy-sample-app.sh` | Deploy nginx demo app with IngressRoute |
| `deploy-kubernetes-dashboard.sh` | Deploy Kubernetes Dashboard with TLS + basic auth |
| `create-k8s-api-lb.sh` | Create Hetzner Load Balancer for K8s API HA |
| `load-balancer.md` | Load balancer docs — deploy, config, tear down |
| `kubernetes-dashboard.md` | Dashboard docs — deploy, users, tokens, kubeconfig |

---

## Common Commands

### List Your Servers
```bash
hcloud server list
hcloud server list --selector "cluster=k3s-cluster"
```

### SSH to a Server
```bash
source hcloud_server_ips.env
ssh -i ~/.ssh/id_ed25519_k3s root@$IP_MASTER_1
```

### Check Server Details
```bash
hcloud server describe k3s-master-1 --output json | jq .
```

### Scale Up (Add More Workers)
```bash
# Edit hcloud-config.env: WORKER_COUNT=5 (was 2)
./hcloud-create-servers.sh
source hcloud_server_ips.env
# Then add to Ansible inventory and run install playbook
```

### Scale Down (Remove Workers)
```bash
hcloud server delete k3s-worker-3
```

### Delete Entire Cluster
```bash
source fu-hcloud-create-server.sh
export CLUSTER_TAG="k3s-cluster"
hcloud_delete_cluster
```

### Export for Terraform
```bash
# Export IPs as Terraform variables for load balancer config
source hcloud_server_ips.env
cat > terraform.tfvars << 'EOF'
master_ips = [
  "$IP_MASTER_1",
  "$IP_MASTER_2",
  "$IP_MASTER_3"
]
worker_ips = [
  "$IP_WORKER_1",
  "$IP_WORKER_2"
]
EOF
```

---

## Configuration Quick Snippets

See [Hetzner Cost-Optimized CX types](https://www.hetzner.com/cloud/cost-optimized) for current server specs and pricing.

### Production HA (3 Masters, 3 Workers)
```bash
MASTER_COUNT=3
MASTER_TYPE="cx33"       # 4 vCPU, 8GB RAM
WORKER_COUNT=3
WORKER_TYPE="cx33"
MASTER_ROTATE_LOCATIONS=1
WORKER_ROTATE_LOCATIONS=1
ATTACH_TO_NETWORK=1
```

### Development (1 Master, 2 Workers)
```bash
MASTER_COUNT=1
MASTER_TYPE="cx23"       # 2 vCPU, 4GB RAM
WORKER_COUNT=2
WORKER_TYPE="cx23"
MASTER_LOCATIONS=("nbg1")
ATTACH_TO_NETWORK=0
```

### GPU Workers (3 Masters + 2 GPU)
```bash
MASTER_COUNT=3
MASTER_TYPE="cx33"
WORKER_COUNT=2
WORKER_TYPE="gx211"      # NVIDIA L4
ATTACH_TO_NETWORK=1
```

---

## Logging & Debugging

### View Script Logs
```bash
tail -f hcloud_create_servers_*.log
grep ERROR hcloud_create_servers_*.log
```

### Test SSH Connectivity
```bash
for i in 1 2 3; do
  echo "Master $i:"
  ssh -o ConnectTimeout=5 root@${!IP_MASTER_$i} "cat /etc/os-release | head -1"
done
```

### Check Ansible Connectivity
```bash
ansible -i hcloud_servers_inventory.yml all -m ping
```

### Monitor Server Creation
```bash
watch -n 5 'hcloud server list'
```

---

## Troubleshooting Quick Fix

| Problem | Fix |
|---------|-----|
| `HCLOUD_TOKEN validation failed` | `export HCLOUD_TOKEN="..."` |
| `SSH key not found` | `hcloud ssh-key create --name k3s-admin --public-key ~/.ssh/id_ed25519_k3s.pub` |
| `Image not found` | Create MicroOS snapshot (see HCLOUD_SERVER_CREATION.md) |
| `SSH times out` | Wait 2-3 minutes, servers still booting |
| `Ansible can't connect` | `ansible -i hcloud_servers_inventory.yml all -m ping` |
| `K3S install fails` | Check bootstrap ran: `ansible all -m command -a 'cat /etc/sysctl.d/99-k3s.conf'` |

---

## User Management & Dashboard

All dashboard-related documentation — user management, tokens, kubeconfig, troubleshooting — has been moved to **[kubernetes-dashboard.md](kubernetes-dashboard.md)**.

---

## Environment Variables

```bash
# Load credentials
source ~/.config/hetzner/runtime.env

# Use custom config file
CONFIG_FILE=hcloud-config.prod.env ./hcloud-create-servers.sh

# Override specific settings
MASTER_COUNT=5 ./hcloud-create-servers.sh

# Set cluster tag
CLUSTER_TAG="prod-cluster" ./hcloud-create-servers.sh
```

---

## Key Files Generated

After running `hcloud-create-servers.sh`, these files are created:

| File | Contents |
|------|----------|
| `hcloud_create_servers_*.log` | Detailed execution log |
| `hcloud_server_ips.env` | Shell variables with all IPs (source this!) |
| `hcloud_servers_inventory.yml` | Ansible inventory YAML |

---

## Integration with Existing Automation

### Use with Terraform Control Planes
```bash
# Terraform creates masters and network
cd automation/terraform/hetzner
terraform apply

# Create workers with these scripts
cd ../../scripts
./hcloud-create-servers.sh

# All nodes join same cluster via Ansible
```

### Use with Existing Ansible Playbooks
```bash
# Scripts export IPs to Ansible inventory format
./hcloud-create-servers.sh

# Run standard Ansible playbooks
ansible-playbook -i hcloud_servers_inventory.yml \
  ../ansible/playbooks/bootstrap-os.yml

ansible-playbook -i hcloud_servers_inventory.yml \
  ../ansible/playbooks/install-k3s-servers.yml
```

---

## GPU Worker Setup

After cluster is running:

```bash
# Install NVIDIA device plugin
helm repo add nvidia https://nvidia.github.io/k8s-device-plugin
helm install nvidia-device-plugin nvidia/nvidia-device-plugin \
  --namespace kube-system

# Verify GPU workers are ready
kubectl get nodes -L nvidia.com/gpu

# Test GPU access
kubectl run -it --image=nvidia/cuda:11.8.0 gpu-test -- nvidia-smi
```

---

## Full Documentation Links

- **Detailed Docs:** [HCLOUD_SERVER_CREATION.md](HCLOUD_SERVER_CREATION.md)
- **Integration:** [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)
- **Complete Runbook:** [docs/runbooks/hetzner-from-scratch.md](../../../docs/runbooks/hetzner-from-scratch.md)
- **Day-2 Operations:** [docs/operations/day2-operations.md](../../../docs/operations/day2-operations.md)

---

## Support

1. Check logs: `grep ERROR hcloud_create_servers_*.log`
2. Verify config: `cat hcloud-config.env`
3. Test connectivity: `ansible -i hcloud_servers_inventory.yml all -m ping`
4. Review full docs: See HCLOUD_SERVER_CREATION.md

---

**Last Updated:** 2026-06-11
**Version:** 1.0

# Hetzner K3S Server Creation Scripts - Enhanced README

## Overview

These scripts automate the creation of K3S master (control plane) and worker nodes on Hetzner Cloud using MicroOS as the host OS.

**Features:**
- ✅ Fully configurable master and worker node counts
- ✅ Multiple server types supported (including GPU workers like GEX44)
- ✅ Multi-location deployment (Falkenstein, Nuremberg, Helsinki, etc.)
- ✅ Optional rotation across locations for availability
- ✅ Private network attachment for secure inter-node communication
- ✅ Automatic IP export for Ansible integration
- ✅ Server lifecycle management (create, update, delete)
- ✅ Comprehensive logging and error handling
- ✅ Rate-limiting for Hetzner API
- ✅ SSH key validation and tag-based organization

## Files

- `hcloud-create-servers.sh` - Main orchestration script
- `fu-hcloud-create-server.sh` - Function library for individual server operations
- `hcloud-config.env.example` - Configuration template (copy and customize)
- `hcloud-config.env` - Your configuration (create from .example, DON'T commit!)

## Prerequisites

### 1. Install Hetzner Cloud CLI

```bash
# On Linux (x86_64)
curl https://github.com/hetznercloud/cli/releases/download/v1.47.3/hcloud-linux-amd64.tar.gz -L -o hcloud.tar.gz
tar xzf hcloud.tar.gz
sudo mv hcloud /usr/local/bin/
hcloud --version
```

See: https://github.com/hetznercloud/cli/releases

### 2. Create Hetzner Project and API Token

```bash
# In Hetzner Cloud Console:
# 1. Create a project (or use existing)
# 2. Project → Security → API Tokens → Generate
# 3. Create SSH key: Project → Security → SSH Keys → Add SSH Key
# 4. Create/snapshot MicroOS image (see section below)
```

### 3. Store API Token Securely

```bash
mkdir -p ~/.config/hetzner
cat > ~/.config/hetzner/runtime.env << 'EOF'
export HCLOUD_TOKEN="your-actual-token-here"
EOF
chmod 600 ~/.config/hetzner/runtime.env

# Load before running script
source ~/.config/hetzner/runtime.env
```

### 4. Create MicroOS Snapshot

This is a one-time setup per Hetzner project.

See detailed instructions in: `docs/runbooks/hetzner-from-scratch.md` (section 4)

Quick summary:
```bash
# 1. Create temporary Cloud VM
# 2. Enable Rescue mode for that VM
# 3. Write MicroOS qcow2 image to disk
# 4. Create snapshot from booted MicroOS VM
# 5. Use snapshot ID/name in hcloud-config.env as MASTER_IMAGE and WORKER_IMAGE
```

## Configuration

### Quick Start

```bash
# Copy template
cp hcloud-config.env.example hcloud-config.env

# Edit with your settings
nano hcloud-config.env

# Key settings to customize:
# - MASTER_COUNT: Number of master nodes (recommend 3 for HA)
# - WORKER_COUNT: Number of worker nodes (recommend 2-3)
# - MASTER_TYPE: cx32 for production
# - SSH_KEY: Your SSH key name in Hetzner
# - MASTER_IMAGE: Your MicroOS snapshot name/ID
```

### Common Configurations

#### Production HA Cluster (3 masters, 3 workers)

```bash
MASTER_COUNT=3
MASTER_TYPE="cx32"
MASTER_ROTATE_LOCATIONS=1
WORKER_COUNT=3
WORKER_TYPE="cx32"
WORKER_ROTATE_LOCATIONS=1
ATTACH_TO_NETWORK=1
```

#### Development Cluster (1 master, 2 workers)

```bash
MASTER_COUNT=1
MASTER_TYPE="cx22"
MASTER_LOCATIONS=("nbg1")
MASTER_ROTATE_LOCATIONS=0
WORKER_COUNT=2
WORKER_TYPE="cx22"
ATTACH_TO_NETWORK=1
```

#### GPU Worker Pool (3 masters + 2 GPU workers)

```bash
MASTER_COUNT=3
MASTER_TYPE="cx32"
WORKER_COUNT=2
WORKER_TYPE="gx211"  # NVIDIA L4 GPU
WORKER_LOCATIONS=("nbg1" "fsn1")
```

## Usage

### 1. Prepare Environment

```bash
# Load credentials
source ~/.config/hetzner/runtime.env

# Navigate to scripts directory
cd automation/scripts

# Verify prerequisites
hcloud project list  # Should list your projects
hcloud ssh-key list  # Should show your SSH key
```

### 2. Run Script

```bash
# Basic run with default config (hcloud-config.env)
./hcloud-create-servers.sh

# Or with custom config file
CONFIG_FILE=hcloud-config.prod.env ./hcloud-create-servers.sh
```

### 3. Monitor Progress

```bash
# In another terminal, watch server creation
watch -n 5 'hcloud server list'

# Or check logs
tail -f hcloud_create_servers_*.log

# Check specific server
hcloud server describe k3s-master-1
```

### 4. Retrieve IPs

```bash
# After script completes, IPs are exported to file
source hcloud_server_ips.env

# Access individual IPs
echo "Master 1: $IP_MASTER_1"
echo "Master 2: $IP_MASTER_2"
echo "Worker 1: $IP_WORKER_1"

# Or view generated Ansible inventory
cat hcloud_servers_inventory.yml
```

### 5. Wait for SSH

Servers take 2-3 minutes to boot and SSH to become available.

```bash
# Check SSH connectivity
ssh -o ConnectTimeout=5 root@"$IP_MASTER_1" 'echo "SSH OK"'

# Or wait in loop
for i in {1..30}; do
  ssh -o ConnectTimeout=5 root@"$IP_MASTER_1" 'echo "SSH OK"' && break
  echo "Waiting... ($i/30)"
  sleep 10
done
```

### 6. Integrate with Ansible

```bash
# Use generated inventory
cd ../..  # Back to repo root

# Run bootstrap playbook
ansible-playbook \
  -i automation/scripts/hcloud_servers_inventory.yml \
  automation/ansible/playbooks/bootstrap-os.yml

# Install K3S
ansible-playbook \
  -i automation/scripts/hcloud_servers_inventory.yml \
  automation/ansible/playbooks/install-k3s-servers.yml

ansible-playbook \
  -i automation/scripts/hcloud_servers_inventory.yml \
  automation/ansible/playbooks/install-k3s-agents.yml

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

## Advanced Operations

### Resize Existing Servers

```bash
# Edit hcloud-config.env
UPDATE=1
NEW_MASTER_TYPE="cx52"
NEW_WORKER_TYPE="cx52"

# Run script
./hcloud-create-servers.sh
```

### Rebuild with New Image

```bash
# Edit hcloud-config.env
UPDATE=1
NEW_IMAGE="microos-snapshot-v2"

# Run script
./hcloud-create-servers.sh
```

### List All Cluster Servers

```bash
# Source the functions
source fu-hcloud-create-server.sh

# Set cluster tag
export CLUSTER_TAG="k3s-cluster"

# List servers
hcloud_list_cluster_servers
```

### Delete Entire Cluster (Use with Caution!)

```bash
# Source the functions
source fu-hcloud-create-server.sh

# Set cluster tag
export CLUSTER_TAG="k3s-cluster"

# Delete all servers tagged with cluster
hcloud_delete_cluster
```

### Manual SSH to Server

```bash
# Using public IP
ssh -i ~/.ssh/id_ed25519_k3s root@"$IP_MASTER_1"

# Or specify key explicitly
ssh -o IdentityFile=~/.ssh/id_ed25519_k3s root@"$IP_MASTER_1"

# For private-only nodes, use jump host
ssh -o ProxyJump=root@"$IP_MASTER_1" root@10.80.10.21
```

## Troubleshooting

### Issue: "HCLOUD_TOKEN validation failed"

**Solution:** Verify your API token:
```bash
echo "$HCLOUD_TOKEN"  # Should print your token
hcloud project list   # Should work
```

### Issue: "SSH key 'k3s-admin' not found"

**Solution:** Create SSH key in Hetzner:
```bash
hcloud ssh-key create --name k3s-admin --public-key ~/.ssh/id_ed25519_k3s.pub
hcloud ssh-key list  # Verify
```

### Issue: "Image 'microos-snapshot' not found"

**Solution:** Create MicroOS snapshot (one-time per project):
- See `docs/runbooks/hetzner-from-scratch.md` section 4
- Use correct snapshot ID/name in `hcloud-config.env`
- List available images: `hcloud image list --type system`

### Issue: Server stuck in "initializing" status

**Solution:** Wait longer (5-10 minutes typical), or check logs:
```bash
hcloud server describe k3s-master-1 --format json
# Look at "status" and "action" fields

# Force reboot if stuck
hcloud server reboot k3s-master-1
```

### Issue: SSH times out after server is "running"

**Solution:** Server may still be booting. Wait and retry:
```bash
sleep 30
ssh -o ConnectTimeout=10 root@"$IP_MASTER_1" 'echo "SSH OK"'
```

### Issue: Private network attachment failed

**Solution:** Verify network and vSwitch configuration:
```bash
# List networks
hcloud network list

# Check network has vSwitch enabled (for physical servers)
hcloud network describe runtime-net --format json | grep -i vswitch
```

## Log Files

Script creates dated log files automatically:
```bash
hcloud_create_servers_1718286542.log  # Example timestamp
```

Review logs for detailed execution trace:
```bash
tail -n 100 hcloud_create_servers_*.log
grep -E "ERROR|FAIL" hcloud_create_servers_*.log
```

## Integration with Existing Infrastructure

### Terraform Control Planes

These scripts create **worker nodes only** for Terraform-provisioned clusters:

```bash
# Terraform creates:
# - Cloud VMs for control planes (k3s-master-*)
# - Load balancer
# - Private network
# - Firewall rules

# Then use these scripts to:
# - Add additional masters (if scaling control plane)
# - Add worker nodes (cx22, cx32, GPU workers, etc.)

# Workflow:
terraform apply  # Creates control plane infrastructure
./hcloud-create-servers.sh  # Adds workers
ansible-playbook bootstrap-os.yml  # Baseline setup
ansible-playbook install-k3s-agents.yml  # Join workers
```

## Performance Tuning

### API Rate Limiting

Adjust `API_RATE_LIMIT_DELAY` if hitting rate limits:
```bash
# Slower (safer)
API_RATE_LIMIT_DELAY=10

# Faster (risk rate limit errors)
API_RATE_LIMIT_DELAY=2
```

### Server Polling

Adjust `POLL_TIMEOUT` and `POLL_INTERVAL` for slow connections:
```bash
# Default (300 seconds total timeout)
POLL_TIMEOUT=300
POLL_INTERVAL=5

# Faster detection
POLL_TIMEOUT=600
POLL_INTERVAL=10
```

## FAQ

**Q: Can I mix CPU and GPU workers?**
A: Yes! Set `WORKER_TYPE=gx211` for GPU workers, or create separate runs with different `WORKER_TYPE` values.

**Q: How do I add servers to an existing cluster?**
A: Update `MASTER_COUNT` or `WORKER_COUNT` and re-run. New servers will be created, existing ones will be skipped.

**Q: Can I run this on Windows?**
A: Yes, in WSL2 or Git Bash with hcloud CLI installed.

**Q: How do I backup/migrate the cluster?**
A: Use Velero or similar backup tool. These scripts only handle infrastructure creation; data persistence requires separate backup strategy.

## Additional Resources

- Hetzner Cloud CLI: https://github.com/hetznercloud/cli
- Hetzner Cloud API: https://docs.hetzner.cloud/
- openSUSE MicroOS: https://microos.opensuse.org/
- K3S Documentation: https://docs.k3s.io/
- Ansible Playbooks: See `automation/ansible/README.md`
- Full Runbook: See `docs/runbooks/hetzner-from-scratch.md`

## Support & Contributions

- Check logs for errors: `grep ERROR hcloud_create_servers_*.log`
- Validate config: Review settings in `hcloud-config.env`
- Verify prerequisites: Run all checks in Prerequisites section
- Review Hetzner limits: https://docs.hetzner.cloud/#rate-limiting

---

**Last Updated:** 2026-06-11
**Tested On:** Ubuntu 24.04, Hetzner Cloud CLI v1.47+, Bash 5.0+

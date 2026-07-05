# K3S Hetzner Server Creation - Getting Started

## 🎯 What You Have

A complete, production-ready automation solution for creating K3S servers on Hetzner Cloud with MicroOS. This enhances your existing Terraform + Ansible + bash script setup.

---

## 📁 File Locations

All new files are in: **`automation/scripts/`**

```
automation/scripts/
├── 📄 QUICKSTART.md                    ← START HERE! (5 min read)
├── 📄 HCLOUD_SERVER_CREATION.md        ← Full documentation (30 min read)
├── 📄 INTEGRATION_GUIDE.md             ← How it integrates (20 min read)
├── 📄 hcloud-config.env.example        ← Copy & customize
│
├── 🔧 hcloud-create-servers.sh         ← Main script (RUN THIS)
└── 📚 fu-hcloud-create-server.sh       ← Function library (auto-loaded)
```

---

## ⚡ Quick Start (5 Minutes)

### 1️⃣ Load Your Credentials
```bash
export HCLOUD_TOKEN="your-api-token-here"
# Or load from file: source ~/.config/hetzner/runtime.env
```

### 2️⃣ Copy Configuration
```bash
cd automation/scripts
cp hcloud-config.env.example hcloud-config.env
```

### 3️⃣ Customize (Edit These Variables)
```bash
nano hcloud-config.env

# Key settings:
MASTER_COUNT=3           # Number of master nodes
WORKER_COUNT=2           # Number of worker nodes
MASTER_TYPE="cx32"       # Server size
SSH_KEY="k3s-admin"      # SSH key name
MASTER_IMAGE="microos-snapshot"  # Your MicroOS image
```

### 4️⃣ Run It
```bash
./hcloud-create-servers.sh
```

### 5️⃣ Wait & Bootstrap
```bash
# Wait 5-10 minutes for servers to boot, then:
source hcloud_server_ips.env

# Run Ansible
cd ../..
ansible-playbook -i automation/scripts/hcloud_servers_inventory.yml \
  automation/ansible/playbooks/bootstrap-os.yml

ansible-playbook -i automation/scripts/hcloud_servers_inventory.yml \
  automation/ansible/playbooks/install-k3s-servers.yml

ansible-playbook -i automation/scripts/hcloud_servers_inventory.yml \
  automation/ansible/playbooks/install-k3s-agents.yml
```

---

## 📖 Documentation Roadmap

```
START HERE
    ↓
📄 QUICKSTART.md (TL;DR, 5 min)
    ↓
Want to understand the flow?
    ↓
📄 INTEGRATION_GUIDE.md (Full workflow, 20 min)
    ↓
Need detailed features?
    ↓
📄 HCLOUD_SERVER_CREATION.md (Complete ref, 30 min)
    ↓
Ready to run?
    ↓
✏️  hcloud-config.env (Customize)
    ↓
🚀 ./hcloud-create-servers.sh (Execute)
```

---

## 🎯 What Each Script Does

### `hcloud-create-servers.sh` (Main Script)
- **What:** Orchestrates server creation
- **When:** Run this to create your cluster
- **Output:** 
  - `hcloud_server_ips.env` (IPs for automation)
  - `hcloud_servers_inventory.yml` (Ansible inventory)
  - `hcloud_create_servers_*.log` (Detailed logs)

### `fu-hcloud-create-server.sh` (Functions Library)
- **What:** Reusable functions for individual operations
- **When:** Auto-loaded by main script
- **Useful for:** Advanced operations, manual server management

---

## 🔑 Key Features at a Glance

| Feature | What It Does | Use Case |
|---------|------------|----------|
| **Multi-location** | Deploy across EU locations | Geographic redundancy |
| **Auto-rotation** | Spread servers across datacenters | Load balancing |
| **GPU Support** | Create GPU worker nodes | ML/AI workloads |
| **Private Network** | Secure inter-node communication | Production security |
| **Ansible Integration** | Auto-generate inventory | Seamless automation |
| **Update Mode** | Resize/rebuild existing servers | Scaling existing cluster |
| **Lifecycle Management** | Create, update, delete servers | Complete cluster control |
| **Comprehensive Logging** | Detailed timestamped logs | Troubleshooting |

---

## 📋 Configuration Examples

### Example 1: Production HA (3 Masters, 3 Workers)
```bash
MASTER_COUNT=3
MASTER_TYPE="cx32"
WORKER_COUNT=3
WORKER_TYPE="cx32"
MASTER_ROTATE_LOCATIONS=1  # Spread across locations
ATTACH_TO_NETWORK=1        # Private network
```

### Example 2: Development (1 Master, 2 Workers)
```bash
MASTER_COUNT=1
MASTER_TYPE="cx22"  # Smaller
WORKER_COUNT=2
WORKER_TYPE="cx22"
ATTACH_TO_NETWORK=0  # Optional for dev
```

### Example 3: GPU Cluster (3 Masters, 2 GPU Workers)
```bash
MASTER_COUNT=3
MASTER_TYPE="cx32"
WORKER_COUNT=2
WORKER_TYPE="gx211"  # NVIDIA L4 GPU
```

---

## 🔄 Complete Workflow

```
┌─ One-Time Setup ─────────────────────────────────┐
│ 1. Create Hetzner project                        │
│ 2. Create SSH key in Hetzner                     │
│ 3. Create API token                              │
│ 4. Create MicroOS snapshot                       │
│ 5. Create private network                        │
└────────────────────────────────────────────────┬┘
                                                 ↓
         ┌─ Create Servers ──────────────────────────┐
         │ 1. Copy hcloud-config.env.example         │
         │ 2. Customize settings (counts, type, etc) │
         │ 3. Run: ./hcloud-create-servers.sh        │
         │ 4. Wait 5-10 minutes                      │
         │ 5. Source IPs: source hcloud_server_ips   │
         └──────────────────────────┬────────────────┘
                                    ↓
    ┌─ Bootstrap with Ansible ──────────────────────┐
    │ 1. ansible-playbook bootstrap-os.yml          │
    │ 2. ansible-playbook install-k3s-servers.yml   │
    │ 3. ansible-playbook install-k3s-agents.yml    │
    └──────────────────────────┬────────────────────┘
                               ↓
              ┌─ Verify Cluster ──────────────┐
              │ kubectl get nodes             │
              │ kubectl get pods -A           │
              └──────────────────────────────┘
```

---

## 🚀 Common Operations

### List Your Servers
```bash
hcloud server list
```

### SSH to a Server
```bash
source hcloud_server_ips.env
ssh -i ~/.ssh/id_ed25519_k3s root@$IP_MASTER_1
```

### Add More Workers
```bash
# Edit hcloud-config.env: WORKER_COUNT=5 (was 2)
./hcloud-create-servers.sh
```

### Delete a Server
```bash
hcloud server delete k3s-worker-3
```

### Check Server Details
```bash
hcloud server describe k3s-master-1
```

---

## 🐛 Troubleshooting

### Problem: "HCLOUD_TOKEN validation failed"
```bash
# Solution:
export HCLOUD_TOKEN="your-actual-token"
./hcloud-create-servers.sh
```

### Problem: "SSH key not found"
```bash
# Solution:
hcloud ssh-key create --name k3s-admin --public-key ~/.ssh/id_ed25519_k3s.pub
```

### Problem: "SSH times out"
```bash
# Solution: Wait 2-3 minutes, servers still booting
sleep 60
ssh root@$IP_MASTER_1 'echo OK'
```

### Problem: "Image not found"
```bash
# Solution: Create MicroOS snapshot (see docs)
# See: docs/runbooks/hetzner-from-scratch.md section 4
```

**For more help:** Check `HCLOUD_SERVER_CREATION.md` troubleshooting section

---

## 📦 What's in Each File

| File | Size | Purpose |
|------|------|---------|
| `hcloud-create-servers.sh` | 12KB | Main orchestration script |
| `fu-hcloud-create-server.sh` | 12KB | Function library (auto-loaded) |
| `hcloud-config.env.example` | 7KB | Configuration template |
| `QUICKSTART.md` | 4KB | 5-minute quick start |
| `HCLOUD_SERVER_CREATION.md` | 11KB | Complete documentation |
| `INTEGRATION_GUIDE.md` | 9KB | Workflow integration guide |

---

## ✅ Capabilities

You can now:

- ✅ Create master (control plane) nodes
- ✅ Create worker nodes  
- ✅ Mix CPU and GPU workers
- ✅ Deploy across multiple locations
- ✅ Use private networks for security
- ✅ Auto-generate Ansible inventory
- ✅ Scale cluster up or down
- ✅ Manage complete lifecycle
- ✅ Integrate with Terraform
- ✅ Automate from zero to running cluster

---

## 🎓 Learning Path

**5 minutes:**
- Read [QUICKSTART.md](QUICKSTART.md)

**15 minutes:**
- Read [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)
- Copy and review `hcloud-config.env.example`

**30 minutes:**
- Read [HCLOUD_SERVER_CREATION.md](HCLOUD_SERVER_CREATION.md)
- Customize `hcloud-config.env`
- Run the script

**45 minutes:**
- Script runs and creates servers (5-10 min wait)
- Bootstrap with Ansible
- Verify cluster is running

---

## 🔗 Integration Points

### With Your Terraform
```bash
# Terraform creates control planes
terraform apply

# These scripts create workers
./hcloud-create-servers.sh

# All nodes join same cluster via Ansible
```

### With Your Ansible
```bash
# Scripts auto-generate inventory
./hcloud-create-servers.sh

# Use with existing playbooks
ansible-playbook -i hcloud_servers_inventory.yml playbook.yml
```

### With Your Runbooks
- See: `docs/runbooks/hetzner-from-scratch.md`
- Scripts implement steps 5-6 of the runbook
- Terraform implements earlier infrastructure steps

---

## 📞 Next Steps

1. **Read** `QUICKSTART.md` (5 minutes)
2. **Copy** configuration: `cp hcloud-config.env.example hcloud-config.env`
3. **Customize** settings in `hcloud-config.env`
4. **Run** `./hcloud-create-servers.sh`
5. **Bootstrap** with Ansible playbooks
6. **Verify** cluster with `kubectl get nodes`

---

## 📝 Notes

- Scripts are idempotent: safe to run multiple times
- Existing servers are skipped, new ones are created
- All servers get tagged for easy management
- Comprehensive logging for debugging
- Production-ready error handling

---

**Ready?** → Start with [QUICKSTART.md](QUICKSTART.md)

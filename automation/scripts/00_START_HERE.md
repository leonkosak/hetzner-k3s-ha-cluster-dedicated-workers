# Docs:
automation/scripts/
├── 00_START_HERE.md          ← Main entry — install tools, one command
├── 01_QUICKSTART.md          ← TL;DR — commands, snippets, troubleshooting
├── 02_INTEGRATION_GUIDE.md   ← MERGED — architecture, configs, scaling, advanced ops, FAQ
├── 03_load-balancer.md       ← Hetzner LB (was 04)
├── 04_RANCHER.md             ← Rancher deploy & management (was 05)
├── 05_MICROOS_IMAGE_PREP.md  ← MicroOS snapshot prep (was 06)
└── README.md                 ← Brief pointer


# K3s HA Cluster on Hetzner — Getting Started
One command to create a production-ready HA K3s cluster on Hetzner Cloud:

```bash
cd automation/scripts
cp hcloud-config.env.example hcloud-config.env   # edit to your needs
./create-cluster.sh
```

That's it. Servers, load balancer, OS bootstrap, K3s install, Let's Encrypt TLS, and Rancher — all automated.

---

## System requirements

- **Linux** (native or WSL2) or **macOS**
- A Hetzner Cloud account (sign up at [hetzner.com/cloud](https://www.hetzner.com/cloud))
- About 15–20 minutes for a full cluster creation

---

## Prerequisites (one-time setup)

You only need to do this once per machine. About 10 minutes.

### 1. Install the Hetzner CLI (`hcloud`)

**Linux:**
```bash
# Download and install
curl -L https://github.com/hetznercloud/cli/releases/download/v1.47.3/hcloud-linux-amd64.tar.gz -o /tmp/hcloud.tar.gz
tar xzf /tmp/hcloud.tar.gz -C /tmp
sudo mv /tmp/hcloud /usr/local/bin/hcloud

# Verify
hcloud version
```

**macOS:**
```bash
brew install hcloud
```

**Windows (WSL2):** use the Linux instructions above inside your WSL terminal.

### 2. Install Ansible

**Linux (Debian/Ubuntu):**
```bash
sudo apt update && sudo apt install -y ansible
```

**Linux (Fedora/RHEL):**
```bash
sudo dnf install -y ansible
```

**macOS:**
```bash
brew install ansible
```

**Any Linux (pip):**
```bash
pip3 install --user ansible
```

Verify:
```bash
ansible --version
```

### 3. Generate an SSH key and upload it to Hetzner

If you already have an SSH key at `~/.ssh/id_rsa` or `~/.ssh/id_ed25519`, skip the generation step.

```bash
# Generate a new key (press Enter for defaults, no passphrase)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_k3s -N ""

# Upload the public key to Hetzner
hcloud ssh-key create --name k3s-admin --public-key-from-file ~/.ssh/id_ed25519_k3s.pub
```

> **Important:** note the key name (`k3s-admin`) — you'll put it in `hcloud-config.env` later.

### 4. Create an API token

1. Go to [console.hetzner.com](https://console.hetzner.com) → your project
2. **Security** → **API Tokens** → **Generate API Token**
3. Give it a name (e.g. "k3s-cluster"), select **Read & Write**, click **Create**
4. Copy the token — it's shown only once

Store it so the script auto-detects it:
```bash
mkdir -p ~/.config/hetzner
echo 'export HCLOUD_TOKEN="paste-your-token-here"' > ~/.config/hetzner/runtime.env
chmod 600 ~/.config/hetzner/runtime.env
```

### 5. Create a MicroOS snapshot in Hetzner

This is a one-time step per Hetzner project. Follow the step-by-step guide in
**[05_MICROOS_IMAGE_PREP.md](05_MICROOS_IMAGE_PREP.md)** — you'll create a
temporary VM, write the MicroOS disk image, and snapshot it.

Once done, put the snapshot name in your `hcloud-config.env` as `MASTER_IMAGE` and `WORKER_IMAGE`.
For current project this was already done, hcloud-config.env is defined with boootable MicroOS image , e.g. MASTER_IMAGE="403783838" .  

---

## What `create-cluster.sh` does

| Step | What | Script/Playbook |
|------|------|----------------|
| 1 | Create Hetzner servers (masters + workers) | `hcloud-create-servers.sh` |
| 2 | Create K8s API load balancer (if `CREATE_LB=1`) | `create-k8s-api-lb.sh` |
| 3 | Wait for SSH, bootstrap OS | `bootstrap-os.yml` |
| 4 | Install K3s on masters | `install-k3s-servers.yml` |
| 5 | Install K3s on workers | `install-k3s-agents.yml` |
| 6 | Configure Let's Encrypt on Traefik | inline HelmChartConfig |
| 7 | Deploy Rancher (if `INSTALL_RANCHER=1`) | `deploy-rancher.sh` |
| 8 | Save kubeconfig to `~/.kube/config` | `create-k8s-api-lb.sh --permanent` |

---

## Configuration (`hcloud-config.env`)

Key settings to customize:

```bash
MASTER_COUNT=3              # 3 for HA, 1 for dev
WORKER_COUNT=3
MASTER_TYPE="cx23"          # See Hetzner CX pricing
WORKER_TYPE="cx23"
CREATE_LB=1                 # 1 = create API load balancer
INSTALL_RANCHER=1           # 1 = deploy Rancher UI
RANCHER_PASSWORD="admin123" # initial admin password
SSH_KEY="k3s-admin"         # the SSH key name you configured in Hetzner
```

---

## Documentation index

| File | What's in it |
|------|-------------|
| **00_START_HERE.md** | ← You are here. Overview, install tools, single-command flow. |
| **01_QUICKSTART.md** | TL;DR reference — common commands, config snippets, troubleshooting |
| **02_INTEGRATION_GUIDE.md** | Full architecture, config scenarios, scaling, troubleshooting |
| **03_load-balancer.md** | Hetzner Load Balancer — deploy, configure, tear down |
| **04_RANCHER.md** | Rancher deployment and management — deploy, login, reset password |
| **05_MICROOS_IMAGE_PREP.md** | How to prepare a MicroOS snapshot in Hetzner Cloud |

# K8s API Load Balancer

Creates a Hetzner Cloud Load Balancer that fronts the K3s API (`:6443`) across all
master nodes, providing a single stable IP for `kubectl` and node join operations.

## Deploy

```bash
cd automation/scripts
source ~/.config/hetzner/runtime.env
source hcloud_server_ips.env

# Create LB + save kubeconfig locally (recommended)
./create-k8s-api-lb.sh --permanent

# Or just create the LB without touching kubeconfig
./create-k8s-api-lb.sh
```

## How it works

```
Masters: <IP_MASTER_1>, <IP_MASTER_2>, <IP_MASTER_3>
                          │
      ┌───────────────────┼───────────────────┐
      ▼                   ▼                   ▼
 ┌─────────┐        ┌─────────┐        ┌─────────┐
 │ master1 │        │ master2 │        │ master3 │
 │  :6443  │        │  :6443  │        │  :6443  │
 └────┬────┘        └────┬────┘        └────┬────┘
      │                  │                  │
      └──────────────────┼──────────────────┘
                         ▼
              ┌──────────────────┐
              │   Load Balancer  │
              │   49.xx.xx.xx    │
              │     :6443        │
              └──────────────────┘
                         ▲
                         │
                  kubectl / agents
```

After creation, update `k3s_api_endpoint` in `group_vars/all.yml` or set the
environment variable when running the install playbooks.

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `LB_NAME` | `k3s-cluster-api-lb` | Load balancer name in Hetzner |
| `LB_TYPE` | `lb11` | Type (lb11=€7.49, lb21=€21.49, lb31=€42.99) |
| `LB_LOCATION` | `nbg1` | Datacenter location |
| `LB_PORT` | `6443` | API port |

### TLS certificate note

The K3s server certificate must include the LB IP as a Subject Alternative Name
for kubectl to verify TLS. Two options:

1. **Auto (recommended):** Set `CREATE_LB=1` in `hcloud-config.env` **before** running
   `hcloud-create-servers.sh`. The Ansible playbook will auto-detect the LB and add
   its IP as a `--tls-san` during K3s install.

2. **Manual:** If the cluster already exists, the `--permanent` flag saves the
   kubeconfig with `insecure-skip-tls-verify: true` as a workaround. Recreate the
   cluster to get proper TLS verification.

### Make kubeconfig permanent

```bash
# Deploy LB and save kubeconfig locally so kubectl uses the LB automatically
./create-k8s-api-lb.sh --permanent

# Verify
kubectl get nodes
```

### Ad-hoc usage (no permanent changes)

```bash
./create-k8s-api-lb.sh
# Prints the LB IP — use it inline:
kubectl --kubeconfig=<(ssh root@$IP_MASTER_1 'cat /etc/rancher/k3s/k3s.yaml' \
  | sed 's#https://127.0.0.1:6443#https://<LB_IP>:6443#g') get nodes
```

### Re-run (LB already exists)

The script detects the existing LB and skips creation. Use `--permanent` on
re-runs to refresh the local kubeconfig:

```bash
./create-k8s-api-lb.sh --permanent
```

### Remove the load balancer

```bash
source ~/.config/hetzner/runtime.env
./create-k8s-api-lb.sh --delete
```

This removes the LB and all its targets. Servers are not affected.


## Tear down

```bash
hcloud load-balancer delete k3s-cluster-api-lb
```

# Kubernetes Dashboard

## Deploy

```bash
cd automation/scripts
source hcloud_server_ips.env

# Single user
DASHBOARD_BASIC_AUTH_USER=admin DASHBOARD_BASIC_AUTH_PASSWORD='change-me' ./deploy-kubernetes-dashboard.sh

# Or multiple users
DASHBOARD_BASIC_AUTH_USERS="admin:admin123 operator:op123 viewer:view123" ./deploy-kubernetes-dashboard.sh
```

## Access URLs

| URL | Protocol | Auth | Notes |
|-----|----------|------|-------|
| `https://db.$IP_MASTER_1.nip.io/` | HTTPS | Skip button | Let's Encrypt — works on phones |
| `http://db.$IP_MASTER_1.nip.io/` | HTTP | Skip button | No TLS |
| `http://dashboard.$IP_MASTER_1.nip.io/` | HTTP | basic auth | SPA may break in browsers |
| `https://$IP_MASTER_1:30443` | HTTPS | Skip button | Self-signed — blocked on phones |

Log in with the printed token or click **Skip**.

## User Management

### Add Basic-Auth Users

The dashboard is protected by Traefik's basic-auth middleware. To add or change users:

**Single user (redeploy):**
```bash
source hcloud_server_ips.env
DASHBOARD_BASIC_AUTH_USER=admin DASHBOARD_BASIC_AUTH_PASSWORD='new-password' ./deploy-kubernetes-dashboard.sh
```

**Multiple users (redeploy):**
```bash
source hcloud_server_ips.env
DASHBOARD_BASIC_AUTH_USERS="admin:admin123 operator:op123 viewer:view123" ./deploy-kubernetes-dashboard.sh
```

**Manual update (without redeploy):**
```bash
source hcloud_server_ips.env

# Generate hashes
HASH1=$(openssl passwd -apr1 'admin-pass')
HASH2=$(openssl passwd -apr1 'operator-pass')

# Update the secret (users line-separated, htpasswd format)
kubectl --kubeconfig=<(ssh root@$IP_MASTER_1 'cat /etc/rancher/k3s/k3s.yaml' | sed "s#https://127.0.0.1:6443#https://$IP_MASTER_1:6443#g") \
  -n kubernetes-dashboard create secret generic kubernetes-dashboard-basic-auth \
  --from-literal="users=admin:$HASH1
operator:$HASH2" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Add Cluster-Admin Service Accounts

Create additional service accounts with cluster-admin access for token-based login:

```bash
source hcloud_server_ips.env
KUBECTL="kubectl --kubeconfig=<(ssh root@$IP_MASTER_1 'cat /etc/rancher/k3s/k3s.yaml' | sed "s#https://127.0.0.1:6443#https://$IP_MASTER_1:6443#g")"

# Create a new admin service account
eval "$KUBECTL -n kubernetes-dashboard create serviceaccount operator-user"

# Bind it to cluster-admin
eval "$KUBECTL apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: operator-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: operator-user
    namespace: kubernetes-dashboard
EOF"

# Get a token for this user
eval "$KUBECTL -n kubernetes-dashboard create token operator-user"
```

### Get Tokens

**Temporary token (1 hour):**
```bash
source hcloud_server_ips.env
kubectl --kubeconfig=<(ssh root@$IP_MASTER_1 'cat /etc/rancher/k3s/k3s.yaml' | sed "s#https://127.0.0.1:6443#https://$IP_MASTER_1:6443#g") \
  -n kubernetes-dashboard create token admin-user
```

**Long-lived token (no expiry):**
```bash
source hcloud_server_ips.env
kubectl --kubeconfig=<(ssh root@$IP_MASTER_1 'cat /etc/rancher/k3s/k3s.yaml' | sed "s#https://127.0.0.1:6443#https://$IP_MASTER_1:6443#g") \
  -n kubernetes-dashboard apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-token
  annotations:
    kubernetes.io/service-account.name: admin-user
type: kubernetes.io/service-account-token
EOF
# Wait a moment, then extract:
kubectl --kubeconfig=<(ssh root@$IP_MASTER_1 'cat /etc/rancher/k3s/k3s.yaml' | sed "s#https://127.0.0.1:6443#https://$IP_MASTER_1:6443#g") \
  -n kubernetes-dashboard get secret admin-user-token -o jsonpath='{.data.token}' | base64 -d && echo
```

### Get the Kubeconfig File

```bash
source hcloud_server_ips.env
ssh root@$IP_MASTER_1 'cat /etc/rancher/k3s/k3s.yaml' \
  | sed "s#https://127.0.0.1:6443#https://$IP_MASTER_1:6443#g" \
  > ~/.kube/config
kubectl get nodes
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Dashboard 404 on phone` | Use HTTPS: `https://db.$IP_MASTER_1.nip.io` — self-signed NodePort certs are blocked by mobile browsers |
| `Dashboard broken after login` | Basic auth breaks SPAs — use `http://db.$IP_MASTER_1.nip.io` (HTTP, Skip) instead |
| `Invalid credentials` in browser | Use the Skip button, or the HTTPS URL — basic auth over HTTP + SPA is unreliable |

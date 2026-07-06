# Rancher Management UI

Rancher provides a web-based UI for cluster management, monitoring, and operations.
It is deployed as part of `create-cluster.sh` (step 7, if `INSTALL_RANCHER=1`).

## Deploy

Rancher is installed automatically by `create-cluster.sh`. To deploy it manually:

```bash
source hcloud_server_ips.env
./deploy-rancher.sh
```

The script installs:
- **cert-manager** (v1.16.2) — required by Rancher for TLS
- **Rancher** (v2.14.3) — the management UI
- A Traefik `IngressRoute` with Let's Encrypt TLS

## Access

```
https://rancher.<MASTER_IP>.nip.io
```

The admin password is displayed at the end of the script output:
```
==============================================
  Rancher deployed!
  URL:      https://rancher.91.98.125.143.nip.io
  Username: admin
  Password: <actual-password>
  (bootstrap password / current password)
==============================================
```

## Login

- **First install**: enter the bootstrap password (shown in terminal), then set your own admin password on the setup page.
- **Re-run on existing cluster**: the script auto-detects this and resets the password — use the new one displayed.

## Reset admin password

```bash
kubectl -n cattle-system exec deployment/rancher -- reset-password
```

The new password is printed to stdout. This is what `deploy-rancher.sh` calls internally when it detects an existing Rancher setup.

## Post-login: import this cluster

After logging in:
1. Go to ☰ → **Cluster Management** → **Import Existing**
2. Rancher will auto-detect the `local` cluster (the K3s cluster it's running on)
3. It's already managed — no further import steps needed

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "401 Unauthorized" at login | Password was reset by a subsequent script run. Check terminal output for the latest password, or run `kubectl exec rancher -- reset-password`. |
| Browser shows cert warning | Let's Encrypt not configured. Run step 6 of `create-cluster.sh` or apply the `HelmChartConfig` for Traefik. |
| Rancher pod not starting | Check cert-manager is running: `kubectl -n cert-manager get pods` |

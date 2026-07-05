# Scripts

These scripts are intended to be fetched directly from GitHub on target nodes.

Example:

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/<branch>/automation/scripts/node-bootstrap.sh | sudo bash
```

Keep scripts small and explicit; orchestration belongs in Ansible.

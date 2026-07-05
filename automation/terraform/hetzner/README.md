# Terraform (Hetzner adapter)

This module provisions:
- private network + subnet
- firewall baseline
- control-plane VM set
- API load balancer (`6443/tcp`)

Note:
- set `image` to a Hetzner Cloud snapshot created from openSUSE MicroOS.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Export outputs to inventory or copy values into Ansible inventory manually.

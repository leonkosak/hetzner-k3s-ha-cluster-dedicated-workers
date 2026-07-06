# Prepare a Bootable openSUSE MicroOS Image for Hetzner Cloud

This document explains how to prepare a bootable openSUSE MicroOS image in Hetzner Cloud, create a snapshot, and use it as the image for your K3S master and worker nodes.

## Why this is needed

Hetzner Cloud servers must boot from a disk image that has a valid bootloader and partition layout. The OpenStack QCOW2 image is suitable for Hetzner/KVM only if you write it to the VM disk as a raw disk image, not if you try to use it directly as an ISO or an imported disk file.

## Recommended image

Use the `ContainerHost OpenStack Cloud` QCOW2 image from openSUSE:

- `https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-ContainerHost-OpenStack-Cloud.qcow2`

This is the recommended starting point for Hetzner Cloud because it is a KVM-compatible cloud image variant.

> Do not use the ISO installer for this workflow. Instead, write the QCOW2 image directly to the target disk in rescue mode.

## Steps

### 1. Create a temporary Hetzner server

Create a temporary server with any standard Linux image and attach your SSH key.

```bash
hcloud server create \
  --name microos-template \
  --type cpx21 \
  --location nbg1 \
  --image ubuntu-24.04 \
  --ssh-key "$SSH_KEY"
```

### 2. Boot it into rescue mode

Enable rescue mode and reboot the server.

```bash
hcloud server enable-rescue microos-template --ssh-key "$SSH_KEY"
hcloud server reboot microos-template
```

SSH into the rescue system once it is available.

### 3. Download the MicroOS QCOW2 image

On the rescue host:

```bash
apt-get update
apt-get install -y qemu-utils curl ca-certificates

cd /tmp

MICROOS_QCOW2="https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-ContainerHost-OpenStack-Cloud.qcow2"

curl -LO "$MICROOS_QCOW2"
curl -LO "$MICROOS_QCOW2.sha256"

sha256sum -c "$(basename "$MICROOS_QCOW2").sha256"
```

### 4. Write it to `/dev/sda`

Confirm the primary disk device before overwriting it.

```bash
lsblk
```

On Hetzner Cloud the main disk is usually `/dev/sda`, but verify first.

```bash
qemu-img convert -p -f qcow2 -O raw "$(basename "$MICROOS_QCOW2")" /dev/sda
sync
reboot
```

If `/dev/sda` is not the correct disk, use whatever device `lsblk` shows as the main system disk.

### 5. Configure SSH / first boot

After the VM reboots, verify MicroOS boots successfully and that SSH works.

```bash
ssh root@<server-ip> "cat /etc/os-release"
```

If needed, add your SSH key or create a simple first-boot configuration.

### 6. Create a Hetzner snapshot

When the VM is booted and usable, power it off and create a snapshot:

```bash
hcloud server poweroff microos-template

hcloud server create-image \
  microos-template \
  --type snapshot \
  --description "openSUSE MicroOS ContainerHost template"
```

Record the snapshot ID or name.

### 7. Use that snapshot ID as the image for masters/workers

In your real cluster creation config, set the image to the snapshot ID:

```bash
IMAGE_ID="your-snapshot-id"

hcloud server create \
  --name k3s-master-1 \
  --type cpx31 \
  --location nbg1 \
  --image "$IMAGE_ID" \
  --ssh-key "$SSH_KEY"
```

## Notes

- The `ContainerHost OpenStack Cloud` QCOW2 image is the correct file family for Hetzner/KVM in this workflow.
- The key step is converting and writing the image to the VM disk in rescue mode.
- Once the snapshot is created, use that snapshot consistently for all cluster nodes.

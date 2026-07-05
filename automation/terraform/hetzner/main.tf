resource "hcloud_ssh_key" "admin" {
  name       = "${var.cluster_name}-admin-key"
  public_key = file(var.ssh_public_key_path)
}

resource "hcloud_network" "cluster" {
  name     = "${var.cluster_name}-net"
  ip_range = var.network_cidr
}

resource "hcloud_network_subnet" "cluster" {
  network_id   = hcloud_network.cluster.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_cidr
}

resource "hcloud_firewall" "k3s_nodes" {
  name = "${var.cluster_name}-k3s-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.api_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = var.api_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = var.api_allowed_cidrs
  }
}

resource "hcloud_server" "control_planes" {
  count       = var.control_plane_count
  name        = format("%s-cp-%02d", var.cluster_name, count.index + 1)
  location    = var.location
  server_type = var.control_plane_type
  image       = var.image
  ssh_keys    = [hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  firewall_ids = [hcloud_firewall.k3s_nodes.id]

  lifecycle {
    ignore_changes = [image]
  }
}

resource "hcloud_server_network" "control_planes" {
  count      = var.control_plane_count
  server_id  = hcloud_server.control_planes[count.index].id
  network_id = hcloud_network.cluster.id
}

resource "hcloud_load_balancer" "k8s_api" {
  name               = "${var.cluster_name}-api-lb"
  load_balancer_type = "lb11"
  location           = var.location
}

resource "hcloud_load_balancer_network" "k8s_api" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  network_id       = hcloud_network.cluster.id
}

resource "hcloud_load_balancer_target" "control_planes" {
  count            = var.control_plane_count
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  server_id        = hcloud_server.control_planes[count.index].id
  use_private_ip   = true
}

resource "hcloud_load_balancer_service" "k8s_api" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "tcp"
    port     = 6443
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

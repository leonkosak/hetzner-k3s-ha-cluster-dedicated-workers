output "control_plane_public_ips" {
  value = {
    for s in hcloud_server.control_planes :
    s.name => s.ipv4_address
  }
}

output "control_plane_private_ips" {
  value = {
    for s in hcloud_server.control_planes :
    s.name => one([for n in hcloud_server_network.control_planes : n.ip if n.server_id == s.id])
  }
}

output "api_load_balancer_public_ipv4" {
  value = hcloud_load_balancer.k8s_api.ipv4
}

output "cluster_network" {
  value = {
    cidr        = hcloud_network.cluster.ip_range
    subnet_cidr = hcloud_network_subnet.cluster.ip_range
  }
}

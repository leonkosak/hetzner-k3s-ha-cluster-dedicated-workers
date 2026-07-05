variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "cluster_name" {
  type    = string
  default = "runtime"
}

variable "location" {
  type    = string
  default = "nbg1"
}

variable "network_zone" {
  type    = string
  default = "eu-central"
}

variable "control_plane_count" {
  type    = number
  default = 3
}

variable "control_plane_type" {
  type    = string
  default = "cpx31"
}

variable "image" {
  type    = string
  default = "microos-snapshot"
}

variable "network_cidr" {
  type    = string
  default = "10.80.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.80.10.0/24"
}

variable "ssh_public_key_path" {
  type = string
}

variable "api_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0", "::/0"]
}

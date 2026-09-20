variable "proxmox_endpoint" {
  description = "Proxmox API URL. Override with TF_VAR_proxmox_endpoint in .env when working remotely."
  type        = string
  default     = "https://10.69.10.2:8006/"
}

variable "proxmox_insecure" {
  description = "Set to true only if Proxmox uses a certificate your machine does not trust."
  type        = bool
  default     = false
}

variable "node_name" {
  description = "Proxmox node name."
  type        = string
  default     = "pve"
}

variable "vm_datastore_id" {
  description = "Datastore for VM disks and cloud-init drives."
  type        = string
  default     = "armoury-1"
}

variable "image_datastore_id" {
  description = "Datastore with the import content type, used to store cloud images."
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Network bridge for the VMs."
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Default gateway for the VMs."
  type        = string
  default     = "10.69.0.1"
}

variable "network_prefix_length" {
  description = "Prefix length of the VM network."
  type        = number
  default     = 16
}

variable "dns_servers" {
  description = "DNS servers for the VMs. Change this if your DNS is not on the gateway."
  type        = list(string)
  default     = ["10.69.10.13", "10.69.0.1"]
}

variable "ubuntu_image_release" {
  description = "Ubuntu 26.04 cloud image release date, for example 20260918. Set by scripts/set-image.sh."
  type        = string
  default     = ""
}

variable "ubuntu_image_sha256" {
  description = "SHA-256 of the Ubuntu cloud image. Set by scripts/set-image.sh."
  type        = string
  default     = ""
}

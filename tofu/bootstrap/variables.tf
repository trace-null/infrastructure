variable "proxmox_endpoint" {
  description = "Proxmox API URL. Replace the placeholder with your real address."
  type        = string
  default     = "https://10.69.10.1:8006/"
}

variable "proxmox_insecure" {
  description = "Set to true only if Proxmox uses a self-signed certificate."
  type        = bool
  default     = false
}

variable "proxmox_ssh_user" {
  description = "User for the SSH connection to the Proxmox node."
  type        = string
  default     = "root"
}

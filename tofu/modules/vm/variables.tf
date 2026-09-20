variable "name" {
  description = "VM name."
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID."
  type        = number
}

variable "node_name" {
  description = "Proxmox node that hosts the VM."
  type        = string
}

variable "datastore_id" {
  description = "Datastore for the VM disk and the cloud-init drive."
  type        = string
}

variable "template_vm_id" {
  description = "ID of a cloud-init template to clone. Leave null to import image_id instead."
  type        = number
  default     = null
}

variable "image_id" {
  description = "ID of an imported cloud image (content type import). Used when template_vm_id is null."
  type        = string
  default     = null
}

variable "bridge" {
  description = "Network bridge."
  type        = string
}

variable "cores" {
  description = "Number of vCPUs."
  type        = number
}

variable "memory_mb" {
  description = "Memory in MB."
  type        = number
}

variable "disk_gb" {
  description = "Disk size in GB. When cloning, this must be at least the size of the template disk."
  type        = number
}

variable "ip_address" {
  description = "Static IPv4 address, without a prefix length."
  type        = string
}

variable "prefix_length" {
  description = "Network prefix length, for example 16."
  type        = number
}

variable "gateway" {
  description = "IPv4 gateway."
  type        = string
}

variable "dns_servers" {
  description = "DNS servers."
  type        = list(string)
}

variable "username" {
  description = "Login user created by cloud-init."
  type        = string
}

variable "ssh_keys" {
  description = "Public SSH keys allowed to log in as the user."
  type        = list(string)
}

variable "tags" {
  description = "Proxmox tags."
  type        = list(string)
  default     = []
}

variable "description" {
  description = "VM description."
  type        = string
  default     = "Managed by OpenTofu."
}

variable "virtiofs_shares" {
  description = "Directory mappings shared into the VM with virtiofs. The mapping name is also the mount tag inside the guest."
  type = list(object({
    mapping   = string
    cache     = optional(string, "auto")
    direct_io = optional(bool, false)
  }))
  default = []
}

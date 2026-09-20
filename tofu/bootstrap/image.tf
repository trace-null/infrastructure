variable "image_source" {
  description = "Where VM disks come from: template (clone an existing cloud-init template) or download (import an Ubuntu cloud image)."
  type        = string
  default     = "template"

  validation {
    condition     = contains(["template", "download"], var.image_source)
    error_message = "image_source must be template or download."
  }
}

variable "template_vm_id" {
  description = "ID of the cloud-init template to clone when image_source is template."
  type        = number
  default     = 9000
}

locals {
  template_vm_id = var.image_source == "template" ? var.template_vm_id : null
  image_id       = one(proxmox_download_file.ubuntu[*].id)
}

# Ubuntu 26.04 LTS cloud image, downloaded by Proxmox itself and checked
# against a pinned SHA-256. Only used when image_source is download.
# Change the release with: just set-image <date>
#
# This needs the Sys.Modify privilege and a Proxmox node that can reach the
# internet. The legacy amd64 image is used because the VMs run with the
# x86-64-v2 CPU type. The amd64v3 image needs a v3 CPU type.
resource "proxmox_download_file" "ubuntu" {
  count = var.image_source == "download" ? 1 : 0

  node_name    = var.node_name
  datastore_id = var.image_datastore_id
  content_type = "import"

  file_name = "ubuntu-26.04-server-cloudimg-amd64-${var.ubuntu_image_release}.qcow2"
  url       = "https://cloud-images.ubuntu.com/releases/resolute/release-${var.ubuntu_image_release}/ubuntu-26.04-server-cloudimg-amd64.img"

  checksum           = var.ubuntu_image_sha256
  checksum_algorithm = "sha256"
  overwrite          = false
  upload_timeout     = 1800

  lifecycle {
    precondition {
      condition     = can(regex("^[0-9]{8}$", var.ubuntu_image_release)) && can(regex("^[0-9a-f]{64}$", var.ubuntu_image_sha256))
      error_message = "No image release is pinned. Run: just set-image <release-date> (for example 20260918)"
    }
  }
}

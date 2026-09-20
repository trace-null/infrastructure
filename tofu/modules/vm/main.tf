terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  description = var.description
  tags        = var.tags
  node_name   = var.node_name
  vm_id       = var.vm_id

  on_boot = true

  # Clone an existing template when one is given. Full clones stay independent
  # of the template, so the template can be replaced or deleted later.
  dynamic "clone" {
    for_each = var.template_vm_id == null ? [] : [var.template_vm_id]
    content {
      vm_id        = clone.value
      datastore_id = var.datastore_id
      full         = true
    }
  }

  # The guest agent stays off until Ansible has confirmed it runs in the
  # guest. A clone inherits the template's setting, so this is set explicitly.
  # Without a running agent Proxmox cannot shut the guest down cleanly, hence
  # stop_on_destroy.
  agent {
    enabled = false
  }
  stop_on_destroy = true

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    import_from  = var.template_vm_id == null ? var.image_id : null
    interface    = "scsi0"
    size         = var.disk_gb
    file_format  = "raw"
    discard      = "on"
    ssd          = true
  }

  initialization {
    datastore_id = var.datastore_id
    file_format  = "raw"

    ip_config {
      ipv4 {
        address = "${var.ip_address}/${var.prefix_length}"
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.username
      keys     = var.ssh_keys
    }
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # Cloud images use the serial console. This matches the template.
  serial_device {}

  vga {
    type = "serial0"
  }

  # Persistent data lives on host datasets, shared in with virtiofs. Inside
  # the guest the share is mounted by its mapping name, for example:
  #   mount -t virtiofs <mapping> /mnt/infra
  dynamic "virtiofs" {
    for_each = var.virtiofs_shares
    content {
      mapping   = virtiofs.value.mapping
      cache     = virtiofs.value.cache
      direct_io = virtiofs.value.direct_io
    }
  }

  lifecycle {
    precondition {
      condition     = length(var.ssh_keys) > 0
      error_message = "No SSH keys found. Add your public key to tofu/bootstrap/authorized_keys."
    }

    precondition {
      condition     = var.template_vm_id != null || var.image_id != null
      error_message = "Give the module a template_vm_id to clone or an image_id to import."
    }
  }
}

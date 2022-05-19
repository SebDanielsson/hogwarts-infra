terraform {
  backend "cloud" {
    organization = "hogwarts"

    workspaces {
      name = "prod-eu-central"
    }
  }

  required_providers {
    linode = {
      source = "linode/linode"
      version = "1.27.2"
    }

    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "3.15.0"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

provider "cloudflare" { 
  email   = var.cloudflare_email
  api_key = var.cloudflare_api_key
}

resource "linode_instance" "server1" {
  label = var.server1_label
  tags = [ "prod" ]
  image = var.server1_image
  region = var.server1_region
  type = var.server1_type
  authorized_keys = [ var.server1_authorized_keys ]
  root_pass = var.server1_root_pass
  backups_enabled = var.server1_backups
  watchdog_enabled = var.server1_watchdog
  swap_size = var.server1_swap

  provisioner "remote-exec" {
    inline = [
      # upgrade system
      "dnf -q -y upgrade",

      # install software
      "dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo",
      "dnf config-manager --add-repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo",
      "dnf -q -y install dnf-automatic cockpit-pcp docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-scan-plugin wireguard-tools bind restic tailscale git tmux",
      #"pip3 install linode-cli",
      "systemctl daemon-reload",
      "systemctl enable --now docker",
      "systemctl enable --now tailscaled",

      # misc config
      "hostnamectl set-hostname ${var.server1_hostname}",
      "timedatectl set-timezone Europe/Berlin",
      "sed -i 's/PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sed -i 's/PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config",

      # Add Tailscale login
      "tailscale up --authkey=${var.server1_tskey}",

      # .bashrc
      "echo -e '## Aliases\nalias ls='ls -ahlG'\ncdls() { cd '$@' && ls; }\nalias cd='cdls'\n\n# Restart linode1, simply running reboot from the OS doesn't bring up the Linode\nexport LINODE_TOKEN=${var.linode_selfrestart_token}\nalias reboot='linode-cli linodes reboot ${linode_instance.server1.id}'\n' >> .bashrc",

      # firewall config
      "firewall-cmd --permanent --service=http --add-port=80/udp",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=http",

      "firewall-cmd --permanent --service=https --add-port=443/udp",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=https",

      "firewall-cmd --permanent --new-service=etlegacy",
      "firewall-cmd --permanent --service=etlegacy --add-port=27960/udp",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=etlegacy",

      "firewall-cmd --permanent --new-service=minecraft",
      "firewall-cmd --permanent --service=minecraft --add-port=19132-19133/udp",
      "firewall-cmd --zone=FedoraServer --permanent --add-service=minecraft",

      "firewall-cmd --reload",

      //"sed -i 's/TARGET_DOMAIN=.*/TARGET_DOMAIN=${var.server1_hostname}/' /compose/traefik-cloudflare-companion/compose.yaml",
      //"for d in /compose/*/ ; do (cd $d && docker compose up -d); done",

      # complete
      "echo 'Please restart the server from the dashboard for all changes to take effect.'",
    ]

    connection {
      type = "ssh"
      user = "root"
      password = var.server1_root_pass
      host = linode_instance.server1.ip_address
    }
  }   
}

resource "cloudflare_record" "dns_ipv4_server1" {
  depends_on = [linode_instance.server1]
  zone_id = var.cloudflare_zone_id
  name    = var.server1_label
  value   = linode_instance.server1.ip_address
  type    = "A"
  ttl     = 1

  timeouts {
    create = "2m"
    update = "2m"
  }
}

resource "cloudflare_record" "dns_ipv6_server1" {
  depends_on = [linode_instance.server1]
  zone_id = var.cloudflare_zone_id
  name    = var.server1_label
  value   = trimsuffix(linode_instance.server1.ipv6, "/128")
  type    = "AAAA"
  ttl     = 1

  timeouts {
    create = "2m"
    update = "2m"
  }
}

### Variables ###

# Linode tokens
variable "linode_token" {
  description = "Linode API token"
  type = string
  sensitive = true
}

variable "linode_selfrestart_token" {
  description = "Linode self-restart token"
  type = string
  sensitive = true
}

# Cloudflare tokens
variable "cloudflare_email" {
  description = "Cloudflare account email"
  type = string
  sensitive = true
}

variable "cloudflare_api_key" {
  description = "Cloudflare API Key"
  type = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type = string
  sensitive = true
}

# Linode instance
variable "server1_label" {
  description = "Label for server1"
  type = string
}

variable "server1_hostname" {
  description = "Hostname for server1"
  type = string
}

variable "server1_root_pass" {
  description = "Password for the root user"
  type = string
  sensitive = true
}

variable "server1_authorized_keys" {
  description = "authorized_keys for server1"
  type = string
  sensitive = true
}

variable "server1_image" {
  description = "OS image for server1"
  type = string
  default = "linode/fedora36"
}

variable "server1_region" {
  description = "Region for server1"
  type = string
  default = "eu-central"
}

variable "server1_type" {
  description = "Instance type for server1"
  type = string
  default = "g6-standard-1"
}

variable "server1_swap" {
  description = "Swap size for server1"
  default = 1024
}

variable "server1_backups" {
  description = "Linode backups for server1"
  type = bool
  default = false
}

variable "server1_watchdog" {
  description = "Watchdog for server1"
  type = bool
  default = false
}

# Tailscale authkey
variable "server1_tskey" {
  description = "Tailscale authkey"
  type = string
  sensitive = true
}

# Restic restore
variable "server1_restic_repository" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  sensitive = true
}

variable "server1_restic_password" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  sensitive = true
}

variable "server1_restic_aws_access_key_id" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  sensitive = true
}

variable "server1_aws_secret_access_key" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  sensitive = true
}

variable "server1_snapshot" {
  description = "Restore snapshot with Docker volumes for server1"
  type = string
  default = "latest"
}

variable "server1_snapshot_target" {
  description = "Where to put restored files from snapshot1"
  type = string
  default = "/"
}

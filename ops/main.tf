terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.15.0"
    }
  }
}
variable "DO_TOKEN" {}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.DO_TOKEN
}

resource "digitalocean_vpc" "vpc" {
  name = "vpc"
  region = "sgp1"
  ip_range = "10.10.10.0/24"
}

data "digitalocean_certificate" "cert" {
  name = "cert"
}

locals {
  garak = 31154024
  bodhi = 31212382
  worker_count = 2

  subnet = "10.10.10.0/24"

  ssh_config = trimspace(
    <<EOT
      Port 22
      #AddressFamily any
      #ListenAddress 0.0.0.0
      #ListenAddress ::

      #LoginGraceTime 2m
      PermitRootLogin yes
      #StrictModes yes
      #MaxAuthTries 6
      #MaxSessions 10

      PasswordAuthentication no
      PrintMotd no
    EOT
  )
}

resource "digitalocean_droplet" "manager" {
  image = "docker-18-04"
  name = "manager"
  region = "sgp1"
  size = "s-1vcpu-1gb"
  vpc_uuid = digitalocean_vpc.vpc.id
  ssh_keys = [local.garak, local.bodhi]
  monitoring = true
  tags = ["swarm", "manager"]
  private_networking = true

  user_data = trimspace(
    <<EOT
    #!/bin/bash
    echo "
      ${local.ssh_config}
    " > /etc/sshd/config

    # local ip
    lip=$(hostname -I | awk '{print $3}')

    # init swarm
    docker swarm init --advertise-addr $lip

    ufw allow from ${local.subnet} to any port 2377
    ufw allow from ${local.subnet} to any port 7946
    ufw allow from ${local.subnet} to any port 4789

    ufw allow 80
    ufw allow 443

    systemctl restart sshd
    EOT
  )
}

resource "digitalocean_droplet" "worker" {
  image = "docker-18-04"
  name = "worker-${count.index}"
  region = "sgp1"
  size = "s-1vcpu-1gb"
  vpc_uuid = digitalocean_vpc.vpc.id
  ssh_keys = [local.garak, local.bodhi]
  monitoring = true
  tags = ["swarm", "worker", "worker-${count.index}"]
  private_networking = true
  count = local.worker_count
   user_data = trimspace(
    <<EOT
    #!/bin/bash

    ufw allow from 10.10.10.0/24 to any port 2377
    ufw allow from 10.10.10.0/24 to any port 7946
    ufw allow from 10.10.10.0/24 to any port 4789

    ufw allow 80
    ufw allow 443
    EOT
  )
}

resource "digitalocean_loadbalancer" "lb" {
  name   = "lb"
  region = "sgp1"

  vpc_uuid = digitalocean_vpc.vpc.id

  forwarding_rule {
    entry_port     = 443
    entry_protocol = "https"

    target_port     = 80
    target_protocol = "http"

    certificate_name = data.digitalocean_certificate.cert.name
  }

  // shouldn't be necessary, but I get errors
  // if I don't include it
  // "422: some of the specified target droplets don't belong to the same VPC as the Load Balancer"
  depends_on = [
    digitalocean_droplet.manager,
    digitalocean_droplet.worker,
    digitalocean_vpc.vpc
  ]

  droplet_ids = concat(
    [ digitalocean_droplet.manager.id ]
    ,
    digitalocean_droplet.worker[*].id
  )  
}

resource "digitalocean_container_registry" "registry" {
  name = "${terraform.workspace}-swarm-test"
  subscription_tier_slug = "basic"
}

resource "digitalocean_container_registry_docker_credentials" "registry" {
  registry_name = digitalocean_container_registry.registry.name
}

resource "digitalocean_project" "project" {
  name        = "${terraform.workspace}-swarm-test-odin"
  description = "Testing out Docker swarm"
  purpose     = "Web Application"
  environment = "development"
}

resource "digitalocean_project_resources" "resources" {
    project = digitalocean_project.project.id
    resources = concat(
      [digitalocean_loadbalancer.lb.urn, digitalocean_droplet.manager.urn],
      digitalocean_droplet.worker[*].urn
    )
}

resource "digitalocean_firewall" "firewall" {
  name = "only-22-80-and-443"

  # depends_on = [
  #   digitalocean_droplet.manager
  #   , digitalocean_droplet.worker
  # ]

  droplet_ids = concat(
    [ digitalocean_droplet.manager.id ]
    ,
    digitalocean_droplet.worker[*].id
  )

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol = "tcp"
    port_range = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

output registry_url {
  value = digitalocean_container_registry.registry.endpoint
}

output registry_auth {
  value = digitalocean_container_registry_docker_credentials.registry.docker_credentials
  sensitive = true
}

output manager_ip {
  value = digitalocean_droplet.manager.ipv4_address
}

output "worker_ips" {
  value = digitalocean_droplet.worker[*].ipv4_address
}


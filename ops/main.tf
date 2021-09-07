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

# resource "digitalocean_domain" "domain" {
#   name = "harth.app"
# }
# resource "digitalocean_certificate" "cert" {
#   name = "cert"
#   type = "lets_encrypt"
#   domains = [digitalocean_domain.domain.id]

#   lifecycle {
#     create_before_destroy = true
#   }
# }

locals {
  garak = 31154024
  bodhi = 31212382
  worker_count = 2
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

    # local ip
    lip=$(hostname -I | awk '{print $3}')

    # init swarm
    docker swarm init --advertise-addr $lip

    ufw allow 2377
    ufw allow 7946
    ufw allow 4789
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

    ufw allow 2377
    ufw allow 7946
    ufw allow 4789
    EOT
  )
}

# resource "digitalocean_loadbalancer" "lb" {
#   name   = "lb"
#   region = "sgp1"

#   vpc_uuid = digitalocean_vpc.vpc.id

#   forwarding_rule {
#     entry_port     = 22
#     entry_protocol = "tcp"

#     target_port     = 22
#     target_protocol = "tcp"

#     certificate_name = digitalocean_certificate.cert.name
#   }

#   droplet_ids = [
#     digitalocean_droplet.manager.id
#   ]
# }

resource "digitalocean_container_registry" "registry" {
  name = "${terraform.workspace}-swarm-test"
  subscription_tier_slug = "starter"
}

resource "digitalocean_container_registry_docker_credentials" "registry" {
  registry_name = digitalocean_container_registry.registry.name
}

# provider "docker" {
#   host = "ssh://root@${digitalocean_droplet.manager.ipv4_address}"

#   registry_auth {
#     address             = digitalocean_container_registry.registry.server_url
#     config_file_content = digitalocean_container_registry_docker_credentials.registry.docker_credentials
#   }
# }

# resource "docker_image" "api" {
#   name = "api"
#   build {
#     path = "./server"
#     # image = "${digitalocean_container_registry.registry.server_url}/api"
#   }
# }

# resource "docker_service" "api" {
#   name = "api"

#   task_spec {
#     container_spec {
#       image = docker_image.api.repo_digest
#     }
#   }

#   endpoint_spec {
#     ports {
#       target_port = "8080"
#     }
#   }

#   mode {
#     replicated {
#       replicas = 2
#     }
#   }
# }

resource "digitalocean_project" "project" {
  name        = "${terraform.workspace}-swarm-test-odin"
  description = "Testing out Docker swarm"
  purpose     = "Web Application"
  environment = "development"
}

resource "digitalocean_project_resources" "resources" {
    project = digitalocean_project.project.id
    resources = concat(
      [digitalocean_droplet.manager.urn],
      digitalocean_droplet.worker[*].urn
    )
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


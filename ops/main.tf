terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Set the variable value in *.tfvars file
# or using -var="do_token=..." CLI option
variable "do_token" {}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_project" "project" {
  name        = "${terraform.workspace}-swarm-test-odin"
  description = "Testing out Docker swarm"
  purpose     = "Web Application"
  environment = "development"
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
  worker_count = 2
}

resource "digitalocean_droplet" "manager" {
  image = "docker-20-04"
  name = "manager"
  region = "sgp1"
  size = "s-1vcpu-1gb"
  vpc_uuid = digitalocean_vpc.vpc.id
  ssh_keys = [local.garak]
  monitoring = true
  tags = ["swarm", "manager"]
  private_networking = true
  user_data = file("${path.module}/manager-init.sh")
}

data "external" "join_command" {
  depends_on = [
    digitalocean_droplet.manager
  ]
  program = [ 
    "/usr/bin/node", "./run.js", "get-join-token-command"
  ]
  working_dir = "../"
}

resource "digitalocean_droplet" "worker" {
  image = "docker-20-04"
  name = "worker-${count.index}"
  region = "sgp1"
  size = "s-1vcpu-1gb"
  vpc_uuid = digitalocean_vpc.vpc.id
  ssh_keys = [local.garak]
  monitoring = true
  tags = ["swarm", "worker", "worker-${count.index}"]
  private_networking = true
  count = local.worker_count
  user_data = data.external.join_command.result.command
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
  name = "${terraform.workspace}-swarm-test-odin"
  subscription_tier_slug = "starter"
}

# resource "digitalocean_project_resources" "resources" {
#     project = digitalocean_project.project.id
#     resources = concat(
#       [digitalocean_droplet.manager.urn],
#       digitalocean_droplet.worker[*].urn
#     )
# }
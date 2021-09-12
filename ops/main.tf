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
variable "SSH_PORT" {}

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
	manager_pairs = 2
	
	# do not edit, read only
	manager_count = local.manager_pairs * 2

	ssh_port = var.SSH_PORT

	managerToken = data.external.manager-join-token.result.token
	workerToken = data.external.worker-join-token.result.token

	token = {
		manager = data.external.manager-join-token.result.token
		worker = data.external.worker-join-token.result.token
	}

	leaderIP = digitalocean_droplet.leader.ipv4_address_private
}

resource "digitalocean_droplet" "leader" {
	image = "docker-18-04"
	name = "leader"
	region = "sgp1"
	size = "s-1vcpu-1gb"
	vpc_uuid = digitalocean_vpc.vpc.id
	ssh_keys = [local.garak, local.bodhi]
	monitoring = true
	tags = ["swarm", "manager", "leader"]
	private_networking = true

	user_data = trimspace(
		<<EOT
		#!/bin/bash
		set -e

		cat <<- SSHCONFIG > /etc/ssh/sshd_config
			Port ${local.ssh_port}
			PermitRootLogin yes
			#StrictModes yes
			#MaxAuthTries 6
			#MaxSessions 10
			#PubkeyAuthentication yes

			ChallengeResponseAuthentication no
			UsePAM yes

			X11Forwarding yes
			PrintMotd no

			# override default of no subsystems
			Subsystem       sftp    /usr/lib/openssh/sftp-server			
		SSHCONFIG

		ufw allow ${local.ssh_port}
		systemctl restart sshd

		# local ip
		lip=$(hostname -I | awk '{print $3}')

		# init swarm
		docker swarm init --advertise-addr $lip

		ufw allow from 10.10.10.0/24 to any port 2377
		ufw allow from 10.10.10.0/24 to any port 7946
		ufw allow from 10.10.10.0/24 to any port 4789

		managerToken=$(docker swarm join-token manager -q)
		workerToken=$(docker swarm join-token worker -q)

		managerToken='{ "token":''"'$managerToken'"''}'
		workerToken='{ "token":''"'$workerToken'"''}'

		echo $managerToken > /root/manager-token.json
		echo $workerToken > /root/worker-token.json
		
		# trigger release v1
		ufw allow 80
		ufw allow 443
		EOT
	)
}

resource "digitalocean_droplet" "manager" {
	image = "docker-18-04"
	name = "manager-${count.index}"
	region = "sgp1"
	size = "s-1vcpu-1gb"
	vpc_uuid = digitalocean_vpc.vpc.id
	ssh_keys = [local.garak, local.bodhi]
	monitoring = true
	tags = ["swarm", "manager"]
	private_networking = true

	count = local.manager_count

	user_data = trimspace(
		<<EOT
		#!/bin/bash
		set -e

		cat <<- SSHCONFIG > /etc/ssh/sshd_config
			Port ${local.ssh_port}
			PermitRootLogin yes
			#StrictModes yes
			#MaxAuthTries 6
			#MaxSessions 10
			#PubkeyAuthentication yes

			ChallengeResponseAuthentication no
			UsePAM yes

			X11Forwarding yes
			PrintMotd no

			# override default of no subsystems
			Subsystem       sftp    /usr/lib/openssh/sftp-server			
		SSHCONFIG

		ufw allow ${local.ssh_port}
		systemctl restart sshd

		ufw allow from 10.10.10.0/24 to any port 2377
		ufw allow from 10.10.10.0/24 to any port 7946
		ufw allow from 10.10.10.0/24 to any port 4789
		
		ufw allow 80
		ufw allow 443
		EOT
	)

}

locals {
	config = {
		worker = [
			for d in digitalocean_droplet.worker[*]: 
				{ 
					user_data = d.user_data
					size = d.size
					ssh_keys = d.ssh_keys
					region = d.region
					image = d.image
					name = d.name
					type = "worker"
				}
		]

		leader = [
			for d in digitalocean_droplet.leader[*]: 
				{ 
					user_data = d.user_data
					size = d.size
					ssh_keys = d.ssh_keys
					region = d.region
					image = d.image
					name = d.name
					type = "leader"
				}
		]

		manager = [
			for d in digitalocean_droplet.manager[*]: 
				{ 
					user_data = d.user_data
					size = d.size
					ssh_keys = d.ssh_keys
					region = d.region
					image = d.image
					name = d.name
					type = "manager"
				}
		]
	}
	hashes = {
		manager = [for x in local.config.manager[*]: sha256( jsonencode(x) ) ]
		worker = [for x in local.config.worker[*]: sha256( jsonencode(x) ) ]
		leader = [for x in local.config.leader[*]: sha256( jsonencode(x) ) ]
	}
	complete = {
		manager = [for i, d in digitalocean_droplet.manager[*]: merge(d, local.config.manager[i])]
		worker = [for i, d in digitalocean_droplet.worker[*]: merge(d, local.config.worker[i])]
		leader = [for i, d in digitalocean_droplet.leader[*]: merge(d, local.config.leader[i])]
	}
}


resource "null_resource" "cloud-init-complete" {

	for_each = zipmap( 
		concat( local.hashes.manager[*], local.hashes.worker[*], local.hashes.leader[*] )
		, concat( local.complete.manager[*], local.complete.worker[*], local.complete.leader[*] )
	)

	provisioner "remote-exec" {
		connection {
			type = "ssh"
			user = "root"
			host = each.value.ipv4_address
			port = local.ssh_port
			private_key = file(pathexpand("~/.ssh/id_rsa"))
		}
		# || true because sometimes cloud init fails 
		# for reasons that don't matter
		# e.g. do-agent failing
		# the main thing is we want to know the process is
		# complete, even if it failed
		# if it failed, we'll discover soon after
		# because a swarm will be invalid etc
		inline = ["cloud-init status --wait || true"]
	}
}

data "external" "manager-join-token" {

	depends_on = [null_resource.cloud-init-complete]

	program = [
		"ssh"
		, "root@${digitalocean_droplet.leader.ipv4_address}"
		, "-o", "UserKnownHostsFile=/dev/null"
		, "-o", "CheckHostIP no"
		, "-o", "StrictHostKeychecking no"
		, "-p", local.ssh_port
		, "cat manager-token.json"
	]
}

data "external" "worker-join-token" {

	depends_on = [null_resource.cloud-init-complete]

	program = [
		"ssh"
		, "root@${digitalocean_droplet.leader.ipv4_address}"
		, "-o", "UserKnownHostsFile=/dev/null"
		, "-o", "CheckHostIP no"
		, "-o", "StrictHostKeychecking no"
		, "-p", local.ssh_port
		, "cat worker-token.json"
	]
}

resource "null_resource" "swarm-membership" {
	triggers = {
		ssh_port = local.ssh_port
		ipv4_address = each.value.ipv4_address
		name = each.value.name
		leader_ip = digitalocean_droplet.leader.ipv4_address
	}
	
	for_each = zipmap( 
		concat( local.hashes.manager, local.hashes.worker )
		, concat( local.complete.manager, local.complete.worker )
	)

	provisioner "remote-exec" {
		connection {
			type = "ssh"
			user = "root"
			host = each.value.ipv4_address
			port = local.ssh_port
			private_key = file(pathexpand("~/.ssh/id_rsa"))
		}
		
		inline = [
			"docker swarm join --token ${local.token[each.value.type]} ${local.leaderIP}:2377"
		]
	}

	provisioner "remote-exec" {
		# one of the worst aspects of tf
		# can't access local.ssh_port in destroy provisioner
		when = destroy
		on_failure = continue
		connection {
			type = "ssh"
			user = "root"
			host = self.triggers.leader_ip
			port = self.triggers.ssh_port
			private_key = file(pathexpand("~/.ssh/id_rsa"))
		}

		
		inline = [
			"docker node update --availability drain ${self.triggers.name}",
			"docker node demote ${self.triggers.name}",
			"docker node rm ${self.triggers.name} --force"
		]
	}
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
		set -e

		cat <<- SSHCONFIG > /etc/ssh/sshd_config
			Port ${local.ssh_port}
			PermitRootLogin yes
			#StrictModes yes
			#MaxAuthTries 6
			#MaxSessions 10
			#PubkeyAuthentication yes

			ChallengeResponseAuthentication no
			UsePAM yes

			X11Forwarding yes
			PrintMotd no

			# override default of no subsystems
			Subsystem       sftp    /usr/lib/openssh/sftp-server			
		SSHCONFIG

		ufw allow ${local.ssh_port}
		systemctl restart sshd

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
		digitalocean_droplet.manager[*].id
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
			[digitalocean_loadbalancer.lb.urn],
			digitalocean_droplet.leader[*].urn,
			digitalocean_droplet.manager[*].urn,
			digitalocean_droplet.worker[*].urn
		)
}

resource "digitalocean_firewall" "firewall" {
	name = "only-22-80-and-443"

	droplet_ids = concat(
		digitalocean_droplet.manager[*].id
		,
		digitalocean_droplet.worker[*].id
		,
		digitalocean_droplet.leader[*].id
	)

	inbound_rule {
		protocol         = "tcp"
		port_range       = "22"
		source_addresses = ["0.0.0.0/0", "::/0"]
	}

	inbound_rule {
		protocol         = "tcp"
		port_range       = "${local.ssh_port}"
		source_addresses = ["0.0.0.0/0", "::/0"]
	}

	inbound_rule {
		protocol         = "tcp"
		port_range       = "443"
		source_addresses = ["0.0.0.0/0", "::/0"]
	}

	inbound_rule {
		protocol = "tcp"
		port_range = 2377
		source_addresses = ["10.10.10.0/24"]
		source_droplet_ids = concat(
			digitalocean_droplet.manager[*].id
			,
			digitalocean_droplet.worker[*].id
			,
			digitalocean_droplet.leader[*].id
		)
	}
	inbound_rule {
		protocol = "tcp"
		port_range = 7946
		source_addresses = ["10.10.10.0/24"]
		source_droplet_ids = concat(
			digitalocean_droplet.manager[*].id
			,
			digitalocean_droplet.worker[*].id
			,
			digitalocean_droplet.leader[*].id
		)
	}
	inbound_rule {
		protocol = "tcp"
		port_range = 4789
		source_addresses = ["10.10.10.0/24"]
		source_droplet_ids = concat(
			digitalocean_droplet.manager[*].id
			,
			digitalocean_droplet.worker[*].id
			,
			digitalocean_droplet.leader[*].id
		)
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

output leader_ip {
	value = digitalocean_droplet.leader.ipv4_address
}

output manager_ips {
	value = digitalocean_droplet.manager[*].ipv4_address
}

output worker_ips {
	value = digitalocean_droplet.worker[*].ipv4_address
}

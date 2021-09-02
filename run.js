#! /usr/bin/node

import { $, argv } from 'zx'
let ssh = (ip, command) => $`ssh root@${ip} -q -o "CheckHostIP no" -o "StrictHostKeychecking no" -o "UserKnownHostsFile=/dev/null" ${command}`

async function getJoinTokenCommand(){
	$.verbose = false
	let x 
	
	x = await $`doctl compute droplet list --tag-name swarm --tag-name manager --format PublicIPv4,PrivateIPv4 --no-header`
	let [publicIP, privateIP] = x.stdout.trim().split(/\s+/)
	
	await ssh(publicIP, "cloud-init status --wait")
	x = await ssh(publicIP, "docker swarm join-token worker -q")
	x = x.stdout.trim()
	
	x = `docker swarm join --token ${x} ${privateIP}:2377`
	x = '#!/bin/bash\n' + x
	x = { command: x }
	
	console.log(JSON.stringify(x))
}

let subcommand = argv._.shift()

let commands = {
	'get-join-token-command': getJoinTokenCommand
}

if( subcommand && commands[subcommand] ) {
	commands[subcommand](argv, argv._)
	.then( () => process.exit(0), err => {
		throw e
	} )
}

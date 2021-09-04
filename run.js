#! /usr/bin/node

import { $, argv, fs } from 'zx'

let retry = async ({ count, delay=5000 }, f) => {
	for(let i = 0; i < count; i++){
		try {
			return await f()
		} catch (e) {
			await new Promise( Y => setTimeout(Y, delay))
		}
	}
}
let ssh = (ip, command) => 
	retry({ count: 100 }, () =>
		$`ssh root@${ip} -q -o "CheckHostIP no" -o "StrictHostKeychecking no" -o "UserKnownHostsFile=/dev/null" ${command};`
	)

async function up(){
	let prefix = `export DOCKER_CONFIG=./ops/docker-config.json`

}

async function getJoinTokenCommand(){
	$.verbose = false
	let x 
	
	x = await $`doctl compute droplet list --tag-name swarm --tag-name manager --format PublicIPv4,PrivateIPv4 --no-header`
	let [publicIP, privateIP] = x.stdout.trim().split(/\s+/)
	m
	await ssh(publicIP, "cloud-init status --wait")
	x = await ssh(publicIP, "docker swarm join-token worker -q")
	x = x.stdout.trim()
	
	x = `docker swarm join --token ${x} ${privateIP}:2377`
	x = '#!/bin/bash\n' + x
	x = { command: x }
	await fs.mkdir('./output').catch( () => {} )
	await fs.writeFile('./output/getJoinTokenCommand.json', JSON.stringify(x))
	console.log(JSON.stringify(x))
}

let subcommand = argv._.shift()

let commands = {
	'get-join-token-command': getJoinTokenCommand
}

if( subcommand && commands[subcommand] ) {
	commands[subcommand](argv, argv._)
	.then( () => process.exit(0), async err => {
		await fs.writeFile('./output/error.json', JSON.stringify({ message: err.message, stack: err.stack }))
		throw err
	} )
}

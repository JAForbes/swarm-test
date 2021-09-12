#! /usr/bin/node

import { $, argv, fs, sleep } from 'zx'

let retry = async ({ count, delay=5000 }, f, evaluator=() => false) => {
	for(let i = 0; i < count; i++){
		try {

			return await f()
		} catch (e) {
			let done = await evaluator(e)
			if( done ) return e
			await new Promise( Y => setTimeout(Y, delay))
		}
	}
}

let ssh = (ip, command, ...args) => 
	retry(
		{ count: 10, delay: 30000 }
		, () =>
			$`ssh root@${ip} -p $SSH_PORT -o "CheckHostIP no" -o "StrictHostKeychecking no" -o "UserKnownHostsFile=/dev/null" ${command};`
		, ...args
	)

async function verifyCloudInit(ip){
	await ssh(ip, `cloud-init status --wait`, x => {
		x= x+''
		x = x.trim()
		x= x.split('\n')
		x= x.slice(-1)[0]

		if( x == 'status: error' ) {
			return true
		}
	})
	{
		let y
		y= await ssh(ip, `cat /run/cloud-init/status.json`)
		y= JSON.parse(y.stdout)	
		
		if( y.v1['modules-final'].errors.find( x => x.includes('scripts-user') )) {
			throw new Error('Cloud init failed')
		}
	}
}

async function useConnection({ ip }, f) {
	await $`touch ~/.ssh/known_hosts`
	await $`ssh-keygen -R ${ip}`
	await retry({ count: 5, delay: 30000 }
		, () => $`ssh-keyscan -p $SSH_PORT -H ${ip} >> ~/.ssh/known_hosts`
	)

	try {
		return await f()
	} finally {
		await $`ssh-keygen -R ${ip}`
	}
}

async function joinSwarm(type, ips){
	let x = ips
	let cmd = await getJoinTokenCommand(type)
	
	x= x.map( 
		x => ssh(x, cmd, x => {
			if ( (x+'').includes('The attempt to join the swarm will continue in the background.') ) {
				return true
			} else if ( (x+'').includes('This node is already part of a swarm.') ) {
				return true
			}
		}) 
	)
	await Promise.all(x)
}

async function useTunnel({ timeout=5*60*1000, ip }, f){
	try {

		await $`fuser -k 2377/tcp`.catch( () => {})
	
		// do not await, run in background
		retry({ count: 5, delay: 20000 }, () => 
			$`ssh -p $SSH_PORT -NL localhost:2377:/var/run/docker.sock root@${ip}`
		)
		
		// check the tunnel is running
		await Promise.race([
			sleep(timeout).then( () => { throw Error('Netstat Timeout') })
			, $`until netstat -an | grep 2377; do sleep 100; done;`
		])

		return await f()
	} finally {
		await $`fuser -k 2377/tcp`.catch( () => {})
	}
}

async function oncreate(){
	let x
	x= await $`terraform -chdir=ops output -json`
	x= JSON.parse(x.stdout)

	let ip = x.manager_ip.value
	await useConnection({ ip }, async () => {
		
		await verifyCloudInit(ip)

		await useTunnel({ ip }, async () => {
			await joinSwarm(x.worker_ips.value)
		})
	})
}

async function onbeforeremove(){
	// let x
	// x= await $`terraform -chdir=ops output -json`
	// x= JSON.parse(x.stdout)
	// await $`ssh-keygen -R ${x.manager_ip.value}`
}

async function getJoinTokenCommand(type){
	let x 
	
	x = await $`doctl compute droplet list --tag-name swarm --tag-name manager --format PublicIPv4,PrivateIPv4 --no-header`
	let [publicIP, privateIP] = x.stdout.trim().split(/\s+/)

	x = await ssh(publicIP, `docker swarm join-token ${type} -q`)
	x = x.stdout.trim()
	
 	return `docker swarm join --token ${x} ${privateIP}:2377`
}

async function dockerStuff(){
	await $`rm -fr  ~/.docker`
	await $`docker-compose build`
	await $`docker login -u $DO_TOKEN -p $DO_TOKEN registry.digitalocean.com`
	await $`docker-compose push`
	await $`export DOCKER_HOST='localhost:2377'; docker stack deploy --compose-file docker-compose.yml swarm_test --with-registry-auth`
}

async function react(){
	let xs = await fs.readFile('./output/events.jsonstream', 'utf8')
	xs= xs.toString()
	xs= xs.trim()
	xs= xs.split('\n') 
	xs= xs.map( JSON.parse )
	
	let idx = {}
	for(let event of xs){
		idx[event.eventName] = 
		idx[event.eventName] || []

		idx[event.eventName].push(event)
		console.log(event)
	}

	let output = await $`terraform -chdir=ops output -json`
	output = JSON.parse(output)

	// if( idx['leader-created'] ) {
	// 	await oncreate()
	// 	return null
	// }

	// if (idx['worker-created']) {
	// 	let ips = []
		
	// 	for(let event of idx['worker-created']){
	// 		ips.push(output.worker_ips[event.count])
	// 	}

	// 	await joinSwarm('worker', ips)
	// }

	// if(idx['manager-created']) {

	// }

	console.log(idx)
	console.log(output)
}

async function event(data, eventName){
	let x
	x = { ...data }
	delete x._
	x= { eventName, ...x }
	x= JSON.stringify(x)
	x = `${x}\n`
	fs.appendFileSync('./output/events.jsonstream', x)
}

let subcommand = argv._.shift()

let commands = {
	'get-join-token-command': getJoinTokenCommand
	, oncreate
	, onbeforeremove
	, event
	, react
}

if(!subcommand || !(subcommand in commands)) {
	console.error(Object.keys(commands).join('\n'))
	process.exitCode = 1
} else if( subcommand && commands[subcommand] ) {
	commands[subcommand](argv, ...argv._)
	.then( () => process.exit(0), async err => {
		await $`mkdir -p ./output`
		await fs.writeFile('./output/error.json', JSON.stringify({ message: err.message, stack: err.stack }))
		throw err
	} )
}

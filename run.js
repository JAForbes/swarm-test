#! /usr/bin/node

import { $, argv, fs, sleep } from 'zx'

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
	retry({ count: 10, delay: 30000 }, () =>
		$`ssh root@${ip} -o "CheckHostIP no" -o "StrictHostKeychecking no" -o "UserKnownHostsFile=/dev/null" ${command};`
	)

let ignoreResolve = promise => new Promise(function(Y,N){
	return promise.catch(N)
})

async function oncreate(){
	try {
		let x
		x= await $`terraform -chdir=ops output -json`
		x= JSON.parse(x.stdout)

		await $`touch ~/.ssh/known_hosts`
		await $`ssh-keygen -R ${x.manager_ip.value}`
		await retry({ count: 5, delay: 30000 }
			, () => $`ssh-keyscan -H ${x.manager_ip.value} >> ~/.ssh/known_hosts`
		)

		await $`fuser -k 2377/tcp`.catch( () => {})

		// do not await, run in background
		retry({ count: 5, delay: 20000 }, () => 
			$`ssh -NL localhost:2377:/var/run/docker.sock root@${x.manager_ip.value}`
		)
		
		// check the tunnel is running
		await Promise.race([
			sleep(5*60*1000).then( () => { throw Error('Netstat Timeout') })
			, $`until netstat -an | grep 2377; do sleep 100; done;`
		])
		
		await ssh(x.manager_ip.value, `cloud-init status --wait`)
		
		let restore = x; {
			let cmd = await getJoinTokenCommand()
			
			x= x.worker_ips.value.map( x => ssh(x, cmd) )
			x= await Promise.all(x)
			x = restore;
		}
	
		await $`mkdir -p ./ops/.docker`
		await $`rm -fr ./ops/.docker/**`
		await $`terraform -chdir=ops output -raw registry_auth > $(pwd)/ops/.docker/config.json`
	
	
		await $`mkdir -p ./output`
		await $`rm -fr ./output/**`
		await $`echo "export DOCKER_CONFIG=$(pwd)/ops/.docker" >> ./output/exports.sh`
		await $`echo "export DOCKER_HOST='localhost:2377'" >> ./output/exports.sh`
		await $`echo "export REGISTRY=${x.registry_url.value}" >> ./output/exports.sh`
	
		await $`rm -fr  ~/.docker`
		$.prefix = `source ./output/exports.sh;`
		await $`docker-compose build`
		await $`docker login -u $DO_TOKEN -p $DO_TOKEN registry.digitalocean.com`
		await $`docker-compose push`
		await $`docker stack deploy --compose-file docker-compose.yml swarm_test --with-registry-auth`
	} catch (e) {
		console.error(e)
		throw e
	} finally {
		await $`fuser -k 2377/tcp`.catch( () => {})
	}
	

}

async function onbeforeremove(){
	let x;
	x= await $`terraform -chdir=ops output -json`
	x= JSON.parse(x.stdout)
	// await $`docker context use default`
	// await $`docker context rm remote`.catch( () => {})
	await $`ssh-keygen -R ${x.manager_ip.value}`
}

async function getJoinTokenCommand(){
	let x 
	
	x = await $`doctl compute droplet list --tag-name swarm --tag-name manager --format PublicIPv4,PrivateIPv4 --no-header`
	let [publicIP, privateIP] = x.stdout.trim().split(/\s+/)

	await ssh(publicIP, "cloud-init status --wait")
	x = await ssh(publicIP, "docker swarm join-token worker -q")
	x = x.stdout.trim()
	
 	return `docker swarm join --token ${x} ${privateIP}:2377`
}

let subcommand = argv._.shift()

let commands = {
	'get-join-token-command': getJoinTokenCommand
	, oncreate
	, onbeforeremove
}

if(!subcommand || !(subcommand in commands)) {
	console.error(Object.keys(commands).join('\n'))
	process.exitCode = 1
} else if( subcommand && commands[subcommand] ) {
	commands[subcommand](argv, argv._)
	.then( () => process.exit(0), async err => {
		await $`mkdir -p ./output`
		await fs.writeFile('./output/error.json', JSON.stringify({ message: err.message, stack: err.stack }))
		throw err
	} )
}

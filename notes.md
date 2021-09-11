End to end worked with 2222.  Just cleaning up a bit, I think I don't need `./output/exports.sh` anymore as the only variable needed is `DOCKER_HOST` and it is only used for the `stack` call.

I was just thinking too, even if I have n managers.  The ideal way to deploy it is to have a single leader at infra time, and then add managers and workers to that leader's swarm.  So the logic is not too different.

I'll simply treat `manager[0]` is the leader and `manager[n+1]` as joiners.  All my initial propagation commands can rely on that leader existing.  Subsequent deployments will fail if the `manager[0]` is down, but the existing app will continue to work as the other managers will handle the load.

I'm just thinking out loud here. 

Is the initial deployment and subsequent deployments necessarily different?

If I run apply, and there's no infra change, my run script will run as if its the first time, which isn't good.  So I can have this script instead run as a provisioner in terraform to ensure that only runs oncreate.

If I am simply deploying images though, I'll want that to happen everytime an app changes.

So maybe I have an app resource in terraform, it hashes the app source, and if it changes it makes an image, pushes it to the registry.

If there is a new app, there is a new resource, and that works fine.

So the separation is joining/creating swarms and managing services/images.  If I separate them, I can do everything with `apply`.

I think that's the next step.  I'll make an app resource.

The other thing to check is, can I go back to managing images and the registry in terraform by using the official docker provider?  I'm not doing anything too special.  The only interesting thing is the ssh tunnel, but I assume the terraform provider would have retries internally anyway.  Who knows.  I could still manage the tunnel in terraform if not.

---

It was ufw, omg.  So obvious. 

I'll now try an end to end with all infra ( e.g. + DO firewall, + VPC, + ufw ) on port 2222

And then I'll use the randomly allocated port

---

I think it didn't work because I was using an already allocated port.  Maybe random ports aren't a good idea.  Or at least, being unsophisticated about it.

---

I'm thinking how I can optimize caching of application source.

Maybe each repo pushes its own image to the private registry?  But I kind of like the idea of the app in question having no idea about any of that, and instead the infra repo pulls the repo down, and builds the image here.

It is a trade off.  Ultimately an application repository has the best understanding of what its own requirements are.  But that kind of config changes so infrequently.

It would be annoying to have to pull every repo every time with zero caching.  But git sub modules doesn't sound too attractive either.

Maybe there is a mirror server, every time there is a git update on any of the target repos, the mirror server pulls down the code.  And all deployments happen on that persistent build server.

The deploy repo simply ssh's in, and runs whatever commands we are doing here.

Or... the deploy repo just commits changes from other apps and it is stored just like any other source control.  Then it can't be public, but it is so much simpler.

Not sure.

Might just do a shallow clone and hope for the best.  Or profile fetching tarballs.

Back to ports!

---

I have no idea why, but generating the SSH config isn't working the moment I change the port from 22.  I might pair down the infra a bit and see if I can get basic thing going.  

But just had a thought, it is probably super obvious but it never occurred to me.

I could have a deployment repo.  This repo would basically compile images for all the apps.  And push the images up to the swarm, and manage ports and stuff like that centrally.

When a merge request occurs in a given app, it could simply invoke a github action on the deploy repo.

That way, only 1 repo needs all this config, and env, and if we hire developers we can contract out and not worry about developers with full repo access having access to infrastructure.

I am a big fan of monorepos.  But for resource sharing on a cluster, the benefits superceded the benefits of a monorepo.

So I may convert this repo into an an actual production thing.

Even better, the infra repo could be open source without exposing secrets to the world.  E.g. random port allocation would stop an on looker from knowing what the port to SSH into the swarm is.  Making targeted attacks that much more annoying and easier to block.

I was thinking before I'd use this as an experimental place and then copy the config into each product.  But having it all here makes it seem feasible to build out the real thing without too much pain.  I can use alternative domains, get production up for every app and then switch the real apps over when I am convinced it is stable.

So that's my new target goal I think.

But it also means I need to harden security further.

---

Refactors work.  And custom SSH config working from cloud-init.  Trying hardcoded port 23 and if that works I'll randomize it with the terraform random data provider.

---


Refactoring a bit now.  Just putting stuff into functions first.  But it'd be great if all the setup teardown stuff was guaranteed to tear down.

Maybe...

```js
await useDockerTunnel( x => {

})
```

And it can use finally / exit listeners.  Maybe I'll try prexit again.

Be cool if prefix could be function aware...

---

I'm going to commit the current garbage checks I'm doing to make `cloud-init status --wait` reliable before I find alternatives.  Apparently I can grab the errors in a structured json format.  Some errors are fine, they have nothing to do with my config, but instead things like digital ocean agent which is just used for metrics and stuff and can be repaired easily.

I think its worth recording

---

Tried it, but immediately decided it is a terrible idea.  You have to encode shell scripts in yaml which is a minefield with escaping.

Technically, I think, values on the cloud-config can be base64 encoded.  But just feels like a rabbit hole without much gain.  Running scripts is enough for me right now.

I guess if you were building the yml in hcl, and then used their yml functions it might be fine.  But I can test that later in another context.

---

Trying cloud-config now instead of a simple script.  If this works I can control security a little more easily.  Like changing the SSH config to not use 22 but instead use a random port

But also preinstalling packages before the `runcmd`

---

Firewall working.

---

Meanwhile I've been reading up on nomad.  It sounds cool.  The reliance on consul for service discovery is a little disappointing.  I really love that swarm has a load balancer built in so you can allocate ports to services and still have n replicas per node.

I'm going to do a few experiments with nomad before deciding how I go.  But swarm is probably fine for the meanwhile.  It works well once you know how to avoid certain pitfalls.

Having an ssh tunnel, not using `context`, nuking `~/.docker`, stuff like that solves a lot of problems.

---

😅 was banging my head against the wall why the deployment suddenly was failing on simple apt-gets.

Turns out digital ocean's firewall defaults to no outbound traffic unless otherwise specified.  Which is great, but also suprising.

Trying a deploy now with an outbound rule for all tcp traffic.

---

I'm getting 500s on my load balancer creation when I introduce a firewall.  No idea what is going on.

I keep meaning to turn on TG_LOG=INFO but I don't want to cancel a run, and then when I start the run I do it automatically without thinking to change the command.

---

I also want to play with `depends_on` to see if I can get certain scripts to run at logical times.

E.g. joining a swarm should happen after any worker is created but only if a manager is ready.

I could put the depends_on on the worker but then the worker wouldn't get created in parallel.

So I'm hoping I can trigger a provisioner on a null resource per worker.

---

So I did that.  The certificate is now just a data source.  Which seems so obvious in hindsight.

Now I'm hitting issues with my firewall.  I put an ipv6 address in the allow list, and was locked out.  So I'm just going to allow all IPs for now.  For production I'll probably use a bastion.

Next up I'll change the ssh ports.  Randomizing would be cool.  Does terraform have a random function?

I love it: https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/integer

Random pet names.... hmm...

---

I just thought I could set `prevent_destroy` on the certificate resource.  But that isn't great either.  I'd need to never use destroy and instead comment out terraform files to cycle everything else.

Maybe I create the certificate outside of this workflow and then simply import it into the config via a data source?

---

Hitting let's encrypt rate limits now so I can't keep testing the entire thing unless I stop using DO's certificate resource because I can't see a way to specify the LE endpoint to be staging.

There is a let's encrypt provider.  So I may try that, or I may generate a certificate file and use that instead, but probably not as I don't want to think about expiring certificates.

So that just incentivizes me further to use passthrough on the loadbalancer and handle the certificate/https inside the LB using nginx or something.  And then I can easily have wildcard subdomains.

That said, for odin, I don't think we'll use wildcard subdomains, that's more a thing for other apps.  So that's not a big deal for me right now.

I'm not sure how LE would work with multiple nodes each with their own nginx

---

I'm thinking about how I want this to work in reality now that is working quite well.

So I was imagining inlining something similar to this repo in each project.  But the main cost benefit in having a swarm would be for every project to share the swarm.  That way if theres a lot of small projects with next to no traffic they can piggy back on larger commercial projects.  And equally larger commercial projects can justify having so many nodes because they are carrying load beyond just their app.

So I cant believe I'm saying this, but I am thinking of having a distinct swarm repo that just managers the cluster.  And then each app simply thinks in docker stacks.  From those apps perspective the swarm is a static resource.  It has a static registry address, a static ssh domain etc.

But... each app would need to share the same port space, and there could easily be collisions.  Which makes me think port registration should be replaced in favour of something like DNS look ups.

Maybe each app has its own load balancer, but all apps share the same cluster?

I know how to rig this up for a single app now.  From here its just building more complex images, linking the database to the VPC and that is all fairly rote.

None of this accounts for static resources I guess, that is a question I hadn't considered.  Maybe I need to look at integrating spaces.

There's also the question of wildcard subdomains, something not supported by DO directly.  Maybe I can have an nginx server on each node (`--global`) and that nginx server knows about all the apps, and all the certificates and routes via docker domain name to the correct service.  That's kind of great.  In that case, port mapping can be random.  We don't really care.

Or, maybe there is an API in front of the cluster that accepts deployments.  And it does all this mess.

Oh I also forgot about traefik!  I need to try that because that is probably the answer to a lot of these questions about routing to services and handling multiple apps.  Great

---

Working on adding in a loadbalancer and tightening up the firewall a bit before proceeding as it would be cool to see all this live against a domain.

So I'm thinking I'll update the ufw rules to all target the swarm subnet.  I'll add a DO firewall that only allows 2222 / 443

And then map 2222 to 22 or something.  Maybe I'll randomize it.  I actually don't need SSH access really once the infra is up as I'd rather just create a new workspace, deploy and use that.  I'm not sure why that isn't standard practice, maybe there is a reason?

Maybe I'll reserve an IP that is allowed to SSH in, and then I'll use a floating IP and bind it to an ephemeral droplet whenever I need to SSH in I'll hop to the droplet via doctl, and into the given server and then teardown the ephemeral droplet on disconnect.

---

Automation with tunnel working.  I'll look at moving some/all of this back into terraform now that it works.

---

This approached worked for me https://sysadmins.co.za/forwarding-the-docker-socket-via-a-ssh-tunnel-to-execute-docker-commands-locally/


Having a local socket didn't, also arguably better because you don't need to remember to cleanup the local .sock file.

Trying to automate using the port forwarding now.  But it isn't happy.  But I have faith!

---

Lol stack deploy works.  Ok I'll try the socket thing, that should remove most remaining problems I was hitting.  Then I'll go back to automating this instead of running commands manually.

---

Ok it works now.  I'll try stack deploy next

---

Oh my god, I just found a big mistake on my part.  The copy pasta node example I was using was listening _specifically_ on 127.0.0.1 which means it would ignore requests that didn't use that exact hostname.  Removing that worked locally.  I'll try that as a service, and then I'll retry stack deploy.

I feel sheepish!

---

Now I'm running my built image on the swarm.  Curling it doesn't seem to work.  I just get connection refused.

I might need to upgrade my registry so I can run 2 repositories and run my image and nginx side by side to see what the issue is.  But somehow nginx works and mine doesn't so that implies this is my fault as I deployed them in the same way.

---

Running ngninx with `docker service create` works great.  So I think, I will avoid docker-compose files, docker stack etc.

For now I'll try manually deploying a local build via `docker service create`

If that works I'll look into the docker ssh socket thing and then automate everything again.

I this works, I may return to using the docker terraform provider as my main gripe was the incompatibility with the docker compose format.  But the docker compose format doesn't even work so maybe it will work well 100% in terraform.

---

My new favourite thing is, private docker registries don't automatically fallback to the public docker registry.  So in order to have a mix of private and public images you need to first pull down the public images then push them to your registry...

I can't believe that.

---

Trying docker service create, and I just can't believe how flaky using ssh for DOCKER_HOST is.

So I thought, what if I port forward the docker socket and keep a persistent connection for the entire deploy.

And... someone else thought of this which is great!

https://medium.com/@dperny/forwarding-the-docker-socket-over-ssh-e6567cfab160

---

I keep getting an issue where I can ssh into the server fine, but docker-compose can't.  I'm very over this.  Going to try nomad next.

Actually I may just try `docker service create` which will probably work fine.  Trust me for listening to devrel "I always prefer a stack!".

---

I deployed an nginx service, and docker stack doesn't seem to like my network.  But I just remembered, reading, somewhere... that nginx image exposes on port 80 so I have to bind to 80 or it won't work.  That wouldn't explain why my node code wasn't working, but lets at least try nginx with port 80 bound.

Also I'm getting a new issue where terraform ends, known hosts works, cloud init waits and completes but then docker stack deploy doesn't connect straight away.  I think its connect limits/timeouts/rate limiting again.  But it seems worth it to tell SSH to temporarily not do that.  Another rabbit hole....

---

After seeing example after example using nginx, I thought I may as well use it to test my networking issues to rule out my build.

Also, another thought.  Having scripts in terraform is nice because you can always run apply or destroy and the script won't necessarily run.  So I think what I'll do instead is have a null resource that references nothing and put the provisioners on that.

It's not perfect but it at least will not run the script if an apply is a no-op.  It will capture oncreate/ondestroy for the entire config.

---

Other than whining, I should say, I managed to mess around with overlay, host, bridge networks a bit and I could ping a running nginx container from the public internet no problem.

I think by default the swarm network is meant to be reachable by the host, but again, maybe its some version thing.

Apparently there is a new docker-compose cli, `docker compose`.  it is a plugin for the main docker cli, and it is written in go.  Maybe there is more love there...

I think I can specify host networking in the docker-compose yml, but I think that is also wrong.

---

I had to jump on a different machine because my ISP was being an ISP.  And immediately I hit new CLI issues.

I think its pretty clear when using docker in production you need to pin your versions.  It's so easy to break a deploy script by being on the wrong point release.  Which is a sad state of affairs.  The amount of time I've wasted on silly bugs with open tickets.

Also things like the snap repository not having permission to use remote docker hosts but instead of sayin that, there's just a cryptic error... it feels like a script you or I would write, not a tool used by thousands of companies.

It is great tech, but the surface level stuff is flaky.

---

Its probably something really obvious, but I cannot curl the running service.  I haven't ruled out anything really yet though.

A lot of the examples are using `docker service create`, whereas I've been using `docker stack deploy` and `docker-compose push` etc.

Maybe `docker stack deploy` does something differently with networking.

---

I think once this works, I'll try out nomad to get a comparison.  I can see the value in swarm, and the simplicity.  But the CLI for docker is full of bugs.  And it rings alarms for me.

I always had a good experience with terraform's CLI so it's worth giving it a go.

I'm still very hesitant to use Kubernetes.  I don't want to introduce that level of complexity to Odin.  But I feel like I should
do a few K8s examples so I can meaningfully compare before commiting to Nomad or Swarm.

I just watched a stream where Bret Fisher was saying he was one of the last holdouts for swarm but he's not recommending it anymore.  This all seems to be based on non technical reasons, more industry reasons like everyone in industry moving towards K8s and docker selling off its closed source resources and team making people question if Swarm will continue to be developed.


---

Hanging on `docker logout` again so now I'm just doing:

`rm ~/.docker` instead.

---

I tried something basic and it didn't seem to work, so I'm reading this again:

https://docs.docker.com/network/network-tutorial-overlay/

---

Now that it deploys.  I'll see if I can actually ping the running service from one of the nodes.

---

It works.  Fully automated now.  I wrapped terraform as `terraform.sh` and added in my lifecycle scripts.

It builds, it pushes, it replicates.

---

Now `docker login` hangs, scratch that `docker` hangs generally.

---

This seems to work:


`docker login -u $DO_TOKEN -p $DO_TOKEN registry.digitalocean.com`

That means I need the DO_TOKEN available to my oncreate script.  It's currently in tfvars.

Maybe I shouldn't use tfvars, it just creates duplication.

I might bring back an .env file and have a terraform.sh script that just sets the directory and sources the env before usage.

in CI .env won't exist but that's fine I'll just do `source .env || true` or something

---

Getting quite far now, but can't seem to auth into the registry by setting DOCKER_CONFIG to the correct path

---

On 18-04 which is meant to fix this issue (it didn't) the docker-compose version is

docker-compose version 1.27.4, build 40524192

and on my machine the docker-compose version is 

docker-compose version 1.29.2, build 5becea4c


I guess I'll try and install the same docker version on my local.

`sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose`

---

My new problem is this:

> stderr=OpenSSL version mismatch. Built against 1010106f, you have 101000cf

There's an open issue for it https://github.com/docker/compose/issues/7686

All kinds of fun things happening.  Apparently if I downgrade docker compose the error will go away.  When I ssh into the manager and run `docker-compose --version` it just hangs.

---

Two things that tripped me up this morning.  SSH rate limiting and a bug in docker cli where a DOCKER_CONTEXT for an invalid server will just hang any `docker context` commands.

---

My automation journey was basically a circular spiral of death.

First I tried to script everything in terraform.  It worked but its janky because you can't see the output of logs for custom data providers and so its hard to debug.

Then I thought to script everything in one pass afterwards.  But got distracted when it came to extract the auth necessesary to contact the registry.

I wondered if I could get the auth from terraform, you can!  And the example shows usage with a docker terraform resource.  Which took me down the rabbit hole of using terraform instead of manually scripting.

But ultimately I found the docker provider super confusing because it maps to the docker API not the docker-compose format.  It was hard to get basic things working like defining an `image` property on the service to auto push to the private registry on build and deploy.  It kept saying the property was unexpected.

So now I'm thinking, I'll use this container registry thing, but only to store the auth as an output and then go back to manual scripting after the infra is up.
---

Ok before I proceed I am going to try to automate what I had to do so far.

---

I was wondering why the node.js docker image is 500mb, seems crazy.  The reason seems to be it includes an entire Debian distribution, and so several medium articles say to use alpine.  But I was reading from a docker captain that picking debian makes more sense because you won't trip on messing necessary common dependencies.

The digital ocean registry pricing is $5 a month for 5gig which is probably fair, but here is a docker article on using S3 backed storage:

https://docs.docker.com/registry/storage-drivers/s3/

and another

https://ops.tips/gists/aws-s3-private-docker-registry/

It would be nice to not care too much registry cost or image size.  That's not something I want to have to think about.  And if the paid registry has no special sauce, why not just use S3.

If DO automatically cleaned old images, maybe that'd be worth it.  But I don't think it does.

---

I need to parameterize the registry reference in the docker file with an env var from the terraform config.

Or parameterize both with a top level env var.

---

I'm still not 100% across using the CLI to check if the app is healthy.  And I didn't actually ping any of the services to see if they working.  But deployment at least is working.

---

I got it working, well the basics.

Lots of important steps to repro.  First of all you need a docker context, and you need to ensure SSH doesn't trip over known hosts.  But that is fine.

Next you need to include the registry in the `image` property for the service.  If `build` exists on a service, then `image` is assumed to be the name you want your image to be, as opposed to the name of an image you want to use.

You need to use `--with-registry-auth` so the workers can actually pull from the registry.  I had a failed replication because they were saying the image didn't exist.  It did, they just didn't have the auth.

You can inspect anything on the manager by just using `--context remote` arguably you may just want to switch into the remote context.

The image size for me for a basic app was 300mb, the free registry on docker has 500mb of space, so that could be an issue.

Also I used doctl to login to the registry, not sure if that was even needed.

So the final command that actualy deployed correctly for me was:

`docker --context remote stack deploy swarm-test --compose-file docker-compose.yml --with-registry-auth`

To build/deploy the image I used:

`docker-compose push` but the key thing was that the `image` property was in the yaml, and it referred to the private registry.

I set this env var:  `export DOCKER_CONFIG=$(echo $(pwd)/ops)` to point to the directory that contains my `config.json` which has the registry auth in it.

---

So I just figured out how to run docker commands against a remote host using SSH.

This could all easily be automated.

- Get the manager IP lets say it is `174.138.17.121`
- Create a docker context `docker context create remote --docker 'host=ssh://root@174.138.17.121'`
- This context can now be used when executing any command e.g. `docker --context run hello-world`

But, you need to ensure this address is in your known hosts so docker doesn't trip over itself.  You also need to ensure you follow the docker installation instructions and don't use the `snap` installation which will not have permission to fork ssh.  (That was a time sink).

If we wanted, we could use this to round robin `docker run` pretty easily.  We get all the IPs from terraform, create a context for each docker server and for each command execute docker run against the next IP.

It looks like a native Job abstraction is coming to docker swarm in a future release.  But this could easily replace `heroku run` for us now.

The main benefit of this context stuff though, or the initial intention for it, is deploying in CI without having to copy anything over.  It should be possible to run `docker stack deploy` with `--context remote` and it will build the image locally (hopefully) add it to the remote registry, and then distribute the replicas across the swarm.

I think I may need to do it as two steps though `docker-compose build --with-registry-auth` should place the images in the remote registry.  And then `docker-compose --context remote up` should have access to the registry.  Honestly not sure yet.

I have questions:

- Does the manager server need access to the registry, or will my local (or CI) command registry config be used even if I am using a remote context?

- If I use a remote context, and there is a build step, what happens?  Does the build happen remotely?  How can it if the source for the build is local?



---

This video shows how to update secrets without downtime:

https://youtu.be/oWrwi1NiViw?t=357

---

This shows that you can have a build step in the same compose file that is deployed as a stack.  It must just automatically use the latest image for that file.  Pretty cool.

https://docs.docker.com/engine/swarm/stack-deploy/

---

I guess I could also create and deploy the image for the latest src in the terraform config.  Just reimagining common workflows in this new world.

There must be an existing terraform resource for just that ... (googling) and there is...

https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/registry_image

So seems I just point this build property at the api folder (as an example) and it would automatically manage the deployment of that image.

That is amazing.

---

> We can skip the docker/hello-world, and jump straight to something interesting.  Let's see if we can run 6 instances of the same simple node app across 3 servers.

I got distracted.  So first lets see if we can get a simple node app running with across the swarm.

I'll try creating a private registry and pushing our image to the registry, and make a `production.yml` that only uses the private image.

---

One thing I was wondering is, do you have to SSH into the manager node to deploy a stack?

If so, wouldn't the repo need to be on the manager node? Unless if the `docker-compose.yml` didn't reference any relative paths and only referenced images on the private registry...

Come to think of it, not even sure if build works with deploy, so a private registry may be mandatory anyway...

But - irregardless found this: https://docs.docker.com/compose/production/#running-compose-on-a-single-server

Which explains if you set 3 env vars, the `docker-compose` command will actually execute against your remote server.  So I guess theoretically the same would be true for `docker stack deploy`.

I found this example of deploying via gitlab-ci with docker stack deploy and it seems to be doing exactly that: https://golangforall.com/en/post/go-deploy-docker-swarm-gitlab.html


---

Looks like Traefik could be super useful for sharing multiple domains with the same cluster.

---

Was wondering about this

https://docs.docker.com/engine/swarm/admin_guide/#force-the-swarm-to-rebalance

When I shutdown a worker and restart it, it didn't rejoin the swarm.  Which surprised me.  I thought it was because I needed to rejoin, but even after manually rejoining no tasks were allocated to the worker.

Seems this is by design.  I don't really get why though.  What harm is there to start using a server, if the rollout fails you just rollback, the existing services should still stay up.

But apparently you can force a rebalance via:

    docker service update -f

And with rolling updates I dont think that would cause much disruption.  I need to test though.

---

I'm just absorbing lots of documentation before continuing as it will probably save time later.

One thing I'm stuck on is, do I have to keep a container running for my worker tasks, or can I spin up a one time container across the swarm as required, sort of like `heroku run` or `docker run` or a lambda.

I think technically it is possible to create a service, that does not restart, and then remove the service afterwards.  But I'm wondering if there is something more native.

I also was reading about faasd, it lets you run serverless functions easily, but only on a single server.

The manager node exposes an API I think, so maybe it is possible to abstract away a lot of the mess of creating ephemeral services.  I'd rather not have a continually running container for every type of ephemeral task I may have on every node I want to run it.

But you know what, maybe that's logical.  I mean the servers will be there no matter what at the moment, I'm not planning on making that too dynamic.  I just want it to be easy to manually manage at the moment.  And an idle node.js web server in a container is likely very lightweight.  There is a problem where I'd like a completely ephemeral file system.  But even lambda doesn't provide that.


Maybe a viable approach is to run a global, non containerized simple web server on each node that has the ability to execute `docker run`.

When you hit the load balancer, you get a random node, each random node is guaranteed to have that server.  You can then say to run some arbirary image and it will.  The server could return any kind of statistics you want on that container.

Maybe the manager API already provides this ability.

More controversial - maybe I only have manager nodes, and no worker nodes.  Then they all have the API.

Turns out all docker engines machines have an API and the docker CLI is just making calls to the REST API behind the scenes running on each machine.  So theoretically that API could be proxied/exposed and abstracted to make "tasks" work.

---

Reading about volumes.  This is pretty amazing:

> You can mount a Samba share directly in docker without configuring a mount point on your host.

    docker volume create \
        --driver local \
        --opt type=cifs \
        --opt device=//uxxxxx.your-server.de/backup \
        --opt o=addr=uxxxxx.your-server.de,username=uxxxxxxx,password=*****,file_mode=0777,dir_mode=0777 \
        --name cif-volume

https://docs.docker.com/storage/volumes/#create-cifssamba-volumes

I have a few samba shares on my network, it would be cool to configure all of that via a local swarm.  I wonder if that can be configured in a service.yml file

---

For logging into our private registry:

    docker login registry.example.com
    docker service  create \
        --with-registry-auth \
        --name my_service \
    registry.example.com/acme/my_image:latest

https://docs.docker.com/engine/swarm/services/#create-a-service-using-an-image-on-a-private-registry

---

I'm playing with the services automatically repairing nodes that go offline.  It's not as ootb as I expected.

Thinking I need to add a call to rejoin the swarm on reboot so I can power cycle any worker.

    @reboot /path/to/script

https://askubuntu.com/a/816

or

    /etc/rc.local

https://askubuntu.com/a/1199

It also seems docker swarm doesn't redistributed scale when new servers appear, you need to explicitly re-scale the nodes.  I need to do more testing, but that kind of is disappointing.

---

> You can also use node labels in service constraints. Apply constraints when you create a service to limit the nodes where the scheduler assigns tasks for the service.

Seems very useful.

---

Ok, so I've got the swarm working on infra provision.  Pretty cool.  Next thing would be to check I can run an app across those nodes.

We can skip the docker/hello-world, and jump straight to something interesting.  Let's see if we can run 6 instances of the same simple node app across 3 servers.

That's a good place to expand from.  And enough to start thinking about rolling releases and how that will work.

---

Seems apply works eventually, but on the first run it doesn't.  I think data.external must have a timeout or something and doesn't wait for the manager to start.  Going to try a few things.  First, I'm going to log the json out before logging it.  Second I'm going to potentially do a remote-exec for wait waiting for cloud-init instead of a data.external

---

So I did some reading, here is the point...

Swarm mode allows us to have a swarm of machines that we can deploy multiple apps to, not just Odin, or Bute, but whatever.  We can have real machines, and then virtual instances automatically distributing load over those machines.  It automatically will handle a lot of things we'd expect say Heroku or DO App platform to do, like restarting apps that crash, and fine scale controls.  Note the scaling controls or for instances of a docker container, not new machines.

Docker swarm is distributed, what does that mean?  It means we could have a single swarm that spans local and remote nodes.  We could add raspberry pi's to the swarm as worker nodes, we could have digital ocean dedicated servers and AWS spot instances all interacting together on the same overlay network.  It gives us the ability to abstract away infra and providers.

Using swarm will also give us admin tools, and APIs, CLI's etc to anaylyze running services and servers.  

If we instead simply made each server have a single docker image, or a single systemd service, it would work, but it wouldn't give us the same level of freedom/control/distribution/introspection.  We'd be automating against Digital Ocean's API not the Docker API which allows us to move our infra to different providers without too much interruption.

One clear win is, we could have an AU cluster hosted on Vultr and a US cluster hosted on DO and only need some terraform config for each swarm.  We would need to have a different managed database cluster for each region and some servers and that would all be defined in the config.  It is not that simple, some data would need to be shared and synced but its also not that difficult either.

So we should go ahead.


---

I'm also thinking, what is the point of swarm?  If I can just plan/apply with different counts, and I can use the 
private container registry, why even bother with swarm?

What is the point?

---

Seems docker swarm requires us to create the infra ahead of time.

1. We need to create a manager and request a worker token for each worker node.
2. We need to know our own IP when scripting swarm init, not impossible to do dynamically, but trivial to do as a script after terraform
3. Each time we add a new node, we'll need to generate a new token, so the process is something like:

    - Generate new node (via terraform?)
    - SSH into manager and request a new worker token
    - SSH into worker and join with the given token

4. But... what if the cloud-init for the worker included the ssh key to log into the manager

   - And, it can ssh in and generate a token directly
   - And, then it can join using the token
   - But... do we want workers to have ssh access to the manager
    - I am guessing no?  But they are all connected as a VPC anyway.

5. 4 is nice, but I think 3 is safer and doesn't require the manager or the worker to have SSH capabilities into eachother 


So I'm thinking next step is to have a command to 

- create/update the infra with a parmaterized `count`
- identify the nodes which are not yet in the swarm
- ssh into each of them (preferably in parallel) and register them

---

First thing first, lets spin up 2 servers somewhere...  We'll need a terraform file
We'll also probably want a run file to orchestrate all the various commands
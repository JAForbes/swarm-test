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
I'm also thinking, what is the point of swarm?  If I can just plan/apply with different counts, and I can use the 
private container registry, why even bother with swarm?

What is the point?

So I did some reading, here is the point...

Swarm mode allows us to have a swarm of machines that we can deploy multiple apps to, not just Odin, or Bute, but whatever.  We can have real machines, and then virtual instances automatically distributing load over those machines.  It automatically will handle a lot of things we'd expect say Heroku or DO App platform to do, like restarting apps that crash, and fine scale controls.  Note the scaling controls or for instances of a docker container, not new machines.

Docker swarm is distributed, what does that mean?  It means we could have a single swarm that spans local and remote nodes.  We could add raspberry pi's to the swarm as worker nodes, we could have digital ocean dedicated servers and AWS spot instances all interacting together on the same overlay network.  It gives us the ability to abstract away infra and providers.

Using swarm will also give us admin tools, and APIs, CLI's etc to anaylyze running services and servers.  

If we instead simply made each server have a single docker image, or a single systemd service, it would work, but it wouldn't give us the same level of freedom/control/distribution/introspection.  We'd be automating against Digital Ocean's API not the Docker API which allows us to move our infra to different providers without too much interruption.

One clear win is, we could have an AU cluster hosted on Vultr and a US cluster hosted on DO and only need some terraform config for each swarm.  We would need to have a different managed database cluster for each region and some servers and that would all be defined in the config.  It is not that simple, some data would need to be shared and synced but its also not that difficult either.

So we should go ahead.

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
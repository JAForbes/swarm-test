# Swarm Test

This is just me experimenting with docker-swarm to see how easy/difficult it would be to use swarm instead of heroku for all our servers / tasks.

## Structure

I am imagining we'll have a terraform file which helps us rapidly spin up more or less servers and preconfigure them to be swarm nodes.  And then there will be a second layer which is management of those nodes via the docker CLI.

It would be really great to automatically increase/decrease the number of servers as required too, but I'm not sure if that will be possible in terraform alone, we may need to have a watcher that automatically tracks CPU usage or something.

Then there's the matter of deployment, how will that work?  Is each Odin release simply a new docker file?  How do releases propagate?  Can we have two releases live but only one promoted?

And finally cost, what is the cost savings over using say Heroku or DO's managed apps.

## Providers

I want to explore Linode, Vultr and AWS because they all support AU servers.  I also want to test out digital ocean because their pricing is so simple and their docs and API's are so good.

## Jobs vs Servers

I don't know if we'll have a serverless abstraction or if we simply have servers running horizontally.

## DNS

How DNS is managed is another interesting question.  It would be cool to support wildcard subdomains, something we can't do easily right now due to cloudflare.

## Databases

Can our managed database be in the same VPC as our docker swarm?  Or do we need to have our postgres cluster?
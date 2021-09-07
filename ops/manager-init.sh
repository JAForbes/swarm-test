#!/bin/bash

# local ip
lip=$(hostname -I | awk '{print $3}')

# init swarm
docker swarm init --advertise-addr $lip

# allow workers to join
ufw allow 2377
#!/bin/bash

source .env.sh || true

function init(){
    terraform -chdir=ops init $@
}
function plan(){
    terraform -chdir=ops plan $@
}
function apply(){
    # touch ./output/events.jsonstream
    # rm ./output/events.jsonstream 
    terraform -chdir=ops apply $@
    # ./run.js react
    
}
function destroy(){
    # touch ./output/events.jsonstream
    # rm ./output/events.jsonstream
    terraform -chdir=ops destroy $@
    # ./run.js react
}
function state(){
    terraform -chdir=ops state $@
}
function output(){
    terraform -chdir=ops output $@
}
function show(){
    terraform -chdir=ops show $@
}
function dangerous-loop(){
    destroy -auto-approve && apply -auto-approve
}

eval "$@"
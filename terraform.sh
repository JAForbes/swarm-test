#!/bin/bash

source .env.sh || true

function init(){
    terraform -chdir=ops init $@
}
function plan(){
    terraform -chdir=ops plan $@
}
function apply(){
    terraform -chdir=ops apply $@ \
    && ./run.js oncreate
}
function destroy(){
    ./run.js onbeforeremove
    terraform -chdir=ops destroy $@
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
#!/bin/bash

source .env || true

function plan(){
    terraform -chdir=ops plan $@
}
function apply(){
    terraform -chdir=ops apply $@
    ./run.js oncreate
}
function destroy(){
    ./run.js onbeforeremove
    terraform -chdir=ops destroy $@
}
function dangerous-loop(){
    destroy -auto-approve && apply -auto-approve
}

eval "$@"
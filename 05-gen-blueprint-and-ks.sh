#!/usr/bin/env bash

. $(dirname $0)/demo.conf

[[ $EUID -eq 0 ]] && exit_on_error "Must NOT run as root"

export EDGE_PASS_HASH="$(openssl passwd -6 ${EDGE_PASS})"

envsubst '${HOSTIP} ${EDGE_USER} ${EDGE_PASS_HASH} ${EDGE_VER}' \
    < edge.ks.orig > edge.ks

ORIG_BLUEPRINT=8-rfe-blueprint.toml.orig
if [ $EDGE_VER -eq 9 ]
then
    ORIG_BLUEPRINT=9-rfe-blueprint.toml.orig
fi

envsubst '${HOSTIP} ${EDGE_USER} ${EDGE_PASS_HASH} ${EDGE_VER}' \
    < $ORIG_BLUEPRINT > rfe-blueprint.toml

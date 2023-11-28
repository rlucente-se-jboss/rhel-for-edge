#!/usr/bin/env bash

. $(dirname $0)/demo.conf

[[ $EUID -eq 0 ]] && exit_on_error "Must NOT run as root"

export EDGE_PASS_HASH="$(openssl passwd -6 ${EDGE_PASS})"

envsubst '${HOSTIP}' < rfe-blueprint.toml.orig \
    > rfe-blueprint.toml

envsubst '${EDGE_USER} ${EDGE_PASS_HASH}' \
    < rfe-iso-blueprint.toml.orig > rfe-iso-blueprint.toml

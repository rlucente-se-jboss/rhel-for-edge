#!/usr/bin/env bash

. $(dirname $0)/demo.conf

[[ $EUID -ne 0 ]] && exit_on_error "Must run as root"

#
# Install the container-tools
#
dnf -y install container-tools

#
# Setup for a local insecure registry
#
firewall-cmd --permanent --add-port=5000/tcp
firewall-cmd --reload

#
# Configure insecure registry
mkdir -p /var/lib/registry
cat >/etc/containers/registries.conf.d/003-local-registry.conf <<EOF1
[[registry]]
location = "$HOSTIP:5000"
insecure = true
EOF1

#
# Create systemd unit files for registry service
#
CTR_ID=$(podman run --privileged -d --name registry -p 5000:5000 -v /var/lib/registry:/var/lib/registry:Z --restart=always docker.io/library/registry:2)
podman generate systemd --new --files --name $CTR_ID

#
# Clean up running containers
#
podman stop --all
podman rm -f --all

#
# Enable registry service
#
cp container-registry.service /etc/systemd/system
restorecon -vFr /etc/systemd/system
systemctl daemon-reload
systemctl enable --now container-registry.service


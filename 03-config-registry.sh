#!/usr/bin/env bash

. $(dirname $0)/demo.conf

[[ $EUID -ne 0 ]] && exit_on_error "Must run as root"

#
# Install the container-tools
#
grep VERSION_ID /etc/os-release | grep -q '9\.' && \
    dnf -y install container-tools || \
    dnf -y module install container-tools

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
# Create systemd quadlet for registry service
#
cat > /etc/containers/systemd/registry.container << EOF1
[Unit]
Description=Simple Container Registry Service
Requires=network-online.target

[Container]
Image=docker.io/library/registry:2
ContainerName=registry
PublishPort=5000:5000
Volume=/var/lib/registry:/var/lib/registry:Z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target default.target
EOF1

#
# Enable registry service
#
restorecon -vFr /etc/containers/systemd
systemctl daemon-reload
systemctl start registry


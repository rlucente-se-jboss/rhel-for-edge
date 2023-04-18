#!/usr/bin/env bash

. $(dirname $0)/demo.conf

[[ $EUID -eq 0 ]] && exit_on_error "Must NOT run as root"

# prep the edge.ks file
export VIP_STATE=${VIP_STATE_MASTER}
export VIP_PRIORITY=${VIP_PRIORITY_MASTER}

envsubst '${HOSTIP} ${VIP_IP} ${VIP_MASK} ${EDGE_USER} ${EDGE_PASS} ${VIP_STATE} ${VIP_PRIORITY}' \
    < edge.ks.orig > edge-master.ks

export VIP_STATE=${VIP_STATE_BACKUP}
export VIP_PRIORITY=${VIP_PRIORITY_BACKUP}

envsubst '${HOSTIP} ${VIP_IP} ${VIP_MASK} ${EDGE_USER} ${EDGE_PASS} ${VIP_STATE} ${VIP_PRIORITY}' \
    < edge.ks.orig > edge-backup.ks

# create blueprint file for image build
cat > rfe-blueprint.toml <<EOF
name = "RFE"
description = "RHEL for Edge"
version = "0.0.1"
modules = []
groups = []

[[packages]]
name = "container-tools"
version = "*"

[[packages]]
name = "jq"
version = "*"

[[packages]]
name = "keepalived"
version = "*"

[customizations.firewall]
ports = ["8080:tcp"]

[[customizations.user]]
name = "${EDGE_USER}"
description = "Admin User"
password = "$(openssl passwd -6 ${EDGE_PASS})"
groups = ["wheel"]

[customizations.services]
enabled = ["sshd","keepalived"]
EOF


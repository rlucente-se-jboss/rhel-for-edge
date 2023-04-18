#!/usr/bin/env bash

. $(dirname $0)/demo.conf

[[ $EUID -ne 0 ]] && exit_on_error "Must run as root"

# install image builder and other necessary packages
dnf -y install osbuild-composer composer-cli cockpit-composer \
    bash-completion jq golang

# enable image builder to start after reboot
systemctl enable --now osbuild-composer.socket cockpit.socket

# local autocomplete shell configuration script
source /etc/bash_completion.d/composer-cli

# add user to weldr group so they don't need to be root to run image builder
[[ ! -z "$SUDO_USER" ]] && usermod -aG weldr $SUDO_USER

# open firewall port for downloading updated rpm-ostree content
firewall-cmd --permanent --add-port=8000/tcp
firewall-cmd --reload


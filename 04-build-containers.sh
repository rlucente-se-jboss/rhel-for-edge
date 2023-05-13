#!/usr/bin/env bash

. $(dirname $0)/demo.conf

[[ $EUID -eq 0 ]] && exit_on_error "Must NOT run as root"

#
# Create containerized httpd application version 1
#
CTR_ID=$(buildah from registry.access.redhat.com/ubi9/ubi:latest)
buildah run $CTR_ID -- dnf -y install httpd
buildah run $CTR_ID -- sed -i "s/Listen 80/Listen 127.0.0.1:8080/g" /etc/httpd/conf/httpd.conf
cat <<'EOF1' > index.html
 ____  _   _ _____ _        __              _____    _            
|  _ \| | | | ____| |      / _| ___  _ __  | ____|__| | __ _  ___ 
| |_) | |_| |  _| | |     | |_ / _ \| '__| |  _| / _` |/ _` |/ _ \
|  _ <|  _  | |___| |___  |  _| (_) | |    | |__| (_| | (_| |  __/
|_| \_\_| |_|_____|_____| |_|  \___/|_|    |_____\__,_|\__, |\___|
                                                       |___/      
EOF1
buildah copy $CTR_ID index.html /var/www/html/index.html
buildah config --cmd "/usr/sbin/httpd -D FOREGROUND" $CTR_ID
buildah config --port 8080 $CTR_ID
buildah commit $CTR_ID $HOSTIP:5000/httpd:v1

podman push $HOSTIP:5000/httpd:v1

#
# Tag the image as "prod" in the local insecure registry
#
podman tag $HOSTIP:5000/httpd:v1 $HOSTIP:5000/httpd:prod
podman push $HOSTIP:5000/httpd:prod

#
# Create containerized httpd application version 2
#
CTR_ID=$(buildah from $HOSTIP:5000/httpd:v1)
cat <<'EOF2' >> index.html
 ________________________________ 
( Podman auto-update is awesome! )
 -------------------------------- 
   o
    o
        .--.
       |o_o |
       |:_/ |
      //   \ \
     (|     | )
    /'\_   _/`\
    \___)=(___/
EOF2
buildah copy $CTR_ID index.html /var/www/html/index.html
buildah commit $CTR_ID $HOSTIP:5000/httpd:v2

podman push $HOSTIP:5000/httpd:v2

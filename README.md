STILL A WIP

# RHEL for Edge Demo
This presents a demonstration of RHEL for Edge that includes:
* Serverless container application
* Automatic restart of container application
* Automatic update to container application
* Atomic upgrade of the underlying operating system with rollback on failure

## Pre-demo setup 
Start with a minimal install of RHEL on baremetal or on a VM. Make sure
this repository is on your RHEL host using either `git clone` or secure
copy (`scp`).

During RHEL installation, configure a regular user with `sudo` privileges
on the host. These instructions assume that this repository is cloned
or copied to your user's home directory on the RHEL host.

You'll need to customize the settings in the `demo.conf` script to
include your Red Hat Subscription Manager (RHSM) credentials to login
to the [customer support portal](https://access.redhat.com) to pull
updated content.

Login to the RHEL host using `ssh` and then run the first script both
to register and update the system.

    cd ~/rhel-for-edge
    sudo ./01-setup-rhel.sh
    reboot

After the system reboots, simply run the remaining scripts in order:

    sudo ./02-config-image-builder.sh
    sudo ./03-config-registry.sh
    ./04-build-containers.sh
    ./05-gen-blueprint-and-ks.sh
    
The above scripts do the following:
* install and enable the web console and image builder
* enable a local insecure registry on the host
* build two versions of a container app and push both to the local registry
* create the blueprints for the rpm-ostree image and ISO

Once you've run the above scripts successfully, setup is complete.

## Demo
### Compose the operating system image using composer-cli
We'll start by examining the blueprint file that is a template for the
OSTree operating system images we'll be creating.

    cd ~/rhel-for-edge
    less rfe-blueprint.toml

The blueprint file contains metadata for the OSTree image, desired
packages to be installed, and firewall customizations we would like
to add.

We'll continue by pushing the blueprint to the image builder server on
the host so we can begin to compose our image. You can also list all
the blueprints currently on the image builder server.

    composer-cli blueprints push rfe-blueprint.toml
    composer-cli blueprints list

Now, let's compose our first image using the command line tooling.
There are multiple image types that can be composed. Use the following
command to list them:

    composer-cli compose types

We'll be building a `edge-container` image type which is an OSTree image
packaged within a container with its own web server. Start a compose
using the following command:

    composer-cli compose start-ostree RFE edge-container

The image will take around ten minutes to build. You can check the
status using:

    watch composer-cli compose status

which refreshes every two seconds.

When the image is fully built, the status will change from `RUNNING` to
`FINISHED`. Use `CTRL-C` to stop the `watch` command.

Download the container with the embedded rpm-ostree image using:

    composer-cli compose image <TAB>

Copy the image to local container storage then run it to support building
a second version of the rpm-ostree operating system image.

    skopeo copy oci-archive:UUID-container.tar containers-storage:localhost/rfe:0.0.1
    podman run -d -p 8000:8080 localhost/rfe:0.0.1

where UUID matches the compose identifier from the downloaded file.

### Compose another operating system image
Edit the `rfe-blueprint.toml` file and change `version` to `0.0.2`
in the metadata and then add the following package:

    [[packages]]
    name = strace
    version = "*"

For this build, we'll create an `edge-commit` type which has all the
rpm-ostree content in a tarball. Make sure to reference the running
container so this is built as a second version of the current rpm-ostree
image.

    composer-cli blueprints push rfe-blueprint.toml
    composer-cli compose start-ostree RFE edge-commit --url http://HOST_IP:8000/repo

where HOST_IP matches the IP address of the machine building the
rpm-ostree content. The image compose will take around ten minutes to
build. You can check the status using:

    watch composer-cli compose status

Once it's finished, list the image UUIDs on the command line using:

    composer-cli compose status

The output will look something like this:

    ID                                     Status     Time                       Blueprint         Version   Type               Size
    f4dd2a33-c5ec-4a84-84cb-7ef694736206   FINISHED   Tue Nov 28 11:09:54 2023   RFE               0.0.1     edge-container     
    0c735375-5345-4f66-88c6-109676d8e1d8   FINISHED   Tue Nov 28 11:51:03 2023   RFE               0.0.2     edge-commit

Next, we'll create directories to hold our composed images so we can run
a simple web server to provide the content to the edge guest for upgrades.

    mkdir ~/version-2

We want to work with the UUID matching the `0.0.2` version of the image
build. For the `composer-cli compose image` command below, use command
completion by just pressing the TAB key and selecting the UUID matching
version `0.0.2` as shown above.

    cd ~/version-2
    composer-cli compose image IMAGE_UUID

You should download a image that's just over 800 MiB in size. Expand
that image and take a look at the metadata using:

    tar xf *.tar
    jq . compose.json

Use the `ref` to list all the packages in the image:

    rpm-ostree db list rhel/9/x86_64/edge --repo=repo | less

You can confirm that the `strace` package is included in this compose
using:

    rpm-ostree db list rhel/9/x86_64/edge --repo=repo | grep strace

### Build an installable image
Let's create an installable ISO image from the original rpm-ostree
image content. To do this, we'll reuse the podman container that's still
running with the original rpm-ostree image content to serve the image
files to the image-builder.

    cd ~/rhel-for-edge

Push the ISO blueprint file and start the image-builder.

    composer-cli blueprint push rfe-iso-blueprint.toml
    composer-cli compose start-ostree RFE-ISO edge-installer \
        --url http://HOST_IP:8000/repo

Make sure that HOST_IP matches the IP address of the machine hosting
the rpm-ostree. This build will take around ten minutes to complete.
You can check the status using:

    watch composer-cli compose status

Once it's finished, list the image UUIDs on the command line using:

    composer-cli compose status

The output will look something like this:

    ID                                     Status     Time                       Blueprint         Version   Type               Size
    f4dd2a33-c5ec-4a84-84cb-7ef694736206   FINISHED   Tue Nov 28 11:09:54 2023   RFE               0.0.1     edge-container     
    0c735375-5345-4f66-88c6-109676d8e1d8   FINISHED   Tue Nov 28 11:51:03 2023   RFE               0.0.2     edge-commit        
    b2e7bebb-ef8d-4db6-9dc7-1ec243c257c7   FINISHED   Tue Nov 28 13:42:37 2023   RFE-ISO           0.0.1     edge-installer

Download the installer image by using the appropriate UUID from above.

    composer-cli compose image UUID

We'll need to adjust the kickstart so that the installation is
automatic. To do that, use the following commands to get the kickstart
from the ISO, prepend some content to it, and then save as the new
kickstart.

    sudo mount -o loop UUID-installer.iso /mnt
    cat edge.ks.orig /mnt/osbuild.ks > edge.ks
    sudo umount /mnt

Again, make sure that UUID matches the installer UUID from the image
compose status above.

Finally, import the adjusted kickstart into the rpm-ostree image ISO.

    mkksiso edge.ks UUID-installer.iso my_edge.iso

Copy the `my_edge.iso` file to the host that you use to launch virtual
machines.

### Install the edge device
On the host machine (and not any virtual guests) launch the edge device
using the following command:

    sudo virt-install \
        --name edge-device \
        --memory 4096 \
        --vcpus 2 \
        --cdrom my_edge.iso \
        --disk size=64 \
        --graphics vnc,keymap=en-us \
        --noautoconsole \
        --noreboot

### Run the edge guest
Restart the guest and then open the console to it.

    sudo virsh start edge-device


LEFT OFF HERE


### Rootless and serverless container application
Each guest is configured to listen on port 8080 at the virtual IP address
for a web request. When an http request is received, systemd socket
activation will launch a proxy service which will in turn start the
container web application to service the request. The socket listener
and both services are running rootless under user `core`. Neither guest
is running any container applications at start up. The container web
application is started when the first request is received and only one
guest will respond since they are electing an owner for the virtual
IP address.

Let's watch this in action. We need to monitor which guest is running
a container application. Log in to each guest using username `core`
with password `edge` and then run the following command on each guest:

    watch 'clear; podman container list'

In the separate terminal where you built the images, use curl to send a
request to the virtual IP address. This address is defined in `demo.conf`
as the local LAN subnet with `.100`. In the example below, my local LAN
subnet is `192.168.1.0/24` so my virtual IP address is `192.168.1.100`.

    curl http://192.168.1.100:8080

The primary edge guest, if active, will receive the request on port
8080. If the primary edge guest is not running, the backup edge guest
will respond. Systemd, listening to that port via its socket activation
feature, will launch a proxy service that in turn will launch podman as
a service to run our container web application.  Podman will download
the container image from the registry, if it doesn't already have the
container image cached, and launch the containerized process. That
process will then respond to the http request.

Since both the primary and backup edge guests are running, the primary
guest will launch the container web application in response to the curl
request. We can test the failover feature of keepalived by terminating
the primary guest.  In the terminal window where you just ran `curl`,
type the following command:

    sudo virsh destroy edge-device-1

where `edge-device-1` corresponds to the primary guest and `edge-device-2`
corresponds to the backup guest. Adjust accordingly for your system.

Once the primary guest is terminated, resend the web request using:

    curl http://192.168.1.100:8080

Make sure to substitute your virtual IP address in the above command.
You'll see the container web application start on the backup edge guest
using the same mechanism as before. This demonstrates that the virtual
IP address was taken by the backup edge guest after the primary guest
was terminated. The web application was then launched on the backup edge
guest to respond to the web request.

### Auto restart of the container web application
Press the key combination `CTRL-C` on the edge guest to terminate the
`watch` command.

The systemd configuration for our container web service has the policy
`Restart=on-failure`. If the program should unexpectedly fail, systemd
will restart it. However, if the program normally exits, it will not
be restarted. The policy can also be modified to cover many use cases
as we'll see in a minute. Let's go ahead and trigger a restart of our
container web application.  Type the following command on the edge guest:

    pkill -9 httpd

This command sends a KILL signal to the httpd processes inside the
container, immediately terminating them. Since the restart policy is
`on-failure`, systemd will relaunch the container web application.
While that's happening, we can discuss the various restart policies that
are available.

The table below lists how the various policies affect a restart.
The left-most column lists the various causes for why the systemd managed
service exited. The top row lists the various restart policies. And the
`X`'s indicate whether a restart will occur for each combination of exit
reason and policy. A full discussion of the `Restart=` option in the
systemd service unit file is available via the command `man systemd-unit`
on the host system (the guest has no man pages installed to reduce space).

 Restart settings/Exit causes | no | always | on-success | on-failure | on-abnormal | on-abort | on-watchdog 
------------------------------|----|--------|------------|------------|-------------|----------|-------------
 Clean exit code or signal    |    |   X    |     X      |            |             |          |             
 Unclean exit code            |    |   X    |            |     X      |             |          |             
 Unclean signal               |    |   X    |            |     X      |     X       |    X     |             
 Timeout                      |    |   X    |            |     X      |     X       |          |             
 Watchdog                     |    |   X    |            |     X      |     X       |          |     X       

Once again, please confirm that the container application has fully
started. In the same terminal, type the following commands to see if
the container web application is fully active.

    systemctl --user status container-httpd.service
    watch 'clear; podman container list'

### Auto update of the container web application
Let's update the container web application image from version 1 to
version 2. In the same terminal window where you've been running `curl`,
type the following commands:

    HOSTIP=192.168.1.200
    podman pull --all-tags ${HOSTIP}:5000/httpd
    podman tag  ${HOSTIP}:5000/httpd:v2 ${HOSTIP}:5000/httpd:prod
    podman push ${HOSTIP}:5000/httpd:prod

Make sure the value of HOSTIP matches the IP address of your RHEL
host. You can determine this using:

    ip route get 8.8.8.8

and then look at the `src` field.

The edge guest is running a timer that periodically triggers a systemd
service to run `podman auto-update`. This command checks if there's
a different container image than what's currently running on the edge
guest. If so, the newer image is pulled to the guest and the container
web application is restarted. The above commands force this to occur. You
should see output in the edge guest indicating that the container web
application was restarted.

Resend the web request in the same terminal window as before using:

    curl http://192.168.1.100:8080

Make sure to substitute your virtual IP address in the above command.
You'll see that the response from the container web application has
changed.

### Atomic operating system upgrade with rollback on failure
RHEL for Edge simplifies operating system upgrades and automates rollbacks
when upgrades fail.  The greenboot facility enables applications to
define the conditions necessary for a successful upgrade.

On the edge guest, run the following command to view the greenboot
directory structure:

    find /etc/greenboot

Greenboot is implemented as simple shell scripts that return pass/fail
results in a prescribed directory structure. The directory structure is
shown below:

    /etc/greenboot
    +-- check
    |   +-- required.d  /* these scripts MUST succeed */
    |   +-- wanted.d    /* these scripts SHOULD succeed */
    +-- green.d         /* scripts run after success */
    +-- red.d           /* scripts run after failure */

All scripts in `required.d` must return a successful result for the
upgrade to occur. If there's a failure, the upgrade will be rolled
back. Our edge guest has a simple shell script mechanism to force a
rollback to occur.

Scripts within the `wanted.d` directory may succeed, but they won't
trigger a rollback of an upgrade if they fail. The `green.d` directory
contains scripts that should run as part of a successful upgrade and
scripts in the `red.d` directory will run if there's a rollback.

The simple shell script at
`/etc/greenboot/check/required.d/01_check_upgrade.sh` will fail if the
files `orig.txt` and `current.txt` differ. These files hold the OSTree
commit identifier after initial boot and the OSTree commit identifier for
the current boot. On the edge guest, run the following commands to review
the current OSTree commit identifier and the contents of those files:

    rpm-ostree status -v
    cat /etc/greenboot/orig.txt /etc/greenboot/current.txt

The text files hold the same OSTree commit identifier that's currently
active. We'll use this simple mechanism, for demonstration purposes, to
control if an upgrade succeeds or rolls back. By default, an attempted
upgrade will fail since the file `orig.txt` will not match the new OSTree
commit identifier in `current.txt`.

On the edge guest, examine the shell script that triggers a rollback
when these files are different:

    less /etc/greenboot/check/required.d/01_check_upgrade.sh

The file `orig.txt` is only written if it doesn't already exist.
This enables the guest to remember its original OSTree commit identifier
between upgrade attempts. You can allow an upgrade to happen simply
by deleting this file prior to starting the upgrade.  Again, this is
an artifice to enable demonstrating the rollback process. Production
systems should implement checks meaningful to the operating system and
application workloads.

To deliver updated OSTree content, we need to have a running web
server. We'll use a simple web server again on the host to serve the
OSTree content to the edge guest. Type the following commands in the host
terminal to start the web server in the same directory as the updated
OSTree content:

    cd ~/version-2
    go run ../demo-rfe/main.go

The edge guest has two systemd services, triggered by configurable
timers, to stage new OSTree images and force a reboot to trigger an
upgrade. The `rpm-ostreed-automatic` service downloads and stages
OSTree image content. The timer for this service is triggered once
an hour per the corresponding timer configuration. Systemd timers are
incredibly flexible and can be configured for virtually any schedule. The
`applyupdate` service triggers a reboot when there is staged OSTree
image content. The timer for this service is triggered once per minute
to automate upgrades for this demonstration.  Again, nearly any schedule
can be used for this timer.

Type the following command in a guest terminal to view when these timers
are set to be triggered.

    systemctl list-timers --no-pager

The output will resemble the following:

    Fri 2021-04-02 18:11:32 UTC  56s left      Fri 2021-04-02 18:10:32 UTC  3s ago applyupdate.timer
    Fri 2021-04-02 18:59:11 UTC  48min left    n/a                          n/a    rpm-ostreed-automatic.timer

Rather than wait up to an hour for the `rpm-ostreed-automatic` service to
be triggered via its timer, we'll instead force an upgrade by directly
running the service. Type the following command in the guest terminal
window:

    sudo systemctl start rpm-ostreed-automatic

This will start the process on the edge guest device to pull new
content from the host. In the host terminal, you'll see the various
files being downloaded to the the guest. You should also notice that
the number of files and their accumulative size is much smaller than
the initial installation. This is because rpm-ostree only downloads the
deltas between the current OSTree image and the new OSTree image which
can save significant bandwidth and time when operating in environments
with limited connectivity.

After the content is downloaded and staged, the `applyupdate` timer
will expire within a minute and start the `applyupdate` service that
will trigger a reboot.

Since the `/etc/greenboot/orig.txt` file contains the OSTree commit
identifier from the initial installation, any successive upgrade will
fail. The system will attempt to upgrade the operating system three
times before rolling back to the prior version. With each boot attempt,
you should see the following appear in the guest terminal:

      Red Hat Enterprise Linux 8.4 (Ootpa) (ostree:0)
      Red Hat Enterprise Linux 8.4 (Ootpa) (ostree:1)

The `ostree:0` image will be highlighted on the first three boot attempts
since `ostree:0` designates the most recent operating system content and
`ostree:1` represents the previous operating system content. After the
third failed attempt, the guest terminal will then highlight `ostree:1`
which indicates that a roll back is occurring to the prior image. This
entire process will take a few minutes to complete.

When the rollback is completed, the login prompt will appear for the
edge guest. Login using username `core` and password `edge`.

When we built the `0.0.2` version of our operating system OSTree image,
we added the `strace` utility. You can confirm that utility is missing
in the current active operating system image by typing the following
command in the guest terminal:

    which strace

The output should resemble the following:

    /usr/bin/which: no strace in (/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin)

Type the following command to confirm that the upgrade did not occur
by looking at the current commit identifiers of the local operating
system content:

    rpm-ostree status -v

The output from that command will resemble the following:

    State: idle
    AutomaticUpdates: stage; rpm-ostreed-automatic.timer: no runs since boot
    Deployments:
    ● ostree://edge:rhel/9/x86_64/edge
                     Timestamp: 2021-03-31T00:11:31Z
                        Commit: 98a1d03316797162d4b3a1fad22c36be049c46b42605307a0553e35c909c6a6d
                        Staged: no
                     StateRoot: rhel
    
      ostree://edge:rhel/9/x86_64/edge
                     Timestamp: 2021-03-31T00:38:20Z
                        Commit: 662c26c39800e4fa97430fecdab6d25bd704c8d9228555e082217b16d5697f02
                     StateRoot: rhel

The active image is preceded with an `●` and you can tell its the
prior image by looking at the timestamps for both. The commit identifier
for the active image also matches the commit identifiers in both the
`/etc/greenboot/orig.txt` and `/etc/greenboot/current.txt` files. Type
the following commands to exxamine those files.

    cat /etc/greenboot/orig.txt /etc/greenboot/current.txt

Now, let's enable the OSTree upgrade to occur by deleting the
`/etc/greenboot/orig.txt` file so that our greenboot script at
`/etc/greenboot/check/required.d/01-check_upgrade.sh` returns success,
allowing the upgrade process to move forward. In the guest terminal,
type the following command:

    sudo rm -f orig.txt

We need to stage new OSTree content for the upgrade, so we'll re-run the
`rpm-ostreed-automatic` service to download and stage the content from
the web server on the host. Please type the following commands on the
edge guest to review the timers and start the atomic upgrade process:

    systemctl list-timers --no-pager
    sudo systemctl start rpm-ostreed-automatic

You'll observe in the host terminal that only five files are requested
of inconsequential size. The guest already has the content needed so
it's merely requesting metadata to determine if this is the most recent
OSTree content. Once the content is staged, the `applyupdate` service
timer will expire within a minute and the `applyupdate` service will
trigger a reboot.

The upgrade will succeed this time. The boot screen with the OSTree
image list will appear only once. This will take a minute or two to
finish. Login again as user `core` with password `edge`. Confirm that
the upgrade was successful by typing the following command on the edge
guest to show that the `strace` command is available:

    which strace

The output should resemble:

    /usr/bin/strace

You can also examine the OSTree image list to see that the newest OSTree
image content is active.

    rpm-ostree status -v

The output from that command will resemble:

    State: idle
    AutomaticUpdates: stage; rpm-ostreed-automatic.timer: no runs since boot
    Deployments:
    ● ostree://edge:rhel/9/x86_64/edge
                     Timestamp: 2021-03-31T00:38:20Z
                        Commit: 662c26c39800e4fa97430fecdab6d25bd704c8d9228555e082217b16d5697f02
                        Staged: no
                     StateRoot: rhel
    
      ostree://edge:rhel/9/x86_64/edge
                     Timestamp: 2021-03-31T00:11:31Z
                        Commit: 98a1d03316797162d4b3a1fad22c36be049c46b42605307a0553e35c909c6a6d
                     StateRoot: rhel

The `orig.txt` and `current.txt` files will also contain the OSTree commit
identifier for the latest OSTree image. Type the following commands on
the edge guest:

    cat /etc/greenboot/orig.txt /etc/greenboot/current.txt

To terminate the emulated edge device, simply type the following command
in the guest terminal window:

    sudo poweroff

This completes the RHEL for Edge demo.


---
title: Aidan Houck - Blog - Scripting Proxmox Containers
subtitle: I use NixOS btw
date: 2024-11-24
---

# Introduction
Currently, I have a single Proxmox node with 1 VM and 8 LXC containers. These containers all run fairly simple individual services, while the singular VM just runs Docker for the few things that really are best done in Docker.

Inspired by [Docker Compose](https://docs.docker.com/compose/), and more specifically how easy their compose files make embracing [server as cattle](https://www.engineyard.com/blog/pets-vs-cattle/), I wanted to try and glue together some automation for Proxmox. 

My immediate goal would be to convert most (all?) of my containers into scripts that can dynamically create containers with known-good state (defined in config files and code). This would help with upgrades, bug squashing, speed to create new containers, and disaster recovery (maybe). 

In the future I wouldn't mind moving some of my docker containers into LXC containers and potentially even getting rid of that VM to save on resources, but some of them use pretty involved [Docker Networking](https://docs.docker.com/engine/network/) on third party images so I'm not holding my breath quite yet. 

This is the game plan:
<ol>
	<li>Figure out how to create PVE containers using [pct](https://pve.proxmox.com/pve-docs/pct.1.html)</li>
	<li>Figure out how to assign meta-container configuration (memory, CPU, mount points, privileged vs unprivileged)</li>
	<li>Figure out how to copy files from the host into the containers (config files, setup scripts)</li>
	<li>Figure out how to actually shut down an existing PVE container
		<ol type="a">
			<li>Do I need to destroy the container to create a new one? Or can I just shutdown and "archive" somehow?</li>
			<li>Does this do anything weird with volumes, logs, etc? Any footguns before nuking a container I'm actually using?</li>
		</ol>
	</li>
	<li>Clean up the script so that it can be easily extended for different containers</li>	
	<li>Actually start to migrate some existing containers and their data into this system</li>
	<li>BONUS: Figure out if there is a way to add this button in the PVE UI somewhere (don't judge me I like the GUI)</li>
</ol>

Whew.

# Steps

## 1. `pct` Basics
<abbr title="Proxmox Container Toolkit">`pct`</abbr> provides an interface for creating containers natively without having to use the GUI. Much of the below steps were gathered from the [official PVE documentation](https://pve.proxmox.com/wiki/Linux_Container#_managing_containers_with_tt_span_class_monospaced_pct_span_tt).

First we want to create a new container. Start by finding your existing container template if you already have one. I know the only template I use for Debian 12 is located here:
<picture>
	<img src="images/blogs/pve_scripting/1-pve_container_template.png" alt="A screenshot of my Debian 12 container template in Proxmox.">
</picture>

You can use <abbr title="Proxmox VE Appliance Manager">`pveam`</abbr> to find the name that is used to refer to that template in Proxmox:
<pre><code>
root@pve:~# pveam list zfs-dir
NAME                                                         SIZE
zfs-dir:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst       120.29MB
</code></pre>

Then you can use that information to create a basic container like so:
<pre><code>
pct create 150 zfs-dir:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst
</code></pre>

This fails:
<pre><code>
root@pve:~# pct create 150 zfs-dir:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst
400 Parameter verification failed.
storage: storage 'local' does not support container directories
pct create <vmid> <ostemplate> [OPTIONS]
</code></pre>

Because my default storage location (`local`) does not allow for container storage volumes. Instead I use my ZFS array titled `zfs-main` for that purpose. We'll need to append that to the create command so it puts it in the right place:
<pre><code>
pct create 150 zfs-dir:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst --storage zfs-main
</code></pre>

And now it works!
<pre><code>
root@pve:~# pct create 150 zfs-dir:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst --storage zfs-main
extracting archive '/zfs/backups/template/cache/debian-12-standard_12.2-1_amd64.tar.zst'
Total bytes read: 519987200 (496MiB, 91MiB/s)
Detected container architecture: amd64
Creating SSH host key 'ssh_host_rsa_key' - this may take some time ...
done: SHA256:QSlHc6fDLKNztb3UalfntLvfTjIfazsKsK6ovS9U0aQ root@localhost
Creating SSH host key 'ssh_host_dsa_key' - this may take some time ...
done: SHA256:+3z7yUefkBegm4rjcyQnovIG7pzBsxYcxuyjYFOZ2zY root@localhost
Creating SSH host key 'ssh_host_ecdsa_key' - this may take some time ...
done: SHA256:Gca9h6kIHX71mihXzB0vi62MjewQn6mrfHrY+Y2wxX8 root@localhost
Creating SSH host key 'ssh_host_ed25519_key' - this may take some time ...
done: SHA256:t3o9jWNja5CCj+Gd8lVjbV4V/cQ/rIai1hpVy8VPiZs root@localhost

root@pve:~# pct list
VMID       Status     Lock         Name
101        running                 tailscale
102        running                 ns1
103        running                 ns2
104        running                 ripe-probe
105        running                 wiki
106        running                 dashboard
107        running                 cacti
108        running                 cache
150        stopped                 CT150
</code></pre>


## 2. `pct` Additional Details
Now that we have a proof of concept we need to start fine-tuning some of these parameters. Poking around the GUI at little `150` I'm noticing a lot of different things like networking, storage, CPU, etc we're missing.

Before getting started on this I want to start throwing these commands into a nice script so they're easy to reuse. 
<pre><code>
root@pve:~# cat /opt/pve-new-ct.sh
#!/bin/bash

# If did not supply LXC ID, die
[ -z "${1}" ] && printf "Usage: $0 <LXC ID>\n" && exit 1

# Create new container
pct create "${1}" zfs-dir:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst --storage zfs-main
root@pve:~# chmod +x /opt/pve-new-ct.sh
root@pve:~# /opt/pve-new-ct.sh 150
CT 150 already exists on node 'pve'
</code></pre>

<aside>
I'm not sure if `/opt` is really the best place for system-wide scripts like this but that's just what I've always defaulted to.
</aside>

This works but as you can see we're blindly trying to create new containers without checking if one is there already. Let's add some additional logic. We can check what IDs are in use via `/etc/pve/.vmlist`:
<pre><code>
root@pve:~# cat /etc/pve/.vmlist
{
"version": 3255,
"ids": {
"104": { "node": "pve", "type": "lxc", "version": 3217 },
"201": { "node": "pve", "type": "qemu", "version": 3259 },
"103": { "node": "pve", "type": "lxc", "version": 3207 },
"102": { "node": "pve", "type": "lxc", "version": 3197 },
"108": { "node": "pve", "type": "lxc", "version": 3257 },
"101": { "node": "pve", "type": "lxc", "version": 3187 },
"107": { "node": "pve", "type": "lxc", "version": 3247 },
"106": { "node": "pve", "type": "lxc", "version": 3237 },
"105": { "node": "pve", "type": "lxc", "version": 3227 },
"150": { "node": "pve", "type": "lxc", "version": 3263 }}

}
</code></pre>

And gather status using `pct list`:
<pre><code>
root@pve:~# pct list
VMID       Status     Lock         Name
101        running                 tailscale
102        running                 ns1
103        running                 ns2
104        running                 ripe-probe
105        running                 wiki
106        running                 dashboard
107        running                 cacti
108        running                 cache
150        stopped                 CT150
</code></pre>

<aisde>
We could probably just use pct list for this but it feels a bit "nicer" to read a text file where possible instead of immediately doing a query on the system.
</aside>

I ended up with this:
<pre><code>
# Check if ID is in use
if grep -q \""${1}"\" /etc/pve/.vmlist; then
        printf "ID %s already in use...\n" "$1"
        STATUS_LIST=$(pct list | grep -E "^${1}" | tr -s ' ')
        STATUS=$(echo "$STATUS_LIST" | cut -d' ' -f2)
        NAME=$(echo "$STATUS_LIST" | cut -d' ' -f3)

        while true; do
                printf "Container %s (%s) is currently %s.\n" "$NAME" "$1" "$STATUS"
                read -rp "Continue and destroy container? (y/n) " yn
                case $yn in
                        [Yy]* ) break;;
                        [Nn]* ) exit;;
                esac
        done
else
        printf "ID %s is not in use. Continue...\n" "$1"
		EXISTING=0
fi
</code></pre>

And it seems to work OK:
<pre><code>
root@pve:~# /opt/pve-new-ct.sh 150
ID 150 already in use...
Container CT150 (150) is currently stopped.
Continue and destroy container? (y/n) y

root@pve:~# /opt/pve-new-ct.sh 151
ID 151 is not in use. Continue...

root@pve:~# /opt/pve-new-ct.sh 102
ID 102 already in use...
Container ns1 (102) is currently running.
Continue and destroy container? (y/n) n
</code></pre>

Now that the script feels a little more controlled I'll start adding cleanup functionality too. In general this will only ever be used for a full delete and re-build so I'm not going to bother trying to edit any existing containers.
<pre><code>
# If this had a previous container destroy it first
if [ -z "$EXISTING" ]; then
        printf "Destroying CT %s...\n" "$1"
        pct destroy "$1" --purge || { echo "Failed to purge container, exiting..."; exit 1; }
fi
</code></pre>

Finally time to get into the bulk of the `pct` options. Most of these things it seems like you have the choice of doing _at_ creation time or _after_ creation time. I'll do as much as possible _at_ creation because that just saves an extra step. Here is the big long `pct create` command I ended up with:
<pre><code>
# Create new container
pct create "${1}" \
        zfs-dir:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
        --storage zfs-main \
        --hostname "Testing" \
        --description "Testing description" \
        --onboot 1 \
        --cores 1 \
        --memory 256 \
        --swap 256 \
        --features nesting=1 \
        --timezone host \
        --unprivileged 1 \
        --net0 name=eth0,bridge=vmbr0,firewall=1,ip=192.168.30.150/24,gw=192.168.30.1,ip6=fd00:30::150/64,gw6=fd00:30::1 \
        --start 1 \
        || { echo "Failed to create container, exiting..."; exit 1; }


pct status "$1" --verbose
</code></pre>

This script will need cleaned up so you can dynamically import things like hostname, needed memory, IP addresses, etc but for now it should be good enough.

## 3. Moving Files into the Container
Now that we can dynamically create containers with specific options we need to start the actual setup process. My base ZFS volume is mounted on the Proxmox host under `/zfs` so I'm going to start adding things there. I'll use `/zfs/lxc/<CT>` as the root dir for files under each container. I'm also going to have some shared files for common setup so those will go under `/zfs/lxc/shared`:
<pre><code>
houck@pve:~$ tree /zfs/lxc/
/zfs/lxc/
├── shared
│   └── opt
│       └── setup.sh
└── testing
    ├── opt
    │   └── hello-world.sh
    └── root
        └── hello-world.txt

6 directories, 3 files
</code></pre>

We'll modify our initial script to try copying all 3 of these files into the container filesystem, then executing both startup scripts. 
<pre><code>
# Copy needed files into container filesystem
printf "Copying files into CT %s...\n" "$1"
pct push "$1" /zfs/lxc/shared/opt/setup.sh /opt/setup.sh
pct push "$1" /zfs/lxc/testing/opt/hello-world.sh /opt/hello-world.sh
pct push "$1" /zfs/lxc/testing/root/hello-world.txt /root/hello-world.txt
</code></pre>

If we login manually we can see the files are there:
<pre><code>
# Copy needed files into container filesystem
printf "Copying files into CT %s...\n" "$1"
pct push "$1" /zfs/lxc/shared/opt/setup.sh /opt/setup.sh
pct push "$1" /zfs/lxc/testing/opt/hello-world.sh /opt/hello-world.sh
pct push "$1" /zfs/lxc/testing/root/hello-world.txt /root/hello-world.txt
</code></pre>

Now we can start running setup commands.
<pre><code>
# Run setup commands
printf "Running setup in CT %s...\n" "$1"
pct exec "$1" -- bash -c 'chmod +x /opt/*.sh'
pct exec "$1" -- bash -c '/opt/setup.sh'
pct exec "$1" -- bash -c '/opt/hello-world.sh'
pct exec "$1" -- bash -c 'cat /root/hello-world.txt'
</code></pre>

And this works as expected:
<pre><code>
houck@pve:~$ sudo /opt/pve-new-ct.sh 150
ID 150 already in use...
Container Testing (150) is currently running.
Continue and destroy container? (y/n) y
Shutting down CT 150...
Destroying CT 150...

<snip>

Could not execute systemctl:  at /usr/bin/deb-systemd-invoke line 145.
Setting up ssh (1:9.2p1-2+deb12u3) ...
Processing triggers for man-db (2.11.2-2) ...
Processing triggers for libc-bin (2.36-9+deb12u3) ...
hello world
</code></pre>

There is a lot more functionality I need to add to my setup script to create a fully fledged out system, but I'll worry about that in <a href="#final-primary-script-cleanup">step 5</a> once we are ready to start looking at "prod" deployments.

## 4. Gracefully Deleting the Previous Container
While messing with this I noticed that I was missing some nightly backups for my test LXC, `150`. In the picture below notice I only have a backup from the 14th, while this container was first created mid-day on the 12th:
<picture>
	<img src="images/blogs/pve_scripting/2-pve_backups.png" alt="A screenshot of missing Proxmox container backups.">
</picture>

This is because I somehow misread what the `--purge` part of `pct destroy XXX --purge` did...
<pre><code>
root@pve:/home/houck# pct help destroy
USAGE: pct destroy <vmid> [OPTIONS]

  Destroy the container (also delete all uses files).

...

  --purge    <boolean>   (default=0)
             Remove container from all related configurations. For example,
             backup jobs, replication jobs or HA. Related ACLs and Firewall
             entries will *always* be removed.
</code></pre>

That is, in fact, the whole point. I've modified the script to no longer use the purge flag and now it no longer yeets all of my mostly-valid backups when rebuilding a container. 

While toying with this I was curious if taking a [Snapshot](https://pve.proxmox.com/wiki/Live_Snapshots) right before deletion would make sense. Because snapshots capture RAM and state theoretically if the new container goes awry this would make it easier to rebuild from scratch. 

However snapshots [do not persist when a container is deleted](https://forum.proxmox.com/threads/snapshot-deleted-after-restore-vm-from-backup.26035/) and re-created. They aren't separate entities like full backups, but rather are linked to the container. Instead, I do think it would be wise to do a manual _full backup_ right before destroying the container. 

This can be done via [vzdump](https://pve.proxmox.com/pve-docs/vzdump.1.html) relatively simply:
<pre><code>
// Options mostly copied from `/etc/pve/jobs.cfg`
printf "Creating backup of CT %s...\n" "$1"
vzdump "$1" \
        --compress zstd \
        --fleecing 0 \
        --mailnotification always \
        --mailto pve@aidanhouck.com \
        --mode snapshot \
        --node pve \
        --notes-template "Pre-rebuild: {{guestname}}" \
        --storage zfs-dir \
        || { echo "Failed to backup container, exiting..."; exit 1; }
</code></pre>

## 5. Final Primary Script Cleanup
Now that the big steps are sensible I want to finish cleaning up this script. I left a few hard coded IPs, files, etc in there that need to come out before moving a prod container.

I ended up modifying the script to take a directory name as parameter 2:
<pre><code>
CONFIG_ABOUT="/zfs/lxc/${2}/about.sh"
CONFIG_FILES="/zfs/lxc/${2}/files.sh"

# If did not supply path to container info, die
[ ! -f "${CONFIG_ABOUT}" ] && printf "ERROR: /zfs/lxc/%s/about.sh cannot be read!\n" "$2" && exit 1
[ ! -f "${CONFIG_FILES}" ] && printf "ERROR: /zfs/lxc/%s/files.sh cannot be read!\n" "$2" && exit 1

# shellcheck source=/dev/null
source "$CONFIG_ABOUT" || { printf "Failed to source %s, exiting..." "$CONFIG_ABOUT"; exit 1; }

...

# Use files.sh to copy needed files into the container and execute them
# shellcheck source=/dev/null
source "$CONFIG_FILES" || { printf "Failed to source %s, exiting..." "$CONFIG_FILES"; exit 1; }
</code></pre>

These files will look something like this:
<pre><code>
root@pve:~# cat /zfs/lxc/testing/about.sh
#!/bin/bash

CT_NAME="Testing"
CT_DESC="Testing description"
CT_CORES="1"
CT_MEMORY="256"
CT_SWAP="256"
CT_UNPRIV="1"

CT_BRIDGE="vmbr0"
CT_IP4="192.168.30.150/24"
CT_IP4_GW="192.168.30.1"
CT_IP6="fd00:30::150/64"
CT_IP6_GW="fd00:30::1"

root@pve:~# cat /zfs/lxc/testing/files.sh
#!/bin/bash

# Copy needed files into container filesystem
printf "Copying files into CT %s...\n" "$1"
pct push "$1" /zfs/lxc/shared/opt/setup.sh /opt/setup.sh
pct push "$1" /zfs/lxc/testing/opt/hello-world.sh /opt/hello-world.sh
pct push "$1" /zfs/lxc/testing/root/hello-world.txt /root/hello-world.txt

# Run setup commands
printf "Running setup in CT %s...\n" "$1"
pct exec "$1" -- bash -c 'chmod +x /opt/*.sh'
pct exec "$1" -- bash -c '/opt/setup.sh'
pct exec "$1" -- bash -c '/opt/hello-world.sh'
pct exec "$1" -- bash -c 'cat /root/hello-world.txt'
</code></pre>

The shellchecks are needed for [SC1090](https://www.shellcheck.net/wiki/SC1090), but besides that no real issues. Now I just need to make new directories and copy template/script files over for each container.

## 6. Putting It All Together
Finally it's time to finally move a single container over just to finish the proof of concept up. I keep pretty decent notes in my wiki when setting something up for the first time, but they're mostly interactive configuration. Things like config files, databases, and changes I forgot about are all going to be tough to deal with. 

I'm going to start with Tailscale.

First, scaffolding using the template dir:
<pre><code>
cp -r /zfs/lxc/shared /zfs/lxc/tailscale
mv /zfs/lxc/tailscale/about-template.sh /zfs/lxc/tailscale/about.sh
mv /zfs/lxc/tailscale/files-template.sh /zfs/lxc/tailscale/files.sh
mv /zfs/lxc/tailscale/opt/setup-sh /zfs/lxc/tailscale/opt/tailscale-setup.sh
</code></pre>

Then tweaking `about.sh` and `files.sh` with reasonable values. I mostly just mirrored what my existing Tailscale container was running with.

<aside>
NOTE: If you're going to run the new and old containers in parallel (like I'm about to do) make sure you don't give them the same IP addresses!
</aside>

After some trials and tribulation this is what my `tailscale-setup.sh` ended up looking like:
<pre><code>
# Install curl and Tailscale
apt-get install -y curl
curl -fsSL https://tailscale.com/install.sh | sh

# Make necessary changes for acting as an exit node
echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf

# Change default config to allow tailscail to run
# in an unprivileged container
#cp /etc/default/tailscaled /etc/default/tailscaled.bak
#sed -iE 's/FLAGS.*$/FLAGS="--tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055"/' /etc/default/tailscaled

# Verify the status is started
systemctl start tailscaled

# Bring up with authkey
tailscale up --authkey=`cat /opt/tailscale-authkey` --advertise-routes="192.168.0.0/16" --advertise-exit-node --advertise-tags=tag:container --statedir=/var/lib/tailscale

tailscale status
</code></pre>

`/opt/tailscale-authkey` was generated manually from https://login.tailscale.com/admin/settings/keys and expires after 90 days. I might look into auto-refreshes via API? Or potentially disabling expiration. 

The new containers were not coming up as exit nodes due to not having the routes approved in the dashboard first:
<picture>
	<img src="images/blogs/pve_scripting/3-tailscale_autoapprove.png" alt="A screenshot the Tailscale dashboard showing the new container not being approved to advertise its' routes.">
</picture>

This was a pretty easy fix using the beta [auto approvers](https://tailscale.com/kb/1337/acl-syntax#auto-approvers) feature. I edited my ACL in the Tailscale dashboard with the following sections:
<pre><code>
	// Define the tags which can be applied to devices and by which users.
	"tagOwners": {
	 	"tag:container": ["autogroup:admin"],
	},
	
	"autoApprovers": {
		"routes": {
			"192.168.0.0/16": ["tag:container"],
		},
		"exitNode": ["tag:container"],
	},
</code></pre>

Now this all works, but after recreating the container it won't remove the old one from the admin GUI. There may be a way to auto-delete intelligently but in reality this should probably be done similar to the [docker container](https://tailscale.com/kb/1282/docker)'s setup with a persistent state directory.
<pre><code>
# Create world read-writable dir for Tailscale to use
mkdir -p /zfs/lxc/tailscale/persist
chmod 777 tailscale/persist/

# Add to `tailscale-setup.sh`:
 --statedir=/persist/tailscale --state/persist/tailscale/tailscaled.state

# Needed because the default systemd service includes a
# '--state=/...' parameter, $FLAGS (from /etc/default/tailscaled)
# are placed AFTER the default parameter. Evidently Tailscale
# prefers the first duplicate flag defined, not the most recent...

mkdir /etc/systemd/system/tailscaled.service.d
echo '[Service]' > /etc/systemd/system/tailscaled.service.d/override.conf
echo 'ExecStart=' >> /etc/systemd/system/tailscaled.service.d/override.conf
echo 'ExecStart=/usr/sbin/tailscaled --socket=/run/tailscale/tailscaled.sock --port=${PORT} $FLAGS' >> /etc/systemd/system/tailscaled.service.d/override.conf

systemctl daemon-reload
systemctl restart tailscaled.service

# Add to `tailscale-files.sh`:
echo 'mp0: /zfs/lxc/tailscale/persist,mp=/persist' | tee -a /etc/pve/lxc/${1}.conf
</code></pre>

Now when I delete and recreate the container it proper re-registers as the same, existing machine in the Tailscale dashboard. Testing seems good so now the last step is migrating the Prod container.

I took a manual backup for good luck (PVE->CT101->Backup->Backup Now) then let it fly:
<pre><code>
pct shutdown 111
rm -r /zfs/lxc/tailscale/persist/tailscale/*
vim /zfs/lxc/tailscale/about.sh
	-> edit non-conflicting IP addresses to intended IP addresses
	-> edit hostname to intended hostname
/opt/pve-new-ct.sh 101 tailscale
</code></pre>

While this was in the middle of building I went ahead and deleted the old machine from Tailscale's dashboard. This is easier than trying to migrate state when there is really nothing important to migrate. 

After a few minutes it finished installation and popped up in the dashboard:
<picture>
	<img src="images/blogs/pve_scripting/4-tailscale_setup_complete.png" alt="A screenshot of the Tailscale dashboard showing the new container fully functional.">
</picture>

## 7. Extra: Hacking the PVE GUI
I like using the Proxmox GUI (I know, I know), so I figured it might be fun to try and hack on it to insert my own custom button for this script.

Looking online, some people have done similar things but not quite adding custom functionality: https://lunar.computer/news/customize-proxmox-60/

Before worrying about persistence I should try and get it working. Starting with the [source code](https://github.com/proxmox/pve-manager/tree/master) I was able to browse to [these lines](https://github.com/proxmox/pve-manager/blob/master/www/manager6/lxc/Config.js#L112-L167):
<pre><code>
Ext.define('PVE.lxc.Config', {
...
	var moreBtn = Ext.create('Proxmox.button.Button', {
	    text: gettext('More'),
	    menu: {
 items: [
		{
		    text: gettext('Clone'),
		    iconCls: 'fa fa-fw fa-clone',
		    hidden: !caps.vms['VM.Clone'],
		    handler: function() {
			PVE.window.Clone.wrap(nodename, vmid, template, 'lxc');
		    },
		},
		{
...
</code></pre>

This looks like where the "More" dropdown for LXC containers is defined, which seems like a perfect place to add my own button. 

Scouring around my local install it seems like all of these JS files get compiled into `/usr/share/pve-manager/js/pvemanagerlib.js`. Editing that file around line `34445` (Your mileage may vary...) I found the exact same code as above. 

Adding my own `item` element worked very easily:
<picture>
	<img src="images/blogs/pve_scripting/5-pve_add_button.png" alt="The custom button added to Proxmox showing up in the GUI.">
</picture>

<aside>
You don't even need to restart the web service for this, just a refresh of the page.
</aside>

This is what I ended up with:
<pre><code>
                {
                    text: gettext('Rebuild Container'),
                    disabled: template,
                    xtype: 'pveMenuItem',
                    iconCls: 'fa fa-terminal',
                    hidden: false,
                    confirmMsg: 'Are you sure?',
                    handler: function() {
                        Proxmox.Utils.API2Request({
                            url: base_url + '/template',
                            waitMsgTarget: me,
                            method: 'POST',
                            failure: function(response, opts) {
                                Ext.Msg.alert('Error', response.htmlStatus);
                            },
                        });
                    },
                },
</code></pre>

This adds a button, but you may notice the `handler:` looks a bit off. This is where I got stuck. Somehow, you want this button to register and run a script on the server (`/opt/pve-new-ct.sh $CT_ID $CT_NAME`). I'm guessing you'll need to determine where exactly the API is defined and add a new API endpoint specifically for this action, possibly even adding it as a job that gets shown with a proper status and everything.

That is a lot more work than I'm willing to entertain right now, so this is where I'll leave it. There very well may be an easier way to hack this together without all of that footwork, but I wasn't able to figure one out quite yet. 

# Conclusion
After all of this work I've accomplished the following:
<ol>
	<li>Learn a bit more about managing Proxmox via `pct`</li>
	<li>Script some basic `lxc` creation, backups, and deletion</li>
	<li>Build out shared scripting for common setup actions I was copy-pasting (auto updates, SSH, and email alerting)</li>
	<li>Put it all together and fully "define" one of my containers</li>
</ol>

Hopefully some of this will be helpful, or at the very least interesting. I don't endorse blindly copying my hackjob scripts but if you're looking to do something similar and want some inspiration feel free. 

---
title: Aidan Houck - Blog - NixOS Raspberry Pi Quickstart
subtitle: State Shmate
date: 2025-01-01
---

# Introduction
[NixOS](https://nixos.org/), if you're not familiar, is a neat project. Many people have explained it [way better than I can](https://www.youtube.com/watch?v=5D3nUU1OVx8) but in short it enables defining your entire system via config files, dynamically rebuilding and falling back as you make changes, with everything permanently tracked and reverseable through a git repo. 

The main downside is the inherent complexity that comes with so much power, plus the added unnecessary complexity of the arcane Nix language. I plan to get my feet wet by "diving into the deep end," but on my spare Raspberry Pi which is a non-critical system. 

## Image Setup
There is much documentation on how to specifically setup a Raspberry Pi 4 with NixOS (including the [official Wiki](https://nixos.wiki/wiki/NixOS_on_ARM/Raspberry_Pi_4) and [a writeup from Michael Lynch](https://mtlynch.io/nixos-pi4/) that read thoroughly) so I'll keep this brief.

First, download the shell if using a non-NixOS system for setting the image up:
```bash
sh <(curl -L https://nixos.org/nix/install) --no-daemon
. ~/.nix-profile/etc/profile.d/nix.sh
```

Download and decompress the latest `.img` file from NixOS.org's [hydra](https://nixos.wiki/wiki/NixOS_on_ARM#Installation) CI system:
```bash
mkdir /tmp/pinix
cd /tmp/pinix
wget https://hydra.nixos.org/build/281550993/download/1/nixos-sd-image-24.05.7013.7109b680d161-aarch64-linux.img.zst
nix-shell -p zstd --run "unzstd $ls *.img.zst)"
```

Next I need access to a USB which is [annoying to do](https://learn.microsoft.com/en-us/windows/wsl/connect-usb) in WSL2, so I transferred the image to my Proxmox machine.
```bash
cp nixos-sd-image-24.05.7013.7109b680d161-aarch64-linux.img houck@pve.lan.aidanhouck.com:/zfs/backups/rpi/
```

Finally format the SD card in the USB reader.
```bash
sudo dmesg | tail -n20
// -> search for dev name after it was plugged in, mine was `sdc`

// Unmount
sudo umount /dev/sdc

// Backup existing image (a working Rasbian image, just in case)
mkdir -p /zfs/backups/rpi
cd /zfs/backups/rpi
sudo dd if=/dev/sdc of=~/20241210-rasbian-backup-before-nixos.img bs=4M status=progress

// Copy NixOS to card
sudo dd if=nixos-sd-image-24.05.7013.7109b680d161-aarch64-linux.img of=/dev/sdc bs=4M status=progress
```

## Booting NixOS
After plugging in the SD card and trying to boot it eventually hangs with the following:
```bash
Failed to open device: scard' (cmd
371a0010 status 1fff0001)
Failed to open device: 'scard' (cmd 371a0010 status 1fff0001)
```

I haven't used this Pi in a while so I figured updating the boot loader wouldn't hurt, in case some things had changed recently. 
<ol>
	<li>Download and install the [Pi imager software]()</li>
	<li>Follow the [docs](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#bootloader_update_stable) to update the boot loader with the Boot Loader Updater (how convenient!)</li>
	<li>This gives me the same error...</li>
	<li>Re-flash the SD card for the third time with latest headless raspbian</li>
	<li>This boots successfully and I can follow the docs for [updating the bootloader within Raspbian](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#update-the-bootloader-configuration)</li>
	<li>After that's done re-flash my SD card for a fourth time with the NixOS image... now it boots succesfully and we have a terminal prompt!</li>
</ol>

# NixOS
## Initial Setup
Now we're booted into NixOS but with no internet connection. Wifi setup involved an annoying amount of trial and error but what ended up working wasn't that bad:
```bash
wpa_passphrase SSIDNameGoesHere >~/passphrase.txt
	-> SSID PSK goes in stdin
sudo wpa_supplicant -B -i wlan0 -c passphrase.txt
sudo reboot // Not sure why I needed to do this but I was getting errors accessing the wlan0 device until I did. 
```

Then add my main machine's public keys to authorize SSH:
```bash
GITHUB_USERNAME="AidanHouck"
mkdir -p ~/.ssh && \
  curl "https://github.com/${GITHUB_USERNAME}.keys" > ~/.ssh/authorized_keys
```

Now SSH works and I can resume configuration from my desk (until I break something):
```bash
$ ssh nixos@192.168.20.88
Last login: Wed Dec  6 21:22:10 2023

[nixos@nixos:~]$ uname -a
Linux nixos 6.6.63 #1-NixOS SMP Fri Nov 22 14:38:37 UTC 2024 aarch64 GNU/Linux
```

Including running Raspberry Pi updates from NixOS as recommended by the docs. Not sure if they still need updates after the bootloader was updated in Raspbian but it can't hurt:
```bash
sudo nix-shell -p raspberrypi-eeprom
sudo mount /dev/disk/by-label/FIRMWARE /mnt
sudo BOOTFS=/mnt FIRMWARE_RELEASE_STATUS=stable rpi-eeprom-update -d -a
```

## Initial configuration
I decided to start with a template somebody else had made for their Raspberry Pi since it seemed to have some useful options. See that post [here](https://nix.dev/tutorials/nixos/installing-nixos-on-a-raspberry-pi)
```bash
sudo bash -i
curl -L https://tinyurl.com/tutorial-nixos-install-rpi4 > /etc/nixos/configuration.nix

// Update some defaults like hostname and user
vim /etc/nixos/configuration.nix

// Rebuild and reboot
nixos-rebuild boot
reboot
```

I know Nix's store can use an oddly high amount of disk space, but it seemed to be OK for the time being.
```bash
[houck@nixpi:~]$ du -ch /nix/store/* | tail -n1
3.0G    total

[houck@nixpi:~]$ df -h
Filesystem                   Size  Used Avail Use% Mounted on
devtmpfs                     190M     0  190M   0% /dev
tmpfs                        1.9G     0  1.9G   0% /dev/shm
tmpfs                        946M  3.5M  942M   1% /run
tmpfs                        1.9G  1.2M  1.9G   1% /run/wrappers
/dev/disk/by-label/NIXOS_SD   30G  3.3G   25G  12% /
tmpfs                        379M  4.0K  379M   1% /run/user/1001
```

Now that we have a fancy `configuration.nix` I can make changes like so:
```bash
$ echo $EDITOR
nano

$ sudo vim /etc/nixos/configuration.nix
// add environment.variables.EDITOR = "vim";

$ sudo nixos-rebuild switch

$ exit
$ ctrl+r ssh

$ echo $EDITOR
vim
```

## Hardware configuration
I'm not sure how necessary this is since one did not get auto-generated, but most people seem to use a `hardware-configuration.nix` file in addition to their base `configuration.nix` file. I went ahead and generated one:
```bash
sudo nixos-generate-config --show-hardware-config >| /etc/nixos/hardware-configuration.nix
```

Then edited `/etc/nixos/configuration.nix` to reference it.
```nixos
  imports = [
    ./hardware-configuration.nix
  ];
```

And tried to rebuild:
```bash
sudo nixos-rebuild switch
```

This gave me an error with a pretty easy fix:
```bash
error: The option `fileSystems."/".device' has conflicting definition values:
       - In `/etc/nixos/configuration.nix': "/dev/disk/by-label/NIXOS_SD"
       - In `/etc/nixos/hardware-configuration.nix': "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888"
       Use `lib.mkForce value` or `lib.mkDefault value` to change the priority on any of these definitions.
```

I edited `configuration.nix` with `lib.mkForce` as recommended and that worked:
```nixos
device = lib.mkForce "/dev/disk/by-label/NIXOS_SD";
```

## Flakes
[Flakes](https://wiki.nixos.org/wiki/Flakes) are a relatively new and "experimental" addition to Nix. They should be added cautiously since breaking changes are not impossible, however, flakes seem to be gaining more and more traction [and many people espose their benefits](https://jade.fyi/blog/flakes-arent-real/). This is compelling enough for me so I wanted to give it a shot (you can always un-flake later).

Flakes add a `flake.nix` file which lets you define inputs (such as the Nix packages repo) and outputs (such as machine1 configuration). They also add an auto-generated `flake.lock` file which records all inputs, their hash values, and their relevant version numbers. This enables easier complete reproducability as all inputs are pinned _by default_ to specific revisions, usually the individual git commit.

It's worth noting both of these files are merely wrappers around existing Nix utilities (such as `nix-channel` for managing inputs), but they seem to have saner and more reproducable defaults than plain Nix does.

The other experimental feature added around the same time is `nix-command` (see: [nixos.wiki](https://nixos.wiki/wiki/Nix_command)) which attempts to create a more unified/intuitive API for many common Nix operations. `nix-shell` -> `nix shell / nix develop / nix run`, `nix-build` -> `nix build`, etc. I'm not too familiar with what all this entails but I always see people suggest enabling `flakes` and `nix-command` at the same time so that is exactly what I did.

Edit `/etc/nixos/configuration.nix` to add the experimental features:
```nixos
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

After a `sudo nixos-rebuild switch` your system can now use flakes. You can use the following to skim around an example flake file:
```bash
nix flake init -t templates#full
more flake.nix
rm flake.nix
```

I created a basic `flake.nix` like so:
```nixos
sudo bash -i
cat <<"EOT" >/etc/nixos/flake.nix
{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations.nixpi = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        # Import the previous configuration.nix
        ./configuration.nix
      ];
    };
  };
}
EOT
```

Now after another `sudo nixos-rebuild switch` a `flake.lock` file was created:
```bash
[houck@nixpi:~]$ ll /etc/nixos
total 16
-rw-r--r-- 1 root root 1728 Dec 11 02:36 configuration.nix
-rw-r--r-- 1 root root  564 Dec 11 02:57 flake.lock
-rw-r--r-- 1 root root  368 Dec 11 02:54 flake.nix
-rw-r--r-- 1 root root 1196 Dec 11 02:25 hardware-configuration.nix
```

<ol>
	<li>`configuration.nix`: The original non-flake config file with all of my packages, changes, etc</li>
	<li>`hardware-configuration.nix`: Generated config file specific for this machine</li>
	<li>`flake.nix`: A thin wrapper around `configuration.nix` that serves as an entry point for the flake</li>
	<li>`flake.lock`: Automatically generated version lock file for all flake _inputs_ to ensure reproducability</li>
</ol>

Overall I'm feeling somewhat confident in my knowledge of what is going on and how to manage this system. I have a decent idea of what files are doing what, and how they interact with eachother. The next step is adding version control via `git` so my configurations are tracked and can be instantly reproduced on any other devices.

## Creating a git Repository
I created a new repo for this: [github:AidanHouck/nix-config](https://github.com/AidanHouck/nix-config)

Then basic init:
```bash
nix-shell -p git
mkdir -p ~/src
cd ~/src
git clone https://github.com/AidanHouck/nix-config
```

And copy over my files for the initial commit.
```bash
echo "Hello World" > README.md
git add . && git commit

cp /etc/nixos/* ~/src/nix-config
git add . && git commit
```

See the inital repo state I arrive at in [this commit](https://github.com/AidanHouck/nix-config/tree/ce43fdb79ad086b0e0501a2696bdc6573661cfcc).

A symlink can also be used to place my `flake.nix` file where it is searched for by default:
```bash
sudo ln -s ~/src/nix-config/flake.nix /etc/nixos/flake.nix
```

This means I can continue using `sudo nixos-rebuild switch` instead of being forced to do `sudo nixos-rebuild switch --flake ~/src/nix-config/flake.nix#hostname` every time I want to rebuild. 

Now in order to update any machine using this config all I need to do is pull latest changes and rebuild:
```bash
cd ~/src/nix-config
git pull

sudo nixos-rebuild switch
```

## Secret Management
If you browsed around that git commit you may have noticed the lines like `password = "FooBar";` and `SSIDpassword = "FooBar";`. That's because I, of course, don't want to commit any passwords to a permanent `git` repo's history.

There are multiple capable tools for doing this properly, namely [agenix](https://github.com/ryantm/agenix) and [sops-nix](https://github.com/Mic92/sops-nix/). I couldn't really tell which would be better for me so I just picked `sops-nix` mostly at random. 

SOPS can work in a number of different ways, but using SSH keys seemed the easiest to me as all of my machines will use SSH. First, generate a new key (if one doesn't exist already)
```bash
sh-keygen -t ed25519
cat ~/.ssh/id_ed25519.pub
// Add to https://github.com/settings/keys
```

Then, use that key to create equivalent `age` keys used by SOPS:
```bash
mkdir -p ~/.config/sops/age
sudo nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt"
```

Make sure to grab the `age` public key which will be used to decide who is allowed to decrypt your secrets:
```bash
nix-shell -p ssh-to-age --run "ssh-to-age < ~/.ssh/id_ed25519.pub"
```

Create a basic `.sops.yaml` file:
```yaml
keys:
  - &host age184zg0rfghppepg2lkev6hzmauvtz6wnnftkt4uwpdgm8rukm6y7szj7qff
creation_rules:
  - path_regex: secrets/secrets.yaml$
    key_groups:
      - age:
        - *host
```

Where `- &host <KEY>` is your `age` public key and any identifier (I chose to use my hostname), `path_regex:` leads to the file that will be encrypted, and `*host` is the identifier for which public keys should be allowed to decrypt that specific file. You can add multiple files, regex rules (e.g. `secrets/host1/*`, `secrets/host2/*`), and public keys in the future if you want more granularity.

For now this is fine and we can create the encrypted file:
```bash
mkdir -p secrets && cd secrets
nix-shell -p sops --run "sops secrets/secrets.yaml"
```

This encrypted yaml file looks something like this:
```bash
houck_pass_hash: HASHGOESHERE
wireless.env: |
    home_uuid=SSID
    home_psk=PSK
```

And the configuration you need to add looks something like this (Note the extra steps for user passwords [as documented](https://github.com/Mic92/sops-nix?tab=readme-ov-file#setting-a-users-password)):
```nixos
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];
  sops.defaultSopsFile = ../secrets/secrets.yaml;
  sops.defaultSopsFormat = "yaml";
  sops.age.keyFile = "/home/houck/.config/sops/age/keys.txt";
  sops.secrets."wireless.env" = { };

  // If you're setting up Wifi this only works on 24.05, 24.11 and
  // newer use a different (easier) syntax for wlan config and you
  // can simply define a standard file in your `secrets.yaml` file.
  // Example: https://github.com/AidanHouck/nix-config/commit/ce5f6c0d797b4cf212a2102f848e7710578caf03
  wireless = {
    enable = true;
    networks."${SSID}".psk = SSIDpassword;
    environmentFile = config.sops.secrets."wireless.env".path;
    networks = {
  	"@home_uuid@" = {
  	  psk = "@home_psk@";
      };
  };

  sops.secrets."houck".neededForUsers = true;
  users = {
    mutableUsers = false;
    users.houck = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets."houck_pass_hash".path;
```

If you ever need to add more public keys to `.sops.yaml` (like another machine) be sure to re-encrypt the file with the updated keys:
```bash
sops updatekeys secrets/secrets.yaml
```

After another `sudo nixos-rebuild switch` WLAN config is auto populated, correct expanded from the variables, the new is created and with the proper password. All stored securely and in `git`. 

# Conclusion
Now I have a single host with reproducable config defined by one or more `*.nix` files all encompassed in a single `flake.nix` entry point. All config is controlled on `git` and can be pulled from the cloud then installed on any machine in only a few commands.

There is plenty left that could be added, optimized, or expanded upon, however that is where I'll leave this blog for now. Below is an incomplete list of resources I used in no particular order, if you feel the urge to blow away your system and dive head-first into NixOS then hopefully they will help :^).

<ol>
	<li>[NixOS Wiki](https://nixos.wiki/wiki/Main_Page)</li>
	<li>[Nix Language Basics](https://nix.dev/tutorials/nix-language)</li> 
	<li>[NixOS and Flakes Book](https://nixos-and-flakes.thiscute.world/preface)</li>
	<li>[Nix explained from the ground up](https://www.youtube.com/watch?v=5D3nUU1OVx8)</li>
	<li>[Ultimate NixOS Guide](https://www.youtube.com/watch?v=a67Sv4Mbxmc)</li>
	<li>[NixOS Packages & Options Search](https://search.nixos.org/packages)</li>
	<li>[Misterio77's nix-starter-configs](https://github.com/Misterio77/nix-starter-configs)</li>
	<li>[Nixpkgs Source Code](https://github.com/NixOS/nixpkgs/)</li>
	<li>[ryan4yin's nix-config repo](https://github.com/ryan4yin/nix-config)</li>
	<li>[An older (simpler) revision of ryan4yin's nix-config repo](https://github.com/ryan4yin/nix-config/tree/i3-kickstarter)</li>
</ol>


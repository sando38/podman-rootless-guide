#!/bin/sh
# https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md

##Get root permission##

## Uncomment line below to allow debugging:
#set -x

## General variables ##
inet_dev='eth0'
nftables_config='/etc/nftables.conf'
# User that will run the pods/containers:
users='podman'
# Rootful (0) or rootless (1) install. Default (1) recommended.
rootless='1'

apt update && apt-get update && apt upgrade -y
apt install -y nftables \
               sudo \
               fuse-overlayfs

echo "## Only enable temporarily as these are testing repositories that could break the system!!
deb http://deb.debian.org/debian testing main non-free contrib
deb http://deb.debian.org/debian unstable main non-free contrib" >> /etc/apt/sources.list

apt update && apt-get update
apt-get -y -f install libsemanage-common
apt install -y podman/testing \
               slirp4netns/testing \
               aardvark-dns

sed -i '/testing/d' /etc/apt/sources.list
sed -i '/unstable/d' /etc/apt/sources.list

apt update && apt-get update
apt -y autoremove && apt -y autoclean && apt -y clean

systemctl --now enable systemd-networkd
systemctl --now start systemd-networkd

# Remove existing .bashrc and add variables to get podman working.
rm -rf /home/$users/.bashrc
touch /home/$users/.bashrc
echo "export XDG_RUNTIME_DIR=/run/user/$(id -u $users)
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $users)/bus
export DOCKER_HOST=unix:///run/user/$(id -u $users)/podman/podman.sock" >> /home/$users/.bashrc


# enable user namespaces (cgroup)
if [ "$rootless -eq 1" ]; then
  # enable user namespaces (cgroup)
  if grep -q user_namespace.enable=1 /etc/default/grub; then
    echo "user_namespace already enabled in grub2"
  else
    if grep -q user_namespace.enable=0 /etc/default/grub; then
      sed -i 's/user_namespace.enable=0/user_namespace.enable=1/g' /etc/default/grub
      grub-mkconfig -o /boot/grub/grub.cfg
    else
      sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="user_namespace.enable=1 /g' /etc/default/grub
      grub-mkconfig -o /boot/grub/grub.cfg
    fi
  fi
fi

# enable binfmt to emulated foreign architectures
systemctl start systemd-binfmt.service

# https://wiki.archlinux.org/title/Podman
sysctl kernel.unprivileged_userns_clone=1

for user in $users
do
  uid="$(id -u $user)"
  # keep rootless users logged in to prevent container stops
  loginctl enable-linger $uid

  # add /etc/subuid and /etc/subgid configuration
  rm -f /etc/subuid /etc/subgid
  echo "$user:${uid}000:65536" >> /etc/subuid
  echo "$user:${uid}000:65536" >> /etc/subgid
  ## alternative:
  ## $ usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $user

  # create user directories
  mkdir -p /home/$user/.config/systemd/user/
  mkdir -p /home/$user/.config/containers
  #cp /usr/share/containers/{containers.conf,storage.conf} \
  #    /home/$user/.config/containers
  chown -R $user /home/$user/.config
done

# activate subuid and subgid changes
podman system migrate

# https://github.com/lxc/lxd/issues/3397#issuecomment-307632741
chmod +s /usr/bin/newuidmap
chmod +s /usr/bin/newgidmap

# enable binding to privileged ports
lowest_port='0'
echo "net.ipv4.ip_unprivileged_port_start=$lowest_port" > /etc/sysctl.d/40-privilegedPorts.conf
sysctl -p /etc/sysctl.d/40-privilegedPorts.conf

# enable unpriviledged ping
max_gid='2147483647'
echo "net.ipv4.ping_group_range=0 $max_gid" > /etc/sysctl.d/50-podman-unpriviledged-ping.conf
sysctl -p /etc/sysctl.d/50-podman-unpriviledged-ping.conf

# prepare host nftables and Co.
# https://linux-audit.com/nftables-beginners-guide-to-traffic-filtering/
## replace default nftables.conf
cp $nftables_config /etc/nftables.conf.backup
nft -f $nftables_config

### to make it work, the host has to have routing enabled
cat > /etc/sysctl.d/30-ipforward.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl -p /etc/sysctl.d/30-ipforward.conf

### REDIS: Memory overcommit must be enabled! Without it, a background save or
### replication may fail under low memory condition. Being disabled, it can can
### also cause failures without low memory condition,
### see https://github.com/jemalloc/jemalloc/issues/1328.
cat > /etc/sysctl.d/35-vm-overcommit-memory.conf <<EOF
vm.overcommit_memory = 1
EOF
sysctl -p /etc/sysctl.d/35-vm-overcommit-memory.conf

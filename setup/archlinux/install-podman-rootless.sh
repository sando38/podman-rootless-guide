#!/bin/sh
# https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md

# general variables
inet_dev='eth0'
nftables_config='/etc/nftables.conf'
users='iamgroot'
rootless='1'
# ArchLinux packages
qemu_pkgs='qemu-user-static qemu-user-static-binfmt'
rootless_pkgs='slirp4netns'


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

# install podman and relevant packages
pacman -S --noconfirm \
      aardvark-dns \
      podman \
      $qemu_pkgs \
      $rootless_pkgs

# enable binfmt to emulated foreign architectures
systemctl start systemd-binfmt.service

# https://wiki.archlinux.org/title/Podman
sysctl kernel.unprivileged_userns_clone=1

# we can use native overlays with Arch -> Linux Kernel > 5.11 :)
#files=$(find / -name storage.conf)
#for file in $files
#do
#    sed -i 's|#mount_program = "/usr/bin/fuse-overlayfs"|mount_program = "/usr/bin/fuse-overlayfs"|' $file
#done
#sed -i 's|#mount_program = "/usr/bin/fuse-overlayfs"|mount_program = "/usr/bin/fuse-overlayfs"|' \
#        /etc/containers/storage.conf
# after reboot
#modprobe fuse

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

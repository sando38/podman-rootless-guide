# Requirements

Archlinux has pretty much all tools up-to-date. Therefore, a clean setup should
work in all cases.

## Software used

For networking:

* `systemd-networkd` (should be enabled as default)
* `iptables-nft` (must be installed, remove legacy `iptables` as well)


## add your users to SUDOers

* e.g. by adding them the group `wheel`
* enabling password-less `sudo` through uncommenting this part in `/etc/sudoers`

```console
EDITOR=VIM visudo
...
## Same thing without a password
# %wheel ALL=(ALL:ALL) NOPASSWD: ALL
...
```

This change saves you some password typing. If you are done with your setup,
your user running podman does not need any sudo rights anymore, unless you need
to create a new pod and, hence, the network bridge.

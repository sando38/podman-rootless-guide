# Podman rootless guide

> Disclaimer: You are using these examples at your own risk. Check the scripts
before applying them. Don't run random scripts of random people from the WWW. If
you see any room of improvements, the maintainers are happy to include them.
> It is recommended to apply the examples from this repository on a clean
machine

This repository is meant to contain example setups for podman rootless container
stacks. It should help users to achieve their goal in creating container stacks
which

* run rootless
* have minimized associated performance impacts (e.g. through [custom
networking](https://podman.io/community/meeting/notes/2021-10-05/Podman-Rootless-Networking.pdf))
* are configured healthy in terms of e.g. linux capabilities, etc.

It aims to provide example scripts for different operating systems how to setup
podman rootless correctly.

It will also explain some drawbacks with workarounds, however, there may be more
elegant solutions. PRs are welcome.

## Structure of the repository

The [setup](setup) directory contains the scripts to install podman rootless on
the various operating systems. The sections also include the parameters of the
systems which run with the setup, e.g. OS version, Linux Kernel, Podman version,
etc.

The [setup](setup) directory contains an `nftables.conf.example` ruleset
tailored to the solutions presented in this repository.

The [container](container) directory has examples of various scripts on how to
setup various applications with pods/containers.

## How to start

Be aware this repo cannot provide "ready-to-use" scripts, because most likely
you need a customized solution, e.g. you may not have an IPv6 address, etc.

The easiest way is to clone this repository first:

    git clone https://github.com/sando38/podman-rootless-guide

Afterwards do your changes in the different files. Generally, you need to follow
the following steps which can be achieved with the example scripts:

* setup your machine to run podman rootless (see examples in [setup](setup))
    * install relevant packages
    * enable users
    * grant them `sudo` rights
* adjust your nftables (or iptables or else) rules
    * IPv4 and/or IPv6 necessary
    * Adjust the network ranges
    * Check the ports you want to forward to the respective pods/containers
    * Most services are commented (e.g. STUN/TURN, XMPP)
* customize the applications to fit your needs, each application directory is
structured like
    * the root containing the `start.sh` script
    * `appdata` containing the relevant data, e.g. for persistence, configs

## Some further hints and potential challenges on the path

In the root of the applications directory are two files `pod.conf` and
`resolv.conf`. `pod.conf` is used to determine a custom IP address for the
respective pod, e.g. database pod. The pods' numbers must match the ones defined
in the `nftables.conf.example` ruleset.

`resolve.conf` is used to be mounted into the
containers, because the pods and, hence, containers are started with the flag
`--net=none`. Therefore, they do not always have the DNS service IPs at hand and
will fail to query public addresses, if they do not have them. `resolve.conf`
currently contains the IP addresses from Cloudflare's [DNS services](https://one.one.one.one/dns/).
Change those if wanted.

The custom network stack also relies very much on the `hosts` file, which should
be appended to the one on your host machine in `/etc/hosts`. If a service calls
another service via there public address, e.g. `https://example.com` it should
point to the respective IP address of the pod listening for that address - this
is most likely the reverse proxy. The IP addresses must also match the ones
defined in the `nftables` ruleset. This may be a limitation of the current setup
and a more clever approach could work. In that case please create a PR.

In the application directory is a folder called `secrets` which contains
credentials and else to be included as `podman secrets` into the running
containers. Do check permissions, so that they are protected against unwanted
readers.

## Podman rootless and volume mounts/file permissions

This is a special topic and important, that everythings works as desired. As we
run in rootless environments, `podman rootless` uses user-namespaces. To be very
basic, in a user-namespace your user running podman e.g. with `uid=1000` is
"root" with `uid=0`. This is okay, if all containers run as `root`. Then mapping
the users directories as volumes into the container is working.

However, images exists, which have custom users, e.g. `uid=9000` like
`ghcr.io/processone/ejabberd`. In that case the normal way would be to `chown`
the directories on the host machine to match `uid=9000`, however, in rootless
environments this does not match the `uid` in the respective user's namespace.

The magic command in this is case is called:

    podman unshare chown 9000:9000 /path/to/ejabberd-volume

More information [here](https://github.com/processone/eturnal/tree/master/docker-k8s#rootless-environments).

Most of the application scripts change file permissions of the mounted volumes
before container start to match the defined `uid`s.

## Some notes to the example applications provided

Currently the stack relies on `traefik` as a reverse proxy for most internet
facing services. This may be desired or not.

In `applications/traefik/appdata/rules` are the ingress rules defined for the
respective services. Please adjust them to your need. To route traffic to other
pods only the pod name is necessary, e.g. `database`.


## Not covered yet

* Backup solutions, however this could be easily done by dumping the application
folders by a cronjob and save them to your backup storage
* Persistence in case of reboot - currently no persistence is established, so in
case of a reboot, each service must be started again by executing the respective
`start.sh` script
    * this could be achieved e.g. by systemd units


## Known issues (help wanted)

When running custom nftables rules, rootful podman does not work anymore,
because of [netavark](https://github.com/containers/netavark) not being able to
set masquerade rules.

```console
# podman run --rm -it alpine sh
Error: netavark: unable to append rule '! -d 224.0.0.0/4 -j MASQUERADE' to table 'nat': code: 4, msg: Warning: Extension MASQUERADE revision 0 not supported, missing kernel module?
iptables v1.8.9 (nf_tables):  RULE_APPEND failed (No such file or directory): rule in chain NETAVARK-1D8721804F16F
```

Currently pods are not isolated, because they are all part of the network bridge
subnet, hence they can communicate with each other. Creating custom bridges for
every pod lead to very slow networking performance. This could be definitely
improved.

Cosmetics are also welcome, especially as the nftables ruleset and the stack for
IPv6 related networking still uses NAT which is in theory not necessary.

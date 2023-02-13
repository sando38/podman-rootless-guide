# Configuration examples for various appications

This folder hosts the different configuration examples of various apps. Each
script contains some variables which can be defined. Most variables should be
fine though already.

Each application contains a `startup.sh` script which:

* checks for the existence of a pod (and creates one)
* checks for the existence of a network bridge (and creates one)
* handles file permissions
* build, start container images and link them into the pods

The scripts needs to know the location of the files, e.g. for volume mounts,
secrets, etc.

The scripts assume that the repository is cloned in the user's home directory.
Otherwise you could define the variable `ROOT_DIR='/path/to/applications'` to
overwrite that setting.

To start an application do:

```console
export ROOT_DIR='/path/to/podman-rootless-guide/applications'
chmod +x $ROOT_DIR/traefik/startup.sh
$ROOT_DIR/traefik/startup.sh
```

Make sure you have checked the applications' scripts beforehand to fit your
needs.

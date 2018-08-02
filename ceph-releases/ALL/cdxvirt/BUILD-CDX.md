# Build mimic cdxvirt ubuntu

## Make Dockerfile from mimic-ubuntu-16.04
```
echo "VSDX" > src/__DOCKERFILE_MAINTAINER__
make stage FLAVORS=mimic,ubuntu,16.04
ls staging/mimic-ubuntu-16.04-x86_64/daemon-base/Dockerfile
ls staging/mimic-ubuntu-16.04-x86_64/daemon/Dockerfile
```
## Prepare files
```
$ mkdir -p ceph-releases/ALL/cdxvirt/ubuntu/daemon{,-base}
PUT ceph-releases/ALL/cdxvirt/ubuntu/daemon-base/Dockerfile
PUT ceph-releases/ALL/cdxvirt/ubuntu/daemon/Dockerfile
PUT cdx directory into ceph-releases/ALL/cdxvirt/ubuntu/daemon
```
## Build Images
```
make build FLAVORS=mimic,cdxvirt,ubuntu
```

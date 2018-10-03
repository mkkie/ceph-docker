# CDXvirt Ceph Daemon
---
## How to Build ?
### With Ceph Daemon Builder
For building a ceph-daemon, we need "make" & "python" commands.
Hence, this is a good choice to build images by a specific container.
[BUILDER.md](BUILDER.md)

```
# CMD="make build FLAVORS=mimic,cdxvirt,ubuntu-ceph-base"
git clone https://github.com/cdxvirt/ceph-docker.git -b branch ~/ceph-container
cd ~/ceph-container/ceph-releases/ALL/cdxvirt
SRC_PATH=~/ceph-container ./ceph-daemon-builder.sh ${CMD}
```
## Ubuntu 16.04 Base
```
docker build -t cdxvirt/ubuntu-ceph-base -f Dockerfile.ubuntu-ceph-base .
make build FLAVORS=mimic,cdxvirt,ubuntu-ceph-base DAEMON_TAG=cdxvirt-ceph-daemon
docker tag ceph/cdxvirt-ceph-daemon:latest cdxvirt/ceph-daemon
```
## CDXvirt Base
```
make build FLAVORS=mimic,cdxvirt,ceph-base DAEMON_TAG=cdxvirt-ceph-daemon
docker tag ceph/cdxvirt-ceph-daemon:latest cdxvirt/ceph-daemon
```

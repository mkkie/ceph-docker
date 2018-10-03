# CDXvirt Ceph Daemon
---
## How to Build ?
### Make a Ceph Daemon Builder
For building a ceph-daemon, we need "make" & "python" commands.
Hence, this is a good choice to build images by a specific container.
[BUILDER.md](BUILDER.md)

### Ubuntu 16.04 Base
Build ceph-daemon ubuntu:16.04 first.
```
# BUILD_CMD="make build FLAVORS=mimic,ubuntu,16.04 DAEMON_BASE_TAG=daemon-base DAEMON_TAG=daemon"
$ git clone https://github.com/cdxvirt/ceph-docker.git -b branch ~/ceph-container
$ cd ~/ceph-container/ceph-releases/ALL/cdxvirt
$ SRC_PATH=~/ceph-container ./ceph-daemon-builder.sh ${BUILD_CMD}
$ docker tag ceph/daemon cdxvirt/ceph-base
```
Let ceph/daemon as a base image, rebuild a new ceph-daemon.
```
$ cd ~/ceph-container/ceph-releases/ALL/cdxvirt/daemon
$ UBUNTU_BASE="cdxvirt/ceph-base"
$ CEPH_DAEMON="cdxvirt/ceph-daemon"
$ sed "s#@UBUNTU_BASE_IMG@#${UBUNTU_BASE}#" Dockerfile.ubuntu-base | docker build -t ${CEPH_DAEMON} -f - .
```
## CDXvirt Base
```
$ cd ~/ceph-container/ceph-releases/ALL/cdxvirt/daemon
$ CDXVIRT_BASE="cdxvirt/ceph-base:mini"
$ CEPH_DAEMON="cdxvirt/ceph-daemon:mini"
$ sed "s#@CDXVIRT_BASE_IMG@#${CDXVIRT_BASE}#" Dockerfile.cdxvirt-base | docker build -t ${CEPH_DAEMON} -f -  .
```

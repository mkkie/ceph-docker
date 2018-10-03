# Ceph Daemon Builder
## Create a builder
```
docker build -t cdxvirt/ceph-daemon-builder -f Dockerfile.builder .
```
## Build the Ceph container
```
git clone https://github.com/cdxvirt/ceph-docker.git ~/ceph-container
SRC_PATH=~/ceph-container
docker run -it --privileged \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /run/torcx/unpack/docker/bin/docker:/bin/docker \
-v /run/torcx/unpack/docker/lib:/host/lib \
-v ${SRC_PATH}:/ceph-container \
cdxvirt/ceph-daemon-builder
```
e.g.
```
make build FLAVORS=mimic,ubuntu,16.04
```

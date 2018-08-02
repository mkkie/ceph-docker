# Ceph Container builder
## Create a builder
```
docker build -t cdxvirt/ceph-container-builder -f Dockerfile.builder .
```
## Build the Ceph container
```
git clone https://github.com/ceph/ceph-container.git
SRC_PATH=/home/core/ceph-container
docker run -it --privileged \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /run/torcx/unpack/docker/bin/docker:/bin/docker \
-v /run/torcx/unpack/docker/lib:/host/lib \
-v ${SRC_PATH}:/ceph-container \
cdxvirt/ceph-container-builder
```
e.g.
```
make build FLAVORS=mimic,ubuntu,16.04
```

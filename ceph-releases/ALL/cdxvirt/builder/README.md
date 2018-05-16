# Ceph Container builder
## Create a builder
```
docker build -t cdxvirt/ceph-container-builder .
```
## Build the Ceph container
```
SRC_PATH=/home/core/ceph-container
docker run -it --privileged \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /run/torcx/unpack/docker/bin/docker:/bin/docker \
-v /run/torcx/unpack/docker/lib:/host/lib \
-v ${SRC_PATH}:/ceph-container \
cdxvirt/ceph-container-builder

make FLAVORS=luminous,ubuntu,16.04 build
```

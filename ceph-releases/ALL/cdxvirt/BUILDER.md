# Ceph Daemon Builder
## Create a builder
```
docker build -t cdxvirt/ceph-daemon-builder -f Dockerfile.builder .
```
## Build the ceph-daemon
```
$ git clone https://github.com/cdxvirt/ceph-docker.git ~/ceph-container
$ SRC_PATH=~/ceph-container
$ docker run -it --privileged \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /bin/docker:/bin/docker \
    -v ${SRC_PATH}:/ceph-container \
    cdxvirt/ceph-daemon-builder \
    make build FLAVORS=mimic,ubuntu,16.04
```

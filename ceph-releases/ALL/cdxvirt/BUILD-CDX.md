# Build luminous cdxvirt ubuntu

## Copy Dockerfile from luminous-ubuntu-16.04
```
make stage FLAVORS=luminous,ubuntu,16.04
cp staging/luminous-ubuntu-16.04-x86_64/daemon-base/Dockerfile ceph-releases/ALL/cdxvirt/ubuntu/daemon-base
cp staging/luminous-ubuntu-16.04-x86_64/daemon/Dockerfile ceph-releases/ALL/cdxvirt/ubuntu/daemon
```
## Edit contents
```
vi ceph-releases/ALL/cdxvirt/ubuntu/daemon-base/Dockerfile
vi ceph-releases/ALL/cdxvirt/ubuntu/daemon/Dockerfile
cp cdx ceph-releases/ALL/cdxvirt/ubuntu/daemon
```
## Build Images
```
make build FLAVORS=luminous,cdxvirt,ubuntu
```

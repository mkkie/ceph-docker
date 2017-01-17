Ceph Cluster Standalone
=

Start
---

Deploy & start Ceph monitor
```sh
$ ./mon-alone.sh start
$ ./mon-alone.sh initial
```

Deploy & start OSD
```sh
$ OSD_DEVICE=/dev/sdb ./osd-alone.sh start
```

If disk was an OSD, force to format disk & start OSD
```sh
$ OSD_FORCE_ZAP=1 OSD_DEVICE=/dev/sdb ./osd-alone.sh start
```

Stop
---

Stop some OSD
```sh
$ OSD_DEVICE=/dev/sdb ./osd-alone.sh stop
```

Stop Ceph Cluster
```sh
$ ./osd-alone.sh stop-all
$ ./mon-alone.sh stop
```

Deploy another node
---

Copy configuration & keyring
```sh
A-node $ sudo scp -r /etc/ceph/ /var/lib/ceph/bootstrap-{mds,osd,rgw} user@B-node:/tmp
B-node $ sudo mkdir -p /var/lib/ceph; sudo mv /tmp/ceph/ /etc/; sudo mv /tmp/bootstrap-{mds,osd,rgw} /var/lib/ceph
```

Deploy Ceph service
```sh
B-node $ ./mon-alone.sh start
B-node $ OSD_DEVICE=/dev/sdb ./osd-alone.sh start
```

Tools
---

Command line
```sh
$ ./mon-alone.sh bash
```
List Devices
```sh
$ lsblk
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
sda      8:0    0   1.8T  0 disk
|-sda1   8:1    0   128M  0 part
|-sda2   8:2    0     2M  0 part
|-sda3   8:3    0     1G  0 part
|-sda4   8:4    0     1G  0 part
|-sda6   8:6    0   128M  0 part
|-sda7   8:7    0    64M  0 part
`-sda9   8:9    0   1.8T  0 part /
sdb      8:16   0   1.8T  0 disk
sdc      8:32   1   1.8T  0 disk
loop0    7:0    0 216.8M  0 loop /usr
```

List OSDs
```sh
$ ./osd-alone.sh list
$ ./osd-alone.sh list-id
```

Cleanup
```sh
$ sudo rm -r /etc/ceph /var/lib/ceph/
```

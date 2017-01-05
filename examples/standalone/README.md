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
A-node $ sudo scp -r /etc/ceph/ /var/lib/ceph/bootstrap-{mds,osd,rgw} B-node:/tmp
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

List OSDs
```sh
$ ./osd-alone.sh list
$ ./osd-alone.sh list-id
```

Cleanup
```sh
$ sudo rm -r /etc/ceph /var/lib/ceph/
```

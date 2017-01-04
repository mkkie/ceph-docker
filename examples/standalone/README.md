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

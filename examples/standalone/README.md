Ceph Cluster Standalone
=

Deploy & start Ceph monitor
```sh
$ ./mon-alone.sh start
$ ./mon-alone.sh initial
```

Command line
```sh
$ ./mon-alone.sh bash
```

Deploy & start OSD
```sh
$ OSD_DEVICE=/dev/sdb ./osd-alone.sh start
```

Force to format disk & start OSD
```sh
$ OSD_FORCE_ZAP=1 OSD_DEVICE=/dev/sdb ./osd-alone.sh start
```

List OSDs
```sh
$ ./osd-alone.sh list
$ ./osd-alone.sh list-id
```

Stop some OSD
```sh
$ OSD_DEVICE=/dev/sdb ./osd-alone.sh stop
```

Stop Ceph Cluster
```sh
$ ./osd-alone.sh stop-all
$ ./mon-alone.sh stop
```

Cleanup
```sh
$ sudo rm -r /etc/ceph /var/lib/ceph/
```

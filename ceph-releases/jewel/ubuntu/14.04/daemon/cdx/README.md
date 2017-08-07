# CDXVIRT Ceph Daemon

## CDX ENTRYPOINT
### cdx_mon
Brfore running start_mon, check monip, monmap first.
### cdx_osd
Choose disk, zap disk, and activate disk in different containers.
### cdx_controller
Kubernetes required.Choose nodes to deploy ceph-mon, update endpoints.
### ceph-api
Operate OSD containers.
### admin
Execute other commands.

## CDX ENV
### Use CDX_ENV=true to enable it.
### OSD
- CRUSH_TYPE=space
```txt
# CRUSH TYPE operate number of replications.
# There are "space", "safety" & "none" three modes.
# Space mode sets rbd pool to size 2, and safety mode set to 3.
# none mode won't do any change of crush rules.
```
- PGs_PER_OSD=32
```txt
# Adjust the pgs of rbd pool.
```
- OSD_INIT_MODE=minimal
```txt
# OSD INIT MODE is about selecting disk to deploy as OSD.
# There are "minimal", "force" & "strict" three modes about
# First, we won't use any disk that has been mounted.
# Minimal mode selects disks that not Ceph OSD. For example, an OSD disk from other won't be select.
# But if the seleted_list is empty, minimal mode forces to choose one disk.
# Force mode chooses any disks that has no mountpoint.
# Strict mode only select disks that isn't an OSD.
```
- MAX_OSD=1
```txt
# How many OSD containers in each host?
```
- OSD_MEM=2048M
- OSD_CPU_CORE=2
```txt
# Resource limits for OSD containers.
```
### MON
MAX_MON=3
```txt
# How many MON containers in a cluster?
```
K8S_NAMESPACE=ceph
MON_LABEL="cdx/ceph-mon"
```txt
Kubernetes MON POD settings.
```

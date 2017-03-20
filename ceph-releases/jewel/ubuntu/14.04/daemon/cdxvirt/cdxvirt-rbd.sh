#!/bin/bash

################
# RBD_SNAPSHOT #
################

function rbd_snapshot {
  get_ceph_admin
  log "Backup snapshot starting..."
  # rm $cycle ago snapshot
  [[ "$(rbd snap ls ${rbd_pool}/${rbd_image} | grep ${rbd_image}_$(date --date="$cycle days ago" +%Y%m%d%H) )" = "" ]] || rbd snap rm ${rbd_pool}/${rbd_image}@${rbd_image}_$(date --date="$cycle days ago" +%Y%m%d%H)

  rbd snap create ${rbd_pool}/${rbd_image}@${rbd_image}_$(date +%Y%m%d%H)
}


##############
# RBD_EXPORT #
##############

function rbd_export {
  get_ceph_admin
  log "Export backup to starting..."
  # rbd export imag and gizp it, then rsync to $rsync
  rbd export ${rbd_pool}/${rbd_image} - | gzip -9 > /tmp/daily_${rbd_image}_$(date +%Y%m%d).img
  rsync -av --delete --password-file=/rsync.password /tmp/daily_${rbd_image}_$(date +%Y%m%d).img.gz $rsync
}

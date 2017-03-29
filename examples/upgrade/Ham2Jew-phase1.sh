#!/bin/bash

source cdxvirt/osd.sh
: ${MON_ROOT_PATH:="/var/lib/ceph/mon/"}
: ${OSD_ROOT_PATH:="/var/lib/ceph/osd/"}

################
# UPDATE OWNER #
################

function update_osd_owner {
  if [ -z $1 ]; then
    echo "ERROR: update_owner osd_disk_path"
    exit 1
  else
    local osd_disk=$1
    osd_disk=${osd_disk}1
  fi

  mkdir -p ${OSD_ROOT_PATH}
  chown ceph. ${OSD_ROOT_PATH}
  if ceph-disk --setuser ceph --setgroup disk activate ${osd_disk} --no-start-daemon &>/dev/null; then
    OSD_ID=$(df | grep "${osd_disk}" | sed "s/.*${CLUSTER}-//g")
    OSD_PATH=$(df | grep "${osd_disk}" | awk '{print $6}')
  else
    echo "ERROR: Failed to mount ${osd_disk} as CEPH OSD."
  fi

  if chown ceph. -R ${OSD_PATH} && umount ${OSD_PATH}; then
    echo "SUCCESS: Update OSD.${OSD_ID}"
  else
    echo "ERROR: Failed to umount ${osd_disk}."
  fi
}

function update_mon_owner {
  MON_PATH=$(ls -d /var/lib/ceph/mon/*/)
  for mon_data in ${MON_PATH}; do
    if [ -e ${mon_data}/store.db/ ]; then
      chown ceph. -R ${MON_PATH}
      echo "SUCCESS: Update ${mon_data}"
    fi
  done
}

########
# MAIN #
########

# OSD
DISKS=$(get_avail_disks)
for disk in ${DISKS}; do
  if [ "$(is_osd_disk ${disk})" == "true" ]; then
    update_osd_owner ${disk}
  fi
done

# MON
MON_FOLDER_NUM=$(ls -d ${MON_ROOT_PATH}*/ 2>/dev/null | wc -w)
if [ "${MON_FOLDER_NUM}" -eq 0 ]; then
  echo "No MON folders."
else
  update_mon_owner
fi

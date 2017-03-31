#!/bin/bash

############
# API MAIN #
############

function ceph_api {
  case $1 in
    start_all_osds|set_max_osd|get_max_osd|stop_all_osds|restart_all_osds|get_active_osd_nums|run_osds)
      source cdxvirt/osd.sh
      check_docker_cmd
      $@
      ;;
    set_max_mon|get_max_mon|ceph_status|fix_monitor)
      source cdxvirt/ceph-controller.sh
      $@
      ;;
    get_osd_map)
      source cdxvirt/dev-map.sh
      $@
      ;;
    get_ceph_admin|get_ceph_conf)
      $@
      ;;
    *)
      log_warn "Wrong options."
      ;;
  esac
}

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
    set_max_mon|get_max_mon|remove_mon)
      source cdxvirt/mon.sh
      mon_controller_env
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

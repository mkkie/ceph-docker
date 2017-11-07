#! /bin/bash

function cacl_recovery_time {
  local LEFT_OBJ=$(ceph "${CLI_OPTS[@]}" status -f json | jq .pgmap.degraded_objects)
  local REC_OBJ_SEC=$(ceph "${CLI_OPTS[@]}" status -f json | jq .pgmap.recovering_objects_per_sec)

  if [ "${LEFT_OBJ}" == "null" ] || [ "${REC_OBJ_SEC}" == "null" ]; then
    local est_time=0
  else
    local est_time=$(expr "${LEFT_OBJ}" / "${REC_OBJ_SEC}")
  fi

  echo "${est_time}"
}


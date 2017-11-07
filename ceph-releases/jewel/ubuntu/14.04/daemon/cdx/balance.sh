#!/bin/bash

function cacl_balance {
  local NODE_JSON=$(ceph "${CLI_OPTS[@]}" osd tree -f json | jq --raw-output '.nodes | .[] | select(.type=="host")  | {name}+{children}')
  local NODE_LIST=$(echo "${NODE_JSON}" | jq --raw-output .name)
  local NODES=$(echo "${NODE_LIST}" | wc -w)
  local NODE_OSD_NUM=$(echo "${NODE_JSON}" | jq '{"name": (.name), "number": (.children | length)}')
  local OSD_NUM_LIST=$(echo "${NODE_JSON}" | jq '(.children | length)')

  # find the maximum & minimum of OSDS in a single node.
  local MAX_OSD=$(echo "${OSD_NUM_LIST}" | head -n1)
  local MIN_OSD="${MAX_OSD}"
  for num in ${OSD_NUM_LIST}; do
    (( num > MAX_OSD )) && MAX_OSD="${num}"
    (( num < MIN_OSD )) && MIN_OSD="${num}"
  done

  local MAX_LIST_PRE="echo \$NODE_OSD_NUM | jq --raw-output '. | select(.number==$MAX_OSD) | .name'"
  local MAX_LIST=$(eval "${MAX_LIST_PRE}")
  local NOT_MAX_LIST_PRE="echo \$NODE_OSD_NUM | jq --raw-output '. | select(.number<$MAX_OSD) | .name'"
  local NOT_MAX_LIST=$(eval "${NOT_MAX_LIST_PRE}")
  local MAX_NODE=$(echo "${MAX_LIST}" | wc -w)

  # calculate balancing status & make add & move list
  local OSD_DIFF=$(expr "${MAX_OSD}" - "${MIN_OSD}")
  local ADD_LIST
  local MOV_LIST
  local counter=0

  if [ "${NODES}" == "${MAX_NODE}" ]; then
    ADD_LIST="${MAX_LIST}"
    MOV_LIST=""
    BAL_STAT="true"
  elif [ "${OSD_DIFF}" -ge "2" ]; then
    ADD_LIST="${NOT_MAX_LIST}"
    for node in ${MAX_LIST}; do
      if [ "${counter}" -lt "1" ]; then
        MOV_LIST="${node}"
      fi
      let counter=counter+1
    done
    BAL_STAT="false"
  else
    ADD_LIST="${NOT_MAX_LIST}"
    MOV_LIST=""
    BAL_STAT="true"
  fi

  ADD_LIST="\"$(echo ${ADD_LIST})\""
  MOV_LIST="\"$(echo ${MOV_LIST})\""
  BAL_STAT="\"$(echo ${BAL_STAT})\""
  local J_FORM="{\"balance\":\"\",\"movable\":\"\",\"addable\":\"\"}"
  J_FORM=$(echo ${J_FORM} | jq ".balance |= .+ ${BAL_STAT}")
  J_FORM=$(echo ${J_FORM} | jq ".movable |= .+ ${MOV_LIST}")
  J_FORM=$(echo ${J_FORM} | jq ".addable |= .+ ${ADD_LIST}")

  echo "${J_FORM}"
}

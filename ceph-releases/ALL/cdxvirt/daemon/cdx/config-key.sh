#!/bin/bash
set -e

function get_kv {
  local key="${1}"
  if ceph config-key exists "${key}"/"${HOSTNAME}" &>/dev/null; then
    ceph config-key get "${key}"/"${HOSTNAME}" 2>/dev/null
  elif ceph config-key exists "${key}" &>/dev/null; then
    ceph config-key get "${key}" 2>/dev/null
  fi
}

function init_kv {
  local key="${1}"
  local value="${2}"
  if ! ceph config-key exists "${key}" &>/dev/null; then
    ceph config-key set "${key}" "${value}"
  fi
}

function list_all_kv {
  ceph config-key list | jq --raw-output ".[]" | grep "^${KV_PATH}" || true
}

function cleanup_kv {
  for key in $(list_all_kv); do
    echo "${key}: $(ceph config-key get "${key}" 2>/dev/null)"
    ceph config-key rm "${key}"
  done
}

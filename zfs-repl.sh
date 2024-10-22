#!/usr/bin/env bash
# This script automates the replication of ZFS datasets across different pools.
# It utilizes custom ZFS metadata properties to identify source and target datasets
# for replication, and provides full and incremental replication functionalities.

set -o nounset
set -o pipefail

# Custom ZFS metadata property used to specify the target dataset for replication.
# To mark a dataset for replication, set the custom property to the target dataset name.
#
# Example:
#   $> zfs set zfs-utils:replication-target=thor/services/cloud odin/services/cloud
#
#   This marks the `odin/services/cloud` dataset for replication to `thor/services/cloud`.
readonly META_REPLICATION_TARGET="zfs-utils:replication-target"

PV=$(command -v pv)
ZFS=$(command -v zfs)
readonly PV ZFS

function log {
  local level=$1; shift
  case $level in
    (err*) logger -t "zfs-repl" -p "user.err" "$*"; echo "Error: $*" 1>&2 ;;
    (war*) logger -t "zfs-repl" -p "user.warning" "$*"; echo "Warning: $*" 1>&2 ;;
    (inf*) logger -t "zfs-repl" -p "user.info" "$*"; echo "$*" ;;
  esac
}

function replicate_dataset {
  local source=${1:-}
  local target=${2:-}

  local -r latest_source_snapshot=$( ${ZFS} list -Ht snap -o name,creation -p | grep "^${source}@" | sort -n -k2 | tail -1 | awk '{print $1}' )
  local -r latest_target_snapshot=$( ${ZFS} list -Ht snap -o name,creation -p | grep "^${target}@" | sort -n -k2 | tail -1 | awk '{print $1}' )

  if [[ -z "${latest_source_snapshot}" ]]; then
    log err "No snapshots found for source dataset '${source}'. Replication aborted."
    return 1
  fi
  
  local replicated_source_snapshot=""
  if [[ -n "${latest_target_snapshot}" ]]; then
    replicated_source_snapshot=$( ${ZFS} list -Ht snap -o name | grep "^${source}@${latest_target_snapshot#*@}$" )
  fi

  if [[ "${latest_source_snapshot}" == "${replicated_source_snapshot}" ]]; then
    log info "Snapshot '${latest_source_snapshot}' is already fully replicated. Skipping replication of dataset '${source}'."
    return 0
  fi
  
  if [[ -n "${latest_target_snapshot}" && -z "${replicated_source_snapshot}" ]]; then
    log err "No matching source snapshot found for target snapshot '${latest_target_snapshot}'. Manual intervention required: the source snapshot may be missing or deleted."
    return 1
  fi

  if [[ -n "${latest_target_snapshot}" && -n "${replicated_source_snapshot}" ]]; then
    log info "Target snapshot '${latest_target_snapshot}' matches the source snapshot '${replicated_source_snapshot}'. Proceeding with incremental replication."
    incremental_replication "${replicated_source_snapshot}" "${latest_source_snapshot}" "${target}"
  else
    full_replication "${latest_source_snapshot}" "${target}"
  fi
}

function full_replication {
  local source_snapshot=${1:-}
  local target_dataset=${2:-}

  local -r snapshot_size=$( ${ZFS} send --raw -Pnv -cp "${source_snapshot}" | awk '/size/ {print $2}' )
  local -r snapshot_size_iec=$(bytes_to_human "${snapshot_size}")

  log info "Initiating full replication of snapshot '${source_snapshot}' to dataset '${target_dataset}' (size: ${snapshot_size_iec})."

  if ! ${ZFS} send --raw -cp "${source_snapshot}" \
        | ${PV} -s "${snapshot_size}" \
        | ${ZFS} recv "${target_dataset}"; then
    return 1
  fi
}

function incremental_replication {
  local replicated_source_snapshot=${1:-}
  local latest_source_snapshot=${2:-}
  local target_dataset=${3:-}

  local -r snapshot_size=$( ${ZFS} send --raw -Pnv -cpi "${replicated_source_snapshot}" "${latest_source_snapshot}" | awk '/size/ {print $2}' )
  local -r snapshot_size_iec=$(bytes_to_human "${snapshot_size}")

  log info "Initiating incremental replication from snapshot '${replicated_source_snapshot}' to '${latest_source_snapshot}' for dataset '${target_dataset}' (size: ${snapshot_size_iec})."

  if ! ${ZFS} send --raw -cpi "${replicated_source_snapshot}" "${latest_source_snapshot}" \
        | ${PV} -s "${snapshot_size}" \
        | ${ZFS} recv "${target_dataset}"; then
    return 1
  fi
}

function bytes_to_human {
  local i=${1:-0} d="" s=0 
  local S=("Bytes" "KiB" "MiB" "GiB" "TiB" "PiB" "EiB" "YiB" "ZiB")

  while ((i > 1024 && s < ${#S[@]}-1)); do
    printf -v d ".%02d" $((i % 1024 * 100 / 1024))
    i=$((i / 1024))
    s=$((s + 1))
  done

  echo "$i$d ${S[$s]}"
}

if [[ -z "${ZFS}" || -z "${PV}" ]]; then
  log err "Missing required binaries: zfs, pv."
  exit 1
fi

${ZFS} list -o name,"${META_REPLICATION_TARGET}" -H -r \
    | awk -F '\t' '$2 != "-" && $1 != $2' \
    | while IFS=$'\t' read -r source target; do
  log info "Initiating replication of dataset '${source}' to '${target}'."

  if replicate_dataset "${source}" "${target}"; then
    log info "Successfully replicated dataset '${source}' to '${target}'."
  else
    log warn "Replication failed for dataset '${source}' to '${target}'."
  fi
done

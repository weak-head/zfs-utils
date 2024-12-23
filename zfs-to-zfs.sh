#!/usr/bin/env bash
# This script automates the replication of ZFS datasets across different pools.
# It utilizes custom ZFS metadata properties to identify source and target datasets
# for replication, and provides full and incremental replication functionalities.

set -o nounset
set -o pipefail

readonly VERSION="v0.1.0"

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

function capture_errors {
  while IFS= read -r line; do
    log err "$line"
  done
}

function replicate_dataset {
  local source_dataset=$1
  local target_dataset=$2
  local base_snapshot=""
  local source_snapshot=""
  local target_snapshot=""

  source_snapshot=$( ${ZFS} list -Ht snap -o name,creation -p | grep "^${source_dataset}@" | sort -n -k2 | tail -1 | awk '{print $1}' )
  target_snapshot=$( ${ZFS} list -Ht snap -o name,creation -p | grep "^${target_dataset}@" | sort -n -k2 | tail -1 | awk '{print $1}' )

  if [[ -z "${source_snapshot}" ]]; then
    log err "Replication aborted: No snapshots found for source dataset '${source_dataset}'."
    return 1
  fi
  
  if [[ -n "${target_snapshot}" ]]; then
    if [[ "${source_snapshot#*@}" == "${target_snapshot#*@}" ]]; then
      log info "Replication skipped: source '${source_dataset}' is already replicted to the target '${target_dataset}'."
      return 0
    fi

    base_snapshot=$( ${ZFS} list -Ht snap -o name | grep "^${source_dataset}@${target_snapshot#*@}$" )
    if [[ -z "${base_snapshot}" ]]; then
      log err "Replication halted: Target dataset '${target_dataset}' lacks matching snapshots with" \
              "source dataset '${source_dataset}', indicating possible dataset desynchronization." \
              "Manual intervention is required to restore continuity."
      return 1
    fi

    replicate_incr "${base_snapshot}" "${source_snapshot}" "${target_dataset}"
  else
    replicate_full "${source_snapshot}" "${target_dataset}"
  fi
}

function replicate_full {
  local source_snapshot=$1
  local target_dataset=$2
  local snapshot_size=""

  snapshot_size=$( ${ZFS} send --raw -Pnv -cp "${source_snapshot}" | awk '/size/ {print $2}' )

  log info "Initiating full replication of snapshot '${source_snapshot}'" \
           "to dataset '${target_dataset}' (size: $(bytes_to_human "${snapshot_size}"))."

  if ! ${ZFS} send --raw -cp "${source_snapshot}" \
        | ${PV} -s "${snapshot_size}" \
        | ${ZFS} recv "${target_dataset}" > >(capture_errors) 2>&1; then
    return 1
  fi
}

function replicate_incr {
  local base_snapshot=$1
  local change_snapshot=$2
  local target_dataset=$3
  local snapshot_size=""
  
  snapshot_size=$( ${ZFS} send --raw -Pnv -cpi "${base_snapshot}" "${change_snapshot}" | awk '/size/ {print $2}' )

  log info "Initiating incremental replication from snapshot '${base_snapshot}'" \
           "to '${change_snapshot}' for dataset '${target_dataset}' (size: $(bytes_to_human "${snapshot_size}"))."

  if ! ${ZFS} send --raw -cpi "${base_snapshot}" "${change_snapshot}" \
        | ${PV} -s "${snapshot_size}" \
        | ${ZFS} recv "${target_dataset}" > >(capture_errors) 2>&1; then
    return 1
  fi
}

function bytes_to_human {
  local bytes=${1:-0}
  local decimal_part=""
  local suffix_index=0
  local suffixes=("Bytes" "KiB" "MiB" "GiB" "TiB" "PiB" "EiB" "YiB" "ZiB")

  while ((bytes > 1024 && suffix_index < ${#suffixes[@]} - 1)); do
    decimal_part=$(printf ".%02d" $((bytes % 1024 * 100 / 1024)))
    bytes=$((bytes / 1024))
    suffix_index=$((suffix_index + 1))
  done

  echo "${bytes}${decimal_part} ${suffixes[${suffix_index}]}"
}

if [[ -z "${ZFS}" || -z "${PV}" ]]; then
  log err "Missing required binaries: zfs, pv."
  exit 1
fi

${ZFS} list -o name,"${META_REPLICATION_TARGET}" -H -r \
    | awk -F '\t' '$2 != "-" && $1 != $2' \
    | while IFS=$'\t' read -r source target; do
  log info "Starting replication of dataset '${source}' to '${target}'."

  if replicate_dataset "${source}" "${target}"; then
    log info "Source dataset '${source}' is replicated to target dataset '${target}'."
  else
    log err "Failed to replicate source dataset '${source}' to target dataset '${target}'."
  fi
done

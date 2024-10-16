#!/usr/bin/env bash
# This script automates the synchronization of ZFS datasets across different pools.
# It utilizes custom ZFS metadata properties to identify source and target datasets
# for synchronization, and provides full and incremental sync functionalities.

set -o nounset
set -o pipefail

# This custom ZFS metadata property identifies the source and target datasets
# that should be synchronized. To mark a dataset for synchronization, 
# set this custom property to the target dataset name.
#
# Example:
#   $> zfs set zfs-utils:sync-target=thor/services/cloud odin/services/cloud
#
#   This command marks the `odin/services/cloud` dataset for synchronization,
#   and designates the `thor/services/cloud` dataset as the synchronization target.
readonly META_SYNC_TARGET="zfs-utils:sync-target"

readonly PV=$(which pv)
readonly ZFS=$(which zfs)

function sync {
  local source_dataset=${1:-}
  local target_dataset=${2:-}

  local latest_source_snapshot=$( ${ZFS} list -Ht snap -o name,creation -p | grep "^$source_dataset@" | sort -n -k2 | tail -1 | awk '{print $1}' )
  local latest_target_snapshot=$( ${ZFS} list -Ht snap -o name,creation -p | grep "^$target_dataset@" | sort -n -k2 | tail -1 | awk '{print $1}' )

  # If there is no source snapshot, we cannot synchronize the datasets.
  if [[ -z "$latest_source_snapshot" ]]; then
    echo "Error: No snapshot found for dataset '$source_dataset'. Synchronization cannot proceed."
    return 1
  fi

  # Verify if there exist a snapshot on the source dataset side,
  # that corresponds to the latest snapshot on the target dataset.
  # If so we can use the incremental synchronization instead of the full dataset sync.
  local synced_source_snapshot=""
  if [[ -n "$latest_target_snapshot" ]]; then
    local latest_target_snapshot_label=$( echo $latest_target_snapshot | awk -F'@' '{print $2}' )
    synced_source_snapshot=$( ${ZFS} list -Ht snap -o name | grep "^$source_dataset@$latest_target_snapshot_label$" )
  fi

  # If the latest source snapshot is already synchronized, there is noting left to do.
  if [[ "$latest_source_snapshot" == "$synced_source_snapshot" ]]; then
    echo "The dataset '$target_dataset' is already up-to-date with the latest snapshot '$latest_source_snapshot'."
    return 0
  fi

  if [[ -n "$latest_target_snapshot" && -n "$synced_source_snapshot" ]]; then
    echo "Initiating incremental synchronization of dataset '$source_dataset' with '$target_dataset'."
    incremental_sync $synced_source_snapshot $latest_source_snapshot $target_dataset
  else
    echo "Initiating full synchronization of dataset '$source_dataset' with '$target_dataset'."
    full_sync $latest_source_snapshot $target_dataset
  fi

  return $?
}

function full_sync {
  local source_snapshot=${1:-}
  local target_dataset=${2:-}

  local snapshot_size=$( ${ZFS} send --raw -Pnv -cp $source_snapshot | awk '/size/ {print $2}' )
  local snapshot_size_iec=$(bytes_to_human $snapshot_size)

  echo " - Starting full synchronization of '$source_snapshot' (size: $snapshot_size_iec)."

  ${ZFS} send --raw -cp $source_snapshot | ${PV} -F "   %t %a %p" -s $snapshot_size | ${ZFS} recv $target_dataset
  local exit_status=$?

  if [[ $exit_status -eq 0 ]]; then
    echo " - Full synchronization of snapshot '$source_snapshot' to dataset '$target_dataset' completed successfully."
  else
    echo " - Error: Synchronization of snapshot '$source_snapshot' to dataset '$target_dataset' failed."
    return 1
  fi
}

function incremental_sync {
  local synced_source_snapshot=${1:-}
  local latest_source_snapshot=${2:-}
  local target_dataset=${3:-}

  local snapshot_size=$( ${ZFS} send --raw -Pnv -cpi $synced_source_snapshot $latest_source_snapshot | awk '/size/ {print $2}' )
  local snapshot_size_iec=$(bytes_to_human $snapshot_size)

  echo " - Starting incremental synchronization of '$latest_source_snapshot' (size: $snapshot_size_iec)."

  ${ZFS} send --raw -cpi $synced_source_snapshot $latest_source_snapshot | ${PV} -F "   %t %a %p" -s $snapshot_size | ${ZFS} recv $target_dataset
  local exit_status=$?

  if [[ $exit_status -eq 0 ]]; then
    echo " - Incremental synchronization of snapshot '$latest_source_snapshot' to dataset '$target_dataset' completed successfully."
  else
    echo " - Error: Synchronization of snapshot '$latest_source_snapshot' to dataset '$target_dataset' failed."
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

if [[ -z "$ZFS" || -z "$PV" ]]; then
  echo "Error: Required binaries (zfs, pv) are not found."
  exit 1
fi

${ZFS} list -o name,${META_SYNC_TARGET} -H -r | awk '$2 != "-"' | while IFS=$'\t' read -r source_dataset target_dataset; do
  if [[ "$source_dataset" == "$target_dataset" ]]; then
    continue
  fi

  echo ""
  echo "===== Synchronizing '$source_dataset' to '$target_dataset' ====="
  sync $source_dataset $target_dataset
  exit_status=$?

  if [[ $exit_status -ne 0 ]]; then
    echo "Error: Synchronization of '$source_dataset' to '$target_dataset' failed. Terminating process."
    exit $exit_status
  fi

  echo "Synchronization of '$source_dataset' to '$target_dataset' completed successfully."
  echo ""
done

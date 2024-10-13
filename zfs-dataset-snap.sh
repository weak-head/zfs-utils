#!/usr/bin/env bash
# This script automates the creation of snapshots for configured ZFS datasets.
# It leverages custom ZFS metadata properties to identify the datasets
# that require snapshots. 

set -o nounset
set -o pipefail

# This custom ZFS metadata property marks datasets for automatic snapshots.
# To enable automatic snapshotting for a dataset, set this property to 'true'.
#
# Example:
#   $> zfs set zfs-utils:auto-snap=true odin/services/cloud
#
#   This command designates the `odin/services/cloud` dataset for automatic snapshots.
readonly META_AUTO_SNAP="zfs-utils:auto-snap"

readonly ZFS=$(which zfs)

if [[ -z "$ZFS" ]]; then
  echo "Error: Required 'zfs' binary is not found."
  exit 1
fi

# ISO style date: YYYY-MM-DD
label=$(date -u +'%Y-%m-%d')

${ZFS} list -o name,${META_AUTO_SNAP} -H -r | awk '$2 != "-"' | while IFS=$'\t' read -r dataset value; do
  if [[ "$value" != "true" ]]; then
    continue
  fi

  ${ZFS} snap "$dataset@$label"

  exit_status=$?
  if [[ $exit_status -eq 0 ]]; then
    echo "Snapshot created: '$dataset@$label'"
  fi
done

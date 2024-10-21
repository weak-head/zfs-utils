#!/usr/bin/env bash
# This script automates the creation of snapshots for configured ZFS datasets.
# It uses a custom ZFS metadata property to identify datasets that need snapshots.

set -o nounset
set -o pipefail

# Custom ZFS metadata property to mark datasets for automatic snapshots.
# To enable automatic snapshotting for a dataset, set this property to 'true'.
#
# Example:
#   $> zfs set zfs-utils:auto-snap=true odin/services/cloud
#
# This command designates the `odin/services/cloud` dataset for automatic snapshots.
readonly META_AUTO_SNAP="zfs-utils:auto-snap"

readonly ZFS=$(command -v zfs)

function log {
  local level=$1; shift
  case $level in
    (err*) logger -t "zfs-snap" -p "user.err" "$*"; echo "Error: $*" 1>&2 ;;
    (war*) logger -t "zfs-snap" -p "user.warning" "$*"; echo "Warning: $*" 1>&2 ;;
    (inf*) logger -t "zfs-snap" -p "user.info" "$*"; echo "$*" ;;
  esac
}

function capture_errors {
  while IFS= read -r line; do
    log err "$line"
  done
}

function create_snapshot {
  local dataset=$1
  local label=$2

  # Verify if the requested snapshot already exists
  if ${ZFS} list -Ht snap -o name | grep -q "^${dataset}@${label}$"; then
    log warn "Snapshot '${dataset}@${label}' already exists. Snapshot creation skipped."
    return 0
  fi

  if ${ZFS} snap "${dataset}@${label}" > >(capture_errors) 2>&1; then
    log info "Snapshot '${dataset}@${label}' created successfully."
  else
    log err "Failed to create snapshot '${label}' for dataset '${dataset}'."
    return 1
  fi
}

if [[ -z "$ZFS" ]]; then
  log err "Missing required binary: zfs"
  exit 1
fi

# Generate an ISO 8601 date label (YYYY-MM-DD) to be used as the snapshot identifier.
# This label will be applied to all snapshots created in this run.
# Example: The resulting snapshot name will be in the format:
#   <dataset>@<date>, such as odin/services/cloud@2024-10-21
label=$(date -u +'%Y-%m-%d')

# List all ZFS datasets recursively, including their custom auto-snapshot property.
# Filter the output to include only datasets where the auto-snapshot property is set to "true".
# For each matching dataset, create a snapshot using the generated date label.
${ZFS} list -H -o name,"${META_AUTO_SNAP}" -r \
    | awk -v auto_snap="${META_AUTO_SNAP}" '$2 == "true"' \
    | while IFS=$'\t' read -r dataset _; do
  create_snapshot "${dataset}" "${label}"
done

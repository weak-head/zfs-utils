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

# Color codes for pretty print
readonly NC='\033[0m' # No Color
declare -A COLORS=(
  [TITLE]='\033[0;36m'  # Cyan
  [TEXT]='\033[0;37m'   # White
  [CMD]='\033[0;34m'    # Blue
  [ARGS]='\033[0;35m'   # Magenta
  # -- message severity
  [INFO]='\033[0;36mℹ️ '     # Cyan
  [WARN]='\033[0;33m⚡ '    # Yellow
  [ERROR]='\033[0;31m❌ '   # Red
)

PV=$(command -v pv)
ZFS=$(command -v zfs)
readonly PV ZFS

function print_usage {
  local VERSION="v0.3.0"

  echo -e "${COLORS[TITLE]}$(basename "$0")${NC} ${COLORS[TEXT]}${VERSION}${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Usage:${NC}"
  echo -e "  ${COLORS[CMD]}$(basename "$0")${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Description:${NC}"
  echo -e "  This script automates the replication of ZFS datasets across different pools."
  echo -e "  It utilizes custom ZFS metadata properties to identify source and target datasets"
  echo -e "  for replication, and provides full and incremental replication functionalities."
  echo -e ""
  echo -e "${COLORS[TITLE]}ZFS Metadata:${NC}"
  echo -e "  ${COLORS[ARGS]}zfs-utils:replication-target${NC}"
  echo -e "    Custom ZFS metadata property used to specify the target dataset for replication."
  echo -e "    To mark a dataset for replication, set the custom property to the target dataset name."
  echo -e ""
  echo -e "    Example:"
  echo -e "      $> ${COLORS[CMD]}zfs set zfs-utils:replication-target=thor/services/cloud odin/services/cloud${NC}"
  echo -e "      This marks the 'odin/services/cloud' dataset for replication to 'thor/services/cloud'."
  echo -e ""
}

function log {
  local level=$1; shift
  case $level in
    (err*) logger -t "zfs-to-zfs" -p "user.err" "$*"; echo -e "${COLORS[ERROR]}Error:${NC} $*" 2>&2 ;;
    (war*) logger -t "zfs-to-zfs" -p "user.warning" "$*"; echo -e "${COLORS[WARN]}Warning:${NC} $*" 1>&2 ;;
    (inf*) logger -t "zfs-to-zfs" -p "user.info" "$*"; echo -e "${COLORS[INFO]}${NC}$*" ;;
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
    log err "Aborted: no '${source_dataset}' snapshots."
    return 1
  fi
  
  if [[ -n "${target_snapshot}" ]]; then
    if [[ "${source_snapshot#*@}" == "${target_snapshot#*@}" ]]; then
      log info "Skipped: '${source_dataset}' is already replicated."
      return 0
    fi

    base_snapshot=$( ${ZFS} list -Ht snap -o name | grep "^${source_dataset}@${target_snapshot#*@}$" )
    if [[ -z "${base_snapshot}" ]]; then
      log err "Replication halted: Target dataset '${target_dataset}' lacks matching snapshots with" \
              "source dataset '${source_dataset}', indicating possible dataset desynchronization." \
              "Manual intervention is required to restore continuity."
      return 1
    fi
    
    log info "Base snapshot: '${base_snapshot}'."

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

  log info "Full replication: '${source_snapshot}' ($(bytes_to_human "${snapshot_size}"))."

  if ! ${ZFS} send --raw -cp "${source_snapshot}" \
        | ${PV} --size "${snapshot_size}" --progress --rate --width 60 \
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

  log info "Incremental replication: '${change_snapshot}' ($(bytes_to_human "${snapshot_size}"))."

  if ! ${ZFS} send --raw -cpi "${base_snapshot}" "${change_snapshot}" \
        | ${PV} --size "${snapshot_size}" --progress --rate --width 60 \
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

function check_zfs_permissions {
  local dataset=$1
  local required=$2
  local user permissions original_ifs

  user=$(whoami)
  if [[ "${user}" == "root" ]]; then
    return 0
  fi

  permissions=$( ${ZFS} allow "${dataset}" | grep -E "(${user}|@)")

  # Temporary use comma as the delimiter
  original_ifs=$IFS
  IFS=','
  trap 'IFS=$original_ifs' RETURN

  for perm in ${required}; do
    if ! grep -q "${perm}" <<< "${permissions}"; then
      log err "User ${user} does not have 'zfs ${perm}' permission on '${dataset}'."
      return 1
    fi
  done
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help) print_usage; exit 0 ;;
    *) break ;;
  esac
done

if [[ -z "${ZFS}" || -z "${PV}" ]]; then
  log err "Missing required binaries: zfs, pv."
  exit 1
fi

${ZFS} list -o name,"${META_REPLICATION_TARGET}" -H -r \
    | awk -F '\t' '$2 != "-" && $1 != $2' \
    | while IFS=$'\t' read -r source target; do
  log info "Replicate '${source}' to '${target}'."

  if ! check_zfs_permissions "${source}" "send"; then
    log warn "Skipped '${source}': no access to '${source}' ZFS dataset."
    continue
  fi

  if ! check_zfs_permissions "${target}" "recv"; then
    log warn "Skipped '${source}': no access to '${target}' ZFS dataset."
    continue
  fi

  if replicate_dataset "${source}" "${target}"; then
    log info "Replicated: '${source}'."
  else
    log err "Failed: '${source}'."
  fi
done

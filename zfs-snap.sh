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

# Color codes for pretty print
readonly NC='\033[0m' # No Color
declare -A COLORS=(
  [TITLE]='\033[0;36m'      # Cyan
  [TEXT]='\033[0;37m'       # White
  [CMD]='\033[0;34m'        # Blue
  [ARGS]='\033[0;35m'       # Magenta
  # -- message severity
  [INFO]='\033[0;36mℹ️ '     # Cyan
  [WARN]='\033[0;33m⚡ '    # Yellow
  [ERROR]='\033[0;31m❌ '   # Red
)

ZFS=$(command -v zfs)
readonly ZFS

function print_usage {
  local VERSION="v0.3.0"

  echo -e "${COLORS[TITLE]}$(basename "$0")${NC} ${COLORS[TEXT]}${VERSION}${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Usage:${NC}"
  echo -e "  ${COLORS[CMD]}$(basename "$0")${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Description:${NC}"
  echo -e "  This script automates the creation of snapshots for configured ZFS datasets."
  echo -e "  It uses a custom ZFS metadata property to identify datasets that need snapshots."
  echo -e ""
  echo -e "${COLORS[TITLE]}ZFS Metadata:${NC}"
  echo -e "  ${COLORS[ARGS]}zfs-utils:auto-snap${NC}"
  echo -e "    Custom ZFS metadata property to mark datasets for automatic snapshots."
  echo -e "    To enable automatic snapshotting for a dataset, set this property to 'true'."
  echo -e "    $> ${COLORS[CMD]}zfs set zfs-utils:auto-snap=true odin/services/cloud${NC}"
  echo -e ""
}

function log {
  local level=$1; shift
  case $level in
    (err*) logger -t "zfs-snap" -p "user.err" "$*"; echo -e "${COLORS[ERROR]}Error:${NC} $*" 2>&2 ;;
    (war*) logger -t "zfs-snap" -p "user.warning" "$*"; echo -e "${COLORS[WARN]}Warning:${NC} $*" 1>&2 ;;
    (inf*) logger -t "zfs-snap" -p "user.info" "$*"; echo -e "${COLORS[INFO]}${NC}$*" ;;
  esac
}

function capture_errors {
  while IFS= read -r line; do
    log err "$line"
  done
}

function create_snapshot {
  local dataset=$1 label=$2

  # Verify if the requested snapshot already exists
  if ${ZFS} list -Ht snap -o name | grep -q "^${dataset}@${label}$"; then
    log warn "Skipped: '${dataset}@${label}' already exists."
    return 0
  fi

  if ${ZFS} snap "${dataset}@${label}" > >(capture_errors) 2>&1; then
    log info "Created: '${dataset}@${label}'."
  else
    log err "Failed: '${dataset}@${label}'."
    return 1
  fi
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

if [[ -z "$ZFS" ]]; then
  log err "Missing required binary: zfs"
  exit 1
fi

LABEL_FORMAT=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help) print_usage; exit 0 ;;
    -l|--label)
      if [[ "$#" -lt 2 || "$2" == -* ]]; then
        log err "Option '$1' requires an argument.\n"
        print_usage
        exit 1
      fi
      LABEL_FORMAT="$2"; shift 2 ;;
    *) break ;;
  esac
done

if [[ "$#" -gt 1 ]]; then
  log err "Unrecognized extra arguments.\n"
  print_usage
  exit 1
fi

if [[ -n "${LABEL_FORMAT}" ]]; then
  label=$(date -u +"${LABEL_FORMAT}")
else
  # Generate an ISO 8601 date label (YYYY-MM-DD) to be used as the snapshot identifier.
  # This label will be applied to all snapshots created in this run.
  # The resulting snapshot name will be in the format: <dataset>@<date>
  # Such as 'odin/services/cloud@2024-10-21'.
  label=$(date -u +'%Y-%m-%d')
fi

# List all ZFS datasets recursively, including their custom auto-snapshot property.
# Filter the output to include only datasets where the auto-snapshot property is set to "true".
# For each matching dataset, create a snapshot using the generated date label.
${ZFS} list -H -o name,"${META_AUTO_SNAP}" -r \
    | awk -v auto_snap="${META_AUTO_SNAP}" '$2 == "true"' \
    | while IFS=$'\t' read -r dataset _; do

  if ! check_zfs_permissions "${dataset}" "snap"; then
    log warn "Skipped '${dataset}': permission denied."
    continue
  fi

  create_snapshot "${dataset}" "${label}"
done

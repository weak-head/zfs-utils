#!/usr/bin/env bash
# This interactive script streamlines the process of identifying and safely removing ZFS dataset snapshots
# based on user-defined naming patterns. It allows for flexible filtering using multiple criteria, applying 
# a logical 'OR' to match any snapshots that fulfill one or more specified filters.
#
# Key Features:
# - Accepts one or more filter patterns to target specific snapshots based on their names.
# - Snapshots created within the last 7 days are preserved to prevent premature deletion.
# - The most recent snapshot for each dataset is protected to ensure backup integrity.
# - Provides a comprehensive summary of snapshots that match the filters, along with
#   a confirmation prompt before any deletions take place.
#
# Usage Instructions:
#   $> zfs-clear <pattern1> <pattern2> ... <patternN>
#
# Parameters:
#   pattern1, pattern2, ... patternN - One or more strings used to filter snapshot names. Only snapshots that 
#                                      match any provided patterns will be considered for deletion, provided they meet
#                                      additional criteria.
#
# Example Command:
#   $> zfs-clear 2024-10 2023 
#   This command will identify and prompt for the deletion of snapshots containing either "2024-10" or "2023" 
#   in their names, while automatically preserving recent snapshots and the latest snapshot of each dataset.

# Color codes for pretty print
readonly NC='\033[0m' # No Color
declare -A COLORS=(
    # -- print usage
    [TITLE]='\033[0;36m'        # Cyan
    [TEXT]='\033[0;37m'         # White
    [CMD]='\033[0;34m'          # Blue
    [ARGS]='\033[0;35m'         # Magenta
    # -- operation log
    [SECTION]='\033[1;32m'      # Green (bold)
    [ACTION]='\033[0;34m⏳ '    # Blue
    # -- message severity
    [INFO]='\033[0;36mℹ️ '       # Cyan
    [WARN]='\033[0;33m⚡ '      # Yellow
    [ERROR]='\033[0;31m❌ '     # Red
    [SUCCESS]='\033[0;32m✅ '   # Green
)

# Determines if confirmation is required before deleting a snapshot.  
# When set to 'true', a confirmation prompt will be displayed.  
# Use the `-y` flag to bypass this prompt and proceed without confirmation.  
CONFIRMATION_REQUIRED=true

# Snapshots created within the specified number of days will be excluded
# from the deletion process to prevent the removal of recent backups.
# This threshold is set to 7 days by default.
readonly SKIP_DAYS=7

CURRENT_DATE=$(date +%s)
readonly CURRENT_DATE

ZFS=$(command -v zfs)
readonly ZFS


function print_usage {
  local VERSION="v0.3.0"

  echo -e "${COLORS[TITLE]}$(basename "$0")${NC} ${COLORS[TEXT]}${VERSION}${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Usage:${NC}"
  echo -e "  ${COLORS[CMD]}$(basename "$0")${NC} ${COLORS[ARGS]}[options] <pattern1> ... <patternN>${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Options:${NC}"
  echo -e "  ${COLORS[ARGS]}-y, --yes${NC}    Skip the confirmation prompt and delete all matched dataset snapshots."
  echo -e "  ${COLORS[ARGS]}--help${NC}       Display this help message and exit."
  echo -e ""
  echo -e "${COLORS[TITLE]}Arguments:${NC}"
  echo -e "  ${COLORS[ARGS]}<pattern1> <pattern2> ... <patternN>${NC}"
  echo -e "      One or more strings used to filter snapshot names."
  echo -e "      Only snapshots matching any provided patterns will be considered for deletion,"
  echo -e "      provided they meet additional criteria."
  echo -e ""
  echo -e "${COLORS[TITLE]}Examples:${NC}"
  echo -e "  ${COLORS[CMD]}$(basename "$0")${NC} ${COLORS[ARGS]}2024-10 2023${NC}"
  echo -e "      This command will identify and prompt for the deletion of snapshots containing either '2024-10' or '2023'"
  echo -e "      in their names, while preserving recent snapshots and the latest snapshot of each dataset."
  echo -e ""
  echo -e "  ${COLORS[CMD]}$(basename "$0")${NC} ${COLORS[ARGS]}-y 2024-10${NC}"
  echo -e "      This command will delete all snapshots containing '2024-10' in their names without prompting for confirmation,"
  echo -e "      while still preserving recent snapshots and the latest snapshot of each dataset."
  echo -e ""
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
      echo -e "${COLORS[ERROR]}Error: User ${user} does not have 'zfs ${perm}' permission on '${dataset}'.${NC}"
      return 1
    fi
  done
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -y|--yes) CONFIRMATION_REQUIRED=false; shift;;
    --help) print_usage; exit 0 ;;
    *) break ;;
  esac
done

if [[ -z "$ZFS" ]]; then
  echo -e "${COLORS[ERROR]}Missing required binary: zfs\n${NC}"
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo -e "${COLORS[ERROR]}Error: No snapshot filter provided. Please specify at least one filter pattern.\n${NC}"
  exit 1
fi

params=("$@")
for pattern in "${params[@]}"; do
  if [[ -z "${pattern}" || "${pattern}" =~ ^[[:space:]]*$ ]]; then
    echo -e "${COLORS[ERROR]}Error: Snapshot filter cannot be an empty string. Please provide valid patterns.\n${NC}"
    exit 1
  fi
done

# Snapshots that match ANY of the specified patterns
snapshots=$(${ZFS} list -rH -t snapshot -o name | grep -E "$(IFS="|"; echo "${params[*]}")")

# Snapshots marked for deletion
removals=()

if [[ -z "${snapshots}" ]]; then
  echo -e "${COLORS[WARN]}Warning: No matching snapshots found for the specified patterns. Exiting.\n${NC}"
  exit 1
fi

echo -e ""
echo -e "${COLORS[SECTION]}Snapshots excluded from the deletion:${NC}"
echo -e "-----------------------------------------"
name_width=$( awk -v pad=4 '{ if (length($0) > max) max = length($0) } END { print max + pad }' <<< "${snapshots}" )
while IFS=$'\t' read -r snapshot; do
  creation_date=$(${ZFS} get -Hp -o value creation "${snapshot}")
  age=$(( (CURRENT_DATE - creation_date) / 86400 ))  # Age in days

  if (( age <= SKIP_DAYS )); then
    printf "${COLORS[SUCCESS]}%-${name_width}s${NC} %s\n" "$snapshot" "(created within the last ${SKIP_DAYS} days)"
    continue
  fi

  latest_snapshot=$( ${ZFS} list -Ht snap -o name -s creation "${snapshot%%@*}" | tail -1 )
  if [[ "${snapshot}" == "${latest_snapshot}" ]]; then
    printf "${COLORS[SUCCESS]}%-${name_width}s${NC} %s\n" "$snapshot" "(not permitted to destroy the latest snapshot)"
    continue
  fi

  removals+=("${snapshot}")
done <<< "${snapshots}"

if [[ ${#removals[@]} -eq 0 ]]; then
  echo -e "\n${COLORS[WARN]}No snapshots meet the criteria for deletion. Exiting.\n${NC}"
  exit 1
fi

echo -e ""
echo -e "${COLORS[SECTION]}Snapshots eligible for deletion:${NC}"
echo -e "-----------------------------------------"
for snapshot in "${removals[@]}"; do
  echo -e "${COLORS[WARN]}${snapshot}${NC}"
done

if ${CONFIRMATION_REQUIRED}; then
  echo -e ""
  echo -e "${COLORS[SECTION]}Confirming snapshot removals...${NC}"
  echo -e "-----------------------------------------"
  read -r -p "Are you sure you want to delete the above snapshots? (y/n): " choice
  case "${choice}" in 
    y|Y ) echo -e "${COLORS[SUCCESS]}Proceeding with deletion...${NC}";;
    n|N ) echo -e "${COLORS[WARN]}Operation cancelled. No changes made.\n${NC}"; exit 1;;
    * ) echo -e "${COLORS[ERROR]}Invalid input. Please enter 'y' or 'n'. Exiting.\n${NC}"; exit 1;;
  esac
fi

echo -e ""
echo -e "${COLORS[SECTION]}Deleting snapshots...${NC}"
echo -e "-----------------------------------------"
for snapshot in "${removals[@]}"; do
  echo -e "${COLORS[ACTION]}Deleting '${snapshot}'...${NC}"

  dataset="${snapshot%@*}"
  if ! check_zfs_permissions "${dataset}" "destroy"; then
    echo -e "${COLORS[WARN]}Warning: Skipped '${snapshot}': permission denied${NC}\n"
    continue
  fi

  if ! ${ZFS} destroy "${snapshot}"; then
    echo -e "${COLORS[ERROR]}Error: Failed to delete '${snapshot}'${NC}\n"
  else
    echo -e "${COLORS[SUCCESS]}Removed '${snapshot}'${NC}\n"
  fi
done


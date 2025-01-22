#!/usr/bin/env bash

readonly NC='\033[0m' # No Color
declare -A COLORS=(
  [TITLE]='\033[0;36m'  # Cyan
  [TEXT]='\033[0;37m'   # White
  [CMD]='\033[0;34m'    # Blue
  [META]='\033[0;35m'   # Magenta
  # -- message severity
  [INFO]='\033[0;37mℹ️ '     # White
  [WARN]='\033[0;33m⚡ '    # Yellow
  [ERROR]='\033[0;31m❌ '   # Red
)

ZFS=$(command -v zfs)
AWK=$(command -v awk)
readonly ZFS AWK

function print_usage {
  local VERSION="v0.3.0"

  echo -e "${COLORS[TITLE]}$(basename "$0")${NC} ${COLORS[TEXT]}${VERSION}${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Usage:${NC}"
  echo -e "  ${COLORS[CMD]}$(basename "$0")${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Description:${NC}"
  echo -e "  This script provides a summary of ZFS metadata properties for all ZFS datasets."
  echo -e "  It fetches and formats custom metadata properties, such as:"
  echo -e "    - ${COLORS[META]}zfs-utils:auto-snap${NC}: Indicates if automatic snapshots are enabled."
  echo -e "    - ${COLORS[META]}zfs-utils:aws-bucket${NC}: Specifies the associated AWS S3 bucket (if any)."
  echo -e "    - ${COLORS[META]}zfs-utils:replication-target${NC}: Specifies the target dataset for replication."
  echo -e ""
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help) print_usage; exit 0 ;;
    *) break ;;
  esac
done

if [[ -z "${ZFS}" || -z "${AWK}" ]]; then
  echo -e "${COLORS[ERROR]}Missing required binaries: zfs, awk.${NC}\n"
  exit 1
fi

${ZFS} get -H \
    -o name,property,value \
    -t filesystem,volume \
    zfs-utils:auto-snap,zfs-utils:aws-bucket,zfs-utils:replication-target | \
${AWK} '
BEGIN { 
    header = sprintf("%-30s %-20s %-30s %-30s", "Dataset", "Auto-Snap", "AWS Bucket", "Replication Target"); 
    separator = "-------------------------------------------------------------------------------------------------------------"; 
    print header; 
    print separator; 
}
{
    data[$1][$2] = $3
}
END {
    for (dataset in data) {
        printf "%-30s %-20s %-30s %-30s\n", 
            dataset, 
            (data[dataset]["zfs-utils:auto-snap"] ? data[dataset]["zfs-utils:auto-snap"] : "N/A"), 
            (data[dataset]["zfs-utils:aws-bucket"] ? data[dataset]["zfs-utils:aws-bucket"] : "N/A"), 
            (data[dataset]["zfs-utils:replication-target"] ? data[dataset]["zfs-utils:replication-target"] : "N/A");
    }
}' | ${AWK} 'NR <= 2 {print $0} NR > 2 {print $0 | "sort"}'


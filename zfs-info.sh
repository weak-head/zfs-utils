#!/usr/bin/env bash
# This script provides a summary of ZFS metadata properties for all ZFS datasets.
# It fetches and formats custom metadata properties, such as:
#   - zfs-utils:auto-snap           - Indicates if automatic snapshots are enabled.
#   - zfs-utils:aws-bucket          - Specifies the associated AWS S3 bucket (if any).
#   - zfs-utils:replication-target  - Specifies the target dataset for replication.

set -o nounset
set -o pipefail

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
readonly ZFS

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

if [[ -z "${ZFS}" ]]; then
  echo -e "${COLORS[ERROR]}Missing required binary: zfs.${NC}\n"
  exit 1
fi

# shellcheck disable=SC2016
${ZFS} get -H \
    -o name,property,value \
    -t filesystem,volume \
    zfs-utils:auto-snap,zfs-utils:aws-bucket,zfs-utils:replication-target | \
awk '
{
    # 1. Store the raw data into our 2D array
    data[$1][$2] = $3
}
END {
    # 2. Initialize max widths with the length of the column headers
    max_c1 = length("Dataset")
    max_c2 = length("Auto-Snap")
    max_c3 = length("AWS Bucket")
    max_c4 = length("Replication Target")

    # 3. Iterate through data to find the absolute maximum width for each column
    for (dataset in data) {
        if (length(dataset) > max_c1) max_c1 = length(dataset)
        
        v2 = data[dataset]["zfs-utils:auto-snap"] ? data[dataset]["zfs-utils:auto-snap"] : "-"
        if (length(v2) > max_c2) max_c2 = length(v2)
        
        v3 = data[dataset]["zfs-utils:aws-bucket"] ? data[dataset]["zfs-utils:aws-bucket"] : "-"
        if (length(v3) > max_c3) max_c3 = length(v3)
        
        v4 = data[dataset]["zfs-utils:replication-target"] ? data[dataset]["zfs-utils:replication-target"] : "-"
        if (length(v4) > max_c4) max_c4 = length(v4)
    }

    # 4. Add 4 spaces for padding
    max_c1 += 4; max_c2 += 4; max_c3 += 4; max_c4 += 4

    # 5. Dynamically build the format string (e.g., "%-34s %-24s %-34s %-34s")
    fmt = sprintf("%%-%ds %%-%ds %%-%ds %%-%ds", max_c1, max_c2, max_c3, max_c4)

    # 6. Print the header using the new dynamic format
    printf(fmt "\n", "Dataset", "Auto-Snap", "AWS Bucket", "Replication Target")
    
    # 7. Dynamically generate and print the separator line (---)
    total_len = max_c1 + max_c2 + max_c3 + max_c4 + 3 # +3 for the 3 spaces between the 4 columns
    sep = sprintf("%" total_len "s", "")
    gsub(/ /, "-", sep)
    print sep

    # 8. Print the actual formatted data
    for (dataset in data) {
        v2 = data[dataset]["zfs-utils:auto-snap"] ? data[dataset]["zfs-utils:auto-snap"] : "-"
        v3 = data[dataset]["zfs-utils:aws-bucket"] ? data[dataset]["zfs-utils:aws-bucket"] : "-"
        v4 = data[dataset]["zfs-utils:replication-target"] ? data[dataset]["zfs-utils:replication-target"] : "-"
        
        printf(fmt "\n", dataset, v2, v3, v4)
    }
}' | awk 'NR <= 2 {print $0} NR > 2 {print $0 | "sort"}'

#!/usr/bin/env bash

ZFS=$(command -v zfs)
readonly ZFS

if [[ -z "$ZFS" ]]; then
  echo -e "Missing required binary: zfs\n"
  exit 1
fi

${ZFS} get -H \
    -o name,property,value \
    -t filesystem,volume \
    zfs-utils:auto-snap,zfs-utils:aws-bucket,zfs-utils:replication-target | \
awk '
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
}' | awk 'NR <= 2 {print $0} NR > 2 {print $0 | "sort"}'


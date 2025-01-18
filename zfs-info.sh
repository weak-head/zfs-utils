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
    zfs-utils:auto-snap,zfs-utils:replication-target,zfs-utils:aws-bucket \
| awk '
BEGIN { 
    printf "%-30s %-10s %-30s %-30s\n", "Dataset", "Auto-Snap", "Replication Target", "AWS Bucket"; 
    print "-------------------------------------------------------------------------------------------------------------"; 
}
{
    data[$1][$2] = $3
}
END {
    for (dataset in data) {
        printf "%-30s %-10s %-30s %-30s\n", 
            dataset, 
            (data[dataset]["zfs-utils:auto-snap"] ? data[dataset]["zfs-utils:auto-snap"] : "-"), 
            (data[dataset]["zfs-utils:replication-target"] ? data[dataset]["zfs-utils:replication-target"] : "-"),
            (data[dataset]["zfs-utils:aws-bucket"] ? data[dataset]["zfs-utils:aws-bucket"] : "-"); 
    }
}' | (head -n 2 && tail -n +3 | sort)


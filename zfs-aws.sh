#!/usr/bin/env bash
# This script automates the backup of ZFS datasets to AWS S3.
# It uses custom ZFS metadata properties to specify the AWS S3 bucket
# for backups, providing both full and incremental backup capabilities.
#
# Dataset snapshots could be restored directly from AWS S3 bucket:
#   $> aws s3 cp s3://bucket/directory/file - | pv | zfs recv odin/services/cloud

set -o nounset
set -o pipefail

# This custom ZFS metadata property specifies the AWS S3 bucket 
# designated for storing dataset backups. To enable AWS S3 backups 
# for a dataset, set this custom property to the target bucket name.
#
# Example:
#   $> zfs set zfs-utils:aws-bucket=backup.bucket.aws odin/services/cloud
#
#   This command marks the `odin/services/cloud` dataset for AWS S3 backups,
#   and specifies `backup.bucket.aws` as the backup destination.
readonly META_AWS_BUCKET="zfs-utils:aws-bucket"

readonly PV=$(which pv)
readonly ZFS=$(which zfs)
readonly AWS=$(which aws)

function upload {
  local dataset=${1:-}
  local aws_bucket=${2:-}
  local aws_directory=$( echo "$dataset" | sed 's/\//./g' )

  local latest_snapshot=$( ${ZFS} list -Ht snap -o name,creation -p | grep "^$dataset@" | sort -n -k2 | tail -1 | awk '{print $1}' )
  local latest_uploaded=$( ${AWS} s3 ls "s3://${aws_bucket}/${aws_directory}/" | grep -v \/\$ | sort -r | head -1 | awk '{print $4}' )

  # We cannot proceed if the dataset has no snapshots.
  if [[ -z "$latest_snapshot" ]]; then
    echo "Error: No snapshot found for dataset '$dataset'. AWS S3 upload cannot proceed."
    return 1
  fi

  # Verify if there exist a local version of the dataset snapshot,
  # that corresponds to the latest snapshot uploaded to the AWS S3 bucket.
  # If so we can use the incremental upload instead of the full dataset upload.
  local synced_snapshot=""
  if [[ -n "$latest_uploaded" ]]; then
    local uploaded_label=$( echo $latest_uploaded | awk -F'_' '{print $1}' )
    synced_snapshot=$( ${ZFS} list -Ht snap -o name | grep "^$dataset@$uploaded_label$" )
  fi

  # If the latest snapshot is already uploaded, there is nothing left to do.
  if [[ "$latest_snapshot" == "$synced_snapshot" ]]; then
    echo "The latest snapshot '$latest_snapshot' is already uploaded to AWS S3."
    return 0
  fi

  if [[ -n "$latest_snapshot" && -n "$synced_snapshot" ]]; then
    echo "Initiating incremental upload of dataset '$dataset'."
    incremental_upload $synced_snapshot $latest_snapshot $aws_bucket $aws_directory
  else
    echo "Initiating full upload of dataset '$dataset'."
    full_upload $latest_snapshot $aws_bucket $aws_directory
  fi

  return $?
}

function full_upload {
  local latest_snapshot=${1:-}
  local aws_bucket=${2:-}
  local aws_directory=${3:-}

  local snapshot_label=$( echo "$latest_snapshot" | awk -F'@' '{print $2}' )
  local aws_filename="${snapshot_label}_full"

  local snapshot_size=$( ${ZFS} send --raw -Pnv -cp $latest_snapshot | awk '/size/ {print $2}' )
  local snapshot_size_iec=$(bytes_to_human $snapshot_size)

  echo " - Starting full upload of '$latest_snapshot' (size: $snapshot_size_iec)."

  ${ZFS} send --raw -cp $latest_snapshot \
    | ${PV} -F "   %t %a %p" -s $snapshot_size \
    | ${AWS} s3 cp - "s3://$aws_bucket/$aws_directory/$aws_filename" --expected-size $snapshot_size
  local exit_status=$?

  if [[ $exit_status -eq 0 ]]; then
    echo " - Snapshot '$latest_snapshot' has been successfully uploaded to '$aws_bucket' bucket."
  else
    echo " - Error: Failed to upload '$latest_snapshot' snapshot to '$aws_bucket' bucket."
    return 1
  fi
}

function incremental_upload {
  local synced_snapshot=${1:-}
  local latest_snapshot=${2:-}
  local aws_bucket=${3:-}
  local aws_directory=${4:-}

  local synced_snapshot_label=$( echo "$synced_snapshot" | awk -F'@' '{print $2}' )
  local latest_snapshot_label=$( echo "$latest_snapshot" | awk -F'@' '{print $2}' )
  local aws_filename="${latest_snapshot_label}_incr-${synced_snapshot_label}"

  local snapshot_size=$( ${ZFS} send --raw -Pnv -cpi $synced_snapshot $latest_snapshot | awk '/size/ {print $2}' )
  local snapshot_size_iec=$(bytes_to_human $snapshot_size)

  echo " - Starting incremental upload of '$latest_snapshot' (size: $snapshot_size_iec)."

  ${ZFS} send --raw -cpi $synced_snapshot $latest_snapshot \
    | ${PV} -F "   %t %a %p" -s $snapshot_size \
    | ${AWS} s3 cp - "s3://$aws_bucket/$aws_directory/$aws_filename" --expected-size $snapshot_size
  local exit_status=$?
  
  if [[ $exit_status -eq 0 ]]; then
    echo " - Snapshot '$latest_snapshot' has been successfully uploaded to '$aws_bucket' bucket."
  else
    echo " - Error: Failed to upload '$latest_snapshot' snapshot to '$aws_bucket' bucket."
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

if [[ -z "$ZFS" || -z "$PV" || -z "$AWS" ]]; then
  echo "Error: Required binaries (zfs, pv, aws) are not found."
  exit 1
fi

${ZFS} list -o name,${META_AWS_BUCKET} -H -r | awk '$2 != "-"' | while IFS=$'\t' read -r dataset aws_bucket; do
  echo ""
  echo "===== Uploading '$dataset' to '$aws_bucket' ====="
  upload $dataset $aws_bucket
  exit_status=$?

  if [[ $exit_status -ne 0 ]]; then
    echo "Error: Failed to upload '$dataset' dataset to AWS S3 '$aws_bucket' bucket. Terminating process."
    exit $exit_status
  fi

  echo "Dataset '$dataset' has been successfully processed."
  echo ""
done

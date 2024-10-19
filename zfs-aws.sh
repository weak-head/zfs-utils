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

# All uploaded ZFS snapshots are tagged with this tag upon successful completion
# of the upload process. The tag helps in tracking and verifying the upload status.
readonly AWS_UPLOAD_STATUS_TAG='{"TagSet":[{"Key":"zfs-utils.upload-status","Value":"success"}]}'

readonly JQ=$(which jq)
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
    log err "No snapshots found for dataset '$dataset'. Cannot proceed with upload to AWS S3."
    return 1
  fi

  # Check if the latest uploaded file is tagged as complete.
  # Without the completion tag, the file cannot be trusted.
  if [[ -n "$latest_uploaded" ]]; then
    local upload_status=$( ${AWS} s3api get-object-tagging --bucket "$aws_bucket" --key "$aws_directory/$latest_uploaded" \
      | jq -r '.TagSet[] | select(.Key == "zfs-utils.upload-status") | .Value' )

    if [[ "$upload_status" == "success" ]]; then
      log info "The latest uploaded file '$aws_directory/$latest_uploaded' has been validated."
    else
      log warn "The latest uploaded file '$aws_directory/$latest_uploaded' is missing completion tag or is marked as incomplete. Incremental upload is not possible."
      latest_uploaded=""
    fi
  fi

  # Verify if there exist a local version of the dataset snapshot,
  # that corresponds to the latest snapshot uploaded to the AWS S3 bucket.
  # If so we can use the incremental upload instead of the full dataset upload.
  local synced_snapshot=""
  if [[ -n "$latest_uploaded" ]]; then
    local uploaded_label=$( echo $latest_uploaded | awk -F'_' '{print $1}' )
    synced_snapshot=$( ${ZFS} list -Ht snap -o name | grep "^$dataset@$uploaded_label$" )
  fi

  # Check if latest uploaded file matches the latest available snapshot.
  if [[ "$latest_snapshot" == "$synced_snapshot" ]]; then
    log info "Snapshot '$latest_snapshot' is already uploaded. Skipping the dataset '$dataset' upload."
    return 0
  fi

  # A previous snapshot has been uploaded, but there is no corresponding local
  # snapshot available. Incremental upload cannot be applied.
  if [[ -n "$latest_uploaded" && -z "$synced_snapshot" ]]; then
    log warn "No local snapshot matches the latest uploaded file '$latest_uploaded'. Incremental upload is not possible."
  fi

  if [[ -n "$synced_snapshot" ]]; then
    log info "The latest uploaded file '$latest_uploaded' corresponds to the local snapshot '$synced_snapshot'."
    incremental_upload $synced_snapshot $latest_snapshot $aws_bucket $aws_directory
  else
    full_upload $latest_snapshot $aws_bucket $aws_directory
  fi

  local exit_status=$?
  if [[ $exit_status -eq 0 ]]; then
    log info "Dataset '$dataset' has been successfully uploaded to AWS S3 bucket '$aws_bucket'."
  else
    log warn "Failed to upload dataset '$dataset' to AWS S3 bucket '$aws_bucket'."
  fi

  return $exit_status
}

function full_upload {
  local latest_snapshot=${1:-}
  local aws_bucket=${2:-}
  local aws_directory=${3:-}

  local snapshot_label=$( echo "$latest_snapshot" | awk -F'@' '{print $2}' )
  local aws_filename="${snapshot_label}_full"

  local snapshot_size=$( ${ZFS} send --raw -Pnv -cp $latest_snapshot | awk '/size/ {print $2}' )
  local snapshot_size_iec=$(bytes_to_human $snapshot_size)

  log info "Starting full upload of snapshot '$latest_snapshot' to 's3://$aws_bucket/$aws_directory/$aws_filename' (size: $snapshot_size_iec)."

  # Upload latest snapshot
  if ! ${ZFS} send --raw -cp $latest_snapshot \
        | ${PV} -s $snapshot_size \
        | ${AWS} s3 cp - "s3://$aws_bucket/$aws_directory/$aws_filename" \
            --expected-size $snapshot_size > >(capture_errors) 2>&1; then
    return 1
  fi

  log info "Successfully uploaded 's3://$aws_bucket/$aws_directory/$aws_filename'."

  mark_as_completed $aws_bucket "$aws_directory/$aws_filename"
  return $?
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

  log info "Starting incremental upload of snapshot '$latest_snapshot' based on '$synced_snapshot' to 's3://$aws_bucket/$aws_directory/$aws_filename' (size: $snapshot_size_iec)."

  # Upload snapshot diff @synced <-> @latest
  if ! ${ZFS} send --raw -cpi $synced_snapshot $latest_snapshot \
        | ${PV} -s $snapshot_size \
        | ${AWS} s3 cp - "s3://$aws_bucket/$aws_directory/$aws_filename" \
            --expected-size $snapshot_size > >(capture_errors) 2>&1; then
    return 1
  fi

  log info "Successfully uploaded 's3://$aws_bucket/$aws_directory/$aws_filename'."

  mark_as_completed $aws_bucket "$aws_directory/$aws_filename"
  return $?
}

function mark_as_completed {
  local aws_bucket=${1:-}
  local aws_key=${2:-}

  if ! ${AWS} s3api put-object-tagging --bucket "$aws_bucket" --key "$aws_key" \
        --tagging "$AWS_UPLOAD_STATUS_TAG" > >(capture_errors) 2>&1; then
    log err "Failed to set completion tag for 's3://$aws_bucket/$aws_key'."
    return 1
  fi

  log info "Successfully set completion tag for 's3://$aws_bucket/$aws_key'."
}

function validate_aws_bucket {
  local aws_bucket=${1:-}
  local aws_bucket_ls=$( ${AWS} s3 ls "$aws_bucket" 2>&1 )

  if [[ $aws_bucket_ls =~ 'An error occurred (AccessDenied)' ]]; then
    log err "Unable to access AWS S3 bucket '$aws_bucket': Access denied."
    return 1
  elif [[ $aws_bucket_ls =~ 'An error occurred (NoSuchBucket)' ]]; then
    log err "AWS S3 bucket '$aws_bucket' not found."
    return 1
  else
    log info "Access to AWS S3 bucket '$aws_bucket' confirmed."
  fi
}

function check_partial_uploads {
  local aws_bucket=${1:-}
  local current_uploads=$( ${AWS} s3api list-multipart-uploads --bucket "$aws_bucket" )

  if [[ -n $current_uploads ]]; then
    log warn "Incomplete multipart uploads exists for AWS S3 bucket '$aws_bucket'."
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

function capture_errors {
  while IFS= read -r line; do
    log err "$line"
  done
}

function log {
  local level=$1; shift
  case $level in
    (err*) logger -t "zfs-aws" -p "user.err" "$*";     echo "Error: $*" 1>&2 ;;
    (war*) logger -t "zfs-aws" -p "user.warning" "$*"; echo "Warning: $*" 1>&2 ;;
    (inf*) logger -t "zfs-aws" -p "user.info" "$*";    echo "$*" ;;
  esac
}

if [[ -z "$ZFS" || -z "$PV" || -z "$AWS" || -z "$JQ" ]]; then
  log err "Missing required binaries: zfs, pv, aws, jq."
  exit 1
fi

${ZFS} list -o name,${META_AWS_BUCKET} -H -r | awk '$2 != "-"' | while IFS=$'\t' read -r dataset aws_bucket; do
  log info "Initiating upload of dataset '$dataset' to AWS S3 bucket '$aws_bucket'."

  if ! validate_aws_bucket $aws_bucket; then
    log warn "Skipping dataset '$dataset' upload."
    continue
  fi

  check_partial_uploads $aws_bucket
  upload $dataset $aws_bucket
done

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
readonly ZFS_META_AWS_BUCKET="zfs-utils:aws-bucket"

# All uploaded ZFS snapshots are tagged with this tag upon successful completion
# of the upload process. The tag helps in tracking and verifying the upload status.
readonly AWS_TAG_UPLOAD_STATUS="zfs-utils.upload-status"

readonly AWS_META_SNAPSHOT_NAME="snapshot-name"
readonly AWS_META_SNAPSHOT_BASE="snapshot-base"
readonly AWS_META_SNAPSHOT_KIND="snapshot-kind"

JQ=$(command -v jq)
PV=$(command -v pv)
ZFS=$(command -v zfs)
AWS=$(command -v aws)
readonly JQ PV ZFS AWS

function log {
  local level=$1; shift
  case $level in
    (err*) logger -t "zfs-aws" -p "user.err" "$*"; echo "Error: $*" 1>&2 ;;
    (war*) logger -t "zfs-aws" -p "user.warning" "$*"; echo "Warning: $*" 1>&2 ;;
    (inf*) logger -t "zfs-aws" -p "user.info" "$*"; echo "$*" ;;
  esac
}

function capture_errors {
  while IFS= read -r line; do
    log err "${line}"
  done
}

function get_upload_status {
  local aws_bucket=$1 aws_key=$2

  ${AWS} s3api get-object-tagging --bucket "${aws_bucket}" --key "${aws_key}" \
    | jq -r ".TagSet[] | select(.Key == \"${AWS_TAG_UPLOAD_STATUS}\").Value"
}

function set_upload_status {
  local aws_bucket=$1 aws_key=$2 status=$3

  ${AWS} s3api put-object-tagging --bucket "${aws_bucket}" --key "${aws_key}" \
    --tagging "{\"TagSet\":[{\"Key\":\"${AWS_TAG_UPLOAD_STATUS}\",\"Value\":\"${status}\"}]}" \
    > >(capture_errors) 2>&1
}

function upload {
  local dataset=$1 aws_bucket=$2
  local aws_directory="${dataset//\//.}"

  local synced_snapshot=""
  local latest_snapshot=""
  local latest_uploaded=""

  latest_snapshot=$( ${ZFS} list -Ht snap -o name,creation -p | grep "^${dataset}@" | sort -n -k2 | tail -1 | awk '{print $1}' )
  latest_uploaded=$( ${AWS} s3 ls "s3://${aws_bucket}/${aws_directory}/" | grep -v "/$" | sort -r | head -1 | awk '{print $4}' )

  if [[ -z "${latest_snapshot}" ]]; then
    log err "No available snapshots found for dataset '${dataset}'. Upload to AWS S3 cannot proceed."
    return 1
  fi

  if [[ -n "${latest_uploaded}" ]]; then
    local upload_status=""
    upload_status=$(get_upload_status "${aws_bucket}" "${aws_directory}/${latest_uploaded}")

    if [[ "${upload_status}" == "success" ]]; then
      synced_snapshot=$( ${ZFS} list -Ht snap -o name | grep "^${dataset}@${latest_uploaded%_*}$" )

      if [[ "${latest_snapshot}" == "${synced_snapshot}" ]]; then
        log info "Snapshot '${latest_snapshot}' has already been uploaded to '${aws_directory}'. No further action required."
        return 0
      elif [[ -z "${synced_snapshot}" ]]; then
        log warn "No corresponding local snapshot found for the uploaded file '${latest_uploaded}'. Incremental upload cannot proceed."
      else
        log info "Uploaded file '${latest_uploaded}' matches local snapshot '${synced_snapshot}'. Preparing for incremental upload."
      fi
    else
      log warn "The latest uploaded file '${aws_directory}/${latest_uploaded}' is missing a completion tag or is marked as incomplete. Incremental upload cannot proceed."
    fi
  fi

  if [[ -n "${synced_snapshot}" ]]; then
    upload_incr "${synced_snapshot}" "${latest_snapshot}" "${aws_bucket}" "${aws_directory}"
  else
    upload_full "${latest_snapshot}" "${aws_bucket}" "${aws_directory}"
  fi
}

function upload_full {
  local snapshot=$1 aws_bucket=$2 aws_directory=$3

  local aws_filename=""
  local snapshot_size=""

  aws_filename="${snapshot##*@}_full"
  snapshot_size=$( ${ZFS} send --raw -Pnv -cp "${snapshot}" | awk '/size/ {print $2}' )
  
  log info "Initiating full upload of snapshot '${snapshot}' to 's3://${aws_bucket}/${aws_directory}/${aws_filename}' (size: $(bytes_to_human "${snapshot_size}"))."

  if ! ${ZFS} send --raw -cp "${snapshot}" \
        | ${PV} -s "${snapshot_size}" \
        | ${AWS} s3 cp - "s3://${aws_bucket}/${aws_directory}/${aws_filename}" \
          --expected-size "${snapshot_size}" \
          --metadata "${AWS_META_SNAPSHOT_NAME}=${snapshot},${AWS_META_SNAPSHOT_KIND}=full" \
          > >(capture_errors) 2>&1; then
    return 1
  fi

  set_upload_status "${aws_bucket}" "${aws_directory}/${aws_filename}" "success"
}

function upload_incr {
  local synced_snapshot=$1 latest_snapshot=$2 aws_bucket=$3 aws_directory=$4

  local aws_filename=""
  local snapshot_size=""

  aws_filename="${latest_snapshot##*@}_incr"
  snapshot_size=$( ${ZFS} send --raw -Pnv -cpi "${synced_snapshot}" "${latest_snapshot}" | awk '/size/ {print $2}' )

  log info "Initiating incremental upload of snapshot '${latest_snapshot}' based on '${synced_snapshot}' to 's3://${aws_bucket}/${aws_directory}/${aws_filename}' (size: $(bytes_to_human "${snapshot_size}"))."

  if ! ${ZFS} send --raw -cpi "${synced_snapshot}" "${latest_snapshot}" \
        | ${PV} -s "${snapshot_size}" \
        | ${AWS} s3 cp - "s3://${aws_bucket}/${aws_directory}/${aws_filename}" \
          --expected-size "${snapshot_size}" \
          --metadata "${AWS_META_SNAPSHOT_NAME}=${latest_snapshot},${AWS_META_SNAPSHOT_BASE}=${synced_snapshot},${AWS_META_SNAPSHOT_KIND}=incremental" \
          > >(capture_errors) 2>&1; then
    return 1
  fi

  set_upload_status "${aws_bucket}" "${aws_directory}/${aws_filename}" "success"
}

function check_aws_access {
  local aws_bucket=$1

  local aws_bucket_ls=""
  aws_bucket_ls=$( ${AWS} s3 ls "${aws_bucket}" 2>&1 )

  if [[ "${aws_bucket_ls}" == *"An error occurred (AccessDenied)"* ]]; then
    log err "Access denied: Unable to access AWS S3 bucket '${aws_bucket}'."
    return 1
  elif [[ "${aws_bucket_ls}" == *"An error occurred (NoSuchBucket)"* ]]; then
    log err "AWS S3 bucket '${aws_bucket}' does not exist."
    return 1
  fi
}

function check_incomplete_uploads {
  local aws_bucket=$1

  local incomplete_uploads=""
  incomplete_uploads=$( ${AWS} s3api list-multipart-uploads --bucket "${aws_bucket}" | ${JQ} '.Uploads | length > 0' )

  if [[ "${incomplete_uploads}" == "true" ]]; then
    log warn "Found incomplete multipart uploads in AWS S3 bucket '${aws_bucket}'. Consider reviewing or cleaning up."
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

if [[ -z "${ZFS}" || -z "${PV}" || -z "${AWS}" || -z "${JQ}" ]]; then
  log err "Missing required binaries: zfs, pv, aws, jq."
  exit 1
fi

${ZFS} list -o name,${ZFS_META_AWS_BUCKET} -H -r \
    | awk '$2 != "-"' \
    | while IFS=$'\t' read -r dataset aws_bucket; do
  log info "Starting upload process for dataset '${dataset}' to AWS S3 bucket '${aws_bucket}'."

  if ! check_aws_access "${aws_bucket}"; then
    log warn "Validation failed for AWS S3 bucket '${aws_bucket}'. Skipping upload for dataset '${dataset}'."
    continue
  fi

  check_incomplete_uploads "${aws_bucket}"

  if upload "${dataset}" "${aws_bucket}"; then
    log info "Successfully uploaded dataset '${dataset}' to AWS S3 bucket '${aws_bucket}'."
  else
    log error "Upload failed for dataset '${dataset}' to AWS S3 bucket '${aws_bucket}'."
  fi
done

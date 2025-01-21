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

readonly STATUS_SUCCESS="success"

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

JQ=$(command -v jq)
PV=$(command -v pv)
ZFS=$(command -v zfs)
AWS=$(command -v aws)
readonly JQ PV ZFS AWS

function print_usage {
  local VERSION="v0.3.0"

  echo -e "${COLORS[TITLE]}$(basename "$0")${NC} ${COLORS[TEXT]}${VERSION}${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Usage:${NC}"
  echo -e "  ${COLORS[CMD]}$(basename "$0")${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}Description:${NC}"
  echo -e "  This script automates the backup of ZFS datasets to AWS S3."
  echo -e "  It uses custom ZFS metadata properties to specify the AWS S3 bucket"
  echo -e "  for backups, providing both full and incremental backup capabilities."
  echo -e ""
  echo -e "  Dataset snapshots could be restored directly from AWS S3 bucket:"
  echo -e "  $> ${COLORS[CMD]}aws s3 cp s3://bucket/directory/file - | pv | zfs recv odin/services/cloud${NC}"
  echo -e ""
  echo -e "${COLORS[TITLE]}ZFS Metadata:${NC}"
  echo -e "  ${COLORS[ARGS]}zfs-utils:aws-bucket${NC}"
  echo -e "    This custom ZFS metadata property specifies the AWS S3 bucket"
  echo -e "    designated for storing dataset backups. To enable AWS S3 backups"
  echo -e "    for a dataset, set this custom property to the target bucket name."
  echo -e ""
  echo -e "    Example:"
  echo -e "    $> ${COLORS[CMD]}zfs set zfs-utils:aws-bucket=backup.bucket.aws odin/services/cloud${NC}"
  echo -e "      This command marks the 'odin/services/cloud' dataset for AWS S3 backups,"
  echo -e "      and specifies 'backup.bucket.aws' as the backup destination."
  echo -e ""
}

function log {
  local level=$1; shift
  case $level in
    (err*) logger -t "zfs-to-s3" -p "user.err" "$*"; echo -e "${COLORS[ERROR]}Error: $*${NC}" 2>&2 ;;
    (war*) logger -t "zfs-to-s3" -p "user.warning" "$*"; echo -e "${COLORS[WARN]}Warning: $*${NC}" 1>&2 ;;
    (inf*) logger -t "zfs-to-s3" -p "user.info" "$*"; echo -e "${COLORS[INFO]}$*${NC}" ;;
  esac
}

function capture_errors {
  while IFS= read -r line; do
    log err "${line}"
  done
}

function get_tag {
  local aws_bucket=$1
  local aws_key=$2
  local tag_key=$3

  ${AWS} s3api get-object-tagging --bucket "${aws_bucket}" --key "${aws_key}" \
    | ${JQ} -r ".TagSet[] | select(.Key == \"${tag_key}\").Value"
}

function set_tag {
  local aws_bucket=$1
  local aws_key=$2
  local tag_key=$3
  local tag_value=$4

  ${AWS} s3api put-object-tagging \
    --bucket "${aws_bucket}" --key "${aws_key}" \
    --tagging "{\"TagSet\":[{\"Key\":\"${tag_key}\",\"Value\":\"${tag_value}\"}]}" \
    > >(capture_errors) 2>&1
}

function get_meta {
  local aws_bucket=$1
  local aws_key=$2
  local meta_key=$3

  ${AWS} s3api head-object --bucket "${aws_bucket}" --key "${aws_key}" --output json \
    | ${JQ} -r ".Metadata[\"${meta_key}\"]"
}

function gen_name {
  local snapshot=$1 
  local tag=$2
  local label="${snapshot##*@}"

  echo "${label}_${tag}"
}

function upload {
  local dataset=$1 
  local aws_bucket=$2
  local aws_directory="${dataset//\//.}"
  local aws_key
  local uploaded_status
  local synced_snapshot
  local latest_snapshot
  local latest_uploaded

  latest_snapshot=$( ${ZFS} list -Ht snap -o name,creation -p | grep "^${dataset}@" | sort -n -k2 | tail -1 | awk '{print $1}' )
  latest_uploaded=$( ${AWS} s3 ls "s3://${aws_bucket}/${aws_directory}/" | grep -v "/$" | sort -r | head -1 | awk '{print $4}' )

  if [[ -z "${latest_snapshot}" ]]; then
    log err "Upload cannot proceed: no snapshots for '${dataset}'."
    return 1
  fi

  if [[ -n "${latest_uploaded}" ]]; then
    aws_key="${aws_directory}/${latest_uploaded}"
    uploaded_status=$( get_tag "${aws_bucket}" "${aws_key}" "${AWS_TAG_UPLOAD_STATUS}" )
    uploaded_snapshot=$( get_meta "${aws_bucket}" "${aws_key}" "${AWS_META_SNAPSHOT_NAME}" )

    if [[ "${uploaded_status}" == "${STATUS_SUCCESS}" && -n "${uploaded_snapshot}" ]]; then
      synced_snapshot=$( ${ZFS} list -Ht snap -o name | grep "^${uploaded_snapshot}$" )

      if [[ "${latest_snapshot}" == "${synced_snapshot}" ]]; then
        log info "Snapshot '${latest_snapshot}' has already been uploaded."
        return 0
      elif [[ -z "${synced_snapshot}" ]]; then
        log warn "Incremental upload cannot proceed: no local snapshot '${uploaded_snapshot}'."
      else
        log info "Preparing for incremental upload (${synced_snapshot})."
      fi

    else
      log warn "Incremental upload cannot proceed: '${aws_key}' is incomplete."
    fi
  fi

  if [[ -n "${synced_snapshot}" ]]; then
    upload_incr "${synced_snapshot}" "${latest_snapshot}" "${aws_bucket}" "${aws_directory}"
  else
    upload_full "${latest_snapshot}" "${aws_bucket}" "${aws_directory}"
  fi
}

function upload_full {
  local snapshot=$1
  local aws_bucket=$2
  local aws_directory=$3
  local aws_filename=""
  local snapshot_size=""

  aws_filename=$( gen_name "${snapshot}" "full" )
  snapshot_size=$( ${ZFS} send --raw -Pnv -cp "${snapshot}" | awk '/size/ {print $2}' )
  
  log info "Full upload '${snapshot}' to 's3://${aws_bucket}/${aws_directory}/${aws_filename}' ($(bytes_to_human "${snapshot_size}"))."

  if ! ${ZFS} send --raw -cp "${snapshot}" \
        | ${PV} -s "${snapshot_size}" \
        | ${AWS} s3 cp - "s3://${aws_bucket}/${aws_directory}/${aws_filename}" \
          --expected-size "${snapshot_size}" \
          --metadata "${AWS_META_SNAPSHOT_NAME}=${snapshot},${AWS_META_SNAPSHOT_KIND}=full" \
          > >(capture_errors) 2>&1; then
    return 1
  fi

  set_tag "${aws_bucket}" "${aws_directory}/${aws_filename}" "${AWS_TAG_UPLOAD_STATUS}" "${STATUS_SUCCESS}"
}

function upload_incr {
  local synced_snapshot=$1
  local latest_snapshot=$2
  local aws_bucket=$3
  local aws_directory=$4
  local aws_filename=""
  local snapshot_size=""

  aws_filename=$( gen_name "${latest_snapshot}" "incr" )
  snapshot_size=$( ${ZFS} send --raw -Pnv -cpi "${synced_snapshot}" "${latest_snapshot}" | awk '/size/ {print $2}' )

  log info "Incremental upload '${latest_snapshot}' to 's3://${aws_bucket}/${aws_directory}/${aws_filename}' ($(bytes_to_human "${snapshot_size}"))."

  if ! ${ZFS} send --raw -cpi "${synced_snapshot}" "${latest_snapshot}" \
        | ${PV} -s "${snapshot_size}" \
        | ${AWS} s3 cp - "s3://${aws_bucket}/${aws_directory}/${aws_filename}" \
          --expected-size "${snapshot_size}" \
          --metadata "${AWS_META_SNAPSHOT_NAME}=${latest_snapshot},${AWS_META_SNAPSHOT_BASE}=${synced_snapshot},${AWS_META_SNAPSHOT_KIND}=incremental" \
          > >(capture_errors) 2>&1; then
    return 1
  fi

  set_tag "${aws_bucket}" "${aws_directory}/${aws_filename}" "${AWS_TAG_UPLOAD_STATUS}" "${STATUS_SUCCESS}"
}

function check_aws_access {
  local aws_bucket=$1
  local aws_bucket_ls=""

  aws_bucket_ls=$( ${AWS} s3 ls "${aws_bucket}" 2>&1 )

  if [[ "${aws_bucket_ls}" == *"An error occurred (AccessDenied)"* ]]; then
    log err "Access denied to '${aws_bucket}' bucket."
    return 1
  elif [[ "${aws_bucket_ls}" == *"An error occurred (NoSuchBucket)"* ]]; then
    log err "'${aws_bucket}' bucket does not exist."
    return 1
  fi
}

function check_incomplete_uploads {
  local aws_bucket=$1
  local incomplete_uploads=""

  incomplete_uploads=$( ${AWS} s3api list-multipart-uploads --bucket "${aws_bucket}" | ${JQ} '.Uploads | length > 0' )

  if [[ "${incomplete_uploads}" == "true" ]]; then
    log warn "Found incomplete multipart uploads in '${aws_bucket}' bucket."
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

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help) print_usage; exit 0 ;;
    *) break ;;
  esac
done

if [[ -z "${ZFS}" || -z "${PV}" || -z "${AWS}" || -z "${JQ}" ]]; then
  log err "Missing required binaries: zfs, pv, aws, jq."
  exit 1
fi

${ZFS} list -o name,${ZFS_META_AWS_BUCKET} -H -r \
    | awk '$2 != "-"' \
    | while IFS=$'\t' read -r dataset aws_bucket; do
  log info "Preparing '${dataset}' upload to '${aws_bucket}' bucket."

  if ! check_aws_access "${aws_bucket}"; then
    log warn "Skipping '${dataset}' upload: validation failed."
    continue
  fi

  check_incomplete_uploads "${aws_bucket}"

  if upload "${dataset}" "${aws_bucket}"; then
    log info "Uploaded '${dataset}'."
  else
    log error "Failed to upload '${dataset}'."
  fi
done

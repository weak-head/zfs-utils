<div align="center">
  
  # ZFS utils

  Opinionated set of scripts to automate ZFS snapshots, dataset replication and backups to AWS. 

  <p align="center">
    <a href="https://github.com/weak-head/zfs-utils/actions/workflows/lint.yaml">
      <img alt="lint" 
           src="https://img.shields.io/github/actions/workflow/status/weak-head/zfs-utils/lint.yaml?label=lint"/>
    </a>
    <a href="https://github.com/weak-head/zfs-utils/releases">
      <img alt="GitHub Release"
           src="https://img.shields.io/github/v/release/weak-head/zfs-utils?color=blue" />
    </a>
    <a href="https://www.gnu.org/software/bash/">
      <img alt="#!/bin/bash" 
           src="https://img.shields.io/badge/-%23!%2Fbin%2Fbash-1f425f.svg?logo=image%2Fpng%3Bbase64%2CiVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAyZpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw%2FeHBhY2tldCBiZWdpbj0i77u%2FIiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8%2BIDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuNi1jMTExIDc5LjE1ODMyNSwgMjAxNS8wOS8xMC0wMToxMDoyMCAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIENDIDIwMTUgKFdpbmRvd3MpIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOkE3MDg2QTAyQUZCMzExRTVBMkQxRDMzMkJDMUQ4RDk3IiB4bXBNTTpEb2N1bWVudElEPSJ4bXAuZGlkOkE3MDg2QTAzQUZCMzExRTVBMkQxRDMzMkJDMUQ4RDk3Ij4gPHhtcE1NOkRlcml2ZWRGcm9tIHN0UmVmOmluc3RhbmNlSUQ9InhtcC5paWQ6QTcwODZBMDBBRkIzMTFFNUEyRDFEMzMyQkMxRDhEOTciIHN0UmVmOmRvY3VtZW50SUQ9InhtcC5kaWQ6QTcwODZBMDFBRkIzMTFFNUEyRDFEMzMyQkMxRDhEOTciLz4gPC9yZGY6RGVzY3JpcHRpb24%2BIDwvcmRmOlJERj4gPC94OnhtcG1ldGE%2BIDw%2FeHBhY2tldCBlbmQ9InIiPz6lm45hAAADkklEQVR42qyVa0yTVxzGn7d9Wy03MS2ii8s%2BeokYNQSVhCzOjXZOFNF4jx%2BMRmPUMEUEqVG36jo2thizLSQSMd4N8ZoQ8RKjJtooaCpK6ZoCtRXKpRempbTv5ey83bhkAUphz8fznvP8znn%2B%2F3NeEEJgNBoRRSmz0ub%2FfuxEacBg%2FDmYtiCjgo5NG2mBXq%2BH5I1ogMRk9Zbd%2BQU2e1ML6VPLOyf5tvBQ8yT1lG10imxsABm7SLs898GTpyYynEzP60hO3trHDKvMigUwdeaceacqzp7nOI4n0SSIIjl36ao4Z356OV07fSQAk6xJ3XGg%2BLCr1d1OYlVHp4eUHPnerU79ZA%2F1kuv1JQMAg%2BE4O2P23EumF3VkvHprsZKMzKwbRUXFEyTvSIEmTVbrysp%2BWr8wfQHGK6WChVa3bKUmdWou%2BjpArdGkzZ41c1zG%2Fu5uGH4swzd561F%2BuhIT4%2BLnSuPsv9%2BJKIpjNr9dXYOyk7%2FBZrcjIT4eCnoKgedJP4BEqhG77E3NKP31FO7cfQA5K0dSYuLgz2TwCWJSOBzG6crzKK%2BohNfni%2Bx6OMUMMNe%2Fgf7ocbw0v0acKg6J8Ql0q%2BT%2FAXR5PNi5dz9c71upuQqCKFAD%2BYhrZLEAmpodaHO3Qy6TI3NhBpbrshGtOWKOSMYwYGQM8nJzoFJNxP2HjyIQho4PewK6hBktoDcUwtIln4PjOWzflQ%2Be5yl0yCCYgYikTclGlxadio%2BBQCSiW1UXoVGrKYwH4RgMrjU1HAB4vR6LzWYfFUCKxfS8Ftk5qxHoCUQAUkRJaSEokkV6Y%2F%2BJUOC4hn6A39NVXVBYeNP8piH6HeA4fPbpdBQV5KOx0QaL1YppX3Jgk0TwH2Vg6S3u%2BdB91%2B%2FpuNYPYFl5uP5V7ZqvsrX7jxqMXR6ff3gCQSTzFI0a1TX3wIs8ul%2Bq4HuWAAiM39vhOuR1O1fQ2gT%2F26Z8Z5vrl2OHi9OXZn995nLV9aFfS6UC9JeJPfuK0NBohWpCHMSAAsFe74WWP%2BvT25wtP9Bpob6uGqqyDnOtaeumjRu%2ByFu36VntK%2FPA5umTJeUtPWZSU9BCgud661odVp3DZtkc7AnYR33RRC708PrVi1larW7XwZIjLnd7R6SgSqWSNjU1B3F72pz5TZbXmX5vV81Yb7Lg7XT%2FUXriu8XLVqw6c6XqWnBKiiYU%2BMt3wWF7u7i91XlSEITwSAZ%2FCzAAHsJVbwXYFFEAAAAASUVORK5CYII%3D" /></a>
    <a href="https://opensource.org/license/mit">
      <img alt="MIT License" 
           src="https://img.shields.io/badge/license-MIT-blue" />
    </a>
  </p>
</div>


## Table of Contents
- [Overview](#overview)
- [Gettings Started](#getting-started)
- [zfs-info](#zfs-info)
- [zfs-snap](#zfs-snap)
- [zfs-clear](#zfs-clear)
- [zfs-to-zfs](#zfs-to-zfs)
- [zfs-to-s3](#zfs-to-s3)

## Overview

ZFS utils is a set of bash scripts for automating ZFS snapshots, cleanup, replication, backups, and metadata inspection. It leverages custom ZFS properties for efficient dataset management.

- `zfs-info`: Displays custom ZFS metadata properties, including snapshot settings, AWS S3 backup configuration, and replication targets.
- `zfs-snap`: Creates snapshots for configured datasets, typically scheduled via cron.
- `zfs-clear`: Interactively removes old snapshots based on user-defined patterns while preserving recent and latest snapshots.
- `zfs-to-zfs`: Automates dataset replication across pools with full and incremental sync.
- `zfs-to-s3`: Backs up datasets to AWS S3, supporting direct restoration via AWS CLI.

## Getting Started

This project includes several scripts, each with specific dependencies. The only required dependency for all scripts is `zfs`. Additional dependencies, which depend on the script being used, include `pv`, `aws`, and `jq`.

The scripts' behavior is controlled through ZFS metadata, which determines whether actions like snapshots, replication, or AWS S3 backups should be performed.

| Script        | ZFS Metadata Key               | Description                     |
|---------------|--------------------------------|---------------------------------|
| `zfs-snap`    | `zfs-utils:auto-snap`          | Enables automatic snapshots.    |
| `zfs-to-s3`   | `zfs-utils:aws-bucket`         | Enables AWS S3 backups.         |
| `zfs-to-zfs`  | `zfs-utils:replication-target` | Enables dataset replication.    |

You can configure ZFS metadata using the `zfs set` command. Here are some examples:

```bash
# Enable automatic snapshots for a dataset
zfs set zfs-utils:auto-snap=true odin/services/cloud

# Configure AWS S3 backups for a dataset
zfs set zfs-utils:aws-bucket=backup.bucket.aws odin/services/cloud

# Define a replication target for a dataset
zfs set zfs-utils:replication-target=thor/services/cloud odin/services/cloud
```

To install the scripts, run:

```bash
# This installs the scripts to `/usr/local/sbin/` 
make install

# This installs cron jobs to `/etc/cron.d/zfs-utils`
make install-cron
```

By default the following cron schedule is created:

```cron
# At 01:00 on day-of-month 1 => create ZFS snapshots
0 1 1 * * root zfs-snap

# At 02:00 on day-of-month 1 => upload ZFS snapshots to AWS S3
0 2 1 * * root zfs-to-s3
```

To view all datasets and their associated metadata, use the `zfs-info` command.

## zfs-info

This script provides a summary of ZFS metadata properties for all ZFS datasets.  
It fetches and formats custom metadata properties, such as:
  - `zfs-utils:auto-snap`: Indicates if automatic snapshots are enabled.
  - `zfs-utils:aws-bucket`: Specifies the associated AWS S3 bucket (if any).
  - `zfs-utils:replication-target`: Specifies the target dataset for replication.

**Syntax**

```bash
zfs-info [--help]
```

**Options**

- `--help`: Displays usage instructions and exits.  

## zfs-snap

`zfs-snap` automates the creation of ZFS snapshots for datasets explicitly configured for automatic snapshotting. 
Each snapshot is labeled with a timestamp using the default `YYYY-MM-DD` format, though users can customize this label by specifying a format with standard `date` syntax.  

The script exclusively detects and processes datasets marked with the `zfs-utils:auto-snap=true` metadata, ensuring that only intended datasets are snapshotted. 
Additionally, it logs operations with categorized messages, making debugging and tracking actions more efficient and transparent.

**Syntax**

```bash
zfs-snap [--help] [-l <format> | --label <format>]
```  

**Options**

- `-l <format>`, `--label <format>`: Snapshot label format using `date` syntax.  
- `--help`: Displays usage instructions and exits.  

**Examples**

```bash
# Creates a snapshot with the default label, e.g., `2025-01-25`.
zfs-snap

# Creates a snapshot labeled `daily_2025-01-25`, useful for daily backups.
zfs-snap -l daily_%Y-%m-%d

# Creates a snapshot with a timestamp, e.g., `2025-01-25_15-45`, for precise tracking.
zfs-snap -l %Y-%m-%d_%H-%M

# Creates a static snapshot labeled `before_migration`, useful for critical system changes.  
zfs-snap -l before_migration
```  

## zfs-clear

TBD

## zfs-to-zfs

TBD

## zfs-to-s3

TBD

## Contributing

Contributions, bug reports, and feature requests are welcome! Feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See the LICENSE file for details.


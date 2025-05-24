# CUBE Region Minecraft Server Apps

This repository provides Kubernetes manifests for deploying Minecraft server applications using the ArgoCD App of Apps pattern.

## Overview

This repository contains manifests for deploying Minecraft server applications on a Kubernetes cluster for the CUBE Region.

Currently, only vanilla Minecraft servers are provided via Kubernetes. Miniaturia and cocricot servers are provided using docker compose on VM.


## Backup Management

### About Automated Backups

All servers are configured to automatically back up every 3 hours.

### Backup Operations

#### How to Copy Data Locally

Run the following script to copy server data to your local machine:

```bash
./scripts/copy-to-local.sh
```

The script performs the following operations:
1. Presents an interactive selector for namespace and pod
2. Disables auto-save on the Minecraft server
3. Forces a save of all worlds
4. Copies data to `./backup` directory
5. Re-enables auto-save

#### How to Manually Trigger Automated Backups

Run the following script to trigger an automated backup:

```bash
./scripts/trigger-backup.sh
```

The script performs the following operations:
1. Presents an interactive selector for namespace and pod
2. Presents an interactive selector for the backup container
3. Triggers the backup process with confirmation

#### How to Restore a Backup

The easiest way to restore a backup is to use the provided script:

```bash
./scripts/restore-backup.sh
```

This script performs the following operations:
1. Interactive selection of namespace, StatefulSet, and Pod
2. Listing and selection of available backups
3. Server shutdown
4. Backup restoration (temporary ConfigMap creation, CronJob execution, and cleanup after completion)
5. Server restart

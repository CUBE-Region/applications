#!/bin/bash

# Import utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Default namespace pattern
NAMESPACE_PATTERN="minecraft"

# Main function
main() {
  # Select pod from namespace
  print_info "Selecting pod from namespaces matching: $NAMESPACE_PATTERN"

  # Get namespace and pod ID from the selection
  SELECTION=$(select_pod_by_namespace "$NAMESPACE_PATTERN")

  if [[ $? -ne 0 ]]; then
    print_error "Failed to select pod"
    exit 1
  fi

  read -r NAMESPACE POD_ID <<<"$SELECTION"

  print_success "Selected namespace: $NAMESPACE"
  print_success "Selected pod: $POD_ID"
  echo

  # Extract StatefulSet name from pod ID
  STS_ID=$(echo "$POD_ID" | sed 's/-[0-9]\+$//') # Get available containers in the pod
  print_info "Fetching containers in pod $POD_ID..."
  CONTAINERS=$(kubectl get pod -n "$NAMESPACE" "$POD_ID" -o jsonpath="{.spec.containers[*].name}" 2>/dev/null)

  if [[ -z "$CONTAINERS" ]]; then
    print_error "No containers found in pod: $POD_ID"
    exit 1
  fi

  # Look for backup container (ending with mc-backup)
  BACKUP_CONTAINER=""
  for container in $CONTAINERS; do
    if [[ "$container" == *-mc-backup ]]; then
      BACKUP_CONTAINER="$container"
      break
    fi
  done

  # Set container ID to backup container if found
  local CONTAINER_ID
  if [[ -n "$BACKUP_CONTAINER" ]]; then
    CONTAINER_ID="$BACKUP_CONTAINER"
    print_info "Automatically selected backup container: $CONTAINER_ID"
  else
    # Create an array of containers for manual selection
    local -a container_array
    for container in $CONTAINERS; do
      container_array+=("$container")
    done

    print_warning "No container with name ending in '-mc-backup' found. Please select a container manually:"

    # Let user select a container using fzf
    CONTAINER_ID=$(printf "%s\n" "${container_array[@]}" | fzf --height 40% --reverse --header="Select a container for restoration")

    if [[ -z "$CONTAINER_ID" ]]; then
      print_error "No container selected"
      exit 1
    fi
  fi

  print_success "Selected container: $CONTAINER_ID"

  # List snapshots
  print_info "Retrieving available backup snapshots..."

  # Create a temporary file for snapshot list with headers
  TMP_SNAPSHOT_FILE=$(mktemp /tmp/snapshots.XXXXXX)

  # Get formatted snapshot list with headers directly from restic
  kubectl exec -n "${NAMESPACE}" "${POD_ID}" -c "${CONTAINER_ID}" -- restic snapshots >"$TMP_SNAPSHOT_FILE"
  if [[ $? -ne 0 ]]; then
    rm -f "$TMP_SNAPSHOT_FILE"
    print_error "Failed to retrieve snapshots from container"
    exit 1
  fi

  # Count lines in the snapshot file (should be more than just headers)
  SNAPSHOT_COUNT=$(grep -c "^[a-z0-9]" "$TMP_SNAPSHOT_FILE")
  if [[ $SNAPSHOT_COUNT -eq 0 ]]; then
    rm -f "$TMP_SNAPSHOT_FILE"
    print_error "No backups available to restore"
    exit 1
  fi

  # Set header line count for fzf (ID and header separator line)
  HEADER_LINE_COUNT=2

  # Count lines in the file to find the last separator line (not the header one)
  TOTAL_LINES=$(wc -l <"$TMP_SNAPSHOT_FILE")
  LAST_SEPARATOR_LINE=$(grep -n "^-\{10,\}" "$TMP_SNAPSHOT_FILE" | tail -1 | cut -d":" -f1)

  if [[ -n "$LAST_SEPARATOR_LINE" && "$LAST_SEPARATOR_LINE" -gt 2 ]]; then
    # Remove only the footer (last separator line onwards)
    sed -i "${LAST_SEPARATOR_LINE},${TOTAL_LINES}d" "$TMP_SNAPSHOT_FILE"
  fi

  # Let user select a snapshot with fixed header
  print_info "Please select a backup to restore:"
  print_info "Found $(grep -c "^[a-z0-9]" "$TMP_SNAPSHOT_FILE") snapshots:"

  SELECTED_SNAPSHOT=$(cat "$TMP_SNAPSHOT_FILE" | fzf --height 40% --reverse \
    --header="Select a backup to restore" \
    --header-lines=$HEADER_LINE_COUNT)

  rm -f "$TMP_SNAPSHOT_FILE" # Clean up temporary file

  if [[ -z "$SELECTED_SNAPSHOT" ]]; then
    print_error "No backup selected"
    exit 1
  fi

  # Extract snapshot ID from the selected line (without numbers)
  if [[ "$SELECTED_SNAPSHOT" =~ ^([a-z0-9]+)[[:space:]] ]]; then
    BACKUP_ID="${BASH_REMATCH[1]}"
  else
    print_error "Could not parse backup ID from selection"
    exit 1
  fi
  print_success "Selected backup ID: $BACKUP_ID"
  echo

  # Confirmation with more details
  if ! confirm_action "Are you sure you want to restore backup $BACKUP_ID to pod $POD_ID? This will stop the server and cannot be undone."; then
    print_warning "Operation cancelled by user"
    exit 0
  fi

  print_info "Starting backup restoration process..."

  # Create temporary ConfigMap
  print_info "Creating temporary configuration for restoration..."
  kubectl create configmap -n "${NAMESPACE}" minecraft-cube-restore-config --from-literal=backup_id="${BACKUP_ID}" --dry-run=client -o yaml | kubectl apply -f -
  if [[ $? -ne 0 ]]; then
    print_error "Failed to create temporary ConfigMap"
    exit 1
  fi

  # Scale down the server
  print_info "Stopping Minecraft server..."
  kubectl scale --namespace "${NAMESPACE}" statefulset "${STS_ID}" --replicas=0

  print_info "Waiting for pod to terminate..."
  kubectl wait --namespace "${NAMESPACE}" --for=delete pod/"${POD_ID}" --timeout=120s
  if [[ $? -ne 0 ]]; then
    print_warning "Timeout waiting for pod to terminate, continuing anyway..."
  fi

  # Create and run a job directly from the CronJob template (works with suspended CronJob)
  print_info "Starting backup restoration job..."
  JOB_NAME="minecraft-cube-restore-manual-$(date +%s)"
  print_info "Creating restoration job: $JOB_NAME..."
  kubectl create job -n "${NAMESPACE}" --from=cronjob/minecraft-cube-vanilla-restore-backup "${JOB_NAME}"
  if [[ $? -ne 0 ]]; then
    print_error "Failed to create restoration job"
    print_info "Restarting server..."
    kubectl scale --namespace "${NAMESPACE}" statefulset "${STS_ID}" --replicas=1
    exit 1
  fi

  # Wait for job completion with a longer timeout
  print_info "Waiting for backup restoration to complete (this may take a few minutes)..."
  kubectl wait --namespace "${NAMESPACE}" --for=condition=complete job/"${JOB_NAME}" --timeout=600s
  JOB_STATUS=$?

  # Display job logs
  if [[ $JOB_STATUS -eq 0 ]]; then
    print_success "Restoration job completed"
  else
    print_warning "Restoration job may have timed out or failed, displaying logs:"
  fi
  print_info "Restoration job logs:"
  kubectl logs -n "${NAMESPACE}" job/"${JOB_NAME}"

  # Delete temporary ConfigMap
  print_info "Deleting temporary configuration..."
  kubectl delete configmap -n "${NAMESPACE}" minecraft-cube-restore-config
  if [[ $? -ne 0 ]]; then
    print_warning "Failed to delete temporary ConfigMap, please check manually"
  fi

  # Restart server
  print_info "Restarting the Minecraft server..."
  kubectl scale --namespace "${NAMESPACE}" statefulset "${STS_ID}" --replicas=1
  if [[ $? -ne 0 ]]; then
    print_error "Failed to restart server"
    return 1
  fi

  if [[ $JOB_STATUS -eq 0 ]]; then
    print_success "Backup restoration completed successfully!"
    print_info "The server is now restarting. It may take a few minutes to become fully operational."
  else
    print_error "Error occurred during backup restoration. The server has been restarted, but data may be incomplete."
    print_warning "Please check the job logs above for more details."
    return 1
  fi
}

# Run the main function
main

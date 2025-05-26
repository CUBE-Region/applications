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

  # Get available containers in the pod
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
    CONTAINER_ID=$(printf "%s\n" "${container_array[@]}" | fzf --height 40% --reverse --header="Select a container for backup")

    if [[ -z "$CONTAINER_ID" ]]; then
      print_error "No container selected"
      exit 1
    fi
  fi

  print_success "Selected container: $CONTAINER_ID"

  # Confirm backup operation
  if ! confirm_action "Trigger backup in container $CONTAINER_ID of pod $POD_ID?"; then
    print_warning "Operation cancelled by user"
    exit 0
  fi

  # Execute backup command
  print_info "Triggering backup..."
  kubectl exec -n "$NAMESPACE" "$POD_ID" -c "$CONTAINER_ID" -- env RESTIC_ADDITIONAL_TAGS=manual backup now

  if [[ $? -eq 0 ]]; then
    print_success "Backup successfully triggered!"
  else
    print_error "Failed to trigger backup. Check if the selected container supports the backup command."
    exit 1
  fi
}

# Run the main function
main

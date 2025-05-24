#!/bin/bash

# Import utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Default namespace pattern for Kubernetes
NAMESPACE_PATTERN="minecraft"

# Main function
main() {
  # Select pod from Kubernetes namespaces
  print_info "Selecting pod from namespaces matching: $NAMESPACE_PATTERN"
  
  # Get namespace and pod ID from the selection
  SELECTION=$(select_pod_by_namespace "$NAMESPACE_PATTERN")
  
  if [[ $? -ne 0 ]]; then
    print_error "Failed to select pod from namespaces"
    exit 1
  fi
  
  read -r NAMESPACE POD_ID <<< "$SELECTION"
  
  print_success "Selected namespace: $NAMESPACE"
  print_success "Selected pod: $POD_ID"
  
  # Check if backup directory exists
  if [[ -d "./backup" ]]; then
    # Confirm deletion of existing backup
    if ! confirm_action "The backup directory already exists. It will be deleted before copying. Continue?"; then
      print_warning "Operation cancelled by user"
      exit 0
    fi
    
    print_info "Removing existing backup directory..."
    rm -rf ./backup
  fi
  
  # Confirm backup operation
  if ! confirm_action "Data will be copied from $POD_ID to ./backup directory. Continue?"; then
    print_warning "Operation cancelled by user"
    exit 0
  fi
  
  print_info "Starting backup process..."
  
  # Execute backup commands
  print_info "Disabling auto-save..."
  kubectl exec --namespace ${NAMESPACE} ${POD_ID} -- rcon-cli save-off
  if [[ $? -ne 0 ]]; then
    print_error "Failed to disable auto-save. Aborting."
    exit 1
  fi
  
  print_info "Forcing save of all worlds..."
  kubectl exec --namespace ${NAMESPACE} ${POD_ID} -- rcon-cli save-all
  if [[ $? -ne 0 ]]; then
    print_error "Failed to save worlds. Re-enabling auto-save and aborting."
    kubectl exec --namespace ${NAMESPACE} ${POD_ID} -- rcon-cli save-on
    exit 1
  fi
  
  print_info "Copying data from pod to local backup directory..."
  kubectl cp ${NAMESPACE}/${POD_ID}:/data ./backup
  if [[ $? -ne 0 ]]; then
    print_error "Failed to copy data. Re-enabling auto-save and aborting."
    kubectl exec --namespace ${NAMESPACE} ${POD_ID} -- rcon-cli save-on
    exit 1
  fi
  
  print_info "Re-enabling auto-save..."
  kubectl exec --namespace ${NAMESPACE} ${POD_ID} -- rcon-cli save-on
  
  print_success "Backup completed successfully!"
  print_success "Data is now available in the ./backup directory"
}

# Run the main function
main

#!/bin/bash

# Function to select a pod using kubectl only
select_pod_by_namespace() {
  local namespace_pattern=$1

  # Get all namespaces matching the pattern
  print_info "Fetching namespaces matching: $namespace_pattern..." >&2
  local namespaces=$(kubectl get namespaces -o jsonpath="{.items[*].metadata.name}" | tr ' ' '\n' | grep -E "$namespace_pattern" 2>/dev/null)

  if [[ -z "$namespaces" ]]; then
    print_error "No namespaces found matching pattern: $namespace_pattern" >&2
    return 1
  fi

  # Create an array of namespaces
  local -a namespace_array
  for ns in $namespaces; do
    namespace_array+=("$ns")
  done

  # Let user select a namespace using fzf
  local selected_namespace
  selected_namespace=$(printf "%s\n" "${namespace_array[@]}" | fzf --height 40% --reverse --header="Select a namespace")

  if [[ -z "$selected_namespace" ]]; then
    print_error "No namespace selected." >&2
    return 1
  fi

  print_success "Selected namespace: $selected_namespace" >&2

  # Get all StatefulSet and Deployment pods in the selected namespace
  print_info "Fetching pods in namespace: $selected_namespace..." >&2
  local pods=$(kubectl get pods -n "$selected_namespace" -o jsonpath="{.items[*].metadata.name}" 2>/dev/null)

  if [[ -z "$pods" ]]; then
    print_error "No pods found in namespace: $selected_namespace" >&2
    return 1
  fi

  # Create an array of pods
  local -a pod_array
  for pod in $pods; do
    pod_array+=("$pod")
  done

  # Let user select a pod using fzf
  local selected_pod
  selected_pod=$(printf "%s\n" "${pod_array[@]}" | fzf --height 40% --reverse --header="Select a pod")

  if [[ -z "$selected_pod" ]]; then
    print_error "No pod selected." >&2
    return 1
  fi

  print_success "Selected pod: $selected_pod" >&2

  # Return the namespace and selected pod
  echo "$selected_namespace $selected_pod"
}

# Function to confirm an action
confirm_action() {
  local message=$1
  local default=${2:-n}

  if [[ "$default" == "y" ]]; then
    local prompt="$message [Y/n]: "
  else
    local prompt="$message [y/N]: "
  fi

  while true; do
    read -p "$prompt" response
    case "${response:-$default}" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    *) print_warning "Please answer yes (y) or no (n)." ;;
    esac
  done
}

# Color definitions for terminal output
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

# Function to print colored information messages
print_info() {
  echo -e "${BLUE}INFO:${RESET} $1"
}

# Function to print colored success messages
print_success() {
  echo -e "${GREEN}SUCCESS:${RESET} $1"
}

# Function to print colored warning messages
print_warning() {
  echo -e "${YELLOW}WARNING:${RESET} $1"
}

# Function to print colored error messages
print_error() {
  echo -e "${RED}ERROR:${RESET} $1"
}

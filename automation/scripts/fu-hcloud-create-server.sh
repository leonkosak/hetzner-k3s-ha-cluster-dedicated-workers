#!/bin/bash

################################################################################
# Hetzner Cloud Server Creation Function Library
#
# Purpose:
#   Provides functions for creating, updating, and managing individual 
#   Hetzner Cloud servers for K3S clusters
#
# Usage:
#   source ./fu-hcloud-create-server.sh
#   hcloud_create_server "server-name" "image" "type" "location" "ssh-key"
################################################################################

set -euo pipefail

###############################################################################
# CONFIGURATION (inherit from parent script)
###############################################################################

# These should be set by the calling script:
# - LOG_FILE: path to log file
# - UPDATE: 0=delete/recreate, 1=update existing
# - ATTACH_TO_NETWORK: whether to attach to private network
# - PRIVATE_NETWORK: network name
# - CLUSTER_TAG: cluster tag name
# - ENVIRONMENT_TAG: environment label
# - POLL_TIMEOUT, POLL_INTERVAL: timing configuration

###############################################################################
# CORE FUNCTIONS
###############################################################################

# Main server creation function
# Usage: hcloud_create_server <name> <image> <type> <location> <ssh-key> [<role>]
hcloud_create_server() {
    local server_name="$1"
    local image="$2"
    local type="$3"
    local location="$4"
    local ssh_key="$5"
    local role="${6:-worker}"  # master or worker
    
    log_info "Processing server: $server_name (role: $role)"
    
    # Check if server exists
    if hcloud_server_exists "$server_name"; then
        log_info "Server '$server_name' already exists"
        
        if [ "${UPDATE:-0}" -eq 1 ]; then
            log_info "UPDATE mode enabled - modifying existing server"
            hcloud_update_server "$server_name" "$type" "$image"
        else
            log_warn "Server exists but UPDATE=0. Deleting and recreating..."
            hcloud_delete_server "$server_name"
            hcloud_create_new_server "$server_name" "$image" "$type" "$location" "$ssh_key" "$role"
        fi
    else
        log_info "Server '$server_name' does not exist - creating new"
        hcloud_create_new_server "$server_name" "$image" "$type" "$location" "$ssh_key" "$role"
    fi
    
    # Retrieve and export IP
    hcloud_get_and_export_ip "$server_name" "$role"
}

# Check if server exists
hcloud_server_exists() {
    local server_name="$1"
    hcloud server list -o json 2>/dev/null | grep -q "\"name\": \"$server_name\"" && return 0 || return 1
}

# Create a new server
hcloud_create_new_server() {
    local server_name="$1"
    local image="$2"
    local type="$3"
    local location="$4"
    local ssh_key="$5"
    local role="$6"
    
    log_info "Creating server '$server_name' with type=$type, image=$image, location=$location"
    
    # Build hcloud command
    local hcloud_cmd=(
        hcloud server create
        --name "$server_name"
        --type "$type"
        --image "$image"
        --location "$location"
        --ssh-key "$ssh_key"
        --format json
    )
    
    # Add labels for management
    hcloud_cmd+=(
        --label "cluster=$CLUSTER_TAG"
        --label "environment=${ENVIRONMENT_TAG:-production}"
        --label "role=$role"
        --label "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    )
    
    # Execute creation
    if ! output=$("${hcloud_cmd[@]}" 2>&1); then
        log_error "Failed to create server '$server_name': $output"
        return 1
    fi
    
    log_success "Server '$server_name' created successfully"
    
    # Attach to private network if configured
    if [ "${ATTACH_TO_NETWORK:-0}" -eq 1 ] && [ -n "${PRIVATE_NETWORK:-}" ]; then
        hcloud_attach_network "$server_name" "$PRIVATE_NETWORK"
    fi
    
    # Wait for server to be ready
    hcloud_wait_for_server "$server_name"
}

# Delete server
hcloud_delete_server() {
    local server_name="$1"
    
    log_warn "Deleting server '$server_name'..."
    
    if hcloud server delete "$server_name" >> "${LOG_FILE:-/dev/null}" 2>&1; then
        log_success "Server '$server_name' deleted successfully"
    else
        log_error "Failed to delete server '$server_name'"
        return 1
    fi
}

# Update existing server (resize or rebuild)
hcloud_update_server() {
    local server_name="$1"
    local new_type="${2:-}"
    local new_image="${3:-}"
    
    # Resize server if new type specified
    if [ -n "$new_type" ]; then
        log_info "Resizing server '$server_name' to $new_type..."
        
        # Power off before resize
        if ! hcloud server poweroff "$server_name" >> "${LOG_FILE:-/dev/null}" 2>&1; then
            log_error "Failed to power off server '$server_name' before resize"
            return 1
        fi
        
        sleep 5
        
        if ! hcloud server change-type "$server_name" "$new_type" >> "${LOG_FILE:-/dev/null}" 2>&1; then
            log_error "Failed to resize server '$server_name'"
            return 1
        fi
        
        # Power on after resize
        if ! hcloud server poweron "$server_name" >> "${LOG_FILE:-/dev/null}" 2>&1; then
            log_error "Failed to power on server '$server_name' after resize"
            return 1
        fi
        
        log_success "Server '$server_name' resized successfully"
        hcloud_wait_for_server "$server_name"
    fi
    
    # Rebuild server if new image specified
    if [ -n "$new_image" ]; then
        log_info "Rebuilding server '$server_name' with image $new_image..."
        
        if ! hcloud server rebuild "$server_name" --image "$new_image" >> "${LOG_FILE:-/dev/null}" 2>&1; then
            log_error "Failed to rebuild server '$server_name'"
            return 1
        fi
        
        log_success "Server '$server_name' rebuilt successfully"
        hcloud_wait_for_server "$server_name"
    fi
}

# Attach server to private network
hcloud_attach_network() {
    local server_name="$1"
    local network_name="$2"
    
    log_info "Attaching server '$server_name' to network '$network_name'..."
    
    # Get network ID
    local network_id
    network_id=$(hcloud network list --output columns=ID,name | grep "$network_name" | awk '{print $1}')
    
    if [ -z "$network_id" ]; then
        log_error "Network '$network_name' not found"
        return 1
    fi
    
    if hcloud server attach-to-network "$server_name" "$network_id" >> "${LOG_FILE:-/dev/null}" 2>&1; then
        log_success "Server '$server_name' attached to network"
    else
        log_error "Failed to attach server '$server_name' to network"
        return 1
    fi
}

# Wait for server to be ready (running status)
hcloud_wait_for_server() {
    local server_name="$1"
    local timeout="${POLL_TIMEOUT:-300}"  # 5 minutes default
    local interval="${POLL_INTERVAL:-5}"
    local elapsed=0
    
    log_info "Waiting for server '$server_name' to be ready (max ${timeout}s)..."
    
    while [ $elapsed -lt $timeout ]; do
        local status
        status=$(hcloud server describe "$server_name" -o json | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        
        if [ "$status" = "running" ]; then
            log_success "Server '$server_name' is running"
            sleep 10  # Additional wait for SSH to be ready
            return 0
        fi
        
        log_info "Server status: $status (waiting...)"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    log_warn "Timeout waiting for server '$server_name' to be ready"
    return 1
}

# Retrieve server IP and export as environment variable
hcloud_get_and_export_ip() {
    local server_name="$1"
    local role="$2"
    
    log_info "Retrieving IP address for '$server_name'..."
    
    # Get public IPv4 (might not exist on private-only nodes)
    local public_ip
    public_ip=$(hcloud server describe "$server_name" -o json 2>/dev/null | grep -o '"ipv4":\s*{[^}]*"ip":\s*"[^"]*"' | grep -o '"[0-9.]*"' | tr -d '"')
    
    if [ -z "$public_ip" ]; then
        log_warn "No public IP found for '$server_name' (may be private-only)"
        public_ip="N/A"
    else
        log_success "Public IP: $public_ip"
    fi
    
    # Get private IP if attached to network
    local private_ip
    private_ip=$(hcloud server describe "$server_name" -o json 2>/dev/null | grep -o '"ip":\s*"10\.[0-9.]*"' | grep -o '"10[^"]*"' | tr -d '"' | head -1)
    
    if [ -n "$private_ip" ]; then
        log_info "Private IP: $private_ip"
    fi
    
    # Export as environment variable
    # Extract index from server name (e.g., "k3s-master-1" -> "1")
    local index
    index=$(echo "$server_name" | grep -o '[0-9]*$')
    
    if [ -z "$index" ]; then
        log_error "Could not extract index from server name '$server_name'"
        return 1
    fi
    
    # Use public IP if available, otherwise private IP, otherwise N/A
    local export_ip="${public_ip}"
    if [ "$export_ip" = "N/A" ] && [ -n "$private_ip" ]; then
        export_ip="$private_ip"
    fi
    
    # Export as variable
    local var_name="IP_${role^^}_${index}"  # e.g., IP_MASTER_1, IP_WORKER_1
    declare -g "$var_name"="$export_ip"
    export "$var_name"
    
    log_success "Exported: $var_name=$export_ip"
}

# Verify server SSH connectivity
hcloud_verify_ssh() {
    local server_name="$1"
    local ip="$2"
    local ssh_key="${3:--i ~/.ssh/id_ed25519}"  # Default SSH key
    local max_attempts=30
    local attempt=0
    
    log_info "Verifying SSH connectivity to $server_name ($ip)..."
    
    while [ $attempt -lt $max_attempts ]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $ssh_key root@"$ip" "echo 'SSH OK'" 2>/dev/null; then
            log_success "SSH connection successful"
            return 0
        fi
        
        log_info "SSH not ready yet, retrying... ($((attempt + 1))/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    log_warn "Could not verify SSH connectivity to $server_name after $max_attempts attempts"
    return 1
}

# Get server details
hcloud_get_server_info() {
    local server_name="$1"
    
    if ! hcloud_server_exists "$server_name"; then
        log_error "Server '$server_name' not found"
        return 1
    fi
    
    log_info "Server details for '$server_name':"
    hcloud server describe "$server_name"
}

# List all cluster servers
hcloud_list_cluster_servers() {
    local cluster_tag="${CLUSTER_TAG:-k3s-cluster}"
    
    log_info "Listing all servers tagged with cluster=$cluster_tag"
    
    hcloud server list \
        --selector "cluster=$cluster_tag" \
        --output columns=name,status,type,location,public_net.ipv4.ip
}

# Cleanup function: Delete all cluster servers (use with caution!)
hcloud_delete_cluster() {
    local cluster_tag="${CLUSTER_TAG:-k3s-cluster}"
    
    log_warn "DANGER: Deleting all servers tagged with cluster=$cluster_tag"
    read -p "Type 'yes' to confirm deletion: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Deletion cancelled"
        return 0
    fi
    
    # Get all server names with cluster tag
    local servers
    servers=$(hcloud server list --selector "cluster=$cluster_tag" -o columns=name | tail -n +2)
    
    if [ -z "$servers" ]; then
        log_info "No servers found to delete"
        return 0
    fi
    
    # Delete each server
    while IFS= read -r server_name; do
        if [ -n "$server_name" ]; then
            log_warn "Deleting $server_name..."
            hcloud server delete "$server_name"
        fi
    done <<< "$servers"
    
    log_success "Cluster deletion completed"
}

###############################################################################
# EXPORT FUNCTIONS FOR USE IN CALLING SCRIPT
###############################################################################

export -f \
    hcloud_create_server \
    hcloud_server_exists \
    hcloud_create_new_server \
    hcloud_delete_server \
    hcloud_update_server \
    hcloud_attach_network \
    hcloud_wait_for_server \
    hcloud_get_and_export_ip \
    hcloud_verify_ssh \
    hcloud_get_server_info \
    hcloud_list_cluster_servers \
    hcloud_delete_cluster

#!/bin/bash

################################################################################
# Hetzner Cloud: K3S Server Creation Script
# 
# Purpose:
#   Create MicroOS-based K3S master and worker nodes on Hetzner Cloud
#   Suitable for creating both control planes (Cloud VMs) and dedicated workers
#
# Usage:
#   export HCLOUD_TOKEN="your-token"
#   ./hcloud-create-servers.sh
#
# Configuration:
#   Edit variables below or source from external config file
################################################################################

set -euo pipefail

###############################################################################
# CONFIGURATION SECTION
###############################################################################

# Logging
export LOG_FILE="hcloud_create_servers_$(date +%s).log"

# === K3S SERVER CONFIGURATION ===

# Master (Control Plane) Configuration
MASTER_COUNT=3              # Number of master nodes (recommend 1, 3, or 5 for HA)
MASTER_TYPE="cx32"          # Server type: cx22, cx32, cx52, etc.
MASTER_IMAGE="microos-snapshot"  # Image: snapshot ID, snapshot name, or image ID (e.g., "312611387")
MASTER_LOCATIONS=("nbg1" "fsn1" "hel1")  # Locations: fsn1, nbg1, hel1, ash, sin, sgp, etc.
MASTER_ROTATE_LOCATIONS=1   # 1=rotate across locations, 0=all in first location

# Worker (Agent) Configuration
WORKER_COUNT=2              # Number of worker nodes
WORKER_TYPE="cx22"          # Server type
WORKER_IMAGE="microos-snapshot"  # Same image as masters
WORKER_LOCATIONS=("nbg1" "fsn1" "hel1")  # Can be different from masters
WORKER_ROTATE_LOCATIONS=1   # 1=rotate, 0=all in first location

# === NETWORKING ===
# Private network for inter-node communication (optional but recommended)
PRIVATE_NETWORK="runtime-net"  # Hetzner private network name
ATTACH_TO_NETWORK=1         # 1=attach to private network, 0=public only

# === SSH & ACCESS ===
SSH_KEY="k3s-admin"         # SSH key name in Hetzner (must exist)

# === SERVER LIFECYCLE ===
# RECREATE_CLUSTER=1: Delete ALL masters + workers, then recreate from config
# INCREASE_WORKERS=1: Keep existing servers, only add new workers up to WORKER_COUNT
#
# Note: INCREASE_WORKERS=1 is optional. Normal mode (INCREASE_WORKERS=0) also
# skips existing servers and only creates missing ones. The flag just adds
# explicit logging ("currently X workers, will create Y new ones").
# Set in hcloud-config.env or as env vars: RECREATE_CLUSTER=1 ./hcloud-create-servers.sh

# === TAGS & LABELS ===
CLUSTER_TAG="k3s-cluster"   # Tag for all servers in this cluster
ENVIRONMENT_TAG="production"  # Environment label

# === OUTPUT & INTEGRATION ===
# Export IPs to file for Ansible inventory or later use
EXPORT_IPS_FILE="hcloud_server_ips.env"
EXPORT_YAML_FILE="hcloud_servers_inventory.yml"  # Optional Ansible inventory format

# === ADVANCED OPTIONS ===
API_RATE_LIMIT_DELAY=5      # Seconds to wait between API calls
POLL_TIMEOUT=300            # Max seconds to wait for server ready
POLL_INTERVAL=5             # Seconds between status polls

# === LOAD FROM EXTERNAL CONFIG (Optional) ===
# If CONFIG_FILE exists, source it to override above variables
# Save lifecycle flags from env first — env vars must win over config file
_saved_recreate="${RECREATE_CLUSTER:-}"
_saved_increase="${INCREASE_WORKERS:-}"

CONFIG_FILE="${CONFIG_FILE:-./hcloud-config.env}"
if [ -f "$CONFIG_FILE" ]; then
    echo "Loading configuration from $CONFIG_FILE"
    normalized_config="$(mktemp)"
    sed 's/\r$//' "$CONFIG_FILE" > "$normalized_config"
    # shellcheck disable=SC1090
    source "$normalized_config"
    rm -f "$normalized_config"
fi

# Restore env var overrides (env vars > config file)
[ -n "${_saved_recreate}" ] && RECREATE_CLUSTER="${_saved_recreate}"
[ -n "${_saved_increase}" ] && INCREASE_WORKERS="${_saved_increase}"
# Apply defaults if neither env var nor config set them
: "${RECREATE_CLUSTER:=0}"
: "${INCREASE_WORKERS:=0}"

# === HCLOUD CREDENTIALS & ENVIRONMENT ===
# Load from environment or set here (NEVER commit tokens)
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    echo "ERROR: HCLOUD_TOKEN environment variable is not set"
    echo "Set it in your shell or place 'export HCLOUD_TOKEN=...' in $CONFIG_FILE"
    exit 1
fi

###############################################################################
# LOGGING & UTILITY FUNCTIONS
###############################################################################

# Logging function with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# Export logging function for subshells
export -f log log_info log_warn log_error log_success

# Error handler
error_exit() {
    log_error "$@"
    exit 1
}

# Cleanup function on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "[$(date +%H:%M:%S)] ERROR: Script failed with exit code $exit_code. Check $LOG_FILE for details." >&2
    fi
    exit $exit_code
}
trap cleanup EXIT

###############################################################################
# VALIDATION & PREREQUISITE CHECKS
###############################################################################

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check hcloud CLI
    if ! command -v hcloud &> /dev/null; then
        error_exit "hcloud CLI not installed. Install from https://github.com/hetznercloud/cli"
    fi
    log_success "hcloud CLI found: $(hcloud version)"
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warn "jq not found (optional, for better parsing)"
    fi
    
    # Validate HCLOUD_TOKEN by attempting a simple API call
    if ! hcloud project list &> /dev/null; then
        error_exit "HCLOUD_TOKEN validation failed. Check your token and permissions."
    fi
    log_success "HCLOUD_TOKEN authenticated"
    
    # Verify SSH key exists
    if ! hcloud ssh-key list | grep -q "$SSH_KEY"; then
        error_exit "SSH key '$SSH_KEY' not found in Hetzner. Create it first."
    fi
    log_success "SSH key '$SSH_KEY' found"
    
    # If attaching to network, verify it exists
    if [ "$ATTACH_TO_NETWORK" -eq 1 ]; then
        if ! hcloud network list | grep -q "$PRIVATE_NETWORK"; then
            error_exit "Network '$PRIVATE_NETWORK' not found. Create it first or set ATTACH_TO_NETWORK=0"
        fi
        log_success "Private network '$PRIVATE_NETWORK' found"
    fi
    
    # Verify image exists (by ID or name)
    log_info "Verifying image availability..."
    if ! hcloud image list | grep -E "(ID|$MASTER_IMAGE)" &> /dev/null; then
        log_warn "Image '$MASTER_IMAGE' may not exist. Create snapshot first or verify image ID."
    fi
}

###############################################################################
# MAIN FUNCTIONS
###############################################################################

# Source the function library
SOURCE_LIB="./fu-hcloud-create-server.sh"
if [ ! -f "$SOURCE_LIB" ]; then
    error_exit "Function library $SOURCE_LIB not found. Must be in same directory."
fi
source "$SOURCE_LIB"

# Create master nodes
create_master_nodes() {
    log_info "Creating $MASTER_COUNT master node(s)..."
    
    for i in $(seq 1 "$MASTER_COUNT"); do
        local server_name="k3s-master-$i"
        local index=$(( (i - 1) % ${#MASTER_LOCATIONS[@]} ))
        
        if [ "$MASTER_ROTATE_LOCATIONS" -eq 1 ]; then
            local location="${MASTER_LOCATIONS[$index]}"
        else
            local location="${MASTER_LOCATIONS[0]}"
        fi
        
        # Call function from library
        hcloud_create_server \
            "$server_name" \
            "$MASTER_IMAGE" \
            "$MASTER_TYPE" \
            "$location" \
            "$SSH_KEY" \
            "master"
        
        # Rate limiting
        if [ "$i" -lt "$MASTER_COUNT" ]; then
            sleep "$API_RATE_LIMIT_DELAY"
        fi
    done
}

# Create worker nodes
create_worker_nodes() {
    log_info "Creating $WORKER_COUNT worker node(s)..."
    
    for i in $(seq 1 "$WORKER_COUNT"); do
        local server_name="k3s-worker-$i"
        local index=$(( (i - 1) % ${#WORKER_LOCATIONS[@]} ))
        
        if [ "$WORKER_ROTATE_LOCATIONS" -eq 1 ]; then
            local location="${WORKER_LOCATIONS[$index]}"
        else
            local location="${WORKER_LOCATIONS[1]:-${WORKER_LOCATIONS[0]}}"
        fi
        
        hcloud_create_server \
            "$server_name" \
            "$WORKER_IMAGE" \
            "$WORKER_TYPE" \
            "$location" \
            "$SSH_KEY" \
            "worker"
        
        if [ "$i" -lt "$WORKER_COUNT" ]; then
            sleep "$API_RATE_LIMIT_DELAY"
        fi
    done
}

# Export IPs to file for Ansible
export_inventory() {
    log_info "Exporting server inventory..."
    
    # Export as shell variables for sourcing
    {
        echo "# Exported server IPs - $(date)"
        echo "# Source this file to access IPs: source $EXPORT_IPS_FILE"
        echo ""
        
        for i in $(seq 1 "$MASTER_COUNT"); do
            local ip_var="IP_MASTER_$i"
            echo "export ${ip_var}='${!ip_var:-}'"
        done
        
        for i in $(seq 1 "$WORKER_COUNT"); do
            local ip_var="IP_WORKER_$i"
            echo "export ${ip_var}='${!ip_var:-}'"
        done
        
        echo "export MASTER_COUNT=$MASTER_COUNT"
        echo "export WORKER_COUNT=$WORKER_COUNT"
    } > "$EXPORT_IPS_FILE"
    
    chmod 600 "$EXPORT_IPS_FILE"
    log_success "IPs exported to $EXPORT_IPS_FILE"
    
    # Optional: Export as Ansible inventory (YAML format)
    if [ -n "${EXPORT_YAML_FILE:-}" ]; then
        export_ansible_inventory
    fi
}

# Export as Ansible inventory format
export_ansible_inventory() {
    log_info "Exporting Ansible inventory..."
    
    {
        echo "# Ansible inventory for K3S cluster"
        echo "# Generated: $(date)"
        echo ""
        echo "all:"
        echo "  vars:"
        echo "    ansible_user: root"
        echo "    ansible_ssh_private_key_file: /home/pesto/.ssh/id_rsa"
        echo ""
        echo "  children:"
        echo "    k3s_masters:"
        echo "      hosts:"
        
        for i in $(seq 1 "$MASTER_COUNT"); do
            local ip_var="IP_MASTER_$i"
            local ip="${!ip_var:-}"
            if [ -n "$ip" ]; then
                echo "        k3s-master-$i:"
                echo "          ansible_host: $ip"
            fi
        done
        
        echo ""
        echo "    k3s_workers:"
        echo "      hosts:"
        
        for i in $(seq 1 "$WORKER_COUNT"); do
            local ip_var="IP_WORKER_$i"
            local ip="${!ip_var:-}"
            if [ -n "$ip" ]; then
                echo "        k3s-worker-$i:"
                echo "          ansible_host: $ip"
            fi
        done
    } > "$EXPORT_YAML_FILE"
    
    log_success "Ansible inventory exported to $EXPORT_YAML_FILE"
}

# Print summary
print_summary() {
    log_info "=========================================="
    log_info "K3S SERVER CREATION SUMMARY"
    log_info "=========================================="
    log_info "Masters: $MASTER_COUNT"
    log_info "Workers: $WORKER_COUNT"
    log_info "Total Servers: $(( MASTER_COUNT + WORKER_COUNT ))"
    log_info ""
    log_info "Master IPs:"
    for i in $(seq 1 "$MASTER_COUNT"); do
        local ip_var="IP_MASTER_$i"
        log_info "  k3s-master-$i: ${!ip_var:-PENDING}"
    done
    log_info ""
    log_info "Worker IPs:"
    for i in $(seq 1 "$WORKER_COUNT"); do
        local ip_var="IP_WORKER_$i"
        log_info "  k3s-worker-$i: ${!ip_var:-PENDING}"
    done
    log_info ""
    log_info "Next Steps:"
    log_info "  1. source $EXPORT_IPS_FILE"
    log_info "  2. Wait for servers to boot (2-3 minutes)"
    log_info "  3. Run Ansible bootstrap: ansible-playbook bootstrap-os.yml"
    log_info "  4. Install K3S: ansible-playbook install-k3s-servers.yml"
    log_info ""
    log_info "Log file: $LOG_FILE"
    log_info "=========================================="
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    log_info "=== Hetzner K3S Server Creation ==="
    log_info "Log file: $LOG_FILE"
    
    # Validate environment
    validate_prerequisites
    
    # --- RECREATE_CLUSTER mode: delete everything, start fresh ---
    if [ "${RECREATE_CLUSTER:-0}" -eq 1 ]; then
        log_info "RECREATE_CLUSTER=1 — deleting all existing servers..."
        hcloud_cleanup_all_servers
    fi
    
    # --- INCREASE_WORKERS mode: only add new workers ---
    if [ "${INCREASE_WORKERS:-0}" -eq 1 ]; then
        local current_workers
        current_workers=$(hcloud_count_workers)
        log_info "INCREASE_WORKERS=1 — currently $current_workers worker(s), config wants $WORKER_COUNT"
        
        if [ "$WORKER_COUNT" -le "$current_workers" ]; then
            log_warn "WORKER_COUNT ($WORKER_COUNT) is not greater than current workers ($current_workers) — nothing to do"
        else
            local new_count=$((WORKER_COUNT - current_workers))
            log_info "Will create $new_count new worker(s) starting from k3s-worker-$((current_workers + 1))"
            # Override WORKER_COUNT temporarily for the creation loop
            local saved_worker_count="$WORKER_COUNT"
            WORKER_COUNT="$current_workers"
            # Create only the NEW workers (loop starts at current_workers+1)
            local start_index=$((current_workers + 1))
            for i in $(seq "$start_index" "$saved_worker_count"); do
                local server_name="k3s-worker-$i"
                local index=$(( (i - 1) % ${#WORKER_LOCATIONS[@]} ))
                local location
                if [ "$WORKER_ROTATE_LOCATIONS" -eq 1 ]; then
                    location="${WORKER_LOCATIONS[$index]}"
                else
                    location="${WORKER_LOCATIONS[1]:-${WORKER_LOCATIONS[0]}}"
                fi
                hcloud_create_server \
                    "$server_name" \
                    "$WORKER_IMAGE" \
                    "$WORKER_TYPE" \
                    "$location" \
                    "$SSH_KEY" \
                    "worker"
                sleep "$API_RATE_LIMIT_DELAY"
            done
            WORKER_COUNT="$saved_worker_count"
        fi
    else
        # Normal mode: create all servers defined in config
        if [ "$MASTER_COUNT" -gt 0 ]; then
            create_master_nodes
        fi
        
        if [ "$WORKER_COUNT" -gt 0 ]; then
            create_worker_nodes
        fi
    fi
    
    # Export inventory
    export_inventory
    
    # Print summary
    print_summary
    
    log_success "Server creation completed successfully!"
}

# Run main function
main "$@"

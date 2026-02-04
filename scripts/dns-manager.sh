#!/bin/bash
# Unified DNS Manager for Conspire Testing
# Uses Linode instance IDs for DNS names to enable parallelism and simplicity

set -e

# Configuration
DOMAIN="goneelsewhere.org"
TTL=60  # Fast propagation for testing
MAX_WAIT=300  # 5 minutes max wait for DNS propagation
VERBOSE=false

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND [ARGS]

DNS management for Conspire testing infrastructure using Linode instance IDs.

Commands:
  create <instance_id> <ip>    Create DNS record for instance, wait for propagation
  cleanup <instance_id>       Delete DNS record for specific instance  
  cleanup-all                  Delete all test DNS records
  status                       Show current test DNS records (passive)
  --clear-cache                Clear local DNS cache (use if stuck with NXDOMAIN)

Options:
  -h, --help                  Show this help message
  -v, --verbose               Show detailed operations and progress
  --version                   Show version information
  --clear-cache               Clear local DNS cache to avoid NXDOMAIN issues

DNS Naming:
  Records created as: test-{INSTANCE_ID}.goneelsewhere.org
  Example: test-91029154.goneelsewhere.org

Examples:
  $0 create 91029154 172.234.253.161
  $0 status
  $0 cleanup 91029154
  $0 cleanup-all
  $0 --clear-cache    # Clear DNS cache if stuck with NXDOMAIN

EOF
}

# Version information
show_version() {
    echo "$0 version 1.0.0 - Conspire Testing DNS Manager"
}

# Verbose logging function
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "$1"
    fi
}

# Helper function to get domain ID
get_domain_id() {
    linode-cli domains list --text | grep "$DOMAIN" | awk '{print $1}'
}

# Create DNS record tied to instance ID
create_dns_for_instance() {
    local instance_id="$1"
    local ip="$2"
    
    local domain_id=$(get_domain_id)
    local dns_name="test-$instance_id"
    local full_domain="$dns_name.$DOMAIN"
    
    log_verbose "Creating DNS record with domain ID: $domain_id"
    log_verbose "DNS record: $full_domain -> $ip (TTL: ${TTL}s)"
    
    # Create DNS record
    local record_output=$(linode-cli domains records-create "$domain_id" \
        --name "$dns_name" --type "A" --target "$ip" --ttl_sec "$TTL" --text 2>/dev/null)
    
    log_verbose "DNS creation output: $record_output"
    
    # Wait for DNS propagation - Use Linode DNS directly first to avoid NXDOMAIN caching
    log_verbose "Waiting for DNS propagation..."
    
    # First, verify record exists at Linode DNS to avoid negative cache
    log_verbose "Verifying DNS record exists at Linode..."
    local record_verified=false
    local verify_attempts=0
    while [ $verify_attempts -lt 30 ] && [ "$record_verified" = false ]; do
        if linode-cli domains records-list "$domain_id" --text | grep -q "$dns_name"; then
            record_verified=true
            log_verbose "DNS record verified at Linode"
        else
            sleep 2
            verify_attempts=$((verify_attempts + 1))
        fi
    done
    
    if [ "$record_verified" = false ]; then
        log_verbose "DNS record not found at Linode after verification period"
        return 1
    fi
    
    # Now check propagation through local resolver (safe since we know record exists)
    local elapsed=0
    while [ $elapsed -lt $MAX_WAIT ]; do
        log_verbose "Checking DNS resolution for $full_domain..."
        if dig +short "$full_domain" @ns1.linode.com | grep -q "$ip"; then
            log_verbose "DNS propagated after ${elapsed}s!"
            echo "$full_domain"  # Return the full domain name (clean output)
            return 0
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_verbose "Still waiting... (${elapsed}s elapsed)"
        fi
    done
    
    log_verbose "DNS failed to propagate after ${MAX_WAIT}s"
    log_verbose "Expected: $ip"
    log_verbose "Linode DNS: $(dig +short "$full_domain" @ns1.linode.com || echo 'not found')"
    log_verbose "Local resolver: $(dig +short "$full_domain" || echo 'not found')"
    return 1
}

# Clean up DNS records for specific instance
cleanup_dns_for_instance() {
    local instance_id="$1"
    local domain_id=$(get_domain_id)
    local dns_name="test-$instance_id"
    
    log_verbose "Looking for DNS record: $dns_name"
    echo "🧹 Cleaning up DNS for instance $instance_id..."
    
    # Find and delete DNS record
    local record_id=$(linode-cli domains records-list "$domain_id" --text | grep "$dns_name" | awk '{print $1}')
    
    if [ -n "$record_id" ]; then
        echo "  🗑️  Deleting DNS record $record_id"
        log_verbose "Executing: linode-cli domains records-delete $domain_id $record_id"
        linode-cli domains records-delete "$domain_id" "$record_id"
    else
        echo "  ℹ️  No DNS record found for instance $instance_id"
    fi
}

# Clean up all test DNS records (bulk cleanup)
cleanup_all_test_dns() {
    local domain_id=$(get_domain_id)
    
    echo "🧹 Cleaning up all test DNS records..."
    
    # Find all test-* DNS records
    linode-cli domains records-list "$domain_id" --text | grep "test-" | while IFS=$'\t' read -r id name type target; do
        if [ -n "$id" ]; then
            echo "  🗑️  Deleting DNS record: $name"
            linode-cli domains records-delete "$domain_id" "$id" 2>/dev/null || true
        fi
    done
}

# Show status of test DNS records
show_dns_status() {
    local domain_id=$(get_domain_id)
    
    echo "📊 Test DNS Records Status:"
    
    # Use Linode CLI for status (avoids DNS queries that could create negative cache)
    linode-cli domains records-list "$domain_id" --text | grep "test-" | while IFS=$'\t' read -r id type name target ttl priority weight; do
        echo "  📍 $name.$DOMAIN -> $target (TTL: ${ttl}s, ID: $id)"
        # Optionally test resolution if verbose
        if [ "$VERBOSE" = true ]; then
            if dig +short "$name.$DOMAIN" @ns1.linode.com | grep -q "$target"; then
                echo "    ✅ Resolves correctly via Linode DNS"
            else
                echo "    ❌ Not resolving via Linode DNS"
            fi
        fi
    done
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --version)
    show_version
    exit 0
            ;;
    --clear-cache)
            echo "🧹 Attempting to clear DNS cache for test records..."
            # Clear local DNS cache (macOS/BSD)
            if command -v dscacheutil >/dev/null 2>&1; then
                sudo dscacheutil -flushcache 2>/dev/null || true
            fi
            # Clear systemd-resolved (Linux)
            if command -v systemd-resolve >/dev/null 2>&1; then
                sudo systemd-resolve --flush-caches 2>/dev/null || true
            fi
            echo "✅ DNS cache cleared (if possible)"
            exit 0
            ;;
    *)
            break
            ;;
    esac
done

# Only execute main command routing if script is called directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
    create)
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "❌ Usage: $0 create <instance_id> <ip>"
            exit 1
        fi
        create_dns_for_instance "$2" "$3"
        ;;
    cleanup)
        if [ -z "${2:-}" ]; then
            echo "❌ Usage: $0 cleanup <instance_id>"
            exit 1
        fi
        cleanup_dns_for_instance "$2"
        ;;
    cleanup-all)
        cleanup_all_test_dns
        ;;
    status)
        show_dns_status
        ;;
    *)
        show_help
        exit 1
        ;;
esac
fi
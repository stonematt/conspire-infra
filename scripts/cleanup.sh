#!/bin/bash
# Unified cleanup script for Conspire test resources
# Cleans up instances and their associated DNS records

set -e

# Configuration
DOMAIN="goneelsewhere.org"
VERBOSE=false

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND [ARGS]

Clean up Conspire test resources (instances and DNS records).

Commands:
  all                    Clean up all test instances and DNS records
  old [max_age]          Clean up instances older than max_age seconds (default: 3600)
  specific <instance_id>  Clean up specific instance and its DNS
  status                 Show current test resources without cleaning (passive)
  dns-only               Clean up DNS records only

Options:
  -h, --help                  Show this help message
  -v, --verbose               Show detailed operations and progress
  --version                   Show version information

Safety Features:
  - Instance-driven cleanup (delete instance → delete its DNS)
  - Age-based cleanup for forgotten resources
  - Orphaned DNS cleanup
  - Resource status reporting

Examples:
  $0 all                         # Clean everything
  $0 old 7200                    # Clean instances older than 2 hours
  $0 specific 91029154           # Clean specific instance ID
  $0 status                      # Show resources without cleaning
  $0 dns-only                    # Clean DNS records only

EOF
}

# Version information
show_version() {
    echo "$0 version 1.0.0 - Conspire Test Resource Cleanup"
}

# Verbose logging function
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "$1"
    fi
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
        *)
            break
            ;;
    esac
done

# Source DNS manager utilities
DNS_MANAGER_SCRIPT="$(dirname "$0")/dns-manager.sh"
source "$DNS_MANAGER_SCRIPT"

echo "🧹 Cleaning up Conspire test resources..."

# Get domain ID for DNS operations
DOMAIN_ID=$(linode-cli domains list --text | grep "$DOMAIN" | awk '{print $1}')

if [ -z "$DOMAIN_ID" ]; then
    echo "❌ Could not find domain ID for $DOMAIN"
    exit 1
fi

# Function to clean up specific instance and its DNS
cleanup_instance() {
    local instance_id="$1"
    local label="$2"
    
    echo "🗑️  Cleaning up instance $instance_id ($label)..."
    
    # Clean up DNS first
    cleanup_dns_for_instance "$instance_id"
    
    # Clean up instance
    echo "  Deleting instance $instance_id"
    linode-cli linodes delete "$instance_id" 2>/dev/null || echo "  Instance already deleted or not found"
}

# Function to clean up all test instances
cleanup_all_instances() {
    echo "🔍 Finding test instances..."
    
    # Get all test instances (matching our naming pattern)
    linode-cli linodes list --text | grep "conspire-test-" | while IFS=$'\t' read -r id label region status ipv4; do
        if [ -n "$id" ]; then
            cleanup_instance "$id" "$label"
        fi
    done
    
    # Also clean up any orphaned DNS records
    echo "🌐 Cleaning up orphaned DNS records..."
    cleanup_all_test_dns
}

# Function to clean up old instances (older than specified age)
cleanup_old_instances() {
    local max_age="${1:-3600}"  # Default 1 hour
    
    echo "🕐 Cleaning up instances older than ${max_age}s..."
    
    linode-cli linodes list --text | grep "conspire-test-" | while IFS=$'\t' read -r id label region status ipv4; do
        if [ -n "$id" ] && [ "$status" = "running" ]; then
            # Extract timestamp from label (conspire-test-UNIX_TIMESTAMP)
            local timestamp=$(echo "$label" | cut -d'-' -f3)
            
            if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                local current_time=$(date +%s)
                local instance_age=$((current_time - timestamp))
                
                if [ $instance_age -gt $max_age ]; then
                    echo "  🗑️  Deleting old instance: $label (${instance_age}s old)"
                    cleanup_instance "$id" "$label"
                fi
            fi
        fi
    done
}

# Show current test resources before cleanup
show_current_resources() {
    echo "📊 Current Test Resources:"
    
    # Show instances
    echo "  🖥️  Test Instances:"
    local instance_count=$(linode-cli linodes list --text | grep "conspire-test-" | wc -l)
    if [ "$instance_count" -gt 0 ]; then
        linode-cli linodes list --text | grep "conspire-test-" | while IFS=$'\t' read -r id label region status ipv4; do
            echo "     $id: $label ($status, $ipv4)"
        done
    else
        echo "     No test instances found"
    fi
    
    # Show DNS records
    echo "  🌐 DNS Records:"
    show_dns_status
}

# Main command routing
case "${1:-}" in
    all|cleanup-all)
        show_current_resources
        echo ""
        cleanup_all_instances
        ;;
    old)
        max_age="${2:-3600}"
        show_current_resources
        echo ""
        cleanup_old_instances "$max_age"
        ;;
    specific)
        if [ -z "${2:-}" ]; then
            echo "❌ Usage: $0 specific <instance_id>"
            exit 1
        fi
        instance_id="$2"
        # Find instance label for context
        label=$(linode-cli linodes list --text | grep "$instance_id" | awk '{print $2}')
        show_current_resources
        echo ""
        cleanup_instance "$instance_id" "$label"
        ;;
    status)
        show_current_resources
        ;;
    dns-only)
        echo "🌐 Cleaning up DNS records only..."
        cleanup_all_test_dns
        ;;
    *)
        show_help
        exit 1
        ;;
esac

echo ""
echo "✅ Cleanup complete!"
echo "💡 Verify no remaining charges in your Linode dashboard"
#!/bin/bash
# Simplified Test Instance Creation with DNS Management
# Uses Linode instance IDs for DNS names - enables CI/CD parallelism

set -e

# Configuration
REGION="us-sea"
TYPE="g6-nanode-1"
IMAGE="linode/ubuntu22.04"
DOMAIN="goneelsewhere.org"
TTL=60
VERBOSE=false

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Create a Conspire test instance with DNS management.

This script:
1. Creates a Linode instance with SSH key authentication
2. Creates DNS record: test-{INSTANCE_ID}.goneelsewhere.org  
3. Waits for DNS propagation (60s TTL)
4. Generates Ansible inventory and variable files
5. Fails if DNS creation fails (required for certificate management)

Options:
  -h, --help                  Show this help message
  -v, --verbose               Show detailed operations and progress
  --version                   Show version information

Instance Configuration:
  Region: $REGION
  Type: $TYPE
  Image: $IMAGE
  DNS TTL: ${TTL}s

Files Created:
  - conspire-infra/inventories/test/hosts.yml
  - conspire-infra/group_vars/test.yml

Examples:
  $0                          # Create test instance with default settings
  $0 --verbose                 # Create with detailed progress output
  $0 -h                       # Show this help

Cost: ~\$0.01-0.02 per test cycle

EOF
}

# Version information
show_version() {
    echo "$0 version 1.0.0 - Conspire Test Instance Creator"
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
            echo "❌ Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Source DNS manager utilities
DNS_MANAGER_SCRIPT="$(dirname "$0")/dns-manager.sh"
source "$DNS_MANAGER_SCRIPT"

echo "🚀 Creating Conspire test instance..."

# Generate unique instance label
INSTANCE_LABEL="conspire-test-$(date +%s)"

echo "📋 Instance Configuration:"
echo "   Label: $INSTANCE_LABEL"
echo "   Type: $TYPE"
echo "   Region: $REGION"
echo "   Image: $IMAGE"

# Create Linode instance
echo "⏳ Creating Linode instance..."
INSTANCE_OUTPUT=$(linode-cli linodes create \
    --label "$INSTANCE_LABEL" \
    --region "$REGION" \
    --type "$TYPE" \
    --image "$IMAGE" \
    --root_pass "$(openssl rand -base64 32)" \
    --authorized_keys "$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub)" \
    --tags "conspire,test,ephemeral" \
    --text
)

# Extract instance details from tabular output
INSTANCE_ID=$(echo "$INSTANCE_OUTPUT" | tail -1 | awk '{print $1}')
IP=$(echo "$INSTANCE_OUTPUT" | tail -1 | awk '{print $6}')

log_verbose "Instance output parsing:"
log_verbose "Full output: $INSTANCE_OUTPUT"
log_verbose "Extracted ID: $INSTANCE_ID"
log_verbose "Extracted IP: $IP"

if [ -z "$INSTANCE_ID" ] || [ -z "$IP" ]; then
    echo "❌ Failed to extract instance details from Linode CLI output"
    echo "Output received:"
    echo "$INSTANCE_OUTPUT"
    exit 1
fi

echo "✅ Instance created!"
echo "   ID: $INSTANCE_ID"
echo "   IP: $IP"
echo "   Label: $INSTANCE_LABEL"

# Wait for instance to finish provisioning and get real IP
if [ "$IP" = "provisioning" ] || [ -z "$IP" ]; then
    echo "⏳ Instance is provisioning, waiting for IP address..."
    while [ "$IP" = "provisioning" ] || [ -z "$IP" ]; do
        sleep 5
        INSTANCE_DETAILS=$(linode-cli linodes list --text | grep "$INSTANCE_ID")
        IP=$(echo "$INSTANCE_DETAILS" | awk '{print $7}')
        status=$(echo "$INSTANCE_DETAILS" | awk '{print $6}')
        log_verbose "Current status: $status, IP: $IP"
        echo "   Current status: $status, IP: $IP"
    done
fi

echo "✅ Instance IP ready: $IP"

# Create DNS record immediately (Option A: immediately when IP available)
echo "🌐 Creating DNS record..."
TEST_DOMAIN=$(create_dns_for_instance "$INSTANCE_ID" "$IP" 2>/dev/null)

if [ -z "$TEST_DOMAIN" ]; then
    echo "❌ DNS creation failed - aborting test setup"
    # Clean up the instance since DNS failed
    echo "🧹 Cleaning up failed instance..."
    log_verbose "Executing: linode-cli linodes delete $INSTANCE_ID"
    linode-cli linodes delete "$INSTANCE_ID"
    exit 1
fi

echo "✅ DNS record created: $TEST_DOMAIN"

# Create inventory file
cat > ./inventories/test/hosts.yml << EOF
---
# Auto-generated test configuration
test:
  hosts:
    test-host:
      ansible_host: $IP
      ansible_user: root
      test_domain: $TEST_DOMAIN
      instance_id: $INSTANCE_ID
      instance_label: $INSTANCE_LABEL
EOF

# Update group variables
cat > ./group_vars/test.yml << EOF
---
# Test configuration - auto-generated
domain: $TEST_DOMAIN
certbot_email: test@goneelsewhere.org
conspire_port: "8443"
landing_port: "443"
conspire_config_dir: /opt/conspire
landing_web_root: /var/www/$TEST_DOMAIN
site_title: "Conspire Test Instance"
site_tagline: "Testing secure anonymous chat"
test_timestamp: $(date +%s)
instance_name: $INSTANCE_LABEL
EOF

echo "📝 Configuration files created:"
echo "   - inventories/test/hosts.yml"
echo "   - group_vars/test.yml"

# Parallel SSH wait + DNS propagation
echo "⏳ Waiting for SSH readiness and DNS propagation in parallel..."

# Start SSH wait in background
(
    echo "🔌 Checking SSH availability..."
    while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$IP" "echo 'SSH ready'" 2>/dev/null; do
        sleep 5
        log_verbose "SSH still not ready, waiting..."
    done
    echo "✅ SSH is ready!"
) &
SSH_PID=$!

# Start DNS propagation check in background
(
    echo "🌐 Checking DNS propagation..."
    elapsed=0
    while [ $elapsed -lt $MAX_WAIT ]; do
        if dig +short "$TEST_DOMAIN" @ns1.linode.com | grep -q "$IP"; then
            echo "✅ DNS propagated after ${elapsed}s!"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "   DNS still propagating... (${elapsed}s elapsed)"
        fi
    done
) &
DNS_PID=$!

# Wait for both SSH and DNS
wait $SSH_PID $DNS_PID

echo ""
echo "🎉 Test environment ready!"
echo ""
echo "🧪 Deployment Command:"
echo "   ansible-playbook -i inventories/test/hosts.yml site.yml"
echo ""
echo "🌐 Test URLs:"
echo "   Landing: https://$TEST_DOMAIN"
echo "   Conspire: https://$TEST_DOMAIN:8443"
echo ""
echo "🧹 Cleanup Commands:"
echo "   ./cleanup.sh all"
echo ""
echo "💰 Expected cost: ~\$0.01-0.02 for this test"
echo ""
echo "🔍 DNS Status:"
show_dns_status
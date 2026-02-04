#!/bin/bash
# Deploy and Test - One-command Conspire testing workflow
# Creates instance, deploys, tests, and optionally opens browser

set -e

# Configuration
VERBOSE=false
OPEN_BROWSER=false
TEST_LEVEL="basic"
DEPLOY_ONLY=false

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy and test Conspire infrastructure in one workflow.

This script:
1. Creates test instance with DNS (parallel SSH + DNS wait)
2. Deploys infrastructure to test instance only
3. Runs deployment tests (basic/standard/comprehensive)
4. Optionally opens browser to landing page
5. Leaves cleanup for manual execution (recommended)

Options:
  -h, --help                  Show this help message
  -v, --verbose               Show detailed operations and progress
  --version                   Show version information
  --open-browser               Open browser to landing page after deployment
  --test-level LEVEL          Test level: basic|standard|comprehensive (default: basic)
  --deploy-only              Deploy without testing (faster for manual testing)

Examples:
  $0                          # Create, deploy, test (basic)
  $0 --open-browser --test-level comprehensive  # Full workflow with browser
  $0 --deploy-only --verbose     # Deploy only, detailed output
  $0 --help                    # Show this help

Instance Management:
  - Targets test instance only (not production)
  - Related to test host ID for cleanup
  - Parallel SSH/DNS waits for efficiency
  - Cost: ~\$0.01-0.02 per run

EOF
}

# Version information
show_version() {
    echo "$0 version 1.0.0 - Conspire Deploy and Test Workflow"
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
        --open-browser)
            OPEN_BROWSER=true
            shift
            ;;
        --test-level)
            if [ -z "${2:-}" ]; then
                echo "❌ --test-level requires a level (basic|standard|comprehensive)"
                exit 1
            fi
            TEST_LEVEL="$2"
            shift 2
            ;;
        --deploy-only)
            DEPLOY_ONLY=true
            shift
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo "🚀 Conspire Deploy and Test Workflow"
echo "🎯 Test Level: $TEST_LEVEL"
echo "🌐 Browser Open: $OPEN_BROWSER"
echo "📦 Deploy Only: $DEPLOY_ONLY"
echo ""

# Step 1: Create test instance with DNS
echo "📋 Step 1: Creating test instance and DNS..."

# Create instance and get test domain
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE_OUTPUT=$(cd "$SCRIPT_DIR" && ./create-test-instance.sh --verbose 2>&1)
TEST_DOMAIN=$(echo "$INSTANCE_OUTPUT" | grep -E "Test environment ready" -A 10 | grep "https://$TEST_DOMAIN" | head -1 | sed 's/.*https:\/\/\([^)]*\).*/\1/')

if [ -z "$TEST_DOMAIN" ]; then
    echo "❌ Failed to extract test domain from creation output"
    exit 1
fi

echo "✅ Test instance created: $TEST_DOMAIN"
echo ""

# Step 2: Deploy infrastructure to test instance
echo "📦 Step 2: Deploying infrastructure..."

cd .
if [ "$VERBOSE" = true ]; then
    ansible-playbook -i inventories/test/hosts.yml site.yml -v
else
    ansible-playbook -i inventories/test/hosts.yml site.yml
fi

echo "✅ Infrastructure deployed to test instance"
echo ""

# Step 3: Test deployment
if [ "$DEPLOY_ONLY" = false ]; then
    echo "🧪 Step 3: Testing deployment..."
    
    cd "$SCRIPT_DIR"
    if [ "$VERBOSE" = true ]; then
        ./test-deployment.sh --verbose "$TEST_LEVEL"
    else
        ./test-deployment.sh "$TEST_LEVEL"
    fi
    
    TEST_EXIT_CODE=$?
    
    if [ $TEST_EXIT_CODE -eq 0 ]; then
        echo "✅ All tests passed!"
    else
        echo "❌ Some tests failed ($TEST_EXIT_CODE failed)"
    fi
else
    echo "⏭️ Skipping tests (deploy-only mode)"
fi

echo ""

# Step 4: Open browser if requested
if [ "$OPEN_BROWSER" = true ]; then
    echo "🌐 Step 4: Opening browser to landing page..."
    
    # Detect browser command
    if command -v open >/dev/null 2>&1; then
        # macOS
        open "https://$TEST_DOMAIN"
    elif command -v xdg-open >/dev/null 2>&1; then
        # Linux
        xdg-open "https://$TEST_DOMAIN"
    elif command -v firefox >/dev/null 2>&1; then
        # Fallback
        firefox "https://$TEST_DOMAIN" &
    else
        echo "⚠️  Could not detect browser command. Please open manually:"
        echo "   https://$TEST_DOMAIN"
    fi
else
    echo "📖 Manual browser access:"
    echo "   https://$TEST_DOMAIN"
fi

echo ""
echo "🎉 Workflow Complete!"
echo ""
echo "📊 Summary:"
echo "   Instance: $TEST_DOMAIN"
echo "   Test Level: $TEST_LEVEL"
echo "   Test Status: $([ $DEPLOY_ONLY = true ] && echo "Skipped" || echo $([ $TEST_EXIT_CODE -eq 0 ] && echo "Passed" || echo "Failed"))"
echo ""
echo "🌐 Test URLs:"
echo "   Landing: https://$TEST_DOMAIN"
echo "   Conspire: https://$TEST_DOMAIN:8443"
echo "   Room Test: https://$TEST_DOMAIN:8443/room/TestRoom"
echo ""
echo "🧹 Cleanup (when done testing):"
echo "   cd $SCRIPT_DIR && ./cleanup.sh all"
echo ""
echo "💰 Total cost: ~\$0.01-0.02 for this workflow"
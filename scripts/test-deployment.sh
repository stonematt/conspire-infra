#!/bin/bash
# Unified Deployment Testing with Dynamic DNS Support
# Supports multiple test levels and auto-loads test configuration

set -e

# Configuration
VERBOSE=false

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [test_level]

Test deployed Conspire infrastructure with configurable depth.

This script automatically loads test configuration from the inventory file
created by create-test-instance.sh and runs a comprehensive test suite.

Test Levels:
  basic        Core functionality (DNS, SSL, services)
  standard     Recommended tests (includes room creation)
  comprehensive Full validation (includes performance and JS checks)

Options:
  -h, --help                  Show this help message
  -v, --verbose               Show detailed test progress and results
  --version                   Show version information

Test Coverage:
  1. DNS resolution
  2. HTTP → HTTPS redirects
  3. SSL certificate validation
  4. HTTPS content serving
  5. Conspire service availability
  6. Room creation functionality
  7. Service status checks
  8. Performance testing (comprehensive)
  9. JavaScript functionality (comprehensive)

Prerequisites:
  - Test environment created with create-test-instance.sh
  - Infrastructure deployed with Ansible
  - Inventory file at: ./inventories/test/hosts.yml

Examples:
  $0                    # Run standard tests (recommended)
  $0 basic              # Run basic functionality tests
  $0 comprehensive       # Run full test suite
  $0 --verbose basic     # Run basic tests with detailed output

Exit Codes:
  0    All tests passed
  1+   Number of failed tests (exit code = failed count)

EOF
}

# Version information
show_version() {
    echo "$0 version 1.0.0 - Conspire Deployment Testing"
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
            # Assume remaining argument is test level
            break
            ;;
    esac
done

# Load test configuration from inventory file
INVENTORY_FILE="./inventories/test/hosts.yml"

if [ ! -f "$INVENTORY_FILE" ]; then
    echo "❌ Test inventory file not found: $INVENTORY_FILE"
    echo "   Run ./create-test-instance.sh first to create a test environment"
    exit 1
fi

# Parse YAML to get test domain and IP
test_domain=$(grep -E '^[[:space:]]+test_domain:' "$INVENTORY_FILE" | awk '{print $2}')
ansible_host=$(grep -E '^[[:space:]]+ansible_host:' "$INVENTORY_FILE" | awk '{print $2}')

if [ -z "$test_domain" ] || [ -z "$ansible_host" ]; then
    echo "❌ Could not parse test configuration from inventory file"
    exit 1
fi

TEST_DOMAIN="$test_domain"
TEST_IP="$ansible_host"

# Test configuration
TEST_LEVEL="${1:-standard}"
FAILED_TESTS=0

echo "🧪 Testing Conspire Deployment"
echo "📍 Domain: $TEST_DOMAIN"
echo "🔗 IP: $TEST_IP"
echo "🎯 Test Level: $TEST_LEVEL"
echo ""

# Test level configuration
case "$TEST_LEVEL" in
    basic)
        echo "🔧 Running basic tests (core functionality only)..."
        TESTS_TO_RUN=(dns https_redirect ssl conspire)
        ;;
    standard)
        echo "🔧 Running standard tests (recommended)..."
        TESTS_TO_RUN=(dns https_redirect ssl conspire room_creation services)
        ;;
    comprehensive)
        echo "🔧 Running comprehensive tests (including performance)..."
        TESTS_TO_RUN=(dns https_redirect ssl conspire room_creation services performance js_check)
        ;;
    *)
        echo "❌ Invalid test level: $TEST_LEVEL"
        echo "   Valid levels: basic, standard, comprehensive"
        show_help
        exit 1
        ;;
esac

# Test functions
test_dns() {
    echo "1. 🌐 Testing DNS resolution..."
    log_verbose "Testing DNS for $TEST_DOMAIN against $TEST_IP"
    if dig +short "$TEST_DOMAIN" | grep -q "$TEST_IP"; then
        echo "   ✅ DNS resolves correctly: $TEST_DOMAIN → $TEST_IP"
        log_verbose "DNS test passed"
        return 0
    else
        echo "   ❌ DNS resolution failed"
        echo "   Expected: $TEST_IP"
        echo "   Got: $(dig +short "$TEST_DOMAIN" || echo 'not found')"
        log_verbose "DNS test failed"
        return 1
    fi
}

test_https_redirect() {
    echo "2. 📄 Testing HTTP → HTTPS redirect..."
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$TEST_DOMAIN" 2>/dev/null)
    if [ "$HTTP_STATUS" = "308" ] || [ "$HTTP_STATUS" = "301" ]; then
        echo "   ✅ HTTP redirects correctly ($HTTP_STATUS)"
        return 0
    else
        echo "   ❌ HTTP redirect failed (got $HTTP_STATUS, expected 301/308)"
        return 1
    fi
}

test_ssl() {
    echo "3. 🔐 Testing SSL certificate..."
    if timeout 10 openssl s_client -servername "$TEST_DOMAIN" -connect "$TEST_DOMAIN:443" </dev/null 2>/dev/null | openssl x509 -noout -checkend 0 2>/dev/null; then
        echo "   ✅ SSL certificate valid and not expired"
        return 0
    else
        echo "   ❌ SSL certificate issue detected"
        return 1
    fi
}

test_https_content() {
    echo "4. 📄 Testing HTTPS landing page..."
    HTTPS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$TEST_DOMAIN" 2>/dev/null)
    if [ "$HTTPS_STATUS" = "200" ]; then
        echo "   ✅ HTTPS landing page working ($HTTPS_STATUS)"
        return 0
    else
        echo "   ❌ HTTPS landing page failed (got $HTTPS_STATUS)"
        return 1
    fi
}

test_conspire() {
    echo "5. 💬 Testing Conspire service..."
    CONSPIRE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$TEST_DOMAIN:8443" 2>/dev/null)
    if [ "$CONSPIRE_STATUS" = "200" ] || [ "$CONSPIRE_STATUS" = "404" ]; then
        echo "   ✅ Conspire service responding ($CONSPIRE_STATUS)"
        return 0
    else
        echo "   ❌ Conspire service failed (got $CONSPIRE_STATUS, expected 200/404)"
        return 1
    fi
}

test_room_creation() {
    echo "6. 🏠 Testing room creation..."
    ROOM_NAME="TestRoom$(date +%s)"
    ROOM_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$TEST_DOMAIN:8443/room/$ROOM_NAME" 2>/dev/null)
    if [ "$ROOM_STATUS" = "200" ]; then
        echo "   ✅ Room creation works ($ROOM_STATUS)"
        return 0
    else
        echo "   ❌ Room creation failed (got $ROOM_STATUS, expected 200)"
        return 1
    fi
}

test_services() {
    echo "7. 🔄 Checking service status..."
    cd .
    
    local service_failures=0
    
    if ! ansible -i inventories/test/hosts.yml test-host -m command -a "systemctl is-active caddy" 2>/dev/null | grep -q "active"; then
        echo "   ❌ Caddy service not active"
        service_failures=$((service_failures + 1))
    else
        echo "   ✅ Caddy service active"
    fi
    
    if ! ansible -i inventories/test/hosts.yml test-host -m command -a "systemctl is-active conspire" 2>/dev/null | grep -q "active"; then
        echo "   ❌ Conspire service not active"
        service_failures=$((service_failures + 1))
    else
        echo "   ✅ Conspire service active"
    fi
    
    return $service_failures
}

test_performance() {
    echo "8. ⚡ Testing performance..."
    LOAD_TIME=$(curl -w "%{time_total}" -s -o /dev/null "https://$TEST_DOMAIN" 2>/dev/null)
    
    if [ -n "$LOAD_TIME" ]; then
        if [ "$(echo "$LOAD_TIME < 2.0" | bc 2>/dev/null)" = "1" ]; then
            echo "   ✅ Fast load time: ${LOAD_TIME}s"
            return 0
        else
            echo "   ⚠️  Slow load time: ${LOAD_TIME}s"
            return 1
        fi
    else
        echo "   ❌ Could not measure load time"
        return 1
    fi
}

test_js_check() {
    echo "9. 🎲 Checking JavaScript room generation..."
    if curl -s "https://$TEST_DOMAIN" 2>/dev/null | grep -q "id=\"new-room\""; then
        echo "   ✅ Room generation button present"
        return 0
    else
        echo "   ❌ Room generation button missing"
        return 1
    fi
}

# Run tests based on level
echo ""
for test_name in "${TESTS_TO_RUN[@]}"; do
    case "$test_name" in
        dns) test_dns && FAILED_TESTS=$((FAILED_TESTS + 0)) || FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        https_redirect) test_https_redirect && FAILED_TESTS=$((FAILED_TESTS + 0)) || FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        ssl) test_ssl && FAILED_TESTS=$((FAILED_TESTS + 0)) || FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        https_content) test_https_content && FAILED_TESTS=$((FAILED_TESTS + 0)) || FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        conspire) test_conspire && FAILED_TESTS=$((FAILED_TESTS + 0)) || FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        room_creation) test_room_creation && FAILED_TESTS=$((FAILED_TESTS + 0)) || FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        services) test_services && FAILED_TESTS=$((FAILED_TESTS + 0)) || FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        performance) test_performance && FAILED_TESTS=$((FAILED_TESTS + 0)) || FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        js_check) test_js_check && FAILED_TESTS=$((FAILED_TESTS + 0)) || FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
    esac
    echo ""
done

# Results summary
echo "🎯 Test Summary:"
echo "   Tests run: ${#TESTS_TO_RUN[@]}"
echo "   Failed: $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo "   🎉 All tests passed! Deployment successful!"
    echo ""
    echo "📱 Manual Testing Instructions:"
    echo "   1. Visit https://$TEST_DOMAIN - should see landing page"
    echo "   2. Click 'Start a New Room' - should redirect to Conspire instance"
    echo "   3. Test chat interface - should work in browser"
    echo "   4. Try multiple browser windows for real-time chat testing"
else
    echo "   ❌ Some tests failed. Check logs above."
    echo "   Failed: $FAILED_TESTS/${#TESTS_TO_RUN[@]} tests"
fi

echo ""
echo "🔗 Quick Access Links:"
echo "   🌐 Landing: https://$TEST_DOMAIN"
echo "   💬 Conspire: https://$TEST_DOMAIN:8443"
echo ""
echo "🧹 Cleanup: ./cleanup.sh"
echo "💰 Estimated test cost: ~\$0.01-0.02"

# Exit with number of failed tests
exit $FAILED_TESTS
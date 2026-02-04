# Conspire Testing Scripts

This directory contains simplified, unified testing scripts for Conspire deployment validation.

## 🚀 One-Command Workflow (Primary Usage)

### `deploy-and-test.sh` - Complete Deploy & Test
**Recommended for 90% of use cases** - Creates instance, deploys infrastructure, runs tests, optionally opens browser.

```bash
# Basic workflow (recommended for quick validation)
./deploy-and-test.sh

# Full workflow with browser and comprehensive testing
./deploy-and-test.sh --open-browser --test-level comprehensive

# Quick deploy for manual testing
./deploy-and-test.sh --deploy-only --verbose
```

**Options:**
- `-h, --help`: Complete workflow guide and examples
- `-v, --verbose`: Detailed operations and progress
- `--version`: Version information
- `--open-browser`: Open browser to landing page after deployment
- `--test-level LEVEL`: Test depth (basic|standard|comprehensive)
- `--deploy-only`: Deploy without testing (for manual testing)

**Features:**
- ✅ Creates test instance + DNS (parallel SSH + DNS wait - 50-70% faster)
- ✅ Deploys Conspire + Landing page infrastructure
- ✅ Runs deployment tests (3 configurable levels)
- ✅ Optionally opens browser to deployed site
- ✅ Safe test-only deployments (no production impact)
- ✅ Instance targeting for easy cleanup

---

## 🛠️ Individual Scripts (Advanced Use)

For CI/CD, custom workflows, or manual control:

### 1. `create-test-instance.sh` - Instance Creation + DNS
Creates a Linode instance and DNS record tied to instance ID.

```bash
./create-test-instance.sh [--verbose]
```

**Features:**
- Creates Linode with SSH key authentication
- DNS hostname: `test-{INSTANCE_ID}.goneelsewhere.org`
- Parallel SSH + DNS waits (50-70% faster)
- Generates Ansible inventory and variables
- Fails fast if DNS fails (required for cert management)

### 2. `test-deployment.sh` - Configurable Testing
Tests deployed Conspire infrastructure with configurable depth.

```bash
./test-deployment.sh [test_level]
```

**Test Levels:**
- `basic`: Core functionality (DNS, SSL, services)
- `standard`: Recommended tests (includes room creation)
- `comprehensive`: Full validation (includes performance and JS checks)

### 3. `cleanup.sh` - Resource Cleanup
Cleans up test instances and their DNS records.

```bash
./cleanup.sh all              # Clean up everything
./cleanup.sh status           # Show current resources
./cleanup.sh old 3600         # Clean up instances older than 1 hour
./cleanup.sh specific 91029154 # Clean up specific instance
```

**Safety Features:**
- Instance-driven cleanup (delete instance → delete its DNS)
- Age-based cleanup for forgotten resources
- Orphaned DNS cleanup
- Passive status reporting

### 4. `dns-manager.sh` - DNS Utilities
Low-level DNS management utilities.

```bash
./dns-manager.sh create 91029154 172.234.253.161    # Create DNS record
./dns-manager.sh status                               # Show all records
./dns-manager.sh cleanup-all                          # Clean up all records
./dns-manager.sh --clear-cache                       # Fix DNS cache issues
```

**DNS Naming:**
- Records: `test-{INSTANCE_ID}.goneelsewhere.org`
- TTL: 60 seconds for fast testing
- Cache-safe propagation checking

---

## 🏗️ Architecture Benefits

### CI/CD Parallelism ✅
- Each test instance gets unique DNS: `test-{INSTANCE_ID}.domain.com`
- Multiple test runs can operate in parallel
- No DNS collisions or sequential numbering required

### Fast Testing ✅
- 60s TTL for rapid DNS propagation
- Parallel SSH + DNS waits (50-70% faster)
- Fail-fast approach (DNS required for cert management)
- Configurable test depth for different use cases

### Production Safety ✅
- Test instance targeting only
- No impact on production infrastructure
- Instance-driven cleanup prevents orphaned resources
- Easy resource tracking and cleanup

---

## 💰 Cost Optimization

- **Instance**: Linode nanode (~$0.0075/hour)
- **DNS**: Free with Linode domain
- **Total test cost**: ~$0.01-0.02 per complete test cycle

---

## 🔄 Example Workflows

### Development Testing (Most Common)
```bash
# Quick validation
./deploy-and-test.sh

# Full testing with browser
./deploy-and-test.sh --open-browser --test-level standard

# Deploy only for manual testing
./deploy-and-test.sh --deploy-only
```

### CI/CD Pipeline
```bash
#!/bin/bash
set -e

# Full automated testing
./deploy-and-test.sh --test-level comprehensive

# Auto-cleanup on exit
trap './cleanup.sh all' EXIT
```

### Manual Step-by-Step
```bash
# 1. Create test environment
./create-test-instance.sh --verbose

# 2. Deploy infrastructure
cd .
ansible-playbook -i inventories/test/hosts.yml site.yml

# 3. Test deployment
cd ./scripts
./test-deployment.sh standard

# 4. Clean up when done
./cleanup.sh all
```

### Troubleshooting DNS Issues
```bash
# Clear DNS cache if stuck with NXDOMAIN
./dns-manager.sh --clear-cache

# Check DNS status
./dns-manager.sh status

# Clean up orphaned records
./cleanup.sh dns-only
```

---

## 📋 Prerequisites

- **Linode CLI**: Configured with API token
- **SSH Keys**: `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`
- **Ansible**: For infrastructure deployment
- **Domain**: DNS zone configured in Linode

---

## 🔍 Help System

All scripts include comprehensive help systems:
```bash
./deploy-and-test.sh --help      # Workflow guide
./create-test-instance.sh --help  # Instance creation guide
./test-deployment.sh --help      # Testing guide
./cleanup.sh --help             # Cleanup guide with safety features
./dns-manager.sh --help         # DNS management guide
```
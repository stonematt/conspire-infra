# AGENTS.md - Conspire Infrastructure

## Commands

```bash
# Infrastructure only (conspire + web server, no site content)
ansible-playbook -i inventories/production/hosts.yml infra.yml

# Full deploy (conspire + landing)
ansible-playbook -i inventories/production/hosts.yml site.yml

# Landing page only
ansible-playbook -i inventories/production/hosts.yml deploy.yml

# Dry run
ansible-playbook -i inventories/production/hosts.yml infra.yml --check --diff

# Syntax check
ansible-playbook --syntax-check site.yml
```

## Structure

```
conspire-infra/
├── site.yml           # Full deploy playbook
├── deploy.yml         # Landing content only
├── vendor/
│   └── conspire-site/ # Git submodule for static content
├── roles/
│   ├── conspire/      # Binary, certs, systemd (port 8443)
│   └── landing/       # Caddy, static files (port 443)
├── inventories/
│   └── example/
└── group_vars/
```

## Key Variables (group_vars/all.yml)

```yaml
domain: s.itri.me
certbot_email: admin@example.com
conspire_port: "8443"
```

## Roles

### conspire
- Downloads latest binary from GitHub releases
- Obtains Let's Encrypt certs via certbot
- Creates systemd service on port 8443
- Sets up cert renewal hooks

### landing
- Installs Caddy
- Deploys static files from vendor/conspire-site/
- Configures TLS on port 443

## Content Management

Static site content is automatically pulled from the `live` branch during deployment:

```bash
# Deploy latest content (auto-updates from live branch)
ansible-playbook -i inventories/production/hosts.yml deploy.yml

# Full deployment (includes latest content)
ansible-playbook -i inventories/production/hosts.yml site.yml
```

**Note:** The landing role automatically updates `vendor/conspire-site` to the latest `live` branch before each deployment, ensuring content is always current.

## Testing

1. Preview landing page locally: `open vendor/conspire-site/index.html`
2. Verify JS generates correct URLs with `:8443`
3. Dry run: `--check --diff`
4. Deploy to staging first if available

# AGENTS.md - Conspire Infrastructure

## Commands

```bash
# Full deploy (conspire + landing)
ansible-playbook -i inventories/production/hosts.yml site.yml

# Landing page only
ansible-playbook -i inventories/production/hosts.yml deploy.yml

# Dry run
ansible-playbook -i inventories/production/hosts.yml site.yml --check --diff

# Syntax check
ansible-playbook --syntax-check site.yml
```

## Structure

```
conspire-infra/
├── site.yml           # Full deploy playbook
├── deploy.yml         # Landing content only
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
- Deploys static files from site_content/
- Configures TLS on port 443

## Submodule

Landing page content lives in `site_content/` submodule:

```bash
git submodule add ../conspire-site site_content
git submodule update --init
```

## Testing

1. Preview landing page locally: `open site_content/index.html`
2. Verify JS generates correct URLs with `:8443`
3. Dry run: `--check --diff`
4. Deploy to staging first if available

# Conspire Infrastructure

Ansible playbooks for deploying [Conspire](https://dyne.org/conspire/) with a custom landing page.

## Architecture

```
host.example.com:443  → Caddy → static landing page
host.example.com:8443 → Conspire (direct TLS)
```

## Quick Start

```bash
# Configure
cp inventories/example/hosts.yml.example inventories/production/hosts.yml
cp group_vars/all.yml.example group_vars/all.yml
# Edit both files with your domain and server details

# Deploy everything
ansible-playbook -i inventories/production/hosts.yml site.yml

# Update landing page only
ansible-playbook -i inventories/production/hosts.yml deploy.yml
```

## Roles

| Role | Port | Description |
|------|------|-------------|
| `conspire` | 8443 | Binary install, TLS certs, systemd |
| `landing` | 443 | Caddy, static site |

## Testing

Automated testing is included in this repository:

```bash
# One-command workflow (recommended)
./scripts/deploy-and-test.sh --test-level standard

# Manual testing workflow
./scripts/create-test-instance.sh
ansible-playbook -i inventories/test/hosts.yml site.yml
./scripts/test-deployment.sh standard
./scripts/cleanup.sh all
```

Note: Currently configured for Linode instances as example cloud provider.

## Requirements

- Ansible 2.10+
- Target: Debian/Ubuntu
- DNS A record pointing to server
- Ports 80 (temp for certbot), 443, 8443 open

## Submodule

Landing page content is in `site_content/` submodule:

```bash
git submodule update --init
```

## License

MIT

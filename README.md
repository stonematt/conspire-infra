# Conspire Infrastructure

Deploy [Conspire](https://dyne.org/conspire/) — ephemeral, anonymous, peer-to-peer chat — with a single Ansible command. Includes automated TLS certificates and a customizable landing page.

## Why This Project?

Conspire is powerful but minimal: it's a WebSocket chat server with a basic UI. For real-world use, you typically need:

- A branded landing page explaining what your community chat is for
- Room generation with shareable links
- TLS certificates (Let's Encrypt)
- A deployment path that doesn't require compiling C++

This project glues Conspire to a static landing site, handles TLS, and automates deployment via Ansible.

## Architecture

Conspire requires direct WebSocket connections (no reverse proxy). This setup uses two ports on a single domain:

```
your-domain.com:443  → Caddy (static landing page)
your-domain.com:8443 → Conspire (direct TLS, WebSocket chat)
```

The landing page includes JavaScript that generates cryptographically random room IDs and redirects users to Conspire on port 8443.

```
┌─────────────────────────────────────────────────────────┐
│                    Your Server                          │
│                                                         │
│   :443 ──► Caddy ──► Static Site (index.html, room.js) │
│                           │                             │
│                           │ "Start New Room" click      │
│                           ▼                             │
│   :8443 ──► Conspire (WebSocket chat, ephemeral rooms) │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Landing Page Integration

The landing page lives in `vendor/conspire-site/` (git submodule). It provides:

- Branded entry point for your community
- JavaScript room generator (`room.js`) that creates random Base58 room IDs
- Redirect to Conspire at `https://your-domain.com:8443/room/{id}`

The key integration is a button that triggers room creation:

```html
<button id="new-room">Start a New Room</button>
<script src="room.js"></script>
```

See [conspire-site](vendor/conspire-site/README.md) for customization (branding, styling, copy).

## Quick Start

### Prerequisites

- Ansible 2.10+
- Target server: Debian/Ubuntu with SSH access
- Domain with DNS A record pointing to your server
- Ports 80 (certbot), 443, and 8443 accessible

### 1. Configure

```bash
# Clone with submodule (landing page content)
git clone --recurse-submodules https://github.com/youruser/conspire-infra.git
cd conspire-infra

# Or init submodule if already cloned
git submodule update --init

# Copy example configs
cp inventories/example/hosts.yml.example inventories/production/hosts.yml
cp group_vars/all.yml.example group_vars/all.yml
```

Edit `inventories/production/hosts.yml`:
```yaml
all:
  hosts:
    your-server:
      ansible_host: 203.0.113.10  # Your server IP
      ansible_user: root
```

Edit `group_vars/all.yml`:
```yaml
domain: your-domain.com
certbot_email: you@example.com
site_title: "Your Community"
site_tagline: "Secure, anonymous chat"
```

### 2. Deploy

```bash
# Full deployment (infrastructure + landing page)
ansible-playbook -i inventories/production/hosts.yml site.yml
```

### 3. Use

Visit `https://your-domain.com` and click "Start a New Room". Share the resulting link with your group.

## Deployment Options

| Command | Description |
|---------|-------------|
| `site.yml` | Full deployment: server setup, Conspire, landing page |
| `infra.yml` | Infrastructure only: base system, Conspire binary, TLS |
| `deploy.yml` | Landing page only: update site content without touching Conspire |

```bash
# Update landing page content only
ansible-playbook -i inventories/production/hosts.yml deploy.yml
```

## Configuration

### Core Variables

In `group_vars/all.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `domain` | — | Your domain (required) |
| `certbot_email` | — | Email for Let's Encrypt (required) |
| `conspire_port` | `8443` | Conspire WebSocket port |
| `landing_port` | `443` | Landing page HTTPS port |
| `site_title` | "Neighborhood Connect" | Landing page title |
| `site_tagline` | "Secure, anonymous community chat" | Landing page tagline |

### Vendor Configuration

The landing page submodule is managed via the `vendor` stanza:

```yaml
vendor:
  site_content:
    enabled: true
    name: "conspire-site"
    repo: "git@github.com:stonematt/conspire-site.git"
    branch: "live"                    # Environment-specific
    local_path: "vendor/conspire-site"
    destination: "{{ landing_web_root }}/"
    owner: "caddy"
    group: "caddy"
```

| Key | Description |
|-----|-------------|
| `enabled` | Toggle submodule updates on/off |
| `branch` | Per-environment branch selection (live/main/test) |
| `repo` | Git repository URL |
| `local_path` | Submodule location on control host |
| `destination` | Target path on remote server |
| `owner`/`group` | File ownership on remote |

This allows environment-specific branch targeting (e.g., `test` branch for test inventory, `live` for production) and is extensible for additional vendor submodules.

## Testing

Automated testing scripts are provided for development validation using Linode instances:

```bash
# Recommended: one-command test cycle
./scripts/deploy-and-test.sh --test-level standard

# With browser verification
./scripts/deploy-and-test.sh --open-browser --test-level comprehensive

# Manual testing workflow
./scripts/create-test-instance.sh
ansible-playbook -i inventories/test/hosts.yml site.yml
./scripts/test-deployment.sh standard
./scripts/cleanup.sh all
```

See [scripts/README.md](scripts/README.md) for detailed testing documentation.

## Project Structure

```
conspire-infra/
├── site.yml                 # Main playbook (full deployment)
├── infra.yml                # Infrastructure-only playbook
├── deploy.yml               # Landing page-only playbook
├── group_vars/
│   ├── all.yml.example      # Configuration template
│   └── all.yml              # Your configuration (gitignored)
├── inventories/
│   ├── example/             # Template inventory
│   ├── production/          # Production servers
│   └── test/                # Test instances
├── roles/
│   ├── conspire/            # Conspire binary, TLS, systemd
│   ├── landing/             # Caddy, static site deployment
│   └── landing-infra/       # Base Caddy installation
├── scripts/                 # Testing automation (Linode)
└── vendor/
    └── conspire-site/       # Landing page submodule
```

## Related Projects

- **[Conspire](https://dyne.org/conspire/)** — The core chat application by Dyne.org
- **[conspire-site](https://github.com/youruser/conspire-site)** — Landing page template (included as submodule)

## Troubleshooting

**Port 8443 not accessible**: Check firewall rules (`ufw allow 8443/tcp`) and any cloud firewall settings.

**Certificate errors**: Ensure DNS points to your server before running the playbook. Let's Encrypt needs to reach port 80.

**WebSocket connection failed**: Conspire must have direct network access. Don't put it behind nginx/Apache.

**Landing page not updating**: Run `deploy.yml` or ensure the submodule is up to date with `git submodule update --remote`.

## License

MIT — See [LICENSE](LICENSE)

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

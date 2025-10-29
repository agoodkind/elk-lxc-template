# ELK Stack LXC for Proxmox

Automated installation of Elasticsearch, Logstash, and Kibana (ELK Stack 8.x) on Proxmox LXC containers.

## Features

✅ **Interactive Configuration**
- SSL/TLS options (Full HTTPS, Backend only, or No SSL)
- Optional memory customization (Elasticsearch & Logstash heap sizes)

✅ **Automatic Security**
- Unique password generation
- SSL certificate creation
- API key management via keystores
- HTTPS enabled by default

✅ **Production Ready**
- IPv6 preferred networking
- Optimized resource allocation
- Comprehensive logging
- Self-contained installation

## Quick Start

### Method 1: Proxmox Community Script

```bash
# Run on Proxmox host
bash -c "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/elk-stack.sh)"
```

During installation:
1. Choose SSL configuration
2. Optionally customize memory
3. Wait for installation (~10-20 minutes)
4. Retrieve credentials: `pct exec CTID -- cat /root/elk-credentials.txt`

### Method 2: Template Build (Multiple Deployments)

```bash
# On Proxmox host
git clone https://github.com/agoodkind/elk-lxc-template.git
cd elk-lxc-template
chmod +x scripts/build/template.sh
./scripts/build/template.sh
```

Deploy from template:
```bash
./examples/deploy-example.sh 300 elk-server
```

## Container Specifications

- **OS**: Ubuntu 24.04
- **CPU**: 4 cores
- **RAM**: 8GB
- **Disk**: 32GB
- **Network**: Dual-stack (IPv4 + IPv6)

## Services & Ports

- **Elasticsearch**: 9200 (HTTP API)
- **Kibana**: 5601 (Web UI)
- **Logstash**: Ready for custom pipelines

## Post-Installation

### Access Kibana

```bash
# Get credentials
pct exec CONTAINER_ID -- cat /root/elk-credentials.txt

# Access via browser
https://CONTAINER_IP:5601
```

### Reset Password

```bash
pct exec CONTAINER_ID -- /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
```

### Add Logstash Pipelines

```bash
# Create custom pipelines in /etc/logstash/conf.d/
pct exec CONTAINER_ID -- nano /etc/logstash/conf.d/my-pipeline.conf
pct exec CONTAINER_ID -- systemctl restart logstash
```

## Development

### Build System

```bash
# Remote mode (for PR submission)
make installer

# Local mode (for testing)
make installer-local

# Template mode
make template

# Tests
make test-quick
```

### Project Structure

```
elk-lxc-template/
├── scripts/
│   ├── install/
│   │   └── elk-stack.sh         # Single source of truth (all configs inline)
│   └── build/
│       ├── ct-wrapper.sh        # Generates out/ct/elk-stack.sh
│       ├── installer.sh         # Generates out/install/elk-stack-install.sh
│       ├── template.sh          # Builds LXC template
│       └── lib/                 # Build helper functions
├── templates/
│   ├── elk-stack-ct-content.sh  # CT wrapper content template
│   ├── header-ascii.txt         # ASCII art
│   └── ui-metadata.json         # UI configuration
├── examples/
│   └── deploy-example.sh        # Template deployment example
├── tests/
│   └── test-build.sh            # Test suite (40 tests)
└── Makefile                     # Build orchestration
```

## Security

- SSL/TLS certificates auto-generated
- Unique passwords per installation
- API keys stored in keystores (encrypted)
- No credentials in plain text
- Self-signed certificates (replace for production)

## Troubleshooting

### Service Status

```bash
pct exec CTID -- systemctl status elasticsearch logstash kibana
pct exec CTID -- journalctl -u elasticsearch -f
```

### Installation Logs

```bash
pct exec CTID -- cat /var/log/elk-install.log
pct exec CTID -- tail -f /var/log/elk-install.log
```

### Network Test

```bash
pct exec CTID -- curl -k https://localhost:9200 -u elastic:PASSWORD
```

## License

Apache License 2.0

## Contributing

Issues and pull requests welcome at https://github.com/agoodkind/elk-lxc-template

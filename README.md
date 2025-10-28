# ELK Stack LXC Template

Automated installation of Elasticsearch, Logstash, and Kibana (ELK Stack) on Proxmox LXC containers.

## Installation Methods

### Method 1: Proxmox Community Script (Recommended)

**Important**: `install.sh` must be built from source before use.

Build the installer:
```bash
git clone https://github.com/agoodkind/elk-lxc-template.git
cd elk-lxc-template
make clean && make
```

Run the generated installer:
```bash
bash out/install.sh
```

This will:
- Create an LXC container with 4 CPU cores, 8GB RAM, 32GB disk
- Install ELK Stack 8.x on Ubuntu 24.04
- Configure all services
- Start services without security (for initial testing)

After installation, configure security:
```bash
pct exec CONTAINER_ID -- /root/elk-configure-security.sh
```

### Method 2: Manual Template Build

Build reusable template for multiple deployments:

```bash
chmod +x build.sh scripts/*.sh examples/*.sh && ./build.sh
```

Deploy container from template:
```bash
./examples/deploy-example.sh 300 elk-prod 192.168.1.100
```

## Configuration

### Initial Setup (Method 1)

After installation with community script:
1. Access Kibana at `http://CONTAINER_IP:5601` (no authentication required initially)
2. Run security configuration: `/root/elk-configure-security.sh`
3. Choose SSL options when prompted
4. Save displayed elastic password
5. Access secured Kibana with credentials

### Security Configuration

The security script prompts for:
- **Backend SSL**: Encrypts Elasticsearch communication
- **Frontend SSL**: Enables HTTPS for Kibana web interface

Features:
- Generates auto-signed certificates using Elasticsearch certutil
- Creates unique passwords per installation
- Stores API keys in keystores (never plain text)
- Password displayed once (not saved to disk)
- Kibana uses service token or API key in keystore
- Logstash uses API key with write-only permissions

### Management Commands

Rotate API keys:
```bash
/root/elk-rotate-api-keys.sh
```

Reset elastic password:
```bash
/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
```

Update ELK stack:
```bash
apt update && apt upgrade elasticsearch logstash kibana
systemctl restart elasticsearch logstash kibana
```

## Container Specifications

- **OS**: Ubuntu 24.04
- **CPU**: 4 cores
- **RAM**: 8GB
- **Disk**: 32GB
- **Network**: Bridge mode (dhcp or static IP)

## Services

- **Elasticsearch**: Port 9200 (HTTP API)
- **Kibana**: Port 5601 (Web Interface)
- **Logstash**: Port 5044 (Beats), Port 5000 (TCP JSON)

## Architecture

### Keystores
- Kibana keystore: `/etc/kibana/kibana.keystore`
- Logstash keystore: `/etc/logstash/logstash.keystore`
- Permissions: 660, owned by service users

### Certificates (if SSL enabled)
- Elasticsearch certs: `/etc/elasticsearch/certs/`
- Kibana certs: `/etc/kibana/certs/`
- Logstash certs: `/etc/logstash/certs/`

### Configuration Files
- Elasticsearch: `/etc/elasticsearch/elasticsearch.yml`
- Kibana: `/etc/kibana/kibana.yml`
- Logstash pipelines: `/etc/logstash/conf.d/`
- JVM options: `/etc/*/jvm.options.d/heap.options`

## Default Resource Allocation

- Elasticsearch heap: 2GB
- Logstash heap: 1GB
- Kibana: Remaining RAM

Adjust in `/etc/*/jvm.options.d/heap.options` if needed.

## Security Notes

- Initial installation has no authentication (testing only)
- Run security configuration before production use
- All API keys stored in keystores (encrypted at rest)
- No credentials in configuration files
- Elastic password shown once during setup
- Self-signed certificates suitable for internal use
- For production, replace with CA-signed certificates

## Troubleshooting

Check service status:
```bash
systemctl status elasticsearch logstash kibana
```

View logs:
```bash
journalctl -u elasticsearch -f
journalctl -u logstash -f
journalctl -u kibana -f
```

Test Elasticsearch:
```bash
curl -k -u elastic:PASSWORD https://localhost:9200
```

List keystore contents:
```bash
/usr/share/kibana/bin/kibana-keystore list
/usr/share/logstash/bin/logstash-keystore list
```

## License

Apache License 2.0

## Build System

The `out/install.sh` file is generated from component scripts using Make:

```bash
# Generate install.sh
make

# Clean generated files
make clean

# Run comprehensive test suite
make test

# Quick syntax validation
make test-quick

# Verify component files
make check-components
```

**Component Structure:**
- `templates/install-header.sh` - Proxmox framework setup
- `templates/extract-install-logic.awk` - AWK processor for install-steps.sh
- `templates/install-footer.sh` - Final setup and output
- `scripts/install-steps.sh` - Installation logic (source of truth)
- `scripts/post-deploy.sh` - Security configuration script
- `scripts/rotate-api-keys.sh` - API key rotation script
- `config/` - Configuration files embedded via EMBED_FILE markers
  - `elasticsearch.yml` - Elasticsearch configuration
  - `kibana.yml` - Kibana configuration
  - `jvm.options.d/` - JVM heap settings
  - `logstash-pipelines/` - Logstash pipeline configurations
- `tests/test-build.sh` - Comprehensive test suite (58 tests)

**EMBED_FILE Markers:**

Scripts reference config files using markers:
```bash
# EMBED_FILE: config/file.yml -> /etc/service/file.yml          # Creates new file
# EMBED_FILE_APPEND: config/file.yml -> /etc/service/file.yml   # Appends to file
```

AWK processor reads config files and embeds during build.

**Why this approach?**
- **Separation of concerns**: Config files separate from logic
- **DRY principle**: Single source for configuration
- **Easy maintenance**: Edit configs without touching scripts
- **Automatic rebuild**: Makefile tracks config dependencies
- **Two build modes**:
  - Template build: `scripts/install-elk.sh` sources `install-steps.sh` directly
  - Community script: Makefile processes `install-steps.sh` and embeds configs
- Comprehensive test suite validates all components

## Contributing

Submit issues and pull requests on GitHub.

**When modifying installation logic**, edit `scripts/install-steps.sh` and regenerate:
```bash
make clean && make && make test
```

**When modifying configurations**, edit files in `config/` directory - Makefile automatically rebuilds.

Both the template build and community script will use updated logic and configs.

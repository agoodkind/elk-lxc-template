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
- Log all installation steps to `/var/log/elk-install.log` inside container

Monitor installation progress:
```bash
# View installation log in real-time
pct exec CONTAINER_ID -- tail -f /var/log/elk-install.log
```

After installation, configure security:
```bash
pct exec CONTAINER_ID -- /root/elk-configure-security.sh
```

### Method 2: Manual Template Build

**Entrypoint**: `build.sh` - Run on Proxmox host as root

Build reusable template for multiple deployments:

```bash
# Make scripts executable
chmod +x build.sh scripts/*.sh examples/*.sh

# Run template builder (shows live installation progress)
./build.sh

# If Ubuntu mirrors are slow, use a faster one:
UBUNTU_MIRROR=mirrors.mit.edu ./build.sh

# Other fast mirror options:
# UBUNTU_MIRROR=mirror.math.princeton.edu ./build.sh
# UBUNTU_MIRROR=mirror.us.leaseweb.net ./build.sh
```

The build script will:
- Create a temporary LXC container (ID 900)
- Install and configure ELK Stack with full logging
- Display live installation progress from `/var/log/elk-install.log`
- Clean up and export as reusable template
- Save to `/var/lib/vz/template/cache/elk-stack-ubuntu-24.04.tar.zst`

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

### Installation Logs

Both deployment methods log to `/var/log/elk-install.log` inside the container:

```bash
# View installation log
pct exec CONTAINER_ID -- cat /var/log/elk-install.log

# Monitor installation in real-time
pct exec CONTAINER_ID -- tail -f /var/log/elk-install.log

# Check for errors during installation
pct exec CONTAINER_ID -- grep -i error /var/log/elk-install.log
```

### Service Status

Check service status:
```bash
systemctl status elasticsearch logstash kibana
```

View service logs:
```bash
journalctl -u elasticsearch -f
journalctl -u logstash -f
journalctl -u kibana -f
```

### Connectivity Tests

Test Elasticsearch:
```bash
curl -k -u elastic:PASSWORD https://localhost:9200
```

Test Kibana:
```bash
curl http://localhost:5601/api/status
```

### Keystore Management

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
- `scripts/install-elk.sh` - **Single source of truth** for all installation logic
- `build.sh` - Template builder, defines logging shims and calls install-elk.sh
- `templates/install-header.sh` - Proxmox framework setup
- `templates/install-footer.sh` - Final setup and output
- `scripts/post-deploy.sh` - Security configuration script
- `scripts/rotate-api-keys.sh` - API key rotation script
- `config/` - Configuration files embedded during build
  - `elasticsearch.yml` - Elasticsearch configuration
  - `kibana.yml` - Kibana configuration
  - `jvm.options.d/` - JVM heap settings
  - `logstash-pipelines/` - Logstash pipeline configurations
- `tests/test-build.sh` - Comprehensive test suite (58 tests)

**Single Source of Truth:**

`scripts/install-elk.sh` is the only installation script. It works in two modes:

1. **Template build**: `build.sh` defines shims (`msg_info`, `msg_ok`, `handle_config`) with logging, then sources `install-elk.sh`
2. **Community script**: Makefile wraps `install-elk.sh` with Proxmox framework and embeds config files inline

**Why this approach?**
- **True single source**: All installation logic in one file (`install-elk.sh`)
- **No duplication**: Same code runs in both deployment modes
- **Shim pattern**: Caller defines environment-specific functions
- **Easy maintenance**: Edit one file, both modes stay in sync
- **Automatic rebuild**: Makefile tracks all dependencies

## Contributing

Submit issues and pull requests on GitHub.

**When modifying installation logic**, edit `scripts/install-elk.sh` and regenerate:
```bash
make clean && make && make test
```

**When modifying configurations**, edit files in `config/` directory - Makefile automatically rebuilds.

Both the template build and community script use the same `install-elk.sh` logic.

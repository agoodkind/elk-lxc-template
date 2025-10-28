# ELK Stack LXC - Quick Start

## For Proxmox Community Script Submission

### Main Installation Script

**File**: `install.sh`

Single-file installer compatible with Proxmox community scripts framework.

### Installation Command

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/agoodkind/elk-lxc-template/main/install.sh)"
```

### What Gets Installed

1. **Container**: Ubuntu 24.04 LXC (4 CPU, 8GB RAM, 32GB disk)
2. **ELK Stack**: Elasticsearch, Logstash, Kibana 8.x
3. **Configuration**: Base configs for all services
4. **Keystores**: Pre-initialized for secure credential storage
5. **Management Scripts**:
   - `/root/elk-configure-security.sh` - Enable authentication and SSL
   - `/root/elk-rotate-api-keys.sh` - Rotate API keys

### Post-Installation Steps

1. **Access Initial Installation** (no authentication):
   ```
   http://CONTAINER_IP:5601
   ```

2. **Configure Security**:
   ```bash
   pct exec CONTAINER_ID -- /root/elk-configure-security.sh
   ```
   
   This will:
   - Prompt for SSL options (backend and frontend)
   - Generate certificates
   - Create unique passwords
   - Set up API keys in keystores
   - Display elastic password (save it!)

3. **Access Secured Installation**:
   ```
   http://CONTAINER_IP:5601  (or https if frontend SSL enabled)
   Username: elastic
   Password: [displayed during security configuration]
   ```

### Repository Structure

```
elk-lxc-template/
├── install.sh              # Proxmox community script (main file)
├── README.md               # User documentation
├── SUBMISSION.md           # Guide for submitting to Proxmox community
├── QUICKSTART.md          # This file
├── build.sh               # (Optional) Template builder for multiple deployments
├── scripts/               # (Optional) Individual scripts for template method
│   ├── install-elk.sh
│   ├── post-deploy.sh
│   ├── cleanup.sh
│   └── rotate-api-keys.sh
├── config/                # (Optional) Config files for template method
│   ├── elasticsearch.yml
│   ├── kibana.yml
│   └── logstash-pipelines/
└── examples/              # (Optional) Deployment examples for template method
    └── deploy-example.sh
```

### Two Installation Methods

#### Method 1: Community Script (Recommended for Proxmox)
- Single command installation
- Uses Proxmox framework
- Perfect for community script submission
- File: `install.sh`

#### Method 2: Template Build (Optional for multiple deployments)
- Build once, deploy many times
- Good for organizations deploying multiple ELK instances
- Files: `build.sh`, `scripts/`, `config/`, `examples/`

### Key Features

✅ **Security First**
- No credentials in plain text
- Keystores for API keys
- SSL/TLS support
- Unique passwords per installation

✅ **Easy Management**
- Update function included
- API key rotation script
- Service management commands
- Clear documentation

✅ **Production Ready**
- Proper resource allocation
- Service isolation
- Tested configurations
- Elasticsearch best practices

### Service Ports

- **Elasticsearch**: 9200 (HTTP API)
- **Kibana**: 5601 (Web UI)
- **Logstash**: 5044 (Beats input), 5000 (TCP JSON)

### Resource Requirements

- **Minimum**: 4 CPU, 8GB RAM, 32GB disk
- **Elasticsearch heap**: 2GB (configured)
- **Logstash heap**: 1GB (configured)

### Updating ELK Stack

```bash
bash -c "$(wget -qLO - URL_TO_SCRIPT)" -s --update
```

Or manually:
```bash
apt update && apt upgrade elasticsearch logstash kibana
systemctl restart elasticsearch logstash kibana
```

### Troubleshooting

**Services not starting?**
```bash
systemctl status elasticsearch logstash kibana
journalctl -u elasticsearch -f
```

**Can't connect to Elasticsearch?**
```bash
curl http://localhost:9200
# Or with SSL:
curl -k -u elastic:PASSWORD https://localhost:9200
```

**Forgot password?**
```bash
/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
```

### Next Steps

1. **Test the script locally** on your Proxmox host
2. **Update copyright** in `install.sh` with your name
3. **Follow SUBMISSION.md** to submit to Proxmox community
4. **Update README.md** with your GitHub URLs

### Support

- Issues: https://github.com/YOUR_USERNAME/elk-lxc-template/issues
- Docs: https://github.com/YOUR_USERNAME/elk-lxc-template
- ELK Docs: https://www.elastic.co/guide/

### License

Apache License 2.0 - Free to use and modify


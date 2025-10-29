# ELK Stack LXC - Quick Start

## Installation

### Run on Proxmox Host

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/elk-stack.sh)"
```

### Interactive Prompts

During installation you'll be asked:

1. **SSL/TLS Configuration**
   - [1] Full HTTPS (Elasticsearch + Kibana) [Recommended]
   - [2] Backend only (Elasticsearch HTTPS, Kibana HTTP)
   - [3] No SSL (HTTP only - testing/dev)

2. **Memory Configuration** (optional)
   - Default: Elasticsearch 2GB, Logstash 1GB
   - Customize if needed

### Installation Process

- Creates Ubuntu 24.04 container
- Installs ELK Stack 8.x
- Configures security based on your choices
- Generates unique password
- Takes 10-20 minutes (~2GB download)

## Post-Installation

### Get Credentials

```bash
pct exec CONTAINER_ID -- cat /root/elk-credentials.txt
```

Shows:
- Kibana URL
- Username: `elastic`
- Generated password
- Management commands

### Access Kibana

```
https://CONTAINER_IP:5601
(or http if you chose No SSL)
```

### Reset Password

```bash
pct exec CONTAINER_ID -- /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
```

## Build from Source

### For Development/Testing

```bash
git clone https://github.com/agoodkind/elk-lxc-template.git
cd elk-lxc-template

# Local mode (fully embedded, no GitHub needed)
make clean && make installer-local

# Copy to Proxmox
scp out/ct/elk-stack.sh root@PROXMOX_HOST:/root/

# Run
ssh root@PROXMOX_HOST
bash /root/elk-stack.sh
```

### For PR Submission

```bash
# Remote mode (uses GitHub URLs)
make clean && make installer

# Test locally first
scp out/ct/elk-stack.sh root@PROXMOX_HOST:/root/
# Push to GitHub, then test download
```

## Service Ports

- Elasticsearch: 9200
- Kibana: 5601
- Logstash: Configure custom pipelines in `/etc/logstash/conf.d/`

## Updating

Reset password or modify configurations anytime:

```bash
# Reset password
/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic

# Restart services
systemctl restart elasticsearch logstash kibana

# Update packages
apt update && apt upgrade elasticsearch logstash kibana
```

## Support

- Issues: https://github.com/agoodkind/elk-lxc-template/issues
- ELK Docs: https://www.elastic.co/guide/

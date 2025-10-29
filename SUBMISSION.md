# Proxmox Community Scripts Submission Guide

## Prerequisites

1. Fork https://github.com/community-scripts/ProxmoxVE
2. Clone your fork:
```bash
git clone https://github.com/YOUR_USERNAME/ProxmoxVE.git
cd ProxmoxVE
```

## Submission Steps

### 1. Build and Test

```bash
cd /path/to/elk-lxc-template

# Build for production
make clean && make installer

# Run quick tests
make test-quick
```

### 2. Copy Generated Files

```bash
# Copy all 4 required files
cp out/ct/elk-stack.sh /path/to/ProxmoxVE/ct/elk-stack.sh
cp out/install/elk-stack-install.sh /path/to/ProxmoxVE/install/elk-stack-install.sh
cp out/ct/headers/elk-stack /path/to/ProxmoxVE/ct/headers/elk-stack
cp out/frontend/public/json/elk-stack.json /path/to/ProxmoxVE/frontend/public/json/elk-stack.json
```

### 3. Test on Proxmox

```bash
# On Proxmox host
cd /path/to/ProxmoxVE
bash ct/elk-stack.sh
```

Verify:
- Container created successfully
- ELK services running
- Interactive prompts work
- Kibana accessible
- Credentials saved

### 4. Create Pull Request

```bash
cd /path/to/ProxmoxVE

git add ct/elk-stack.sh install/elk-stack-install.sh ct/headers/elk-stack frontend/public/json/elk-stack.json
git commit -m "Add ELK Stack (Elasticsearch, Logstash, Kibana) installation script"
git push origin main
```

### 5. Submit PR

- Go to https://github.com/community-scripts/ProxmoxVE
- Click "New Pull Request"
- Select your fork
- Fill in PR template

## PR Description Template

```markdown
## ELK Stack Installation Script

### Description
Automated installation of Elasticsearch, Logstash, and Kibana (ELK Stack) version 8.x on Ubuntu 24.04 LXC containers with interactive configuration.

### Features
- ✅ Interactive SSL/TLS configuration (Full HTTPS/Backend only/No SSL)
- ✅ Optional memory customization during installation
- ✅ Automatic password generation and certificate creation
- ✅ API keys stored securely in keystores
- ✅ IPv6 preferred networking
- ✅ Comprehensive installation logging

### Installation Flow
1. User selects SSL configuration
2. Optionally customizes JVM heap sizes
3. Installs ELK Stack 8.x (~2GB download, 10-20 minutes)
4. Configures security based on choices
5. Saves credentials to `/root/elk-credentials.txt`

### Default Resources
- CPU: 4 cores
- RAM: 8GB
- Disk: 32GB
- OS: Ubuntu 24.04
- Unprivileged container

### Container Variables
```bash
var_cpu="4"
var_ram="8192"
var_disk="32"
var_os="ubuntu"
var_version="24.04"
var_unprivileged="1"
```

### Post-Installation
Users retrieve credentials with:
```bash
pct exec CONTAINER_ID -- cat /root/elk-credentials.txt
```

### Important Notes
1. **Automatic Security**: SSL and passwords configured during installation
2. **Self-Signed Certs**: Generated certificates suitable for internal use
3. **Minimum RAM**: 8GB required for Elasticsearch
4. **Password Storage**: Shown in credentials file (not displayed during install)
5. **No Pipelines**: Users configure Logstash pipelines post-installation

### Testing
Tested on Proxmox VE 8.x with Ubuntu 24.04 containers.

### Support
- GitHub: https://github.com/agoodkind/elk-lxc-template
- Issues: https://github.com/agoodkind/elk-lxc-template/issues
```

## After Submission

### Monitor PR
- Respond to reviewer feedback
- Make requested changes
- Update based on community input

### Once Merged

Users install with:
```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/elk-stack.sh)"
```

## Maintenance

After submission:
1. Keep scripts updated with latest ELK versions
2. Test with new Proxmox releases
3. Respond to community issues
4. Submit updates via new PRs

## File Structure for Submission

```
ProxmoxVE/
├── ct/
│   ├── elk-stack.sh              # Main CT wrapper
│   └── headers/
│       └── elk-stack             # ASCII art header
├── install/
│   └── elk-stack-install.sh      # Installation wrapper
└── frontend/public/json/
    └── elk-stack.json            # UI metadata
```

All 4 files required for complete submission.

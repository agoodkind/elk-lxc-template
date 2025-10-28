# Proxmox Community Scripts Submission Guide

## Submitting ELK Stack Script to Proxmox Community

### Prerequisites

1. Fork the Proxmox Community Scripts repository:
   ```bash
   https://github.com/community-scripts/ProxmoxVE
   ```

2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ProxmoxVE.git
   cd ProxmoxVE
   ```

### Submission Steps

1. **Run comprehensive test suite**:
   ```bash
   cd /path/to/elk-lxc-template
   make clean && make && make test
   ```

2. **Verify all tests pass** (58/58 tests):
   - Component file validation
   - Bash syntax validation
   - AWK script validation
   - Makefile target validation
   - Generated script validation
   - Structure validation
   - Content validation

3. **Copy the generated script**:
   ```bash
   cp out/install.sh /path/to/ProxmoxVE/ct/elk-stack.sh
   ```

4. **Verify the copyright header** in `ct/elk-stack.sh`:
   ```bash
   # Author: Alex Goodkind (agoodkind)
   ```

5. **Test the script locally**:
   ```bash
   # On your Proxmox host:
   bash -c "$(cat ct/elk-stack.sh)"
   ```

6. **Verify installation**:
   - Container created successfully
   - ELK services running
   - Kibana accessible
   - Security configuration script works
   - API key rotation works

7. **Create a pull request**:
   ```bash
   git add ct/elk-stack.sh
   git commit -m "Add ELK Stack (Elasticsearch, Logstash, Kibana) installation script"
   git push origin main
   ```

8. **Submit PR to upstream**:
   - Go to https://github.com/community-scripts/ProxmoxVE
   - Click "New Pull Request"
   - Select your fork and branch
   - Fill in PR template

### PR Description Template

```markdown
## ELK Stack Installation Script

### Description
Automated installation of Elasticsearch, Logstash, and Kibana (ELK Stack) version 8.x on Ubuntu 24.04 LXC containers.

### Features
- ✅ Installs Elasticsearch, Logstash, Kibana 8.x
- ✅ Creates keystores for secure credential storage
- ✅ Provides post-install security configuration script
- ✅ SSL/TLS support with auto-generated certificates
- ✅ API key-based authentication (no plain text passwords)
- ✅ API key rotation script included
- ✅ Update function for ELK stack upgrades
- ✅ Production-ready configuration

### Container Specs
- **OS**: Ubuntu 24.04
- **CPU**: 4 cores
- **RAM**: 8GB
- **Disk**: 32GB
- **Unprivileged**: Yes

### Usage
After installation:
1. Access Kibana at http://CONTAINER_IP:5601
2. Run security configuration: `/root/elk-configure-security.sh`
3. Save displayed credentials
4. Access with authentication

### Testing
- [x] Container creates successfully
- [x] All services start properly
- [x] Kibana accessible
- [x] Security configuration works
- [x] SSL certificates generate correctly
- [x] API keys stored in keystores
- [x] API key rotation works
- [x] Update function works

### Source
- Elasticsearch: https://www.elastic.co/elasticsearch
- Logstash: https://www.elastic.co/logstash
- Kibana: https://www.elastic.co/kibana

### Tags
logging, elasticsearch, kibana, logstash, elk, monitoring, analytics
```

### Community Script Requirements Checklist

- [x] Uses `build.func` framework
- [x] Includes `header_info` call
- [x] Sets all required variables (APP, var_tags, var_cpu, etc.)
- [x] Implements `update_script()` function
- [x] Uses `$STD` for silent command execution
- [x] Uses msg_info/msg_ok for progress messages
- [x] Properly handles errors
- [x] Creates unprivileged container
- [x] Includes copyright header with MIT license
- [x] Single self-contained script
- [x] Tested on Proxmox VE

### Script Variables

```bash
APP="ELK-Stack"
var_tags="logging;elasticsearch;kibana;logstash"
var_cpu="4"              # 4 CPU cores (Elasticsearch needs resources)
var_ram="8192"           # 8GB RAM (Elasticsearch requires minimum 2GB heap)
var_disk="32"            # 32GB disk (logs and indices)
var_os="ubuntu"
var_version="24.04"
var_unprivileged="1"     # Runs as unprivileged container
```

### Post-Install Scripts

The installation creates two management scripts:

1. **`/root/elk-configure-security.sh`**:
   - Configures SSL/TLS
   - Sets up authentication
   - Creates API keys
   - Stores credentials in keystores

2. **`/root/elk-rotate-api-keys.sh`**:
   - Rotates Logstash API key
   - Maintains security best practices

### Update Function

The `update_script()` function allows users to update their ELK stack:
```bash
# Run from Proxmox host:
bash -c "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/elk-stack.sh)" -s --update
```

### Important Notes

1. **Initial State**: Services start without authentication for ease of setup
2. **Security Required**: Run `/root/elk-configure-security.sh` before production use
3. **Self-Signed Certs**: Generated certificates are self-signed (suitable for internal use)
4. **Resource Requirements**: 8GB RAM minimum (Elasticsearch requirement)
5. **Password Storage**: Elastic password shown once, not saved to disk

### Support

- GitHub Issues: https://github.com/agoodkind/elk-lxc-template/issues
- Documentation: https://github.com/agoodkind/elk-lxc-template/blob/main/README.md

## After Submission

### Monitor PR Status
- Respond to reviewer comments promptly
- Make requested changes
- Update based on community feedback

### Once Merged
Users can install with:
```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/elk-stack.sh)"
```

Or via Proxmox VE Helper Scripts web interface.

## Alternative: Direct Installation

If not submitting to community scripts, users must build first:

```bash
git clone https://github.com/agoodkind/elk-lxc-template.git
cd elk-lxc-template
make clean && make
out/install.sh
```

## Maintenance

After submission:
1. Keep install.sh updated with latest ELK versions
2. Test with new Proxmox releases
3. Update documentation as needed
4. Respond to community issues/questions
5. Submit updates via new PRs


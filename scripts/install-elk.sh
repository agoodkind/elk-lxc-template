#!/bin/bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0

set -e

# Initialize logging
LOG_FILE="/var/log/elk-install.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting ELK Stack installation" | tee "$LOG_FILE"
echo "Installation log: $LOG_FILE" | tee -a "$LOG_FILE"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Step marker function
step_info() {
    echo "" | tee -a "$LOG_FILE"
    echo "▶ $1" | tee -a "$LOG_FILE"
}

step_ok() {
    echo "✓ $1" | tee -a "$LOG_FILE"
}

# Update system and install dependencies
log "Updating system packages"
apt update 2>&1 | tee -a "$LOG_FILE"
apt upgrade -y 2>&1 | tee -a "$LOG_FILE"

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Process and execute installation steps with logging
step_info "Installing Dependencies"
log "Starting dependency installation"
apt-get install -y curl wget gnupg apt-transport-https ca-certificates openjdk-11-jre-headless vim net-tools htop unzip openssl 2>&1 | tee -a "$LOG_FILE"
log "Dependencies installed"
step_ok "Installing Dependencies"

step_info "Adding Elastic Repository"
log "Downloading Elastic GPG key"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg 2>&1 | tee -a "$LOG_FILE"
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
log "Elastic repository added"
step_ok "Adding Elastic Repository"

step_info "Installing ELK Stack (Elasticsearch, Logstash, Kibana)"
log "Running apt-get update"
apt-get update 2>&1 | tee -a "$LOG_FILE"
log "Downloading ELK packages (this may take several minutes)"
apt-get install -y elasticsearch logstash kibana 2>&1 | tee -a "$LOG_FILE"
log "ELK Stack packages installed"
step_ok "Installing ELK Stack"

step_info "Configuring Elasticsearch"
log "Configuring Elasticsearch"
cat /tmp/elk-config/elasticsearch.yml >> /etc/elasticsearch/elasticsearch.yml
cat /tmp/elk-config/elasticsearch.options > /etc/elasticsearch/jvm.options.d/heap.options
step_ok "Configuring Elasticsearch"

step_info "Configuring Logstash"
mkdir -p /etc/logstash/conf.d
cat /tmp/elk-config/00-input.conf > /etc/logstash/conf.d/00-input.conf
cat /tmp/elk-config/30-output.conf > /etc/logstash/conf.d/30-output.conf
cat /tmp/elk-config/logstash.options > /etc/logstash/jvm.options.d/heap.options
step_ok "Configuring Logstash"

step_info "Configuring Kibana"
cat /tmp/elk-config/kibana.yml >> /etc/kibana/kibana.yml
step_ok "Configuring Kibana"

step_info "Initializing Keystores"
log "Initializing keystores"
/usr/share/kibana/bin/kibana-keystore create 2>&1 | tee -a "$LOG_FILE"
chown kibana:kibana /etc/kibana/kibana.keystore
chmod 660 /etc/kibana/kibana.keystore

/usr/share/logstash/bin/logstash-keystore create 2>&1 | tee -a "$LOG_FILE"
chown logstash:logstash /etc/logstash/logstash.keystore
chmod 660 /etc/logstash/logstash.keystore
step_ok "Initializing Keystores"

step_info "Enabling Services"
systemctl enable elasticsearch logstash kibana 2>&1 | tee -a "$LOG_FILE"
step_ok "Enabling Services"

log "ELK Stack installation completed successfully"
echo "" | tee -a "$LOG_FILE"
echo "Installation log saved to: $LOG_FILE" | tee -a "$LOG_FILE"

# Clean up temp config directory
rm -rf /tmp/elk-config

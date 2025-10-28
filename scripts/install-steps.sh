#!/bin/bash
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0
#
# Installation steps for ELK Stack
# This file contains the raw installation commands that are:
# 1. Used by scripts/install-elk.sh for template builds
# 2. Parsed by Makefile to generate out/install.sh for Proxmox community scripts

# STEP: Installing Dependencies
apt-get install -y curl wget gnupg apt-transport-https ca-certificates openjdk-11-jre-headless vim net-tools htop unzip openssl

# STEP: Adding Elastic Repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list

# STEP: Installing ELK Stack (Elasticsearch, Logstash, Kibana)
apt-get update
apt-get install -y elasticsearch logstash kibana

# STEP: Configuring Elasticsearch
cat >> /etc/elasticsearch/elasticsearch.yml << 'ELKEOF'
# Elasticsearch network configuration
# Prefer IPv6 and listen on all interfaces
network.host: [_::, 0.0.0.0]
http.port: 9200

# Cluster and node settings
cluster.name: elk-cluster
node.name: ${HOSTNAME}

# Disable security and SSL for demo/dev use
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
ELKEOF

cat > /etc/elasticsearch/jvm.options.d/heap.options << 'ELKEOF'
# JVM heap settings for Elasticsearch
-Xms2g
-Xmx2g
ELKEOF

# STEP: Configuring Logstash
mkdir -p /etc/logstash/conf.d

cat > /etc/logstash/conf.d/00-input.conf << 'ELKEOF'
# Logstash input configuration
input {
	beats {
		port => 5044
	}
	tcp {
		port => 5000
		codec => json
	}
}
ELKEOF

cat > /etc/logstash/conf.d/30-output.conf << 'ELKEOF'
# Logstash output configuration
output {
	elasticsearch {
		hosts => ["http://[::1]:9200"]
		index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
	}
}
ELKEOF

cat > /etc/logstash/jvm.options.d/heap.options << 'ELKEOF'
# JVM heap settings for Logstash
-Xms1g
-Xmx1g
ELKEOF

# STEP: Configuring Kibana
cat >> /etc/kibana/kibana.yml << 'ELKEOF'
# Kibana server configuration
server.port: 5601
server.host: "::"

# Elasticsearch connection
elasticsearch.hosts: ["http://[::1]:9200"]
ELKEOF

# STEP: Initializing Keystores
/usr/share/kibana/bin/kibana-keystore create
chown kibana:kibana /etc/kibana/kibana.keystore
chmod 660 /etc/kibana/kibana.keystore

/usr/share/logstash/bin/logstash-keystore create
chown logstash:logstash /etc/logstash/logstash.keystore
chmod 660 /etc/logstash/logstash.keystore

# STEP: Enabling Services
systemctl enable elasticsearch logstash kibana


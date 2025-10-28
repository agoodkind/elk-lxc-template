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
# EMBED_FILE_APPEND: config/elasticsearch.yml -> /etc/elasticsearch/elasticsearch.yml
# EMBED_FILE: config/jvm.options.d/elasticsearch.options -> /etc/elasticsearch/jvm.options.d/heap.options

# STEP: Configuring Logstash
mkdir -p /etc/logstash/conf.d

# EMBED_FILE: config/logstash-pipelines/00-input.conf -> /etc/logstash/conf.d/00-input.conf
# EMBED_FILE: config/logstash-pipelines/30-output.conf -> /etc/logstash/conf.d/30-output.conf
# EMBED_FILE: config/jvm.options.d/logstash.options -> /etc/logstash/jvm.options.d/heap.options

# STEP: Configuring Kibana
# EMBED_FILE_APPEND: config/kibana.yml -> /etc/kibana/kibana.yml

# STEP: Initializing Keystores
/usr/share/kibana/bin/kibana-keystore create
chown kibana:kibana /etc/kibana/kibana.keystore
chmod 660 /etc/kibana/kibana.keystore

/usr/share/logstash/bin/logstash-keystore create
chown logstash:logstash /etc/logstash/logstash.keystore
chmod 660 /etc/logstash/logstash.keystore

# STEP: Enabling Services
systemctl enable elasticsearch logstash kibana


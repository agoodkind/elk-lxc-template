#!/bin/bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0

set -e

# Script to rotate API keys for Kibana and Logstash
# Run this script when you need to rotate credentials

if [[ $EUID -ne 0 ]]; then
    echo "Run as root"
    exit 1
fi

# Load Logstash keystore password from environment file
if [ -f /etc/default/logstash ]; then
    source /etc/default/logstash
    export LOGSTASH_KEYSTORE_PASS
fi

# Detect SSL configuration
if grep -q "xpack.security.http.ssl.enabled: true" /etc/elasticsearch/elasticsearch.yml; then
    ES_URL="https://localhost:9200"
    CURL_OPTS="-k"
else
    ES_URL="http://localhost:9200"
    CURL_OPTS=""
fi

# Prompt for elastic password
read -sp "Enter elastic user password: " ELASTIC_PASSWORD
echo ""

# Revoke old Logstash API key
echo "Revoking old Logstash API key..."
OLD_KEY_ID=$(curl $CURL_OPTS -s -X GET "$ES_URL/_security/api_key" -u "elastic:$ELASTIC_PASSWORD" -H "Content-Type: application/json" | grep -o '"id":"[^"]*","name":"logstash_writer"' | cut -d'"' -f4 | head -1)
if [ -n "$OLD_KEY_ID" ]; then
    curl $CURL_OPTS -s -X DELETE "$ES_URL/_security/api_key" -u "elastic:$ELASTIC_PASSWORD" -H "Content-Type: application/json" -d "{\"ids\":[\"$OLD_KEY_ID\"]}" > /dev/null
    echo "Old key revoked"
fi

# Create new Logstash API key
echo "Creating new Logstash API key..."
LOGSTASH_KEY_RESPONSE=$(curl $CURL_OPTS -s -X POST "$ES_URL/_security/api_key" -u "elastic:$ELASTIC_PASSWORD" -H "Content-Type: application/json" -d '{"name":"logstash_writer","role_descriptors":{"logstash_writer":{"cluster":["monitor","manage_index_templates","manage_ilm"],"indices":[{"names":["logs-*","logstash-*","ecs-*"],"privileges":["write","create","create_index","manage","manage_ilm"]}]}}}')
LOGSTASH_API_KEY=$(echo "$LOGSTASH_KEY_RESPONSE" | grep -o '"encoded":"[^"]*' | cut -d'"' -f4)

if [ -z "$LOGSTASH_API_KEY" ]; then
    echo "Failed to create API key"
    exit 1
fi

# Update Logstash keystore with new API key
echo "Updating Logstash keystore..."
echo "$LOGSTASH_API_KEY" | /usr/share/logstash/bin/logstash-keystore add ELASTICSEARCH_API_KEY --stdin --force
chown logstash:root /etc/logstash/logstash.keystore
chmod 0600 /etc/logstash/logstash.keystore

# Clear sensitive variables from memory
unset ELASTIC_PASSWORD LOGSTASH_API_KEY LOGSTASH_KEY_RESPONSE OLD_KEY_ID

# Restart Logstash
echo "Restarting Logstash..."
systemctl restart logstash

echo ""
echo "API key rotation complete"
echo "New Logstash API key generated and stored in keystore"


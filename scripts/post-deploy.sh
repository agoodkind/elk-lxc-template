#!/bin/bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0

set -e

# Reconfigure SSH server for new host keys
dpkg-reconfigure -f noninteractive openssh-server

# Prompt for SSL configuration
echo ""
echo "=== ELK Stack Security Configuration ==="
echo ""
read -p "Enable SSL for Elasticsearch backend? (y/N): " -n 1 -r ENABLE_BACKEND_SSL
echo ""
read -p "Enable SSL for Kibana frontend? (y/N): " -n 1 -r ENABLE_FRONTEND_SSL
echo ""

# Configure Elasticsearch
ES_CONFIG="/etc/elasticsearch/elasticsearch.yml"
KIBANA_CONFIG="/etc/kibana/kibana.yml"

# Always enable xpack security for password protection
sed -i 's/xpack.security.enabled: false/xpack.security.enabled: true/' "$ES_CONFIG"

# Configure backend SSL
if [[ $ENABLE_BACKEND_SSL =~ ^[Yy]$ ]]; then
    echo "Configuring Elasticsearch SSL with auto-generated certificates..."
    sed -i 's/xpack.security.http.ssl.enabled: false/xpack.security.http.ssl.enabled: true/' "$ES_CONFIG"
    sed -i 's/xpack.security.transport.ssl.enabled: false/xpack.security.transport.ssl.enabled: true/' "$ES_CONFIG"
    
    # Add SSL certificate configuration
    cat >> "$ES_CONFIG" << 'EOF'

# Auto-generated SSL certificates
xpack.security.http.ssl.keystore.path: certs/http.p12
xpack.security.transport.ssl.keystore.path: certs/transport.p12
xpack.security.transport.ssl.truststore.path: certs/transport.p12
xpack.security.transport.ssl.verification_mode: certificate
EOF
    
    ES_URL="https://localhost:9200"
else
    echo "Elasticsearch SSL disabled"
    ES_URL="http://localhost:9200"
fi

# Start Elasticsearch
systemctl start elasticsearch
echo "Waiting for Elasticsearch to start..."
sleep 30

# Generate SSL certificates if backend SSL enabled
if [[ $ENABLE_BACKEND_SSL =~ ^[Yy]$ ]]; then
    echo "Generating SSL certificates..."
    /usr/share/elasticsearch/bin/elasticsearch-certutil cert --silent --pem --out /tmp/certs.zip
    unzip -q /tmp/certs.zip -d /tmp/certs
    mkdir -p /etc/elasticsearch/certs
    
    # Convert PEM to PKCS12 for Elasticsearch
    openssl pkcs12 -export -in /tmp/certs/instance/instance.crt -inkey /tmp/certs/instance/instance.key -out /etc/elasticsearch/certs/http.p12 -name "http" -passout pass:
    cp /etc/elasticsearch/certs/http.p12 /etc/elasticsearch/certs/transport.p12
    
    chown -R elasticsearch:elasticsearch /etc/elasticsearch/certs
    chmod 660 /etc/elasticsearch/certs/*.p12
    
    # Restart Elasticsearch with SSL
    systemctl restart elasticsearch
    sleep 30
    
    # Copy certs for Kibana and Logstash
    mkdir -p /etc/kibana/certs /etc/logstash/certs
    cp /tmp/certs/ca/ca.crt /etc/kibana/certs/
    cp /tmp/certs/ca/ca.crt /etc/logstash/certs/
    
    if [[ $ENABLE_FRONTEND_SSL =~ ^[Yy]$ ]]; then
        cp /tmp/certs/instance/instance.crt /etc/kibana/certs/
        cp /tmp/certs/instance/instance.key /etc/kibana/certs/
        chmod 640 /etc/kibana/certs/*
    else
        chmod 640 /etc/kibana/certs/ca.crt
    fi
    
    chown -R kibana:kibana /etc/kibana/certs
    chown -R logstash:logstash /etc/logstash/certs
    chmod 640 /etc/logstash/certs/ca.crt
    
    rm -rf /tmp/certs /tmp/certs.zip
fi

# Set elastic user password and store in keystore
ELASTIC_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
echo "Setting elastic user password..."
if [[ $ENABLE_BACKEND_SSL =~ ^[Yy]$ ]]; then
    curl -k -X POST "$ES_URL/_security/user/elastic/_password" -u "elastic:changeme" -H "Content-Type: application/json" -d "{\"password\":\"$ELASTIC_PASSWORD\"}" 2>/dev/null || \
    /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s -i <<< "$ELASTIC_PASSWORD" > /dev/null
else
    curl -X POST "$ES_URL/_security/user/elastic/_password" -u "elastic:changeme" -H "Content-Type: application/json" -d "{\"password\":\"$ELASTIC_PASSWORD\"}" 2>/dev/null || \
    /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s -i <<< "$ELASTIC_PASSWORD" > /dev/null
fi

# Create Kibana system user for service account
echo "Creating Kibana system user..."
if [[ $ENABLE_BACKEND_SSL =~ ^[Yy]$ ]]; then
    KIBANA_TOKEN=$(curl -k -X POST "$ES_URL/_security/service/elastic/kibana/credential/token/kibana_token" -u "elastic:$ELASTIC_PASSWORD" -H "Content-Type: application/json" 2>/dev/null | grep -o '"value":"[^"]*' | cut -d'"' -f4)
else
    KIBANA_TOKEN=$(curl -X POST "$ES_URL/_security/service/elastic/kibana/credential/token/kibana_token" -u "elastic:$ELASTIC_PASSWORD" -H "Content-Type: application/json" 2>/dev/null | grep -o '"value":"[^"]*' | cut -d'"' -f4)
fi

# If service token creation fails, create API key for Kibana
if [ -z "$KIBANA_TOKEN" ]; then
    echo "Creating Kibana API key..."
    if [[ $ENABLE_BACKEND_SSL =~ ^[Yy]$ ]]; then
        KIBANA_KEY_RESPONSE=$(curl -k -X POST "$ES_URL/_security/api_key" -u "elastic:$ELASTIC_PASSWORD" -H "Content-Type: application/json" -d '{"name":"kibana_api_key","role_descriptors":{"kibana_system":{"cluster":["monitor","manage_index_templates","manage_ingest_pipelines","manage_ilm"],"indices":[{"names":["*"],"privileges":["all"]}]}}}' 2>/dev/null)
        KIBANA_API_KEY=$(echo "$KIBANA_KEY_RESPONSE" | grep -o '"encoded":"[^"]*' | cut -d'"' -f4)
    else
        KIBANA_KEY_RESPONSE=$(curl -X POST "$ES_URL/_security/api_key" -u "elastic:$ELASTIC_PASSWORD" -H "Content-Type: application/json" -d '{"name":"kibana_api_key","role_descriptors":{"kibana_system":{"cluster":["monitor","manage_index_templates","manage_ingest_pipelines","manage_ilm"],"indices":[{"names":["*"],"privileges":["all"]}]}}}' 2>/dev/null)
        KIBANA_API_KEY=$(echo "$KIBANA_KEY_RESPONSE" | grep -o '"encoded":"[^"]*' | cut -d'"' -f4)
    fi
fi

# Create Logstash writer API key
echo "Creating Logstash API key..."
if [[ $ENABLE_BACKEND_SSL =~ ^[Yy]$ ]]; then
    LOGSTASH_KEY_RESPONSE=$(curl -k -X POST "$ES_URL/_security/api_key" -u "elastic:$ELASTIC_PASSWORD" -H "Content-Type: application/json" -d '{"name":"logstash_writer","role_descriptors":{"logstash_writer":{"cluster":["monitor","manage_index_templates","manage_ilm"],"indices":[{"names":["logs-*","logstash-*","ecs-*"],"privileges":["write","create","create_index","manage","manage_ilm"]}]}}}' 2>/dev/null)
    LOGSTASH_API_KEY=$(echo "$LOGSTASH_KEY_RESPONSE" | grep -o '"encoded":"[^"]*' | cut -d'"' -f4)
else
    LOGSTASH_KEY_RESPONSE=$(curl -X POST "$ES_URL/_security/api_key" -u "elastic:$ELASTIC_PASSWORD" -H "Content-Type: application/json" -d '{"name":"logstash_writer","role_descriptors":{"logstash_writer":{"cluster":["monitor","manage_index_templates","manage_ilm"],"indices":[{"names":["logs-*","logstash-*","ecs-*"],"privileges":["write","create","create_index","manage","manage_ilm"]}]}}}' 2>/dev/null)
    LOGSTASH_API_KEY=$(echo "$LOGSTASH_KEY_RESPONSE" | grep -o '"encoded":"[^"]*' | cut -d'"' -f4)
fi

# Configure Kibana connection to Elasticsearch using keystore
sed -i "s|elasticsearch.hosts:.*|elasticsearch.hosts: [\"$ES_URL\"]|" "$KIBANA_CONFIG"

# Use service token or API key for Kibana
if [ -n "$KIBANA_TOKEN" ]; then
    echo "Configuring Kibana with service token..."
    echo "$KIBANA_TOKEN" | /usr/share/kibana/bin/kibana-keystore add elasticsearch.serviceAccountToken --stdin --force
else
    echo "Configuring Kibana with API key..."
    echo "$KIBANA_API_KEY" | /usr/share/kibana/bin/kibana-keystore add elasticsearch.apiKey --stdin --force
fi

chown kibana:kibana /etc/kibana/kibana.keystore

# Configure Logstash to use API key from keystore
echo "Configuring Logstash with API key..."
echo "$LOGSTASH_API_KEY" | /usr/share/logstash/bin/logstash-keystore add ELASTICSEARCH_API_KEY --stdin --force
chown logstash:logstash /etc/logstash/logstash.keystore

LOGSTASH_OUTPUT="/etc/logstash/conf.d/30-output.conf"

# Update Logstash output to use API key from keystore
cat > "$LOGSTASH_OUTPUT" << EOF
# Logstash output configuration
output {
	elasticsearch {
		hosts => ["$ES_URL"]
		api_key => "\${ELASTICSEARCH_API_KEY}"
		index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
EOF

# Add SSL CA if backend SSL enabled
if [[ $ENABLE_BACKEND_SSL =~ ^[Yy]$ ]]; then
    cat >> "$LOGSTASH_OUTPUT" << 'EOF'
		ssl => true
		cacert => "/etc/logstash/certs/ca.crt"
EOF
fi

cat >> "$LOGSTASH_OUTPUT" << 'EOF'
	}
}
EOF

# Clear API key variables from memory
unset KIBANA_TOKEN KIBANA_API_KEY LOGSTASH_API_KEY KIBANA_KEY_RESPONSE LOGSTASH_KEY_RESPONSE

# Configure frontend SSL if enabled
if [[ $ENABLE_FRONTEND_SSL =~ ^[Yy]$ ]]; then
    echo "Configuring Kibana SSL..."
    echo "server.ssl.enabled: true" >> "$KIBANA_CONFIG"
    echo "server.ssl.certificate: /etc/kibana/certs/instance.crt" >> "$KIBANA_CONFIG"
    echo "server.ssl.key: /etc/kibana/certs/instance.key" >> "$KIBANA_CONFIG"
    
    if [[ $ENABLE_BACKEND_SSL =~ ^[Yy]$ ]]; then
        echo "elasticsearch.ssl.certificateAuthorities: [\"/etc/kibana/certs/ca.crt\"]" >> "$KIBANA_CONFIG"
    fi
    
    KIBANA_PROTOCOL="https"
else
    KIBANA_PROTOCOL="http"
fi

# Start Logstash and Kibana
systemctl start logstash kibana

# Wait for Kibana to start
sleep 15

# Display connection information
IP_ADDR=$(hostname -I | awk '{print $1}')
echo ""
echo "============================================"
echo "ELK Stack Deployment Complete"
echo "============================================"
echo ""
echo "Connection Info:"
echo "  Elasticsearch: $ES_URL"
echo "  Kibana: ${KIBANA_PROTOCOL}://${IP_ADDR}:5601"
echo ""
echo "Admin Credentials:"
echo "  Username: elastic"
echo "  Password: $ELASTIC_PASSWORD"
echo ""
echo "Security Configuration:"
echo "  Backend SSL: $(if [[ $ENABLE_BACKEND_SSL =~ ^[Yy]$ ]]; then echo "Enabled"; else echo "Disabled"; fi)"
echo "  Frontend SSL: $(if [[ $ENABLE_FRONTEND_SSL =~ ^[Yy]$ ]]; then echo "Enabled"; else echo "Disabled"; fi)"
echo "  Kibana keystore: /etc/kibana/kibana.keystore"
echo "  Logstash keystore: /etc/logstash/logstash.keystore"
echo ""
echo "IMPORTANT: Save this password now"
echo "It will not be displayed again or stored on disk"
echo ""
echo "Management:"
echo "  Rotate API keys: /root/rotate-api-keys.sh"
echo "  Reset elastic password: /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic"
echo "============================================"
echo ""

# Clear sensitive variables from memory
unset ELASTIC_PASSWORD

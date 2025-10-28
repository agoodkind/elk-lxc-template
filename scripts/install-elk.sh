
#!/bin/bash
set -e

# Update system and install dependencies
apt update && apt upgrade -y
apt install -y curl wget gnupg apt-transport-https ca-certificates openjdk-11-jre-headless vim net-tools htop

# Add Elastic GPG key and repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list

# Install ELK stack
apt update && apt install -y elasticsearch logstash kibana

# Configure Elasticsearch
cat /tmp/elk-config/elasticsearch.yml >> /etc/elasticsearch/elasticsearch.yml
cp /tmp/elk-config/elasticsearch.options /etc/elasticsearch/jvm.options.d/heap.options

# Configure Logstash
mkdir -p /etc/logstash/conf.d
cp /tmp/elk-config/*.conf /etc/logstash/conf.d/
cp /tmp/elk-config/logstash.options /etc/logstash/jvm.options.d/heap.options

# Configure Kibana
cat /tmp/elk-config/kibana.yml >> /etc/kibana/kibana.yml

# Enable services and clean up
systemctl enable elasticsearch logstash kibana
rm -rf /tmp/elk-config

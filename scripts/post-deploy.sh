
#!/bin/bash

# Reconfigure SSH server for new host keys
dpkg-reconfigure -f noninteractive openssh-server

# Start Elasticsearch, then Logstash and Kibana
systemctl start elasticsearch
sleep 10
systemctl start logstash kibana

# Output Kibana URL
echo "Kibana: http://$(hostname -I | awk '{print $1}'):5601"

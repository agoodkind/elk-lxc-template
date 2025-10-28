#!/bin/bash
dpkg-reconfigure -f noninteractive openssh-server
systemctl start elasticsearch && sleep 10 && systemctl start logstash kibana
echo "Kibana: http://$(hostname -I | awk '{print $1}'):5601"

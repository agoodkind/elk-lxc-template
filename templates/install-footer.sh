msg_info "Starting Elasticsearch"
$STD systemctl start elasticsearch
msg_ok "Started Elasticsearch"

msg_info "Waiting for Elasticsearch to initialize"
sleep 10
msg_ok "Elasticsearch Ready"

msg_info "Starting Logstash and Kibana"
$STD systemctl start logstash kibana
msg_ok "Started Logstash and Kibana"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

msg_ok "${APP} setup has been successfully initialized!"
msg_info "Services are running without security (no authentication)"
msg_info "To configure security (SSL, passwords, API keys):"
msg_info "  /root/elk-configure-security.sh"
msg_info "Access Kibana using the following URL:"
msg_info "  http://${IP}:5601"
msg_info "After security configuration, use the displayed credentials"


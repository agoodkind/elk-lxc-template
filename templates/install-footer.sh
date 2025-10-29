motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

msg_ok "${APP} setup has been successfully initialized!"
msg_info "Credentials saved to: /root/elk-credentials.txt"
msg_info "Access Kibana (HTTPS with authentication):"
msg_info "  https://${IP}:5601"
msg_info "View credentials:"
msg_info "  cat /root/elk-credentials.txt"
msg_info "Manage API keys:"
msg_info "  /root/elk-rotate-api-keys.sh"


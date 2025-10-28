msg_info "Starting ELK Services (without security)"
systemctl start elasticsearch
sleep 10
systemctl start logstash kibana
msg_ok "Started ELK Services"

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Services are running without security (no authentication)${CL}"
echo -e "${INFO}${YW} To configure security (SSL, passwords, API keys):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/root/elk-configure-security.sh${CL}"
echo -e "${INFO}${YW} Access Kibana using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5601${CL}"
echo -e "${INFO}${YW} After security configuration, use the displayed credentials${CL}"


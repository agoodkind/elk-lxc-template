#!/usr/bin/env bash
{{BUILD_FUNC_SOURCE}}
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0
# Source: https://www.elastic.co/elk-stack

APP="ELK-Stack"
var_tags="${var_tags:-logging;elasticsearch;kibana;logstash;elk}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-32}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /usr/share/elasticsearch ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP}"
  # Load Logstash keystore password for service operations
  if [ -f /etc/default/logstash ]; then
    source /etc/default/logstash
    export LOGSTASH_KEYSTORE_PASS
  fi
  $STD apt-get update
  $STD apt-get -y upgrade elasticsearch logstash kibana
  $STD systemctl restart elasticsearch logstash kibana
  msg_ok "Updated Successfully"
  exit
}

start
build_container
description

# Execute install script
{{INSTALL_SCRIPT_OVERRIDE}}

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e ""

# Get IP if not already set by description() function
if [ -z "${IP:-}" ]; then
  IP=$(pct exec "$CTID" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
fi

echo -e "${INFO}${YW} Credentials: ${GATEWAY}${BGN}pct exec $CTID -- cat /root/elk-credentials.txt${CL}"
echo -e "${INFO}${YW} Kibana:      ${GATEWAY}${BGN}http://${IP}:5601${CL}"
echo -e "${INFO}${YW} Logs:        ${GATEWAY}${BGN}pct exec $CTID -- cat /tmp/elk-install.log${CL}"
echo
echo -e "${INFO}${YW} Instructions to turn on HTTPS:${CL}"
echo "1. Put your own certificate and key in /etc/kibana/certs/ca.crt and /etc/kibana/certs/ca.key"
echo "2. Edit /etc/kibana/kibana.yml" and add the following:
echo
echo "  server.ssl.enabled: true"
echo "  server.ssl.certificate: /etc/kibana/certs/ca.crt"
echo "  server.ssl.key: /etc/kibana/certs/ca.key"
echo "  server.port: 443 # (optional, default is 5601)"
echo
echo "3. Restart Kibana: pct exec $CTID -- systemctl restart kibana"
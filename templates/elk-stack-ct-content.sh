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
var_disk="${var_disk:-100}"
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

tab () {
  local tabs="$1"
  local result=""
  for ((i=0; i<tabs; i++)); do
    result="${result}${TAB}"
  done
  echo "$result"
}

echo -e "${INFO}${YW} Credentials: ${GATEWAY}${BGN}pct exec $CTID -- cat /root/elk-credentials.txt${CL}"
echo -e "${INFO}${YW} Kibana:      ${GATEWAY}${BGN}http://${IP}:5601${CL}"
echo
echo -e "${INFO}${YW} A default pipeline and data view have been created for you:${CL}"
echo
echo "$(tab 3)HTTP Endpoint: http://${IP}:8080"
echo "$(tab 3)You can send logs via HTTP POST with JSON body"
echo "$(tab 3)Example:"
echo "$(tab 4)curl -X POST http://${IP}:8080 \\"
echo "$(tab 4)-H \"Content-Type: application/json\" \\"
echo "$(tab 4)-d '{\"message\":\"test\",\"level\":\"info\"}'"
echo "$(tab 3)Data Stream: logs-generic-default"
echo "$(tab 3)View logs in Kibana > Discover > \"Generic Logs\" data view"
echo
# Users can add custom pipelines to /etc/logstash/conf.d/ after installation
echo -e "${INFO}${YW} Put your custom pipelines in:${CL}"
echo
echo "$(tab 3)/etc/logstash/conf.d/"
echo
echo -e "${INFO}${YW} HTTPS has been autoconfigured for the backend:${CL}"
echo -e "${INFO}${YW} You can turn on HTTPS for the frontend by following the instructions below:${CL}"
echo
echo "$(tab 3)1. Put your own certificate and key in /etc/kibana/certs/ca.crt and /etc/kibana/certs/ca.key"
echo "$(tab 3)2. Edit /etc/kibana/kibana.yml" and add the following:
echo
echo "$(tab 4)server.ssl.enabled: true"
echo "$(tab 4)server.ssl.certificate: /etc/kibana/certs/ca.crt"
echo "$(tab 4)server.ssl.key: /etc/kibana/certs/ca.key"
echo "$(tab 4)server.port: 443 # (optional, default is 5601)"
echo
echo "$(tab 3)3. Restart Kibana: pct exec $CTID -- systemctl restart kibana"
echo
echo -e "${INFO}${YW} Management Commands:${CL}"
echo
echo "$(tab 3)Reset password: pct exec $CTID -- /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic"
echo "$(tab 3)Restart services: pct exec $CTID -- systemctl restart elasticsearch logstash kibana"
echo
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
echo -e "${INFO}${YW} View Credentials:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct exec $CTID -- cat /root/elk-credentials.txt${CL}"
echo -e ""
echo -e "${INFO}${YW} Access Kibana (HTTP):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://\${IP}:5601${CL}"
echo -e "${TAB}${YW}Note: Backend connection to Elasticsearch is secured via HTTPS${CL}"
echo -e ""
echo -e "${INFO}${YW} Enable Kibana Frontend HTTPS:${CL}"
echo -e "${TAB}${YW}1. Extract certificates from Elasticsearch's http.p12:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct exec $CTID -- bash -c 'PASS=\$(/usr/share/elasticsearch/bin/elasticsearch-keystore show xpack.security.http.ssl.keystore.secure_password) && \\${CL}"
echo -e "${TAB}${GATEWAY}${BGN}echo \"\$PASS\" | openssl pkcs12 -in /etc/elasticsearch/certs/http.p12 -clcerts -nokeys -passin stdin | openssl x509 -out /etc/kibana/cert.pem && \\${CL}"
echo -e "${TAB}${GATEWAY}${BGN}echo \"\$PASS\" | openssl pkcs12 -in /etc/elasticsearch/certs/http.p12 -nocerts -nodes -passin stdin | openssl rsa -out /etc/kibana/privkey.pem && \\${CL}"
echo -e "${TAB}${GATEWAY}${BGN}chown kibana:kibana /etc/kibana/*.pem && chmod 640 /etc/kibana/*.pem'${CL}"
echo -e "${TAB}${YW}2. Add to /etc/kibana/kibana.yml:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}server.ssl.enabled: true${CL}"
echo -e "${TAB}${GATEWAY}${BGN}server.ssl.certificate: /etc/kibana/cert.pem${CL}"
echo -e "${TAB}${GATEWAY}${BGN}server.ssl.key: /etc/kibana/privkey.pem${CL}"
echo -e "${TAB}${YW}3. Restart Kibana:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct exec $CTID -- systemctl restart kibana${CL}"
echo -e ""
echo -e "${INFO}${YW} Installation Log:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct exec $CTID -- cat /tmp/elk-install.log${CL}"
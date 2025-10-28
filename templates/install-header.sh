#!/usr/bin/env bash

# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP="elk-stack"
var_tags="${var_tags:-logging;elasticsearch;kibana;logstash;elk}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-32}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

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


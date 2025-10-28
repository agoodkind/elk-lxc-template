#!/bin/bash
systemctl stop elasticsearch logstash kibana 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null
rm -rf /tmp/* /var/tmp/* && apt clean && history -c && cat /dev/null > ~/.bash_history
truncate -s 0 /etc/machine-id && rm -f /var/lib/dbus/machine-id && ln -s /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_* /tmp/*.sh

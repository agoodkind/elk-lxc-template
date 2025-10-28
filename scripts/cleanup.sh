#!/bin/bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0

# Stop ELK services if running
systemctl stop elasticsearch logstash kibana 2>/dev/null || true

# Truncate all log files
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null

# Clean temp files, apt cache, and shell history
rm -rf /tmp/* /var/tmp/*
apt-get clean
history -c
cat /dev/null > ~/.bash_history

# Reset machine-id for cloning
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# Remove SSH host keys and leftover scripts
rm -f /etc/ssh/ssh_host_*
rm -f /tmp/*.sh

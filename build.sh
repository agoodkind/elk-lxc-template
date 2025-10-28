#!/bin/bash
set -e
TEMPLATE_ID=900; TEMPLATE_NAME="elk-template"; BASE_IMAGE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"; CORES=4; MEMORY=8192; SWAP=4096; DISK_SIZE=32; STORAGE="local-lvm"; TEMPLATE_STORAGE="local"
[[ $EUID -ne 0 ]] && { echo "Run as root"; exit 1; }
pct status $TEMPLATE_ID &>/dev/null && { read -p "Destroy $TEMPLATE_ID? (y/N): " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]] && { pct stop $TEMPLATE_ID 2>/dev/null || true; pct destroy $TEMPLATE_ID; } || exit 1; }
pveam update && { pveam list $TEMPLATE_STORAGE | grep -q "$BASE_IMAGE" || pveam download $TEMPLATE_STORAGE $BASE_IMAGE; }
sysctl -w vm.max_map_count=262144; grep -q "vm.max_map_count" /etc/sysctl.conf || echo "vm.max_map_count=262144" >> /etc/sysctl.conf
pct create $TEMPLATE_ID ${TEMPLATE_STORAGE}:vztmpl/${BASE_IMAGE} --arch amd64 --cores $CORES --hostname $TEMPLATE_NAME --memory $MEMORY --swap $SWAP --net0 name=eth0,bridge=vmbr0,ip=dhcp,type=veth --onboot 0 --ostype ubuntu --rootfs ${STORAGE}:${DISK_SIZE} --features nesting=1
pct start $TEMPLATE_ID && sleep 5
for f in scripts/*.sh; do pct push $TEMPLATE_ID "$f" "/tmp/$(basename $f)" --perms 755; done
pct push $TEMPLATE_ID scripts/post-deploy.sh /root/post-deploy.sh --perms 755
pct exec $TEMPLATE_ID -- mkdir -p /tmp/elk-config
for f in config/*.yml config/logstash-pipelines/*.conf config/jvm.options.d/*.options; do pct push $TEMPLATE_ID "$f" "/tmp/elk-config/$(basename $f)"; done
pct exec $TEMPLATE_ID -- /tmp/install-elk.sh && pct exec $TEMPLATE_ID -- /tmp/cleanup.sh
pct stop $TEMPLATE_ID
vzdump $TEMPLATE_ID --compress zstd --dumpdir /var/lib/vz/template/cache --mode stop
cd /var/lib/vz/template/cache && mv "$(ls -t vzdump-lxc-${TEMPLATE_ID}-*.tar.zst | head -1)" elk-stack-ubuntu-22.04.tar.zst
echo "Template ready: /var/lib/vz/template/cache/elk-stack-ubuntu-22.04.tar.zst"

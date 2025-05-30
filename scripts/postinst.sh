#!/usr/bin/env bash
set -e
function info { echo -e "\e[32m[info] $*\e[39m"; }
function warn  { echo -e "\e[33m[warn] $*\e[39m"; }
function error { echo -e "\e[31m[error] $*\e[39m"; exit 1; }
# . /usr/share/debconf/confmodule
ARCH=$(uname -m)

BINARY_DOCKER=/usr/bin/docker

DOCKER_REPO="ghcr.io/home-assistant"

SERVICE_DOCKER="docker.service"
SERVICE_NM="NetworkManager.service"

# systemctl enable --now podman.socket

# Read infos from web
URL_CHECK_ONLINE="https://checkonline.home-assistant.io/online.txt"
URL_VERSION="https://version.home-assistant.io/stable.json"
HASSIO_VERSION=$(curl -s ${URL_VERSION} | jq -e -r '.supervisor')
URL_APPARMOR_PROFILE="https://version.home-assistant.io/apparmor_stable.txt"

# reload systemd
info "Reload systemd"
systemctl daemon-reload

# Restart NetworkManager
# info "Restarting NetworkManager"
# systemctl restart "${SERVICE_NM}"

# Set permissions of /etc/systemd/resolved.conf
# check if file has correct permissions
if [ "$(stat -c %a /etc/systemd/resolved.conf)" != "644" ]; then
    info "Setting permissions of /etc/systemd/resolved.conf"
    chmod 644 /etc/systemd/resolved.conf
fi

# Enable and restart systemd-resolved
info "Enable systemd-resolved"
systemctl enable systemd-resolved.service
info "Restarting systemd-resolved"
systemctl restart systemd-resolved.service

# Check and fix systemd-journal-gatewayd socket location
if [ ! -S "/run/systemd-journal-gatewayd.sock" ]; then
    info "Set up systemd-journal-gatewayd socket file"
    if [ "$(systemctl is-active systemd-journal-gatewayd.socket)" = 'active' ]; then
        systemctl stop systemd-journal-gatewayd.socket
    fi
    rm -rf "/run/systemd-journal-gatewayd.sock";
fi
# Enable and start systemd-journal-gatewayd
if [ "$(systemctl is-active systemd-journal-gatewayd.socket)" = 'inactive' ]; then
    info "Enable systemd-journal-gatewayd"
    systemctl enable systemd-journal-gatewayd.socket
    systemctl start systemd-journal-gatewayd.socket
fi
# Start nfs-utils.service for nfs mounts
if [ "$(systemctl is-active nfs-utils.service)" = 'inactive' ]; then
    info "Start nfs-utils.service"
    systemctl start nfs-utils.service
fi

# Restart Docker service
info "Restarting docker service"
systemctl restart "${SERVICE_DOCKER}"

# Check network connection
while ! curl -q ${URL_CHECK_ONLINE} >/dev/null 2>&1 ; do
    info "Waiting for ${URL_CHECK_ONLINE} - network interface might be down..."
    sleep 2
done

# Get primary network interface
PRIMARY_INTERFACE=$(ip route | awk '/^default/ { print $5; exit }')
IP_ADDRESS=$(ip -4 addr show dev "${PRIMARY_INTERFACE}" | awk '/inet / { sub("/.*", "", $2); print $2 }')

case ${ARCH} in
    "i386" | "i686")
        MACHINE=${MACHINE:=qemux86}
        HASSIO_DOCKER="${DOCKER_REPO}/i386-hassio-supervisor"
    ;;
    "x86_64")
        MACHINE=${MACHINE:=qemux86-64}
        info "I am here!"
        HASSIO_DOCKER="${DOCKER_REPO}/amd64-hassio-supervisor"
    ;;
    "arm" |"armv6l")
        if [ -z "${MACHINE}" ]; then
             db_input critical ha/machine-type || true
             db_go || true
             db_get ha/machine-type || true
             MACHINE="${RET}"
             db_stop
        fi
        HASSIO_DOCKER="${DOCKER_REPO}/armhf-hassio-supervisor"
    ;;
    "armv7l")
        if [ -z "${MACHINE}" ]; then
             db_input critical ha/machine-type || true
             db_go || true
             db_get ha/machine-type || true
             MACHINE="${RET}"
             db_stop
        fi
        HASSIO_DOCKER="${DOCKER_REPO}/armv7-hassio-supervisor"
    ;;
    "aarch64")
        if [ -z "${MACHINE}" ]; then
             db_input critical ha/machine-type || true
             db_go || true
             db_get ha/machine-type || true
             MACHINE="${RET}"
             db_stop

        fi
        HASSIO_DOCKER="${DOCKER_REPO}/aarch64-hassio-supervisor"
    ;;
    *)
        error "${ARCH} unknown!"
    ;;
esac

info Detected architecture: $ARCH

PREFIX=${PREFIX:-/usr}
SYSCONFDIR=${SYSCONFDIR:-/etc}
DEFAULT_DATA_SHARE=/var/lib/homeassistant
DATA_SHARE=${DATA_SHARE:-$DEFAULT_DATA_SHARE}
CONFIG="${SYSCONFDIR}/hassio.json"

mkdir -p ${DEFAULT_DATA_SHARE}

if [ -f "${CONFIG}" ]; then
    # Using data share of existing configuration
    DATA_SHARE=$(jq -r --arg default "$DEFAULT_DATA_SHARE" '.data // $default' "$CONFIG")
fi

cat > "${CONFIG}" <<- EOF
{
    "supervisor": "${HASSIO_DOCKER}",
    "machine": "${MACHINE}",
    "data": "${DATA_SHARE}"
}
EOF


# Install Supervisor
# info "Install supervisor startup scripts"
sed -i "s,%%HASSIO_CONFIG%%,${CONFIG},g" "${PREFIX}"/sbin/hassio-supervisor
sed -i -e "s,%%BINARY_DOCKER%%,${BINARY_DOCKER},g" \
       -e "s,%%SERVICE_DOCKER%%,${SERVICE_DOCKER},g" \
       -e "s,%%BINARY_HASSIO%%,${PREFIX}/sbin/hassio-supervisor,g" \
       "${SYSCONFDIR}/systemd/system/hassio-supervisor.service"
cat > /etc/sysconfig/hassio-supervisor <<EOF
SUPERVISOR_IMAGE=${HASSIO_DOCKER}
SUPERVISOR_DATA=${DATA_SHARE}
SUPERVISOR_MACHINE=${MACHINE}
EOF

systemctl daemon-reload

# chmod a+x "${PREFIX}/sbin/hassio-supervisor"
systemctl enable hassio-supervisor.service > /dev/null 2>&1;

# Start Supervisor
info "Start Home Assistant Supervised"
systemctl start hassio-supervisor.service

# Install HA CLI
# info "Installing the 'ha' cli"
# chmod a+x "${PREFIX}/bin/ha"

# Switch to cgroup v2
# if [ -f /etc/default/grub ]
# then
#     if grep -q "systemd.unified_cgroup_hierarchy=false" /etc/default/grub; then
#         info "Switching to cgroup v2"
#         cp /etc/default/grub /etc/default/grub.bak
#         sed -i 's/systemd\.unified_cgroup_hierarchy=false //' /etc/default/grub
#         update-grub
#         touch /var/run/reboot-required
#     fi
# elif [ -f /boot/firmware/cmdline.txt ]
# then
#     if grep -q "systemd.unified_cgroup_hierarchy=false" /boot/firmware/cmdline.txt; then
#         info "Switching to cgroup v2"
#         sed -i.bak 's/ systemd\.unified_cgroup_hierarchy=false//' /boot/firmware/cmdline.txt
#         touch /var/run/reboot-required
#     fi
# else
#     warn "Could not find /etc/default/grub or /boot/firmware/cmdline.txt failed to switch to cgroup v1"
# fi
info "Within a few minutes you will be able to reach Home Assistant at:"
info "http://homeassistant.local:8123 or using the IP address of your"
info "machine: http://${IP_ADDRESS}:8123"
if [ -f /var/run/reboot-required ]
then
    warn "A reboot is required to apply changes to grub."
fi

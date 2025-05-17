# Home Assistant installation on CentOS

tl;dr - don't do it, supervisor is hopelessly locked to Debian in a weirdest way.

Next time do HA in container and do simple supervisor, or install addons manually.

## General startup order

- On system boot, systemd starts essential host services, including Docker, NetworkManager, and the os-agent.
- The systemd service for the Home Assistant Supervisor (hassio-supervisor.service or similar) is initiated.
- The Supervisor container starts.
- The Supervisor then takes over and begins starting the other core Home Assistant containers (Core, DNS, Audio, CLI) in the correct order and with the appropriate configurations.
- If add-ons are configured to start on boot, the Supervisor will start them as well.
- Home Assistant Core initializes, loads integrations, and becomes available on its web interface (typically port 8123).

## Changes

- use podman

## Progress

### Install *os-agent*

It is a golang binary and systemd unit.

Manual setup:

- download tar file
  - https://github.com/home-assistant/os-agent/releases/tag/1.7.2
- extract tar
- copy binary
- create systemd unit
- enable and start

```bash
# podman
sudo dnf -y install udisks2 systemd-resolved systemd-journal-remote docker-ce
setenforce 0


# agent
curl -o /tmp/os-agent.tar.gz https://github.com/home-assistant/os-agent/releases/download/1.7.2/os-agent_1.7.2_linux_amd64.tar.gz
mkdir os-agent
tar -xf /tmp/os-agent.tar.gz -C ./os-agent/
mv os-agent/os-agent /usr/bin/os-agent

cat > /etc/dbus-1/system.d/io.haoss.conf <<EOF
<!DOCTYPE busconfig PUBLIC
          "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
          "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <!-- Only root can own the Home Assitant OS service -->
  <policy user="root">
    <allow own="io.hass.os"/>
  </policy>
  <policy group="root">
    <allow own="io.hass.os"/>
  </policy>

  <policy context="default">
    <allow send_destination="io.hass.os"/>
    <allow receive_sender="io.hass.os"/>
  </policy>
</busconfig>
EOF

cat > /etc/systemd/system/haos-agent.service <<EOF
[Unit]
Description=Home Assistant OS Agent
DefaultDependencies=no
Requires=dbus.socket udisks2.service
After=dbus.socket sysinit.target

[Service]
BusName=io.hass.os
Type=notify
Restart=always
RestartSec=5s
Environment="DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket"
ExecStart=/usr/bin/os-agent

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart haos-agent
```

### Install *supervisor*

- copy config files and scripts
- execute postinst.sh script

```bash
cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNSSEC=no
DNSOverTLS=no
DNSStubListener=no
EOF

mkdir -p /etc/systemd/system/systemd-journal-gatewayd.socket.d
cat > /etc/systemd/system/systemd-journal-gatewayd.socket.d/10-hassio-supervisor.conf <<EOF
[Socket]
ListenStream=
ListenStream=/run/systemd-journal-gatewayd.sock
EOF

# cat > /etc/containers/systemd/hassio-supervisor.container <<'EOF'
# [Unit]
# Description=Home Assistant Supervisor Container
# After=network-online.target
# Wants=network-online.target

# [Service]
# EnvironmentFile=/etc/sysconfig/hassio-supervisor
# ExecStartPre=mkdir -p /run/supervisor

# [Container]
# ContainerName=hassio_supervisor
# Image=${SUPERVISOR_IMAGE}:latest

# Network=host
# PodmanArgs=--privileged

# # Volume mounts from the docker command
# Volume=/run/podman/podman.sock:/run/docker.sock:rw
# Volume=/run/podman/podman.sock:/run/containerd/containerd.sock:rw
# Volume=/run/systemd-journal-gatewayd.sock:/run/systemd-journal-gatewayd.sock:rw
# Volume=/run/dbus:/run/dbus:ro
# Volume=/run/supervisor:/run/os:rw
# Volume=/run/udev:/run/udev:ro
# Volume=/etc/machine-id:/etc/machine-id:ro
# Volume=${SUPERVISOR_DATA}:/data:rw,rslave

# # Environment variables from the docker command
# Environment=SUPERVISOR_SHARE=${SUPERVISOR_DATA}
# Environment=SUPERVISOR_NAME=hassio_supervisor
# Environment=SUPERVISOR_MACHINE=${SUPERVISOR_MACHINE}
# EOF
```

Lame quick deploy

```bash
scp -r etc scripts/postinst.sh usr 192.168.124.83:~/ && \
    ssh 192.168.124.83 'sudo mv ~/postinst.sh ~root/ && \
        sudo mv ~jveverka/usr/sbin/hassio-supervisor /usr/sbin/ && \
        sudo mv ~jveverka/etc/systemd/system/hassio-supervisor.service /etc/systemd/system/ && \
        sudo chmod 755 /usr/sbin/hassio-supervisor ~root/postinst.sh && \
        ~root/postinst.sh'
```

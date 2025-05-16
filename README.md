# Home Assistant installation on CentOS

## General startup order

- On system boot, systemd starts essential host services, including Docker, NetworkManager, and the os-agent.
- The systemd service for the Home Assistant Supervisor (hassio-supervisor.service or similar) is initiated.
- The Supervisor container starts.
- The Supervisor then takes over and begins starting the other core Home Assistant containers (Core, DNS, Audio, CLI) in the correct order and with the appropriate configurations.
- If add-ons are configured to start on boot, the Supervisor will start them as well.
- Home Assistant Core initializes, loads integrations, and becomes available on its web interface (typically port 8123).


# systemctl - Service Management

Manage systemd services on Photon OS.

## Commands

### Status
- List active: `systemctl list-units --type=service --state=active`
- List all: `systemctl list-units --type=service`
- Service status: `systemctl status <service>`
- Is active: `systemctl is-active <service>`
- Is enabled: `systemctl is-enabled <service>`

### Control
- Start: `systemctl start <service>`
- Stop: `systemctl stop <service>`
- Restart: `systemctl restart <service>`
- Reload config: `systemctl reload <service>`
- Enable at boot: `systemctl enable <service>`
- Disable at boot: `systemctl disable <service>`

### Logs
- Service logs: `journalctl -u <service> --no-pager -n 50`
- Follow logs: `journalctl -u <service> -f`
- Since boot: `journalctl -u <service> -b`

### System
- Default target: `systemctl get-default`
- Set target: `systemctl set-default multi-user.target`
- List timers: `systemctl list-timers`
- Reload daemon: `systemctl daemon-reload`

## Common Photon OS Services
- sshd, docker, iptables, ntpd, systemd-networkd, systemd-resolved

# logs - System Log Analysis

Analyze system logs on Photon OS using journalctl.

## Commands

### View Logs
- Recent: `journalctl --no-pager -n 100`
- Follow: `journalctl -f`
- Since boot: `journalctl -b`
- Previous boot: `journalctl -b -1`
- By priority: `journalctl -p err --no-pager -n 50`

### Filter
- By service: `journalctl -u <service> --no-pager -n 50`
- By time: `journalctl --since "1 hour ago" --no-pager`
- By PID: `journalctl _PID=<pid> --no-pager`
- Kernel only: `journalctl -k --no-pager -n 50`
- JSON output: `journalctl -o json-pretty -n 10`

### Disk Usage
- Journal size: `journalctl --disk-usage`
- Vacuum by size: `journalctl --vacuum-size=100M`
- Vacuum by time: `journalctl --vacuum-time=7d`

### Common Patterns
- Auth failures: `journalctl -u sshd | grep -i "failed\|invalid"`
- OOM kills: `journalctl -k | grep -i "out of memory\|oom"`
- Disk errors: `journalctl -k | grep -i "error\|fault\|fail" | grep -i "sd\|nvme"`

## Notes
- Config: /etc/systemd/journald.conf
- Storage: /var/log/journal/

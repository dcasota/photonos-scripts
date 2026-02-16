# performance - System Performance

Monitor and tune system performance on Photon OS.

## Commands

### CPU
- Load average: `uptime`
- CPU usage: `top -bn1 | head -20`
- Per-CPU: `mpstat -P ALL 1 1` (if sysstat installed)
- Process CPU: `ps aux --sort=-%cpu | head -20`

### Memory
- Overview: `free -h`
- Detailed: `cat /proc/meminfo`
- Process memory: `ps aux --sort=-%mem | head -20`
- Shared memory: `ipcs -m`

### Disk
- Usage: `df -h`
- Inodes: `df -i`
- IO stats: `iostat 1 3` (if sysstat installed)
- Large files: `find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null`
- Directory sizes: `du -sh /* 2>/dev/null | sort -rh | head -20`

### Network
- Connections: `ss -s`
- Bandwidth: `cat /proc/net/dev`
- Open files: `lsof -i -P -n 2>/dev/null | head -30`

### Process
- Tree: `pstree -p`
- Open files: `lsof -p <pid>`
- Process limits: `cat /proc/<pid>/limits`
- Threads: `ps -eLf | wc -l`

## Notes
- Install sysstat for advanced tools: `tdnf install -y sysstat`
- Kernel tuning: /etc/sysctl.conf or /etc/sysctl.d/
- Apply sysctl: `sysctl -p`

# network - Network Configuration

Network management on Photon OS using systemd-networkd.

## Commands

### Status
- Interfaces: `ip link show`
- IP addresses: `ip addr show`
- Routes: `ip route show`
- DNS: `resolvectl status`
- Connections: `ss -tuln`
- Listening ports: `ss -tlnp`

### Configuration
- Network files: `ls /etc/systemd/network/`
- View config: `cat /etc/systemd/network/*.network`
- Restart networking: `systemctl restart systemd-networkd`
- Restart resolver: `systemctl restart systemd-resolved`

### Diagnostics
- Ping: `ping -c 4 <host>`
- Traceroute: `traceroute <host>`
- DNS lookup: `dig <domain>` or `nslookup <domain>`
- Port check: `ss -tlnp | grep <port>`

### Static IP Example
File: /etc/systemd/network/10-static.network
```
[Match]
Name=eth0
[Network]
Address=192.168.1.100/24
Gateway=192.168.1.1
DNS=8.8.8.8
```

## Notes
- Photon OS uses systemd-networkd, not NetworkManager
- Config dir: /etc/systemd/network/
- Hostname: hostnamectl set-hostname <name>

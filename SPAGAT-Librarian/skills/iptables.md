# iptables - Firewall Management

Manage firewall rules on Photon OS.

## Commands

### View
- List all rules: `iptables -L -n -v`
- List with line numbers: `iptables -L -n --line-numbers`
- List NAT rules: `iptables -t nat -L -n -v`
- List specific chain: `iptables -L INPUT -n -v`

### Add Rules
- Allow port: `iptables -A INPUT -p tcp --dport <port> -j ACCEPT`
- Allow from IP: `iptables -A INPUT -s <ip> -j ACCEPT`
- Block IP: `iptables -A INPUT -s <ip> -j DROP`
- Allow established: `iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT`
- Allow loopback: `iptables -A INPUT -i lo -j ACCEPT`

### Remove Rules
- By line number: `iptables -D INPUT <number>`
- Flush all: `iptables -F`

### Persist
- Save: `iptables-save > /etc/systemd/scripts/ip4save`
- Restore: `iptables-restore < /etc/systemd/scripts/ip4save`
- Service: `systemctl restart iptables`

## Notes
- Photon OS stores rules at /etc/systemd/scripts/ip4save
- Default policy: check with `iptables -L | head -3`

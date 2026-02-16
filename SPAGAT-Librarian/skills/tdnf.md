# tdnf - Package Management

Photon OS package manager (Tiny DNF). Use for installing, updating, and querying packages.

## Commands

### Query packages
- List installed: `tdnf list installed`
- Search: `tdnf search <keyword>`
- Package info: `tdnf info <package>`
- Check updates: `tdnf check-update`
- List available: `tdnf list available`
- List repos: `tdnf repolist`

### Install/Remove
- Install: `tdnf install -y <package>`
- Remove: `tdnf erase <package>`
- Update all: `tdnf update -y`
- Update one: `tdnf update -y <package>`
- Reinstall: `tdnf reinstall <package>`

### Troubleshooting
- Clean cache: `tdnf clean all`
- Rebuild cache: `tdnf makecache`
- Check deps: `tdnf deplist <package>`
- History: `tdnf history`

## Notes
- Use `-y` flag to skip confirmation in automated scripts
- Photon OS repos: photon, photon-updates, photon-extras
- Config: /etc/tdnf/tdnf.conf
- Repo configs: /etc/yum.repos.d/

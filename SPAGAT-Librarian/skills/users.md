# users - User Management

User and group management on Photon OS.

## Commands

### Query
- Current user: `whoami`
- User info: `id <username>`
- All users: `cat /etc/passwd`
- All groups: `cat /etc/group`
- Logged in: `who`
- Last logins: `last -n 20`

### Manage Users
- Add user: `useradd -m -s /bin/bash <username>`
- Set password: `passwd <username>`
- Delete user: `userdel -r <username>`
- Modify shell: `usermod -s /bin/bash <username>`
- Add to group: `usermod -aG <group> <username>`
- Lock account: `usermod -L <username>`
- Unlock account: `usermod -U <username>`

### Manage Groups
- Add group: `groupadd <groupname>`
- Delete group: `groupdel <groupname>`
- List group members: `getent group <groupname>`

### SSH Keys
- List keys: `cat ~/.ssh/authorized_keys`
- Generate key: `ssh-keygen -t ed25519`

## Notes
- Root login via SSH: check /etc/ssh/sshd_config PermitRootLogin
- PAM config: /etc/pam.d/

To create a self-hosted copy of https://vmware.github.io/photon, you can use `installer.sh` in this repository.
1. Create a vm with 8gb ram, 2vcpu, 20gb disk, with generalized kernel support, and with STIG hardening if available
2. copy installer.sh to the vm
3. run
   ```
   chmod a+x ./installer.sh
   ./installer.sh /var/www/photon-site
   ```

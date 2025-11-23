issues:
- severity: critical
  category: orphaned_page
  description: Page exists on production but missing on localhost
  location: https://*.github.io/photon/
  fix_suggestion: Ensure content is present in local build
- severity: critical
  category: broken_link
  description: 'Broken link found: https://192.168.225.155/docs-v4/whats-new//'
  location: https://192.168.225.155/blog/2021/02/24/photon-os-4.0-now-available/
  fix_suggestion: Fix or remove the link
- severity: critical
  category: broken_link
  description: 'Broken link found: https://192.168.225.155/docs-v5/administration-guide/security-policy/default-firewall-settings/troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh/'
  location: https://192.168.225.155/docs-v5/administration-guide/security-policy/default-firewall-settings/
  fix_suggestion: Fix or remove the link
- severity: critical
  category: broken_link
  description: 'Broken link found: https://192.168.225.155/docs-v5/user-guide/working-with-kickstart/'
  location: https://192.168.225.155/docs-v5/administration-guide/photon-rpm-ostree/installing-a-host-against-custom-server-repository/
  fix_suggestion: Fix or remove the link
- severity: critical
  category: broken_link
  description: 'Broken link found: https://192.168.225.155/docs-v5/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel/'
  location: https://192.168.225.155/docs-v5/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/
  fix_suggestion: Fix or remove the link
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/whats-new.md:11
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/_index.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/whats-new-photon-os-4-rev2-.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H8'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H15'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel.md:31
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H6'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel.md:40
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H7'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel.md:74
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/investigating-the-guest-kernel.md:18
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/kernel-log-replication-with-vprobes.md:13
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H11'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/vmtoolsd.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H15'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H9 followed by H12'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:109
  fix_suggestion: Adjust heading level to H10
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H11 followed by H14'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:124
  fix_suggestion: Adjust heading level to H12
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H7 followed by H17'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:155
  fix_suggestion: Adjust heading level to H8
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H8 followed by H12'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:178
  fix_suggestion: Adjust heading level to H9
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H6 followed by H12'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:191
  fix_suggestion: Adjust heading level to H7
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H13'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/cloud-init.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H13 followed by H16'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/cloud-init.md:20
  fix_suggestion: Adjust heading level to H14
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H16 followed by H18'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/cloud-init.md:31
  fix_suggestion: Adjust heading level to H17
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H6'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H2 followed by H6'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:25
  fix_suggestion: Adjust heading level to H3
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H5'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:33
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H5'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/package-management.md:30
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H7'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/package-management.md:56
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H4 followed by H7'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/photon-os-general-troubleshooting/package-management.md:123
  fix_suggestion: Adjust heading level to H5
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H12'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H13'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:97
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H9 followed by H14'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:100
  fix_suggestion: Adjust heading level to H10
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H14 followed by H19'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:101
  fix_suggestion: Adjust heading level to H15
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H19 followed by H25'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:102
  fix_suggestion: Adjust heading level to H20
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H14 followed by H16'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:105
  fix_suggestion: Adjust heading level to H15
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H16 followed by H19'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:106
  fix_suggestion: Adjust heading level to H17
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H15 followed by H17'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:109
  fix_suggestion: Adjust heading level to H16
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H17 followed by H20'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:110
  fix_suggestion: Adjust heading level to H18
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H17 followed by H20'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:116
  fix_suggestion: Adjust heading level to H18
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H18 followed by H21'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/introduction/photon-os-logs.md:118
  fix_suggestion: Adjust heading level to H19
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/troubleshooting-tools/common-tools.md:28
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H6'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh.md:20
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/troubleshooting-guide/solutions-to-common-problems/resetting-a-lost-root-password.md:38
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/support-for-selinux.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/configure-wireless-networking.md:11
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-real-time-operating-system.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/_index.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/installing-and-using-lightwave/remotely-upgrade-multiple-photon-os-machines-with-lightwave-client-and-photon-management-daemon-installed.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/installing-and-using-lightwave/remotely-upgrade-a-photon-os-machine-with-lightwave-client-and-photon-management-daemon-installed.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/managing-network-configuration/netmgr.python.md:18
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/managing-network-configuration/setting-up-networking-for-multiple-nics/combining-dhcp-and-static-ip-addresses-with-ipv4-and-ipv6.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/managing-network-configuration/setting-up-networking-for-multiple-nics/_index.md:39
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H3'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/managing-packages-with-tdnf/tdnf-automatic.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/remotes/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/querying-for-metadata/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/concepts-in-action/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/file-oriented-server-operations/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/introduction/_index.md:6
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/install-or-rebase-to-photon-os-4/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/installing-a-host-against-custom-server-repository/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/automatic-updates/_index.md:19
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/running-container-applications-between-bootable-images/_index.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H18'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/running-container-applications-between-bootable-images/_index.md:40
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/host-updating-operations/_index.md:18
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/installing-a-host-against-default-server-repository/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/creating-a-rpm-ostree-server/_index.md:45
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-rpm-ostree/package-oriented-server-operations/_index.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/managing-services-withsystemd/installing-sendmail.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/containers/support_distributed_builds.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H8'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-os-packages/examining-packages-spec-dir.md:36
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H8 followed by H22'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-os-packages/examining-packages-spec-dir.md:37
  fix_suggestion: Adjust heading level to H9
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-os-packages/building-a-package-from-a-source-rpm.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/photon-management-daemon/available-apis.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/cloud-init-on-photon-os/running-a-photon-os-machine-on-gce.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H13'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2.md:64
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H3'
  location: /var/www/photon-site/content/en/docs-v4/administration-guide/cloud-init-on-photon-os/customizing-gos-cloud-init.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/overview/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/command-line-reference/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/command-line-reference/command-line-Interfaces/photon-real-time-cli.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/cloud-images.md:19
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H11'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/cloud-images.md:52
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H10'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/cloud-images.md:76
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H10 followed by H12'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/cloud-images.md:84
  fix_suggestion: Adjust heading level to H11
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H7 followed by H10'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/cloud-images.md:100
  fix_suggestion: Adjust heading level to H8
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H4 followed by H8'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/cloud-images.md:130
  fix_suggestion: Adjust heading level to H5
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/build-package-or-kernel-modules-using-script.md:21
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/_index.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/downloading-photon.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/run-photon-on-gce/prerequisites-for-photon-os-on-gce.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H12'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/run-photon-on-raspberry-pi/enabling-RPi-interfaces-using-devicetree.md:33
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/run-photon-on-raspberry-pi/installing-the-iso-image-for-photon-os-rpi.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/run-photon-on-azure/setting-up-azure-storage-and-uploading-the-vhd.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H11'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/run-photon-on-azure/setting-up-azure-storage-and-uploading-the-vhd.md:107
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H11'
  location: /var/www/photon-site/content/en/docs-v4/installation-guide/run-photon-on-azure/remove-photon-from-azure.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/user-guide/working-with-kickstart.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/user-guide/mounting-remote-file-systems.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/user-guide/_index.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v4/user-guide/kubernetes-on-photon-os/running-kubernetes-on-photon-os/configure-kubernetes-on-node.md:62
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/blog/new-photon-package-repo.md:7
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/blog/releases/photon4-ga.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/_index.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/Overview/whats-new.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H7'
  location: /var/www/photon-site/content/en/docs-v3/Overview/whats-new.md:33
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/Overview/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H8'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H15'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel.md:31
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H6'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel.md:40
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H7'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel.md:74
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/investigating-the-guest-kernel.md:18
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/kernel-log-replication-with-vprobes.md:13
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H11'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/vmtoolsd.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H15'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H9 followed by H12'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:109
  fix_suggestion: Adjust heading level to H10
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H11 followed by H14'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:124
  fix_suggestion: Adjust heading level to H12
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H7 followed by H17'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:155
  fix_suggestion: Adjust heading level to H8
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H8 followed by H12'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:178
  fix_suggestion: Adjust heading level to H9
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H6 followed by H12'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:191
  fix_suggestion: Adjust heading level to H7
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H13'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/cloud-init.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H13 followed by H16'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/cloud-init.md:20
  fix_suggestion: Adjust heading level to H14
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H16 followed by H18'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/cloud-init.md:31
  fix_suggestion: Adjust heading level to H17
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H6'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H4 followed by H6'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:23
  fix_suggestion: Adjust heading level to H5
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H5'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:31
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H4 followed by H6'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:47
  fix_suggestion: Adjust heading level to H5
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H5 followed by H8'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:87
  fix_suggestion: Adjust heading level to H6
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H5'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/package-management.md:31
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H7'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/package-management.md:57
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H4 followed by H7'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/photon-os-general-troubleshooting/package-management.md:124
  fix_suggestion: Adjust heading level to H5
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H12'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H13'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:94
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H9 followed by H14'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:97
  fix_suggestion: Adjust heading level to H10
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H14 followed by H19'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:98
  fix_suggestion: Adjust heading level to H15
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H19 followed by H25'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:99
  fix_suggestion: Adjust heading level to H20
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H14 followed by H16'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:102
  fix_suggestion: Adjust heading level to H15
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H16 followed by H19'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:103
  fix_suggestion: Adjust heading level to H17
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H15 followed by H17'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:106
  fix_suggestion: Adjust heading level to H16
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H17 followed by H20'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:107
  fix_suggestion: Adjust heading level to H18
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H17 followed by H20'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:113
  fix_suggestion: Adjust heading level to H18
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H18 followed by H21'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/introduction/photon-os-logs.md:115
  fix_suggestion: Adjust heading level to H19
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/troubleshooting-tools/common-tools.md:28
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/troubleshooting-guide/solutions-to-common-problems/resetting-a-lost-root-password.md:38
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/configure-wireless-networking.md:11
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/_index.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/managing-network-configuration/netmgr.python.md:18
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/managing-network-configuration/setting-up-networking-for-multiple-nics/combining-dhcp-and-static-ip-addresses-with-ipv4-and-ipv6.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/remotes/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/querying-for-metadata/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/concepts-in-action/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/file-oriented-server-operations/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/introduction/_index.md:6
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/installing-a-host-against-custom-server-repository/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/automatic-updates/_index.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/running-container-applications-between-bootable-images/_index.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H18'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/running-container-applications-between-bootable-images/_index.md:39
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/install-or-rebase-to-photon-os-3/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/host-updating-operations/_index.md:18
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/installing-a-host-against-default-server-repository/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/creating-a-rpm-ostree-server/_index.md:45
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-rpm-ostree/package-oriented-server-operations/_index.md:23
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/managing-services-withsystemd/installing-sendmail.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H8'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-os-packages/examining-packages-spec-dir.md:36
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H8 followed by H22'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-os-packages/examining-packages-spec-dir.md:37
  fix_suggestion: Adjust heading level to H9
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/photon-os-packages/building-a-package-from-a-source-rpm.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/cloud-init-on-photon-os/running-a-photon-os-machine-on-gce.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H13'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2.md:64
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H3'
  location: /var/www/photon-site/content/en/docs-v3/administration-guide/cloud-init-on-photon-os/customizing-gos-cloud-init.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/command-line-reference/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/cloud-images.md:19
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H11'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/cloud-images.md:52
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H10'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/cloud-images.md:76
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H10 followed by H12'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/cloud-images.md:84
  fix_suggestion: Adjust heading level to H11
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H7 followed by H10'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/cloud-images.md:100
  fix_suggestion: Adjust heading level to H8
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H4 followed by H8'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/cloud-images.md:130
  fix_suggestion: Adjust heading level to H5
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/build-package-or-kernel-modules-using-script.md:21
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/downloading-photon.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/installing-and-using-lightwave/remotely-upgrade-multiple-photon-os-machines-with-lightwave-client-and-photon-management-daemon-installed.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/installing-and-using-lightwave/remotely-upgrade-a-photon-os-machine-with-lightwave-client-and-photon-management-daemon-installed.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/installing-and-using-lightwave/installing-lightwave-server-and-setting-up-a-domain.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/installing-and-using-lightwave/installing-the-photon-management-daemon-on-a-lightwave-client.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/installing-and-using-lightwave/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/installing-and-using-lightwave/installing-lightwave-client-and-joining-a-domain.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/run-photon-on-gce/prerequisites-for-photon-os-on-gce.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H12'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/run-photon-on-raspberry-pi/enabling-RPi-interfaces-using-devicetree.md:32
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/run-photon-on-raspberry-pi/installing-the-iso-image-for-photon-os-rpi.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/install-photon-on-dell-gateway/installing-photon-os-on-dell-300X.md:11
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/install-photon-on-dell-gateway/installing-photon-os-on-dell-500X.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/photon-management-daemon/available-apis.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/run-photon-on-azure/setting-up-azure-storage-and-uploading-the-vhd.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H11'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/run-photon-on-azure/setting-up-azure-storage-and-uploading-the-vhd.md:107
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H11'
  location: /var/www/photon-site/content/en/docs-v3/installation-guide/run-photon-on-azure/remove-photon-from-azure.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/user-guide/working-with-kickstart.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H2 followed by H12'
  location: /var/www/photon-site/content/en/docs-v3/user-guide/working-with-kickstart.md:289
  fix_suggestion: Adjust heading level to H3
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/user-guide/mounting-remote-file-systems.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/user-guide/_index.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/user-guide/packer-examples/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v3/user-guide/kubernetes-on-photon-os/running-kubernetes-on-photon-os/configure-kubernetes-on-node.md:62
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/whats-new.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/_index.md:26
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/Overview/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H3'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-installation-issue.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/troubleshooting-linux-kernel.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/investigating-the-guest-kernel.md:18
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/kernel-problems-and-boot-and-login-errors/kernel-log-replication-with-vprobes.md:13
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/secureboot-with-fips.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H11'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/vmtoolsd.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H15'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H9 followed by H12'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:109
  fix_suggestion: Adjust heading level to H10
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H11 followed by H14'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:124
  fix_suggestion: Adjust heading level to H12
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H7 followed by H17'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:155
  fix_suggestion: Adjust heading level to H8
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H8 followed by H12'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:178
  fix_suggestion: Adjust heading level to H9
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H6 followed by H12'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/network-configuration.md:191
  fix_suggestion: Adjust heading level to H7
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H13'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/cloud-init.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H13 followed by H16'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/cloud-init.md:20
  fix_suggestion: Adjust heading level to H14
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H16 followed by H18'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/cloud-init.md:31
  fix_suggestion: Adjust heading level to H17
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H6'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H2 followed by H6'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:25
  fix_suggestion: Adjust heading level to H3
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H5'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/photon-code.md:33
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H5'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/package-management.md:30
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H7'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/package-management.md:56
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H4 followed by H7'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/photon-os-general-troubleshooting/package-management.md:123
  fix_suggestion: Adjust heading level to H5
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H12'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H13'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:97
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H9 followed by H14'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:100
  fix_suggestion: Adjust heading level to H10
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H14 followed by H19'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:101
  fix_suggestion: Adjust heading level to H15
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H19 followed by H25'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:102
  fix_suggestion: Adjust heading level to H20
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H14 followed by H16'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:105
  fix_suggestion: Adjust heading level to H15
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H16 followed by H19'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:106
  fix_suggestion: Adjust heading level to H17
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H15 followed by H17'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:109
  fix_suggestion: Adjust heading level to H16
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H17 followed by H20'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:110
  fix_suggestion: Adjust heading level to H18
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H17 followed by H20'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:116
  fix_suggestion: Adjust heading level to H18
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H18 followed by H21'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/introduction/photon-os-logs.md:118
  fix_suggestion: Adjust heading level to H19
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/troubleshooting-tools/common-tools.md:28
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H6'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh.md:20
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/troubleshooting-guide/solutions-to-common-problems/resetting-a-lost-root-password.md:38
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/support-for-selinux.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/configure-wireless-networking.md:11
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-real-time-operating-system.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/_index.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-os-installer-overview.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/kernel-live-patching.md:17
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/managing-network-configuration/configuring-network-photon-using-network-config-manager.md:95
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/managing-network-configuration/configuring-a-secondary-network-interface-using-cloud-network.md:21
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/managing-network-configuration/using-network-event-broker.md:16
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/managing-network-configuration/setting-up-networking-for-multiple-nics/combining-dhcp-and-static-ip-addresses-with-ipv4-and-ipv6.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/managing-network-configuration/setting-up-networking-for-multiple-nics/_index.md:39
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/managing-packages-with-tdnf/configuration_options.md:32
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H3'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/managing-packages-with-tdnf/tdnf-automatic.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/remotes/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/querying-for-metadata/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/concepts-in-action/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/file-oriented-server-operations/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/introduction/_index.md:6
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/install-or-rebase-to-photon-os-4/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/installing-a-host-against-custom-server-repository/_index.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/automatic-updates/_index.md:19
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/running-container-applications-between-bootable-images/_index.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H18'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/running-container-applications-between-bootable-images/_index.md:40
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/host-updating-operations/_index.md:18
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/installing-a-host-against-default-server-repository/_index.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/creating-a-rpm-ostree-server/_index.md:45
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-rpm-ostree/package-oriented-server-operations/_index.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/managing-services-withsystemd/installing-sendmail.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/containers/support_distributed_builds.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/containers/docker-rootless-support.md:6
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/Configuration.md:65
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/system-management.md:6
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/network-management.md:6
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/network-management.md:1226
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/user-group-host-management.md:6
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H2 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/user-group-host-management.md:130
  fix_suggestion: Adjust heading level to H3
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H2 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/user-group-host-management.md:170
  fix_suggestion: Adjust heading level to H3
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H2 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/user-group-host-management.md:238
  fix_suggestion: Adjust heading level to H3
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H2 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/user-group-host-management.md:258
  fix_suggestion: Adjust heading level to H3
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/service-management.md:6
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/package-management.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/process-configurtion-management.md:7
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/pmd-nextgen/photon-mgmtd-web-REST-API/firewall-nftable-management.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/photon-os-packages/building-a-package-from-a-source-rpm.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/cloud-init-on-photon-os/running-a-photon-os-machine-on-gce.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H13'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/cloud-init-on-photon-os/customizing-a-photon-os-machine-on-ec2.md:64
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H3'
  location: /var/www/photon-site/content/en/docs-v5/administration-guide/cloud-init-on-photon-os/customizing-gos-cloud-init.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/command-line-reference/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/command-line-reference/command-line-Interfaces/photon-real-time-cli.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/command-line-reference/command-line-Interfaces/photon-network-config-manager-cli/configure-wireguard-using-network-config-manager.md:30
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/cloud-images.md:19
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H11'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/cloud-images.md:52
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H10'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/cloud-images.md:76
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H10 followed by H12'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/cloud-images.md:84
  fix_suggestion: Adjust heading level to H11
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H7 followed by H10'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/cloud-images.md:100
  fix_suggestion: Adjust heading level to H8
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H4 followed by H8'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/cloud-images.md:130
  fix_suggestion: Adjust heading level to H5
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/downloading-photon.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/building images/build-custom-iso-from-source-code-for-photon-os-installer.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/run-photon-on-gce/installing-photon-os-on-gce.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H2 followed by H11'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/run-photon-on-gce/installing-photon-os-on-gce.md:62
  fix_suggestion: Adjust heading level to H3
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/run-photon-on-gce/prerequisites-for-photon-os-on-gce.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H12'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/run-photon-on-raspberry-pi/enabling-RPi-interfaces-using-devicetree.md:33
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/run-photon-on-raspberry-pi/installing-the-iso-image-for-photon-os-rpi.md:10
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/build-package-kernel-modules-using-script/package-with-patch-file.md:75
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/build-package-kernel-modules-using-script/package-which-downloads-source-from-github.md:76
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/build-package-kernel-modules-using-script/package-to-provide-hello-world-kernel-module.md:60
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H4'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/build-package-kernel-modules-using-script/package-which-provides-hello-world-binary.md:52
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/build-package-kernel-modules-using-script/package-which-is-dependent-on-another-package.md:57
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/build-package-kernel-modules-using-script/_index.md:21
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/run-photon-on-azure/setting-up-azure-storage-and-uploading-the-vhd.md:8
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H11'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/run-photon-on-azure/setting-up-azure-storage-and-uploading-the-vhd.md:107
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H11'
  location: /var/www/photon-site/content/en/docs-v5/installation-guide/run-photon-on-azure/remove-photon-from-azure.md:22
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/working-with-kickstart.md:15
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/mounting-remote-file-systems.md:9
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/_index.md:14
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/packer-examples/_index.md:12
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/running-kubernetes-on-photon-os/configure-kubernetes-on-node.md:62
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H6'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/run-an-app.md:32
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-master-node.md:11
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H3'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-master-node.md:64
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H3'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-master-node.md:94
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H8'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-master-node.md:99
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H7 followed by H17'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-master-node.md:118
  fix_suggestion: Adjust heading level to H8
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H6 followed by H10'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-master-node.md:122
  fix_suggestion: Adjust heading level to H7
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H8'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-master-node.md:140
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H2 followed by H6'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-master-node.md:241
  fix_suggestion: Adjust heading level to H3
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H6'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-master-node.md:269
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H0 followed by H2'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-worker-node-on-kubernetes.md:15
  fix_suggestion: Adjust heading level to H1
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H3'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-worker-node-on-kubernetes.md:64
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H3'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-worker-node-on-kubernetes.md:94
  fix_suggestion: Adjust heading level to H2
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H3 followed by H8'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-worker-node-on-kubernetes.md:99
  fix_suggestion: Adjust heading level to H4
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H7 followed by H17'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-worker-node-on-kubernetes.md:118
  fix_suggestion: Adjust heading level to H8
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H6 followed by H10'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-worker-node-on-kubernetes.md:122
  fix_suggestion: Adjust heading level to H7
- severity: high
  category: markdown
  description: 'Heading hierarchy violation: H1 followed by H8'
  location: /var/www/photon-site/content/en/docs-v5/user-guide/kubernetes-on-photon-os/kubernetes-kubeadm-cluster-on-photon/configure-worker-node-on-kubernetes.md:140
  fix_suggestion: Adjust heading level to H2

# Photon OS URL Health - cross-branch matrix

## Spec-matrix — issue applicability per branch

**223** packages with at least one issue across 8 branches.

Cell legend: severity colour + issue category number(s) — 🔴 High (1,2,3) · 🟠 Medium (4,5,6,7) · 🟡 Low-Medium (8) · 🟢 present & URL health OK · ⚪ not carried · 📌 vendor-pinned subrelease (non-issue) · 🔵 VMware-internal Source0 (non-issue).

| Spec | 3.0 | 4.0 | 5.0 | 5.0/SPECS/90 | 5.0/SPECS/91 | 6.0 | common | dev | master | main | main/SPECS/90 | main/SPECS/91 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Linux-PAM.spec | 🟠7 | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | 📌 | ⚪ |
| ModemManager.spec | 🟠7 | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | ⚪ | 📌 | ⚪ |
| PyPAM.spec | 🔴3 | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| PyYAML.spec | 🟠5 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| alternatives.spec | ⚪ | ⚪ | 🔴2 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴2 | ⚪ | ⚪ |
| apache-tomcat-native.spec | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠5 | 🟢 | 🟢 | ⚪ | ⚪ |
| apparmor.spec | 🟠7 | 🟠7 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | ⚪ | 📌 |
| autoconf213.spec | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| bluez-tools.spec | 🟡8 | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | ⚪ | 📌 | ⚪ |
| bridge-utils.spec | 🟠7 | 🟠7 | ⚪ | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | ⚪ | ⚪ | 📌 |
| c-rest-engine.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| ca-certificates-nxtgn-openssl.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| cdrkit.spec | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| check.spec | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟠6 | 🟢 | ⚪ | ⚪ |
| chromium.spec | ⚪ | 🔴1 | 🔴1 | ⚪ | ⚪ | 🔴1 | ⚪ | 🔴1 | 🔴1 | 🔴1 | ⚪ | ⚪ |
| clang.spec | 🟠7 | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | ⚪ | ⚪ | 📌 |
| cloud-network-setup.spec | ⚪ | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| commons-daemon.spec | 🟠7 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| containers-common.spec | ⚪ | 🟠5 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| copenapi.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| cpulimit.spec | 🔴3 | 🔴3 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| crash.spec | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| cronie.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| cve-check-tool.spec | 🟡8 | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| dbus-python.spec | 🟠7 | 🟠7 | 🟢 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟢 | ⚪ | 📌 |
| dcerpc.spec | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| dhcp.spec | 🔴2 | 🔴2 | ⚪ | 📌 | ⚪ | 🔴2 | ⚪ | 🟡8 | 🟡8 | ⚪ | ⚪ | 📌 |
| dnsmasq.spec | 🟢 | 🟠5 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| dos2unix.spec | ⚪ | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| dovecot-pigeonhole.spec | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| dovecot.spec | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| dracut.spec | 🟢 | 🟢 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | 📌 | ⚪ |
| dtb-raspberrypi.spec | ⚪ | 🟠5 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| efivar.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| erofs-utils.spec | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ |
| etcd-3.3.27.spec | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| ethtool.spec | 🟢 | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| eventlog.spec | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | 📌 | ⚪ |
| expat.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| fcgi.spec | 🔴3 | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| filesystem.spec | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🟠6 | 🟠6 | 🔴3 | ⚪ | ⚪ |
| findutils.spec | 🟠7 | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| finger.spec | 🔴3 | 🔴3 | ⚪ | 📌 | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| font-util.spec | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| fontconfig.spec | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| fuse3.spec | 🟢 | 🟢 | 🟠6 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| glog.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| google-compute-engine.spec | 🟢 | 🟠5 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟢 | 🟢 | ⚪ | ⚪ | ⚪ |
| govmomi.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| gst-plugins-bad.spec | ⚪ | 🟠5 | ⚪ | 📌 | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| gtest.spec | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| haproxy.spec | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠7 | 🟠7 | 🟢 | ⚪ | ⚪ |
| hawkey.spec | 🟠5 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| heapster.spec | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| http-parser.spec | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| hyper-v.spec | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| ibmtpm.spec | 🟢 | 🟢 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | ⚪ | 📌 |
| icu.spec | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| influxdb.spec | 🟢 | 🟠5 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| iotop.spec | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | 📌 |
| iptables.spec | 🟢 | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟠5 | 🟢 | ⚪ | 📌 |
| iptraf.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| iputils.spec | 🟠7 | 🟠7 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟠7 | 🟠7 | 🟢 | ⚪ | 📌 |
| ipxe.spec | 🟠5 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| json_spirit.spec | 🟠6 | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| kbd.spec | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠5 | 🟢 | 🟢 | ⚪ | ⚪ |
| kexec-tools.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| kubernetes-dashboard.spec | 🟡8 | 🟡8 | 🟡8 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | 📌 |
| lasso.spec | ⚪ | 🟠6 | 🟠6 | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | 📌 |
| leveldb.spec | 🟠7 | 🟠7 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libICE.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libSM.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXScrnSaver.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXau.spec | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXcomposite.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXcursor.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXdamage.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXdcmp.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| libXdmcp.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXext.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXfixes.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXfont2.spec | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXi.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXrandr.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXrender.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXt.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libXtst.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libassuan.spec | 🔴3 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libbsd.spec | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| libcap.spec | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ |
| libclc.spec | ⚪ | ⚪ | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 📌 |
| libdaemon.spec | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ |
| libdisplay-info.spec | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ |
| libdrm.spec | ⚪ | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| libepoxy.spec | ⚪ | 🟢 | 🟠6 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libfastjson.spec | 🟠7 | 🟠7 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠7 | 🟠7 | 🟢 | ⚪ | ⚪ |
| libfontenc.spec | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libgsystem.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| libhugetlbfs.spec | 🟢 | 🟢 | 🟠5 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libmspack.spec | 🟠5 | 🟠5 | 🟠5 | 📌 | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | 📌 |
| libnss-ato.spec | 🟠5 | 🟠5 | 🟠5 | 📌 | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| libpciaccess.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| libsepol.spec | 🔴3 | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| libslirp.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| libtar.spec | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libtirpc.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| libunwind.spec | 🟢 | 🟢 | 🟠7 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libxml2.spec | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| libxshmfence.spec | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| lightstep-tracer-cpp.spec | 🔴3 | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| lightwave.spec | 🟠5 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| likewise-open.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| linux-api-headers.spec | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠6 | ⚪ | ⚪ |
| linux-esx.spec | 🟢 | 🟢 | 🟠5 | ⚪ | 📌 | 🟢 | ⚪ | 🟢 | 🟢 | 🟠6 | ⚪ | 📌 |
| linux.spec | 🟢 | 🟠5 | 🟠5 | ⚪ | 📌 | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🔴3 | ⚪ | 📌 |
| lldb.spec | 🟠7 | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | ⚪ | ⚪ | 📌 |
| llvm.spec | 🟠7 | 🟠7 | 🟢 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟢 | ⚪ | 📌 |
| log4cpp.spec | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| lshw.spec | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| lvm2.spec | 🟢 | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟠5 | 🟢 | 🟢 | ⚪ | 📌 |
| lxcfs.spec | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| lzo.spec | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | 📌 |
| mc.spec | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| mdadm.spec | ⚪ | ⚪ | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | 📌 | ⚪ |
| mesa.spec | ⚪ | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| motd.spec | 🟠5 | 🟠5 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| mozjs.spec | ⚪ | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| ncurses.spec | 🟢 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟢 | 🟢 | 🟠7 | ⚪ | ⚪ |
| ndsend.spec | 🔴3 | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| netkit-telnet.spec | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ |
| netmgmt.spec | 🟠5 | 🟠5 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| nodejs-10.24.0.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| nodejs-8.17.0.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| nodejs-9.11.2.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| nss.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🔴2 | 🔴2 | 🟠7 | ⚪ | ⚪ |
| nxtgn-openssl.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| oniguruma.spec | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| open-sans-fonts.spec | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| open-vm-tools.spec | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| openjdk10.spec | 🟠7 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| openjdk11_aarch64.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| openjdk17_aarch64.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| openjdk25.spec | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ |
| openjdk8_aarch64.spec | 🔴2 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| openssh.spec | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| openssl.spec | 🟠5 | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| pcre.spec | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| pcstat.spec | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| perl-Clone.spec | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | ⚪ |
| perl-Data-Dump.spec | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | ⚪ |
| perl-File-Which.spec | 🟢 | 🟢 | 🟠6 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| perl-IPC-Run.spec | ⚪ | 🟠6 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠6 | 🟠6 | 🟠7 | ⚪ | ⚪ |
| perl-List-MoreUtils.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| perl-Module-ScanDeps.spec | 🟢 | 🟢 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟢 | 🟢 | 🟠5 | ⚪ | ⚪ |
| perl-URI.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| perl-YAML-Tiny.spec | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| pgaudit.spec | 🟠7 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| pgaudit13.spec | ⚪ | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| pgaudit14.spec | ⚪ | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| pgaudit15.spec | ⚪ | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| pgaudit16.spec | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| pgaudit17.spec | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ |
| polkit.spec | 🟠7 | 🟢 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| popt.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| procps-ng.spec | 🟢 | 🟢 | 🔴3 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🔴3 | ⚪ | 📌 |
| proto.spec | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| pth.spec | 🟠7 | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | ⚪ | 📌 | ⚪ |
| python-antlrpythonruntime.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| python-argparse.spec | ⚪ | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | ⚪ | ⚪ | 📌 |
| python-atomicwrites.spec | 🟡8 | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | ⚪ | 📌 | ⚪ |
| python-daemon.spec | 🔴3 | 🔴3 | ⚪ | 📌 | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | 📌 |
| python-dateutil.spec | 🟢 | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟠6 | 🟢 | ⚪ | 📌 |
| python-enum.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| python-filelock.spec | ⚪ | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| python-google-auth.spec | ⚪ | ⚪ | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| python-installer.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| python-ipaddr.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟡8 | 🟡8 | ⚪ | ⚪ | ⚪ |
| python-lockfile.spec | 🟡8 | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | 📌 |
| python-pycodestyle.spec | 🟡8 | 🟡8 | 🟡8 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | 📌 |
| python-pyvmomi.spec | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| python-ruamel-yaml.spec | 🔴3 | 🔴3 | 🔴3 | 📌 | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | 📌 |
| python-subprocess32.spec | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| python-terminaltables.spec | 🟡8 | ⚪ | 🟡8 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | 📌 |
| python-vcs-versioning.spec | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ |
| python3-Pygments.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| python3-hatchling.spec | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ |
| python3-iniconfig.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| python3-iniparse.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| python3-legacy-cgi.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| python3-markupsafe.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| python3-msal.spec | ⚪ | ⚪ | 🔴2 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴2 | ⚪ | ⚪ |
| python3-passlib.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| python3-roman-numerals.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| python3-trove-classifiers.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| python3-wheel.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| qemu.spec | ⚪ | ⚪ | 🟠7 | 📌 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠7 | ⚪ | 📌 |
| raspberrypi-firmware.spec | ⚪ | 🔴1 | 🔴1 | ⚪ | ⚪ | 🔴1 | ⚪ | 🔴1 | 🔴1 | 🔴1 | ⚪ | ⚪ |
| re2.spec | ⚪ | 🟠5 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| repmgr18.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| scons.spec | 🟠7 | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🔴3 | 🔴3 | 🟠7 | ⚪ | 📌 |
| sendmail.spec | 🟢 | 🔴3 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🔴3 | 🔴3 | 🟢 | 📌 | ⚪ |
| socat.spec | 🟢 | 🟠5 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| spirv-headers.spec | ⚪ | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| spirv-tools.spec | ⚪ | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| sqlite2.spec | 🔴3 | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| squid.spec | 🟢 | 🟢 | 🔴2 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🔴2 | ⚪ | 📌 |
| syslinux.spec | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| systemd.spec | 🟢 | 🟢 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟠5 | 🟢 | 🟠5 | 📌 | ⚪ |
| tcl.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| tiptop.spec | 🟠6 | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| tmux.spec | 🟢 | 🟠5 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| tzdata.spec | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| ulogd.spec | 🔴3 | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| unixODBC.spec | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| urw-fonts.spec | 🟠5 | 🟠5 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| util-macros.spec | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| vulkan-tools.spec | ⚪ | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| wal2json18.spec | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🔴3 | ⚪ | ⚪ |
| wayland-protocols.spec | ⚪ | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| xfsprogs.spec | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | ⚪ | ⚪ |
| xorg-applications.spec | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | 📌 |
| xorg-fonts.spec | 🔴3 | 🔴3 | ⚪ | 📌 | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | ⚪ | ⚪ | 📌 |
| xtrans.spec | 🔴3 | 🔴3 | 🔴3 | 📌 | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |

## Issue categories — affected packages

| # | Issue Category | Severity | Packages | Affected specs |
|---|---|---|---|---|
| 1 | Source URL blank / macro unresolved (UrlHealth=blank) | 🔴 High | 2 | chromium.spec, raspberrypi-firmware.spec |
| 2 | URL substitution unfinished | 🔴 High | 6 | alternatives.spec, dhcp.spec, nss.spec, openjdk8_aarch64.spec, python3-msal.spec, squid.spec |
| 3 | Source URL unreachable (UrlHealth=0) | 🔴 High | 63 | PyPAM.spec, cdrkit.spec, cpulimit.spec, dcerpc.spec, fcgi.spec, filesystem.spec, finger.spec, font-util.spec, hyper-v.spec, iptraf.spec, libICE.spec, libSM.spec, libXScrnSaver.spec, libXau.spec, libXcomposite.spec, libXcursor.spec, libXdamage.spec, libXdcmp.spec, libXdmcp.spec, libXext.spec, libXfixes.spec, libXfont2.spec, libXi.spec, libXrandr.spec, libXrender.spec, libXt.spec, libXtst.spec, libassuan.spec, libfontenc.spec, libgsystem.spec, libpciaccess.spec, libsepol.spec, libxshmfence.spec, lightstep-tracer-cpp.spec, likewise-open.spec, linux.spec, ndsend.spec, openjdk11_aarch64.spec, openjdk17_aarch64.spec, procps-ng.spec, proto.spec, python-daemon.spec, python-enum.spec, python-installer.spec, python-ruamel-yaml.spec, python3-Pygments.spec, python3-iniconfig.spec, python3-iniparse.spec, python3-legacy-cgi.spec, python3-markupsafe.spec, python3-passlib.spec, python3-roman-numerals.spec, python3-trove-classifiers.spec, python3-wheel.spec, repmgr18.spec, scons.spec, sendmail.spec, sqlite2.spec, ulogd.spec, util-macros.spec, wal2json18.spec, xorg-fonts.spec, xtrans.spec |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 🟠 Medium | 36 | PyYAML.spec, apache-tomcat-native.spec, apparmor.spec, containers-common.spec, dnsmasq.spec, dracut.spec, dtb-raspberrypi.spec, google-compute-engine.spec, gst-plugins-bad.spec, hawkey.spec, ibmtpm.spec, influxdb.spec, iptables.spec, ipxe.spec, kbd.spec, libhugetlbfs.spec, libmspack.spec, libnss-ato.spec, lightwave.spec, linux-esx.spec, linux.spec, lshw.spec, lvm2.spec, mdadm.spec, motd.spec, netmgmt.spec, openssl.spec, pcstat.spec, perl-Module-ScanDeps.spec, re2.spec, socat.spec, syslinux.spec, systemd.spec, tmux.spec, urw-fonts.spec, xfsprogs.spec |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 🟠 Medium | 41 | ca-certificates-nxtgn-openssl.spec, check.spec, dovecot-pigeonhole.spec, dovecot.spec, ethtool.spec, eventlog.spec, filesystem.spec, fuse3.spec, gtest.spec, iotop.spec, json_spirit.spec, lasso.spec, libbsd.spec, libdaemon.spec, libdisplay-info.spec, libepoxy.spec, linux-api-headers.spec, linux-esx.spec, log4cpp.spec, lzo.spec, mc.spec, netkit-telnet.spec, nodejs-10.24.0.spec, nodejs-8.17.0.spec, nodejs-9.11.2.spec, nxtgn-openssl.spec, oniguruma.spec, open-sans-fonts.spec, openjdk25.spec, perl-Clone.spec, perl-Data-Dump.spec, perl-File-Which.spec, perl-IPC-Run.spec, perl-YAML-Tiny.spec, popt.spec, python-antlrpythonruntime.spec, python-dateutil.spec, python3-hatchling.spec, tiptop.spec, tzdata.spec, xorg-applications.spec |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 🟠 Medium | 64 | Linux-PAM.spec, ModemManager.spec, apparmor.spec, bridge-utils.spec, clang.spec, commons-daemon.spec, cronie.spec, dbus-python.spec, dos2unix.spec, dtb-raspberrypi.spec, efivar.spec, erofs-utils.spec, expat.spec, findutils.spec, fontconfig.spec, glog.spec, govmomi.spec, haproxy.spec, icu.spec, iputils.spec, kexec-tools.spec, leveldb.spec, libcap.spec, libclc.spec, libdrm.spec, libfastjson.spec, libslirp.spec, libtirpc.spec, libunwind.spec, libxml2.spec, lldb.spec, llvm.spec, lxcfs.spec, mesa.spec, mozjs.spec, ncurses.spec, nss.spec, open-vm-tools.spec, openjdk10.spec, openssh.spec, perl-IPC-Run.spec, perl-List-MoreUtils.spec, perl-URI.spec, pgaudit.spec, pgaudit13.spec, pgaudit14.spec, pgaudit15.spec, pgaudit16.spec, pgaudit17.spec, polkit.spec, popt.spec, pth.spec, python-filelock.spec, python-google-auth.spec, python-pyvmomi.spec, python-vcs-versioning.spec, qemu.spec, scons.spec, spirv-headers.spec, spirv-tools.spec, tcl.spec, unixODBC.spec, vulkan-tools.spec, wayland-protocols.spec |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 🟡 Low-Medium | 23 | autoconf213.spec, bluez-tools.spec, c-rest-engine.spec, cloud-network-setup.spec, copenapi.spec, crash.spec, cve-check-tool.spec, dhcp.spec, etcd-3.3.27.spec, heapster.spec, http-parser.spec, kubernetes-dashboard.spec, libtar.spec, motd.spec, pcre.spec, python-argparse.spec, python-atomicwrites.spec, python-ipaddr.spec, python-lockfile.spec, python-pycodestyle.spec, python-subprocess32.spec, python-terminaltables.spec, sqlite2.spec |

## Non-issue categories (informational — not counted as issues)

| Category | Marker | Packages | Specs |
|---|---|---|---|
| Vendor-pinned subrelease (frozen for a Photon sub-release) | 📌 | 618 | GConf.spec, ImageMagick.spec, Linux-PAM.spec, ModemManager.spec, WALinuxAgent.spec, ansible-community-general.spec, ansible-posix.spec, ansible.spec, ant-contrib.spec, apparmor.spec, apr-util.spec, argon2.spec, asciidoc3.spec, at-spi2-core.spec, atk.spec, audit.spec, aufs-util.spec, autogen.spec, backward-cpp.spec, bash-completion.spec, bash.spec, bazel.spec, bcc.spec, bindutils.spec, bluez-tools.spec, bluez.spec, bpftrace.spec, bridge-utils.spec, btrfs-progs.spec, bubblewrap.spec, c-ares.spec, calico-bgp-daemon.spec, calico-libnetwork.spec, calico.spec, checkpolicy.spec, chkconfig.spec, chrpath.spec, clang.spec, cloud-init.spec, containerd.spec, cppunit.spec, cracklib.spec, createrepo_c.spec, crun.spec, cryptsetup.spec, ctags.spec, cve-check-tool.spec, cython3.spec, dbus-broker.spec, dbus-python.spec, dbus.spec, device-mapper-multipath.spec, dhcp.spec, distcc.spec, dnsmasq.spec, docker-buildx.spec, docker-py.spec, docker-pycreds.spec, docker.spec, dool.spec, dotnet-runtime.spec, dotnet-sdk.spec, doxygen.spec, dracut.spec, drpm.spec, dtb-raspberrypi.spec, e2fsprogs.spec, ethtool.spec, eventlog.spec, fail2ban.spec, falco.spec, findutils.spec, finger.spec, fio.spec, fontconfig.spec, fping.spec, frr.spec, fsarchiver.spec, fuse-overlayfs.spec, fuse.spec, fuse3.spec, gawk.spec, gcc.spec, gdb.spec, gdk-pixbuf.spec, geoip-api-c.spec, git.spec, glib-networking.spec, glib.spec, glibc.spec, glibmm.spec, glslang.spec, gnome-common.spec, gnutls.spec, go.spec, gobgp.spec, gobject-introspection.spec, gpsd.spec, graphene.spec, gst-plugins-bad.spec, gstreamer-plugins-base.spec, gstreamer.spec, gtk-doc.spec, gtk3.spec, harfbuzz.spec, hiredis.spec, hyperscan.spec, iana-etc.spec, ibmtpm.spec, icu.spec, influxdb.spec, initscripts.spec, inotify-tools.spec, iotop.spec, iproute2.spec, iptables.spec, iputils.spec, itstool.spec, jc.spec, json-glib.spec, jsoncpp.spec, kafka.spec, keepalived.spec, kubernetes-dashboard.spec, lasso.spec, libbpf.spec, libcap-ng.spec, libcap.spec, libclc.spec, libdaemon.spec, libdnet.spec, libecap.spec, libgudev.spec, libical.spec, libldb.spec, libmbim.spec, libmodulemd.spec, libmspack.spec, libnetfilter_conntrack.spec, libnftnl.spec, libnsl.spec, libnss-ato.spec, libnvme.spec, libpsl.spec, libpwquality.spec, librelp.spec, librepo.spec, libretls.spec, libselinux-python3.spec, libselinux.spec, libsemanage.spec, libsepol.spec, libsolv.spec, libsoup.spec, libssh2.spec, libtalloc.spec, libtdb.spec, libteam.spec, libtevent.spec, libtraceevent.spec, libtracefs.spec, libvirt.spec, libxcb.spec, libxcrypt.spec, libxml2.spec, lighttpd.spec, linux-esx.spec, linux-rt.spec, linux-tools-90.spec, linux-tools.spec, linux.spec, linuxptp.spec, lldb.spec, llvm.spec, lttng-tools.spec, lttng-ust.spec, lvm2.spec, lxcfs.spec, lzo.spec, mariadb.spec, mdadm.spec, mercurial.spec, mesa.spec, meson.spec, minimal.spec, mkinitcpio.spec, monitoring-plugins.spec, mozjs.spec, msr-tools.spec, mysql.spec, net-snmp.spec, net-tools.spec, netcat.spec, netkit-telnet.spec, nfs-utils.spec, nftables.spec, nginx.spec, nicstat.spec, ninja-build.spec, nodejs.spec, ntp.spec, ntpsec.spec, nvme-cli.spec, open-vm-tools.spec, openipmi.spec, openscap.spec, openssh.spec, openssl-fips-provider.spec, openssl.spec, openvswitch.spec, ostree.spec, pam_tacplus.spec, pandoc.spec, pango.spec, pgaudit13.spec, pgaudit14.spec, pgaudit15.spec, pgbackrest.spec, photon-os-installer.spec, photon-repos.spec, podman.spec, policycoreutils.spec, polkit.spec, postgresql10.spec, postgresql13.spec, postgresql14.spec, postgresql15.spec, postgresql16.spec, postgresql17.spec, powershell.spec, procmail.spec, procps-ng.spec, protobuf.spec, pth.spec, pycurl.spec, python-CacheControl.spec, python-ConcurrentLogHandler.spec, python-Js2Py.spec, python-M2Crypto.spec, python-PyHamcrest.spec, python-PyJWT.spec, python-PyNaCl.spec, python-PyYAML.spec, python-Pygments.spec, python-Twisted.spec, python-alabaster.spec, python-altgraph.spec, python-appdirs.spec, python-argparse.spec, python-asn1crypto.spec, python-atomicwrites.spec, python-attrs.spec, python-automat.spec, python-autopep8.spec, python-babel.spec, python-backports.ssl_match_hostname.spec, python-backports_abc.spec, python-bcrypt.spec, python-binary.spec, python-boto.spec, python-boto3.spec, python-botocore.spec, python-cachetools.spec, python-cassandra-driver.spec, python-certifi.spec, python-cffi.spec, python-chardet.spec, python-charset-normalizer.spec, python-click.spec, python-configobj.spec, python-configparser.spec, python-constantly.spec, python-coverage.spec, python-cqlsh.spec, python-cryptography.spec, python-daemon.spec, python-dateutil.spec, python-decorator.spec, python-deepmerge.spec, python-defusedxml.spec, python-distlib.spec, python-distro.spec, python-dnspython.spec, python-docopt.spec, python-docutils.spec, python-ecdsa.spec, python-email-validator.spec, python-etcd.spec, python-ethtool.spec, python-filelock.spec, python-flit-core.spec, python-fuse.spec, python-geomet.spec, python-gevent.spec, python-google-auth.spec, python-graphviz.spec, python-greenlet.spec, python-hatch-fancy-pypi-readme.spec, python-hatch-vcs.spec, python-hatchling.spec, python-hyperlink.spec, python-hypothesis.spec, python-idna.spec, python-imagesize.spec, python-importlib-metadata.spec, python-incremental.spec, python-iniconfig.spec, python-iniparse.spec, python-ipaddress.spec, python-jinja2.spec, python-jmespath.spec, python-jsonpatch.spec, python-jsonpointer.spec, python-jsonschema.spec, python-kubernetes.spec, python-linux-procfs.spec, python-lockfile.spec, python-looseversion.spec, python-lxml.spec, python-mako.spec, python-markupsafe.spec, python-mistune.spec, python-mock.spec, python-more-itertools.spec, python-msgpack.spec, python-ndg-httpsclient.spec, python-netaddr.spec, python-netifaces.spec, python-networkx.spec, python-nocasedict.spec, python-nocaselist.spec, python-ntplib.spec, python-numpy.spec, python-oauthlib.spec, python-packaging.spec, python-pam.spec, python-paramiko.spec, python-pathspec.spec, python-pbr.spec, python-pexpect.spec, python-pg8000.spec, python-pika.spec, python-pkgconfig.spec, python-platformdirs.spec, python-pluggy.spec, python-ply.spec, python-portalocker.spec, python-prettytable.spec, python-prometheus_client.spec, python-prompt_toolkit.spec, python-psutil.spec, python-psycopg2.spec, python-ptyprocess.spec, python-py.spec, python-pyOpenSSL.spec, python-pyasn1-modules.spec, python-pyasn1.spec, python-pycodestyle.spec, python-pycparser.spec, python-pycryptodome.spec, python-pycryptodomex.spec, python-pydantic.spec, python-pyflakes.spec, python-pygobject.spec, python-pyinstaller-hooks-contrib.spec, python-pyinstaller.spec, python-pyjsparser.spec, python-pyparsing.spec, python-pyrsistent.spec, python-pyserial.spec, python-pytest.spec, python-pytz-deprecation-shim.spec, python-pytz.spec, python-pyudev.spec, python-pyvim.spec, python-pyvmomi.spec, python-pywbem.spec, python-requests-oauthlib.spec, python-requests-toolbelt.spec, python-requests-unixsocket.spec, python-requests.spec, python-resolvelib.spec, python-rsa.spec, python-ruamel-yaml.spec, python-s3transfer.spec, python-schedutils.spec, python-scp.spec, python-scramp.spec, python-semantic-version.spec, python-service_identity.spec, python-setuptools-rust.spec, python-setuptools_scm.spec, python-simplejson.spec, python-six.spec, python-snowballstemmer.spec, python-sortedcontainers.spec, python-sphinx.spec, python-sphinxcontrib-applehelp.spec, python-sphinxcontrib-devhelp.spec, python-sphinxcontrib-htmlhelp.spec, python-sphinxcontrib-jsmath.spec, python-sphinxcontrib-qthelp.spec, python-sphinxcontrib-serializinghtml.spec, python-sqlalchemy.spec, python-systemd.spec, python-terminaltables.spec, python-toml.spec, python-tornado.spec, python-typing-extensions.spec, python-tzlocal.spec, python-ujson.spec, python-urllib3.spec, python-vcversioner.spec, python-versioningit.spec, python-virtualenv.spec, python-wcwidth.spec, python-webob.spec, python-websocket-client.spec, python-werkzeug.spec, python-wheel.spec, python-wrapt.spec, python-xmltodict.spec, python-yamlloader.spec, python-zipp.spec, python-zmq.spec, python-zope.event.spec, python-zope.interface.spec, python3-gcovr.spec, python3-pip.spec, python3-pyroute2.spec, python3-setuptools.spec, python3.spec, qemu.spec, rabbitmq-server.spec, rdma-core.spec, redis.spec, repmgr13.spec, repmgr14.spec, repmgr15.spec, rng-tools.spec, rootlesskit.spec, rpm-ostree.spec, rpm.spec, rpmdevtools.spec, rrdtool.spec, rsyslog.spec, rt-tests.spec, ruby.spec, rubygem-activesupport.spec, rubygem-addressable.spec, rubygem-async-http.spec, rubygem-async-io.spec, rubygem-async-pool.spec, rubygem-async.spec, rubygem-aws-eventstream.spec, rubygem-aws-partitions.spec, rubygem-aws-sdk-core.spec, rubygem-aws-sdk-kms.spec, rubygem-aws-sdk-s3.spec, rubygem-aws-sdk-sqs.spec, rubygem-aws-sigv4.spec, rubygem-backports.spec, rubygem-builder.spec, rubygem-bundler.spec, rubygem-concurrent-ruby.spec, rubygem-console.spec, rubygem-cool-io.spec, rubygem-declarative.spec, rubygem-dig_rb.spec, rubygem-digest-crc.spec, rubygem-domain_name.spec, rubygem-faraday-net_http.spec, rubygem-faraday.spec, rubygem-ffi-compiler.spec, rubygem-ffi.spec, rubygem-fiber-annotation.spec, rubygem-fiber-local.spec, rubygem-fiber-storage.spec, rubygem-fluent-plugin-concat.spec, rubygem-fluent-plugin-gcs.spec, rubygem-fluent-plugin-kubernetes_metadata_filter.spec, rubygem-fluent-plugin-remote_syslog.spec, rubygem-fluent-plugin-s3.spec, rubygem-fluent-plugin-systemd.spec, rubygem-fluent-plugin-vmware-loginsight.spec, rubygem-fluentd.spec, rubygem-google-apis-core.spec, rubygem-google-apis-iamcredentials_v1.spec, rubygem-google-apis-storage_v1.spec, rubygem-google-cloud-core.spec, rubygem-google-cloud-env.spec, rubygem-google-cloud-errors.spec, rubygem-google-cloud-storage.spec, rubygem-google-logging-utils.spec, rubygem-googleauth.spec, rubygem-highline.spec, rubygem-hpricot.spec, rubygem-http-accept.spec, rubygem-http-cookie.spec, rubygem-http-form_data.spec, rubygem-http-parser.spec, rubygem-http.spec, rubygem-http_parser.rb.spec, rubygem-httpclient.spec, rubygem-i18n.spec, rubygem-io-endpoint.spec, rubygem-io-event.spec, rubygem-io-stream.spec, rubygem-jmespath.spec, rubygem-jsonpath.spec, rubygem-jwt.spec, rubygem-kubeclient.spec, rubygem-libxml-ruby.spec, rubygem-llhttp-ffi.spec, rubygem-lru_redux.spec, rubygem-metrics.spec, rubygem-mime-types-data.spec, rubygem-mime-types.spec, rubygem-mini_mime.spec, rubygem-mini_portile2.spec, rubygem-msgpack.spec, rubygem-multi_json.spec, rubygem-mustache.spec, rubygem-net-http.spec, rubygem-netrc.spec, rubygem-nio4r.spec, rubygem-nokogiri.spec, rubygem-oj.spec, rubygem-optimist.spec, rubygem-os.spec, rubygem-protocol-hpack.spec, rubygem-protocol-http.spec, rubygem-protocol-http1.spec, rubygem-protocol-http2.spec, rubygem-public_suffix.spec, rubygem-rbvmomi.spec, rubygem-rdiscount.spec, rubygem-recursive-open-struct.spec, rubygem-remote_syslog_sender.spec, rubygem-representable.spec, rubygem-rest-client.spec, rubygem-retriable.spec, rubygem-ronn.spec, rubygem-rubyzip.spec, rubygem-serverengine.spec, rubygem-sigdump.spec, rubygem-signet.spec, rubygem-strptime.spec, rubygem-syslog_protocol.spec, rubygem-systemd-journal.spec, rubygem-terminal-table.spec, rubygem-thread_safe.spec, rubygem-timers.spec, rubygem-traces.spec, rubygem-trailblazer-option.spec, rubygem-trollop.spec, rubygem-tzinfo-data.spec, rubygem-tzinfo.spec, rubygem-uber.spec, rubygem-unf.spec, rubygem-unf_ext.spec, rubygem-unicode-display_width.spec, rubygem-unicode-emoji.spec, rubygem-webrick.spec, rubygem-yajl-ruby.spec, runc.spec, runit.spec, rust.spec, s3fs-fuse.spec, samba-client.spec, scons.spec, selinux-policy.spec, selinux-python.spec, semodule-utils.spec, sendmail.spec, setools.spec, sg3_utils.spec, spirv-headers.spec, spirv-llvm-translator.spec, spirv-tools.spec, squid.spec, sssd.spec, stalld.spec, stig-hardening.spec, strace.spec, strongswan.spec, stunnel.spec, suricata.spec, sysdig.spec, syslog-ng.spec, systemd.spec, systemtap.spec, tcpdump.spec, tdnf.spec, telegraf.spec, timescaledb14.spec, timescaledb15.spec, tinycdb.spec, toybox.spec, tpm2-pkcs11.spec, tpm2-pytss.spec, trace-cmd.spec, traceroute.spec, tuna.spec, tuned.spec, u-boot.spec, userspace-rcu.spec, util-linux.spec, uwsgi.spec, vim.spec, vsftpd.spec, vulkan-loader.spec, xcb-proto.spec, xerces-c.spec, xmlto.spec, xorg-applications.spec, xorg-fonts.spec, xtrans.spec |
| VMware-internal Source0 URL (not publicly resolvable) | 🔵 | 18 | abupdate.spec, ant-contrib.spec, basic.spec, build-essential.spec, ca-certificates.spec, distrib-compat.spec, docker-vsock.spec, fipsify.spec, grub2-theme.spec, initramfs.spec, minimal.spec, photon-iso-config.spec, photon-release.spec, photon-repos.spec, photon-upgrade.spec, rubygem-async-io.spec, shim-signed.spec, stig-hardening.spec |


# Photon OS URL Health - cross-branch matrix

## Spec-matrix — issue applicability per branch

**215** packages with at least one issue across 7 branches.

Cell legend: severity colour + issue category number(s) — 🔴 High (1,2,3) · 🟠 Medium (4,5,6,7) · 🟡 Low-Medium (8) · 🟢 present & URL health OK · ⚪ not carried · 📌 vendor-pinned subrelease (non-issue) · 🔵 VMware-internal Source0 (non-issue).

| Spec | 4.0 | 5.0 | 5.0/SPECS/90 | 5.0/SPECS/91 | 6.0 | common | dev | master | main | main/SPECS/90 | main/SPECS/91 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 7zip.spec | ⚪ | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| ModemManager.spec | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | ⚪ | 📌 | ⚪ |
| PyPAM.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| WALinuxAgent.spec | 🟠6 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| abseil-cpp.spec | 🟠6 | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| alternatives.spec | ⚪ | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟡8 | ⚪ | ⚪ |
| apparmor.spec | 🟠7 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | ⚪ | 📌 |
| audit.spec | 🟢 | 🟠6 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| bluez-tools.spec | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | ⚪ | 📌 | ⚪ |
| bridge-utils.spec | 🟠7 | ⚪ | 📌 | ⚪ | 🟢 | ⚪ | 🟠6 | 🟢 | ⚪ | ⚪ | 📌 |
| c-rest-engine.spec | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| cairo.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| capstone.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| cdrkit.spec | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| chromium.spec | 🔴1 | 🔴1 | ⚪ | ⚪ | 🔴1 | ⚪ | 🔴1 | 🔴1 | 🔴1 | ⚪ | ⚪ |
| clang.spec | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | ⚪ | ⚪ | 📌 |
| cloud-network-setup.spec | 🟡8 | 🟡8 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| containers-common.spec | 🟠5 | 🟠5 | 📌 | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| copenapi.spec | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| cracklib.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠6 | ⚪ | 📌 |
| crash.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| cronie.spec | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| cryptsetup.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| ctags.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟠7 | 🟢 | ⚪ | 📌 |
| cve-check-tool.spec | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| cyrus-sasl.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ |
| dbus-python.spec | 🟡8 | 🟢 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟢 | ⚪ | 📌 |
| dcerpc.spec | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| dhcp.spec | 🔴3 | ⚪ | 📌 | ⚪ | 🔴3 | ⚪ | 🟡8 | 🟡8 | ⚪ | ⚪ | 📌 |
| distcc.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| dnsmasq.spec | 🟠5 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| docker-buildx.spec | 🟢 | 🟠6 | 📌 | ⚪ | 🟢 | ⚪ | ⚪ | ⚪ | 🟢 | ⚪ | 📌 |
| dool.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠6 | ⚪ | 📌 |
| dovecot-pigeonhole.spec | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| dovecot.spec | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| dracut.spec | 🟢 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | 📌 | ⚪ |
| dtb-raspberrypi.spec | 🟠5 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| efivar.spec | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| elixir.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ |
| erlang-sd_notify.spec | 🟢 | 🟠6 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| eventlog.spec | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | 📌 | ⚪ |
| expat.spec | 🟠6 | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| fakeroot.spec | ⚪ | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| fcgi.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| filesystem.spec | 🔴3 | 🔴3 | ⚪ | ⚪ | 🔴3 | ⚪ | 🟠6 | 🟠6 | 🔴3 | ⚪ | ⚪ |
| finger.spec | 🔴3 | ⚪ | 📌 | ⚪ | 🔴3 | ⚪ | 🔴3 | 🔴3 | 🔴3 | ⚪ | ⚪ |
| font-util.spec | 🟡8 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| fontconfig.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| fping.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| fuse-overlayfs-snapshotter.spec | 🟢 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| fuse3.spec | 🟢 | 🟠6 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| git.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| glide.spec | 🟠6 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| glog.spec | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| google-compute-engine.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | ⚪ |
| govmomi.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| gst-plugins-bad.spec | 🟠5 | ⚪ | 📌 | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| gtk3.spec | 🟢 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| haproxy.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠7 | 🟠7 | 🟢 | ⚪ | ⚪ |
| heapster.spec | 🟡8 | 🟡8 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| hiredis.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | 📌 | ⚪ |
| http-parser.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| i2c-tools.spec | 🟢 | 🟠6 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| iana-etc.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟠6 | 🟠6 | 🟢 | ⚪ | ⚪ |
| ibmtpm.spec | 🟢 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | ⚪ | 📌 |
| icu.spec | 🟡8 | 🟡8 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | 📌 |
| iotop.spec | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | 📌 |
| iputils.spec | 🟠7 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟠7 | 🟠7 | 🟢 | ⚪ | 📌 |
| ipvsadm.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ |
| jemalloc.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟠6 | 🟢 | ⚪ | ⚪ |
| json_spirit.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| kbd.spec | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| kexec-tools.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ |
| keyutils.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ |
| kmod.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| kubernetes-dashboard.spec | 🟡8 | 🟡8 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | 📌 |
| lapack.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| leveldb.spec | 🟠7 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libXScrnSaver.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXau.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXcomposite.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXdamage.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXdmcp.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXext.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXfixes.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXfont2.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXi.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXrandr.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXrender.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXt.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libXtst.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libbsd.spec | ⚪ | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| libcap-ng.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟠6 | 🟢 | ⚪ | 📌 |
| libclc.spec | ⚪ | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 📌 |
| libdaemon.spec | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ |
| libdisplay-info.spec | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ |
| libdrm.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libfastjson.spec | 🟠7 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠7 | 🟠7 | 🟢 | ⚪ | ⚪ |
| libfido2.spec | ⚪ | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠6 | ⚪ | ⚪ |
| libfontenc.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libmspack.spec | 🟠5 | 🟠5 | 📌 | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | 📌 |
| libnss-ato.spec | 🟠6 | 🟠6 | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| libnvme.spec | ⚪ | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| libpciaccess.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libqmi.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libslirp.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libtar.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| libtirpc.spec | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| libunwind.spec | 🟢 | 🟠7 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libwebp.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libxml2.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| libxslt.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| libyang.spec | 🟢 | 🟠6 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| lightstep-tracer-cpp.spec | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| linux-api-headers.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠6 | ⚪ | ⚪ |
| linux-esx.spec | 🟢 | 🟠5 | ⚪ | 📌 | 🟢 | ⚪ | 🟢 | 🟢 | 🟠6 | ⚪ | 📌 |
| linux.spec | 🟠5 | 🟠5 | ⚪ | 📌 | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟢 | ⚪ | 📌 |
| lldb.spec | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | ⚪ | ⚪ | 📌 |
| llvm.spec | 🟠7 | 🟢 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟢 | ⚪ | 📌 |
| log4cplus.spec | ⚪ | 🔴2 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| log4cpp.spec | 🟠6 | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| lshw.spec | 🟠5 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| lsof.spec | 🟠6 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| lxcfs.spec | 🟠7 | 🟠6 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| lzo.spec | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | 📌 |
| mdadm.spec | ⚪ | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | 📌 | ⚪ |
| mkinitcpio.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟠5 | 🟢 | ⚪ | 📌 |
| mokutil.spec | ⚪ | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ |
| motd.spec | 🟠5 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| mozjs.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| mpfr.spec | 🟢 | 🟠6 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| ncurses.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠6 | ⚪ | ⚪ |
| ndctl.spec | 🟠6 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| ndsend.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| netkit-telnet.spec | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | ⚪ | 📌 | ⚪ |
| netmgmt.spec | 🟠5 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| nghttp2.spec | 🟢 | 🟠6 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| nss.spec | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🔴3 | 🔴3 | 🟠7 | ⚪ | ⚪ |
| ntp.spec | 🟢 | ⚪ | 📌 | ⚪ | 🟢 | ⚪ | 🟠5 | 🟢 | ⚪ | 📌 | ⚪ |
| open-sans-fonts.spec | 🟠6 | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| open-vm-tools.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| openjdk25.spec | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ |
| openresty.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| openssh.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| pcre.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| pcstat.spec | 🟠5 | 🟠5 | 📌 | ⚪ | 🟡8 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| perftest.spec | 🟢 | 🟠6 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| perl-Clone.spec | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | ⚪ |
| perl-Data-Dump.spec | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | ⚪ |
| perl-IPC-Run.spec | 🟠6 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟠6 | 🟠6 | 🟢 | ⚪ | ⚪ |
| perl-List-MoreUtils.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| perl-Path-Class.spec | 🟠6 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| perl-URI.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| perl-libintl.spec | 🟢 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| perl.spec | 🟢 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| pgaudit13.spec | 🟠7 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| pgaudit14.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠6 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| pgaudit15.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| pgaudit16.spec | ⚪ | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| pgaudit17.spec | ⚪ | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ |
| pmd-ng.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| polkit.spec | 🟢 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| popt.spec | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| proto.spec | 🟠5 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| pth.spec | 🟠6 | ⚪ | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | ⚪ | 📌 | ⚪ |
| python-argparse.spec | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | ⚪ | ⚪ | 📌 |
| python-atomicwrites.spec | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | ⚪ | 📌 | ⚪ |
| python-google-auth.spec | ⚪ | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| python-ipaddr.spec | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟡8 | 🟡8 | ⚪ | ⚪ | ⚪ |
| python-lockfile.spec | 🟡8 | ⚪ | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | 📌 |
| python-pam.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| python-pycodestyle.spec | 🟡8 | 🟡8 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | 📌 |
| python-terminaltables.spec | ⚪ | 🟡8 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | 📌 |
| python-vcs-versioning.spec | ⚪ | 🟠7 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠7 | ⚪ | ⚪ |
| python3-Pygments.spec | ⚪ | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟡8 | ⚪ | ⚪ |
| python3-gcovr.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | 🟢 | ⚪ | 📌 |
| python3-hatchling.spec | ⚪ | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | ⚪ | ⚪ |
| python3-trove-classifiers.spec | ⚪ | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟡8 | ⚪ | ⚪ |
| python3-wheel.spec | ⚪ | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟡8 | ⚪ | ⚪ |
| qemu.spec | ⚪ | 🟠7 | 📌 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠7 | ⚪ | 📌 |
| raspberrypi-firmware.spec | 🔴1 | 🔴1 | ⚪ | ⚪ | 🔴1 | ⚪ | 🔴1 | 🔴1 | 🔴1 | ⚪ | ⚪ |
| rdma-core.spec | 🟢 | 🟠6 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | 📌 |
| re2.spec | 🟠5 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| rrdtool.spec | 🟢 | 🟠6 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| runc.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟠6 | 🟢 | ⚪ | 📌 |
| scons.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟡8 | 🟡8 | 🟠7 | ⚪ | 📌 |
| sendmail.spec | 🔴3 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🔴3 | 🔴3 | 🟢 | 📌 | ⚪ |
| shadow.spec | 🟠6 | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| snoopy.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟠5 | 🟢 | ⚪ | ⚪ |
| socat.spec | 🟠5 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| spirv-headers.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| spirv-tools.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | 📌 |
| sqlite2.spec | 🟡8 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| syslinux.spec | 🟠5 | 🟠5 | ⚪ | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | 🟠5 | ⚪ | ⚪ |
| systemd.spec | 🟢 | 🟠5 | 📌 | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟠5 | 📌 | ⚪ |
| tiptop.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| tmux.spec | 🟠5 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| tzdata.spec | 🟠6 | 🟠6 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | 🟠6 | ⚪ | ⚪ |
| u-boot.spec | 🟢 | ⚪ | 📌 | ⚪ | 🟠5 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| ulogd.spec | 🔴3 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| unixODBC.spec | 🟠7 | 🟠7 | ⚪ | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| urw-fonts.spec | 🟠5 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ |
| util-macros.spec | 🟡8 | 🟡8 | ⚪ | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| vulkan-loader.spec | 🟢 | 🟢 | 📌 | ⚪ | 🟢 | ⚪ | 🟠6 | 🟢 | 🟢 | ⚪ | 📌 |
| vulkan-tools.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| wayland-protocols.spec | 🟠7 | 🟠7 | 📌 | ⚪ | 🟠7 | ⚪ | 🟠7 | 🟠7 | 🟠7 | ⚪ | ⚪ |
| xinetd.spec | 🟠6 | ⚪ | ⚪ | ⚪ | ⚪ | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | ⚪ |
| xorg-applications.spec | 🟠6 | ⚪ | 📌 | ⚪ | 🟠6 | ⚪ | 🟠6 | 🟠6 | ⚪ | ⚪ | 📌 |
| xorg-fonts.spec | 🟠5 | ⚪ | 📌 | ⚪ | 🟠5 | ⚪ | 🟠5 | 🟠5 | ⚪ | ⚪ | 📌 |
| xorriso.spec | 🟠6 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| xtrans.spec | 🟡8 | 🟢 | 📌 | ⚪ | 🟡8 | ⚪ | 🟡8 | 🟡8 | 🟡8 | ⚪ | ⚪ |
| yaml-cpp.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| zookeeper.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟠6 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |
| zsh.spec | 🟢 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟠6 | 🟢 | 🟢 | ⚪ | ⚪ |
| zstd.spec | 🟠6 | 🟢 | ⚪ | ⚪ | 🟢 | ⚪ | 🟢 | 🟢 | 🟢 | ⚪ | ⚪ |

## Issue categories — affected packages

| # | Issue Category | Severity | Packages | Affected specs |
|---|---|---|---|---|
| 1 | Source URL blank / macro unresolved (UrlHealth=blank) | 🔴 High | 2 | chromium.spec, raspberrypi-firmware.spec |
| 2 | URL substitution unfinished | 🔴 High | 1 | log4cplus.spec |
| 3 | Source URL unreachable (UrlHealth=0) | 🔴 High | 11 | 7zip.spec, PyPAM.spec, cdrkit.spec, dhcp.spec, fcgi.spec, filesystem.spec, finger.spec, ndsend.spec, nss.spec, sendmail.spec, ulogd.spec |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 🟠 Medium | 31 | apparmor.spec, containers-common.spec, dnsmasq.spec, dracut.spec, dtb-raspberrypi.spec, fuse-overlayfs-snapshotter.spec, gst-plugins-bad.spec, ibmtpm.spec, libmspack.spec, libqmi.spec, linux-esx.spec, linux.spec, lshw.spec, mdadm.spec, mkinitcpio.spec, motd.spec, netmgmt.spec, ntp.spec, pcstat.spec, perl-libintl.spec, perl.spec, proto.spec, re2.spec, snoopy.spec, socat.spec, syslinux.spec, systemd.spec, tmux.spec, u-boot.spec, urw-fonts.spec, xorg-fonts.spec |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 🟠 Medium | 86 | WALinuxAgent.spec, abseil-cpp.spec, audit.spec, bridge-utils.spec, cairo.spec, capstone.spec, cracklib.spec, cryptsetup.spec, cyrus-sasl.spec, distcc.spec, docker-buildx.spec, dool.spec, dovecot-pigeonhole.spec, dovecot.spec, elixir.spec, erlang-sd_notify.spec, eventlog.spec, expat.spec, filesystem.spec, fping.spec, fuse3.spec, git.spec, glide.spec, google-compute-engine.spec, gtk3.spec, hiredis.spec, i2c-tools.spec, iana-etc.spec, iotop.spec, ipvsadm.spec, jemalloc.spec, json_spirit.spec, kexec-tools.spec, keyutils.spec, kmod.spec, lapack.spec, libbsd.spec, libcap-ng.spec, libdaemon.spec, libdisplay-info.spec, libfido2.spec, libnss-ato.spec, libnvme.spec, libwebp.spec, libxslt.spec, libyang.spec, linux-api-headers.spec, linux-esx.spec, log4cpp.spec, lsof.spec, lxcfs.spec, lzo.spec, mokutil.spec, mpfr.spec, ncurses.spec, ndctl.spec, netkit-telnet.spec, nghttp2.spec, open-sans-fonts.spec, openjdk25.spec, openresty.spec, perftest.spec, perl-Clone.spec, perl-Data-Dump.spec, perl-IPC-Run.spec, perl-Path-Class.spec, pgaudit14.spec, pmd-ng.spec, pth.spec, python-pam.spec, python3-gcovr.spec, python3-hatchling.spec, rdma-core.spec, rrdtool.spec, runc.spec, shadow.spec, tiptop.spec, tzdata.spec, vulkan-loader.spec, xinetd.spec, xorg-applications.spec, xorriso.spec, yaml-cpp.spec, zookeeper.spec, zsh.spec, zstd.spec |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 🟠 Medium | 46 | ModemManager.spec, apparmor.spec, bridge-utils.spec, clang.spec, cronie.spec, ctags.spec, dtb-raspberrypi.spec, efivar.spec, fontconfig.spec, glog.spec, govmomi.spec, haproxy.spec, iputils.spec, kbd.spec, leveldb.spec, libclc.spec, libfastjson.spec, libtirpc.spec, libunwind.spec, libxml2.spec, lldb.spec, llvm.spec, lxcfs.spec, mozjs.spec, nss.spec, open-vm-tools.spec, openssh.spec, perl-List-MoreUtils.spec, perl-URI.spec, pgaudit13.spec, pgaudit14.spec, pgaudit15.spec, pgaudit16.spec, pgaudit17.spec, polkit.spec, popt.spec, pth.spec, python-google-auth.spec, python-vcs-versioning.spec, qemu.spec, scons.spec, spirv-headers.spec, spirv-tools.spec, unixODBC.spec, vulkan-tools.spec, wayland-protocols.spec |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 🟡 Low-Medium | 51 | alternatives.spec, bluez-tools.spec, c-rest-engine.spec, cloud-network-setup.spec, copenapi.spec, crash.spec, cve-check-tool.spec, dbus-python.spec, dcerpc.spec, dhcp.spec, fakeroot.spec, font-util.spec, heapster.spec, http-parser.spec, icu.spec, kubernetes-dashboard.spec, libXScrnSaver.spec, libXau.spec, libXcomposite.spec, libXdamage.spec, libXdmcp.spec, libXext.spec, libXfixes.spec, libXfont2.spec, libXi.spec, libXrandr.spec, libXrender.spec, libXt.spec, libXtst.spec, libdrm.spec, libfontenc.spec, libpciaccess.spec, libslirp.spec, libtar.spec, lightstep-tracer-cpp.spec, motd.spec, pcre.spec, pcstat.spec, python-argparse.spec, python-atomicwrites.spec, python-ipaddr.spec, python-lockfile.spec, python-pycodestyle.spec, python-terminaltables.spec, python3-Pygments.spec, python3-trove-classifiers.spec, python3-wheel.spec, scons.spec, sqlite2.spec, util-macros.spec, xtrans.spec |

## Non-issue categories (informational — not counted as issues)

| Category | Marker | Packages | Specs |
|---|---|---|---|
| Vendor-pinned subrelease (frozen for a Photon sub-release) | 📌 | 722 | GConf.spec, ImageMagick.spec, Linux-PAM.spec, ModemManager.spec, WALinuxAgent.spec, XML-Parser.spec, amdvlk.spec, ansible-community-general.spec, ansible-posix.spec, ansible.spec, ant-contrib.spec, apparmor.spec, apr-util.spec, argon2.spec, asciidoc3.spec, at-spi2-core.spec, atk.spec, audit.spec, aufs-util.spec, autogen.spec, backward-cpp.spec, bash-completion.spec, bash.spec, bazel.spec, bcc.spec, bluez-tools.spec, bluez.spec, bpftrace.spec, bridge-utils.spec, btrfs-progs.spec, bubblewrap.spec, build-essential.spec, c-ares.spec, cairo.spec, calico-bgp-daemon.spec, calico-libnetwork.spec, calico.spec, checkpolicy.spec, chkconfig.spec, chrpath.spec, clang.spec, cloud-init.spec, cloud-network-setup.spec, cni.spec, containerd.spec, containers-common.spec, coredns.spec, cppcheck.spec, cppunit.spec, cracklib.spec, createrepo_c.spec, cri-tools.spec, crun.spec, cryptsetup.spec, ctags.spec, curl.spec, cve-check-tool.spec, cython3.spec, dbus-broker.spec, dbus-python.spec, dbus.spec, device-mapper-multipath.spec, dhcp.spec, distcc.spec, dnsmasq.spec, docbook-xml.spec, docbook-xsl.spec, docker-buildx.spec, docker-compose.spec, docker-py.spec, docker-pycreds.spec, docker.spec, dool.spec, dotnet-runtime.spec, dotnet-sdk.spec, doxygen.spec, dracut.spec, drpm.spec, dtb-raspberrypi.spec, e2fsprogs.spec, etcd.spec, ethtool.spec, eventlog.spec, fail2ban.spec, falco.spec, file.spec, findutils.spec, finger.spec, fio.spec, flannel.spec, fontconfig.spec, fping.spec, frr.spec, fsarchiver.spec, fuse-overlayfs-snapshotter.spec, fuse-overlayfs.spec, fuse.spec, fuse3.spec, gawk.spec, gcc.spec, gdb.spec, gdk-pixbuf.spec, geoip-api-c.spec, git-lfs.spec, git.spec, glib-networking.spec, glib.spec, glibc.spec, glibmm.spec, glide.spec, glslang.spec, gmp.spec, gnome-common.spec, gnutls.spec, go-md2man.spec, go.spec, gobgp.spec, gobject-introspection.spec, google-guest-agent.spec, govmomi.spec, gpsd.spec, graphene.spec, grep.spec, gssntlmssp.spec, gst-plugins-bad.spec, gstreamer-plugins-base.spec, gstreamer.spec, gtk-doc.spec, gtk3.spec, haproxy-dataplaneapi.spec, harfbuzz.spec, heapster.spec, hiredis.spec, hyperscan.spec, iana-etc.spec, ibmtpm.spec, icu.spec, influxdb.spec, initscripts.spec, inotify-tools.spec, iotop.spec, iproute2.spec, iptables.spec, iputils.spec, itstool.spec, jc.spec, jq.spec, json-glib.spec, jsoncpp.spec, kafka.spec, kapacitor.spec, keepalived.spec, kube-bench.spec, kubernetes-dashboard.spec, kubernetes-dns.spec, kubernetes-metrics-server.spec, kubernetes.spec, lapack.spec, lasso.spec, libbpf.spec, libcap-ng.spec, libcap.spec, libclc.spec, libconfig.spec, libdaemon.spec, libdnet.spec, libecap.spec, libglvnd.spec, libgudev.spec, libical.spec, libldb.spec, libmbim.spec, libmodulemd.spec, libmspack.spec, libnetfilter_conntrack.spec, libnftnl.spec, libnsl.spec, libnss-ato.spec, libnvme.spec, libpsl.spec, libpwquality.spec, librelp.spec, librepo.spec, libretls.spec, libselinux-python3.spec, libselinux.spec, libsemanage.spec, libsepol.spec, libsolv.spec, libsoup.spec, libssh2.spec, libtalloc.spec, libtdb.spec, libteam.spec, libtevent.spec, libtraceevent.spec, libtracefs.spec, libvirt.spec, libxcb.spec, libxcrypt.spec, libxkbcommon.spec, libxml2.spec, libxslt.spec, lighttpd.spec, linux-esx.spec, linux-rt.spec, linux-tools-90.spec, linux-tools.spec, linux.spec, linuxptp.spec, lldb.spec, lldpad.spec, llvm.spec, lttng-tools.spec, lttng-ust.spec, lvm2.spec, lxcfs.spec, lzo.spec, mariadb.spec, mdadm.spec, mercurial.spec, mesa.spec, meson.spec, minimal.spec, mkinitcpio.spec, monitoring-plugins.spec, mozjs.spec, mpc.spec, mpfr.spec, msr-tools.spec, mysql.spec, ncurses.spec, nerdctl.spec, net-snmp.spec, net-tools.spec, netcat.spec, netkit-telnet.spec, network-event-broker.spec, nfs-utils.spec, nftables.spec, nghttp2.spec, nginx-ingress.spec, nginx.spec, nicstat.spec, ninja-build.spec, nmap.spec, nodejs.spec, ntp.spec, ntpsec.spec, nvme-cli.spec, oniguruma.spec, open-vm-tools.spec, open-vmdk.spec, openipmi.spec, openjdk11.spec, openjdk17.spec, openjdk21.spec, openldap.spec, openscap.spec, openssh.spec, openssl-fips-provider.spec, openssl.spec, openvswitch.spec, ostree.spec, pam_tacplus.spec, pandoc.spec, pango.spec, pcstat.spec, perl-CGI.spec, perl-Canary-Stability.spec, perl-Config-IniFiles.spec, perl-Crypt-SSLeay.spec, perl-DBD-SQLite.spec, perl-DBI.spec, perl-DBIx-Simple.spec, perl-Data-Validate-IP.spec, perl-Exporter-Tiny.spec, perl-File-HomeDir.spec, perl-File-Which.spec, perl-IO-Socket-SSL.spec, perl-IPC-Run.spec, perl-JSON-Any.spec, perl-JSON-XS.spec, perl-JSON.spec, perl-List-MoreUtils.spec, perl-Module-Build.spec, perl-Module-Install.spec, perl-Module-ScanDeps.spec, perl-Net-SSLeay.spec, perl-NetAddr-IP.spec, perl-Object-Accessor.spec, perl-Parse-Yapp.spec, perl-Path-Class.spec, perl-Perl4-CoreLibs.spec, perl-TermReadKey.spec, perl-Try-Tiny.spec, perl-Types-Serialiser.spec, perl-URI.spec, perl-WWW-Curl.spec, perl-YAML-Tiny.spec, perl-YAML.spec, perl-common-sense.spec, perl-libintl.spec, perl.spec, pgaudit13.spec, pgaudit14.spec, pgaudit15.spec, pgbackrest.spec, photon-os-installer.spec, photon-repos.spec, pmd-ng.spec, podman.spec, policycoreutils.spec, polkit.spec, postgresql10.spec, postgresql13.spec, postgresql14.spec, postgresql15.spec, postgresql16.spec, postgresql17.spec, powershell.spec, procmail.spec, procps-ng.spec, protobuf.spec, pth.spec, pycurl.spec, python-CacheControl.spec, python-ConcurrentLogHandler.spec, python-Js2Py.spec, python-M2Crypto.spec, python-PyHamcrest.spec, python-PyJWT.spec, python-PyNaCl.spec, python-PyYAML.spec, python-Pygments.spec, python-Twisted.spec, python-alabaster.spec, python-altgraph.spec, python-appdirs.spec, python-argparse.spec, python-asn1crypto.spec, python-atomicwrites.spec, python-attrs.spec, python-automat.spec, python-autopep8.spec, python-babel.spec, python-backports.ssl_match_hostname.spec, python-backports_abc.spec, python-bcrypt.spec, python-binary.spec, python-boto.spec, python-boto3.spec, python-botocore.spec, python-cachetools.spec, python-cassandra-driver.spec, python-certifi.spec, python-cffi.spec, python-chardet.spec, python-charset-normalizer.spec, python-click.spec, python-configobj.spec, python-configparser.spec, python-constantly.spec, python-coverage.spec, python-cqlsh.spec, python-cryptography.spec, python-daemon.spec, python-dateutil.spec, python-decorator.spec, python-deepmerge.spec, python-defusedxml.spec, python-distlib.spec, python-distro.spec, python-dnspython.spec, python-docopt.spec, python-docutils.spec, python-ecdsa.spec, python-email-validator.spec, python-etcd.spec, python-ethtool.spec, python-filelock.spec, python-flit-core.spec, python-fuse.spec, python-geomet.spec, python-gevent.spec, python-google-auth.spec, python-graphviz.spec, python-greenlet.spec, python-hatch-fancy-pypi-readme.spec, python-hatch-vcs.spec, python-hatchling.spec, python-hyperlink.spec, python-hypothesis.spec, python-idna.spec, python-imagesize.spec, python-importlib-metadata.spec, python-incremental.spec, python-iniconfig.spec, python-iniparse.spec, python-ipaddress.spec, python-jinja2.spec, python-jmespath.spec, python-jsonpatch.spec, python-jsonpointer.spec, python-jsonschema.spec, python-kubernetes.spec, python-linux-procfs.spec, python-lockfile.spec, python-looseversion.spec, python-lxml.spec, python-mako.spec, python-markupsafe.spec, python-mistune.spec, python-mock.spec, python-more-itertools.spec, python-msgpack.spec, python-ndg-httpsclient.spec, python-netaddr.spec, python-netifaces.spec, python-networkx.spec, python-nocasedict.spec, python-nocaselist.spec, python-ntplib.spec, python-numpy.spec, python-oauthlib.spec, python-packaging.spec, python-pam.spec, python-paramiko.spec, python-pathspec.spec, python-pbr.spec, python-pexpect.spec, python-pg8000.spec, python-pika.spec, python-pkgconfig.spec, python-platformdirs.spec, python-pluggy.spec, python-ply.spec, python-portalocker.spec, python-prettytable.spec, python-prometheus_client.spec, python-prompt_toolkit.spec, python-psutil.spec, python-psycopg2.spec, python-ptyprocess.spec, python-py.spec, python-pyOpenSSL.spec, python-pyasn1-modules.spec, python-pyasn1.spec, python-pycodestyle.spec, python-pycparser.spec, python-pycryptodome.spec, python-pycryptodomex.spec, python-pydantic.spec, python-pyflakes.spec, python-pygobject.spec, python-pyinstaller-hooks-contrib.spec, python-pyinstaller.spec, python-pyjsparser.spec, python-pyparsing.spec, python-pyrsistent.spec, python-pyserial.spec, python-pytest.spec, python-pytz-deprecation-shim.spec, python-pytz.spec, python-pyudev.spec, python-pyvim.spec, python-pyvmomi.spec, python-pywbem.spec, python-requests-oauthlib.spec, python-requests-toolbelt.spec, python-requests-unixsocket.spec, python-requests.spec, python-resolvelib.spec, python-rsa.spec, python-ruamel-yaml.spec, python-s3transfer.spec, python-schedutils.spec, python-scp.spec, python-scramp.spec, python-semantic-version.spec, python-service_identity.spec, python-setuptools-rust.spec, python-setuptools_scm.spec, python-simplejson.spec, python-six.spec, python-snowballstemmer.spec, python-sortedcontainers.spec, python-sphinx.spec, python-sphinxcontrib-applehelp.spec, python-sphinxcontrib-devhelp.spec, python-sphinxcontrib-htmlhelp.spec, python-sphinxcontrib-jsmath.spec, python-sphinxcontrib-qthelp.spec, python-sphinxcontrib-serializinghtml.spec, python-sqlalchemy.spec, python-systemd.spec, python-terminaltables.spec, python-toml.spec, python-tornado.spec, python-typing-extensions.spec, python-tzlocal.spec, python-ujson.spec, python-urllib3.spec, python-vcversioner.spec, python-versioningit.spec, python-virtualenv.spec, python-wcwidth.spec, python-webob.spec, python-websocket-client.spec, python-werkzeug.spec, python-wheel.spec, python-wrapt.spec, python-xmltodict.spec, python-yamlloader.spec, python-zipp.spec, python-zmq.spec, python-zope.event.spec, python-zope.interface.spec, python3-gcovr.spec, python3-pip.spec, python3-pyroute2.spec, python3-setuptools.spec, python3.spec, qemu.spec, rabbitmq-server.spec, rdma-core.spec, readline.spec, redis.spec, repmgr13.spec, repmgr14.spec, repmgr15.spec, rng-tools.spec, rootlesskit.spec, rpm-ostree.spec, rpm.spec, rpmdevtools.spec, rrdtool.spec, rsyslog.spec, rt-tests.spec, ruby.spec, rubygem-activesupport.spec, rubygem-addressable.spec, rubygem-async-http.spec, rubygem-async-io.spec, rubygem-async-pool.spec, rubygem-async.spec, rubygem-aws-eventstream.spec, rubygem-aws-partitions.spec, rubygem-aws-sdk-core.spec, rubygem-aws-sdk-kms.spec, rubygem-aws-sdk-s3.spec, rubygem-aws-sdk-sqs.spec, rubygem-aws-sigv4.spec, rubygem-backports.spec, rubygem-builder.spec, rubygem-bundler.spec, rubygem-concurrent-ruby.spec, rubygem-console.spec, rubygem-cool-io.spec, rubygem-declarative.spec, rubygem-dig_rb.spec, rubygem-digest-crc.spec, rubygem-domain_name.spec, rubygem-faraday-net_http.spec, rubygem-faraday.spec, rubygem-ffi-compiler.spec, rubygem-ffi.spec, rubygem-fiber-annotation.spec, rubygem-fiber-local.spec, rubygem-fiber-storage.spec, rubygem-fluent-plugin-concat.spec, rubygem-fluent-plugin-gcs.spec, rubygem-fluent-plugin-kubernetes_metadata_filter.spec, rubygem-fluent-plugin-remote_syslog.spec, rubygem-fluent-plugin-s3.spec, rubygem-fluent-plugin-systemd.spec, rubygem-fluent-plugin-vmware-loginsight.spec, rubygem-fluentd.spec, rubygem-google-apis-core.spec, rubygem-google-apis-iamcredentials_v1.spec, rubygem-google-apis-storage_v1.spec, rubygem-google-cloud-core.spec, rubygem-google-cloud-env.spec, rubygem-google-cloud-errors.spec, rubygem-google-cloud-storage.spec, rubygem-google-logging-utils.spec, rubygem-googleauth.spec, rubygem-highline.spec, rubygem-hpricot.spec, rubygem-http-accept.spec, rubygem-http-cookie.spec, rubygem-http-form_data.spec, rubygem-http-parser.spec, rubygem-http.spec, rubygem-http_parser.rb.spec, rubygem-httpclient.spec, rubygem-i18n.spec, rubygem-io-endpoint.spec, rubygem-io-event.spec, rubygem-io-stream.spec, rubygem-jmespath.spec, rubygem-jsonpath.spec, rubygem-jwt.spec, rubygem-kubeclient.spec, rubygem-libxml-ruby.spec, rubygem-llhttp-ffi.spec, rubygem-lru_redux.spec, rubygem-metrics.spec, rubygem-mime-types-data.spec, rubygem-mime-types.spec, rubygem-mini_mime.spec, rubygem-mini_portile2.spec, rubygem-msgpack.spec, rubygem-multi_json.spec, rubygem-mustache.spec, rubygem-net-http.spec, rubygem-netrc.spec, rubygem-nio4r.spec, rubygem-nokogiri.spec, rubygem-oj.spec, rubygem-optimist.spec, rubygem-os.spec, rubygem-protocol-hpack.spec, rubygem-protocol-http.spec, rubygem-protocol-http1.spec, rubygem-protocol-http2.spec, rubygem-public_suffix.spec, rubygem-rbvmomi.spec, rubygem-rdiscount.spec, rubygem-recursive-open-struct.spec, rubygem-remote_syslog_sender.spec, rubygem-representable.spec, rubygem-rest-client.spec, rubygem-retriable.spec, rubygem-ronn.spec, rubygem-rubyzip.spec, rubygem-serverengine.spec, rubygem-sigdump.spec, rubygem-signet.spec, rubygem-strptime.spec, rubygem-syslog_protocol.spec, rubygem-systemd-journal.spec, rubygem-terminal-table.spec, rubygem-thread_safe.spec, rubygem-timers.spec, rubygem-traces.spec, rubygem-trailblazer-option.spec, rubygem-trollop.spec, rubygem-tzinfo-data.spec, rubygem-tzinfo.spec, rubygem-uber.spec, rubygem-unf.spec, rubygem-unf_ext.spec, rubygem-unicode-display_width.spec, rubygem-unicode-emoji.spec, rubygem-webrick.spec, rubygem-yajl-ruby.spec, runc.spec, runit.spec, rust.spec, s3fs-fuse.spec, samba-client.spec, scons.spec, selinux-policy.spec, selinux-python.spec, semodule-utils.spec, sendmail.spec, setools.spec, sg3_utils.spec, shared-mime-info.spec, spirv-headers.spec, spirv-llvm-translator.spec, spirv-tools.spec, squid.spec, sssd.spec, stalld.spec, stig-hardening.spec, strace.spec, strongswan.spec, stunnel.spec, subversion.spec, suricata.spec, sysdig.spec, syslog-ng.spec, systemd.spec, systemtap.spec, tcpdump.spec, tdnf.spec, telegraf.spec, termshark.spec, timescaledb14.spec, timescaledb15.spec, tinycdb.spec, toybox.spec, tpm2-pkcs11.spec, tpm2-pytss.spec, trace-cmd.spec, traceroute.spec, tuna.spec, tuned.spec, u-boot.spec, unzip.spec, userspace-rcu.spec, util-linux.spec, uwsgi.spec, vim.spec, vsftpd.spec, vulkan-loader.spec, vulkan-tools.spec, wayland-protocols.spec, wayland.spec, wireshark.spec, xcb-proto.spec, xerces-c.spec, xmlsec1.spec, xmlstarlet.spec, xmlto.spec, xorg-applications.spec, xorg-fonts.spec, xtrans.spec, zip.spec, zlib.spec |
| VMware-internal Source0 URL (not publicly resolvable) | 🔵 | 16 | abupdate.spec, ant-contrib.spec, basic.spec, build-essential.spec, ca-certificates.spec, distrib-compat.spec, grub2-theme.spec, initramfs.spec, minimal.spec, photon-iso-config.spec, photon-release.spec, photon-repos.spec, photon-upgrade.spec, rubygem-async-io.spec, shim-signed.spec, stig-hardening.spec |


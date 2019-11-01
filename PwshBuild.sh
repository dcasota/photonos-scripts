#!/bin/sh

cd /

tdnf install -y \
	curl
	
tdnf install -y \
	tar \
	libunwind \
	userspace-rcu \
	lttng-ust \
	icu \
	dotnet-sdk \
	dotnet-runtime \
	psmisc \
	cmake \
	clang \
	git \		

git clone https://github.com/vmware/photon.git


mkdir -p /photon/SPECS/powershell/Powershell-6.1.1
cd /photon/SPECS/powershell/Powershell-6.1.1

curl -O -J -L https://github.com/PowerShell/PowerShell/releases/download/v6.1.1/powershell-6.1.1-linux-x64.tar.gz
cp powershell-6.1.1-linux-x64.tar.gz Powershell-6.1.1.tar.gz
rm powershell-6.1.1-linux-x64.tar.gz
tar -xzvf Powershell-6.1.1.tar.gz

# curl -O -J -L https://github.com/PowerShell/PowerShell/archive/v6.2.0-preview.2.tar.gz
# tar -xzvf PowerShell-6.2.0-preview.2.tar.gz

/photon/tools/scripts/build_spec.sh /photon/SPECS/powershell/powershell.spec


# TODO Cleanup

# 1. Create sandbox
#         Use local build template image OK
# 2. Prepare build environment
#         Create source folder OK
#         Copy sources from /photon/SPECS/powershell OK
#         Install build requirements OK
# 3. Build
#         Run rpmbuild FAIL
# Sandbox is preserved for analisys. Use 'docker exec -it build_spec /bin/bash'
# Build failed. See /photon/SPECS/powershell/stage/LOGS/powershell.log for full output
# 
# Installing/Updating: subversion-1.10.2-5.ph3.x86_64
# Installing/Updating: subversion-perl-1.10.2-5.ph3.x86_64
# Installing/Updating: git-2.23.0-1.ph3.x86_64
# Installing/Updating: dotnet-sdk-2.1.403-1.ph3.x86_64
# Installing/Updating: cmake-3.12.1-4.ph3.x86_64
# Installing/Updating: clang-6.0.1-1.ph3.x86_64
# Installing/Updating: psmisc-23.2-4.ph3.x86_64
# 
# Complete!
# error: Bad source: /usr/src/photon/SOURCES/powershell-6.1.1.tar.gz: No such file or directory
# 

# root@photonos [ /work/photon/SPECS/powershell/PowerShell-6.1.1 ]# docker exec -it build_spec /bin/bash
# root [ / ]# ls /usr/src/photon/SOURCES/
# PowerShell-6.1.1  PowerShell-6.2.0-preview.2  PowerShell-6.2.0-preview.2.tar.gz  build.sh  powershell-6.1.1.tar.gz  powershell.spec  stage
# root [ / ]# ls /var/tmp
# rpm-tmp.Fn1UQ3
# root [ / ]# cat /var/tmp/rpm-tmp.Fn1UQ3
# #!/bin/sh
# 
# RPM_SOURCE_DIR="/usr/src/photon/SOURCES"
# RPM_BUILD_DIR="/usr/src/photon/BUILD"
# RPM_OPT_FLAGS="-O2 -g"
# RPM_ARCH="x86_64"
# RPM_OS="linux"
# export RPM_SOURCE_DIR RPM_BUILD_DIR RPM_OPT_FLAGS RPM_ARCH RPM_OS
# RPM_DOC_DIR="/usr/share/doc"
# export RPM_DOC_DIR
# RPM_PACKAGE_NAME="powershell"
# RPM_PACKAGE_VERSION="6.1.1"
# RPM_PACKAGE_RELEASE="2.ph3"
# export RPM_PACKAGE_NAME RPM_PACKAGE_VERSION RPM_PACKAGE_RELEASE
# LANG=C
# export LANG
# unset CDPATH DISPLAY ||:
# RPM_BUILD_ROOT="/usr/src/photon/BUILDROOT/powershell-6.1.1-2.ph3.x86_64"
# export RPM_BUILD_ROOT
# 
# PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:/usr/lib/pkgconfig:/usr/share/pkgconfig"
# export PKG_CONFIG_PATH

# set -x
# umask 022
# cd "/usr/src/photon/BUILD"

# cd '/usr/src/photon/BUILD'
# rm -rf 'PowerShell-6.1.1'
# /bin/gzip -dc '/usr/src/photon/SOURCES/powershell-6.1.1.tar.gz' | /bin/tar --no-same-owner -xof -
# STATUS=$?
# if [ $STATUS -ne 0 ]; then
#   exit $STATUS
# fi
# cd 'PowerShell-6.1.1'
# /bin/chmod -Rf a+rX,u+w,g-w,o-w .
# 
# exit $?root [ / ]# exit
# exit
# root@photonos [ /work/photon/SPECS/powershell/PowerShell-6.1.1 ]#

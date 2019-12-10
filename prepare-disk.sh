#!/bin/sh

cd /root
tdnf install -y syslinux dosfstools glibc-iconv wget tar
tdnf install -y autoconf automake binutils diffutils gawk gcc glib-devel glibc-devel gzip libtool linux-api-headers make ncurses-devel sed util-linux-devel zlib-devel

# install Msdos tools for Linux
wget ftp://ftp.gnu.org/gnu/mtools/mtools-4.0.23.tar.gz
tar -xzvf mtools-4.0.23.tar.gz
cd ./mtools-4.0.23
./configure --disable-floppyd
make
make install

# fdisk

umount /dev/sdc1
umount /dev/sdc2

# delete partitions
# Press [d] to delete existing partitions. d 1 d 2 d
echo -e "d\n1\nd\n2\nd\nw" | fdisk /dev/sdc

# create partitions
# Press [o] to create a new empty DOS partition table.
# Press [n], [p] and press Enter 3 times to accept the default settings. This step creates a primary partition for you.
echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/sdc

# Press [t] to toggle the partition file system type.
# Press [c] to set the file system type to FAT32
# Press [a] to make the partition active.
# Press [w] to write the changes to disk.
echo -e "t\nc\nc\na\nw" | fdisk /dev/sdc


# Format
/sbin/mkfs.vfat -F 32 -n ESXI /dev/sdc1

# copy bootloader
/usr/bin/syslinux /dev/sdc1
cat /usr/share/syslinux/mbr.bin > /dev/sdc

# Download ISO
cd /root
curl -O -J -L https://downloads.dell.com/FOLDER05796977M/1/VMware-VMvisor-Installer-6.7.0.update03-14320388.x86_64-DellEMC_Customized-A00.iso

mkdir /usbdisk
mount /dev/sdc1 /usbdisk
mkdir /esxicd

mount -o loop /root/VMware-VMvisor-Installer-6.7.0.update03-14320388.x86_64-DellEMC_Customized-A00.iso /esxicd
cp -r /esxicd/* /usbdisk

mv /usbdisk/isolinux.cfg /usbdisk/syslinux.cfg
# vi /usbdisk/syslinux.cfg

umount /esxicd
rmdir /esxicd
umount /usbdisk
rmdir /usbdisk

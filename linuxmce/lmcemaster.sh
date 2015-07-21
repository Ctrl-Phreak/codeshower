#!/bin/bash
##################################################################
# This script creates an installable DVD iso from a base dd
# image file, specified as IMAGEFILE below. This currently 
# presumes that the video-wizard-videos package is in the same 
# directory. Please contact Jason l3droid@gmail.com with 
# problems/questions. This script is free under GNU2 license.
##################################################################
# About the boot process for the iso produced. Some startup scripts 
# are suspended and one is replaced to kill nbd directories and
# launch the dvd-installer.sh. After the install kde is overwritten
# as the default display manager on exit, as the install brings it 
# back. See http://wiki.linuxmce.org/index.php/Live_DVD for details

set -e

CDBOOTTYPE="ISOLINUX"
LIVECDURL="http://www.linuxmce.org"
IMAGEFILE=1004
VERSION=10
ARCH=i386

if [[ "$2" != "" ]]; then
	IMAGEFILE=$1
fi
CDLABEL="`echo $IMAGEFILE|cut -b1,2`.`echo $IMAGEFILE|cut -b3,4`"	

DDDIR=`mktemp -d $IMAGEFILE-dd.XXXXXXXXXX`
WORKDIR=`mktemp -d $IMAGEFILE-wrk.XXXXXXXXXX`
ISODIR=`mktemp -d $IMAGEFILE-iso.XXXXXXXXXX`
NEWINST="/root/new-installer"
DDMASTER="$DDDIR$NEWINST"
WORKMASTER="$WORKDIR$NEWINST"
CUSTOMISO="LMCE-$IMAGEFILE-`date +%Y%m%d%H%M`$2.iso"
LIVECDLABEL="LinuxMCE $CDLABEL Live CD"

### Mount the image and create some required directories in the temporary folders
mount -o loop $IMAGEFILE $DDDIR
mount none -t proc ${DDDIR}/proc
mount none -t devpts ${DDDIR}/dev/pts
mount none -t sysfs ${DDDIR}/sys
mkdir -p ${ISODIR}/{casper,isolinux,install,.disk}
mkdir -p ${DDDIR}/usr/sbin
mkdir -p ${DDDIR}/root/new-installer
mkdir -p ${WORKMASTER}/runners

# Remove fluffy references
sed -i 's/fluffybitch\.org/dcerouter\.org/g' ${DDDIR}/etc/postfix/main.cf
echo "dcerouter.org" > ${DDDIR}/etc/mailname
if [[ -f /etc/ipsec.d/certs/fluffybitch.orgCert.pem ]]; then
	rm /etc/ipsec.d/certs/fluffybitch.orgCert.pem
fi
if [[ -f /etc/ipsec.d/private/fluffybitch.orgKey.pem ]]; then
	rm /etc/ipsec.d/private/fluffybitch.orgKey.pem
fi

trap futureTrap EXIT
futureTrap () {
	mounted=$(mount | grep $IMAGEFILE-dd | grep none | awk '{print $3}')
	for mounts in $mounted; do umount -lf $mounts; done
	umount -lf `mount | grep $IMAGEFILE-dd | grep loop | awk '{print $3}'`
	sleep 1
	rm -r $DDDIR
	rm -r $WORKDIR
	rm -r $ISODIR	
}

echo "LinuxMCE will now be mastered to an iso image."
echo "Downloading tools and creating scripts"
if [[ $(dpkg-query -l squashfs-tools | grep "^ii" | awk '{print $2}') != "squashfs-tools" ]]; then 
	apt-get install -yf squashfs-tools
fi

#### Set temporary network file
# Create casper preboot file to automatically handle dual networking

cat <<EOL > ${ISODIR}/casper/firstnet
#!/bin/bash
chroot LC_ALL=C -c ". /root/usr/pluto/bin/dvd-installer.sh; FirstNetwork"
EOL
chmod +x ${ISODIR}/casper/firstnet


cat <<EOL > ${DDDIR}/etc/network/interfaces.temp 
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOL

# Create the dvd boot config menu	
cat <<EOL > ${ISODIR}/isolinux/isolinux.cfg
default vesamenu.c32
prompt 0
timeout 450

menu width 78
menu margin 14
menu rows 6
menu vshift 2
menu timeoutrow 12
menu tabmsgrow 13
menu background splash.png
menu title $LIVECDLABEL
menu color tabmsg 0 #fffc9306 #00fc9306 std
menu color timeout 0 #ff000000 #00fc9306 std
menu color border 0 #ffffffff #ee000000 std
menu color title 0 #ff00ff00 #ee000000 std
menu color sel 0 #ffffffff #fffc9306 std
menu color unsel 0 #ffffffff #ee000000 std
menu color hotkey 0 #ff00ff00 #ee000000 std
menu color hotsel 0 #ffffffff #85000000 std
#####menu color option  forground #ALPHA/R/G/B  background #ALPHA/R/G/B 

label live
  menu label Live - Boot LinuxMCE Live! from DVD
  kernel /casper/vmlinuz
  append preseed/file=/cdrom/preseed.cfg boot=casper initrd=/casper/initrd.gz quiet splash noeject noprompt --

label hybrid
  menu label Install LinuxMCE Hybrid - Core + MD
  kernel /casper/vmlinuz
  append preseed/file=/cdrom/preseed.cfg boot=casper only-ubiquity initrd=/casper/initrd.gz quiet splash noeject noprompt --

label core
  menu label Install LinuxMCE Core - Headless Core
  kernel /casper/vmlinuz
  append preseed/file=/cdrom/preseedco.cfg boot=casper only-ubiquity initrd=/casper/initrd.gz quiet splash noeject noprompt --

label xforcevesa
  menu label xforcevesa - boot Live in safe graphics mode
  kernel /casper/vmlinuz
  append preseed/file=/cdrom/preseed.cfg boot=casper xforcevesa initrd=/casper/initrd.gz quiet splash noeject noprompt --

label memtest
  menu label memtest - Run memtest
  kernel /isolinux/memtest
  append -

label hd
  menu label hd - boot the first hard disk
  localboot 0x80
append -
EOL

# Make hybrid preseed file
cat <<EOL > ${ISODIR}/preseed.cfg
tasksel tasksel/first multiselect
d-i pkgsel/install-language-support boolean false
d-i preseed/early_command string service mysql stop
#d-i finish-install/reboot_in_progress note
ubiquity ubiquity/success_command string bash /cdrom/install/postseed.sh
EOL
cp -pd ${ISODIR}/preseed.cfg ${ISODIR}/casper

# Make core only preseed file
cat <<EOL > ${ISODIR}/preseedco.cfg
tasksel tasksel/first multiselect
d-i pkgsel/install-language-support boolean false
d-i preseed/early_command string service mysql stop
ubiquity ubiquity/success_command string bash /cdrom/install/postseedco.sh
EOL
cp -pd ${ISODIR}/preseed.cfg ${ISODIR}/casper

cat <<EOL > ${ISODIR}/install/postseed.sh
#!/bin/bash
mount -o bind /dev /target/dev
mount -t proc none /target/proc
mount -t devpts none /target/dev/pts
mount -t proc sysfs /target/sys
#cp /etc/udev/rules.d/70-persistent-net.rules /target/etc/udev/rules.d
su - ubuntu -c /cdrom/install/messages.sh &
coreOnly="0" chroot /target /root/new-installer/postinst.sh
kill \$(ps aux |grep log-output | grep -v grep | cut -d" " -f6) 
exit 0
EOL

cat <<EOL > ${ISODIR}/install/postseedco.sh
#!/bin/bash
mount -o bind /dev /target/dev
mount -t proc none /target/proc
mount -t devpts none /target/dev/pts
mount -t proc sysfs /target/sys
#cp /etc/udev/rules.d/70-persistent-net.rules /target/etc/udev/rules.d
su - ubuntu -c /cdrom/install/messages.sh &
coreOnly="1" chroot /target /root/new-installer/postinst.sh
kill \$(ps aux | grep log-output | grep -v grep | cut -d" " -f6) 
exit 0
EOL

### Make On Screen Display
cat <<EOL > ${ISODIR}/install/messages.sh
#!/bin/bash
export DISPLAY=:0
OSD_Message() {
	gnome-osd-client --full --dbus "<message id='bootmsg' osd_fake_translucent_bg='off' osd_vposition='center' hide_timeout='10000000' osd_halignment='center'><span foreground='white' font='Arial 72'>\$*</span></message>"
}

msgchk=/target/tmp/msgchk
newmsg=/target/tmp/messenger
touch \$newmsg

if [[ ! -f \$msgchk ]]; then 
	sudo touch -r \$msgchk 
fi

while true; do
	if [[ "\$newmsg" -nt "\$msgchk" ]]; then
		sleep 1
		OSD_Message "\$(cat \$newmsg)"
		sudo touch -r \$newmsg \$msgchk
	fi

	if [[ "\$(cat \$newmsg)" == "Reboot" ]]; then
		OSD_Message " "
		break
	fi
done
EOL

### The main post-installer
cat <<EOL > ${WORKMASTER}/postinst.sh
#!/bin/bash
. /usr/pluto/bin/dvd-installer.sh
export LC_ALL=C
#log_file=/var/log/LinuxMCE_Setup.log
Messg_File=/tmp/messenger
echo "Running post-install. Do NOT reboot." > \$Messg_File
rm /root/new-installer/spacemaker
service mysql stop
killall -9 mysqld
sleep 2
mysqld --skip-networking&
sleep 5
StatusMessage "Configuring Pluto"
Setup_Pluto_Conf
echo "Removing ubiquity and casper options" > \$Messg_File
apt-get -y remove --purge --force-yes ubiquity ubiquity-casper ubiquity-ubuntu-artwork ubiquity-frontend-kde casper
echo "Updating initramfs. This will take several minutes." > \$Messg_File
update-alternatives --install /lib/plymouth/themes/default.plymouth default.plymouth /lib/plymouth/themes/LinuxMCE/LinuxMCE.plymouth 900
# Disable compcache
	if [[ -f /usr/share/initramfs-tools/conf.d/compcache ]]; then
		rm -f /usr/share/initramfs-tools/conf.d/compcache && update-initramfs -u
	else 
		update-initramfs -u
	fi
cp -pd /usr/pluto/bin/firstboot /etc/init.d/firstboot
chmod 755 /etc/init.d/firstboot
update-rc.d firstboot start 90 2 . >/dev/null
echo "Unmounting and shutting down MySQL" > \$Messg_File
umount -lf /dev/pts
umount -lf /sys
umount -lf /proc
service mysql stop
killall -9 mysqld_safe
kill \`lsof | grep mysqld | cut -d" " -f3 | sort -u | head -1\` ||:
umount -lf /dev
dpkg-divert --add --rename --divert /usr/bin/kdm.wraped /usr/bin/kdm
cp -pd /etc/network/interfaces.temp /target/etc/network/interfaces
echo "Preparing for Core reboot" > \$Messg_File
sleep 3
echo "Reboot" > \$Messg_File
#rm /target/tmp/messenger
EOL

#####################################
# Prepping chroot image
#####################################
# TODO this step will probably not be necessary on your end, but make sure you have enough room on your base image to get/extract/install
# Should probably be the first package you install if you wish to preserve a smaller disk size.
echo "Installing video-wizard-videos if necessary"
	
	if [[ ! -d ${DDDIR}/home/videowiz ]]; then
		cp video-wizard-videos_1.1_all.deb ${DDDIR}/usr/pluto
		chroot $DDDIR dpkg -i /usr/pluto/video-wizard-videos_1.1_all.deb
		rm ${DDDIR}/usr/pluto/video-wizard-videos_1.1_all.deb
	fi
	
echo "Downloading tools to the CHROOT needed for mastering."
mkdir -p ${DDDIR}/etc/udev/rules.d
	if [[ ! -e "${DDDIR}/sbin/losetup" ]]; then
		echo > ${DDDIR}/sbin/losetup
	fi
	if [[ ! -e "${DDDIR}/sbin/udevtrigger" ]]; then
		echo > ${DDDIR}/sbin/udevtrigger;
	fi

####################################
# Configure DCERouter
####################################
cat <<EOL > ${DDDIR}/root/new-installer/prepmaster.sh
#!/bin/bash
. /usr/pluto/bin/dvd-installer.sh
sleep 5
StatusMessage "Pre-configuring Install"
TimeUpdate
CreateBackupSources
AddAptRetries
StatusMessage "Configuring deb-cache"
Pre-InstallNeededPackages
if ls /var/cache/apt/archives/*.deb; then
	mv /var/cache/apt/archives/*.deb /usr/pluto/deb-cache/
fi
CreatePackagesFiles
StatusMessage "Cleaning debs"
apt-get clean
#ConfigSources
StatusMessage "Finalizing image setup"
PreSeed_Prefs
Fix_Initrd_Vmlinux
#apt-get install festival
apt-get remove -yq popularity-contest
PackageCleanUp
#apt-get remove -y festival
apt-get remove -y *java*
EOL

chmod +x ${DDDIR}/root/new-installer/prepmaster.sh
LC_ALL=C chroot $DDDIR /root/new-installer/prepmaster.sh
sleep 5

#####################################
# Prepping the dvd file system
#####################################

### This moves things around and creates the file system to be squashed.
echo "Time to move. This may take a while. Go code something..."
	
	# Wipe and prevent the installer from changing the apt sources.list
	if [[ ! -f "${DDDIR}/usr/share/ubiquity/apt-setup.saved" ]]; then
		cp -pd ${DDDIR}/usr/share/ubiquity/apt-setup ${DDDIR}/usr/share/ubiquity/apt-setup.saved
	fi

# move images for ubiquity background
cp -pd ${DDDIR}/lib/plymouth/themes/LinuxMCE/LinuxMCE-logo.png ${DDDIR}/usr/share/kde4/apps/kdm/themes/ethais/wallpapers/background-1920x1200.png
cp -pd ${DDDIR}/lib/plymouth/themes/LinuxMCE/LinuxMCE-logo.png ${DDDIR}/usr/share/kde4/apps/kdm/themes/ethais/wallpapers/background.png

# Creates the CD tree in the work directory
mkdir -p ${WORKDIR}/{home,dev,etc,proc,tmp,sys,var}
mkdir -p ${WORKDIR}/mnt/dev
mkdir -p ${WORKDIR}/media/cdrom
chmod ug+rwx,o+rwt ${WORKDIR}/tmp
	
# Copying /var and /etc to temp area and excluding extra files
	if [[ "$EXCLUDES" != "" ]]; then
		for addvar in $EXCLUDES ; do
			VAREXCLUDES="$VAREXCLUDES --exclude='$addvar' "
		done
	fi

# This moves everthing but what is excluded
rsync --exclude='*.log' --exclude='*.log.*' --exclude='*.pid' --exclude='*.bak'  $VAREXCLUDES-a ${DDDIR}/var/. ${WORKDIR}/var/.
#--exclude='*.[0-9].gz' --exclude='*.deb' 
rsync $VAREXCLUDES-a ${DDDIR}/etc/. ${WORKDIR}/etc/.
	
# This removes everything we want to make fresh
rm -rf ${WORKDIR}/etc/X11/xorg.conf*
rm -rf ${WORKDIR}/etc/timezone
rm -rf ${WORKDIR}/etc/mtab
rm -rf ${WORKDIR}/etc/fstab
rm -rf ${WORKDIR}/etc/udev/rules.d/70-persistent*
rm -rf ${WORKDIR}/etc/cups/ssl/server.*
rm -rf ${WORKDIR}/etc/ssh/ssh_host*
rm -rf ${WORKDIR}/etc/gdm/custom.conf
#ls ${WORKDIR}/var/lib/apt/lists | grep -v ".gpg" | grep -v "lock" | grep -v "partial" | xargs -i rm ${WORKDIR}/var/lib/apt/lists/{} ;
echo > ${WORKDIR}/etc/gdm/gdm.conf-custom
rm -rf ${WORKDIR}/etc/group
rm -rf ${WORKDIR}/etc/passwd
rm -rf ${WORKDIR}/etc/*hadow*
rm -rf ${WORKDIR}/etc/wicd/wir*.conf
rm -rf ${WORKDIR}/etc/printcap
touch ${WORKDIR}/etc/printcap

# We use copy here to move home directory including hidden files.
cp -rpd ${DDDIR}/home/* ${WORKDIR}/home 
cp -rpdn ${DDDIR}/root/* ${WORKDIR}/root 
cp -rpdn ${DDDIR}/root/.??* ${WORKDIR}/root 

# This removes what we don't want in there.
find ${WORKDIR}/var/run ${WORKDIR}/var/log ${WORKDIR}/var/mail ${WORKDIR}/var/spool ${WORKDIR}/var/lock ${WORKDIR}/var/backups ${WORKDIR}/var/tmp ${WORKDIR}/var/crash -type f -exec rm {} \;


# Makes sure we have relevant logs available in var
	for i in dpkg.log lastlog mail.log syslog auth.log daemon.log faillog lpr.log mail.warn user.log boot debug mail.err messages wtmp bootstrap.log dmesg kern.log mail.info
		do touch ${WORKDIR}/var/log/${i}
	done
	
# See if any temp users left over
grep '^[^:]*:[^:]*:[5-9][0-9][0-9]:' ${DDDIR}/etc/passwd | awk -F ":" '{print "/usr/sbin/userdel -f",$1}'> ${WORKDIR}/cleantmpusers
. ${WORKDIR}/cleantmpusers
grep '^[^:]*:[^:]*:[0-9]:' ${DDDIR}/etc/passwd >> ${WORKDIR}/etc/passwd
grep '^[^:]*:[^:]*:[0-9][0-9]:' ${DDDIR}/etc/passwd >> ${WORKDIR}/etc/passwd
grep '^[^:]*:[^:]*:[0-9][0-9][0-9]:' ${DDDIR}/etc/passwd >> ${WORKDIR}/etc/passwd
grep '^[^:]*:[^:]*:[3-9][0-9][0-9][0-9][0-9]:' ${DDDIR}/etc/passwd >> ${WORKDIR}/etc/passwd
grep '^[^:]*:[^:]*:[0-9]:' ${DDDIR}/etc/group >> ${WORKDIR}/etc/group
grep '^[^:]*:[^:]*:[0-9][0-9]:' ${DDDIR}/etc/group >> ${WORKDIR}/etc/group
grep '^[^:]*:[^:]*:[0-9][0-9][0-9]:' ${DDDIR}/etc/group >> ${WORKDIR}/etc/group
grep '^[^:]*:[^:]*:[3-9][0-9][0-9][0-9][0-9]:' ${DDDIR}/etc/group >> ${WORKDIR}/etc/group
grep '^[^:]*:[^:]*:[5-9][0-9][0-9]:' ${DDDIR}/etc/passwd | awk -F ":" '{print $1}'> ${WORKDIR}/tmpusers1
grep '^[^:]*:[^:]*:[1-9][0-9][0-9][0-9]:' ${DDDIR}/etc/passwd | awk -F ":" '{print $1}'> ${WORKDIR}/tmpusers2
grep '^[^:]*:[^:]*:[1-2][0-9][0-9][0-9][0-9]:' ${DDDIR}/etc/passwd | awk -F ":" '{print $1}'> ${WORKDIR}/tmpusers3

cat ${WORKDIR}/tmpusers1 ${WORKDIR}/tmpusers2 ${WORKDIR}/tmpusers3 > ${WORKDIR}/tmpusers
	cat ${WORKDIR}/tmpusers | while read LINE ; do
		echo $LINE | xargs -i sed -e 's/,{}//g' ${WORKDIR}/etc/group > ${WORKDIR}/etc/group.new1
		echo $LINE | xargs -i sed -e 's/{},//g' ${WORKDIR}/etc/group.new1 > ${WORKDIR}/etc/group.new2
		echo $LINE | xargs -i sed -e 's/{}//g' ${WORKDIR}/etc/group.new2 > ${WORKDIR}/etc/group
		rm -rf ${WORKDIR}/etc/group.new1 ${WORKDIR}/etc/group.new2
	done
	 
# Make sure the adduser and autologin functions of casper as set according to the mode
[ ! -d ${WORKDIR}/home ] && mkdir ${WORKDIR}/home && chmod 755 ${DDDIR}/usr/share/initramfs-tools/scripts/casper-bottom/*adduser ${DDDIR}/usr/share/initramfs-tools/scripts/casper-bottom/*autologin
	
# BOOT Type is isolinux
cp -pd ${DDDIR}/boot/memtest86+.bin ${ISODIR}/isolinux/memtest
	
# Check and see if they have a custom isolinux already setup.
find ${DDDIR}/usr -name 'isolinux.bin' -exec cp -pd {} ${ISODIR}/isolinux/ \;
find ${DDDIR}/usr -name 'vesamenu.c32' -exec cp -pd {} ${ISODIR}/isolinux/ \;
	
# Setup isolinux for the livecd
	if [[ -e ${DDMASTER}/splash.png ]]; then 
		cp -pd ${DDMASTER}/splash.png ${ISODIR}/isolinux
	fi
	if [[ -e splash.png ]]; then
		cp splash.png ${ISODIR}/isolinux
	fi
	
	# We need a defines file and copy it to the casper dir
cat <<EOL > ${ISODIR}/README.diskdefines
#define DISKNAME  $LIVECDLABEL
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  $ARCH
#define ARCH$ARCH  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOL

cp -pd ${ISODIR}/README.diskdefines ${ISODIR}/casper/README.diskdefines
	
# Make the filesystem.manifest and filesystem.manifest-desktop
echo "Creating filesystem.manifest and filesystem.manifest-desktop"
dpkg-query -W --showformat='${Package} ${Version}\n' > ${ISODIR}/casper/filesystem.manifest
cp -pd ${ISODIR}/casper/filesystem.manifest ${ISODIR}/casper/filesystem.manifest-desktop
cp -pd ${DDDIR}/etc/casper.conf ${WORKDIR}/etc/
# Copy the install icon to the live install users desktop
udtop=$(find ${DDDIR}/usr -name 'ubiquity*.desktop')
cp -pd $udtop ${DDDIR}/etc/skel/Desktop

echo "Setting up casper and ubiquity options."
rm -f ${DDDIR}/usr/share/ubiquity/apt-setup
echo "#do nothing" > ${DDDIR}/usr/share/ubiquity/apt-setup
chmod 755 ${DDDIR}/usr/share/ubiquity/apt-setup

#####################################
# Rebuild initram and squash
#####################################
# make a new initial ramdisk including the casper scripts and LinuxMCE plymouth theme
KERN=$(ls ${DDDIR}/lib/modules --sort time | head -1)
LC_ALL=C chroot $DDDIR update-alternatives --install /lib/plymouth/themes/default.plymouth default.plymouth /lib/plymouth/themes/LinuxMCE/LinuxMCE.plymouth 900
LC_ALL=C chroot $DDDIR mkinitramfs -o /boot/initrd.img-${KERN} $KERN
LC_ALL=C chroot $DDDIR update-alternatives --install /lib/plymouth/themes/default.plymouth default.plymouth /lib/plymouth/themes/LinuxMCE/LinuxMCE.plymouth 900
LC_ALL=C chroot $DDDIR update-initramfs -u
	
echo "Copying your kernel and initrd for the livecd"
cp -pd ${DDDIR}/boot/vmlinuz-${KERN} ${ISODIR}/casper/vmlinuz
cp -pd ${DDDIR}/boot/initrd.img-${KERN} ${ISODIR}/casper/initrd.gz


###############################################
# This moves and rewrites some startup scripts
###############################################
echo "Adjusting startup scripts"

if [[ -f ${WORKDIR}/etc/init.d/a0start_avwizard ]]; then
	mv ${WORKDIR}/etc/init.d/a0start_avwizard ${WORKMASTER}/runners
	cat <<EOL > ${WORKDIR}/etc/init.d/a0start_avwizard
#!/bin/bash
### BEGIN INIT INFO 
# Provides:		avwizard
# Required-Start:	check_avwizard
# Required-Stop:	 
# Should-Start:	
# Default-Start:	 2 
# Default-Stop:	1 
# Short-Description: AVWizard
# Description:	 This script starts the AV Wizard
### END INIT INFO #
rm /dev/nbd*
. /usr/pluto/bin/dvd-installer.sh
FirstNetwork
exit 0
EOL
	chmod +x ${WORKDIR}/etc/init.d/a0start_avwizard
fi

if [[ -f ${WORKDIR}/etc/init.d/apache2 ]]; then
	mv ${WORKDIR}/etc/init.d/apache2 ${WORKMASTER}/runners
	cat <<EOL > ${WORKDIR}/etc/init.d/apache2
#!/bin/sh -e
### BEGIN INIT INFO
# Provides:          apache2
# Required-Start:    $local_fs $remote_fs $network $syslog
# Required-Stop:     $local_fs $remote_fs $network $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# X-Interactive:     true
# Short-Description: Start/stop apache2 web server
### END INIT INFO
#
# apache2               This init.d script is used to start apache2.
#                       It basically just calls apache2ctl.
exit 0
EOL
	chmod +x ${WORKDIR}/etc/init.d/apache2
fi

if [[ -f ${WORKDIR}/etc/init.d/apparmor ]]; then
	mv ${WORKDIR}/etc/init.d/apparmor ${WORKMASTER}/runners
	cat <<EOL > ${WORKDIR}/etc/init.d/apparmor
#!/bin/sh
# ----------------------------------------------------------------------
#    Copyright (c) 1999, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007
#     NOVELL (All rights reserved)
#    Copyright (c) 2008, 2009 Canonical, Ltd.
#
#    This program is free software; you can redistribute it and/or
#    modify it under the terms of version 2 of the GNU General Public
#    License published by the Free Software Foundation.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, contact Novell, Inc.
# ----------------------------------------------------------------------
# Authors:
#  Steve Beattie <steve.beattie@canonical.com>
#  Kees Cook <kees@ubuntu.com>
#
# /etc/init.d/apparmor
#
### BEGIN INIT INFO
# Provides: apparmor
# Required-Start: mountall
# Required-Stop: umountfs
# Default-Start: S
# Default-Stop:
# Short-Description: AppArmor initialization
# Description: AppArmor init script. This script loads all AppArmor profiles.
### END INIT INFO
exit 0
EOL
	chmod +x ${WORKDIR}/etc/init.d/apparmor
fi

if [[ -f ${WORKDIR}/etc/init.d/asterisk ]]; then
mv ${WORKDIR}/etc/init.d/asterisk ${WORKMASTER}/runners
cat <<EOL > ${WORKDIR}/etc/init.d/asterisk
#!/bin/sh
#
# asterisk      start the asterisk PBX
# (c) Mark Purcell <msp@debian.org>
# (c) Tzafrir Cohen <tzafrir.cohen@xorcom.com>
# (c) Faidon Liambotis <paravoid@debian.org>
#
#   This package is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
### BEGIN INIT INFO
# Provides:          asterisk
# Required-Start:    $remote_fs
# Required-Stop:     $remote_fs
# Should-Start:      $syslog $network $named mysql postgresql dahdi
# Should-Stop:       $syslog $network $named mysql postgresql
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Asterisk PBX
# Description:       Controls the Asterisk PBX
### END INIT INFO
cp -pd /etc/network/interfaces.temp /etc/network/interfaces
exit 0
EOL
	chmod +x ${WORKDIR}/etc/init.d/asterisk
fi

if [[ -f ${WORKDIR}/etc/init.d/bind9 ]]; then
	mv ${WORKDIR}/etc/init.d/bind9 ${WORKMASTER}/runners
	cat <<EOL > ${WORKDIR}/etc/init.d/bind9
### BEGIN INIT INFO
# Provides:          bind9
# Required-Start:    $remote_fs
# Required-Stop:     $remote_fs
# Should-Start:      $network $syslog
# Should-Stop:       $network $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start and stop bind9
# Description:       bind9 is a Domain Name Server (DNS)
#        which translates ip addresses to and from internet names
### END INIT INFO
exit 0
EOL
	chmod +x ${WORKDIR}/etc/init.d/bind9
fi

if [[ -f ${WORKDIR}/etc/init.d/linuxmce ]]; then
	mv ${WORKDIR}/etc/init.d/linuxmce ${WORKMASTER}/runners
	cat <<EOL > ${WORKDIR}/etc/init.d/linuxmce
#!/bin/bash
### BEGIN INIT INFO 
# Provides:		linuxmce
# Required-Start:	$remote_fs $syslog 
# Required-Stop:	 $remote_fs $syslog 
# Should-Start:	$named 
# Default-Start:	 2 
# Default-Stop:	1 
# Short-Description: LinuxMCE 
# Description:	 This script is the entry point to start the LinuxMCE core
#			  It starts a couple of needed services and daemons, loads X (if running with AutoStartMedia)
#			  and executes LMCE_Launch_Manager to start devices and taking care of the rest.
### END INIT INFO #
#. /usr/pluto/bin/dvd-installer.sh
#Nic_Config
#/etc/init.d/networking restart
exit 0
EOL
	chmod +x ${WORKDIR}/etc/init.d/linuxmce
fi

if [[ -f ${WORKDIR}/etc/init.d/mediatomb ]]; then
	mv ${WORKDIR}/etc/init.d/mediatomb ${WORKMASTER}/runners
	cat <<EOL > ${WORKDIR}/etc/init.d/mediatomb
#! /bin/sh
#
# MediaTomb initscript
#
# Original Author: Tor Krill <tor@excito.com>.
# Modified by:     Leonhard Wimmer <leo@mediatomb.cc>
# Modified again by Andres Mejia <mcitadel@gmail.com> to
# base it off of /etc/init.d/skeleton
#
#

### BEGIN INIT INFO
# Provides:          mediatomb
# Required-Start:    $local_fs $network $remote_fs
# Required-Stop:     $local_fs $network $remote_fs
# Should-Start:      $all
# Should-Stop:       $all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: upnp media server
### END INIT INFO
exit 0
EOL
	chmod +x ${WORKDIR}/etc/init.d/mediatomb
fi

	if [[ -f ${WORKDIR}/etc/init.d/nis ]]; then
mv ${WORKDIR}/etc/init.d/nis ${WORKMASTER}/runners
cat <<EOL > ${WORKDIR}/etc/init.d/nis
#!/bin/sh
#
# /etc/init.d/nis	 Start NIS (formerly YP) daemons.
#
### BEGIN INIT INFO
# Provides:		 ypbind ypserv ypxfrd yppasswdd
# Required-Start:	 $network $portmap
# Required-Stop:	  $portmap
# Default-Start:	  2 3 4 5
# Default-Stop:		1
# Short-Description:	Start NIS client and server daemons.
# Description:		Start NIS client and server daemons.  NIS is mostly
#				 used to let several machines in a network share the
#				 same account information (eg the password file).
### END INIT INFO
exit 0
EOL
	chmod +x ${WORKDIR}/etc/init.d/nis
fi

if [[ -f ${WORKDIR}/etc/init.d/smbd ]]; then
	mv ${WORKDIR}/etc/init.d/smbd ${WORKMASTER}/runners
	cat <<EOL > ${WORKDIR}/etc/init.d/smbd
#!/bin/sh -e
# upstart-job
#
# Symlink target for initscripts that have been converted to Upstart.
exit 0
EOL
	chmod +x ${WORKDIR}/etc/init.d/smbd
fi



# Make executables
chmod +x ${ISODIR}/install/postseed.sh
chmod +x ${ISODIR}/install/postseedco.sh
chmod +x ${ISODIR}/install/messages.sh
chmod +x ${WORKMASTER}/postinst.sh

# Create 400mb file to be deleted on reboot so aufs has enough room for larger downloads. 
cp -pd ${DDDIR}/etc/network/interfaces.temp ${DDDIR}/etc/network/interfaces
dd if=/dev/zero of=${WORKMASTER}/spacemaker count=4 bs=100MB

# Make filesystem.squashfs
	if [[ -f "lmcemaster.log" ]]; then
		rm -f lmcemaster.log
		touch lmcemaster.log
	fi
	
	if [[ -f "${ISODIR}/casper/filesystem.squashfs" ]]; then
		rm -f ${ISODIR}/casper/filesystem.squashfs
	fi

# Suppress Desktop
echo "/bin/false" > ${WORKDIR}/etc/X11/default-display-manager
echo "/bin/false" > ${DDDIR}/etc/X11/default-display-manager

echo "Time to squash"
SQUASHFSOPTSHIGH="-no-recovery -always-use-fragments"
echo "Adding stage 1 files/folders that the livecd requires."
	
# Add the blank folders and trimmed down /var to the cd filesystem
mksquashfs $WORKDIR ${ISODIR}/casper/filesystem.squashfs -b 1M -no-duplicates $SQUASHFSOPTSHIGH 2>>lmcemaster.log
echo "Adding stage 2 files/folders that the livecd requires."
mksquashfs $DDDIR ${ISODIR}/casper/filesystem.squashfs -b 1M -no-duplicates $SQUASHFSOPTSHIGH -e .thumbnails .cache .bash_history Cache boot/grub dev etc home media mnt proc sys tmp var $WORKDIR $EXCLUDES 2>>lmcemaster.log
# Checking the size of the compressed filesystem to ensure it meets the iso9660 spec for a single file
SQUASHFSSIZE=`ls -s ${ISODIR}/casper/filesystem.squashfs | awk -F " " '{print $1}'`
#	if [[ "$SQUASHFSSIZE" -gt "3999999" ]]; then
#		echo "The compressed filesystem is larger than the iso9660 specification allows for a single file. You must try to reduce the amount of data you are backing up and try again."
#		echo " Too big for DVD">>lmcemaster.log
#		exit 1
#	fi
	
# Add filesystem size for lucid
echo "Calculating the installed filesystem size for the installer"
unsquashfs -lls ${ISODIR}/casper/filesystem.squashfs | grep -v " inodes " | grep -v "unsquashfs:" | awk '{print $3}' | grep -v "," > ${DDDIR}/tmp/size.tmp
	for i in `cat ${DDDIR}/tmp/size.tmp`; do 
		a=$(($a+$i))
	done
echo $a > ${ISODIR}/casper/filesystem.size


###########################################
# Let's make us an iso
###########################################
# TODO this probably is unnecessary, but I don't know what fluffys guts look like.
CREATEISO="`which mkisofs`"
	if [[ "$CREATEISO" = "" ]]; then
		CREATEISO="`which genisoimage`"
	fi
	
# Check to see if the cd filesystem exists
	if [[ ! -f "${ISODIR}/casper/filesystem.squashfs" ]]; then
		echo "The cd filesystem is missing."
		exit 1
	fi
	
# Checking the size of the compressed filesystem to ensure it meets the iso9660 spec for a single file
SQUASHFSSIZE=`ls -s ${ISODIR}/casper/filesystem.squashfs | awk -F " " '{print $1}'`
#	if [[ "$SQUASHFSSIZE" -gt "3999999" ]]; then
#		echo " The compressed filesystem is larger than the iso9660 specification allows for a single file. You must try to reduce the amount of data you are backing up and try again."
#		echo " Too big for DVD.">>lmcemaster.log
#		exit 1
#	fi
	
# Make ISO compatible with Ubuntu Startup Disk Creator for those who would like to use it for usb boots
echo "Making disk compatible with Ubuntu Startup Disk Creator."
touch ${ISODIR}/ubuntu
touch ${ISODIR}/.disk/base_installable
echo "full_cd/single" > ${ISODIR}/.disk/cd_type
echo $LIVECDLABEL - Release i386 > ${ISODIR}/.disk/info
echo $LIVECDURL > ${ISODIR}/.disk/release_notes_url

# Make md5sum.txt for the files on the livecd - this is used during the checking function of the livecd
echo "Creating md5sum.txt for the livecd/dvd"
cd $ISODIR && find . -type f -print0 | xargs -0 md5sum > md5sum.txt

# Remove files that change and cause problems with checking the disk
sed -e '/isolinux/d' md5sum.txt > md5sum.txt.new
sed -e '/md5sum/d' md5sum.txt.new > md5sum.txt
rm -f md5sum.txt.new
	
# Make the ISO file
echo "Creating $CUSTOMISO"
$CREATEISO -r -V "$LIVECDLABEL" -iso-level 3 -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ../${CUSTOMISO} "./" 2>>../lmcemaster.log 1>>../lmcemaster.log
	
# Create the md5 sum file
echo "Creating $CUSTOMISO.md5"
cd ../
md5sum $CUSTOMISO > $CUSTOMISO.md5
echo " "
	if [[ ! -e $CUSTOMISO ]]; then
		echo "Something has gone horribly wrong. Iso does not exist. Exiting."
	else
		echo "Success!!! `ls -hs $CUSTOMISO` is ready to be burned or tested in a virtual machine."
	fi

# Cleans and unmounts without displaying an error message as the trap should.
cleanFinish () {
	if [[ -e ${DDDIR}/usr/sbin/invoke-rc.d.orig ]]; then
		mv ${DDDIR}/usr/sbin/invoke-rc.d.orig ${DDDIR}/usr/sbin/invoke-rc.d.orig
	fi

mounted=$(mount | grep $IMAGEFILE-dd | grep none | awk '{print $3}')
	for mounts in $mounted; do 
		umount -lf $mounts
	done
	umount -lf `mount | grep $IMAGEFILE-dd | grep loop | awk '{print $3}'`
	rm -r $DDDIR
	rm -r $WORKDIR
	rm -r $ISODIR
	exit 0
}

echo "Unmounting and exiting cleanly."
# This will give a clean unmount and not trigger the trap, so the trap can show errors.
# cleanFinish 
exit 0

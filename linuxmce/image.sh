#!/bin/bash
#
# Create an image which can be dd'ed onto
# a harddisk, and, after adding a boot loader
# using grub, be ready for consumption.
#
set -e

#http_proxy=http://10.10.42.99:3142/

OLDDIR=$(pwd)
DISTRO=precise
DISTRONO=1204

if [ "$1" != "" ]; then
	DISTRO=$1
fi
if [ "$DISTRO" = "lucid" ] ; then 
	DISTRONO=1004
fi
if [ "$DISTRO" = "precise" ] ; then
	DISTRONO=1204
fi

echo "Installing required packages"
#apt-get -y install debootstrap dpkg-dev

echo "Creating an image for $DISTRO"
IMAGEFILE=$(tempfile -p $DISTRONO)
dd if=/dev/zero of=$IMAGEFILE count=110 bs=100MB
mkfs.ext2 -F $IMAGEFILE
TEMPDIR=$(mktemp -d $DISTRONO-dir.XXXXXXXXXX)
mount -o loop $IMAGEFILE $TEMPDIR

echo "Running debootstrap in the image"
#debootstrap --arch=i386 --include=mysql-server,rsync $DISTRO $TEMPDIR
http_proxy=$http_proxy debootstrap --arch=i386 $DISTRO $TEMPDIR

echo "Mount required directories"
# mount required directories
mount -o bind /dev $TEMPDIR/dev
mount -t proc none $TEMPDIR/proc
mount -t devpts none $TEMPDIR/dev/pts
mount -t sysfs none $TEMPDIR/sys

echo "Creating config files"
# create pluto.conf with mysqlhost set to localhost
cat <<-EOF > $TEMPDIR/etc/pluto.conf
	MySqlHost = localhost
	EOF

echo "Setting hostname"
# set the hostname to dcerouter
echo dcerouter > $TEMPDIR/etc/hostname

echo "Setting nameserver"
# set the nameserver to Google's server, which
# should always be reachable.
echo nameserver 8.8.8.8 > $TEMPDIR/etc/resolv.conf
echo nameserver 8.8.8.8 > $TEMPDIR/etc/resolvconf/resolv.conf.d/tail
echo nameserver 8.8.8.8 > $TEMPDIR/etc/resolvconf/resolv.conf.d/original

LC_ALL=C chroot $TEMPDIR mkdir -p /var/run/network /lib/plymouth/themes

echo "Setting up sources.list"
# setup permanent apt sources
cat <<-EOF >$TEMPDIR/etc/apt/sources.list
	deb http://deb.linuxmce.org/ubuntu/ $DISTRO unstable
	deb http://debian.slimdevices.com/ stable  main
	deb http://ppa.launchpad.net/yavdr/stable-vdr/ubuntu/ $DISTRO main
	EOF

# LOCAL MIRROR
# These sources will be added to sources.list at the end of this script
# The installation process will also wipe out these entries
cat <<-EOF >$TEMPDIR/etc/apt/sources.list.d/ubuntu.list
	#deb http://ca.archive.ubuntu.com/ubuntu/ $DISTRO main restricted universe multiverse
	#deb http://ca.archive.ubuntu.com/ubuntu/ $DISTRO-updates main restricted universe multiverse
	deb http://archive.ubuntu.com/ubuntu/ $DISTRO main restricted universe multiverse
	deb http://archive.ubuntu.com/ubuntu/ $DISTRO-updates main restricted universe multiverse
	deb http://security.ubuntu.com/ubuntu/ $DISTRO-security main restricted universe
	EOF

# These sources will be removed at the end of this script
cat <<-EOF >$TEMPDIR/etc/apt/sources.list.d/fluffy.list
	deb http://fluffybitch.org/builder-$DISTRO/ ./
	EOF

# Copy proxy file, if it exists.  This will be removed at the end of this script
echo "Enable proxy if configured on host"
if [ -f /etc/apt/apt.conf.d/02proxy ]; then
	cp /etc/apt/apt.conf.d/02proxy $TEMPDIR/etc/apt/apt.conf.d/02proxy
fi

echo "Create preseed file"
# create preseed file
cat <<-EOF | LC_ALL=C chroot $TEMPDIR debconf-set-selections
	debconf debconf/frontend  select noninteractive
	# Choices: critical, high, medium, low
	debconf debconf/priority        select critical
	msttcorefonts   msttcorefonts/http_proxy        string
	msttcorefonts   msttcorefonts/defoma    note
	msttcorefonts   msttcorefonts/dlurl     string
	msttcorefonts   msttcorefonts/savedir   string
	msttcorefonts   msttcorefonts/baddldir  note
	msttcorefonts   msttcorefonts/dldir     string
	msttcorefonts   msttcorefonts/blurb     note
	msttcorefonts   msttcorefonts/accepted-mscorefonts-eula boolean true
	msttcorefonts   msttcorefonts/present-mscorefonts-eula  boolean false
	sun-java6-bin   shared/accepted-sun-dlj-v1-1    boolean true
	sun-java6-jre   shared/accepted-sun-dlj-v1-1    boolean true
	sun-java6-jre   sun-java6-jre/jcepolicy note
	sun-java6-jre   sun-java6-jre/stopthread        boolean true
	man-db man-db/install-setuid boolean false
	EOF

echo "Update sources"
# Update sources and ignore error messages at apt-get for now.
LC_ALL=C chroot $TEMPDIR apt-get update || :

echo "Install service invocation packages sysv-rc and upstart"
# Install service invocation utilities
LC_ALL=C chroot $TEMPDIR apt-get install sysv-rc upstart screen || :

echo "Disable all service invocation"
# disable service invocation and tools
mv $TEMPDIR/usr/sbin/invoke-rc.d $TEMPDIR/usr/sbin/invoke-rc.d.orig
mv $TEMPDIR/sbin/start $TEMPDIR/sbin/start.orig
mv $TEMPDIR/sbin/restart $TEMPDIR/sbin/restart.orig
mv $TEMPDIR/sbin/initctl $TEMPDIR/sbin/initctl.orig

cat <<-EOF > $TEMPDIR/usr/sbin/invoke-rc.d
	#!/bin/bash
	exit 0
	EOF
chmod +x $TEMPDIR/usr/sbin/invoke-rc.d

cat <<-EOF > $TEMPDIR/sbin/start
	#!/bin/bash
	exit 0
	EOF
chmod +x $TEMPDIR/sbin/start
cp $TEMPDIR/sbin/start $TEMPDIR/sbin/restart
cp $TEMPDIR/sbin/start $TEMPDIR/sbin/initctl

mv $TEMPDIR/usr/bin/screen $TEMPDIR/usr/bin/screen.orig
cat <<-EOF > $TEMPDIR/usr/bin/screen
	#!/bin/bash
	exit 0
	EOF
chmod +x $TEMPDIR/usr/bin/screen

echo "Upgrade the image"
# dist-upgrade the image
LC_ALL=C chroot $TEMPDIR apt-get dist-upgrade -y --allow-unauthenticated || :

echo "Install packages"
# install packages
LC_ALL=C chroot $TEMPDIR apt-get install mysql-server rsync linux-image-generic libc-dev-bin linux-libc-dev libc6-dev linux-headers-generic manpages-dev joe nano -y --allow-unauthenticated

# We make sure that the chroot knows about the current kernel version
export KVERS="`LC_ALL=C chroot $TEMPDIR apt-cache policy linux-image-generic|grep Installed|cut -d" " -f4-`"
echo "The image is running kernel $KVERS"

# Create a default my.cnf
mkdir -p $TEMPDIR/etc/mysql
cat <<-EOF > $TEMPDIR/etc/mysql/my.cnf
	#
	# The MySQL database server configuration file.
	#
	# You can copy this to one of:
	# - "/etc/mysql/my.cnf" to set global options,
	# - "~/.my.cnf" to set user-specific options.
	#
	# One can use all long options that the program supports.
	# Run program with --help to get a list of available options and with
	# --print-defaults to see which it would actually understand and use.
	#
	# For explanations see
	# http://dev.mysql.com/doc/mysql/en/server-system-variables.html

	# This will be passed to all mysql clients
	# It has been reported that passwords should be enclosed with ticks/quotes
	# escpecially if they contain "#" chars...
	# Remember to edit /etc/mysql/debian.cnf when changing the socket location.
	[client]
	port		= 3306
	socket		= /var/run/mysqld/mysqld.sock
	#charset_name    = utf8

	# Here is entries for some specific programs
	# The following values assume you have at least 32M ram

	# This was formally known as [safe_mysqld]. Both versions are currently parsed.
	[mysqld_safe]
	socket		= /var/run/mysqld/mysqld.sock
	nice		= 0

	[mysqld]
	transaction-isolation = READ-UNCOMMITTED
	init_connect='SET NAMES utf8; SET collation_connection = utf8_general_ci;' # Set UTF8 for connection
	character-set-server=utf8
	collation-server=utf8_general_ci
	skip-character-set-client-handshake  # Tells to server to ignore client's charset for connetion
	skip-name-resolve

	#
	# * Basic Settings
	#
	#
	# * IMPORTANT
	#   If you make changes to these settings and your system uses apparmor, you may
	#   also need to also adjust /etc/apparmor.d/usr.sbin.mysqld.
	#
	user		= mysql
	pid-file	= /var/run/mysqld/mysqld.pid
	socket		= /var/run/mysqld/mysqld.sock
	port		= 3306
	basedir		= /usr
	datadir		= /var/lib/mysql
	tmpdir		= /tmp
	language	= /usr/share/mysql/english
	#skip-external-locking
	#
	# Instead of skip-networking the default is now to listen only on
	# localhost which is more compatible and is not less secure.
	#bind-address=0.0.0.0
	skip-networking
	#
	# * Fine Tuning
	#
	#key_buffer		= 16M
	key_buffer		= 128M
	max_allowed_packet	= 16M
	thread_stack=128
	thread_cache_size	= 8
	# This replaces the startup script and checks MyISAM tables if needed
	# the first time they are touched
	myisam-recover		= BACKUP
	#max_connections        = 100
	#table_cache            = 64
	table_cache		= 512
	#thread_concurrency     = 10
	#
	# * Query Cache Configuration
	#
	#query_cache_limit       = 1M
	#query_cache_size        = 16M
	query_cache_size = 128MB
	query_cache_limit = 16MB

	sort_buffer_size = 32M
	myisam_sort_buffer_size = 32M

	#
	# * Logging and Replication
	#
	# Both location gets rotated by the cronjob.
	# Be aware that this log type is a performance killer.
	#log		= /var/log/mysql/mysql.log
	#
	# Error logging goes to syslog. This is a Debian improvement :)
	#
	# Here you can see queries with especially long duration
	#log_slow_queries	= /var/log/mysql/mysql-slow.log
	long_query_time = 1
	#log-queries-not-using-indexes
	#
	# The following can be used as easy to replay backup logs or for replication.
	# note: if you are setting up a replication slave, see README.Debian about
	#       other settings you may need to change.
	#server-id		= 1
	#log_bin			= /var/log/mysql/mysql-bin.log
	#expire_logs_days	= 10
	max_binlog_size         = 100M
	#binlog_do_db		= include_database_name
	#binlog_ignore_db	= include_database_name
	#
	# * BerkeleyDB
	#
	# Using BerkeleyDB is now discouraged as its support will cease in 5.1.12.
	#
	# * InnoDB
	#
	# InnoDB is enabled by default with a 10MB datafile in /var/lib/mysql/.
	# Read the manual for more InnoDB related options. There are many!
	# You might want to disable InnoDB to shrink the mysqld process by circa 100MB.
	#skip-innodb
	#
	# * Federated
	#
	# The FEDERATED storage engine is disabled since 5.0.67 by default in the .cnf files
	# shipped with MySQL distributions (my-huge.cnf, my-medium.cnf, and so forth).
	#
	skip-federated
	#
	# * Security Features
	#
	# Read the manual, too, if you want chroot!
	# chroot = /var/lib/mysql/
	#
	# For generating SSL certificates I recommend the OpenSSL GUI "tinyca".
	#
	# ssl-ca=/etc/mysql/cacert.pem
	# ssl-cert=/etc/mysql/server-cert.pem
	# ssl-key=/etc/mysql/server-key.pem

	#Enter a name for the slow query log. Otherwise a default name will be used.
	#log-slow-queries= /root/mysql_slow.log

	[mysqldump]
	quick
	quote-names
	max_allowed_packet	= 16M

	[mysql]
	#no-auto-rehash	# faster start of mysql but no tab completition

	[isamchk]
	key_buffer		= 16M
	#
	# * NDB Cluster
	#
	# See /usr/share/doc/mysql-server-*/README.Debian for more information.
	#
	# The following configuration is read by the NDB Data Nodes (ndbd processes)
	# not from the NDB Management Nodes (ndb_mgmd processes).
	#
	# [MYSQL_CLUSTER]
	# ndb-connectstring=127.0.0.1

	#
	# * IMPORTANT: Additional settings that can override those from this file!
	#   The files must end with '.cnf', otherwise they'll be ignored.
	#
	!includedir /etc/mysql/conf.d/
	EOF

echo "Starting MySQL Networking with localhost."
chmod 755 $TEMPDIR/var/lib/mysql
LC_ALL=C chroot $TEMPDIR mysqld --skip-networking &

echo "Begining LMCE Hybrid installation."
LC_ALL=C chroot $TEMPDIR apt-get install lmce-hybrid -y --allow-unauthenticated || :
LC_ALL=C chroot $TEMPDIR apt-get -f install

# Add the minimal KDE meta package, which will also install Xorg.
if [ "$DISTRONO" == "1004" ]; then
	LC_ALL=C chroot $TEMPDIR apt-get install kde-minimal -y --allow-unauthenticated
else
	LC_ALL=C chroot $TEMPDIR apt-get install kubuntu-desktop -y --allow-unauthenticated
fi

# Add video-wizard-videos and remove.deb
LC_ALL=C chroot $TEMPDIR apt-get install video-wizard-videos -y --allow-unauthenticated
rm -rf $TEMPDIR/var/cache/apt/archives/video-wizard-videos*.deb

# Add some LinuxMCE packages that are not part of the lmce-hybrid dependency, but that we still
# want pre-installed
LC_ALL=C chroot $TEMPDIR apt-get install pluto-text-to-speech pluto-xine-plugin pluto-mplayer-player lmce-picture-plugin lmce-mediatomb pluto-x-scripts pluto-orbiter lmce-plymouth-theme -y --allow-unauthenticated

# Asterisk stuff
LC_ALL=C chroot $TEMPDIR apt-get install lmce-asterisk asterisk pluto-asterisk -y --allow-unauthenticated

# Additional stuff wanted by l3mce
# removed ubuntu-standard
if [ "$DISTRONO" == "1004" ]; then
	LC_ALL=C chroot $TEMPDIR apt-get install casper ffmpeg lupin-casper discover1 laptop-detect os-prober linux-generic grub2 plymouth-x11 ubiquity-frontend-kde initramfs-tools firefox libestools1.2 libmp3lame0 cryptsetup debconf-utils dialog dmraid ecryptfs-utils libdebconfclient0 libdebian-installer4 libdmraid1.0.0.rc16 libecryptfs0 localechooser-data memtest86+ python-pyicu rdate reiserfsprogs squashfs-tools=1:4.0-6ubuntu1 ubiquity ubiquity-casper ubiquity-ubuntu-artwork ubiquity-frontend-kde user-setup xresprobe xserver-xorg-video-nouveau pastebinit festival -y --allow-unauthenticated
else
	# discover1 no longer exists, we use discover instead.
	# and we do not limit ourselves to a specific version of the squash-tools.
	LC_ALL=C chroot $TEMPDIR apt-get install casper ffmpeg lupin-casper discover laptop-detect os-prober linux-generic grub2 plymouth-x11 ubiquity-frontend-kde initramfs-tools firefox libestools1.2 libmp3lame0 cryptsetup debconf-utils dialog dmraid ecryptfs-utils libdebconfclient0 libdebian-installer4 libdmraid1.0.0.rc16 libecryptfs0 localechooser-data memtest86+ python-pyicu rdate reiserfsprogs squashfs-tools ubiquity ubiquity-casper ubiquity-ubuntu-artwork ubiquity-frontend-kde user-setup xresprobe xserver-xorg-video-nouveau pastebinit festival -y --allow-unauthenticated
fi

# copy the installer and firstboot script to the image
cp {dvd-installer.sh,firstboot} $TEMPDIR/usr/pluto/bin

if [ -f VBoxLinuxAdditions.run ]; then
	cp VBoxLinuxAdditions.run $TEMPDIR/usr/pluto/bin
fi

# Even more stuff wanted by l3mce
# to get the device install going in lmcemaster.sh
if [ "$DISTRONO" == "1004" ]; then
	LC_ALL=C chroot $TEMPDIR apt-get install foomatic-filters libcupscgi1 libcupsdriver1 libcupsmime1 libcupsppdc1 libijs-0.35 libpoppler5 poppler-utils cups-common cups-client ttf-freefont cups foomatic-db foomatic-db-engine libgutenprint2 ghostscript-cups cups-driver-gutenprint libhpmud0 hpijs min12xxw pnm2ppa -y --allow-unauthenticated
	LC_ALL=C chroot $TEMPDIR apt-get install php-pear libmyodbc pluto-messagetrans libcddb\* pluto-disk-drive pluto-xine-plugin lmce-picture-plugin ffmpeg flac pluto-irbase lmce-usb-gamepad libdvdnav4 lame libmyodbc pluto-mplayer-player id-my-disc pluto-skins-basic pluto-cddb-ident -y --allow-unauthenticated
else
	# libpoppler is now 19, and id-my-disc is currently not in the repo.
	LC_ALL=C chroot $TEMPDIR apt-get install foomatic-filters libcupscgi1 libcupsdriver1 libcupsmime1 libcupsppdc1 libijs-0.35 libpoppler19 poppler-utils cups-common cups-client ttf-freefont cups foomatic-db foomatic-db-engine libgutenprint2 ghostscript-cups cups-driver-gutenprint libhpmud0 hpijs min12xxw pnm2ppa -y --allow-unauthenticated
	LC_ALL=C chroot $TEMPDIR apt-get install php-pear libmyodbc pluto-messagetrans libcddb\* pluto-disk-drive pluto-xine-plugin lmce-picture-plugin ffmpeg flac pluto-irbase lmce-usb-gamepad libdvdnav4 lame libmyodbc pluto-mplayer-player pluto-skins-basic pluto-cddb-ident -y --allow-unauthenticated
fi
LC_ALL=C chroot $TEMPDIR apt-get install lmce-picture-viewer lmce-picture-plugin lmce-usb-gamepad pluto-photo-screen-saver -y --allow-unauthenticated
LC_ALL=C chroot $TEMPDIR apt-get install pluto-asterisk -d -y --allow-unauthenticated
LC_ALL=C chroot $TEMPDIR apt-get install ubiquity-frontend-kde -y --allow-unauthenticated
LC_ALL=C chroot $TEMPDIR apt-get install dpkg-dev -y --allow-unauthenticated

# download myth and vdr files to have in deb-cache for setup wizard
LC_ALL=C chroot $TEMPDIR apt-get install dkms apport-gtk aptdaemon-data defoma fonts-droid gir1.2-atk-1.0 gir1.2-dbusmenu-glib-0.4 gir1.2-dbusmenu-gtk-0.4 gir1.2-dee-1.0 gir1.2-freedesktop gir1.2-gdkpixbuf-2.0 gir1.2-gtk-2.0 gir1.2-gtk-3.0 gir1.2-javascriptcoregtk-3.0 gir1.2-pango-1.0 gir1.2-soup-2.4 gir1.2-unity-5.0 gir1.2-vte-2.90 gir1.2-webkit-3.0 gksu gnome-keyring id-my-disc indicator-application liba52-0.7.4 libappindicator3-1 libarchive-zip-perl libass4 libavahi-compat-libdnssd1 libcap2-bin libclass-load-perl libclass-methodmaker-perl libclass-singleton-perl libcommon-sense-perl libcrystalhd3 libdancer-xml0 libdata-dump-perl libdata-optlist-perl libdate-manip-perl libdatetime-format-strptime-perl libdatetime-locale-perl libdatetime-perl libdatetime-timezone-perl libdee-1.0-4 libdigest-hmac-perl libemail-address-perl libemail-find-perl libemail-valid-perl libexporter-lite-perl libextractor1c2a libextractor-plugins libfaac0 libfile-slurp-perl libftdi1 libgck-1-0 libgcr-3-1 libgcr-3-common libgee2 libgksu2-0 libgsf-1-114 libgsf-1-common libgtop2-7 libgtop2-common libhtml-fromtext-perl libhtml-tableextract-perl libhttp-cache-transparent-perl libhttp-server-simple-perl libindicator3-7 libjpeg62 libjson-perl libjson-xs-perl liblingua-preferred-perl liblist-moreutils-perl liblog-tracemessages-perl libmath-round-perl libmjpegtools-1.9 libmodule-runtime-perl libmysqlclient15off libmyth-0.25-0 libmyth-python libmythtv-perl libnet-dns-perl libnet-domain-tld-perl libnet-ip-perl libnet-upnp-perl libnotify-bin libpackage-deprecationmanager-perl libpackage-stash-perl libpackage-stash-xs-perl libpam-cap libpam-gnome-keyring libparams-classify-perl libparams-util-perl libparams-validate-perl libparse-recdescent-perl libportaudio2 libqt3-mt libquicktime2 libregexp-common-perl librpm2 librpmio2 libsub-install-perl libterm-progressbar-perl libterm-readkey-perl libtext-bidi-perl libtie-ixhash-perl libtry-tiny-perl libtwolame0 libunicode-string-perl libunity9 libva-glx1 libva-x11-1 libvte-2.90-9 libvte-2.90-common libwww-mechanize-perl libx264-120 libxine1-xvdr libxml-dom-perl libxml-libxml-perl libxml-libxslt-perl libxml-perl libxml-regexp-perl libxmltv-perl libxml-twig-perl libxml-writer-perl libxml-xpath-perl libyaml-syck-perl lirc lmce-mythtv-scripts lmce-windowutils mjpegtools mysql-client mythtv-backend mythtv-common mythtv-database mythtv-frontend mythtv-transcode-utils mythweb netcat netcat-traditional php-mythtv pluto-mythtv-player pluto-mythtv-plugin pluto-vdr pluto-vdr-plugin pwgen python-aptdaemon.gtk3widgets python-imdbpy python-lxml python-mysqldb python-urlgrabber rpm-common setserial software-properties-common software-properties-gtk transcode-doc transcode ttf-dejavu twolame unixodbc update-manager update-notifier vdr vdr-plugin-streamdev-client vdr-plugin-streamdev-server vdr-plugin-xineliboutput xineliboutput-sxfe xmltv-util -yd --allow-unauthenticated

#these were ultimately too large for the squashfs
# download all non-src pluto-* packages to have in deb-cache
#LC_ALL=C chroot $TEMPDIR apt-get install pluto-bluetooth-dongle pluto-chromoflex pluto-cm11a pluto-cm15a pluto-ffmpeg pluto-gc100 pluto-generic-serial-device pluto-hdhomerun pluto-hvr-1600 pluto-irtrans-ethernet pluto-irtrans-wrapper pluto-libbd pluto-mplayer pluto-msiml-disp-butt pluto-mythtv-includes pluto-nvidia-video-drivers pluto-plcbus pluto-usb-uirt-0038 pluto-xml-data-plugin pluto-zwave-lighting -yd --allow-unauthenticated
# download all non-src lmce-* packages to have in deb-cache, not including anything game related cause it's too big.
#LC_ALL=C chroot $TEMPDIR apt-get install lmce-advanced-ip-camera lmce-agocontrol-bridge lmce-airplay-audio-player lmce-airplay-plugin lmce-airplay-streamer lmce-airplay-streamer-plugin lmce-datalog-database lmce-datalog-db lmce-datalogger-plugin lmce-dlna lmce-dpms-monitor lmce-enocean-tcm120 lmce-hai-omni-rs232 lmce-insteon lmce-omx-plugin lmce-onewire lmce-pandora-plugin lmce-phoenix-solo-usb lmce-qorbiter-skins-android lmce-qorbiter-skins-common lmce-qorbiter-skins-desktop lmce-qorbiter-skins-qt4libs lmce-qorbiter-skins-qt5libs lmce-qorbiter-skins-rpi lmce-rain8 lmce-roku lmce-screen-capture-camera lmce-shoutcast-radio-plugin lmce-squeezeslave lmce-transmission-client lmce-update-traversal lmce-vistaicm2 lmce-weather lmce-weather-plugin lmce-wiimote-support lmce-zwave-ozw -yd --allow-unauthenticated

# Remove fluffy and our providers Ubuntu mirror from the sources.list
rm -f $TEMPDIR/etc/apt/sources.list.d/fluffy.list

# Make sure fluffy is not in the list of available repositories
LC_ALL=C chroot $TEMPDIR apt-get update || :

# Ensure the image is fully upgraded
LC_ALL=C chroot $TEMPDIR apt-get dist-upgrade -y --allow-unauthenticated || :

# Downgrade python for ubiquity to run
LC_ALL=C chroot $TEMPDIR apt-get install python=2.7.3-0ubuntu2 python-minimal=2.7.3-0ubuntu2 -y --force-yes --allow-unauthenticated

# Add ubuntu sources to the sources.list file so confirm dependencies can work with it.
cat $TEMPDIR/etc/apt/sources.list.d/ubuntu.list >> $TEMPDIR/etc/apt/sources.list
rm -f $TEMPDIR/etc/apt/sources.list.d/ubuntu.list

# Remove the apt proxy if it exists so it is not transferred to the diskless tarball.
rm -f $TEMPDIR/etc/apt/apt.conf.d/02proxy

# Create the initial MD diskless image.
#LC_ALL=C chroot $TEMPDIR /usr/pluto/bin/Diskless_CreateTBZ.sh || :

# As Diskless_CreateTBZ.sh bind mounts our var/cache/apt dir, we now have all
# the needed files in var/cache/apt/archive and can move them to /usr/pluto/deb-cache
# and rebuild the Packages* files.
mkdir -p $TEMPDIR/usr/pluto/deb-cache
mv -f $TEMPDIR/var/cache/apt/archives/*.deb $TEMPDIR/usr/pluto/deb-cache || :

cat <<-"EOF" > $TEMPDIR/usr/pluto/bin/update-deb-cache.sh
	#!/bin/bash

        # Remove all but the latest package
        thedir="/usr/pluto/deb-cache"
        X=$(dpkg -l|grep "^ii"|awk '{print $2,$3}')
        odd="1"
        for var in $X
        do
                if [[ "$odd" -eq "1" ]]; then
                        package="$var"
                        odd="0"
                else
                        version="$var"
                        odd="1"
                        all="$package"
                        all+="_*"
                        latest="${thedir}/${package}"
                        latest+="_$version"
                        latest+="_i386.deb"
                        Alls=$(find "$thedir" -iname "$all")
                        for each in $Alls
                        do
                                if [[ "$each" != "$latest" ]]; then
                                        rm "$each"
                                fi
                        done
                fi
        done > /dev/null

	# update the packages list
	cd /usr/pluto/deb-cache
	dpkg-scanpackages -m . /dev/null | tee Packages | gzip -9c > Packages.gz
	EOF
chmod +x $TEMPDIR/usr/pluto/bin/update-deb-cache.sh
LC_ALL=C chroot $TEMPDIR /usr/pluto/bin/update-deb-cache.sh

# We now have the problem, that Pluto/LinuxMCEs startup scripts get executed WITHOUT the
# use of invoke-rc.d - instead, they use screen.
LC_ALL=C chroot $TEMPDIR service netatalk stop 2>/dev/null || :

rm $TEMPDIR/usr/sbin/invoke-rc.d
mv $TEMPDIR/usr/sbin/invoke-rc.d.orig $TEMPDIR/usr/sbin/invoke-rc.d

rm $TEMPDIR/sbin/start $TEMPDIR/sbin/restart $TEMPDIR/sbin/initctl
mv $TEMPDIR/sbin/start.orig $TEMPDIR/sbin/start
mv $TEMPDIR/sbin/restart.orig $TEMPDIR/sbin/restart
mv $TEMPDIR/sbin/initctl.orig $TEMPDIR/sbin/initctl

rm $TEMPDIR/usr/bin/screen
mv $TEMPDIR/usr/bin/screen.orig $TEMPDIR/usr/bin/screen

umount $TEMPDIR/dev/pts
umount $TEMPDIR/proc
umount $TEMPDIR/sys

kill $(lsof $TEMPDIR|grep $TEMPDIR|grep mysqld|cut -d" " -f3|sort -u|head -1) || :
sleep 10
umount $TEMPDIR/dev

# Show the current usage
du -h --max-depth=1 $TEMPDIR |& grep -v "du: cannot access"

# Get rid of existing network assignments
rm -f $TEMPDIR/etc/udev/rules.d/70-persistent-net-rules

# Get rid of the machine-id
rm -f $TEMPDIR/var/lib/dbus/machine-id

# Clean up debconf back to dialog
echo debconf debconf/frontend select dialog | LC_ALL=C chroot $TEMPDIR debconf-set-selections 

# Let's unmount everything, and run fsck to make sure the image is nice and clean.
echo lsof $TEMPDIR
lsof $TEMPDIR || :
echo "unmount and then remove $TEMPDIR"
umount $TEMPDIR
rm -fR $TEMPDIR

#fsck.ext2 $IMAGEFILE
# make a backup of the old rz'd image.
#if [ -f /var/www/$DISTRONO.rz ]; then
#	mv -f /var/www/$DISTRONO.rz /var/www/$DISTRONO.old.rz
#fi
#rzip -k $IMAGEFILE -o /var/www/$DISTRONO.rz
#chown www-data: /var/www/$DISTRONO.rz
#cp /var/www/$DISTRONO.rz /opt
#cp $IMAGEFILE /opt/$DISTRONO.img

echo "Copy as $DISTRONO into current dir"
cp $IMAGEFILE $OLDDIR/$DISTRONO

# All finished
#pushd /var/www
#SIZE=`ls -lh $DISTRONO.rz | cut -d" " -f 5|head -1`
#wget --quiet http://vt100.at/announce.php?text=$DISTRONO.rz\ ready\ for\ l3top-size\ $SIZE -O /dev/null
#popd
exit 0

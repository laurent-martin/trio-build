#!/bin/bash
# Laurent Martin 2018
# debian only

SCRIPT_FOLDER=$(cd $(dirname $0);pwd -P)
PKG_DEST="${SCRIPT_FOLDER}/pkg"
mkdir -p ${PKG_DEST}

# recommended location for systemd unit files
systemd_unit_file_folder=/etc/systemd/system

#-----------------------------------------------------------
# Global methods

PRE_REQ_SUFFIX=_prerequisites
DOWNLOAD_SUFFIX=_download

# exit if specified package is not installed
assert_installed(){
	local pkg_name=$1
	if ! dpkg -s ${pkg_name} > /dev/null 2>&1;then
		echo "Error: missing package: ${pkg_name}" 1>&2
		exit 1
	fi
}

# install specified packages
install_packages(){
	sudo apt-get install --yes --quiet=2 "${@}"
}

# build a debian package
# $1 : pkg_name : name of package
# $2 : down_name : type of source fetch : git or archive
# required functions:
# ${pkg_name}_${down_name}${DOWNLOAD_SUFFIX}
# ${pkg_name}${PRE_REQ_SUFFIX}
# if env var KEEP is set to non empty value, then build folder is kept, else deleted
build_deb(){
	local pkg_name=$1
	local down_name=$2
	# make sure required packages for package build are installed
	install_packages cdbs debhelper pkg-config
	download_func=${pkg_name}_${down_name}_download
	build_dir=${pkg_name}-build
	src_dir=${pkg_name}
	rm -fr ${build_dir}
	mkdir ${build_dir} || exit 1
	pushd ${build_dir} || exit 1
	echo "Downloading ${pkg_name}"
	eval ${download_func} ${src_dir} || exit 1
	pushd ${src_dir} || exit 1
	cd $PWD
	echo "Installing pre-requisites for build of ${pkg_name}"
	eval ${pkg_name}${PRE_REQ_SUFFIX} || exit 1
	LC_ALL=C dpkg-buildpackage --build=binary --unsigned-changes || exit 1
	popd # back to build_dir
	mv ${pkg_name}*.deb "${PKG_DEST}"
	popd
	test -z "$KEEP" && rm -fr ${build_dir}
}

# list modules that can be built on stdout
list_build_methods(){
	declare -F|while read line;do
		line=${line#declare -f }
		case $line in *${DOWNLOAD_SUFFIX})
			line=${line%${DOWNLOAD_SUFFIX}}
			echo build_deb ${line/_/ }
		esac
	done
}
#-----------------------------------------------------------
# pthsem
#
libpthsem_prerequisites(){
	:
}
libpthsem_archive_download(){
	local subfolder=$1
	wget https://www.auto.tuwien.ac.at/~mkoegler/pth/pthsem_2.0.8.tar.gz || exit 1
	tar zxf pthsem_2.0.8.tar.gz || exit 1
	mv pthsem-2.0.8 ${subfolder} || exit 1
}
# dev package necessary to build linknx
libpthsem_install_dev(){
	sudo dpkg -i "${PKG_DEST}"/libpthsem20_*.deb "${PKG_DEST}"/libpthsem-dev_*.deb
}
libpthsem_install(){
	sudo dpkg -i "${PKG_DEST}"/libpthsem20_*.deb
}
#-----------------------------------------------------------
# linknx
#
# default location of linknx conf file
LINKNX_CONF_FILE_PATH=/etc/linknx.xml
linknx_prerequisites(){
	assert_installed libpthsem-dev
	install_packages libesmtp-dev liblog4cpp5-dev
		#    liblua5.1-0-dev libxml2 dpkg
}
linknx_archive_download(){
	local subfolder=$1
	wget https://github.com/linknx/linknx/archive/0.0.1.36.zip || exit 1
	mv 0.0.1.36.zip linknx-0.0.1.36.zip
	unzip linknx-0.0.1.36.zip || exit 1
	mv linknx-0.0.1.36 ${subfolder} || exit 1
	pushd linknx || exit 1
	linknx_add_deb_pkg_info
	popd # out of linknx
}
linknx_git_download(){
	install_packages git
	git clone https://github.com/linknx/linknx.git
	pushd linknx || exit 1
	git checkout releases
	tar zcf linknx_0.0.1.36.orig.tar.gz linknx
	linknx_add_deb_pkg_info
	popd # out of linknx
}
linknx_install(){
	sudo dpkg -i "${PKG_DEST}"/linknx_*.deb
}
linknx_add_deb_pkg_info(){
	# bare with me, little hack, ant not needed really, but needed by build
	test -e /usr/bin/ant || sudo ln -s /bin/true /usr/bin/ant
	echo "== populating debian folder"
	mkdir -p debian || exit 1
	pushd debian
	# name of this package
	pkgname=linknx
	# absolute path to debian folder
	debian_absolute=$(pwd)
	# install folder corresponding to root of target system
	install_destdir=${debian_absolute}/${pkgname}
	mkdir -p ${install_destdir} || exit 1
	# location of bin folder where linknx will be installed on target
	install_prefix=/usr
	# create necessary files for debian package creation
	mkdir -p source || exit 1
	echo '3.0 (quilt)' > source/format
	touch copyright
	echo 10 > compat
	cat>changelog<<EOF
linknx (0.0.1.36-1) UNRELEASED; urgency=medium

  * Initial release. (Closes: #XXXXXX)

 --  <pi@raspberrypi>  Tue, 17 Apr 2018 22:18:24 +0000
EOF
	cat>rules<<EOF
#!/usr/bin/make -f
%:
	dh \$@
override_dh_auto_configure:
	dh_auto_configure -- --without-pth-test --enable-smtp --with-log4cpp --with-lua --with-mysql
override_dh_auto_install:
	\$(MAKE) DESTDIR=${install_destdir} prefix=${install_prefix} install
EOF
	chmod a+x rules
	cat>control<<EOF
Source: linknx
Maintainer: Todo <todo@todo.todo>
Section: misc
Priority: optional
Standards-Version: 3.9.2
Build-Depends: debhelper (>= 9), libpthsem-dev

Package: linknx
Architecture: any
Depends: ${shlibs:Depends}, ${misc:Depends}, libpthsem20
Description: knx automation
 linknx
EOF
	# put default config file
	mkdir -p ${install_destdir}$(dirname ${LINKNX_CONF_FILE_PATH})
	cp ../conf/linknx.xml ${install_destdir}${LINKNX_CONF_FILE_PATH}
 	# create service unit file
 	mkdir -p ${install_destdir}/${systemd_unit_file_folder}
	cat>${install_destdir}/${systemd_unit_file_folder}/linknx.service<<EOF
[Unit]
Description=Linknx Server
After=knxd.service
[Service]
ExecStart=${install_prefix}/bin/linknx --daemon=/var/log/linknx.log --config=${LINKNX_CONF_FILE_PATH} --pid-file=/run/linknx.pid -w
PIDFile=/run/linknx.pid
Type=forking
Restart=always
[Install]
WantedBy=multi-user.target
EOF
	popd # out of debian
}

#-----------------------------------------------------------
# knxd
#
knxd_prerequisites(){
	install_packages libusb-1.0-0-dev libsystemd-dev dh-systemd libev-dev cmake libtool
	#build-essential git-core debhelper cdbs autoconf automake libtool libusb-1.0-0-dev libsystemd-daemon-dev dh-systemd --yes -y -qq
}
knxd_git_download(){
	install_packages git
	git clone https://github.com/knxd/knxd.git
	pushd knxd || exit 1
	git checkout stable
	tar zcf knxd_0.14.tar.gz knxd
	popd # out of knxd
}
knxd_install(){
	sudo dpkg -i "${PKG_DEST}"/knxd_*.deb "${PKG_DEST}"/knxd-tools_*.deb
}
#-----------------------------------------------------------
# knxweb
#
knxweb_git_download(){
	install_packages git
	git clone https://github.com/linknx/knxweb.git
	pushd knxweb || exit 1
	knxweb_add_deb_pkg_info
	popd # out of knxweb
}

knxweb_prerequisites(){
	:
}

knxweb_add_deb_pkg_info(){
	pkgname=knxweb
	pkgvers=$(cat version)
	install_root=/opt/${pkgname}
	echo "== populating debian folder"
	mkdir -p debian || exit 1
	pushd debian
	mkdir -p source || exit 1
	#mkdir -p ${pkgname} || exit 1
	echo '3.0 (quilt)' > source/format
	touch copyright
	echo 10 > compat
	cat>changelog<<EOF
${pkgname} (${pkgvers}) UNRELEASED; urgency=medium

  * Initial release. (Closes: #XXXXXX)

 --  <pi@raspberrypi>  Tue, 17 Apr 2018 22:18:24 +0000
EOF
	cat>rules<<EOF
#!/usr/bin/make -f
%:
	dh \$@
EOF
	chmod a+x rules
	cat>control<<EOF
Source: ${pkgname}
Maintainer: Todo <todo@todo.todo>
Section: misc
Priority: optional
Version: ${pkgvers}
Standards-Version: 3.9.2
Build-Depends: debhelper (>= 9)

Package: ${pkgname}
Architecture: all
Depends: ${shlibs:Depends}, ${misc:Depends}
Description: knx automation
 ${pkgname}
EOF
	popd # out of debian
	cat>Makefile<<EOF
all:
	echo MAKE ALL
INSTROOT=\$(DESTDIR)${install_root}
install:
	mkdir -p \$(INSTROOT)
	mv *.php favicon.* css images js include lang lib objectUpdater.jar robots.txt htaccess* pictures template \$(INSTROOT)
	mv design plugins \$(INSTROOT)
	chown -R www-data: \$(INSTROOT)
EOF
}

install_all(){
	libpthsem_install
	linknx_install
	knxd_install
	knxweb_install
	install_packages apache2 php libapache2-mod-php php7.2-xml
	# sudo a2ensite 050-knxweb
	# sudo a2dissite 000-default
	# sudo systemctl reload apache2
}

knxweb_install(){
	sudo dpkg -i "${PKG_DEST}"/knxweb_*.deb
}

case $# in
0) cat<<EOF
Usage: $0 build_deb <module> <archive type>
o set KEEP env var to keep build folder, else it is deleted after build, amnd only .deb is kept.
  export KEEP=1
o list of build methods:
EOF
list_build_methods
cat<<EOF
o Example of full build:
(note that ubuntu has knxd pre-build, can be installed with: apt install knxd)
$0 build_deb libpthsem archive
$0 libpthsem_install_dev
$0 build_deb linknx archive
$0 build_deb knxd git
$0 build_deb knxweb git
$0 install_all
chown -R www-data: /opt/knxweb
cp 0Config/etc/knxd.ini /etc
sed -i.bak -Ee "s/^(KNXD_OPTS=).*/\1\/etc\/knxd.ini/" /etc/knxd.conf
cp 0Config/etc/knxweb.conf /etc/apache2/sites-available
a2ensite knxweb
systemctl reload apache2
cp 0Config/etc/linknx.xml /etc
mkdir -p /var/lib/linknx/persist
cp 0Config/etc/systemd/linknx.service /lib/systemd/system/
systemctl enable linknx.service
systemctl start linknx.service
chown -R www-data /opt/knxweb/include/config.xml
EOF
# my old knxd options
# KNXD_OPTS="--Discovery --Tunnelling --Routing --Server --listen-local --trace=255 --error=5 --layer2=ipt:192.168.0.111:3671"
;;
*) eval "$@";;
esac

# sudo apt-get install apache2
# TODO: /etc/apache2/sites-available/001-knxweb.conf<<EOF
# as root:
# a2dissite 000-default
# a2ensite 001-knxweb
# systemctl reload apache2
# apache_user=$(apachectl -D DUMP_RUN_CFG 2>&1|sed -nEe 's/^User: name="(.*)".*/\1/p')
# chown -R $apache_user: /opt/knxweb
# apt-get install php7.0
# apt-get install libapache2-mod-php
	
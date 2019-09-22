#!/bin/bash
# Laurent Martin 2018

PKG_DEST="${PWD}/pkg"
mkdir -p ${PKG_DEST}

#-----------------------------------------------------------
# generic
#
check_installed(){
	local pkg_name=$1
	if ! dpkg -s ${pkg_name} > /dev/null 2>&1;then
		echo "Error: missing package: ${pkg_name}"
		exit 1
	fi
}

install_packages(){
	sudo apt-get install --yes --quiet=2 "${@}"
}

build_deb(){
	local pkg_name=$1
	local down_name=$2
	# make sure build pre-req are installed
	install_packages cdbs debhelper
	download_func=${pkg_name}_download_${down_name}
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
	eval ${pkg_name}_prerequisites || exit 1
	LC_ALL=C dpkg-buildpackage --build=binary --unsigned-changes || exit 1
	popd # back to build_dir
	mv ${pkg_name}*.deb "${PKG_DEST}"
	popd
	test -z "$KEEP" && rm -fr ${build_dir}
}

#-----------------------------------------------------------
# pthsem
#
libpthsem_download_archive(){
	local subfolder=$1
	wget https://www.auto.tuwien.ac.at/~mkoegler/pth/pthsem_2.0.8.tar.gz || exit 1
	tar zxf pthsem_2.0.8.tar.gz || exit 1
	mv pthsem-2.0.8 ${subfolder} || exit 1
}

libpthsem_install_dev(){
	sudo dpkg -i "${PKG_DEST}"/libpthsem20_*.deb "${PKG_DEST}"/libpthsem-dev_*.deb
}
libpthsem_install(){
	sudo dpkg -i "${PKG_DEST}"/libpthsem20_*.deb
}
libpthsem_prerequisites(){
	:
}
#-----------------------------------------------------------
# linknx
#
linknx_download_archive(){
	local subfolder=$1
	wget https://github.com/linknx/linknx/archive/0.0.1.36.zip || exit 1
	mv 0.0.1.36.zip linknx-0.0.1.36.zip
	unzip linknx-0.0.1.36.zip || exit 1
	mv linknx-0.0.1.36 ${subfolder} || exit 1
	pushd linknx || exit 1
	linknx_add_deb_pkg_info
	popd # out of linknx
}

linknx_download_git(){
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
	debian_absolute=$(pwd)
	pkgname=linknx
	install_destdir=${debian_absolute}/${pkgname}
	install_prefix=/usr
	default_conf_file=/var/lib/linknx/linknx.xml
	systemd_conf=${install_destdir}/etc/systemd/system
	linknx_conf=${install_destdir}$(dirname ${default_conf_file})
	mkdir -p source || exit 1
	mkdir -p linknx || exit 1
	echo '3.0 (quilt)' > source/format
	touch copyright
	echo 10 > compat
	cat<<EOF>changelog
linknx (0.0.1.36-1) UNRELEASED; urgency=medium

  * Initial release. (Closes: #XXXXXX)

 --  <pi@raspberrypi>  Tue, 17 Apr 2018 22:18:24 +0000
EOF
	cat<<EOF>rules
#!/usr/bin/make -f
%:
	dh \$@
override_dh_auto_configure:
	dh_auto_configure -- --without-pth-test --enable-smtp --with-log4cpp --with-lua --with-mysql
override_dh_auto_install:
	\$(MAKE) DESTDIR=${install_destdir} prefix=${install_prefix} install
EOF
	chmod a+x rules
	cat<<EOF>control
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
	cat<<EOF>changelog
linknx (0.0.1.36-1) UNRELEASED; urgency=medium

  * Initial release. (Closes: #XXXXXX)

 --  <pi@raspberrypi>  Tue, 17 Apr 2018 22:18:24 +0000
EOF
	mkdir -p ${linknx_conf}
	cp ../conf/linknx.xml ${linknx_conf}
 	mkdir -p ${systemd_conf}
	cat<<EOF>${systemd_conf}/linknx.service
[Unit]
Description=Linknx Server
After=knxd.service
[Service]
ExecStart=${install_prefix}/bin/linknx --daemon=/var/log/linknx.log --config=${default_conf_file} --pid-file=/run/linknx.pid -w
PIDFile=/run/linknx.pid
Type=forking
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    #chmod a+x /etc/systemd/system/linknx.service
	popd # out of debian
}

linknx_prerequisites(){
	check_installed libpthsem-dev
	install_packages libesmtp-dev liblog4cpp5-dev
		#    liblua5.1-0-dev libxml2 dpkg
}

#-----------------------------------------------------------
# knxd
#
knxd_prerequisites(){
	install_packages libusb-1.0-0-dev libsystemd-dev dh-systemd libev-dev cmake libtool
	#build-essential git-core debhelper cdbs autoconf automake libtool libusb-1.0-0-dev libsystemd-daemon-dev dh-systemd --yes -y -qq
}

knxd_download_git(){
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
knxweb_download_git(){
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
	mkdir -p ${pkgname} || exit 1
	echo '3.0 (quilt)' > source/format
	touch copyright
	echo 10 > compat
	cat<<EOF>changelog
${pkgname} (${pkgvers}) UNRELEASED; urgency=medium

  * Initial release. (Closes: #XXXXXX)

 --  <pi@raspberrypi>  Tue, 17 Apr 2018 22:18:24 +0000
EOF
	cat<<EOF>rules
#!/usr/bin/make -f
%:
	dh \$@
EOF
	chmod a+x rules
	cat<<EOF>control
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
	cat<<EOF>changelog
${pkgname} (${pkgvers}) UNRELEASED; urgency=medium

  * Initial release. (Closes: #XXXXXX)

 --  <pi@raspberrypi>  Tue, 17 Apr 2018 22:18:24 +0000
EOF
	popd # out of debian
	cat<<EOF>Makefile
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
	install_packages apache2
	# sudo a2ensite 050-knxweb
	# sudo a2dissite 000-default
	# sudo systemctl reload apache2
}

knxweb_install(){
	sudo dpkg -i "${PKG_DEST}"/knxweb_*.deb
}

# restore:
# sudo dpkg -r $(diff allfiles_find_new_sort.txt allfiles_find_sort.txt|sed -nEe 's/^< \/var\/lib\/dpkg\/info\/(.*)\.list$/\1/p')

case $# in
0) cat<<EOF
export KEEP=1
build_deb libpthsem archive
libpthsem_install_dev
build_deb linknx archive
build_deb knxd git
build_deb knxweb git
install_all
EOF
;;
*) eval "$@";;
esac



exit 0

# sudo apt-get install apache2
cat<<EOF>/etc/apache2/sites-available/001-knxweb.conf
xxx
EOF


as root:
a2dissite 000-default
a2ensite 001-knxweb
systemctl reload apache2
apache_user=$(apachectl -D DUMP_RUN_CFG|sed -nEe 's/^User: name="(.*)".*/\1/p')
chown -R $apache_user: /opt/knxweb
apt-get install php7.0
apt-get install libapache2-mod-php
	
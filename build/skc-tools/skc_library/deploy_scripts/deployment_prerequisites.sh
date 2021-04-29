#!/bin/bash

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

install_pre_requisites()
{
	if [[ "$OS" == "rhel" && "$VER" == "8.1" || "$VER" == "8.2" ]]; then
		echo "installing libgda and softhsm"
		dnf install -qy https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/e/epel-release-8-10.el8.noarch.rpm || exit 1
		dnf install -qy https://dl.fedoraproject.org/pub/fedora/linux/releases/33/Everything/x86_64/os/Packages/s/softhsm-2.6.1-3.fc33.4.x86_64.rpm || exit 1
		dnf install -qy https://dl.fedoraproject.org/pub/fedora/linux/releases/33/Everything/x86_64/os/Packages/l/libgda-5.2.9-6.fc33.x86_64.rpm || exit 1
		dnf install -qy https://dl.fedoraproject.org/pub/fedora/linux/releases/33/Everything/x86_64/os/Packages/l/libgda-sqlite-5.2.9-6.fc33.x86_64.rpm || exit 1
		echo "installing devel packages"
		dnf install -qy yum-utils tar wget gcc-c++ kernel-devel kernel-headers dkms make jq protobuf jsoncpp jsoncpp-devel nginx || exit 1
		groupadd intel
		usermod -G intel nginx
		\cp -rpf bin/pkcs11.so /usr/lib64/engines-1.1/
		\cp -rpf bin/libp11.so.3.4.3 /usr/lib64/
		ln -sf /usr/lib64/libp11.so.3.4.3 /usr/lib64/libp11.so
		ln -sf /usr/lib64/engines-1.1/pkcs11.so /usr/lib64/engines-1.1/libpkcs11.so
		ln -sf /usr/lib64/libjsoncpp.so /usr/lib64/libjsoncpp.so.0

	elif [[ "$OS" == "ubuntu" && "$VER" == "18.04" ]]; then
		apt install -y build-essential ocaml automake autoconf libtool tar wget python libssl-dev || exit 1
		apt-get install -y libcurl4-openssl-dev libprotobuf-dev curl || exit 1
		apt install -y dkms make jq libjsoncpp1 libjsoncpp-dev softhsm libgda-5.0-4 nginx || exit 1
		groupadd intel
		usermod -G intel www-data
		\cp -rpf bin/pkcs11.so /usr/lib/x86_64-linux-gnu/engines-1.1/
		\cp -rpf bin/libp11.so.3.4.3 /usr/lib/
		ln -sf /usr/lib/libp11.so.3.4.3 /usr/lib/libp11.so
		ln -sf /usr/lib/x86_64-linux-gnu/engines-1.1/pkcs11.so /usr/lib/x86_64-linux-gnu/engines-1.1/libpkcs11.so
		ln -sf /usr/lib/libjsoncpp.so /usr/lib/libjsoncpp.so.0
	else
		echo "${red} Unsupported OS. Please use RHEL 8.1/8.2 or Ubuntu 18.04 ${reset}"
		exit 1
	fi
}

install_pre_requisites

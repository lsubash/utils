#!/bin//bash

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')

install_pre_requisites()
{
	if [[ "$OS" == "rhel" && "$VER" == "8.1" || "$VER" == "8.2" ]]; then
		dnf install -qy bc wget tar git gcc-c++ make automake autoconf libtool yum-utils p11-kit-devel cppunit-devel openssl-devel || exit 1
	elif [[ "$OS" == "ubuntu" && "$VER" == "18.04" ]]; then
		apt install -y build-essential ocaml ocamlbuild automake autoconf libtool cmake perl libcppunit-dev libssl-dev || exit 1
                wget http://archive.ubuntu.com/ubuntu/pool/main/libt/libtasn1-6/libtasn1-6_4.16.0-2_amd64.deb || exit 1
                wget http://archive.ubuntu.com/ubuntu/pool/main/libf/libffi/libffi8ubuntu1_3.4~20200819gead65ca871-0ubuntu3_amd64.deb || exit 1
                wget http://archive.ubuntu.com/ubuntu/pool/main/p/p11-kit/libp11-kit0_0.23.22-1_amd64.deb || exit 1
                wget http://archive.ubuntu.com/ubuntu/pool/main/p/p11-kit/libp11-kit-dev_0.23.22-1_amd64.deb || exit 1

                apt install -f -y ./libtasn1-6_4.16.0-2_amd64.deb || exit 1
                apt install -f -y ./libffi8ubuntu1_3.4~20200819gead65ca871-0ubuntu3_amd64.deb || exit 1
                apt install -f -y ./libp11-kit0_0.23.22-1_amd64.deb || exit 1
                apt install -f -y ./libp11-kit-dev_0.23.22-1_amd64.deb || exit 1

		rm -rf *.deb
	else
		echo "Unsupported OS. Please use RHEL 8.1/8.2 or Ubuntu 18.04"
		exit 1
	fi
}

install_pre_requisites

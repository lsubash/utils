#!/bin/bash
SGX_VERSION=2.13.3
SAMPLEAPPS_DIR=sample_apps
SAMPLEAPPS_BIN_DIR=$SAMPLEAPPS_DIR/bin

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

SGX_URL="https://download.01.org/intel-sgx/sgx-linux/${SGX_VERSION}/distro/$OS_FLAVOUR-server"

install_psw_qpl_qgl()
{
	if [ "$OS" == "rhel" ]; then
		wget -q $SGX_URL/sgx_rpm_local_repo.tgz || exit 1
                \cp -pf sgx_rpm_local_repo.tgz $SAMPLEAPPS_BIN_DIR
		tar -xf sgx_rpm_local_repo.tgz || exit 1
		yum-config-manager --add-repo file://$PWD/sgx_rpm_local_repo || exit 1
		dnf install -qy --nogpgcheck libsgx-launch libsgx-uae-service libsgx-urts libsgx-dcap-ql-devel || exit 1
		rm -rf sgx_rpm_local_repo sgx_rpm_local_repo.tgz /etc/yum.repos.d/*sgx_rpm_local_repo.repo
	elif [ "$OS" == "ubuntu" ]; then
		echo 'deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu/ bionic main' | sudo tee /etc/apt/sources.list.d/intel-sgx.list
		wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | sudo apt-key add - || exit 1
		apt update -y || exit 1
		apt install -y libsgx-launch libsgx-uae-service libsgx-urts libsgx-dcap-ql-dev || exit 1
	fi
}

install_psw_qpl_qgl

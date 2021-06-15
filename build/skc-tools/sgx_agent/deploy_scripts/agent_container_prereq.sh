#!/bin/bash
SGX_DRIVER_VERSION=1.41
KDIR=/lib/modules/$(uname -r)/build
SGX_INSTALL_DIR=/opt/intel
MP_RPM_VER=1.10.103.1-1
SGX_AGENT_BIN=bin

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

cat $KDIR/.config | grep 'CONFIG_INTEL_SGX=y\|CONFIG_X86_SGX=y' > /dev/null
INKERNEL_SGX=$?

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')

uninstall_sgx_agent_dependencies()
{
	echo "uninstalling sgx psw/qgl and multi-package agent rpm"
	if [ "$OS" == "rhel" ]; then
		dnf remove -y libsgx-dcap-ql libsgx-ra-uefi
	elif [ "$OS" == "ubuntu" ]; then
		apt remove -y libsgx-dcap-ql libsgx-ra-uefi
	fi
	
	if [[ "$INKERNEL_SGX" -eq 1 ]]; then
		DRIVER_VERSION=`modinfo intel_sgx | grep -w 'version:' | awk '{print $2}'`
		if [ "$DRIVER_VERSION" == "" ]; then
			echo "SGX DCAP driver not installed"
			return
		fi
		if [ "$DRIVER_VERSION" != "$SGX_DRIVER_VERSION" ]; then
			echo "uninstalling sgx dcap driver"
			systemctl stop aesmd
			sh $SGX_INSTALL_DIR/sgxdriver/uninstall.sh
			if [[ $? -ne 0 ]]; then
				echo "${red} sgx dcap driver uninstallation failed. exiting ${reset}"
				exit 1
			fi
			systemctl start aesmd
		fi
	else
                echo "found inbuilt sgx driver, skipping dcap driver uninstallation"
        fi

}

install_prerequisites()
{
	source deployment_prerequisites.sh
	if [[ $? -ne 0 ]]; then
		echo "${red} sgx agent pre-requisite package installation failed. exiting ${reset}"
		exit 1
	fi
	echo "${green} sgx agent pre-requisite package installation completed ${reset}"
}

install_dcap_driver()
{
	chmod u+x $SGX_AGENT_BIN/sgx_linux_x64_driver_${SGX_DRIVER_VERSION}.bin
	if [[ "$INKERNEL_SGX" -eq 1 ]]; then
                DRIVER_VERSION=`modinfo intel_sgx | grep -w 'version:' | awk '{print $2}'`
                if [ "$DRIVER_VERSION" == "" ] || [ "$DRIVER_VERSION" != "$SGX_DRIVER_VERSION" ]; then
                        echo "Installing sgx dcap driver...."
                        ./$SGX_AGENT_BIN/sgx_linux_x64_driver_${SGX_DRIVER_VERSION}.bin -prefix=$SGX_INSTALL_DIR || exit 1
                        echo "sgx dcap driver installed successfully"
                else
                        echo "sgx dcap driver with same version $DRIVER_VERSION already installed, skipping installation..."
                fi
        else
                echo "found inbuilt sgx driver, skipping dcap driver installation"
        fi
}

install_psw_qgl()
{
	if [ "$OS" == "rhel" ]; then
		tar -xf $SGX_AGENT_BIN/sgx_rpm_local_repo.tgz
		yum-config-manager --add-repo file://$PWD/sgx_rpm_local_repo || exit 1
		dnf install -qy --nogpgcheck libsgx-dcap-ql || exit 1
		rm -rf sgx_rpm_local_repo /etc/yum.repos.d/*sgx_rpm_local_repo.repo
	elif [ "$OS" == "ubuntu" ]; then
		echo 'deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu/ bionic main' | sudo tee /etc/apt/sources.list.d/intel-sgx.list
		wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | sudo apt-key add -
		apt update -y || exit 1
		apt install -y libsgx-dcap-ql || exit 1
	fi
	echo "${green} sgx psw and qgl installed ${reset}"
}
	

uninstall_sgx_agent_dependencies
install_prerequisites
install_dcap_driver
install_psw_qgl

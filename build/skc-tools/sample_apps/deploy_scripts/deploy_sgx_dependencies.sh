#!/bin/bash
SAMPLEAPPS_BIN=bin
SGX_DRIVER_VERSION=1.41
SGX_INSTALL_DIR=/opt/intel

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

KDIR=/lib/modules/$(uname -r)/build
cat $KDIR/.config | grep 'CONFIG_INTEL_SGX=y\|CONFIG_X86_SGX=y' > /dev/null
INKERNEL_SGX=$?
DRIVER_VERSION=`modinfo intel_sgx | grep -w 'version:' | awk '{print $2}'`
modprobe -n intel_sgx 2>/dev/null
DRIVER_LOADED=$?

uninstall_skc()
{
	if [[ -d $SGX_INSTALL_DIR/sgxssl ]]; then
		echo "uninstalling sgxssl"
		rm -rf $SGX_INSTALL_DIR/sgxssl
	fi

	echo "uninstalling sgx psw/qgl"
        if [ "$OS" == "rhel" ]; then
		dnf remove -y libsgx-launch libsgx-uae-service libsgx-urts libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-devel libsgx-dcap-default-qpl-devel libsgx-dcap-default-qpl
        elif [ "$OS" == "ubuntu" ]; then
                apt purge -y libsgx-launch libsgx-uae-service libsgx-urts libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-dev libsgx-dcap-default-qpl-dev libsgx-dcap-default-qpl
        fi
	
	if [[ "$INKERNEL_SGX" -eq 1 ]]; then
                if [[ "$DRIVER_LOADED" -ne 0 ]]; then
                        echo "SGX DCAP driver not installed"
                elif [ "$DRIVER_VERSION" != "$SGX_DRIVER_VERSION" ]; then
                        echo "uninstalling sgx dcap driver"
                        sh $SGX_INSTALL_DIR/sgxdriver/uninstall.sh
                        if [[ $? -ne 0 ]]; then
                                echo "${red} sgx dcap driver uninstallation failed. exiting ${reset}"
                                exit 1
                        fi
                fi
        else
                echo "found inbuilt sgx driver, skipping dcap driver uninstallation"
        fi
}

install_prerequisites()
{
	source deployment_prerequisites.sh 
	if [[ $? -ne 0 ]]; then
		echo "${red} pre requisited installation failed ${reset}"
		exit 1
	fi
}

install_dcap_driver()
{
	chmod u+x $SAMPLEAPPS_BIN/sgx_linux_x64_driver_${SGX_DRIVER_VERSION}.bin
        if [[ "$INKERNEL_SGX" -eq 1 ]]; then
                if [[ "$DRIVER_VERSION" == ""  || "$DRIVER_VERSION" != "$SGX_DRIVER_VERSION" ]]; then
			echo "Installing sgx dcap driver...."
			./$SAMPLEAPPS_BIN/sgx_linux_x64_driver_${SGX_DRIVER_VERSION}.bin -prefix=$SGX_INSTALL_DIR || exit 1
			echo "${green} sgx dcap driver installed successfully ${reset}"
		elif [ "$DRIVER_VERSION" != "$SGX_DRIVER_VERSION" ]; then
			echo "${red} incompatible sgx dcap driver loaded, uninstall the existing driver before proceeding ${reset}"
			exit 1
		fi
	else
		echo "found inbuilt sgx driver, skipping dcap driver installation"
        fi
}

install_psw_qgl()
{
	if [ "$OS" == "rhel" ]; then
		tar -xf $SAMPLEAPPS_BIN/sgx_rpm_local_repo.tgz || exit 1
		yum-config-manager --add-repo file://$PWD/sgx_rpm_local_repo || exit 1
		dnf install -qy --nogpgcheck libsgx-launch libsgx-uae-service libsgx-urts libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-devel libsgx-dcap-default-qpl-devel libsgx-dcap-default-qpl || exit 1
		rm -rf sgx_rpm_local_repo /etc/yum.repos.d/*sgx_rpm_local_repo.repo
	elif [ "$OS" == "ubuntu" ]; then
		echo 'deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu/ bionic main' | sudo tee /etc/apt/sources.list.d/intel-sgx.list
		wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | sudo apt-key add - || exit 1
		apt update -y || exit 1
		apt install -y libsgx-launch libsgx-uae-service libsgx-urts || exit 1
		apt install -y libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-dev libsgx-dcap-default-qpl-dev libsgx-dcap-default-qpl || exit 1
	fi
	echo "${green} sgx psw and qgl libraries installed ${reset}"
	sed -i "s|PCCS_URL=.*|PCCS_URL=https://<csp-scs-ip>:<scs-port>/scs/sgx/certification/v1/|g" /etc/sgx_default_qcnl.conf
	sed -i "s|USE_SECURE_CERT=.*|USE_SECURE_CERT=FALSE|g" /etc/sgx_default_qcnl.conf
}

install_sgxssl()
{
        \cp -prf sgxssl $SGX_INSTALL_DIR
	echo "${green} sgxssl installed ${reset}"
}

uninstall_skc
install_prerequisites
install_dcap_driver
install_psw_qgl
install_sgxssl

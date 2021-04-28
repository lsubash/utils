#!/bin/bash
SGX_DRIVER_VERSION=1.41
SGX_INSTALL_DIR=/opt/intel
MP_RPM_VER=1.10.100.4-1
SGX_AGENT_BIN=bin

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

KDIR=/lib/modules/$(uname -r)/build
cat $KDIR/.config | grep 'CONFIG_INTEL_SGX=y\|CONFIG_X86_SGX=y' > /dev/null
INKERNEL_SGX=$?
DRIVER_VERSION=`modinfo intel_sgx | grep -w 'version:' | awk '{print $2}'`
modprobe -n intel_sgx 2>/dev/null
DRIVER_LOADED=$?

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')

uninstall_sgx_agent()
{
	echo "uninstalling sgx psw/qgl and multi-package agent rpm"
	if [ "$OS" == "rhel" ]; then
		dnf remove -y libsgx-dcap-ql libsgx-ra-uefi
	elif [ "$OS" == "ubuntu" ]; then
		apt remove -y libsgx-dcap-ql libsgx-ra-uefi
	fi
	echo "uninstalling PCKIDRetrieval Tool"
	rm -rf /usr/sbin/libdcap_quoteprov.so.1 /usr/sbin/pck_id_retrieval_tool_enclave.signed.so /usr/sbin/PCKIDRetrievalTool
	
	if [[ "$INKERNEL_SGX" -eq 1 ]]; then
		if [[ "$DRIVER_LOADED" -ne 0 ]]; then
			echo "SGX DCAP driver not installed"
		elif [ "$DRIVER_VERSION" != "$SGX_DRIVER_VERSION" ]; then
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

	echo "Uninstalling existing SGX Agent Installation...."
	sgx_agent uninstall --purge
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
                if [[ "$DRIVER_VERSION" == ""  || "$DRIVER_VERSION" != "$SGX_DRIVER_VERSION" ]]; then
                        echo "Installing sgx dcap driver...."
                        ./$SGX_AGENT_BIN/sgx_linux_x64_driver_${SGX_DRIVER_VERSION}.bin -prefix=$SGX_INSTALL_DIR || exit 1
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
	
install_multipackage_agent_rpm()
{
	if [ "$OS" == "rhel" ]; then
		rpm -ivh $SGX_AGENT_BIN/libsgx-ra-uefi-$MP_RPM_VER.el8.x86_64.rpm || exit 1
	elif [ "$OS" == "ubuntu" ]; then
		apt install -y libsgx-ra-uefi || exit 1
	fi
	echo "${green} sgx multipackage registration agent installed ${reset}"
}

install_pckretrieval_tool()
{
	\cp -pf $SGX_AGENT_BIN/libdcap_quoteprov.so.1 $SGX_AGENT_BIN/pck_id_retrieval_tool_enclave.signed.so /usr/sbin/
	\cp -pf $SGX_AGENT_BIN/PCKIDRetrievalTool /usr/sbin/
	echo "${green} pckid retrieval tool installed ${reset}"
}

install_sgx_agent() { 
	\cp -pf sgx_agent.env ~/sgx_agent.env

	source agent.conf
	if [ $? -ne 0 ]; then
		echo "${red} please set correct values in agent.conf ${reset}"
		exit 1
	fi
	CMS_URL=https://$CMS_IP:$CMS_PORT/cms/v1
	SCS_URL=https://$SCS_IP:$SCS_PORT/scs/sgx
	sed -i "s@^\(CMS_BASE_URL\s*=\s*\).*\$@\1$CMS_URL@" ~/sgx_agent.env
	sed -i "s@^\(SCS_BASE_URL\s*=\s*\).*\$@\1$SCS_URL@" ~/sgx_agent.env
	sed -i "s/^\(CMS_TLS_CERT_SHA384\s*=\s*\).*\$/\1$CMS_TLS_SHA/" ~/sgx_agent.env
	if [ -z $SHVS_IP ]; then
		sed -i "/SHVS_BASE_URL/d" ~/sgx_agent.env
	else
		SHVS_URL=https://$SHVS_IP:$SHVS_PORT/sgx-hvs/v2
		sed -i "s@^\(SHVS_BASE_URL\s*=\s*\).*\$@\1$SHVS_URL@" ~/sgx_agent.env
	fi
	LONG_LIVED_TOKEN=`./create_roles.sh`
	if [ $? -ne 0 ]; then
		echo "${red} sgx_agent token generation failed. exiting ${reset}"
		exit 1
	fi
	echo "${green} sgx agent roles created ${reset}"

	sed -i "s|BEARER_TOKEN=.*|BEARER_TOKEN=$LONG_LIVED_TOKEN|g" ~/sgx_agent.env

	echo "Installing SGX Agent...."
	$SGX_AGENT_BIN/sgx_agent-v*.bin
	sgx_agent status > /dev/null
	if [ $? -ne 0 ]; then
		echo "${red} SGX Agent Installation Failed ${reset}"
		exit 1
	fi
	echo "${green} SGX Agent Installation Successful ${reset}"
}

uninstall_sgx_agent
install_prerequisites
install_dcap_driver
install_psw_qgl
install_multipackage_agent_rpm
install_pckretrieval_tool
install_sgx_agent

#!/bin/bash
SKCLIB_BIN=bin
SGX_DRIVER_VERSION=1.41
SGX_INSTALL_DIR=/opt/intel

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

source skc_library.conf
if [ $? -ne 0 ]; then
	echo "${red} Please set correct values in skc_library.conf ${reset}"
	exit 1
fi

KDIR=/lib/modules/$(uname -r)/build
/sbin/lsmod | grep intel_sgx >/dev/null 2>&1
SGX_DRIVER_INSTALLED=$?
cat $KDIR/.config | grep "CONFIG_INTEL_SGX=y" > /dev/null
INKERNEL_SGX=$?

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
	if [ $SGX_DRIVER_INSTALLED -eq 0 ] || [ $INKERNEL_SGX -eq 0 ]; then
		echo "found sgx driver, skipping dcap driver installation"
		return
	fi

	chmod u+x $SKCLIB_BIN/sgx_linux_x64_driver_${SGX_DRIVER_VERSION}.bin
	$SKCLIB_BIN/sgx_linux_x64_driver_${SGX_DRIVER_VERSION}.bin -prefix=$SGX_INSTALL_DIR || exit 1
	echo "${green} sgx dcap driver installed ${reset}"
}

install_psw_qgl()
{
	if [ "$OS" == "rhel" ]; then
		tar -xf $SKCLIB_BIN/sgx_rpm_local_repo.tgz
		yum-config-manager --add-repo file://$PWD/sgx_rpm_local_repo || exit 1
		dnf install -qy --nogpgcheck libsgx-launch libsgx-uae-service libsgx-urts libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-devel libsgx-dcap-default-qpl-devel libsgx-dcap-default-qpl || exit 1
		rm -rf sgx_rpm_local_repo /etc/yum.repos.d/*sgx_rpm_local_repo.repo
	elif [ "$OS" == "ubuntu" ]; then
		echo 'deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu/ bionic main' | sudo tee /etc/apt/sources.list.d/intel-sgx.list
		wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | sudo apt-key add -
		apt update -y
		apt install -y libsgx-launch libsgx-uae-service libsgx-urts || exit 1
		apt install -y libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-dev libsgx-dcap-default-qpl-dev libsgx-dcap-default-qpl || exit 1
	fi
	echo "${green} sgx psw and qgl libraries installed ${reset}"
	sed -i "s|PCCS_URL=.*|PCCS_URL=https://$CSP_SCS_IP:9000/scs/sgx/certification/v1/|g" /etc/sgx_default_qcnl.conf
	sed -i "s|USE_SECURE_CERT=.*|USE_SECURE_CERT=FALSE|g" /etc/sgx_default_qcnl.conf
	
	#Update SCS root CA Certificate in SGX Compute node certificate store in order for  QPL to verify SCS
	curl -k -H 'Accept:application/x-pem-file' https://$CSP_CMS_IP:8445/cms/v1/ca-certificates > /etc/pki/ca-trust/source/anchors/skc-lib-cms-ca.cert
	# 'update-ca-trust' command is specific to RHEL OS, to update the system-wide trust store configuration.
	update-ca-trust extract
}

install_sgxssl()
{
        \cp -prf sgxssl $SGX_INSTALL_DIR
	echo "${green} sgxssl installed ${reset}"
}

install_cryptoapitoolkit()
{
	\cp -prf cryptoapitoolkit $SGX_INSTALL_DIR
	echo "${green} crypto api toolkit installed ${reset}"
}

install_skc_library_bin()
{
	$SKCLIB_BIN/skc_library_v*.bin
	if [ $? -ne 0 ]; then
		echo "${red} skc_library installation failed ${reset}"
		exit 1
	fi
	echo "${green} skc_library modules installed ${reset}"
}

run_post_deployment_script()
{
	./skc_library_create_roles.sh
	if [ $? -ne 0 ]; then
		echo "${red} failed to create skc_library user/roles ${reset}"
		exit 1
	fi
	echo "${green} skc_library deployment successful ${reset}"
}

install_prerequisites
install_dcap_driver
install_psw_qgl
install_sgxssl
install_cryptoapitoolkit
install_skc_library_bin
run_post_deployment_script

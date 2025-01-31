#!/bin/bash
source config
if [ $? -ne 0 ]; then
	echo "unable to read config variables"
	exit 1
fi

SKCLIB_BIN=bin
SKCLIB_INSTALL_DIR=/opt/skc
SKCLIB_DEVOPS_DIR=$SKCLIB_INSTALL_DIR/devops
SKC_DEVOPS_SCRIPTS_PATH=$SKCLIB_DEVOPS_DIR/scripts

source skc_library.conf
if [ $? -ne 0 ]; then
	echo "${red} Please set correct values in skc_library.conf ${reset}"
	exit 1
fi

uninstall_skc()
{
	if [[ -d $SGX_INSTALL_DIR/cryptoapitoolkit ]]; then
		echo "Uninstalling cryptoapitoolkit"
		rm -rf $SGX_INSTALL_DIR/cryptoapitoolkit
	fi

	if [[ -d $SGX_INSTALL_DIR/sgxssl ]]; then
		echo "uninstalling sgxssl"
		rm -rf $SGX_INSTALL_DIR/sgxssl
	fi

	echo "uninstalling sgx psw/qgl"
        if [ "$OS" == "rhel" ]; then
		$PKGMGR remove -y libsgx-launch libsgx-uae-service libsgx-urts libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-devel libsgx-dcap-default-qpl-devel libsgx-dcap-default-qpl
        elif [ "$OS" == "ubuntu" ]; then
                $PKGMGR purge -y libsgx-launch libsgx-uae-service libsgx-urts libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-dev libsgx-dcap-default-qpl-dev libsgx-dcap-default-qpl
        fi
	
	echo "Uninstalling skc-library"
	sh $SKC_DEVOPS_SCRIPTS_PATH/uninstall.sh
}

install_prerequisites()
{
	source deployment_prerequisites.sh 
	if [[ $? -ne 0 ]]; then
		echo "${red} pre requisited installation failed ${reset}"
		exit 1
	fi
}

install_psw_qgl()
{
	if [ "$OS" == "rhel" ]; then
		tar -xf $SKCLIB_BIN/sgx_rpm_local_repo.tgz || exit 1
		yum-config-manager --add-repo file://$PWD/sgx_rpm_local_repo || exit 1
		$PKGMGR install -qy --nogpgcheck libsgx-launch libsgx-uae-service libsgx-urts libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-devel libsgx-dcap-default-qpl-devel libsgx-dcap-default-qpl || exit 1
		rm -rf sgx_rpm_local_repo /etc/yum.repos.d/*sgx_rpm_local_repo.repo
	elif [ "$OS" == "ubuntu" ]; then
                echo $SGX_LIBS_REPO | sudo tee /etc/$PKGMGR/sources.list.d/intel-sgx.list
		wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | sudo $PKGMGR-key add - || exit 1
		$PKGMGR update -y || exit 1
		$PKGMGR install -y libsgx-launch libsgx-uae-service libsgx-urts || exit 1
		$PKGMGR install -y libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-dev libsgx-dcap-default-qpl-dev libsgx-dcap-default-qpl || exit 1
	fi
	echo "${green} sgx psw and qgl libraries installed ${reset}"
	sed -i "s|PCCS_URL=.*|PCCS_URL=https://$CSP_SCS_IP:$CSP_SCS_PORT/scs/sgx/certification/v1/|g" /etc/sgx_default_qcnl.conf
	sed -i "s|.*USE_SECURE_CERT=.*|USE_SECURE_CERT=FALSE|g" /etc/sgx_default_qcnl.conf
	
	#Update SCS root CA Certificate in SGX Compute node certificate store in order for  QPL to verify SCS
	curl -k -H 'Accept:application/x-pem-file' https://$CSP_CMS_IP:$CSP_CMS_PORT/cms/v1/ca-certificates > /etc/pki/ca-trust/source/anchors/skc-lib-cms-ca.cert
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
	./credential_agent.sh
	if [ $? -ne 0 ]; then
		echo "${red} failed to run credential agent ${reset}"
		exit 1
	fi
	echo "${green} skc_library deployment successful ${reset}"
}

uninstall_skc
install_prerequisites
install_psw_qgl
install_sgxssl
install_cryptoapitoolkit
install_skc_library_bin
run_post_deployment_script

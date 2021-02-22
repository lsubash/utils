#!/bin/bash
SKCLIB_BIN=bin
SGX_DRIVER_VERSION=1.41
SGX_INSTALL_DIR=/opt/intel

source skc_library.conf

KDIR=/lib/modules/$(uname -r)/build
/sbin/lsmod | grep intel_sgx >/dev/null 2>&1
SGX_DRIVER_INSTALLED=$?
cat $KDIR/.config | grep "CONFIG_INTEL_SGX=y" > /dev/null
INKERNEL_SGX=$?

install_prerequisites()
{
	source deployment_prerequisites.sh 
	if [[ $? -ne 0 ]]
	then
		echo "pre requisited installation failed"
		exit 1
	fi
}

install_dcap_driver()
{
	if [ $SGX_DRIVER_INSTALLED -eq 0 ] || [ $INKERNEL_SGX -eq 0 ] ; then
		echo "found sgx driver, skipping dcap driver installation"
		return
	fi

	chmod u+x $SKCLIB_BIN/sgx_linux_x64_driver_${SGX_DRIVER_VERSION}.bin
	$SKCLIB_BIN/sgx_linux_x64_driver_${SGX_DRIVER_VERSION}.bin -prefix=$SGX_INSTALL_DIR || exit 1
	echo "sgx dcap driver installed"
}

install_psw_qgl()
{
	tar -xf $SKCLIB_BIN/sgx_rpm_local_repo.tgz
	yum-config-manager --add-repo file://$PWD/sgx_rpm_local_repo || exit 1
	dnf install -y --nogpgcheck libsgx-launch libsgx-uae-service libsgx-urts libsgx-ae-qve libsgx-dcap-ql libsgx-dcap-ql-devel libsgx-dcap-default-qpl-devel libsgx-dcap-default-qpl || exit 1
	rm -rf sgx_rpm_local_repo /etc/yum.repos.d/*sgx_rpm_local_repo.repo

	sed -i "s|PCCS_URL=.*|PCCS_URL=https://$CSP_IP:9000/scs/sgx/certification/v1/|g" /etc/sgx_default_qcnl.conf
	#Update SCS root CA Certificate in SGX Compute node certificate store in order for  QPL to verify SCS
	curl -k -H 'Accept:application/x-pem-file' https://$CSP_IP:8445/cms/v1/ca-certificates > /etc/pki/ca-trust/source/anchors/skc-lib-cms-ca.cert
	# 'update-ca-trust' command is specific to RHEL OS, to update the system-wide trust store configuration.
	update-ca-trust
}

install_sgxssl()
{
        \cp -prf sgxssl $SGX_INSTALL_DIR
}

install_prerequisites
install_dcap_driver
install_psw_qgl
install_sgxssl

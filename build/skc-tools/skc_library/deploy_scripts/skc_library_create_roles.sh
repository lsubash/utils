#!/bin/bash

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

source skc_library.conf

SKCLIB_INST_PATH=/opt/skc
KMS_NPM_PATH=$SKCLIB_INST_PATH/etc/kms_npm.ini
CREDENTIAL_PATH=$SKCLIB_INST_PATH/etc/credential_agent.ini
CURL_OPTS="-s -k"
CONTENT_TYPE="Content-Type: application/json"
ACCEPT="Accept: application/jwt"
SGX_DEFAULT_PATH=/etc/sgx_default_qcnl.conf
aas_url=https://$ENTERPRISE_IP:8444/aas

mkdir -p /tmp/skclib
tmpdir=$(mktemp -d -p /tmp/skclib)

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

if [ "$OS" == "rhel" ]; then
	dnf install -qy jq
elif [ "$OS" == "ubuntu" ]; then
	apt install -qy jq
fi


echo "################ Install Admin user token....  #################"
INSTALL_ADMIN_TOKEN=`curl --noproxy "*" -k -X POST https://$ENTERPRISE_IP:8444/aas/token -d '{"username": "superadmin", "password": "superAdminPass" }'`
if [ $? -ne 0 ]; then
 echo "############ Could not get token for Install Admin User ####################"
 exit 1
fi

update_credential_ini()
{
	sed -i "s|server=.*|server=https:\/\/$KBS_HOSTNAME:$9443|g" $KMS_NPM_PATH
	sed -i "s|request_params=.*|request_params=\"\/CN=$SKC_USER\"|g" $CREDENTIAL_PATH
	sed -i "s|server=.*|server=$ENTERPRISE_IP|g" $CREDENTIAL_PATH
	sed -i "s|port=.*|port=8445|g" $CREDENTIAL_PATH
	sed -i "s|^token=.*|token=\"$INSTALL_ADMIN_TOKEN\"|g" $CREDENTIAL_PATH
	curl $CURL_OPTS -H 'Accept:application/x-pem-file' https://$ENTERPRISE_IP:8445/cms/v1/ca-certificates > $SKCLIB_INST_PATH/store/cms-ca.cert
}

run_credential_agent()
{
	$SKCLIB_INST_PATH/bin/credential_agent_init
	if [ $? -ne 0 ]; then
		echo "${red} credential_agent init failed ${reset}"
		exit 1
	fi
}

update_kbshostname_in_conf_file()
{
	sed -i "s|PCCS_URL=.*|PCCS_URL=https:\/\/$CSP_IP:9000/scs/sgx/certification/v1/|g" $SGX_DEFAULT_PATH
	grep -q "^$ENTERPRISE_IP" /etc/hosts && sed -i "s/^$ENTERPRISE_IP.*//" /etc/hosts && sed  -i '/^$/d' /etc/hosts
	sed -i "1i $ENTERPRISE_IP $KBS_HOSTNAME" /etc/hosts
}

update_credential_ini
run_credential_agent
update_kbshostname_in_conf_file
rm -rf $tmpdir

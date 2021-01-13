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
aas_url=https://$AAS_IP:$AAS_PORT/aas

mkdir -p /tmp/skclib
tmpdir=$(mktemp -d -p /tmp/skclib)

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

cat > $tmpdir/aasadmin.json << EOF
{
	"username": "admin@aas",
	"password": "aasAdminPass"
}
EOF

#Get the AAS Admin JWT Token
output=`curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "$ACCEPT" --data @$tmpdir/aasadmin.json -w "%{http_code}" $aas_url/token`
Bearer_token=`echo $output | rev | cut -c 4- | rev`

if [ "$OS" == "rhel" ]; then
	dnf install -qy jq
elif [ "$OS" == "ubuntu" ]; then
	apt install -qy jq
fi

# This routined checks if skc_library user exists and reurns user id
# it creates a new user if one does not exist
create_skclib_user()
{
cat > $tmpdir/user.json << EOF
{
"username":"$SKC_USER",
"password":"$SKC_USER_PASSWORD"
}
EOF

	#check if user already exists
	curl $CURL_OPTS -H "Authorization: Bearer ${Bearer_token}" -o $tmpdir/user_response.json -w "%{http_code}" $aas_url/users?name=$SKC_USER > $tmpdir/user_response.status

	len=$(jq '. | length' < $tmpdir/user_response.json)
	if [ $len -ne 0 ]; then
		user_id=$(jq -r '.[0] .user_id' < $tmpdir/user_response.json)
	else
		curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "Authorization: Bearer ${Bearer_token}" --data @$tmpdir/user.json -o $tmpdir/user_response.json -w "%{http_code}" $aas_url/users > $tmpdir/user_response.status

		local status=$(cat $tmpdir/user_response.status)
		if [ $status -ne 201 ]; then
			return 1
		fi

		if [ -s $tmpdir/user_response.json ]; then
			user_id=$(jq -r '.user_id' < $tmpdir/user_response.json)
			if [ -n "$user_id" ]; then
				echo "${green} Created skc_library user, id: $user_id ${reset}"
			fi
		fi
	fi
}

# This routined checks if skc_library CertApprover/KeyTransfer roles exist and reurns those role ids
# it creates above roles if not present in AAS db
create_roles()
{
cat > $tmpdir/certroles.json << EOF
{
	"service": "CMS",
	"name": "CertApprover",
	"context": "CN=$SKC_USER;CERTTYPE=TLS-Client"
}
EOF

cat > $tmpdir/keytransferroles.json << EOF
{
	"service": "KBS",
	"name": "KeyTransfer",
	"context": "permissions=nginx,USA"
}
EOF

	#check if CertApprover role already exists
	curl $CURL_OPTS -H "Authorization: Bearer ${Bearer_token}" -o $tmpdir/role_response.json -w "%{http_code}" $aas_url/roles?contextContains=CN=$SKC_USER > $tmpdir/role_response.status

	len=$(jq '. | length' < $tmpdir/role_response.json)
        if [ $len -ne 0 ]; then
                cms_role_id=$(jq -r '.[0] .role_id' < $tmpdir/role_response.json)
                echo $cms_role_id
        else
		curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "Authorization: Bearer ${Bearer_token}" --data @$tmpdir/certroles.json -o $tmpdir/role_response.json -w "%{http_code}" $aas_url/roles > $tmpdir/role_response-status.json

		local status=$(cat $tmpdir/role_response-status.json)
		if [ $status -ne 201 ]; then
			return 1
		fi

		if [ -s $tmpdir/role_response.json ]; then
			cms_role_id=$(jq -r '.role_id' < $tmpdir/role_response.json)
		fi
	fi

	#check if KeyTransfer role already exists
	curl $CURL_OPTS -H "Authorization: Bearer ${Bearer_token}" -o $tmpdir/role_resp.json -w "%{http_code}" $aas_url/roles?name=KeyTransfer > $tmpdir/role_resp.status

	len=$(jq '. | length' < $tmpdir/role_resp.json)
	if [ $len -ne 0 ]; then
		kbs_role_id=$(jq -r '.[0] .role_id' < $tmpdir/role_resp.json)
	else
		curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "Authorization: Bearer ${Bearer_token}" --data @$tmpdir/keytransferroles.json -o $tmpdir/role_resp.json -w "%{http_code}" $aas_url/roles > $tmpdir/role_resp-status.json

		local status=$(cat $tmpdir/role_resp-status.json)
		if [ $status -ne 201 ]; then
			return 1
		fi

		if [ -s $tmpdir/role_resp.json ]; then
			kbs_role_id=$(jq -r '.role_id' < $tmpdir/role_resp.json)
		fi
	fi
	ROLE_ID_TO_MAP=`echo \"$cms_role_id\",\"$kbs_role_id\"`
}

#Map skc_library User to Roles
mapUser_to_role() {
cat >$tmpdir/mapRoles.json <<EOF
{
	"role_ids": [$ROLE_ID_TO_MAP]
}
EOF

	curl $CURL_OPTS -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${Bearer_token}" --data @$tmpdir/mapRoles.json -o $tmpdir/mapRoles_response.json -w "%{http_code}" $aas_url/users/$user_id/roles > $tmpdir/mapRoles_response-status.json

	local actual_status=$(cat $tmpdir/mapRoles_response-status.json)
	if [ $actual_status -ne 201 ]; then
		return 1 
	fi
}

SKCLIB_SETUP="create_skclib_user create_roles mapUser_to_role"
status=
for api in $SKCLIB_SETUP
do
	eval $api
    	status=$?
	if [ $status -ne 0 ]; then
		break;
	fi
done

if [ $status -ne 0 ]; then
	echo "${red} skc_library user/roles creation failed: $api ${reset}"
	exit 1
else
	echo "${green} skc_library user/roles creation completed ${reset}"
fi

#Get Token for SKC_Library user
curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "$ACCEPT" --data @$tmpdir/user.json -o $tmpdir/skclib_token-response.json -w "%{http_code}" $aas_url/token > $tmpdir/skclibtoken-response.status

status=$(cat $tmpdir/skclibtoken-response.status)
if [ $status -ne 200 ]; then
	echo "${red} Couldn't get bearer token for skc_library user ${reset}"
	exit 1
else
	SKC_TOKEN=`cat $tmpdir/skclib_token-response.json`
fi

update_credential_ini()
{
	sed -i "s|server=.*|server=https:\/\/$KBS_HOSTNAME:$KBS_PORT|g" $KMS_NPM_PATH
	sed -i "s|request_params=.*|request_params=\"\/CN=$SKC_USER\"|g" $CREDENTIAL_PATH
	sed -i "s|server=.*|server=$CMS_IP|g" $CREDENTIAL_PATH
	sed -i "s|port=.*|port=$CMS_PORT|g" $CREDENTIAL_PATH
	sed -i "s|^token=.*|token=\"$SKC_TOKEN\"|g" $CREDENTIAL_PATH
	curl $CURL_OPTS -H 'Accept:application/x-pem-file' https://$CMS_IP:$CMS_PORT/cms/v1/ca-certificates > $SKCLIB_INST_PATH/store/cms-ca.cert
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
	sed -i "s|PCCS_URL=.*|PCCS_URL=https:\/\/$SCS_IP:$SCS_PORT/scs/sgx/certification/v1/|g" $SGX_DEFAULT_PATH
	grep -q "^$KBS_IP" /etc/hosts && sed -i "s/^$KBS_IP.*//" /etc/hosts && sed  -i '/^$/d' /etc/hosts
	sed -i "1i $KBS_IP $KBS_HOSTNAME" /etc/hosts
}

update_credential_ini
run_credential_agent
update_kbshostname_in_conf_file
rm -rf $tmpdir

#!/bin/bash
AGENT_env="/root/sgx_agent.env"
source $AGENT_env
if [ $? -ne 0 ]; then
	echo "${red} please set correct values in agent.env ${reset}"
	exit 1
fi

source agent.conf
if [ $? -ne 0 ]; then
	echo "${red} please set correct values in agent.conf ${reset}"
	exit 1
fi

#Get the value of AAS IP address and port. Default value is also provided.
aas_hostname=$AAS_API_URL
CURL_OPTS="-s -k"
CONTENT_TYPE="Content-Type: application/json"
ACCEPT="Accept: application/jwt"
CN="SGX_AGENT TLS Certificate"

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

mkdir -p /tmp/sgx_agent
tmpdir=$(mktemp -d -p /tmp/sgx_agent)

#Get the AAS Admin JWT Token
Bearer_token=`curl $CURL_OPTS -H "$CONTENT_TYPE" -H "$ACCEPT" -X POST $aas_hostname/token -d \{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"\}`
if [ $? -ne 0 ]; then
	echo "${red} failed to get aas admin token ${reset}"
	exit 1
fi

if [ "$OS" == "rhel" ]; then
	dnf install -qy jq
elif [ "$OS" == "ubuntu" ]; then
	apt install -qy jq
fi

# This routine checks if sgx agent user exists and returns user id
# it creates a new user if one does not exist
create_sgx_agent_user()
{
cat > $tmpdir/user.json << EOF
{
	"username":"$AGENT_USER",
	"password":"$AGENT_PASSWORD"
}
EOF
	#check if user already exists
	curl $CURL_OPTS -H "Authorization: Bearer ${Bearer_token}" -o $tmpdir/user_response.json -w "%{http_code}" $aas_hostname/users?name=$AGENT_USER > $tmpdir/user-response.status
	if [ $? -ne 0 ]; then
		echo "${red} failed to get sgx user details ${reset}"
		exit 1
	fi

	len=$(jq '. | length' < $tmpdir/user_response.json)
	if [ $len -ne 0 ]; then
		user_id=$(jq -r '.[0] .user_id' < $tmpdir/user_response.json)
	else
		curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "Authorization: Bearer ${Bearer_token}" --data @$tmpdir/user.json -o $tmpdir/user_response.json -w "%{http_code}" $aas_hostname/users > $tmpdir/user_response.status
		if [ $? -ne 0 ]; then
			echo "${red} failed to create sgx_agent user ${reset}"
			exit 1
		fi

		local status=$(cat $tmpdir/user_response.status)
		if [ $status -ne 201 ]; then
			return 1
		fi

		if [ -s $tmpdir/user_response.json ]; then
			user_id=$(jq -r '.user_id' < $tmpdir/user_response.json)
			if [ -n "$user_id" ]; then
				echo "${green} Created sgx_agent user, id: $user_id ${reset}"
			fi
		fi
	fi
}

# This routine check if sgx agent HostDataReader/HostDataUpdater roles exist and returns those role ids
# it creates above roles if not present in AAS db
create_roles()
{
cat > $tmpdir/scsdataread.json << EOF
{
	"service": "SCS",
	"name": "HostDataReader",
	"context": ""
}
EOF

cat > $tmpdir/scsdataup.json << EOF
{
	"service": "SCS",
	"name": "HostDataUpdater",
	"context": ""
}
EOF

cat > $tmpdir/shvsdataup.json << EOF
{
	"service": "SHVS",
	"name": "HostDataUpdater",
	"context": ""
}
EOF

	#check if HostDataReader role already exists
	curl $CURL_OPTS -H "Authorization: Bearer ${Bearer_token}" -o $tmpdir/role_resp.json -w "%{http_code}" $aas_hostname/roles?name=HostDataReader > $tmpdir/role_resp.status
	if [ $? -ne 0 ]; then
		echo "${red} failed to get all HostDataReader roles info ${reset}"
		exit 1
	fi

	scs_role_id=$(jq -r '.[] | select ( .service | ( contains("SCS")))' < $tmpdir/role_resp.json | jq -r '.role_id')
	if [ -z $scs_role_id ]; then
		curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "Authorization: Bearer ${Bearer_token}" --data @$tmpdir/scsdataread.json -o $tmpdir/scs_role_resp.json -w "%{http_code}" $aas_hostname/roles > $tmpdir/scs_role_resp-status.json
		if [ $? -ne 0 ]; then
			echo "${red} failed to create SCS HostDataReader role ${reset}"
			exit 1
		fi

		local status=$(cat $tmpdir/scs_role_resp-status.json)
		if [ $status -ne 201 ]; then
			return 1
		fi

		if [ -s $tmpdir/scs_role_resp.json ]; then
			scs_role_id=$(jq -r '.role_id' < $tmpdir/scs_role_resp.json)
		fi
	fi

	#check if SCS HostDataUpdater role already exists
	curl $CURL_OPTS -H "Authorization: Bearer ${Bearer_token}" -o $tmpdir/scs_role_resp.json -w "%{http_code}" $aas_hostname/roles?name=HostDataUpdater > $tmpdir/scs_role_resp.status
	if [ $? -ne 0 ]; then
		echo "${red} failed to check HostDataUpdater role ${reset}"
		exit 1
	fi

	scs_role_id1=$(jq -r '.[] | select ( .service | ( contains("SCS")))' < $tmpdir/scs_role_resp.json | jq -r '.role_id')
	if [ -z $scs_role_id1 ]; then
		curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "Authorization: Bearer ${Bearer_token}" --data @$tmpdir/scsdataup.json -o $tmpdir/scs_role_resp.json -w "%{http_code}" $aas_hostname/roles > $tmpdir/scs_role_resp-status.json
		if [ $? -ne 0 ]; then
			echo "${red} failed to create SCS HostDataUpdater role ${reset}"
			exit 1
		fi

		local status=$(cat $tmpdir/scs_role_resp-status.json)
		if [ $status -ne 201 ]; then
			return 1
		fi

		if [ -s $tmpdir/scs_role_resp.json ]; then
			scs_role_id1=$(jq -r '.role_id' < $tmpdir/scs_role_resp.json)
		fi
	fi

	#check if SHVS HostDataUpdater role already exists
	curl $CURL_OPTS -H "Authorization: Bearer ${Bearer_token}" -o $tmpdir/shvs_role_resp.json -w "%{http_code}" $aas_hostname/roles?name=HostDataUpdater > $tmpdir/shvs_role_resp.status
	if [ $? -ne 0 ]; then
		echo "${red} failed to check HostDataUpdater role ${reset}"
		exit 1
	fi

	shvs_role_id=$(jq -r '.[] | select ( .service | ( contains("SHVS")))' < $tmpdir/shvs_role_resp.json | jq -r '.role_id')
	if [ -z $shvs_role_id ]; then
		curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "Authorization: Bearer ${Bearer_token}" --data @$tmpdir/shvsdataup.json -o $tmpdir/shvs_role_resp.json -w "%{http_code}" $aas_hostname/roles > $tmpdir/shvs_role_resp-status.json
		if [ $? -ne 0 ]; then
			echo "${red} failed to create SHVS HostDataUpdater role ${reset}"
			exit 1
		fi

		local status=$(cat $tmpdir/shvs_role_resp-status.json)
		if [ $status -ne 201 ]; then
			return 1
		fi

		if [ -s $tmpdir/shvs_role_resp.json ]; then
			shvs_role_id=$(jq -r '.role_id' < $tmpdir/shvs_role_resp.json)
		fi
	fi

	ROLE_ID_TO_MAP=`echo \"$scs_role_id\",\"$scs_role_id1\",\"$shvs_role_id\"`
}

# Maps sgx_agent user to HostDataReader/HostDataUpdater Roles
mapUser_to_role()
{
cat >$tmpdir/mapRoles.json <<EOF
{
	"role_ids": [$ROLE_ID_TO_MAP]
}
EOF

	curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "Authorization: Bearer ${Bearer_token}" --data @$tmpdir/mapRoles.json -o $tmpdir/mapRoles_response.json -w "%{http_code}" $aas_hostname/users/$user_id/roles > $tmpdir/mapRoles_response-status.json
	if [ $? -ne 0 ]; then
		echo "${red} failed to HostDataReader/HostDataUpdater role to sgx_agent user${reset}"
		exit 1
	fi

	local status=$(cat $tmpdir/mapRoles_response-status.json)
	if [ $status -ne 201 ]; then
		return 1
	fi
}

SGX_AGENT_SETUP_API="create_sgx_agent_user create_roles mapUser_to_role"
status=
for api in $SGX_AGENT_SETUP_API
do
	eval $api
    	status=$?
done

# Get sgx_agent user token and configure it in sgx_agent.env
curl $CURL_OPTS -X POST -H "$CONTENT_TYPE" -H "$ACCEPT" --data @$tmpdir/user.json -o $tmpdir/agent_token-resp.json -w "%{http_code}" $aas_hostname/token > $tmpdir/get_agent_token-response.status
if [ $? -ne 0 ]; then
	echo "${red} failed to get token for sgx_agent user.: $api ${reset}"
	exit 1
fi

status=$(cat $tmpdir/get_agent_token-response.status)
if [ $status -ne 200 ]; then
	echo "${red} Couldn't get bearer token for sgx agent user ${reset}"
else
	TOKEN=`cat $tmpdir/agent_token-resp.json`
	sed -i "s|BEARER_TOKEN=.*|BEARER_TOKEN=$TOKEN|g" $AGENT_env
	echo $TOKEN
fi

# cleanup
rm -rf $tmpdir

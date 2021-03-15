#!/bin/bash

# Check OS
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"

# read from environment variables file if it exists
if [ -f ./kbs.conf ]; then
    echo "Reading Installation variables from $(pwd)/kbs.conf"
    source kbs.conf
    if [ $? -ne 0 ]; then
        echo "${red} please set correct values in kbs.conf ${reset}"
        exit 1
    fi

    env_file_exports=$(cat ./kbs.conf | grep -E '^[A-Z0-9_]+\s*=' | cut -d = -f 1)
    if [ -n "$env_file_exports" ]; then eval export $env_file_exports; fi
fi

CONTENT_TYPE="Content-Type: application/json"
ACCEPT="Accept: application/json"
AAS_BASE_URL=https://$SYSTEM_IP:$AAS_PORT/aas/v1

rm -rf output *response.* *debug.*

if [ "$OS" == "rhel" ]; then
dnf install jq -y || exit 1
elif [ "$OS" == "ubuntu" ]; then
apt-get install jq -y || exit 1
fi

aas_token=`curl -k -H "$CONTENT_TYPE" -H "$ACCEPT" --data \{\"username\":\"$AAS_USERNAME\",\"password\":\"$AAS_PASSWORD\"\} $AAS_BASE_URL/token`

# Create EnterPriseAdmin User and assign the roles.
user_="\"username\":\"$ENTERPRISE_ADMIN\""
password_="\"password\":\"$ENTERPRISE_PASSWORD\""
curl -s -k -H "$CONTENT_TYPE" -H "Authorization: Bearer $aas_token" --data \{$user_,$password_\} $http_header $AAS_BASE_URL/users

user_details=`curl -k "$CONTENT_TYPE" -H "Authorization: Bearer $aas_token" -w %{http_code}  $AAS_BASE_URL/users?name=$ENTERPRISE_ADMIN`
user_id=`echo $user_details| awk 'BEGIN{RS="user_id\":\""} {print $1}' | sed -n '2p' | awk 'BEGIN{FS="\",\"username\":\""} {print $1}'`

# createRoles("KMS","KeyCRUD","","permissions:["*:*:*"]")
curl -s -k -H "$CONTENT_TYPE" -H "Authorization: Bearer $aas_token" --data \{\"service\":\"KBS\",\"name\":\"KeyCRUD\",\"permissions\":[\"*:*:*\"]\} $http_header $AAS_BASE_URL/roles
role_details=`curl -k "$CONTENT_TYPE" -H "Authorization: Bearer $aas_token" -w %{http_code} $AAS_BASE_URL/roles?service=KBS\&name=KeyCRUD`
role_id1=`echo $role_details | cut -d '"' -f 4`

# map Key CRUD roles to enterprise admin
curl -s -k -H "$CONTENT_TYPE" -H "Authorization: Bearer ${aas_token}" --data \{\"role_ids\":\[\"$role_id1\"\]\} -w %{http_code} $AAS_BASE_URL/users/$user_id/roles

# get updated user token
BEARER_TOKEN=`curl -k -H "$CONTENT_TYPE" -H "$ACCEPT" -H "Authorization: Bearer $aas_token" --data \{\"username\":\"$ENTERPRISE_ADMIN\",\"password\":\"$ENTERPRISE_PASSWORD\"\} $AAS_BASE_URL/token`
echo $BEARER_TOKEN

curl -H "Authorization: Bearer ${BEARER_TOKEN}" -H "$CONTENT_TYPE" --cacert $CACERT_PATH \
	-H "$ACCEPT" --data @transfer_policy_request.json  -o transfer_policy_response.json -w "%{http_code}" \
	https://$SYSTEM_IP:$KBS_PORT/v1/key-transfer-policies >transfer_policy_response.status 2>transfer_policy_debug.log

transfer_policy_id=$(cat transfer_policy_response.json | jq '.id');

if [ "$1" = "reg" ]; then
# create a RSA key
	source gen_cert_key.sh
printf "{
   \"key_information\":{
      \"algorithm\":\"RSA\",
      \"key_length\":3072,
      \"key_string\":\"$(cat ${SERVER_PKCS8_KEY} | tr '\r\n' '@')\"
   },
    \"transfer_policy_ID\": ${transfer_policy_id}
}" > key_request.json

sed -i "s/@/\\\n/g" key_request.json

else
# create a AES key
printf "{
   \"key_information\":{
   \"algorithm\":\"AES\",
   \"key_length\":256
   },
   \"transfer_policy_ID\":${transfer_policy_id}
}" > key_request.json
fi

curl -H "Authorization: Bearer ${BEARER_TOKEN}" -H "$CONTENT_TYPE" --cacert $CACERT_PATH \
    -H "$ACCEPT" --data @key_request.json -o key_response.json -w "%{http_code}" \
    https://$SYSTEM_IP:$KBS_PORT/v1/keys > key_response.status 2>key_debug.log

key_id=$(cat key_response.json | jq '.key_information.id');

if [ "$1" = "reg" ]; then
    file_name=$(echo $key_id | sed -e "s|\"||g")
    mv output/server.cert output/$file_name.crt
    echo "cert path:$(realpath output/$file_name.crt)"
fi

echo "Created Key:$key_id"

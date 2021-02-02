#!/bin/bash

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

HOME_DIR=~/
SKC_BINARY_DIR=$HOME_DIR/binaries

# Copy env files to Home directory
\cp -pf ./env/cms.env $HOME_DIR
\cp -pf ./env/authservice.env $HOME_DIR
\cp -pf ./env/scs.env $HOME_DIR
\cp -pf ./env/shvs.env $HOME_DIR
\cp -pf ./env/ihub.env $HOME_DIR
\cp -pf ./env/iseclpgdb.env $HOME_DIR

# Copy DB scripts to Home directory
\cp -pf ./install_pg.sh $HOME_DIR
\cp -pf ./install_pgscsdb.sh $HOME_DIR
\cp -pf ./install_pgshvsdb.sh $HOME_DIR

# read from environment variables file if it exists
if [ -f ./csp_skc.conf ]; then
    echo "Reading Installation variables from $(pwd)/csp_skc.conf"
    source csp_skc.conf
    env_file_exports=$(cat ./csp_skc.conf | grep -E '^[A-Z0-9_]+\s*=' | cut -d = -f 1)
    if [ -n "$env_file_exports" ]; then eval export $env_file_exports; fi
fi

if [[ "$OS" == "rhel" && "$VER" == "8.1" || "$VER" == "8.2" ]]; then
    dnf install -y jq
elif [[ "$OS" == "ubuntu" && "$VER" == "18.04" ]]; then
    apt install -y jq curl
else
    echo "Unsupported OS. Please use RHEL 8.1/8.2 or Ubuntu 18.04"
    exit 1
fi

echo "################ Uninstalling CMS....  #################"
cms uninstall --purge
echo "################ Uninstalling AAS....  #################"
authservice uninstall --purge
echo "################ Remove AAS DB....  #################"
pushd $PWD
cd /usr/local/pgsql
sudo -u postgres dropdb $AAS_DB_NAME
echo "################ Uninstalling SCS....  #################"
scs uninstall --purge
echo "################ Remove SCS DB....  #################"
sudo -u postgres dropdb $SCS_DB_NAME
echo "################ Uninstalling SHVS....  #################"
shvs uninstall --purge
echo "################ Remove SHVS DB....  #################"
sudo -u postgres dropdb $SHVS_DB_NAME
echo "################ Uninstalling IHUB....  #################"
ihub uninstall --purge
popd

function is_database() {
    export PGPASSWORD=$3
    psql -U $2 -lqt | cut -d \| -f 1 | grep -wq $1
}

if is_database $AAS_DB_NAME $AAS_DB_USERNAME $AAS_DB_PASSWORD
then 
   echo $AAS_DB_NAME database exists
else
   echo "################ Update iseclpgdb.env for AAS....  #################"
   sed -i "s@^\(ISECL_PGDB_DBNAME\s*=\s*\).*\$@\1$AAS_DB_NAME@" ~/iseclpgdb.env
   sed -i "s@^\(ISECL_PGDB_USERNAME\s*=\s*\).*\$@\1$AAS_DB_USERNAME@" ~/iseclpgdb.env
   sed -i "s@^\(ISECL_PGDB_USERPASSWORD\s*=\s*\).*\$@\1$AAS_DB_PASSWORD@" ~/iseclpgdb.env
   pushd $PWD
   cd ~
   bash install_pg.sh
fi

if is_database $SCS_DB_NAME $SCS_DB_USERNAME $SCS_DB_PASSWORD
then
   echo $SCS_DB_NAME database exists
else
   echo "################ Update iseclpgdb.env for SCS....  #################"
   sed -i "s@^\(ISECL_PGDB_DBNAME\s*=\s*\).*\$@\1$SCS_DB_NAME@" ~/iseclpgdb.env
   sed -i "s@^\(ISECL_PGDB_USERNAME\s*=\s*\).*\$@\1$SCS_DB_USERNAME@" ~/iseclpgdb.env
   sed -i "s@^\(ISECL_PGDB_USERPASSWORD\s*=\s*\).*\$@\1$SCS_DB_PASSWORD@" ~/iseclpgdb.env
   bash install_pgscsdb.sh
fi

if is_database $SHVS_DB_NAME $SHVS_DB_USERNAME $SHVS_DB_PASSWORD
then
   echo $SHVS_DB_NAME database exists
else
   echo "################ Update iseclpgdb.env for SHVS....  #################"
   sed -i "s@^\(ISECL_PGDB_DBNAME\s*=\s*\).*\$@\1$SHVS_DB_NAME@" ~/iseclpgdb.env
   sed -i "s@^\(ISECL_PGDB_USERNAME\s*=\s*\).*\$@\1$SHVS_DB_USERNAME@" ~/iseclpgdb.env
   sed -i "s@^\(ISECL_PGDB_USERPASSWORD\s*=\s*\).*\$@\1$SHVS_DB_PASSWORD@" ~/iseclpgdb.env
   bash install_pgshvsdb.sh
fi

popd

pushd $PWD
cd $SKC_BINARY_DIR
echo "################ Installing CMS....  #################"
AAS_URL=https://$SYSTEM_IP:8444/aas
sed -i "s/^\(AAS_TLS_SAN\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/cms.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/cms.env
sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/cms.env

./cms-*.bin || exit 1
if [ $? -ne 0 ]; then
  echo "############ CMS Installation Failed"
  exit 1
fi
echo "################ Installed CMS....  #################"

echo "################ Installing AuthService....  #################"

echo "################ Copy CMS token to AuthService....  #################"
export AAS_TLS_SAN=$SYSTEM_IP
CMS_TOKEN=`cms setup cms_auth_token --force | grep 'JWT Token:' | awk '{print $3}'`
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$CMS_TOKEN/"  ~/authservice.env

CMS_TLS_SHA=`cms tlscertsha384`
sed -i "s/^\(CMS_TLS_CERT_SHA384\s*=\s*\).*\$/\1$CMS_TLS_SHA/"  ~/authservice.env

CMS_URL=https://$SYSTEM_IP:8445/cms/v1/
sed -i "s@^\(CMS_BASE_URL\s*=\s*\).*\$@\1$CMS_URL@"  ~/authservice.env

sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/"  ~/authservice.env
sed -i "s/^\(AAS_DB_NAME\s*=\s*\).*\$/\1$AAS_DB_NAME/"  ~/authservice.env
sed -i "s/^\(AAS_DB_USERNAME\s*=\s*\).*\$/\1$AAS_DB_USERNAME/"  ~/authservice.env
sed -i "s/^\(AAS_DB_PASSWORD\s*=\s*\).*\$/\1$AAS_DB_PASSWORD/"  ~/authservice.env

./authservice-*.bin || exit 1
if [ $? -ne 0 ]; then
  echo "############ AuthService Installation Failed"
  exit 1
fi
echo "################ Installed AuthService....  #################"

echo "################ Create user and role on AuthService....  #################"
TOKEN=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/token -d '{"username": "admin@aas", "password": "aasAdminPass" }'`

if [ $? -ne 0 ]; then
  echo "############ Could not get TOKEN from AuthService "
  exit 1
fi

USER_ID=`curl --noproxy "*" -k https://$SYSTEM_IP:8444/aas/users?name=admin@aas -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' | jq -r '.[0].user_id'`
echo "Got admin user ID $USER_ID"

# SGX Caching Service User and Roles

SCS_USER=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/users -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"username": "scsuser@scs","password": "scspassword"}'`
SCS_USER_ID=`curl --noproxy "*" -k https://$SYSTEM_IP:8444/aas/users?name=scsuser@scs -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' | jq -r '.[0].user_id'`
echo "Created SCS User with user ID $SCS_USER_ID"
SCS_ROLE_ID1=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "CMS","name": "CertApprover","context": "CN=SCS TLS Certificate;SAN='$SYSTEM_IP';certType=TLS"}' | jq -r ".role_id"`
echo "Created SCS TLS cert role with ID $SCS_ROLE_ID1"
SCS_ROLE_ID2=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "SCS","name": "CacheManager","context": ""}' | jq -r ".role_id"`
echo "Created SCS CacheManager role with ID $SCS_ROLE_ID2"

if [ $? -eq 0 ]; then
  curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/users/$SCS_USER_ID/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"role_ids": ["'"$SCS_ROLE_ID1"'", "'"$SCS_ROLE_ID2"'"]}'
fi

SCS_TOKEN=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/token -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"username": "scsuser@scs","password": "scspassword"}'`
echo "SCS Token $SCS_TOKEN"

# SGX Host Verification Service User and Roles

SHVS_USER=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/users -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"username": "shvsuser@shvs","password": "shvspassword"}'`
SHVS_USER_ID=`curl --noproxy "*" -k https://$SYSTEM_IP:8444/aas/users?name=shvsuser@shvs -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' | jq -r '.[0].user_id'`
echo "Created SHVS User with user ID $SHVS_USER_ID"
SHVS_ROLE_ID1=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "CMS","name": "CertApprover","context": "CN=SHVS TLS Certificate;SAN='$SYSTEM_IP';certType=TLS"}' | jq -r ".role_id"`
echo "Created SHVS TLS cert role with ID $SHVS_ROLE_ID1"
SHVS_ROLE_ID2=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "SGX_AGENT","name": "HostDataReader","context": ""}' | jq -r ".role_id"`
echo "Created SHVS HostDataReader role with ID $SHVS_ROLE_ID2"
SHVS_ROLE_ID3=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "SCS","name": "HostDataUpdater","context": ""}' | jq -r ".role_id"`
echo "Created SHVS HostDataUpdater role with ID $SHVS_ROLE_ID3"
SHVS_ROLE_ID4=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "SCS","name": "HostDataReader","context": ""}' | jq -r ".role_id"`
echo "Created SHVS HostDataReader role with ID $SHVS_ROLE_ID4"
SHVS_ROLE_ID5=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "SHVS","name": "HostListManager","context": ""}' | jq -r ".role_id"`
echo "Created SHVS HostListManager role with ID $SHVS_ROLE_ID5"
SHVS_ROLE_ID6=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "SHVS","name": "HostsListReader","context": ""}' | jq -r ".role_id"`
echo "Created SHVS HostsListReader role with ID $SHVS_ROLE_ID6"
SHVS_ROLE_ID7=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "SHVS","name": "HostDataReader","context": ""}' | jq -r ".role_id"`
echo "Created SHVS HostDataReader role with ID $SHVS_ROLE_ID7"

if [ $? -eq 0 ]; then
  curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/users/$SHVS_USER_ID/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"role_ids": ["'"$SHVS_ROLE_ID1"'", "'"$SHVS_ROLE_ID2"'", "'"$SHVS_ROLE_ID3"'", "'"$SHVS_ROLE_ID4"'", "'"$SHVS_ROLE_ID5"'", "'"$SHVS_ROLE_ID6"'", "'"$SHVS_ROLE_ID7"'"]}'
fi

SHVS_TOKEN=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/token -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"username": "shvsuser@shvs","password": "shvspassword"}'`
echo "SHVS Token $SHVS_TOKEN"

#  IHUB User and Roles
IHUB_USER=`curl --noproxy "*" -k  -X POST https://$SYSTEM_IP:8444/aas/users -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"username": "admin@hub","password": "hubAdminPass"}'`
IHUB_USER_ID=`curl --noproxy "*" -k https://$SYSTEM_IP:8444/aas/users?name=admin@hub -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' | jq -r '.[0].user_id'`
echo "Created IHUB User with user ID $IHUB_USER_ID"
IHUB_ROLE_ID=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"service": "CMS","name": "CertApprover","context": "CN=Integration HUB TLS Certificate;SAN='$SYSTEM_IP';certType=TLS"}' | jq -r ".role_id"`
echo "Created IHUB TLS cert role with ID $IHUB_ROLE_ID"

if [ $? -eq 0 ]; then
  curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/users/$IHUB_USER_ID/roles -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"role_ids": ["'"$IHUB_ROLE_ID"'", "'"$SHVS_ROLE_ID6"'", "'"$SHVS_ROLE_ID7"'"]}'
fi

IHUB_TOKEN=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/token -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"username": "admin@hub","password": "hubAdminPass"}'`
echo "IHUB Token $IHUB_TOKEN"

echo "################ Update SCS env....  #################"
sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/"  ~/scs.env
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$SCS_TOKEN/"  ~/scs.env
sed -i "s/^\(CMS_TLS_CERT_SHA384\s*=\s*\).*\$/\1$CMS_TLS_SHA/" ~/scs.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/scs.env
sed -i "s@^\(CMS_BASE_URL\s*=\s*\).*\$@\1$CMS_URL@" ~/scs.env
sed -i "s@^\(INTEL_PROVISIONING_SERVER\s*=\s*\).*\$@\1$INTEL_PROVISIONING_SERVER@" ~/scs.env
sed -i "s@^\(INTEL_PROVISIONING_SERVER_API_KEY\s*=\s*\).*\$@\1$INTEL_PROVISIONING_SERVER_API_KEY@" ~/scs.env
sed -i "s/^\(SCS_DB_NAME\s*=\s*\).*\$/\1$SCS_DB_NAME/"  ~/scs.env
sed -i "s/^\(SCS_DB_USERNAME\s*=\s*\).*\$/\1$SCS_DB_USERNAME/"  ~/scs.env
sed -i "s/^\(SCS_DB_PASSWORD\s*=\s*\).*\$/\1$SCS_DB_PASSWORD/"  ~/scs.env

echo "################ Installing SCS....  #################"
./scs-*.bin || exit 1
if [ $? -ne 0 ]; then
  echo "############ SCS Installation Failed"
  exit 1
fi
echo "################ Installed SCS....  #################"

echo "################ Update SHVS env....  #################"
sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/shvs.env
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$SHVS_TOKEN/" ~/shvs.env
sed -i "s/^\(CMS_TLS_CERT_SHA384\s*=\s*\).*\$/\1$CMS_TLS_SHA/" ~/shvs.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/shvs.env
sed -i "s@^\(CMS_BASE_URL\s*=\s*\).*\$@\1$CMS_URL@" ~/shvs.env
SCS_URL=https://$SYSTEM_IP:9000/scs/sgx/
sed -i "s@^\(SCS_BASE_URL\s*=\s*\).*\$@\1$SCS_URL@" ~/shvs.env
sed -i "s/^\(SHVS_DB_NAME\s*=\s*\).*\$/\1$SHVS_DB_NAME/"  ~/shvs.env
sed -i "s/^\(SHVS_DB_USERNAME\s*=\s*\).*\$/\1$SHVS_DB_USERNAME/"  ~/shvs.env
sed -i "s/^\(SHVS_DB_PASSWORD\s*=\s*\).*\$/\1$SHVS_DB_PASSWORD/"  ~/shvs.env

echo "################ Installing SHVS....  #################"
./shvs-*.bin || exit 1
if [ $? -ne 0 ]; then
  echo "############ SHVS Installation Failed"
  exit 1
fi
echo "################ Installed SHVS....  #################"

echo "################ Update IHUB env....  #################"
sed -i "s/^\(TLS_SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/ihub.env
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$IHUB_TOKEN/" ~/ihub.env
sed -i "s/^\(CMS_TLS_CERT_SHA384\s*=\s*\).*\$/\1$CMS_TLS_SHA/" ~/ihub.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/ihub.env
sed -i "s@^\(CMS_BASE_URL\s*=\s*\).*\$@\1$CMS_URL@" ~/ihub.env
SHVS_URL=https://$SYSTEM_IP:13000/sgx-hvs/v1
K8S_URL=https://$K8S_IP:6443/
sed -i "s@^\(ATTESTATION_SERVICE_URL\s*=\s*\).*\$@\1$SHVS_URL@" ~/ihub.env
sed -i "s@^\(KUBERNETES_URL\s*=\s*\).*\$@\1$K8S_URL@" ~/ihub.env
if [[ "$OS" != "ubuntu" ]]; then
OPENSTACK_AUTH_URL=http://$OPENSTACK_IP:5000/
OPENSTACK_PLACEMENT_URL=http://$OPENSTACK_IP:8778/
sed -i "s@^\(OPENSTACK_AUTH_URL\s*=\s*\).*\$@\1$OPENSTACK_AUTH_URL@" ~/ihub.env
sed -i "s@^\(OPENSTACK_PLACEMENT_URL\s*=\s*\).*\$@\1$OPENSTACK_PLACEMENT_URL@" ~/ihub.env
fi
sed -i "s@^\(TENANT\s*=\s*\).*\$@\1$TENANT@" ~/ihub.env

echo "################ Installing IHUB....  #################"
./ihub-*.bin || exit 1
if [ $? -ne 0 ]; then
  echo "############ IHUB Installation Failed"
  exit 1
fi
echo "################ Installed IHUB....  #################"

popd

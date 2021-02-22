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
\cp -pf ./env/populate-users.env $HOME_DIR

# Copy DB scripts to Home directory
\cp -pf ./install_pg.sh $HOME_DIR
\cp -pf ./install_pgscsdb.sh $HOME_DIR
\cp -pf ./install_pgshvsdb.sh $HOME_DIR
\cp -pf ./populate-users.sh $HOME_DIR

# read from environment variables file if it exists
if [ -f ./csp_skc.conf ]; then
    echo "Reading Installation variables from $(pwd)/csp_skc.conf"
    source csp_skc.conf
    if [[ "$SCS_DB_NAME" == "$SHVS_DB_NAME" || "$AAS_DB_NAME" == "$SHVS_DB_NAME" || "$SCS_DB_NAME" == "$AAS_DB_NAME" ]]; then
        echo "SCS_DB_NAME, SHVS_DB_NAME & AAS_DB_NAME should not be same. Please change in csp_skc.conf"
        exit 1
    fi
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

pushd $PWD
cd ~
if is_database $AAS_DB_NAME $AAS_DB_USERNAME $AAS_DB_PASSWORD
then 
   echo $AAS_DB_NAME database exists
else
   echo "################ Update iseclpgdb.env for AAS....  #################"
   sed -i "s@^\(ISECL_PGDB_DBNAME\s*=\s*\).*\$@\1$AAS_DB_NAME@" ~/iseclpgdb.env
   sed -i "s@^\(ISECL_PGDB_USERNAME\s*=\s*\).*\$@\1$AAS_DB_USERNAME@" ~/iseclpgdb.env
   sed -i "s@^\(ISECL_PGDB_USERPASSWORD\s*=\s*\).*\$@\1$AAS_DB_PASSWORD@" ~/iseclpgdb.env
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

echo "################ Installing CMS....  #################"
AAS_URL=https://$SYSTEM_IP:8444/aas
sed -i "s/^\(AAS_TLS_SAN\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/cms.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/cms.env
sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/cms.env

./cms-*.bin || exit 1
cms status > /dev/null
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
authservice status > /dev/null
if [ $? -ne 0 ]; then
  echo "############ AuthService Installation Failed"
  exit 1
fi
echo "################ Installed AuthService....  #################"

echo "################ Update Populate users env ....  #################"
ISECL_INSTALL_COMPONENTS=AAS,SCS,SHVS,SIH,SGX_AGENT
sed -i "s@^\(ISECL_INSTALL_COMPONENTS\s*=\s*\).*\$@\1$ISECL_INSTALL_COMPONENTS@" ~/populate-users.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/populate-users.env

AAS_ADMIN_USERNAME=$(cat ~/authservice.env | grep ^AAS_ADMIN_USERNAME= | cut -d'=' -f2)
AAS_ADMIN_PASSWORD=$(cat ~/authservice.env | grep ^AAS_ADMIN_PASSWORD= | cut -d'=' -f2)
sed -i "s/^\(AAS_ADMIN_USERNAME\s*=\s*\).*\$/\1$AAS_ADMIN_USERNAME/" ~/populate-users.env
sed -i "s/^\(AAS_ADMIN_PASSWORD\s*=\s*\).*\$/\1$AAS_ADMIN_PASSWORD/" ~/populate-users.env

sed -i "s@^\(IH_CERT_SAN_LIST\s*=\s*\).*\$@\1$SYSTEM_IP@" ~/populate-users.env
sed -i "s@^\(SCS_CERT_SAN_LIST\s*=\s*\).*\$@\1$SYSTEM_IP@" ~/populate-users.env
sed -i "s@^\(SHVS_CERT_SAN_LIST\s*=\s*\).*\$@\1$SYSTEM_IP@" ~/populate-users.env
sed -i "s@^\(SGX_AGENT_CERT_SAN_LIST\s*=\s*\).*\$@\1$SGX_AGENT_IP@" ~/populate-users.env

IHUB_SERVICE_USERNAME=$(cat ~/ihub.env | grep ^IHUB_SERVICE_USERNAME= | cut -d'=' -f2)
IHUB_SERVICE_PASSWORD=$(cat ~/ihub.env | grep ^IHUB_SERVICE_PASSWORD= | cut -d'=' -f2)
sed -i "s/^\(IHUB_SERVICE_USERNAME\s*=\s*\).*\$/\1$IHUB_SERVICE_USERNAME/" ~/populate-users.env
sed -i "s/^\(IHUB_SERVICE_PASSWORD\s*=\s*\).*\$/\1$IHUB_SERVICE_PASSWORD/" ~/populate-users.env

SCS_ADMIN_USERNAME=$(cat ~/scs.env | grep ^SCS_ADMIN_USERNAME= | cut -d'=' -f2)
SCS_ADMIN_PASSWORD=$(cat ~/scs.env | grep ^SCS_ADMIN_PASSWORD= | cut -d'=' -f2)
sed -i "s/^\(SCS_SERVICE_USERNAME\s*=\s*\).*\$/\1$SCS_ADMIN_USERNAME/" ~/populate-users.env
sed -i "s/^\(SCS_SERVICE_PASSWORD\s*=\s*\).*\$/\1$SCS_ADMIN_PASSWORD/" ~/populate-users.env

SHVS_ADMIN_USERNAME=$(cat ~/shvs.env | grep ^SHVS_ADMIN_USERNAME= | cut -d'=' -f2)
SHVS_ADMIN_PASSWORD=$(cat ~/shvs.env | grep ^SHVS_ADMIN_PASSWORD= | cut -d'=' -f2)
sed -i "s/^\(SHVS_SERVICE_USERNAME\s*=\s*\).*\$/\1$SHVS_ADMIN_USERNAME/" ~/populate-users.env
sed -i "s/^\(SHVS_SERVICE_PASSWORD\s*=\s*\).*\$/\1$SHVS_ADMIN_PASSWORD/" ~/populate-users.env

sed -i "s@^\(SGX_AGENT_USERNAME\s*=\s*\).*\$@\1$SGX_AGENT_USERNAME@" ~/populate-users.env
sed -i "s@^\(SGX_AGENT_PASSWORD\s*=\s*\).*\$@\1$SGX_AGENT_PASSWORD@" ~/populate-users.env

sed -i "/GLOBAL_ADMIN_USERNAME/d" ~/populate-users.env
sed -i "/GLOBAL_ADMIN_PASSWORD/d" ~/populate-users.env

sed -i '$ a INSTALL_ADMIN_USERNAME=superadmin' ~/populate-users.env
sed -i '$ a INSTALL_ADMIN_PASSWORD=superAdminPass' ~/populate-users.env

echo "################ Call populate users script....  #################"
pushd $PWD
cd ~
./populate-users.sh || exit 1
if [ $? -ne 0 ]; then
  echo "############ Failed to run populate user script  ####################3"
  exit 1
fi
popd

echo "################ Install Admin user token....  #################"
INSTALL_ADMIN_TOKEN=`curl --noproxy "*" -k -X POST https://$SYSTEM_IP:8444/aas/token -d '{"username": "superadmin", "password": "superAdminPass" }'`

if [ $? -ne 0 ]; then
  echo "############ Could not get token for Install Admin  User####################3"
  exit 1
fi

echo "################ Update SCS env....  #################"
sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/"  ~/scs.env
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$INSTALL_ADMIN_TOKEN/"  ~/scs.env
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
scs status > /dev/null
if [ $? -ne 0 ]; then
  echo "############ SCS Installation Failed"
  exit 1
fi
echo "################ Installed SCS....  #################"

echo "################ Update SHVS env....  #################"
sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/shvs.env
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$INSTALL_ADMIN_TOKEN/" ~/shvs.env
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
shvs status > /dev/null
if [ $? -ne 0 ]; then
  echo "############ SHVS Installation Failed"
  exit 1
fi
echo "################ Installed SHVS....  #################"

echo "################ Update IHUB env....  #################"
sed -i "s/^\(TLS_SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/ihub.env
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$INSTALL_ADMIN_TOKEN/" ~/ihub.env
sed -i "s/^\(CMS_TLS_CERT_SHA384\s*=\s*\).*\$/\1$CMS_TLS_SHA/" ~/ihub.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/ihub.env
sed -i "s@^\(CMS_BASE_URL\s*=\s*\).*\$@\1$CMS_URL@" ~/ihub.env
SHVS_URL=https://$SYSTEM_IP:13000/sgx-hvs/v2
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
ihub status > /dev/null
if [ $? -ne 0 ]; then
  echo "############ IHUB Installation Failed"
  exit 1
fi
echo "################ Installed IHUB....  #################"

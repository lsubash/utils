#!/bin/bash
HOME_DIR=~/
SKC_BINARY_DIR=$HOME_DIR/binaries
KBS_HOSTNAME=$("hostname")

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

if [[ "$OS" == "rhel" && "$VER" == "8.1" || "$VER" == "8.2" ]]; then
        dnf install -qy jq
elif [[ "$OS" == "ubuntu" && "$VER" == "18.04" ]]; then
        apt install -y jq curl
else
        echo "Unsupported OS. Please use RHEL 8.1/8.2 or Ubuntu 18.04"
        exit 1
fi

# Copy env files to Home directory
\cp -pf $SKC_BINARY_DIR/env/cms.env $HOME_DIR
\cp -pf $SKC_BINARY_DIR/env/authservice.env $HOME_DIR
\cp -pf $SKC_BINARY_DIR/env/scs.env $HOME_DIR
\cp -pf $SKC_BINARY_DIR/env/sqvs.env $HOME_DIR
\cp -pf $SKC_BINARY_DIR/env/kbs.env $HOME_DIR
\cp -pf $SKC_BINARY_DIR/env/iseclpgdb.env $HOME_DIR
\cp -pf $SKC_BINARY_DIR/env/populate-users.env $HOME_DIR

\cp -pf $SKC_BINARY_DIR/trusted_rootca.pem /tmp

# Copy DB scripts to Home directory
\cp -pf $SKC_BINARY_DIR/install_pg.sh $HOME_DIR
\cp -pf $SKC_BINARY_DIR/install_pgscsdb.sh $HOME_DIR
\cp -pf $SKC_BINARY_DIR/populate-users.sh $HOME_DIR

# read from environment variables file if it exists
if [ -f ./skc.conf ]; then
    echo "Reading Installation variables from $(pwd)/skc.conf"
    source skc.conf
    env_file_exports=$(cat ./skc.conf | grep -E '^[A-Z0-9_]+\s*=' | cut -d = -f 1)
    if [ -n "$env_file_exports" ]; then eval export $env_file_exports; fi
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
echo "################ Uninstalling SQVS....  #################"
sqvs uninstall --purge
echo "################ Uninstalling KBS....  #################"
kbs uninstall --purge
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

popd

echo "################ Installing CMS....  #################"
AAS_URL=https://$SYSTEM_IP:8444/aas
sed -i "s/^\(AAS_TLS_SAN\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/cms.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/cms.env
sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/cms.env

./cms-*.bin
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
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$CMS_TOKEN/" ~/authservice.env

CMS_TLS_SHA=`cms tlscertsha384`
sed -i "s/^\(CMS_TLS_CERT_SHA384\s*=\s*\).*\$/\1$CMS_TLS_SHA/" ~/authservice.env

CMS_URL=https://$SYSTEM_IP:8445/cms/v1/
sed -i "s@^\(CMS_BASE_URL\s*=\s*\).*\$@\1$CMS_URL@" ~/authservice.env

sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/" ~/authservice.env
sed -i "s/^\(AAS_DB_NAME\s*=\s*\).*\$/\1$AAS_DB_NAME/" ~/authservice.env
sed -i "s/^\(AAS_DB_USERNAME\s*=\s*\).*\$/\1$AAS_DB_USERNAME/" ~/authservice.env
sed -i "s/^\(AAS_DB_PASSWORD\s*=\s*\).*\$/\1$AAS_DB_PASSWORD/" ~/authservice.env

./authservice-*.bin
authservice status > /dev/null
if [ $? -ne 0 ]; then
  echo "############ AuthService Installation Failed"
  exit 1
fi
echo "################ Installed AuthService....  #################"

echo "################ Update Populate users env ....  #################"
ISECL_INSTALL_COMPONENTS=AAS,SCS,SGX_AGENT,SQVS,SKBS,SKC-LIBRARY
sed -i "s@^\(ISECL_INSTALL_COMPONENTS\s*=\s*\).*\$@\1$ISECL_INSTALL_COMPONENTS@" ~/populate-users.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/populate-users.env

AAS_ADMIN_USERNAME=$(cat ~/authservice.env | grep ^AAS_ADMIN_USERNAME= | cut -d'=' -f2)
AAS_ADMIN_PASSWORD=$(cat ~/authservice.env | grep ^AAS_ADMIN_PASSWORD= | cut -d'=' -f2)
sed -i "s/^\(AAS_ADMIN_USERNAME\s*=\s*\).*\$/\1$AAS_ADMIN_USERNAME/" ~/populate-users.env
sed -i "s/^\(AAS_ADMIN_PASSWORD\s*=\s*\).*\$/\1$AAS_ADMIN_PASSWORD/" ~/populate-users.env

sed -i "s@^\(SCS_CERT_SAN_LIST\s*=\s*\).*\$@\1$SYSTEM_IP@" ~/populate-users.env
sed -i "s@^\(SGX_AGENT_CERT_SAN_LIST\s*=\s*\).*\$@\1$SGX_AGENT_IP@" ~/populate-users.env
sed -i "s@^\(KBS_CERT_SAN_LIST\s*=\s*\).*\$@\1$SYSTEM_IP@" ~/populate-users.env
sed -i "s@^\(SQVS_CERT_SAN_LIST\s*=\s*\).*\$@\1$SYSTEM_IP@" ~/populate-users.env

SCS_ADMIN_USERNAME=$(cat ~/scs.env | grep ^SCS_ADMIN_USERNAME= | cut -d'=' -f2)
SCS_ADMIN_PASSWORD=$(cat ~/scs.env | grep ^SCS_ADMIN_PASSWORD= | cut -d'=' -f2)
sed -i "s/^\(SCS_SERVICE_USERNAME\s*=\s*\).*\$/\1$SCS_ADMIN_USERNAME/" ~/populate-users.env
sed -i "s/^\(SCS_SERVICE_PASSWORD\s*=\s*\).*\$/\1$SCS_ADMIN_PASSWORD/" ~/populate-users.env

sed -i "s@^\(SGX_AGENT_USERNAME\s*=\s*\).*\$@\1$SGX_AGENT_USERNAME@" ~/populate-users.env
sed -i "s@^\(SGX_AGENT_PASSWORD\s*=\s*\).*\$@\1$SGX_AGENT_PASSWORD@" ~/populate-users.env

KBS_SERVICE_USERNAME=$(cat ~/kbs.env | grep ^KBS_SERVICE_USERNAME= | cut -d'=' -f2)
KBS_SERVICE_PASSWORD=$(cat ~/kbs.env | grep ^KBS_SERVICE_PASSWORD= | cut -d'=' -f2)
sed -i "s/^\(KBS_SERVICE_USERNAME\s*=\s*\).*\$/\1$KBS_SERVICE_USERNAME/" ~/populate-users.env
sed -i "s/^\(KBS_SERVICE_PASSWORD\s*=\s*\).*\$/\1$KBS_SERVICE_PASSWORD/" ~/populate-users.env

sed -i "s/^\(SKC_LIBRARY_USERNAME\s*=\s*\).*\$/\1$SKC_USER/" ~/populate-users.env
sed -i "s/^\(SKC_LIBRARY_PASSWORD\s*=\s*\).*\$/\1$SKC_USER_PASSWORD/" ~/populate-users.env
sed -i "s/^\(SKC_LIBRARY_CERT_COMMON_NAME\s*=\s*\).*\$/\1$SKC_USER/" ~/populate-users.env
SKC_LIBRARY_KEY_TRANSFER_CONTEXT=permissions=nginx,USA
sed -i "s/^\(SKC_LIBRARY_KEY_TRANSFER_CONTEXT\s*=\s*\).*\$/\1$SKC_LIBRARY_KEY_TRANSFER_CONTEXT/" ~/populate-users.env

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
  echo "############ Could not get token for Install Admin User ####################"
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
./scs-*.bin
scs status > /dev/null
if [ $? -ne 0 ]; then
  echo "############ SCS Installation Failed"
  exit 1
fi
echo "################ Installed SCS....  #################"

echo "################ Update SQVS env....  #################"
sed -i "s/^\(SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP/"  ~/sqvs.env
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$INSTALL_ADMIN_TOKEN/"  ~/sqvs.env
sed -i "s/^\(CMS_TLS_CERT_SHA384\s*=\s*\).*\$/\1$CMS_TLS_SHA/" ~/sqvs.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/sqvs.env
sed -i "s@^\(CMS_BASE_URL\s*=\s*\).*\$@\1$CMS_URL@" ~/sqvs.env
SCS_URL=https://$SYSTEM_IP:9000/scs/sgx/certification/v1
sed -i "s@^\(SCS_BASE_URL\s*=\s*\).*\$@\1$SCS_URL@" ~/sqvs.env

echo "################ Installing SQVS....  #################"
./sqvs-*.bin
sqvs status > /dev/null
if [ $? -ne 0 ]; then
  echo "############ SQVS Installation Failed"
  exit 1
fi
echo "################ Installed SQVS....  #################"

echo "################ Update KBS env....  #################"
sed -i "s/^\(TLS_SAN_LIST\s*=\s*\).*\$/\1$SYSTEM_IP,$KBS_DOMAIN/" ~/kbs.env
sed -i "s/^\(BEARER_TOKEN\s*=\s*\).*\$/\1$INSTALL_ADMIN_TOKEN/" ~/kbs.env
sed -i "s/^\(CMS_TLS_CERT_SHA384\s*=\s*\).*\$/\1$CMS_TLS_SHA/" ~/kbs.env
sed -i "s@^\(AAS_API_URL\s*=\s*\).*\$@\1$AAS_URL@" ~/kbs.env
sed -i "s@^\(CMS_BASE_URL\s*=\s*\).*\$@\1$CMS_URL@" ~/kbs.env
SQVS_URL=https://$SYSTEM_IP:12000/svs/v1
sed -i "s@^\(SQVS_URL\s*=\s*\).*\$@\1$SQVS_URL@" ~/kbs.env
ENDPOINT_URL=https://$SYSTEM_IP:9443/v1
sed -i "s@^\(ENDPOINT_URL\s*=\s*\).*\$@\1$ENDPOINT_URL@" ~/kbs.env

echo "################ Installing KBS....  #################"
./kbs-*.bin
kbs status > /dev/null
if [ $? -ne 0 ]; then
  echo "############ KBS Installation Failed"
  exit 1
fi
echo "################ Installed KBS....  #################"

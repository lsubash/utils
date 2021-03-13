#!/bin/bash

source isecl-skc-k8s.env
if [ $? != 0 ]; then
    echo "failed to source isecl-skc-k8s.env"
fi

if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
  KUBECTL=microk8s.kubectl
elif [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
  KUBECTL=kubectl
else
  echo "K8s Distribution" $K8S_DISTRIBUTION "not supported"
fi

CMS_TLS_CERT_SHA384=""
AAS_BOOTSTRAP_TOKEN=""
BEARER_TOKEN=""

HOME_DIR=`pwd`
AAS_DIR=$HOME_DIR/aas

AAS="aas"
CMS="cms"
SCS="scs"
SHVS="shvs"
SQVS="sqvs"
IHUB="ihub"
KBS="kbs"
SGX_AGENT="sgx-agent"
SKC_LIB="skc-library"
ISECL_SCHEDULER="isecl-k8s-scheduler"
ISECL_CONTROLLER="isecl-k8s-controller"

check_mandatory_variables() {
  IFS=',' read -ra ADDR <<< "$2"
  for env_var in "${ADDR[@]}"; do
    if [[ ! -v "${env_var}" ]]; then
        echo "$env_var is not set for service: $1"
        exit 1
    fi
  done
}

deploy_cms() {

    echo "----------------------------------------------------"
    echo "|      DEPLOY:CERTIFICATE-MANAGEMENT-SERVICE       |"
    echo "----------------------------------------------------"

   cd cms/

     # update configMap
    sed -i "s/\${SAN_LIST}/cms-svc.isecl.svc.cluster.local/g" configMap.yml
    sed -i "s/\${AAS_TLS_SAN}/aas-svc.isecl.svc.cluster.local/g" configMap.yml

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 60
    local cms_pod=''
    $KUBECTL get pod -n isecl -l app=cms | grep Running
    if [ $? == 0 ]; then
        echo "CERTIFICATE-MANAGEMENT-SERVICE DEPLOYED SUCCESSFULLY"
    else
        echo "ERROR: Failed to deploy CMS"
        echo "Exiting with error..."
        exit 1
    fi
    cd ../
}

get_cms_tls_cert_sha384(){
    cms_pod=$($KUBECTL get pod -n isecl -l app=cms -o jsonpath="{.items[0].metadata.name}")
    CMS_TLS_CERT_SHA384=$($KUBECTL exec -n isecl --stdin $cms_pod -- cms tlscertsha384)
}


get_AAS_BOOTSTRAP_TOKEN(){
  cms_pod=$($KUBECTL get pod -n isecl -l app=cms -o jsonpath="{.items[0].metadata.name}")
  AAS_BOOTSTRAP_TOKEN=$($KUBECTL exec -n isecl --stdin $cms_pod -- cms setup  cms-auth-token --force  | grep "JWT Token:" | awk '{print $3}')
}

deploy_authservice(){

    echo "----------------------------------------------------"
    echo "|    DEPLOY:AUTHENTICATION-AUTHORIZATION-SERVICE   |"
    echo "----------------------------------------------------"

    required_variables="AAS_ADMIN_USERNAME,AAS_ADMIN_PASSWORD,AAS_DB_HOSTNAME,AAS_DB_NAME,AAS_DB_PORT,AAS_DB_SSLMODE,AAS_DB_SSLCERT,AAS_BOOTSTRAP_TOKEN,AAS_SAN_LIST"
    check_mandatory_variables $AAS $required_variables

    cd aas/

    # update configMap and secrets
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: $AAS_BOOTSTRAP_TOKEN/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $CMS_TLS_CERT_SHA384/g" configMap.yml
    sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: $CMS_BASE_URL#g" configMap.yml
    sed -i "s/SAN_LIST:.*/SAN_LIST: $AAS_SAN_LIST/g" configMap.yml
    sed -i "s/AAS_DB_HOSTNAME:.*/AAS_DB_HOSTNAME: $AAS_DB_HOSTNAME/g" configMap.yml
    sed -i "s/AAS_DB_NAME:.*/AAS_DB_NAME: $AAS_DB_NAME/g" configMap.yml
    sed -i "s/AAS_DB_PORT:.*/AAS_DB_PORT: \"$AAS_DB_PORT\"/g" configMap.yml
    sed -i "s/AAS_DB_SSLMODE:.*/AAS_DB_SSLMODE: $AAS_DB_SSLMODE/g" configMap.yml
    sed -i "s#AAS_DB_SSLCERT:.*#AAS_DB_SSLCERT: $AAS_DB_SSLCERT#g" configMap.yml
    sed -i "s/AAS_ADMIN_USERNAME:.*/AAS_ADMIN_USERNAME: $AAS_ADMIN_USERNAME/g" secrets.yml
    sed -i "s/AAS_ADMIN_PASSWORD:.*/AAS_ADMIN_PASSWORD: $AAS_ADMIN_PASSWORD/g" secrets.yml

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 60
    $KUBECTL get pod -n isecl -l app=aas | grep Running
    if [ $? == 0 ]; then
        echo "AUTHENTICATION-AUTHORIZATION-SERVICE DEPLOYED SUCCESSFULLY"
    else
        echo "ERROR: Failed to deploy AAS"
        echo "Exiting with error..."
        exit 1
    fi

    echo "Waiting for AAS to bootstrap itself..."
    sleep 60
    cd $HOME_DIR
}

get_bearer_token(){

    aas_scripts_dir=$AAS_DIR/scripts
    echo "Running populate-users script"
    sed -i "s/ISECL_INSTALL_COMPONENTS=.*/ISECL_INSTALL_COMPONENTS=$ISECL_INSTALL_COMPONENTS/g" $aas_scripts_dir/populate-users.env
    sed -i "s#CMS_BASE_URL=.*#CMS_BASE_URL=$CMS_BASE_URL#g" $aas_scripts_dir/populate-users.env
    sed -i "s#AAS_API_URL=.*#AAS_API_URL=$AAS_API_CLUSTER_ENDPOINT_URL#g" $aas_scripts_dir/populate-users.env
    sed -i "s/SCS_CERT_SAN_LIST=.*/SCS_CERT_SAN_LIST=$SCS_CERT_SAN_LIST/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SHVS_CERT_SAN_LIST=.*/SHVS_CERT_SAN_LIST=$SHVS_CERT_SAN_LIST/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SQVS_CERT_SAN_LIST=.*/SQVS_CERT_SAN_LIST=$SQVS_CERT_SAN_LIST/g" $aas_scripts_dir/populate-users.env
    sed -i "s/IH_CERT_SAN_LIST=.*/IH_CERT_SAN_LIST=$IH_CERT_SAN_LIST/g" $aas_scripts_dir/populate-users.env
    sed -i "s/KBS_CERT_SAN_LIST=.*/KBS_CERT_SAN_LIST=$KBS_CERT_SAN_LIST/g" $aas_scripts_dir/populate-users.env

    sed -i "s/AAS_ADMIN_USERNAME=.*/AAS_ADMIN_USERNAME=$AAS_ADMIN_USERNAME/g" $aas_scripts_dir/populate-users.env
    sed -i "s/AAS_ADMIN_PASSWORD=.*/AAS_ADMIN_PASSWORD=$AAS_ADMIN_PASSWORD/g" $aas_scripts_dir/populate-users.env

    sed -i "s/IHUB_SERVICE_USERNAME=.*/IHUB_SERVICE_USERNAME=$IHUB_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
    sed -i "s/IHUB_SERVICE_PASSWORD=.*/IHUB_SERVICE_PASSWORD=$IHUB_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

    sed -i "s/SCS_SERVICE_USERNAME=.*/SCS_SERVICE_USERNAME=$SCS_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SCS_SERVICE_PASSWORD=.*/SCS_SERVICE_PASSWORD=$SCS_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

    sed -i "s/SHVS_SERVICE_USERNAME=.*/SHVS_SERVICE_USERNAME=$SHVS_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SHVS_SERVICE_PASSWORD=.*/SHVS_SERVICE_PASSWORD=$SHVS_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

    sed -i "s/KBS_SERVICE_USERNAME=.*/KBS_SERVICE_USERNAME=$KBS_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
    sed -i "s/KBS_SERVICE_PASSWORD=.*/KBS_SERVICE_PASSWORD=$KBS_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

    sed -i "s/CSP_ADMIN_USERNAME=.*/CSP_ADMIN_USERNAME=$CSP_ADMIN_USERNAME/g" $aas_scripts_dir/populate-users.env
    sed -i "s/CSP_ADMIN_PASSWORD=.*/CSP_ADMIN_PASSWORD=$CSP_ADMIN_PASSWORD/g" $aas_scripts_dir/populate-users.env

    sed -i "s/SKC_LIBRARY_USERNAME=.*/SKC_LIBRARY_USERNAME=$SKC_LIBRARY_USERNAME/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SKC_LIBRARY_PASSWORD=.*/SKC_LIBRARY_PASSWORD=$SKC_LIBRARY_PASSWORD/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SKC_LIBRARY_KEY_TRANSFER_CONTEXT=.*/SKC_LIBRARY_KEY_TRANSFER_CONTEXT=$SKC_LIBRARY_KEY_TRANSFER_CONTEXT/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SKC_LIBRARY_CERT_COMMON_NAME=.*/SKC_LIBRARY_CERT_COMMON_NAME=$SKC_LIBRARY_CERT_COMMON_NAME/g" $aas_scripts_dir/populate-users.env

    sed -i "s/GLOBAL_ADMIN_USERNAME=.*/GLOBAL_ADMIN_USERNAME=$GLOBAL_ADMIN_USERNAME/g" $aas_scripts_dir/populate-users.env
    sed -i "s/GLOBAL_ADMIN_PASSWORD=.*/GLOBAL_ADMIN_PASSWORD=$GLOBAL_ADMIN_PASSWORD/g" $aas_scripts_dir/populate-users.env

    sed -i "s/INSTALL_ADMIN_USERNAME=.*/INSTALL_ADMIN_USERNAME=$INSTALL_ADMIN_USERNAME/g" $aas_scripts_dir/populate-users.env
    sed -i "s/INSTALL_ADMIN_PASSWORD=.*/INSTALL_ADMIN_PASSWORD=$INSTALL_ADMIN_PASSWORD/g" $aas_scripts_dir/populate-users.env



    # TODO: need to check if this can be fetched from builds instead of bundling the script here
    chmod +x $aas_scripts_dir/populate-users
    $aas_scripts_dir/populate-users --answerfile $aas_scripts_dir/populate-users.env > $aas_scripts_dir/populate-users.log

    BEARER_TOKEN=$(grep -m 1 "BEARER_TOKEN" $aas_scripts_dir/populate-users.log | cut -d '=' -f2)
    echo "Install token: $BEARER_TOKEN"
}

deploy_scs() {

    echo "----------------------------------------------------"
    echo "|            DEPLOY:SGX CACHING SERVICE            |"
    echo "----------------------------------------------------"

    cd scs/

    # The variables BEARER_TOKEN and CMS_TLS_CERT_SHA384 get loaded with below functions, this required if we want to deploy individual hvs service
    get_bearer_token
    get_cms_tls_cert_sha384

    required_variables="BEARER_TOKEN,SCS_CERT_SAN_LIST,CMS_TLS_CERT_SHA384,AAS_API_URL,SCS_ADMIN_USERNAME,SCS_ADMIN_PASSWORD,SCS_DB_HOSTNAME,SCS_DB_NAME,SCS_DB_SSLCERTSRC,SCS_DB_PORT,INTEL_PROVISIONING_SERVER,INTEL_PROVISIONING_SERVER_API_KEY"
    check_mandatory_variables $SCS $required_variables

    # update scs configMap & secrets
    sed -i "s/SCS_ADMIN_USERNAME:.*/SCS_ADMIN_USERNAME: ${SCS_ADMIN_USERNAME}/g" secrets.yml
    sed -i "s/SCS_ADMIN_PASSWORD:.*/SCS_ADMIN_PASSWORD: ${SCS_ADMIN_PASSWORD}/g" secrets.yml
    sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: $CMS_BASE_URL#g" configMap.yml
    sed -i "s#AAS_API_URL:.*#AAS_API_URL: ${AAS_API_URL}#g" configMap.yml
    sed -i "s/SAN_LIST:.*/SAN_LIST: ${SCS_CERT_SAN_LIST}/g" configMap.yml
    sed -i "s/SCS_DB_HOSTNAME:.*/SCS_DB_HOSTNAME: ${SCS_DB_HOSTNAME}/g" configMap.yml
    sed -i "s/SCS_DB_NAME:.*/SCS_DB_NAME: ${SCS_DB_NAME}/g" configMap.yml
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: ${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: ${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s#SCS_DB_SSLCERTSRC:.*#SCS_DB_SSLCERTSRC: ${SCS_DB_SSLCERTSRC}#g" configMap.yml
    sed -i "s/SCS_DB_PORT:.*/SCS_DB_PORT: \"$SCS_DB_PORT\"/g" configMap.yml
    sed -i "s#INTEL_PROVISIONING_SERVER:.*#INTEL_PROVISIONING_SERVER: ${INTEL_PROVISIONING_SERVER}#g" configMap.yml
    sed -i "s/INTEL_PROVISIONING_SERVER_API_KEY:.*/INTEL_PROVISIONING_SERVER_API_KEY: ${INTEL_PROVISIONING_SERVER_API_KEY}/g" configMap.yml

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 60
    $KUBECTL get pod -n isecl -l app=scs | grep Running
    if [ $? == 0 ]; then
        echo "SGX CACHING SERVICE DEPLOYED SUCCESSFULLY"
    else
        echo "Error: Deploying SCS"
        echo "Exiting with error..."
        exit 1
    fi
    cd ../
}

deploy_shvs() {

    echo "-------------------------------------------------------------"
    echo "|            DEPLOY:SGX HOST VERIFICATION SERVICE            |"
    echo "-------------------------------------------------------------"

   cd shvs/

    # The variables BEARER_TOKEN and CMS_TLS_CERT_SHA384 get loaded with below functions, this required if we want to deploy individual hvs service 
    get_bearer_token
    get_cms_tls_cert_sha384

    required_variables="BEARER_TOKEN,CMS_TLS_CERT_SHA384,SHVS_CERT_SAN_LIST,AAS_API_URL,CMS_BASE_URL,SCS_BASE_URL,SHVS_DB_HOSTNAME,SHVS_DB_SSLCERTSRC,SHVS_DB_PORT,SHVS_DB_NAME"
    check_mandatory_variables $SHVS $required_variables

    # update hvs configMap & secrets
    sed -i "s/SHVS_ADMIN_USERNAME:.*/SHVS_ADMIN_USERNAME: ${SHVS_ADMIN_USERNAME}/g" secrets.yml
    sed -i "s/SHVS_ADMIN_PASSWORD:.*/SHVS_ADMIN_PASSWORD: ${SHVS_ADMIN_PASSWORD}/g" secrets.yml

    sed -i "s/SAN_LIST:.*/SAN_LIST: ${SHVS_CERT_SAN_LIST}/g" configMap.yml
    sed -i "s/SHVS_DB_HOSTNAME:.*/SHVS_DB_HOSTNAME: ${SHVS_DB_HOSTNAME}/g" configMap.yml
    sed -i "s/SHVS_DB_NAME:.*/SHVS_DB_NAME: ${SHVS_DB_NAME}/g" configMap.yml
    sed -i "s/SHVS_DB_PORT:.*/SHVS_DB_PORT: \"$SHVS_DB_PORT\"/g" configMap.yml
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: ${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: ${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s#AAS_API_URL:.*#AAS_API_URL: ${AAS_API_URL}#g" configMap.yml
    sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: ${CMS_BASE_URL}#g" configMap.yml
    sed -i "s#SCS_BASE_URL:.*#SCS_BASE_URL: ${SCS_BASE_URL}#g" configMap.yml
    sed -i "s/SHVS_DB_HOSTNAME:.*/SHVS_DB_HOSTNAME: ${SHVS_DB_HOSTNAME}/g" configMap.yml
    sed -i "s#SHVS_DB_SSLCERTSRC:.*#SHVS_DB_SSLCERTSRC: ${SHVS_DB_SSLCERTSRC}#g" configMap.yml

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 60
    $KUBECTL get pod -n isecl -l app=shvs | grep Running
    if [ $? == 0 ]; then
        echo "SGX-HOST-VERIFICATION-SERVICE DEPLOYED SUCCESSFULLY"
    else
        echo "Error: Deploying SHVS"
        echo "Exiting with error..."
        exit 1
    fi
    cd ../
}

deploy_SKC_library()
{

    echo "----------------------------------------------------"
    echo "|      DEPLOY:SKC LIBRARY                           |"
    echo "----------------------------------------------------"
    
    cd skc_library
    # deploy
    $KUBECTL create configmap skc-lib-config --from-file=resources/skc_library.conf --namespace=isecl
    $KUBECTL create configmap nginx-config --from-file=resources/nginx.conf --namespace=isecl
    $KUBECTL create configmap kbs-key-config --from-file=resources/keys.txt --namespace=isecl 
    $KUBECTL create configmap sgx-qcnl-config --from-file=resources/sgx_default_qcnl.conf --namespace=isecl
    $KUBECTL create configmap openssl-config --from-file=resources/openssl.cnf --namespace=isecl
    $KUBECTL create configmap pkcs11-config --from-file=resources/pkcs11-apimodule.ini --namespace=isecl
    $KUBECTL create secret generic kbs-cert-secret --from-file=resources/94dcee8a-580b-416f-ba6a-52d126cb2cb0.crt --namespace=isecl
    $KUBECTL create configmap haproxy-hosts-config --from-file=resources/hosts --namespace=isecl
    $KUBECTL kustomize . | $KUBECTL apply -f -


 # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 60
    $KUBECTL get pod -n isecl -l app=skclib | grep Running
    if [ $? == 0 ]; then
        echo "SKC LIBRARY DEPLOYED SUCCESSFULLY"
    else
        echo "ERROR: Failed to deploy skc library"
        echo "Exiting with error..."
        exit 1
    fi

    echo "Waiting for SKC LIBRARY to bootstrap itself..."
    sleep 60
    cd $HOME_DIR

}

deploy_sqvs() {

    echo "----------------------------------------------------"
    echo "|      DEPLOY:SGX QUOTE VERIFICATION SERVICE       |"
    echo "----------------------------------------------------"

    required_variables="SQVS_USERNAME,SQVS_PASSWORD,SQVS_INCLUDE_TOKEN,SGX_TRUSTED_ROOT_CA_PATH"
    check_mandatory_variables $SQVS $required_variables

    cd sqvs/		
    mkdir -p secrets

    # generate server.crt,server.key
    openssl req -new -x509 -days 365 -newkey rsa:4096 -addext "subjectAltName = DNS:sqvsdb-svc.isecl.svc.cluster.local" -nodes -text -out secrets/server.crt -keyout secrets/server.key -sha384 -subj "/CN=ISecl Self Sign Cert"

    # The variables BEARER_TOKEN and CMS_TLS_CERT_SHA384 get loaded with below functions, this required if we want to deploy individual hvs service 
    get_bearer_token
    get_cms_tls_cert_sha384
    
    # update sqvs configMap & secrets
    sed -i "s/SQVS_USERNAME:.*/SQVS_USERNAME: ${SQVS_USERNAME}/g" secrets.yml
    sed -i "s/SQVS_PASSWORD:.*/SQVS_PASSWORD: ${SQVS_PASSWORD}/g" secrets.yml
    sed -i "s#AAS_API_URL:.*#AAS_API_URL: ${AAS_API_URL}#g" configMap.yml
    sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: ${CMS_BASE_URL}#g" configMap.yml
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: ${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: ${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/SAN_LIST:.*/SAN_LIST: ${SQVS_CERT_SAN_LIST}/g" configMap.yml
    sed -i "s/SQVS_INCLUDE_TOKEN:.*/SQVS_INCLUDE_TOKEN: \"${SQVS_INCLUDE_TOKEN}\"/g" configMap.yml
    sed -i "s#SGX_TRUSTED_ROOT_CA_PATH:.*#SGX_TRUSTED_ROOT_CA_PATH: ${SGX_TRUSTED_ROOT_CA_PATH}#g" configMap.yml

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 60
    $KUBECTL get pod -n isecl -l app=sqvs | grep Running
    if [ $? == 0 ]; then
        echo "SGX QUOTE VERIFICATION SERVICE DEPLOYED SUCCESSFULLY"
    else
        echo "Error: Deploying SQVS"
        echo "Exiting with error..."
        exit 1
    fi
    cd ../
}

deploy_custom_controller(){

    echo "----------------------------------------------------"
    echo "|            DEPLOY: K8S-CONTROLLER                |"
    echo "----------------------------------------------------"

    cd k8s-extensions-controller/

    $KUBECTL create clusterrolebinding isecl-clusterrole --clusterrole=system:node --user=system:serviceaccount:isecl:isecl

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 60
    $KUBECTL get pod -n isecl -l app=isecl-controller | grep Running
    if [ $? == 0 ]; then
        echo "K8S-CONTROLLER DEPLOYED SUCCESSFULLY"
    else
        echo "Error: Deploying K8S-CONTROLLER"
        echo "Exiting with error..."
        exit 1
    fi

    cd ../
}

deploy_ihub(){

    echo "----------------------------------------------------"
    echo "|             DEPLOY:INTEGRATION-HUB               |"
    echo "----------------------------------------------------"

    required_variables="IHUB_SERVICE_USERNAME,IHUB_SERVICE_PASSWORD,K8S_API_SERVER_CERT"
    check_mandatory_variables $IHUB $required_variables

    cd ihub/

    kubernetes_token=$($KUBECTL get secrets -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='default')].data.token}" -n isecl |base64 --decode)

    # The variables BEARER_TOKEN and CMS_TLS_CERT_SHA384 get loaded with below functions, this required if we want to deploy individual ihub service
    get_bearer_token
    get_cms_tls_cert_sha384

    mkdir -p secrets
    mkdir -p /etc/ihub/

    if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
        API_SERVER_PORT=6443
    elif [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
        API_SERVER_PORT=16443
    else
        echo "K8s Distribution" $K8S_DISTRIBUTION "not supported"
        exit 1
    fi

    cp $K8S_API_SERVER_CERT /etc/ihub/apiserver.crt
    cp /etc/ihub/apiserver.crt secrets/apiserver.crt

    #update configMap & secrets
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: $BEARER_TOKEN/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $CMS_TLS_CERT_SHA384/g" configMap.yml
    sed -i "s/TLS_SAN_LIST:.*/TLS_SAN_LIST: $IH_CERT_SAN_LIST/g" configMap.yml
    sed -i "s/KUBERNETES_TOKEN:.*/KUBERNETES_TOKEN: $kubernetes_token/g" configMap.yml
    sed -i "s/KUBERNETES_URL:.*/KUBERNETES_URL: https:\/\/$K8_MASTER_IP:$API_SERVER_PORT\//g" configMap.yml
    sed -i "s/IHUB_SERVICE_USERNAME:.*/IHUB_SERVICE_USERNAME: $IHUB_SERVICE_USERNAME/g" secrets.yml
    sed -i "s/IHUB_SERVICE_PASSWORD:.*/IHUB_SERVICE_PASSWORD: $IHUB_SERVICE_PASSWORD/g" secrets.yml
    sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: ${CMS_BASE_URL}#g" configMap.yml
    sed -i "s#AAS_API_URL:.*#AAS_API_URL: ${AAS_API_URL}#g" configMap.yml

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 30
    $KUBECTL get pod -n isecl -l app=ihub | grep Running
    if [ $? == 0 ]; then
        echo "INTEGRATION-HUB DEPLOYED SUCCESSFULLY"
    else
        echo "Error: Deploying HUB"
        echo "Exiting with error..."
        exit 1
    fi

    cd ../

}

deploy_extended_scheduler(){

    #K8s SCHEDULER
    echo "----------------------------------------------------"
    echo "|            DEPLOY: K8S-SCHEDULER                 |"
    echo "----------------------------------------------------"

    required_variables="K8S_CA_CERT,K8S_CA_KEY"
    check_mandatory_variables "$ISECL_SCHEDULER" $required_variables

    cd k8s-extensions-scheduler/

    echo "Installing Pre-requisites"

    # create certs
    chmod +x scripts/create_k8s_extsched_certs.sh
    cd scripts && echo ./create_k8s_extsched_certs.sh -n "K8S Extended Scheduler" -s "$K8S_MASTER_IP","$K8S_MASTER_HOSTNAME" -c "$K8S_CA_CERT" -k "$K8S_CA_KEY"
    ./create_k8s_extsched_certs.sh -n "K8S Extended Scheduler" -s "$K8S_MASTER_IP","$K8S_MASTER_HOSTNAME" -c "$K8S_CA_CERT" -k "$K8S_CA_KEY"
    if [ $? -ne 0 ]; then
        echo "Error while creating certificates for extended scheduler"
        exit 1
    fi

    cd ..
    mkdir -p secrets
    cp scripts/server.key secrets/
    cp scripts/server.crt secrets/

    if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
        cp /etc/ihub/ihub_public_key.pem secrets/sgx_ihub_public_key.pem
    elif [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
        cp $IHUB_PUB_KEY_PATH secrets/sgx_ihub_public_key.pem
    else
        echo "K8s Distribution" $K8S_DISTRIBUTION "not supported"
        exit 1
    fi

    # Create kubernetes secrets scheduler-secret for isecl-scheduler.
    $KUBECTL create secret generic scheduler-certs --namespace isecl --from-file=secrets

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    cd ../
}

deploy_sagent(){

    echo "----------------------------------------------------"
    echo "|             DEPLOY:SGX-AGENT                     |"
    echo "----------------------------------------------------"

    cd sgx_agent/

    # The variables BEARER_TOKEN and CMS_TLS_CERT_SHA384 get loaded with below functions, this required if we want to deploy individual sagent service
    get_cms_tls_cert_sha384

    required_variables="CSP_ADMIN_USERNAME,CSP_ADMIN_PASSWORD,CMS_TLS_CERT_SHA384,VALIDITY_DAYS"
    check_mandatory_variables "$SGX_AGENT" $required_variables

    #update configMap
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $CMS_TLS_CERT_SHA384/g" configMap.yml
    sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: ${CMS_BASE_URL}#g" configMap.yml
    sed -i "s/VALIDITY_DAYS:.*/VALIDITY_DAYS: \"${VALIDITY_DAYS}\"/g" configMap.yml
    sed -i "s#AAS_API_URL:.*#AAS_API_URL: ${AAS_API_URL}#g" configMap.yml
    sed -i "s/CSP_ADMIN_USERNAME:.*/CSP_ADMIN_USERNAME: ${CSP_ADMIN_USERNAME}/g" secrets.yml
    sed -i "s/CSP_ADMIN_PASSWORD:.*/CSP_ADMIN_PASSWORD: ${CSP_ADMIN_PASSWORD}/g" secrets.yml
   
    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 60
    $KUBECTL get pod -n isecl -l app=sagent | grep Running
    if [ $? == 0 ]; then
        echo "SGX-AGENT DEPLOYED SUCCESSFULLY"
    else
        echo "Error: Deploying SGX-AGENT"
        echo "Exiting with error..."
        exit 1
    fi

    cd ../

}


deploy_kbs(){

    #KBS
    echo "----------------------------------------------------"
    echo "|            DEPLOY:KBS                            |"
    echo "----------------------------------------------------"

    required_variables="KBS_SERVICE_USERNAME,KBS_SERVICE_PASSWORD,SQVS_URL,ENDPOINT_URL,SKC_CHALLENGE_TYPE,SESSION_EXPIRY_TIME"
    check_mandatory_variables $KBS $required_variables

    get_bearer_token
    get_cms_tls_cert_sha384
    cd kbs/

    #update configMap
    sed -i "s/KBS_SERVICE_USERNAME:.*/KBS_SERVICE_USERNAME: ${KBS_SERVICE_USERNAME}/g" secrets.yml
    sed -i "s/KBS_SERVICE_PASSWORD:.*/KBS_SERVICE_PASSWORD: ${KBS_SERVICE_PASSWORD}/g" secrets.yml
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: $BEARER_TOKEN/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $CMS_TLS_CERT_SHA384/g" configMap.yml
    sed -i "s/TLS_SAN_LIST:.*/TLS_SAN_LIST: $KBS_CERT_SAN_LIST/g" configMap.yml
    sed -i "s#SQVS_URL:.*#SQVS_URL: $SQVS_URL#g" configMap.yml
    sed -i "s#ENDPOINT_URL:.*#ENDPOINT_URL: $ENDPOINT_URL#g" configMap.yml
    sed -i "s/SKC_CHALLENGE_TYPE:.*/SKC_CHALLENGE_TYPE: \"$SKC_CHALLENGE_TYPE\"/g" configMap.yml
    sed -i "s/SESSION_EXPIRY_TIME:.*/SESSION_EXPIRY_TIME: \"$SESSION_EXPIRY_TIME\"/g" configMap.yml

     # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    sleep 60
    $KUBECTL get pod -n isecl -l app=kbs | grep Running
    if [ $? == 0 ]; then
        echo "KBS DEPLOYED SUCCESSFULLY"
    else
        echo "Error: Deploying KBS"
        echo "Exiting with error..."
        exit 1
    fi
    cd ../

}

cleanup_kbs (){

    echo "Cleaning up KBS..."

    cd kbs/

    sed -i "s/BEARER_TOKEN: .*/BEARER_TOKEN: \${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384: .*/CMS_TLS_CERT_SHA384: \${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/TLS_SAN_LIST: .*/TLS_SAN_LIST: \${TLS_SAN_LIST}/g" configMap.yml
    sed -i "s/KBS_SERVICE_USERNAME: .*/KBS_SERVICE_USERNAME: \${KBS_SERVICE_USERNAME}/g" secrets.yml
    sed -i "s/KBS_SERVICE_PASSWORD: .*/KBS_SERVICE_PASSWORD: \${KBS_SERVICE_PASSWORD}/g" secrets.yml

    $KUBECTL delete secret kbs-service-credentials --namespace isecl
    $KUBECTL delete configmap kbs-config --namespace isecl
    $KUBECTL delete deploy kbs-deployment --namespace isecl
    $KUBECTL delete svc kbs-svc --namespace isecl

    if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
        $KUBECTL delete pvc kbs-config-pvc --namespace isecl
        $KUBECTL delete pvc kbs-logs-pvc --namespace isecl
        $KUBECTL delete pvc kbs-opt-pvc --namespace isecl
        $KUBECTL delete pv kbs-config-pv --namespace isecl
        $KUBECTL delete pv kbs-logs-pv --namespace isecl
        $KUBECTL delete pv kbs-opt-pv --namespace isecl
    fi

    cd ../
}

cleanup_SKC_library()
{

    echo "Cleaning up skc LIBRARY..."
    cd skc_library
    $KUBECTL delete secret kbs-cert-secret --namespace isecl
    $KUBECTL delete configmap skc-lib-config nginx-config kbs-key-config sgx-qcnl-config openssl-config pkcs11-config kbs-cert-config haproxy-hosts-config --namespace isecl
    $KUBECTL delete deploy skclib-deployment --namespace isecl
    $KUBECTL delete svc skclib-svc --namespace isecl
    cd ../
}

cleanup_sagent(){

    echo "Cleaning up SGX-AGENT..."

    cd sgx_agent/

    sed -i "s/BEARER_TOKEN: .*/BEARER_TOKEN: \${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384: .*/CMS_TLS_CERT_SHA384: \${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/CURRENT_IP: .*/CURRENT_IP: \${CURRENT_IP}/g" configMap.yml
    sed -i "s/SAN_LIST: .*/SAN_LIST: \${SAN_LIST}/g" configMap.yml
    sed -i "s/SGX_AGENT_USERNAME: .*/SGX_AGENT_USERNAME: \${sagent_service_username}/g" secrets.yml
    sed -i "s/SGX_AGENT_PASSWORD: .*/SGX_AGENT_PASSWORD: \${sagent_service_password}/g" secrets.yml

    $KUBECTL delete secret sagent-llt-credentials --namespace isecl
    $KUBECTL delete configmap sagent-config --namespace isecl
    $KUBECTL delete daemonset sagent-daemonset --namespace isecl

    cd ../
}

cleanup_ihub(){

    echo "Cleaning up INTEGRATION-HUB..."

    cd ihub/

    sed -i "s/BEARER_TOKEN: .*/BEARER_TOKEN: \${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384: .*/CMS_TLS_CERT_SHA384: \${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/KUBERNETES_TOKEN: .*/KUBERNETES_TOKEN: \${KUBERNETES_TOKEN}/g" configMap.yml
    sed -i "s/KUBERNETES_URL: .*/KUBERNETES_URL: \${KUBERNETES_URL}/g" configMap.yml
    sed -i "s/SAN_LIST: .*/SAN_LIST: \${SAN_LIST}/g" configMap.yml
    sed -i "s/IHUB_SERVICE_USERNAME: .*/IHUB_SERVICE_USERNAME: \${IHUB_SERVICE_USERNAME}/g" secrets.yml
    sed -i "s/IHUB_SERVICE_PASSWORD: .*/IHUB_SERVICE_PASSWORD: \${IHUB_SERVICE_PASSWORD}/g" secrets.yml

    $KUBECTL delete secret ihub-service-credentials --namespace isecl
    $KUBECTL delete configmap ihub-config --namespace isecl
    $KUBECTL delete deploy ihub-deployment --namespace isecl

    if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
       $KUBECTL delete pvc ihub-config-pvc --namespace isecl
       $KUBECTL delete pvc ihub-logs-pvc --namespace isecl
       $KUBECTL delete pv ihub-config-pv --namespace isecl
       $KUBECTL delete pv ihub-logs-pv --namespace isecl
    fi

    cd ../
}

cleanup_isecl_controller(){

    cd k8s-extensions-controller/

    $KUBECTL delete deploy isecl-controller-deployment --namespace isecl
    $KUBECTL delete crd hostattributes.crd.isecl.intel.com --namespace isecl
    $KUBECTL delete clusterrole isecl-controller --namespace isecl
    $KUBECTL delete clusterrolebinding isecl-controller-binding --namespace isecl
    $KUBECTL delete clusterrolebinding isecl-clusterrole --namespace isecl

    cd ..
}

cleanup_isecl_scheduler(){

    cd k8s-extensions-scheduler/

    $KUBECTL delete deploy isecl-scheduler-deployment --namespace isecl
    $KUBECTL delete svc isecl-scheduler-svc --namespace isecl
    rm -rf secrets

    cd ..
}


cleanup_shvs(){

    echo "Cleaning up SGX-HOST-VERIFICATION-SERVICE..."
    
    cd shvs/
    
    sed -i "s/BEARER_TOKEN: .*/BEARER_TOKEN: \${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384: .*/CMS_TLS_CERT_SHA384: \${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/SAN_LIST: .*/SAN_LIST: \${SAN_LIST}/g" configMap.yml
    sed -i "s/SHVS_SERVICE_USERNAME: .*/SHVS_SERVICE_USERNAME: \${shvs_service_username}/g" secrets.yml
    sed -i "s/SHVS_SERVICE_PASSWORD: .*/SHVS_SERVICE_PASSWORD: \${shvs_service_password}/g" secrets.yml
    sed -i "s/SHVS_DB_USERNAME: .*/SHVS_DB_USERNAME: \${shvs_db_username}/g" secrets.yml
    sed -i "s/SHVS_DB_PASSWORD: .*/SHVS_DB_PASSWORD: \${SHVS_DB_PASSWORD}/g" secrets.yml
    sed -i "s/SHVS_ADMIN_USERNAME:.*/SHVS_ADMIN_USERNAME: \${SHVS_ADMIN_USERNAME}/g" secrets.yml
    sed -i "s/SHVS_ADMIN_PASSWORD:.*/SHVS_ADMIN_PASSWORD: \${SHVS_ADMIN_PASSWORD}/g" secrets.yml
    
    $KUBECTL delete secret shvs-service-credentials --namespace isecl

    $KUBECTL delete configmap shvs-config --namespace isecl
    $KUBECTL delete deploy shvs-deployment --namespace isecl
    $KUBECTL delete svc shvs-svc --namespace isecl

    if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
        $KUBECTL delete pvc shvs-config-pvc --namespace isecl
        $KUBECTL delete pvc shvs-logs-pvc --namespace isecl
        $KUBECTL delete pv shvs-config-pv --namespace isecl
        $KUBECTL delete pv shvs-logs-pv --namespace isecl
    fi

    rm -rf secrets/server.crt
    rm -rf secrets/server.key

    cd ../
    
    echo `pwd`
}

cleanup_sqvs(){

    echo "Cleaning up SGX QUOTE VERIFICATION SERVICE..."
    
    cd sqvs/
    
    sed -i "s/BEARER_TOKEN: .*/BEARER_TOKEN: \${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384: .*/CMS_TLS_CERT_SHA384: \${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/SAN_LIST: .*/SAN_LIST: \${SAN_LIST}/g" configMap.yml
    sed -i "s/SQVS_SERVICE_USERNAME: .*/SQVS_SERVICE_USERNAME: \${sqvs_service_username}/g" secrets.yml
    sed -i "s/SQVS_SERVICE_PASSWORD: .*/SQVS_SERVICE_PASSWORD: \${sqvs_service_password}/g" secrets.yml
    
    
    $KUBECTL delete secret sqvs-service-credentials --namespace isecl
    $KUBECTL delete configmap sqvs-config --namespace isecl
    $KUBECTL delete deploy sqvs-deployment --namespace isecl
    $KUBECTL delete svc sqvs-svc --namespace isecl

    if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
        $KUBECTL delete pvc sqvs-config-pvc --namespace isecl
        $KUBECTL delete pvc sqvs-logs-pvc --namespace isecl
        $KUBECTL delete pv sqvs-config-pv --namespace isecl
        $KUBECTL delete pv sqvs-logs-pv --namespace isecl
    fi

    cd ../
    
    echo `pwd`
}

cleanup_scs(){

    echo "Cleaning up SGX CACHING SERVICE..."
    
    cd scs/
    
    sed -i "s/BEARER_TOKEN: .*/BEARER_TOKEN: \${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384: .*/CMS_TLS_CERT_SHA384: \${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/SAN_LIST: .*/SAN_LIST: \${SAN_LIST}/g" configMap.yml
    sed -i "s/SCS_ADMIN_USERNAME: .*/SCS_ADMIN_USERNAME: \${SCS_ADMIN_USERNAME}/g" secrets.yml
    sed -i "s/SCS_ADMIN_PASSWORD: .*/SCS_ADMIN_PASSWORD: \${SCS_ADMIN_PASSWORD}/g" secrets.yml
    sed -i "s/SCS_DB_USERNAME: .*/SCS_DB_USERNAME: \${SCS_DB_USERNAME}/g" secrets.yml
    sed -i "s/SCS_DB_PASSWORD: .*/SCS_DB_PASSWORD: \${SCS_DB_PASSWORD}/g" secrets.yml
    
    $KUBECTL delete secret scs-service-credentials --namespace isecl
    $KUBECTL delete configmap scs-config --namespace isecl
    $KUBECTL delete deploy scs-deployment --namespace isecl
    $KUBECTL delete svc scs-svc --namespace isecl

    if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
        $KUBECTL delete pvc scs-config-pvc --namespace isecl
        $KUBECTL delete pvc scs-logs-pvc --namespace isecl
        $KUBECTL delete pv scs-config-pv --namespace isecl
        $KUBECTL delete pv scs-logs-pv --namespace isecl
    fi

    cd ../
    
    echo `pwd`
}

cleanup_authservice() {

    echo "Cleaning up AUTHENTICATION-AUTHORIZATION-SERVICE..."

    cd aas/

    sed -i "s/BEARER_TOKEN: .*/BEARER_TOKEN: \${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384: .*/CMS_TLS_CERT_SHA384: \${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/SAN_LIST: .*/SAN_LIST: \${SAN_LIST}/g" configMap.yml
    sed -i "s/AAS_ADMIN_USERNAME: .*/AAS_ADMIN_USERNAME: \${AAS_ADMIN_USERNAME}/g" secrets.yml
    sed -i "s/AAS_ADMIN_PASSWORD: .*/AAS_ADMIN_PASSWORD: \${AAS_ADMIN_PASSWORD}/g" secrets.yml
    sed -i "s/AAS_DB_USERNAME: .*/AAS_DB_USERNAME: \${AAS_DB_USERNAME}/g" secrets.yml
    sed -i "s/AAS_DB_PASSWORD: .*/AAS_DB_PASSWORD: \${AAS_DB_PASSWORD}/g" secrets.yml

    $KUBECTL delete secret aas-service-credentials --namespace isecl
    $KUBECTL delete configmap aas-config --namespace isecl
    $KUBECTL delete deploy aas-deployment --namespace isecl
    $KUBECTL delete svc aas-svc --namespace isecl

    cd scripts/

    if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
        $KUBECTL delete pvc aas-config-pvc --namespace isecl
        $KUBECTL delete pvc aas-logs-pvc --namespace isecl
        $KUBECTL delete pv aas-config-pv --namespace isecl
        $KUBECTL delete pv aas-logs-pv --namespace isecl
    fi

    cd ../..

}

cleanup_cms(){

    echo "Cleaning up CERTIIFCATION-MANAGEMENT-SERVICE..."

    cd cms/

    sed -i "s/SAN_LIST: .*/SAN_LIST: \${SAN_LIST}/g" configMap.yml
    sed -i "s/AAS_TLS_SAN: .*/AAS_TLS_SAN: \${AAS_TLS_SAN}/g" configMap.yml

    $KUBECTL delete configmap cms-config --namespace isecl
    $KUBECTL delete deploy cms-deployment --namespace isecl
    $KUBECTL delete svc cms-svc --namespace isecl

    if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
        $KUBECTL delete pvc cms-config-pvc --namespace isecl
        $KUBECTL delete pvc cms-logs-pvc --namespace isecl
        $KUBECTL delete pv cms-config-pv --namespace isecl
        $KUBECTL delete pv cms-logs-pv --namespace isecl
    fi

    cd ../
    echo `pwd`
}

bootstrap() {

    echo "----------------------------------------------------"
    echo "|        BOOTSTRAPPING ISECL SERVICES               |"
    echo "----------------------------------------------------"

    echo "----------------------------------------------------"
    echo "|                    PRECHECKS                     |"
    echo "----------------------------------------------------"
    echo "Kubenertes-> "

    if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
        $KUBECTL version --short
        if [ $? != 0 ]; then
            echo "microk8s not installed. Cannot bootstrap ISecL Services"
            echo "Exiting with Error.."
            exit 1
        fi
    elif [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
        kubeadm version
        if [ $? != 0 ]; then
            echo "kubeadm not installed. Cannot bootstrap ISecL Services"
            echo "Exiting with Error.."
            exit 1
        fi
    else
        echo "K8s Distribution" $K8S_DISTRIBUTION "not supported"
    fi

    echo "ipAddress: $K8S_MASTER_IP"
    echo "hostName: $K8S_MASTER_HOSTNAME"

    echo "----------------------------------------------------"
    echo "|     DEPLOY: ISECL SERVICES                        |"
    echo "----------------------------------------------------"
    echo ""

    deploy_cms
    get_cms_tls_cert_sha384
    get_AAS_BOOTSTRAP_TOKEN
    deploy_authservice
    get_bearer_token
    deploy_scs
    deploy_shvs
    deploy_custom_controller
    deploy_ihub
    deploy_sagent
    deploy_sqvs
    deploy_kbs

    if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
        deploy_extended_scheduler
    fi

    cd ../

}

# #Function to cleanup Intel Micro SecL on Micro K8s
cleanup() {

    echo "----------------------------------------------------"
    echo "|                    CLEANUP                       |"
    echo "----------------------------------------------------"
    
    cleanup_SKC_library
    cleanup_kbs
    cleanup_sqvs
    cleanup_sagent
    cleanup_ihub
    cleanup_isecl_scheduler
    cleanup_isecl_controller
    cleanup_shvs
    cleanup_scs
    cleanup_authservice
    cleanup_cms
    if [ $? == 0 ]; then
        echo "Wait for pods to terminate..."
        sleep 30
    fi

}

purge() {
    echo "Cleaning up logs from /var/log/"
    rm -rf  /var/log/cms/ /var/log/authservice /var/log/scs /var/log/shvs /var/log/ihub /var/log/sgx_agent /var/log/sqvs /var/log/kbs
    echo "Cleaning up config from /etc/"
    rm -rf /etc/cms /etc/authservice /etc/scs /etc/shvs /etc/ihub /etc/sgx_agent /etc/sqvs /etc/kbs
    echo "Cleaning up data from /usr/local/kube/data/"
    rm -rf  /usr/local/kube/data/authservice /usr/local/kube/data/sgx-host-verification-service /usr/local/kube/data/sgx-caching-service
}

#Help section
print_help() {
    echo "Usage: $0 [-help/up/down/purge]"
    echo "    -help                                     Print help and exit"
    echo "    up   [all/<agent>/<service>/<usecase>]    Bootstrap SKC K8s environment for specified agent/service/usecase"
    echo "    down [all/<agent>/<service>/<usecase>]    Delete SKC K8s environment for specified agent/service/usecase [will not delete data,config and logs]"
    echo "    purge                                     Delete SKC K8s environment with data,config,logs"
    echo ""
    echo "    Available Options for up/down command:"
    echo "        agent      Can be one of sagent,skclib"
    echo "        service    Can be one of cms,authservice,scs,shvs,ihub,sqvs,kbs,isecl-controller,isecl-scheduler"
    echo "        usecase    Can be one of secure-key-caching,sgx-attestation,sgx-orchestration-k8s"
}

deploy_common_components () {
    deploy_cms
    deploy_authservice
    deploy_scs
    deploy_sagent
}

cleanup_common_components () {
    cleaup_cms
    cleanup_authservice
    cleanup_scs
    cleanup_sagent
}

#Dispatch works based on args to script
dispatch_works() {

    case $1 in
        "up" )
                  case $2 in
            	    "cms") deploy_cms
            	    ;;
            	    "authservice") deploy_authservice
            	    ;;
                  "scs") deploy_scs
            	    ;;
            	    "shvs") deploy_shvs
            	    ;;
            	    "ihub") deploy_ihub
            	    ;;
                  "sagent") deploy_sagent
            	    ;;
                  "sqvs") deploy_sqvs
            	    ;;
                  "kbs") deploy_kbs
                  ;;
            	    "isecl-controller") deploy_custom_controller
            	    ;;
            	    "isecl-scheduler") deploy_extended_scheduler
                  ;;
                  "skclib") deploy_SKC_library
            	    ;;
            	    "secure-key-caching") deploy_common_components
                                        deploy_sqvs
                                        deploy_kbs
                  ;;
                  "sgx-attestation") deploy_common_components
                  ;;
                  "sgx-orchestration-k8s")  deploy_common_components
                                        deploy_custom_controller
                                        deploy_ihub
                                        deploy_extended_scheduler
                  ;;
                  "all")  bootstrap
                  ;;
            	    *)
                	    print_help
                	    exit 1
                  ;;
	                esac
	      ;;

        "down" )
              case $2 in
               	 "cms") cleanup_cms
		  ;;
            	 "authservice") cleanup_authservice
		  ;;
		 "scs") cleanup_scs
 		  ;;
                 "shvs") cleanup_shvs
 		  ;;
            	 "ihub") cleanup_ihub
                  ;;
            	 "isecl-controller") cleanup_isecl_controller
		  ;;
		 "isecl_scheduler") cleanup_isecl_scheduler
		  ;;
                 "sagent") cleanup_sagent
                  ;;
                 "sqvs") cleanup_sqvs
                  ;;
                 "kbs") cleanup_kbs
                  ;;
                 "skclib") cleanup_SKC_library
	          ;;
            	 "secure-key-caching") cleanup_commont_components
                                        cleanup_sqvs
                                        cleanup_kbs
                  ;;
                  "sgx-attestation") cleanup_common_components
                  ;;
                  "sgx-orchestration-k8s")  cleanup_common_components
                                            cleanup_ihub
                                            cleanup_isecl_controller
                                            cleanup_isecl_scheduler
                  ;;
                  "all")  cleanup
                  ;;

               	*)
                  print_help
                  exit 1
                ;;
	            esac
	         ;;
	        "purge")
              if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
                  cleanup
                  purge
                  if [ $? -ne 0 ]; then exit 1; fi
              else
                  echo "-purge not supported"
                  exit 1
              fi
    esac
}

if [ $# -eq 0 ]; then
    print_help
    exit 1
fi

work_list=""
while getopts h:u:d:p opt; do
    case ${opt} in
    h)
        print_help
        exit 0
        ;;
    u) work_list+="up" ;;
    d) work_list+="down" ;;
    p) work_list+="purge";;
    *)
        print_help
        exit 1
        ;;
    esac
done

# run commands
dispatch_works $*

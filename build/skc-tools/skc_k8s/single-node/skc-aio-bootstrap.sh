#!/bin/bash

cms_tls_digest=""
aas_bootstrap_token=""
bearer_token=""
ip_address=$(hostname -i)
hostname=$(hostname -f)
aio_secl_dir=`pwd`
aas_dir=$aio_secl_dir/aas
K8s_API_SERVER_CERT=${K8s_API_SERVER_CERT:-/var/snap/microk8s/1916/certs/server.crt}
K8S_CA_KEY=${K8S_CA_KEY:-/var/snap/microk8s/1916/certs/ca.crt}
K8S_CA_CERT=${K8S_CA_CERT:-/var/snap/microk8s/1916/certs/ca.key}
# Setting default KUBECTl command as kubectl
KUBECTL=microk8s.kubectl
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
    cms_tls_digest=$($KUBECTL exec -n isecl --stdin $cms_pod -- cms tlscertsha384)
}


get_aas_bootstrap_token(){
  cms_pod=$($KUBECTL get pod -n isecl -l app=cms -o jsonpath="{.items[0].metadata.name}")
  aas_bootstrap_token=$($KUBECTL exec -n isecl --stdin $cms_pod -- cms setup  cms_auth_token --force  | grep "JWT Token:" | awk '{print $3}')
}

deploy_authservice(){

    echo "----------------------------------------------------"
    echo "|    DEPLOY:AUTHENTICATION-AUTHORIZATION-SERVICE   |"
    echo "----------------------------------------------------"

    cd aas/
    mkdir -p secrets

    # set user:group for pgdata directory
     mkdir -p /usr/local/kube/data/authservice/pgdata
     chmod 700 /usr/local/kube/data/authservice/pgdata
     chown -R 2000:2000 /usr/local/kube/data/authservice/pgdata

     echo `pwd`
    # generate server.crt,server.key
     openssl req -new -x509 -days 365 -newkey rsa:4096 -addext "subjectAltName = DNS:aasdb-svc.isecl.svc.cluster.local" -nodes -text -out secrets/server.crt -keyout secrets/server.key -sha384 -subj "/CN=ISecl Self Sign Cert"

    # authservice bootstrap credentials
    aas_admin_username="admin@aas"
    aas_admin_password="aasAdminPass"
    aas_db_username="aasdbuser"
    aas_db_password="aasdbpassword"

    # update configMap and secrets
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: $aas_bootstrap_token/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $cms_tls_digest/g" configMap.yml
    sed -i "s/SAN_LIST:.*/SAN_LIST: aas-svc.isecl.svc.cluster.local/g" configMap.yml
    sed -i "s/AAS_ADMIN_USERNAME:.*/AAS_ADMIN_USERNAME: $aas_admin_username/g" secrets.yml
    sed -i "s/AAS_ADMIN_PASSWORD:.*/AAS_ADMIN_PASSWORD: $aas_admin_password/g" secrets.yml
    sed -i "s/AAS_DB_USERNAME:.*/AAS_DB_USERNAME: $aas_db_username/g" secrets.yml
    sed -i "s/AAS_DB_PASSWORD:.*/AAS_DB_PASSWORD: $aas_db_password/g" secrets.yml

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
    cd $aio_secl_dir
}

get_bearer_token(){

    aas_scripts_dir=$aas_dir/scripts
    echo "Running populate-users script"
    sed -i "s/SCS_CERT_SAN_LIST=.*/SCS_CERT_SAN_LIST=scs-svc.isecl.svc.cluster.local/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SHVS_CERT_SAN_LIST=.*/SHVS_CERT_SAN_LIST=shvs-svc.isecl.svc.cluster.local/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SQVS_CERT_SAN_LIST=.*/SQVS_CERT_SAN_LIST=sqvs-svc.isecl.svc.cluster.local/g" $aas_scripts_dir/populate-users.env
    sed -i "s/IH_CERT_SAN_LIST=.*/IH_CERT_SAN_LIST=ihub-svc.isecl.svc.cluster.local/g" $aas_scripts_dir/populate-users.env
    sed -i "s/KBS_CERT_SAN_LIST=.*/KBS_CERT_SAN_LIST=$ip_address,$hostname,kbs-svc.isecl.svc.cluster.local/g" $aas_scripts_dir/populate-users.env
    sed -i "s/SGX_AGENT_CERT_SAN_LIST=.*/SGX_AGENT_CERT_SAN_LIST=$hostname/g" $aas_scripts_dir/populate-users.env

    # TODO: need to check if this can be fetched from builds instead of bundling the script here
    chmod +x $aas_scripts_dir/populate-users
    $aas_scripts_dir/populate-users --answerfile $aas_scripts_dir/populate-users.env > $aas_scripts_dir/populate-users.log

    bearer_token=$(grep -m 1 "BEARER_TOKEN" $aas_scripts_dir/populate-users.log | cut -d '=' -f2)
    echo "Install token: $bearer_token"
}

deploy_scs() {

    echo "----------------------------------------------------"
    echo "|            DEPLOY:SGX CACHING SERVICE            |"
    echo "----------------------------------------------------"

    cd scs/
    mkdir -p secrets 
    # set user:group for pgdata directory
    mkdir -p /usr/local/kube/data/sgx-caching-service/pgdata/
    chmod 700 /usr/local/kube/data/sgx-caching-service/pgdata
    chown -R 2000:2000 /usr/local/kube/data/sgx-caching-service/pgdata

    # generate server.crt,server.key
    openssl req -new -x509 -days 365 -newkey rsa:4096 -addext "subjectAltName = DNS:scsdb-svc.isecl.svc.cluster.local" -nodes -text -out secrets/server.crt -keyout secrets/server.key -sha384 -subj "/CN=ISecl Self Sign Cert"

    # The variables bearer_token and cms_tls_digest get loaded with below functions, this required if we want to deploy individual hvs service
    get_bearer_token
    get_cms_tls_cert_sha384

    # SGX Caching Service bootstrap credentials
    scs_admin_username="scs@admin"
    scs_admin_password="scsAdminPass"
    scs_db_username="scsdbuser"
    scs_db_password="scsdbpassword"
    scs_db_hostname=scsdb-svc.isecl.svc.cluster.local
    scs_db_name=pgscsdb

    # update scs configMap & secrets
    SAN_LIST=scs-svc.isecl.svc.cluster.local
    sed -i "s/SCS_ADMIN_USERNAME:.*/SCS_ADMIN_USERNAME: ${scs_admin_username}/g" secrets.yml
    sed -i "s/SCS_ADMIN_PASSWORD:.*/SCS_ADMIN_PASSWORD: ${scs_admin_password}/g" secrets.yml
    sed -i "s/SCS_DB_USERNAME:.*/SCS_DB_USERNAME: ${scs_db_username}/g" secrets.yml
    sed -i "s/SCS_DB_PASSWORD:.*/SCS_DB_PASSWORD: ${scs_db_password}/g" secrets.yml

    sed -i "s/SCS_DB_HOSTNAME:.*/SCS_DB_HOSTNAME: ${scs_db_hostname}/g" configMap.yml
    sed -i "s/SCS_DB_NAME:.*/SCS_DB_NAME: ${scs_db_name}/g" configMap.yml
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: ${bearer_token}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: ${cms_tls_digest}/g" configMap.yml
    sed -i "s/SAN_LIST:.*/SAN_LIST: ${SAN_LIST}/g" configMap.yml

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
    mkdir -p secrets
    # set user:group for pgdata directory
    mkdir -p /usr/local/kube/data/sgx-host-verification-service/pgdata/			
    chmod 700 /usr/local/kube/data/sgx-host-verification-service/pgdata
    chown -R 2000:2000 /usr/local/kube/data/sgx-host-verification-service/pgdata

    # generate server.crt,server.key
    openssl req -new -x509 -days 365 -newkey rsa:4096 -addext "subjectAltName = DNS:shvsdb-svc.isecl.svc.cluster.local" -nodes -text -out secrets/server.crt -keyout secrets/server.key -sha384 -subj "/CN=ISecl Self Sign Cert"

    # The variables bearer_token and cms_tls_digest get loaded with below functions, this required if we want to deploy individual hvs service 
    get_bearer_token
    get_cms_tls_cert_sha384
    
    # host-verification-service bootstrap credentials
    shvs_admin_username="shvs@admin"
    shvs_admin_password="shvsAdminPass"
    shvs_db_username="shvsdbuser"
    shvs_db_password="shvsdbpassword"		
    shvs_db_hostname=shvsdb-svc.isecl.svc.cluster.local
    shvs_db_name=pgshvsdb
    
    # update hvs configMap & secrets
    SAN_LIST=shvs-svc.isecl.svc.cluster.local
    sed -i "s/SHVS_ADMIN_USERNAME:.*/SHVS_ADMIN_USERNAME: ${shvs_admin_username}/g" secrets.yml
    sed -i "s/SHVS_ADMIN_PASSWORD:.*/SHVS_ADMIN_PASSWORD: ${shvs_admin_password}/g" secrets.yml
    sed -i "s/SHVS_DB_USERNAME:.*/SHVS_DB_USERNAME: ${shvs_db_username}/g" secrets.yml
    sed -i "s/SHVS_DB_PASSWORD:.*/SHVS_DB_PASSWORD: ${shvs_db_password}/g" secrets.yml
    
    sed -i "s/SHVS_DB_HOSTNAME:.*/SHVS_DB_HOSTNAME: ${shvs_db_hostname}/g" configMap.yml
    sed -i "s/SHVS_DB_NAME:.*/SHVS_DB_NAME: ${shvs_db_name}/g" configMap.yml
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: ${bearer_token}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: ${cms_tls_digest}/g" configMap.yml
    sed -i "s/SAN_LIST:.*/SAN_LIST: ${SAN_LIST}/g" configMap.yml

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
    cd $aio_secl_dir

}

deploy_sqvs() {

    echo "----------------------------------------------------"
    echo "|      DEPLOY:SGX QUOTE VERIFICATION SERVICE       |"
    echo "----------------------------------------------------"

    cd sqvs/		
    mkdir -p secrets

    # generate server.crt,server.key
    openssl req -new -x509 -days 365 -newkey rsa:4096 -addext "subjectAltName = DNS:sqvsdb-svc.isecl.svc.cluster.local" -nodes -text -out secrets/server.crt -keyout secrets/server.key -sha384 -subj "/CN=ISecl Self Sign Cert"

    # The variables bearer_token and cms_tls_digest get loaded with below functions, this required if we want to deploy individual hvs service 
    get_bearer_token
    get_cms_tls_cert_sha384
    
    # SGX Caching Service bootstrap credentials
    sqvs_username="superadmin"
    sqvs_password="superAdminPass"
    
    
    # update sqvs configMap & secrets
    SAN_LIST=sqvs-svc.isecl.svc.cluster.local
    sed -i "s/SQVS_USERNAME:.*/SQVS_USERNAME: ${sqvs_username}/g" secrets.yml
    sed -i "s/SQVS_PASSWORD:.*/SQVS_PASSWORD: ${sqvs_password}/g" secrets.yml
   
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: ${bearer_token}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: ${cms_tls_digest}/g" configMap.yml
    sed -i "s/SAN_LIST:.*/SAN_LIST: ${SAN_LIST}/g" configMap.yml

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
    #$KUBECTL create clusterrolebinding isecl-crd-clusterrole --clusterrole=isecl-controller --user=system:serviceaccount:isecl:isecl

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

    cd ihub/

    kubernetes_token=$($KUBECTL get secrets -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='default')].data.token}" -n isecl |base64 --decode)

    # The variables bearer_token and cms_tls_digest get loaded with below functions, this required if we want to deploy individual ihub service
    get_bearer_token
    get_cms_tls_cert_sha384

    # ihub bootstrap credentials
    ihub_service_username="ihub@admin"
    ihub_service_password="ihubAdminPass"
    mkdir -p secrets
    mkdir -p /etc/ihub/
    cp $K8s_API_SERVER_CERT /etc/ihub/apiserver.crt
    cp /etc/ihub/apiserver.crt secrets/apiserver.crt

    #update configMap & secrets
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: $bearer_token/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $cms_tls_digest/g" configMap.yml
    sed -i "s/TLS_SAN_LIST:.*/TLS_SAN_LIST: ihub-svc.isecl.svc.cluster.local/g" configMap.yml
    sed -i "s/KUBERNETES_TOKEN:.*/KUBERNETES_TOKEN: $kubernetes_token/g" configMap.yml
    sed -i "s/KUBERNETES_URL:.*/KUBERNETES_URL: https:\/\/$ip_address:16443\//g" configMap.yml
    sed -i "s/IHUB_SERVICE_USERNAME:.*/IHUB_SERVICE_USERNAME: $ihub_service_username/g" secrets.yml
    sed -i "s/IHUB_SERVICE_PASSWORD:.*/IHUB_SERVICE_PASSWORD: $ihub_service_password/g" secrets.yml

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

    cd k8s-extensions-scheduler/

    echo "Installing Pre-requisites"

    which cfssl
    if [ $? -ne 0 ]; then
        wget http://pkg.cfssl.org/R1.2/cfssl_linux-amd64
        chmod +x cfssl_linux-amd64
        mv cfssl_linux-amd64 /usr/local/bin/cfssl
    fi

    which cfssljson
    if [ $? -ne 0 ]; then
        wget http://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
        chmod +x cfssljson_linux-amd64
        mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
    fi

    # TODO: move the below into Dockerfile
    K8S_EXTENSIONS_DIR=/opt/isecl-k8s-extensions
    mkdir -p $K8S_EXTENSIONS_DIR

    # create certs
    chmod +x scripts/create_k8s_extsched_certs.sh
    cd scripts && echo ./create_k8s_extsched_certs.sh -n "K8S Extended Scheduler" -s "$ip_address","$hostname" -c "$K8S_CA_CERT" -k "$K8S_CA_KEY"
    ./create_k8s_extsched_certs.sh -n "K8S Extended Scheduler" -s "$ip_address","$hostname" -c "$K8S_CA_CERT" -k "$K8S_CA_KEY"
    if [ $? -ne 0 ]; then
        echo "Error while creating certificates for extended scheduler"
        exit 1
    fi

    cd ../
    mkdir secrets
    cp scripts/server.key secrets/
    cp scripts/server.crt secrets/

    # This doesn't work in multi-node cluster.
    cp /etc/ihub/ihub_public_key.pem secrets/sgx_ihub_public_key.pem

    # Create kubernetes secrets scheduler-secret for isecl-scheduler.
    $KUBECTL create secret generic scheduler-certs --namespace isecl --from-file=secrets

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    cd ../

    #echo "--policy-config-file=opt/isecl-k8s-extensions/scheduler-policy.json" >> /var/snap/microk8s/1916/args/kube-scheduler

}

deploy_sagent(){

    echo "----------------------------------------------------"
    echo "|             DEPLOY:SGX-AGENT                     |"
    echo "----------------------------------------------------"

    cd sgx_agent/

    # The variables bearer_token and cms_tls_digest get loaded with below functions, this required if we want to deploy individual sagent service
    get_cms_tls_cert_sha384
    csp_admin_username="cspAdminUser"
    csp_admin_password="cspAdminPass"

    #update configMap
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $cms_tls_digest/g" configMap.yml
    sed -i "s/CSP_ADMIN_USERNAME:.*/CSP_ADMIN_USERNAME: ${csp_admin_username}/g" secrets.yml
    sed -i "s/CSP_ADMIN_PASSWORD:.*/CSP_ADMIN_PASSWORD: ${csp_admin_password}/g" secrets.yml
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

    get_bearer_token
    get_cms_tls_cert_sha384
    cd kbs/

    # KBS bootstrap credentials
    kbs_service_username="kbs@admin"
    kbs_service_password="kbsAdminPass"

    #update configMap
    sed -i "s/KBS_SERVICE_USERNAME:.*/KBS_SERVICE_USERNAME: ${kbs_service_username}/g" secrets.yml
    sed -i "s/KBS_SERVICE_PASSWORD:.*/KBS_SERVICE_PASSWORD: ${kbs_service_password}/g" secrets.yml
    sed -i "s/BEARER_TOKEN:.*/BEARER_TOKEN: $bearer_token/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $cms_tls_digest/g" configMap.yml
    sed -i "s/TLS_SAN_LIST:.*/TLS_SAN_LIST: $ip_address,$hostname,kbs-svc.isecl.svc.cluster.local/g" configMap.yml

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
    sed -i "s/KBS_SERVICE_USERNAME: .*/KBS_SERVICE_USERNAME: \${kbs_service_username}/g" secrets.yml
    sed -i "s/KBS_SERVICE_PASSWORD: .*/KBS_SERVICE_PASSWORD: \${kbs_service_password}/g" secrets.yml

    $KUBECTL delete secret kbs-service-credentials --namespace isecl
    $KUBECTL delete configmap kbs-config --namespace isecl
    $KUBECTL delete deploy kbs-deployment --namespace isecl
    $KUBECTL delete svc kbs-svc --namespace isecl

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

    $KUBECTL delete secret sagent-service-credentials --namespace isecl
    $KUBECTL delete configmap sagent-config --namespace isecl
    $KUBECTL delete deploy sagent-deployment --namespace isecl
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
    sed -i "s/IHUB_SERVICE_USERNAME: .*/IHUB_SERVICE_USERNAME: \${ihub_service_username}/g" secrets.yml
    sed -i "s/IHUB_SERVICE_PASSWORD: .*/IHUB_SERVICE_PASSWORD: \${ihub_service_password}/g" secrets.yml

    $KUBECTL delete secret ihub-service-credentials --namespace isecl
    $KUBECTL delete configmap ihub-config --namespace isecl
    $KUBECTL delete deploy ihub-deployment --namespace isecl
    $KUBECTL delete svc ihub-svc --namespace isecl

    cd ../
}

cleanup_k8s_extensions(){

    cd k8s-extensions-controller/

    $KUBECTL delete crd hostattributes.crd.isecl.intel.com --namespace isecl
    $KUBECTL delete deploy isecl-controller isecl-scheduler --namespace isecl
    $KUBECTL delete svc isecl-scheduler-svc --namespace isecl
    $KUBECTL delete clusterrole isecl-controller --namespace isecl
    $KUBECTL delete clusterrolebinding isecl-controller-binding --namespace isecl

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
    sed -i "s/SHVS_DB_PASSWORD: .*/SHVS_DB_PASSWORD: \${shvs_db_password}/g" secrets.yml
    sed -i "s/SHVS_ADMIN_USERNAME:.*/SHVS_ADMIN_USERNAME: \${shvs_admin_username}/g" secrets.yml
    sed -i "s/SHVS_ADMIN_PASSWORD:.*/SHVS_ADMIN_PASSWORD: \${shvs_admin_password}/g" secrets.yml
    
    $KUBECTL delete secret shvs-db-credentials shvs-service-credentials shvs-db-certs --namespace isecl
    $KUBECTL delete configmap shvs-config shvs-db-config --namespace isecl
    $KUBECTL delete deploy shvsdb-deployment shvs-deployment --namespace isecl
    $KUBECTL delete svc shvsdb-svc shvs-svc --namespace isecl
   
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
   
    rm -rf secrets/server.crt
    rm -rf secrets/server.key

    cd ../
    
    echo `pwd`
}

cleanup_scs(){

    echo "Cleaning up SGX CACHING SERVICE..."
    
    cd scs/
    
    sed -i "s/BEARER_TOKEN: .*/BEARER_TOKEN: \${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384: .*/CMS_TLS_CERT_SHA384: \${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/SAN_LIST: .*/SAN_LIST: \${SAN_LIST}/g" configMap.yml
    sed -i "s/SCS_ADMIN_USERNAME: .*/SCS_ADMIN_USERNAME: \${scs_admin_username}/g" secrets.yml
    sed -i "s/SCS_ADMIN_PASSWORD: .*/SCS_ADMIN_PASSWORD: \${scs_admin_password}/g" secrets.yml
    sed -i "s/SCS_DB_USERNAME: .*/SCS_DB_USERNAME: \${scs_db_username}/g" secrets.yml
    sed -i "s/SCS_DB_PASSWORD: .*/SCS_DB_PASSWORD: \${scs_db_password}/g" secrets.yml
    
    $KUBECTL delete secret scs-db-credentials scs-service-credentials scs-db-certs --namespace isecl
    $KUBECTL delete configmap scs-config scs-db-config --namespace isecl
    $KUBECTL delete deploy scsdb-deployment scs-deployment --namespace isecl
    $KUBECTL delete svc scsdb-svc scs-svc --namespace isecl
   
    rm -rf secrets/server.crt
    rm -rf secrets/server.key

    cd ../
    
    echo `pwd`
}

cleanup_authservice() {

    echo "Cleaning up AUTHENTICATION-AUTHORIZATION-SERVICE..."

    cd aas/

    sed -i "s/BEARER_TOKEN: .*/BEARER_TOKEN: \${BEARER_TOKEN}/g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384: .*/CMS_TLS_CERT_SHA384: \${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s/SAN_LIST: .*/SAN_LIST: \${SAN_LIST}/g" configMap.yml
    sed -i "s/AAS_ADMIN_USERNAME: .*/AAS_ADMIN_USERNAME: \${aas_admin_username}/g" secrets.yml
    sed -i "s/AAS_ADMIN_PASSWORD: .*/AAS_ADMIN_PASSWORD: \${aas_admin_password}/g" secrets.yml
    sed -i "s/AAS_DB_USERNAME: .*/AAS_DB_USERNAME: \${aas_db_username}/g" secrets.yml
    sed -i "s/AAS_DB_PASSWORD: .*/AAS_DB_PASSWORD: \${aas_db_password}/g" secrets.yml

    $KUBECTL delete secret aas-db-credentials aas-service-credentials aas-db-certs --namespace isecl
    $KUBECTL delete configmap aas-config aas-db-config --namespace isecl
    $KUBECTL delete deploy aasdb-deployment aas-deployment --namespace isecl
    $KUBECTL delete svc aasdb-svc aas-svc --namespace isecl

    rm -rf secrets/server.crt
    rm -rf secrets/server.key

    cd scripts/

    sed -i "s/SHVS_CERT_SAN_LIST=.*/SHVS_CERT_SAN_LIST=/g" populate-users.env
    sed -i "s/IH_CERT_SAN_LIST=.*/SIH_CERT_SAN_LIST=/g" populate-users.env
    sed -i "s/SQVS_CERT_SAN_LIST=.*/SQVS_CERT_SAN_LIST=/g" populate-users.env
    sed -i "s/KBS_CERT_SAN_LIST=.*/SKBS_CERT_SAN_LIST=/g" populate-users.env
    sed -i "s/SCS_CERT_SAN_LIST=.*/SCS_CERT_SAN_LIST=/g" populate-users.env
    sed -i "s/SGX_AGENT_CERT_SAN_LIST=.*/SGX_AGENT_CERT_SAN_LIST=/g" populate-users.env

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

    cd ../
    echo `pwd`
}

bootstrap() {

    echo "----------------------------------------------------"
    echo "|         WELCOME TO ISECL-AIO-STACK               |"
    echo "----------------------------------------------------"

    echo "----------------------------------------------------"
    echo "|                    PRECHECKS                     |"
    echo "----------------------------------------------------"
    echo "Kubenertes-> "

    if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
      KUBECTL=microk8s.kubectl
      $KUBECTL version --short
      if [ $? != 0 ]; then
          echo "Microk8s not installed. Cannot bootstrap Intel-Micro-SecL"
          echo "Exiting with Error.."
          exit 1
      fi
    elif [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
      KUBECTL=kubectl
      kubeadm version
      if [ $? != 0 ]; then
          echo "kubeadm not installed. Cannot bootstrap Intel-Micro-SecL"
          echo "Exiting with Error.."
          exit 1
      fi
    else
      echo "K8s Distribution" $K8S_DISTRIBUTION "not supported"
    fi
    echo "OpenSSL->"
    openssl version
    if [ $? != 0 ]; then
        echo "OpenSSL is not installed. Cannot create certificates needed for SSL connection to DB"
        echo "Exiting with Error.."
        exit 1
    fi

    ip_address=$(hostname -i)
    hostname=$(hostname -f)
    echo "ipAddress: $ip_address"
    echo "hostName: $hostname"

    echo "----------------------------------------------------"
    echo "|     DEPLOY:NAMESPACE FOR AIO SECL DEPLOYMENT     |"
    echo "----------------------------------------------------"
    echo ""

    $KUBECTL create namespace isecl

    echo "----------------------------------------------------"
    echo "|     DEPLOY: SERVICES FOR AIO SECL                 |"
    echo "----------------------------------------------------"
    echo ""

    deploy_cms
    get_cms_tls_cert_sha384
    get_aas_bootstrap_token
    deploy_authservice
    get_bearer_token
    deploy_scs
    deploy_shvs
    deploy_custom_controller
    deploy_ihub
    deploy_sagent
    deploy_sqvs
    deploy_kbs
    deploy_extended_scheduler
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
    cleanup_k8s_extensions
    cleanup_shvs
    cleanup_scs
    cleanup_authservice
    cleanup_cms
    if [ $? == 0 ]; then
        echo "Wait for pods to terminate..."
        sleep 30
    fi

    #DELETE NAMESPACE
    $KUBECTL delete namespace isecl

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
    echo "Usage: $0 [-help/-up/-down/-p]"
    echo "    -help    print help and exit"
    echo "    -up      Bootstrap Intel AIO SecL environment"
    echo "    -down    Delete Intel AIO SecL environment[will not delete data,config and logs]"
    echo "    -purge   Delete data,config,logs of Intel AIO SecL environment"
}

#Dispatch works based on args to script
dispatch_works() {
    if [[ $1 == *"up"* ]]; then
        if [[ -z "$2" ]];
        then
            bootstrap
        else
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
            	*)
                	print_help
                	exit 1
                ;;
	     esac
        fi
        if [ $? -ne 0 ]; then exit 1; fi
    fi
    if [[ $1 == *"down"* ]]; then
        if [[ -z "$2" ]];
        then
            cleanup
        else
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
            	"k8s_extensions") cleanup_k8s_extensions
		          ;;
              "sagent") cleanup_sagent
              ;;
              "sqvs") cleanup_sqvs
              ;;
              "kbs") cleanup_kbs
              ;;
              "skclib") cleanup_SKC_library
	      ;;
            	*)
                print_help
                exit 1
                ;;
	    esac
        fi
        if [ $? -ne 0 ]; then exit 1; fi
    fi
    if [[ $1 == *"purge"* ]]; then
        cleanup
        purge
        if [ $? -ne 0 ]; then exit 1; fi
    fi
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

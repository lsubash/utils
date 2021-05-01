#!/bin/bash

source isecl-k8s.env
if [ $? != 0 ]; then
  echo "failed to source isecl-k8s.env"
fi

CMS_TLS_CERT_SHA384=""
AAS_BOOTSTRAP_TOKEN=""
BEARER_TOKEN=""

HOME_DIR=$(pwd)
AAS_DIR=$HOME_DIR/aas

AAS="aas"
CMS="cms"
HVS="hvs"
IHUB="ihub"
KBS="kbs"
WLS="wls"
TAGENT="tagent"
WLAGENT="wlagent"
ISECL_SCHEDULER="isecl-k8s-scheduler"
ISECL_CONTROLLER="isecl-k8s-controller"

check_k8s_distribution() {
  if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
    KUBECTL=microk8s.kubectl
  elif [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    KUBECTL=kubectl
  else
    echo "K8s Distribution \"$K8S_DISTRIBUTION\" not supported"
  fi
}

check_mandatory_variables() {
  IFS=',' read -ra ADDR <<<"$2"
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
  sed -i "s/SAN_LIST:.*/SAN_LIST: $CMS_SAN_LIST/g" configMap.yml
  sed -i "s/AAS_TLS_SAN:.*/AAS_TLS_SAN: $AAS_SAN_LIST/g" configMap.yml

  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  # wait to get ready
  echo "Wait for pods to initialize..."
  POD_NAME=`$KUBECTL get pod -l app=cms -n isecl -o name`
  $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
  if [ $? == 0 ]; then
    echo "CERTIFICATE-MANAGEMENT-SERVICE DEPLOYED SUCCESSFULLY"
  else
    echo "ERROR: Failed to deploy CMS"
    echo "Exiting with error..."
    exit 1
  fi
  echo "Waiting for CMS to bootstrap itself..."
  sleep 20
  cd $HOME_DIR
}

get_cms_tls_cert_sha384() {
  cms_pod=$($KUBECTL get pod -n isecl -l app=cms -o jsonpath="{.items[0].metadata.name}")
  CMS_TLS_CERT_SHA384=$($KUBECTL exec -n isecl --stdin $cms_pod -- cms tlscertsha384)
}

get_aas_bootstrap_token() {
  cms_pod=$($KUBECTL get pod -n isecl -l app=cms -o jsonpath="{.items[0].metadata.name}")
  AAS_BOOTSTRAP_TOKEN=$($KUBECTL exec -n isecl --stdin $cms_pod -- cms setup cms-auth-token --force | grep "JWT Token:" | awk '{print $3}')
}

deploy_authservice() {

  get_cms_tls_cert_sha384
  get_aas_bootstrap_token
  echo "----------------------------------------------------"
  echo "|    DEPLOY:AUTHENTICATION-AUTHORIZATION-SERVICE   |"
  echo "----------------------------------------------------"

  required_variables="AAS_ADMIN_USERNAME,AAS_ADMIN_PASSWORD,AAS_DB_HOSTNAME,AAS_DB_NAME,AAS_DB_PORT,AAS_DB_SSLMODE,AAS_DB_SSLCERT,AAS_BOOTSTRAP_TOKEN,AAS_SAN_LIST"
  check_mandatory_variables $AAS $required_variables

  cd aas/

  # update configMap and secrets
  sed -i "s/BEARER_TOKEN=.*/BEARER_TOKEN=$AAS_BOOTSTRAP_TOKEN/g" secrets.txt
  sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $CMS_TLS_CERT_SHA384/g" configMap.yml
  sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: $CMS_BASE_URL#g" configMap.yml
  sed -i "s/SAN_LIST:.*/SAN_LIST: $AAS_SAN_LIST/g" configMap.yml
  sed -i "s/AAS_DB_HOSTNAME:.*/AAS_DB_HOSTNAME: $AAS_DB_HOSTNAME/g" configMap.yml
  sed -i "s/AAS_DB_NAME:.*/AAS_DB_NAME: $AAS_DB_NAME/g" configMap.yml
  sed -i "s/AAS_DB_PORT:.*/AAS_DB_PORT: \"$AAS_DB_PORT\"/g" configMap.yml
  sed -i "s/AAS_DB_SSLMODE:.*/AAS_DB_SSLMODE: $AAS_DB_SSLMODE/g" configMap.yml
  sed -i "s#AAS_DB_SSLCERT:.*#AAS_DB_SSLCERT: $AAS_DB_SSLCERT#g" configMap.yml
  sed -i "s/AAS_DB_USERNAME=.*/AAS_DB_USERNAME=$AAS_DB_USERNAME/g" secrets.txt
  sed -i "s/AAS_DB_PASSWORD=.*/AAS_DB_PASSWORD=$AAS_DB_PASSWORD/g" secrets.txt
  sed -i "s/AAS_ADMIN_USERNAME=.*/AAS_ADMIN_USERNAME=$AAS_ADMIN_USERNAME/g" secrets.txt
  sed -i "s/AAS_ADMIN_PASSWORD=.*/AAS_ADMIN_PASSWORD=$AAS_ADMIN_PASSWORD/g" secrets.txt

  $KUBECTL create secret generic aas-secret --from-file=secrets.txt --namespace=isecl
  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  # wait to get ready
  echo "Wait for pods to initialize..."
  POD_NAME=`$KUBECTL get pod -l app=aas -n isecl -o name`
  $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
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

get_bearer_token() {

  aas_scripts_dir=$AAS_DIR/scripts
  echo "Running populate-users script"
  sed -i "s/ISECL_INSTALL_COMPONENTS=.*/ISECL_INSTALL_COMPONENTS=$ISECL_INSTALL_COMPONENTS/g" $aas_scripts_dir/populate-users.env
  sed -i "s#CMS_BASE_URL=.*#CMS_BASE_URL=$CMS_BASE_URL#g" $aas_scripts_dir/populate-users.env
  sed -i "s#AAS_API_URL=.*#AAS_API_URL=$AAS_API_CLUSTER_ENDPOINT_URL#g" $aas_scripts_dir/populate-users.env
  sed -i "s/HVS_CERT_SAN_LIST=.*/HVS_CERT_SAN_LIST=$HVS_CERT_SAN_LIST/g" $aas_scripts_dir/populate-users.env
  sed -i "s/IH_CERT_SAN_LIST=.*/IH_CERT_SAN_LIST=$IH_CERT_SAN_LIST/g" $aas_scripts_dir/populate-users.env
  sed -i "s/KBS_CERT_SAN_LIST=.*/KBS_CERT_SAN_LIST=$KBS_CERT_SAN_LIST/g" $aas_scripts_dir/populate-users.env
  sed -i "s/WLS_CERT_SAN_LIST=.*/WLS_CERT_SAN_LIST=$WLS_CERT_SAN_LIST/g" $aas_scripts_dir/populate-users.env
  sed -i "s#TA_CERT_SAN_LIST=.*#TA_CERT_SAN_LIST=$TA_CERT_SAN_LIST#g" $aas_scripts_dir/populate-users.env

  sed -i "s/AAS_ADMIN_USERNAME=.*/AAS_ADMIN_USERNAME=$AAS_ADMIN_USERNAME/g" $aas_scripts_dir/populate-users.env
  sed -i "s/AAS_ADMIN_PASSWORD=.*/AAS_ADMIN_PASSWORD=$AAS_ADMIN_PASSWORD/g" $aas_scripts_dir/populate-users.env

  sed -i "s/IHUB_SERVICE_USERNAME=.*/IHUB_SERVICE_USERNAME=$IHUB_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
  sed -i "s/IHUB_SERVICE_PASSWORD=.*/IHUB_SERVICE_PASSWORD=$IHUB_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

  sed -i "s/WLS_SERVICE_USERNAME=.*/WLS_SERVICE_USERNAME=$WLS_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
  sed -i "s/WLS_SERVICE_PASSWORD=.*/WLS_SERVICE_PASSWORD=$WLS_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

  sed -i "s/WLA_SERVICE_USERNAME=.*/WLA_SERVICE_USERNAME=$WLA_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
  sed -i "s/WLA_SERVICE_PASSWORD=.*/WLA_SERVICE_PASSWORD=$WLA_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

  sed -i "s/WPM_SERVICE_USERNAME=.*/WPM_SERVICE_USERNAME=$WPM_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
  sed -i "s/WPM_SERVICE_PASSWORD=.*/WPM_SERVICE_PASSWORD=$WPM_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

  sed -i "s/HVS_SERVICE_USERNAME=.*/HVS_SERVICE_USERNAME=$HVS_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
  sed -i "s/HVS_SERVICE_PASSWORD=.*/HVS_SERVICE_PASSWORD=$HVS_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

  sed -i "s/KBS_SERVICE_USERNAME=.*/KBS_SERVICE_USERNAME=$KBS_SERVICE_USERNAME/g" $aas_scripts_dir/populate-users.env
  sed -i "s/KBS_SERVICE_PASSWORD=.*/KBS_SERVICE_PASSWORD=$KBS_SERVICE_PASSWORD/g" $aas_scripts_dir/populate-users.env

  sed -i "s/INSTALL_ADMIN_USERNAME=.*/INSTALL_ADMIN_USERNAME=$INSTALL_ADMIN_USERNAME/g" $aas_scripts_dir/populate-users.env
  sed -i "s/INSTALL_ADMIN_PASSWORD=.*/INSTALL_ADMIN_PASSWORD=$INSTALL_ADMIN_PASSWORD/g" $aas_scripts_dir/populate-users.env
 
  sed -i "s/GLOBAL_ADMIN_USERNAME=.*/GLOBAL_ADMIN_USERNAME=$GLOBAL_ADMIN_USERNAME/g" $aas_scripts_dir/populate-users.env
  sed -i "s/GLOBAL_ADMIN_PASSWORD=.*/GLOBAL_ADMIN_PASSWORD=$GLOBAL_ADMIN_PASSWORD/g" $aas_scripts_dir/populate-users.env

  sed -i "s/CCC_ADMIN_USERNAME=.*//g" $aas_scripts_dir/populate-users.env
  sed -i "s/CCC_ADMIN_PASSWORD=.*//g" $aas_scripts_dir/populate-users.env

  # TODO: need to check if this can be fetched from builds instead of bundling the script here
  chmod +x $aas_scripts_dir/populate-users
  $aas_scripts_dir/populate-users --answerfile $aas_scripts_dir/populate-users.env >$aas_scripts_dir/populate-users.log

  BEARER_TOKEN=$(grep -m 1 "BEARER_TOKEN" $aas_scripts_dir/populate-users.log | cut -d '=' -f2)
  echo "Install token: $BEARER_TOKEN"
}

deploy_hvs() {

  echo "-------------------------------------------------------------"
  echo "|            DEPLOY: HOST VERIFICATION SERVICE            |"
  echo "-------------------------------------------------------------"

  cd hvs/

  # The variables BEARER_TOKEN and CMS_TLS_CERT_SHA384 get loaded with below functions, this required if we want to deploy individual hvs service
  get_bearer_token
  get_cms_tls_cert_sha384

  required_variables="BEARER_TOKEN,CMS_TLS_CERT_SHA384,HVS_SERVICE_USERNAME,HVS_SERVICE_PASSWORD,HVS_CERT_SAN_LIST,AAS_API_URL,CMS_BASE_URL,HVS_DB_HOSTNAME,HVS_DB_SSLCERTSRC,HVS_DB_PORT,HVS_DB_NAME"
  check_mandatory_variables $SHVS $required_variables

  # update hvs configMap & secrets
  sed -i "s/HVS_SERVICE_USERNAME=.*/HVS_SERVICE_USERNAME=${HVS_SERVICE_USERNAME}/g" secrets.txt
  sed -i "s/HVS_SERVICE_PASSWORD=.*/HVS_SERVICE_PASSWORD=${HVS_SERVICE_PASSWORD}/g" secrets.txt
  sed -i "s/HVS_DB_USERNAME=.*/HVS_DB_USERNAME=${HVS_DB_USERNAME}/g" secrets.txt
  sed -i "s/HVS_DB_PASSWORD=.*/HVS_DB_PASSWORD=${HVS_DB_PASSWORD}/g" secrets.txt

  sed -i "s/SAN_LIST:.*/SAN_LIST: ${HVS_CERT_SAN_LIST}/g" configMap.yml
  sed -i "s/HVS_DB_HOSTNAME:.*/HVS_DB_HOSTNAME: ${HVS_DB_HOSTNAME}/g" configMap.yml
  sed -i "s/HVS_DB_NAME:.*/HVS_DB_NAME: ${HVS_DB_NAME}/g" configMap.yml
  sed -i "s/HVS_DB_PORT:.*/HVS_DB_PORT: \"$HVS_DB_PORT\"/g" configMap.yml
  sed -i "s/BEARER_TOKEN=.*/BEARER_TOKEN=${BEARER_TOKEN}/g" secrets.txt
  sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: ${CMS_TLS_CERT_SHA384}/g" configMap.yml
  sed -i "s#AAS_API_URL:.*#AAS_API_URL: ${AAS_API_URL}#g" configMap.yml
  sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: ${CMS_BASE_URL}#g" configMap.yml
  sed -i "s/HVS_DB_HOSTNAME:.*/HVS_DB_HOSTNAME: ${HVS_DB_HOSTNAME}/g" configMap.yml
  sed -i "s#HVS_DB_SSLCERTSRC:.*#HVS_DB_SSLCERTSRC: ${HVS_DB_SSLCERTSRC}#g" configMap.yml

  $KUBECTL create secret generic hvs-secret --from-file=secrets.txt --namespace=isecl

  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  # wait to get ready
  echo "Wait for pods to initialize..."
  POD_NAME=`$KUBECTL get pod -l app=hvs -n isecl -o name`
  $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
  if [ $? == 0 ]; then
    echo "HOST-VERIFICATION-SERVICE DEPLOYED SUCCESSFULLY"
  else
    echo "Error: Deploying HVS"
    echo "Exiting with error..."
    exit 1
  fi
  cd $HOME_DIR
}

deploy_custom_controller() {

  echo "----------------------------------------------------"
  echo "|            DEPLOY: K8S-CONTROLLER                |"
  echo "----------------------------------------------------"

  cd k8s-extensions-controller/

  $KUBECTL create clusterrolebinding isecl-clusterrole --clusterrole=system:node --user=system:serviceaccount:isecl:isecl

  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  # wait to get ready
  echo "Wait for pods to initialize..."
  POD_NAME=`$KUBECTL get pod -l app=isecl-controller -n isecl -o name`
  $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
  if [ $? == 0 ]; then
    echo "K8S-CONTROLLER DEPLOYED SUCCESSFULLY"
  else
    echo "Error: Deploying K8S-CONTROLLER"
    echo "Exiting with error..."
    exit 1
  fi

  cd $HOME_DIR
}

deploy_ihub() {

  echo "----------------------------------------------------"
  echo "|             DEPLOY:INTEGRATION-HUB               |"
  echo "----------------------------------------------------"

  required_variables="IHUB_SERVICE_USERNAME,IHUB_SERVICE_PASSWORD,K8S_API_SERVER_CERT,HVS_BASE_URL"
  check_mandatory_variables $IHUB $required_variables

  cd ihub/

  kubernetes_token=$($KUBECTL get secrets -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='default')].data.token}" -n isecl | base64 --decode)

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

  cp $K8S_API_SERVER_CERT secrets/apiserver.crt

  #update configMap & secrets
  sed -i "s/BEARER_TOKEN=.*/BEARER_TOKEN=${BEARER_TOKEN}/g" secrets.txt
  sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $CMS_TLS_CERT_SHA384/g" configMap.yml
  sed -i "s/TLS_SAN_LIST:.*/TLS_SAN_LIST: $IH_CERT_SAN_LIST/g" configMap.yml
  sed -i "s/KUBERNETES_TOKEN:.*/KUBERNETES_TOKEN: $kubernetes_token/g" configMap.yml
  sed -i "s/KUBERNETES_URL:.*/KUBERNETES_URL: https:\/\/$K8S_MASTER_IP:$API_SERVER_PORT\//g" configMap.yml
  sed -i "s/IHUB_SERVICE_USERNAME=.*/IHUB_SERVICE_USERNAME=$IHUB_SERVICE_USERNAME/g" secrets.txt
  sed -i "s/IHUB_SERVICE_PASSWORD=.*/IHUB_SERVICE_PASSWORD=$IHUB_SERVICE_PASSWORD/g" secrets.txt
  sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: ${CMS_BASE_URL}#g" configMap.yml
  sed -i "s#AAS_API_URL:.*#AAS_API_URL: ${AAS_API_URL}#g" configMap.yml
  sed -i "s#HVS_BASE_URL:.*#HVS_BASE_URL: ${HVS_BASE_URL}#g" configMap.yml
  sed -i "s/SHVS_BASE_URL:.*//g" configMap.yml
  

  $KUBECTL create secret generic ihub-secret --from-file=secrets.txt --namespace=isecl

  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  # wait to get ready
  echo "Wait for pods to initialize..."
  POD_NAME=`$KUBECTL get pod -l app=ihub -n isecl -o name`
  $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
  if [ $? == 0 ]; then
    echo "INTEGRATION-HUB DEPLOYED SUCCESSFULLY"
  else
    echo "Error: Deploying HUB"
    echo "Exiting with error..."
    exit 1
  fi

  cd $HOME_DIR

}

deploy_extended_scheduler() {

  #K8s SCHEDULER
  echo "----------------------------------------------------"
  echo "|            DEPLOY: K8S-SCHEDULER                 |"
  echo "----------------------------------------------------"

  required_variables="K8S_CA_CERT,K8S_CA_KEY"
  check_mandatory_variables "$ISECL_SCHEDULER" $required_variables

  cd k8s-extensions-scheduler/

  echo "Installing Pre-requisites"

  sed -i "s#{HVS_IHUB_PUBLIC_KEY_PATH_VALUE}#\"/opt/isecl-k8s-extensions/hvs_ihub_public_key.pem\"#g" isecl-scheduler.yml
  sed -i "s#{SGX_IHUB_PUBLIC_KEY_PATH_VALUE}#\"\"#g" isecl-scheduler.yml
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
    cp /etc/ihub/ihub_public_key.pem secrets/hvs_ihub_public_key.pem
  elif [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    cp $IHUB_PUB_KEY_PATH secrets/hvs_ihub_public_key.pem
  else
    echo "K8s Distribution" $K8S_DISTRIBUTION "not supported"
    exit 1
  fi

  # Create kubernetes secrets scheduler-secret for isecl-scheduler.
  $KUBECTL create secret generic scheduler-certs --namespace isecl --from-file=secrets

  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  cd $HOME_DIR
}

deploy_kbs() {

  #KBS
  echo "----------------------------------------------------"
  echo "|            DEPLOY:KBS                            |"
  echo "----------------------------------------------------"

  required_variables="ENDPOINT_URL,KBS_CERT_SAN_LIST"
  check_mandatory_variables $KBS $required_variables

  get_bearer_token
  get_cms_tls_cert_sha384
  cd kbs/

  #update configMap
  sed -i "s/BEARER_TOKEN=.*/BEARER_TOKEN=${BEARER_TOKEN}/g" secrets.txt
  sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $CMS_TLS_CERT_SHA384/g" configMap.yml
  sed -i "s/TLS_SAN_LIST:.*/TLS_SAN_LIST: $KBS_CERT_SAN_LIST/g" configMap.yml
  sed -i "s#ENDPOINT_URL:.*#ENDPOINT_URL: $ENDPOINT_URL#g" configMap.yml
  sed -i "s/SKC_CHALLENGE_TYPE:.*//g" configMap.yml
  sed -i "s/SQVS_URL:.*//g" configMap.yml
  sed -i "s/SESSION_EXPIRY_TIME:.*//g" configMap.yml


  $KUBECTL create secret generic kbs-secret --from-file=secrets.txt --namespace=isecl

  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  # wait to get ready
  echo "Wait for pods to initialize..."
  POD_NAME=`$KUBECTL get pod -l app=kbs -n isecl -o name`
  $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
  if [ $? == 0 ]; then
    echo "KBS DEPLOYED SUCCESSFULLY"
  else
    echo "Error: Deploying KBS"
    echo "Exiting with error..."
    exit 1
  fi
  cd $HOME_DIR

}

deploy_wls() {
    #WLS
    echo "----------------------------------------------------"
    echo "|            DEPLOY:WORKLOAD-SERVICE           |"
    echo "----------------------------------------------------"

    cd wls/

    required_variables="WLS_SERVICE_USERNAME,WLS_SERVICE_PASSWORD,WLS_CERT_SAN_LIST,AAS_API_URL,HVS_URL,CMS_BASE_URL"
    check_mandatory_variables $WLS $required_variables

    # The variables bearer_token and cms_tls_digest get loaded with below functions, this required if we want to deploy individual wls service
    get_bearer_token
    get_cms_tls_cert_sha384

    # update wls configMap & secrets
    sed -i "s/BEARER_TOKEN=.*/BEARER_TOKEN=${BEARER_TOKEN}/g" secrets.txt
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: ${CMS_TLS_CERT_SHA384}/g" configMap.yml
    sed -i "s#AAS_API_URL:.*#AAS_API_URL: $AAS_API_URL#g" configMap.yml
    sed -i "s#HVS_URL:.*#HVS_URL: $HVS_URL#g" configMap.yml
    sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: $CMS_BASE_URL#g" configMap.yml
    sed -i "s/SAN_LIST:.*/SAN_LIST: $WLS_CERT_SAN_LIST/g" configMap.yml
    sed -i "s/WLS_SERVICE_USERNAME=.*/WLS_SERVICE_USERNAME=${WLS_SERVICE_USERNAME}/g" secrets.txt
    sed -i "s/WLS_SERVICE_PASSWORD=.*/WLS_SERVICE_PASSWORD=${WLS_SERVICE_PASSWORD}/g" secrets.txt
    sed -i "s/WLS_DB_USERNAME=.*/WLS_DB_USERNAME=${WLS_DB_USERNAME}/g" secrets.txt
    sed -i "s/WLS_DB_PASSWORD=.*/WLS_DB_PASSWORD=${WLS_DB_PASSWORD}/g" secrets.txt

    $KUBECTL create secret generic wls-secret --from-file=secrets.txt --namespace=isecl

    # deploy
    $KUBECTL kustomize . | $KUBECTL apply -f -

    # wait to get ready
    echo "Wait for pods to initialize..."
    POD_NAME=`$KUBECTL get pod -l app=wls -n isecl -o name`
    $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
    if [ $? == 0 ]; then
        echo "WORKLOAD-SERVICE DEPLOYED SUCCESSFULLY"
    else
        echo "Error: Deploying WLS"
        echo "Exiting with error..."
        exit 1
    fi
    cd $HOME_DIR
}

deploy_tagent() {

    # get latest bearer_token and cms tls cert digest
    get_bearer_token
    get_cms_tls_cert_sha384

    required_variables="GRUB_FILE,TPM_OWNER_SECRET,TA_CERT_SAN_LIST,AAS_API_URL,HVS_URL,CMS_BASE_URL"
    check_mandatory_variables $TAGENT $required_variables

    cd ta/
    # #update trustagent.env
    sed -i "s#GRUB_FILE:.*#GRUB_FILE: $GRUB_FILE#g" configMap.yml
    sed -i "s#AAS_API_URL:.*#AAS_API_URL: $AAS_API_URL#g" configMap.yml
    sed -i "s#HVS_URL:.*#HVS_URL: $HVS_URL#g" configMap.yml
    sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: $CMS_BASE_URL#g" configMap.yml
    sed -i "s#CMS_TLS_CERT_SHA384:.*#CMS_TLS_CERT_SHA384: $CMS_TLS_CERT_SHA384#g" configMap.yml
    sed -i "s/BEARER_TOKEN=.*/BEARER_TOKEN=$BEARER_TOKEN/g" secrets.txt
    sed -i "s/TPM_OWNER_SECRET=.*/TPM_OWNER_SECRET=$TPM_OWNER_SECRET/g" secrets.txt

    $KUBECTL create secret generic ta-secret --from-file=secrets.txt --namespace=isecl

    $KUBECTL kustomize . | $KUBECTL apply -f -
    # wait to get ready
    echo "Wait for ta daemonsets to initialize..."
    sleep 120
    cd $HOME_DIR

}

deploy_wlagent(){

    # get latest bearer_token and cms tls cert digest
    get_bearer_token
    get_cms_tls_cert_sha384

    required_variables="WLA_SERVICE_USERNAME,WLA_SERVICE_PASSWORD,AAS_API_URL,HVS_URL,CMS_BASE_URL"
    check_mandatory_variables $WLAGENT $required_variables
    cd wla/
    # #update trustagent.env
    sed -i "s/BEARER_TOKEN=.*/BEARER_TOKEN=$BEARER_TOKEN/g" secrets.txt
    sed -i "s#AAS_API_URL:.*#AAS_API_URL: $AAS_API_URL#g" configMap.yml
    sed -i "s#HVS_URL:.*#HVS_URL: $HVS_URL#g" configMap.yml
    sed -i "s#CMS_BASE_URL:.*#CMS_BASE_URL: $CMS_BASE_URL#g" configMap.yml
    sed -i "s/CMS_TLS_CERT_SHA384:.*/CMS_TLS_CERT_SHA384: $CMS_TLS_CERT_SHA384/g" configMap.yml
    sed -i "s/WLA_SERVICE_USERNAME=.*/WLA_SERVICE_USERNAME=$WLA_SERVICE_USERNAME/g" secrets.txt
    sed -i "s/WLA_SERVICE_PASSWORD=.*/WLA_SERVICE_PASSWORD=$WLA_SERVICE_PASSWORD/g" secrets.txt

    $KUBECTL create secret generic wla-secret --from-file=secrets.txt --namespace=isecl

    $KUBECTL kustomize . | $KUBECTL apply -f -
    # wait to get ready
    echo "Wait for daemonset to initialize..."
    sleep 20
    $KUBECTL get pod -n isecl -l app=wla | grep Running
    if [ $? == 0 ]; then
        echo "WLA DAEMONSET DEPLOYED SUCCESSFULLY"
    else
        echo "Error: Deploying WLA"
        echo "Exiting with error..."
        exit 1
    fi
    cd $HOME_DIR

}

cleanup_wls() {

    echo "Cleaning up WORKLOAD-SERVICE..."


    $KUBECTL delete secret wls-secret --namespace isecl
    $KUBECTL delete configmap wls-config  --namespace isecl
    $KUBECTL delete deploy wls-deployment --namespace isecl

    if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
      $KUBECTL delete pvc wls-config-pvc --namespace isecl
      $KUBECTL delete pvc wls-logs-pvc --namespace isecl
      $KUBECTL delete pv wls-config-pv --namespace isecl
      $KUBECTL delete pv wls-logs-pv --namespace isecl

    fi

}

cleanup_tagent(){
  $KUBECTL delete configmap ta-config  --namespace isecl
  $KUBECTL delete secret ta-secret  --namespace isecl
  $KUBECTL delete daemonset ta-daemonset-txt --namespace isecl
  $KUBECTL delete daemonset ta-daemonset-suefi --namespace isecl
}

cleanup_wlagent(){
  $KUBECTL delete configmap wla-config  --namespace isecl
  $KUBECTL delete secret wla-secret  --namespace isecl
  $KUBECTL delete daemonset wla-daemonset --namespace isecl
}

cleanup_kbs() {

  echo "Cleaning up KBS..."

  $KUBECTL delete secret kbs-secret --namespace isecl
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
}

cleanup_ihub() {

  echo "Cleaning up INTEGRATION-HUB..."

  $KUBECTL delete secret ihub-secret --namespace isecl
  $KUBECTL delete configmap ihub-config --namespace isecl
  $KUBECTL delete deploy ihub-deployment --namespace isecl

  if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    $KUBECTL delete pvc ihub-config-pvc --namespace isecl
    $KUBECTL delete pvc ihub-logs-pvc --namespace isecl
    $KUBECTL delete pv ihub-config-pv --namespace isecl
    $KUBECTL delete pv ihub-logs-pv --namespace isecl
  fi
}

cleanup_isecl_controller() {

  $KUBECTL delete deploy isecl-controller-deployment --namespace isecl
  $KUBECTL delete crd hostattributes.crd.isecl.intel.com --namespace isecl
  $KUBECTL delete clusterrole isecl-controller --namespace isecl
  $KUBECTL delete clusterrolebinding isecl-controller-binding --namespace isecl
  $KUBECTL delete clusterrolebinding isecl-clusterrole --namespace isecl

}

cleanup_isecl_scheduler() {

  cd k8s-extensions-scheduler/

  $KUBECTL delete deploy isecl-scheduler-deployment --namespace isecl
  $KUBECTL delete svc isecl-scheduler-svc --namespace isecl
  $KUBECTL delete secret scheduler-certs --namespace isecl
  rm -rf secrets

  cd $HOME_DIR
}

cleanup_hvs() {

  echo "Cleaning up HOST-VERIFICATION-SERVICE..."

  $KUBECTL delete secret hvs-secret --namespace isecl

  $KUBECTL delete configmap hvs-config --namespace isecl
  $KUBECTL delete deploy hvs-deployment --namespace isecl
  $KUBECTL delete svc hvs-svc --namespace isecl

  if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    $KUBECTL delete pvc hvs-config-pvc --namespace isecl
    $KUBECTL delete pvc hvs-logs-pvc --namespace isecl
    $KUBECTL delete pv hvs-config-pv --namespace isecl
    $KUBECTL delete pv hvs-logs-pv --namespace isecl
  fi

  echo $(pwd)
}

cleanup_authservice() {

  echo "Cleaning up AUTHENTICATION-AUTHORIZATION-SERVICE..."

  $KUBECTL delete secret aas-secret --namespace isecl
  $KUBECTL delete configmap aas-config --namespace isecl
  $KUBECTL delete deploy aas-deployment --namespace isecl
  $KUBECTL delete svc aas-svc --namespace isecl

  if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    $KUBECTL delete pvc aas-config-pvc --namespace isecl
    $KUBECTL delete pvc aas-logs-pvc --namespace isecl
    $KUBECTL delete pv aas-config-pv --namespace isecl
    $KUBECTL delete pv aas-logs-pv --namespace isecl
  fi

}

cleanup_cms() {

  echo "Cleaning up CERTIIFCATION-MANAGEMENT-SERVICE..."

  $KUBECTL delete configmap cms-config --namespace isecl
  $KUBECTL delete deploy cms-deployment --namespace isecl
  $KUBECTL delete svc cms-svc --namespace isecl

  if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    $KUBECTL delete pvc cms-config-pvc --namespace isecl
    $KUBECTL delete pvc cms-logs-pvc --namespace isecl
    $KUBECTL delete pv cms-config-pv --namespace isecl
    $KUBECTL delete pv cms-logs-pv --namespace isecl
  fi
  echo $(pwd)
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
  get_aas_bootstrap_token
  deploy_authservice
  get_bearer_token
  deploy_hvs
  deploy_custom_controller
  deploy_ihub
  deploy_wls
  deploy_kbs
  deploy_tagent
  deploy_wlagent

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

  cleanup_kbs
  cleanup_wlagent
  cleanup_tagent
  cleanup_ihub
  cleanup_wls
  cleanup_isecl_scheduler
  cleanup_isecl_controller
  cleanup_hvs
  cleanup_authservice
  cleanup_cms
  if [ $? == 0 ]; then
    echo "Wait for pods to terminate..."
    sleep 30
  fi

}

purge() {
  echo "Cleaning up logs from /var/log/"
  rm -rf /var/log/cms/ /var/log/authservice /var/log/workload-service /var/log/hvs /var/log/ihub /var/log/trustagent /var/log/workload-agent /var/log/kbs
  echo "Cleaning up config from /etc/"
  rm -rf /etc/cms /etc/authservice /etc/workload-service /etc/hvs /etc/ihub /opt/trustagent /etc/workload-agent /etc/kbs
}

#Help section
print_help() {
  echo "Usage: $0 [-help/up/down/purge]"
  echo "    -help                                     Print help and exit"
  echo "    up   [all/<agent>/<service>/<usecase>]    Bootstrap ISecL K8s environment for specified agent/service/usecase"
  echo "    down [all/<agent>/<service>/<usecase>]    Delete ISecL K8s environment for specified agent/service/usecase [will not delete data, config, logs]"
  echo "    purge                                     Delete ISecL K8s environment with data, config, logs [only supported for single node deployments]"
  echo ""
  echo "    Available Options for up/down command:"
  echo "        agent      Can be one of tagent, wlagent"
  echo "        service    Can be one of cms, authservice, hvs, ihub, wls, kbs, isecl-controller, isecl-scheduler"
  echo "        usecase    Can be one of foundation-security, workload-security, isecl-orchestration-k8s"
}

deploy_common_components() {
  deploy_cms
  deploy_authservice
  deploy_hvs
  deploy_tagent
}

cleanup_common_components() {
  cleanup_cms
  cleanup_authservice
  cleanup_hvs
  cleanup_tagent
}

#Dispatch works based on args to script
dispatch_works() {

  case $1 in
  "up")
    check_k8s_distribution
    case $2 in
    "cms")
      deploy_cms
      ;;
    "authservice")
      deploy_authservice
      ;;
    "wls")
      deploy_wls
      ;;
    "hvs")
      deploy_hvs
      ;;
    "ihub")
      deploy_ihub
      ;;
    "tagent")
      deploy_tagent
      ;;
    "kbs")
      deploy_kbs
      ;;
    "isecl-controller")
      deploy_custom_controller
      ;;
    "isecl-scheduler")
      deploy_extended_scheduler
      ;;
    "wlagent")
      deploy_wlagent
      ;;
    "foundational_security")
      deploy_common_components
      ;;
    "workload-security")
      deploy_common_components
      deploy_wls
      deploy_kbs
      deploy_wlagent
      ;;
    "isecl-orchestration-k8s")
      deploy_common_components
      deploy_custom_controller
      deploy_ihub
      if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
        deploy_extended_scheduler
      fi
      ;;
    "all")
      bootstrap
      ;;
    *)
      print_help
      exit 1
      ;;
    esac
    ;;

  "down")
    check_k8s_distribution
    case $2 in
    "cms")
      cleanup_cms
      ;;
    "authservice")
      cleanup_authservice
      ;;
    "wls")
      cleanup_wls
      ;;
    "hvs")
      cleanup_hvs
      ;;
    "ihub")
      cleanup_ihub
      ;;
    "isecl-controller")
      cleanup_isecl_controller
      ;;
    "isecl-scheduler")
      cleanup_isecl_scheduler
      ;;
    "tagent")
      cleanup_tagent
      ;;
     "kbs")
      cleanup_kbs
      ;;
    "wlagent")
      cleanup_wlagent
      ;;
    "foundational_security")
      cleanup_common_components
       ;;
    "isecl-orchestration-k8s")
      cleanup_common_components
      cleanup_ihub
      cleanup_isecl_controller
      cleanup_isecl_scheduler
      ;;
    "workload-security")
      cleanup_common_components
      cleanup_kbs
      cleanup_wlagent
      cleanup_wls
      ;;
    "all")
      cleanup
      ;;

    *)
      print_help
      exit 1
      ;;
    esac
    ;;
  "purge")
    if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
      KUBECTL=microk8s.kubectl
      cleanup
      purge
      if [ $? -ne 0 ]; then exit 1; fi
    else
      echo "purge command not supported for this K8s distribution"
      exit 1
    fi
    ;;
  "-help")
    print_help
    ;;
  *)
    echo "Invalid Command"
    print_help
    exit 1
    ;;
  esac
}

if [ $# -eq 0 ]; then
  print_help
  exit 1
fi

# run commands
dispatch_works $*


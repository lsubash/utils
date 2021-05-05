#!/bin/bash

source isecl-skc-k8s.env
if [ $? != 0 ]; then
  echo "failed to source isecl-skc-k8s.env"
fi

check_k8s_distribution() {
  if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
    KUBECTL=microk8s.kubectl
  elif [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    KUBECTL=kubectl
  else
    echo "K8s Distribution" $K8S_DISTRIBUTION "not supported"
  fi
}

HOME_DIR=$(pwd)

K8S_DISTRIBUTION=${K8S_DISTRIBUTION:-"microk8s"}
# Setting default KUBECTl command as kubectl
KUBECTL=${KUBECTL:-"microk8s.kubectl"}

deploy_authservice_db() {

  echo "-----------------------------------------------------------------------"
  echo "|    DEPLOY:AUTHENTICATION-AUTHORIZATION-SERVICE DATABASE INSTANCE    |"
  echo "-----------------------------------------------------------------------"

  cd aas-db/
  mkdir -p secrets

  if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
    # set user:group for pgdata directory
    mkdir -p /usr/local/kube/data/authservice/pgdata
    chmod 700 /usr/local/kube/data/authservice/pgdata
    chown -R 2000:2000 /usr/local/kube/data/authservice/pgdata
  fi

  # generate server.crt,server.key
  openssl req -new -x509 -days 365 -newkey rsa:4096 -addext "subjectAltName = DNS:$AAS_DB_HOSTNAME" -nodes -text -out secrets/server.crt -keyout secrets/server.key -sha384 -subj "/CN=ISecl Self Sign Cert"

  $KUBECTL create secret generic aas-db-certs -n isecl --from-file=server.crt=secrets/server.crt --from-file=server.key=secrets/server.key
  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  # wait to get ready
  echo "Wait for pods to initialize..."
  POD_NAME=$($KUBECTL get pod -l app=aasdb -n isecl -o name)
  $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
  if [ $? == 0 ]; then
    echo "AUTHENTICATION-AUTHORIZATION-SERVICE DATABASE DEPLOYED SUCCESSFULLY"
  else
    echo "ERROR: Failed to deploy AAS Database Pod"
    echo "Exiting with error..."
    exit 1
  fi

  cd $HOME_DIR
}

deploy_scs_db() {

  echo "---------------------------------------------------------------------"
  echo "|            DEPLOY:SGX CACHING SERVICE DATABASE INSTANCE            |"
  echo "----------------------------------------------------------------------"

  cd scs-db/
  mkdir -p secrets

  if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
    # set user:group for pgdata directory
    mkdir -p /usr/local/kube/data/sgx-caching-service/pgdata/
    chmod 700 /usr/local/kube/data/sgx-caching-service/pgdata
    chown -R 2000:2000 /usr/local/kube/data/sgx-caching-service/pgdata
  fi

  # generate server.crt,server.key
  openssl req -new -x509 -days 365 -newkey rsa:4096 -addext "subjectAltName = DNS:$SCS_DB_HOSTNAME" -nodes -text -out secrets/server.crt -keyout secrets/server.key -sha384 -subj "/CN=ISecl Self Sign Cert"

  $KUBECTL create secret generic scs-db-certs -n isecl --from-file=server.crt=secrets/server.crt --from-file=server.key=secrets/server.key
  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  # wait to get ready
  echo "Wait for pods to initialize..."
  POD_NAME=$($KUBECTL get pod -l app=scsdb -n isecl -o name)
  $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
  if [ $? == 0 ]; then
    echo "SGX CACHING SERVICE DATABASE DEPLOYED SUCCESSFULLY"
  else
    echo "Error: Deploying SCS DB Pod"
    echo "Exiting with error..."
    exit 1
  fi
  cd ../
}

deploy_shvs_db() {

  echo "-------------------------------------------------------------"
  echo "|            DEPLOY:SGX HOST VERIFICATION SERVICE            |"
  echo "-------------------------------------------------------------"

  cd shvs-db/
  mkdir -p secrets
  if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
    # set user:group for pgdata directory
    mkdir -p /usr/local/kube/data/sgx-host-verification-service/pgdata/
    chmod 700 /usr/local/kube/data/sgx-host-verification-service/pgdata
    chown -R 2000:2000 /usr/local/kube/data/sgx-host-verification-service/pgdata
  fi

  # generate server.crt,server.key
  openssl req -new -x509 -days 365 -newkey rsa:4096 -addext "subjectAltName = DNS:$SHVS_DB_HOSTNAME" -nodes -text -out secrets/server.crt -keyout secrets/server.key -sha384 -subj "/CN=ISecl Self Sign Cert"
  $KUBECTL create secret generic shvs-db-certs -n isecl --from-file=server.crt=secrets/server.crt --from-file=server.key=secrets/server.key
  # deploy
  $KUBECTL kustomize . | $KUBECTL apply -f -

  # wait to get ready
  echo "Wait for pods to initialize..."
  POD_NAME=$($KUBECTL get pod -l app=shvsdb -n isecl -o name)
  $KUBECTL wait --for=condition=Ready $POD_NAME -n isecl --timeout=60s
  if [ $? == 0 ]; then
    echo "SGX-HOST-VERIFICATION-SERVICE DATABASE DEPLOYED SUCCESSFULLY"
  else
    echo "Error: Deploying SHVS Database Pod"
    echo "Exiting with error..."
    exit 1
  fi
  cd ../
}

cleanup_shvs_db() {

  echo "Cleaning up SGX-HOST-VERIFICATION-SERVICE Database"

  cd shvs-db/

  $KUBECTL delete secret shvs-db-credentials shvs-db-certs --namespace isecl

  $KUBECTL delete configmap shvs-db-config --namespace isecl
  $KUBECTL delete deploy shvsdb-deployment --namespace isecl
  $KUBECTL delete svc shvsdb-svc --namespace isecl

  if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    $KUBECTL delete pvc shvs-db-pvc --namespace isecl
    $KUBECTL delete pv shvs-db-pv --namespace isecl
  fi

  rm -rf secrets/server.crt
  rm -rf secrets/server.key

  cd ../

  echo $(pwd)
}

cleanup_scs_db() {

  echo "Cleaning up SGX CACHING SERVICE..."

  cd scs-db/

  $KUBECTL delete secret scs-db-credentials scs-db-certs --namespace isecl
  $KUBECTL delete configmap scs-db-config --namespace isecl
  $KUBECTL delete deploy scsdb-deployment --namespace isecl
  $KUBECTL delete svc scsdb-svc --namespace isecl

  rm -rf secrets/server.crt
  rm -rf secrets/server.key

  if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    $KUBECTL delete pvc scs-db-pvc --namespace isecl
    $KUBECTL delete pv scs-db-pv --namespace isecl
  fi

  cd ../

  echo $(pwd)
}

cleanup_authservice_db() {

  echo "Cleaning up AUTHENTICATION-AUTHORIZATION-SERVICE..."

  cd aas-db/

  $KUBECTL delete secret aas-db-credentials aas-db-certs --namespace isecl
  $KUBECTL delete configmap aas-db-config --namespace isecl
  $KUBECTL delete deploy aasdb-deployment --namespace isecl
  $KUBECTL delete svc aasdb-svc --namespace isecl

  rm -rf secrets/server.crt
  rm -rf secrets/server.key

  if [ "$K8S_DISTRIBUTION" == "kubeadm" ]; then
    $KUBECTL delete pvc aas-db-pvc --namespace isecl
    $KUBECTL delete pv aas-db-pv --namespace isecl
  fi

  cd ../..

}

bootstrap() {

  echo "Kubenertes-> "
  check_k8s_distribution

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

  echo "OpenSSL->"
  openssl version
  if [ $? != 0 ]; then
    echo "OpenSSL is not installed. Cannot create certificates needed for SSL connection to DB"
    echo "Exiting with Error.."
    exit 1
  fi

  echo "-------------------------------------------------------------------------------------------------------------"
  echo "|     DEPLOY: Database SERVICES For Authservice, SGX Caching Service and SGX Host Verification Services     |"
  echo "-------------------------------------------------------------------------------------------------------------"
  echo ""

  deploy_authservice_db
  deploy_scs_db
  deploy_shvs_db

  cd ../

}

# #Function to cleanup Intel Micro SecL on Micro K8s
cleanup() {

  echo "----------------------------------------------------"
  echo "|                    CLEANUP                       |"
  echo "----------------------------------------------------"

  check_k8s_distribution
  cleanup_shvs_db
  cleanup_scs_db
  cleanup_authservice_db
  if [ $? == 0 ]; then
    echo "Wait for pods to terminate..."
    sleep 30
  fi

  if [ "$K8S_DISTRIBUTION" == "microk8s" ]; then
    purge
  fi

}

purge() {
  echo "Cleaning up data from /usr/local/kube/data/"
  rm -rf /usr/local/kube/data/authservice /usr/local/kube/data/sgx-host-verification-service /usr/local/kube/data/sgx-caching-service
}

#Help section
print_help() {
  echo "Usage: $0 [-help/up/purge]"
  echo "    -help          print help and exit"
  echo "    up        Bootstrap Database Services for Authservice, SGX Caching Service and SGX Host verification Service"
  echo "    purge     Delete Database Services for Authservice, SGX Caching Service and SGX Host verification Service"
}

#Dispatch works based on args to script
dispatch_works() {

  case $1 in
  "up")
    bootstrap
    ;;
  "purge")
    cleanup
    ;;
  *)
    print_help
    exit 1
    ;;

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
  d) work_list+="purge" ;;
  *)
    print_help
    exit 1
    ;;
  esac
done

# run commands
dispatch_works $*

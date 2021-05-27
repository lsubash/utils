#!/bin/bash

NATS_CERT_COMMON_NAME=${NATS_CERT_COMMON_NAME:-"NATS TLS Certificate"}
sed -i "s#DNS.1=.*#DNS.1=$HOSTNAME/" opensslSAN.conf

echo "Creating certificate request..."
CSR_FILE=sslcert.csr
openssl req -out $CSR_FILE -newkey rsa:3072 -nodes -keyout secrets/server.key -config opensslSAN.conf -subj "/CN=$NATS_CERT_COMMON_NAME" -sha384
echo "Downloading TLS Cert from CMS...."
curl --noproxy "*" -k -X POST https://$CMS_BASE_URL/certificates?certType=TLS -H 'Accept: application/x-pem-file' -H "Authorization: Bearer $BEARER_TOKEN" -H 'Content-Type: application/x-pem-file' --data-binary "@$CSR_FILE" > secrets/server.pem
#!/bin/bash

source nats-tls-download.env
NATS_CERT_COMMON_NAME=${NATS_CERT_COMMON_NAME:-"NATS TLS Certificate"}
sed -i "s/^\(IP\.1\s*=\s*\).*\$/\1$SAN_IP/" opensslSAN.conf
sed -i "s#DNS.1=.*#DNS.1=$SAN_DNS/" opensslSAN.conf

echo "Creating certificate request..."
CSR_FILE=sslcert.csr
openssl req -out $CSR_FILE -newkey rsa:3072 -nodes -keyout tls.key -config opensslSAN.conf -subj "/CN=$NATS_CERT_COMMON_NAME" -sha384
echo "Downloading TLS Cert from CMS...."
curl --noproxy "*" -k -X POST https://$CMS_IP:$CMS_PORT/cms/v1/certificates?certType=TLS -H 'Accept: application/x-pem-file' -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/x-pem-file' --data-binary "@$CSR_FILE" > tls-cert.pem
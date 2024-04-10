#!/bin/bash

# Lifted and tweaked from https://www.golinuxcloud.com/shell-script-to-generate-certificate-openssl/#Sample_shell_script_to_generate_RootCA_and_server_certificate

OUTPUT_PATH="./certs"

DO_CLEAN="no"
COMMON_NAME=""

while getopts ":con:" opt; do
    case ${opt} in
        c )
          DO_CLEAN="yes"
          ;;
        o )
          OUTPUT_PATH=$OPTARG
          ;;
        n )
          COMMON_NAME=$OPTARG
          ;;
        \? )
          echo "Invalid option: $OPTARG"
          ;;
    esac
done

CA_CERT_CONF="./openssl-conf/ca_cert.cnf"
SERVER_CERT_CONF="./openssl-conf/server_cert.cnf"
SERVER_CERT_EXT_CONF_TEMPLATE="./openssl-conf/server_ext.cnf"

SERVER_CERT_EXT_CONF="$OUTPUT_PATH/server_ext.cnf" # this file will be created from $SERVER_CERT_EXT_CONF_TEMPLATE
SERVER_KEY="$OUTPUT_PATH/server.key"
SERVER_CSR="$OUTPUT_PATH/server.csr"
SERVER_CRT="$OUTPUT_PATH/server.crt"
CA_KEY="$OUTPUT_PATH/ca.key"
CA_CRT="$OUTPUT_PATH/cacert.pem"

if [[ "$DO_CLEAN" == "yes" ]]; then
    echo "Cleaning up the certs directory"
    rm -rf "$SERVER_CERT_EXT_CONF" "$SERVER_KEY" "$SERVER_CSR" "$SERVER_CRT" "$CA_KEY" "$CA_CRT"
fi
if [[ -z $COMMON_NAME ]]; then
    echo "ERROR: Common Name is required (-n)"
    exit 1
fi

mkdir -p "$OUTPUT_PATH"
cat $SERVER_CERT_EXT_CONF_TEMPLATE > "$SERVER_CERT_EXT_CONF"
echo "DNS.1 = $COMMON_NAME" >> "$SERVER_CERT_EXT_CONF"

function generate_root_ca {

    ## generate rootCA private key
    echo -e "\nGenerating RootCA private key"
    if [[ ! -f $CA_KEY ]];then
       openssl genrsa -out "$CA_KEY" 4096
       [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $CA_KEY" && exit 1
    elif [ -f "$CA_CRT" ]; then        
       echo -e "\n$CA_KEY seems to be already generated, skipping the generation of RootCA certificate"
       return 0
    fi

    ## generate rootCA certificate
    echo -e "\nGenerating RootCA certificate"
    openssl req -new -x509 -days 3650 -config "$CA_CERT_CONF" -key "$CA_KEY" -out "$CA_CRT"
    [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $CA_CRT" && exit 1

    ## read the certificate
    echo -e "\nVerify RootCA certificate"
    openssl  x509 -noout -text -in "$CA_CRT"
    [[ $? -ne 0 ]] && echo "ERROR: Failed to read $CA_CRT" && exit 1
}

function generate_server_certificate {

    echo -e "\nGenerating server private key"
    openssl genrsa -out "$SERVER_KEY" 4096
    [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $SERVER_KEY" && exit 1

    echo -e "\nGenerating certificate signing request for server"
    openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$SERVER_CERT_CONF" -subj "/CN=$COMMON_NAME"
    [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $SERVER_CSR" && exit 1

    echo -e "\nGenerating RootCA signed server certificate"
    openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -out "$SERVER_CRT" -CAcreateserial -days 365 -sha512 -extfile "$SERVER_CERT_EXT_CONF"
    [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $SERVER_CRT" && exit 1

    echo -e "\nVerifying the server certificate against RootCA"
    openssl verify -CAfile "$CA_CRT" "$SERVER_CRT"
     [[ $? -ne 0 ]] && echo "ERROR: Failed to verify $SERVER_CRT against $CA_CRT" && exit 1

}

# MAIN
generate_root_ca
generate_server_certificate
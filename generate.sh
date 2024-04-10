#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m' # No Color

function greenEcho() {
  echo -e "${GREEN}$1${NC}" >&2
}

# Lifted and tweaked from https://www.golinuxcloud.com/shell-script-to-generate-certificate-openssl/#Sample_shell_script_to_generate_RootCA_and_server_certificate

OUTPUT_PATH="./certs"

DO_CLEAN="no"
COMMON_NAME=""
JAVA_STORES="no"
PASSWORD="password"

while getopts "cjn:o:" opt; do
    case "${opt}" in
        c)
          DO_CLEAN="yes"
          ;;
        j)
          JAVA_STORES="yes"
          ;;
        n)
          COMMON_NAME="${OPTARG}"
          ;;
        o)
          OUTPUT_PATH="${OPTARG}"
          greenEcho "Output path: $OUTPUT_PATH"
          ;;
        \?)
          echo "Invalid option: $OPTARG"
          ;;
       :)
          echo "Option -$OPTARG requires an argument" 1>&2
          usage
          ;;
    esac
done
shift $((OPTIND -1))

CA_CERT_CONF="./openssl-conf/ca_cert.cnf"
SERVER_CERT_CONF="./openssl-conf/server_cert.cnf"
SERVER_CERT_EXT_CONF_TEMPLATE="./openssl-conf/server_ext_template.cnf"

SERVER_CERT_EXT_CONF="$OUTPUT_PATH/server_ext.cnf" # this file will be created from $SERVER_CERT_EXT_CONF_TEMPLATE
SERVER_KEY="$OUTPUT_PATH/server.key"
SERVER_CSR="$OUTPUT_PATH/server.csr"
SERVER_CRT="$OUTPUT_PATH/server.crt"
CA_KEY="$OUTPUT_PATH/ca.key"
CA_CRT="$OUTPUT_PATH/cacert.pem"

JAVA_OUTPUT_PATH="$OUTPUT_PATH/java"
KEYSTORE_P12_FILE="$JAVA_OUTPUT_PATH/keystore.p12"
KEYSTORE_JKS_FILE="$JAVA_OUTPUT_PATH/keystore.jks"
TRUSTSTORE_FILE="$JAVA_OUTPUT_PATH/truststore.jks"
CA_DER_FILE="$JAVA_OUTPUT_PATH/ca.der"

if [[ "$DO_CLEAN" == "yes" ]]; then
    greenEcho "Cleaning the certs directory"
    rm -rf "$SERVER_CERT_EXT_CONF" "$SERVER_KEY" "$SERVER_CSR" "$SERVER_CRT" "$CA_KEY" "$CA_CRT" "$JAVA_OUTPUT_PATH"
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
  greenEcho "\nGenerating RootCA private key"
  if [[ ! -f $CA_KEY ]];then
     openssl genrsa -out "$CA_KEY" 4096
     [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $CA_KEY" && exit 1
  elif [ -f "$CA_CRT" ]; then        
     greenEcho "\n$CA_KEY seems to be already generated, skipping the generation of RootCA certificate"
     return 0
  fi
  
  ## generate rootCA certificate
  greenEcho "\nGenerating RootCA certificate"
  openssl req -new -x509 -days 3650 -config "$CA_CERT_CONF" -key "$CA_KEY" -out "$CA_CRT"
  [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $CA_CRT" && exit 1
  
  ## read the certificate
  greenEcho "\nVerify RootCA certificate"
  openssl  x509 -noout -text -in "$CA_CRT"
  [[ $? -ne 0 ]] && echo "ERROR: Failed to read $CA_CRT" && exit 1
}

function generate_server_certificate {  
  greenEcho "\nGenerating server private key"
  openssl genrsa -out "$SERVER_KEY" 4096
  [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $SERVER_KEY" && exit 1
  
  greenEcho "\nGenerating certificate signing request for server"
  openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$SERVER_CERT_CONF" -subj "/CN=$COMMON_NAME"
  [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $SERVER_CSR" && exit 1
  
  greenEcho "\nGenerating RootCA signed server certificate"
  openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -out "$SERVER_CRT" -CAcreateserial -days 365 -sha512 -extfile "$SERVER_CERT_EXT_CONF"
  [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $SERVER_CRT" && exit 1
  
  greenEcho "\nVerifying the server certificate against RootCA"
  openssl verify -CAfile "$CA_CRT" "$SERVER_CRT"
   [[ $? -ne 0 ]] && echo "ERROR: Failed to verify $SERVER_CRT against $CA_CRT" && exit 1
}

function generate_java_stores() {
  if [[ "$JAVA_STORES" != "yes" ]]; then
    greenEcho "\nSkipping Java store generation. -j flag is not set"
    return 0
  fi
  
  mkdir -p "$JAVA_OUTPUT_PATH"
  
  greenEcho "\nCreate a new Java keystore and import the key and certificate"
  openssl pkcs12 -export -in "$SERVER_CRT" -inkey "$SERVER_KEY" -out "$KEYSTORE_P12_FILE" -name "certificate" -passin pass:$PASSWORD -passout pass:$PASSWORD -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
  keytool -importkeystore \
      -srcstorepass "$PASSWORD" \
      -srckeypass "$PASSWORD" \
      -srckeystore "$KEYSTORE_P12_FILE" \
      -destkeystore "$KEYSTORE_JKS_FILE" \
      -srcstoretype PKCS12 \
      -deststoretype JKS \
      -srcalias "certificate" \
      -deststorepass "$PASSWORD" \
      -destkeypass "$PASSWORD" \
      -noprompt
  
  greenEcho "\nCreate a new Java truststore and import the CA certificate"
  openssl x509 -in "$CA_CRT" -outform der -out "$CA_DER_FILE"
  keytool -importcert -file "$CA_DER_FILE" -keystore "$TRUSTSTORE_FILE" -storepass "$PASSWORD" -noprompt
  keytool -importcert \
      -file "$CA_DER_FILE" \
      -keystore "$TRUSTSTORE_FILE" \
      -storepass "$PASSWORD" \
      -keypass "$PASSWORD" \
      -alias "certificate" \
      -noprompt
}

# MAIN
generate_root_ca
generate_server_certificate
generate_java_stores
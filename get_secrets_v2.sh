#!/bin/sh
set -euoxv

# Set the Kubernetes namespace, secret name and your Google Cloud Project ID and <appname> #Secret Manager Secret ID
# SECRET_ID="$4"
NAMESPACE="$1"
SECRET_NAME="$2"
PROJECT_ID="$3"
APP_NAME="$4"

# Get the Kubernetes secret data
SECRET_DATA=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o json | jq -r '.data')

# Decode the base64-encoded data
SECRET_VALUES=$(echo "${SECRET_DATA}" | jq -r 'to_entries | map("\(.key)=\(.value | @base64d)") | .[]')

# Flag to check if all keys from Kubernetes secret exist
ALL_KEYS_EXIST=true

# Check if all keys from the secret already exist in Google Cloud Secret Manager
IFS=$'\n'
for ENTRY in ${SECRET_VALUES}; do
  KEY=$(echo "${ENTRY}" | cut -d'=' -f1 | tr '[:upper:]' '[:lower:]')

  # Check if the key exists
  if ! gcloud secrets describe ${APP_NAME}-${KEY} --project=${PROJECT_ID} &>/dev/null; then
    ALL_KEYS_EXIST=false
    break
  fi
done

unset IFS

if ${ALL_KEYS_EXIST}; then
  echo "All keys from the secret already exist in Google Cloud Secret Manager. Updating versions..."

  # Update the existing secret with new versions
  IFS=$'\n'
  for ENTRY in ${SECRET_VALUES}; do
    KEY=$(echo "${ENTRY}" | cut -d'=' -f1 | tr '[:upper:]' '[:lower:]')
    VALUE=$(echo "${ENTRY}" | cut -d'=' -f2)

    gcloud secrets versions add ${APP_NAME}-${KEY} --data-file=- --project=${PROJECT_ID} <<EOF
${VALUE}
EOF

    echo "Updated ${KEY} in Google Cloud Secret Manager"
  done

  unset IFS
else
  echo "Some or all keys from the secret do not exist. Creating and adding values..."

  # Create the secret in Google Cloud Secret Manager
  IFS=$'\n'
  for ENTRY in ${SECRET_VALUES}; do
    KEY=$(echo "${ENTRY}" | cut -d'=' -f1 | tr '[:upper:]' '[:lower:]')
    VALUE=$(echo "${ENTRY}" | cut -d'=' -f2)

    gcloud secrets create ${APP_NAME}-${KEY} --data-file=- --project=${PROJECT_ID} <<EOF
${VALUE}
EOF

    echo "Added ${KEY} to Google Cloud Secret Manager"
  done

  unset IFS
fi

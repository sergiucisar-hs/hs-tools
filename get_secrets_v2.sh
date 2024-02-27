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

# Iterate through each key in the Kubernetes secret
IFS=$'\n'
for ENTRY in ${SECRET_VALUES}; do
  KEY=$(echo "${ENTRY}" | cut -d'=' -f1 | tr '[:upper:]' '[:lower:]')
  VALUE=$(echo "${ENTRY}" | cut -d'=' -f2)

  # Check if the key exists in Google Cloud Secret Manager
  EXISTING_VALUE=$(gcloud secrets versions access latest --secret=${APP_NAME}-${KEY} --project=${PROJECT_ID} 2>/dev/null)

  if [ "${EXISTING_VALUE}" != "${VALUE}" ]; then
    # Disable all past versions of the secret
    gcloud secrets versions list ${APP_NAME}-${KEY} --project=${PROJECT_ID} --filter="state=enabled" --format "value(name)" | xargs -I {} gcloud secrets versions disable {} --secret=${APP_NAME}-${KEY} --project=${PROJECT_ID}
    # If the value is different or missing, update the existing secret with a new version
    gcloud secrets versions add ${APP_NAME}-${KEY} --data-file=- --project=${PROJECT_ID} <<EOF
${VALUE}
EOF

    echo "Updated ${KEY} in Google Cloud Secret Manager"
  else
    echo "Value for ${KEY} is already up-to-date in Google Cloud Secret Manager"
  fi
done

unset IFS

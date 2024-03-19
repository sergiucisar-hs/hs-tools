#!/bin/bash
set -euox

# Set the Kubernetes namespace, secret name and your Google Cloud Project ID and <appname> #Secret Manager Secret ID
NAMESPACE="$1"
SECRET_NAME="$2"
PROJECT_ID="$3"
RANDOM_PET="$4"

# Get the Kubernetes secret data
SECRET_DATA=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o json | jq -r '.data')

# Decode the base64-encoded data
SECRET_VALUES=$(echo "${SECRET_DATA}" | jq -r 'to_entries | map("\(.key)=\(.value | @base64d)") | .[]')

# Iterate through each key in the Kubernetes secret
IFS=$'\n'
for ENTRY in ${SECRET_VALUES}; do
  KEY=$(echo "${ENTRY}" | cut -d'=' -f1 | tr '[:upper:]' '[:lower:]' | gsed "s/${RANDOM_PET}_//" | gsed "s/${NAMESPACE}_//")
  VALUE=$(echo -n "${ENTRY}" | cut -d'=' -f2 | tr -d '\n')

  # Check if the key exists in Google Cloud Secret Manager
  EXISTING_VALUE=$(gcloud secrets versions access latest --secret=${NAMESPACE}-${KEY} --project=${PROJECT_ID} | tr -d '\n' || true) #2>/dev/null)

  # Compare existing value with the new value
  if [ "${EXISTING_VALUE}" != "${VALUE}" ]; then
    # If EXISTING_VALUE is null, create a new version
    if [ -z "${EXISTING_VALUE}" ]; then
      # Create a new version of the secret in Google Cloud Secret Manager
      echo -n "${VALUE}" | gcloud secrets versions add ${NAMESPACE}-${KEY}  --data-file=- --project=${PROJECT_ID} || true
    else
      # Disable all past versions of the secret
      gcloud secrets versions list ${NAMESPACE}-${KEY} --project=${PROJECT_ID} --filter="state=enabled" --format "value(name)" | xargs -I {} gcloud secrets versions disable {} --secret=${NAMESPACE}-${KEY} --project=${PROJECT_ID}

      # Create a new version of the secret in Google Cloud Secret Manager
      echo -n "${VALUE}" | gcloud secrets versions add ${NAMESPACE}-${KEY}  --data-file=- --project=${PROJECT_ID} || true
    fi
    echo "Updated ${NAMESPACE}-${KEY} in Google Cloud Secret Manager"
  else
    echo "Value for ${NAMESPACE}-${KEY} is already up-to-date in Google Cloud Secret Manager"
  fi
done

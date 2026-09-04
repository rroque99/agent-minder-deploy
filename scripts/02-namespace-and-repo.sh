#!/usr/bin/env bash
# Lab 2 - Namespace, image pull secret, and Helm repository.
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl helm
require_env NAMESPACE HELM_REPO HELM_REPO_URL

step "Namespace ${NAMESPACE} (PSA ${PSA_LEVEL:-privileged})"
# The platform's workloads (Hazelcast, ClickHouse, the proxy sidecars) need more
# than a 'restricted' PSA profile allows.
ensure_namespace "${NAMESPACE}"

step "Image pull secret ssp-gcr-registry-creds"
require_env BROADCOM_REGISTRY_SERVER BROADCOM_REGISTRY_USERNAME BROADCOM_REGISTRY_TOKEN
case "${BROADCOM_REGISTRY_USERNAME}${BROADCOM_REGISTRY_TOKEN}" in
  *'<'*) die "Set BROADCOM_REGISTRY_USERNAME / BROADCOM_REGISTRY_TOKEN in .env (Broadcom Support Portal)" ;;
esac
# The secret name must match the imagePullSecrets in the override files.
kubectl create secret docker-registry ssp-gcr-registry-creds \
  --docker-server="${BROADCOM_REGISTRY_SERVER}" \
  --docker-username="${BROADCOM_REGISTRY_USERNAME}" \
  --docker-password="${BROADCOM_REGISTRY_TOKEN}" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -
ok "ssp-gcr-registry-creds present in ${NAMESPACE}"

step "Helm repository ${HELM_REPO}"
helm repo add "${HELM_REPO}" "${HELM_REPO_URL}" --force-update
helm repo update "${HELM_REPO}"
helm search repo "${HELM_REPO}/ssp" --versions | head -20

step "Success criteria"
# --show-labels avoids escaping the dotted PSA label keys in a jsonpath.
kubectl get ns "${NAMESPACE}" --show-labels
helm repo list | grep -E "^${HELM_REPO}\b" && ok "repo registered"

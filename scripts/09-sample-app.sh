#!/usr/bin/env bash
# Lab 9 - Deploy the Sample App & MCP Playground (optional).
#
# Deploys a sample web app, a sample MCP server, a sample resource provider, a
# sample SPI, and the MCP Playground for creating and running agents.
#
# The Playground creates agents via GCP Vertex AI, so it needs a GCP project
# with Vertex AI enabled plus a service-account key or Workload Identity. If you
# are not on GCP you can still deploy the sample app and skip the Playground
# (set featureFlags.sampleMCP.enabled=false in the override).
#
# To create the credentials secret (skip if using Workload Identity):
#   GCP_SA_KEY_SECRET=<gcp-sa-key-secret> GCP_SA_KEY_FILE=<path-to-key.json> \
#     scripts/09-sample-app.sh
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl helm
require_env NAMESPACE RELEASENAME HELM_REPO SAMPLE_APP_FQDN GATEWAY_CLASS \
            REGISTRY_SECRET_NAME TLS_SECRET_NAME GCP_PROJECT_ID GCP_REGION

if [[ -n "${GCP_SA_KEY_FILE:-}" ]]; then
  require_env GCP_SA_KEY_SECRET
  step "GCP service-account secret ${GCP_SA_KEY_SECRET}"
  [[ -f "${GCP_SA_KEY_FILE}" ]] || die "Key file not found: ${GCP_SA_KEY_FILE}"
  kubectl create secret generic "${GCP_SA_KEY_SECRET}" \
    --from-file=key.json="${GCP_SA_KEY_FILE}" -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
  ok "secret applied"
else
  info "GCP_SA_KEY_FILE not set - skipping the Vertex AI credentials secret"
  info "(fine if you use Workload Identity or are skipping the MCP Playground)"
fi

step "helm install sample-${RELEASENAME}"
helm_deploy "sample-${RELEASENAME}" "${HELM_REPO}/ssp-sample-app" \
  ssp-sample-app-override 120m

step "Success criteria"
kubectl get pods -n "${NAMESPACE}" | grep -E "sample|mcp|playground" || \
  warn "No sample pods found yet"

cat <<'NOTE'

    You get: sample-app (web app), sample-mcp + mcp-playground (agent
    creation), sample-rp, sample-spi. The Playground exposes an agent port range
    (samplemcp.playground.agentPortMax, default 9600) and persists data on a PVC
    (samplemcp.persistence.size).

    Not reachable? Check the HTTPRoute host in the override matches DNS.
NOTE

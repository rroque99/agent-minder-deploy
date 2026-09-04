#!/usr/bin/env bash
# Lab 5 - Deploy the infrastructure chart (ssp-infra): database, ClickHouse
# (observability) and Fluent Bit. Deploy first, and wait for the create-db job
# before deploying the platform.
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl helm
require_env NAMESPACE RELEASENAME HELM_REPO REGISTRY_SECRET_NAME CLICKHOUSE_ENABLED
# Fluent Bit's output block needs real Elasticsearch credentials. ELASTIC_PASSWORD
# is written into .env by Lab 4; if you skipped Lab 4, set it yourself.
require_env ELASTIC_HOST ELASTIC_PORT ELASTIC_USER ELASTIC_PASSWORD

step "helm install infra-${RELEASENAME}"
helm_deploy "infra-${RELEASENAME}" "${HELM_REPO}/ssp-infra" \
  ssp-infra-override 120m

step "Wait for the database to be created (up to 5 minutes)"
kubectl wait jobs.batch --namespace "${NAMESPACE}" \
  --selector "app.kubernetes.io/name=ssp-infra-create-db-job" \
  --for 'condition=complete' --timeout '5m'
ok "create-db job complete"

step "Success criteria"
kubectl get jobs -n "${NAMESPACE}"
kubectl get pods -n "${NAMESPACE}"

cat <<'NOTE'

    Production: for an external database do NOT enable the bundled DB. Set
    db.enabled=false here and configure ssp.db.* (jdbcUrl, sslMode,
    existingSecret) in the ssp override -- see docs/database-connectivity.md.
NOTE

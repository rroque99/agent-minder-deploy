#!/usr/bin/env bash
# Lab 7 - Deploy the data chart (ssp-data): risk data schema + risk/network data.
#
# ssp-data is the risk data loader. It creates the risk-engine tables (not the
# platform schema -- ssp-infra's create-db job does that in Lab 5) and loads the
# network / IP reference data used by risk-based authentication and geolocation.
# It reuses the ssp chart's DB secret (ssp.db.existingSecret) and does not
# create its own. Deploy it whenever risk-based auth or geolocation is in scope.
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl helm
require_env NAMESPACE RELEASENAME HELM_REPO REGISTRY_SECRET_NAME

step "helm install data-${RELEASENAME}"
helm_deploy "data-${RELEASENAME}" "${HELM_REPO}/ssp-data" \
  ssp-data-override 60m

step "Success criteria"
kubectl get jobs -n "${NAMESPACE}" | grep -i data || \
  warn "No ssp-data jobs found yet - re-check in a moment"

cat <<'NOTE'

    Expect the risk-data and network-data-loader jobs to reach Completed. The
    network loader handles a large dataset and can run long -- raise --timeout
    rather than interrupting it. To re-run, helm uninstall the data release first.
NOTE

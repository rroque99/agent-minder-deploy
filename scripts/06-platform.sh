#!/usr/bin/env bash
# Lab 6 - Deploy the platform chart (ssp).
#
# Demo and production differ only by which override file is used; SSP_PROFILE
# selects it. Gateway-as-a-Service (the in-platform AI Gateway) is enabled by
# ssp.featureFlags.aigateway.enabled -- no separate chart needed. Observability
# comes from global.observe.enabled + ssp.featureFlags.nats.enabled here plus
# clickhouse.enabled in ssp-infra.
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl helm
require_env NAMESPACE RELEASENAME HELM_REPO

PROFILE="${SSP_PROFILE:-demo}"
VF="${VALUES_DIR}/ssp-override.${PROFILE}.yaml"
[[ -f "$VF" ]] || die "Unknown SSP_PROFILE='${PROFILE}' (expected demo or production)"

step "Profile: ${PROFILE}"
info "values file: ${VF}"
if ! grep -q "host: ${SSP_FQDN}" "$VF"; then
  warn "ssp.ingress.host in ${PROFILE} override does not match SSP_FQDN=${SSP_FQDN}."
  warn "Env vars are not expanded inside values files -- edit the literal host."
fi

step "helm install ${RELEASENAME}"
helm_deploy "${RELEASENAME}" "${HELM_REPO}/ssp" "$VF" 120m

step "Success criteria"
helm status "${RELEASENAME}" -n "${NAMESPACE}" | head -5
kubectl get pods -n "${NAMESPACE}"
kubectl get gateway,httproute -n "${NAMESPACE}" 2>/dev/null || true

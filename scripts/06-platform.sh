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
require_env NAMESPACE RELEASENAME HELM_REPO SSP_FQDN REGISTRY_SECRET_NAME \
            GATEWAY_CLASS SSP_DEPLOYMENT_SIZE OBSERVE_ENABLED NATS_ENABLED \
            AIGATEWAY_ENABLED OTEL_ACCEPT_EXTERNAL

PROFILE="${SSP_PROFILE:-demo}"
TPL="ssp-override.${PROFILE}"
[[ -f "${VALUES_DIR}/${TPL}.yaml.tpl" ]] || \
  die "Unknown SSP_PROFILE='${PROFILE}' (expected demo or production)"

# The production template attaches to $EXISTING_GATEWAY; empty would render an
# existingGateway with no value and fail at apply time in a confusing way.
[[ "${PROFILE}" != "production" ]] || require_env EXISTING_GATEWAY

step "Profile: ${PROFILE}"
info "template: values/${TPL}.yaml.tpl"
info "ingress host: ${SSP_FQDN}  (from .env)"

step "helm install ${RELEASENAME}"
helm_deploy "${RELEASENAME}" "${HELM_REPO}/ssp" "${TPL}" 120m

step "Success criteria"
helm status "${RELEASENAME}" -n "${NAMESPACE}" | head -5
kubectl get pods -n "${NAMESPACE}"
kubectl get gateway,httproute -n "${NAMESPACE}" 2>/dev/null || true

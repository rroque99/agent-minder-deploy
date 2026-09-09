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

step "Signing / encryption keys"
# helm uninstall keeps these secrets on purpose. If they survive from an earlier
# install we must reuse them: the MEK decrypts data already in the database, and
# ClickHouse TLS trusts the ISK it was provisioned with. Generating new ones
# leaves that data unreadable, so detect and reuse rather than asking the chart
# to mint fresh keys.
for _pair in "isk:ISK_EXISTING_SECRET" "mek:MEK_EXISTING_SECRET"; do
  _k="${_pair%%:*}"; _var="${_pair##*:}"
  _sec="${RELEASENAME}-ssp-keys-${_k}"
  if [[ -n "${!_var:-}" ]]; then
    ok "${_var}=${!_var} (from .env)"
  elif kubectl get secret "${_sec}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    info "found existing ${_sec} - reusing it"
    set_env "${_var}" "${_sec}"
  else
    info "no existing ${_k} secret - the chart will generate one"
  fi
done

step "ClickHouse TLS trust"
# Must be pinned whenever an ISK is reused: an empty value plus a provided ISK
# makes the chart use the ISK as ClickHouse's CA, which is only right if
# ClickHouse was provisioned with it. It was not - ssp-infra (Lab 5) creates
# ClickHouse before any ISK exists.
if [[ -n "${CLICKHOUSE_TLS_SECRET:-}" ]]; then
  ok "CLICKHOUSE_TLS_SECRET=${CLICKHOUSE_TLS_SECRET} (from .env)"
else
  _ch=""
  for _cand in "${RELEASENAME}-ssp-ch-tls" "clickhouse-${RELEASENAME}-ssp-ch-tls"; do
    if kubectl get secret "${_cand}" -n "${NAMESPACE}" >/dev/null 2>&1; then _ch="${_cand}"; break; fi
  done
  if [[ -n "${_ch}" ]]; then
    info "found ClickHouse TLS secret ${_ch}"
    set_env CLICKHOUSE_TLS_SECRET "${_ch}"
  elif [[ -n "${ISK_EXISTING_SECRET:-}" ]]; then
    warn "Reusing an ISK but no ClickHouse TLS secret found in ${NAMESPACE}."
    warn "observe-ingestor will trust the ISK as ClickHouse's CA and crash-loop."
    warn "Find it with: kubectl get secret -n ${NAMESPACE} | grep -i ch"
    warn "then set CLICKHOUSE_TLS_SECRET in .env."
  else
    info "no ClickHouse TLS secret found - chart default applies"
  fi
fi

step "helm install ${RELEASENAME}"
helm_deploy "${RELEASENAME}" "${HELM_REPO}/ssp" "${TPL}" 120m

step "Success criteria"
helm status "${RELEASENAME}" -n "${NAMESPACE}" | head -5
kubectl get pods -n "${NAMESPACE}"
kubectl get gateway,httproute -n "${NAMESPACE}" 2>/dev/null || true

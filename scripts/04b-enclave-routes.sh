#!/usr/bin/env bash
# Lab 4 (continued) - expose Kibana and Grafana.
#
# Creates a dedicated enclave Gateway with listeners for kibana.<DOMAIN> and
# grafana.<DOMAIN> that accept routes from any namespace, then attaches the two
# HTTPRoutes to it. Safe to run any time after Lab 4 - it does not depend on the
# ssp chart's Gateway (see the comment below for why it cannot use it).
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl envsubst
require_env DOMAIN NAMESPACE EDGE_GATEWAY_NAME

# The enclave routes attach to the shared edge Gateway created in Lab 3.
# Its *.${DOMAIN} wildcard listener accepts routes from any namespace, so the
# routes in logging/ and monitoring/ attach without a Gateway change.
#
# Override GATEWAY_NAME/GATEWAY_NAMESPACE in .env to target a different Gateway.
GATEWAY_NAME="${GATEWAY_NAME:-${EDGE_GATEWAY_NAME}}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-${NAMESPACE}}"
case "${GATEWAY_NAME}" in *'<'*) GATEWAY_NAME="${EDGE_GATEWAY_NAME}" ;; esac

step "Target Gateway: ${GATEWAY_NAMESPACE}/${GATEWAY_NAME}"
kubectl get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" -o wide \
  || die "Gateway ${GATEWAY_NAMESPACE}/${GATEWAY_NAME} not found - run 03-gateway-api.sh first."

# A listener must both accept routes from other namespaces and match the
# kibana./grafana. hostnames, or the routes report NotAllowedByListeners.
if ! kubectl get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
     -o jsonpath='{range .spec.listeners[*]}{.allowedRoutes.namespaces.from}{"\n"}{end}' \
     2>/dev/null | grep -qE '^(All|Selector)$'; then
  warn "No listener on ${GATEWAY_NAME} accepts routes from other namespaces"
  warn "(allowedRoutes.namespaces.from is 'Same' everywhere). The kibana and"
  warn "grafana routes live in logging/ and monitoring/ and will be refused."
  warn "Re-run scripts/03-gateway-api.sh to create the shared edge Gateway."
fi
export GATEWAY_NAME GATEWAY_NAMESPACE

step "Grafana service"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
# Validate a pinned value rather than trusting it: a previously-discovered
# wrong name (e.g. the '-alerting' service, which does not serve 3000) would
# otherwise stay in .env forever and keep failing with PortNotFound.
if [[ -n "${GRAFANA_SERVICE:-}" ]]; then
  if kubectl get svc "${GRAFANA_SERVICE}" -n monitoring \
       -o jsonpath='{range .spec.ports[*]}{.port}{","}{end}' 2>/dev/null \
       | grep -qE "(^|,)${GRAFANA_PORT}(,|$)"; then
    ok "GRAFANA_SERVICE=${GRAFANA_SERVICE} serves port ${GRAFANA_PORT}"
  else
    warn "GRAFANA_SERVICE=${GRAFANA_SERVICE} does not serve port ${GRAFANA_PORT} - rediscovering"
    GRAFANA_SERVICE=""
  fi
fi

if [[ -n "${GRAFANA_SERVICE:-}" ]]; then
  :
else
  # Select the service that actually exposes the Grafana HTTP port. Matching on
  # the name alone picks up siblings like '-alerting' and '-operator-metrics',
  # which do not serve 3000 - the HTTPRoute then fails with PortNotFound.
  discovered="$(kubectl get svc -n monitoring \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .spec.ports[*]}{.port}{","}{end}{"\n"}{end}' \
    2>/dev/null | awk -v p="${GRAFANA_PORT}" '$2 ~ "(^|,)" p "(,|$)" {print $1}' \
    | grep -i grafana | head -1 || true)"
  if [[ -z "${discovered}" ]]; then
    warn "No service in 'monitoring' exposes port ${GRAFANA_PORT}. Candidates:"
    kubectl get svc -n monitoring 2>/dev/null | sed 's/^/       /' >&2
    die "Set GRAFANA_SERVICE (and GRAFANA_PORT if not 3000) in .env."
  fi
  set_env GRAFANA_SERVICE "${discovered}"
fi
export GRAFANA_SERVICE GRAFANA_PORT

step "Apply HTTPRoutes"
render "${MANIFESTS_DIR}/httproute-kibana.yaml.tpl"  | kubectl apply -f -
render "${MANIFESTS_DIR}/httproute-grafana.yaml.tpl" | kubectl apply -f -

step "Success criteria"
kubectl get httproute kibana  -n logging    -o wide
kubectl get httproute grafana -n monitoring -o wide
info "Expect Accepted=True and ResolvedRefs=True on both."
echo
step "Gateway address - point DNS here"
kubectl get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{range .status.addresses[*]}    {.value}{"\n"}{end}' 2>/dev/null || true
info "kibana.${DOMAIN}  and  grafana.${DOMAIN}  must resolve to that address."
info "Then browse:"
info "  https://kibana.${DOMAIN}"
info "  https://grafana.${DOMAIN}"

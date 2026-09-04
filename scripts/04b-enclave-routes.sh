#!/usr/bin/env bash
# Lab 4 (continued) - attach kibana.<DOMAIN> and grafana.<DOMAIN> HTTPRoutes to
# your Gateway API listener. Terminate TLS there with a CA-signed wildcard
# certificate for *.<DOMAIN>.
#
# Run after a Gateway exists: either your own shared edge Gateway, or the one
# the ssp chart creates in Lab 6 when gatewayApi.createGateway=true.
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl envsubst
require_env DOMAIN NAMESPACE

# GATEWAY_NAME is optional. Left empty (or still a <placeholder>), the Gateway
# is discovered from the cluster: the ssp chart names the one it creates in
# Lab 6, so there is nothing sensible to hard-code for the demo path.
# Default both here so `set -u` is satisfied even when .env omits them entirely.
GATEWAY_NAME="${GATEWAY_NAME:-}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-${NAMESPACE}}"
case "${GATEWAY_NAME}" in *'<'*) GATEWAY_NAME="" ;; esac

# gw_list <namespace>|-A  ->  lines of "<namespace> <name> <gatewayclass>"
gw_list() {
  local scope="$1"
  local jp='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.gatewayClassName}{"\n"}{end}'
  if [[ "$scope" == "-A" ]]; then
    kubectl get gateway -A -o jsonpath="$jp" 2>/dev/null || true
  else
    kubectl get gateway -n "$scope" -o jsonpath="$jp" 2>/dev/null || true
  fi
}

if [[ -n "${GATEWAY_NAME}" ]]; then
  step "Target Gateway (pinned): ${GATEWAY_NAMESPACE}/${GATEWAY_NAME}"
  kubectl get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
    || die "Gateway ${GATEWAY_NAMESPACE}/${GATEWAY_NAME} not found. kubectl get gateway -A"
else
  step "Discover the Gateway"
  # Prefer $GATEWAY_NAMESPACE (where the ssp chart puts it), then cluster-wide.
  found="$(gw_list "${GATEWAY_NAMESPACE}" | grep -v '^[[:space:]]*$' || true)"
  scope="namespace ${GATEWAY_NAMESPACE}"
  if [[ -z "${found}" ]]; then
    found="$(gw_list -A | grep -v '^[[:space:]]*$' || true)"
    scope="the cluster"
  fi

  count="$(printf '%s\n' "${found}" | grep -c . || true)"
  if [[ "${count}" -eq 0 ]]; then
    die "No Gateway found in ${scope}. In demo mode the ssp chart creates it in Lab 6 - run 06-platform.sh first, or set GATEWAY_NAME to a shared edge Gateway."
  fi

  # More than one candidate: narrow by GATEWAY_CLASS before giving up.
  if [[ "${count}" -gt 1 ]] && [[ -n "${GATEWAY_CLASS:-}" ]]; then
    narrowed="$(printf '%s\n' "${found}" | awk -v c="${GATEWAY_CLASS}" '$3 == c' || true)"
    narrowed_count="$(printf '%s\n' "${narrowed}" | grep -c . || true)"
    if [[ "${narrowed_count}" -eq 1 ]]; then
      info "narrowed ${count} candidates to gatewayClassName=${GATEWAY_CLASS}"
      found="${narrowed}"; count=1
    fi
  fi

  if [[ "${count}" -gt 1 ]]; then
    warn "Found ${count} Gateways in ${scope}:"
    printf '%s\n' "${found}" | awk '{printf "       %s/%s  (class %s)\n", $1, $2, $3}' >&2
    die "Ambiguous - set GATEWAY_NAME (and GATEWAY_NAMESPACE) in .env to pick one."
  fi

  GATEWAY_NAMESPACE="$(printf '%s\n' "${found}" | awk '{print $1}')"
  GATEWAY_NAME="$(printf '%s\n' "${found}" | awk '{print $2}')"
  ok "GATEWAY_NAME=${GATEWAY_NAME}  GATEWAY_NAMESPACE=${GATEWAY_NAMESPACE}  (class $(printf '%s\n' "${found}" | awk '{print $3}'))"
fi
export GATEWAY_NAME GATEWAY_NAMESPACE

step "Discover the Grafana service"
GRAFANA_SERVICE="${GRAFANA_SERVICE:-$(kubectl get svc -n monitoring -o name \
  | grep -i grafana | grep -v operator-metrics | head -1 | cut -d/ -f2)}"
[[ -n "${GRAFANA_SERVICE}" ]] || die "No Grafana service found in 'monitoring'. Set GRAFANA_SERVICE explicitly."
export GRAFANA_SERVICE
ok "GRAFANA_SERVICE=${GRAFANA_SERVICE}"

step "Apply HTTPRoutes"
render "${MANIFESTS_DIR}/httproute-kibana.yaml.tpl"  | kubectl apply -f -
render "${MANIFESTS_DIR}/httproute-grafana.yaml.tpl" | kubectl apply -f -

step "Success criteria"
kubectl get httproute kibana  -n logging    -o wide
kubectl get httproute grafana -n monitoring -o wide
info "Expect Accepted=True on both. Then browse:"
info "  https://kibana.${DOMAIN}"
info "  https://grafana.${DOMAIN}"

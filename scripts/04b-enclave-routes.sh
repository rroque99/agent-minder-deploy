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
require_env DOMAIN GATEWAY_NAME GATEWAY_NAMESPACE

case "${GATEWAY_NAME}" in
  *'<'*) die "Set GATEWAY_NAME in .env. List candidates with: kubectl get gateway -A" ;;
esac

step "Target Gateway"
kubectl get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  || die "Gateway ${GATEWAY_NAMESPACE}/${GATEWAY_NAME} not found. kubectl get gateway -A"

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

#!/usr/bin/env bash
# Lab 8 - Verify the deployment.
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl curl
require_env NAMESPACE SSP_FQDN

step "Workloads"
kubectl get pods -n "${NAMESPACE}"
echo
kubectl get pods,svc,ing -n "${NAMESPACE}" -o wide

step "Not-ready workloads"
not_ready="$(kubectl get pods -n "${NAMESPACE}" --no-headers \
  | awk '$3 != "Running" && $3 != "Completed" { print "    " $0 }')"
if [[ -n "$not_ready" ]]; then
  warn "Some pods are not Running/Completed:"
  printf '%s\n' "$not_ready"
  info "Investigate with: kubectl describe pod <name> -n ${NAMESPACE}"
else
  ok "All pods Running or Completed"
fi

step "Recent events"
kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp | tail -20

step "OIDC discovery on https://${SSP_FQDN}"
# --insecure because demo mode uses a self-signed certificate.
url="https://${SSP_FQDN}/default/.well-known/openid-configuration?sspinfo=true"
info "GET ${url}"
if body="$(curl --insecure --show-error --silent --max-time 30 "$url")"; then
  if printf '%s' "$body" | grep -q '"issuer"'; then
    ok "discovery document returned (contains issuer)"
    printf '%s\n' "$body" | head -c 600; echo
  else
    warn "Response did not contain 'issuer':"
    printf '%s\n' "$body" | head -c 600; echo
    warn "HTTP 404 usually means the HTTPRoute host does not match ${SSP_FQDN}."
  fi
else
  warn "Request failed. SSL settings on the ingress can require a controller restart:"
  warn "  kubectl rollout restart deployment/envoy-gateway -n envoy-gateway-system"
  warn "  (or, for nginx: kubectl rollout restart deployment ingress-nginx-controller -n ingress)"
  exit 1
fi

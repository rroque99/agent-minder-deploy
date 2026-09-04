#!/usr/bin/env bash
# Preflight - verify the prerequisites from "Before You Begin".
source "$(dirname "$0")/lib/common.sh"
load_env

step "Tooling"
require_cmd kubectl helm base64
if ! command -v envsubst >/dev/null 2>&1; then
  die "envsubst not found (renders manifests/*.yaml.tpl). Install it: $(install_hint gettext gettext-base)"
fi
command -v curl >/dev/null 2>&1 || \
  warn "curl not found - needed by 08-verify.sh. Install it: $(install_hint curl curl)"
helm_ver="$(helm version --short 2>/dev/null || true)"
kubectl_ver="$(kubectl version --client -o json 2>/dev/null \
  | grep -oE '"gitVersion": *"[^"]*"' | head -1 | cut -d'"' -f4)"
info "kubectl: ${kubectl_ver:-unknown}"
info "helm:    ${helm_ver}"
case "$helm_ver" in
  v3.*) ok "Helm 3.x (guide requires 3.10 or above)" ;;
  *)    warn "Expected Helm 3.10+, got '${helm_ver}'" ;;
esac

step "Cluster reachability"
kubectl get nodes >/dev/null || die "kubectl cannot reach the cluster"
node_count="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
ok "${node_count} node(s) reachable"
if (( node_count < 5 )); then
  warn "Demo mode wants 5-6 nodes at 4 vCPU / 16 GB; found ${node_count}."
fi
server_minor="$(kubectl version -o json 2>/dev/null \
  | grep -A5 serverVersion | grep -oE '"minor": *"[^"]*"' | cut -d'"' -f4 | tr -dc '0-9')"
if [[ -n "$server_minor" ]] && (( server_minor < 32 )); then
  warn "Kubernetes 1.${server_minor} is below the 1.32.x minimum."
else
  ok "Kubernetes server version acceptable"
fi

step "Gateway API CRDs"
if kubectl get crd gatewayclasses.gateway.networking.k8s.io >/dev/null 2>&1; then
  ok "Gateway API CRDs present"
  kubectl get gatewayclass 2>/dev/null | sed 's/^/    /' || true
else
  warn "Gateway API CRDs missing - run scripts/03-gateway-api.sh (Lab 3)"
fi

step "Environment"
require_env PREFIX DOMAIN SSP_FQDN RELEASENAME NAMESPACE HELM_REPO HELM_REPO_URL
info "SSP_FQDN=${SSP_FQDN}  NAMESPACE=${NAMESPACE}  RELEASENAME=${RELEASENAME}"
info "profile=${SSP_PROFILE:-demo}"
# || dns_rc=$? keeps the call in a condition context so `set -e` does not fire.
dns_rc=0; resolves "$SSP_FQDN" || dns_rc=$?
case $dns_rc in
  0) ok   "${SSP_FQDN} resolves" ;;
  1) warn "${SSP_FQDN} does not resolve yet - add DNS before Lab 8 verification" ;;
  2) info "cannot check DNS for ${SSP_FQDN} (no host/getent/nslookup/dig on PATH)" ;;
esac

step "Values files"
for f in "${VALUES_DIR}"/*.yaml; do
  if grep -qE '^[^#]*<[A-Za-z0-9_.-]+>' "$f"; then
    warn "$(basename "$f") still has placeholders to edit"
  else
    ok "$(basename "$f")"
  fi
done

step "Preflight complete"

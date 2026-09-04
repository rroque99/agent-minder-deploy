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

PROFILE="${SSP_PROFILE:-demo}"

step "Configuration (.env, profile: ${PROFILE})"
# .env is the only file anyone edits; the values/ templates are rendered from
# it. So validate variables here rather than scanning generated YAML.
unset_now=""
pending=""

need() {  # need VAR "why it matters"
  if [[ -z "${!1:-}" ]]; then unset_now="${unset_now} $1"; else ok "$1=${!1}"; fi
}
need_secret() {  # like need, but do not echo the value
  if [[ -z "${!1:-}" ]]; then unset_now="${unset_now} $1"; else ok "$1 is set"; fi
}
later() {  # later VAR "which lab fills it in"
  [[ -n "${!1:-}" ]] && ok "$1=${!1}" || pending="${pending}\n       $1 - $2"
}

need SSP_FQDN;   need NAMESPACE; need RELEASENAME
need HELM_REPO;  need HELM_REPO_URL
need REGISTRY_SECRET_NAME
need GATEWAY_CLASS
need SSP_DEPLOYMENT_SIZE
need_secret BROADCOM_REGISTRY_USERNAME
need_secret BROADCOM_REGISTRY_TOKEN

case "${PROFILE}" in
  production) need IMAGE_REPOSITORY_BASE; need DB_TYPE; need DB_JDBC_URL
              need DB_SECRET; need EXISTING_GATEWAY; need TLS_SECRET_NAME ;;
esac

later ELASTIC_PASSWORD "set by Lab 4 (scripts/04-enclave-services.sh)"
later GATEWAY_NAME     "set by Lab 4b once a Gateway exists (after Lab 6)"
later GRAFANA_SERVICE  "set by Lab 4b (scripts/04b-enclave-routes.sh)"

if [[ -n "${unset_now# }" ]]; then
  warn "Unset in .env, needed before deploying:"
  for v in ${unset_now}; do printf '       %s\n' "$v" >&2; done
  die "Set them in .env and re-run."
fi
[[ -n "${pending}" ]] && { info "Discovered later (fine to be empty now):"; printf "${pending}\n"; }

# Placeholders left in .env are a hard stop: they render straight into a chart.
ph="$(grep -nE '^[[:space:]]*export [A-Z_]+="?<[A-Za-z0-9_.-]+>' "${ENV_FILE}" 2>/dev/null || true)"
if [[ -n "$ph" ]]; then
  # Only complain about ones this profile actually consumes.
  relevant=""
  while IFS= read -r line; do
    var="$(printf '%s' "$line" | sed -E 's/^[0-9]+:[[:space:]]*export ([A-Z_]+)=.*/\1/')"
    case "$var" in
      IMAGE_REPOSITORY_BASE|DB_HOST|DB_JDBC_URL)
        [[ "${PROFILE}" == "production" ]] && relevant="${relevant}\n       ${line}" ;;
      GCP_PROJECT_ID|GCP_SA_KEY_SECRET)
        info "${var} still a placeholder - only needed for Lab 9 (sample app)" ;;
      AIGW_GROUP_ID)
        info "${var} still a placeholder - only needed for Lab 11 (AI Gateway)" ;;
      *) relevant="${relevant}\n       ${line}" ;;
    esac
  done <<< "$ph"
  if [[ -n "$relevant" ]]; then
    warn "Placeholders still in .env for profile '${PROFILE}':"
    printf "${relevant}\n" >&2
    die "Replace them in .env."
  fi
fi

step "Template render check"
# Render every template the selected profile uses; catches unresolved
# variables now rather than mid-install.
tpls="ssp-infra-override ssp-override.${PROFILE} ssp-data-override
      kube-prometheus-values grafana-operator-values"
for t in ${tpls}; do
  if out="$(render_values "$t" 2>&1)"; then
    ok "$(basename "$t").yaml.tpl renders"
  else
    warn "$t failed to render:"; printf '%s\n' "$out" | sed 's/^/       /' >&2
    die "Fix .env (or the template) and re-run."
  fi
done

step "Preflight complete"

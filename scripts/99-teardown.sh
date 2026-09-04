#!/usr/bin/env bash
# Teardown (optional) - uninstall in reverse dependency order.
#
# Demo clusters cost money while they run. Database, ClickHouse, PVCs, secrets
# and any externally managed Gateway persist beyond helm uninstall -- clean
# those up deliberately. If you created the cluster solely for this course,
# delete the cluster itself to stop all charges.
#
#   scripts/99-teardown.sh                 # uninstall the Helm releases
#   DELETE_NAMESPACE=1 scripts/99-teardown.sh   # also delete the namespace
#   TEARDOWN_ENCLAVE=1 scripts/99-teardown.sh   # also remove logging/monitoring
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl helm
require_env NAMESPACE RELEASENAME

printf '\n%sThis will uninstall AgentMinder from namespace "%s".%s\n' "$_Y" "${NAMESPACE}" "$_0"
[[ "${DELETE_NAMESPACE:-}" == "1" ]] && printf '%sThe namespace itself (and its PVCs/secrets) will be DELETED.%s\n' "$_R" "$_0"
[[ "${TEARDOWN_ENCLAVE:-}" == "1" ]] && printf '%sThe logging and monitoring namespaces will be DELETED.%s\n' "$_R" "$_0"
if [[ "${ASSUME_YES:-}" != "1" ]]; then
  read -r -p 'Type the namespace name to confirm: ' reply
  [[ "$reply" == "${NAMESPACE}" ]] || die "Aborted."
fi

uninstall() { # uninstall <release> <note>
  if helm status "$1" -n "${NAMESPACE}" >/dev/null 2>&1; then
    step "helm uninstall $1   ($2)"
    helm uninstall "$1" -n "${NAMESPACE}"
  else
    info "skip $1 - not installed   ($2)"
  fi
}

uninstall "aigw-${RELEASENAME}"   "external AI Gateway, Lab 11"
uninstall "sample-${RELEASENAME}" "sample app / MCP Playground, Lab 9"
uninstall "${RELEASENAME}"        "platform, Lab 6"
uninstall "data-${RELEASENAME}"   "risk data schema + risk/network data, Lab 7"
uninstall "infra-${RELEASENAME}"  "database, ClickHouse, Fluent Bit, Lab 5"

if [[ "${DELETE_NAMESPACE:-}" == "1" ]]; then
  step "kubectl delete ns ${NAMESPACE}"
  kubectl delete ns "${NAMESPACE}"
else
  step "Remaining objects in ${NAMESPACE}"
  kubectl get all,pvc,secret -n "${NAMESPACE}" 2>/dev/null || true
  info "PVCs and secrets survive helm uninstall."
  info "Re-run with DELETE_NAMESPACE=1 to remove the namespace and clear them."
fi

if [[ "${TEARDOWN_ENCLAVE:-}" == "1" ]]; then
  step "Enclave services"
  helm uninstall grafana-operator    -n monitoring 2>/dev/null || true
  helm uninstall prometheus-operator -n monitoring 2>/dev/null || true
  kubectl delete -n logging -f "${MANIFESTS_DIR}/kibana.yaml"        2>/dev/null || true
  kubectl delete -n logging -f "${MANIFESTS_DIR}/elasticsearch.yaml" 2>/dev/null || true
  helm uninstall elastic-operator -n logging 2>/dev/null || true
  kubectl delete ns monitoring logging 2>/dev/null || true
fi

step "Teardown complete"
info "If this cluster existed only for the course, delete the cluster (GKE/EKS/AKS/VKS)."

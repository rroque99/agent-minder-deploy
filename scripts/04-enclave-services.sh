#!/usr/bin/env bash
# Lab 4 - Deploy enclave services: platform observability (Elasticsearch/Kibana)
# and monitoring (Prometheus/Grafana).
#
# These are IDSP's *platform* observability stack and are required for a
# supportable deployment. They are distinct from AgentMinder 4.1 Observability
# (ClickHouse/NATS/OpenTelemetry, which captures agentic runtime telemetry) --
# both are needed; neither replaces the other. If you already run an enterprise
# observability stack you may link IDSP to it instead.
#
# Deploy order: Lab 3 (Gateway API) -> Lab 4 (this) -> Lab 5 (ssp-infra).
# In demo mode the enclave stack adds roughly 7 cores and 16 GB of RAM.
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl helm
require_env ECK_OPERATOR_VERSION KUBE_PROMETHEUS_VERSION GRAFANA_OPERATOR_VERSION

step "Namespaces logging + monitoring (PSA ${PSA_LEVEL:-privileged})"
# Created here rather than by Helm's --create-namespace / later in the script,
# so the PSA labels are in place before any enclave pod is admitted.
ensure_namespace logging
ensure_namespace monitoring

step "1/5 ECK operator (namespace: logging)"
helm repo add elastic https://helm.elastic.co --force-update
helm repo update elastic
# Private registry: create a docker-registry secret in 'logging' first, then add
#   --set imagePullSecrets[0].name=<registry-secret-name>
eck_extra=()
[[ -n "${LOGGING_PULL_SECRET:-}" ]] && eck_extra+=(--set "imagePullSecrets[0].name=${LOGGING_PULL_SECRET}")
# ${arr[@]+"${arr[@]}"} - see the note in 03-gateway-api.sh (bash 3.2 + set -u).
helm upgrade --install elastic-operator elastic/eck-operator \
  -n logging --create-namespace --version="${ECK_OPERATOR_VERSION}" \
  ${eck_extra[@]+"${eck_extra[@]}"}
kubectl rollout status statefulset/elastic-operator -n logging --timeout=5m

step "2/5 Elasticsearch + Kibana"
render "${MANIFESTS_DIR}/elasticsearch.yaml.tpl" | kubectl apply -n logging -f -
info "waiting for Elasticsearch to become ready (this takes a few minutes)"
kubectl wait --for=jsonpath='{.status.health}'=green \
  elasticsearch/elasticsearch -n logging --timeout=15m || \
  warn "Elasticsearch not green yet - check 'kubectl get pods -n logging' (a Pending pod usually means an unbound PVC)"
render "${MANIFESTS_DIR}/kibana.yaml.tpl" | kubectl apply -n logging -f -
kubectl get pods -n logging

step "3/5 Elasticsearch 'elastic' user password"
# Check the secret is readable before decoding: GNU base64 fails hard on empty
# input ("base64: invalid input"), which hides the real cause.
ELASTIC_B64="$(kubectl get secret -n logging elasticsearch-es-elastic-user \
  -o=jsonpath='{.data.elastic}' 2>/dev/null || true)"
[[ -n "${ELASTIC_B64}" ]] || die \
  "Cannot read secret logging/elasticsearch-es-elastic-user - is Elasticsearch up? (kubectl get pods -n logging)"
ELASTIC_PW="$(printf '%s' "${ELASTIC_B64}" | base64 --decode)"
[[ -n "${ELASTIC_PW}" ]] || die "Decoded Elasticsearch password is empty"
# Persist it so Lab 5 renders the Fluent Bit output without anyone copying it.
set_env ELASTIC_PASSWORD "${ELASTIC_PW}"
info "Fluent Bit will ship logs to ${ELASTIC_HOST:-elasticsearch-es-http.logging.svc} as user ${ELASTIC_USER:-elastic}"

step "4/5 Prometheus + Grafana (namespace: monitoring)"
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm repo update bitnami
helm upgrade --install prometheus-operator bitnami/kube-prometheus -n monitoring \
  -f "$(render_values kube-prometheus-values)" --version="${KUBE_PROMETHEUS_VERSION}"
helm upgrade --install grafana-operator bitnami/grafana-operator -n monitoring \
  -f "$(render_values grafana-operator-values)" --version="${GRAFANA_OPERATOR_VERSION}"
kubectl get pods -n monitoring

step "5/5 Grafana datasource + IDSP dashboard (Grafana.com ID 25306)"
kubectl apply -n monitoring -f "${MANIFESTS_DIR}/grafana-datasource.yaml"
kubectl apply -n monitoring -f "${MANIFESTS_DIR}/grafana-dashboard.yaml"

step "Success criteria"
kubectl get pods -n logging
kubectl get pods -n monitoring

cat <<'NOTE'

    Expose Kibana and Grafana on the shared edge Gateway (created in Lab 3):
      scripts/04b-enclave-routes.sh

    Then, in the UIs:
      Kibana  -> Data Views -> Create data view
                 index pattern: ssp_log*  (repeat for ssp_audit*, ssp_tp_log*)
                 timestamp field: @timestamp
      Grafana -> sign in (admin / prom-operator -- change it)
                 Dashboards -> confirm the IDSP dashboard (25306)
                            -> Enclave Services Health (per-pod enclave health)
NOTE

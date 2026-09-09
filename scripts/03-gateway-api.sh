#!/usr/bin/env bash
# Lab 3 - Deploy the Gateway API controller (Envoy Gateway) and a GatewayClass.
#
# Envoy Gateway is recommended because it is the only supported controller with
# full frontend mTLS. ALB does not support it; GKE L7 and Azure AGC cannot
# forward client certificates.
#
# If your platform already manages the Gateway API CRDs, re-run with
# SKIP_CRDS=1 to add --skip-crds to the helm install.
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl helm
require_env GATEWAY_CLASS ENVOY_GATEWAY_VERSION NAMESPACE DOMAIN \
            SSP_FQDN EDGE_GATEWAY_NAME TLS_SECRET_NAME

step "Namespace envoy-gateway-system (PSA ${PSA_LEVEL:-privileged})"
# Created here rather than by Helm's --create-namespace, so the PSA labels are
# in place before the controller pod is admitted.
ensure_namespace envoy-gateway-system

step "Install Envoy Gateway ${ENVOY_GATEWAY_VERSION}"
extra=()
[[ "${SKIP_CRDS:-}" == "1" ]] && extra+=(--skip-crds)
# ${arr[@]+"${arr[@]}"} - expanding an empty array as "${arr[@]}" is an unbound
# variable error under `set -u` in bash 3.2, which is what macOS ships.
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "${ENVOY_GATEWAY_VERSION}" \
  -n envoy-gateway-system --create-namespace ${extra[@]+"${extra[@]}"}

step "Wait for the controller"
kubectl wait --timeout=5m -n envoy-gateway-system \
  deployment/envoy-gateway --for=condition=Available
ok "envoy-gateway Available"

step "GatewayClass ${GATEWAY_CLASS}"
if [[ "${GATEWAY_CLASS}" == "eg" ]]; then
  kubectl apply -f "${MANIFESTS_DIR}/gatewayclass-eg.yaml"
else
  info "GATEWAY_CLASS=${GATEWAY_CLASS} -- applying manifests/gatewayclass-eg.yaml with the name overridden"
  sed "s/^  name: eg$/  name: ${GATEWAY_CLASS}/" \
    "${MANIFESTS_DIR}/gatewayclass-eg.yaml" | kubectl apply -f -
fi

step "TLS certificate for the wildcard listener"
# The listener serves *.${DOMAIN}, so the certificate should cover that. A
# per-host cert (e.g. ssp.${DOMAIN}) still works but browsers will warn on the
# other hostnames.
if kubectl get secret "${TLS_SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  ok "${TLS_SECRET_NAME} already exists in ${NAMESPACE}"
elif [[ "${EDGE_TLS_SELF_SIGNED:-true}" == "true" ]]; then
  require_cmd openssl
  info "generating a self-signed *.${DOMAIN} certificate (lab use)"
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/edgetls.XXXXXX")"
  openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -keyout "${tmpd}/tls.key" -out "${tmpd}/tls.crt" \
    -subj "/CN=*.${DOMAIN}" \
    -addext "subjectAltName=DNS:*.${DOMAIN},DNS:${DOMAIN}" >/dev/null 2>&1 \
    || die "openssl failed to generate the certificate"
  kubectl create secret tls "${TLS_SECRET_NAME}" \
    --cert="${tmpd}/tls.crt" --key="${tmpd}/tls.key" -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
  rm -rf "${tmpd}"
  ok "${TLS_SECRET_NAME} created (self-signed - replace with a CA-signed wildcard for production)"
else
  die "Secret ${TLS_SECRET_NAME} not found in ${NAMESPACE}. Create it, or set EDGE_TLS_SELF_SIGNED=true in .env to generate a self-signed one."
fi

step "Shared edge Gateway ${NAMESPACE}/${EDGE_GATEWAY_NAME}"
# Created here, before the ssp chart (Lab 6), so the chart can attach to it
# with createGateway=false instead of provisioning a second Gateway.
render "${MANIFESTS_DIR}/gateway-edge.yaml.tpl" | kubectl apply -f -
kubectl wait --for=condition=Programmed --timeout=5m \
  gateway/"${EDGE_GATEWAY_NAME}" -n "${NAMESPACE}" \
  || warn "Gateway not Programmed yet - check 'kubectl describe gateway ${EDGE_GATEWAY_NAME} -n ${NAMESPACE}'"

step "Success criteria"
kubectl get gatewayclass "${GATEWAY_CLASS}"
kubectl get pods -n envoy-gateway-system
kubectl get gateway "${EDGE_GATEWAY_NAME}" -n "${NAMESPACE}" -o wide

step "Gateway address - point ALL DNS here"
addr="$(kubectl get gateway "${EDGE_GATEWAY_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
if [[ -n "${addr}" ]]; then
  ok "${addr}"
  info "Create A records pointing at it:"
  info "  ${SSP_FQDN}"
  info "  mgmt-${SSP_FQDN}"
  info "  kibana.${DOMAIN}"
  info "  grafana.${DOMAIN}"
  info "  ${SAMPLE_APP_FQDN}   (if deploying Lab 9)"
else
  warn "No address assigned yet. If it stays empty the cluster has no"
  warn "load-balancer provider - see 'kubectl get svc -n envoy-gateway-system'."
fi

cat <<NOTE

    The ssp chart attaches to this Gateway rather than creating its own:
      ssp.ingress.gatewayApi.createGateway:  false
      ssp.ingress.gatewayApi.existingGateway: ${EDGE_GATEWAY_NAME}
    Both values templates are already set up that way.
NOTE

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
require_env GATEWAY_CLASS ENVOY_GATEWAY_VERSION

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

step "Success criteria"
kubectl get gatewayclass "${GATEWAY_CLASS}"
kubectl get pods -n envoy-gateway-system
kubectl get crd | grep gateway || true

cat <<'NOTE'

    Next: reference this GatewayClass from values/ssp-override.<profile>.yaml
      ssp.ingress.type: gatewayapi
      ssp.ingress.gatewayApi.gatewayClassName: <GATEWAY_CLASS>
      ssp.ingress.gatewayApi.createGateway: true   (chart-managed mode)
NOTE

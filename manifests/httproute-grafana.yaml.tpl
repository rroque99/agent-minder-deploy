# Lab 4 - expose Grafana on the Gateway API (HTTPRoute -> Grafana service :3000).
# Rendered by scripts/04-enclave-services.sh via envsubst.
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
  - name: ${GATEWAY_NAME}
    namespace: ${GATEWAY_NAMESPACE}
  hostnames:
  - grafana.${DOMAIN}
  rules:
  - backendRefs:
    - name: ${GRAFANA_SERVICE}
      port: 3000

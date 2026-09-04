# Lab 4 - expose Kibana on the Gateway API (HTTPRoute -> kibana-kb-http:5601).
# Rendered by scripts/04-enclave-services.sh via envsubst.
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: kibana
  namespace: logging
spec:
  parentRefs:
  - name: ${GATEWAY_NAME}
    namespace: ${GATEWAY_NAMESPACE}
  hostnames:
  - kibana.${DOMAIN}
  rules:
  - backendRefs:
    - name: kibana-kb-http
      port: 5601

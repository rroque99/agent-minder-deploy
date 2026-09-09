# Shared edge Gateway - one Gateway, one external IP, for every hostname.
#
# Lives in ${NAMESPACE} deliberately: the ssp chart's own HTTPRoutes are created
# there, so they attach same-namespace and need no cross-namespace support from
# the chart. allowedRoutes.namespaces.from=All then lets the enclave routes in
# logging/ and monitoring/ attach to the same listener.
#
# The wildcard hostname means any new <name>.${DOMAIN} route works with no
# Gateway change. Created by scripts/03-gateway-api.sh, before the ssp chart is
# installed (Lab 6) so the chart can attach with createGateway=false.
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${EDGE_GATEWAY_NAME}
  namespace: ${NAMESPACE}
spec:
  gatewayClassName: ${GATEWAY_CLASS}
  listeners:
  - name: https-wildcard
    hostname: "*.${DOMAIN}"
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: ${TLS_SECRET_NAME}
    allowedRoutes:
      namespaces:
        from: All
  - name: http-redirect
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All

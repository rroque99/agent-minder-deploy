# ssp-aigateway-override.yaml (optional - external / standalone AI Gateway)
# rendered from .env     Chart: ssp-aigateway   Release: aigw-$RELEASENAME   Lab 11
#
# Only needed for a gateway at the edge or in another cluster. The in-platform
# AI Gateway is enabled by AIGATEWAY_ENABLED in Lab 6.
aigateway:
  name: aigateway
  groupId: "${AIGW_GROUP_ID}"        # Admin Console -> AI Gateways -> Group GUID
  # idspBaseUrl derives control-plane, auth, PDP, OTLP and token endpoints
  idspBaseUrl: "${IDSP_BASE_URL}"
  defaultCredentials:
    existingSecret: "${AIGW_CREDENTIALS_SECRET}"
    scopes:
      - "${AIGW_SCOPES}"
  otel:
    enabled: true                    # activates the OpenTelemetry pipeline
imagePullSecrets:
  - name: ${REGISTRY_SECRET_NAME}

tls:
  generateSelfSignedCert: ${AIGW_TLS_SELF_SIGNED}   # dev/test only
ingress:
  enabled: false                     # disable legacy ingress for Gateway API
gatewayApi:
  enabled: true                      # activate Kubernetes Gateway API support
  httpRoute:
    enabled: true                    # chart-managed HTTPRoute resource
    rules:
      - hostname: "${AIGW_FQDN}"
        port: 443                    # standard TLS listener port
        matches:
          - path:
              type: PathPrefix
              value: /
  gateway:
    create: true                     # let the chart provision the Gateway
    gatewayClassName: "${GATEWAY_CLASS}"
    tls:
      existingSecretName: "${TLS_SECRET_NAME}"

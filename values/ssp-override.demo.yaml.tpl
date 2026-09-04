# ssp-override.yaml (demo / POC)  - rendered from .env
# Chart: ssp     Release: $RELEASENAME     Lab 6
ssp:
  deployment:
    size: ${SSP_DEPLOYMENT_SIZE}   # demo = 60 auth/min, single replica
  ingress:
    host: ${SSP_FQDN}
    type: gatewayapi               # Kubernetes Gateway API (edge routing)
    gatewayApi:
      createGateway: true          # let the chart create the Gateway
      gatewayClassName: ${GATEWAY_CLASS}
      skipWildcardListener: true
  featureFlags:
    aigateway:
      enabled: ${AIGATEWAY_ENABLED}  # central (in-platform) AI Gateway
    nats:
      enabled: ${NATS_ENABLED}       # NATS JetStream - required for observability
global:
  image:
    pullSecretNames:
    - ${REGISTRY_SECRET_NAME}
  observe:
    enabled: ${OBSERVE_ENABLED}      # AgentMinder observability pipeline
  otelAcceptExternalRequests:
    enabled: ${OTEL_ACCEPT_EXTERNAL} # accept external OTLP
opentelemetry-collector:
  imagePullSecrets:
    - name: ${REGISTRY_SECRET_NAME}
nats:
  config:
    cluster:
      enabled: false               # multi-node cluster disabled
      replicas: 1                  # single nats pod for demo
  global:
    image:
      pullSecretNames:
      - ${REGISTRY_SECRET_NAME}
hazelcast-enterprise:
  cluster:
    memberCount: 1                 # single Hazelcast member for demo
  image:
    imagePullSecrets:
    - name: ${REGISTRY_SECRET_NAME}

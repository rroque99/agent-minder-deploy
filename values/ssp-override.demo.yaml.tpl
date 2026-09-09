# ssp-override.yaml (demo / POC)  - rendered from .env
# Chart: ssp     Release: $RELEASENAME     Lab 6
#
# Pull secrets: every subchart defaults to its OWN secret name
# (ssp-hazelcast-registrypullsecret, ssp-otel-registrypullsecret,
# ssp-nats-registrypullsecret), so each must be pointed at ours separately -
# and each uses a different key and list format. Verify any change with:
#   helm template ssp <repo>/ssp -n <ns> -f .rendered/ssp-override.demo.yaml \
#     | grep -B25 imagePullSecrets
ssp:
  deployment:
    size: ${SSP_DEPLOYMENT_SIZE}   # demo = 60 auth/min, single replica
  ingress:
    host: ${SSP_FQDN}
    type: gatewayapi               # Kubernetes Gateway API (edge routing)
    gatewayApi:
      # Attach to the shared edge Gateway created in Lab 3 rather than making a
      # second one. That Gateway has a *.${DOMAIN} wildcard listener accepting
      # routes from any namespace, so the platform, sample app and enclave UIs
      # all share one external address.
      createGateway: false
      existingGateway: ${EDGE_GATEWAY_NAME}
      gatewayClassName: ${GATEWAY_CLASS}
    tls:
      secretName: ${TLS_SECRET_NAME}
  featureFlags:
    aigateway:
      enabled: ${AIGATEWAY_ENABLED}  # central (in-platform) AI Gateway
    nats:
      enabled: ${NATS_ENABLED}       # NATS JetStream - required for observability
  global:
    ssp:
      registry:
        # -- pull secrets for parent-chart pods: dataseed job, db-initializer,
        # and the platform services
        existingSecrets:
        - name: ${REGISTRY_SECRET_NAME}
global:
  # -- shared with subcharts (chart values ~line 318)
  imagePullSecrets:
    - name: ${REGISTRY_SECRET_NAME}
  observe:
    enabled: ${OBSERVE_ENABLED}      # AgentMinder observability pipeline
  otelAcceptExternalRequests:
    enabled: ${OTEL_ACCEPT_EXTERNAL} # accept external OTLP
opentelemetry-collector:
  imagePullSecrets:                  # takes `- name:` objects
    - name: ${REGISTRY_SECRET_NAME}
nats:
  config:
    cluster:
      enabled: false               # multi-node cluster disabled
      replicas: 1                  # single nats pod for demo
  global:
    image:
      pullSecretNames:             # NATS subchart key; bare strings
      - ${REGISTRY_SECRET_NAME}
hazelcast-enterprise:
  cluster:
    memberCount: 1                 # single Hazelcast member for demo
  image:
    pullSecrets:                   # NOT imagePullSecrets; bare strings
    - ${REGISTRY_SECRET_NAME}
  mancenter:
    image:
      pullSecrets:
      - ${REGISTRY_SECRET_NAME}

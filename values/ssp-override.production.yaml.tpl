# ssp-override.yaml (production)  - rendered from .env
# Chart: ssp     Release: $RELEASENAME     Lab 6
#
# Pair with CLICKHOUSE_ENABLED / an external database: set DB_* in .env and
# db.enabled=false on ssp-infra. See docs/database-connectivity.md.
global:
  # -- shared with subcharts (chart values ~line 318)
  imagePullSecrets:
    - name: ${REGISTRY_SECRET_NAME}
  imageRepositoryBase: "${IMAGE_REPOSITORY_BASE}"
  useImageDigest: ${USE_IMAGE_DIGEST}   # immutable image digests
  observe:
    enabled: ${OBSERVE_ENABLED}
  otelAcceptExternalRequests:
    enabled: ${OTEL_ACCEPT_EXTERNAL}
ssp:
  deployment:
    size: ${SSP_DEPLOYMENT_SIZE}        # small | medium | large
  db:
    type: ${DB_TYPE}                    # mysql | postgresql | oracle
    jdbcUrl: "${DB_JDBC_URL}"
    sslMode: ${DB_SSL_MODE}
    existingSecret: ${DB_SECRET}        # never inline plaintext in prod
  ingress:
    host: ${SSP_FQDN}
    type: gatewayapi
    gatewayApi:
      createGateway: false              # attach to an existing Gateway
      # defaults to the shared edge Gateway from Lab 3; override in .env
      existingGateway: ${EXISTING_GATEWAY}
      gatewayClassName: ${GATEWAY_CLASS}
    tls:
      secretName: ${TLS_SECRET_NAME}
    mtls:
      enabled: ${MTLS_ENABLED}          # true (+ caCertSecretName) for frontend mTLS
  featureFlags:
    aigateway: { enabled: ${AIGATEWAY_ENABLED} }
    nats:      { enabled: ${NATS_ENABLED} }
  keys:
    # Reuse the keys from a previous install of this release. Helm keeps
    # these secrets on uninstall on purpose: the MEK protects data already
    # encrypted in the database, and ClickHouse TLS trusts the ISK it was
    # provisioned with. Regenerating either orphans existing data.
    # Empty on a genuinely fresh install; 06-platform.sh detects and fills
    # these in automatically.
    isk:
      existingSecret: "${ISK_EXISTING_SECRET}"
    mek:
      existingSecret: "${MEK_EXISTING_SECRET}"
  global:
    ssp:
      registry:
        # -- pull secrets for parent-chart pods: dataseed job, db-initializer,
        # and the platform services
        existingSecrets:
        - name: ${REGISTRY_SECRET_NAME}
opentelemetry-collector:
  imagePullSecrets:                  # takes `- name:` objects
    - name: ${REGISTRY_SECRET_NAME}
nats:
  global:
    image:
      pullSecretNames:               # NATS subchart key; bare strings
      - ${REGISTRY_SECRET_NAME}
  natsBox:
    container:
      image:
        pullSecretNames:
          - ${REGISTRY_SECRET_NAME}
hazelcast-enterprise:
  image:
    pullSecrets:                     # NOT imagePullSecrets; bare strings
    - ${REGISTRY_SECRET_NAME}
  mancenter:
    image:
      pullSecrets:
      - ${REGISTRY_SECRET_NAME}

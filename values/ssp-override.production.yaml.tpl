# ssp-override.yaml (production)  - rendered from .env
# Chart: ssp     Release: $RELEASENAME     Lab 6
#
# Pair with CLICKHOUSE_ENABLED / an external database: set DB_* in .env and
# db.enabled=false on ssp-infra. See docs/database-connectivity.md.
global:
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
      createGateway: false              # attach to an existing enterprise Gateway
      existingGateway: ${EXISTING_GATEWAY}
      gatewayClassName: ${GATEWAY_CLASS}
    tls:
      secretName: ${TLS_SECRET_NAME}
    mtls:
      enabled: ${MTLS_ENABLED}          # true (+ caCertSecretName) for frontend mTLS
  featureFlags:
    aigateway: { enabled: ${AIGATEWAY_ENABLED} }
    nats:      { enabled: ${NATS_ENABLED} }
opentelemetry-collector:
  imagePullSecrets:
    - name: ${REGISTRY_SECRET_NAME}
nats:
  natsBox:
    container:
      image:
        pullSecretNames:
          - ${REGISTRY_SECRET_NAME}

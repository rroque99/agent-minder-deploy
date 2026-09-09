# ssp-sample-app-override.yaml (optional - Sample App & MCP Playground)
# rendered from .env     Chart: ssp-sample-app   Release: sample-$RELEASENAME   Lab 9
sspReleaseName: ${RELEASENAME}
featureFlags:
  sampleApp: { enabled: true }   # sample web application
  sampleMCP: { enabled: true }   # sample MCP server + MCP Playground
  sampleRP:  { enabled: true }   # sample resource provider
  sampleSPI: { enabled: true }   # sample SPI (SMS/email test wiring)
ingress:
  type: gatewayapi
  host: ${SAMPLE_APP_FQDN}
  gatewayApi:
    gatewayType: auto
    createGateway: false         # attach to the shared edge Gateway (Lab 3)
    existingGateway: ${EDGE_GATEWAY_NAME}
    gatewayClassName: ${GATEWAY_CLASS}
  tls:
    secretName: ${TLS_SECRET_NAME}
global:
  registry:
    existingSecrets:
    - name: ${REGISTRY_SECRET_NAME}

# MCP Playground - creates agents via GCP Vertex AI (prerequisite: a GCP project)
samplemcp:
  gcp:
    projectId: ${GCP_PROJECT_ID}
    region: ${GCP_REGION}
    credentialsSecretName: "${GCP_SA_KEY_SECRET}"   # "" to use Workload Identity

# ssp-infra-override.yaml  - rendered from .env, do not edit the rendered copy
# Chart: ssp-infra     Release: infra-$RELEASENAME     Lab 5
#
# NOTE: the printed guide lost a line break in this sample (a stray "global:"
# ran onto the clickhouse comment line, and fluent-bit's "global:" sat at
# column 0, which is invalid YAML). The structure below is the corrected form.
sspReleaseName: ${RELEASENAME}

clickhouse:
  enabled: ${CLICKHOUSE_ENABLED}    # required for AgentMinder observability

global:
  registry:
    existingSecrets:
    - name: ${REGISTRY_SECRET_NAME}

fluent-bit:
  global:
    registry:
      existingSecrets:
      - name: ${REGISTRY_SECRET_NAME}
  customConfig:               # build the Fluent Bit ConfigMap for log routing:
    outputs:
    - tags:
      - ssp_log
      - ssp_audit
      - ssp_tp_log
      # ${tag} below is a Fluent Bit placeholder, NOT one of ours - it is
      # excluded from ENVSUBST_VARS so rendering leaves it intact.
      template: |
        Name es
        Host  ${ELASTIC_HOST}
        Port  ${ELASTIC_PORT}
        tls   on
        tls.verify   off
        Suppress_Type_Name On
        Replace_Dots On
        Index ${tag}-%Y.%m.%d
        HTTP_User ${ELASTIC_USER}
        HTTP_Passwd ${ELASTIC_PASSWORD}

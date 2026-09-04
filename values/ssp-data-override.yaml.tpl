# ssp-data-override.yaml (risk data schema + risk/network data) - rendered from .env
# Chart: ssp-data     Release: data-$RELEASENAME     Lab 7
#
# ssp-data reuses the ssp chart's DB secret (ssp.db.existingSecret) - it does
# not create its own.
sspReleaseName: ${RELEASENAME}
ssp:
  global:
    ssp:
      registry:
        existingSecrets:
        - name: ${REGISTRY_SECRET_NAME}

# grafana-operator-values.yaml  (Enclave monitoring - Grafana)
# Chart: bitnami/grafana-operator --version=4.9.37   Namespace: monitoring
operator:
  image:
    repository: bitnamilegacy/grafana-operator
  containerSecurityContext:
    readOnlyRootFilesystem: true
grafana:
  image:
    repository: bitnamilegacy/grafana
  labels:
    dashboards: ssp-grafana            # datasource/dashboard CRs select this label
  config:
    security:
      admin_password: prom-operator    # change after first login

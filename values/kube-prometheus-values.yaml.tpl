# kube-prometheus-values.yaml  (Enclave monitoring - Prometheus)
# Chart: bitnami/kube-prometheus --version=11.3.10   Namespace: monitoring
global:
  security:
    allowInsecureImages: true          # allow the bitnamilegacy images below
prometheus:
  scrapeInterval: 1m
  evaluationInterval: 1m
  persistence:
    enabled: true                      # size the PV to your retention policy
  image:
    repository: bitnamilegacy/prometheus
alertmanager:
  persistence:
    enabled: true
  image:
    repository: bitnamilegacy/alertmanager
operator:
  image:
    repository: bitnamilegacy/prometheus-operator
blackboxExporter:
  image:
    repository: bitnamilegacy/blackbox-exporter
kube-state-metrics:
  image:
    registry: bitnamilegacy
    repository: kube-state-metrics
node-exporter:
  image:
    registry: bitnamilegacy
    repository: node-exporter

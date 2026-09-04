# Lab 4 - Kibana against the Elasticsearch above.
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: kibana
  namespace: logging
spec:
  version: ${ES_VERSION}
  count: 1
  elasticsearchRef:
    name: elasticsearch
  http:
    service:
      spec:
        type: ClusterIP
    tls:
      selfSignedCertificate:
        disabled: true             # terminate TLS at the Gateway (wildcard *.<DOMAIN>)
  podTemplate:
    spec:
      containers:
      - name: kibana
        resources:
          requests: { memory: 1Gi, cpu: 0.5 }
          limits:   { memory: 2Gi, cpu: 1 }

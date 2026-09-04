# Lab 4 - Elasticsearch (ECK) for platform log storage.
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
  namespace: logging
spec:
  version: ${ES_VERSION}
  nodeSets:
  - name: default
    count: ${ES_NODE_COUNT}          # demo: 1  |  production: 3
    config:
      node.roles: [ master, data ]
      node.store.allow_mmap: false
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests: { memory: 4Gi, cpu: 1 }
            limits:   { memory: 4Gi, cpu: 1 }
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: [ ReadWriteOnce ]
        resources:
          requests:
            storage: ${ES_STORAGE}
  volumeClaimDeletePolicy: DeleteOnScaledownOnly

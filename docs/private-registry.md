# Appendix — Using a Private Image Registry (optional / air-gapped)

Mirror the AgentMinder images into your own registry when you need air-gapped
installs, image scanning, or tighter control over image sources. Three steps:
pull from the Broadcom registry, push to your private registry, then deploy
pointing the charts at it.

## 1. Authenticate to the Broadcom image registry

The password is the registry access token from the Broadcom Support Portal.

```bash
docker login --username "<BROADCOM_REGISTRY_USERNAME>" \
  --password "<BROADCOM_REGISTRY_TOKEN>" \
  securityservices.packages.broadcom.com/agentminder-images
```

## 2. Pull the images

Platform services share a build tag, e.g. `4.1.0.1578`.

```bash
docker pull securityservices.packages.broadcom.com/agentminder-images/admin-svc:4.1.0.1578
```

Repeat for each service:

`authmgr`, `factors-svc`, `oidc-svc`, `opa`, `identity-svc`, `icf-svc`,
`ssprisk-svc`, `geolocation-svc`, `machineid-svc`, `ssprouter`, `proxysidecar`,
`authhub-adminconsole`, `authhub-signin`, `authhub-selfserviceconsole`,
`ssp-db-initializer`, `observe-ingestor`, `mcpserver-svc`, …

Two images carry their own tags:

```bash
docker pull securityservices.packages.broadcom.com/agentminder-images/hazelcast-enterprise:5.7.0-p3
docker pull securityservices.packages.broadcom.com/agentminder-images/network-data-loader:2026.26   # weekly release
```

## 3. Re-tag and push

Keep the same base path, names, and tags.

```bash
docker tag securityservices.packages.broadcom.com/agentminder-images/admin-svc:4.1.0.1578 \
  "<PRIVATE_REGISTRY>/securityservices.packages.broadcom.com/agentminder-images/admin-svc:4.1.0.1578"
docker push "<PRIVATE_REGISTRY>/securityservices.packages.broadcom.com/agentminder-images/admin-svc:4.1.0.1578"
```

## 4. Create an image pull secret in the install namespace

```bash
kubectl create secret docker-registry ssp-registry-creds \
  --docker-server="<PRIVATE_REGISTRY>" --docker-username="<REGISTRY_USER>" \
  --docker-password="<REGISTRY_TOKEN>" -n "${NAMESPACE}"
```

## 5. Deploy from your registry

Add to the `ssp-infra`, `ssp`, `ssp-data`, and `ssp-sample-app` installs:

```
--set ssp.global.ssp.registry.imageRepositoryBase="<PRIVATE_REGISTRY>/securityservices.packages.broadcom.com/agentminder-images/"
```

The `ssp` chart **only** also needs:

```
--set hazelcast-enterprise.image.repository="<PRIVATE_REGISTRY>/securityservices.packages.broadcom.com/agentminder-images/hazelcast-enterprise"
```

Reference the pull secret from each chart via its image-pull-secret values — for
example `opentelemetry-collector.imagePullSecrets` and
`nats.natsBox.container.image.pullSecretNames`, both already present in the
`ssp` override files in `values/`.

For the ECK operator in the `logging` namespace, create a docker-registry secret
there and set `LOGGING_PULL_SECRET=<secret-name>` before running
`scripts/04-enclave-services.sh`.

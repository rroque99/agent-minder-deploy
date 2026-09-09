# AgentMinder 4.1 — Deployment

Runnable companion to **AgentMinder · Technical Course 2 — Installation Lab
Guide** (`AgentMinder-deploymentguide.docx`). Everything here is transcribed
from that guide: the values-override files, the Kubernetes manifests, and one
script per lab.

**Scope: installation only.** These files stand up a working platform, retrieve
admin access, and optionally deploy the Sample App / MCP Playground and an
external AI Gateway. Object configuration (Part B), branding, and SMTP/SMS are
done in the Admin Console / REST API and are out of scope.

**Method.** `.env` is the only file you edit. Everything in `values/` is a
template (`*.yaml.tpl`) rendered from `.env` into `.rendered/` at install time
and passed to Helm with `-f`. Only the release name, `-n <namespace>`, the chart
reference, and `--timeout` stay on the command line.

> **Never edit `values/` or `.rendered/`.** `.rendered/` is regenerated on every
> run, so edits there are silently discarded. Environment-specific data belongs
> in `.env`; a template gets it via `${VAR}`.

> **Values discovered mid-deploy are written back to `.env` automatically.** The
> Elasticsearch password does not exist until Lab 4 creates the cluster, and the
> `ssp` chart names the Gateway it creates in Lab 6. The script that discovers
> each one persists it, so later scripts consume it with no manual step. See
> [Configuration model](#configuration-model).

**AgentMinder = platform + 2 flags.** The install follows the same steps as the
underlying platform, plus two observability feature flags. No extra packages or
infrastructure are required.

---

## Layout

```
.
├── README.md
├── .env.example              THE ONLY FILE YOU EDIT — copy to .env
├── .rendered/                generated; templates rendered from .env (gitignored)
├── values/                   chart values templates, rendered from .env
│   ├── kube-prometheus-values.yaml.tpl    enclave monitoring — Prometheus
│   ├── grafana-operator-values.yaml.tpl   enclave monitoring — Grafana
│   ├── ssp-infra-override.yaml.tpl        Lab 5 — database, ClickHouse, Fluent Bit
│   ├── ssp-override.demo.yaml.tpl         Lab 6 — platform (demo / POC)
│   ├── ssp-override.production.yaml.tpl   Lab 6 — platform (production)
│   ├── ssp-data-override.yaml.tpl         Lab 7 — risk data schema + risk/network data
│   ├── ssp-sample-app-override.yaml.tpl   Lab 9 — sample app & MCP Playground
│   └── ssp-aigateway-override.yaml.tpl    Lab 11 — external AI Gateway
├── manifests/                kubectl manifests (.tpl = rendered from .env)
│   ├── gatewayclass-eg.yaml               Lab 3
│   ├── gateway-edge.yaml.tpl              Lab 3 — the shared edge Gateway
│   ├── elasticsearch.yaml.tpl             Lab 4 — version/count/storage from .env
│   ├── kibana.yaml.tpl                    Lab 4
│   ├── grafana-datasource.yaml            Lab 4
│   ├── grafana-dashboard.yaml             Lab 4 — Grafana.com ID 25306
│   ├── httproute-kibana.yaml.tpl          Lab 4
│   └── httproute-grafana.yaml.tpl         Lab 4
├── scripts/
│   ├── lib/common.sh                     render, set_env, PSA, discovery helpers
│   ├── 00-preflight.sh                   prerequisite checks
│   ├── 02-namespace-and-repo.sh          Lab 2
│   ├── 03-gateway-api.sh                 Lab 3
│   ├── 04-enclave-services.sh            Lab 4
│   ├── 04b-enclave-routes.sh             Lab 4 — expose Kibana/Grafana
│   ├── 05-infra.sh                       Lab 5
│   ├── 06-platform.sh                    Lab 6
│   ├── 07-data.sh                        Lab 7
│   ├── 08-verify.sh                      Lab 8
│   ├── 09-sample-app.sh                  Lab 9 (optional)
│   ├── 10-admin-credentials.sh           Lab 10
│   ├── 11-aigateway.sh                   Lab 11 (optional)
│   ├── deploy-all.sh                     core path, Labs 2–8 + 10
│   └── 99-teardown.sh                    teardown
└── docs/
    ├── private-registry.md               appendix — private / air-gapped registry
    └── database-connectivity.md          appendix — production database
```

---

## Prerequisites

- A running Kubernetes cluster, and `kubectl` configured to reach it
  (`kubectl get nodes` works).
- Helm 3.x installed — **3.10 or above** (`helm version`).
- A Kubernetes Gateway API controller and a GatewayClass. Envoy Gateway is
  recommended; `scripts/03-gateway-api.sh` installs it. Also supported: AWS
  Load Balancer Controller (ALB), Avi Kubernetes Operator (AKO), GKE Gateway
  (L7), Azure Application Gateway for Containers.
- A database decision — demo uses the bundled database from `ssp-infra`;
  production uses an external MySQL / PostgreSQL / Oracle reachable from the
  cluster (see [docs/database-connectivity.md](docs/database-connectivity.md)).
- Access to the AgentMinder Helm chart repository and image registry, including
  an image pull secret (`$REGISTRY_SECRET_NAME`, created in Lab 2).
- A DNS name for the platform FQDN, and — in production — a TLS certificate.
- *Optional (external AI Gateway):* Admin Console access, to create an AI
  Gateway Group.
- *Optional (MCP Playground):* a GCP project with Vertex AI enabled, plus a
  service-account key or Workload Identity — the Playground creates agents via
  Vertex AI.

**Supported Kubernetes:** all active releases, and equivalent OpenShift.
Minimum **1.32.x**. Tested on GKE / EKS / AKS 1.32, 1.33, 1.34; OpenShift 4.18;
VKS (VCF/vSphere) v1.31.4+vmware.1-fips.

**Supported databases:** MySQL 8.0 / 8.4 (default) and Aurora MySQL 8.0;
PostgreSQL 14.19 / 15.14 / 17.7; Oracle 19c.

### Workstation requirements

The scripts run on **macOS and Linux**. They are written for bash 3.2, so
macOS' system `/bin/bash` works — no Homebrew bash needed.

| Tool | Needed by | If missing |
| --- | --- | --- |
| `kubectl`, `helm` | everything | — |
| `envsubst` | `04b-enclave-routes.sh` (renders the HTTPRoute templates) | macOS: `brew install gettext` · Debian/Ubuntu: `apt-get install gettext-base` · RHEL/Fedora: `dnf install gettext` |
| `curl` | `08-verify.sh` (OIDC discovery check) | preinstalled on macOS; `apt-get install curl` on a slim Linux image |
| `host` / `getent` / `nslookup` / `dig` | `00-preflight.sh` DNS check only | optional — preflight reports "cannot check DNS" and carries on |

`00-preflight.sh` checks for all of these and prints the right install command
for your platform. Stock Debian/Ubuntu images ship none of `envsubst`, `curl`,
or `host`, so on a minimal jump host install `gettext-base` and `curl` first.

**Demo-mode cluster minimum:** an autoscaling node pool of 5–6 nodes at 4 vCPU /
16 GB RAM each (GKE `n2d-standard-4`, EKS `t3.xlarge`, AKS / VKS
`Standard_D4s_v3`). In demo mode the enclave stack adds roughly 7 cores and
16 GB of RAM on top of the platform. For production sizing, use the interactive
sizing sheet on the "Sizing the Deployment" docs page.

---

## Quick start

```bash
cp .env.example .env
$EDITOR .env                     # the only file you edit

./scripts/00-preflight.sh        # verify prerequisites + render templates
./scripts/deploy-all.sh          # Labs 2–8 + 10, end to end
```

For a demo deployment you set **three things** in `.env`: `DOMAIN`, and your
Broadcom `BROADCOM_REGISTRY_USERNAME` / `BROADCOM_REGISTRY_TOKEN`. Everything
else has a working default, and `SSP_FQDN` is derived from `PREFIX` + `DOMAIN`.

`00-preflight.sh` validates `.env` for the selected profile, reports which
variables are filled in later by which lab, and renders every template the
profile uses — so an unresolved variable surfaces before any install starts.

`deploy-all.sh` runs the core path without stopping: Lab 4 captures the
Elasticsearch password into `.env` itself, so Lab 5 renders Fluent Bit with no
manual step. Every script uses `helm upgrade --install`, so re-running is safe
and always reflects the current `.env`.

Skips: `SKIP_GATEWAY=1` (a Gateway API controller already runs),
`SKIP_ENCLAVE=1` (you link IDSP to an existing observability stack).

To deploy production instead of demo, set `SSP_PROFILE=production` in `.env`,
along with the variables under its "Production only" heading.

---

## Configuration model

`.env` in, rendered YAML out. Nothing else is hand-maintained.

```
.env  ──►  values/*.yaml.tpl  ──envsubst──►  .rendered/*.yaml  ──►  helm -f
  ▲
  └── set_env: scripts write back what they discover
```

**Three kinds of value live in `.env`:**

| Kind | Examples | You set it? |
| --- | --- | --- |
| Environment facts | `DOMAIN`, registry credentials, `DB_HOST` | Yes — before you start |
| Tunables with defaults | `PSA_LEVEL`, `SSP_DEPLOYMENT_SIZE`, `ES_STORAGE`, feature flags | Only to change behavior |
| Discovered | `ELASTIC_PASSWORD`, `GATEWAY_NAME`, `GATEWAY_NAMESPACE`, `GRAFANA_SERVICE` | No — a script writes it back |

Several values are derived, so you set the input once: `SSP_FQDN` from `PREFIX` +
`DOMAIN`, `SAMPLE_APP_FQDN` and `AIGW_FQDN` from `DOMAIN`, and `DB_JDBC_URL` from
`DB_TYPE` / `DB_HOST` / `DB_PORT` / `DB_SCHEMA`.

### Write-back

`set_env VAR VALUE` rewrites the matching line in `.env` in place (appending if
absent) and exports it for the current run. It is idempotent — re-running a
script updates the line rather than adding another — and it `chmod 600`s `.env`,
which holds the Elasticsearch password once Lab 4 has run.

| Variable | Discovered by | Why it cannot be set up front |
| --- | --- | --- |
| `ELASTIC_PASSWORD` | Lab 4 | ECK generates it when Elasticsearch starts |
| `GATEWAY_NAME`, `GATEWAY_NAMESPACE` | Lab 4b | the `ssp` chart names the Gateway it creates in Lab 6 |
| `GRAFANA_SERVICE` | Lab 4b | depends on the Grafana operator's release name |

Set any of these yourself to pin them — a non-empty value is used as-is and
never overwritten by discovery. That is the path for using your own
Elasticsearch (`ELASTIC_HOST` / `ELASTIC_USER` / `ELASTIC_PASSWORD`) or a shared
edge Gateway.

### Rendering rules

- Templates are rendered with an **explicit** variable list (`ENVSUBST_VARS` in
  `scripts/lib/common.sh`). Unlisted `${...}` tokens are left untouched — which
  is what keeps Fluent Bit's `Index ${tag}-%Y.%m.%d` intact. A bare `envsubst`
  would blank it and silently break log indexing.
- After each render, unresolved `${VAR}` tokens and leftover `<placeholder>`
  markers are hard errors pointing back at `.env`.
- An *unset* variable renders to an empty string rather than staying `${VAR}`,
  so it is not caught by that check. Each script therefore declares what it
  needs with `require_env`, which is the authoritative gate. Adding a `${VAR}`
  to a template means adding it to `ENVSUBST_VARS` **and** to the consuming
  script's `require_env`.

### Adding a new setting

1. Add `export MY_VAR="default"` to `.env.example` under the right lab heading.
2. Add `${MY_VAR}` to `ENVSUBST_VARS` in `scripts/lib/common.sh`.
3. Reference `${MY_VAR}` in the relevant `values/*.yaml.tpl`.
4. Add it to `require_env` in the script that installs that chart.

---

## Networking: one shared edge Gateway

Every hostname is served by a **single** Gateway — one external IP, one TLS
certificate, one set of DNS records:

```
              edge-gateway  (ssp namespace, *.${DOMAIN} :443 + :80)
                     │  allowedRoutes.namespaces.from: All
     ┌───────────────┼────────────────┬──────────────────┐
 ssp/ssp-ssp-*   logging/kibana   monitoring/grafana   ssp/sample-app
 ssp.${DOMAIN}   kibana.${DOMAIN}  grafana.${DOMAIN}   sampleapp-*.${DOMAIN}
```

`03-gateway-api.sh` creates it, before any chart is installed, so the `ssp` and
`ssp-sample-app` charts attach with `createGateway: false` +
`existingGateway: $EDGE_GATEWAY_NAME` instead of each provisioning its own.

**Why it lives in `$NAMESPACE`, not `envoy-gateway-system`.** The `ssp` chart
creates its HTTPRoutes in its release namespace, so a Gateway there is
same-namespace for them and needs no cross-namespace support from the chart.
`from: All` then admits the enclave routes from `logging` and `monitoring`. The
TLS Secret must also sit beside the Gateway — a Gateway cannot reference a
Secret in another namespace without a `ReferenceGrant`.

**Why not the chart's own Gateway.** With `createGateway: true` the `ssp` chart
produces listeners that are `allowedRoutes.namespaces.from: Same` and whose
hostnames cover only the platform FQDN. Routes in `logging`/`monitoring` are
refused with `NotAllowedByListeners`, and patching that Gateway does not last —
the chart owns it, so the next `helm upgrade` reverts the change.

**TLS.** The wildcard listener wants a `*.$DOMAIN` certificate. If
`$TLS_SECRET_NAME` does not exist, Lab 3 generates a self-signed one
(`EDGE_TLS_SELF_SIGNED=true`). One wildcard cert covers every hostname, so there
is no SNI mismatch. Replace it with a CA-signed wildcard for production.

**DNS.** Point every hostname at the Gateway's address, which Lab 3 prints:

```bash
kubectl get gateway "$EDGE_GATEWAY_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.status.addresses[0].value}{"\n"}'
```

An address that never appears means the cluster has no load-balancer provider —
common on bare metal and on vSphere/VKS without NSX ALB. Install MetalLB, or
expose the Envoy service as a NodePort and point DNS at a node.

---

## Pod Security Admission

Every namespace these scripts create is labelled for Pod Security Admission
before any workload is deployed into it:

```bash
kubectl label --overwrite ns "<namespace>" \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged
```

| Namespace | Created by | Holds |
| --- | --- | --- |
| `$NAMESPACE` | `02-namespace-and-repo.sh` | the platform, infra, data, sample app, AI Gateway |
| `envoy-gateway-system` | `03-gateway-api.sh` | the Envoy Gateway controller |
| `logging` | `04-enclave-services.sh` | ECK operator, Elasticsearch, Kibana |
| `monitoring` | `04-enclave-services.sh` | Prometheus, Grafana |

All three modes are set, not just `enforce` — otherwise `audit` and `warn` keep
evaluating against the cluster default and emitting noise. The level comes from
`PSA_LEVEL` in `.env` (default `privileged`), and the shared
`ensure_namespace` helper in `scripts/lib/common.sh` applies it.

The platform's workloads (Hazelcast, ClickHouse, the proxy sidecars) need more
than a `restricted` profile allows. `privileged` is Kubernetes' built-in default
when a namespace carries no PSA labels, so on a stock cluster this is a no-op.
It earns its keep where a stricter cluster-wide default is in force — a
`PodSecurity` admission-configuration file, or a policy engine that stamps
namespace labels — and it documents what the workloads actually need.

Labelling happens *before* the workloads land, which is why `logging` and
`envoy-gateway-system` are created explicitly rather than by Helm's
`--create-namespace`. A pod admitted under one profile is not re-evaluated when
the namespace is relabelled later, so late labelling produces a namespace that
looks compliant while running pods that never passed the check.

**Tightening individual namespaces.** `privileged` across all four is the
permissive default, not a considered per-namespace judgement. The enclave and
gateway components are likelier to tolerate a stricter profile than the platform
itself — Envoy Gateway's controller is a plain Go deployment, and our
Elasticsearch manifest already sets `node.store.allow_mmap: false` partly to
reduce its privilege needs. `ensure_namespace` takes an optional second argument
for this:

```bash
ensure_namespace envoy-gateway-system baseline
ensure_namespace monitoring restricted
```

I have not verified which of these actually hold under a tighter profile, so
treat the above as a starting point to test, not a recommendation.

**OpenShift.** PSA labels alone may not be sufficient — SCC assignment governs
there as well, so check whether the service accounts need an SCC binding.

---

## The labs

### Lab 1 — Environment variables

`cp .env.example .env` and edit. These drive the release name, namespace, and
chart repo **only** — chart configuration lives in `values/`. Every script
sources `.env` automatically.

*Success:* `env | grep -E 'RELEASENAME|NAMESPACE|SSP_FQDN|HELM_REPO'` echoes
your values, and `echo "$SSP_FQDN"` resolves to `prefix.domain`.

*Troubleshooting:* if a new terminal loses the variables, `source .env` again.
Avoid spaces around the `=` sign.

### Lab 2 — Namespace, pull secret, Helm repository

```bash
./scripts/02-namespace-and-repo.sh
```

Creates the namespace, labels it for Pod Security Admission, creates the
`ssp-gcr-registry-creds` docker-registry secret from your Broadcom Support
Portal credentials, and registers the chart repo. The secret name must match the
`imagePullSecrets` referenced in the override files. Using a private or mirrored
registry instead? See [docs/private-registry.md](docs/private-registry.md).

Pod Security Admission labelling is covered in
[its own section](#pod-security-admission) — it applies to this namespace and to
the three the later labs create.

Pin a chart version by setting `AGENTMINDER_CHART_VERSION` in `.env`; otherwise
the latest is used.

*Success:* the namespace shows `Active` with `enforce=privileged`,
`helm repo list` includes `$HELM_REPO`, and `helm search repo "$HELM_REPO/ssp"`
lists the charts.

*Troubleshooting:* "repo not found" → `helm repo add` then `helm repo update`.
401/403 pulling charts → verify registry credentials. "namespace already
exists" is safe to ignore.

### Lab 3 — Gateway API controller (Envoy Gateway)

```bash
./scripts/03-gateway-api.sh
```

AgentMinder routes edge (north-south) traffic through the Kubernetes Gateway
API, so a controller must be running before the `ssp` chart. This creates and
[PSA-labels](#pod-security-admission) `envoy-gateway-system`, installs Envoy
Gateway, waits for it, and creates the `eg` GatewayClass.

Reference it from the platform override: `ssp.ingress.type: gatewayapi` and
`ssp.ingress.gatewayApi.gatewayClassName: eg` (chart-managed mode also sets
`createGateway: true`). If your platform already manages the Gateway API CRDs,
re-run with `SKIP_CRDS=1`.

> **mTLS:** choose Envoy Gateway when you need frontend mutual TLS. ALB does not
> support it, and GKE L7 and Azure AGC cannot forward client certificates.

*Success:* `kubectl get gatewayclass eg` reports `ACCEPTED=True`, the
`envoy-gateway` pod is `Running`, and `kubectl get crd | grep gateway` lists the
Gateway API CRDs.

*Troubleshooting:* GatewayClass not Accepted → the controller isn't ready;
re-run the `kubectl wait`. Timeout or Pending pod → confirm spare cluster
capacity.

### Lab 4 — Enclave services (observability & monitoring)

```bash
./scripts/04-enclave-services.sh
# later, once a Gateway exists:
./scripts/04b-enclave-routes.sh
```

Enclave services are IDSP's **platform** observability (Elasticsearch/Kibana for
logs) and monitoring (Prometheus/Grafana for metrics), and are required for a
supportable deployment. They are **distinct from** AgentMinder 4.1
Observability (ClickHouse/NATS/OpenTelemetry, which captures agentic runtime
telemetry) — both are needed, and one does not replace the other. If you already
run an enterprise observability stack, you may link IDSP to it instead.

The script creates and [PSA-labels](#pod-security-admission) the `logging` and
`monitoring` namespaces up front, then deploys into them.

The script reads the Elasticsearch `elastic` user password and writes it to
`.env` as `ELASTIC_PASSWORD`, so Lab 5 renders the Fluent Bit output block with
no manual step. Using your own Elasticsearch instead? Set `ELASTIC_HOST`,
`ELASTIC_PORT`, `ELASTIC_USER`, and `ELASTIC_PASSWORD` in `.env` and the
discovery is skipped.

`04b-enclave-routes.sh` attaches the `kibana.<DOMAIN>` and `grafana.<DOMAIN>`
HTTPRoutes to the shared edge Gateway. It needs only Lab 3 (the Gateway) and
Lab 4 (the services), so it runs immediately after Lab 4 — `deploy-all.sh`
includes it in sequence.

**It attaches to the shared edge Gateway** created in Lab 3 (see
[Networking](#networking-one-shared-edge-gateway)), whose `*.$DOMAIN` wildcard
listener accepts routes from any namespace. Override `GATEWAY_NAME` /
`GATEWAY_NAMESPACE` in `.env` to target a different Gateway; the script warns if
no listener on it accepts cross-namespace routes.

`GRAFANA_SERVICE` is discovered by finding the service in `monitoring` that
actually exposes `$GRAFANA_PORT` — matching on the name alone picks up siblings
like `-alerting`, which do not serve 3000 and make the route fail with
`PortNotFound`.

Then, in the UIs:

- **Kibana** (`https://kibana.<DOMAIN>`) → Data Views → Create data view.
  Index pattern `ssp_log*` (repeat for `ssp_audit*`, `ssp_tp_log*`), timestamp
  field `@timestamp`. Then use Discover.
- **Grafana** (`https://grafana.<DOMAIN>`) → sign in (`admin` /
  `prom-operator` — change it) → Dashboards → confirm the IDSP dashboard
  (25306). The **Enclave Services Health** dashboard reports the health of every
  enclave pod at the pod level; see the product docs' "Enclave Service Issues"
  section for troubleshooting.

Size the Elasticsearch and Prometheus persistent volumes to your retention
policy — for example 1 GB/day × 90 days = 90 GB.

*Success:* the ECK, Elasticsearch, Kibana, Prometheus, and Grafana pods are
`Running` in `logging` and `monitoring`; both HTTPRoutes report
`Accepted=True`; Kibana Discover shows `ssp_log` / `ssp_audit` / `ssp_tp_log`
entries; the Grafana dashboards populate.

*Troubleshooting:* Kibana shows no data → confirm the data view time field is
`@timestamp` and widen the date filter. Grafana FQDN unreachable → ensure
`grafana.<DOMAIN>` resolves and its HTTPRoute is Accepted. Elasticsearch pod
Pending → a PVC is unbound; check the storage class and PVC size against your
retention policy.

### Lab 5 — Infrastructure chart (`ssp-infra`)

```bash
./scripts/05-infra.sh
```

Creates the database, ClickHouse (for observability), and Fluent Bit, then waits
for the create-db job. Release: `infra-${RELEASENAME}`.

*Success:* the `ssp-infra-create-db-job` job shows `Complete`, and the database,
ClickHouse, and Fluent Bit pods are `Running`.

*Troubleshooting:* create-db-job stuck Pending → a PVC is unbound; check
`kubectl get pvc -n "$NAMESPACE"` and the storage class. Job Failed → inspect
the DB pod logs. External database → make sure the bundled DB is disabled and
`ssp.db.*` is set.

### Lab 6 — Platform chart (`ssp`)

```bash
./scripts/06-platform.sh
```

Installs the core platform from `values/ssp-override.${SSP_PROFILE}.yaml.tpl`. Demo
and production differ only by which file is used. Release: `${RELEASENAME}`.

> **Gateway-as-a-Service:** the in-platform (embedded) AI Gateway is enabled by
> `ssp.featureFlags.aigateway.enabled` — no separate chart needed. Deploy a
> separate external AI Gateway only for edge/standalone scenarios (Lab 11).

> **Observability:** `global.observe.enabled` + `ssp.featureFlags.nats.enabled`
> (`ssp`) and `clickhouse.enabled` (`ssp-infra`) turn on the observability
> pipeline. To disable later, set `global.observe.enabled=false` and
> `clickhouse.enabled=false`, then `helm upgrade`.

*Success:* `helm status "$RELEASENAME"` reports `deployed`, the `ssp` pods reach
READY/Running, and the Gateway and HTTPRoutes show Accepted.

*Troubleshooting:* `ImagePullBackOff` → check the image pull secret and
`global.imageRepositoryBase`. `CrashLoopBackOff` → usually DB
secret/connectivity. HTTPRoute not Accepted → `gatewayApi.gatewayClassName` must
match the GatewayClass from Lab 3.

### Lab 7 — Data chart (`ssp-data`)

```bash
./scripts/07-data.sh
```

The risk data loader. It creates the **risk-engine tables** (the risk data
schema) — not the platform schema, which `ssp-infra`'s create-db job created in
Lab 5 — and loads the **network / IP reference data** used by risk-based
authentication and geolocation. Deploy it whenever risk-based authentication or
geolocation is in scope. Release: `data-${RELEASENAME}`.

> **Same database:** `ssp-data` reuses the `ssp` chart's DB secret
> (`ssp.db.existingSecret`) — set it to the same secret name; the loader does not
> create its own.

*Success:* `kubectl get jobs -n "$NAMESPACE" | grep -i data` shows the
risk-data and network-data-loader jobs `Completed`.

*Troubleshooting:* job fails → it must reuse the `ssp` chart's DB secret. Loader
runs long → it loads large network data; increase `--timeout`. To re-run,
`helm uninstall` the data release first.

### Lab 8 — Verify

```bash
./scripts/08-verify.sh
```

Lists pods/services/events, flags anything not Running or Completed, then calls
the OIDC discovery endpoint:

```bash
curl --insecure \
  https://"${SSP_FQDN}"/default/.well-known/openid-configuration?sspinfo=true
```

*Success:* all pods READY (e.g. `1/1`) and Running with jobs Completed, and the
discovery curl returns JSON containing `issuer` and the OIDC endpoints.

*Troubleshooting:* curl SSL error → SSL settings on the ingress can need a
controller restart (`kubectl rollout restart deployment/envoy-gateway -n
envoy-gateway-system`, or `deployment ingress-nginx-controller -n ingress`),
then retry. HTTP 404 → the HTTPRoute host doesn't match `$SSP_FQDN`. Pods not
Ready → `kubectl describe pod` and read the Events.

### Lab 9 — Sample App & MCP Playground (optional)

```bash
GCP_SA_KEY_SECRET=my-gcp-key GCP_SA_KEY_FILE=./sa-key.json \
  ./scripts/09-sample-app.sh
```

Deploys a sample web application, a sample MCP server, a sample resource
provider, a sample SPI, and the MCP Playground for creating and running agents.
Use it to validate the platform and to have agents to protect in Course 3.
Release: `sample-${RELEASENAME}`.

*Prerequisite (MCP Playground):* the Playground creates agents via GCP Vertex
AI. You need a GCP project with Vertex AI enabled and a service-account key
(stored as a Kubernetes Secret) or Workload Identity; set
`samplemcp.gcp.projectId` / `region` / `credentialsSecretName` in the override.
If you are not on GCP, deploy the sample app and skip the Playground.

You get `sample-app` (web app), `sample-mcp` + `mcp-playground` (agent
creation), `sample-rp`, `sample-spi`. The Playground exposes an agent port range
(`samplemcp.playground.agentPortMax`, default 9600) and persists data on a PVC
(`samplemcp.persistence.size`).

*Troubleshooting:* not reachable → check the HTTPRoute host and that the release
deployed. This lab is optional — skip it if you are not demonstrating the sample
app.

### Lab 10 — Initial administrative credentials

```bash
./scripts/10-admin-credentials.sh
```

Deployment seeds four bootstrap credentials, **valid 48 hours**. The script
decodes the tenant admin login ID and password from
`${RELEASENAME}-ssp-secret-defaulttenantadminuser`.

> **48-hour window:** log in at `https://$SSP_FQDN` and create a durable admin
> identity within 48 hours; otherwise run the break-glass recovery. See
> *Configuring Administrative Access*.

*Troubleshooting:* secret not found → confirm the `$RELEASENAME` prefix and
namespace in the secret name. Login rejected → the 48-hour bootstrap window may
have expired; use break-glass recovery. Console unreachable → verify the
Gateway/HTTPRoute and DNS for `$SSP_FQDN`.

### Lab 11 — External AI Gateway (optional / advanced)

```bash
AIGW_CLIENT_ID=... AIGW_CLIENT_SECRET=... ./scripts/11-aigateway.sh
```

The Gateway-as-a-Service ships with the platform (Lab 6). Deploy a separate
external / standalone AI Gateway with the `ssp-aigateway` chart when you need a
gateway at the edge or in another cluster. It registers with AgentMinder as its
control plane on startup, then syncs its configuration. Release:
`aigw-${RELEASENAME}`.

Before you begin:

1. In the Admin Console → **AI Gateways**, create a **Gateway Group**. Record
   the group GUID — it becomes `aigateway.groupId` (the chart validates UUID
   format at render time).
2. From Gateway Group → General Settings → **Platform Client**, record the
   client ID and client secret. The script turns them into the
   `${RELEASENAME}-aigateway-credentials` Secret.
3. Identify the AgentMinder base URL for the target tenant, e.g.
   `https://idsp.example.com/<tenant>` — this drives `aigateway.idspBaseUrl`.

> **`idspBaseUrl` shorthand:** setting it auto-derives `control_plane.url`, the
> auth issuer + `jwks_url` (`<base>/oauth2/v1/jwks`), the authorization PDP
> (`<base>/access/v1/evaluation`), the OTLP endpoint (`<base>/otel`), and the
> token endpoint (`<base>/oauth2/v1/token`). Set those individually only if
> custom ingress splits the services.

After install the gateway registers, performs an initial config sync, and serves
traffic on its listener (HTTPS `:8090`, exposed as Service port 443).

> **Deployment-level settings:** listeners/ports and bootstrap credentials are
> read once at pod startup and cannot be changed by a control-plane config sync.
> Changing them (or rotating credentials) requires updating the values/Secret and
> running `helm upgrade` — or, for credentials only, updating the Secret in place
> and running
> `kubectl rollout restart deployment/<release>-ssp-aigateway -n <namespace>`.

> **TLS confinement:** all certificate/CA/key files (listener TLS or
> `configMounts`) must reside under `/etc/gateway/tls`, the gateway TLS
> confinement root, or the pod fails to start.

*Troubleshooting:* not registering → verify the control-plane URL and
credentials in the override. DPoP errors → start with an optional posture, then
harden to required.

---

## Teardown

```bash
./scripts/99-teardown.sh                       # uninstall releases
DELETE_NAMESPACE=1 ./scripts/99-teardown.sh    # also delete the namespace
TEARDOWN_ENCLAVE=1 ./scripts/99-teardown.sh    # also remove logging/monitoring
```

Uninstalls in reverse dependency order. **Cost & cleanup:** demo clusters cost
money while they run — tear down when you are done. If you created the cluster
solely for this course, delete the cluster itself (GKE/EKS/AKS/VKS) to stop all
charges.

> **Persistence:** database, ClickHouse, PVCs, secrets, and any externally
> managed Gateway persist beyond `helm uninstall` — clean them up deliberately.
> Deleting the namespace clears lingering PVCs and secrets.

*Success:* `kubectl get all,pvc,secret -n "$NAMESPACE"` returns nothing, or the
namespace no longer exists.

---

## Override files & releases at a glance

| Chart | Release name | Override file |
| --- | --- | --- |
| `ssp-infra` | `infra-${RELEASENAME}` | `ssp-infra-override.yaml.tpl` |
| `ssp` | `${RELEASENAME}` | `ssp-override.demo.yaml.tpl` \| `ssp-override.production.yaml.tpl` |
| `ssp-data` | `data-${RELEASENAME}` | `ssp-data-override.yaml.tpl` |
| `ssp-sample-app` (opt) | `sample-${RELEASENAME}` | `ssp-sample-app-override.yaml.tpl` |
| `ssp-aigateway` (opt) | `aigw-${RELEASENAME}` | `ssp-aigateway-override.yaml.tpl` |

---

## Transcription notes

- **`ssp-infra-override.yaml.tpl`** — the sample in the .docx lost a line break: a
  stray `global:` ran onto the end of the `clickhouse.enabled` comment line, and
  the Fluent Bit `global:` key sat at column 0 while its sibling `customConfig:`
  sat at two spaces, which is not valid YAML. The template
  carries the corrected structure (top-level `global.registry` for the shared
  pull secret, and `fluent-bit.global` + `fluent-bit.customConfig` nested under
  `fluent-bit`). Verify it against the current `ssp-infra` chart values
  reference before a production install.
- **`ssp-override.demo.yaml.tpl`** — the guide shows
  `gatewayClassName: <your-gatewayclass>`; this repo sets `eg` to match the
  GatewayClass created in Lab 3.
- **Enclave HTTPRoutes** — the guide's `<your-gateway>` / `<gateway-namespace>`
  / `<grafana-service>` placeholders became `.yaml.tpl` templates rendered by
  `envsubst`, since these are `kubectl` manifests rather than Helm values files.
  All three values are discovered from the cluster and written back to `.env`
  rather than hand-edited: the `ssp` chart names the Gateway it creates, so the
  guide's placeholder had no answer a reader could fill in ahead of time.
- **Lab 4 → Lab 5 ordering** — the guide applies the enclave HTTPRoutes inside
  Lab 4, but in demo mode the Gateway they attach to is created by the `ssp`
  chart in Lab 6. That step is split into `scripts/04b-enclave-routes.sh` so it
  can run after a Gateway exists.
- **Values files are templates, not hand-edited copies.** The guide says to
  "copy the sample YAML below into real files and edit the placeholders," and
  warns that `${SSP_FQDN}` is not expanded inside a values file. That warning is
  about Helm's behavior, not a bar on generating the file — so `values/` holds
  `*.yaml.tpl` rendered from `.env`, and `.env` is the only thing edited. The
  rendered output is what the guide describes; only the authoring step differs.
- The scripts use `helm upgrade --install` rather than `helm install`, so a
  re-run after a fix is idempotent.

---

## Source references

AgentMinder 4.1: Installing · Deploying the External AI Gateway with Helm ·
Configuring Kubernetes Gateway API for Ingress · Configuring Administrative
Access · chart configuration pages (`ssp`, `ssp-infra`, `ssp-data`,
`ssp-aigateway`, `ssp-sample-app`).

#!/usr/bin/env bash
# Lab 11 - Deploy an External / Standalone AI Gateway (optional, advanced).
#
# The Gateway-as-a-Service ships with the platform (Lab 6). Use this chart only
# when you need a gateway at the edge or in another cluster. It registers with
# AgentMinder as its control plane on startup, then syncs its configuration.
#
# Before you begin:
#   1. Admin Console -> AI Gateways -> create a Gateway Group. Record the group
#      GUID -> aigateway.groupId (the chart validates UUID format at render).
#   2. Gateway Group -> General Settings -> Platform Client: record the client
#      ID and client secret.
#   3. Provide them here so the credentials Secret can be created:
#        AIGW_CLIENT_ID=... AIGW_CLIENT_SECRET=... scripts/11-aigateway.sh
#   4. Identify the AgentMinder base URL for the target tenant, e.g.
#      https://idsp.example.com/<tenant> -> aigateway.idspBaseUrl
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl helm
require_env NAMESPACE RELEASENAME HELM_REPO

secret="${RELEASENAME}-aigateway-credentials"
if [[ -n "${AIGW_CLIENT_ID:-}" && -n "${AIGW_CLIENT_SECRET:-}" ]]; then
  step "Credentials secret ${secret}"
  kubectl create secret generic "${secret}" \
    --from-literal=clientId="${AIGW_CLIENT_ID}" \
    --from-literal=clientSecret="${AIGW_CLIENT_SECRET}" \
    -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  ok "applied"
else
  step "Credentials secret ${secret}"
  kubectl get secret "${secret}" -n "${NAMESPACE}" >/dev/null 2>&1 \
    || die "Secret not found. Re-run with AIGW_CLIENT_ID and AIGW_CLIENT_SECRET set."
  info "already exists - reusing"
fi
info "Reference it as aigateway.defaultCredentials.existingSecret: ${secret}"

step "helm install aigw-${RELEASENAME}"
helm_deploy "aigw-${RELEASENAME}" "${HELM_REPO}/ssp-aigateway" \
  "${VALUES_DIR}/ssp-aigateway-override.yaml" 120m

step "Registration and config sync"
kubectl get pods -n "${NAMESPACE}" | grep aigateway || warn "No aigateway pods yet"
kubectl logs -n "${NAMESPACE}" "deploy/aigw-${RELEASENAME}-ssp-aigateway" \
  2>/dev/null | grep -i "register\|sync" || \
  info "No register/sync lines yet - the pod may still be starting"

cat <<'NOTE'

    The gateway serves traffic on HTTPS :8090, exposed as Service port 443.

    Deployment-level settings: listeners/ports and bootstrap credentials are
    read once at pod startup and cannot be changed by a control-plane config
    sync. Changing them requires updating values and running helm upgrade. For
    credentials only, update the Secret in place and restart:
      kubectl rollout restart deployment/<release>-ssp-aigateway -n <namespace>

    TLS confinement: every certificate/CA/key file (listener TLS or
    configMounts) must live under /etc/gateway/tls, the gateway TLS confinement
    root, or the pod fails to start.

    Not registering? Verify the control-plane URL and credentials in the
    override. For DPoP errors, start with an optional posture and then harden
    to required.
NOTE

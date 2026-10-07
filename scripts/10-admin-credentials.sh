#!/usr/bin/env bash
# Lab 10 - Retrieve initial administrative credentials.
#
# Deployment seeds four bootstrap credentials, valid for 48 HOURS. Log in and
# create a durable admin identity inside that window, or you will need the
# break-glass recovery procedure (see Configuring Administrative Access).
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl base64
require_env NAMESPACE RELEASENAME SSP_FQDN TENANT ADMIN_CONSOLE_PATH

step "Bootstrap secrets in ${NAMESPACE}"
kubectl get secret -n "${NAMESPACE}" | grep ssp-secret || \
  die "No ssp-secret-* secrets found. Check the RELEASENAME prefix and namespace."

secret="${RELEASENAME}-ssp-secret-defaulttenantadminuser"
step "Tenant admin user (${secret})"
login="$(kubectl get secret "${secret}" -n "${NAMESPACE}" \
  -o jsonpath="{.data.userLoginId}" | base64 --decode)"
password="$(kubectl get secret "${secret}" -n "${NAMESPACE}" \
  -o jsonpath="{.data.userPassword}" | base64 --decode)"
[[ -n "$login" && -n "$password" ]] || die "Secret found but empty - check the secret name"

printf '    login:    %s\n' "$login"
printf '    password: %s\n' "$password"

step "Admin Console URL"
# The UIs are tenant-scoped and live under /<tenant>/ui/v1/<component>/. Do NOT
# link straight to .../signin/ - that is the redirect target of an authorization
# request and fails with "Application with the given id does not exist" when
# opened directly, because there is no client_id to resolve. Enter through the
# console's own path so it starts the OIDC flow itself.
#
# Hostnames are read from the platform HTTPRoutes rather than assumed: the chart
# provisions both a runtime and a mgmt- router, and the guide documents neither.
hosts="$(kubectl get httproute -n "${NAMESPACE}" \
  -o jsonpath='{range .items[*]}{range .spec.hostnames[*]}{.}{"\n"}{end}{end}' \
  2>/dev/null | grep -v '^$' | sort -u || true)"
[[ -n "${hosts}" ]] || hosts="${SSP_FQDN}"

for h in ${hosts}; do
  printf '    https://%s/%s%s\n' "$h" "${TENANT}" "${ADMIN_CONSOLE_PATH}"
done
info "(try the mgmt- host first if there is more than one)"
info "Self-service console: /${TENANT}/ui/v1/selfserviceconsole/"

warn "These bootstrap credentials expire 48 hours after deployment."
warn "Sign in now and create a durable admin identity."

#!/usr/bin/env bash
# Lab 10 - Retrieve initial administrative credentials.
#
# Deployment seeds four bootstrap credentials, valid for 48 HOURS. Log in and
# create a durable admin identity inside that window, or you will need the
# break-glass recovery procedure (see Configuring Administrative Access).
source "$(dirname "$0")/lib/common.sh"
load_env
require_cmd kubectl base64
require_env NAMESPACE RELEASENAME SSP_FQDN

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
printf '    console:  https://%s\n' "${SSP_FQDN}"

warn "These bootstrap credentials expire 48 hours after deployment."
warn "Sign in now and create a durable admin identity."

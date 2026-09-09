#!/usr/bin/env bash
# Run the core deployment path end to end: Labs 2-8.
#
# Optional labs are not included -- run them yourself:
#   scripts/09-sample-app.sh        Sample App & MCP Playground
#   scripts/11-aigateway.sh         external / standalone AI Gateway
#
#   SKIP_GATEWAY=1  skip Lab 3 (a Gateway API controller already runs)
#   SKIP_ENCLAVE=1  skip Lab 4 (you link IDSP to an existing stack)
source "$(dirname "$0")/lib/common.sh"
load_env

HERE="$(cd "$(dirname "$0")" && pwd)"

run() {
  local script="$1"
  printf '\n%s%s\n=== %s\n%s%s\n' "$_B" "$(printf '=%.0s' {1..70})" "$script" "$(printf '=%.0s' {1..70})" "$_0"
  "${HERE}/${script}"
}

run 00-preflight.sh
run 02-namespace-and-repo.sh
[[ "${SKIP_GATEWAY:-}" == "1" ]] || run 03-gateway-api.sh
[[ "${SKIP_ENCLAVE:-}" == "1" ]] || run 04-enclave-services.sh
# 04b only needs the Gateway (Lab 3) and the enclave services (Lab 4), so it
# runs here rather than being deferred - the shared edge Gateway already exists.
[[ "${SKIP_ENCLAVE:-}" == "1" ]] || run 04b-enclave-routes.sh

# Lab 4 writes ELASTIC_PASSWORD into .env itself, so no manual step is needed.
# Re-read it here in case a sub-script updated the file after we sourced it.
load_env
if [[ -z "${ELASTIC_PASSWORD:-}" ]]; then
  warn "ELASTIC_PASSWORD is empty - Fluent Bit cannot ship logs without it."
  if [[ "${SKIP_ENCLAVE:-}" == "1" ]]; then
    die "With SKIP_ENCLAVE=1, set ELASTIC_PASSWORD (and ELASTIC_HOST/ELASTIC_USER) in .env for your own Elasticsearch."
  fi
  die "Lab 4 should have set it. Re-run scripts/04-enclave-services.sh."
fi
ok "ELASTIC_PASSWORD present (captured by Lab 4)"

run 05-infra.sh
run 06-platform.sh
run 07-data.sh
run 08-verify.sh
run 10-admin-credentials.sh

step "Core deployment complete"
info "Admin Console: https://${SSP_FQDN}  (bootstrap credentials expire in 48h)"
info "Next: the optional labs - scripts/09-sample-app.sh and scripts/11-aigateway.sh."

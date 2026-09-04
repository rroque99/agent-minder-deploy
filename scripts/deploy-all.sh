#!/usr/bin/env bash
# Run the core deployment path end to end: Labs 2-8.
#
# Optional labs are not included -- run them yourself:
#   scripts/04b-enclave-routes.sh   expose Kibana/Grafana (needs a Gateway)
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

# Fluent Bit needs Elasticsearch credentials before Lab 5 can install. Lab 4
# prints them; with SKIP_ENCLAVE=1 they come from your own Elasticsearch.
if grep -q '<elastic_password>' "${VALUES_DIR}/ssp-infra-override.yaml"; then
  warn "values/ssp-infra-override.yaml still contains <elastic_password>."
  if [[ "${SKIP_ENCLAVE:-}" == "1" ]]; then
    warn "Put your existing Elasticsearch credentials in the fluent-bit"
    warn "customConfig block (HTTP_User / HTTP_Passwd, and the Host line),"
    warn "then re-run this script."
  else
    warn "Paste the Elasticsearch password printed above into the fluent-bit"
    warn "customConfig HTTP_Passwd field, then re-run this script."
  fi
  die  "Stopping before Lab 5."
fi

run 05-infra.sh
run 06-platform.sh
run 07-data.sh
run 08-verify.sh
run 10-admin-credentials.sh

step "Core deployment complete"
info "Admin Console: https://${SSP_FQDN}  (bootstrap credentials expire in 48h)"
info "Next: scripts/04b-enclave-routes.sh, then the optional labs 9 and 11."

#!/usr/bin/env bash
# Shared helpers for the AgentMinder deployment scripts.
# Sourced, not executed.

set -euo pipefail

# ${BASH_SOURCE[0]:-$0} so `set -u` does not trip when this file is sourced
# from an interactive shell, where BASH_SOURCE is unset.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
VALUES_DIR="${ROOT_DIR}/values"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
RENDERED_DIR="${ROOT_DIR}/.rendered"
ENV_FILE="${ROOT_DIR}/.env"

# Every variable the templates may reference. envsubst is given this list
# explicitly so that unrelated ${...} tokens survive rendering - Fluent Bit's
# `Index ${tag}-%Y.%m.%d` is a Fluent Bit variable, not one of ours, and a bare
# `envsubst` would silently blank it.
ENVSUBST_VARS='
${NAMESPACE} ${RELEASENAME} ${SSP_FQDN} ${DOMAIN} ${PREFIX}
${REGISTRY_SECRET_NAME} ${IMAGE_REPOSITORY_BASE}
${GATEWAY_CLASS} ${GATEWAY_NAME} ${GATEWAY_NAMESPACE} ${EXISTING_GATEWAY}
${TLS_SECRET_NAME} ${MTLS_ENABLED}
${SSP_DEPLOYMENT_SIZE} ${OBSERVE_ENABLED} ${AIGATEWAY_ENABLED} ${NATS_ENABLED}
${CLICKHOUSE_ENABLED} ${OTEL_ACCEPT_EXTERNAL}
${ELASTIC_HOST} ${ELASTIC_PORT} ${ELASTIC_USER} ${ELASTIC_PASSWORD}
${DB_TYPE} ${DB_HOST} ${DB_PORT} ${DB_SCHEMA} ${DB_USER} ${DB_SECRET}
${DB_SSL_MODE} ${DB_JDBC_URL} ${USE_IMAGE_DIGEST}
${SAMPLE_APP_FQDN} ${GCP_PROJECT_ID} ${GCP_REGION} ${GCP_SA_KEY_SECRET}
${AIGW_FQDN} ${AIGW_GROUP_ID} ${AIGW_SCOPES} ${IDSP_BASE_URL}
${AIGW_CREDENTIALS_SECRET} ${AIGW_TLS_SELF_SIGNED}
${ES_VERSION} ${ES_NODE_COUNT} ${ES_STORAGE} ${GRAFANA_SERVICE}
'

# --- output ------------------------------------------------------------------
if [[ -t 1 ]]; then
  _B=$'\033[1m'; _G=$'\033[32m'; _Y=$'\033[33m'; _R=$'\033[31m'; _0=$'\033[0m'
else
  _B=''; _G=''; _Y=''; _R=''; _0=''
fi
step() { printf '\n%s==> %s%s\n' "$_B" "$*" "$_0"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '%s  ok%s %s\n' "$_G" "$_0" "$*"; }
warn() { printf '%s  !!%s %s\n' "$_Y" "$_0" "$*" >&2; }
die()  { printf '%s  xx%s %s\n' "$_R" "$_0" "$*" >&2; exit 1; }

# --- environment -------------------------------------------------------------
load_env() {
  if [[ -f "${ROOT_DIR}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/.env"
  elif [[ -z "${NAMESPACE:-}" ]]; then
    die "No .env found and no environment exported. Run: cp .env.example .env && \$EDITOR .env"
  fi
}

require_env() {
  local missing=()
  local v
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || missing+=("$v")
  done
  (( ${#missing[@]} == 0 )) || \
    die "Unset in .env: ${missing[*]}  - set them in ${ENV_FILE#"${ROOT_DIR}"/} and re-run."
}

# set_env VAR VALUE
#
# Persist a value discovered at runtime into .env, then export it, so later
# scripts pick it up without anyone hand-editing a file. Used for values that
# cannot exist before a step runs: the Elasticsearch password (Lab 4) and the
# Gateway the ssp chart creates (Lab 6).
#
# Rewrites via a temp file rather than `sed -i`, whose syntax differs between
# GNU and BSD.
set_env() {
  local var="$1" val="$2" tmp
  [[ -n "$var" ]] || die "set_env: missing variable name"

  export "${var}=${val}"

  if [[ ! -f "${ENV_FILE}" ]]; then
    warn "No .env to update - ${var} is exported for this run only."
    return 0
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/env.XXXXXX")" || die "set_env: mktemp failed"
  # Preserve the file's own permissions; .env holds secrets.
  awk -v v="$var" -v val="$val" '
    BEGIN { done = 0 }
    # match `export VAR=...` or `VAR=...`, commented-out or not
    $0 ~ "^[[:space:]]*#?[[:space:]]*(export[[:space:]]+)?" v "=" {
      if (!done) { print "export " v "=\"" val "\""; done = 1 }
      next
    }
    { print }
    END { if (!done) { print ""; print "# added by set_env"; print "export " v "=\"" val "\"" } }
  ' "${ENV_FILE}" > "$tmp" || { rm -f "$tmp"; die "set_env: failed to rewrite .env"; }

  cat "$tmp" > "${ENV_FILE}" && rm -f "$tmp"
  chmod 600 "${ENV_FILE}" 2>/dev/null || true
  ok "${var} saved to .env"
}

# render_values <basename>   values/<basename>.yaml.tpl -> .rendered/<basename>.yaml
# Echoes the rendered path.
render_values() {
  local name="$1"
  local tpl="${VALUES_DIR}/${name}.yaml.tpl"
  local out="${RENDERED_DIR}/${name}.yaml"
  [[ -f "$tpl" ]] || die "Template not found: ${tpl}"
  mkdir -p "${RENDERED_DIR}"
  envsubst "${ENVSUBST_VARS}" < "$tpl" > "$out"
  validate_rendered "$out" "$name"
  printf '%s' "$out"
}

# Catch anything the render left unresolved, and point at .env rather than at
# the generated file - editing the rendered copy would be overwritten silently.
validate_rendered() {
  local out="$1" name="$2" unresolved placeholders
  # Note: an unset variable renders to an empty string rather than being left
  # as ${VAR}, so it is NOT caught here. Each script guards the variables it
  # actually needs with require_env - that is the authoritative check.
  # Tokens that are deliberately NOT ours and must survive rendering. Filtered
  # with grep -vF: in a BSD grep BRE, the '$' in '${tag}' is read as an anchor,
  # so a plain `grep -v '${tag}'` matches nothing and the exclusion silently
  # fails on macOS while working on GNU grep.
  unresolved="$(grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$out" \
    | grep -vF '${tag}' || true)"
  placeholders="$(grep -nE '^[^#]*<[A-Za-z0-9_.-]+>' "$out" || true)"

  if [[ -n "$unresolved" ]]; then
    warn "${name}: variables left unresolved after render:"
    printf '%s\n' "$unresolved" | sed 's/^/       /' >&2
    die "Add them to .env (they are not in ENVSUBST_VARS, or are unset)."
  fi
  if [[ -n "$placeholders" ]]; then
    warn "${name}: <placeholder> still present after render:"
    printf '%s\n' "$placeholders" | sed 's/^/       /' >&2
    die "This is a template bug - the value should come from .env."
  fi
  return 0
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "Required command not found on PATH: $c"
  done
}

# --- dns ---------------------------------------------------------------------
# resolves <fqdn>  ->  0 = resolves, 1 = does not, 2 = no tool to check with
#
# 'host' ships with macOS but not with a stock Debian/Ubuntu or a slim container
# image; 'getent' is present wherever glibc is. Try both rather than reporting
# "does not resolve" when the real problem is a missing lookup tool.
#
# Each branch returns 0/1 explicitly: the underlying tools use their own exit
# codes (getent returns 2 for "not found"), which would otherwise collide with
# the 2 = "cannot check" sentinel.
#
# Call it in a condition context - a bare `resolves foo` would trip `set -e`:
#     rc=0; resolves "$fqdn" || rc=$?
resolves() {
  local fqdn="$1"
  if command -v host >/dev/null 2>&1; then
    host "$fqdn" >/dev/null 2>&1 && return 0 || return 1
  elif command -v getent >/dev/null 2>&1; then
    getent hosts "$fqdn" >/dev/null 2>&1 && return 0 || return 1
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$fqdn" >/dev/null 2>&1 && return 0 || return 1
  elif command -v dig >/dev/null 2>&1; then
    [[ -n "$(dig +short "$fqdn" 2>/dev/null)" ]] && return 0 || return 1
  fi
  return 2
}

# Package hint for a missing tool, per platform.
install_hint() {
  case "$(uname -s)" in
    Darwin) printf 'brew install %s' "$1" ;;
    Linux)  printf 'apt-get install -y %s   (or: dnf install -y %s)' "$2" "$2" ;;
    *)      printf 'install %s' "$1" ;;
  esac
}

# --- namespaces --------------------------------------------------------------
# ensure_namespace <name> [psa-level]
#
# Create the namespace if it does not exist, then stamp the Pod Security
# Admission labels on it. Always label *before* any workload lands, so pods are
# never admitted under one profile and then re-evaluated under another.
#
# 'privileged' is Kubernetes' built-in default when a namespace carries no PSA
# labels, so on a stock cluster this is a no-op. It earns its keep where a
# stricter cluster-wide default is in force (a PodSecurity admission config, or
# a policy engine that stamps namespace labels), and it documents what the
# workloads actually need.
#
# Pass a second argument to hold one namespace to a tighter profile than the
# global PSA_LEVEL, e.g. ensure_namespace monitoring restricted
ensure_namespace() {
  local ns="$1" level="${2:-${PSA_LEVEL:-privileged}}"
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    info "namespace ${ns} already exists"
  else
    kubectl create ns "$ns" >/dev/null
    ok "namespace ${ns} created"
  fi
  kubectl label --overwrite ns "$ns" \
    "pod-security.kubernetes.io/enforce=${level}" \
    "pod-security.kubernetes.io/audit=${level}" \
    "pod-security.kubernetes.io/warn=${level}" >/dev/null
  ok "PSA enforce/audit/warn=${level} on ${ns}"
  [[ "$level" == "privileged" ]] || \
    warn "PSA level '${level}' on ${ns} is stricter than privileged - pods may be rejected."
}

# --- helm --------------------------------------------------------------------
# Adds --version only when AGENTMINDER_CHART_VERSION is set.
chart_version_args() {
  if [[ -n "${AGENTMINDER_CHART_VERSION:-}" ]]; then
    printf '%s' "--version=${AGENTMINDER_CHART_VERSION}"
  fi
}

# helm_deploy <release> <chart> <values-basename> [timeout]
#
# Renders values/<basename>.yaml.tpl from .env, then installs or upgrades - so
# re-running any script is safe and always reflects the current .env.
helm_deploy() {
  local release="$1" chart="$2" name="$3" timeout="${4:-120m}"
  local valuesfile; valuesfile="$(render_values "$name")"
  info "rendered ${name}.yaml.tpl -> ${valuesfile#"${ROOT_DIR}"/}"
  local -a args=(upgrade --install "$release" "$chart"
                 -n "$NAMESPACE" -f "$valuesfile" "--timeout=${timeout}")
  local vflag; vflag="$(chart_version_args)"
  [[ -n "$vflag" ]] && args+=("$vflag")
  info "helm ${args[*]}"
  helm "${args[@]}"
}

# render <template> -> stdout   (for manifests/*.yaml.tpl)
render() {
  local tpl="$1"
  [[ -f "$tpl" ]] || die "Template not found: $tpl"
  envsubst "${ENVSUBST_VARS}" < "$tpl"
}

#!/usr/bin/env bash
# Shared helpers for the AgentMinder deployment scripts.
# Sourced, not executed.

set -euo pipefail

# ${BASH_SOURCE[0]:-$0} so `set -u` does not trip when this file is sourced
# from an interactive shell, where BASH_SOURCE is unset.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
VALUES_DIR="${ROOT_DIR}/values"
MANIFESTS_DIR="${ROOT_DIR}/manifests"

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
  (( ${#missing[@]} == 0 )) || die "Unset required variable(s): ${missing[*]}"
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

# --- placeholder guard -------------------------------------------------------
# The guide is explicit: shell variables are NOT expanded inside values files.
# So every <placeholder> must be edited by hand before install. Catch the ones
# that were missed instead of letting Helm render a broken release.
check_placeholders() {
  local f="$1" hits
  [[ -f "$f" ]] || die "Values file not found: $f"
  # Ignore comment-only lines; flag <...> markers in actual values.
  hits="$(grep -nE '^[^#]*<[A-Za-z0-9_.-]+>' "$f" || true)"
  if [[ -n "$hits" ]]; then
    warn "Unedited placeholders in $(basename "$f"):"
    printf '%s\n' "$hits" | sed 's/^/       /' >&2
    if [[ "${SKIP_PLACEHOLDER_CHECK:-}" == "1" ]]; then
      warn "SKIP_PLACEHOLDER_CHECK=1 -- continuing anyway."
    else
      die "Edit the file, or re-run with SKIP_PLACEHOLDER_CHECK=1 to override."
    fi
  fi
}

# --- helm --------------------------------------------------------------------
# Adds --version only when AGENTMINDER_CHART_VERSION is set.
chart_version_args() {
  if [[ -n "${AGENTMINDER_CHART_VERSION:-}" ]]; then
    printf '%s' "--version=${AGENTMINDER_CHART_VERSION}"
  fi
}

# Install or upgrade, so re-running a script is safe.
helm_deploy() {
  local release="$1" chart="$2" valuesfile="$3" timeout="${4:-120m}"
  check_placeholders "$valuesfile"
  local -a args=(upgrade --install "$release" "$chart"
                 -n "$NAMESPACE" -f "$valuesfile" "--timeout=${timeout}")
  local vflag; vflag="$(chart_version_args)"
  [[ -n "$vflag" ]] && args+=("$vflag")
  info "helm ${args[*]}"
  helm "${args[@]}"
}

render() { # render <template> -> stdout
  local tpl="$1"
  [[ -f "$tpl" ]] || die "Template not found: $tpl"
  envsubst < "$tpl"
}

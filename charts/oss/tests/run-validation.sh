#!/usr/bin/env bash
# =============================================================
# Validation tests for charts/opensource-services
# =============================================================
# Usage:
#   ./tests/run-validation.sh                 (from chart root)
#   cd charts/opensource-services && ./tests/run-validation.sh
#
# Requires: helm (v3+)
# Returns exit code 0 if all tests pass, 1 if any fail.
# =============================================================

set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_VALS="${CHART_DIR}/tests/values"
PASS=0
FAIL=0

# ---- helpers ------------------------------------------------

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET='\033[0m'

pass() { echo -e "  ${GREEN}✓${RESET} $*"; ((PASS++)) || true; }
fail() { echo -e "  ${RED}✗${RESET} $*"; ((FAIL++)) || true; }
header() { echo -e "\n${YELLOW}▸ $*${RESET}"; }

# Render a test values file and return stdout.
render() {
  helm template test-release "${CHART_DIR}" \
    --values "${TEST_VALS}/$1" 2>&1
}

# Assert that output contains a string.
assert_contains() {
  local output="$1" needle="$2" label="$3"
  if printf '%s\n' "${output}" | grep -q "${needle}"; then
    pass "${label}"
  else
    fail "${label}"
    echo "         expected to find: ${needle}"
  fi
}

# Assert that output does NOT contain a string.
assert_not_contains() {
  local output="$1" needle="$2" label="$3"
  if ! printf '%s\n' "${output}" | grep -q "${needle}"; then
    pass "${label}"
  else
    fail "${label}"
    echo "         expected NOT to find: ${needle}"
  fi
}

# Assert rendering succeeds (no helm error).
assert_valid_yaml() {
  local file="$1"
  if helm template test-release "${CHART_DIR}" \
      --values "${TEST_VALS}/${file}" > /dev/null 2>&1; then
    pass "renders without errors"
  else
    fail "helm template returned an error"
    render "${file}" | head -20 || true
  fi
}

# ---- tests --------------------------------------------------

# ------------------------------------------------------------------
header "TEST 01 – Minimal: convention value-file path auto-generated"
# ------------------------------------------------------------------
OUT=$(render "01-minimal.yaml")
assert_valid_yaml "01-minimal.yaml"
assert_contains "${OUT}" \
  "repoURL: https://valkey.io/valkey-helm/" \
  "chart source uses the correct helm repoURL"
assert_contains "${OUT}" \
  "chart: valkey" \
  "chart name is set"
assert_contains "${OUT}" \
  "\$values/clusters/test-cluster/test/values/valkey/valkey-values.yaml" \
  "convention value-file path is auto-generated"
assert_contains "${OUT}" \
  "ref: values" \
  "values-ref source is auto-injected"
assert_not_contains "${OUT}" \
  "clusters/test-cluster/test/values/valkey/valkey-addons" \
  "no extra path source is emitted when extraPath is not set"

# ------------------------------------------------------------------
header "TEST 02 – extraPath: third source emitted only when set"
# ------------------------------------------------------------------
OUT=$(render "02-extra-path.yaml")
assert_valid_yaml "02-extra-path.yaml"
assert_contains "${OUT}" \
  "chart: kube-prometheus-stack" \
  "chart source present"
assert_contains "${OUT}" \
  "ref: values" \
  "values-ref source auto-injected"
assert_contains "${OUT}" \
  "path: clusters/test-cluster/test/values/kps-addons" \
  "extraPath source is emitted with correct path"
# Verify the extraPath uses the global repoURL
assert_contains "${OUT}" \
  "repoURL: https://github.com/example/repo.git" \
  "extraPath source reuses the global repoURL"

# ------------------------------------------------------------------
header "TEST 03 – extraSources: custom source appended after standard ones"
# ------------------------------------------------------------------
OUT=$(render "03-extra-sources.yaml")
assert_valid_yaml "03-extra-sources.yaml"
assert_contains "${OUT}" \
  "chart: loki" \
  "chart source present"
assert_contains "${OUT}" \
  "ref: values" \
  "values-ref source auto-injected"
assert_contains "${OUT}" \
  "repoURL: https://github.com/example/loki-extras.git" \
  "extraSources custom repoURL is emitted"
assert_contains "${OUT}" \
  "path: overlays/test-cluster" \
  "extraSources path is emitted"

# ------------------------------------------------------------------
header "TEST 04 – extraValueFiles: added to chart source"
# ------------------------------------------------------------------
OUT=$(render "04-extra-value-files.yaml")
assert_valid_yaml "04-extra-value-files.yaml"
assert_contains "${OUT}" \
  "\$values/clusters/test-cluster/test/values/opensource-services/tempo-values.yaml" \
  "convention value-file still present"
assert_contains "${OUT}" \
  "tempo-secrets.yaml" \
  "extra value file appended"

# ------------------------------------------------------------------
header "TEST 05 – Escape hatch: fully custom sources list"
# ------------------------------------------------------------------
OUT=$(render "05-escape-hatch-sources.yaml")
assert_valid_yaml "05-escape-hatch-sources.yaml"
assert_contains "${OUT}" \
  "vault-override.yaml" \
  "second custom value file from escape-hatch present"
# When using the escape hatch the values-ref source is NOT auto-injected
# (the user wrote their own ref source manually at the end of the list).
# Verify the comment block from auto-generation is absent.
assert_not_contains "${OUT}" \
  "auto-assembled sources" \
  "auto-generation comment is absent in escape-hatch mode"
assert_contains "${OUT}" \
  "MutatingWebhookConfiguration" \
  "ignoreDifferences block is rendered"

# ------------------------------------------------------------------
header "TEST 06 – Chart version override + explicit valueFiles"
# ------------------------------------------------------------------
OUT=$(render "06-chart-version-override.yaml")
assert_valid_yaml "06-chart-version-override.yaml"
assert_contains "${OUT}" \
  "targetRevision: 2026.3.0" \
  "overridden chart version is used"
assert_contains "${OUT}" \
  "authentik-ldap.yaml" \
  "explicit extra value file (ldap) is present"
assert_contains "${OUT}" \
  "authentik-values.yaml" \
  "first explicit value file is present"
# When valueFiles is set explicitly, the string 'convention path' should not appear
# (i.e. no extra duplicate of the same file from auto-generation side effects)
assert_not_contains "${OUT}" \
  "opensource-services.defaultValuesFile" \
  "no raw helper name leaks into rendered output"

# ------------------------------------------------------------------
header "TEST 07 – Legacy single source (path-based app)"
# ------------------------------------------------------------------
OUT=$(render "07-legacy-source.yaml")
assert_valid_yaml "07-legacy-source.yaml"
assert_contains "${OUT}" \
  "path: clusters/test-cluster/test/my-plain-app" \
  "legacy source path is rendered"
assert_contains "${OUT}" \
  "recurse: true" \
  "directory.recurse is rendered"
assert_not_contains "${OUT}" \
  "sources:" \
  "legacy mode uses singular 'source:', not 'sources:'"

# ------------------------------------------------------------------
header "TEST 08 – Real cluster values: Internals/dev"
# ------------------------------------------------------------------
CLUSTER_VALS="${CHART_DIR}/../../clusters/Internals/dev/values/opensource-services-values.yaml"
CLUSTER_TMPFILE=$(mktemp /tmp/oss-test08.XXXXXX)
if helm template test-release "${CHART_DIR}" \
    --values "${CLUSTER_VALS}" > "${CLUSTER_TMPFILE}" 2>&1; then
  pass "Internals/dev cluster values render without errors"
  grep -q "name: loki"       "${CLUSTER_TMPFILE}" \
    && pass "loki Application object present"       || fail "loki Application object present"
  grep -q "name: authentik"  "${CLUSTER_TMPFILE}" \
    && pass "authentik Application object present"  || fail "authentik Application object present"
  grep -q "name: uptime-kuma" "${CLUSTER_TMPFILE}" \
    && pass "uptime-kuma Application object present" || fail "uptime-kuma Application object present"
  ! grep -q "name: mimir"    "${CLUSTER_TMPFILE}" \
    && pass "mimir is disabled and not rendered"    || fail "mimir is disabled and not rendered"
else
  fail "Internals/dev cluster values failed to render"
  head -30 "${CLUSTER_TMPFILE}" || true
fi
rm -f "${CLUSTER_TMPFILE}"

# ------------------------------------------------------------------
header "TEST 09 – Fan-out: instances generate one Application per entry"
# ------------------------------------------------------------------
OUT=$(helm template test-release "${CHART_DIR}" \
  --set "apps.cnpg-clusters.enabled=true" \
  --set "apps.cnpg-clusters.localChart.path=charts/cnpg-cluster" \
  --set "apps.cnpg-clusters.valuesDir=cnpg" \
  --set "apps.cnpg-clusters.syncWave=11" \
  --set "apps.cnpg-clusters.syncOptions[0]=CreateNamespace=true" \
  --set "apps.cnpg-clusters.instances[0].name=test-db-a" \
  --set "apps.cnpg-clusters.instances[0].namespace=ns-a" \
  --set "apps.cnpg-clusters.instances[1].name=test-db-b" \
  --set "apps.cnpg-clusters.instances[1].namespace=ns-b" \
  --set "apps.cnpg-clusters.instances[1].syncWave=20" \
  2>&1)
if echo "${OUT}" | helm template test-release "${CHART_DIR}" \
  --set "apps.cnpg-clusters.enabled=true" > /dev/null 2>&1 || [[ "${OUT}" != *"Error:"* ]]; then
  pass "fan-out renders without errors"
else
  fail "fan-out helm template returned an error: ${OUT}"
fi
assert_contains "${OUT}" \
  "name: test-db-a" \
  "first instance Application name is rendered"
assert_contains "${OUT}" \
  "namespace: ns-a" \
  "first instance namespace is rendered"
assert_contains "${OUT}" \
  "name: test-db-b" \
  "second instance Application name is rendered"
assert_contains "${OUT}" \
  "namespace: ns-b" \
  "second instance namespace is rendered"
assert_contains "${OUT}" \
  "sync-wave: \"20\"" \
  "per-instance syncWave override is applied"
assert_contains "${OUT}" \
  "values/cnpg/test-db-a-values.yaml" \
  "first instance uses convention value-file path with valuesDir"
assert_contains "${OUT}" \
  "values/cnpg/test-db-b-values.yaml" \
  "second instance uses convention value-file path with valuesDir"
assert_contains "${OUT}" \
  "path: charts/cnpg-cluster" \
  "local chart path is rendered"
# Disabled instance must be skipped
OUT_DISABLED=$(helm template test-release "${CHART_DIR}" \
  --set "apps.cnpg-clusters.enabled=true" \
  --set "apps.cnpg-clusters.localChart.path=charts/cnpg-cluster" \
  --set "apps.cnpg-clusters.valuesDir=cnpg" \
  --set "apps.cnpg-clusters.instances[0].name=skip-db" \
  --set "apps.cnpg-clusters.instances[0].namespace=skip-ns" \
  --set "apps.cnpg-clusters.instances[0].enabled=false" \
  2>&1)
assert_not_contains "${OUT_DISABLED}" \
  "name: skip-db" \
  "instance with enabled:false is not rendered"

# ---- summary ------------------------------------------------

echo ""
echo "============================================="
if [[ ${FAIL} -eq 0 ]]; then
  echo -e "${GREEN}ALL ${PASS} TESTS PASSED${RESET}"
  echo "============================================="
  exit 0
else
  echo -e "${RED}${FAIL} TEST(S) FAILED, ${PASS} PASSED${RESET}"
  echo "============================================="
  exit 1
fi

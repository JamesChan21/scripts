#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/v2ray-reality/update-sni.sh"

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq "$expected" "$file"; then
    echo "Expected ${file} to contain: ${expected}" >&2
    echo "--- ${file} ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

make_config() {
  local path="$1"
  cat > "${path}" <<'JSON'
{
  "inbounds": [
    {
      "port": 12345,
      "streamSettings": {
        "security": "reality",
        "realitySettings": {
          "dest": "www.python.org:443",
          "serverNames": ["www.python.org"],
          "privateKey": "keep-private-key",
          "shortIds": ["keep-short-id"]
        }
      }
    }
  ]
}
JSON
}

test_manual_update_keeps_reality_secrets() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  make_config "${tmpdir}/config.json"

  mkdir -p "${tmpdir}/bin"
  cat > "${tmpdir}/bin/systemctl" <<'SH'
#!/usr/bin/env bash
echo "$@" >> "${SYSTEMCTL_LOG}"
SH
  chmod +x "${tmpdir}/bin/systemctl"

  PATH="${tmpdir}/bin:${PATH}" \
    XRAY_CONFIG_PATH="${tmpdir}/config.json" \
    SYSTEMCTL_LOG="${tmpdir}/systemctl.log" \
    bash "${SCRIPT}" www.microsoft.com > "${tmpdir}/output.txt"

  assert_contains "${tmpdir}/config.json" '"dest": "www.microsoft.com:443"'
  assert_contains "${tmpdir}/config.json" '"serverNames": ['
  assert_contains "${tmpdir}/config.json" '"www.microsoft.com"'
  assert_contains "${tmpdir}/config.json" '"privateKey": "keep-private-key"'
  assert_contains "${tmpdir}/config.json" '"shortIds": ['
  assert_contains "${tmpdir}/config.json" '"keep-short-id"'
  assert_contains "${tmpdir}/systemctl.log" 'restart xray'
  assert_contains "${tmpdir}/output.txt" '客户端 servername / sni 请改成：www.microsoft.com'
}

test_auto_update_selects_best_successful_sni() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  make_config "${tmpdir}/config.json"

  mkdir -p "${tmpdir}/bin"
  cat > "${tmpdir}/bin/systemctl" <<'SH'
#!/usr/bin/env bash
echo "$@" >> "${SYSTEMCTL_LOG}"
SH
  cat > "${tmpdir}/bin/curl" <<'SH'
#!/usr/bin/env bash
url="${@: -1}"
case "${url}" in
  https://www.microsoft.com) printf '0.050000 0.120000 0.200000 200\n' ;;
  https://www.apple.com) printf '0.040000 0.080000 0.110000 200\n' ;;
  *) printf '0.000000 0.000000 0.000000 000\n'; exit 28 ;;
esac
SH
  chmod +x "${tmpdir}/bin/systemctl" "${tmpdir}/bin/curl"

  PATH="${tmpdir}/bin:${PATH}" \
    XRAY_CONFIG_PATH="${tmpdir}/config.json" \
    SYSTEMCTL_LOG="${tmpdir}/systemctl.log" \
    SNI_CANDIDATES="www.microsoft.com www.apple.com" \
    SNI_TEST_RUNS=2 \
    bash "${SCRIPT}" > "${tmpdir}/output.txt"

  assert_contains "${tmpdir}/config.json" '"dest": "www.apple.com:443"'
  assert_contains "${tmpdir}/config.json" '"www.apple.com"'
  assert_contains "${tmpdir}/output.txt" '已选择 Reality 目标站：www.apple.com'
  assert_contains "${tmpdir}/output.txt" '客户端 servername / sni 请改成：www.apple.com'
}

test_manual_update_keeps_reality_secrets
test_auto_update_selects_best_successful_sni

echo "update-sni tests passed"

#!/usr/bin/env bash
# 手动更新 Xray Reality 的服务端 SNI / serverName。
# 用法：
#   bash update-sni.sh                  # 自动测速选择
#   bash update-sni.sh www.microsoft.com # 手动指定目标站

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

DEFAULT_CONFIG_PATH="/usr/local/etc/xray/config.json"
CONFIG_PATH="${XRAY_CONFIG_PATH:-${DEFAULT_CONFIG_PATH}}"
TEST_RUNS="${SNI_TEST_RUNS:-3}"
CANDIDATES="${SNI_CANDIDATES:-www.microsoft.com www.apple.com www.amazon.com www.cloudflare.com www.yahoo.com www.samsung.com www.ibm.com www.oracle.com www.intel.com www.amd.com www.nvidia.com www.bing.com www.github.com www.paypal.com www.adobe.com www.cisco.com www.mozilla.org www.cloudflarestatus.com www.skype.com www.live.com}"

die() {
  echo -e "${RED}错误: $*${NC}" >&2
  exit 1
}

is_domain() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

float_less() {
  awk -v left="$1" -v right="$2" 'BEGIN { exit !(left < right) }'
}

float_greater() {
  awk -v left="$1" -v right="$2" 'BEGIN { exit !(left > right) }'
}

average() {
  awk -v sum="$1" -v count="$2" 'BEGIN {
    if (count == 0) {
      printf "9999.000000"
    } else {
      printf "%.6f", sum / count
    }
  }'
}

check_ready() {
  if [[ "${CONFIG_PATH}" == "${DEFAULT_CONFIG_PATH}" && "${EUID}" -ne 0 ]]; then
    die "请使用 root 权限运行此脚本"
  fi

  [[ -f "${CONFIG_PATH}" ]] || die "找不到 Xray 配置文件: ${CONFIG_PATH}"
  command -v curl >/dev/null 2>&1 || die "缺少 curl，请先安装 curl"
  command -v python3 >/dev/null 2>&1 || die "缺少 python3，无法安全修改 JSON 配置"
  [[ "${TEST_RUNS}" =~ ^[0-9]+$ && "${TEST_RUNS}" -gt 0 ]] || die "SNI_TEST_RUNS 必须是正整数"
}

measure_domain() {
  local domain="$1"
  local success=0
  local total_sum=0
  local tls_sum=0
  local i result connect_time tls_time total_time http_code

  for ((i = 1; i <= TEST_RUNS; i++)); do
    if result="$(curl -o /dev/null -sS --tlsv1.3 --connect-timeout 3 -m 6 \
      -w "%{time_connect} %{time_appconnect} %{time_total} %{http_code}\n" \
      "https://${domain}" 2>/dev/null)"; then
      read -r connect_time tls_time total_time http_code <<< "${result}"
      if [[ "${http_code}" != "000" ]] && float_greater "${tls_time}" "0"; then
        success=$((success + 1))
        total_sum="$(awk -v left="${total_sum}" -v right="${total_time}" 'BEGIN { printf "%.6f", left + right }')"
        tls_sum="$(awk -v left="${tls_sum}" -v right="${tls_time}" 'BEGIN { printf "%.6f", left + right }')"
      fi
    fi
  done

  printf '%s %s %s\n' "${success}" "$(average "${tls_sum}" "${success}")" "$(average "${total_sum}" "${success}")"
}

choose_best_sni() {
  local best_domain=""
  local best_success=-1
  local best_tls=9999
  local best_total=9999
  local domain stats success avg_tls avg_total

  echo "正在从候选域名中选择 Reality 目标站..."
  for domain in ${CANDIDATES}; do
    if ! is_domain "${domain}"; then
      echo -e "  - ${domain}: ${YELLOW}跳过，域名格式无效${NC}"
      continue
    fi

    read -r success avg_tls avg_total <<< "$(measure_domain "${domain}")"
    echo "  - ${domain}: 成功 ${success}/${TEST_RUNS}, tls=${avg_tls}s, total=${avg_total}s"

    if [[ "${success}" -gt "${best_success}" ]] ||
      [[ "${success}" -eq "${best_success}" && "$(float_less "${avg_total}" "${best_total}"; echo $?)" -eq 0 ]]; then
      best_domain="${domain}"
      best_success="${success}"
      best_tls="${avg_tls}"
      best_total="${avg_total}"
    fi
  done

  [[ -n "${best_domain}" && "${best_success}" -gt 0 ]] || die "所有候选域名都测试失败，未修改配置"
  echo -e "${YELLOW}已选择 Reality 目标站：${best_domain} (成功 ${best_success}/${TEST_RUNS}, tls=${best_tls}s, total=${best_total}s)${NC}"
  SELECTED_SNI="${best_domain}"
}

update_config() {
  local domain="$1"
  local backup_path
  local tmp_path

  backup_path="${CONFIG_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
  tmp_path="${CONFIG_PATH}.tmp.$$"

  cp "${CONFIG_PATH}" "${backup_path}"

  python3 - "${CONFIG_PATH}" "${tmp_path}" "${domain}" <<'PY'
import json
import sys

config_path, tmp_path, domain = sys.argv[1:]

with open(config_path, "r", encoding="utf-8") as handle:
    config = json.load(handle)

updated = False
for inbound in config.get("inbounds", []):
    stream_settings = inbound.get("streamSettings", {})
    if stream_settings.get("security") != "reality":
        continue

    reality_settings = stream_settings.get("realitySettings")
    if not isinstance(reality_settings, dict):
        continue

    reality_settings["dest"] = f"{domain}:443"
    reality_settings["serverNames"] = [domain]
    updated = True

if not updated:
    raise SystemExit("未找到 streamSettings.security = reality 的入站配置")

with open(tmp_path, "w", encoding="utf-8") as handle:
    json.dump(config, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

  mv "${tmp_path}" "${CONFIG_PATH}"
  echo "已备份原配置：${backup_path}"
}

restart_xray() {
  systemctl restart xray
}

main() {
  local selected_sni="${1:-}"

  check_ready

  if [[ -n "${selected_sni}" ]]; then
    is_domain "${selected_sni}" || die "手动指定的域名格式无效: ${selected_sni}"
    echo -e "${YELLOW}使用手动指定 Reality 目标站：${selected_sni}${NC}"
  else
    choose_best_sni
    selected_sni="${SELECTED_SNI}"
  fi

  update_config "${selected_sni}"
  restart_xray

  echo -e "${GREEN}服务端 Reality SNI 已更新完成。${NC}"
  echo -e "${YELLOW}客户端 servername / sni 请改成：${selected_sni}${NC}"
  echo "注意：客户端只改 servername/sni，UUID、端口、Public Key、Short ID 不要改。"
}

main "$@"

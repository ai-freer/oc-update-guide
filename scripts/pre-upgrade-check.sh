#!/usr/bin/env bash
#
# pre-upgrade-check.sh — OpenClaw 升级前自动检查脚本
#
# 用法：
#   bash scripts/pre-upgrade-check.sh [target_version]
#
# 示例：
#   bash scripts/pre-upgrade-check.sh 2026.3.28
#   bash scripts/pre-upgrade-check.sh              # 仅检查，不指定版本

set -euo pipefail

TOOL="openclaw"
TARGET_VERSION="${1:-}"
HAS_BLOCKERS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[⚠]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*"; }

echo "=============================="
echo " 升级前检查: ${TOOL}"
echo "=============================="
echo ""

# 0. Dreaming 窗口距离检查 (2026-06-26 事故防御)
# ---------------------------------------------
# Nightly dreaming 在 ~03:00 GMT+8 触发，窗口 02:00-04:00。
# gateway/node restart 撞窗口 → boot 期间 dreaming 静默跳过 → 当日 deep/light/rem 全 0。
# 2026-06-26 doubao 就是这么丢的（PSA msg 8844）。
# 规则：当前时间或预期完成时间在 02:00-04:00 GMT+8 内 → BLOCK。
echo "--- Dreaming 窗口检查 (GMT+8) ---"
# epoch-based: 计算"现在"到下一个 02:00 GMT+8 的秒数
NOW_EPOCH=$(date +%s)
# 今天 02:00 GMT+8 的 epoch
TODAY_0200_EPOCH=$(TZ=Asia/Shanghai date -d "today 02:00" +%s)
TODAY_0400_EPOCH=$(TZ=Asia/Shanghai date -d "today 04:00" +%s)
TOMORROW_0200_EPOCH=$(TZ=Asia/Shanghai date -d "tomorrow 02:00" +%s)

DREAM_HHMM_NOW=$(TZ=Asia/Shanghai date +%H:%M)

# 当前是否在 [02:00, 04:00) 窗口内
if (( NOW_EPOCH >= TODAY_0200_EPOCH && NOW_EPOCH < TODAY_0400_EPOCH )); then
  err "当前时间 ${DREAM_HHMM_NOW} GMT+8 处于 dreaming 窗口 (02:00-04:00)"
  err "升级会重启 gateway，撞 dreaming 触发 → 当日记忆丢失"
  err "请等到 04:00 GMT+8 之后再升级"
  HAS_BLOCKERS=1
else
  # 计算到下一个 02:00 的秒数
  if (( NOW_EPOCH < TODAY_0200_EPOCH )); then
    NEXT_WINDOW=$TODAY_0200_EPOCH
  else
    NEXT_WINDOW=$TOMORROW_0200_EPOCH
  fi
  SEC_TO_WINDOW=$(( NEXT_WINDOW - NOW_EPOCH ))
  MIN_TO_WINDOW=$(( SEC_TO_WINDOW / 60 ))
  HM_TO_WINDOW=$(printf "%dh%02dm" $((MIN_TO_WINDOW/60)) $((MIN_TO_WINDOW%60)))

  if (( SEC_TO_WINDOW < 3600 )); then
    err "当前 ${DREAM_HHMM_NOW} GMT+8，距 02:00 dreaming 窗口仅 ${HM_TO_WINDOW}"
    err "升级 + npm pack + restart 通常 > 30min，极易撞窗口"
    err "请等到 04:00 GMT+8 之后再升级，或推迟到次日"
    HAS_BLOCKERS=1
  elif (( SEC_TO_WINDOW < 7200 )); then
    warn "当前 ${DREAM_HHMM_NOW} GMT+8，距 02:00 dreaming 窗口 ${HM_TO_WINDOW}"
    warn "确保升级在 02:00 前完成，或推迟到 04:00 之后"
  else
    info "当前 ${DREAM_HHMM_NOW} GMT+8，距 02:00 dreaming 窗口 ${HM_TO_WINDOW}（安全）"
  fi
fi

if [[ -x /usr/local/bin/openclaw-safe-restart ]]; then
  info "openclaw-safe-restart wrapper 已安装（运行时二次防御生效）"
else
  warn "openclaw-safe-restart wrapper 未安装；建议先装：见 workspace-lisa/TOOLS.md"
fi
echo ""

# 1. 当前版本
echo "--- 当前版本 ---"
if command -v "${TOOL}" &>/dev/null; then
  CURRENT=$("${TOOL}" --version 2>/dev/null || echo "unknown")
  info "已安装: ${TOOL} ${CURRENT}"
else
  err "${TOOL} 未找到"
  exit 1
fi

NPM_INFO=$(npm list -g "${TOOL}" 2>/dev/null || true)
if [[ -n "${NPM_INFO}" ]]; then
  info "npm 全局: $(echo "${NPM_INFO}" | grep "${TOOL}" | head -1)"
fi
echo ""

# 2. 安装路径
echo "--- 安装路径 ---"
INSTALL_PATH=$(npm root -g 2>/dev/null)/"${TOOL}"
if [[ -d "${INSTALL_PATH}" ]]; then
  info "安装路径: ${INSTALL_PATH}"
else
  warn "安装路径不存在: ${INSTALL_PATH}"
fi
echo ""

# 3. 配置文件
echo "--- 配置文件 ---"
CONFIG_DIR="${HOME}/.${TOOL}"
if [[ -d "${CONFIG_DIR}" ]]; then
  info "配置目录: ${CONFIG_DIR}"
  LATEST_BACKUP=$(ls -t "${CONFIG_DIR}"/*.bak.* 2>/dev/null | head -1 || true)
  if [[ -n "${LATEST_BACKUP}" ]]; then
    info "最近备份: ${LATEST_BACKUP}"
  else
    warn "未找到配置备份"
  fi
else
  warn "配置目录不存在: ${CONFIG_DIR}"
fi
echo ""

# 4. Patch 检查
echo "--- Patch 状态 ---"
PATCH_SCRIPT="${CONFIG_DIR}/workspace/patches/apply-patches.sh"
if [[ -f "${PATCH_SCRIPT}" ]]; then
  info "Patch 入口: ${PATCH_SCRIPT}"
  PATCH_COUNT=$(grep -c "patch\|sed\|replace" "${PATCH_SCRIPT}" 2>/dev/null || echo "0")
  info "Patch 操作数（启发式估算，非精确值）: ${PATCH_COUNT}"
else
  PATCH_SCRIPT="${HOME}/.${TOOL}/workspace-*/patches/apply-patches.sh"
  FOUND=$(ls ${PATCH_SCRIPT} 2>/dev/null | head -1 || true)
  if [[ -n "${FOUND}" ]]; then
    info "Patch 入口: ${FOUND}"
  else
    warn "未找到 patch 脚本"
  fi
fi
echo ""

# 5. 服务状态
echo "--- 服务状态 ---"
# 服务名探测：兼容 root 安装 (openclaw-gateway-root.service) 和 user 安装
SERVICE=""
if systemctl is-active "${TOOL}-gateway-root.service" &>/dev/null 2>&1; then
  SERVICE="${TOOL}-gateway-root.service"
elif systemctl --user is-active "${TOOL}-gateway.service" &>/dev/null 2>&1; then
  SERVICE="${TOOL}-gateway.service"
fi

if [[ -n "${SERVICE}" ]]; then
  info "${SERVICE} 正在运行"
else
  FOUND=$(systemctl list-units --all 2>/dev/null | grep -o "${TOOL}-gateway[a-z-]*[.]service" | head -1 || true)
  if [[ -n "${FOUND}" ]]; then
    if systemctl is-active "${FOUND}" &>/dev/null 2>&1; then
      info "${FOUND} 正在运行"
    else
      warn "${FOUND} 已加载但未运行"
    fi
  else
    warn "未找到 ${TOOL}-gateway(-root).service"
  fi
fi
echo ""

# 6. Changelog 检查
echo "--- Changelog ---"
CHANGELOG="${INSTALL_PATH}/CHANGELOG.md"
if [[ -f "${CHANGELOG}" ]]; then
  info "Changelog: ${CHANGELOG}"
  LINE_COUNT=$(wc -l < "${CHANGELOG}")
  info "总行数: ${LINE_COUNT}"
  if [[ -n "${TARGET_VERSION}" ]]; then
    MENTIONS=$(grep -c "${TARGET_VERSION}" "${CHANGELOG}" 2>/dev/null || echo "0")
    if [[ "${MENTIONS}" -gt 0 ]]; then
      info "目标版本 ${TARGET_VERSION} 在 changelog 中有 ${MENTIONS} 处提及"
    else
      warn "目标版本 ${TARGET_VERSION} 未在本地 changelog 中找到（可能需先查看 GitHub）"
    fi
  fi
else
  warn "本地 changelog 未找到"
fi
echo ""

# 7. 磁盘空间
echo "--- 磁盘空间 ---"
if [[ -d "${INSTALL_PATH}" ]]; then
  AVAIL=$(df -BG "${INSTALL_PATH}" 2>/dev/null | tail -1 | awk '{gsub(/G/, "", $4); print $4}')
  info "可用空间: ${AVAIL}G"
  if (( ${AVAIL:-0} < 10 )); then
    err "磁盘空间不足 10G（当前 ${AVAIL}G），升级有风险"
    HAS_BLOCKERS=1
  fi
else
  warn "安装路径不存在，跳过磁盘检查"
fi
echo ""

# 8. 目标版本 npm 可用性
if [[ -n "${TARGET_VERSION}" ]]; then
  echo "--- 目标版本 ---"
  if npm view "${TOOL}@${TARGET_VERSION}" version &>/dev/null 2>&1; then
    info "${TOOL}@${TARGET_VERSION} 在 npm 上可用"
    PUBLISH_DATE=$(npm view "${TOOL}@${TARGET_VERSION}" time --json 2>/dev/null | grep "${TARGET_VERSION}" | head -1 || true)
    if [[ -n "${PUBLISH_DATE}" ]]; then
      info "发布时间: ${PUBLISH_DATE}"
    fi
  else
    err "${TOOL}@${TARGET_VERSION} 在 npm 上不可用"
    HAS_BLOCKERS=1
  fi
  echo ""
fi

echo "=============================="
echo " 检查完成"
echo "=============================="

exit "${HAS_BLOCKERS}"

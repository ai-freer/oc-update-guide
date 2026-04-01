#!/usr/bin/env bash
#
# pre-upgrade-check.sh — OpenClaw 升级前自动检查脚本
#
# 用法：
#   bash pre-upgrade-check.sh [target_version]
#
# 示例：
#   bash pre-upgrade-check.sh 2026.3.28
#   bash pre-upgrade-check.sh              # 仅检查，不指定版本

set -euo pipefail

TOOL="openclaw"
TARGET_VERSION="${1:-}"

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
  info "Patch 操作数（估算）: ${PATCH_COUNT}"
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
SERVICE="${TOOL}-gateway.service"
if systemctl --user is-active "${SERVICE}" &>/dev/null 2>&1; then
  info "${SERVICE} 正在运行"
elif systemctl --user is-enabled "${SERVICE}" &>/dev/null 2>&1; then
  warn "${SERVICE} 已启用但未运行"
else
  warn "${SERVICE} 未找到或未启用"
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
AVAIL=$(df -h "${INSTALL_PATH}" 2>/dev/null | tail -1 | awk '{print $4}')
info "可用空间: ${AVAIL}"
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
  fi
  echo ""
fi

echo "=============================="
echo " 检查完成"
echo "=============================="

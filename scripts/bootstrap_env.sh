#!/usr/bin/env bash
# 编剧助手 · 开发环境引导脚本
#
# 作用：在会话/容器被重置后，一条命令幂等恢复 Flutter 工具链。
# 设计前提：容器根文件系统（/opt、/tmp、/root）是临时的，只有工作区目录持久，
#          因此 SDK 安装包缓存在持久目录的 .toolchain/ 下，本脚本优先从缓存解压，
#          避免重复下载 1.5GB。
#
# 用法：  bash scripts/bootstrap_env.sh
# 完成后：export PATH="/opt/flutter/bin:$PATH"
#
# 可选环境变量：
#   FLUTTER_CACHE_DIR  指定 SDK 安装包缓存目录
#   FLUTTER_HOME       指定 SDK 解压目录（默认 /opt/flutter）

set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
TARBALL_NAME="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

log() { printf '[bootstrap] %s\n' "$*"; }

# 选择缓存目录：显式指定 > 持久工作区 > 仓库同级目录
pick_cache_dir() {
  if [ -n "${FLUTTER_CACHE_DIR:-}" ]; then
    printf '%s' "${FLUTTER_CACHE_DIR}"
    return
  fi
  local candidate
  for candidate in \
    "/root/userdata/workspace/.toolchain" \
    "${REPO_ROOT}/../.toolchain"; do
    if [ -d "${candidate}" ]; then
      printf '%s' "${candidate}"
      return
    fi
  done
  printf '%s' "${REPO_ROOT}/../.toolchain"
}

CACHE_DIR="$(pick_cache_dir)"
TARBALL="${CACHE_DIR}/${TARBALL_NAME}"

# 1) 已装好且版本匹配 → 直接复用
if [ -x "${FLUTTER_HOME}/bin/flutter" ]; then
  INSTALLED="$("${FLUTTER_HOME}/bin/flutter" --version --machine 2>/dev/null \
    | grep -o '"flutterVersion": *"[^"]*"' | cut -d'"' -f4 || true)"
  if [ "${INSTALLED}" = "${FLUTTER_VERSION}" ]; then
    log "已检测到 Flutter ${FLUTTER_VERSION}，跳过安装"
  else
    log "检测到版本 ${INSTALLED:-未知}，与目标 ${FLUTTER_VERSION} 不符，重新安装"
    rm -rf "${FLUTTER_HOME}"
  fi
fi

# 2) 需要安装：优先用持久缓存，缓存缺失才下载
if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
  mkdir -p "${CACHE_DIR}"
  if [ ! -s "${TARBALL}" ]; then
    log "缓存缺失，开始下载 Flutter ${FLUTTER_VERSION}（约 1.5GB）→ ${TARBALL}"
    curl -fL --retry 3 --retry-delay 2 -o "${TARBALL}.part" "${DOWNLOAD_URL}"
    mv "${TARBALL}.part" "${TARBALL}"
  else
    log "使用持久缓存 ${TARBALL}"
  fi

  log "校验压缩包完整性"
  xz -t "${TARBALL}"

  log "解压到 ${FLUTTER_HOME}（约 1 分钟）"
  rm -rf "${FLUTTER_HOME}"
  tar -xJf "${TARBALL}" -C "$(dirname "${FLUTTER_HOME}")"
fi

# 3) 基础配置：git 安全目录、关闭遥测、预热 Web 构建产物
git config --global --add safe.directory "${FLUTTER_HOME}" 2>/dev/null || true
export PATH="${FLUTTER_HOME}/bin:${PATH}"
flutter --disable-analytics >/dev/null 2>&1 || true
flutter precache --web >/dev/null 2>&1 || log "precache 跳过（非致命）"

log "环境就绪："
flutter --version 2>/dev/null | grep -E '^(Flutter|Tools)' || true

cat <<EOF

[bootstrap] 完成。后续命令请先执行：
    export PATH="${FLUTTER_HOME}/bin:\$PATH"
EOF

#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ggml-org/llama.cpp

APP="llama-cpp"
var_tags="${var_tags:-ai;llm}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_gpu="${var_gpu:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/llama-cpp ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Only the bNNNN tags carry the prebuilt binaries; other tags have no assets.
  if check_for_gh_release "llama-cpp" "ggml-org/llama.cpp" "" "" "b"; then
    msg_info "Stopping Service"
    systemctl stop llama-cpp
    msg_ok "Stopped Service"

    # Keep the build variant the install picked; the CPU tarball would otherwise
    # overwrite a GPU build and quietly end offload.
    LLAMA_BACKEND="$(cat /opt/llama-cpp_data/.backend 2>/dev/null || echo cpu)"
    LLAMA_ARCH="$(arch_resolve x64 arm64)"
    # Older installs recorded rocm while actually running the Vulkan build.
    [[ "$LLAMA_BACKEND" == "rocm" && ! -d /opt/llama-cpp_data/rocm ]] && LLAMA_BACKEND="vulkan"

    LLAMA_CUDART_ASSET=""
    case "$LLAMA_BACKEND" in
    vulkan) LLAMA_ASSET="llama-*-bin-ubuntu-vulkan-${LLAMA_ARCH}.tar.gz" ;;
    cuda-12 | cuda-13)
      LLAMA_ASSET="llama-*-bin-ubuntu-cuda-${LLAMA_BACKEND#cuda-}.*-${LLAMA_ARCH}.tar.gz"
      LLAMA_CUDART_ASSET="cudart-${LLAMA_ASSET}"
      ;;
    rocm) LLAMA_ASSET="llama-*-bin-ubuntu-rocm-*-x64.tar.gz" ;;
    sycl-fp16 | sycl-fp32) LLAMA_ASSET="llama-*-bin-ubuntu-${LLAMA_BACKEND}-x64.tar.gz" ;;
    openvino) LLAMA_ASSET="llama-*-bin-ubuntu-openvino-*x64.tar.gz" ;;
    *) LLAMA_ASSET="llama-*-bin-ubuntu-${LLAMA_ARCH}.tar.gz" ;;
    esac

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "${CHECK_UPDATE_RELEASE}" "/opt/llama-cpp" "$LLAMA_ASSET"
    if [[ -n "$LLAMA_CUDART_ASSET" ]]; then
      # The wipe above also removed the CUDA runtime, so it always goes back in.
      rm -f ~/.llama-cpp-cudart
      fetch_and_deploy_gh_release "llama-cpp-cudart" "ggml-org/llama.cpp" "prebuild" "${CHECK_UPDATE_RELEASE}" "/opt/llama-cpp" "$LLAMA_CUDART_ASSET"
    fi
    chmod +x /opt/llama-cpp/llama-*

    case "$LLAMA_BACKEND" in
    sycl-* | openvino)
      if [[ -d /dev/dri ]]; then
        msg_info "Updating Intel GPU Runtime"
        fetch_and_deploy_gh_release "level-zero" "oneapi-src/level-zero" "binary" "latest" "" "libze1_*+u24.04_amd64.deb" || true
        fetch_and_deploy_gh_release "intel-level-zero-gpu" "intel/compute-runtime" "binary" "latest" "" "libze-intel-gpu1_*_amd64.deb" || true
        msg_ok "Updated Intel GPU Runtime"
      fi
      ;;
    rocm)
      # The ROCm build links against the ROCm release it was built with, so
      # follow it when upstream moves to a newer one.
      ROCM_WANTED="$(jq -r '.. | .name? // empty' "${TOOLS_GH_REL_JSON:-/dev/null}" 2>/dev/null | grep -oP 'bin-ubuntu-rocm-\K[0-9.]+(?=-x64)' | head -1)"
      ROCM_HAVE="$(cat /opt/llama-cpp_data/rocm/.version 2>/dev/null)"
      if [[ -n "$ROCM_WANTED" && "$ROCM_WANTED" != "$ROCM_HAVE" ]]; then
        msg_info "Updating ROCm Runtime ${ROCM_HAVE:-unknown} -> ${ROCM_WANTED} (Patience)"
        $STD uv pip install --python /opt/llama-cpp_data/rocm --index-url https://stable.repo.amd.com/rocm/whl-next/ "rocm[libraries]==${ROCM_WANTED}.*"
        echo "$ROCM_WANTED" >/opt/llama-cpp_data/rocm/.version
        msg_ok "Updated ROCm Runtime ${ROCM_WANTED}"
      fi
      ;;
    esac

    msg_info "Starting Service"
    systemctl start llama-cpp
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW}Change the served model in /opt/llama-cpp.env${CL}"

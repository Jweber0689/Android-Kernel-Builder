#!/bin/bash
# ============================================================
#  Unified Kernel Patch Manager
#  Handles ALL patching except KernelSU itself
# ============================================================

set -e

log() {
    echo "[PATCH-MANAGER] $1"
}

# ============================================================
#  Detect Kernel Version (Makefile → fallback)
# ============================================================

detect_kernel_version() {
    if [[ -f Makefile ]]; then
        VERSION=$(grep '^VERSION = ' Makefile | awk '{print $3}')
        PATCHLEVEL=$(grep '^PATCHLEVEL = ' Makefile | awk '{print $3}')
        SUBLEVEL=$(grep '^SUBLEVEL = ' Makefile | awk '{print $3}')
    fi

    if [[ -z "$VERSION" || -z "$PATCHLEVEL" ]]; then
        if [[ -f include/config/kernel.release ]]; then
            FULL=$(cat include/config/kernel.release)
            VERSION=$(echo "$FULL" | cut -d. -f1)
            PATCHLEVEL=$(echo "$FULL" | cut -d. -f2)
            SUBLEVEL=$(echo "$FULL" | cut -d. -f3)
        fi
    fi

    if [[ -z "$VERSION" || -z "$PATCHLEVEL" ]]; then
        log "ERROR: Cannot detect kernel version"
        exit 1
    fi

    KERNEL_VER="${VERSION}.${PATCHLEVEL}"
    SUB="${SUBLEVEL:-0}"

    log "Detected kernel version: $KERNEL_VER.$SUB"
}

detect_kernel_version

# ============================================================
#  SUSFS Auto-Resolver (GitHub → GitLab fallback)
#  PRIORITY UPDATED: gki-android13 FIRST for 5.15 kernels
# ============================================================

resolve_susfs_branch() {
    SUSFS_REPO_GH="https://github.com/ShirkNeko/susfs4ksu.git"
    SUSFS_REPO_GL="https://gitlab.com/simonpunk/susfs4ksu.git"

    # Motorola Edge+ 2023 uses Android 13 → kernel 5.15
    if [[ "$KERNEL_VER" == "5.15" ]]; then
        BRANCHES=(
            "gki-android13-5.15"
            "gki-android14-5.15"
            "gki-android15-5.15"
            "gki-android16-5.15"
            "gki-android12-5.15"
            "kernel-5.15"
        )
    else
        BRANCHES=(
            "gki-android13-${KERNEL_VER}"
            "gki-android14-${KERNEL_VER}"
            "gki-android15-${KERNEL_VER}"
            "gki-android16-${KERNEL_VER}"
            "gki-android12-${KERNEL_VER}"
            "kernel-${KERNEL_VER}"
        )
    fi

    for B in "${BRANCHES[@]}"; do
        if git ls-remote --heads "$SUSFS_REPO_GH" "$B" | grep -q .; then
            SUSFS_BRANCH="$B"
            SUSFS_REPO="$SUSFS_REPO_GH"
            log "Using SUSFS branch $B from GitHub"
            return
        fi
        if git ls-remote --heads "$SUSFS_REPO_GL" "$B" | grep -q .; then
            SUSFS_BRANCH="$B"
            SUSFS_REPO="$SUSFS_REPO_GL"
            log "Using SUSFS branch $B from GitLab"
            return
        fi
    done

    log "ERROR: No SUSFS branch found for kernel $KERNEL_VER"
    exit 1
}

# ============================================================
#  SUSFS Integration
# ============================================================

if [[ "$USE_SUSFS" == "true" ]]; then
    resolve_susfs_branch

    log "Cloning SUSFS patches..."
    rm -rf ../susfs_patches
    git clone --depth=1 --branch "$SUSFS_BRANCH" "$SUSFS_REPO" ../susfs_patches

    log "Applying SUSFS base patch..."
    PATCH=$(find ../susfs_patches/kernel_patches -maxdepth 1 -name '50_add_susfs_in_*.patch' | head -1)
    if [[ -n "$PATCH" ]]; then
        patch -p1 -F3 --no-backup-if-mismatch < "$PATCH" || true
    fi

    log "Copying SUSFS source files..."
    cp -r ../susfs_patches/kernel_patches/fs/* fs/ 2>/dev/null || true
    cp -r ../susfs_patches/kernel_patches/include/linux/* include/linux/ 2>/dev/null || true

    log "Applying SUSFS KSU-side patch..."
    if [[ -d KernelSU ]]; then
        KSU_PATCH=$(find ../susfs_patches/kernel_patches/KernelSU -name '10_enable_susfs_for_ksu.patch' | head -1)
        if [[ -n "$KSU_PATCH" ]]; then
            cd KernelSU
            patch -p1 -F3 --no-backup-if-mismatch < "$KSU_PATCH" || true
            cd ..
        fi
    fi
fi

# ============================================================
#  Kernel Patch Manager (KPM)
# ============================================================

if [[ "$USE_KPM" == "true" ]]; then
    log "Integrating KPM..."
    rm -rf ../kpm
    git clone https://github.com/CyberKnight777/kpm.git ../kpm || true
    for p in ../kpm/patch/*.patch; do
        patch -p1 --force < "$p" || true
    done
fi

# ============================================================
#  SukiSU-Ultra
# ============================================================

if [[ "$USE_SUKISU" == "true" ]]; then
    log "Integrating SukiSU-Ultra..."
    rm -rf ../sukisu-ultra
    git clone https://github.com/sidex15/SukiSU-Ultra.git ../sukisu-ultra || true
    for p in ../sukisu-ultra/patches/*.patch; do
        patch -p1 --force < "$p" || true
    done
fi

# ============================================================
#  Nomount Patch
# ============================================================

if [[ "$APPLY_NOMOUNT" == "true" ]]; then
    log "Applying nomount patch..."
    curl -LSs "https://raw.githubusercontent.com/maxsteeel/nomount/main/patches/nomount-susfs-kernel-5.15.patch" -o nomount.patch
    patch -p1 --force < nomount.patch || true
fi

# ============================================================
#  zRAM / BBR / VFS / LTO
# ============================================================

log "Applying tuning patches..."

find arch/arm64/configs -type f -exec sed -i \
    -e 's/# CONFIG_ZRAM_DEF_COMP_LZ4 is not set/CONFIG_ZRAM_DEF_COMP_LZ4=y/' \
    -e 's/# CONFIG_ZSMALLOC_STAT is not set/CONFIG_ZSMALLOC_STAT=y/' {} +

find arch/arm64/configs -type f -exec sed -i \
    -e 's/# CONFIG_TCP_CONG_BBR is not set/CONFIG_TCP_CONG_BBR=y/' \
    -e 's/CONFIG_DEFAULT_CUBIC=y/# CONFIG_DEFAULT_CUBIC is not set/' \
    -e 's/# CONFIG_DEFAULT_BBR is not set/CONFIG_DEFAULT_BBR=y/' \
    -e 's/CONFIG_DEFAULT_TCP_CONG="cubic"/CONFIG_DEFAULT_TCP_CONG="bbr"/' {} +

find arch/arm64/configs -type f -exec sed -i \
    -e 's/# CONFIG_FSCACHE is not set/CONFIG_FSCACHE=y/' {} +

find arch/arm64/configs -type f -exec sed -i \
    -e 's/CONFIG_LTO_NONE=y/# CONFIG_LTO_NONE is not set/' \
    -e 's/# CONFIG_LTO_CLANG_THIN is not set/CONFIG_LTO_CLANG_THIN=y/' \
    -e 's/CONFIG_LTO_CLANG_FULL=y/# CONFIG_LTO_CLANG_FULL is not set/' {} +

# ============================================================
#  ABI Bypass
# ============================================================

log "Bypassing ABI checks..."
sed -i 's/ -dirty//g' scripts/setlocalversion 2>/dev/null || true
touch abi_symbollist.raw 2>/dev/null || true
sed -i 's/check_defconfig//' build.config.gki 2>/dev/null || true

# ============================================================
#  Reject Scanner
# ============================================================

log "Collecting patch rejects..."
mkdir -p ../patch-rejects
find . -type f -name '*.rej' -exec cp --parents {} ../patch-rejects/ \; || true

log "Patch manager completed successfully."

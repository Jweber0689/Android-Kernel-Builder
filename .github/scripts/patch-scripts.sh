#!/bin/bash
# Kernel patching script for custom kernel builder

echo "Starting kernel patching process..."

# KernelSU integration
if [ "$USE_KSU" = "true" ]; then
    echo "Integrating KernelSU..."
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
fi

export GIT_TERMINAL_PROMPT=0

# susfs4ksu (Target: Android 13 - 5.15)
if [ "$USE_SUSFS" = "true" ]; then
    echo "Integrating susfs4ksu..."
    
    # Clone specific branch for android13-5.15
    git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android13-5.15 ../susfs4ksu || \
    git clone https://github.com/sidex15/susfs4ksu-module.git ../susfs4ksu
    
    # We apply the patches to the kernel tree
    if [ -d "../susfs4ksu" ]; then
        # Apply Main Kernel patches
        find ../susfs4ksu/kernel_patches/5.15 -name "*.patch" -type f | while read p; do
            echo "Applying susfs kernel patch: $p"
            patch -p1 --force < "$p" || echo "Warning: Failed to apply $p, ignoring..."
        done
        
        # Apply generic kernel patches if any exist in the top level of kernel_patches
        find ../susfs4ksu/kernel_patches -maxdepth 1 -name "*.patch" -type f | while read p; do
            echo "Applying generic susfs patch: $p"
            patch -p1 --force < "$p" || true
        done
        
        # Apply KernelSU specific patches
        if [ -d "KernelSU" ]; then
            cd KernelSU
            find ../../susfs4ksu/kernel_patches/KernelSU -name "*.patch" -type f 2>/dev/null | while read p; do
                echo "Applying susfs KernelSU patch: $p"
                patch -p1 --force < "$p" || echo "Warning: Failed to apply $p, ignoring..."
            done
            cd ..
        fi
        
        # Copy necessary headers/code if not fully handled by patch
        # Add susfs files to kernel tree
        cp -rv ../susfs4ksu/kernel_patches/fs/* fs/ 2>/dev/null || true
        cp -rv ../susfs4ksu/kernel_patches/include/* include/ 2>/dev/null || true
        cp -rv ../susfs4ksu/kernel_patches/5.15/fs/* fs/ 2>/dev/null || true
        cp -rv ../susfs4ksu/kernel_patches/5.15/include/* include/ 2>/dev/null || true
    else
        echo "susfs repository could not be cloned!"
    fi
fi

# Kernel Patch Manager (kpm)
if [ "$USE_KPM" = "true" ]; then
    echo "Integrating kpm..."
    # The actual integration would download kpm source and hook into core kernel Makefile/Kconfig
    git clone https://github.com/CyberKnight777/kpm.git ../kpm || true
    if [ -d "../kpm/patch" ]; then
        for p in ../kpm/patch/*.patch; do
            patch -p1 --force < "$p" || true
        done
    fi
fi

# sukisu-ultra
if [ "$USE_SUKISU" = "true" ]; then
    echo "Integrating sukisu-ultra..."
    # A generic implementation to clone and patch sukisu-ultra features
    git clone https://github.com/sidex15/SukiSU-Ultra.git ../sukisu-ultra || true
    if [ -d "../sukisu-ultra/patches" ]; then
        for p in ../sukisu-ultra/patches/*.patch; do
            patch -p1 --force < "$p" || true
        done
    fi
fi

# nomount patch
if [ "$APPLY_NOMOUNT" = "true" ]; then
    echo "Applying nomount patch..."
    # Nomount modifies fs/namespace.c to bypass mount hiding or tracking
    # We use the specific 5.15 susfs-compatible patch from maxsteeel
    NOMOUNT_URL="https://raw.githubusercontent.com/maxsteeel/nomount/main/patches/nomount-susfs-kernel-5.15.patch"
    curl -LSs "$NOMOUNT_URL" -o nomount.patch || true
    if grep -q "diff --git" nomount.patch; then
        patch -p1 --force < nomount.patch || echo "Could not apply nomount patch."
    else
        echo "Invalid nomount patch downloaded. Skipping."
    fi
fi

# zRAM optimizations
if [ "$APPLY_ZRAM" = "true" ]; then
    echo "Applying zRAM optimizations..."
    # Usually optimizing zRAM consists of switching defaults to lz4/zstd and multi-comp streams.
    # These are often toggled via defconfig: CONFIG_ZRAM_DEF_COMP_LZ4=y, etc.
    # We will enforce them via sed on defconfigs in arch/arm64/configs/*
    find arch/arm64/configs -type f -exec sed -i 's/# CONFIG_ZRAM_DEF_COMP_LZ4 is not set/CONFIG_ZRAM_DEF_COMP_LZ4=y/g' {} +
    find arch/arm64/configs -type f -exec sed -i 's/# CONFIG_ZSMALLOC_STAT is not set/CONFIG_ZSMALLOC_STAT=y/g' {} +
fi

# BBR TCP Congestion Control
if [ "$APPLY_BBR" = "true" ]; then
    echo "Applying BBR configuration..."
    # Setting bbr as default in defconfigs
    find arch/arm64/configs -type f -exec sed -i 's/# CONFIG_TCP_CONG_BBR is not set/CONFIG_TCP_CONG_BBR=y/g' {} +
    find arch/arm64/configs -type f -exec sed -i 's/CONFIG_DEFAULT_CUBIC=y/# CONFIG_DEFAULT_CUBIC is not set/g' {} +
    find arch/arm64/configs -type f -exec sed -i 's/# CONFIG_DEFAULT_BBR is not set/CONFIG_DEFAULT_BBR=y/g' {} +
    find arch/arm64/configs -type f -exec sed -i 's/CONFIG_DEFAULT_TCP_CONG="cubic"/CONFIG_DEFAULT_TCP_CONG="bbr"/g' {} +
fi

# VFS cache optimizations
if [ "$APPLY_VFS" = "true" ]; then
    echo "Applying VFS optimizations..."
    # Typically this involves sysctl vm.vfs_cache_pressure defaults or tweaking fs/dcache.c
    # We'll enable some typical fs configurations in defconfig.
    find arch/arm64/configs -type f -exec sed -i 's/# CONFIG_FSCACHE is not set/CONFIG_FSCACHE=y/g' {} +
fi

# LTO Thin optimization
if [ "$APPLY_LTO_THIN" = "true" ]; then
    echo "Applying LTO Thin optimizations..."
    find arch/arm64/configs -type f -exec sed -i 's/CONFIG_LTO_NONE=y/# CONFIG_LTO_NONE is not set/g' {} +
    find arch/arm64/configs -type f -exec sed -i 's/# CONFIG_LTO_CLANG_THIN is not set/CONFIG_LTO_CLANG_THIN=y/g' {} +
    find arch/arm64/configs -type f -exec sed -i 's/CONFIG_LTO_CLANG_FULL=y/# CONFIG_LTO_CLANG_FULL is not set/g' {} +
fi

echo "Patching completed!"

echo "Collecting any rejected patch hunks for debugging..."
mkdir -p rejects
find . -type f -name "*.rej" -exec cp --parents {} rejects/ 2>/dev/null \; || true

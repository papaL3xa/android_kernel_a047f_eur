#!/bin/bash

export RDIR="$(pwd)"
export ARCH=arm64
export KBUILD_BUILD_USER="@ravindu644"
export PLATFORM_VERSION=12
export ANDROID_MAJOR_VERSION=s

# Install requirements
if [ ! -f ".requirements" ]; then
    echo "[i] Installing build requirements..."
    sudo apt update && sudo apt install -y \
        git device-tree-compiler lz4 xz-utils zlib1g-dev \
        openjdk-17-jdk gcc g++ python3 python-is-python3 \
        p7zip-full android-sdk-libsparse-utils erofs-utils \
        default-jdk git gnupg flex bison gperf build-essential \
        zip curl libc6-dev libncurses-dev libx11-dev libreadline-dev \
        libgl1 libgl1-mesa-dev python3-markdown libxml2-utils \
        xsltproc bc libtinfo6 libssl-dev libelf-dev kmod openssl \
        cpio pahole tofrodos --fix-missing
        
    # Install libtinfo5 if needed
    if ! dpkg -l | grep -q libtinfo5; then
        wget -q http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb
        sudo dpkg -i libtinfo5_6.3-2ubuntu0.1_amd64.deb
        rm -f libtinfo5_6.3-2ubuntu0.1_amd64.deb
    fi
    
    touch .requirements
    echo "[i] Requirements installed successfully."
fi

# Toolchain paths
export BUILD_CROSS_COMPILE="${RDIR}/toolchain/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
export BUILD_CC="${RDIR}/toolchain/clang/host/linux-x86/clang-r353983c/bin/clang"

# Check if toolchains exist
check_toolchains() {
    if [ ! -f "${BUILD_CROSS_COMPILE}gcc" ]; then
        echo "[!] Cross compiler not found at: ${BUILD_CROSS_COMPILE}"
        return 1
    fi
    
    if [ ! -f "${BUILD_CC}" ]; then
        echo "[!] Clang compiler not found at: ${BUILD_CC}"
        return 1
    fi
    
    return 0
}

# Initialize KSU next
echo "[i] Initializing KernelSU submodule..."
git submodule init && git submodule update

# Create output directory
if [ ! -d "${RDIR}/out" ]; then
    mkdir -p "${RDIR}/out"
    echo "[i] Created output directory: ${RDIR}/out"
fi

# Create build directory
if [ ! -d "${RDIR}/build" ]; then
    mkdir -p "${RDIR}/build"
    echo "[i] Created build directory: ${RDIR}/build"
else
    echo "[i] Cleaning build directory..."
    rm -rf "${RDIR}/build" && mkdir -p "${RDIR}/build"
fi

# Kernel version
if [ -z "$BUILD_KERNEL_VERSION" ]; then
    export BUILD_KERNEL_VERSION="dev"
fi

echo "[i] Building kernel version: ${BUILD_KERNEL_VERSION}"

# Setting up localversion
echo "[i] Setting up local version..."
echo -e "CONFIG_LOCALVERSION_AUTO=n\nCONFIG_LOCALVERSION=\"-FlameKernel-${BUILD_KERNEL_VERSION}\"\n" > "${RDIR}/arch/arm64/configs/version.config"

# Build options
export ARGS="
-w \
-C $(pwd) \
O=$(pwd)/out \
-j$(nproc --all) \
ARCH=arm64 \
CROSS_COMPILE=${BUILD_CROSS_COMPILE} \
CC=${BUILD_CC} \
CLANG_TRIPLE=aarch64-linux-gnu- \
"

# Build kernel image
build_kernel(){
    echo "[i] Starting kernel build..."
    
    if ! check_toolchains; then
        echo "[!] Toolchain check failed. Aborting build."
        exit 1
    fi
    
    # Run make commands
    make ${ARGS} exynos850-a04sxx_defconfig || exit 1
    make ${ARGS} a04s.config || exit 1
    make ${ARGS} version.config || exit 1
    make ${ARGS} menuconfig || exit 1
    make ${ARGS} || exit 1
    
    echo "[✓] Kernel build completed successfully."
}

# Build boot.img
build_boot() {    
    echo "[i] Building boot.img..."
    
    # Check if AIK-Linux directory exists
    if [ ! -d "${RDIR}/AIK-Linux" ]; then
        echo "[!] AIK-Linux directory not found!"
        exit 1
    fi
    
    # Check if kernel image exists
    if [ ! -f "${RDIR}/out/arch/arm64/boot/Image" ]; then
        echo "[!] Kernel image not found at: ${RDIR}/out/arch/arm64/boot/Image"
        exit 1
    fi
    
    # Clean previous files
    rm -f "${RDIR}/AIK-Linux/split_img/boot.img-kernel" "${RDIR}/AIK-Linux/boot.img"
    
    # Copy kernel image
    cp "${RDIR}/out/arch/arm64/boot/Image" "${RDIR}/AIK-Linux/split_img/boot.img-kernel"
    
    # Create necessary directories
    mkdir -p "${RDIR}/AIK-Linux/ramdisk/"{debug_ramdisk,dev,metadata,mnt,proc,second_stage_resources,sys}
    
    # Repack boot image
    cd "${RDIR}/AIK-Linux" && ./repackimg.sh --nosudo
    
    # Check if repacking was successful
    if [ ! -f "image-new.img" ]; then
        echo "[!] Boot image repacking failed!"
        exit 1
    fi
    
    mv image-new.img "${RDIR}/build/boot.img"
    echo "[✓] boot.img created successfully."
}

# Build odin flashable tar
build_tar(){
    echo "[i] Creating Odin flashable tar..."
    
    cd "${RDIR}/build"
    
    # Check if boot.img exists
    if [ ! -f "boot.img" ]; then
        echo "[!] boot.img not found in build directory!"
        exit 1
    fi
    
    tar -cvf "KernelSU-Next-SM-A047F-${BUILD_KERNEL_VERSION}.tar" boot.img
    rm -f boot.img
    
    # Verify tar was created
    if [ -f "KernelSU-Next-SM-A047F-${BUILD_KERNEL_VERSION}.tar" ]; then
        echo "[✓] Build finished: KernelSU-Next-SM-A047F-${BUILD_KERNEL_VERSION}.tar"
    else
        echo "[!] Failed to create tar file!"
        exit 1
    fi
    
    cd "${RDIR}"
}

# Main build process
main() {
    echo "[i] Starting build process..."
    
    build_kernel
    build_boot
    build_tar
    
    echo "[✓] All build steps completed successfully!"
}

# Run main function
main "$@"

# shellcheck shell=bash

export BOARD_NAME="Turing RK1"
export BOARD_MAKER="Turing Machines"
export BOARD_SOC="Rockchip RK3588"
export BOARD_CPU="ARM Cortex A76 / A55"
export UBOOT_PACKAGE="u-boot-turing-rk3588"
export UBOOT_RULES_TARGET="turing-rk1-rk3588"
export COMPATIBLE_SUITES=("resolute")
export COMPATIBLE_FLAVORS=("server")

# Files the boot packages read when config-image.sh installs them.
config_image_hook__turing-rk1() {
    local chroot_dir="$1"

    # flash-kernel (device tree only, see config-image.sh) needs to know
    # the board: the entry for the database and the name, because the
    # model is not readable from /proc/device-tree inside the chroot. The
    # name is the model string of Linux's rk3588-turing-rk1.dts.
    mkdir -p "${chroot_dir}/etc/flash-kernel"
    cat > "${chroot_dir}/etc/flash-kernel/db" << 'DB'
Machine: Turing Machines RK1
Kernel-Flavors: any
DTB-Id: rockchip/rk3588-turing-rk1.dtb
DB
    echo "Turing Machines RK1" > "${chroot_dir}/etc/flash-kernel/machine"

    # Kernel command line for grub.cfg. No console=: the kernel then takes
    # its console from the device tree's stdout-path (serial9, ttyS9), which
    # an explicit console= would override, and the cloud image's
    # console=tty1 console=ttyAMA0 (50-cloudimg-settings.cfg) would leave
    # the serial line silent. Also drop the cloud image's initrd-less
    # PARTUUID boot, whose value is from another disk.
    mkdir -p "${chroot_dir}/etc/default/grub.d"
    cat > "${chroot_dir}/etc/default/grub.d/99-turing-rk1.cfg" << 'CFG'
GRUB_CMDLINE_LINUX_DEFAULT="earlycon"
GRUB_FORCE_PARTUUID=
CFG
}

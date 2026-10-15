#!/bin/bash

set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

cleanup_loopdev() {
    local loop="$1"

    sync --file-system
    sync

    sleep 1

    if [ -b "${loop}" ]; then
        for part in "${loop}"p*; do
            if mnt=$(findmnt -n -o target -S "$part"); then
                umount "${mnt}"
            fi
        done
        losetup -d "${loop}"
    fi
}

wait_loopdev() {
    local loop="$1"
    local seconds="$2"

    until test $((seconds--)) -eq 0 -o -b "${loop}"; do sleep 1; done

    ((++seconds))

    ls -l "${loop}" &> /dev/null
}

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 filename.rootfs.tar"
    exit 1
fi

rootfs="$(readlink -f "$1")"
if [[ "$(basename "${rootfs}")" != *".rootfs.tar" || ! -e "${rootfs}" ]]; then
    echo "Error: $(basename "${rootfs}") must be a rootfs tarfile"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
mkdir -p images build && cd build

if [[ -z ${BOARD} ]]; then
    echo "Error: BOARD is not set"
    exit 1
fi

# Create an empty disk image
img="../images/$(basename "${rootfs}" .rootfs.tar)${KVER}.img"
size="$(( $(wc -c < "${rootfs}" ) / 1024 / 1024 ))"
truncate -s "$(( size + 2048 ))M" "${img}"

# Create loop device for disk image
loop="$(losetup -f)"
losetup -P "${loop}" "${img}"
disk="${loop}"

# Cleanup loopdev on early exit
trap 'cleanup_loopdev ${loop}' EXIT

# Ensure disk is not mounted
mount_point=/tmp/mnt
umount "${disk}"* 2> /dev/null || true
umount ${mount_point}/* 2> /dev/null || true
mkdir -p ${mount_point}

# Setup partition table. Partition 1 is the EFI System Partition (/boot/efi)
# and also carries the cloud-init seed, found by its CIDATA label. U-Boot's
# distro boot searches only the partitions it calls bootable for
# EFI/BOOT/BOOTAA64.EFI, and for GPT that is the legacy BIOS bootable
# attribute or the ESP type; with none it tries partition 1 alone.
dd if=/dev/zero of="${disk}" count=4096 bs=512
parted --script "${disk}" \
mklabel gpt \
mkpart primary fat32 16MiB 272MiB \
mkpart primary ext4 272MiB 100%

# Create partitions
{
    echo "t"
    echo "1"
    echo "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
    echo "t"
    echo "2"
    echo "0FC63DAF-8483-4772-8E79-3D69D8477DE4"
    echo "w"
} | fdisk "${disk}" &> /dev/null || true

partprobe "${disk}"

partition_char="$(if [[ ${disk: -1} == [0-9] ]]; then echo p; fi)"

sleep 1

wait_loopdev "${disk}${partition_char}2" 60 || {
    echo "Failure to create ${disk}${partition_char}1 in time"
    exit 1
}

sleep 1

wait_loopdev "${disk}${partition_char}1" 60 || {
    echo "Failure to create ${disk}${partition_char}1 in time"
    exit 1
}

sleep 1

# Generate random uuid for bootfs
boot_uuid=$(uuidgen | head -c8)
boot_uuid="${boot_uuid^^}"
boot_uuid="${boot_uuid:0:4}-${boot_uuid:4:4}"

# Generate random uuid for rootfs
root_uuid=$(uuidgen)

# Create filesystems on partitions
mkfs.vfat -i "${boot_uuid/-/}" -F32 -n CIDATA "${disk}${partition_char}1"
dd if=/dev/zero of="${disk}${partition_char}2" bs=1KB count=10 > /dev/null
mkfs.ext4 -U "${root_uuid}" -L cloudimg-rootfs "${disk}${partition_char}2"

# Mount partitions
mkdir -p ${mount_point}/writable
mount "${disk}${partition_char}2" ${mount_point}/writable

# Copy the rootfs to root partition
tar -xpf "${rootfs}" -C ${mount_point}/writable

# The ESP, with the cloud-init config for the server image
mkdir -p ${mount_point}/writable/boot/efi
mount "${disk}${partition_char}1" ${mount_point}/writable/boot/efi
cp ../overlay/boot/firmware/{meta-data,user-data,network-config} ${mount_point}/writable/boot/efi

# Create fstab entries
echo "# <file system>     <mount point>  <type>  <options>   <dump>  <fsck>" > ${mount_point}/writable/etc/fstab
echo "UUID=${root_uuid,,} /              ext4    defaults,x-systemd.growfs    0       1" >> ${mount_point}/writable/etc/fstab
echo "UUID=${boot_uuid} /boot/efi      vfat    umask=0077    0       1" >> ${mount_point}/writable/etc/fstab

# Write bootloader to disk image
if [ -f "${mount_point}/writable/usr/lib/u-boot/u-boot-rockchip.bin" ]; then
    dd if="${mount_point}/writable/usr/lib/u-boot/u-boot-rockchip.bin" of="${loop}" seek=1 bs=32k conv=fsync
else
    dd if="${mount_point}/writable/usr/lib/u-boot/idbloader.img" of="${loop}" seek=64 conv=notrunc
    dd if="${mount_point}/writable/usr/lib/u-boot/u-boot.itb" of="${loop}" seek=16384 conv=notrunc
fi

# Run build image hook to handle board specific changes
if [[ $(type -t build_image_hook__"${BOARD}") == function ]]; then
    build_image_hook__"${BOARD}"
fi 

# GRUB on the ESP, and grub.cfg. grub-install and grub-probe need the real
# root and ESP devices, which is why this is done here and not in
# config-image.sh. The install is what grub-efi-arm64's postinst repeats on
# upgrades (it uses /boot/efi from fstab); update-grub is what the kernel
# hooks repeat.
mount --bind /dev ${mount_point}/writable/dev
mount -t proc proc ${mount_point}/writable/proc
mount -t sysfs sysfs ${mount_point}/writable/sys
chroot ${mount_point}/writable/ grub-install --target=arm64-efi --no-nvram
chroot ${mount_point}/writable/ update-grub
umount ${mount_point}/writable/sys ${mount_point}/writable/proc ${mount_point}/writable/dev

sync --file-system
sync

# Umount partitions
umount "${disk}${partition_char}1"
umount "${disk}${partition_char}2" 2> /dev/null || true

# The two partitions on their own, for writing into partitions that
# already exist (the RK1's eMMC, where the first 16 MiB hold the boot
# loader and must stay untouched): the ESP (with the cloud-init seed) and
# the root filesystem, which holds /boot. The disk image has them in place.
esp_img="${img%.img}.esp.img"
root_img="${img%.img}.root.img"
dd if="${disk}${partition_char}1" of="${esp_img}" bs=1M conv=sparse status=none
dd if="${disk}${partition_char}2" of="${root_img}" bs=1M conv=sparse status=none

# Remove loop device
losetup -d "${loop}"

# Exit trap is no longer needed
trap '' EXIT

for file in "${img}" "${esp_img}" "${root_img}"; do
    echo -e "\nCompressing $(basename "${file}.xz")\n"
    xz -6 --force --keep --quiet --threads=0 "${file}"
    rm -f "${file}"
    (cd ../images && sha256sum "$(basename "${file}.xz")" > "$(basename "${file}.xz.sha256")")
done

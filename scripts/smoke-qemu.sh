#!/bin/bash
# Boot the built disk image on QEMU's "virt" machine and check that its
# userspace comes up: UEFI firmware runs EFI/BOOT/BOOTAA64.EFI from the
# ESP, GRUB finds grub.cfg and starts Ubuntu's kernel and initrd, systemd
# finishes starting, cloud-init finishes and `apt-get update` works.
#
# The RK3588 cannot be emulated, so this says nothing about U-Boot, the
# device tree or any RK3588 driver; it catches packaging, GRUB and
# initramfs regressions before anyone touches the board.
#
# Usage: scripts/smoke-qemu.sh <name>.img.xz      (as root)
# Writes report, errors and serial.log into $SMOKE_OUT (default ./smoke).
# Exits 1 when errors is not empty.
#
# What differs from the image as built, on a throwaway copy:
#  - the `devicetree /boot/dtb-<kver>` lines are removed from grub.cfg: they
#    hand the kernel the RK1's device tree, which describes no virtio
#    device, so it would find neither its root nor the network;
#  - a test script is appended to the cloud-init seed on the ESP.
# The image's own seed, command line, initrd and everything else are used
# as they are.

set -eEu

out=${SMOKE_OUT:-$PWD/smoke}
img_xz=${1:?usage: $0 <name>.img.xz}

mkdir -p "$out"
cd "$out"
: > report; : > errors; : > warnings; : > serial.log

# Job logs are not readable without a sign-in: name the failing command in an annotation.
trap 'echo "::error title=smoke::smoke script failed at line $LINENO: $BASH_COMMAND"' ERR

err() { echo "$*" >> errors; }
warn() { echo "$*" >> warnings; }

work=$(mktemp -d)
mnt=$work/mnt
mkdir -p "$mnt/esp" "$mnt/root"
loop=
cleanup() {
    mountpoint -q "$mnt/esp" && umount "$mnt/esp"
    mountpoint -q "$mnt/root" && umount "$mnt/root"
    [ -z "$loop" ] || losetup -d "$loop"
    return 0
}
trap cleanup EXIT

xz -dc "$img_xz" | dd of="$work/disk.img" bs=1M conv=sparse status=none
loop=$(losetup -f --show -P "$work/disk.img")
# The partition nodes appear a moment after losetup returns.
for _ in $(seq 30); do [ -b "${loop}p2" ] && break; sleep 1; done
[ -b "${loop}p2" ] || { echo "::error title=smoke::no partition nodes for $loop: $(echo "${loop}"*)"; exit 1; }
mount "${loop}p1" "$mnt/esp"
mount "${loop}p2" "$mnt/root"

cfg=$mnt/root/boot/grub/grub.cfg
kvers=
for f in "$mnt/root"/boot/vmlinuz-*; do kvers="$kvers ${f##*/vmlinuz-}"; done
echo "image: $(basename "$img_xz")" >> report
echo "kernel(s):$kvers" >> report

# What the initramfs carries of what the RK3588 needs to reach its root. A
# driver built as a module that is missing here is a boot failure on the
# board and invisible in QEMU, which needs virtio_blk only.
for k in $kvers; do
    conf=$mnt/root/boot/config-$k
    list=$work/initrd-$k.list
    if ! lsinitramfs "$mnt/root/boot/initrd.img-$k" > "$list" 2> "$work/lsinitramfs.err"; then
        err "cannot list initrd.img-$k: $(head -c 300 "$work/lsinitramfs.err")"
        continue
    fi
    {
        echo
        echo "initrd.img-$k: $(wc -l < "$list") files, $(grep -c '\.ko' "$list") kernel modules"
        echo "storage and platform drivers (CONFIG symbol: kernel config / in the initrd):"
    } >> report
    for pair in VIRTIO_BLK:virtio_blk MMC_BLOCK:mmc_block MMC_SDHCI_OF_DWCMSHC:sdhci-of-dwcmshc \
                MMC_DW_ROCKCHIP:dw_mmc-rockchip BLK_DEV_NVME:nvme PCIE_ROCKCHIP_DW_HOST:pcie-dw-rockchip \
                PHY_ROCKCHIP_SNPS_PCIE3:phy-rockchip-snps-pcie3 PHY_ROCKCHIP_NANENG_COMBO_PHY:phy-rockchip-naneng-combphy \
                SPI_ROCKCHIP:spi-rockchip MFD_RK8XX_SPI:rk8xx-spi REGULATOR_RK808:rk808-regulator \
                PINCTRL_ROCKCHIP:pinctrl-rockchip COMMON_CLK_SCMI:clk-scmi; do
        sym=${pair%%:*}; mod=${pair##*:}
        state=$(sed -n "s/^CONFIG_$sym=//p" "$conf")
        if grep -qE "/$mod\.ko" "$list"; then where=yes; else where=no; fi
        echo "  $sym: ${state:-unset} / $where" >> report
        if [ "$state" = m ] && [ "$where" = no ]; then
            warn "$k: $sym is a module ($mod) and the initrd does not have it"
        fi
    done
done

# The seed on the ESP: the image's own, plus a script that reports from inside
# the guest. The seed must not define these keys already, or the appended ones
# would duplicate them.
if grep -qE '^(write_files|runcmd|power_state):' "$mnt/esp/user-data"; then
    err "the seed's user-data already has write_files, runcmd or power_state: the smoke test cannot append its own"
fi
cat >> "$mnt/esp/user-data" << 'EOF'

# --- appended by scripts/smoke-qemu.sh, not part of the image ---
write_files:
  - path: /usr/local/sbin/smoke.sh
    permissions: '0755'
    content: |
      #!/bin/sh
      exec > /dev/ttyAMA0 2>&1
      say() { echo "SMOKE $*"; }
      say begin
      say "is-system-running: $(systemctl is-system-running --wait)"
      say "failed units: $(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')"
      say "kernel: $(uname -r)"
      say "cmdline: $(cat /proc/cmdline)"
      say "console: $(cat /sys/class/tty/console/active)"
      say "efi: $(ls /sys/firmware/efi >/dev/null 2>&1 && echo yes || echo no)"
      say "root: $(findmnt -n -o SOURCE,FSTYPE,SIZE /)"
      say "esp: $(findmnt -n -o SOURCE,FSTYPE /boot/efi)"
      cloud-init status --wait > /tmp/ci.status 2>&1
      say "cloud-init: rc=$? $(tr '\n' ' ' < /tmp/ci.status)"
      say "timing: $(systemd-analyze 2>&1 | head -n1)"
      n=0
      until ip route show default | grep -q . || [ $n -ge 120 ]; do sleep 1; n=$((n + 1)); done
      say "default route after ${n}s: $(ip route show default | head -n1)"
      apt-get update > /tmp/apt.log 2>&1
      say "apt-get-update: rc=$? $(grep -c '^Get:\|^Hit:' /tmp/apt.log) fetched, $(grep -c '^Err:' /tmp/apt.log) errors"
      grep -E '^(Err|W|E):' /tmp/apt.log | head -n 5 | sed 's/^/SMOKE apt: /'
      say end
      sync
      systemctl poweroff
runcmd:
  - [ systemd-run, --no-block, --unit=smoke, /usr/local/sbin/smoke.sh ]
EOF

# The firmware's device tree and the RK1's built-in one are not what this
# test is about (see the header): drop the devicetree lines in the copy.
grep -qE '^\s+devicetree\s' "$cfg" || err "grub.cfg of the image has no devicetree line (the image build checks for one)"
sed -i -E '/^\s+devicetree\s/d' "$cfg"

umount "$mnt/esp" "$mnt/root"
losetup -d "$loop"; loop=

# UEFI firmware as pflash, the disk on virtio, user-mode networking.
code=/usr/share/AAVMF/AAVMF_CODE.fd
vars=/usr/share/AAVMF/AAVMF_VARS.fd
cp "$code" "$work/code.fd"; cp "$vars" "$work/vars.fd"
truncate -s 64M "$work/code.fd" "$work/vars.fd"
if [ -w /dev/kvm ]; then accel=kvm; cpu=host; else accel=tcg; cpu=max,pauth-impdef=on; fi
echo "qemu: $(qemu-system-aarch64 --version | head -n1), accel $accel, firmware $(dpkg -s qemu-efi-aarch64 | sed -n 's/^Version: //p')" >> report

rc=0
timeout "${SMOKE_TIMEOUT:-1500}" qemu-system-aarch64 \
    -machine "virt,accel=$accel" -cpu "$cpu" -smp 4 -m 4G \
    -display none -monitor none -serial file:serial.log -no-reboot \
    -drive if=pflash,format=raw,readonly=on,file="$work/code.fd" \
    -drive if=pflash,format=raw,file="$work/vars.fd" \
    -drive if=none,format=raw,file="$work/disk.img",id=d0 -device virtio-blk-pci,drive=d0 \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -device virtio-rng-pci || rc=$?
[ "$rc" -eq 0 ] || err "qemu exited with $rc$([ "$rc" -ne 124 ] || echo ' (timed out)')"

# Strip the escape sequences and carriage returns of the console.
sed -i -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' -e 's/\r//g' serial.log
{
    echo
    echo "serial console: $(wc -l < serial.log) lines"
    echo "firmware and GRUB: $(grep -aoE 'GNU GRUB +version [0-9.]+[^ ]*|EFI stub: [A-Za-z ]*' serial.log | sort -u | paste -sd'|')"
    echo "from the guest:"
    grep -a '^SMOKE ' serial.log | sed 's/^SMOKE /  /'
} >> report

want() { # <what> <pattern>: the guest's line must match
    grep -aqE "^SMOKE $2" serial.log || err "$1"
}
if ! grep -aq '^SMOKE begin' serial.log; then
    err "the guest's userspace never ran the test script (no boot, no console, or cloud-init did not run it)"
else
    want "systemd did not finish starting (is-system-running is not running or degraded)" 'is-system-running: (running|degraded)'
    want "cloud-init did not finish with status: done" 'cloud-init: rc=0 status: done'
    want "apt-get update failed" 'apt-get-update: rc=0 '
    want "the test did not get to its end" 'end$'
    grep -aqE '^SMOKE failed units: *$' serial.log || err "failed units: $(sed -n 's/^SMOKE failed units: //p' serial.log)"
    grep -aq '^SMOKE console: ttyAMA0' serial.log || warn "the kernel's console is not ttyAMA0: $(sed -n 's/^SMOKE console: //p' serial.log)"
    grep -aq '^SMOKE cmdline: .*console=' serial.log && err "the kernel command line has a console= (the image sets none)"
fi

cd "$out"
cat report
while IFS= read -r line; do echo "::warning title=smoke::$line"; done < warnings
while IFS= read -r line; do echo "::error title=smoke::$line"; done < errors
msg=$(sed ':a;N;$!ba;s/%/%25/g;s/\r/%0D/g;s/\n/%0A/g' report)
echo "::notice title=smoke (QEMU virt)::$msg"
# The head shows firmware and GRUB, the tail the end of the boot: enough to see where it stopped.
for part in head tail; do
    msg=$("$part" -n 40 serial.log | cut -c1-200 | sed ':a;N;$!ba;s/%/%25/g;s/\r/%0D/g;s/\n/%0A/g')
    echo "::notice title=smoke serial $part::$msg"
done
test ! -s errors

#!/bin/bash
# Collect the E1 boot-path and hardware evidence on the RK1 test boot
# (docs/e1-runbook.md, step 6), as root, on the system booted from the eMMC.
#
# Everything lands in /root/e1-evidence/ and one tarball next to it; the
# last lines say which boot-path checks passed. Read-only with respect to
# every disk: it never mounts, writes to or runs a filesystem check on any
# block device, and refuses to run when the root filesystem is not on the
# eMMC, so a slip onto the production NVMe system does nothing.
#
# Usage: sudo scripts/e1-evidence.sh [seconds of CPU load, default 120]

# The commands handed to sh_run are single-quoted on purpose: they expand in
# the shell that sh_run starts.
# shellcheck disable=SC2016
set -u

if [ "$(id -u)" -ne 0 ]; then echo "run as root" >&2; exit 1; fi

root_src=$(findmnt -n -o SOURCE /)
case "$root_src" in
    /dev/mmcblk0p2) ;;
    *) echo "root is on $root_src, not /dev/mmcblk0p2: this is not the eMMC test system. Nothing done." >&2; exit 1 ;;
esac

load=${1:-120}
out=/root/e1-evidence
rm -rf "$out"; mkdir -p "$out"
cd "$out" || exit 1

run() { # <file> <command...>: save the output, and the exit status as the last line
    local f=$1; shift
    { "$@" 2>&1; echo "[exit $?]"; } > "$f.txt"
}
sh_run() { # <file> <shell text>
    run "$1" sh -c "$2"
}

# --- Boot path -------------------------------------------------------------
run uname uname -a
run os-release cat /etc/os-release
run cmdline cat /proc/cmdline
run console-active cat /sys/class/tty/console/active
run proc-consoles cat /proc/consoles
run dt-model cat /proc/device-tree/model
sh_run dt-top 'ls /proc/device-tree'
sh_run efi 'ls -l /sys/firmware/efi; ls /sys/firmware/efi/efivars 2>&1 | head -n 5'
run dmesg dmesg
sh_run dmesg-boot-path 'dmesg | grep -iE "earlycon|console \[|efi:|EFI stub|fdt|Machine model|Kernel command line|KASLR|OF: "'
sh_run dmesg-warn-err 'dmesg --level=emerg,alert,crit,err,warn'
sh_run kernel-files 'uname -r; ls -l /boot; ls -l /boot/dtbs/* 2>&1 | head -n 20; dpkg -l "linux-image*" "linux-modules*" grub-efi-arm64 flash-kernel | cat'
sh_run grub-cfg 'grep -nE "^\s+(linux|initrd|devicetree)\s|^menuentry" /boot/grub/grub.cfg'
sh_run mounts 'findmnt; echo; lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTTYPENAME,MOUNTPOINTS'
sh_run blkid 'blkid'

# The device tree the kernel runs on against the file GRUB was told to load.
# Ubuntu's has the GPU and the NPU cores; U-Boot 2024.01's built-in one has
# neither. The EFI stub adds to /chosen (bootargs, initrd, rng seed, ...), so
# /chosen is left out of the comparison.
sh_run dt-gpu-npu 'ls -d /proc/device-tree/gpu@fb000000 /proc/device-tree/npu@fdab0000 /proc/device-tree/npu@fdac0000 /proc/device-tree/npu@fdad0000 2>&1; ls /proc/device-tree | grep -iE "gpu|npu|rknn|video-codec|vop|hdmi"'
if command -v dtc > /dev/null; then
    strip_chosen() { dtc -I dtb -O dts -s "$1" 2> /dev/null | awk '/^\tchosen \{/{skip=1} !skip{print} skip&&/^\t\};/{skip=0}'; }
    kver=$(uname -r)
    strip_chosen /sys/firmware/fdt > running.dts
    strip_chosen "/boot/dtb-$kver" > file.dts
    strip_chosen "/lib/firmware/$kver/device-tree/rockchip/rk3588-turing-rk1.dtb" > kernel-package.dts
    { diff -u file.dts running.dts; echo "[exit $?]"; } > dtb-diff-running-vs-boot-dtb.txt 2>&1
    { diff -u kernel-package.dts file.dts; echo "[exit $?]"; } > dtb-diff-boot-dtb-vs-package.txt 2>&1
    sh_run dtb-links 'ls -l /boot/dtb-*; sha256sum /sys/firmware/fdt "/boot/dtb-$(uname -r)"'
else
    echo "dtc is not installed (apt-get install device-tree-compiler): no DTB comparison" > dtb-diff-running-vs-boot-dtb.txt
fi

# --- Hardware --------------------------------------------------------------
run lscpu lscpu
run meminfo free -h
sh_run lspci 'lspci -nnvv 2>&1 || echo "no lspci (apt-get install pciutils)"'
sh_run lsusb 'lsusb -t 2>&1 || echo "no lsusb (apt-get install usbutils)"'
run ip-link ip -d link
run ip-addr ip -br addr
for netdev in /sys/class/net/*; do
    dev=${netdev##*/}
    [ "$dev" = lo ] && continue
    sh_run "ethtool-$dev" "ethtool $dev; ethtool -i $dev"
done
sh_run nvme-emmc-visible 'ls -l /dev/nvme* /dev/mmcblk* 2>&1; nvme list 2>&1 || echo "no nvme-cli (apt-get install nvme-cli)"'
sh_run emmc-mmc-ios 'cat /sys/kernel/debug/mmc0/ios 2>&1; for f in type name manfid oemid date; do echo "$f: $(cat /sys/class/mmc_host/mmc0/mmc0:*/$f 2>&1)"; done'
sh_run proc-interrupts 'cat /proc/interrupts'
sh_run lsmod 'lsmod'

# cpufreq, thermal, fan: idle, then under load
snapshot() { # <label>
    {
        echo "== $1 $(date +%T)"
        for p in /sys/devices/system/cpu/cpufreq/policy*; do
            echo "$(basename "$p"): cpus $(cat "$p/related_cpus") driver $(cat "$p/scaling_driver") governor $(cat "$p/scaling_governor") cur $(cat "$p/scaling_cur_freq") min $(cat "$p/cpuinfo_min_freq") max $(cat "$p/cpuinfo_max_freq")"
        done
        for z in /sys/class/thermal/thermal_zone*; do echo "$(basename "$z"): $(cat "$z/type") $(cat "$z/temp")"; done
        for c in /sys/class/thermal/cooling_device*; do echo "$(basename "$c"): $(cat "$c/type") cur_state $(cat "$c/cur_state") max_state $(cat "$c/max_state")"; done
        for h in /sys/class/hwmon/hwmon*; do echo "$(basename "$h"): $(cat "$h/name") $(for f in "$h"/pwm1 "$h"/fan1_input; do [ -e "$f" ] && echo "$(basename "$f")=$(cat "$f")"; done)"; done
    } >> thermal-cpufreq.txt 2>&1
}
: > thermal-cpufreq.txt
snapshot idle
if command -v stress-ng > /dev/null; then
    stress-ng --cpu 0 --timeout "${load}s" > stress-ng.txt 2>&1 &
    pid=$!
    i=0
    while [ "$i" -lt "$load" ] && kill -0 "$pid" 2> /dev/null; do
        sleep 10; i=$((i + 10)); snapshot "load ${i}s"
    done
    wait "$pid"
    sleep 20; snapshot "after load"
else
    echo "no stress-ng (apt-get install stress-ng): no load samples" >> thermal-cpufreq.txt
fi

# --- Userspace -------------------------------------------------------------
sh_run systemd 'systemctl is-system-running; systemctl --failed --no-pager; systemd-analyze 2>&1 | head -n 3'
sh_run cloud-init 'cloud-init status --long'
sh_run journal-warn 'journalctl -b -p warning --no-pager'
sh_run k3s-absent 'systemctl list-unit-files | grep -i k3s || echo "no k3s unit: as intended"'

# --- Boot-path verdicts ----------------------------------------------------
{
    verdict() { # <name> <pass if command succeeds>
        local name=$1; shift
        if "$@" > /dev/null 2>&1; then echo "PASS $name"; else echo "FAIL $name"; fi
    }
    verdict "booted by UEFI (/sys/firmware/efi exists)" test -d /sys/firmware/efi
    verdict "cmdline has root=UUID=" grep -q 'root=UUID=' /proc/cmdline
    verdict "cmdline has no console=" sh -c '! grep -q "console=" /proc/cmdline'
    verdict "console is ttyS9" grep -qx ttyS9 /sys/class/tty/console/active
    verdict "root filesystem is on the eMMC" test "$root_src" = /dev/mmcblk0p2
    verdict "DT model is Turing Machines RK1" grep -q 'Turing Machines RK1' /proc/device-tree/model
    verdict "DT has gpu@fb000000" test -d /proc/device-tree/gpu@fb000000
    verdict "DT has the three NPU cores" sh -c 'test -d /proc/device-tree/npu@fdab0000 && test -d /proc/device-tree/npu@fdac0000 && test -d /proc/device-tree/npu@fdad0000'
    verdict "/boot/dtb-<kver> is the kernel's own RK1 DTB" cmp -s "/boot/dtb-$(uname -r)" "/lib/firmware/$(uname -r)/device-tree/rockchip/rk3588-turing-rk1.dtb"
    verdict "running DT equals /boot/dtb-<kver> outside /chosen" sh -c 'test -s running.dts && cmp -s running.dts file.dts'
    verdict "no k3s service running" sh -c '! systemctl is-active --quiet k3s k3s-agent'
} | tee verdicts.txt

cd /root && tar czf e1-evidence.tar.gz e1-evidence
echo "evidence: /root/e1-evidence.tar.gz ($(du -h /root/e1-evidence.tar.gz | cut -f1))"

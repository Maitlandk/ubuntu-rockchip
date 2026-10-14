# ubuntu-rockchip (Maitlandk fork)

## What this is turning into

Stock Ubuntu on Rockchip boards with **no kernel of our own**: Canonical's
`linux-generic`, mainline U-Boot and the upstream device trees. Everything
after first boot updates with `apt` from the Ubuntu archive. Ubuntu 26.04 LTS
first; Turing RK1 (RK3588) first, other boards as mainline supports them.

What the tree still is today: upstream `Joshua-Riek/ubuntu-rockchip` at
38dfb49 (archived). It builds a vendor kernel from `Joshua-Riek/linux-rockchip`
(a fork of `armbian/linux-rockchip`, i.e. the Rockchip BSP 5.10/6.1 tree) and
pulls PPAs (`jjriek/*`, panfork) that are no longer maintained. All of that
goes away; it is not updated or ported.

Open question #1, answered by `.github/workflows/kernel-config-check.yml`:
does Ubuntu's generic arm64 kernel enable everything the RK3588 and the RK1
need, and does it ship the RK1 device tree?

## Rules

1. **Don't break what runs.** The only test hardware is a production k3s
   node. Nothing we do may be irreversible on it; its NVMe is never written
   by a test.
2. **Upstream first.** No out-of-tree kernel patches. A missing driver is a
   Launchpad bug against Ubuntu's kernel config; a DT or driver bug goes to
   mainline. Anything carried meanwhile links its upstream submission and is
   dropped when merged.
3. **Delete, don't port.** This series should remove far more than it adds.
   If a change grows the tree, ask whether Canonical or mainline already
   ships it.
4. **Small, bisectable commits.** One logical change each, every commit
   builds. Subject `area: summary`, body says *why*. No drive-by cleanups.
5. **Evidence, not "should work".** Hardware claims cite dmesg, a .config,
   a boot log or upstream source. Say what was verified and how.
6. **No workarounds without a root cause**, and every workaround names its bug.

Practical: LF line endings, bash scripts shellcheck-clean, no new
dependencies without a reason in the commit message.

## Layout

- `build.sh` drives `scripts/build-{kernel,u-boot,rootfs,image}.sh` and
  `scripts/config-image.sh`.
- `config/boards/*.sh`: per board (`UBOOT_PACKAGE`, `UBOOT_RULES_TARGET`,
  `COMPATIBLE_SUITES`, hooks). `config/suites/*.sh`: per Ubuntu release
  (`KERNEL_REPO`/`KERNEL_BRANCH`, `EXTRA_PPAS`, all to be removed).
  `config/flavors/`: server, desktop.
- `config/kernel-check/*.txt`: kernel requirement profiles, checked by
  `scripts/check-kernel-config.sh`.
- `packages/u-boot-*`: Debian packaging of U-Boot.
  `u-boot-turing-rk3588` = **mainline** U-Boot @ cb493752 (2024.01) + 3 local
  patches + Rockchip rkbin blobs (DDR init, BL31).
- `overlay/`: files copied into the root filesystem.

## Turing RK1 facts

Verified on a running RK1 (turingnode2, 2026-10-14) unless marked otherwise.

- No SPI flash (`/proc/mtd` is empty). The boot ROM loads U-Boot from the
  eMMC user area (sector 64). Installed: "U-Boot SPL 2024.01 (Jan 28 2024)",
  i.e. this repo's `u-boot-turing-rk3588`.
- U-Boot boot order (patch 0001): `mmc1 nvme scsi usb mmc0 pxe dhcp spi`, so
  NVMe boots before eMMC. `/boot/firmware` is `nvme0n1p1` and `/` is
  `nvme0n1p2`; that U-Boot loads the boot script from the NVMe is inferred
  from the boot order, not observed on the console.
- **The eMMC boot loader region (first 16 MiB) is shared**: the NVMe system
  depends on it. Never overwrite it during a test; back it up before any
  change to it.
- eMMC is 29 GiB: `mmcblk0p1` 512M + `mmcblk0p2` 28.6G (a stale original
  install), plus unused 4 MiB hardware boot partitions.
- Serial console: `ttyS9,115200` on the vendor kernel. Mainline aliases it
  differently (`ttyS0` per Armbian's board config and this repo's oracular
  hook): unverified here.
- Mainline Linux's `rk3588-turing-rk1.dtsi` already has the PCIe 3.0 x4
  CLKREQ pinctrl that U-Boot patch 0002 adds (checked against torvalds/master).
- The node runs with `systemd.unified_cgroup_hierarchy=0` (cgroup v1). That is
  the owner's cluster config, not this repo's; new images must not carry it.

## Testing on hardware

The owner does all hardware work; we provide images, exact commands and
read the logs. A test boot must be non-persistent: interrupt U-Boot on the
BMC serial console (`tpi uart`), boot `mmc0` by hand, and a power cycle
returns the node to its NVMe system.

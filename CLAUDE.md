# ubuntu-rockchip (Maitlandk fork)

## What this is turning into

Stock Ubuntu on Rockchip boards with **no kernel of our own**: Canonical's
`linux-generic`, mainline U-Boot and the upstream device trees. Everything
after first boot updates with `apt` from the Ubuntu archive. Ubuntu 26.04 LTS
first; Turing RK1 (RK3588) first, other boards as mainline supports them.

The tree started as upstream `Joshua-Riek/ubuntu-rockchip` at 38dfb49
(archived), which built a vendor kernel from `Joshua-Riek/linux-rockchip`
(the Rockchip BSP 5.10/6.1 tree) and pulled unmaintained PPAs (`jjriek/*`,
panfork). The kernel build, the PPAs, the other 30 boards and the old
suites are gone (roadmap A1-A4). What is left still builds its root
filesystem with Joshua's `livecd-rootfs` fork until B1 replaces it.

Ubuntu's generic arm64 kernel enables everything the RK3588 and the RK1
need and ships the RK1 device tree (26.04, 7.0.0-38; details in
`docs/ROADMAP.md`, Q1). `.github/workflows/kernel-config-check.yml` keeps
checking that.

**Work is planned in `docs/ROADMAP.md`**, one session per task. Read the
task you were given there before reading code.

## Sessions

`docs/ROADMAP.md` is the plan and the record; it lives in git so every
session reads and updates the same copy.

1. **Start:** `git pull`. Read this file and your task(s) in the roadmap.
   Read only the code the task names until you need more.
2. **Work:** small commits (rule 4), push to `main` as you go. CI builds and
   checks; read results as annotations (below). Do not build images or
   kernels in the session.
3. **Stop and report**, without pushing through, when: the task is clearly
   bigger than its size; CI fails twice on the same problem; the task needs
   an owner decision or hardware; or a fact in this file or the roadmap
   turns out wrong (fix the fact, then stop).
4. **Finish:** update the task's status line, add one line to the session
   log at the end of the roadmap, and fix anything here that your work
   proved or disproved. Commit that as `docs: roadmap: ...` and push. If the
   push races another session, `git pull --rebase` and resolve; the
   roadmap is the only file sessions commonly share.

Scope (owner decision, 2026-10-14): the Turing RK1 (RK3588) only, with its
GPU, NPU, video decode and display in scope.

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

- `build.sh` drives `scripts/build-{u-boot,rootfs,image}.sh` and
  `scripts/config-image.sh`.
- `config/boards/*.sh`: per board (`UBOOT_PACKAGE`, `UBOOT_RULES_TARGET`,
  `COMPATIBLE_SUITES`, hooks); only `turing-rk1.sh` now.
  `config/suites/*.sh`: per Ubuntu release; only `resolute.sh` (26.04).
  `config/flavors/`: server.
- `config/kernel-check/*.txt`: kernel requirement profiles, checked by
  `scripts/check-kernel-config.sh`.
- `packages/u-boot-*`: Debian packaging of U-Boot.
  `u-boot-turing-rk3588` = **mainline** U-Boot v2026.10 + 1 local patch
  (boot order) + Rockchip rkbin blobs (DDR init, BL31).
- `overlay/boot/firmware`: cloud-init seed, copied onto the ESP (partition 1,
  label CIDATA, mounted at `/boot/efi`).

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
- Serial console: `ttyS9,115200` on the vendor kernel, and it is `ttyS9` on
  Ubuntu's too. Mainline's `rk3588-turing-rk1.dts` (v7.0) has `stdout-path =
  "serial9:115200n8"` and `rk3588-base.dtsi` aliases `serial9` to the UART
  at `febc0000`. Ubuntu 26.04's 7.0.0-38 config has
  `SERIAL_8250_RUNTIME_UARTS=32` (and `NR_UARTS=48`, `8250_CONSOLE=y`,
  `DW=y`, `SERIAL_EARLYCON=y`; rootfs-check run 38660291621), so line 9
  exists. `ttyS0` (uart0) is disabled on the RK1: a `console=ttyS0` would
  silence the line and, as a cmdline console, turn off the stdout-path
  fallback. The image therefore sets no `console=` and CI fails if one
  appears on GRUB's command line. Not yet seen on the console; E1 checks
  `/proc/cmdline` and `/sys/class/tty/console/active`.
- **Ubuntu's arm64 `vmlinuz` is an EFI zboot image** (26.04, 7.0.0-38:
  `CONFIG_EFI_ZBOOT=y`, bytes at offset 56 are zero; rootfs-check run
  38655920188). U-Boot's `booti`, which extlinux uses, needs the arm64
  Image magic there, so extlinux cannot boot this kernel. The image boots
  by UEFI instead: U-Boot's distro boot runs `efi/boot/bootaa64.efi` (GRUB)
  from the ESP, partition 1, and `flash-kernel` (used only for that) links
  `/boot/dtb-<kver>` to the kernel's own `rk3588-turing-rk1.dtb`, which
  GRUB's `10_linux` loads with `devicetree`, so the kernel gets Ubuntu's DTB
  and not the one built into U-Boot (2024.01's has no GPU or NPU nodes).
  Proven in CI up to `grub.cfg` (`docs/ROADMAP.md`, B2); U-Boot running
  `bootaa64.efi` and the DTB reaching the kernel are for E1. Read from
  U-Boot v2026.10 source, not seen on the console.
- Mainline v7.0's RK1 device tree already enables the GPU and the three NPU
  cores, and the base dtsi leaves the video decoders enabled; what is
  missing is userspace and display (`docs/ROADMAP.md`, F1-F4).
- Mainline Linux's `rk3588-turing-rk1.dtsi` already has the PCIe 3.0 x4
  CLKREQ pinctrl that U-Boot patch 0002 adds (checked against torvalds/master).
- The node runs with `systemd.unified_cgroup_hierarchy=0` (cgroup v1). That is
  the owner's cluster config, not this repo's; new images must not carry it.

## Reading CI results

From a cloud session, job logs and artifacts are out of reach: the API
redirects them to blob storage the session's network does not allow, and
the web UI wants a sign-in for logs. Annotations are served by the API
directly, so the workflows publish their results as annotations
(`::notice` for the full report, `::error` per failure). To read the
newest run of a workflow:

```sh
repo=Maitlandk/ubuntu-rockchip
run=$(gh api "repos/$repo/actions/workflows/kernel-config-check.yml/runs?per_page=1" \
      --jq '.workflow_runs[0] | "\(.id) \(.status) \(.conclusion) \(.head_sha[:7])"')
echo "$run"
for job in $(gh api "repos/$repo/actions/runs/${run%% *}/jobs" --jq '.jobs[].id'); do
  gh api "repos/$repo/check-runs/$job" --jq '"== \(.name): \(.conclusion)"'
  gh api "repos/$repo/check-runs/$job/annotations" \
     --jq '.[] | "[\(.annotation_level)] \(.path):\(.start_line) \(.title)\n\(.message)\n"'
done
```

New workflows follow the same rule: anything a session needs to read comes
out as an annotation.

## Testing on hardware

The owner does all hardware work; we provide images, exact commands and
read the logs. A test boot must be non-persistent: interrupt U-Boot on the
BMC serial console (`tpi uart`), boot `mmc0` by hand, and a power cycle
returns the node to its NVMe system.

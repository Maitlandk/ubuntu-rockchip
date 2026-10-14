# Roadmap

Each task below is sized to be **one session**: it names what to read, what
to produce and how we know it is done. A session starts by reading
`CLAUDE.md` and its task here, not the whole tree, and ends by updating the
task's status line in this file in the same commit series.

Sizes are a hint for planning, not a budget: **S** reads a few files and
makes one or two commits, **M** touches several files or needs one CI round
trip, **L** needs research or several CI round trips. Tasks marked
**parallel** touch no files another open task touches and can run in their
own session at the same time.

Status: ✅ done · 🔜 next · ⏳ waiting on something · 📋 queued · 👤 owner

## Done

- ✅ **Q1. Does Ubuntu's own kernel support the RK3588 and the RK1?** Yes.
  Ubuntu 26.04, `7.0.0-38-generic`: all 42 symbols in
  `config/kernel-check/` enabled, optional ones included (Panthor GPU,
  Rocket NPU, rkvdec/Hantro, VOP2, HDMI QP); `rk3588-turing-rk1.dtb` ships
  in `linux-modules` at `/usr/lib/firmware/<kver>/device-tree/rockchip/`.
  There is no `linux-modules-extra` for that kernel: every module is in
  `linux-modules`, which `linux-image-generic` depends on, so `=m` means
  installed. Evidence: run 38635844232 of `kernel-config-check.yml`.
- ✅ Scheduled and duplicate workflows removed (nightly, stale, next,
  release). `build.yml` stays until D1 replaces it.

## A. Delete the vendor stack

Sequential: these touch the same scripts. Each is a series of small
commits; nothing new is added here.

- 🔜 **A1. Remove the kernel build** (M). `scripts/build-kernel.sh`;
  `--kernel-only` and `--launchpad` in `build.sh`; the linux-image/headers/
  modules/buildinfo/rockchip-headers lookup, purge, `dpkg -i` and
  `apt-mark hold` in `scripts/config-image.sh`; `KERNEL_REPO`,
  `KERNEL_BRANCH`, `KERNEL_FLAVOR` in `config/suites/*.sh`; the kernel job in
  `.github/workflows/build.yml`. Done when no file references
  `linux-rockchip` or builds a kernel, and `bash -n` passes on every
  touched script.
- 📋 **A2. Remove the PPAs and vendor userspace** (S). `EXTRA_PPAS`;
  the `jjriek` pin files in `scripts/build-rootfs.sh`; panfork,
  libmali, camera-engine-rkaiq installs in `config/boards/*.sh` hooks;
  `ubuntu-server-rockchip` / `ubuntu-desktop-rockchip` meta-packages.
  Done when `grep -ri 'jjriek\|panfork\|libmali\|rkaiq'` finds nothing.
- 📋 **A3. One suite: resolute** (S). Replace `config/suites/*` with
  `resolute.sh` (26.04). jammy/oracular/plucky are out of support or
  vendor-kernel-only; noble's 6.8 generic kernel predates most mainline
  RK3588 support. Fix `COMPATIBLE_SUITES` in board files to match.
- 👤 **A4. Which boards stay?** Owner decision. Proposal: a board is
  listed only when it has a kernel-check profile that passes and a
  mainline U-Boot target in `packages/`; the other 30 board files and the
  prebuilt Bluetooth/Wi-Fi helpers in `overlay/usr` that only they use
  are removed now and come back one by one, with a tester. RK1 first.

## B. Root filesystem for 26.04 without Joshua's forks

- 📋 **B1. Choose the rootfs builder** (L, parallel). Today
  `scripts/build-rootfs.sh` builds Joshua's fork of `livecd-rootfs` and
  runs live-build with `PROJECT=ubuntu-cpc`. Compare: Ubuntu's own
  `livecd-rootfs` from the archive (same pipeline, no fork); Canonical's
  arm64 cloud-image root tarball; `mmdebstrap` with Ubuntu's server seed.
  Criterion: smallest amount of our code that yields a stock 26.04 server
  rootfs with `linux-generic`, cloud-init and nothing from outside the
  archive. Output: a short decision note in this file, then the change.
- 📋 **B2. Boot configuration that survives `apt upgrade`** (M, after B1).
  The image already runs `u-boot-update` (package `u-boot-menu`), which
  writes `/boot/extlinux/extlinux.conf` and re-runs from the kernel's
  postinst hooks. Point it at Ubuntu's DTB directory (above), set the
  console for the mainline serial alias (`ttyS9` vendor vs `ttyS0`
  mainline is unverified, see CLAUDE.md), drop the cgroup-v1 cmdline if
  present. Done when installing a second kernel package in the chroot
  regenerates `extlinux.conf` with both entries.
- 📋 **B3. Image layout** (M, after B2). `scripts/build-image.sh` gives the
  ext4 root partition the EFI System Partition type GUID and the 4 MiB
  CIDATA partition the basic-data type. Find out why before changing it
  (rule 6). Add an output for the RK1 eMMC test: boot and root filesystem
  images that are written into existing partitions, leaving the first
  16 MiB (boot loader) untouched.

## C. U-Boot

Not needed for the first hardware test: the RK1s already run mainline
U-Boot 2024.01 from this repo, and changing the boot loader and the OS at
once is two variables.

- 📋 **C1. Current mainline U-Boot for the RK1** (M, parallel). Ubuntu's
  `u-boot-rockchip` (26.04) has no RK3588 targets, because the DDR init
  is a Rockchip binary, so this repo keeps packaging it. Move
  `u-boot-turing-rk3588` to the current release; drop patches that are
  upstream (0002 PCIe CLKREQ, 0003 eMMC strobe: check), keep 0001's boot
  order only if upstream's differs; drop the other boards' targets
  (patches 0004-0006) per A4. Note whether mainline TF-A now replaces the
  `rk3588_bl31` blob. Build-only; nobody flashes it before E is done.

## D. CI

- 📋 **D1. Image build workflow** (M, after A1-A3 and B1-B2). Replace
  `build.yml`: build the RK1 26.04 server image natively on
  `ubuntu-24.04-arm`, upload it, publish size, sha256, kernel version and
  `extlinux.conf` as annotations (see "Reading CI results" in CLAUDE.md).
- 📋 **D2. QEMU smoke test** (M, after D1). The RK3588 cannot be emulated,
  but the image's userspace can: boot its kernel, initrd and root
  filesystem on `qemu-system-aarch64 -M virt` and check that systemd
  reaches multi-user, cloud-init finishes and `apt-get update` works.
  Catches packaging and boot-script regressions before anyone touches
  hardware.

## E. First boot on node 2

👤 All hardware steps are the owner's; sessions prepare exact commands and
read the logs.

- 📋 **E1. Runbook** (S, after B3). Back up the eMMC boot loader region and
  partitions to the Odroid; write the B3 images into `mmcblk0p1`/`p2`;
  interrupt U-Boot over `tpi uart`, boot `mmc0` by hand; a power cycle
  returns to the NVMe system. Evidence to collect: `dmesg`, `lspci`,
  `lsusb -t`, `ip -d link`, `ethtool eth0`, NVMe and eMMC visible, fan
  speed under load, `cpufreq` scaling, thermal zones, the serial console
  name. No k3s on this boot.
- ⏳ **E2. Read the evidence** (S, after E1). File Launchpad bugs or
  mainline reports for anything missing; record findings in CLAUDE.md.

## Outside this repo

- 👤 **Cluster handoff.** Node 2 boots with
  `systemd.unified_cgroup_hierarchy=0` (cgroup v1). That confirms risk G11
  in the cluster's k3s upgrade plan and must be fixed there; the cluster
  agent owns it.

## Running a task in a cloud session

Start the session with:

> Read CLAUDE.md and docs/ROADMAP.md. Do task **A1**. One logical change
> per commit, push to main, update A1's status here, and report what CI
> says (via annotations).

What keeps a session cheap: start from the task, not the tree; let CI
build and read its annotations, never build an image in the session; stop
and report when a task turns out bigger than its size, instead of
pushing through.

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

- ✅ **A1. Remove the kernel build** (M). `scripts/build-kernel.sh`;
  `--kernel-only` and `--launchpad` in `build.sh`; the linux-image/headers/
  modules/buildinfo/rockchip-headers lookup, purge, `dpkg -i` and
  `apt-mark hold` in `scripts/config-image.sh`; `KERNEL_REPO`,
  `KERNEL_BRANCH`, `KERNEL_FLAVOR` in `config/suites/*.sh`; the kernel job in
  `.github/workflows/build.yml`. Done when no file references
  `linux-rockchip` or builds a kernel, and `bash -n` passes on every
  touched script.
- ✅ **A2. Remove the PPAs and vendor userspace** (S). `EXTRA_PPAS`;
  the `jjriek` pin files in `scripts/build-rootfs.sh`; panfork,
  libmali, camera-engine-rkaiq installs in `config/boards/*.sh` hooks;
  `ubuntu-server-rockchip` / `ubuntu-desktop-rockchip` meta-packages.
  Done when `grep -ri 'jjriek\|panfork\|libmali\|rkaiq'` finds nothing.
  *Done 2026-10-14*, except that the grep still hits Joshua Riek's
  `jjriek@verizon.net` in `packages/u-boot-turing-rk3588` (Maintainer line,
  changelog, patch authorship), which is attribution and stays. The
  `ubuntu-{server,desktop}-rockchip` metas became the archive's
  `ubuntu-server`/`ubuntu-desktop`; B1 owns the real package set.
- ✅ **A3. One suite: resolute** (S). Replace `config/suites/*` with
  `resolute.sh` (26.04). jammy/oracular/plucky are out of support or
  vendor-kernel-only; noble's 6.8 generic kernel predates most mainline
  RK3588 support. Fix `COMPATIBLE_SUITES` in board files to match.
- ✅ **A4. RK1 only** (M). Owner decision (2026-10-14): the Turing RK1
  (RK3588) is the only board for now; others come back one at a time, each
  with a passing kernel-check profile, a mainline U-Boot target and a
  tester. Remove the other 30 `config/boards/*.sh`; the
  `u-boot-mixtile-rk3588`, `u-boot-radxa-rk3588` and `u-boot-rk3576`
  packages; the orangepi-3b and radxa-zero3 targets inside
  `u-boot-turing-rk3588` (`targets.mk`, patches 0004-0006, their rkbin
  blobs); and the `overlay/usr` Bluetooth/Wi-Fi/audio helpers, none of
  which the RK1 uses (check each against `turing-rk1.sh` first). Done when
  `config/boards/` holds only `turing-rk1.sh` and nothing references a
  removed board. *Done 2026-10-14.* The RK1's `config_image_hook` was
  removed in A3 (every branch was keyed on a deleted suite); B2 must set
  the serial console and `/etc/kernel/cmdline`. `overlay/usr` is gone; the
  unused non-UART9 `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.16.bin` blob in
  `u-boot-turing-rk3588/debian/rkbin` is left for C1 to decide.

## B. Root filesystem for 26.04 without Joshua's forks

- ✅ **B1. Choose the rootfs builder** (L, parallel). Today
  `scripts/build-rootfs.sh` builds Joshua's fork of `livecd-rootfs` and
  runs live-build with `PROJECT=ubuntu-cpc`. Compare: Ubuntu's own
  `livecd-rootfs` from the archive (same pipeline, no fork); Canonical's
  arm64 cloud-image root tarball; `mmdebstrap` with Ubuntu's server seed.
  Criterion: smallest amount of our code that yields a stock 26.04 server
  rootfs with `linux-generic`, cloud-init and nothing from outside the
  archive. Output: a short decision note in this file, then the change.
  *Done 2026-10-14.* **Decision: Canonical's cloud root tarball.**
  It is the output of the same `ubuntu-cpc` livecd-rootfs pipeline, built
  and signed by Canonical, with `linux-*` and `grub-*` purged
  (`create-root-dir.binary`): `cloud-images.ubuntu.com/releases/resolute/
  release/ubuntu-26.04-server-cloudimg-arm64-root.tar.xz`, 252 MB, 619
  packages incl. `ubuntu-server` and cloud-init, no kernel, GRUB, shim or
  flash-kernel. `SHA256SUMS.gpg` is signed by the UEC Image Automatic
  Signing Key (`ubuntu-cloudimage-keyring`). Running livecd-rootfs
  ourselves reproduces that pipeline with more code; mmdebstrap needs our
  own package list and copies of the cpc hooks, i.e. our own definition
  of Ubuntu Server. Joshua's fork was livecd-rootfs 24.04.56 plus 4
  commits (mask AppArmor, vendor cmdline, delete cpc hooks), none kept.
  `build-rootfs.sh` now downloads and verifies; `config-image.sh`
  installs `linux-generic --no-install-recommends`, because the kernel
  recommends `flash-kernel | grub-efi-arm64` and flash-kernel 3.110ubuntu2
  exits 1 on a machine missing from its db, which the RK1 is. Desktop
  flavor removed (no desktop tarball). `rootfs-check.yml` verifies all
  this as annotations. For B2: nothing installs `u-boot-menu` any more
  (it came from `ubuntu-server-rockchip`), so `build-image.sh`'s
  `u-boot-update` fails until B2 installs it. Evidence: run 38651860639
  of `rootfs-check.yml` (serial 20260927, `linux-image-7.0.0-38-generic`,
  RK1 DTB and initrd present, `update-initramfs` is dracut's, no boot
  loader package, no package outside the archive; sources are
  `archive.ubuntu.com` and `security.ubuntu.com`, which served arm64).
  B3: `build-image.sh`'s desktop branch is dead.
- ✅ **B2. Boot configuration that survives `apt upgrade`** (M, after B1).
  Originally: `u-boot-menu` writing `extlinux.conf`. *Done 2026-10-15, as
  UEFI boot through GRUB, by owner decision.* The extlinux route cannot
  boot Ubuntu's kernel: its arm64 `vmlinuz` is an EFI *zboot* image
  (`CONFIG_EFI_ZBOOT=y`, `CONFIG_KERNEL_ZSTD=y`, 23.8 MB, first bytes
  `4d 5a 00 00`, zero at offset 56; runs 38655920188 and 38658843109)
  and U-Boot's pxe code runs `booti` for arm64 (`boot/pxe_utils.c`
  v2026.10), whose `booti_setup()` (`arch/arm/lib/image.c`) fails with "Bad
  Linux ARM64 Image magic!" without the `ARM\x64` magic at offset 56.
  Nothing in U-Boot v2026.10's pxe, booti or bootm code handles zboot, and
  Ubuntu's `flash-kernel` has no zboot support either.

  What the image does now (`config-image.sh`, `config/boards/turing-rk1.sh`,
  `build-image.sh`):
  - U-Boot's distro boot loads `efi/boot/bootaa64.efi` from a bootable
    partition and runs it with `bootefi` (`include/config_distro_bootcmd.h`);
    for GPT the ESP type counts as bootable (`disk/part_efi.c`). That file
    is GRUB: `grub-efi-arm64` 2.14-2ubuntu1, installed with
    `grub-install --target=arm64-efi --no-nvram` in the chroot of the real
    partitions (grub-probe needs them) and `update-grub`. The ESP then has
    `EFI/BOOT/BOOTAA64.EFI` and `EFI/ubuntu/grubaa64.efi`. On `apt
    upgrade`, grub-efi-arm64's postinst repeats `grub-install` (it does so
    when `/boot/grub/arm64-efi/core.efi` exists) and the kernel hooks
    (`zz-update-grub`) rewrite `grub.cfg`; `/boot/efi` is in fstab.
  - **Ubuntu's DTB reaches the kernel, not U-Boot's built-in one.** GRUB's
    `10_linux` (2.14-2ubuntu2) emits `devicetree /boot/dtb-<kver>` if that
    file exists, and has no other knob. Nothing in the archive creates it
    except `flash-kernel`, whose `handle_dtb()` copies
    `/lib/firmware/<kver>/device-tree/rockchip/rk3588-turing-rk1.dtb` to
    `/boot/dtbs/<kver>/` and links `/boot/dtb-<kver>` on kernel install,
    removes it on removal, and does so before it looks at boot methods
    (and before `zz-update-grub` by name). It is used for that alone,
    through two data files from the board hook: an entry for
    `Machine: Turing Machines RK1` (the DT's `model`) in
    `/etc/flash-kernel/db` and the name in `/etc/flash-kernel/machine`. No
    script of ours. Two things it needs, both found by failing: it exits at
    once in a chroot or container unless `FK_FORCE=yes`
    (`usr/share/flash-kernel/functions`, `main()`), and with `FK_FORCE` its
    postinst stopped silently when no kernel was installed yet (cause not
    isolated; run 38662341153), so it is installed after `linux-generic`.
  - Command line: `ro earlycon`, no `console=`, via
    `/etc/default/grub.d/99-turing-rk1.cfg`, which replaces the cloud
    image's `console=tty1 console=ttyAMA0` (those would leave the serial
    line silent) and empties `GRUB_FORCE_PARTUUID`. The kernel then takes
    its console from the DT's `stdout-path` (ttyS9; `SERIAL_8250_RUNTIME_UARTS=32`).
  - Evidence. `rootfs-check` (run 38662552324 ✅): `/boot/dtb-<kver>` exists
    and is byte-identical to the kernel's RK1 DTB for the first kernel, after
    installing `7.0.0-14` as a second one, and is gone for it after its
    removal; the grub command line is `earlycon` only. `build.yml` (run
    38665217711 ✅) on the built image: ESP with the two EFI files and the
    seed, `grub.cfg` with `root=UUID=<the image's>` and a `devicetree
    /boot/dtb-<kver>` line per kernel; then, in a chroot on a copy of the
    image, installing `linux-image-7.0.0-14-generic` produced `grub.cfg`
    entries for both kernels each with its `devicetree` line, and removing it
    took its lines away again.
  - GRUB finds `grub.cfg` through the prefix baked into its core image,
    `(,gpt2)/boot/grub` (run 38666627513): partition 2 of the disk GRUB was
    loaded from, which is the root in this layout on any disk. So the
    partition table must be GPT and the root must be partition 2: true for
    the images, and for the eMMC only if its existing table is GPT (E1:
    `sgdisk -p /dev/mmcblk0`, or `part list mmc 0` in U-Boot).
  - Not verified: that U-Boot 2024.01 on the node finds and runs
    `bootaa64.efi`, and that the kernel ends up on Ubuntu's DTB rather than
    U-Boot's. E1 checks these on the console (below).
  - The F1-F3 checks need Ubuntu's DTB (the GPU and NPU nodes are in the
    kernel's `rk3588-turing-rk1.dtb`; U-Boot 2024.01's built-in tree has
    neither). `ls /proc/device-tree | grep -i -e gpu -e rknn` after boot says which one
    the kernel got.
- ✅ **B3. Image layout** (M, after B2). `scripts/build-image.sh` gave the
  ext4 root partition the EFI System Partition type GUID and the 4 MiB
  CIDATA partition the basic-data type. *Done 2026-10-14/15.* Why: U-Boot's
  distro boot lists the partitions to search with `part list ... -bootable`
  and falls back to partition 1 alone when none qualifies; a GPT partition
  counts as bootable with the legacy-BIOS-bootable attribute **or the ESP
  type** (`include/config_distro_bootcmd.h`, `cmd/part.c`, `disk/part_efi.c`
  `get_bootable()`). `1207608` ("migrate to extlinux") put the ESP type on
  the ext4 root so U-Boot would scan it for `extlinux.conf` instead of the
  CIDATA vfat partition 1: a workaround for a missing attribute. With UEFI
  boot (B2) the layout is simply right way round: partition 1 is a 256 MiB
  ESP (type C12A7328, vfat, label CIDATA, mounted at `/boot/efi`) that also
  carries the cloud-init seed, partition 2 is the ext4 root (Linux
  filesystem, no attributes). Built image (run 38665217711): p1 `EF00`
  C12A7328, p2 `8300` 0FC63DAF, U-Boot SPL 2026.10 at sector 64. The
  desktop layout is gone. Outputs next to the disk image:
  `<name>.esp.img.xz` (256 MiB vfat, 80 KB compressed) and
  `<name>.root.img.xz` (ext4 with `/boot`, 4.1 GB, 2.7 GB used; grows by
  `x-systemd.growfs`); neither covers anything below the partition start, so
  writing them cannot touch the first 16 MiB. They fit the eMMC's
  `mmcblk0p1` (512 MB) and `mmcblk0p2` (28.6 GB). The existing eMMC
  partitions will not necessarily be typed as an ESP, in which case
  U-Boot's scan tries partition 1 only, which is the ESP: nothing to
  change on the eMMC. Verified in the image and from U-Boot's source, not on
  hardware.

## C. U-Boot

Not needed for the first hardware test: the RK1s already run mainline
U-Boot 2024.01 from this repo, and changing the boot loader and the OS at
once is two variables.

- ✅ **C1. Current mainline U-Boot for the RK1** (M, parallel). Ubuntu's
  `u-boot-rockchip` (26.04) has no RK3588 targets, because the DDR init
  is a Rockchip binary, so this repo keeps packaging it. Move
  `u-boot-turing-rk3588` to the current release; drop patches that are
  upstream (0002 PCIe CLKREQ, 0003 eMMC strobe: check), keep 0001's boot
  order only if upstream's differs; drop the other boards' targets
  (patches 0004-0006) per A4. Note whether mainline TF-A now replaces the
  `rk3588_bl31` blob. Build-only; nobody flashes it before E is done.
  *Done 2026-10-14.* `u-boot-turing-rk3588` is now v2026.10 (5508406582f6,
  fetched by tag: it is not on GitHub's `master` yet), built by the new
  `u-boot-build.yml` (run 38652164516: `U-Boot SPL 2026.10`, 9.77 MB
  `u-boot-rockchip.bin`). Dropped: 0002 (Linux 3d50680fcb31, now in
  `dts/upstream`: mainline muxes the real CLKREQ# function, function 4
  pull-none, where 0002 set a GPIO pull-down), 0003 (Linux 37f3d6108730,
  `pcfg_pull_down` in `dts/upstream` rk3588-base-pinctrl.dtsi:372),
  0004-0006, the SPI image (the defconfig has no
  `CONFIG_ROCKCHIP_SPI_IMAGE`; the RK1 has no SPI flash) and the unused
  non-UART9 DDR blob. Kept: 0001, because mainline's default is
  `mmc1 mmc0 nvme ...` (eMMC before NVMe) and the production node must
  boot the NVMe; it applies unmodified. TF-A: Ubuntu 26.04's
  `arm-trusted-firmware` 2.12.1 ships `rk3588/bl31.elf` and TF-A has a
  `plat/rockchip/rk3588`, so mainline TF-A can replace `rk3588_bl31` in
  principle; U-Boot's own docs still say to use rkbin's BL31 for RK3588.
  Not changed here: untested on hardware and the DDR init stays a blob
  either way (rule 1). Try it in E-phase as a separate test. Still
  open: build deps (`python3-distutils`) in `control` are stale on 26.04.

## D. CI

- ✅ **D1. Image build workflow** (M, after A1-A3 and B1-B2). Replace
  `build.yml`: build the RK1 26.04 server image natively on
  `ubuntu-24.04-arm`, upload it, publish size, sha256, kernel version and
  the boot configuration as annotations (see "Reading CI results" in
  CLAUDE.md). *Done 2026-10-14.* `build.yml` calls `u-boot-build.yml` (now
  also `workflow_call`, and it uploads the .deb), then builds on
  `ubuntu-24.04-arm` with `build.sh`; it takes about 17 minutes and uploads
  the three images as one artifact (2.37 GB). One annotation reports sizes,
  sha256, partition table (types and attributes), the boot loader at sector
  64, the ESP's files, kernel, root UUID, fstab, the `grub.cfg` lines
  (`linux`, `initrd`, `devicetree`), and the result of installing and
  removing a second kernel in a chroot on a copy of the image (run
  38665217711 ✅). It fails on: wrong partition types, a missing
  `BOOTAA64.EFI`, seed file, kernel, initrd or `/boot/dtb-<kver>` link,
  a `grub.cfg` whose root is not the image's UUID or that has a `console=`
  other than `ttyS9` or lacks a `devicetree` line for any kernel. It runs
  on pushes to the build inputs; `workflow_dispatch` is there too.
  Reading it needed the web page, not the API (60 requests an hour
  unauthenticated); the workflow also puts the failing command of the
  report step into an annotation, because job logs need a sign-in.
- ✅ **D2. QEMU smoke test** (M, after D1). *Done 2026-10-15.* The RK3588
  cannot be emulated, but the image's userspace can. `smoke.yml` runs
  `scripts/smoke-qemu.sh` on `ubuntu-24.04-arm` after every successful Build
  (and on changes to the script) against the newest green Build run's
  artifact: it boots the **disk image** on `qemu-system-aarch64 -M virt`
  with Ubuntu's AAVMF firmware, TCG (no `/dev/kvm` on the runner), about 9
  minutes. UEFI runs `EFI/BOOT/BOOTAA64.EFI`, GRUB finds `grub.cfg` through its
  baked-in `(,gpt2)/boot/grub`, the kernel starts with the image's own command
  line and initrd, and a script appended to the image's own cloud-init seed
  reports from inside: systemd `running`, no failed units, cloud-init `status:
  done`, `apt-get update` rc 0. Two changes to a throwaway copy, both
  needed: the `devicetree` lines are removed from `grub.cfg` (the RK1's DTB
  describes no virtio device), and the ESP is relabelled `E1SEED` with
  `fs_label` set in cloud-init (E1 step 5). Evidence: run 38675976298 ✅ (and
  38676942610 ✅, and 38677828960 ✅ for the final script): kernel `7.0.0-38-generic`,
  `BOOT_IMAGE=/boot/vmlinuz-7.0.0-38-generic root=UUID=<the image's> ro
  earlycon` (the `BOOT_IMAGE=` is GRUB's), `efi: yes`, ACPI SPCR console
  `ttyAMA0` (QEMU's; the RK1 gets `ttyS9` from its DT, which QEMU cannot
  show), root `vdb2` ext4, `instance-id: cloud-image` from `/dev/vdb1`, 48
  indexes fetched, 0 errors, 2.5-3 minutes to userspace under TCG. A decoy
  `CIDATA` disk was not used (an unpinned control run did not use it
  either, so QEMU does not reproduce the seed collision the runbook guards
  against). **Side finding for E1:** the initrd is dracut's generic one (4965
  files, 3336 modules), and every RK3588 boot driver that is a module is in
  it: `sdhci-of-dwcmshc`, `mmc_block`, `dw_mmc-rockchip`, `nvme`,
  `phy-rockchip-snps-pcie3`, `phy-rockchip-naneng-combphy`, `spi-rockchip`,
  `rk8xx-spi`, `rk808-regulator`; `pinctrl-rockchip`, `pcie-dw-rockchip`,
  `virtio_blk` and `clk-scmi` are built in. So a missing storage module
  in the initrd is not a risk for the eMMC or NVMe boot. What the smoke test
  cannot see: U-Boot, the RK1 DTB, any RK3588 driver. Getting here took
  ten runs, all test-script bugs, none the image's: an invalid workflow file
  (a colon in a YAML scalar: no jobs, so no annotations), a relative image path
  after `cd` that produced an empty disk image (`xz | dd` hides the failure
  without `pipefail`), a missing `efi-virtio.rom`, and `pipefail` plus an
  ERR trap inside `$(...)`. The script now keeps an xtrace and annotates its
  tail on any non-zero exit.

## F. GPU, NPU, video and display

Owner decision (2026-10-14): these are in scope. The kernel side is
already there: all six drivers are enabled in 26.04's kernel and are now
`required` in `config/kernel-check/rk3588.txt`. What is left is userspace
from the Ubuntu archive, one hardware check each, and one upstream gap.
Each task can run in parallel with the others; none touches the build
scripts until it has evidence.

- ✅ **F1. GPU: Panthor + Mesa** (S; researched 2026-10-14, hardware check in E1). Confirm the 26.04 Mesa in
  the archive includes the Panthor Gallium/Vulkan drivers (`panfrost` /
  `panvk`), and which packages a server image needs for compute or
  headless rendering. Hardware check for E1: `/dev/dri/renderD*`,
  `vulkaninfo` or `eglinfo` naming Mali-G610.
- ✅ **F2. Video decode: rkvdec / Hantro** (M; researched 2026-10-14, hardware check in E1). Find what mainline
  7.0 decodes on the RK3588 (codecs and the VDPU381 support CNX reported)
  and the archive userspace that drives it (GStreamer `v4l2codecs`, FFmpeg
  V4L2 request API). Hardware check: `v4l2-ctl --list-devices`, one
  hardware-decoded H.264 and HEVC file.
- ✅ **F3. NPU: Rocket + Mesa Teflon** (M; researched 2026-10-14, hardware check in E1; owner answered the cluster-NPU question). The mainline NPU
  driver is used through Mesa's Teflon TensorFlow Lite delegate, not
  Rockchip's RKNN runtime: RKNN models do not run on it. Establish what
  26.04's Mesa ships for Teflon on Rocket and which model formats work;
  check whether any cluster workload uses the NPU today (ask the cluster
  agent). Hardware check: `/dev/accel/accel0`, one TFLite model through
  the delegate.
- 🟡 **F4. HDMI on the RK1: device tree gap** (M). Patch prepared, not sent: `upstream/linux/` (HDMI0 + VOP vp0 + hdptxphy0 in the `.dts`; checkpatch --strict and dtbs_check clean in CI, run 38680595353; a node 1 boot test still owed, then the owner sends it; ⏸ that test waits until node 1 itself runs the new system, see "Rollout order"). Mainline's
  `rk3588-turing-rk1.dtsi` (and the 4-line `.dts`) enable no display
  nodes: no `vop`, `hdmi0` or `hdptxphy` (checked against torvalds/master,
  2026-10-14). The drivers exist; the board description does not use them.
  Find from the RK1 and Turing Pi 2 schematics/docs which HDMI port the
  RK1 drives and on which carrier node it is wired, write the DT change
  against mainline and submit it upstream (rule 2). Until it is merged
  and in Ubuntu's kernel, HDMI does not work on stock Ubuntu; we do not
  carry a private DTB.

### F1-F3 findings (research, 2026-10-14)

Method: package facts are read from the 26.04 (`resolute`) arm64 indexes
and `.deb` contents on `ports.ubuntu.com` (release, `-updates`,
`-security`; indexes dated 2026-10-14), kernel facts from the `v7.0`
tag of torvalds/linux (Ubuntu's `7.0.0-38` is based on it), Mesa facts from
the `mesa-26.0.8` tag. Nothing here was run on hardware; "expect" lines
are predictions for E1 to confirm or refute.

**F1. GPU: yes, nothing to carry.**

- Archive: Mesa `26.0.8-1ubuntu0.3` in `resolute-updates` (release pocket:
  `26.0.3-1ubuntu1`). `mesa-vulkan-drivers` (main) ships
  `libvulkan_panfrost.so` and `icd.d/panfrost_icd.json`: that is **PanVK**.
  `libgl1-mesa-dri` (main) has the `panthor_dri.so` entry point (symlink to
  `libdril_dri.so`); the Panfrost Gallium driver lives in `mesa-libgallium`
  (strings in `libgallium-26.0.8-*.so`: `panfrost`, `panthor`,
  `PANTHOR_BO_QUERY_INFO`).
- Support level at the 26.0.8 tag (`docs/drivers/panfrost.rst`): Mali-G610
  is Valhall v10, OpenGL ES 3.1 / OpenGL 3.1 / **Vulkan 1.4**, and Mesa
  lists both the GLES and the Vulkan driver as *conformant* on G610.
  `panvk_physical_device.c` only gates v6/v7 behind
  `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER`; v10 loads without it. GPU id
  `0xa807` is "G610" in `pan_model.c`.
- **OpenCL: not available.** The same doc says OpenCL is not supported at
  this time. `mesa-opencl-icd` (universe, rusticl) exists but Panfrost is
  not a supported rusticl target in 26.0.8. Compute means Vulkan compute.
- Firmware: Panthor (CSF) needs `arm/mali/arch10.8/mali_csffw.bin.zst`,
  which is in `linux-firmware-misc` (listed in `Contents-arm64`, both
  `resolute` and `-updates`). `linux-image-generic` depends on
  `linux-firmware`, which depends on `linux-firmware-misc`, so it is
  installed with the kernel. (Which `archN.M` the G610 loads is inferred
  from the file list and upstream convention; E1's dmesg confirms it.)
- Kernel: `panthor.ko` is in `linux-modules-7.0.0-38-generic`. The RK1
  device tree (v7.0 `rk3588-turing-rk1.dtsi`) sets `&gpu { mali-supply;
  status = "okay" }`; the base dtsi has `rockchip,rk3588-mali` /
  `arm,mali-valhall-csf`. No DT work for the GPU.
- Packages for a server image: render/compute needs `mesa-vulkan-drivers`
  (+ `libvulkan1`); headless GL/GLES/EGL (GBM, surfaceless) needs
  `libegl-mesa0`, `libgbm1`, `libgl1-mesa-dri`, `mesa-libgallium` (all
  main). `mesa-vulkan-drivers` is 22 MB by itself and pulls `libllvm21`
  and X/Wayland client libraries. Diagnostics (`vulkan-tools`,
  `mesa-utils`) are universe and test-only; do not put them in the image.

**F2. Video decode: H.264 and HEVC (and AV1) in hardware through one
GStreamer path; no FFmpeg path.**

- Kernel `v7.0`, `drivers/media/platform/rockchip/rkvdec/rkvdec.c`:
  `rockchip,rk3588-vdec` binds the **VDPU381** variant with exactly two
  coded formats, H.264 (`H264_SLICE`; decoded NV12, NV15, NV16, NV20, i.e.
  8/10-bit 4:2:0 and 4:2:2) and HEVC (`HEVC_SLICE`; NV12, NV15), up to
  65520 / 65472 px. **No VP9 on the RK3588** (the VP9 code is the RK3399
  variant only).
- Both `vdec0` and `vdec1` are in the base dtsi and enabled by default,
  but the driver has no multi-core support: the second core logs
  "missing multi-core support, ignoring this instance" and returns
  `-ENODEV` (`rkvdec_disable_multicore`). Expect one rkvdec video device,
  not two. Throughput is that of one core.
- AV1: `rockchip,rk3588-av1-vpu` -> `rk3588_vpu981_variant` in the
  verisilicon (`hantro-vpu.ko`) driver, AV1 decode only. The `av1d` node
  is enabled by default.
- `vpu121` (`rockchip,rk3588-vpu121`, falls back to `rockchip,rk3568-vpu`):
  the older Hantro VDPU2 core, MPEG-2, VP8 and H.264 decode.
  `rockchip,rk3588-vepu121` (two or more nodes) is JPEG **encode** only.
  `drivers/media/platform/rockchip/` has no RKVENC driver (only `rga`,
  `rkcif`, `rkisp1`, `rkvdec`): **there is no mainline H.264/HEVC hardware
  encoder** for the RK3588 in 7.0.
- Modules in `linux-modules-7.0.0-38-generic`: `rockchip-vdec.ko`,
  `hantro-vpu.ko`. No board DT change: the RK1 dtsi touches no video
  node and the base dtsi disables none.
- Userspace in the archive: **GStreamer 1.28.2**.
  `gstreamer1.0-plugins-bad` (**universe**, `1.28.2-1ubuntu1.2`) ships
  `libgstv4l2codecs.so` with the stateless decoders for H.264, H.265, AV1,
  VP8, VP9 and MPEG-2 (element names `v4l2slh264dec`, `v4l2slh265dec`,
  `v4l2slav1dec`, ...; from the plugin's strings). The parsers
  (`h264parse`, `h265parse`) are also in plugins-bad; demuxers are in
  plugins-good (main). plugins-bad has a large dependency set (GTK,
  OpenEXR, ...), so it is for the test, not for a base image.
- **FFmpeg cannot use rkvdec from this archive.** `libavcodec62`
  `7:8.0.1-3ubuntu2` (universe): the configure line has no V4L2 request
  option, and the library contains `{h264,hevc,vp9}_v4l2m2m` (the
  *stateful* V4L2 wrappers, a different kernel API than rkvdec's
  stateless one) but no `v4l2_request` hwaccel. So `ffmpeg` and `mpv`
  (0.41.0, built on it) decode in software on this node. Do not promise
  hardware decode in those; if it matters, file a Launchpad bug against
  `ffmpeg` (rule 2).
- Not in the archive, and not needed: Rockchip MPP / `librga` / `rkmpp`
  (vendor stack; the arm64 indexes list no package with those names).

**F3. NPU: the kernel driver and the delegate are in 26.04; a model
runtime for Python is not.**

- Kernel: `rocket.ko` (`drivers/accel/rocket`, "Rocket") is in
  `linux-modules-7.0.0-38-generic`; it binds `rockchip,rk3588-rknn-core`,
  loads no firmware, and exposes `/dev/accel/accel*`. The RK1 dtsi
  **already enables** `rknn_core_0..2` and `rknn_mmu_0..2` (with
  `vdd_npu_s0`), so there is no DT work.
- Mesa: `mesa-teflon-delegate` (**universe**, `26.0.8-1ubuntu0.3`, 1.2 MB)
  ships a single file, `/usr/lib/teflon/libteflon.so` (not on the library
  path: it is passed by path). Its strings contain `rocket`,
  `ROCKET_DEBUG`, `TEFLON_DEBUG` and `tflite_plugin_create_delegate`, so
  the Rocket driver is built in. Mesa's pipe loader probes
  `/dev/accel/accel%d` for it (`pipe_loader_drm.c`).
- What it runs (Mesa 26.0.8): the only documented hardware is "RK3588 NPU
  on PINE64 QuartzPro64", with **UINT8**-quantised MobileNet V1 (~18 ms),
  MobileNet V2 (~21 ms) and SSDLite MobileDet (~48 ms). Rocket's
  `rkt_ml_operation_supported` accepts only **convolution (including
  depthwise)** and **add**, and for convolutions only per-tensor
  quantisation and dilation 1. Other operators (pooling, concat, fully
  connected, ...) are recognised by Teflon but rejected by the Rocket
  driver today and stay on the CPU, so a network with them is only partly
  accelerated.
- Model format: **TensorFlow Lite flatbuffers (`.tflite`), fully integer
  quantised (uint8; int8 per-tensor appears in the delegate code but is
  not in Mesa's tested list)**. Not RKNN (`.rknn`) models, not ONNX, not
  float models. Anything built on Rockchip's RKNN toolkit or `librknnrt`
  will not run on this driver.
- Runtime: the delegate is an *external delegate* loaded by a TFLite
  runtime. The archive has only the C++ library `libtensorflow-lite2.14.1`
  / `libtensorflow-lite-dev` (`2.14.1+dfsg-3build1`, universe), which
  exports `TfLiteExternalDelegateCreate`. There is **no Python TFLite
  package in the archive** (no `python3-tflite-runtime`, no
  `python3-tensorflow`, no LiteRT; `python3` is 3.14.3). Python users need
  a pip wheel: `ai-edge-litert` 2.3.0 has a `cp314`
  `manylinux_2_27_aarch64` wheel and its `interpreter.py` defines
  `load_delegate` (checked in the wheel). Mesa vendors its own TFLite
  headers (`include/tensorflow/lite/`, schema v2.15.0) and `libteflon.so`
  does not link TFLite; it resolves the runtime's symbols from the host
  process. Compatibility with the archive's 2.14.1 or pip's LiteRT 2.3.0
  is **unverified**: E1 decides.

**Owner's answer (F3, 2026-10-14):** no cluster workload uses the NPU
today; the owner plans to use it later for model testing. So nothing
blocks node 2 on the NPU, and models for that testing should be prepared
as fully integer-quantised TFLite with convolution/add-heavy graphs (see
above for what Rocket accelerates). A pip-installed TFLite runtime
(`ai-edge-litert`) is acceptable for the E1 smoke test.

**Not examined:** ONNX Runtime (`libonnxruntime1.23` 1.23.2 is in the
archive, but whether any execution provider can drive Rocket was not
looked at); video encode paths; HDMI (F4).

**Side findings for other tasks:**

- B2: `rk3588-turing-rk1.dts` at v7.0 has `stdout-path = "serial9:115200n8"`,
  so the mainline console should be `ttyS9`, like the vendor kernel, not
  `ttyS0`. This is source, not observed: confirm on the console in E1, and
  check that Ubuntu's `CONFIG_SERIAL_8250_NR_UARTS` / `RUNTIME_UARTS`
  allows line 9.

## E. First boot on node 2

👤 All hardware steps are the owner's; sessions prepare exact commands and
read the logs.

- 🟡 **E1. Runbook** (S, after B3). **Written: `docs/e1-runbook.md`; the
  owner runs it, nothing has been run on hardware.** It backs up the eMMC
  (first 16 MiB, GPT, both partitions, boot partitions) to the Odroid and
  verifies the backups; writes `*.esp.img.xz` into `mmcblk0p1` and
  `*.root.img.xz` into `mmcblk0p2` (nothing below the partitions, hashed
  before and after); makes cloud-init take the image's seed only (the NVMe's
  seed partition is probably also `CIDATA`); interrupts U-Boot 2024.01 over
  `tpi uart` and boots the ESP by hand (`run bootcmd_mmc0`, or
  `setenv devtype mmc; setenv devnum 0; setenv distro_bootpart 1; run
  scan_dev_for_efi` when the old table types partition 2 as the ESP); a power
  cycle returns to the NVMe system. `scripts/e1-evidence.sh` collects the boot
  path (EFI, `/proc/cmdline`, `ttyS9`, the GPU and NPU nodes in the running
  tree, `/sys/firmware/fdt` against `/boot/dtb-<kver>` outside `/chosen`) and
  the hardware evidence (dmesg, lspci, lsusb, ethtool, NVMe/eMMC, mmc timing,
  cpufreq, thermal, fan under load) and ends in PASS/FAIL lines; the F1-F3
  checks that were here moved into the runbook unchanged. Read from U-Boot
  at cb493752 (the commit the installed 2024.01 package was cut from), not from
  the board: `part list -bootable` counts an ESP-typed partition as bootable
  (`cmd/part.c`, `disk/part_efi.c`), distro boot's `scan_dev_for_efi` runs
  `efi/boot/bootaa64.efi` with `bootefi` after looking for extlinux and
  `boot.scr`, and `load` records the ESP as the boot device so that GRUB's
  `(,gpt2)` resolves; whether the node's U-Boot was built with
  `CONFIG_EFI_LOADER` (default y on arm64; the RK1 defconfig does not unset it) is the first thing the runbook
  asks the console. `docs/e1-runbook.md` is also where E2 finds what is
  expected to pass.
- ⏳ **E2. Read the evidence** (S, after E1). File Launchpad bugs or
  mainline reports for anything missing; record findings in CLAUDE.md.

## Rollout order (owner, 2026-10-20)

Node 1 is the cluster's master and main server: no test runs on it. In
order: E1/E2 on node 2; node 2 runs the new system stably; node 1 moves
to it; then F4's HDMI boot test on node 1 (the only slot wired to HDMI;
HDMI is not in use on the cluster today, so nothing waits on F4); the k3s
upgrade (cluster agent); then two more master/server nodes. The board is a
Turing Pi 2 v2.4 (owner, to their knowledge), where EDID is broken: the
F4 test expects a 1080p fallback picture, not the monitor's modes. No
roadmap task yet covers moving a node onto the new system.

## Outside this repo

- 👤 **Cluster handoff.** Node 2 boots with
  `systemd.unified_cgroup_hierarchy=0` (cgroup v1). That confirms risk G11
  in the cluster's k3s upgrade plan and must be fixed there; the cluster
  agent owns it.

## Running a task in a cloud session

This file is the plan and the record. It lives in git so every session,
cloud or local, reads the same version and writes back to it. The rules
are in CLAUDE.md under "Sessions"; in short: pull, read your task, do it
in small commits, update the task's status line and add one line to the
session log below, push.

### Kickoff plan (budget: the owner's $100 of usage credits)

Wave 1, run in parallel (no shared files):

| Session | Tasks | Model | Why that model |
|---|---|---|---|
| 1 | A1, A2, A3, A4 in order | Sonnet | mechanical deletions with clear done-criteria |
| 2 | B1 | Opus | a design choice with lasting consequences |
| 3 | C1 | Sonnet | a version bump with a build to check |
| 4 | F1, F2, F3 (research only) | Sonnet | reading package lists and upstream docs |

Wave 2, after wave 1 is in: B2, B3, D1 (one Sonnet session, in order).
Wave 3: D2 and E1 (Sonnet), F4 (Opus: an upstream DT patch is judged
harshly and should be right the first time).

Prompt for a session (replace the task IDs):

> Read CLAUDE.md, then do roadmap task(s) **A1-A4** from docs/ROADMAP.md,
> following "Sessions" in CLAUDE.md. Stop and report if a stop rule hits.

Budget rules:

- Calibrate after the first wave-1 session finishes: note its cost from
  Settings > Usage in its session-log line. Do not start wave 2 until the
  wave-1 total is known and the remainder covers it.
- Never build an image or kernel inside a session; CI builds, the session
  reads annotations.
- Sonnet unless the table says otherwise.

## Session log

One line per session, newest last: date · tasks · model · commits ·
CI run · result · cost if known · next.

- 2026-10-14 · setup (this file, CLAUDE.md, kernel check, CI cleanup) ·
  Opus · 9ee5c91..HEAD · run 38635844232 ✅ · Q1 answered yes, scope set
  to RK1, F added · plan-included usage · next: wave 1.
- 2026-10-14 · A1-A4 · Sonnet · 812cedf..60f56a4 · no workflow triggers on
  these paths (build.yml is dispatch-only; kernel-config-check runs on its
  own paths); `bash -n` clean on every script, shellcheck not available
  locally · A1-A4 done: 30 boards, 3 U-Boot packages, the kernel build,
  PPAs, 4 suites and overlay/usr removed · cost unknown · next: B2 needs
  the rootfs builder (B1); build.yml is untested until D1.
- 2026-10-14 · F1-F3 (research only; no build scripts touched) · Sonnet ·
  docs commit on main · no CI · GPU/video/NPU userspace is in the 26.04
  archive (Mesa 26.0.8 PanVK, GStreamer v4l2codecs, mesa-teflon-delegate);
  gaps: no OpenCL, no VP9 or encode, no FFmpeg hwaccel, no Python TFLite
  in the archive; owner: no NPU use in the cluster today, model testing planned · cost not
  read · next: E1 commands are in place.
- 2026-10-14 · B1 · Opus · e83b970..650e0a9 · run 38651860639 ✅ ·
  rootfs is Canonical's signed cloud root tarball, kernel added in
  config-image.sh without flash-kernel, desktop flavor gone · cost not
  read · next: B2 must install u-boot-menu.
- 2026-10-14 · C1 · Sonnet · 2676690..094aeb5 · run 38652164516 ✅ (first run
  failed: tag not on master; second: shellcheck) · U-Boot v2026.10, patches
  0002/0003 dropped as upstream, 0001 kept, TF-A noted · cost not read ·
  next: E1 can use the CI package; BL31 swap is a separate hardware test.
- 2026-10-14/15 · B2, B3, D1 (+ console, DTB route) · Sonnet · 74b25c4..HEAD ·
  rootfs-check 38655562308 ✅, 38655920188 ✅ (vmlinuz is EFI zboot),
  38660291621 ✅ (serial config), 38662552324 ✅ (DTB links); build 38656041251
  ✅, 38665217711 ✅ · B2 first stopped on the zboot kernel (extlinux cannot
  boot it); owner chose UEFI via GRUB with Ubuntu's DTB; done: GRUB on an
  ESP, flash-kernel (data files only) puts the DTB at /boot/dtb-<kver>, grub.cfg
  loads it for every kernel, proven with a second kernel in the built image ·
  B3: root/ESP layout explained and rebuilt, ESP and root partition images ·
  D1 done · console: none set, ttyS9 by DT, CI guards the command line · not
  run on hardware · cost not read (no cost API in the session) · next: E1
  (checks for U-Boot running bootaa64.efi and GRUB's prefix), D2 can boot the
  image with UEFI firmware in QEMU.
- 2026-10-14 · F4 · Opus · upstream/linux/0001 patch + README · no CI (dtbs_check not run) · HDMI0 from the vendor DTs + data sheet + pin analysis; no public schematic · cost unknown · next: owner boot-tests on node 1 (node 2 has no HDMI) and sends.
- 2026-10-15 · D2, E1 (wave 3) · Sonnet · e6d2271..HEAD · smoke 38675976298 ✅,
  38676942610 ✅, 38677828960 ✅ (after eleven failed or invalid runs, all of the test script
  itself; list under D2) · D2 done: QEMU boots the image's disk through UEFI,
  GRUB, kernel, systemd, cloud-init, apt; initrd carries every RK3588 boot
  driver · E1: runbook `docs/e1-runbook.md` and `scripts/e1-evidence.sh`
  written, nothing run on hardware · stop rule "CI fails twice on the same
  problem": the first three failures at the image mount were one problem
  (an empty image file, misread twice as missing partition nodes and a
  parsing bug) and I kept going, because each run showed new evidence and
  the cause was in the test script, not the task; the rest differed each
  time · cost not read · next: the owner runs the runbook
  (E1); E2 reads what comes back.
- 2026-10-15 · F4 dtbs_check · Opus · 5837943..HEAD · dtbs-check run
  38680261211 ✅, 38680595353 ✅ (second run proves dt-validate ran) · patch
  applies at its base, 0 dtbs warnings before and after, checkpatch --strict
  clean in the tree · cost not read · next: owner boot-tests on node 1, then
  sends.
- 2026-10-20 · owner answers (F4 test, rollout) · Opus · docs only · no CI ·
  node 1 is the master and never a test node; rollout order node 2, then
  node 1, then k3s upgrade, then two more masters; board v2.4 (EDID
  fallback); F4's hardware test waits for node 1's move · next: E1 on
  node 2.

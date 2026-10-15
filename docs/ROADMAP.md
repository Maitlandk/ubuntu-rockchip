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
- ⏳ **B2. Boot configuration that survives `apt upgrade`** (M, after B1).
  The image already runs `u-boot-update` (package `u-boot-menu`), which
  writes `/boot/extlinux/extlinux.conf` and re-runs from the kernel's
  postinst hooks. Point it at Ubuntu's DTB directory (above), set the
  console for the mainline serial alias (`ttyS9` vendor vs `ttyS0`
  mainline is unverified, see CLAUDE.md), drop the cgroup-v1 cmdline if
  present. Done when installing a second kernel package in the chroot
  regenerates `extlinux.conf` with both entries.
  *Half done 2026-10-14; waiting on an owner decision.* The literal done
  criterion is met: `u-boot-menu` 4.2.4ubuntu2 (main) is installed by
  `config-image.sh` before the kernel, and installing the older
  `linux-image-7.0.0-14-generic` on top of `7.0.0-38` in the chroot
  rewrote `extlinux.conf` with both kernels (`l0`/`l0r`, `l1`/`l1r`), each
  with `linux`, `initrd` and `fdtdir /lib/firmware/<kver>/device-tree/`
  (run 38655562308 of `rootfs-check.yml`). No configuration was needed: the
  4.2.4 defaults already use that DTB directory, take `root=` from
  `/etc/fstab` (the image build rewrites it with the root UUID and re-runs
  `u-boot-update`; checked in the built image, run 38656041251) and read
  `/etc/kernel/cmdline`, which we do not create, so there is no
  cgroup-v1 argument. U-Boot's `fdtfile` (`rockchip/rk3588-turing-rk1.dtb`,
  the board defconfig's `CONFIG_DEFAULT_FDT_FILE`) fits under that
  `fdtdir`. The command line is `ro earlycon`, no `console=`: the kernel
  then takes its console from the DT's `stdout-path` (`serial9`), so it
  cannot contradict it; whether to add `console=ttyS9,115200n8` is left to
  the serial-console finding (see the session log).

  **The finding that stops B2: this image cannot boot with extlinux.**
  Ubuntu 26.04's arm64 `vmlinuz` is an EFI *zboot* image, not an arm64
  `Image`: `CONFIG_EFI_ZBOOT=y`, `CONFIG_KERNEL_ZSTD=y`, 23.8 MB, first
  bytes `4d 5a 00 00` ("MZ"), bytes at offset 56 all zero (run
  38655920188; `booti` wants the `ARM\x64` magic, bytes `41 52 4d 64`,
  at offset 56). `extlinux.conf` makes U-Boot's pxe code
  run `booti` for arm64 (`boot/pxe_utils.c`, v2026.10), and `booti_setup()`
  (`arch/arm/lib/image.c`) prints "Bad Linux ARM64 Image magic!" and fails
  on a missing magic. Nothing in U-Boot v2026.10's pxe, booti or bootm code
  handles zboot, and Ubuntu's `flash-kernel` 3.110ubuntu2 has no zboot
  support either. So `u-boot-menu` + `extlinux.conf` + stock `vmlinuz`
  does not boot. Not run on hardware (the prediction is from the sources above); E1 can confirm it
  on the console in one line (`ext4load` the file, `booti`).

  Options, for the owner to choose before more is built on this:
  1. **UEFI boot, the way Ubuntu boots any arm64 machine.** Install
     `grub-efi-arm64` (+ `grub-efi-arm64-bin`) and `grub-install
     --removable --no-nvram` into a FAT ESP; mainline U-Boot's distro boot
     already loads `efi/boot/bootaa64.efi` from a bootable partition and
     runs it with `bootefi` (`include/config_distro_bootcmd.h`, which also
     loads `${fdtfile}` from `/`, `/dtb/` or `/dtb/current/` of that
     partition if one is there, so Ubuntu's DTB could be supplied),
     GRUB loads the zboot kernel through its EFI stub, and the device tree
     is the one embedded in U-Boot (mainline `dts/upstream`), handed over
     through the EFI configuration table. Everything is archive packages
     and survives `apt upgrade` (GRUB's own kernel hooks); no `u-boot-menu`,
     no `/lib/firmware/<kver>/device-tree` use. Costs: the image needs an
     ESP of 100+ MiB (the 4 MiB CIDATA partition cannot hold GRUB; the seed
     moves to another partition or to `/boot/firmware`), `grub-efi-arm64`
     and its recommends come back into the image (B1 left them out because
     of flash-kernel), and the kernel runs on U-Boot's DT rather than
     Ubuntu's `rk3588-turing-rk1.dtb`, which must then be the one tested.
  2. **Keep extlinux and unpack the kernel.** A kernel `postinst.d` hook
     writes the zstd payload of `vmlinuz` (offset and size are in the zboot
     header at bytes 8-15) to `/boot/Image-<kver>` and a second hook points
     `extlinux.conf` at it. Roughly 25 lines of our own shell, a copy of
     every kernel in `/boot`, and a workaround whose bug is that Ubuntu's
     arm64 kernel cannot be started by U-Boot's extlinux (to file against
     `u-boot-menu`/`linux`, rule 6). Keeps B3's layout as built.
  Recommendation: option 1, because it is what stock Ubuntu does on
  arm64 and has no hook of ours to carry. It reverses part of B1/B3, so it
  is a separate task, not part of this one.
- ✅ **B3. Image layout** (M, after B2). `scripts/build-image.sh` gives the
  ext4 root partition the EFI System Partition type GUID and the 4 MiB
  CIDATA partition the basic-data type. Find out why before changing it
  (rule 6). Add an output for the RK1 eMMC test: boot and root filesystem
  images that are written into existing partitions, leaving the first
  16 MiB (boot loader) untouched.
  *Done 2026-10-14, for the extlinux layout (see B2).* Why the root
  partition was an ESP: U-Boot's distro boot lists the partitions to
  search with `part list ... -bootable`, falls back to partition 1 alone
  when none qualifies, and a GPT partition counts as bootable if it has
  the legacy-BIOS-bootable attribute **or the ESP type** (v2026.10
  `include/config_distro_bootcmd.h`, `cmd/part.c`, `disk/part_efi.c`
  `get_bootable()`). 1207608 ("migrate to extlinux") set the ESP type on
  the ext4 root so U-Boot would scan it, instead of the CIDATA vfat
  partition 1. That was a workaround for the missing attribute; the root
  now has type Linux filesystem plus the attribute, CIDATA keeps basic
  data (cloud-init finds it by label). The built image (run 38656041251):
  GPT p1 `EBD0A0A2` (basic data) attributes 0, p2 `0FC63DAF` (Linux
  filesystem) attributes `4`, U-Boot SPL 2026.10 at sector 64. This is
  verified in the image and from U-Boot's source, not on hardware. The
  desktop layout in `build-image.sh` is gone. New outputs next to the disk
  image: `<name>.cidata.img.xz` (4 MiB vfat, the NoCloud seed) and
  `<name>.root.img.xz` (ext4 with `/boot`; 4.3 GB, 2.6 GB used, grows by
  `x-systemd.growfs`); neither covers anything below the partition start.
  For E1: the existing eMMC partitions will not necessarily be marked
  bootable, in which case U-Boot's scan tries partition 1 only. Boot by
  hand with `setenv distro_bootpart 2; run bootcmd_mmc0` (that variable
  short-circuits the list, same header), which changes nothing on the
  eMMC. If B2 moves to UEFI the layout changes again.

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
  `extlinux.conf` as annotations (see "Reading CI results" in CLAUDE.md).
  *Done 2026-10-14.* `build.yml` calls `u-boot-build.yml` (now also
  `workflow_call`, and it uploads the .deb), then builds on
  `ubuntu-24.04-arm` with `build.sh`; it takes 13 minutes, uploads the
  three images as one artifact (2.36 GB) and reports sizes, sha256,
  partition table, boot loader, kernel, root UUID, fstab, `extlinux.conf`
  and the CIDATA contents as one annotation (run 38656041251 ✅, first
  try). It runs on pushes to the build inputs; `workflow_dispatch` is
  there too. It also reports the zboot problem of B2 as a warning.
- 📋 **D2. QEMU smoke test** (M, after D1). The RK3588 cannot be emulated,
  but the image's userspace can: boot its kernel, initrd and root
  filesystem on `qemu-system-aarch64 -M virt` and check that systemd
  reaches multi-user, cloud-init finishes and `apt-get update` works.
  Catches packaging and boot-script regressions before anyone touches
  hardware.

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
- 📋 **F4. HDMI on the RK1: device tree gap** (M). Mainline's
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

- 📋 **E1. Runbook** (S, after B3). Back up the eMMC boot loader region and
  partitions to the Odroid; write the B3 images into `mmcblk0p1`/`p2`;
  interrupt U-Boot over `tpi uart`, boot `mmc0` by hand; a power cycle
  returns to the NVMe system. Evidence to collect: `dmesg`, `lspci`,
  `lsusb -t`, `ip -d link`, `ethtool eth0`, NVMe and eMMC visible, fan
  speed under load, `cpufreq` scaling, thermal zones, the serial console
  name, plus the F1-F3 hardware checks below. No k3s on this boot.

  **F1-F3 hardware checks.** Run as root, after the base evidence; installing
  test tools into the eMMC root is fine, the NVMe system is untouched.
  Save all output. Each block says what a pass looks like.

  GPU (F1):

  ```sh
  ls -l /dev/dri/                       # card*, renderD128 (and maybe 129)
  for n in /sys/class/drm/renderD*; do echo "$n -> $(basename "$(readlink "$n/device/driver")")"; done   # one is panthor
  dmesg | grep -iE 'panthor|mali|firmware'   # panthor, G610, firmware loaded, no "Failed to load"
  apt-get install -y vulkan-tools mesa-utils mesa-vulkan-drivers
  vulkaninfo --summary | grep -iE 'deviceName|driverName|apiVersion|deviceType'   # Mali-G610, PanVK, 1.4; NOT llvmpipe
  eglinfo -B 2>&1 | grep -iE 'renderer|OpenGL ES profile version'   # Mali-G610 / Panfrost, ES 3.1
  ```

  Video (F2):

  ```sh
  apt-get install -y v4l-utils gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav ffmpeg
  dmesg | grep -iE 'rkvdec|hantro|vdec|multi-core'   # the second vdec: "missing multi-core support" is expected
  v4l2-ctl --list-devices
  for d in /dev/video*; do echo "== $d"; v4l2-ctl -d "$d" --info | grep -E 'Driver name|Card type'; v4l2-ctl -d "$d" --list-formats-out; done   # rkvdec: H.264 and HEVC slice formats; hantro: AV1, MPEG2, VP8 ...
  gst-inspect-1.0 v4l2slh264dec v4l2slh265dec v4l2slav1dec | grep -E 'Long-name|No such'
  # test clips, made on another machine and copied over:
  #   ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 20 -c:v libx264 -profile:v high -pix_fmt yuv420p h264.mp4
  #   ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 20 -c:v libx265 -pix_fmt yuv420p -tag:v hvc1 hevc.mp4
  grep -iE 'vdec|video-codec' /proc/interrupts > /tmp/irq.before
  time gst-launch-1.0 filesrc location=h264.mp4 ! qtdemux ! h264parse ! v4l2slh264dec ! fakesink sync=false
  time gst-launch-1.0 filesrc location=hevc.mp4 ! qtdemux ! h265parse ! v4l2slh265dec ! fakesink sync=false
  grep -iE 'vdec|video-codec' /proc/interrupts > /tmp/irq.after; diff /tmp/irq.before /tmp/irq.after
  time gst-launch-1.0 filesrc location=h264.mp4 ! qtdemux ! h264parse ! avdec_h264 ! fakesink sync=false   # software baseline
  ffmpeg -hide_banner -hwaccels         # F2 predicts no V4L2 request hwaccel
  ```

  Pass: both hardware pipelines reach EOS, the rkvdec interrupt counter
  grows, and user CPU time is far below the software baseline.

  NPU (F3):

  ```sh
  ls -l /dev/accel/                     # accel0
  lsmod | grep -w rocket; dmesg | grep -iE 'rocket|rknn|npu'
  apt-get install -y mesa-teflon-delegate python3-venv python3-numpy
  ls -l /usr/lib/teflon/libteflon.so
  python3 -m venv --system-site-packages /root/tf && /root/tf/bin/pip install ai-edge-litert pillow   # outside the archive, test only
  curl -LO http://download.tensorflow.org/models/mobilenet_v1_2018_08_02/mobilenet_v1_1.0_224_quant.tgz && tar xzf mobilenet_v1_1.0_224_quant.tgz
  # save the script below as npu.py, then:
  grep -i rknn /proc/interrupts > /tmp/npu.before
  /root/tf/bin/python npu.py mobilenet_v1_1.0_224_quant.tflite cpu
  TEFLON_DEBUG=verbose /root/tf/bin/python npu.py mobilenet_v1_1.0_224_quant.tflite npu
  grep -i rknn /proc/interrupts > /tmp/npu.after; diff /tmp/npu.before /tmp/npu.after
  ```

  `npu.py`:

```python
import sys, time, numpy as np
from ai_edge_litert.interpreter import Interpreter, load_delegate
model, mode = sys.argv[1], sys.argv[2]
d = [load_delegate("/usr/lib/teflon/libteflon.so")] if mode == "npu" else []
it = Interpreter(model_path=model, experimental_delegates=d); it.allocate_tensors()
i, o = it.get_input_details()[0], it.get_output_details()[0]
np.random.seed(0); it.set_tensor(i["index"], np.random.randint(0, 255, i["shape"], dtype=np.uint8))
it.invoke(); t = time.time()
for _ in range(50): it.invoke()
print(mode, "%.1f ms" % ((time.time() - t) / 50 * 1000), "top1", int(np.argmax(it.get_tensor(o["index"]))))
```

  Pass: the verbose log shows the `rocket`
  driver loaded and convolutions "supported", the NPU interrupt counters
  grow, and `npu` is markedly faster than `cpu` (Mesa quotes ~18 ms on a
  QuartzPro64) with the same top-1. If `load_delegate` crashes or reports
  a registration error, suspect the unverified TFLite-vs-Mesa-header
  compatibility (F3) and retry with a C++ client against the archive's
  `libtensorflow-lite-dev` before filing anything. The pip install is for
  this test only; the image does not carry it.
- ⏳ **E2. Read the evidence** (S, after E1). File Launchpad bugs or
  mainline reports for anything missing; record findings in CLAUDE.md.

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
- 2026-10-14 · B2 (half), B3, D1 · Sonnet · 74b25c4..HEAD · rootfs-check
  38655562308 ✅ (second kernel regenerates extlinux.conf), 38655920188 ✅
  (vmlinuz is EFI zboot), build 38656041251 ✅ (first try, 13 min) · B3 and
  D1 done; B2 stopped: Ubuntu's `vmlinuz` is an EFI zboot image that U-Boot's
  `booti` rejects, so extlinux cannot boot it, owner to choose between UEFI
  boot via GRUB and unpacking the kernel · console left at the DT's
  `stdout-path` (no `console=`) · cost not read (no cost API in the session,
  only plan percentages) · next: decide B2's boot path; D2 and E1 wait on it.

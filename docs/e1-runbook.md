# E1 runbook: first boot of the stock Ubuntu image on the RK1

The owner does every step on hardware; a session reads what comes back
(E2). Nothing here is irreversible, and the commands are written so that a
wrong paste fails before it writes. Read it through once before starting.

**What we test:** the image of a successful `build.yml` run, written into
the eMMC partitions of the production node, started by hand from U-Boot
2024.01 (the boot loader the node runs today, unchanged), once, without
touching the NVMe system. A power cycle returns the node to its NVMe system.

**What each step can touch** (rule 1):

| Step | Reads | Writes |
|---|---|---|
| 2 pre-flight | NVMe system (it is running), eMMC | nothing |
| 3 backups | eMMC (first 16 MiB, GPT, both partitions, boot partitions) | files on the Odroid |
| 4 write | the images | `/dev/mmcblk0p1`, `/dev/mmcblk0p2`: the stale install on the eMMC |
| 5 seed | eMMC partitions | the label of `mmcblk0p1`, one file in `mmcblk0p2` |
| 6 test boot | the eMMC, U-Boot RAM | RAM; the eMMC (the test system's own files) |
| 9 return | everything | nothing |

Never written: the NVMe (`/dev/nvme0n1*`: not mounted, not fsck'd, not
trimmed, not formatted, by anything in this runbook); the eMMC below
partition 1, i.e. the boot loader at sector 64 and the GPT in sectors
0-33 (images are written *into* partitions; step 3 hashes the first 16 MiB
before and step 9 after to prove it); the eMMC hardware boot partitions;
U-Boot's environment (never `saveenv`; the node's U-Boot has no SPI flash).

**Stop and report, without trying to fix it,** when any of these happens;
each is marked with STOP below:

- `mmcblk0` is not the 29 GiB eMMC with a GPT of two partitions, or either
  partition is mounted or in use;
- the NVMe system refers to a filesystem label that the images will put on
  the eMMC (step 2);
- a backup does not verify;
- the first 16 MiB of the eMMC differ from the backup at any later point;
- U-Boot has no `bootefi` command or no `scan_dev_for_efi` (step 6);
- the node does not come back to its NVMe system after a power cycle.

## 0. Names used below

```sh
# on the Odroid (the workstation that holds the backups and the images)
NODE=turingnode2                # ssh name of the production node; its BMC slot is N
N=2                             # BMC slot of that node: confirm in step 1 before any tpi power command
BMC=root@turingpi               # the Turing Pi 2 BMC
B=~/rk1-e1                      # backups and evidence live here
mkdir -p "$B" && cd "$B"
```

`sudo` on the node must work without a prompt for the ssh commands below
(or run them from a shell on the node and move the files with `scp`).

## 1. Get the image and decide it is the right one

1. Pick the newest green run of the **Build** workflow on `main`, and a green
   **Smoke test** run for the same commit (it boots that image on QEMU: GRUB
   finds `grub.cfg`, systemd, cloud-init and `apt-get update` work). Both
   publish annotations; the Build one lists the file sizes and sha256.
2. Download its artifact `ubuntu-26.04-server-turing-rk1` (a zip, about
   2.4 GB; the web UI wants a GitHub sign-in) to `$B/image/`, unzip it. It
   holds three files and their `.sha256`:
   `ubuntu-26.04-preinstalled-server-arm64-turing-rk1.img.xz` (whole disk,
   **not used here**), `….esp.img.xz` (256 MiB vfat: GRUB and the cloud-init
   seed) and `….root.img.xz` (ext4 with `/boot`).
3. Verify, and compare with the sha256 in the Build annotation:

   ```sh
   cd "$B/image" && sha256sum -c ./*.sha256 && sha256sum ./*.xz
   ESP=$(ls "$PWD"/*.esp.img.xz); ROOT=$(ls "$PWD"/*.root.img.xz)
   ```
4. Cluster side (the cluster agent's, not this repo's): cordon and drain
   `turingnode2`. The test boot has the same MAC, so it takes the node's DHCP
   address and answers SSH with a different host key (`ssh-keygen -R` it
   afterwards); k3s is not in the image and does not run.
5. Confirm the BMC slot before any `tpi power` command (`N`): the node's own
   console must show it.

   ```sh
   ssh $BMC tpi power status
   ssh $BMC "tpi uart --node $N get" | tail -n 5     # the last console lines of slot $N: hostname, login prompt
   ```

   The prompt must say `turingnode2`. If it does not, `N` is wrong: stop,
   because `tpi power` on the wrong slot powers off another production node.

## 2. Pre-flight on the running node (read-only)

```sh
ssh $NODE '
  set -x
  uname -a; cat /proc/cmdline
  sudo lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTTYPENAME,MOUNTPOINTS
  sudo blkid
  findmnt -n -o SOURCE,TARGET | grep -E "mmcblk|nvme"
  sudo sgdisk -p /dev/mmcblk0
  sudo sgdisk -i 1 /dev/mmcblk0; sudo sgdisk -i 2 /dev/mmcblk0
  ls /proc/mtd /dev/mmcblk0boot0 /dev/mmcblk0boot1; cat /proc/mtd
  echo "seed keys:"; grep -oE "^[A-Za-z_]+:" /boot/firmware/user-data | sort -u | xargs
  echo "seed mentions of k3s/token/rancher: $(grep -ciE "k3s|token|rancher" /boot/firmware/user-data)"
  grep -rIhE "LABEL=|PARTLABEL=" /etc/fstab /boot/firmware /boot/extlinux 2>/dev/null
' 2>&1 | tee "$B/preflight.txt"
```

Read it, and check each of these. **STOP** if one fails.

- `/dev/mmcblk0` is about 29.1 GiB, `sgdisk -p` says `GPT: present` (not "Found
  invalid GPT and valid MBR"), and it lists partition 1 of about 512 MiB and
  partition 2 of about 28.6 GiB. Neither has a mount point and `findmnt`
  printed no `mmcblk` line. (Partition 1 is where the ESP image goes,
  partition 2 the root image. The GRUB in the image finds its `grub.cfg`
  as `(,gpt2)/boot/grub`: partition 2 of the disk it was loaded from, so
  the table must be GPT and the root must be partition 2.)
- Note partition 2's type GUID from `sgdisk -i 2`. If it is
  `C12A7328-F81F-11D2-BA4B-00A0C93EC93B` (the old image layout put the ESP
  type on the root), U-Boot's `run bootcmd_mmc0` scans partition 2 only, finds
  no `bootaa64.efi` there, and step 6 must use its second form. Nothing to
  change on the disk.
- **Labels.** The images carry the labels `CIDATA` (ESP) and `cloudimg-rootfs`
  (root), which Joshua's images, and so probably this node, also use. Look
  at what the NVMe system refers to by label: the last `grep` above, and
  `blkid`. Boot paths and `fstab` of the NVMe system must use `UUID=`/
  `PARTUUID=`. If anything uses `LABEL=CIDATA` or `LABEL=cloudimg-rootfs`
  (or the other label of the stale eMMC partitions), **STOP**: after the
  write there would be a different filesystem with that label.
- **The NVMe system's cloud-init seed** (`/boot/firmware/user-data`; the
  output above lists its top-level keys and counts words, never values, so
  `preflight.txt` can be shared; do not paste the file itself, it may hold
  keys or tokens):
  if it is also labelled `CIDATA` (`blkid /dev/nvme0n1p1`), cloud-init on the
  test boot could read it instead of the image's own seed, and run whatever
  it holds (users, hostname, packages, commands) on the test system. Step 5
  prevents that by making cloud-init look for another label. The QEMU smoke
  test boots the image with exactly that setting and a decoy `CIDATA` disk
  attached, and the guest uses the image's own seed (`instance-id:
  cloud-image`, from the relabelled ESP), so the setting works and does not
  lock the image out of its seed. It did not show the collision itself: an
  unpinned control run also took the image's seed (which of two `CIDATA`
  devices cloud-init meets first is blkid's order, unknown on the node). If the seed holds
  anything that would reach the cluster (`k3s`, join tokens, a registry
  login), say so in the report; step 5 is then not optional.

## 3. Backups, to the Odroid, and verify them

Everything is read from the live node; nothing is written to it. The
eMMC is not in use by the NVMe system, so two reads of the same device agree.

```sh
cd "$B"
S="ssh $NODE"
# partition table and the first 16 MiB (boot loader at sector 64, the GPT in front of it)
$S 'sudo sfdisk -d /dev/mmcblk0' > emmc-gpt.sfdisk                 # text, for reading
$S 'sudo dd if=/dev/mmcblk0 bs=512 skip=$(( $(sudo blockdev --getsz /dev/mmcblk0) - 33 )) count=33 status=none' > emmc-gpt-tail.img   # the backup GPT at the end
$S 'sudo dd if=/dev/mmcblk0 bs=1M count=16 status=none' > emmc-first16MiB.img
$S 'sudo dd if=/dev/mmcblk0 bs=1M count=16 status=none | sha256sum' | tee emmc-first16MiB.sha
sha256sum emmc-first16MiB.img                        # equal to the line above
strings -n 8 emmc-first16MiB.img | grep -m1 'U-Boot SPL'   # "U-Boot SPL 2024.01 (Jan 28 2024)"
# the two partitions, compressed
$S 'sudo dd if=/dev/mmcblk0p1 bs=4M status=none | zstd -T0 -3' > emmc-p1.img.zst
$S 'sudo dd if=/dev/mmcblk0p2 bs=4M status=none | zstd -T0 -3' > emmc-p2.img.zst     # 28.6 GiB read; minutes
# the hardware boot partitions (read-only devices)
for b in boot0 boot1; do $S "sudo dd if=/dev/mmcblk0$b bs=1M status=none" > emmc-$b.img; done
# the NVMe's partition table and boot partition file list, for the record (read-only)
$S 'sudo sgdisk -p /dev/nvme0n1; ls -lR /boot/firmware | head -n 80' > nvme-record.txt
```

Verify (hash what was read against a second read of the device, and test the
archives):

```sh
zstd -t emmc-p1.img.zst emmc-p2.img.zst
for p in 1 2; do
  a=$(zstd -dc emmc-p$p.img.zst | sha256sum | cut -d' ' -f1)
  b=$($S "sudo sha256sum /dev/mmcblk0p$p" | cut -d' ' -f1)
  [ "$a" = "$b" ] && echo "p$p OK $a" || echo "p$p MISMATCH $a $b"
done
for b in boot0 boot1; do
  [ "$(sha256sum < emmc-$b.img | cut -d' ' -f1)" = "$($S "sudo sha256sum /dev/mmcblk0$b" | cut -d' ' -f1)" ] && echo "$b OK" || echo "$b MISMATCH"
done
ls -l "$B"
```

**STOP** unless every line says OK (and `strings` found the SPL banner). The
backups are the way back: step 10.

## 4. Write the test system into the eMMC partitions

The images are written *into* the partitions that exist; `of=` is never the
whole disk. The ESP image (256 MiB) is smaller than partition 1 (512 MiB),
which is fine: the rest stays unused.

```sh
cd "$B"
S="ssh $NODE"
# last look: right device, nothing mounted, both partitions big enough
$S 'lsblk -b -o NAME,SIZE,MOUNTPOINTS /dev/mmcblk0; ! findmnt -rn -S /dev/mmcblk0p1 && ! findmnt -rn -S /dev/mmcblk0p2 && echo "not mounted: ok"'

xz -dc "$ESP"  | $S 'sudo dd of=/dev/mmcblk0p1 bs=4M conv=fsync status=none'
xz -dc "$ROOT" | $S 'sudo dd of=/dev/mmcblk0p2 bs=4M conv=fsync status=none'
$S 'sudo sync'

# verify what is on the eMMC against the images
for pair in "p1:$ESP" "p2:$ROOT"; do
  p=${pair%%:*}; f=${pair#*:}
  size=$(xz -dc "$f" | wc -c)
  want=$(xz -dc "$f" | sha256sum | cut -d' ' -f1)
  got=$($S "sudo head -c $size /dev/mmcblk0$p | sha256sum" | cut -d' ' -f1)
  [ "$want" = "$got" ] && echo "$p written OK" || echo "$p MISMATCH"
done
# the boot loader region is as it was
[ "$($S 'sudo dd if=/dev/mmcblk0 bs=1M count=16 status=none | sha256sum')" = "$(cat emmc-first16MiB.sha)" ] && echo "first 16 MiB unchanged" || echo "FIRST 16 MiB CHANGED"
```

**STOP** on any MISMATCH or CHANGED (the last would be a bug in this runbook;
restore from `emmc-first16MiB.img` only with the session's go-ahead, since
it writes to the boot loader region).

## 5. Make cloud-init take the image's seed only

The image's seed is on partition 1, found by the label `CIDATA`, like the
NVMe system's. This makes cloud-init look for the label `E1SEED` instead, on
the eMMC only (cloud-init's `fs_label` for NoCloud, `DataSourceNoCloud`):

```sh
$S 'sudo fatlabel /dev/mmcblk0p1 E1SEED && sudo fatlabel /dev/mmcblk0p1'      # prints E1SEED
$S 'set -e; sudo mkdir -p /mnt/e1root; sudo mount /dev/mmcblk0p2 /mnt/e1root
    printf "datasource:\n  NoCloud:\n    fs_label: E1SEED\n" | sudo tee /mnt/e1root/etc/cloud/cloud.cfg.d/99-e1-seed.cfg
    sudo umount /mnt/e1root; sudo sync'
$S 'sudo blkid /dev/mmcblk0p1 /dev/mmcblk0p2'
```

Both are on the eMMC (`fatlabel` does not touch the filesystem's UUID, which
`/etc/fstab` of the image uses). The image's own `user-data` creates the user
`ubuntu` with password `ubuntu`, to be changed at first login.

## 6. The test boot

Interrupt U-Boot, boot `mmc0` by hand, never persist anything.

1. Open the node's serial console (115200 8N1) and log it. Either
   `ssh -t $BMC` and the BMC's terminal program for the slot's UART (see the
   Turing Pi documentation for the device name of slot $N), or the `tpi`
   route below. Keep a log file in `$B` (`script -f "$B/e1-console.log"` on
   the Odroid before the `ssh`).
2. Reboot the node from its own OS (equivalent to a power cycle for this
   purpose, and it needs no BMC power command): `ssh $NODE sudo systemctl reboot`,
   and press Enter repeatedly on the console as soon as U-Boot prints
   `Hit any key to stop autoboot`. With `tpi` only, from the BMC:
   `for i in $(seq 80); do tpi uart --node $N set --cmd ' '; sleep 0.25; done` (with
   the number from step 1 for `$N`), then `tpi uart --node $N get` to read what U-Boot
   printed. (The `tpi uart` syntax is the vendor's; adapt it to your `tpi --help`.)
   Without the interrupt the node simply boots its NVMe system again; nothing
   is lost, repeat.
3. At the `=>` prompt (U-Boot 2024.01; the boot order patched to `mmc1 nvme scsi
   usb mmc0 pxe dhcp spi` is why this must be by hand):

   ```
   mmc list
   mmc dev 0
   part list mmc 0
   part list mmc 0 -bootable devplist
   printenv devplist boot_targets fdtfile scan_dev_for_efi boot_efi_binary
   help bootefi
   ```

   Expected: `mmc list` shows the eMMC as `0` (`mmc@fe2e0000`); `part list` shows
   the 512M and 28.6G partitions; `devplist` holds `1` (the ESP type makes
   partition 1 "bootable" for distro boot; `1 2` or `2` if the old table typed the
   root as an ESP); `scan_dev_for_efi` and `boot_efi_binary` are defined and
   `bootefi` exists. **STOP** if `bootefi` is unknown or `scan_dev_for_efi`
   is not set: this U-Boot cannot run `bootaa64.efi`, and the plan then needs
   the v2026.10 U-Boot from C1 on the eMMC, a boot loader change the owner and
   the session must decide first.

4. Boot. First form:

   ```
   run bootcmd_mmc0
   ```

   Second form, if `devplist` is `2` (or the first form fell through): select the ESP by hand,
   whatever the partition types say:

   ```
   setenv devtype mmc; setenv devnum 0; setenv distro_bootpart 1; run scan_dev_for_efi
   ```

   What each outcome means, in order of appearance:

   | Console | Meaning |
   |---|---|
   | `Scanning mmc 0:1...` then `Found EFI removable media binary efi/boot/bootaa64.efi` | **U-Boot ran the ESP's `bootaa64.efi` (GRUB).** Evidence for B2's open question. |
   | `EFI LOAD FAILED: continuing...` or nothing after `Scanning` | U-Boot found no file or could not start it: send the console log. |
   | GRUB's menu, or nothing, then `EFI stub: Booting Linux Kernel...` | GRUB read its `grub.cfg` (a hidden menu is normal) and started the kernel. |
   | `grub>` prompt | GRUB did not find `grub.cfg`: run `ls`, then `ls (hd0,gpt2)/boot/grub/` (try `hd1`), `echo $prefix $root`, `configfile (hd0,gpt2)/boot/grub/grub.cfg`, and send what they print. Do not reset: the log is the evidence. |
   | `EFI stub: ...` lines, then silence | the kernel started, console or DT problem: wait two minutes, then send the log. |
   | kernel messages on `ttyS9`, then `ubuntu login:` | boot path works; go to step 7. |

   Harmless: `EFI stub: EFI_RNG_PROTOCOL unavailable` and `KASLR disabled due to
   lack of seed` (U-Boot 2024.01 has no EFI RNG here), U-Boot's own warnings
   about the `fdt` it passes on.
5. Log in as `ubuntu`/`ubuntu` on the serial console (it forces a new
   password), or over SSH once `ip -br addr` shows the DHCP address
   (`ssh-keygen -R <ip>` first).

## 7. Collect the evidence

Still on the test system, as root. Install the tools (the eMMC root only;
needs network, itself part of the evidence), then run the collector. It
refuses to run unless `/` is `/dev/mmcblk0p2`.

```sh
sudo -i
apt-get update && apt-get install -y device-tree-compiler pciutils usbutils ethtool nvme-cli stress-ng lm-sensors
curl -fsSL https://raw.githubusercontent.com/Maitlandk/ubuntu-rockchip/main/scripts/e1-evidence.sh -o e1-evidence.sh   # or scp it from the repo
bash e1-evidence.sh 120
```

(No network at all? `scp` the script from the Odroid and run it without
the tools: it notes what is missing; the boot-path checks do not need
them except the DTB comparison.)

It writes `/root/e1-evidence/*.txt` and `/root/e1-evidence.tar.gz`, and ends
with PASS/FAIL lines for the boot path:

| Check | What a PASS proves |
|---|---|
| booted by UEFI | `/sys/firmware/efi` exists: the kernel was started as an EFI application (GRUB), not by `booti`/extlinux. |
| `root=UUID=`, no `console=` | `/proc/cmdline` is GRUB's: `BOOT_IMAGE=/boot/vmlinuz-<kver> root=UUID=<the image's> ro earlycon` (the `BOOT_IMAGE=` is added by GRUB's `linux` command). |
| console is ttyS9 | `/sys/class/tty/console/active` reads `ttyS9`: the DT's `stdout-path` (serial9) is honoured with no `console=` on the line. |
| root on the eMMC | `/` is `/dev/mmcblk0p2`, not the NVMe system. |
| DT model, `gpu@fb000000`, three `npu@fda…0000` | `/proc/device-tree` is Ubuntu's `rk3588-turing-rk1.dtb`: U-Boot 2024.01's built-in tree has neither the GPU nor the NPU nodes. |
| `/boot/dtb-<kver>` is the kernel's own DTB | flash-kernel's link points at `/lib/firmware/<kver>/device-tree/rockchip/rk3588-turing-rk1.dtb`. |
| running DT equals `/boot/dtb-<kver>` outside `/chosen` | `/sys/firmware/fdt` (what the kernel runs on) is that file: GRUB's `devicetree` reached the kernel. `/chosen` is left out because the EFI stub writes `bootargs`, the initrd range and the rng seed there. A failing check leaves `dtb-diff-*.txt` with the difference. |
| no k3s service running | this is not the cluster node. |

Also saved for E2: `dmesg` (full, and the boot-path lines, warnings and
errors), `lspci -nnvv`, `lsusb -t`, `ip -d link`, `ethtool` and `ethtool -i`
per interface (the interface name is not `eth0`: predictable names),
`lsblk` showing the NVMe and eMMC (`nvme list` is a read-only identify; the
NVMe is **never mounted** on the test system either), the eMMC's mmc timing
(`/sys/kernel/debug/mmc0/ios`: HS400 with enhanced strobe expected from the
DT), `/proc/interrupts`, `lsmod`, cpufreq (driver, governor, current/min/max
per policy), thermal zones and cooling devices, the `pwm-fan` hwmon
(`pwm1`) idle and every 10 s under 120 s of `stress-ng` load, `systemd`
state and failed units, `cloud-init status`, `journalctl -b -p warning`.

Copy it off: `scp /root/e1-evidence.tar.gz <odroid>:rk1-e1/` and hand it to the
session (or paste `verdicts.txt`).

## 8. F1-F3 hardware checks

Run as root, after the base evidence (step 7); installing
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

## 9. Back to the NVMe system

1. On the test system: `sudo poweroff`. Then, from the BMC, power-cycle the
   slot (confirm `N` once more, step 1): `tpi power off --node $N; tpi power on --node $N`.
   Nobody interrupts U-Boot this time: its boot order (`mmc1 nvme scsi usb mmc0 ...`)
   reaches the NVMe before the eMMC.
2. Check it is the old system: `uname -r` is the vendor kernel,
   `cat /proc/cmdline` has `systemd.unified_cgroup_hierarchy=0`,
   `findmnt /` is `nvme0n1p2`, `/boot/firmware` is `nvme0n1p1`.
3. The loader region is unchanged (the second half of the proof):

   ```sh
   [ "$(ssh $NODE 'sudo dd if=/dev/mmcblk0 bs=1M count=16 status=none | sha256sum')" = "$(cat $B/emmc-first16MiB.sha)" ] && echo "first 16 MiB unchanged" || echo "FIRST 16 MiB CHANGED"
   ```
4. Cluster side: uncordon the node. `ssh-keygen -R` the test system's host key.

**STOP** if step 2 or 3 fails: do not retry, report.

The eMMC now holds the test system instead of the stale install. Boots are
unaffected (NVMe is tried first); if the NVMe ever failed to boot, the node
would fall through to `mmc0` and start this test system.

## 10. What to send back, and the way back

Send the session: `e1-evidence.tar.gz`, `e1-console.log` (U-Boot to the
login prompt, or to wherever it stopped), `preflight.txt`, the F1-F3 output,
and which of the PASS/FAIL lines failed. Redact nothing but secrets (the
evidence has none by construction). E2 reads it, files Launchpad or
mainline reports and records the findings in `CLAUDE.md`.

Nothing needs undoing for the NVMe system. To put the eMMC partitions back
as they were (only if wanted; the stale install is not used by anything):

```sh
zstd -dc $B/emmc-p1.img.zst | ssh $NODE 'sudo dd of=/dev/mmcblk0p1 bs=4M conv=fsync status=none'
zstd -dc $B/emmc-p2.img.zst | ssh $NODE 'sudo dd of=/dev/mmcblk0p2 bs=4M conv=fsync status=none'
```

The boot loader region and the GPT were never written, so there is nothing to
restore there; `emmc-first16MiB.img`, `emmc-gpt-tail.img` and
`emmc-boot{0,1}.img` are there for the case where something else went wrong
(restoring them is a boot loader write: only with the session's go-ahead).

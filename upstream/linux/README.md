# Pending upstream Linux patches (not sent)

Nothing here is built into an image (rule 2: no private DTB). These are
prepared submissions for the owner to send. Delete each one once it is merged.

## 0001: arm64: dts: rockchip: Enable HDMI0 on Turing RK1 (roadmap F4)

The base is torvalds/master 0fcb05b72344 (v7.3-rc7). `--base` is recorded in the patch.

**Evidence for the wiring.** No RK1 or Turing Pi 2 schematic is public.

- Turing RK1 Data Sheet V1.0 (2023-10-24), Table 4: there is one HDMI TX.
  TMDS pairs are on SO-DIMM pins 63-83, CEC on 94, HPD on 96, DDC SDA on 98 and SCL on 100.
  It does not name the SoC controller or the pin mux.
  The copy used is web.archive.org snapshot 20250311211010 of
  garden.tplant.com.au/Uploads/Turing-RK1-Data-Sheet-V1.0-20231103.pdf.
- docs.turingpi.com (turing-pi2-specs-and-io-ports, turing-rk1-flashing-os):
  HDMI is wired to node 1 only, and SW1 must be all OFF for the RK1.
  HDMI works with the BSP images. EDID is broken on Turing Pi 2 v2.4, which falls back to 1080p.
- Downstream device trees that enable `hdmi0` and its hdptx PHY with the default m0 pins:
  Joshua-Riek/linux-rockchip `noble` (BSP 6.1) and `oracular` (mainline-based).
  None enables hdmi1.
- Pin analysis against mainline: for each TX0 signal, every mux option except m0 is already taken.
  The hdmim1 CEC/SCL/SDA pins are i2c0/i2c1, the CPU and NPU regulator buses.
  The hdmim1 HPD and hdmim2 SCL/SDA pins are SO-DIMM GPIOs.
  This analysis does **not** by itself exclude HDMI1. HDMI0 rests on the vendor device trees, not on a schematic.

**Design choices** (also in the commit message):

- The change goes in the `.dts`, not the SoM `.dtsi`. That matches tiger/haikou, radxa-cm5/cm5-io and coolpi-cm5/evb.
- There is no `hdmi-connector` node. The generic `.dts` does not know the carrier, and dw-hdmi-qp handles HPD and EDID itself, as on mnt-reform2.
- There is no `frl-enable-gpios`, so the output is TMDS only (up to 4K60).
- HDMI audio (`&hdmi0_sound`, `&i2s5_8ch`) is a possible follow-up patch. It is not prepared.

**Checks.**

- Passed, in CI (`.github/workflows/dtbs-check.yml`, run 38680595353), at the
  base commit:
  - `git am` applies cleanly;
  - `make ARCH=arm64 CHECK_DTBS=y W=1 rockchip/rk3588-turing-rk1.dtb`: 0 warnings
    before the patch, 0 after (dt-validate 2026.9; kbuild printed `DTC [C]` for
    the dtb, so the schema check ran);
  - `scripts/checkpatch.pl --strict`, in the tree: 0 errors, 0 warnings, 0 checks.

  The workflow re-runs on every change under `upstream/linux/`.

**Before sending (owner):**

1. Boot-test with the RK1 in **node 1** of the Turing Pi 2. Node 2, the current test node, has no HDMI port.
   Node 1 is the cluster master, so this waits until node 1 runs the new system (roadmap, "Rollout order").
   The board is v2.4 (EDID broken), so expect a 1080p fallback picture and no EDID modes.
   For a non-persistent test, put the patched DTB on the eMMC ESP and point GRUB's `devicetree` at it.
   Expect a picture, `/sys/class/drm/card*-HDMI-A-1/status` = connected, and `modetest -c` listing EDID modes.
   On node 2, check that the same file says `disconnected`, i.e. HPD does not float.
2. Add `Tested-by`/test notes once the test has passed.
3. Signed-off-by is a DCO statement in your name. Check that `Maitlandk <maitland@scootnetworks.com>` is the identity you want.
   The kernel requires a known identity, and many maintainers expect a real name.
4. Send it:

```sh
git send-email --to="Heiko Stuebner <heiko@sntech.de>" \
  --to=linux-rockchip@lists.infradead.org \
  --cc="Rob Herring <robh@kernel.org>" \
  --cc="Krzysztof Kozlowski <krzk+dt@kernel.org>" \
  --cc="Conor Dooley <conor+dt@kernel.org>" \
  --cc=devicetree@vger.kernel.org \
  --cc=linux-arm-kernel@lists.infradead.org \
  --cc=linux-kernel@vger.kernel.org \
  0001-arm64-dts-rockchip-Enable-HDMI0-on-Turing-RK1.patch
```

The recipients are from `scripts/get_maintainer.pl --nogit --nogit-fallback` at the base commit.
Consider also Cc'ing Sam Edwards <CFSworks@gmail.com>, who wrote the RK1 device tree.

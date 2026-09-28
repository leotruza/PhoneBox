# virtual-phone-x86_64 — implementation-ready engineering plan

**Repository:** `leotruza/PhoneBox`  
**Target:** `virtual-phone-x86_64`  
**Status:** architecture and execution plan only; no implementation is authorized by this document  
**Primary recovery:** TWRP  
**Optional experiment:** GearLock only, outside the core architecture  
**Initial Android baseline:** AOSP `android17-release`, product `sdk_phone64_x86_64-userdebug` (`PRODUCT_DEVICE=emu64x`)  
**Primary boot path:** QEMU x86_64 → OVMF X64 → AOSP GBL x86_64 EFI → Android or TWRP  
**Development transport priority:** ADB TCP and GBL Fastboot TCP before USB  

## Executive decision

This project can be built primarily by composing upstream QEMU, OVMF/EDK II, AOSP GBL, AOSP `device/generic/goldfish`, TWRP, Magisk, and standard Android HALs. The custom surface should be limited to a PhoneBox launcher/storage contract, a PhoneBox-specific OVMF companion package for Android GBL protocols, small QEMU glue for any missing Goldfish qemud/battery services, Android/TWRP overlays, and host/test tooling. No custom bootloader, Fastboot protocol, Android framework, or replacement recovery should be created.

The first complete milestone is a **development profile**, not a production-certified phone: GBL `x86_64_dev`, unlocked AVB with test keys, userdebug Android, persistent writable state, TWRP, and development-only Fastboot TCP. A later production profile may use GBL `x86_64_prod`, but current GBL explicitly makes TCP Fastboot development-only; production must use a platform-defined transport or omit Fastboot TCP. [1][6]

The largest integration risks are GBL's Android-specific UEFI protocols, the mismatch between current Android 17 and available TWRP branches, Ranchu graphics/HAL coupling, Magisk API 37 compatibility, and Windows reachability to GBL's link-local IPv6 TCP listener. These are named research spikes below; they must not be hidden behind a claim that an upstream binary already solves the target.

---

## 1. Necessary Phase 0 corrections only

The Phase 0 report is directionally correct that the sandbox could not perform a full build and that no virtual-phone implementation exists. The following corrections are necessary before implementation:

1. **Repository/version fact is stale.** The checked repository currently resolves to public PhoneBox commit `a17ad80afc45366ae0242d88878c21a220edac7f` and `VERSION=11.1.50`; the earlier Phase 0 commit `81ce3a8773` is not the current public HEAD. The tree still has no phone-specific machine implementation. [25]
2. **Baseline choice:** synchronize the implementation branch to upstream QEMU **v11.1.0** and use the explicit machine type `pc-q35-11.1`; do not use moving PhoneBox `11.1.50` as the reproducibility baseline. The current fork contains no identified phone feature that requires 11.1.50, while the release tag and versioned machine type provide a stable device ABI. Keep the PhoneBox remote and record any later cherry-picks separately. [26]
3. **GBL x86_64 is a valid source-build target, not a validated product integration.** Current `uefi-gbl-mainline`/`gbl-mainline` has x86_64 development, production, debug, and bootstub targets; the old x86_32 assumptions and old `main` tree must not be mixed with it. Build `x86_64_dev` first. A Google-certified Android 17 x86_64 release binary is not implied. [1][2][11]
4. **EFI path:** for this x86_64 target use the standard removable-media path `/EFI/BOOT/BOOTX64.EFI`, not the AArch64 `BOOTAA64.EFI` wording in the public deployment page. [1][10]
5. **GBL Block I/O contract:** current GBL source requires `EFI_BLOCK_IO_PROTOCOL` even if `EFI_BLOCK_IO2_PROTOCOL` is present. Virtio-blk is therefore a correct synchronous baseline; Block I/O 2 is optional and can be added with a different device if asynchronous flashing is required. [3][5]
6. **Fastboot TCP is development-only in current GBL.** It uses EFI SNP and GBL's smoltcp path, with port 5554 and `FB01` framing. Production GBL builds compile TCP as `NoOpTcp`; do not make TCP a production firmware requirement. [6][7][8]
7. **GearLock is removed from the required architecture.** TWRP is mandatory. GearLock may be tested later as an Android-x86 experiment only and must not add dependencies to QEMU, OVMF, GBL, Android, or TWRP.
8. **Android product correction:** `sdk_phone_x86_64-userdebug` is not the current native emulator phone product. The exact first target is `sdk_phone64_x86_64-userdebug` (`emu64x`), from `device/generic/goldfish`; the generic `mini_x86_64` product disables the kernel and emulator and is unsuitable. [13][14]
9. **Android layout correction:** the selected goldfish product is currently non-A/B with dynamic `super`, a v4 `vendor_boot` contract, and no proven `init_boot.img` until the actual build is inspected. Do not force an `init_boot`, A/B suffixes, `odm`, or `recovery` partition merely because a generic phone checklist names them. [15][17][18]
10. **TWRP compatibility correction:** no verified upstream Android 17 TWRP branch or modern generic x86_64 device tree exists. Use TWRP `android-14.1` as the newest source baseline and create a new PhoneBox recovery device configuration; treat Android 17 compatibility as a port and test gate, not an upstream guarantee. [19][20][21]
11. **Magisk correction:** stable v30.7 has verified x86_64 binaries and is the default patching baseline, but its stable release notes do not establish Android 17/API 37 support. v31.0 explicitly claims Android 17 support but is prerelease. v30.7 must pass the real guest test; v31.0 is the controlled fallback for API 37/Zygisk, not an unqualified replacement. [22][23]
12. **Repository-guidance correction:** `AGENTS.md` and the related guidance files were removed from the current public PhoneBox tree during the resynchronization. No current repository-level AI contribution restriction was found. This document nevertheless remains intentionally no-code because the updated project instruction explicitly requests planning only; any core QEMU, firmware, Android, or recovery changes should still receive normal maintainer review.

The sandbox's 6 vCPU/7.8 GiB RAM/~40 GiB free disk and absent KVM/toolchain remain appropriate for static analysis only, not an AOSP/GBL/TWRP end-to-end build.

---

## 2. Actual architecture

```text
Windows development host
  ├─ adb.exe ── TCP/host-forward ──┐
  └─ fastboot.exe ── TCP/IPv6 ─────┤
                                    │
                    virtual-phone-x86_64
                                    │
        QEMU pc-q35-11.1, ACPI, x86_64 CPU/RAM/APIC/PCIe
          ├─ OVMF X64 code + persistent vars
          │    ├─ FAT/GPT/DiskIo/BlockIo
          │    ├─ VirtioNetDxe → EFI SNP
          │    ├─ VirtioRngDxe/RngDxe → EFI RNG
          │    └─ PhoneBoxPkg DXE protocols
          │         ├─ BootControl + lock state
          │         ├─ AVB + rollback state
          │         ├─ gbl_fw_api_level
          │         ├─ OS configuration/bootconfig policy
          │         └─ optional Boot Memory/AVF hooks
          ├─ `/EFI/BOOT/BOOTX64.EFI` → GBL x86_64_dev
          │    ├─ normal Android bzImage handoff
          │    ├─ recovery/TWRP mode
          │    └─ development Fastboot TCP on port 5554
          ├─ one persistent GPT qcow2 disk → virtio-blk-pci
          │    ├─ dual ESPs, Android boot metadata, recovery, super
          │    └─ userdata/metadata/misc and all Android logical partitions
          ├─ virtio-net-pci → Android Ethernet + OVMF SNP
          ├─ virtio-gpu-pci → DRM/KMS/TWRP/Linux display baseline
          ├─ virtio-input-pci → touch, mouse, keyboard, phone keys
          ├─ virtio-rng-pci → guest and UEFI entropy
          ├─ virtio-serial-pci → named modem port and optional control ports
          ├─ virtio-snd-pci → audio profile when guest HAL is enabled
          └─ Goldfish-compatible qemud/battery glue where Ranchu requires it

Guest Android profile
  sdk_phone64_x86_64-userdebug / emu64x
    ├─ Linux 6.12 x86_64 Android kernel/modules
    ├─ v4 boot/vendor_boot + dynamic super
    ├─ Ranchu camera, Sensors 2.1, AIDL radio, Health AIDL integrations
    ├─ ADB TCP and userdebug adb root
    ├─ Magisk x86_64 root (validated image-role patch)
    └─ overlayfs-backed adb remount development writes

Guest recovery profile
  TWRP android-14.1 core + device/qemu/virtual-phone
    ├─ same x86_64 kernel/virtio devices and GPT disk
    ├─ DRM/KMS or explicitly validated fbdev display
    ├─ virtio-input evdev touch/keyboard
    ├─ recovery adbd/minadbd over TCP
    └─ same partition, wipe, flash, sideload, and reboot contract
```

**Composition rule:** QEMU provides devices and host-side channels; OVMF provides standard UEFI and a PhoneBox Android firmware package; GBL provides Android boot and Fastboot; AOSP provides the Android product and framework; TWRP provides recovery; Magisk provides root. Android HALs are two-sided contracts and are not considered implemented merely because QEMU enumerates a device.

**No custom machine initially:** launch `pc-q35-11.1` with explicit devices. Registering a new `virtual-phone-x86_64` machine is deferred until a measured guest/firmware incompatibility cannot be solved by a launcher profile. This minimizes QEMU core work and preserves upstream compatibility. [25][26]

---

## 3. Pinned source and reproducibility matrix

| Component | Initial pin/choice | Rule |
|---|---|---|
| PhoneBox/QEMU | upstream QEMU v11.1.0 tag; explicit `pc-q35-11.1` | Do not build the moving `11.1.50` tree as the reference artifact. Record the exact source commit and local PhoneBox patches. |
| GBL manifest | `kernel/manifest` branch `uefi-gbl-mainline`, recorded manifest commit `fbf316d03a5312c3d58699332a0e3a9ffe955c4c` | Use the matching source/resource/header set only. |
| GBL source | `platform/bootable/libbootloader` `gbl-mainline` commit `206c43c04f88d04b7be8481a8b7ee232290d3bf9` for the spike | Never mix with the older `main` ABI or docs. |
| GBL target | `x86_64_dev` | Use `x86_64_prod` only after the protocol/AVB acceptance gates pass; use `x86_64_dev_bootstub` only for an intentionally PE/COFF EFI-stub kernel. |
| GBL EFI path | `/EFI/BOOT/BOOTX64.EFI` on FAT ESP | `BOOTAA64.EFI` is AArch64-only for this plan. |
| OVMF/EDK II | X64 `OvmfPkg/OvmfPkgX64.dsc` and matching FDF; pin a recorded edk2 commit, initially the reviewed `d07d3f5a5769cc8c9f76385174b73ea85525077` | Build PhoneBoxPkg as a companion package; do not silently modify generic OVMF. |
| Android | AOSP manifest `android17-release` commit `29ace668ae756c7b8917c57abb440f6518844b0c` | All Android repos, tools, kernel, and host artifacts are pinned in a lock file. |
| Android product | `sdk_phone64_x86_64-userdebug`, `PRODUCT_DEVICE=emu64x` | Do not use `mini_x86_64`, retired `device/generic/qemu`, 16K, RISC-V, or minigbm as the first profile. |
| Android kernel | AOSP goldfish prebuilt x86_64 6.12 (`prebuilts/qemu-kernel` commit `7fe7e19e1bdb1850d637ce32b206db0b61fc937e`) plus matching virtual-device modules | Verify final kernel/modules in the built artifact; do not use the historical TWRP `kernAl`. |
| TWRP | core branch `android-14.1`; manifest branch matching `twrp-14.1` if available | New PhoneBox x86_64 device configuration; Android 17 compatibility is a port. |
| Magisk | v30.7 stable commit `e8a58776f1d7bdf852072ad0baa6eceb9a1e4aac` | v31.0 prerelease is an isolated API 37/Zygisk fallback only. |
| Windows tools | versioned AOSP Platform Tools `adb.exe`/`fastboot.exe` archive recorded with SHA-256 | Do not substitute a fake client or an unpinned SDK copy. |

The baseline remains intentionally **v11.1.0**, not current PhoneBox `11.1.50`: the target tree has no identified phone-specific changes that justify a moving development snapshot, and the versioned Q35 machine/device defaults are part of the compatibility contract. If a required bug fix exists only in PhoneBox 11.1.50, carry it as a named, reviewed patch on top of v11.1.0 and add a regression test; do not silently switch the baseline.

---

## 4. GBL integration analysis

### 4.1 Build and image selection

1. Sync the exact `uefi-gbl-mainline` manifest and matching resources.
2. Build with the current README procedure: `./bazel.sh run //bootable/libbootloader:gbl_efi_dist`.
3. Select `x86_64_dev` from the generated distribution; record the binary hash, source commit, resource hash, and target name.
4. Copy the artifact to the active FAT ESP as `/EFI/BOOT/BOOTX64.EFI`.
5. Start with the ordinary x86_64 path, which expects an Android-compatible Linux x86_64 bzImage and uses `boot_linux_bzimage`. Do not select `x86_64_dev_bootstub` unless the selected kernel is a PE/COFF EFI-stub image and the initrd `LoadFile2` path is deliberately tested. [1][2][9]
6. Build `x86_64_prod` only after the AVB, entropy, BootControl, lock-state, and protocol tests pass. TCP Fastboot must remain absent or explicitly gated in that profile. [6]

### 4.2 GBL requirement versus OVMF capability/missing/proposed implementation

| GBL requirement | Existing OVMF capability | Missing capability or limitation | Proposed implementation |
|---|---|---|---|
| UEFI x86_64 execution, boot services, ExitBootServices, memory map | OvmfPkgX64 is a normal X64 UEFI platform with boot services, PCI, ACPI, console, variables, allocation, and boot manager | No Android policy | Use pinned OVMF X64; keep services and memory map valid until GBL exits boot services. |
| `EFI_BLOCK_IO_PROTOCOL` | VirtioBlkDxe installs Block I/O for a whole virtio disk; GPT/FAT/DiskIo are included | Must expose a whole-disk handle; logical-partition-only handles are insufficient; BlockIo is required even with BlockIo2 | One GPT disk behind `virtio-blk-pci`; verify whole-disk BlockIo and named GPT partitions. |
| `EFI_BLOCK_IO2_PROTOCOL` | NVMe/SCSI disk drivers can provide Block I/O 2 | Virtio-blk baseline does not provide asynchronous Block I/O 2 | Not required for first correctness milestone. Add virtio-SCSI or NVMe only for a measured asynchronous Fastboot flashing requirement. |
| Memory allocation services | OVMF/UEFI standard boot services provide allocation | Fragmentation and reserved buffers are not Android-aware | Use standard allocation first; add PhoneBox Boot Memory protocol only if image-buffer tests prove a need. |
| `EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL` | Console/text output is present | GBL accepts a no-op, but headless logs can be difficult | Keep console enabled; add serial/OVMF log capture in launcher tests. |
| `EFI_RNG_PROTOCOL` | OvmfRngDxe/RngDxe and VirtioRngDxe can expose RNG | Driver presence does not prove runtime entropy | Add `virtio-rng-pci`; test `GetRNG` at runtime. Production GBL must not rely on static dev randomness. |
| `EFI_SIMPLE_NETWORK_PROTOCOL` for GBL TCP | VirtioNetDxe/NetworkPkg can install SNP on `virtio-net-pci` | OVMF TCP4/TCP6/HTTP are not the GBL transport; SNP must work at link layer and IPv6 reachability is external | Use virtio-net-pci with SNP. Let GBL dev smoltcp own TCP; validate link-local IPv6 on a direct/TAP test profile. Do not add HTTP/TLS/PXE for GBL. |
| `GBL_EFI_BOOT_CONTROL_PROTOCOL` | None in generic OVMF | Slot/mode/retry metadata and recovery/bootloader selection are Android-specific | PhoneBoxPkg DXE reads/writes the Android `misc` GPT partition and exposes a single-slot `A` policy for the selected non-A/B product. Reserve dual ESPs; add true A/B only when an A/B Android artifact is selected. |
| `GBL_EFI_AVB_PROTOCOL` | OVMF Secure Boot is not Android Verified Boot | No vbmeta key/rollback/lock-state/persistent-value implementation | PhoneBoxPkg AVB DXE uses pinned development keys, validates vbmeta/boot/vendor_boot/init_boot/dtbo as applicable, stores rollback/lock values in the `metadata` partition, and reports unlocked/orange development state. |
| `gbl_fw_api_level` under `GBL_EFI_VENDOR_GUID` | Generic variable service exists | Variable is absent and must be read-only with the exact GUID/name/value contract | Install a read-only variable `gbl_fw_api_level` under `5a6d92f3-a2d0-4083-91a1-a50f6c3d9830`; value equals the built image's `ro.board.api_level` (API 37). Test read, value, and write rejection. |
| OS configuration protocol | None Android-specific | Firmware-specific DT/bootconfig/cmdline fixups are absent | Implement a minimal PhoneBox OS Configuration provider that returns the pinned board policy and only applies documented x86 bootconfig/FDT fixups. If no mutation is required, return the loaded image unchanged and prove it with boot logs. |
| Boot Memory protocol | None Android-specific | Reserved/preloaded image buffers and Fastboot download buffers are absent | Omit for first boot if ordinary allocation passes. Add only as a scoped phase if GBL image-buffer/Fastboot stress shows fragmentation or size failures. |
| AVF protocol | None generic OVMF | Protected VM/pVM firmware and policy are not available | Out of scope for the initial `sdk_phone64_x86_64` profile; do not claim AVF. Add only with a matching pvmfw/AVF image contract. |
| GBL Fastboot transport protocol | No platform-defined Android Fastboot transport | No USB Fastboot gadget is required for the first milestone | Use GBL dev TCP over SNP. Do not create a second server. Add USB only after TCP is stable and only as a separate platform transport. |
| GPT and raw-storage naming | GPT/partition drivers exist | Vendor-defined raw device path and stable storage IDs are not automatically supplied | Use stable GPT names for normal partitions. Add the GBL vendor media device path GUID `a09773e3-f027-4f33-adb3-bd8dcf4b3854` only for deliberately exposed raw-storage ranges. |
| Android boot image parsing/verification | OVMF has no Android semantics | GBL needs matching image headers, slots, vbmeta, vendor_boot, init_boot, FDT, bootconfig | Leave parsing to GBL; provide correct image files, BootControl, AVB, OS Configuration, and memory contracts. |
| x86_64 Linux handoff | OVMF can load EFI applications | OVMF does not itself construct Android x86 bzImage handoff | Use GBL ordinary x86_64 path; kernel must be a compatible Android/Linux bzImage. Test FDT `chosen/bootargs`, EFI system-table address, memory map, and e820 handoff. |
| PE/COFF EFI-stub handoff | Generic UEFI can start EFI images | Requires GBL bootstub target and `EFI_LOAD_FILE2`/Linux initrd device path | Not baseline. Maintain a separate bootstub spike and image only if the kernel packaging requires it. |
| Persistent firmware variables | OVMF variable store is persistent if writable vars are supplied | It is a second state store and must not duplicate Android state | Persist only UEFI boot-manager state plus the read-only GBL API variable. Store lock/slot/rollback in Android `misc`/`metadata`. |

The table is the integration contract. “OVMF boots GBL” is not an acceptance criterion unless the Android-specific rows required by the selected GBL/image profile also pass.

### 4.3 OVMF responsibilities and package boundary

Use generic `OvmfPkg/OvmfPkgX64.dsc`/FDF and add a PhoneBox package rather than modifying generic OVMF behavior in-place. The firmware build must:

- enumerate Q35 PCIe and expose the virtio block, network, RNG, input/serial, and optional graphics devices;
- install FAT, GPT, DiskIo, BlockIo, console/SimpleTextOutput, allocation, RNG, and SNP protocols;
- load `/EFI/BOOT/BOOTX64.EFI` from the active ESP;
- provide a persistent writable `OVMF_VARS.fd` for UEFI boot configuration, while keeping Android state on the unified disk;
- install the PhoneBox BootControl, AVB, OS Configuration, and vendor-variable DXE protocols;
- retain usable boot services/memory map until GBL exits boot services;
- preserve deterministic firmware logs and a firmware-version manifest;
- explicitly not implement Android framework, GBL parsing, Fastboot packet handling, SurfaceFlinger, or recovery UI.

`PhoneBoxPkg` should live in a separately pinned EDK II fork or a dedicated firmware repository, with a source manifest imported by the PhoneBox build. A QEMU fork must not become the accidental owner of UEFI Android semantics.

---

## 5. Exact Android product and image contract

### 5.1 Selection

Build **`sdk_phone64_x86_64-userdebug`** from the pinned `android17-release` manifest. It is the current native 64-bit x86 emulator phone product, uses `PRODUCT_DEVICE=emu64x`, inherits the goldfish phone product, enables dynamic partitions, and has the matching Ranchu kernel/module/graphics/ADB integration. [12][13][14]

Do not select:

- `mini_x86_64`: it is a generic PDK/minimal product with `TARGET_NO_KERNEL=true`, `TARGET_NO_BOOTLOADER=true`, and `BUILD_EMULATOR=false`;
- retired or absent current `device/generic/qemu` Android 17 products;
- `sdk_phone16k_x86_64` until a 16K page-size requirement exists;
- `sdk_phone64_x86_64_riscv64`, which is a binary-translation variant rather than native x86_64;
- `sdk_phone64_x86_64_minigbm` as the first profile, because its graphics flags/modules differ materially;
- Cuttlefish as the first image, although `aosp_cf_x86_64_only_phone` remains the fallback comparison image if Ranchu integration fails.

The initial build variant is `userdebug`, not `user`: it is required for `adb root`, `adb remount`, test keys, debug ADB, and development AVB. `eng` is an optional diagnostic build, not the release-like development default.

### 5.2 Actual Android boot/storage contract

The build inspection gate must use `unpack_bootimg`, `avbtool`, `lpdump`, filesystem magic inspection, and GPT tooling before the launcher accepts the artifact. Expected current goldfish characteristics are:

- boot header version 4;
- `vendor_boot.img` approximately 96 MiB with LZ4 vendor ramdisk;
- `fstab.ranchu` under the vendor ramdisk first-stage path;
- dynamic `super` containing logical `system`, `system_dlkm`, `system_ext`, `product`, and `vendor` partitions;
- default ext4 read-only system-side images, with `system_dlkm` EROFS where the selected build emits it;
- separate userdata and metadata partitions;
- sparse output disabled by the goldfish emulator configuration;
- no `init_boot.img` unless the actual build sets `BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE` and emits it;
- no A/B slot-suffixed Android partitions in the initial product because the verified goldfish board sets `AB_OTA_UPDATER=none` and has an empty A/B partition list.

GBL still receives a BootControl implementation because the current GBL contract requires it. The first implementation exposes a truthful **single-slot A development policy** backed by `misc`; it must not pretend that a non-A/B image has a second Android slot. Two FAT ESPs are reserved for GBL/OTA-style firmware rollback, but they do not turn the non-A/B Android product into Virtual A/B. A later A/B profile is a separate image contract, not an inferred property.

### 5.3 Graphics decision

The selected product is Ranchu/goldfish, so its first graphics profile must use the matching AOSP emulator/goldfish userspace and host qemud/pipe contracts, not arbitrary Android-x86 libraries. QEMU's `virtio-gpu-pci` remains the generic DRM/KMS path for Linux and TWRP and the fallback Android display path; `virtio-gpu-gl`/rutabaga/gfxstream are opt-in acceleration profiles, not guaranteed Android compatibility. The bring-up order is:

1. prove a virtio-gpu DRM connector, dumb buffers, EDID/hotplug, and TWRP display;
2. prove the selected Ranchu graphics provider/HWC and guest GLES/Vulkan libraries with the AOSP emulator host services;
3. use SwiftShader/lavapipe software rendering for a deterministic fallback;
4. only then measure virgl or rutabaga/gfxstream acceleration with pinned host blobs and guest libraries.

If the Ranchu provider cannot be made functional without importing the full emulator host, do not rewrite QEMU graphics: run the Cuttlefish x86_64 comparison image as a compatibility fallback and document the product switch. [28][29]

---

## 6. Unified storage and persistence

### 6.1 One source of guest storage truth

Use one persistent writable `state.qcow2` presented as one whole-disk `virtio-blk-pci` device. OVMF, GBL, Android, TWRP, and Fastboot all access the same GPT disk; no per-consumer fake disks or duplicated partition files are allowed. Use explicit QEMU `-blockdev` nodes for the file and qcow2 layers, not implicit per-device `-drive` shortcuts. [26]

Initial disk capacity: **16 GiB minimum**, with a recommended **32 GiB** development image to leave room for userdata, snapshots, and test artifacts. The disk layout is generated by a pinned image-builder manifest, not hand-edited per test.

### 6.2 GPT layout

| GPT name | Baseline role | Format/size policy |
|---|---|---|
| `android_esp_a` | active GBL ESP | FAT32, at least 8 MiB; use 16 MiB; ESP type GUID `C12A7328-F81F-11D2-BA4B-00A0C93EC93B`; contains `/EFI/BOOT/BOOTX64.EFI` |
| `android_esp_b` | inactive/rollback ESP reservation | FAT32, at least 8 MiB; use 16 MiB; same ESP GUID; populated only when a second firmware image is available |
| `boot` | Android boot image | Size from actual image plus margin; no slot suffix in baseline |
| `vendor_boot` | Android vendor boot v4 | At least 96 MiB for the selected board contract, final size from build output |
| `init_boot` | conditional | Create only if actual Android build emits it and AVB/GBL image set requires it |
| `recovery` | PhoneBox developer TWRP image | Dedicated recovery contract for this non-A/B development profile; not claimed as a universal Android 17 layout |
| `dtbo` | conditional | Create only if the selected build emits and GBL verifies it |
| `vbmeta` | Android AVB metadata | Development-signed; include chained descriptors for boot/init_boot/vendor_boot as emitted |
| `super` | dynamic logical partitions | Build-defined; current target is approximately 1.8 GiB and contains system-side logical partitions |
| `metadata` | AVB/metadata-encryption state | Unencrypted metadata partition; size from build/crypto contract |
| `misc` | BootControl/recovery commands | Persistent boot mode and single-slot retry metadata |
| `userdata` | Android/TWRP development state | Ext4 or F2FS according to selected Android build; unencrypted for initial TWRP scope |
| `odm` | conditional | Only if the selected AOSP artifact declares a physical ODM partition; otherwise do not invent it |

The dedicated `recovery` partition is an explicit PhoneBox development choice. It avoids pretending that the selected non-A/B Ranchu product has a seamless-update recovery layout. If a later Cuttlefish-like profile moves recovery resources into `init_boot`/`vendor_boot`, it must be a separate TWRP packaging target and must not silently reuse this GPT contract. [17][19]

### 6.3 Persistence ownership

| State | Source of truth | Reset behavior |
|---|---|---|
| GPT and partition contents | `state.qcow2` GPT/partitions | Survives reboot; only image rebuild/flash changes it |
| Android userdata and TWRP files | `userdata` partition | Survives reboot; `fastboot erase userdata`/factory reset clears it |
| Boot mode, recovery request, retry count | `misc` partition via PhoneBox BootControl | Survives reboot; factory reset does not erase it |
| AVB lock state and rollback indexes | `metadata` partition via PhoneBox AVB provider | Survives reboot; only explicit flash/lock-state operation changes it |
| GBL API level | read-only UEFI variable `gbl_fw_api_level` | Firmware-controlled; never changed by Android factory reset |
| OVMF boot manager entries | `OVMF_VARS.fd` | Persists independently; not used for Android slot/lock truth |
| VM snapshots | QEMU internal snapshot or external qcow2 overlay | Explicitly listed/deleted; must include the single writable disk and vars policy |
| Host configuration | launcher manifest | Recreated from pinned files; never treated as guest state |

QEMU internal snapshots are allowed only after a clean guest shutdown or guest filesystem freeze. They capture device/disk state but do not make an active Android transaction atomic. Disposable tests use a qcow2 external overlay with an explicit backing-chain lifecycle. [26]

---

## 7. QEMU virtual hardware inventory

The launcher must explicitly declare every device and disable unintended Q35 defaults, especially the default e1000e NIC.

| Device/configuration | Required use | Guest-facing contract |
|---|---|---|
| `pc-q35-11.1`, `acpi=on` | Stable x86_64 PCIe/Q35 platform | ACPI, PCIe root, ICH9/LPC, APIC/IOAPIC, power/reset, hotplug foundation |
| x86_64 CPU, APIC, RAM | Phone execution | `-cpu max` for reproducible TCG tests; `-cpu host` with KVM only on a capable development host; record CPU policy |
| OVMF code pflash | UEFI firmware | Read-only `OVMF_CODE.fd` |
| OVMF vars pflash | Persistent firmware variables | Per-device writable copy of `OVMF_VARS.fd`; never share concurrently |
| one `virtio-blk-pci` | Unified disk | Linux virtio-blk and OVMF VirtioBlkDxe whole-disk BlockIo |
| optional `virtio-scsi-pci`/NVMe | BlockIo2 experiment only | Separate measured profile; not the baseline disk device |
| `virtio-net-pci` | Guest Internet and OVMF SNP | User NAT profile for Android/ADB; TAP/bridge profile for direct GBL IPv6 testing |
| `virtio-rng-pci` | Entropy | OVMF RNG and Android virtio-rng module |
| `virtio-gpu-pci` | Display | DRM/KMS, scanout, EDID, TWRP dumb buffers, Linux display; 2D first |
| `virtio-gpu-gl` or rutabaga/gfxstream | Optional acceleration | Only with pinned host/guest capability matrix; never the only display path |
| `virtio-input-pci` keyboard | Physical keyboard | Linux evdev and Android keylayout |
| `virtio-input-host-pci` pointer/touch | Mouse/tablet/touch | EV_ABS/ABS_MT slots and calibrated 1080×2280 coordinates |
| additional virtio-input key device | Phone keys | KEY_POWER, KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_HOME, KEY_BACK, KEY_MENU |
| `virtio-serial-pci` | Named guest channels | At minimum a named `modem` port; optional qemud/control ports |
| `virtio-snd-pci` + QEMU `audiodev` | Preferred audio profile | ALSA PCM playback/capture if Android kernel/HAL is enabled; stereo baseline |
| Intel HDA + codec | Audio fallback | Only for a guest image whose kernel/audio HAL already supports `snd_hda_intel`; do not expose multiple audio cards by default |
| Goldfish battery device/glue | Battery/power model | Conventional power-supply sysfs for Android Health AIDL |
| Goldfish qemud/pipe services | Ranchu camera and sensors | Named `sensors` and `FakeRotatingCameraSensor` channels; host deterministic software values/frames |
| QEMU display backend | Host presentation | GTK/SDL/headless capture; never host-render Android UI outside the guest |
| USB controller | Secondary milestone | Not required for ADB/Fastboot first; later USB gadget/MTP research only |

No physical UFS, phone SoC, PMIC, RF modem, Snapdragon/Qualcomm/Exynos/MediaTek, Adreno/Mali, or physical sensor chip is part of the architecture.

The target display is 1080×2280 portrait. The host input mapping must preserve absolute touch ranges and orientation; PS/2 is an emergency keyboard fallback only, not the multi-touch design. TWRP consumes DRM/evdev directly, while Android consumes the selected HWC/gralloc and InputReader stack. [28][30]

---

## 8. Guest-facing software peripherals

Every subsystem below has a complete host-device → guest interface → Android userspace path. A QEMU device enumeration alone is not acceptance.

### 8.1 Camera — high-risk, deterministic first

**Chosen path:** AOSP goldfish camera provider with `FakeRotatingCamera` over the existing emulator qemu-pipe contract. Expose front and rear logical cameras; use a fixed test pattern/scene and selectable stream resolutions. The provider is the AIDL Ranchu camera provider and must include its VINTF fragment, camera metadata, buffer allocation, SELinux labels, and service startup. [30]

**Stack:**

```text
PhoneBox qemud camera endpoint: FakeRotatingCameraSensor
  → guest camera pipe/channel
  → device/generic/goldfish AIDL camera provider
  → CameraService/camera2
  → Android camera application
```

Use `QemuCamera`/host webcam only as a later nondeterministic profile. Do not co-install the AIDL Ranchu provider and Google emulated HIDL provider without a provider-instance/VINTF decision. Acceptance must enumerate two cameras, open each, deliver deterministic frames at the selected size, and survive ten open/close cycles.

### 8.2 Sensors — medium/high-risk

**Chosen path:** goldfish Sensors 2.1 HIDL sub-HAL loaded by Android sensor multihal, using the qemud `sensors` service. Expose accelerometer, gyroscope, proximity, ambient light, and orientation initially; optional magnetometer, pressure, and temperature follow the same protocol. [31]

```text
QEMU qemud sensors service
  → guest qemu pipe / sensor transport
  → android.hardware.sensors@2.1-impl.ranchu
  → SensorService
  → applications
```

Drive fixed values through the host control interface for CI. The upstream conversion path injects bias/noise and uses elapsed-realtime timestamps for some uncalibrated sensors; deterministic tests must either use calibrated/fixed types or explicitly accept bounded variation. Do not compare raw uncalibrated events byte-for-byte.

### 8.3 Modem/RIL — high-risk

**Chosen path:** current goldfish AIDL radio service (`android.hardware.radio-service.ranchu`) backed by the emulator AModem/modem simulator over a named virtio-serial port `modem`. The guest `qemu-props` port parser must create `vendor.qemu.vport.modem`; the RIL/Radio service opens that endpoint and exchanges AT commands/unsolicited responses. Do not use the legacy reference-RIL for the Android 17 product. [32]

```text
PhoneBox virtio-serial port name=modem
  → guest /sys/class/virtio-ports/... and vendor.qemu.vport.modem
  → goldfish AIDL radio service / AtChannel
  → Android telephony framework
```

The simulator must provide SIM present/profile, airplane mode, registration, signal, SMS, mobile-data state, calls as control-plane state, and network loss. Call audio is explicitly out of scope for the modem; it is an independent audio feature.

### 8.4 Audio — high-risk, image-dependent

**Chosen baseline:** `virtio-snd-pci` with the Linux `SND_VIRTIO` driver and an Android TinyALSA/virtio audio HAL/policy overlay derived from the AOSP Trout virtualization path. Expose one stereo playback stream and one capture stream; route host output/input through a pinned QEMU `audiodev`. [37]

```text
QEMU virtio-snd + host audiodev
  → Linux SND_VIRTIO / ALSA PCM
  → Android virtio/TinyALSA audio HAL + policy
  → AudioFlinger
  → applications
```

If the selected Ranchu product has a working goldfish audio HAL but no virtio-snd contract, the compatibility fallback is Intel HDA/codec with `snd_hda_intel` and the image's existing Android HAL. AC97 is a last-resort legacy fallback. The launcher must expose only one audio card in a given profile. Acceptance covers playback, capture, volume, mute, and clean card enumeration; TWRP has no audio requirement.

### 8.5 Battery/power — medium/high-risk

**Chosen path:** reuse the AOSP goldfish battery model/agent and Android Health AIDL default service. QEMU must expose conventional power-supply attributes for present, online/charger, capacity, health, and status; the guest includes the manifest/init/SELinux wiring and `libbatterymonitor` reads those values. [33]

```text
PhoneBox goldfish battery model/control
  → guest power_supply sysfs
  → Health AIDL v4 default service
  → BatteryManager/SystemUI
```

Provide host controls for percentage, charging/USB power, full/low battery, and discharging. Validate `dumpsys health`, SystemUI icon/percentage, threshold transitions, and Health VTS where the selected build supports it. `hw.battery=yes` alone is not sufficient.

### 8.6 Networking

Primary Android profile: `virtio-net-pci` with QEMU user-mode NAT, explicit DNS/Internet access, and loopback-bound host forwards for ADB. No physical Wi-Fi chip is emulated. A TAP/bridge profile is reserved for GBL TCP IPv6 reachability and optional LAN testing. User networking is not used as evidence of direct inbound IPv6 reachability.


Use QEMU user NAT for normal Android networking and ADB host forwarding. The GBL Fastboot TCP test uses a separate TAP/bridge profile because current GBL derives a link-local IPv6 address from the SNP MAC; a host-only IPv4 forward is not evidence that the GBL IPv6 listener is reachable. [7]

---

## 9. Development, unlocked, AVB, root, and writable-system design

### 9.1 Default development state

The shipped development disk is already unlocked and OEM unlocking is enabled. No unlock ceremony is required. The PhoneBox BootControl/AVB providers report truthful unlocked/orange state and persist it in `metadata`; a factory reset erases userdata but does not relock the device, erase `misc`, or erase AVB state. `flashing lock` remains an explicit destructive operation and is tested separately.

The Android image is `userdebug` with:

- ADB enabled after boot and debug key injection preserved;
- `adb root` available where Android policy permits;
- test AVB keys and unlocked verification state;
- `adb remount`/overlayfs enabled through normal Android development mechanisms;
- no claim of production secure boot or production encryption;
- Magisk x86_64 installed and validated independently of `adb root`.

### 9.2 AVB chain

Keep AVB components present. Build and sign `vbmeta`, `boot`, `vendor_boot`, `init_boot`, `dtbo`, and recovery according to the actual image set. Use PhoneBox development keys in the AVB provider and record public-key fingerprints. The unlocked state is expressed through AVB/GBL policy, not by deleting verification metadata. Use `fastboot --disable-verity --disable-verification` only as a measured development fallback; it is not the primary design and must not be confused with a valid unlocked AVB chain. [22][24]

Acceptance records `ro.boot.verifiedbootstate=orange`, the GBL-reported unlocked value, vbmeta verification results, rollback indexes, and the exact image hashes before/after every patch.

### 9.3 Magisk integration

The integration is an image-patching pipeline, not a custom QEMU root feature:

1. Build the unmodified Android artifacts.
2. Inspect `boot.img`, `init_boot.img`, `vendor_boot.img`, recovery, headers, GKI flags, and AVB descriptors.
3. Apply MagiskBoot v30.7 to the image whose ramdisk participates in first-stage init. Do not blindly patch `boot.img`; v30.7's selection logic makes init_boot/vendor_boot/recovery conditional on the actual board layout. [22][24]
4. Repack while retaining the original header/table/compression contract; sign the patched image with the PhoneBox development key.
5. Flash the patched image through GBL Fastboot or place it in the generated development disk.
6. Install the x86_64 Magisk APK/payload and verify `magisk`, `magiskinit`, `magiskpolicy`, BusyBox, and `su` are the x86_64 artifacts.
7. Boot, test `su -c id` as real UID 0, reboot, and repeat. Test with `adb root` disabled as a separate check so AOSP debug root cannot mask a broken Magisk install.

v30.7 is the stable default because its x86_64 packaging and image tooling are verified, but no stable Android 17/Zygisk guarantee is accepted. If API 37 validation fails, run the isolated v31.0 prerelease branch; promote it only if the full boot, SELinux, persistent `su`, and regression suite passes. If both fail, the baseline remains userdebug/adb-root development only and Magisk is a release blocker rather than a hidden failure. [22][23]

### 9.4 Writable system

Use standard `userdebug + adb root + adb remount` behavior. The underlying `system`, `system_ext`, `product`, `vendor`, and `odm` contents remain in their Android images/super metadata. Development writes are placed in the Android overlayfs upper layer on userdata when `adb remount` selects overlayfs; they are not silently written into immutable EROFS or the base image.

The mandatory write test is:

```text
adb root
adb remount
adb shell 'printf phonebox-dev-<build-id> > /system/etc/phonebox-dev-marker'
adb shell 'cat /system/etc/phonebox-dev-marker'
adb shell 'mount | grep -E " /system |overlay"'
adb reboot
adb wait-for-device
adb shell 'cat /system/etc/phonebox-dev-marker'
```

The expected content must survive a normal reboot and disappear after an explicit overlay/userdata reset. A base-image reflash must be documented as replacing the underlying image while leaving or clearing the overlay according to the selected reset operation. If `adb remount` cannot create a valid overlay on the selected product, do not claim writable system; stop and either correct the build flags or mark the feature unsupported.

---

## 10. Exact Fastboot flow

### 10.1 GBL state machine

Normal Android:

```text
Android → adb reboot bootloader → misc bootloader request → reboot → GBL Fastboot
```

Recovery:

```text
Android → adb reboot recovery → misc recovery request → reboot → GBL selects recovery/TWRP
```

Temporary recovery:

```text
GBL Fastboot → fastboot boot twrp.img → GBL downloads image → boots it in RAM
```

The persistent recovery path uses the `recovery` GPT partition. The temporary `boot` path is independently tested and must not overwrite recovery or Android partitions.

### 10.2 TCP development flow

Current GBL development TCP is the only first-milestone Fastboot transport:

```text
Windows fastboot.exe
  → TCP server port 5554
  → QEMU virtio-net-pci
  → OVMF VirtioNetDxe / EFI_SIMPLE_NETWORK_PROTOCOL
  → GBL smoltcp link-local IPv6 TCP
  → GBL Fastboot engine
  → unified GPT disk
```

The wire acceptance is exact: both endpoints send four bytes `FB01`; each Fastboot message is framed as an unsigned 8-byte big-endian length followed by the Fastboot payload. Use 5554, not the inconsistent illustrative 5555 sentence in one AOSP document. [4][8]

The launcher has two networking profiles:

- **`android-nat`:** user NAT, guest Internet, host-forwarded ADB; no claim of GBL TCP reachability.
- **`fastboot-ipv6`:** virtio-net with a TAP/bridge or equivalent L2 path that lets the Windows host reach the guest's SNP-derived link-local IPv6 address. The launcher prints the actual address and interface scope.

The Windows test uses the pinned AOSP `fastboot.exe` and the current parser's `tcp:<address>:<port>` form. For an IPv6 link-local address, use the parser-accepted bracket/scope spelling determined by the pinned `fastboot.cpp` build; the test artifact must record the exact successful command, for example the equivalent of:

```text
fastboot -s tcp:[fe80::<guest-address>%<Windows-interface-scope>]:5554 getvar all
```

If the Windows client does not accept the bracket/scope spelling, do not invent a new protocol: use the exact syntax emitted by the current AOSP parser or change the network profile so the parser receives its accepted address form. [35]

Mandatory Fastboot operations, with unsupported operations reported truthfully by GBL:

```text
fastboot devices
fastboot -s tcp:<device>:5554 getvar all
fastboot -s tcp:<device>:5554 getvar unlocked
fastboot -s tcp:<device>:5554 getvar product
fastboot -s tcp:<device>:5554 boot twrp.img
fastboot -s tcp:<device>:5554 flash recovery twrp.img
fastboot -s tcp:<device>:5554 erase userdata
fastboot -s tcp:<device>:5554 reboot recovery
fastboot -s tcp:<device>:5554 reboot bootloader
fastboot -s tcp:<device>:5554 reboot
```

`download`, `flash`, `erase`, slot/retry operations, and `flashing unlock/lock` are verified against GBL's actual command set and storage contract. No QEMU Fastboot server or duplicate TCP framing implementation is permitted.

**Production distinction:** GBL `x86_64_prod` must not expose development TCP. A future production profile needs a platform-defined Fastboot transport/USB implementation or explicitly omits Fastboot. The development profile is the deliverable that satisfies the Windows TCP requirement.

---

## 11. Exact ADB Android/TWRP flow

### 11.1 Android

Use ordinary Android `adbd` over TCP first. The Android product keeps its emulator-compatible key injection, but PhoneBox adds a documented TCP property/boot configuration for userdebug, with guest port **5555**. QEMU user NAT forwards `127.0.0.1:<host-adb-port>` to guest TCP 5555; the host port is printed by the launcher and may be allocated to avoid collisions.

```text
Windows adb.exe
  → adb connect 127.0.0.1:<host-adb-port>
  → QEMU user NAT hostfwd
  → Android adbd:5555
```

Acceptance:

```text
adb connect 127.0.0.1:<host-adb-port>
adb devices
adb shell getprop ro.build.version.sdk
adb shell getprop ro.product.cpu.abi
adb shell id
adb push marker /data/local/tmp/marker
adb pull /data/local/tmp/marker marker.out
adb reboot recovery
```

Do not claim emulator odd/even-port discovery unless it is intentionally implemented. Direct `adb connect` is the deterministic Windows contract. The selected goldfish product's `ro.adb.has_usb=0` and interim USB notes make real USB gadget support secondary. [16][34]

### 11.2 TWRP

TWRP recovery uses guest port **5556** in the recovery profile, forwarded by the same QEMU NIC. Build recovery as a debug-capable configuration so `adbd` starts; use `minadbd` for sideload/install IPC. The recovery acceptance is:

```text
adb connect 127.0.0.1:<host-recovery-port>
adb devices
adb shell
adb push test.zip /tmp/test.zip
adb pull /tmp/test.zip pulled.zip
adb sideload signed-test-package.zip
```

`adb sideload` must be tested with the actual TWRP minadbd path; a shell-only connection is not sufficient. MTP is optional and not a dependency; the historical TeamWin x86_64 tree explicitly excluded it. [19][21]

---

## 12. TWRP branch and device strategy

### 12.1 Decision

Use **TWRP core `android-14.1`** as the newest verified TeamWin source baseline. No current upstream TWRP branch is verified for Android 17, and no current TeamWin x86_64/QEMU device tree is a usable Android 17 baseline. The official old x86_64 emulator tree is Android 5.0.1/MTD-era prior art only. TWRP Android 17 compatibility is therefore a new port and a high-risk gate. [19][20][21]

The requested `platform_manifest_twrp_aosp` is used to sync the core where its branch is available; the source lock must pin each repository and commit. If a `twrp-14.1` manifest branch is unavailable, sync the manifest revision that resolves `TeamWin/android_bootable_recovery` to `android-14.1` and record the override. Do not silently use `twrp-12.1` merely because the old plan named it.

### 12.2 Device configuration

Create/adapt only the recovery device configuration at `device/qemu/virtual-phone/`. Do not clone a Samsung, OnePlus, Qualcomm, or physical-phone tree. The device tree must define:

- x86_64 architecture and the exact shared Android 6.12 kernel/module contract;
- QEMU virtio block/net/input/gpu/rng expectations;
- dedicated `recovery.img` packaging for the initial non-A/B PhoneBox contract;
- `recovery.fstab` entries for GPT physical partitions, `super` logical partitions, userdata, metadata, misc, boot, vendor_boot, optional init_boot/dtbo/vbmeta;
- liblp/dynamic-partition flags, slotselect only when a future A/B profile is enabled, EROFS/ext4/F2FS options matching actual images;
- DRM/KMS display and evdev input configuration;
- recovery ADB/minadbd debug transport;
- test keys and unlocked AVB behavior;
- encryption explicitly disabled/unsupported for the initial profile unless the KeyMint/metadata-encryption spike passes.

The recovery kernel must be the same compatible x86_64 kernel family as the Android guest or a separately built kernel with the same virtio, DRM, input, block, crypto, and ADB modules. The obsolete `kernAl`, MTD fstab, fixed 320×480 config, hard-coded 10.0.2.15 network script, and old partition-generation script are prohibited.

### 12.3 UI and storage acceptance

TWRP must render its real UI through DRM/KMS or an explicitly validated fbdev path; no custom recovery UI is allowed. Verify menus, file browser, terminal, touch, keyboard, wipe, flash, reboot, partition visibility, and ADB. The first scope is unencrypted userdata. Android 17 FBE/metadata encryption is a separate go/no-go spike because secure decryption needs matching KeyMint/Keymaster/Gatekeeper/TEE behavior, not merely TWRP code. [19][20]

---

## 13. Dependency-ordered implementation phases

The following phases are ordered by hard dependencies. Each phase ends with an artifact and a gate; no later phase is allowed to compensate for a failed earlier gate.

### Phase 0 — source/policy lock (research/static analysis; AI-allowed)

- Record the source pins in a lock file.
- Confirm QEMU v11.1.0, OVMF commit, GBL manifest/source, Android manifest/product, TWRP branch, Magisk tag, and Windows tools.
- Preserve the repository policy boundary.
- Deliverable: source lock, architecture decision record, and this plan.

### Phase 1 — development host and reproducible build harness (human-owned integration; scripts may be reviewed)

- Provision Linux x86_64 host, KVM, disk, build tools, AOSP repo/Bazel, OVMF build prerequisites, QEMU build prerequisites, and Windows test host.
- Build stock QEMU v11.1.0, stock OVMF X64, GBL `x86_64_dev`, and the AOSP product without PhoneBox changes.
- Deliverable: hashes, build logs, tool versions, and artifact manifest.

### Phase 2 — stock Q35/QEMU machine smoke tests (human-authored QEMU/launcher work)

- Use `pc-q35-11.1,acpi=on` with explicit pflash, one qcow2 disk, virtio-blk, virtio-net, virtio-rng, virtio-gpu, and virtio-input.
- Prove Linux bzImage/initramfs/rootfs boot, virtio storage/network/display/input, and clean shutdown.
- Do not add a new machine type unless a test proves it is necessary.
- Deliverable: launcher profile and QEMU qtest/acceptance evidence.

### Phase 3 — OVMF PhoneBox firmware package (human-authored firmware work; high-risk spike)

- Build PhoneBoxPkg on pinned EDK II.
- Prove BlockIo, RNG, SNP, console, variables, whole-disk GPT, read-only API variable, BootControl, and AVB provider discovery.
- Deliverable: OVMF code/vars artifacts and protocol matrix with runtime evidence.

### Phase 4 — GBL x86_64 bring-up (human firmware/integration work; mandatory research spike)

Answer in order: build, OVMF start, BlockIo discovery, GPT names, GBL logs, API level, BootControl, AVB dev state, ordinary x86 bzImage handoff, Fastboot entry, TCP SNP path. Stop here if a required protocol cannot be supplied without modifying GBL; evaluate U-Boot only as a fallback, never a custom bootloader first.

Deliverable: GBL spike report with binary/source hashes, missing protocol decisions, and Go/No-Go for the permanent boot path.

### Phase 5 — unified disk and Fastboot TCP (human launcher/firmware integration)

- Generate the dual-ESP/GPT/Android partition disk.
- Verify GBL sees whole-disk BlockIo and named partitions.
- Verify Windows Fastboot `FB01`, 8-byte framing, port 5554, `getvar`, `boot`, `flash`, `erase`, and reboots over the IPv6/TAP profile.
- Deliverable: Windows Fastboot runbook and captured logs.

### Phase 6 — AOSP Android image build/inspection (AOSP configuration work)

- Build `sdk_phone64_x86_64-userdebug` from the pinned manifest.
- Inspect all images and headers; generate GPT/super layout from actual artifacts.
- Verify kernel/modules, v4 vendor_boot, fstab, dynamic super, filesystem formats, ADB properties, and AVB descriptors.
- Deliverable: image contract report and reproducible disk image.

### Phase 7 — Android boot, graphics, input, networking, and ADB (guest/host integration)

- Boot Android through GBL ordinary x86 path.
- First prove serial/logcat and a basic UI; then virtio-gpu DRM/TWRP and Ranchu graphics/HWC; then touch/keyboard/phone keys; then user NAT and ADB TCP.
- Deliverable: Android UI/input/ADB acceptance evidence.

### Phase 8 — AVB development state, writable system, and Magisk (high-risk)

- Sign with PhoneBox test keys, validate unlocked/orange state, implement `adb remount`, run overlayfs persistence test, patch correct image with Magisk v30.7, and validate persistent `su`.
- Run v31.0 only in the controlled API 37 fallback matrix.
- Deliverable: root/AVB/remount report and exact image hashes.

### Phase 9 — TWRP x86_64 port (human recovery work; high-risk)

- Sync TWRP android-14.1, create `device/qemu/virtual-phone`, build dedicated recovery image against the selected kernel and GPT contract.
- Prove UI/DRM, input, partitions, wipe/flash, ADB/minadbd, sideload, and reboots.
- Deliverable: TWRP image and recovery acceptance report.

### Phase 10 — software peripherals (one subsystem at a time)

Order: battery/Health → sensors → deterministic camera → audio → modem/RIL. Each subsystem requires QEMU host/device, kernel/interface, guest HAL/service, VINTF/init/SELinux/product wiring, and framework-level acceptance. Deliverable: a separate report per subsystem; failures do not get hidden in an “emulator device present” claim.

### Phase 11 — persistence/snapshot/rollback hardening

- Test normal reboot, power-cycle, factory reset, Fastboot erase, TWRP wipe, AVB state, misc recovery requests, OVMF vars, QMP snapshot-save/load/delete, and external qcow2 overlays.
- Deliverable: state ownership matrix and snapshot runbook.

### Phase 12 — Windows end-to-end and release profile

- Run the complete Android → TWRP → GBL Fastboot → flash/boot → Android path from Windows using real `adb.exe`/`fastboot.exe`.
- Run Linux boot independently.
- Optionally build/test GBL production profile with TCP absent/gated.
- Deliverable: signed release checklist, known limitations, and Definition of Done evidence.

### Fallback ordering

If GBL is blocked after Phase 4, test established UEFI → U-Boot integration. Do not build a custom bootloader. If Ranchu graphics is blocked, use the Cuttlefish x86_64 image/profile and virtio-gpu/gfxstream contract. If TWRP Android 17 port is blocked, ship TWRP as a dedicated unencrypted recovery profile while clearly marking encrypted production userdata unsupported. If peripherals fail, keep the base virtual phone usable and gate each HAL independently.

---

## 14. Repository/file-level change plan (no code yet)

| Repository | Files/paths to add or change | Purpose | Upstream source | Dependency/owner |
|---|---|---|---|---|
| PhoneBox/QEMU | `VERSION`, source pin/branch metadata, launcher profile under `scripts/phonebox/`, `docs/virtual-phone-x86_64-implementation-plan.md` | Pin v11.1.0, explicit machine/device composition, document contract | QEMU v11.1.0 and PhoneBox tree [25][26] | Human maintainer; plan file is documentation only |
| PhoneBox/QEMU | `hw/i386/pc_q35.c`, `hw/i386/meson.build`, `hw/i386/Kconfig` only if measured need for a registered machine | Add a versioned `virtual-phone-x86_64` alias only if launcher composition is insufficient | Existing Q35 implementation [26] | Human QEMU core work; default is no change |
| PhoneBox/QEMU | Existing virtio paths `hw/block`, `hw/net`, `hw/display`, `hw/input`, `hw/audio`, `hw/virtio` | Reuse/fix upstream devices; no parallel models | QEMU virtio docs [26][27][28] | Human; only bug fixes required by tests |
| PhoneBox/QEMU | `hw/misc/goldfish_battery.c`, `include/hw/misc/goldfish_battery.h`, meson/Kconfig entries if absent | Port minimal AOSP goldfish battery device if QEMU fork lacks it | AOSP external/qemu goldfish battery [33] | Human QEMU device work; battery HAL gate |
| PhoneBox/QEMU | qemud/pipe service integration path under existing chardev/host service framework, if absent | Provide `sensors` and `FakeRotatingCameraSensor` deterministic services | AOSP goldfish camera/sensors and external/qemu [30][31] | Human; high-risk, spike before implementation |
| PhoneBox/QEMU | virtio-serial launcher/configuration only; no new protocol | Expose named `modem` port | Goldfish qemu-props/radio [32] | Human launcher plus AOSP modem simulator |
| PhoneBox/QEMU | `tests/qtest/phonebox-*`, acceptance test manifest | Verify device enumeration, reset, persistence, and no unintended NIC/audio | QEMU qtest conventions | Human test owner |
| EDK II/PhoneBox firmware repo | `PhoneBoxPkg/PhoneBoxPkg.dec`, `.dsc`, `.fdf`, `.inf` files | Package companion DXE drivers in pinned OVMF X64 build | OvmfPkgX64 [27] | Human firmware owner |
| EDK II/PhoneBox firmware repo | `PhoneBoxPkg/BootControlDxe`, `AvbDxe`, `OsConfigurationDxe`, `VendorVariableDxe` | Implement exact current GBL protocol contracts and state ownership | GBL EFI integration [3][5] | Human firmware owner; no GBL source fork initially |
| EDK II/PhoneBox firmware repo | optional `BootMemoryDxe`, `AvfDxe`, transport driver | Add only after scoped spike proves required | GBL docs [3] | Human; gated/high-risk |
| EDK II/PhoneBox firmware repo | firmware manifest and build lock | Record edk2/GBL/resource/header hashes and `OVMF_CODE/VARS` provenance | EDK II/GBL pins [1][27] | Human/release owner |
| AOSP checkout | manifest lock file; no changes to core manifest | Reproduce android17-release repositories and revisions | AOSP manifest/product [12] | Build/release owner |
| AOSP overlay repo | `device/qemu/virtual-phone/AndroidProducts.mk`, `BoardConfig.mk`, `device.mk`, product overlays | Small PhoneBox glue overlay; inherit goldfish product instead of replacing it | `device/generic/goldfish` [13][14][15] | Human Android owner; only after image inspection |
| AOSP overlay repo | `fstab.ranchu`/PhoneBox fstab, `init.phonebox.rc`, `ueventd.rc`, VINTF fragments, sepolicy | Expose actual GPT/virtio/HAL/recovery/ADB contracts | Goldfish init/fstab/HAL sources [15][16][30][31][32][33] | Human Android owner |
| AOSP overlay repo | `keylayout/`, touchscreen `.idc`, graphics/audio/radio/camera config | Map virtio-input and select one provider/HAL profile | QEMU/TWRP/AOSP device contracts [28][30] | Human guest integration owner |
| TWRP manifest/core repo | manifest pin; `TeamWin/android_bootable_recovery` branch `android-14.1` | Use newest verified core, not old x86 tree | TWRP sources/releases [19][20] | Human recovery owner |
| TWRP device repo | `device/qemu/virtual-phone/AndroidProducts.mk`, `BoardConfig.mk`, `device.mk`, `recovery.fstab`, recovery init/prop/flags | Dedicated x86_64 recovery image and exact GPT/dynamic partition contract | TWRP core and Android generic boot docs [19][20][21] | Human recovery owner |
| Magisk artifact repo/cache | pinned v30.7 APK/tools; optional v31.0 isolated artifact | x86_64 image patching/root validation | Magisk release/tools [22][23][24] | Human/release owner; no Magisk source fork initially |
| PhoneBox tooling | `scripts/phonebox/launch-x86_64`, `make-disk`, `adb-connect`, `fastboot-ipv6`, `snapshot`, Windows `.ps1` wrappers | Reproducible host flow, port allocation, image/hash logging, state lifecycle | QEMU invocation/QMP docs [26][36] | Human tooling owner; AI may document/static-review only |
| Test repository/PhoneBox tests | `tests/phonebox/manifest`, GBL protocol tests, image inspectors, Windows acceptance scripts | Exact ordered tests and evidence collection | GBL/Fastboot/ADB docs [3][4][8][34][35] | Human test owner |
| Documentation | this plan; firmware protocol matrix; image contract; Windows runbook; peripheral limitations; release checklist | Make source pins, limitations, and DoD auditable | All references below | Documentation owner |

**Policy boundary:** research/static analysis may identify paths, compare upstream sources, write this plan, and perform disposable experiments. Human maintainers must author/review core QEMU machine/device code, OVMF DXE protocols, Android product/HAL changes, TWRP device integration, and any upstreamable changes. No task in this plan authorizes bypassing the repository policy.

---

## 15. Exact tests and acceptance criteria

Tests run in this order. Every result records source pins, QEMU/OVMF/GBL/Android/TWRP/Magisk hashes, host details, command line, serial logs, and artifact paths.

| # | Test | Exact procedure | Acceptance criterion |
|---:|---|---|---|
| 1 | QEMU x86_64 machine | Start explicit `pc-q35-11.1` with no Android disk; query machine/device help; clean shutdown | QEMU starts without implicit e1000e/NIC/audio surprises; Q35/ACPI present; exit is clean |
| 2 | OVMF | Boot pinned `OVMF_CODE.fd` with private writable vars | OVMF menu/shell/serial log appears; vars persist; `BOOTX64.EFI` fallback path is found |
| 3 | GBL EFI start | Place `x86_64_dev` at `/EFI/BOOT/BOOTX64.EFI`; boot | GBL identifies itself, reaches logs/menu/boot mode without protocol crash |
| 4 | GBL storage | Present GPT disk; inspect GBL block/partition discovery and Fastboot `getvar` | Whole-disk BlockIo is discovered; named ESP/boot/super/userdata/misc/metadata/recovery are visible; no duplicate fake disk |
| 5 | GBL API/entropy/protocols | Read `gbl_fw_api_level`; exercise RNG; capture custom protocol installation | API variable is read-only and equals Android API 37; runtime RNG returns entropy; required protocol status is logged |
| 6 | GBL Fastboot entry | `adb reboot bootloader` from Android or set `misc` request; reboot | GBL enters Fastboot without modifying Android state |
| 7 | Fastboot TCP wire | Use packet capture/test harness on pinned client/device; connect port 5554 | Both sides exchange `FB01`; frames use 8-byte big-endian lengths; no custom framing |
| 8 | Windows Fastboot | From Windows run `fastboot devices`, `getvar all`, `getvar unlocked`, `getvar product` using actual AOSP client | Device appears; unlocked is truthfully `yes`; product is `virtual-phone-x86_64` or documented product value; all output is real |
| 9 | Generic Linux | Boot x86_64 bzImage/initramfs/rootfs; use virtio disk/net/gpu/input | Kernel/initramfs/rootfs boot; network, display, keyboard/touch, and virtio storage work independently of Android |
| 10 | Android image inspection | Run unpack_bootimg/avbtool/lpdump/filesystem/GPT inspection on every generated image | Actual header/layout is recorded; no plan assumption about init_boot/A-B/odm survives unverified |
| 11 | Android boot | Boot selected `sdk_phone64_x86_64-userdebug` through GBL ordinary bzImage path | Android reaches home/UI; `getprop ro.build.version.sdk=37`; no GBL image/AVB errors |
| 12 | Display | Verify DRM nodes, connector/mode, SurfaceFlinger/HWC dumpsys, 1080×2280 portrait | Guest renders UI inside Android; screen capture/host display is not a fake host UI |
| 13 | Touch/keyboard/phone keys | `getevent -lp`; inject touch/keyboard/key events; operate Android and TWRP menus | Correct EV_ABS/ABS_MT ranges, keycodes, orientation, and menu operation; no PS/2-only dependency |
| 14 | Android ADB TCP | `adb connect`, `adb devices`, shell, push, pull, reboot | Windows adb connects over documented forwarded TCP port; key authorization works; shell/push/pull/reboot pass |
| 15 | Unlock/AVB | Read GBL lock state, `getprop ro.boot.verifiedbootstate`, AVB logs; attempt factory reset | Default is unlocked/orange; factory reset does not relock; AVB remains present and reports test-key/unlocked state |
| 16 | Root | Run `adb shell id`, `adb shell su -c id`, `adb root`, `adb shell id`; reboot and repeat | Magisk `su -c id` returns UID 0; `adb root` returns UID 0 where allowed; persistent Magisk root survives reboot; test distinguishes these paths |
| 17 | Writable system | Run the exact marker test in section 9.4 | `adb remount` succeeds; marker is readable after reboot; overlay/base/reset behavior is documented and reproducible |
| 18 | TWRP boot | `adb reboot recovery` | Dedicated TWRP image boots through GBL; real TWRP UI appears; no GearLock dependency |
| 19 | TWRP ADB | Connect recovery port; shell/push/pull/sideload | Actual recovery adbd/minadbd works; `adb devices` identifies recovery; sideload completes with a signed test package |
| 20 | TWRP storage/UI | Inspect partitions; browse; terminal; wipe a disposable userdata; flash a test recovery/boot image; reboot | GPT/physical/logical partitions are correctly visible; wipe/flash are bounded to requested targets; UI, touch, keyboard, and reboot pass |
| 21 | Fastboot boot/flash | From Windows `fastboot boot twrp.img`, flash disposable recovery/boot, erase userdata, reboot | Temporary TWRP boot works; flash changes the unified disk; erase affects userdata only; Android boots after recovery/flash |
| 22 | Persistence/snapshot | Reboot; power-cycle; QMP snapshot-save/load/delete after guest quiesce; external overlay create/delete | userdata, misc, metadata, unlock state, and partition contents behave according to ownership table; snapshot operations report completion and restore coherently |
| 23 | Audio | `dumpsys media.audio_flinger`, enumerate ALSA/PCM, play test tone, capture microphone, volume/mute | One intended card/stream is visible; playback and capture produce expected data; volume/mute state changes; if unsupported, the profile is marked not implemented rather than silent |
| 24 | Camera | Enumerate camera provider; open front/rear; request fixed resolutions; capture repeated frames | Two cameras enumerate; deterministic test pattern/hash is stable for fixed settings; repeated open/close succeeds |
| 25 | Sensors | Enumerate requested sensor types; set fixed host values; observe Android events | Accelerometer/gyro/proximity/light/orientation events arrive with valid ranges/timestamps; deterministic test excludes documented noise/timestamp fields |
| 26 | Modem | Query radio power/registration/SIM/signal; send SMS; create/tear down data state; airplane mode/network loss | AIDL radio service is registered; AT/channel path works; control-plane state reaches Telephony; no claim of call audio |
| 27 | Battery | Change host battery controls; inspect sysfs, `dumpsys battery`, `dumpsys health`, SystemUI | Capacity/charging/USB/low-battery transitions reach Health AIDL and Android UI with correct units/status |
| 28 | Production profile gate | Build `x86_64_prod` only after all required protocol/AVB/RNG tests | Production artifact does not expose dev TCP; AVB/entropy/rollback/lock policy is explicit; any unsupported optional AVF/USB feature is documented |

### Mandatory root evidence

The root test is not passed by `adb root` alone. The evidence bundle must include:

```text
adb shell id
adb shell su -c 'id -u; id -Z'
adb shell magisk -c
adb shell magisk --path
adb shell getprop ro.product.cpu.abi
adb shell getprop ro.build.version.sdk
adb shell getprop ro.boot.verifiedbootstate
```

Expected: API 37, ABI `x86_64`, `su` UID 0, live Magisk path, truthful orange/unlocked state, and a result that survives a clean reboot.

### Encryption gate

The initial DoD requires unencrypted userdata and must not claim transparent FBE decrypt. A separate experiment may test F2FS plus metadata encryption only after a matching KeyMint/Gatekeeper/TEE path exists. If it fails, TWRP must advertise format/raw-backup limitations rather than attempting to decrypt or corrupt production-style encrypted data.

---

## 16. Risks, severity, and fallbacks

| Subsystem | Severity | Risk | Fallback |
|---|---|---|---|
| GBL x86_64 integration | High | Source builds but current firmware protocols/image contract may fail | Complete protocol spike; use UEFI→U-Boot only as established fallback; never write custom Fastboot/bootloader first |
| OVMF Android protocols | High | Generic OVMF lacks BootControl, AVB, API variable, OS config, rollback state | PhoneBoxPkg companion DXE; if AVB cannot be made truthful, remain dev-only and do not claim production |
| AOSP Android 17 x86_64 | Medium/high | Product is emulator/Ranchu-specific and moving; image layout may differ from tree flags | Pin actual artifacts; switch to Cuttlefish x86_64 comparison profile rather than inventing a third product |
| QEMU v11.1.0 baseline | Medium | A required PhoneBox fix may exist only in moving 11.1.50 | Carry a named backport on v11.1.0 with regression test; rebase only by explicit ADR |
| Graphics | High | Ranchu HWC/pipe and host renderer mismatch; virtio-gpu alone is not Android graphics | Keep virtio-gpu 2D + SwiftShader/lavapipe; use Cuttlefish/gfxstream profile; do not claim accelerated performance |
| TWRP x86_64/Android 17 | High | No current upstream Android 17 target; recovery placement/kernel/KMI may fail | Dedicated unencrypted recovery image, Android-14.1 core, same kernel; gate encryption and seamless-update claims |
| Magisk x86_64/API 37 | High | v30.7 stable does not prove Android 17; v31.0 is prerelease | Validate v30.7; isolate v31.0; if both fail, expose userdebug adb-root but mark Magisk DoD unmet |
| Fastboot TCP/Windows | High | GBL TCP dev-only, link-local IPv6/SNP/TAP/parser syntax may block Windows | Keep Android/ADB on user NAT; run Fastboot on Linux/TAP for diagnosis; add USB/platform transport later; no custom protocol |
| ADB TCP/recovery | Medium | adbd properties, recovery transport, key authorization, and port forwarding differ | Direct explicit `adb connect`; keep USB secondary; use debug recovery/minadbd and document ports |
| Camera HAL | High | Camera provider/VINTF/pipe/buffers are image-specific; duplicate providers conflict | Deterministic FakeRotatingCamera only; remove alternative provider; fallback to camera capability disabled rather than fake enumeration |
| Sensor HAL | Medium/high | qemud dependency and random bias/noise/timestamps hurt determinism | Fixed calibrated subset; bounded-value tests; retain Sensors 2.1 multihal; no byte-stable uncalibrated claims |
| Audio HAL | High | virtio-snd driver/HAL may not exist in Ranchu product; HDA policy may mismatch | One-card profile at a time; Trout-derived virtio HAL or tested HDA fallback; audio can be gated without blocking boot |
| RIL/modem | High | AIDL service/virtio port ordering/AT coverage/carrier config may fail | Goldfish AIDL path first; emulator modem simulator; reference-RIL only for older compatibility profile |
| Battery/Health | Medium | QEMU power-supply fields/units and Health AIDL/SELinux wiring may mismatch | Port goldfish battery model; validate sysfs/Health; if needed expose a read-only battery capability with explicit limitation |
| Storage/A-B | Medium/high | Selected product is non-A/B while GBL expects BootControl; forcing slots corrupts layout | Truthful single-slot BootControl and dual ESP reservation; add A/B only as a new image contract |
| Encryption | High | Secure FBE requires trusted services absent from generic QEMU | Initial unencrypted userdata; format/raw backup only; no decryption claim |
| Snapshots | Medium | QEMU snapshots do not make active Android writes transactional | Freeze/clean shutdown; one disk/vars manifest; use disposable external qcow2 overlays |
| Host resources | Medium | AOSP build exceeds sandbox resources | Use the specified persistent x86_64 workstation; sandbox remains research-only |

---

## 17. Minimum and recommended development host

### Minimum functional workstation

- x86_64 Linux (Ubuntu 24.04-compatible or the pinned AOSP-supported distribution);
- 12 physical cores / 16 threads;
- 32 GiB RAM plus 16 GiB swap;
- 500 GiB free NVMe after operating-system space;
- `/dev/kvm` available and usable by the build user;
- hardware virtualization enabled in firmware;
- 1 Gb/s or better Internet connection and sufficient repository cache;
- Windows 10/11 x86_64 host or VM with real AOSP Platform Tools for Fastboot/ADB acceptance;
- separate workspace for AOSP `out/`, ccache, QEMU/OVMF/GBL builds, disk images, and logs.

This is a build minimum, not a performance promise. It is materially larger than the Phase 0 sandbox and should not be substituted by it.

### Recommended workstation

- 16–24 physical cores / 32–48 threads;
- 64–128 GiB RAM;
- 1–2 TiB free NVMe, with separate backup space for source/artifact caches;
- KVM and nested virtualization if the Windows test environment is virtualized;
- dedicated GPU with known EGL/OpenGL/Vulkan support for virgl/gfxstream measurements, while retaining SwiftShader/lavapipe fallback;
- a second Windows machine or VM with a real Ethernet/TAP/Wintun setup for link-local IPv6 Fastboot testing;
- stable host clock, serial capture, packet capture, and reproducible container/toolchain metadata.

The Linux host builds QEMU, OVMF, GBL, AOSP, and TWRP. The Windows host runs the acceptance clients; it is not required to build Android.

---

## 18. Precise Definition of Done

The project is **Done for the development profile** only when all items below are evidenced, not merely planned:

1. Source lock records QEMU v11.1.0, `pc-q35-11.1`, OVMF commit, GBL manifest/source/resources, Android manifest/product, TWRP branch/commits, Magisk artifact, and Windows tool hashes.
2. A reproducible Linux build produces QEMU, OVMF code/vars, GBL `x86_64_dev`, Android `sdk_phone64_x86_64-userdebug`, TWRP recovery, and the image-builder outputs.
3. QEMU starts the explicit x86_64 Q35 profile with ACPI and every required virtio device; no unintended default NIC/audio device is present.
4. OVMF loads `/EFI/BOOT/BOOTX64.EFI`, persists vars, exposes BlockIo, RNG, SNP, SimpleTextOutput, allocation, FAT/GPT, and the PhoneBox GBL protocol package.
5. GBL discovers the whole GPT disk, reads the read-only API variable, verifies development AVB/lock state, and boots the Android x86_64 bzImage through the ordinary path.
6. The unified disk is the same storage seen by GBL, Android, TWRP, and Fastboot; no duplicate fake storage exists.
7. Windows `fastboot.exe` reaches GBL over the documented TCP/IPv6 profile on port 5554, passes `FB01`/length framing, reports unlocked truthfully, and successfully performs tested getvar/boot/flash/erase/reboot operations.
8. Android reaches a real guest UI at 1080×2280 portrait, with documented graphics mode and fallback; Android is not host-rendered.
9. Android ADB TCP connects from Windows; shell, push, pull, reboot, and key authorization pass.
10. The default device is unlocked/orange, OEM unlocking is enabled, factory reset does not relock it, and AVB remains present with development keys/state.
11. `adb root` works on the userdebug profile where expected; Magisk x86_64 `su` returns actual UID 0 and survives reboot; the selected Magisk version/API 37 limitation is recorded.
12. `adb remount` succeeds and a marker write to `/system/etc/phonebox-dev-marker` survives reboot in the documented overlay layer and resets predictably.
13. `adb reboot recovery` boots real TWRP from the dedicated recovery contract; TWRP UI, touch, keyboard, storage, wipe, flash, terminal, ADB, sideload, and reboot pass.
14. Android and TWRP use the same GPT/dynamic-partition/userdata/metadata/misc state contract; destructive operations are scoped and logged.
15. Linux independently boots and uses virtio block, network, display, and input.
16. Camera, sensors, modem, audio, and battery each have a tested host-device → guest interface → Android HAL/service path. Unsupported optional features are reported explicitly; no subsystem is declared complete from QEMU enumeration alone.
17. Normal reboot, power-cycle, factory reset, Fastboot erase, TWRP wipe, AVB persistence, and snapshot/overlay lifecycle pass the state ownership matrix.
18. All ordered tests in section 15 have logs and artifact hashes, including Windows Fastboot and ADB tests.
19. A production profile is **not** claimed unless GBL `x86_64_prod`, production AVB/entropy/rollback policy, optional AVF decision, and absence/gating of TCP Fastboot all pass separate acceptance. The development profile's TCP Fastboot is explicitly labeled development-only.
20. Documentation names every unsupported behavior: encrypted userdata decryption unless proven, USB/MTP unless later implemented, physical Wi-Fi/RF/call audio, certified Android 17 x86_64 GBL availability, and any experimental gfxstream/rutabaga mode.

---

## References

[1]: https://android.googlesource.com/platform/bootable/libbootloader/+/206c43c04f88d04b7be8481a8b7ee232290d3bf9/gbl/README.md "AOSP current GBL README and source build procedure"

[2]: https://android.googlesource.com/platform/bootable/libbootloader/+/206c43c04f88d04b7be8481a8b7ee232290d3bf9/gbl/efi/BUILD "AOSP current GBL x86_64 dev/prod/bootstub targets"

[3]: https://android.googlesource.com/platform/bootable/libbootloader/+/206c43c04f88d04b7be8481a8b7ee232290d3bf9/gbl/docs/efi_integration.md "AOSP GBL UEFI protocol and variable contract"

[4]: https://android.googlesource.com/platform/bootable/libbootloader/+/206c43c04f88d04b7be8481a8b7ee232290d3bf9/gbl/docs/gbl_fastboot.md "AOSP GBL Fastboot transport and command behavior"

[5]: https://android.googlesource.com/platform/bootable/libbootloader/+/206c43c04f88d04b7be8481a8b7ee232290d3bf9/gbl/docs/partitions.md "AOSP GBL GPT, BlockIo, raw-storage, and partition rules"

[6]: https://android.googlesource.com/platform/bootable/libbootloader/+/206c43c04f88d04b7be8481a8b7ee232290d3bf9/gbl/efi/src/fastboot.rs "AOSP GBL EFI Fastboot entry and development-only TCP"

[7]: https://android.googlesource.com/platform/bootable/libbootloader/+/206c43c04f88d04b7be8481a8b7ee232290d3bf9/gbl/efi/src/net.rs "AOSP GBL SNP-only network adapter and link-local IPv6"

[8]: https://android.googlesource.com/platform/bootable/libbootloader/+/206c43c04f88d04b7be8481a8b7ee232290d3bf9/gbl/libfastboot/src/lib.rs "AOSP GBL Fastboot TCP FB01 handshake and framing"

[9]: https://android.googlesource.com/platform/bootable/libbootloader/+/206c43c04f88d04b7be8481a8b7ee232290d3bf9/gbl/efi/src/android_boot.rs "AOSP GBL x86_64 bzImage and optional EFI-stub handoff"

[10]: https://source.android.com/docs/core/architecture/bootloader/generic-bootloader/gbl-dev "AOSP GBL deployment requirements and architecture-specific deployment guidance"

[11]: https://source.android.com/docs/core/architecture/bootloader/generic-bootloader/gbl-release-builds "AOSP GBL release artifacts and Android 16/17 release-build documentation"

[12]: https://android.googlesource.com/platform/manifest/+/29ace668ae756c7b8917c57abb440f6518844b0c/default.xml "AOSP android17-release manifest"

[13]: https://android.googlesource.com/device/generic/goldfish/+/296e55aa0244e8929e393e00e34471fef2a5d662/AndroidProducts.mk "AOSP Goldfish product inventory"

[14]: https://android.googlesource.com/device/generic/goldfish/+/296e55aa0244e8929e393e00e34471fef2a5d662/64bitonly/product/sdk_phone64_x86_64.mk "AOSP native x86_64 Goldfish phone product"

[15]: https://android.googlesource.com/device/generic/goldfish/+/296e55aa0244e8929e393e00e34471fef2a5d662/board/BoardConfigCommon.mk "AOSP Goldfish boot, dynamic partition, filesystem, and kernel board configuration"

[16]: https://android.googlesource.com/device/generic/goldfish/+/296e55aa0244e8929e393e00e34471fef2a5d662/init/init.ranchu.rc "AOSP Ranchu init and ADB startup wiring"

[17]: https://source.android.com/docs/core/architecture/partitions/generic-boot "Android generic boot, init_boot, and boot image rules"

[18]: https://source.android.com/docs/core/ota/dynamic_partitions/implement "Android dynamic partition and super metadata implementation"

[19]: https://github.com/TeamWin/android_bootable_recovery/tree/android-14.1 "Newest verified TeamWin recovery core branch"

[20]: https://twrp.me/site/update/2024/02/21/3.7.1-released.html "Official TWRP 3.7.1 release notes and Android-generation scope"

[21]: https://github.com/TeamWin/android_device_emulator_twrpx8664/tree/android-5.0 "Historical TeamWin x86_64 emulator device tree; prior art only"

[22]: https://github.com/topjohnwu/Magisk/releases/tag/v30.7 "Stable Magisk v30.7 release"

[23]: https://github.com/topjohnwu/Magisk/releases/tag/v31.0 "Magisk v31.0 prerelease with Android 17/Zygisk claim"

[24]: https://raw.githubusercontent.com/topjohnwu/Magisk/v30.7/scripts/util_functions.sh "Magisk v30.7 architecture and image-selection logic"

[25]: https://github.com/leotruza/PhoneBox/tree/a17ad80afc45366ae0242d88878c21a220edac7f "PhoneBox public tree and inspected current HEAD"

[26]: https://gitlab.com/qemu-project/qemu/-/tags/v11.1.0 "Official QEMU v11.1.0 tag and release baseline"

[27]: https://github.com/tianocore/edk2/tree/d07d3f5a5769cc8c9f76385174b73ea85525077/OvmfPkg "Pinned-review EDK II OVMF package"

[28]: https://www.qemu.org/docs/master/system/devices/virtio/virtio-gpu.html "QEMU virtio-gpu display, virgl, and rutabaga documentation"

[29]: https://source.android.com/docs/devices/cuttlefish/gpu "AOSP Cuttlefish GPU modes, gfxstream, virgl, and software fallback"

[30]: https://android.googlesource.com/device/generic/goldfish/+/3ce87694caeb4a330280bb1284d9ad050fe28263/hals/camera/FakeRotatingCamera.cpp "AOSP Goldfish deterministic FakeRotatingCamera implementation"

[31]: https://android.googlesource.com/device/generic/goldfish/+/3ce87694caeb4a330280bb1284d9ad050fe28263/hals/sensors/multihal_sensors_qemu.cpp "AOSP Goldfish QEMU Sensors multihal implementation"

[32]: https://android.googlesource.com/device/generic/goldfish/+/3ce87694caeb4a330280bb1284d9ad050fe28263/hals/radio/main.cpp "AOSP Goldfish current AIDL radio service"

[33]: https://android.googlesource.com/platform/external/qemu/+/ae9d18d2b6261179fbd57fffec720a04f7bfb053/android-qemu2-glue/qemu-battery-agent-impl.cpp "AOSP emulator Goldfish battery agent"

[34]: https://developer.android.com/tools/adb "Official Android ADB architecture and transport documentation"

[35]: https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/fastboot.cpp "AOSP Fastboot host TCP address parsing and default port"

[36]: https://www.qemu.org/docs/master/system/qemu-manpage.html "QEMU invocation, explicit blockdev/device, networking, and QMP-related reference"

[37]: https://source.android.com/docs/automotive/virtualization/architecture "AOSP virtualized Android Automotive architecture and virtio-snd guest audio path"

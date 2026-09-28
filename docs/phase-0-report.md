# Phase 0 Report — `virtual-phone-x86_64`

**Date:** 2026-09-28  
**Environment:** Manus Sandbox, Ubuntu 24.04-compatible userspace, x86_64  
**Repository:** `leotruza/PhoneBox` (QEMU fork)  
**Baseline requested:** QEMU 11.1.0, AOSP `android17-release`, GBL, GearLock, Magisk v30.7

## Executive result

**Status: NO-GO for implementation in this sandbox; GO for continued planning and static feasibility work.**

The repository is an unmodified QEMU tree at commit `81ce3a8773`, version `11.1.50`, with no `virtual-phone-x86_64` implementation present. The environment is suitable for repository inspection and small local experiments, but it is not suitable for the planned end-to-end build or boot validation:

- QEMU, OVMF, ADB, fastboot, `repo`, and Bazel are not installed.
- `/dev/kvm` is unavailable, so the requested KVM performance path cannot be tested.
- The sandbox has 6 vCPUs, 7.8 GiB RAM, and approximately 40 GiB free disk. A full AOSP checkout/build plus QEMU/GBL artifacts is not a realistic fit.
- The repository's `AGENTS.md` explicitly limits AI assistance to research, static analysis, debugging, local experiments, and trivial non-copyrightable changes; it forbids writing core QEMU features intended for upstreaming. Therefore no Phase 1 machine implementation or other core feature code was added.

## Checks performed

### Repository baseline

- Cloned `https://github.com/leotruza/PhoneBox.git` successfully.
- Current branch: `master`, tracking `origin/master`.
- Remotes: the selected fork and `upstream` QEMU.
- Current commit: `81ce3a8773`.
- QEMU tree version: `11.1.50`.
- Search found no files matching the planned `virtual-phone`, `gearlock`, or related implementation paths.
- Existing i386 integration uses `hw/i386/meson.build`, `hw/i386/Kconfig`, and the Q35 implementation in `hw/i386/pc_q35.c`; these are the likely static reference points for a future, human-authored local experiment.

### Host capability

| Check | Observed result | Impact |
|---|---|---|
| Architecture | x86_64 | Suitable for x86_64 static analysis and TCG experiments |
| CPUs | 6 vCPUs, Intel Xeon @ 2.10 GHz | Adequate for small builds, not a reference performance host |
| Memory | 7.8 GiB total, 6.6 GiB available at check time | Insufficient margin for AOSP Android 17 build |
| Disk | 51 GiB filesystem, 40 GiB free | Insufficient margin for AOSP checkout, intermediates, and images |
| KVM | `/dev/kvm` unavailable | KVM boot/performance tests cannot run |
| QEMU binary | Not installed | Baseline boot test cannot run yet |
| OVMF | No firmware found under `/usr/share` | UEFI baseline cannot run |
| ADB / fastboot | Not installed | TCP transport checks cannot run |
| repo / Bazel | Not installed | AOSP/GBL source and build steps cannot start |

## Source and version validation

The following lightweight remote checks succeeded:

- QEMU tag `v11.1.0` exists at commit `2c6a474b8ad0ae6a368a025d720c8aec7e499107`.
- AOSP manifest branch `android17-release` exists at commit `29ace668ae756c7b8917c57abb440f6518844b0c`.
- GearLock repository is reachable.
- Magisk tag `v30.7` exists at commit `e8a58776f1d7bdf852072ad0baa6eceb9a1e4aac`.
- The literal URL `https://android.googlesource.com/bootable/libbootloader` in the project plan does **not** resolve as a standalone Git repository. Current GBL documentation uses the `uefi-gbl-mainline` manifest at `https://android.googlesource.com/kernel/manifest`; the source is brought into the checkout as `platform/bootable/libbootloader`.

## GBL plan corrections requiring design review

The plan should not yet treat the GBL path as validated for x86_64:

1. Current official deployment documentation describes two FAT ESP partitions named `android_esp_a` and `android_esp_b`, each at least 8 MiB, rather than one 64 MiB ESP.
2. The official documented EFI path is `/EFI/BOOT/BOOTAA64.EFI` in the deployment section, which reflects the documented ARM64 deployment flow. The project plan's `BOOTX64.EFI` choice for x86_64 requires an explicit x86_64-specific validation rather than assumption.
3. Official GBL requirements include UEFI block I/O, RNG, memory allocation, text output, AVB, boot-control, AVF, vendor variables, slot metadata, and dynamic-partition support. OVMF alone does not provide the Android-specific firmware protocols required by production GBL.
4. Official development instructions build with the `uefi-gbl-mainline` manifest and `tools/bazel run //bootable/libbootloader:gbl_efi_dist`; the project plan's extra Bazel toolchain argument is not required by the current published instructions.
5. The official documentation presents Cuttlefish as the documented virtual-device test path. A standalone Q35 + OVMF + GBL x86_64 path is therefore a research spike, not a demonstrated baseline.

## Phase 0 exit criteria assessment

| Criterion | Result | Notes |
|---|---|---|
| QEMU 11.1.0 boots Linux with OVMF | Not run | Required tools/firmware absent; no KVM |
| AOSP `sdk_phone_x86_64-userdebug` builds/boots | Not run | Toolchain absent; resource budget is inadequate |
| GBL x86_64 builds/runs under OVMF | Not run | Toolchain absent; GBL x86_64 assumptions need validation |
| GearLock installation verified | Not run | No Android-x86 guest or image workflow available |
| Magisk v30.7 patching verified | Not run | No test `init_boot.img` available |
| Windows fastboot TCP verified | Not run | Windows host and fastboot client unavailable here |
| ADB TCP verified | Not run | ADB client and Android guest unavailable |
| GBL feasibility determined | **Conditional / research spike required** | Official docs do not validate the exact standalone x86_64 architecture |
| `docs/phase-0-report.md` written | **Complete** | This report |

## Recommendation

Do not begin Phase 1 core QEMU feature work from this sandbox. First obtain a persistent or local x86_64 development host with substantially more storage and memory, install the QEMU/OVMF and Android build prerequisites, and run a narrowly scoped GBL spike. The spike should answer these questions before any machine-device design is committed:

1. Can the current GBL source produce an x86_64 EFI application from the mainline manifest?
2. Which Android-specific UEFI protocols must be implemented or supplied by the firmware layer?
3. Does the selected AOSP x86_64 product boot with UEFI/ACPI and the proposed partition layout?
4. Is fastboot-over-TCP actually supported by the selected GBL build, or must a separate transport/server be implemented?
5. Can GearLock be booted as a recovery image in this boot chain, or is an Android-x86/GRUB integration required?

Within the repository's AI policy, the next safe contribution is limited to a research note, static analysis, or a disposable local test outside the core QEMU tree. A human maintainer should author and review any upstreamable machine, device, bootloader, or guest integration code.

## References

- [Android Generic Bootloader overview](https://source.android.com/docs/core/architecture/bootloader/generic-bootloader)
- [Android Deploy GBL](https://source.android.com/docs/core/architecture/bootloader/generic-bootloader/gbl-dev)
- QEMU repository guidance: `AGENTS.md`

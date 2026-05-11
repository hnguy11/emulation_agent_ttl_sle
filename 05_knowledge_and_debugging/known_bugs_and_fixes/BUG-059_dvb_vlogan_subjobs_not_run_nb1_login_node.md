---
bug_id: BUG-059
title: "DVB vcssimmpp/jem/cpp vlogan sub-jobs silently 'did not run' when NB=1 set in PCD Makefile.cfg"
date_discovered: 2026-05-11
status: fixed
severity: blocker
stage: "sim.vcssimmpp.vcssimmpp_analysis / codegen_dv.jem / codegen_dv.cpp"
bundle: all
category: build-config
related_patterns: []
tags: [dvb, nb, nbfeeder, vcssimmpp, jem, cpp, vp2ppm, login_node, makefile_cfg, overrides, pcd, zse5, ttlbx]
phase: "BUILD"
symptoms: "DVB vcssimmpp build summary shows root libs Failed Skipped vlogan sub-jobs did not run exit status -10 -3034 no analysis.log created"
keywords: "nb_feeder vp2ppm did_not_run export_NB_1 Makefile.cfg overrides pcd PCD_ZSE5_UPF vcssimmpp_analysis nbfeeder_launch"
trackers: "output/grdlbuild/logs/ttlbx_n2p.sim.vcssimmpp.vcssimmpp_analysis.log output/ttlbx_n2p/vcssimmpp/build_summary.log"
---

## Symptom

DVB vcssimmpp (and jem/cpp) build summary shows root libs as **Failed**, all dependent libs as **Skipped**. No `analysis.log` files are created in the lib directories. The feeder log shows jobs are dispatched but immediately return "Finished - did not run":

```
output/ttlbx_n2p/vcssimmpp/build_summary.log:
| vcssimmpp.lib.uvm_val     | Failed  | ...
| vcssimmpp.lib.uri_rtl_lib | Failed  | ...
| vcssimmpp.lib.comet_val_lib | Failed | ...
| vcssimmpp.lib.uri_verif_lib | Skipped | ...   (all dependents skipped)
...
```

In `/tmp/dvb_nbflow.hnguy11/nbfeeder/logs/tasks.log`:
```
INFO  hnguy11.238 - Job 20174 (UUID:...) Finished - did not run
INFO  hnguy11.238 - Task is finished with exit status -10
```

In the nbfeeder log:
```
WARN CachedInetAddress - /tmp/nbflow.hnguy11/etc/getHostIP.pl script doesn't exist
INFO ProtocolForInteractionGenerator - protocol for interaction vp2ppm with scynbm436.zsc16.intel.com is null
```

## Triggered By

This bug is triggered when **all of the following are true**:
1. `export NB := 1` is set in any of the 3 PCD override Makefile.cfg files (see Root Cause)
2. The `vcssimmpp_analysis` grdlbuild task runs **locally on a login node** (e.g., `sccc05073702`) rather than on a farm node
3. The login node's nbfeeder lacks the `vp2ppm` protocol needed to dispatch jobs to the farm

This typically happens when running a targeted grdlbuild command locally (not a full pipeline run), e.g.:
```bash
grdlbuild :ttlbx_n2p:emu:common:pkg_tls_compile_ready
```

## Root Cause

`export NB := 1` was set in the PCD override Makefile.cfg files during a `-nb` training session. This is **incorrect** — the passing reference build has NO `NB` setting in these files, allowing DVB to run vlogan jobs directly on the local machine (fast, ~28 seconds for all 16 libs via `make -j 8`).

With `NB := 1`, DVB calls `nbfeeder_launch.pl` which tries to submit each vlogan job as a separate farm job. When running on a login node, the nbfeeder lacks the `vp2ppm` protocol → all jobs return "Finished - did not run" within seconds → no libraries are compiled → all root libs show "Failed".

**Files set incorrectly** (real paths, via symlinks under `overrides/`):
- `integration/hotfix/rtl/pcd/verif/emu/PCD_ZSE5_UPF/Makefile.cfg` — line 40
- `integration/hotfix/rtl/pcd_cfgr/verif/emu/PCD_ZSE5_UPF/Makefile.cfg` — line 40
- `integration/hotfix/rtl/pcd_cfgr/verif/emu/PCD_ZSE4_REDUCED_UPF/Makefile.cfg` — line 40

**Include chain (vcssimmpp flow):**
```
verif/vcssimmpp/Makefile
  → cfg/Makefile.common
    → verif/emu/Makefile.sle
      → overrides/pcd/verif/emu/PCD_ZSE5_UPF/Makefile.cfg  ← NB := 1 here
```

**Secondary issue:** A stale `NBFEEDER` address (e.g., `scy21204.zsc16.intel.com:34827`) was also set on line 43 of the same files during the training session. The stale address points to a dead feeder from a prior session, causing DVB to recreate a fresh feeder on the current machine — but that feeder still can't submit jobs from a login node.

## Fix / Solution

**Clear `NB` and `NBFEEDER`** in all 3 real files (the symlinks under `overrides/` point to `integration/hotfix/rtl/`):

```bash
WORKAREA="<path to workarea>"

# Apply to real files (not symlinks)
sed -i 's/^export NB               := 1/export NB               :=/' \
  "$WORKAREA/integration/hotfix/rtl/pcd/verif/emu/PCD_ZSE5_UPF/Makefile.cfg" \
  "$WORKAREA/integration/hotfix/rtl/pcd_cfgr/verif/emu/PCD_ZSE5_UPF/Makefile.cfg" \
  "$WORKAREA/integration/hotfix/rtl/pcd_cfgr/verif/emu/PCD_ZSE4_REDUCED_UPF/Makefile.cfg"

sed -i 's/^export NBFEEDER         := .*/export NBFEEDER         :=/' \
  "$WORKAREA/integration/hotfix/rtl/pcd/verif/emu/PCD_ZSE5_UPF/Makefile.cfg" \
  "$WORKAREA/integration/hotfix/rtl/pcd_cfgr/verif/emu/PCD_ZSE5_UPF/Makefile.cfg" \
  "$WORKAREA/integration/hotfix/rtl/pcd_cfgr/verif/emu/PCD_ZSE4_REDUCED_UPF/Makefile.cfg"

# Verify via symlinks
grep "^export NB\b\|^export NBFEEDER\b" \
  "$WORKAREA/overrides/pcd/verif/emu/PCD_ZSE5_UPF/Makefile.cfg" \
  "$WORKAREA/overrides/pcd_cfgr/verif/emu/PCD_ZSE5_UPF/Makefile.cfg" \
  "$WORKAREA/overrides/pcd_cfgr/verif/emu/PCD_ZSE4_REDUCED_UPF/Makefile.cfg"
# All 3 should show: export NB := (empty) and export NBFEEDER := (empty)
```

After applying, re-run the vcssimmpp build. DVB will run vlogan locally on the farm node (via `make -j 8`), completing all 16 libs in ~30 seconds.

## Files Affected

- `integration/hotfix/rtl/pcd/verif/emu/PCD_ZSE5_UPF/Makefile.cfg` (line 40: NB, line 43: NBFEEDER) — cleared
- `integration/hotfix/rtl/pcd_cfgr/verif/emu/PCD_ZSE5_UPF/Makefile.cfg` (line 40: NB, line 43: NBFEEDER) — cleared
- `integration/hotfix/rtl/pcd_cfgr/verif/emu/PCD_ZSE4_REDUCED_UPF/Makefile.cfg` (line 40: NB, line 43: NBFEEDER) — cleared

## Verification

After fix, re-run and check:
```bash
grep -E "Passed|Failed|Skipped" output/ttlbx_n2p/vcssimmpp/build_summary.log
# Expected: all 16 libs show "Passed"
```

The vcssimmpp_analysis log should show:
```
make --no-print-directory -j 8 -f .../flowgen/Makefile all_analysis
analysis   vcssimmpp.lib.uvm_val   RUN
analysis   vcssimmpp.lib.uvm_val   PASS
...
Exit status: 0
```

## Notes

### Makefile.cfg files are symlinks — edit the real targets

The `overrides/pcd/verif/emu/PCD_ZSE5_UPF/Makefile.cfg` path is a **symlink** to
`integration/hotfix/rtl/pcd/verif/emu/PCD_ZSE5_UPF/Makefile.cfg`.
Using `sed -i` on the symlink silently edits the symlink pointer, not the file content.
Always resolve via `readlink -f` or apply directly to the `integration/hotfix/rtl/` paths.

### NB := 1 in verif/emu/zebu/Makefile.cfg is intentional

`verif/emu/zebu/Makefile.cfg` also has `NBFEEDER` and may have `NB` settings — these are only included by the zebu flow and are intentional for ZeBu builds. Do NOT clear them.

### Relation to BUG-058

BUG-058 documents the prior issue where `NB := 1` + empty `cfg/compute.cth` caused "Compute section not found for netbatch". The fix for BUG-058 (populating `cfg/compute.cth`) resolved that symptom but left `NB := 1` in place, exposing this new failure mode. The correct long-term fix is to NOT set `NB := 1` in the PCD override Makefile.cfg files.

### NEVER set NB := 1 in these Makefile.cfg files during training sessions

Setting `NB := 1` in `overrides/pcd/*/Makefile.cfg` during agent `-nb` build training is **incorrect**. These files control the DVB sub-flow (vlogan compilation), not the top-level grdlbuild NB submission. The top-level NB behavior is controlled by grdlbuild's `useNBResource()` in `build.gradle.kts`, not by Makefile.cfg.

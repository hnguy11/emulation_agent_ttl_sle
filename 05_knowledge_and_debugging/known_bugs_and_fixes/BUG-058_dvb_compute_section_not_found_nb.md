---
bug_id: BUG-058
title: "DVB jem/vcssimmpp/cpp fail with 'Compute section not found for netbatch' on ZSE5 -nb builds"
date_discovered: 2026-05-08
status: fixed
severity: blocker
stage: "codegen_dv.jem / sim.vcssimmpp.vcssimmpp_analysis / codegen_dv.cpp"
bundle: all
category: build-config
related_patterns: []
tags: [dvb, nb, netbatch, compute, cth, jem, vcssimmpp, cpp, zse5, ttlbx]
phase: "BUILD"
symptoms: "Compute section not found for netbatch in tool.cth Exit Status 2 LiteInfraEnv NB"
keywords: "dvb_compute_section netbatch nb_routing jem_nb vcssimmpp_nb cfg_compute_cth"
trackers: "output/grdlbuild/logs/ttlbx_n2p.codegen_dv.jem.log output/grdlbuild/logs/ttlbx_n2p.sim.vcssimmpp.vcssimmpp_analysis.log output/grdlbuild/logs/ttlbx_n2p.codegen_dv.cpp.log"
---

## Symptom

DVB's jem, vcssimmpp, and cpp stages all fail immediately with Exit Status 2 when run with `-nb`.

```
output/grdlbuild/logs/ttlbx_n2p.codegen_dv.jem.log:
| Exit Status    : 2                                                          |

In DVB LiteInfraEnv.py:
FATAL: Compute section not found for netbatch in tool.cth
```

The stages start on the NB farm (qwait = 0-2s) but die within ~1 minute before running any lib analysis jobs.

## Triggered By

```bash
grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse -nb
```

The `-nb` flag itself is NOT the cause — the cause is `NB=1` being set unconditionally by the PCD Makefile include (see Root Cause below). This bug affects ALL TTLbx ZSE5 builds that use DVB flows (jem, vcssimmpp, cpp).

## Root Cause

`NB := 1` is set unconditionally from inside the Makefile include chain, not from the shell environment:

**Include chain:**
```
verif/jem/Makefile
  → cfg/Makefile.common
    → verif/emu/Makefile.sle (line 19)
      → overrides/pcd/verif/emu/PCD_ZSE5_UPF/Makefile.cfg (line 40: export NB := 1)
```

DVB's `LiteInfraEnv.py` (line 132) checks `os.getenv('NB')` — if set, it requires a valid COMPUTE section in `tool.cth`. DVB searches `tool.cth` (which includes `cfg/compute.cth` via `[INCLUDES]`) for a section named:
1. `{flow}@{site}` — e.g. `jem@zsc16`
2. `_DEFAULT@{site}` — e.g. `_DEFAULT@zsc16`
3. `_DEFAULT`

If none found → FATAL. The site name comes from `EC_SITE` env var, which is `zsc16` at TTL.

`cfg/compute.cth` is **empty** in the seed workareas (git initial commit `8ee7ea011` has empty file `e69de29bb`). This means every new workarea cloned from seed will hit this bug on the first `-nb` build.

## Fix / Solution

Populate `cfg/compute.cth` with inline COMPUTE sections for all DVB flows. **Do NOT use `[INCLUDES]`** — keep settings self-contained in the model:

```bash
cat > $WORKAREA/cfg/compute.cth << 'EOF'
[COMPUTE]
    Name = jem@zsc16
    type = batch
    qslot = /PCH/CSS/TTL/emu
    target = zsc16_express
    NBCMD = nbjob
    RAM = 32
    CPU = 4
    OS = SLES15

[COMPUTE]
    Name = vcssimmpp@zsc16
    type = batch
    qslot = /PCH/CSS/TTL/emu
    target = zsc16_express
    NBCMD = nbjob
    RAM = 32
    CPU = 4
    OS = SLES15

[COMPUTE]
    Name = cpp@zsc16
    type = batch
    qslot = /PCH/CSS/TTL/emu
    target = zsc16_express
    NBCMD = nbjob
    RAM = 32
    CPU = 4
    OS = SLES15

[COMPUTE]
    Name = _DEFAULT@zsc16
    type = batch
    qslot = /PCH/CSS/TTL/emu
    target = zsc16_express
    NBCMD = nbjob
    RAM = 32
    CPU = 4
    OS = SLES15
EOF
```

Then commit it to the workarea's git:
```bash
cd $WORKAREA
git add cfg/compute.cth
git commit -m "cfg/compute.cth: add DVB NB COMPUTE sections for zsc16

PCD Makefile.cfg unconditionally sets NB=1 for ZSE5 builds, requiring
COMPUTE sections in tool.cth for DVB jem/vcssimmpp/cpp NB sub-tasks.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Files Affected

- `cfg/compute.cth` — Written with 4 COMPUTE sections (was empty in seed workarea)

## Verification

After applying the fix, re-run the build. DVB should now:
1. NOT fatal with "Compute section not found" — the jem log will show NB jobs queued
2. Inner lib NB jobs will start with `--class SLES15&&32&&4` (visible in `flowgen/nbfeeder.nbtask`)
3. jem DVB summary table shows lib targets as **Passed** or **Skipped** (not **Failed**)

```bash
# Verify the nbtask uses the correct class after flowgen runs:
grep "submissionArgs" output/ttlbx_n2p/jem/flowgen/nbfeeder.nbtask
# Expected: submissionArgs --class SLES15&&32&&4
```

## Notes

### CRITICAL: RAM value must match a real NB class

The `RAM` value generates `--class SLES15&&{RAM}&&{CPU}`. Only specific values are valid in the `zsc16_express` queue — check `flows/grdlbuild/resources.ini` for valid classes. **Invalid example**: `RAM = 256` → generates `SLES15&&256&&4` → NO matching machines → all inner NB lib jobs silently fail with Exit Status 2 and `.done` files from a prior run are used, causing DVB to report them as "Failed" (stale).

Valid 4-core classes as of 2026-05 (from `flows/grdlbuild/resources.ini`):
`4G, 16G, 28G, 32G, 52G, 64G, 80G, 100G, 128G, 150G, 200G, 512G` — **256G does not exist**.

### Do NOT use [INCLUDES] to external site_config file

The `[INCLUDES]` approach pointing to `/nfs/site/disks/issp_ttl_emu_compile_001/site_config/compute.ttl.zsc16.SLES15.cth` works technically, but creates a dependency on a file outside the model. Keep the COMPUTE sections inline in `cfg/compute.cth` so the model is self-contained.

### DVB "Failed" with stale .done files is confusing

When inner NB jobs fail at submission (wrong class), DVB falls back to `.done` files from a prior local run (May 1 timestamps in the bug discovery session). DVB then reports those libs as "Failed" in the summary table even though their individual `analysis.log` files show "Exit Code: 0". This is a DVB make dependency artifact — the `.done` files are older than regenerated flowgen `Makefile` (May 8), so make considers them stale and re-runs the jobs, which then fail at NB submission.

### The site_config reference file

A validated reference with correct settings is kept at:
`/nfs/site/disks/issp_ttl_emu_compile_001/site_config/compute.ttl.zsc16.SLES15.cth`

Use it as reference if settings need to be updated, but copy the content inline into `cfg/compute.cth`.

### Affects all new TTLbx ZSE5 workareas

Every workarea cloned from the TTLbx seed has an empty `cfg/compute.cth`. This fix must be applied to each new workarea before the first `-nb` build. Consider committing it to the seed repo.

### LM_PROJECT must also be set

When launching grdlbuild with `-nb`, `LM_PROJECT` must be set correctly:
```bash
export LM_PROJECT=DDG-TTLPKG
```
The VSCode default shell sets an invalid project (`SC_HNGUY11_UNKN`). Always override before running grdlbuild.

### Follow-on issue: BUG-059

Populating `cfg/compute.cth` (this fix) resolves the "Compute section not found" fatal, but leaves `NB := 1` active in the PCD Makefile.cfg files. This causes a secondary failure where vlogan sub-jobs are dispatched via nbfeeder but silently "did not run" when running from a login node (no vp2ppm protocol). See **BUG-059** for the complete fix: clearing `NB :=` in the 3 `overrides/` Makefile.cfg files so DVB runs vlogan locally instead of via nbfeeder.

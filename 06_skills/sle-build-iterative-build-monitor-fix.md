---
name: sle-build-iterative-build-monitor-fix
description: "Iteratively launch, monitor, diagnose, fix, and relaunch grdlbuild emulation builds. USE WHEN: user asks to run a build end-to-end, launch and monitor a grdlbuild, kick off a build and fix errors, iterative build-fix cycle, automated build management, converged TTLbx parallel build management. Covers: setting WORKAREA, launching grdlbuild, phase-by-phase monitoring (emu_gen, genfilelist/dvJsonGenerator, VCS analysis, VCS elaboration), error detection, automated fix application, email reporting, rebuild decision-making. Converged TTLbx: shared-vs-per-target stage classification, per-target state tracking table, one-target-fails decision tree, fix impact table (full rebuild vs -id per target), parallel monitor deployment. VCS/FPGA builds: deploy fpga_vcs_build_monitor.sh for autonomous background monitoring that survives across conversation turns. ZeBu (ZSE5) builds: deploy monitor_build.sh for zCui orchestrator monitoring, compilation_status.log polling, synthesis Bundle failure diagnosis, zTopBuild force assign verification, driverClk analysis from zTime.log."
argument-hint: "Provide the WORKAREA path and the grdlbuild target (e.g., :ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs or :ttlbx_n2p:emu:sle:pkg_chpr_cfgr_p2e0_816_fast_zse). Optionally provide an email address for reports."
---

# Iterative Build-Monitor-Fix Workflow

## Overview
This skill automates the cycle of: launch build → monitor phases → detect failure → diagnose root cause → apply fix → email report → relaunch build. Repeat until build succeeds or a manual intervention is required.

## Step 0: Gather Required Inputs (MANDATORY)

**Before doing ANY build work**, you MUST ask the user for these three inputs. Use the `vscode_askQuestions` tool to collect all three at once:

1. **WORKAREA** (required): The absolute path to the build workspace.
   - Example: `/nfs/site/disks/issp_ttl_emu_compile_001/pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.fpga_vcs_enablement`
   - This will be used for `setenv WORKAREA` before every `grdlbuild` invocation.

2. **Build command** (required): The exact `grdlbuild` command to run.
   - Example: `grdlbuild :ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs -id`
   - Store this verbatim and reuse it for every relaunch. Do NOT modify or guess the command.

3. **Email address** (required — ask, but allow opt-out): The email address to send build reports to.
   - Example: `hoa.nguyen@intel.com`
   - If the user opts out, skip all email steps but still report results in the chat.

**Store these values in session memory** (e.g., `/memories/session/build_launch_command.md`) so they persist across conversation turns. Always read from session memory before launching or emailing — never guess or use stale values.

### Example askQuestions call:
```
vscode_askQuestions with questions:
  1. header: "WORKAREA", question: "What is the WORKAREA path for this build?"
  2. header: "Build Command", question: "What is the exact grdlbuild command to run?"
  3. header: "Email", question: "Email address for build reports? (type 'none' to opt out)"
```

### After collecting inputs:
- Confirm the values back to the user before proceeding
- Save to session memory immediately
- Use the WORKAREA and build command **exactly as provided** for all subsequent launches

## Workflow Steps

### Step 1: Launch Build

> ⚠️ **CRITICAL — Always validate WORKAREA and LM_PROJECT before launching**
>
> Two environment variables **must** be set explicitly before every `grdlbuild` invocation:
>
> **1. WORKAREA** — The `$WORKAREA` env var may have been set by a previous `cth_psetup` run in a **different directory**.
> A stale or wrong WORKAREA silently corrupts the build in two ways:
>   - grdlbuild submits NB jobs using the wrong path for resources.ini (`GRDLBUILD_COMPUTE_SETTINGS`), causing tasks to land in the wrong NB qslot.
>   - **MORE SERIOUS**: `gradle.properties` sets `outputDir=${WORKAREA}/output/grdlbuild`, so grdlbuild writes ALL output (logs, nbtasks, ZSE5 zcui.work) to the WRONG workarea's `output/` directory. This means the build compiles the wrong workarea's source files. The NB feeder name is derived from `pwd` (so `.1` appears in the feeder name and looks correct), but all actual build paths inside the nbtask point to `$WORKAREA`. This can go undetected for hours.
>
> **2. LM_PROJECT** — The VSCode/Copilot shell auto-constructs an invalid value (e.g., `SC_HNGUY11_UNKN`).
> Intel's `getLf` license fetcher rejects it, causing **all DVB NB subtasks (jem, vcssimmpp, cpp) to fail
> immediately** with `getLf: error: SC_HNGUY11_UNKN is not a valid LM_PROJECT`. Correct value: `DDG-TTLPKG`.
>
> ```bash
> # Validate: WORKAREA must exactly match your target workarea (including any .1, .2 suffix, etc.)
> echo "WORKAREA   : $WORKAREA"
> echo "PWD        : $(pwd)"
> echo "LM_PROJECT : $LM_PROJECT"   # must be DDG-TTLPKG, not SC_HNGUY11_UNKN or similar
> # If either is wrong, fix before proceeding
> ```
>
> **Never assume these are correct from a prior shell session.** Always set them explicitly.
>
> **Verify the build is writing to the correct workarea** (run ~60 seconds after launch):
> ```bash
> # nbtask files must appear under $WORKAREA/output/grdlbuild/nbtasks/
> ls $WORKAREA/output/grdlbuild/nbtasks/*.nbtask 2>/dev/null | head -3
> # If empty, $WORKAREA was wrong — find where nbtask went:
> find /nfs/site/disks/issp_ttl_emu_compile_001/ -maxdepth 4 -name "*.nbtask" -newer /tmp -user $USER 2>/dev/null
> ```

```bash
# Use bash (not tcsh) — preferred for all TTL builds
# ALWAYS set WORKAREA to the explicit absolute path — do NOT use $PWD
export WORKAREA=/nfs/site/disks/issp_ttl_emu_compile_001/<exact-workarea>  # e.g. pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1
export LM_PROJECT=DDG-TTLPKG   # REQUIRED for TTL builds — prevents getLf license failures
cd $WORKAREA/flows/grdlbuild
grdlbuild <TARGET> -nb
```
- `setenv WORKAREA` **MUST** be set before calling `grdlbuild` — the CTH wrapper uses it to set
  `GRDLBUILD_COMPUTE_SETTINGS=$WORKAREA/flows/grdlbuild/resources.ini`, which controls the NB
  pool/qslot for all grdlbuild task submissions. A wrong WORKAREA causes tasks to land in the
  wrong NB qslot (e.g., `/PCH/Client_System_Solution` instead of `/PCH/CSS/TTL/emu`).
- `setenv LM_PROJECT DDG-TTLPKG` **MUST** be set — without it all jem/vcssimmpp/cpp NB tasks fail on license checkout.
- Do **NOT** pass `--project-dir` or `-- make_args=...` — grdlbuild handles these internally via its recipe
- Use `-nb` for NB-submitted builds (ZSE5/FPGA); use `-id` to skip already-completed tasks
- Launch in a **background terminal** since builds run for hours
- Record the terminal ID and start timestamp for monitoring

**Concrete example (FPGA VCS):**
```bash
export WORKAREA=/nfs/site/disks/issp_ttl_emu_compile_001/pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.fpga_vcs_enablement
export LM_PROJECT=DDG-TTLPKG
cd $WORKAREA/flows/grdlbuild
grdlbuild ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs -nb -id
```

### Step 2: Monitor Build Phases
The build proceeds through these phases in order. Monitor each one:

#### Phase 1: emu_gen (Pre-compilation actions, ~2-5 min)
```bash
# Check action pass/fail counts
grep "action.*PASSED\|action.*FAILED" $OUTDIR/log/emu_gen.log

# Watch for failures
grep "FAILED" $OUTDIR/log/emu_gen.log
```
Where `OUTDIR` is:
- FPGA: `$WORKAREA/output/$DUT/emu/fpgasim_emuvcs/$MODEL/vcs/`
- ZSE:  `$WORKAREA/output/$DUT/emu/emuvcs_emuvcs/$MODEL/vcs/`

Typical actions: `rtlchanges_precheck`, `gen_dut_cfg`, `copy_rom_files`, `copy_pkg_upf_changes`, etc.

#### Phase 2: genfilelist / dvJsonGenerator (~3-10 min)
```bash
# Check timestamp log directory for gen_dv_flist
ls -lt $OUTDIR/log/<TIMESTAMP>/

# Read dvJsonGenerator log for fatal errors
tail -20 $OUTDIR/genfilelist_dv/log/dvJsonGenerator.log

# CRITICAL: Verify analysis_opts appears in the JSON
grep "analysis_opts" $OUTDIR/genfilelist_dv/dvb_sim_filelist.json
```
**Key check**: If `analysis_opts` is missing from the JSON, vlogan won't get the global opts file (e.g., `-sverilog`), causing mass analysis failures.

#### Phase 3: gen_analyze_make, dw_gen, spark_co (~1-3 min each)
```bash
# Check each sub-phase
tail -5 $OUTDIR/log/<TIMESTAMP>/gen_analyze_make.log
tail -5 $OUTDIR/log/<TIMESTAMP>/dw_gen.log
tail -5 $OUTDIR/log/<TIMESTAMP>/spark_co.log
```

#### Phase 3b: handle_dynamic_blackboxes (~5-15 min, log grows to ~4MB)
```bash
# This phase runs AFTER gen_analyze_make/dw_gen/spark_co but BEFORE analysis
ls -lt $OUTDIR/log/ | head -3  # handle_dynamic_blackboxes.log should be actively growing
wc -c $OUTDIR/log/handle_dynamic_blackboxes.log  # ~4MB when complete
```
No failures expected here — just wait for it to finish.

#### Phase 3c: pre_analyze (~1 min)
```bash
tail -5 $OUTDIR/log/pre_analyze.log
```

#### Phase 4: VCS Analysis (distributed compilation, ~15-60+ min)
```bash
# Count pass/fail from analysis summary
SUMLOG=$OUTDIR/log/<TIMESTAMP>/analyze_summary.log
grep -c "PASSED" $SUMLOG
grep -c "FAILED" $SUMLOG

# Check for active analysis
tail -5 $OUTDIR/log/<TIMESTAMP>/analyze.log

# If failures, get first error details
grep "FAILED" $SUMLOG | head -5
# Then read the specific .scrout file for the failing library
```

#### Phase 5: VCS Elaboration
```bash
# Check elaboration log
tail -30 $OUTDIR/log/<TIMESTAMP>/elab.log
grep "Error-" $OUTDIR/log/<TIMESTAMP>/elab.log | head -10
```

**CRITICAL — Batch all elab fixes in one iteration:** Elab takes 10-30+ minutes. Do NOT fix one error and relaunch. Instead, collect **all** elab errors, find all affected source files, apply all fixes, then relaunch once:
```bash
# Collect ALL unique error types
grep "Error-\[" $OUTDIR/log/<TIMESTAMP>/elab.log | sort -u | head -30
# For CFCILFBI specifically, list all missing cells
grep "Error-\[CFCILFBI\]" -A3 $OUTDIR/log/<TIMESTAMP>/elab.log | grep "Cell '"
```

### Step 2b: Deploy VCS Background Monitor Script (MANDATORY for FPGA VCS builds)

VCS builds run 45-90+ minutes. **Background terminal IDs expire between VS Code Copilot conversation turns**, so manual polling from background terminals DOES NOT WORK across turns. Instead, deploy a self-contained bash monitor script that:
1. Polls the task log every 60 seconds autonomously
2. Tracks analysis progress from `analyze_summary.log`
3. Detects build completion (pass or fail) from `Exit status:` in the task log
4. Sends summary email on **both success and failure** (failure emails include full error diagnosis)
5. Writes all status updates to `$WORKAREA/output/.fpga_vcs_build_monitor.out`
6. On elab failure, extracts ALL unique errors and CFCILFBI missing cells into the email

**The monitor script is at**: `$WORKAREA/src/val/fpga/scripts/fpga_vcs_build_monitor.sh`

**Deploy immediately after launching the build:**
```bash
nohup bash $WORKAREA/src/val/fpga/scripts/fpga_vcs_build_monitor.sh "$WORKAREA" "hoa.nguyen@intel.com" 60 > /dev/null 2>&1 & echo "Monitor PID: $!"
```

**CRITICAL — Active-wait pattern (Layer 2):** After deploying the background monitor, run a foreground blocking wait that keeps the agent conversation active until the build finishes:
```bash
bash -c 'SF="$WORKAREA/output/.fpga_vcs_build_monitor.out"; while true; do if grep -q "BUILD FAILED\|BUILD PASSED" "$SF" 2>/dev/null; then cat "$SF"; break; fi; sleep 60; done'
```
This command blocks until the monitor detects completion, then dumps the full status so the agent can immediately react (diagnose failure or report success). Run this in a **foreground** terminal with a generous timeout (e.g., 5400000ms = 90 min). **When this command returns, proceed IMMEDIATELY to Step 2c — do not stop or wait for user input.**

**Two-layer monitoring pattern:**
- **Layer 1 (background monitor script)**: Runs autonomously, survives conversation disconnects. Emails user on both success AND failure with full diagnosis. Logs timeline to `.fpga_vcs_build_monitor.out`.
- **Layer 2 (foreground active-wait)**: Blocks the agent's conversation turn until build completes. When it returns, the agent **immediately** reacts — no delay, no user prod needed.

**CRITICAL workflow rules:**
- Deploy **both layers** every time a build is launched
- Layer 1 (background) ensures the user gets an email even if the conversation disconnects
- Layer 2 (foreground) ensures the agent reacts immediately within the conversation — **the agent MUST execute Step 2c auto-fix loop when Layer 2 returns, without waiting for user input**
- **Do NOT** spawn background terminals for one-off status checks — they accumulate (60+ idle tcsh shells)
- The `.fpga_vcs_build_monitor.out` file is the **single source of truth** across all conversation turns
- Periodically report build progress to the user in the chat session

### Step 2c: Reacting to Build Completion (AUTO-FIX LOOP — MANDATORY)

The Layer 2 foreground active-wait returns when the build completes. **The agent MUST immediately react — do NOT wait for user input.** This is an autonomous loop.

**On `BUILD FAILED` — Execute this algorithm immediately and without pause:**

```
1. IDENTIFY failed phase from monitor output / task log
2. READ the phase-specific failure log (see dispatch table below)
3. DIAGNOSE root cause using known patterns (Step 3) + referenced skills
4. APPLY fix (Step 4) — all fixes in one pass for elab errors
5. SEND DETAILED EMAIL (Step 5) — with fix description, skills used, skills acquired
6. RELAUNCH build (Step 1) + redeploy both monitoring layers (Step 2b)
7. REPORT to user: what failed, what was fixed, build relaunched
8. GOTO: wait for Layer 2 again (repeat until pass or unresolvable)
```

**Phase-to-log dispatch table — use this to find the right log for each failure phase:**

| Failed Phase | Log to Read | Diagnosis Skill |
|---|---|---|
| `rtlchanges_precheck` | `$OUTDIR/log/emu_gen.log` (grep `rtlchanges_precheck`) | `sle-build-rtlchanges-refresh` |
| `analyze` | `$OUTDIR/log/<TIMESTAMP>/analyze_summary.log` → find FAILED libs → read their `.analyze.scrout` | (see Step 3 known patterns table) |
| `post_analyze` (rtlchanges_postcheck) | `$OUTDIR/log/rtlchanges_postcheck.log` | `sle-build-fpga-rtlchanges-postcheck-fix` |
| `elab` | `$OUTDIR/log/<TIMESTAMP>/elab.log` | `sle-build-fpga-elab-missing-cell-fix` (for CFCILFBI) |

**Concrete auto-fix commands for each failure type:**

#### post_analyze (rtlchanges_postcheck) failure:
```bash
# 1. Read the postcheck log to find ALL unused files
cat $OUTDIR/log/rtlchanges_postcheck.log | grep "ERROR: file is not used"
# 2. Determine if each file is truly optional:
#    a. Check if any CHANGES.cfg references it:
#       find $WORKAREA/src/val/emu/rtlchanges -name "*CHANGES*" -exec grep -l "<filename>" {} \;
#    b. If NO CHANGES.cfg references it → it's an ORPHAN from IP refresh
#       Add to rtlchanges_optional_ips.json with [] (empty = optional for ALL models)
#    c. If a CHANGES.cfg references it but the library isn't compiled for this model →
#       Add with ["^(?!.*fpga)"] for FPGA-only exclusion, or model-specific regex
# 3. Edit $WORKAREA/src/val/emu/scripts/rtlchanges_optional_ips.json
# 4. Relaunch build
```
Common orphan patterns after PCD/IP refresh: `*_emu_clocks.sv`, DLVR subip files, memory macro replacement files.

#### elab CFCILFBI (missing cell) failure:
```bash
# 1. Collect ALL unique missing cells
grep "Error-\[CFCILFBI\]" -A3 $OUTDIR/log/<TIMESTAMP>/elab.log | grep "Cell '" | sort -u
# 2. For each missing cell, trace to source file and add FPGA guard
#    Consult sle-build-fpga-elab-missing-cell-fix skill for batch-fix approach
# 3. Check RZL reference workspace for matching FPGA guard pattern
# 4. Apply ALL guards in one edit pass, then relaunch
```

#### analyze failure:
```bash
# 1. Find all FAILED libraries
grep "FAILED" $OUTDIR/log/<TIMESTAMP>/analyze_summary.log
# 2. Read the .analyze.scrout for first FAILED lib
cat $OUTDIR/log/<TIMESTAMP>/<lib>.analyze.scrout | grep "Error-" | head -20
# 3. Match against known patterns table (Step 3)
# 4. Apply fix, relaunch
```

**CRITICAL RULES for the auto-fix loop:**
- **Never stop after detecting failure.** Always attempt diagnosis and fix.
- **Never wait for user confirmation on Low-risk fixes.** Apply and relaunch immediately.
- **Batch elab fixes.** Collect ALL elab errors before fixing any. Don't fix-one-relaunch-repeat.
- **Reference companion skills.** Load and follow the referenced skill (e.g., `sle-build-fpga-elab-missing-cell-fix`) for detailed fix procedures.
- **If fix is unclear or High-risk**, report findings to user and ask — but still provide a proposed fix.
- **After relaunching**, re-enter the Layer 2 active-wait. The loop continues until BUILD PASSED or an unresolvable error.

**MANDATORY — Send Agent Email After Every Fix (Step 5 in the algorithm above):**

The Layer 1 monitor script sends a basic failure notification email. The **agent** must ALSO send a **separate, detailed email** after applying fixes and relaunching. This agent email uses the template from Step 5 and MUST include:
1. **FAILURE DETAILS**: The exact error(s) and which phase failed
2. **ROOT CAUSE**: What went wrong and why
3. **FIX APPLIED**: Exactly what was changed (file paths, before/after)
4. **SKILLS APPLIED THIS ITERATION**: List every skill consulted (by name) with a one-line description of how it helped
5. **NEW SKILLS ACQUIRED THIS ITERATION**: Any new patterns learned that should become skills
6. **BUILD N+1 status**: Whether the next build was relaunched, and its risk level

Send this email using:
```tcsh
printf "FPGA VCS Build Report - ...\n\nFIX APPLIED:\n  ...\n\nSKILLS APPLIED:\n  - ...\n" > /tmp/build_report_bN.txt
cat /tmp/build_report_bN.txt | /bin/mail -s "[Build Report] Build N FAILED - Fix Applied, Build N+1 Relaunched" <email>
```

**On `BUILD PASSED`:**
1. Report success to user in chat with build duration
2. Email is already sent by Layer 1 monitor script

### Step 3: Detect and Diagnose Errors

#### Error Detection Strategy
1. Check `$WORKAREA/.grdlbuild_logs/grdlbuild.log` for `failed and exit` lines
2. Identify which phase failed from the log timestamps
3. Read the phase-specific log for error details
4. Cross-reference with known error patterns (see below)

#### Known Error Patterns and Fixes

| Error Pattern | Root Cause | Fix | Risk |
|---|---|---|---|
| `getLf: error: SC_HNGUY11_UNKN is not a valid LM_PROJECT` | VSCode/Copilot shell auto-sets invalid `LM_PROJECT` fallback | Always `export LM_PROJECT=DDG-TTLPKG` before grdlbuild | Low |
| DVB jem/vcssimmpp/cpp: libs show "Failed" but `.done` files exist from earlier date | getLf failure reset `.done` timestamps to today — DVB treats today's timestamp as "Failed" | `find output/ttlbx_n2p/jem/lib/ -name "*.done" -newer "$REF" -exec touch -r "$REF" {} \;` (see build_flow.md .done recovery procedure) | Low |
| DVB cpp: libs show "Failed", no `.done` file present at all | cpp compiled successfully but crashed before writing `.done` marker | `touch -r output/ttlbx_n2p/cpp/lib/<lib>/analysis.log output/ttlbx_n2p/cpp/lib/<lib>/.<lib>.done` | Low |
| DVB jem/vcssimmpp/cpp: all NB sub-tasks fail immediately at license checkout | `cfg/compute.cth` is empty — DVB can't find compute resource for @zsc16 | Populate `cfg/compute.cth` with 4 COMPUTE sections (see environment.md cfg/compute.cth section) | Low |
| `File does not exist` in dvJsonGenerator `-F-` | Stale path in global opts file (e.g., RZL path in TTL workspace) | Update path in `global_fpgasim_vlog_opts.f` to match ZSE equivalent | Low |
| Mass `Error-[SVS]` / `Error-[SVSTS]` in vlogan | Missing `-sverilog` flag | Ensure `analysis_opts` symlinks exist in `verif/emu/emuvcs/` (flow dir) | Low |
| `analysis_opts` missing from JSON | Symlinks missing in `verif/emu/<FLOW_NAME>/` directory | Create symlinks: `global_fpga*.f → ../rtl_cfg/global_fpga*.f` | Low |
| rtlchanges_precheck failure | Stale .ref files or missing HSDs.toml entries | Refresh .ref files, add HSDs.toml entries | Low |
| `Error-[IPD]` identifier previously declared | Double-include via FPGA ifdef guards: both `ifndef FPGA_X` (includes `pcd_xtors.v`) and `ifndef FPGA_Y` (standalone TAP/SPI) fire in non-FPGA builds | Wrap standalone includes in `ifdef FPGA_X` so they only fire when `pcd_xtors.v` was skipped | Low |
| `Error-[URMI]` undefined module | Library excluded by mistake or rtlchange missing | Check `fpga_remove_libs` and rtlchange files | Medium |
| `Error-[CSINFI]` include not found | Missing include path or guarded by missing define | Add `+incdir+` to change_cfg or model opts; or check if a `+define+` needed to skip the include is missing | Medium |
| `Error-[MDNOL]` MPD — multiply defined module | FPGA replacement file compiled via `prepend: file:` AND IP's original via `+incdir+` include | Add `ifndef` include guard to FPGA replacement file | Low |
| `Error-[SE]` syntax error `parameter int` in prepended files | `rtl_configs_lib` libraries don't use `global_*_vlog_opts.f`, so no `-sverilog` | Add `-sverilog` to `prepend: vlog_opts:` in FPGA_CHANGES.cfg second `.*:` section | Low |
| `Error-[IWNMEE]` unbalanced ifdef/endif | IP source has more ifdef/ifndef than endif, hidden by ZSE's extra defines | Compare ZSE vs FPGA defines (grep for key defines in `.analyze.scrout`), add missing `+define+` to FPGA_CHANGES.cfg for the affected library | Low |
| Undefined macro (`nap_cdie1_link0_top` etc.) | IP's hier_defines only covers cdie0 but code references cdie1 unconditionally | Add missing defines to `fpga_missing_hier_defines.sv` prepended to the affected library | Low |

### Step 4: Apply Fix
1. **Low risk fixes** (path corrections, symlink creation, config edits): Apply automatically and relaunch
2. **Medium risk fixes** (rtlchange modifications, library exclusions): Apply but ask user before relaunching
3. **High risk fixes** (model config changes, architectural changes): Report to user and wait for approval

After applying a fix, relaunch the build (Step 1) and redeploy the monitor (Step 2b). Report the fix to the user in chat.

### Step 5: Email Reports (Automated by Monitor Script)
The monitor script now sends email on **both** success and failure:
- **On failure**: Email includes all elab errors (unique), CFCILFBI missing cells, and error context. This ensures the user is notified even if the agent conversation is disconnected.
- **On success**: Email includes full build report with phase results and analysis counts.

The agent's role is to react via the Layer 2 active-wait and fix failures automatically. The email serves as a backup notification.

#### Email Template
```
FPGA VCS Build Report - <DATE>
====================================

BUILD TARGET: <target>
WORKSPACE:    <workspace>

BUILD N RESULT: FAILED / PASSED
=====================
  Started:  <time>
  Failed:   <time>
  Phase:    <phase name>
  Duration: <duration>

FAILURE DETAILS:
  <error description>

ROOT CAUSE:
  <analysis>

FIX APPLIED:
  <fix description>

SKILLS APPLIED THIS ITERATION:
  - <skill-name>: <one-line description of how it was used>
  - (none if no existing skills were consulted)

NEW SKILLS ACQUIRED THIS ITERATION:
  - <skill-name>: <one-line summary of the new pattern learned>
  - (none if no new skills were created)

BUILD N+1: RELAUNCHED / WAITING FOR APPROVAL
  Started: <time>
  Risk: <Low/Medium/High>

-- Copilot Build Agent
```

#### Sending the Email
```tcsh
cat /tmp/build_report.txt | /bin/mail -s "[Build Report] <subject>" <email> && echo "MAIL_SENT_OK"
```
**Note**: In tcsh, heredocs (`<<`) don't work. Write email body to a temp file first, then pipe to `/bin/mail`.

### Step 6: Relaunch Build

> ⚠️ **CRITICAL — Set WORKAREA explicitly before every relaunch. Do NOT rely on the inherited env var.**
> See the WORKAREA warning in Step 1. This applies equally to relaunches.

```bash
# BASH (preferred for TTL builds):
export WORKAREA=/exact/path/to/workarea   # e.g. .../pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1
export LM_PROJECT=DDG-TTLPKG
cd $WORKAREA/flows/grdlbuild
grdlbuild <TARGET> -nb -id
```

Or in tcsh:
```tcsh
setenv WORKAREA /nfs/site/disks/issp_ttl_emu_compile_001/<exact-workarea>
setenv LM_PROJECT DDG-TTLPKG
cd $WORKAREA/flows/grdlbuild
grdlbuild <TARGET> -nb -id
```

**TTL target syntax** (no leading colon, `-nb` required):
```bash
# ZSE5 p2e4 fast model (ttlbx) — relaunch after failure
grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse -nb -id

# ZSE5 cfgr model (ttlbx) — relaunch after failure
grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_cfgr_p2e0_816_fast_zse -nb -id

# FPGA slimsim model (ttlbx) — relaunch after failure
grdlbuild ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs -nb -id
```

**`-id` (ignore-deps) flag rules for TTL builds:**
- **USE `-id`** whenever any upstream NB/DVB tasks have already completed (jem, vcssimmpp, cpp, analyze, fe_be, or any combination) — `-id` tells Gradle to skip those tasks and start from the first incomplete one
- **USE `-id`** after applying a fix to a stage that failed, when all prior stages passed
- **NEVER use `-id`** on the very first build — no completed tasks exist yet
- **NEVER use `-id`** after changing RTL source files, `tool.cth`, `cfg/compute.cth`, or filelists that affect upstream stages — those upstream stages must re-run

**`-nb` flag**: ALWAYS include `-nb` for TTL builds. It submits DVB sub-tasks (jem, vcssimmpp, cpp, ZSE5 elab) to the NB queue. Omitting it causes those tasks to run on the login node (not allowed).

**IMPORTANT**: Do NOT pass `--project-dir` or `-- make_args=...` — grdlbuild handles these internally via its recipe.

After relaunching, verify the build is writing to the correct workarea (nbtask files appear under `$WORKAREA/output/grdlbuild/nbtasks/`) — see Step 1 verification.

### Step 7: Repeat
Continue monitoring from Step 2 until:
- Build succeeds (all phases pass)
- A non-automatable error is encountered
- User requests to stop

---

## Converged TTLbx Build: Parallel Target Management

When running the converged TTLbx build (`grdlbuild ... -nb` with all 3 targets), grdlbuild runs all 3 targets in a single Gradle invocation. Early stages are shared; later stages run in parallel. This section defines how to track, triage, and fix failures across parallel targets without conflating logs.

### Stage Classification: Shared vs. Per-Target

Understanding which stages are shared is critical — a fix that touches a shared-stage input requires a **full rebuild of all 3 targets**, not just the failed one.

| Stage | Shared / Per-Target | Notes |
|-------|---------------------|-------|
| `spark_co`, `override_vcs_home` | **Shared** | Environment setup — any fix here affects all targets |
| `gen_dv_flist` | **Shared** | Filelists — changing filelist sources invalidates all analyze stages |
| `c_compile`, `dw_gen`, `gen_analyze_make` | **Shared** | C model, DW libs — changing `tool.cth` invalidates all |
| `zse_lint`, `pre_analyze`, `gen_elab_src` | **Shared** | Pre-elab setup |
| `analyze` | **Per-Target** | Each target has its own VCS analyze run and output dir |
| `fe_be` | **Per-Target** | Each ZSE5 target has its own DVB/ZeBu synthesis; FPGA has its own VCS elab |
| `zebu_tb`, `emu_gen` | **Per-Target** | Final ZeBu/FPGA steps per target |

> **Key rule**: If a fix modifies RTL source files, `tool.cth`, `cfg/compute.cth`, or filelists → those are shared-stage inputs → **abort all 3 targets and do a full rebuild** (no `-id`). If a fix only modifies a target-specific build config (e.g., `sle_dut.utf`, a ZSE5-only rtlchange) → relaunch only that target with `-id`.

### Per-Target State Tracking

Maintain this table in your session during a converged build. Update it as each target progresses:

| Target | Type | Current Stage | Status | Notes |
|--------|------|--------------|--------|-------|
| `pkg_chpr_p2e4_816_fast` | ZSE5 | — | 🟡 Running | |
| `pkg_chpr_cfgr_p2e0_816_fast` | ZSE5 | — | 🟡 Running | |
| `pkg_chpr_cfgr_p2e0_816_fast` | FPGA | — | 🟡 Running | |

Status legend: 🟡 Running · ✅ Passed · ❌ Failed · ⏸ Waiting (fix in progress) · 🔁 Relaunching

**Output paths per target** (from `$WORKAREA/flows/grdlbuild/`):
```bash
ZSE5_P2E4="$WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/pkg_chpr_p2e4_816_fast/zse5"
ZSE5_CFGR="$WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/pkg_chpr_cfgr_p2e0_816_fast/zse5"
FPGA_CFGR="$WORKAREA/output/ttlbx_n2p/emu/fpgasim_emuvcs/pkg_chpr_cfgr_p2e0_816_fast_fpga_slimsim/vcs"
```

### Status Snapshot Command (run periodically during monitoring)

```bash
cd $WORKAREA/flows/grdlbuild

echo "=== grdlbuild overall ==="
grep -E "started|finished|FAILED" grdlbuild.log | tail -10

echo "=== ZSE5 p2e4 — zCui ==="
grep -E "stage|Bundle|FAILED|PASSED|Compilation Ended" $ZSE5_P2E4/zcui.work/zCui.log 2>/dev/null | tail -5

echo "=== ZSE5 cfgr — zCui ==="
grep -E "stage|Bundle|FAILED|PASSED|Compilation Ended" $ZSE5_CFGR/zcui.work/zCui.log 2>/dev/null | tail -5

echo "=== FPGA cfgr — elab ==="
tail -5 $FPGA_CFGR/log/*/elab.log 2>/dev/null || echo "(elab not yet started)"

echo "=== driverClk snapshot ==="
grep -E "driverClk|kHz" $ZSE5_P2E4/zcui.work/zebu.work/zTime.log 2>/dev/null | head -3
grep -E "driverClk|kHz" $ZSE5_CFGR/zcui.work/zebu.work/zTime.log 2>/dev/null | head -3
```

### Decision Tree: One Target Fails, Others Running

```
One target fails during converged build
│
├── Is the failure in a SHARED stage (analyze or earlier)?
│   ├── YES → Fix affects all targets
│   │         1. Document the failing target
│   │         2. DO NOT cancel other in-flight targets (let them finish)
│   │         3. Apply fix to shared source
│   │         4. After all targets finish (pass or fail), FULL rebuild (no -id):
│   │            grdlbuild <all 3 targets> -nb
│   │
│   └── NO → Failure is in a PER-TARGET stage (fe_be, synthesis, FPGA elab)
│             1. Continue monitoring other in-flight targets normally
│             2. Debug and fix the failed target independently
│             3. Relaunch ONLY the failed target with -id:
│                grdlbuild <failed-target-only> -nb -id
│             4. DO NOT relaunch the other targets (they're still running or passed)
│
└── Did the same error appear on multiple targets?
    ├── YES → Likely a shared-stage or common RTL issue
    │         Fix once, full rebuild (no -id)
    └── NO  → Independent per-target issues
              Fix and relaunch each independently with -id
```

### Per-Target Relaunch Commands

When relaunching a single failed target (per-target failure — use `-id`):
```bash
export WORKAREA=/nfs/site/disks/issp_ttl_emu_compile_001/<workarea>
export LM_PROJECT=DDG-TTLPKG
cd $WORKAREA/flows/grdlbuild

# Relaunch ZSE5 p2e4 only
grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse -nb -id

# Relaunch ZSE5 cfgr only
grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_cfgr_p2e0_816_fast_zse -nb -id

# Relaunch FPGA only
grdlbuild ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs -nb -id
```

When a fix touches shared stages (full rebuild — NO `-id`):
```bash
# Full converged rebuild — all 3 targets from scratch
grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse ttlbx_n2p:emu:sle:pkg_chpr_cfgr_p2e0_816_fast_zse ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs -nb
```

### Fix Impact Classification (Quick Reference)

| What changed | Stage scope | Action |
|-------------|-------------|--------|
| RTL source file (`.sv`, `.v`) | Shared (analyze) | Full rebuild — all 3 targets |
| `tool.cth`, `cfg/compute.cth` | Shared | Full rebuild — all 3 targets |
| Filelist (`.f`, `.list.mako`) | Shared | Full rebuild — all 3 targets |
| ZeBu UTF config (`sle_dut.utf`) | Per-target (ZSE5 only) | Relaunch ZSE5 targets only with `-id` |
| ZSE5 rtlchange (ZeBu-specific) | Per-target (ZSE5 only) | Relaunch affected ZSE5 target with `-id` |
| FPGA rtlchange (VCS-only) | Per-target (FPGA only) | Relaunch FPGA target with `-id` |
| Common rtlchange (all targets) | All targets | Relaunch all 3 with `-id` separately, OR full rebuild |
| `sle_workarounds.py` | All targets | Relaunch all 3 with `-id` separately |

### Monitor Deployment for Converged Builds

For ZSE5 targets, deploy one `monitor_build.sh` instance **per ZSE5 target** — they use different BUILD paths and log files, so they run independently without interference. The FPGA target uses `fpga_vcs_build_monitor.sh` separately.

```bash
# Deploy ZSE5 p2e4 monitor
cp /tmp/monitor_template.sh /tmp/monitor_${WS}_p2e4.sh
# Edit: MODEL=pkg_chpr_p2e4_816_fast, BUILD=$WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/pkg_chpr_p2e4_816_fast
nohup bash /tmp/monitor_${WS}_p2e4.sh > /dev/null 2>&1 &

# Deploy ZSE5 cfgr monitor
cp /tmp/monitor_template.sh /tmp/monitor_${WS}_cfgr.sh
# Edit: MODEL=pkg_chpr_cfgr_p2e0_816_fast, BUILD=$WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/pkg_chpr_cfgr_p2e0_816_fast
nohup bash /tmp/monitor_${WS}_cfgr.sh > /dev/null 2>&1 &

# FPGA monitor (uses its own script and output file)
nohup bash $WORKAREA/src/val/fpga/scripts/fpga_vcs_build_monitor.sh "$WORKAREA" "hoa.nguyen@intel.com" 60 > /dev/null 2>&1 &
```

> ⚠️ Each monitor is hardcoded to its own BUILD path — they do NOT interfere. Email subjects include both WORKAREA stem and MODEL so you can identify which build sent an alert.

## Monitoring Tips

### NFS Stall Workarounds
- `tail` and `cat file | tail` can both stall on NFS during active writes
- If a command stalls, open a **new terminal** and retry
- Use `wc -l` to check if a log is still growing (compare counts 10-15 seconds apart)
- Check process tree: `ps -u $USER -f | grep "grdlbuild\|make\|vlogan\|vcs"` to verify build is alive

### Terminal Monitoring Best Practices
- **Two-layer monitoring for ALL builds**: Deploy background monitor script (Layer 1: email alerts, autonomous logging) + periodic foreground check of monitor output file (Layer 2: on-demand status).
  - **VCS/FPGA builds**: Use `fpga_vcs_build_monitor.sh` → writes to `$WORKAREA/output/.fpga_vcs_build_monitor.out`
  - **ZeBu builds**: Use `monitor_build.sh` → writes to `$BUILD/zse5/monitor_build.out`
- **Preferred VCS status check command** (single foreground command):
  ```bash
  cat $WORKAREA/output/.fpga_vcs_build_monitor.out
  ```
- **Preferred ZeBu status check command** (single foreground command):
  ```bash
  ps -p <MONITOR_PID> -o pid,etime,args | head -3 ; echo "---" ; cat $BUILD/zse5/monitor_build.out
  ```
- **Do NOT spawn background terminals for one-off status checks** — they accumulate (60+ idle tcsh shells) and clutter the user's terminal list. Use a single foreground command instead.
- **Background terminal IDs expire between conversation turns** in VS Code Copilot. Do NOT rely on `sleep N; check_status` in background terminals for monitoring across turns.
- For cross-turn monitoring, the background `monitor_build.sh` script handles persistence — its `monitor_build.out` file is the single source of truth across all turns.
- The tcsh shell does NOT support heredocs (`<<`). Use `printf` or `echo` piped to files instead.
- Use `|& cat` instead of `2>&1` for stderr redirection in tcsh.
- Use `|& head -N` instead of `2>/dev/null | head -N` for suppressing errors in tcsh.

### Log Monitoring: Use `read_file` Tool (NOT Terminal Commands)

**CRITICAL**: When checking build progress, ALWAYS use the `read_file` tool to read log files directly. Do NOT use terminal commands (`cat`, `tail`, `grep`) for log monitoring.

**Why**: NFS-mounted log files frequently cause terminal commands to stall/hang indefinitely during active writes. The `read_file` tool bypasses this issue and returns content reliably.

**Pattern for monitoring:**
```
# WRONG — terminal can stall on NFS:
run_in_terminal: cat $BUILD/zse5/zcui.work/compilation_status.log

# CORRECT — use read_file tool directly:
read_file(filePath="$BUILD/zse5/zcui.work/compilation_status.log", startLine=1, endLine=100)
```

**Exception**: For files > 50MB (e.g., `vcs_splitter_VCS_Task_Builder.log`), `read_file` will fail with "Files above 50MB cannot be synchronized". Only in this case, fall back to terminal with targeted `grep` (not open-ended `cat`/`tail`):
```bash
grep -c 'Error-' $BUILD/zse5/zcui.work/zCui/log/vcs_splitter_VCS_Task_Builder.log
```

**Log files to monitor with `read_file`:**
| Log | When to Check | What to Look For |
|-----|--------------|------------------|
| Gradle task log (`output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log`) | Pre-zCui | PASSED/FAILED for each stage, Exit status |
| `compilation_status.log` | During zCui | Which subtask is Running, how many Waiting/Finished |
| `zCui.log` | During zCui | Task terminations (normal/abnormal), phase transitions |
| `monitor_build.out` | Anytime | Timestamped build history (single source of truth) |
| `zTopBuild.log` | After zTopBuild | HFA001 warnings, FASTCLOCK detection |
| `zTime.log` | After zTime | driverClk speed |

### Timing Expectations
| Phase | Typical Duration |
|---|---|
| emu_gen (all actions) | 2-5 minutes |
| genfilelist/dvJsonGenerator | 3-10 minutes |
| gen_analyze_make + dw_gen | 1-3 minutes |
| handle_dynamic_blackboxes | 5-15 minutes |
| VCS analysis (distributed) | 15-60+ minutes |
| VCS elaboration | 10-30+ minutes |
| Total (emu_gen through analysis complete) | ~45-90 minutes |

### Process Health Check
```bash
# Verify build processes are running
ps -u $USER -f | grep "<workspace_basename>" | grep -v grep

# Check for orphaned processes after a kill
ps -u $USER -f | grep "gradle_exec_wrap\|fpga.*slimsim\|make.*MODEL" | grep -v grep
```

## Key Insight: Symlink Resolution Directory

When enabling a new build target type (e.g., FPGA VCS), symlinks for global opts files must exist in **both**:
1. `verif/emu/<BUILD_TYPE_DIR>/` (e.g., `fpgasim/`) — for some tools
2. `verif/emu/<FLOW_NAME>/` (e.g., `emuvcs/`) — **critical** for dvJsonGenerator resolution

The flow name directory is where dvJsonGenerator actually resolves `analysis_opts` and `elab_opts` file paths. Missing symlinks here cause the opts to silently disappear from the generated JSON.

## Key Insight: FPGA_CHANGES.cfg Two-Section Pattern

The FPGA_CHANGES.cfg file can have **multiple `.*:` (wildcard) sections**. Later sections override earlier ones. This is essential knowledge:

1. **First `.*:` section** (early in file): Contains global `add:` entries — files, vlog_opts, and defines that apply to ALL libraries.
2. **Second `.*:` section** (later in file): Contains `remove: file:` and `prepend: file:` entries specific to emu_clk replacement. The `remove:` entries strip IP-specific emu_clk files; the `prepend:` entries add FPGA replacement files.

**Critical**: The second `.*:` section's `prepend: vlog_opts:` must include `-sverilog` because `rtl_configs_lib` libraries do NOT use the global analysis opts file. Without it, prepended SystemVerilog files (like `emu_fast_clk.sv`) fail with syntax errors.

**Critical**: The first `prepend: file:` in the second `.*:` section should be a guard-defines file (e.g., `fpga_emu_clk_guards.sv`) that uses `ifndef`-guarded defines. This ensures defines like `FPGA_JER_TEAM_NVL_CDIE_VPS` are available even in libraries that don't use global opts.

**Order matters**: VCS preprocessor defines are global across a compilation session. Once `fpga_emu_clk_guards.sv` defines `FPGA_JER_TEAM_NVL_CDIE_VPS` via `ifndef`, subsequent libraries that already received the `+define+` from global opts won't redefine it.

## Key Insight: Cross-Reference ZSE vs FPGA Defines for Diagnosis

When an FPGA build fails but the ZSE build passes for the same library:
1. Check the ZSE `.analyze.scrout` for `+define+` flags not present in the FPGA build
2. Common pattern: ZSE defines `+define+HUB_URI_DISABLE=1` which skips broken code; FPGA build lacks this define
3. Fix: Add the missing define to the FPGA build's FPGA_CHANGES.cfg for the specific library
```bash
# Compare defines between ZSE and FPGA for a specific library
grep '+define+' $ZSE_LOGDIR/<lib>.analyze.scrout | sort > /tmp/zse_defines.txt
grep '+define+' $FPGA_LOGDIR/<lib>.analyze.scrout | sort > /tmp/fpga_defines.txt
diff /tmp/zse_defines.txt /tmp/fpga_defines.txt
```

## Session Notes Template
After Step 0, create a session memory note at `/memories/session/build_launch_command.md`:
```markdown
# Build Launch Configuration

## WORKAREA
<exact path from user>

## Build Command
<exact command from user>

## Email
- **Send to**: <email from user, or "OPTED OUT">

## Build History
- Build N: <timestamp> - <result>
- Build N+1: <timestamp> - <result>
```

**CRITICAL**: Before every `grdlbuild` launch and every email send, re-read this session memory file to get the correct values. Never rely on conversation context alone — it can be lost across turns.

---

## ZeBu (ZSE5) Build: Iterative Monitoring and Fix Workflow

ZeBu builds use a different orchestrator (**zCui**) than VCS builds. After grdlbuild completes the initial setup, zCui runs the full ZeBu compilation. This section covers the ZeBu-specific monitoring and fix workflow.

### Identifying a ZeBu Build
- grdlbuild target contains `_zse` suffix: e.g., `:ttlbx_n2p:emu:sle:pkg_chpr_cfgr_p2e0_816_fast_zse`
- Output goes to `$WORKAREA/output/$DUT/emu/zebu_zebu/$MODEL/` (NOT `emuvcs_emuvcs` or `fpgasim_emuvcs`)
- The zCui work directory is: `$BUILD/zse5/zcui.work/`

### ZeBu Step 1: Launch Build
Same as VCS — grdlbuild handles the launch. Always use bash and set WORKAREA explicitly:
```bash
# ALWAYS set WORKAREA explicitly — do NOT rely on inherited env var or setenv WORKAREA $PWD
export WORKAREA=/nfs/site/disks/issp_ttl_emu_compile_001/<exact-workarea-name>  # include .1/.2 suffix
export LM_PROJECT=DDG-TTLPKG
cd $WORKAREA/flows/grdlbuild
grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse -nb -id
```
Launch in a background terminal. grdlbuild will set up the environment and invoke zCui.

> ⚠️ **CRITICAL — Use the exact WORKAREA path, not a variable like `$PWD`.**
> After any `cd` operation, `$PWD` changes. Setting `export WORKAREA=$PWD` is only safe if done immediately after `cd $WORKAREA/flows/grdlbuild` — but this is fragile. Always set WORKAREA to the explicit absolute path of the target workarea (e.g., `.../pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1`).
> Also: TTL grdlbuild targets do NOT use a leading colon. Use `ttlbx_n2p:emu:sle:...` NOT `:ttlbx_n2p:emu:sle:...`.
> Also: `-nb` is ALWAYS required for TTL ZSE5 builds — do not omit it.

**IMPORTANT — Pre-zCui `cp: File exists` failure with `-id`:**
When using `-id` (incremental), grdlbuild runs `make cleanall flowgen` which deletes the `zse5/` target directory then recreates it. However, DVB's `Makefile.common` prerequisite target uses `\cp -Hrf` (no force flag) to copy build config files into `zse5/user_inputs/`. If a previous failed or interrupted build left stale files in `user_inputs/`, the `\cp` fails:
```
cp: cannot create regular file '.../zse5/user_inputs/Makefile': File exists
make: *** [.../Makefile.common:36: .../zse5/.shadow/prerequisite] Error 1
Exit status: 2
```
**Fix**: Manually remove the stale `zse5/` directory (or just `zse5/user_inputs/`) before relaunching:
```bash
rm -rf $BUILD/zse5
```
Then relaunch with the same `-id` command. The `.nfs*` busy-file errors from `rm -rf` are harmless (NFS lock files from old processes).

### ZeBu Step 2: Monitor Build Phases

ZeBu builds are **much longer** than VCS builds (12-24+ hours end-to-end). Deploy a background monitor script for automated polling.

> ⚠️ **CRITICAL — Use WORKAREA-specific log paths. Never read the shared NB feeder log alone.**
>
> The NB feeder log (`/tmp/gradle.nbflow.hnguy11/logs/nbfeeder.*.log`) is **shared across ALL builds** run by the user on the same day, including builds from other workareas. It accumulates task IDs from every grdlbuild invocation. Reading it without filtering by workarea path produces incorrect status (tasks from the wrong workarea appear as if they belong to the current build).
>
> **Primary monitoring sources — always use `$WORKAREA`-prefixed paths:**
> | Phase | Correct Log |
> |-------|------------|
> | Pre-zCui stages | `$WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log` |
> | zCui overview | `$BUILD/zse5/zcui.work/compilation_status.log` |
> | zCui task transitions | `$BUILD/zse5/zcui.work/zCui/log/zCui.log` |
> | ZSE5 started? | `ls $BUILD/zse5/zcui.work/` (directory exists only after emu_gen creates it) |
>
> `$BUILD = $WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/$MODEL` — all paths use the **exact `$WORKAREA`** including any `.1`, `.2` suffix.
>
> If you must check the feeder log, always filter on the exact workarea path to exclude other builds:
> ```bash
> grep "pkg_chpr_p2e4_816_fast" /tmp/gradle.nbflow.hnguy11/logs/nbfeeder.*.log | grep "$WORKAREA"
> # Entries without $WORKAREA in the task file path = DIFFERENT build — ignore them
> ```

#### Quick Status Check (use `read_file` tool)
```
read_file(filePath="$BUILD/zse5/zcui.work/compilation_status.log", startLine=1, endLine=100)
```
This shows at-a-glance: `[Running - N task(s)]`, `[Waiting - N task(s)]`, `[Finished - N task(s)]`.

**IMPORTANT — Checking zCui Subtasks:** The `compilation_status.log` file lists each individual subtask by name under its status category. Use this to identify WHICH specific task is currently running:
```
[Running - 1 task(s)]
VCS_Task_Builder
[Waiting - 21 task(s)]
design_Default_RTL_GroupBundle_0_Synthesis
design_Default_RTL_GroupBundle_1_Synthesis
...
[Finished - 5 task(s)]
Target_Config
design_Fs_Macro
...
```

**After identifying the running subtask**, check its specific log for progress:

| Running Subtask | Log to Check | How to Monitor |
|----------------|--------------|----------------|
| `VCS_Task_Builder` | `zCui/log/vcs_splitter_VCS_Task_Builder.log` | >50MB — use terminal `grep -c 'Error-'` and `ls -la` for size/freshness |
| `design_Default_RTL_GroupBundle_NNN_Synthesis` | `zCui/log/design_Default_RTL_GroupBundle_NNN_Synthesis.log` | `read_file` last 50 lines for progress |
| `zTopBuild` | `zebu.work/zTopBuild.log` | `read_file` — check for HFA001, FASTCLOCK_GENERIC |
| `zPar` | `zebu.work/zPar.log` | `read_file` last 100 lines for progress |
| `zTime` | `zebu.work/zTime.log` | `read_file` — look for driverClk speed |
| `Design_FPGA_Dispatch` | (multiple backend logs) | Check `zCui.log` for spawned/PASSED/FAILED counts |
| `zTimeFpga` | `backend_default/zTime_fpga.log` | `read_file` — final driverClk speed |

**Also check `zCui.log` for phase transitions:**
```
read_file(filePath="$BUILD/zse5/zcui.work/zCui/log/zCui.log", startLine=<last_50_lines>, endLine=<end>)
```
Look for `"normal task termination"` (success) or `"abnormal task termination"` (failure) entries to see which tasks have completed.

#### Phase-by-Phase Monitoring

**Pre-zCui Stages (grdlbuild task log)**

Before zCui starts, grdlbuild runs three `make` phases sequentially. These are logged in the gradle task log (`$WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log`), NOT in zCui.log. Monitor them with:
```bash
cat $WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log | grep "Target:\|PASSED\|FAILED\|Executing\|#####\|Exit"
```

The stages run in this order (total ~30-60 min before zCui starts):
1. **`cleanall flowgen`** (~5-10 min): `prerequisite` → `spark_co` → `emu_gen`
   - `prerequisite`: Creates output-dir, copies user_inputs. Can fail with `cp: File exists` — see Step 1 warning.
   - `emu_gen`: RTL generation via buildit.py (rtlchanges_precheck, gen_dut_cfg, copy_rom_files).
   - Log: `$BUILD/zse5/log/emu_gen.log`

2. **`gendvflist`** (~5-8 min): `gen_dv_flist`
   - DVB file list generation via dvJsonGenerator.py.
   - Log: `$BUILD/zse5/genfilelist_dv/log/dvJsonGenerator.log`

3. **`runelab`** (~30-60 min): `c_compile` → `gen_analyze_make` → `dw_gen` → `pre_analyze` → **`analyze`** → **`post_analyze`** → `gen_elab_src` → `zebu_tb` → `tb`
   - **`analyze` is the longest pre-zCui stage** (~15-40 min): VCS analysis of all RTL libraries, distributed via NB farm.
   - Check progress: `cat $BUILD/zse5/log/<TIMESTAMP>/analyze_summary.log | grep -c PASSED` vs `grep -c FAILED`
   - **`post_analyze` runs `rtlchanges_postcheck`**: Can fail if rtlchanges exist for files not compiled (orphans from IP refresh). Check `$BUILD/zse5/log/rtlchanges_postcheck.log`. Fix: add entries to `rtlchanges_optional_ips.json`.
   - After `gen_elab_src` completes, `fe_be` launches zCui.

If any pre-zCui stage fails, the gradle task exits with status 2 and grdlbuild.log shows `[Failed]`. Check the stage-specific log for errors.

**Once zCui starts**, `compilation_status.log` appears in `$BUILD/zse5/zcui.work/`. From this point, use the zCui monitoring commands below.

**Phase 1 (zCui): VCS_Task_Builder (3-6 hours)**
The longest single phase. Power-aware VCS elaboration with UPF processing. Submitted to Netbatch.
```bash
# Check log size and freshness
ls -la $BUILD/zse5/zcui.work/zCui/log/vcs_splitter_VCS_Task_Builder.log | awk '{print $5, $6, $7, $8}'

# Check for errors (should remain 0)
cat $BUILD/zse5/zcui.work/zCui/log/vcs_splitter_VCS_Task_Builder.log | grep -c 'Error-'

# Count warnings (9000+ UPF warnings are normal)
cat $BUILD/zse5/zcui.work/zCui/log/vcs_splitter_VCS_Task_Builder.log | grep -c 'Warning-'
```

**Phase 2: Synthesis Bundles (1-3 hours, up to ~2057 parallel bundles)**
After VCS_Task_Builder completes, zCui launches synthesis bundles in parallel:
```bash
# Count completed vs total bundles
cat $BUILD/zse5/zcui.work/zCui/log/zCui.log | grep -c "Synthesis normal task termination"
cat $BUILD/zse5/zcui.work/zCui/log/zCui.log | grep -c "Synthesis abnormal task termination"
```

**Phase 3: zTopBuild (30-90 min)**
After synthesis, check force assign matching:
```bash
# Verify force assigns matched (no HFA001 = good)
grep "HFA001" $BUILD/zse5/zcui.work/zebu.work/zTopBuild.log

# Check FASTCLOCK detection (should NOT show io1p2 if force assign worked)
grep "FASTCLOCK_GENERIC.*io1p2" $BUILD/zse5/zcui.work/zebu.work/zTopBuild.log
```

**Phase 4-5: zPar + zTime**
After zPar completes, check driverClk speed:
```bash
grep -E "driverClk|kHz|Critical" $BUILD/zse5/zcui.work/zebu.work/zTime.log | head -10
```

**Phase 6+: FPGA Dispatch + zTimeFpga**
Final driverClk:
```bash
grep -E "driverClk|kHz|Critical" $BUILD/zse5/zcui.work/backend_default/zTime_fpga.log | head -10
```

**Completion Check:**
```bash
cat $BUILD/zse5/zcui.work/zCui/log/zCui.log | grep "Compilation Ended"
# "Compilation Ended successfully" = PASS
# "Compilation Ended abnormally (...not launched)" = FAIL
```

### ZeBu Step 3: Deploy Background Monitor Script

Since ZeBu builds run 12-24+ hours and the AI agent is not active between conversation turns, deploy a **bash background monitor script** that polls every 60 seconds (pre-zCui) / 5 minutes (zCui) and sends emails on key events.

The monitor script serves **three purposes**:
1. **Email alerts** (autonomous): Sends email on failure, completion, slow driverClk, HFA001 warnings
2. **Monitor log** (`/tmp/monitor_<workarea>_<model>.log`): Timestamped build timeline the agent reads for periodic status checks
3. **Status file** (`/tmp/monitor_<workarea>_<model>.status`): Persistent 3-line file written on every exit (RUNNING/FAILED/PASSED + timestamp + detail). Survives after monitor dies — agent ALWAYS checks this first.

**Recommended monitoring workflow:**
1. Deploy the monitor script **immediately after build launch** (before any log dirs are created)
2. **FIRST CHECK — status file** (valid even if monitor is dead):
   ```bash
   cat /tmp/monitor_<WORKAREA_STEM>_<MODEL>.status
   ```
   - If `FAILED` or `PASSED` → the build has ended; read the detail line and investigate
   - If `RUNNING` → monitor is alive or was alive recently; check PID and log tail
3. **SECOND CHECK — monitor PID** (is it still running?):
   ```bash
   ps -p <PID> -o pid,stat
   ```
   - If dead AND status is still `RUNNING` → monitor crashed unexpectedly; check log tail
4. **THIRD CHECK — monitor log tail** for recent events:
   ```bash
   tail -20 /tmp/monitor_<WORKAREA_STEM>_<MODEL>.log
   ```
5. **Do NOT spawn background terminals** for status checks — they accumulate and clutter the terminal list

> ⚠️ **CRITICAL — Multiple parallel builds**: The user may run multiple builds in different workareas simultaneously. Always:
> - **Hardcode WORKAREA and MODEL** inside the script at deployment — never inherit from the shell environment
> - **Use a unique monitor log/status file** per WORKAREA+MODEL in `/tmp` so monitors don't collide
> - **Include both WORKAREA stem and MODEL in every email subject** so the user can identify which build sent the alert

**Script template** — fill in WORKAREA, MODEL, DUT at deployment time, save to `/tmp/monitor_<WORKAREA_STEM>_<MODEL>.sh`:
```bash
#!/bin/bash
# Hardcode all paths at deployment time — never inherit from shell environment
WORKAREA="<full WORKAREA path including any .1/.2 suffix>"  # e.g. /nfs/.../pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1
MODEL="<model name>"                                          # e.g. pkg_chpr_p2e4_816_fast
DUT="<DUT name>"                                             # e.g. ttlbx_n2p
BUILD="$WORKAREA/output/$DUT/emu/zebu_zebu/$MODEL"           # path to model build dir (without /zse5)
USER_EMAIL="hoa.nguyen@intel.com"

WORKAREA_STEM=$(basename "$WORKAREA")
MONITOR_LOG="/tmp/monitor_${WORKAREA_STEM}_${MODEL}.log"     # unique per WORKAREA+MODEL
# STATUS_FILE persists after the monitor exits — agent always checks this first.
# States: RUNNING | FAILED | PASSED
# Format: line1=state, line2=timestamp, line3=detail
STATUS_FILE="/tmp/monitor_${WORKAREA_STEM}_${MODEL}.status"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$MONITOR_LOG"; }
send_email() { echo -e "$2" | /bin/mail -s "$1" "$USER_EMAIL"; }
# write_status: writes persistent outcome to STATUS_FILE
write_status() {
    local state="$1"
    local detail="$2"
    printf "%s\n%s\n%s\n" "$state" "$(date '+%Y-%m-%d %H:%M:%S')" "$detail" > "$STATUS_FILE"
    log "STATUS -> $STATUS_FILE: $state"
}

LOGDIR="$BUILD/zse5/log"

log "=== Monitor started: $MODEL in $WORKAREA ==="
log "BUILD=$BUILD/zse5"
write_status "RUNNING" "Monitor started"

# ── STARTUP BASELINE: stale failure_info.log at root ─────────────────────────
# DVB's make_execute.py symlinks $LOGDIR/failure_info.log → the most recent NB
# task failure. Capture its target NOW so we can ignore it as stale and only
# alert on NEW failures that appear after the monitor starts.
STALE_FAIL_TARGET=""
if [ -L "$LOGDIR/failure_info.log" ]; then
    STALE_FAIL_TARGET=$(readlink -f "$LOGDIR/failure_info.log" 2>/dev/null)
    log "Baseline: stale failure_info.log → $STALE_FAIL_TARGET (ignoring)"
fi

# ── STARTUP BASELINE: EmuGen stage log mtimes ────────────────────────────────
# EmuGen stages (pre_analyze, post_analyze, rtlchanges_*, emu_gen) run as
# buildit.py invocations from the Makefile — NOT as DVB NB sub-tasks.
# They do NOT create failure_info.log. Failures are detected by watching root
# log files for RuntimeError/Traceback. Record current mtimes so we only check
# content written AFTER monitor start (avoids false positives from prior runs).
declare -A EMUSTAGE_MTIME
declare -A EMUSTAGE_REPORTED
EMUSTAGES="pre_analyze post_analyze rtlchanges_precheck rtlchanges_postcheck emu_gen"
for stage in $EMUSTAGES; do
    STAGELOG="$LOGDIR/${stage}.log"
    if [ -f "$STAGELOG" ]; then
        EMUSTAGE_MTIME[$stage]=$(stat -c %Y "$STAGELOG" 2>/dev/null || echo 0)
        log "Baseline mtime for $stage.log: ${EMUSTAGE_MTIME[$stage]}"
    else
        EMUSTAGE_MTIME[$stage]=0
    fi
    EMUSTAGE_REPORTED[$stage]=0
done

ANALYZE_REPORTED=0
DRVCLK_REPORTED=0
HFA_REPORTED=0
HEARTBEAT_COUNT=0

# ── FAILURE STATE ─────────────────────────────────────────────────────────────
# CRITICAL: Do NOT exit on failure. Instead, set FAILED_STAGE and keep looping.
# This keeps the monitor alive so the agent always sees it running and the
# heartbeat log loudly repeats the failure every 5 min until the build is fixed.
# Exiting on failure was the root cause of missed failures — agent only checks
# when asked, so a dead monitor looks identical to a healthy one.
FAILED_STAGE=""
FAILED_MSG=""

# ── STARTUP BASELINE: zCui.log mtime ─────────────────────────────────────────
# If a prior failed build left zCui.log with "Compilation Ended abnormally",
# baseline its mtime so we don't false-alarm on it when the monitor restarts.
# Only act on zCui.log content written AFTER the monitor started.
# This is critical when relaunching with -id: the old zCui.log from the failed
# run stays in place until fe_be (which launches zCui) runs again.
ZCUI_INIT="$BUILD/zse5/zcui.work/zCui/log/zCui.log"
STALE_ZCUI_MTIME=0
if [ -f "$ZCUI_INIT" ]; then
    STALE_ZCUI_MTIME=$(stat -c %Y "$ZCUI_INIT" 2>/dev/null || echo 0)
    log "Baseline mtime for zCui.log: $STALE_ZCUI_MTIME (stale — prior run result ignored)"
fi

while true; do

    HEARTBEAT_COUNT=$((HEARTBEAT_COUNT + 1))

    # ── HEARTBEAT every 5 cycles (5 min pre-zCui, 25 min during zCui) ────────
    # If build already failed, heartbeat loudly so agent sees it on next check.
    if [ $((HEARTBEAT_COUNT % 5)) -eq 0 ]; then
        if [ -n "$FAILED_STAGE" ]; then
            log "🚨 BUILD FAILED at [$FAILED_STAGE] — awaiting fix+relaunch | $FAILED_MSG"
        else
            RECENT_LOG=$(ls -t "$LOGDIR"/*.log 2>/dev/null | head -1)
            RECENT_BASE=$(basename "${RECENT_LOG:-unknown}" 2>/dev/null)
            log "💓 Monitoring: $MODEL | Most recent log: $RECENT_BASE"
        fi
    fi

    # ── If already failed, skip all detection checks ──────────────────────────
    if [ -n "$FAILED_STAGE" ]; then
        sleep 60
        continue
    fi

    # ── DVB NB failures: root failure_info.log symlink ────────────────────────
    # DVB's make_execute.py creates $LOGDIR/<timestamp>/failure_info.log AND
    # symlinks $LOGDIR/failure_info.log → the timestamped file. This covers ALL
    # DVB NB sub-task failures: analyze, c_compile, dw_gen, fe_be, etc.
    # NOTE: On TTL each DVB NB sub-task gets its own timestamped dir.
    # Watch the ROOT symlink — not individual timestamped dirs.
    if [ -L "$LOGDIR/failure_info.log" ]; then
        CURRENT_FAIL_TARGET=$(readlink -f "$LOGDIR/failure_info.log" 2>/dev/null)
        if [ -n "$CURRENT_FAIL_TARGET" ] && [ "$CURRENT_FAIL_TARGET" != "$STALE_FAIL_TARGET" ]; then
            FAILED_STAGE="DVB NB"
            FAILED_MSG="See $LOGDIR/failure_info.log"
            log "❌ DVB NB FAILURE (failure_info.log):"
            while IFS= read -r line; do log "  $line"; done < <(head -60 "$LOGDIR/failure_info.log")
            send_email "[ZeBu FAIL pre-zCui] $MODEL ($WORKAREA_STEM)" \
                "DVB NB stage failure.\nWORKAREA: $WORKAREA\nMODEL: $MODEL\n\n$(head -60 $LOGDIR/failure_info.log)"
            write_status "FAILED" "DVB NB stage failure — see $LOGDIR/failure_info.log"
            log "❌ Monitor entering FAILED state — heartbeat will repeat failure until build relaunched."
            sleep 60
            continue
        fi
    fi

    # ── EmuGen stage failures: watch root log files for error patterns ────────
    # ALL EmuGen stages (pre_analyze, post_analyze, rtlchanges_*, emu_gen)
    # write to fixed log paths in $LOGDIR/ root — no failure_info.log ever created.
    # Only check files whose mtime advanced past the startup baseline (new content).
    for stage in $EMUSTAGES; do
        if [ "${EMUSTAGE_REPORTED[$stage]}" = "1" ]; then continue; fi
        STAGELOG="$LOGDIR/${stage}.log"
        [ -f "$STAGELOG" ] || continue
        CURRENT_MTIME=$(stat -c %Y "$STAGELOG" 2>/dev/null || echo 0)
        [ "$CURRENT_MTIME" -le "${EMUSTAGE_MTIME[$stage]}" ] && continue
        if grep -q "RuntimeError\|ERROR: CHECK FAILED\|Traceback (most recent" "$STAGELOG" 2>/dev/null; then
            EMUSTAGE_REPORTED[$stage]=1
            ERRORS=$(grep "RuntimeError\|ERROR:\|FAILED" "$STAGELOG" 2>/dev/null | tail -15)
            FAILED_STAGE="$stage"
            FAILED_MSG="See $STAGELOG"
            log "❌ $stage FAILED:"
            while IFS= read -r line; do log "  $line"; done <<< "$ERRORS"
            send_email "[ZeBu FAIL $stage] $MODEL ($WORKAREA_STEM)" \
                "$stage failed.\nWORKAREA: $WORKAREA\nMODEL: $MODEL\n\n$ERRORS"
            write_status "FAILED" "$stage failed — see $STAGELOG"
            log "❌ Monitor entering FAILED state — heartbeat will repeat failure until build relaunched."
            sleep 60
            continue 2
        fi
    done

    # ── Analyze PASSED: search ALL timestamped dirs ───────────────────────────
    # analyze_summary.log lives in ONE of the many timestamped NB sub-task dirs.
    # Do NOT track "current dir" — scan all dirs so rotation doesn't miss it.
    # IMPORTANT: Do NOT use "|| echo 0" with grep -c.
    # grep -c exits with 1 on no match but still outputs "0" to stdout,
    # so "|| echo 0" produces "0\n0" which is NOT a valid integer.
    # Use ${VAR:-0} fallback instead.
    if [ "$ANALYZE_REPORTED" = "0" ]; then
        for d in $(ls -t "$LOGDIR" 2>/dev/null | grep -E '^[0-9]+\.'); do
            SUMLOG="$LOGDIR/$d/analyze_summary.log"
            if [ -f "$SUMLOG" ]; then
                PASSED=$(grep -c "PASSED" "$SUMLOG" 2>/dev/null); PASSED=${PASSED:-0}
                FAILED=$(grep -c "FAILED" "$SUMLOG" 2>/dev/null); FAILED=${FAILED:-0}
                if [ "$PASSED" -gt 0 ] && [ "$FAILED" -eq 0 ]; then
                    log "✅ analyze PASSED ($PASSED libs)"
                    ANALYZE_REPORTED=1
                fi
                break  # Only check most-recent dir that has analyze_summary.log
            fi
        done
    fi

    # ── ZCUI MONITORING (once zcui.work/ appears) ───────────────────────────
    ZCUI_LOG="$BUILD/zse5/zcui.work/zCui/log/zCui.log"
    STATUS_LOG="$BUILD/zse5/zcui.work/compilation_status.log"
    ZTIME_LOG="$BUILD/zse5/zcui.work/zebu.work/zTime.log"
    ZTIME_FPGA_LOG="$BUILD/zse5/zcui.work/backend_default/zTime_fpga.log"
    ZTOPBUILD_LOG="$BUILD/zse5/zcui.work/zebu.work/zTopBuild.log"

    if [ -f "$ZCUI_LOG" ]; then
        ZCUI_MTIME=$(stat -c %Y "$ZCUI_LOG" 2>/dev/null || echo 0)
        # Skip stale zCui.log from a prior run — only act on content from the current run.
        # This is critical when relaunching with -id: the old zCui.log from the failed run
        # remains in place until fe_be runs again and zCui overwrites it.
        if [ "$ZCUI_MTIME" -le "${STALE_ZCUI_MTIME:-0}" ]; then
            sleep 60
            continue
        fi
        # Definitive failure signal — excludes backend P&R strategy failures (see note below)
        if cat "$ZCUI_LOG" 2>/dev/null | grep -q "Compilation Ended abnormally"; then
            FAILED=$(cat "$ZCUI_LOG" | grep -A5 "List of failed tasks")
            FAILED_STAGE="zCui fe_be"
            FAILED_MSG="Compilation Ended abnormally — see $ZCUI_LOG"
            log "❌ ZCUI BUILD FAILED"
            send_email "[ZeBu FAIL] $MODEL ($WORKAREA_STEM)" \
                "Build FAILED.\nWORKAREA: $WORKAREA\nMODEL: $MODEL\n\n$FAILED"
            write_status "FAILED" "zCui Compilation Ended abnormally — see $ZCUI_LOG"
            log "❌ Monitor entering FAILED state — heartbeat will repeat failure until build relaunched."
            sleep 60
            continue
        fi

        # Success
        if cat "$ZCUI_LOG" 2>/dev/null | grep -q "Compilation Ended successfully"; then
            DRVCLK=$(cat "$ZTIME_FPGA_LOG" 2>/dev/null | grep "driverClk" | head -1)
            log "✅ BUILD PASSED. driverClk: $DRVCLK"
            send_email "[ZeBu PASS] $MODEL ($WORKAREA_STEM)" \
                "Build PASSED.\nWORKAREA: $WORKAREA\nMODEL: $MODEL\n\ndriverClk: $DRVCLK"
            write_status "PASSED" "Build succeeded. driverClk: $DRVCLK"
            exit 0
        fi

        # driverClk alert (once, when zTime.log appears)
        if [ "$DRVCLK_REPORTED" = "0" ] && [ -f "$ZTIME_LOG" ]; then
            KHZ=$(cat "$ZTIME_LOG" 2>/dev/null | grep "driverClk" | grep -oP '\d+\s*kHz' | head -1 | grep -oP '\d+')
            if [ -n "$KHZ" ]; then
                log "🕐 driverClk: ${KHZ} kHz"
                if [ "$KHZ" -lt 200 ]; then
                    send_email "[ZeBu SLOW] driverClk ${KHZ} kHz - $MODEL ($WORKAREA_STEM)" \
                        "driverClk is ${KHZ} kHz (below 200 kHz threshold).\nWORKAREA: $WORKAREA\nMODEL: $MODEL"
                fi
                DRVCLK_REPORTED=1
            fi
        fi

        # HFA001 force assign mismatches (once, after zTopBuild completes)
        if [ "$HFA_REPORTED" = "0" ] && cat "$ZCUI_LOG" 2>/dev/null | grep -q "zTopBuild normal task termination"; then
            # IMPORTANT: Do NOT use "|| echo 0" with grep -c — same integer bug as analyze check above.
            HFA=$(grep -c "HFA001" "$ZTOPBUILD_LOG" 2>/dev/null)
            HFA=${HFA:-0}
            if [ "$HFA" -gt 0 ]; then
                log "⚠️ $HFA HFA001 force assign mismatch(es)"
                send_email "[ZeBu WARN] HFA001 - $MODEL ($WORKAREA_STEM)" \
                    "$HFA force assign(s) did not match.\nWORKAREA: $WORKAREA\nMODEL: $MODEL\n\n$(cat $ZTOPBUILD_LOG | grep HFA001)"
            fi
            HFA_REPORTED=1
        fi

        # Log zCui status
        STATUS=$(cat "$STATUS_LOG" 2>/dev/null | grep "Running" | head -3)
        log "zCui: ${STATUS:-waiting...}"
        sleep 300  # 5 min during zCui synthesis
    else
        sleep 60   # 1 min pre-zCui (failures happen fast here)
    fi

done
```

**Deploy the monitor** (fill in WORKAREA_STEM and MODEL with actual values):
```bash
WORKAREA_STEM=$(basename "<WORKAREA>")   # e.g. pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1
MODEL="<model>"                          # e.g. pkg_chpr_p2e4_816_fast
SCRIPT="/tmp/monitor_${WORKAREA_STEM}_${MODEL}.sh"
# ... write script to $SCRIPT with cat > $SCRIPT << 'EOF' ... EOF ...
nohup bash "$SCRIPT" >> "/tmp/monitor_${WORKAREA_STEM}_${MODEL}.log" 2>&1 &
echo "Monitor PID: $!  (log: /tmp/monitor_${WORKAREA_STEM}_${MODEL}.log)"
```

**Read monitor status:**
```bash
WORKAREA_STEM=$(basename "<WORKAREA>")
MODEL="<model>"
tail -30 /tmp/monitor_${WORKAREA_STEM}_${MODEL}.log
```

**Implementation notes:**
- Use `bash` — tcsh cannot handle `$()`, `[[ ]]`, or reliable redirect syntax
- Use `cat file | grep` instead of `grep file` to avoid NFS hangs
- **WORKAREA must be hardcoded inside the script** — if the user has parallel builds, each monitor needs its own hardcoded WORKAREA so they don't interfere. Never use `$WORKAREA` from the shell environment.
- **Monitor log is in `/tmp`** with WORKAREA+MODEL in the filename — unique per build, survives zse5/ not existing yet at deploy time
- **Do NOT use `pgrep`** — it is prohibited in this shell environment. Use file-based signals only (log dirs, failure_info.log, zCui.log keywords).
- **Root `failure_info.log` symlink** (not per-timestamp-dir tracking): DVB's `make_execute.py` symlinks `$LOGDIR/failure_info.log` → the most recent NB sub-task failure. On TTL each DVB NB sub-task (spark_co, gen_dv_flist, c_compile/dw_gen/gen_analyze_make, analyze, fe_be) gets its own timestamped dir, so there are many dirs per build. Tracking "latest timestamped dir" and checking `failure_info.log` within it is fragile — use the root symlink instead. Baseline its target at startup to avoid stale false positives.
- **EmuGen stage failures use root log files, NOT failure_info.log**: Stages `pre_analyze`, `post_analyze`, `rtlchanges_precheck`, `rtlchanges_postcheck`, `emu_gen` are run as `buildit.py` invocations from the Makefile — not as DVB NB sub-tasks. They write to fixed `$LOGDIR/<stage>.log` paths and never create `failure_info.log`. Detect failures by watching these root log files for `RuntimeError|ERROR: CHECK FAILED|Traceback`. Use mtime baselining at startup to avoid false positives from prior runs.
- **zCui.log must also be mtime-baselined at startup**: When relaunching with `-id` after a fe_be failure, the old `zCui.log` from the failed run remains in place until `fe_be` runs again. Without mtime baselining, the monitor will immediately see "Compilation Ended abnormally" and exit as a false positive. Capture `STALE_ZCUI_MTIME` at startup and skip any `zCui.log` whose mtime ≤ that baseline.
- **Heartbeat logging every 5 cycles** so the user can see the monitor is alive even during long quiet phases (analyze takes ~45 min, fe_be takes ~25 hrs).
- **Search ALL timestamped dirs for analyze_summary.log** — do NOT restrict to "current dir". The analyze NB job creates one dir, then later NB jobs create new dirs. If the monitor switches to the new dir, it must still find analyze_summary.log in the older dir.
- Check for `"zTopBuild normal task termination"` (exact string) — do NOT match `"zTopBuildResultAnalyzer"` which appears much earlier
- Email address: always use `hoa.nguyen@intel.com` — do NOT derive from `whoami`
- Include WORKAREA stem AND MODEL in every email subject — user runs multiple parallel builds
- **CRITICAL — Do NOT treat backend FPGA P&R failures as build failures**: `backend_default_U*_M*_F*_L* abnormal task termination` means one FPGA place-and-route strategy failed, but other strategies may succeed. The only definitive failure signal is `"Compilation Ended abnormally"` in zCui.log:
  ```bash
  # WRONG — false positive on backend strategy failures:
  grep -q "abnormal task termination" zCui.log
  # CORRECT — use definitive signal only:
  grep -q "Compilation Ended abnormally" zCui.log
  ```

### ZeBu Step 4: Diagnose Failures

#### Synthesis Bundle Failure
```bash
# Find which bundle failed
cat $BUILD/zse5/zcui.work/zCui/log/zCui.log | grep "abnormal"

# Read the failed bundle log
cat $BUILD/zse5/zcui.work/zCui/log/design_Default_RTL_GroupBundle_NNN_Synthesis.log | grep -i "fatal\|error" | tail -20
```

**Known synthesis failure patterns:**

| Error | Root Cause | Fix |
|-------|-----------|-----|
| `Unsupported System Task $clock_boundary_marker_task` | `clock_boundary_marker` directive in sle_dut.utf; ZFAST V-2024.03-1.7 doesn't support it | Remove `clock_boundary_marker`, use `force assign -value 0` instead |
| `fatal error in ZFAST [116.11]: Error translating circuit` | Usually a downstream effect of the above | Fix the upstream `$clock_boundary_marker_task` error |
| `cp: cannot create regular file '.../user_inputs/Makefile': File exists` (exit status 2) | Pre-zCui failure: DVB `Makefile.common:36` uses `\cp -Hrf` (no `-f`) to populate `zse5/user_inputs/`. Stale files from a prior failed build survive the `cleanall` | `rm -rf $BUILD/zse5` then relaunch with same `-id` command |

#### driverClk Too Slow
If driverClk < 200 kHz after zTime, consult the `sle-build-zebu-driverclock-debug` skill. Key checks:
1. `grep "FASTCLOCK_GENERIC" $BUILD/zse5/zcui.work/zebu.work/zTopBuild.log` — look for auto-detected clocks on analog pads
2. `grep "HFA001" $BUILD/zse5/zcui.work/zebu.work/zTopBuild.log` — force assigns that didn't match (dead fix = FASTCLOCK still active)
3. **CRITICAL (ww17 2026)**: Do NOT use `force assign -value 0` on PCD IO pads without verifying the wrapper instance carries a non-functional signal. The `xxpcd_epd_on.io1p2_inst.xio_pad_1p2` tieoff was REMOVED because it killed functional EPD_ON (PCD→HUB power sequencing), breaking all cfgr model boots. Only 4 of 14 io1p2 instances are safe probe pads: `xxdbg_pmode`, `xxjtagx`, `xxprdy_b`, `xxpreq_b`. Similarly, `io1p8weak_ll_ls` pads carry power sequencing signals — never tieoff with broad wildcards.

#### Force Assign Not Matching
If `HFA001` appears for io1p2:
- **WRONG**: `...io1p2_inst.pad` — `pad` is on the wrapper module (`xxpcd_epd_on`), not on `io1p2_inst`
- **WRONG**: `...io1p2_inst.*probe_xio_pad*` — synthesis-generated name, not in RTL namespace
- **CORRECT**: `...io1p2_inst.xio_pad_1p2` — confirmed wire 27 in `RTLDB/NameDir/io1p2.namemap.gz`
- **BUT**: Only apply `-value 0` to verified non-functional probe pad instances (see `sle-build-zebu-driverclock-debug` skill "Pad Tieoff Safety" section)

### ZeBu Step 5: Apply Fix and Rebuild
1. Edit `$WORKAREA/src/val/emu/build_cfg/sle_dut.utf` (the main ZeBu UTF config file)
2. Relaunch: `grdlbuild :ttlbx_n2p:emu:sle:$MODEL_zse -id`
3. Redeploy the monitor script (the old process will have exited on build completion/failure)

### ZeBu Email Template
```
ZeBu Build Report - <DATE>
====================================

BUILD TARGET: <target>
MODEL:        <model name>
WORKSPACE:    <WORKAREA path>
BUILD DIR:    <$BUILD path>

BUILD RESULT: FAILED / PASSED
=====================
  Started:  <time from zCui.log first entry>
  Ended:    <time from "Compilation Ended" line>
  Phase:    <last phase reached>

FAILURE DETAILS (if failed):
  Failed Task: <bundle or phase name>
  Error: <error description from log>
  Log: <path to specific failure log>

DRIVERCLOCK (if build reached zTime):
  Pre-FPGA:  <driverClk from zTime.log>
  Post-FPGA: <driverClk from zTime_fpga.log>
  Status: OK / SLOW (< 200 kHz)

FORCE ASSIGN VERIFICATION (if build reached zTopBuild):
  HFA001 warnings: <count>
  FASTCLOCK_GENERIC on io1p2: <present/absent>

FIX APPLIED:
  <description of fix, or N/A>

SKILLS APPLIED:
  - sle-build-grdlbuild-monitor: ZeBu build monitoring
  - sle-build-zebu-driverclock-debug: driverClk analysis (if applicable)

-- Copilot Build Agent
```

### ZeBu Timing Expectations

| Phase | Typical Duration | Notes |
|-------|-----------------|-------|
| VCS_Task_Builder | 3-6 hours | Submitted to Netbatch; UPF processing dominates |
| Synthesis Bundles | 1-3 hours | ~2000 bundles in parallel on NB farm |
| zTopBuild | 30-90 min | Force assign matching, FASTCLOCK detection |
| zPar | 1-3 hours | FPGA partitioning |
| zTime | 5-15 min | Pre-FPGA timing |
| FPGA Dispatch (Vivado) | 2-8 hours | Vivado synthesis per FPGA |
| zTimeFpga | 5-15 min | Final timing |
| **Total** | **12-24+ hours** | |

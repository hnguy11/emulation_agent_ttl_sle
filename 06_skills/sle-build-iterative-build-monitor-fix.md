---
name: sle-build-iterative-build-monitor-fix
description: "Iteratively launch, monitor, diagnose, fix, and relaunch grdlbuild emulation builds. USE WHEN: user asks to run a build end-to-end, launch and monitor a grdlbuild, kick off a build and fix errors, iterative build-fix cycle, automated build management. Covers: setting WORKAREA, launching grdlbuild, phase-by-phase monitoring (emu_gen, genfilelist/dvJsonGenerator, VCS analysis, VCS elaboration), error detection, automated fix application, email reporting, rebuild decision-making. VCS/FPGA builds: deploy fpga_vcs_build_monitor.sh for autonomous background monitoring that survives across conversation turns. ZeBu (ZSE5) builds: deploy monitor_build.sh for zCui orchestrator monitoring, compilation_status.log polling, synthesis Bundle failure diagnosis, zTopBuild force assign verification, driverClk analysis from zTime.log."
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

```tcsh
cd /path/to/workspace          # e.g. .../pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1
setenv WORKAREA $PWD           # set WORKAREA to the exact path including any suffix (.1, .2, etc.)
setenv LM_PROJECT DDG-TTLPKG   # REQUIRED for TTL builds — prevents getLf license failures
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
setenv WORKAREA /exact/path/to/workarea
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
Same as VCS — grdlbuild handles the launch:
```tcsh
setenv WORKAREA /path/to/workspace
setenv LM_PROJECT DDG-TTLPKG
grdlbuild :ttlbx_n2p:emu:sle:pkg_chpr_cfgr_p2e0_816_fast_zse -id
```
Launch in a background terminal. grdlbuild will set up the environment and invoke zCui.

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

Since ZeBu builds run 12-24+ hours and the AI agent is not active between conversation turns, deploy a **bash background monitor script** that polls every 5 minutes and sends emails on key events.

The monitor script serves **two purposes**:
1. **Email alerts** (autonomous): Sends email on failure, completion, slow driverClk, HFA001 warnings
2. **Status log** (`monitor_build.out`): Provides a timestamped build timeline that the agent reads with a single foreground command for periodic status checks

**Recommended monitoring workflow:**
1. Deploy `monitor_build.sh` immediately after build launch (or after zse5/ is created)
2. When user asks for status (or for periodic checks), use `read_file` to check logs directly:
   - First: `read_file` on `compilation_status.log` — identifies which subtask is running
   - Then: `read_file` on the running subtask's log (see subtask-to-log table above)
   - Also: `read_file` on `monitor_build.out` for the full timestamped history
3. For a quick overview, `read_file` on `zCui.log` (last 30-50 lines) shows recent task completions
4. **Do NOT use terminal commands** for log reads — NFS stalls. Only use terminal for >50MB files with targeted `grep`.
3. This single command shows monitor health + complete build progress — no need to parse multiple logs
4. **Do NOT spawn background terminals** for status checks — they accumulate and clutter the terminal list

**Script template** (save to `$BUILD/zse5/monitor_build.sh`):
```bash
#!/bin/bash
BUILD="<full path to model build dir>"
WORKAREA="<full WORKAREA path>"
ZCUI_LOG="$BUILD/zse5/zcui.work/zCui/log/zCui.log"
STATUS_LOG="$BUILD/zse5/zcui.work/compilation_status.log"
ZTIME_LOG="$BUILD/zse5/zcui.work/zebu.work/zTime.log"
ZTIME_FPGA_LOG="$BUILD/zse5/zcui.work/backend_default/zTime_fpga.log"
ZTOPBUILD_LOG="$BUILD/zse5/zcui.work/zebu.work/zTopBuild.log"
USER_EMAIL="hoa.nguyen@intel.com"
POLL_INTERVAL=300  # 5 minutes
LOG="$BUILD/zse5/monitor_build.log"

send_email() {
    local subject="$1"
    local body="$2"
    echo -e "$body" | /bin/mail -s "$subject" "$USER_EMAIL"
}

while true; do
    TIMESTAMP=$(date "+[%a %d %b %Y %I:%M:%S %p %Z]")

    # Check for build failure
    if cat "$ZCUI_LOG" 2>/dev/null | grep -q "abnormal task termination\|Compilation Ended abnormally"; then
        FAILED_TASKS=$(cat "$ZCUI_LOG" | grep -A5 "List of failed tasks")
        echo "$TIMESTAMP BUILD FAILED" >> "$LOG"
        send_email "[ZeBu FAIL] $WORKAREA" "Build failed.\nWORKAREA: $WORKAREA\n\nFailed tasks:\n$FAILED_TASKS"
        echo "$TIMESTAMP BUILD FAILED - email sent" >> "$LOG"
        exit 0
    fi

    # Check for build success
    if cat "$ZCUI_LOG" 2>/dev/null | grep -q "Compilation Ended successfully"; then
        echo "$TIMESTAMP BUILD PASSED" >> "$LOG"
        # Check driverClk from zTime_fpga.log
        DRIVCLK=$(cat "$ZTIME_FPGA_LOG" 2>/dev/null | grep "driverClk" | head -1)
        send_email "[ZeBu PASS] $WORKAREA" "Build completed successfully.\nWORKAREA: $WORKAREA\n\ndriverClk: $DRIVCLK"
        echo "$TIMESTAMP BUILD PASSED - email sent" >> "$LOG"
        exit 0
    fi

    # Check for VCS_Task_Builder completion (0 errors expected)
    if cat "$ZCUI_LOG" 2>/dev/null | grep -q "VCS_Task_Builder normal task termination"; then
        VCS_ERRORS=$(cat "$BUILD/zse5/zcui.work/zCui/log/vcs_splitter_VCS_Task_Builder.log" 2>/dev/null | grep -c 'Error-')
        if [ "$VCS_ERRORS" -gt 0 ]; then
            echo "$TIMESTAMP VCS_Task_Builder completed with $VCS_ERRORS errors" >> "$LOG"
        fi
    fi

    # Check for zTopBuild completion — verify force assigns
    if cat "$ZCUI_LOG" 2>/dev/null | grep -q "zTopBuild normal task termination"; then
        HFA_COUNT=$(cat "$ZTOPBUILD_LOG" 2>/dev/null | grep -c "HFA001")
        if [ "$HFA_COUNT" -gt 0 ]; then
            HFA_DETAILS=$(cat "$ZTOPBUILD_LOG" 2>/dev/null | grep "HFA001")
            echo "$TIMESTAMP WARNING: $HFA_COUNT HFA001 warnings (dead force assigns)" >> "$LOG"
            send_email "[ZeBu WARN] HFA001 - $WORKAREA" "Force assign(s) did not match.\nWORKAREA: $WORKAREA\n\n$HFA_DETAILS"
        fi
    fi

    # Check for zTime completion — driverClk speed
    if [ -f "$ZTIME_LOG" ]; then
        DRIVCLK_KHZ=$(cat "$ZTIME_LOG" 2>/dev/null | grep "driverClk" | grep -oP '\d+\s*kHz' | head -1 | grep -oP '\d+')
        if [ -n "$DRIVCLK_KHZ" ] && [ "$DRIVCLK_KHZ" -lt 200 ]; then
            echo "$TIMESTAMP driverClk is slow: ${DRIVCLK_KHZ} kHz" >> "$LOG"
            send_email "[ZeBu SLOW] driverClk ${DRIVCLK_KHZ} kHz - $WORKAREA" "driverClk is ${DRIVCLK_KHZ} kHz (below 200 kHz threshold).\nWORKAREA: $WORKAREA\n\nInvestigate with sle-build-zebu-driverclock-debug skill."
        fi
    fi

    # Log current status
    CURRENT=$(cat "$STATUS_LOG" 2>/dev/null | grep "Running")
    echo "$TIMESTAMP $CURRENT" >> "$LOG"

    sleep $POLL_INTERVAL
done
```

**Launch the monitor:**
```bash
bash -c 'nohup bash $BUILD/zse5/monitor_build.sh > /dev/null 2>&1 & echo "Monitor PID: $!"'
```

**Implementation notes:**
- Use `bash` — tcsh cannot handle `$()`, `[[ ]]`, or reliable redirect syntax
- Use `cat file | grep` instead of `grep file` to avoid NFS hangs
- Check for `"zTopBuild normal task termination"` (exact string) — do NOT also match `"zTopBuildResultAnalyzer"` which appears much earlier
- Email address: always use `hoa.nguyen@intel.com` — do NOT derive from `whoami`
- Include WORKAREA in email subject — user runs multiple parallel builds
- **CRITICAL — Do NOT treat backend FPGA P&R failures as build failures**: `backend_default_U*_M*_F*_L* abnormal task termination` means one FPGA place-and-route strategy failed, but other strategies may succeed. Each FPGA unit runs multiple P&R strategies in parallel — the build only fails if ALL strategies for a unit fail. The failure detection logic must exclude these:
  ```bash
  # WRONG — false positive on backend strategy failures:
  grep -q "abnormal task termination" zCui.log
  # CORRECT — only match non-backend failures, or use definitive signal:
  grep "abnormal task termination" zCui.log | grep -qv "backend_default_U"
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

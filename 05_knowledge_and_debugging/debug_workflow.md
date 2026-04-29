---
title: "Debug Workflow — Log Analysis &amp; Troubleshooting Protocol"
module: 05_knowledge_and_debugging
tags: [debug, workflow, logs, troubleshooting, errors, root-cause]
---

# Debug Workflow — Log Analysis &amp; Troubleshooting Protocol

## Step 1: Identify the Failure Type

### Build Failure
```bash
# Check if build failed
cat output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/log/<TIMESTAMP>/failure_info.log 2>/dev/null || echo "no failure"

# Check top-level verdict
grep -E "PASSED|FAILED|Exit status" output/grdlbuild/logs/emu_build.zebu.pkg_ghpf_model_zse5.log | tail -10
```

### Test Failure
```bash
# Check test results
cat regression/nvlsi7_n2p/doa_pkg_ghpf_model_zse5.list.N/<test>/results.log
cat regression/nvlsi7_n2p/doa_pkg_ghpf_model_zse5.list.N/<test>/assertion_failures.log
cat regression/nvlsi7_n2p/doa_pkg_ghpf_model_zse5.list.N/<test>/postmortem.log | head -5
```

## Step 2: Find the Error

### Build Errors
```bash
ZSE5="output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5"
LOGDIR="$ZSE5/log/<TIMESTAMP>"

# Find which Zebu sub-stage failed
grep "abnormal task termination" "$LOGDIR/fe_be.NB.log" | grep -v "aborted" | tail -10

# Read the specific stage log
grep -i "error\|fatal\|fail" "$ZSE5/zcui.work/zCui/log/backend_default_<STAGENAME>.log" | grep -v "^#.*warning" | tail -20
```

### Test Errors
```bash
# Check logbook for exit status
grep -E "EXIT|FAIL|ERROR|exit" regression/.../logbook.log | tail -10

# Check testbench for runtime errors
grep -i "error\|fatal\|cannot" regression/.../testbench.log | head -20

# Check emurun for infrastructure errors
grep -i "error\|fail\|warning" regression/.../emurun.log | tail -20
```

## Step 3: Cross-Reference with Known Bugs

1. Search `known_bugs_and_fixes/` directory for matching error text
2. Check `common_patterns.md` for the error category
3. If match found → apply documented fix
4. If no match → continue to Step 4

## Step 4: Root Cause Analysis

### Checklist
1. Check `failure_info.log` — gives stage name and captured error lines
2. Open the stage's log file listed in `failure_info.log`
3. Search for `ERROR:`, `Fatal:`, `Error 1`, `No such file`, `cannot stat`
4. Check if the error is a known pattern (see `common_patterns.md`)
5. If a missing binary/script: check if path exists; check shebang line
6. If a missing file: determine if it should have been generated or came from IPX
7. If disk-related: check `df` output; free space; restart the failed stage
8. If permissions: check ownership (`ls -la`), group membership (`id`), symlink target

## Step 5: Document the Fix

After resolving the issue:
1. Create a new file in `known_bugs_and_fixes/` using `bug_template.md`
2. Include exact error text, exact fix commands, files affected, verification steps
3. Update `common_patterns.md` if applicable
4. Update `commands_reference.md` if you used new commands

---

## Expert Log Mapping & Phase Detection (Extracted from ai_picker_sle Reference)

This section provides a structured methodology for classifying test failures by **phase**, mapping the complete log file inventory, and defining conditional log scanning rules. An AI agent should use this section to quickly determine WHERE a failure occurred before analyzing WHAT failed.

### 1. Phase Detection Decision Tree

When a test fails, classify the failure into one of five phases **before** performing root cause analysis. This avoids wasting time in the wrong logs.

```
START → Check logbook.log stage table
  ├─ "Test build" FAIL → PHASE: BUILD
  ├─ "Model run" FAIL → Check emurun.log:
  │   ├─ "force.*error" or "compile.*fail" → BUILD
  │   ├─ "plugin.*fail" → EMU_SETUP
  │   ├─ "timeout" or "WMTRUN" → RUNTIME
  │   └─ No errors in emurun → TEST_EXECUTION
  ├─ "Post processing" FAIL → POST_PROCESS
  └─ All PASS but test FAILED → POST_PROCESS (validation issue)
```

**Phase definitions:**

| Phase | Description |
|-------|-------------|
| `BUILD` | Compilation or model build failure — test never ran |
| `EMU_SETUP` | Emulation infrastructure setup failure (plugins, ZeBu config) |
| `RUNTIME` | Test started running but hit a timeout or infrastructure crash |
| `TEST_EXECUTION` | Test ran but produced incorrect results or hit a DUT bug |
| `POST_PROCESS` | Test ran to completion but post-processing checks failed |

**Time budget for triage:**
- **90 seconds** — Phase detection (parse logbook stage table, classify)
- **60 seconds** — Symptom collection (scan phase-specific logs for error keywords)
- **30 seconds** — Methodology search (match symptoms to known patterns/bugs)

### 2. Complete Log File Inventory

The following table lists ALL known log files in the emulation test environment. Use this as a reference when determining which logs to inspect.

| Log File | Purpose | Success Markers | Failure Markers |
|----------|---------|-----------------|-----------------|
| `logbook.log(.gz)` | Master test run log with stage pass/fail table | All stages `PASS` | Any stage `FAIL` |
| `emurun.log` | Emulation runner log | `"PASSED"` | `"error"`, `"fatal"`, `"timeout"` |
| `merged_idi.log` | IDI/IDIB traffic (AT_IDI_0=Atom, IA_IDI_1=big core, LPID=core within cluster) | Normal traffic flow | Missing transactions, gaps |
| `idi_bridge.log` | IDIB traffic, AT_IDI_0 only | Continuous traffic | Transaction gaps |
| `guop_tracker_*.log.gz` | uCode tracker per processor (e.g., CDIE0_P5C1 = DCM-5 CDie, proc#1) | Execution progress | Stuck at same LIP |
| `uop_log_*.log` | Per-processor test prints, PERSPEC action start/end | `[PERSPEC] N` incrementing | Stuck, exception prints |
| `ptracker.log` | pCode firmware logging | Normal operations | RASSERT, timeout |
| `global*` | Power aspects (C-states, P-states, package power) | State transitions | Stuck states |
| `annotated_iosf_sb_jem_tracker.log` | IOSF sideband traffic | Continuous transactions | Large time gaps |
| `cbo_*` / `cdie_cbo_tracker_*` | CBO/CDie CBO cache coherency logs | Normal traffic | Missing data, errors |
| `hbo_*` | HBO (Home Base Object) logs | Clean operations | `hbo_aggr0 != 0` (error) |
| `cfi_trk.log` | CFI network traffic | Bi-directional flow | One-sided traffic, gaps |
| `fuse*` | Fuse values | Expected values | Unexpected/missing fuses |
| `bootfsm_state_tracker.log.gz` | Boot FSM state machine | Reaches final state | Stuck at INIT/SECURE/LINK |
| `testbench.log` | Testbench execution | No errors | Exception, error messages |
| `lip_tracker_*.log` | Subset of guop: cycles + LIPs executed | Continuous progress | Frozen LIP |
| `results.log` | Overall test result | `PASSED` | `FAILED` |
| `DEBUG` | Test failure details | Empty or no file | Contains exception/error info |
| `ddt_all_buckets.log(.gz)` | DDT failure bucketing signatures | No file (test passed) | Contains `Signature:` lines |

### 3. Phase-Specific Log Priorities

After detecting the phase, check these logs **in order** (highest priority first):

- **BUILD:**
  1. `build.log`
  2. `emurun.log`
  3. `compile.log`

- **EMU_SETUP:**
  1. `emurun.log`
  2. `PyDoh.*.log`
  3. `testbench.log`

- **RUNTIME:**
  1. `logbook.log`
  2. `emurun.log`
  3. `bootfsm_state_tracker.log.gz`
  4. `testbench.log`

- **TEST_EXECUTION:**
  1. `logbook.log`
  2. `emurun.log`
  3. `uop_log*.log`
  4. `testbench.log`
  5. `DEBUG`

- **POST_PROCESS:**
  1. `logbook.log`
  2. `assertion_failures.log`
  3. `zse_assertions.log`
  4. `ddt_all_buckets.log`

### 4. Logbook Stage Table Parsing

The **most reliable** method for phase detection is parsing the stage table in `logbook.log`. This table summarizes every stage of the test run with elapsed time, error/warning counts, and pass/fail status.

```bash
# Parse the stage table from logbook.log (plain text)
grep -A 10 "Stage.*Elapsed.*Status" logbook.log | tail -6

# Parse the stage table from compressed logbook
zgrep -A 10 "Stage.*Elapsed.*Status" logbook.log.gz | tail -6
```

**Example output:**
```
 Stage                                      Elapsed  Errors Warnings Status
Test build                                 00:30:22   0       0     PASS
Model run                                  48:42:13   0       1     PASS
Creating RPT                               00:26:55   0       0     PASS
Post processing                            00:00:04   0       0     PASS
```

**How to interpret:**
- Find the **first** stage with `FAIL` status — that is the failing phase.
- If all stages show `PASS` but the test still failed, the phase is `POST_PROCESS` (a validation/assertion issue that was not captured as a stage error).
- Non-zero `Warnings` with `PASS` status may still contain useful diagnostic information.

### 5. Symptom Extraction Rules

After determining the phase, scan the phase-specific logs for keywords. When a keyword match is found, expand the search into related logs using these conditional rules:

| If you find… | Then also search… | For keywords… |
|--------------|-------------------|---------------|
| `mailbox` or `timeout` | `pcode*`, `ptracker*` | request, response, command, status |
| `memory`, `corruption`, or `lpddr5` | `*lpddr*`, `*ddr*`, `*memss*` | read, write, timing, dfi, training |
| `boot`, `hang`, or `fsm` | `bootfsm*`, `*security*`, `cfi*` | state, secure, protocol, handshake |
| `sagv`, `dvfs`, or `pstate` | `*power*`, `*pstate*`, `*frequency*`, `global*` | frequency, voltage, transition, ratio |
| `exception` or `crash` | `uop_log*`, `guop*` | instruction, opcode, address, register, core |
| `protocol` or `d2d` | `cfi_trk*`, `*fabric*`, `iosf*` | transaction, header, payload, credit, flow |

**Usage pattern for an agent:**
1. Scan phase-priority logs for error/failure lines.
2. Extract keywords from those error lines.
3. Match keywords against the left column of the table above.
4. Expand search into the logs listed in the middle column, using the keywords from the right column.

### 6. uCode List File Locations

When tracing a stuck LIP (Last Instruction Pointer) or uCode execution issue, use these paths to look up the uCode source for the corresponding processor type:

- **Atom CDie:**
  ```
  $WORKAREA/soc/nvlsi7_n2p/cdie0/subip/hip/cdie_n2p_atomcpu/target/ucode/gen/ucode.ulst.clean
  ```

- **Atom HUB:**
  ```
  $WORKAREA/soc/nvlsi7_n2p/hub/subip/hip/hub_atomcpu/target/ucode/gen/ucode.ulst.clean
  ```

- **Big Core:**
  ```
  $WORKAREA/soc/nvlsi7_n2p/cdie0/subip/hip/cdie_n2p_core/target/common/gen/ucode/gen/ucode.ulst.clean
  ```

**How to use:** When a `guop_tracker` or `lip_tracker` log shows a processor stuck at a specific LIP address, grep the corresponding `.ulst.clean` file for that address to identify the uCode instruction being executed.

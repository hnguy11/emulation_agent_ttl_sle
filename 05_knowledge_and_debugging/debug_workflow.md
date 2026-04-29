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

---

## Full Triage Bash Commands

Runnable bash snippets for phased failure triage. All commands use standard `grep`/`zgrep` (no dependency on `log_scanner`). Run these from a test directory:
```
cd regression/nvlsi7_n2p/doa_pkg_ghpf_model_zse5.list.N/<test>/
```

### Method 1: logbook.log Stage Table Parsing (most reliable — 30 seconds max)

```bash
# Parse stage table from logbook.log
if [[ -f logbook.log.gz ]]; then
  echo "=== Phase Detection from logbook.log ==="
  zgrep -A 20 "Stage.*Elapsed.*Status" logbook.log.gz | tail -10
elif [[ -f logbook.log ]]; then
  grep -A 20 "Stage.*Elapsed.*Status" logbook.log | tail -10
fi

# Decision:
#   "Test build" FAIL       → PHASE: BUILD
#   "Model run" FAIL        → needs Method 2
#   "Post processing" FAIL  → PHASE: POST_PROCESS
#   All PASS but test FAIL  → PHASE: POST_PROCESS (validation issue)
```

### Method 2: emurun.log Analysis (fallback — 45 seconds max)

Use when logbook shows "Model run" FAIL or is unavailable.

```bash
echo "=== Checking emurun.log for phase clues ==="

# Build-related errors
BUILD_ERRORS=$(grep -i "force.*error\|compile.*fail\|syntax.*error\|cannot find.*file\|\.sv:\|\.v:\|vlog:" emurun.log 2>/dev/null | head -3)

# Plugin / setup errors
SETUP_ERRORS=$(grep -i "plugin.*fail\|plugin.*reported.*error\|LogScanner.*fail\|validator.*error" emurun.log 2>/dev/null | head -3)

# Runtime errors
RUNTIME_ERRORS=$(grep -i "timeout\|WMTRUN\|simulation.*stop\|fatal.*error" emurun.log 2>/dev/null | head -3)

if [[ -n "$BUILD_ERRORS" ]]; then
  echo "PHASE: BUILD"
  echo "Evidence: $BUILD_ERRORS"
elif [[ -n "$SETUP_ERRORS" ]]; then
  echo "PHASE: EMU_SETUP"
  echo "Evidence: $SETUP_ERRORS"
elif [[ -n "$RUNTIME_ERRORS" ]]; then
  echo "PHASE: RUNTIME or TEST_EXECUTION (needs Method 3)"
else
  echo "PHASE: TEST_EXECUTION (no errors in emurun.log)"
fi
```

### Method 3: Boot vs Test Execution Distinction (15 seconds max)

Use only when Method 2 identified runtime errors. Checks `bootfsm_state_tracker` to distinguish an incomplete boot (RUNTIME) from a DUT bug during test (TEST_EXECUTION).

```bash
echo "=== Distinguishing RUNTIME vs TEST_EXECUTION ==="

if [[ -f bootfsm_state_tracker.log.gz ]]; then
  LAST_BOOT_STATE=$(zcat bootfsm_state_tracker.log.gz | tail -n 1 | awk '{print $4}')

  if echo "$LAST_BOOT_STATE" | grep -q -i "INIT\|SECURE\|LINK\|TRAIN\|BOOT"; then
    echo "PHASE: RUNTIME (boot incomplete at $LAST_BOOT_STATE)"
  else
    echo "PHASE: TEST_EXECUTION (boot completed)"
  fi
elif [[ -f bootfsm_state_tracker.log ]]; then
  LAST_BOOT_STATE=$(tail -n 1 bootfsm_state_tracker.log | awk '{print $4}')
  echo "$LAST_BOOT_STATE" | grep -q -i "INIT\|SECURE\|LINK\|TRAIN\|BOOT" \
    && echo "PHASE: RUNTIME (boot incomplete)" \
    || echo "PHASE: TEST_EXECUTION (boot completed)"
else
  # No boot tracker — check for test execution markers
  if ls uop_log*.log &>/dev/null; then
    grep -q "\[PERSPEC\]" uop_log*.log 2>/dev/null \
      && echo "PHASE: TEST_EXECUTION (test started)" \
      || echo "PHASE: RUNTIME (no test execution detected)"
  else
    echo "PHASE: RUNTIME (assumed — no execution logs)"
  fi
fi
```

### Phase-Specific Quick Analysis Blocks

After detecting the phase, run the matching block below to collect symptoms.

#### BUILD (30 seconds max)

```bash
echo "=== BUILD Phase — Collecting Symptoms ==="
SYMPTOMS=""

FORCE_ERRORS=$(grep -i "force.*signal.*error\|force.*not.*found" emurun.log 2>/dev/null | head -2)
[[ -n "$FORCE_ERRORS" ]] && SYMPTOMS="$SYMPTOMS force_signal_error"

FILE_ERRORS=$(grep -i "no such file\|cannot find.*file\|path.*error" emurun.log 2>/dev/null | head -2)
[[ -n "$FILE_ERRORS" ]] && SYMPTOMS="$SYMPTOMS file_not_found"

SYNTAX_ERRORS=$(grep -i "syntax error\|compile.*fail\|vlog.*error" emurun.log 2>/dev/null | head -2)
[[ -n "$SYNTAX_ERRORS" ]] && SYMPTOMS="$SYMPTOMS compile_error syntax_error"

MISSING=$(grep -i "unknown signal\|module.*not found\|undefined" emurun.log 2>/dev/null | head -2)
[[ -n "$MISSING" ]] && SYMPTOMS="$SYMPTOMS missing_signal missing_module"

echo "BUILD Symptoms: $SYMPTOMS"
```

#### EMU_SETUP (30 seconds max)

```bash
echo "=== EMU_SETUP Phase — Collecting Symptoms ==="
SYMPTOMS=""

PLUGIN_ERRORS=$(grep -i "plugin.*fail\|plugin.*error" emurun.log 2>/dev/null | head -2)
[[ -n "$PLUGIN_ERRORS" ]] && SYMPTOMS="$SYMPTOMS plugin_failure"

[[ -f testbench.log ]] && {
  TB_ERRORS=$(grep -i "error\|fail\|exception" testbench.log 2>/dev/null | head -3)
  [[ -n "$TB_ERRORS" ]] && SYMPTOMS="$SYMPTOMS testbench_error"
}

VIP_ERRORS=$(grep -i "VIP.*fail\|VIP.*error" PyDoh*.log 2>/dev/null | head -2)
[[ -n "$VIP_ERRORS" ]] && SYMPTOMS="$SYMPTOMS vip_failure"

VALIDATOR_ERRORS=$(grep -i "validator.*fail\|LogScanner.*error" emurun.log 2>/dev/null | head -2)
[[ -n "$VALIDATOR_ERRORS" ]] && SYMPTOMS="$SYMPTOMS validator_failure"

echo "EMU_SETUP Symptoms: $SYMPTOMS"
```

#### RUNTIME (40 seconds max)

```bash
echo "=== RUNTIME Phase — Collecting Symptoms ==="
SYMPTOMS=""

# Boot state
if [[ -f bootfsm_state_tracker.log.gz ]]; then
  LAST_STATE=$(zcat bootfsm_state_tracker.log.gz | tail -n 1 | awk '{print $4}')
  SYMPTOMS="$SYMPTOMS boot_hang"
  echo "$LAST_STATE" | grep -q -i "SECURE" && SYMPTOMS="$SYMPTOMS security_state"
  echo "$LAST_STATE" | grep -q -i "LINK\|TRAIN" && SYMPTOMS="$SYMPTOMS link_training"
fi

# BFM warnings (protocol issues)
BFM_WARNINGS=$(grep -i "unsupported\|ignored\|warning" *BFM*.log 2>/dev/null | head -2)
[[ -n "$BFM_WARNINGS" ]] && SYMPTOMS="$SYMPTOMS bfm_warning protocol_mismatch"

# Timeout
TIMEOUT=$(grep -i "timeout\|WMTRUN" emurun.log 2>/dev/null | head -1)
[[ -n "$TIMEOUT" ]] && SYMPTOMS="$SYMPTOMS timeout"

echo "RUNTIME Symptoms: $SYMPTOMS"
```

#### TEST_EXECUTION (45 seconds max)

```bash
echo "=== TEST_EXECUTION Phase — Collecting Symptoms ==="
SYMPTOMS=""

# Exceptions
EXCEPTION=$(grep -i "exception\|exiting due to" DEBUG uop_log*.log 2>/dev/null | head -2)
if [[ -n "$EXCEPTION" ]]; then
  SYMPTOMS="$SYMPTOMS exception"
  echo "$EXCEPTION" | grep -q -i "page.*fault\|#PF" && SYMPTOMS="$SYMPTOMS page_fault"
  echo "$EXCEPTION" | grep -q -i "general.*protect\|#GP" && SYMPTOMS="$SYMPTOMS gp_fault"
fi

# Memory corruption
CORRUPTION=$(grep -i "0xdead\|memcheck\|corruption\|expected.*actual" DEBUG uop_log*.log 2>/dev/null | head -2)
[[ -n "$CORRUPTION" ]] && SYMPTOMS="$SYMPTOMS memory_corruption"

# DVFS / SAGV
DVFS=$(grep -i "dvfsq\|sagv" PyDoh.Sequence.log 2>/dev/null | tail -3)
[[ -n "$DVFS" ]] && SYMPTOMS="$SYMPTOMS dvfs sagv power_state"

# Mailbox timeout
MAILBOX=$(grep -i "mailbox.*timeout\|pcode.*timeout" DEBUG pcode_jem_tracker*.log* 2>/dev/null | head -2)
[[ -n "$MAILBOX" ]] && SYMPTOMS="$SYMPTOMS mailbox_timeout pcode"

echo "TEST_EXECUTION Symptoms: $SYMPTOMS"
```

#### POST_PROCESS (20 seconds max)

```bash
echo "=== POST_PROCESS Phase — Collecting Symptoms ==="
SYMPTOMS="post_process validation"

if [[ -f logbook.log.gz ]]; then
  VALIDATION=$(zgrep -A 5 "Post processing" logbook.log.gz | grep -i "error\|fail")
  [[ -n "$VALIDATION" ]] && echo "Validation failure: $VALIDATION"
elif [[ -f logbook.log ]]; then
  VALIDATION=$(grep -A 5 "Post processing" logbook.log | grep -i "error\|fail")
  [[ -n "$VALIDATION" ]] && echo "Validation failure: $VALIDATION"
fi

SYMPTOMS="$SYMPTOMS checker_fail"
echo "POST_PROCESS Symptoms: $SYMPTOMS"
```

---

## I Feel Lucky Scoring Algorithm

Automated scoring system that ranks BUG files against a detected failure. Given a phase and symptom list, each BUG file is scored using the weighted signals below and the highest-scoring BUG is recommended.

### Signal Weights

| Signal | Weight | Description |
|--------|--------|-------------|
| Exact tag match | **+50 pts** | BUG file tag exactly matches DDT bucket |
| Category match | **+30 pts** | BUG file category matches failure type |
| Partial tag match | **+25 pts** | ≥50% token overlap with failure symptoms |
| Critical symptom | **+10 pts** | High-priority error terms (timeout, hang, crash) |
| Phase match | **+5 pts** | BUG file phase matches detected failure phase |
| **Phase mismatch** | **×0.5 penalty** | Wrong phase **halves** the entire score |
| Regular symptom | **+3 pts** | Standard symptom match |

### Confidence Thresholds

| Score Range | Confidence | Typical Pattern |
|-------------|------------|-----------------|
| ≥ 200 | **VERY HIGH** | 3+ exact tag matches + phase match |
| 100–199 | **VERY HIGH** | 2 exact matches + partials |
| 50–99 | **HIGH** | 1 exact match + symptoms |
| 30–49 | **MEDIUM** | Category match + symptoms |
| 15–29 | **MEDIUM** | Symptom-only matches |
| < 15 | **LOW** | Minimal match |

### Phase Mismatch Warning

> ⚠️ If a BUG file's phase does **not** match the detected phase, the entire score is **halved** (×0.5).
> This is the #1 reason good matches get missed — always verify phase before trusting a score.

```
Example:
  BUG-045 base score = 120 pts
  Detected phase = RUNTIME, BUG-045 phase = POST_PROCESS
  Final score = 120 × 0.5 = 60 pts  →  drops from rank #1 to rank #5+
```

### Real-World NVL-AX Example

**Scenario:** `spacedoa_mobile` fails with exit code 66.

| Step | Detail |
|------|--------|
| Detected phase | `RUNTIME` (Kerberos expired before emulation could connect) |
| Matching BUG file | `BUG-033` — Kerberos ticket expiry |
| BUG-033 phase | `RUNTIME` ✅ |
| BUG-033 symptoms | `kerberos expired rsync ssh` |

**Score breakdown:**

| Signal | Points |
|--------|--------|
| Phase match | +5 |
| Exact tag `kerberos` | +50 |
| Critical symptom `expired` | +10 |
| **Total** | **65 pts → HIGH confidence** |

### How to Use

For automated scoring, run the phase-detection + scoring script:

```bash
cd regression/nvlsi7_n2p/doa_pkg_ghpf_model_zse5.list.N/<test>/
../../scripts/run_phase_detection_nvlax.sh
```

The script outputs ranked BUG files with scores and confidence levels. See `run_phase_detection_nvlax.sh` for implementation details.

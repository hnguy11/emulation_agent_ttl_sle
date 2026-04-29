---
title: "AI Behavioral Guidelines"
module: 01_agent_core
tags: [ai, guidelines, behavior, documentation, context]
---

# AI Behavioral Guidelines

## Documentation Mandate

> **RULE #1: Document everything. Documentation is part of the fix, not an afterthought.**

### What to Document
- Every shell command you run and its output (success or failure)
- Every fix you apply — exact commands, exact file paths, exact diffs
- Every workaround discovered — even temporary ones
- Every new pattern or failure mode encountered
- Every command the user teaches you that works

### Where to Document
| What | Where |
|------|-------|
| New bug/fix | `05_knowledge_and_debugging/known_bugs_and_fixes/BUG-NNN_description.md` |
| New shell command | `02_execution/commands_reference.md` |
| New failure pattern | `05_knowledge_and_debugging/common_patterns.md` |
| Build session log | Bottom of `02_execution/build_flow.md` (append) |
| Test results | `03_testing_and_validation/test_suites.md` (update status) |

### When to Document
- **Immediately** — as soon as a command works or a fix is verified
- NOT at the end of the session
- NOT after a checkpoint
- RIGHT NOW, while the context is fresh

## Command Discovery Protocol

When you encounter a situation where you don't know the correct shell command:

1. **DO NOT GUESS** — Intel infrastructure has non-standard tools, paths, and conventions
2. **ASK THE USER**: "I need to do X. What's the correct command on this system?"
3. **When the user provides the command**: Run it, verify it works
4. **DOCUMENT IT**: Add to `02_execution/commands_reference.md` with:
   - The exact command
   - What it does
   - When to use it
   - Expected output / success criteria

## Contextual Hints

### Build System
- `grdlbuild` wraps Gradle → DVB → Make → Zebu tools
- Shadow files in `.shadow/` track completed stages — presence = done
- `-id` flag = `-Pignore_deps` = skip upstream tasks (safe for mid-build restarts)
- `fe_be` is the longest stage (~25h) — FPGA place-and-route for 192 FPGAs

### Test System
- `simregress` → T-REX → emurun → FM netbatch → Zebu hardware
- DOA tests: `spacedoa_mobile` (50ms cycle limit) + `spacex_mobile` (240ms, completes at ~135ms)
- FM boards: ZSE5 machines at Folsom (fmez5xxx), accessed via NB express queues
- Logbook freezes during active emulation (BUG-030) — this is NORMAL

### Critical DOA Test Rules
- **EMUL_QSLOT**: ALWAYS use `/prj/sv/nvl/emu/interactive` — NEVER `/prj/sv/nvl/showstopper` (see BUG-025: showstopper has `user_max_waiting=2` which blocks simultaneous DOA jobs)
- **simregress command** — use EXACTLY this (do not modify flags without user approval):
  ```bash
  simregress -dut nvlsi7_n2p -save -no_xs -trex -emu_model pkg_ghpf_model -emu_tech zse5 \
    -no_compress EMUL_QSLOT=/prj/sv/nvl/emu/interactive -trex- \
    -P zsc11_express -Q /IVE/NVL/emu \
    -l reglist/nvlsi7_n2p/emu/doa_pkg_ghpf_model_zse5.list
  ```
- **NEVER use `-local` flag** for DOA tests — Zebu hardware requires NB farm submission (see BUG-001)
- **ALWAYS pass `-P zsc11_express -Q /IVE/NVL/emu`** explicitly — omitting causes queue collision (see BUG-003)

### Common Gotchas
- `output/` may be a symlink to a GK build (read-only) — check permissions first
- SLES15 machines don't have old tool versions (python3.7.4, perl 5.14.1) — fix shebangs
- `LD_PRELOAD` doesn't work in Simics module namespace — use RPATH + co-location
- FM gecco environment doesn't honor `LD_LIBRARY_PATH` additions from plugins
- Kerberos tickets expire after ~24h — renew with `kinit -R` for long queue waits

## Session Startup Checklist
1. Read `00_index.md` (this is done by reading this file)
2. Check disk space: `df -h /nfs/site/disks/ive_sle_zsc11_tbaziza | tail -1`
3. Check Kerberos: `klist 2>&1 | grep -E "Expires|>>>"`
4. Check what's running: `nbq -u tbaziza 2>/dev/null | head -10`
5. Check last build status: `ls output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/.shadow/ | wc -l` (19 = complete)

## Expert Debug Heuristics (Extracted from ai_picker_sle Reference)

### 1. The Golden Rule: "Know WHERE Before WHAT"

Most triage failures occur because the agent tries to find root cause before identifying which phase failed. **ENFORCE** this staged approach:

1. **Phase Detection** (90 seconds max) → Answer ONE question: "Which phase failed?"
   - Output: `BUILD` | `EMU_SETUP` | `RUNTIME` | `TEST_EXECUTION` | `POST_PROCESS`
2. **Symptom Collection** (60 seconds max) → Extract key symptoms from that phase's logs
3. **Methodology Search** (30 seconds max) → Match symptoms to known patterns

**Total: 3 minutes to methodology selection. NEVER skip phase detection.**

### 2. Phase Detection Reasoning

Classify the failure phase using this decision tree:

- `cat results.log` → PASSED? Done. FAILED? → Continue
- `logbook.log` stage table → most reliable source. Parse "Stage ... Status" table
- If logbook unavailable → `grep -i "error|fail|fatal" emurun.log`:
  - `force.*error`, `compile.*fail` → **BUILD**
  - `plugin.*fail`, `LogScanner.*error` → **EMU_SETUP**
  - `timeout`, `WMTRUN`, `simulation.*stop` → **RUNTIME** (check if boot completed)
  - No errors → **TEST_EXECUTION**
- If RUNTIME suspected → check `bootfsm_state_tracker.log.gz`:
  - Last state = INIT/SECURE/LINK/TRAIN → **RUNTIME** (boot incomplete)
  - Last state = operational → **TEST_EXECUTION** (boot completed, test failed)

### 3. Symptom Extraction Conditional Rules

When initial symptoms are found, search deeper in related logs:

```
IF symptom contains "mailbox" or "timeout":
  → SEARCH pcode*, ptracker* FOR: request, response, command, status, interface

IF symptom contains "memory", "corruption", or "lpddr5":
  → SEARCH *lpddr*, *ddr*, *memss* FOR: read, write, timing, dfi, training, alignment

IF symptom contains "boot", "hang", or "fsm":
  → SEARCH bootfsm*, *security*, cfi* FOR: state, secure, protocol, handshake, link

IF symptom contains "sagv", "dvfs", or "pstate":
  → SEARCH *power*, *pstate*, *frequency*, global* FOR: frequency, voltage, transition, ratio

IF symptom contains "exception" or "crash":
  → SEARCH uop_log*, guop* FOR: instruction, opcode, address, register, core

IF symptom contains "protocol", "d2d", or "ucie":
  → SEARCH cfi_trk*, *fabric*, iosf* FOR: transaction, header, payload, credit, flow
```

### 4. 2-Minute Drill Patterns

Quick triage patterns by failure bucket (from reference):

#### Boot Hang Drill (2 min)

1. Where stuck? → `tail bootfsm_state_tracker.log.gz` (10s)
2. What waiting for? → `cat waitings.log` (10s)
3. Last protocol activity → `grep "Time:" iosf_sb_jem_tracker.log.gz | tail -10` (20s)
4. Time gap calculation: if GAP > 100K ps → Protocol deadlock (30s)
5. BFM warnings? → `grep "unsupported|ignored" *BFM.log` (30s)
6. Check configuration mismatch (20s)

#### Memory Corruption Drill (2 min)

1. Get exception details → `cat DEBUG | grep "exception|rip:"` (15s)
2. Check DVFS correlation → `grep "dvfsq" PyDoh.Sequence.log | tail -5` (20s)
3. Data mismatch pattern → `cat DEBUG | grep "expected|actual|read data"` (15s)
4. If exception + DVFSQ → SAGV timing violation pattern
5. If read returns zeros → LPDDR5 signal alignment pattern

#### TLM_POST Failure Drill (2 min)

1. Check if emulation PASSED but test FAILED → multi-stage deception pattern
2. Check TLM_POST stage specifically in logbook stage table
3. Check `assertion_failures.log`, `zse_assertions.log`
4. If SVA error → see SVA post-processing methodology

### 5. Methodology Scoring Logic

When multiple debug approaches exist, score them:

| Factor | Points |
|--------|--------|
| **Phase match** | +5 points (methodology phase matches detected failure phase) |
| **Symptom match** | +1 point per symptom found in logs |
| **Tracker match** | +50 points for exact DDT bucket match |
| **Phase mismatch penalty** | ×0.5 (halves entire score) |

Confidence levels:

- **8+ points** → VERY HIGH (trust this methodology)
- **5–7 points** → HIGH (strong candidate)
- **3–4 points** → MEDIUM (partial match, read but verify)
- **1–2 points** → LOW (likely irrelevant)

### 6. False Lead Avoidance

Common traps from the reference — do NOT fall for these:

- **Trap:** MCA error looks like root cause → Actually just a symptom of an upstream issue
- **Trap:** `emurun.log` says PASSED → But TLM_POST/SVA post-processing caught assertion errors (multi-stage test)
- **Trap:** "Error" in log → Some "error" strings are informational (check surrounding context)
- **Trap:** First error in log → May not be root cause; check temporal ordering across logs
- **Trap:** CPU exception → May be caused by memory corruption from SAGV/DVFS, not an instruction issue

### 7. MCA Register Decode Heuristic

When MCA (Machine Check Architecture) errors appear:

- `mc_misc` register: lower 32 bits = `source_location`
  - `bits[31:16]` = `file_hash_short` (identifies source file)
  - `bits[15:0]` = `line_number`
- To find the source file: hash all pCode source filenames and match `file_hash_short`
- pCode source root: check `$WORKAREA` for IP release path
- Use `find_rassert_source.py` pattern to decode RASSERT locations

### 8. Environment Variables for Debug Context

Extract from `.trex.env` in any test directory:

- `TESTNAME` — the test being run
- `WORKAREA` — the build workspace root path
- `CTH_TOOL_OVERRIDE_FILE_MAESTRO` — Maestro tool override file path

These provide crucial context for understanding test intent and build configuration. Always check `.trex.env` early in any debug session.

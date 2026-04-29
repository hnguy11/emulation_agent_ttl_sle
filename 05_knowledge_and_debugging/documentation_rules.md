---
title: "Documentation Rules &amp; Standards"
module: 05_knowledge_and_debugging
tags: [documentation, standards, rules, writing, bugs]
---

# Documentation Rules &amp; Standards

## Core Principle
> **Documentation is a byproduct of work, not a separate task.**
> Every fix you apply generates a document. Every command you discover gets recorded.
> The goal: the NEXT AI session should be able to apply any fix in under 60 seconds.

## Bug Documentation

### When to Create a Bug File
- Any new error you encounter and solve
- Any workaround you apply (even temporary)
- Any informational observation that prevents future mistakes (e.g., BUG-030)
- Any infrastructure issue that blocks work (e.g., BUG-034)

### File Naming Convention
```
BUG-NNN_short_snake_case_description.md
```
Examples:
- `BUG-035_new_shebang_error.md`
- `BUG-036_fm_board_timeout.md`

### Required Sections
Every bug file MUST use the template from `bug_template.md`:
1. **YAML Frontmatter** — metadata for RAG (bug_id, status, severity, category, tags)
2. **Symptom** — exact error message text (copy-paste from logs)
3. **Root Cause** — why it happens (technical explanation)
4. **Fix / Solution** — exact commands to run (copy-paste ready)
5. **Files Affected** — list of files changed
6. **Verification** — how to confirm the fix worked
7. **Notes** — additional context, caveats, prevention

## Command Documentation

### When to Add a Command
- Any shell command you discover that solves a problem
- Any command the user teaches you
- Any monitoring/diagnostic command that proves useful

### Format (in `commands_reference.md`)
| Command | What It Does | When To Use |

## Pattern Documentation

### When to Update `common_patterns.md`
- New bug matches an existing pattern → add bug reference
- New bug reveals a new category → create new Pattern entry
- Existing pattern needs updated advice → edit the pattern

### Pattern Format
```
## Pattern N: Short Name
- **Symptom**: What you see
- **Cause**: Why it happens
- **General Fix**: How to fix it
- **Related Bugs**: BUG-NNN, BUG-MMM
```

## Quality Checks
- [ ] Every bug file has YAML frontmatter
- [ ] Error messages are exact (copy-pasted, not paraphrased)
- [ ] Fix commands are copy-paste ready (absolute paths where needed)
- [ ] Verification step is included
- [ ] Related patterns are cross-referenced

## Methodology Creation Protocol

When a novel failure is encountered (no existing BUG file or common pattern matches), follow this 6-step creation flow adapted from the ai_picker_sle methodology system:

### Step 1: Gather Evidence
Read the test logs and extract:
- Primary symptom (the error that made the test fail)
- Root cause (why it happened — determined through debug)
- Trigger pattern (exact log strings that identify this failure)
- Log files used (which logs were critical for diagnosis)

### Step 2: Check Existing KB
Before creating a new file, search:
```bash
grep -rl "symptom_keyword" /nfs/site/disks/ive_sle_zsc11_tbaziza/NVL_AX_agent_workspace/05_knowledge_and_debugging/known_bugs_and_fixes/
grep -i "symptom_keyword" /nfs/site/disks/ive_sle_zsc11_tbaziza/NVL_AX_agent_workspace/05_knowledge_and_debugging/common_patterns.md
```
If a match exists → update the existing file rather than creating a duplicate.

### Step 3: Create Bug File with Scoring Headers
Use `bug_template.md` and MUST include:
- `phase:` — the failure phase (BUILD/EMU_SETUP/RUNTIME/TEST_EXECUTION/POST_PROCESS)
- `symptoms:` — 5-10 keywords from the error logs
- `keywords:` — 3-5 high-level concepts
- `trackers:` — log files where symptoms appear

### Step 4: Validate Scoring
Run the phase detection script against the original failing test:
```bash
/nfs/site/disks/ive_sle_zsc11_tbaziza/NVL_AX_agent_workspace/05_knowledge_and_debugging/run_phase_detection_nvlax.sh <test_directory>
```
The new bug file should rank in the **top 3** for its source test failure.

### Step 5: Update Pattern Database
If the failure is generalizable, add a new entry to `common_patterns.md`:
```markdown
## Pattern N: Short Name
- **Symptom**: What you see
- **Cause**: Why it happens
- **General Fix**: How to fix it
- **Related Bugs**: BUG-NNN
```

### Step 6: Cross-Reference
- Update `commands_reference.md` if new commands were discovered
- Add links from the new bug file to related bugs
- Commit changes to git with descriptive message

### Symptom Selection Guidelines

**Good symptoms** (specific, searchable):
- Error codes: `0xdead`, `0x90`, `exit_66`
- Component names: `mailbox`, `lpddr5`, `cfi`, `bootfsm`
- Failure modes: `timeout`, `hang`, `corruption`, `mismatch`
- Test-specific: test name keywords

**Bad symptoms** (too generic, match everything):
- `error`, `fail`, `test`, `issue`, `problem`

**Optimal count**: 5-10 symptoms per bug file

### Phase Selection Guide

| When does the failure occur? | Phase |
|------------------------------|-------|
| Before simulation starts (compilation, testbench setup) | `BUILD` |
| Simulation setup (plugin loading, VIP init) | `EMU_SETUP` |
| During boot (boot FSM, security handshake) | `RUNTIME` |
| After boot, during test code execution | `TEST_EXECUTION` |
| After test ends (validation, checkers, SVA) | `POST_PROCESS` |

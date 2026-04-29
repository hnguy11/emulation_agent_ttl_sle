---
title: "NVL-AX Agent Workspace — Index &amp; Routing Guide"
version: "1.0"
project: NVL-AX
platform: ZSE5 Zebu Emulation
dut: nvlsi7_n2p
model: pkg_ghpf_model
last_updated: "2026-04-29"
tags: [index, routing, entry-point, agent-instructions]
---

# NVL-AX Agent Workspace — Index &amp; Routing Guide

> **READ THIS FILE FIRST.** This is the single entry point for the NVL-AX Integration Loop knowledge base.
> It replaces the monolithic `compilation_bugs.md` with a modular, searchable structure.

## Purpose

This workspace contains all accumulated knowledge for compiling, testing, debugging, and monitoring
the `pkg_ghpf_model` Zebu ZSE5 emulation model for the `nvlsi7_n2p` DUT. It is designed for:
- **AI agents** (Copilot CLI, autonomous integration assistants) — optimized for RAG retrieval
- **Human engineers** — structured for rapid lookup and troubleshooting

## Quick-Start Routing Table

| What You Need | Go To |
|---------------|-------|
| Compile the model | `02_execution/build_flow.md` |
| Environment setup (paths, tools, env vars) | `02_execution/environment.md` |
| Shell command reference | `02_execution/commands_reference.md` |
| Run DOA emulation tests | `03_testing_and_validation/test_suites.md` |
| Set up the ZeBu emulator | `03_testing_and_validation/setup_emulator.md` |
| Pre-handoff quality checks | `03_testing_and_validation/quality_checklist.md` |
| Monitor a long-running build/test | `04_monitoring/metrics_definition.md` |
| Something seems stuck/hung | `04_monitoring/alert_thresholds.md` |
| Debug a build/test failure | `05_knowledge_and_debugging/debug_workflow.md` |
| Auto-detect failure phase | `05_knowledge_and_debugging/run_phase_detection_nvlax.sh` |
| Expand symptoms from logs | `05_knowledge_and_debugging/symptom_rules.txt` |
| Search known bugs | `05_knowledge_and_debugging/known_bugs_and_fixes/` (34 files) |
| Recognize a failure pattern | `05_knowledge_and_debugging/common_patterns.md` |
| Document a new bug | `05_knowledge_and_debugging/bug_template.md` + `documentation_rules.md` |

## Directory Structure

```
NVL_AX_agent_workspace/
├── 00_index.md                          # THIS FILE — entry point &amp; routing
├── 01_agent_core/                       # Agent identity &amp; behavioral rules
│   ├── identity_and_safety.md           # Role, goals, red lines
│   └── ai_guidelines.md                # Behavioral rules, documentation mandate
├── 02_execution/                        # Build &amp; command execution
│   ├── build_flow.md                    # Step-by-step compilation &amp; resume
│   ├── environment.md                   # NFS paths, tools, env variables
│   └── commands_reference.md            # Shell commands index
├── 03_testing_and_validation/           # Emulation &amp; DOA testing
│   ├── setup_emulator.md                # ZeBu emulator deployment
│   ├── test_suites.md                   # DOA test execution guide
│   └── quality_checklist.md             # Final validation before handoff
├── 04_monitoring/                       # Real-time pipeline monitoring
│   ├── metrics_definition.md            # What to monitor (CPU, mem, logs)
│   └── alert_thresholds.md              # When to intervene
└── 05_knowledge_and_debugging/          # Living knowledge base
    ├── debug_workflow.md                # Log analysis, phase detection &amp; triage
    ├── common_patterns.md               # 21 recurring failure categories
    ├── documentation_rules.md           # Standards + methodology creation protocol
    ├── symptom_rules.txt               # Conditional symptom extraction config
    ├── run_phase_detection_nvlax.sh    # Automated phase detection script
    └── known_bugs_and_fixes/            # 34 individual bug reports
        ├── bug_template.md              # Template with scoring headers
        └── BUG-001..034_*.md            # One file per bug
```

## AI Agent Instructions — MANDATORY

> **These rules are NON-NEGOTIABLE for any AI agent operating in this workspace.**

### Before Starting ANY Task
1. **Read this file FIRST** — route to the correct module before doing anything
2. **Search `known_bugs_and_fixes/` BEFORE debugging from scratch** — if a fix already exists, USE IT
3. **Read `common_patterns.md`** — the error you're seeing likely matches a known pattern

### During the Session
4. **Document EVERYTHING immediately** — every command you run, every fix you apply, every workaround you discover. Documentation is NOT optional — it is part of the fix. Do NOT wait until the end of the session.
5. **If you don't know a shell command, ASK THE USER** — never guess or hallucinate commands, paths, or tool options. When the user provides a command and it works, document it immediately in `02_execution/commands_reference.md` for future sessions.
6. **Monitor disk space continuously** during compilation — see `04_monitoring/metrics_definition.md`

### After Solving a Problem
7. **Create a new bug file** in `known_bugs_and_fixes/` using `bug_template.md` — include exact error text, exact fix commands, files affected, and verification steps so the NEXT AI session can apply the fix in seconds
8. **Update `common_patterns.md`** if the bug fits an existing pattern or reveals a new one
9. **Update `commands_reference.md`** if you used a new command that worked
10. **Never remove old entries** — even resolved bugs are valuable historical context

### Red Lines
11. **Never delete source files** without backing them up first
12. **Never modify files in `01_agent_core/`** without explicit user approval
13. **Never guess at Intel-specific paths or tool versions** — ask the user
14. **Always verify fixes** before marking a bug as resolved

<div align="center">

# 🤖 NVL-AX Compilation Agent

**An AI-powered agent that compiles, tests, debugs, and fixes NVL-AX ZeBu ZSE5 emulation models — end to end.**

[![Agent](https://img.shields.io/badge/Copilot_CLI-Agent-blue?style=for-the-badge&logo=github)](https://github.com/tbaziza/NVL_AX_agent_workspace)
[![Bugs](https://img.shields.io/badge/Known_Bugs-57-orange?style=for-the-badge)](05_knowledge_and_debugging/known_bugs_and_fixes/)
[![Status](https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge)]()

</div>

---

## ⚡ Quick Start

```bash
# 1. Go to your model workarea
cd <your_model_workarea>

# 2. Launch Copilot CLI
copilot

# 3. Select the agent
/agent sle_emulation_agent

# 4. Start working
You: compile the model
```

That's it. You're ready to go.

---

## 🎯 What Can I Ask?

### 🔨 Compilation
| Prompt | What it does |
|--------|-------------|
| `compile the model` | Start a fresh grdlbuild |
| `resume the build` | Continue a build with `-id` |
| `check if compilation passed` | Run the 6 pass checks |

### 🔧 Post-Build
| Prompt | What it does |
|--------|-------------|
| `run post-build steps` | Run post_zcui + fix_zse5_libs.sh |

### 🧪 Testing
| Prompt | What it does |
|--------|-------------|
| `run DOA tests` | Submit spacedoa/spacex via simregress |
| `check if the test passed` | Run the 5 pass checks |
| `check test status in <path>` | Verify a specific test workarea |

### 🐛 Debugging
| Prompt | What it does |
|--------|-------------|
| `debug this failure` | Full triage: phase detection → symptoms → bug matching |
| `debug the build failure` | Analyze grdlbuild errors |
| `debug the test in <path>` | Analyze a specific DOA test failure |
| `search known bugs for <error text>` | Search the 57 BUG files |
| `what known bugs match <symptom>?` | Find matching bugs by keyword |

### 📋 Status & Info
| Prompt | What it does |
|--------|-------------|
| `what build stage are we on?` | Check .shadow progress |
| `show the build stages` | List all 14 stages |
| `what DOA tests are available?` | List test options |
| `show safety rules` | Review the red lines |

### 🔄 Full Workflow
| Prompt | What it does |
|--------|-------------|
| `compile, test, and debug until it passes` | End-to-end loop |

---

## 🔄 How It Works

```mermaid
flowchart TD
    START([🚀 Start]) --> COMPILE

    COMPILE["🔨 STEP 1 — COMPILE\n━━━━━━━━━━━━━━━━━━━━━\ngrdlbuild\n14 build stages · ~50 hrs\n6 pass checks"]
    COMPILE -->|"✅ pass"| POSTBUILD

    POSTBUILD["🔧 STEP 2 — POST-BUILD\n━━━━━━━━━━━━━━━━━━━━━\npost_zcui\nlibrary symlink repair"]
    POSTBUILD --> TEST

    TEST["🧪 STEP 3 — DOA TEST\n━━━━━━━━━━━━━━━━━━━━━\nsimregress\nspacedoa / spacex · ~4-5 hrs\n5 pass checks"]
    TEST -->|"✅ all stages PASS"| DONE

    COMPILE -->|"❌ fail"| DEBUG
    TEST -->|"❌ fail"| DEBUG

    DEBUG["🐛 STEP 4 — DEBUG\n━━━━━━━━━━━━━━━━━━━━━\n1. Detect failure phase\n2. Collect symptoms from logs\n3. Search 57 known bugs\n4. Score & match best fix"]
    DEBUG -->|"🔁 fix applied — re-run"| COMPILE

    DONE([🎉 Model Ready])

    style COMPILE fill:#0d3b66,stroke:#4a9eff,stroke-width:3px,color:#fff
    style POSTBUILD fill:#1b4332,stroke:#6abf69,stroke-width:3px,color:#fff
    style TEST fill:#5c3d0e,stroke:#f0ad4e,stroke-width:3px,color:#fff
    style DEBUG fill:#6b1d1d,stroke:#ff6b6b,stroke-width:3px,color:#fff
    style DONE fill:#1b6b1b,stroke:#5cb85c,stroke-width:3px,color:#fff
    style START fill:#333,stroke:#aaa,stroke-width:2px,color:#fff

    linkStyle 4 stroke:#ff4444,stroke-width:2px,stroke-dasharray:5
    linkStyle 5 stroke:#ff4444,stroke-width:2px,stroke-dasharray:5
    linkStyle 6 stroke:#ff4444,stroke-width:2px,stroke-dasharray:5
```

---

## 🛡️ Safety Guarantees

| Rule | Detail |
|------|--------|
| 🚫 No showstopper queue | Always uses `/prj/sv/nvl/emu/interactive` |
| 🚫 No `-local` flag | Prevents silent failures (BUG-001) |
| 🚫 No mid-run resubmits | Waits for full PASS/FAIL before acting |
| ✅ Full logbook checks | emurun PASS ≠ overall PASS |
| ✅ Always asks first | Never auto-commits to git |

---

## 📂 Knowledge Base

```
📁 NVL_AX_agent_workspace/
├── 📄 00_index.md                          ← Start here
├── 📁 01_agent_core/                       ← Identity, safety rules, AI guidelines
├── 📁 02_execution/                        ← Build commands, environment setup
├── 📁 03_testing_and_validation/           ← DOA tests, emulator setup, quality gates
├── 📁 04_monitoring/                       ← Metrics, alert thresholds
├── 📁 05_knowledge_and_debugging/          ← Debug workflow, symptom rules
│   ├── 📁 known_bugs_and_fixes/            ← 57 bug files (BUG-001 to BUG-057)
│   ├── 🔧 run_phase_detection_nvlax.sh     ← Automated bug matcher
│   └── 📄 symptom_rules.txt                ← Keyword expansion rules
└── 📁 copilot_cli_agent/                   ← Agent instruction files backup
```

---

## 🔍 Verify Setup

Inside Copilot CLI, run these commands:

```
/agent              → should show sle_emulation_agent
/instructions       → should show 4 loaded files
/env                → should show instruction paths
```

---

## 👥 Contributors

| User | Role |
|------|------|
| tbaziza | Owner |
| michaeleldin | Editor |
| mtzola | Reader |
| vmeskin | Reader |

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
/agent nvlax-compiler

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

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Step 1      │    │  Step 2      │    │  Step 3      │    │  Step 4      │
│  COMPILE     │───▶│  POST-BUILD  │───▶│  DOA TEST    │───▶│  DEBUG       │
│  grdlbuild   │    │  post_zcui   │    │  simregress  │    │  57 bugs KB  │
│  6 checks ✓  │    │  fix_libs ✓  │    │  5 checks ✓  │    │  auto-match  │
└─────────────┘    └─────────────┘    └─────────────┘    └──────┬──────┘
                                                                │
                                           fix applied ◀────────┘
                                           re-run from Step 1 or 3
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
/agent              → should show nvlax-compiler
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

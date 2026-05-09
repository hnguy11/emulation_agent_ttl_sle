<div align="center">

# 🤖  SLE Emulation Agent

**An AI-powered agent that compiles ZeBu ZSE5 and FPGA emulation models, monitors build progress, debugs build failures, and applies fixes — for TTLbx and TTLhm.**

[![Agent](https://img.shields.io/badge/Copilot_CLI-Agent-blue?style=for-the-badge&logo=github)](https://github.com/tbaziza/emulation_agent)
[![Bugs](https://img.shields.io/badge/Known_Bugs-57-orange?style=for-the-badge)](05_knowledge_and_debugging/known_bugs_and_fixes/)
[![Status](https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge)]()

</div>

---

## 📦 First-Time Setup

> **One-time install — do this once per environment.**

### Step 1: Clone the Knowledge Base

```bash
git clone https://github.com/hnguy11/emulation_agent_ttl_sle.git
```

### Step 2: Run the init script

```bash
bash emulation_agent_ttl_sle/copilot_cli_agent/init_agent.sh
```

The script will:
1. **Ask for your working disk path** — enter the path to your large project disk (e.g. `/nfs/site/disks/issp_ttl_emu_compile_001`). This is NOT the model workarea, just your general working disk.
2. **Move your Copilot agents** to the working disk (avoids NFS home quota issues) and create a symlink back at `~/.copilot/agents`
3. **Install the `sle_emulation_agent`** into the agents directory with `KB_ROOT` pre-configured

### Step 3: Done — load the agent

Once the script prints **✅ Setup Complete!**, the agent is ready. Launch Copilot CLI and select it:

```bash
/p/hdk/cad/copilot/latest/copilot
/agent sle_emulation_agent
```

> 💡 **To update later**, `git pull` inside `emulation_agent_ttl_sle/` and re-run `init_agent.sh` with the same working disk path.

---

## ⚡ Quick Start (Daily Use)

```bash
# 1. Go to your model workarea
cd <your_model_workarea>

# 2. Set up the model environment
cth_psetup <your_stepping>

# 3. Launch Copilot CLI
/p/hdk/cad/copilot/latest/copilot

# 4. Select the agent
/agent sle_emulation_agent

# 5. Start working
You: compile the model
```

> ⚠️ **You must run `cth_psetup` before launching Copilot CLI.** The agent relies on the environment it configures.

---

## 🎯 Supported Models

| Model | Type | Platform | Build Command |
|-------|------|----------|--------------|
| **Converged TTLbx** | ZSE5 + FPGA | ttlbx | `grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse ttlbx_n2p:emu:sle:pkg_chpr_cfgr_p2e0_816_fast_zse ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs -nb` |
| `pkg_chpr_p2e4_816_fast` | ZSE5 | ttlbx | `grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse -nb` |
| `pkg_chpr_cfgr_p2e0_816_fast` | ZSE5 | ttlbx | `grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_cfgr_p2e0_816_fast_zse -nb` |
| `pkg_chpr_cfgr_p2e0_816_fast` | FPGA slimsim | ttlbx | `grdlbuild ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs -nb` |
| `pkg_chpr_p2e4_816_fast` | ZSE5 | ttlhm | `grdlbuild ttlhm_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse -nb` |

> **Converged TTLbx** launches all 3 TTLbx targets in a single `grdlbuild` call, sharing common dependency stages. TTLhm has only one target — no converged option.

### Build Types

The agent handles two fundamentally different build types — the target suffix and output path are the key signals:

| Build Type | Target suffix | Output path | Orchestrator | Duration |
|------------|--------------|-------------|-------------|---------|
| **ZeBu / ZSE5** | `emu:sle:..._zse` | `output/.../zebu_zebu/` | zCui | ~25-50 hrs |
| **FPGA slimsim** | `emu:fpga:..._vcs` | `output/.../fpgasim_emuvcs/` | VCS | ~2-5 hrs |

The agent uses different logs, failure signals, monitoring scripts, and debug commands depending on build type. It always identifies the type from the grdlbuild target before running any commands.

---

## 🔄 Typical Workflow

The agent follows this loop until the model compiles successfully:

```mermaid
flowchart TD
    START([🚀 Start]) --> SETUP

    SETUP["⚙️ SESSION SETUP\n━━━━━━━━━━━━━━━━━━━━━\n1. Autopilot mode\n2. Permission level\n3. Monitoring preference\n4. Which model"]
    SETUP --> COMPILE

    COMPILE["🔨 STEP 1 — COMPILE\n━━━━━━━━━━━━━━━━━━━━━\ngrdlbuild ... -nb\n14 build stages · ~50 hrs\nMonitor progress"]
    COMPILE --> MIDCHECK

    MIDCHECK["⏱️🔌 MID-BUILD CHECKS\n━━━━━━━━━━━━━━━━━━━━━\nZSE5: driverClk in zTime.log ≥ 200 kHz\nPost-elab: Reset connectivity check\n(non-blocking — 3 groups, 17 signals)"]
    MIDCHECK -->|"✅ checks pass"| VERIFY
    MIDCHECK -->|"❌ driverClk slow"| DRIVFIX

    DRIVFIX["🐢 driverClk TOO SLOW\n━━━━━━━━━━━━━━━━━━━━━\nRead driverClk KB immediately\nApply zforce/ProbesLib fix"]
    DRIVFIX -->|"🔁 rebuild"| COMPILE

    VERIFY["✅ VERIFY BUILD\n━━━━━━━━━━━━━━━━━━━━━\n6 pass checks\nshadow files · backend dirs\nMuDb · libs · readmem · logs"]
    VERIFY -->|"✅ all 6 pass"| POSTBUILD
    VERIFY -->|"❌ fail"| DEBUG

    COMPILE -->|"❌ build error"| DEBUG

    DEBUG["🐛 DEBUG FAILURES\n━━━━━━━━━━━━━━━━━━━━━\n2a. Detect phase\n2b. Collect symptoms\n2c. Search 57 known bugs\n2d. Apply fix → re-run"]
    DEBUG -->|"🔁 fix applied"| COMPILE
    DEBUG -->|"📝 new bug"| DOCUMENT

    DOCUMENT["📄 DOCUMENT\n━━━━━━━━━━━━━━━━━━━━━\nCreate new BUG file\nYAML frontmatter + fix\nAdd to Knowledge Base"]
    DOCUMENT -->|"🔁 re-run"| COMPILE

    POSTBUILD["📦 POST-BUILD CHECKS\n━━━━━━━━━━━━━━━━━━━━━\nPCD BKC Integration needed?\nIf yes → rsync + apply SLE delta"]
    POSTBUILD -->|"done"| DONE

    DONE([🎉 Build Complete])

    style START fill:#333,stroke:#aaa,stroke-width:2px,color:#fff
    style SETUP fill:#2a2a5a,stroke:#7777cc,stroke-width:3px,color:#fff
    style COMPILE fill:#0d3b66,stroke:#4a9eff,stroke-width:3px,color:#fff
    style MIDCHECK fill:#3b2a00,stroke:#f0ad4e,stroke-width:3px,color:#fff
    style DRIVFIX fill:#6b1d1d,stroke:#ff6b6b,stroke-width:3px,color:#fff
    style VERIFY fill:#1b4332,stroke:#6abf69,stroke-width:3px,color:#fff
    style DEBUG fill:#6b1d1d,stroke:#ff6b6b,stroke-width:3px,color:#fff
    style DOCUMENT fill:#4a1a6b,stroke:#b366e0,stroke-width:3px,color:#fff
    style POSTBUILD fill:#4a1a6b,stroke:#b366e0,stroke-width:3px,color:#fff
    style DONE fill:#1b6b1b,stroke:#5cb85c,stroke-width:3px,color:#fff
```

### Workflow Details

**Session Setup** — Every new session, the agent asks:
1. Switch to autopilot mode (`/model` → autopilot)
2. Permission level: Full auto / Build only / Read-only
3. Monitoring preference: **Manual** *(default — periodic log checks in chat)* or Background script *(known reliability issues)*
4. WORKAREA path (always asked — never assumed)
5. Which model to build

**Mid-Build Checks** — Two non-blocking checks run during the build:
- **driverClk (ZSE5 only)**: As soon as `zCoreBuildTiming` completes, checks `zTime.log` immediately. If driverClk < 200 kHz, reads the driverClk KB and alerts you — the build result would be unusable. Does NOT wait for the full build to finish. For converged builds, checks **each ZSE5 target independently**.
- **Reset connectivity (post-elab)**: After analyze completes, verifies 3 groups of signals (17 total): Group A reset/power (epd_on, pwrgd, boot triggers, pltrst, pmsync/pmdown), Group B IOSF SB structural path, Group C cross-die clock requests. Non-blocking — does not stop the build.

> ⚠️ **driverClk non-determinism**: The same workspace can produce wildly different driverClk across builds (e.g., 612 kHz vs 10 kHz). A single good result does NOT mean the issue is resolved.

**Converged TTLbx: Parallel Target Management** — When all 3 targets run in parallel, the agent:
- Tracks each target's status independently (Running / Passed / Failed / Relaunching)
- Classifies failures as **shared-stage** (affects all 3 → full rebuild) or **per-target** (relaunch that target alone with `-id`)
- Deploys separate monitor instances per target, each namespaced by WORKAREA+MODEL
- Follows a decision tree: if one target fails while others are running, continues monitoring the others and debugs the failed target in parallel — unless the fix touches shared stages (filelists, RTL, `tool.cth`)

**Post-Elab Reset Connectivity Check** — After the analyze/elab phase completes, the agent runs a non-blocking connectivity check on 3 groups of signals (17 total): Group A reset/power (epd_on, pwrgd, boot triggers, pltrst, pmsync/pmdown), Group B IOSF SB structural path (d2d_iiosf_sb_link, ISM states, PMA FSM, sb_link_rst_b), Group C cross-die clock requests (XTAL, CRO, OCB, pmc_wake). Does not gate the build — issues are reported for user review.

**Verify** — Runs 6 pass checks after build completes. All must pass.

**Post-Build: PCD BKC Integration** — After verification passes, the agent asks whether a PCD BKC integration is needed. If yes, walks you through the rsync + SLE delta application flow.

**Debug** — If anything fails, detects the phase (BUILD / ANALYZE/ELAB / SYNTHESIS), collects symptoms, searches 57 known bug files, and applies the best-matched fix before re-running.

---

## 🔄 pkg_ch IP Refresh Workflow

Use this when a new `pkg_ch` model release is available on zsc10 and you need to create a new SLE workarea based on it.

```mermaid
flowchart TD
    START([🚀 pkg_ch Refresh]) --> INPUTS

    INPUTS["📥 GATHER INPUTS\n━━━━━━━━━━━━━━━━━━━━━\nBase SLE model path\nNew pkg_ch path on zsc10\nWorking disk"]
    INPUTS --> EXTRACT

    EXTRACT["🔍 EXTRACT VERSIONS\n━━━━━━━━━━━━━━━━━━━━━\ncdie + hub: SSH zsc10-login\n  .soc.list.mako in new pkg_ch\nPCD: read base SLE model (local)"]
    EXTRACT --> NAME

    NAME["🏷️ NAME NEW WORKAREA\n━━━━━━━━━━━━━━━━━━━━━\npkg-ttlpkg-a0-ttlbxpkg-cXXX_hXXX_pXXX\nCheck for collision → append suffix"]
    NAME --> CLONE

    CLONE["📋 GIT CLONE\n━━━━━━━━━━━━━━━━━━━━━\ngit clone &lt;base_SLE&gt; &lt;new_workarea&gt;"]
    CLONE --> PULL

    PULL["⬇️ GIT PULL\n━━━━━━━━━━━━━━━━━━━━━\ngit pull user@zsc10-login:&lt;pkg_ch_path&gt;"]
    PULL -->|"no conflicts"| SYNCIPS
    PULL -->|"merge conflicts"| RESOLVE

    RESOLVE["🔀 RESOLVE CONFLICTS\n━━━━━━━━━━━━━━━━━━━━━\nKeep pkg_ch as base\nRe-apply SLE-marked blocks\nConfirm unmarked files with user"]
    RESOLVE --> SYNCIPS

    SYNCIPS["🔁 SYNC IPs\n━━━━━━━━━━━━━━━━━━━━━\npython scripts/sync_ips_zsc16.py\nFetches missing IP packages"]
    SYNCIPS --> DONE

    DONE([✅ Workarea Ready for Build])

    style INPUTS fill:#2a2a5a,stroke:#7777cc,stroke-width:3px,color:#fff
    style EXTRACT fill:#0d3b66,stroke:#4a9eff,stroke-width:3px,color:#fff
    style NAME fill:#1b4332,stroke:#6abf69,stroke-width:3px,color:#fff
    style CLONE fill:#1b4332,stroke:#6abf69,stroke-width:3px,color:#fff
    style PULL fill:#3b2a00,stroke:#f0ad4e,stroke-width:3px,color:#fff
    style RESOLVE fill:#6b1d1d,stroke:#ff6b6b,stroke-width:3px,color:#fff
    style SYNCIPS fill:#0d3b66,stroke:#4a9eff,stroke-width:3px,color:#fff
    style DONE fill:#1b6b1b,stroke:#5cb85c,stroke-width:3px,color:#fff
    style START fill:#333,stroke:#aaa,stroke-width:2px,color:#fff
```

### Refresh Workflow Details

**Inputs required**:
- Base SLE model path (known-good, local disk) — e.g., `/nfs/site/disks/issp_ttl_emu_compile_001/pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1`
- New pkg_ch model path on zsc10 — e.g., `/p/cth/rtl/models/ddgcth/ttl/pkg_emu/pkg-ttlpkg-a0-ttlbxpkg-cdie_ww17f_hub_ww17e`
- Working disk for the new clone

**Version extraction** — cdie and hub versions come from `filelists/.soc.list.mako` in the **new pkg_ch model** (accessed via SSH to zsc10-login). PCD version comes from `filelists/.soc.list.mako` in the **base SLE model** (read locally — it is not present in the new pkg_ch model). Tags are extracted from `26wwXXX` workweek strings (e.g., `26ww17f` → `c17f`, `26ww17e` → `h17e`, `26ww13a` → `p13a`).

**Naming** — New workarea is named `<prefix>-c<cdie>_h<hub>_p<pcd>`. If that directory already exists on the working disk, a `.2`, `.3` suffix is appended.

**Merge conflict resolution** — SLE-specific content is identified by `// SLE Change`, `// SLE Addition`, `## SLE Change`, or `## SLE Addition` markers. Resolution rule: use pkg_ch as the base, re-apply all SLE-marked blocks. For comment-free file types (JSON, `.mako`, CSV), the agent diffs both sides and asks the user before discarding any SLE content.

**IP sync** — After the merge commit, runs `python scripts/sync_ips_zsc16.py` to fetch any missing IP packages referenced by the refreshed model.

---

## 🎯 What Can I Ask?

### 🔨 Compilation
| Prompt | What it does |
|--------|-------------|
| `compile the model` | Start a fresh grdlbuild |
| `compile all 3 TTLbx targets` | Launch converged build (p2e4 ZSE5 + cfgr ZSE5 + cfgr FPGA) |
| `resume the build` | Continue a build with `-id` |
| `check if compilation passed` | Run the 6 pass checks (per target for converged builds) |
| `check driverClk` | Check zTime.log for driverClk speed |
| `monitor the build` | Check current progress in grdlbuild.log |
| `show status of all 3 targets` | Per-target snapshot: stage, status, driverClk for converged build |

### 🐛 Debugging
| Prompt | What it does |
|--------|-------------|
| `debug this build failure` | Full triage: phase detection → symptoms → bug matching |
| `one target failed, others are running` | Per-target failure triage: classify shared vs. per-target fix, relaunch only failed target if safe |
| `search known bugs for <error text>` | Search the 57 BUG files |
| `what known bugs match <symptom>?` | Find matching bugs by keyword |
| `why is driverClk slow?` | Read driverClk KB and analyze zTime.log |

### 🔧 RTL Changes & Integration
| Prompt | What it does |
|--------|-------------|
| `create a new rtlchange` | Walk through replacement + .ref + HSDs.toml + config |
| `refresh rtlchanges` | Fix stale .ref files or missing HSDs.toml entries |
| `integrate new PCD BKC` | rsync from FM + apply SLE delta |
| `regenerate ttlpcdhpkg rtlchange` | PCD port list changed → rebuild wrapper rtlchange |

### 🔌 Post-Build Checks
| Prompt | What it does |
|--------|-------------|
| `check reset connectivity` | Verify 6 critical reset signal paths end-to-end (post-elab) |
| `do we need PCD BKC integration?` | Check if a new PCD BKC release needs integration |

### 🔄 pkg_ch IP Refresh
| Prompt | What it does |
|--------|-------------|
| `prepare a new workarea for pkg_ch refresh` | Full flow: clone base SLE, pull new pkg_ch, resolve conflicts, sync IPs |
| `what cdie/hub/pcd version is in this pkg_ch model?` | Read `.soc.list.mako` on zsc10 and extract version tags |

### 📋 Status & Info
| Prompt | What it does |
|--------|-------------|
| `what build stage are we on?` | Check .shadow progress |
| `show the build stages` | List all 14 stages |
| `show safety rules` | Review the red lines |

---

## 🛡️ Safety Red Lines

| Rule | Detail |
|------|--------|
| 🚫 No source file deletion | Always backup before any destructive operation |
| 🚫 No subip/soc/handoff edits | Requires explicit user approval |
| 🚫 No login-node compilation | Always use compute resources |
| 🚫 No GK branch pushes | Requires explicit user approval |
| ✅ Always asks before git commit | Never auto-commits |
| ✅ Never guesses shell commands | Intel infra is non-standard — asks the user |

---

## 🎯 Bug Match Confidence Score

When a failure occurs, the agent searches **57 known bugs** and scores each match:

| Signal | Points |
|--------|--------|
| Exact tag match (e.g., `rpath`, `dlopen`) | **+50 pts** |
| Category match (e.g., `library`, `build-config`) | **+30 pts** |
| Critical symptom found | **+10 pts** |
| Phase match | **+5 pts** |
| Phase mismatch | **×0.5 penalty** |

| Score | Level | Action |
|-------|-------|--------|
| ≥ 200 | 🟢 **VERY HIGH** | Apply fix directly |
| 50–99 | 🟡 **HIGH** | Apply fix, verify result |
| 15–29 | 🟠 **MEDIUM** | Review BUG file before acting |
| < 15  | 🔴 **LOW** | Likely new/unknown — escalate to user |

---

## 📂 Knowledge Base Structure

```
📁 emulation_agent_ttl_sle/
├── 📄 00_index.md                          ← Start here — routing table + file tree
├── 📁 01_agent_core/                       ← Identity, safety rules, AI guidelines
├── 📁 02_execution/                        ← Build commands, environment setup
├── 📁 03_testing_and_validation/           ← Quality gates, emulator setup
├── 📁 04_monitoring/                       ← Metrics, alert thresholds
├── 📁 05_knowledge_and_debugging/          ← Debug workflow, symptom rules
│   ├── 📁 known_bugs_and_fixes/            ← 57 bug files (BUG-001 to BUG-057)
│   ├── 🔧 run_phase_detection_nvlax.sh     ← Automated bug matcher
│   └── 📄 symptom_rules.txt                ← Keyword expansion rules
├── 📁 06_skills/                           ← Procedure KB files (read before acting)
│   ├── sle-build-grdlbuild-monitor.md      ← Build monitoring procedure
│   ├── sle-build-iterative-build-monitor-fix.md ← End-to-end build-fix cycle
│   ├── sle-build-zebu-driverclock-debug.md ← driverClk analysis + fixes
│   ├── sle-build-pkgch-refresh.md          ← pkg_ch IP refresh: clone + pull + conflict resolution + IP sync
│   ├── sle-build-rtlchanges-create.md      ← Create new rtlchange
│   ├── sle-build-rtlchanges-refresh.md     ← Refresh stale rtlchanges
│   ├── sle-build-pcd-bkc-integration.md    ← PCD BKC release integration
│   ├── sle-build-pcd-pkgpinlist-rtlchange-generation.md ← PCD wrapper rtlchange
│   ├── sle-build-fpga-elab-missing-cell-fix.md ← FPGA CFCILFBI fix
│   ├── sle-build-fpga-rtlchanges-postcheck-fix.md ← FPGA postcheck fix
│   ├── sle-build-new-target-analysis-opts.md ← New build target analysis opts
│   ├── sle-build-reset-connectivity-check.md ← Post-elab reset signal connectivity check
│   └── sle-build-dfx-target-enablement.md  ← DFX target enablement
└── 📁 copilot_cli_agent/                   ← Agent instruction file + init script
```

---

## 🔍 Verify Setup

Inside Copilot CLI, run these commands:

```
/agent              → should show sle_emulation_agent
/instructions       → should show loaded instruction file
/env                → should show KB_ROOT path
```

---

<div align="center">

**SLE Emulation · Intel TTL**

</div>

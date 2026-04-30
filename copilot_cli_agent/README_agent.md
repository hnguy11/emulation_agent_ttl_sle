#Setup command 
/p/hdk/bin/cth_psetup -p ddgcth/1.13 -cfg nvlpkg -read_only
setenv WORKAREA $PWD

#Clone model
git clone /p/cth/rtl/git_repos/ddgcth/nvl/gk/nvlpkg/pkg-nvlpkg-a0/

#Gradle build
#List all stages
grdlbuild all -show_tasks

#Run all stages
grdlbuild all

#Run all stages but only build certain DUT
grdlbuild all -dut <DUT>

#Run vcssim and dependencies
grdlbuild vcssim

#Run vcssimmpp and dependencies
grdlbuild vcssimmpp

#Open Code Review and Turnin 
open_code_review -b ${USER}_<feature_name> -t <feature_name>
turnin -proj nvl -c pkg -s nvlpkg-a0 -comments "<Description>"

testing

---

# NVL-AX Compilation Agent (Copilot CLI)

An AI agent that automates the compile → test → debug → fix cycle for NVL-AX ZeBu ZSE5 emulation models.

## Quick Start

```bash
cd <your_model_workarea>   # e.g. /nfs/site/disks/.../models/integrate_bundle1106
copilot
```

That's it. The agent loads automatically from any model workarea that has `.github/instructions/`. Start with:

```
You: compile the model
You: run DOA tests
You: this test failed, debug it
```

## Run From Any Directory

Add this line to your `~/.bashrc`:

```bash
export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="<your_model_workarea>/.github/instructions"
```

Then reload and run from anywhere:

```bash
source ~/.bashrc
copilot
```

## Select the Agent Persona

Inside Copilot CLI:

```
/agent sle_emulation_agent
```

## Verify It's Working

Inside Copilot CLI:

```
/instructions
```

You should see 4 loaded files: `nvlax-agent`, `nvlax-build`, `nvlax-testing`, `nvlax-debug`.

## What It Does

```
Step 1: COMPILE    → runs grdlbuild → checks 6 pass criteria
Step 2: POST-BUILD → runs post_zcui + fix_zse5_libs.sh
Step 3: DOA TEST   → runs simregress → checks 5 pass criteria
Step 4: IF FAIL    → detects phase → searches 57 known bugs → suggests fix
```

## What You Should Know

- The agent knows 57 documented bugs and will match your failure against them
- It will **never** use the showstopper queue or the `-local` flag
- It will **never** resubmit a test that's still running
- It always checks ALL logbook stages — emurun PASS does not mean overall PASS
- It will always ask you before committing to git

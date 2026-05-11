---
name: sle-build-fpga-rtlchanges-postcheck-fix
description: "Fix rtlchanges_postcheck failures in FPGA VCS builds due to uncompiled IP rtlchanges. USE WHEN: grdlbuild FPGA VCS build fails at post_analyze phase with rtlchanges_postcheck errors, FPGA model doesn't compile certain IPs (hubs, cdie, pcd monitors) but rtlchanges exist for them, need to add entries to rtlchanges_optional_ips.json. Covers: post_analyze phase failure diagnosis, rtlchanges_optional_ips.json format and regex patterns, negative lookahead regex for FPGA model exclusion."
argument-hint: "Provide the WORKAREA path and optionally the MODEL name. Specify which IPs failed postcheck."
---

# Fix rtlchanges_postcheck Failures in FPGA VCS Builds

## When to Use
- `grdlbuild` FPGA VCS build passes **analysis** (all 2065 libraries pass) but fails at **post_analyze** phase
- The `post_analyze` phase runs `rtlchanges_postcheck` which verifies all rtlchanges were compiled into at least one library
- FPGA builds compile only a subset of IPs (e.g., no standalone hubs, no standalone cdie), so rtlchanges for excluded IPs cause postcheck failures
- This is expected and non-harmful — the fix is to mark those IPs as optional for FPGA models

## Background: Build Phase Ordering (Post-Analysis)

After VCS analysis passes, the build proceeds through these phases:
1. `c_compile` — testbench C++ compile (~1-2 min)
2. **`post_analyze`** — runs `rtlchanges_postcheck` (~1-2 min) — **can fail here for FPGA builds**
3. `gen_vcs_cmd` — generates VCS elaboration command (~1-2 min)
4. `elab` — VCS elaboration (~10-30 min)

## Symptom

In the grdlbuild task log (`$WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.fpga.*.log`):
```
Target:    post_analyze                             FAILED
```

## Diagnosis

### Step 1: Read the postcheck log
```bash
OUTDIR=$WORKAREA/output/ttlbx_n2p/emu/fpgasim_emuvcs/$MODEL/vcs
cat $OUTDIR/log/rtlchanges_postcheck.log | grep 'FAILED\|Error'
```
The log lists which rtlchanges directories had files that weren't found in any compiled library.

### Step 2: Identify which IPs are missing
Common IPs that are not compiled in FPGA builds:
- `hubs/` — hub subsystem testbench, subips
- `cdie_816_n2p/` — CDIE testbench, subips
- `pcd_cfgr/` — PCD configurator monitors
- Any IP-specific testbench monitors/transactors

## Fix: `rtlchanges_optional_ips.json`

### File Location
```
$WORKAREA/src/val/emu/scripts/rtlchanges_optional_ips.json
```

### Format
This JSON file maps rtlchange directory path substrings to arrays of model regex patterns. If the current model name matches **any** of the regexes for a directory entry, that directory's rtlchanges are treated as **optional** (postcheck skips them).

```json
{
    "<rtlchanges_dir_substring>": ["<model_name_regex>", ...],
    ...
}
```

### Key Regex Pattern: `^(?!.*fpga)`

For FPGA builds, the model name contains `fpga` (e.g., `pkg_chpr_cfgr_p2e0_816_fast_fpga_slimsim`). To make an IP's rtlchanges **required for ZSE5 models but optional for FPGA models**, use the negative lookahead regex:

```
^(?!.*fpga)
```

This regex matches model names that do **NOT** contain `fpga`. This means: the postcheck will REQUIRE the rtlchange to be compiled when the model name doesn't include "fpga" (i.e., ZSE5 models). It will SKIP the check for FPGA models.

> ⚠️ **CRITICAL PITFALL**: `["^(?!.*fpga)"]` means "required for ALL non-FPGA models" — this includes ZSE5 p2e4 and cfgr. If a `pcd_cfgr/` sub-entry uses `["^(?!.*fpga)"]`, it will make pcd_cfgr sub-files required for the ZSE5 p2e4 model — which does NOT compile pcd_cfgr files — causing a postcheck failure.
>
> **Correct regex for pcd_cfgr sub-entries**: use `["pkg_chpr_cfgr"]` (required only for cfgr models, optional for p2e4 and all FPGA).

### Example Entries

From a working FPGA VCS build (`pkg_chpr_cfgr_p2e0_816_fast_fpga_slimsim`):
```json
{
    "hubs/src/val/emu/testbench": ["^(?!.*fpga)"],
    "hubs/src/val/subsystems/dispss/tb": ["^(?!.*fpga)"],
    "hubs/src/val/subsystems/ipuss/tb": ["^(?!.*fpga)"],
    "hubs/src/val/subsystems/vpuss/tb": ["^(?!.*fpga)"],
    "hubs/subip/hip/hub_atomcpu": ["^(?!.*fpga)"],
    "hubs/subip/hip/hub_m78p6rfsupnl1rh1wh256x46bha04": ["^(?!.*fpga)"],
    "hubs/subip/sip/hub_idi_bridge": ["^(?!.*fpga)"],
    "hubs/subip/sip/hub_sfcmem_ddrphy": ["^(?!.*fpga)"],
    "cdie_816_n2p/src/val/emu/testbench": ["^(?!.*fpga)"],
    "cdie_816_n2p/subip/hip/cdie_n2p_core/core/msid": ["^(?!.*fpga)"],
    "cdie_816_n2p/subip/sip/cdie_ccf_n2p": ["^(?!.*fpga)"],
    "pcd_cfgr/emu/pchlp/monitors": ["pkg_chpr_cfgr"],
    "pcd_cfgr/emu/pchlp/pcd_tb/espi": ["pkg_chpr_cfgr"]
}
```

> **Why `pkg_chpr_cfgr` for pcd_cfgr sub-entries?** The broader entry `"rtlchanges/pcd_cfgr/"` already says all of pcd_cfgr is required for cfgr models. The sub-entries must use `["pkg_chpr_cfgr"]` (not `["^(?!.*fpga)"]`) to avoid requiring those files in the ZSE5 p2e4 model, which doesn't compile pcd_cfgr content.

### Pre-existing Entries

The JSON file also has entries for non-FPGA model filtering (using positive regexes like `pkg_c(\\d*)h`, `pkg_gh`, etc.) for IP-specific model exclusions. Do NOT modify these — only add new entries.

## Procedure

1. Read the postcheck log to identify which directories failed
2. For each failing directory, determine the correct required-model regex:
   - If the rtlchange is for a **hub/cdie IP** that should be compiled in all ZSE5 models: use `["^(?!.*fpga)"]`
   - If the rtlchange is for a **cfgr-specific IP** (e.g., `pcd_cfgr/`): use `["pkg_chpr_cfgr"]`
   - If the rtlchange should **never** be required (FPGA-only files, obsolete files): use `[]`
3. Add the entry to `rtlchanges_optional_ips.json`
4. Relaunch the build with `-id` — analysis won't re-run, only `post_analyze` onwards will execute
5. The fix is **low risk** — it only affects postcheck validation, not the actual compilation

## Pitfalls

- **Don't use `.*fpga.*` (positive match)** — the regex array specifies models where the rtlchange IS required, not where it's optional. The negative lookahead `^(?!.*fpga)` means "required for all models except FPGA".
- **Path substring matching** — the JSON key is matched as a substring against the full rtlchanges directory path. Use enough of the path to be unique but not so much that it breaks on workspace path changes.
- **JSON syntax** — ensure proper comma separation between entries. The last entry must NOT have a trailing comma.

## Agent Implementation Note: Prefer `sed` for JSON Edits

When modifying `rtlchanges_optional_ips.json`, **use `sed` via `bash`** instead of the `edit` tool. The `edit` tool has been observed to get interrupted/stuck on this file due to special regex characters like `(?!.*fpga)` in the replacement strings.

### Recommended: sed one-liner pattern

```bash
# To update an existing entry's regex (e.g., add negative lookahead for fpga):
sed -i 's/\("pcd_cfgr\/emu\/pchlp\/monitors": \)\["pkg_chpr_cfgr"\]/\1["pkg_chpr_cfgr(?!.*fpga)"]/' $WORKAREA/src/val/emu/scripts/rtlchanges_optional_ips.json

# To add a new entry before the closing brace:
sed -i '$ s/}/,\n    "new\/path\/here": ["^(?!.*fpga)"]\n}/' $WORKAREA/src/val/emu/scripts/rtlchanges_optional_ips.json
```

### Always verify after editing

```bash
grep "<key_substring>" $WORKAREA/src/val/emu/scripts/rtlchanges_optional_ips.json
python3 -c "import json; json.load(open('$WORKAREA/src/val/emu/scripts/rtlchanges_optional_ips.json')); print('JSON valid')"
```

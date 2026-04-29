---
title: "ZeBu Emulator Setup"
module: 03_testing_and_validation
tags: [zebu, zse5, emulator, setup, fm, boards]
---

# ZeBu Emulator Setup

## ZSE5 Platform Overview
- **Platform**: Synopsys ZeBu ZSE5 (FPGA-based hardware emulation)
- **SDK**: V21.09-2_B4_250617
- **FPGA count**: 192 FPGAs per model partition
- **FM site**: Folsom (Intel FM — Functional Model farm)
- **Board naming**: g503-g514 (ZSE5 boards in the FM farm)

## Prerequisites Before Testing

1. **All 19 shadow files present** (model fully compiled):
   ```bash
   ls output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/.shadow/ | wc -l
   # Must be 19
   ```

2. **Library symlinks created** (BUG-024):
   ```bash
   bash scripts/fix_zse5_libs.sh
   # Creates ~100 symlinks in zse5/lib/, patches RPATH on 352 .so files
   ```

3. **No missing shared library dependencies**:
   ```bash
   ldd output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/simics_workspace/linux64/lib/zse_engine.so 2>/dev/null | grep "not found"
   # Must produce NO output
   ```

4. **Kerberos ticket valid** (for rsync to FM boards):
   ```bash
   klist 2>&1 | grep -E "Expires|>>>"
   # Must NOT show >>>Expired<<<
   ```

5. **SSH BatchMode works** (password not expired):
   ```bash
   ssh -o BatchMode=yes sccc14644327.zsc11.intel.com "echo OK"
   # Must print: OK
   ```

## Emulation Architecture

### Offline Rsync Mode (`-offline_rsync_wo_nb`)
- ALL FM board logs are written LOCALLY on the FM board
- Rsync to ZSC11 NFS happens ONLY AFTER the ENTIRE job completes
- Logbook stays completely frozen during active emulation — this is **NORMAL** (see BUG-030)
- When a board dies: partial rsync (~150 bytes) appears as the "death signal"

### Cycle Times (pkg_ghpf_model, ZSE5)
- Observed rate: ~2.3ms simulated time per hour of wall clock time
- `spacedoa_mobile`: cycle limit 50ms → ~5 hours (but common_defaults overrides to 11ms → ~4-5h)
- `spacex_mobile`: cycle limit 240ms → completes naturally at ~135ms SimTime

### FM Board Behavior
- Boards accessed via NB express queues: `fm_zse5_g503_express` through `fm_zse5_g514_express`
- "Wait Remote" in NB = job running on remote FM site (NOT stuck)
- "Wait Virtual" in FM = board occupied by active emulation
- Auto-requeue on board death: exit codes 137,138,140,162,165,163,164,166,144 → up to 10 retries
- Exit code 66 (rsync/copy-in failure) does NOT auto-requeue — requires manual resubmit

## Key Files in Test Directory
```
regression/nvlsi7_n2p/doa_pkg_ghpf_model_zse5.list.N/
├── spacedoa_mobile/
│   ├── logbook.log          # High-level test progress
│   ├── emurun.log           # Emulation run details, FM job IDs
│   ├── testbench.log        # Simics/DUT output
│   ├── results.log          # PASSED/FAILED verdict
│   ├── assertion_failures.log  # Assertion check results
│   ├── postmortem.log       # Post-run analysis
│   ├── JOBS_STATUS          # Job completion status
│   └── tlm_post/            # Post-processing tracker results
└── spacex_mobile/
    └── (same structure)
```

## ZeBu Runtime Debugging (Extracted from ai_picker_sle Reference)

### 1. Environment Variable Extraction
When debugging a test, extract key variables from `.trex.env` in the test directory:

```bash
# Extract test context from .trex.env
grep -E "^(TESTNAME|WORKAREA|CTH_TOOL_OVERRIDE_FILE_MAESTRO)=" .trex.env
```

| Variable | Purpose |
|----------|---------|
| `TESTNAME` | Name of the test being executed |
| `WORKAREA` | Build workspace root path (model location) |
| `CTH_TOOL_OVERRIDE_FILE_MAESTRO` | Maestro tool override file for this test |

### 2. Test File Locations
- `perspec_test.c` — If it's a Perspec (CDNS) test, this is the C source file
- `$TESTNAME.lst` — Compilation result of the C file, includes all LIPs for processors

### 3. Plugin Failure Detection
Check emulation plugins loaded correctly:

```bash
# Check for plugin failures in emurun.log
grep -i "plugin.*reported.*failed\|plugin.*error\|plugin.*fail" emurun.log

# Check VIP setup
grep -i "VIP.*fail\|VIP.*error" PyDoh.*.log 2>/dev/null | head -3

# Check for LogScanner failures
grep -i "LogScanner.*fail\|validator.*error" emurun.log | head -3
```

Plugin failures indicate EMU_SETUP phase problems — the emulation environment itself failed to initialize.

### 4. Emulation Phase Progression Markers
Track progress through emulation phases:

| Phase | Log Evidence | Normal Duration |
|-------|-------------|-----------------|
| Model load | `emurun.log`: "Loading model..." | 5-15 min |
| Boot | `bootfsm_state_tracker.log.gz`: FSM state progression | 30-60 min |
| Test execution | `uop_log*.log`: `[PERSPEC] N` incrementing | Test-dependent |
| Post-processing | `logbook.log`: "Creating RPT", "Post processing" | 30-60 min |

### 5. Copilot CLI Path
The GitHub Copilot CLI is available at:
```
/p/hdk/cad/copilot/latest/copilot
```
This is the execution path for invoking the Copilot agent from within the Intel infrastructure.

### 6. NFS Path Quirks
- **Symlinked output dirs:** `output/` may be a symlink to a GK build on a different NFS mount (e.g., `ive_nvl_efs_gk_002`). Check with `readlink -f output/` and verify permissions.
- **Cross-site rsync:** FM boards at Folsom write logs locally; rsync to ZSC11 NFS happens post-job. During active emulation, local logs are invisible to ZSC11.
- **Kerberos on NFS:** Long-running jobs (>24h) can outlive Kerberos tickets. Renew with `kinit -R` before job submission for queue waits.
- **Disk capacity:** Check before builds: `df -h /nfs/site/disks/ive_sle_zsc11_tbaziza | tail -1` (builds need 50-100GB)

### 7. ZSE5 Board Monitoring
When jobs are running on FM ZSE5 boards:

```bash
# Check NB job status
nbq -u $USER 2>/dev/null | head -20

# Check FM job status (if FM job ID known)
nbq -u $USER -c fm 2>/dev/null | grep <FM_JOB_ID>

# Check logbook for progress (remember: frozen during offline rsync mode is NORMAL!)
ls -la regression/.../logbook.log*
stat --format='%Y' regression/.../logbook.log 2>/dev/null
```

**CRITICAL:** In `-offline_rsync_wo_nb` mode, logbook stays frozen during active emulation. This is NORMAL (see BUG-030). Do NOT kill jobs because logbook appears stale.

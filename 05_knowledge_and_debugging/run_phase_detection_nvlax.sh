#!/bin/bash
# Phase Detection + Bug Scoring — NVL-AX Adapted Workflow
# Detects failure phase from logbook.log, collects symptoms from logs,
# then scores known BUG-NNN files to recommend the most relevant fixes.

set -e

REPO_ROOT="/nfs/site/disks/ive_sle_zsc11_tbaziza/models/integrate_bundle1106"
DEFAULT_REGDIR="${REPO_ROOT}/regression/nvlsi7_n2p/doa_pkg_ghpf_model_zse5.list.latest"
BUGS_DIR="/nfs/site/disks/ive_sle_zsc11_tbaziza/NVL_AX_agent_workspace/05_knowledge_and_debugging/known_bugs_and_fixes"
COMMON_PATTERNS="/nfs/site/disks/ive_sle_zsc11_tbaziza/NVL_AX_agent_workspace/05_knowledge_and_debugging/common_patterns.md"

TEST_DIR="${1:-$DEFAULT_REGDIR}"
TOP_N="${2:-3}"

cd "$TEST_DIR" || { echo "ERROR: Cannot cd to $TEST_DIR"; exit 1; }

echo "========================================="
echo "PHASE DETECTION + BUG SCORING (NVL-AX)"
echo "========================================="
echo "Test Directory: $TEST_DIR"
echo "Bug Files Dir:  $BUGS_DIR"
echo ""

# ============================================
# STAGE 1: PHASE DETECTION (90s budget)
# ============================================
echo "=== STAGE 1: Phase Detection ==="

PHASE="UNKNOWN"
LOGBOOK=""
if [ -f "logbook.log.gz" ]; then
    LOGBOOK="logbook.log.gz"
elif [ -f "logbook.log" ]; then
    LOGBOOK="logbook.log"
fi

# Helper: search logbook with grep or zgrep
search_logbook() {
    local pattern="$1"
    if [ -z "$LOGBOOK" ]; then return 1; fi
    if [[ "$LOGBOOK" == *.gz ]]; then
        zgrep -qi "$pattern" "$LOGBOOK" 2>/dev/null
    else
        grep -qi "$pattern" "$LOGBOOK" 2>/dev/null
    fi
}

# Check for PASS
if search_logbook "PASS"; then
    PHASE="TEST_PASSED"
    echo "✓ Phase: TEST_PASSED (test passed successfully)"
    echo "No bug scoring needed — test passed"
    exit 0
fi

# Check for BUILD / compilation phase
if [ -f "build.log" ] && grep -qi "error\|fatal" build.log 2>/dev/null; then
    PHASE="BUILD"
    echo "✓ Phase: BUILD (build/compilation errors)"
elif [ -f "fe_be.NB.log" ] && grep -qi "error\|fatal\|killed" fe_be.NB.log 2>/dev/null; then
    PHASE="BUILD"
    echo "✓ Phase: BUILD (fe_be build errors)"
fi

# Check for BOOT / RUNTIME hang
if [ "$PHASE" == "UNKNOWN" ]; then
    if search_logbook "boot.*hang\|stuck.*boot\|timeout.*boot\|boot.*fsm.*stuck\|DOA.*FAIL"; then
        PHASE="RUNTIME"
        echo "✓ Phase: RUNTIME (boot hang or DOA failure)"
    elif search_logbook "emulation.*setup\|model.*load.*fail\|zebu.*error\|zse.*error"; then
        PHASE="EMU_SETUP"
        echo "✓ Phase: EMU_SETUP (emulation environment issues)"
    fi
fi

# Check for OOM / NB infrastructure
if [ "$PHASE" == "UNKNOWN" ]; then
    if search_logbook "killed.*memory\|oom\|out.of.memory\|Exit Status.*-13"; then
        PHASE="INFRASTRUCTURE"
        echo "✓ Phase: INFRASTRUCTURE (OOM or NB job killed)"
    fi
fi

# Default to TEST_EXECUTION
if [ "$PHASE" == "UNKNOWN" ]; then
    PHASE="TEST_EXECUTION"
    echo "✓ Phase: TEST_EXECUTION (runtime test failure)"
fi

echo ""

# ============================================
# STAGE 2: SYMPTOM COLLECTION (60s budget)
# ============================================
echo "=== STAGE 2: Collecting Symptoms ==="

ALL_LOGS=$(find . -maxdepth 2 \( -name "*.log" -o -name "*.log.gz" \) -type f 2>/dev/null)
LOG_COUNT=$(echo "$ALL_LOGS" | grep -c . 2>/dev/null || echo 0)
echo "✓ Found $LOG_COUNT log files to search"

# Collect error/warning lines as symptom fingerprints
SYMPTOMS=""
for logfile in $ALL_LOGS; do
    if [[ "$logfile" == *.gz ]]; then
        hits=$(zgrep -i "error\|fatal\|fail\|killed\|not found\|no such\|timeout\|hang\|stuck\|oom\|denied" "$logfile" 2>/dev/null | head -20)
    else
        hits=$(grep -i "error\|fatal\|fail\|killed\|not found\|no such\|timeout\|hang\|stuck\|oom\|denied" "$logfile" 2>/dev/null | head -20)
    fi
    if [ -n "$hits" ]; then
        SYMPTOMS="${SYMPTOMS}${hits}"$'\n'
    fi
done

SYMPTOM_LINES=$(echo "$SYMPTOMS" | grep -c . 2>/dev/null || echo 0)
echo "✓ Collected $SYMPTOM_LINES symptom lines from logs"
echo ""

# ============================================
# STAGE 3: BUG FILE SCORING (30s budget)
# ============================================
echo "=== STAGE 3: Bug File Scoring ==="
echo ""

# Phase-to-category mapping
phase_matches_category() {
    local phase="$1" category="$2"
    category=$(echo "$category" | tr '[:upper:]' '[:lower:]')
    case "$phase" in
        BUILD)          [[ "$category" == *build* || "$category" == *compil* || "$category" == *config* ]] ;;
        RUNTIME)        [[ "$category" == *runtime* || "$category" == *boot* || "$category" == *doa* || "$category" == *test* ]] ;;
        EMU_SETUP)      [[ "$category" == *emu* || "$category" == *setup* || "$category" == *env* || "$category" == *infra* ]] ;;
        INFRASTRUCTURE) [[ "$category" == *infra* || "$category" == *nb* || "$category" == *netbatch* || "$category" == *oom* || "$category" == *config* ]] ;;
        TEST_EXECUTION) [[ "$category" == *test* || "$category" == *runtime* || "$category" == *doa* ]] ;;
        *)              return 1 ;;
    esac
}

# Score each BUG-NNN file
declare -A SCORES
declare -A SCORE_DETAILS

for bugfile in "$BUGS_DIR"/BUG-*.md; do
    [ -f "$bugfile" ] || continue
    score=0
    filename=$(basename "$bugfile")
    details=""

    # Extract YAML frontmatter fields
    fm=$(sed -n '/^---$/,/^---$/p' "$bugfile" 2>/dev/null)
    category=$(echo "$fm" | grep "^category:" | head -1 | sed 's/^category: *//' | tr -d '"')
    tags_line=$(echo "$fm" | grep "^tags:" | head -1 | sed 's/^tags: *//')
    stage=$(echo "$fm" | grep "^stage:" | head -1 | sed 's/^stage: *//' | tr -d '"')

    # 1. Phase/category match: +5 points
    if phase_matches_category "$PHASE" "$category"; then
        score=$((score + 5))
        details="${details} phase-match(+5)"
    fi

    # 2. Stage match: +3 points
    stage_lower=$(echo "$stage" | tr '[:upper:]' '[:lower:]')
    phase_lower=$(echo "$PHASE" | tr '[:upper:]' '[:lower:]')
    if [ -n "$stage_lower" ] && [[ "$stage_lower" == *"$phase_lower"* || "$phase_lower" == *"$stage_lower"* ]]; then
        score=$((score + 3))
        details="${details} stage-match(+3)"
    fi

    # 3. Tag matching against collected symptoms: +1 per tag found
    # Parse tags from YAML array: [tag1, tag2, tag3]
    tags=$(echo "$tags_line" | tr -d '[]' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | tr '[:upper:]' '[:lower:]')
    for tag in $tags; do
        [ ${#tag} -lt 3 ] && continue
        if echo "$SYMPTOMS" | grep -qi "$tag" 2>/dev/null; then
            score=$((score + 1))
            details="${details} tag:${tag}(+1)"
        fi
    done

    # 4. Search symptom text in bug file body (below frontmatter): +2 if match
    body=$(sed '1,/^---$/d' "$bugfile" | sed '1,/^---$/d' 2>/dev/null)
    symptom_section=$(echo "$body" | sed -n '/## Symptom/,/## /p' | head -10)
    if [ -n "$symptom_section" ] && [ -n "$SYMPTOMS" ]; then
        # Extract key phrases from the bug's symptom section
        key_phrases=$(echo "$symptom_section" | grep -oE '[a-zA-Z_]{4,}' | sort -u | head -15)
        for phrase in $key_phrases; do
            if echo "$SYMPTOMS" | grep -qi "$phrase" 2>/dev/null; then
                score=$((score + 2))
                details="${details} body-match:${phrase}(+2)"
                break
            fi
        done
    fi

    if [ $score -gt 0 ]; then
        SCORES["$bugfile"]=$score
        SCORE_DETAILS["$bugfile"]="$details"
    fi
done

# Also score common_patterns.md: +2 if any pattern section matches symptoms
COMMON_SCORE=0
if [ -f "$COMMON_PATTERNS" ] && [ -n "$SYMPTOMS" ]; then
    pattern_keywords=$(grep -i "Symptom\|Cause\|Fix" "$COMMON_PATTERNS" 2>/dev/null | grep -oE '[a-zA-Z_]{5,}' | sort -u)
    for kw in $pattern_keywords; do
        if echo "$SYMPTOMS" | grep -qi "$kw" 2>/dev/null; then
            COMMON_SCORE=$((COMMON_SCORE + 1))
        fi
    done
fi

# Sort scores and select top N
SORTED=$(for f in "${!SCORES[@]}"; do
    echo "${SCORES[$f]}|$f|$(basename "$f")|${SCORE_DETAILS[$f]}"
done | sort -t'|' -k1 -rn)

if [ -n "$SORTED" ]; then
    echo "Top $TOP_N Recommended Bug Files:"
    echo ""

    SELECTED_FILES=""
    rank=1

    while IFS='|' read -r score filepath filename match_details; do
        [ $rank -gt "$TOP_N" ] && break

        if [ "$score" -ge 8 ]; then
            confidence="VERY HIGH"
        elif [ "$score" -ge 5 ]; then
            confidence="HIGH"
        elif [ "$score" -ge 3 ]; then
            confidence="MEDIUM"
        else
            confidence="LOW"
        fi

        echo "#$rank: $filename"
        echo "    Score: $score points ($confidence confidence)"
        echo "    Matches:$match_details"
        echo "    Path: $filepath"
        echo ""

        if [ $rank -eq 1 ]; then
            SELECTED_FILES="\"$filepath\""
        else
            SELECTED_FILES="$SELECTED_FILES, \"$filepath\""
        fi

        rank=$((rank + 1))
    done <<< "$SORTED"

    # Append common_patterns.md if it scored > 0
    if [ $COMMON_SCORE -gt 0 ]; then
        if [ -n "$SELECTED_FILES" ]; then
            SELECTED_FILES="$SELECTED_FILES, \"$COMMON_PATTERNS\""
        else
            SELECTED_FILES="\"$COMMON_PATTERNS\""
        fi
        echo "Also: common_patterns.md (score: $COMMON_SCORE)"
        echo ""
    fi

    echo "========================================="
    echo "SELECTED_FILES: [$SELECTED_FILES]"
    echo "========================================="
else
    echo "⚠ No matching bug files found for phase: $PHASE"
    echo "  - Check logs manually for novel failure modes"
    echo "  - Consider adding a new BUG-NNN file"

    # Still recommend common_patterns if it matched
    if [ $COMMON_SCORE -gt 0 ]; then
        echo ""
        echo "========================================="
        echo "SELECTED_FILES: [\"$COMMON_PATTERNS\"]"
        echo "========================================="
    fi
fi

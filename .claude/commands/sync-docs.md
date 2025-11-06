Review and synchronize all root documentation files (README.md, CLAUDE.md, ROADMAP.md, ARCHITECTURE.md) to ensure they are:

1. **Consistent** - All dates, statuses, and completion states match across documents
2. **Current** - Reflect the actual state of the project (what's done vs in-progress)
3. **Clear** - Next steps are concrete and actionable, not vague
4. **Accurate** - Recently completed work is properly marked as ✅ complete

## Process

**Step 1: Read all root documents**
- README.md - Project overview and current status
- CLAUDE.md - Developer guidance and current focus
- ROADMAP.md - Development phases and priorities
- ARCHITECTURE.md - System design (check date/version)

**Step 2: Identify inconsistencies**
- Conflicting dates across documents
- Features marked "in progress" that are actually complete
- "Current focus" sections that don't align
- Outdated status descriptions
- Vague "polish" or "complete" without specifics

**Step 3: Cross-reference with recent commits**
- Check git log for last 5-10 commits
- Identify recently completed features not documented
- Look for strategic pivots or architecture changes

**Step 4: Update documents**
- Sync all dates to today's date
- Mark completed work as ✅ done with completion date
- Move finished features from "In Progress" to "Completed"
- Update "Current Focus" sections to match reality
- Make next steps concrete with specific action items
- Ensure comparison tables include recent features

**Step 5: Verify docs/polish-tasks.md or equivalent**
- Check if next steps are prioritized (Highest/High/Medium)
- Ensure tasks are actionable, not vague
- Add "Quick Action Items" if missing

**Step 6: Summary**
After updating, provide a summary showing:
- What dates were synced
- What features were marked complete
- What inconsistencies were resolved
- What the new "current focus" is
- Confidence score (1-10) for documentation accuracy

## Example Issues to Fix

❌ **Before**: "In Progress: GitHub sync completion"
✅ **After**: "Completed (Nov 6): Git-based sync with auto-sync, manual sync, periodic background sync"

❌ **Before**: "Current focus: Polish UI"
✅ **After**: "Current focus: Recording UI polish - error handling, loading states, performance optimization"

❌ **Before**: Last updated dates: Nov 1, Nov 5, Nov 6 (inconsistent)
✅ **After**: All root docs updated: Nov 6, 2025

## Expected Outcome

After running this command, a fresh Claude Code session should be able to:
- Understand what the project is building
- Know exactly what was recently completed
- Have clear, prioritized next steps
- Find no conflicting information about status

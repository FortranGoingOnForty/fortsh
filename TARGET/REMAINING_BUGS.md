# Remaining Terminal Standardization Bugs

**Status**: These are simpler bugs deferred while we fix the critical cursor positioning issue.

## Bug 4: Background Jobs Not Working ❌

**Priority**: HIGH
**Estimated effort**: 3-4 hours

**Issue**: `sleep 100 &` doesn't background properly

**Symptoms**:
```
matthewwolffe@Mac :: ~/D/G/F/fortsh > sleep 100 &-
sleep 200 &
jobs
```

**Root Cause**: Background job execution broken in executor or `&` token parsing

**Files to investigate**:
- `src/parsing/parser.f90` - `&` token parsing
- `src/execution/executor.f90` - Background job handling
- `src/execution/jobs.f90` - add_job() logic

**Fix approach**:
1. Verify `&` token is parsed correctly
2. Check executor creates background jobs
3. Ensure job doesn't block parent

---

## Bug 5: Terminal Title Not Updating ❌

**Priority**: MEDIUM
**Estimated effort**: 1-2 hours

**Issue**: Terminal title stays as "./bin/fortsh" instead of "user@host:path"

**Root Cause**: OSC sequences likely working now (after fort.1 fix), but may need flush or timing

**Files to check**:
- `src/system/interface.f90:1324` - set_terminal_title() - **already has flush after fort.1 fix**
- `src/fortsh.f90` - Verify calls at startup and after cd
- `src/execution/builtins.f90` - cd command

**Fix approach**:
1. Verify set_terminal_title() is called
2. Check if term_supports_color is true
3. Test if escape sequences reach terminal
4. May already be fixed by output_unit change!

---

## Bug 6: UTF-8 Wide Characters Can't Be Inserted ❌

**Priority**: MEDIUM
**Estimated effort**: 3-5 hours

**Issue**: Can't paste emoji or CJK characters - nothing happens

**Root Cause**: Multi-byte UTF-8 character reading broken in read_single_char()

**Files to investigate**:
- `src/system/interface.f90:906` - read_single_char() UTF-8 handling
- `src/io/readline.f90` - Character insertion logic
- `src/io/readline.f90:5229` - utf8_char_width() (this is for display, not input!)

**Fix approach**:
1. Fix read_single_char() to assemble multi-byte sequences
2. Detect UTF-8 lead byte (0xC0-0xFD)
3. Read continuation bytes (0x80-0xBF)
4. Assemble complete character before insertion
5. Handle paste of multi-byte sequences

**Example UTF-8 sequences**:
- Emoji 🚀: `0xF0 0x9F 0x9A 0x80` (4 bytes)
- Chinese 中: `0xE4 0xB8 0xAD` (3 bytes)

---

## Testing After Cursor Fix

Once cursor positioning is fixed, retest all 6 terminal features:

1. ~~Bracketed Paste~~ - Skip (WezTerm doesn't support)
2. ✅ SIGWINCH - **FIXED**
3. 🔧 Cursor Positioning - **IN PROGRESS**
4. ❌ Background Jobs - **DEFERRED**
5. ❌ Terminal Title - **DEFERRED** (may already work!)
6. ❌ UTF-8 Input - **DEFERRED**

**Next steps after cursor fix:**
1. Retest terminal title (might already work!)
2. Fix background jobs
3. Fix UTF-8 input
4. Run full manual test suite
5. Celebrate! 🎉

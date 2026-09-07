# Scene File Binary Conversion Guide

## Problem
- `login.tscn` and other scene files are 1.7+ MB each
- They contain embedded binary font glyph data
- This slows down scene saving/loading

## Solution
Convert text-based `.tscn` files to binary `.scn` format (reduces size by ~60-80%)

---

## Quick Start (2 Steps)

### Step 1: Convert Scenes to Binary
1. Open Godot Editor
2. In the FileSystem panel, locate and open: `ConvertScenesToBinary.gd`
3. Click the ▶ (Play) button at top-right to execute the script
4. Watch the Output console for confirmation

**What it does:**
- Converts `login.tscn` → `login.scn` (~400-500 KB)
- Converts `signup.tscn` → `signup.scn`
- Converts `edit_profile.tscn` → `edit_profile.scn`
- Converts `forgotpass.tscn` → `forgotpass.scn`
- Files are saved with compression enabled

### Step 2: Update Scene References
1. Open: `UpdateSceneReferences.gd`
2. Click the ▶ (Play) button to execute
3. Watch Output to see which files were updated

**What it does:**
- Finds all GDScript files that reference old `.tscn` paths
- Automatically updates them to new `.scn` paths
- UID-based references in project.godot auto-update

---

## Affected Scripts (Updated Automatically)
- ✓ `login_navigation.gd`
- ✓ `signup_navigation.gd` 
- ✓ `forgotpass_navigation.gd` (if exists)
- ✓ `edit_profile_navigation.gd`
- ✓ All other scene change calls

---

## File Size Comparison (Expected)

| File | Before | After | Reduction |
|------|--------|-------|-----------|
| login.tscn | 1.73 MB | ~0.4-0.5 MB | 75-77% |
| signup.tscn | ~1.2 MB | ~0.3-0.4 MB | 70-75% |
| edit_profile.tscn | ~0.8 MB | ~0.2-0.3 MB | 70-75% |
| forgotpass.tscn | ~0.6 MB | ~0.15-0.2 MB | 70-75% |

**Total space saved: ~3-4 MB**

---

## Verification Steps

After running both scripts:

1. **Verify new files exist:**
   - FileSystem → look for `.scn` files alongside `.tscn` files
   
2. **Test scenes still load correctly:**
   - Open each scene in the editor
   - Verify all nodes and properties are intact
   
3. **Run the project:**
   - F5 to test gameplay
   - Verify all scene transitions work

4. **(Optional) Delete old .tscn files:**
   - Once verified, delete the large `.tscn` files
   - Keep `.scn` files

---

## Troubleshooting

**Q: Scripts won't run?**
- A: Enable "Run on Save" in EditorScript settings, or use Ctrl+D in the script editor

**Q: Scenes don't load after conversion?**
- A: Restore from backup and check that project.godot wasn't corrupted
- Run UpdateSceneReferences.gd again to ensure all .tscn → .scn references were updated

**Q: Size reduction is less than expected?**
- A: Scenes may have other large assets. Check for embedded images, audio, or large fonts

---

## Manual Alternative

If scripts don't work, convert manually in Godot Editor:
1. Right-click `login.tscn` in FileSystem
2. Select "Save" (or "Save As...")
3. Choose binary format option
4. Repeat for other scenes
5. Manually update scene references in GDScript files

---

## Files Created

- `ConvertScenesToBinary.gd` - Converts .tscn files to binary .scn format
- `UpdateSceneReferences.gd` - Updates all .gd script references automatically
- This guide file

Run these scripts and you're done!

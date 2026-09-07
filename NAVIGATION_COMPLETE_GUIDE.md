# NAVIGATION & PROFILE SYSTEM - COMPLETE IMPLEMENTATION

## Files Created

### Core Management Scripts
1. **app_setup.gd** - Auto-initializes NavigationHandler & ProfileManager
2. **navigation_handler.gd** - Global navigation hub
3. **profile_manager.gd** - Profile loading/saving

### Screen Navigation Scripts
1. **settings_navigation.gd** - Settings screen (hub)
2. **edit_profile_handler.gd** - Edit profile screen with save
3. **about_navigation.gd** - About Habihero screen
4. **terms_navigation.gd** - Terms (dual path: settings + signup)
5. **privacy_navigation.gd** - Privacy (dual path: settings + signup)
6. **helpsupport_navigation.gd** - Help & Support screen
7. **terms_signup_navigation.gd** - Terms during signup
8. **privacy_signup_navigation.gd** - Privacy during signup
9. **signup_navigation.gd** - UPDATED with profile saving

---

## SETUP INSTRUCTIONS

### Step 1: Enable Autoload
1. Go to **Project → Project Settings → Autoload**
2. Add `app_setup.gd` with name **AppSetup**
3. This auto-initializes NavigationHandler and ProfileManager

### Step 2: Attach Scripts to Scenes

#### settings.tscn
- Attach: `settings_navigation.gd`
- Expected buttons: EditButton, AboutButton, TermsButton, PrivacyButton, HelpButton, LogoutButton
- Or button text: "Edit", "About", "Terms", "Privacy", "Help", "Logout"

#### edit_profile.tscn
- Attach: `edit_profile_handler.gd`
- Required fields:
  - `Panel/VBoxContainer/NameEdit/LineEdit`
  - `Panel/VBoxContainer/GradeEdit/LineEdit`
  - `Panel/VBoxContainer/SectionEdit/LineEdit`
  - `Panel/VBoxContainer/EmailEdit/LineEdit`
- Required buttons: SaveButton, BackButton

#### about.tscn
- Attach: `about_navigation.gd`
- Required button: BackButton

#### terms.tscn
- Attach: `terms_navigation.gd`
- Required elements:
  - `Panel/VBoxContainer/AgreeCheckBox`
  - `Panel/VBoxContainer/AgreeButton`
  - `BackButton`

#### privacy.tscn
- Attach: `privacy_navigation.gd`
- Required elements:
  - `Panel/VBoxContainer/AgreeCheckBox`
  - `Panel/VBoxContainer/AgreeButton`
  - `BackButton`

#### helpsupport.tscn
- Attach: `helpsupport_navigation.gd`
- Required button: BackButton

#### terms_signup.tscn
- Attach: `terms_signup_navigation.gd`
- Required elements:
  - `Panel/VBoxContainer/AgreeCheckBox`
  - `Panel/VBoxContainer/AgreeButton`
  - `BackButton`

#### privacy_signup.tscn
- Attach: `privacy_signup_navigation.gd`
- Required elements:
  - `Panel/VBoxContainer/AgreeCheckBox`
  - `Panel/VBoxContainer/AgreeButton`
  - `BackButton`

#### signup.tscn
- Already has: `signup_navigation.gd` (UPDATED)
- Auto-finds buttons: "Log In", "termslink", "privacylink"

---

## COMPLETE FLOW DIAGRAMS

### SETTINGS FLOW
```
┌─────────────┐
│  SETTINGS   │ (Hub)
└──────┬──────┘
       │
       ├─→ [Edit Profile]
       │   ├─ Load current profile
       │   ├─ Edit fields
       │   ├─ [Save] → Validate → Save to Firebase → SETTINGS
       │   └─ [Back] → SETTINGS
       │
       ├─→ [About]
       │   └─ [Back] → SETTINGS
       │
       ├─→ [Terms]
       │   ├─ [Check box]
       │   ├─ [Agree] → SETTINGS
       │   └─ [Back] → SETTINGS
       │
       ├─→ [Privacy]
       │   ├─ [Check box]
       │   ├─ [Agree] → SETTINGS
       │   └─ [Back] → SETTINGS
       │
       ├─→ [Help & Support]
       │   └─ [Back] → SETTINGS
       │
       └─→ [Log Out] → LOGIN
```

### SIGNUP FLOW
```
┌─────────────┐
│   SIGNUP    │ (Hub)
└──────┬──────┘
       │
       ├─→ [Terms Link]
       │   ├─ Show terms for signup
       │   ├─ [Check box]
       │   ├─ [Agree] → SIGNUP
       │   └─ [Back] → SIGNUP
       │
       ├─→ [Privacy Link]
       │   ├─ Show privacy for signup
       │   ├─ [Check box]
       │   ├─ [Agree] → SIGNUP
       │   └─ [Back] → SIGNUP
       │
       ├─→ [Sign Up Button]
       │   ├─ Collect: name, email, password, grade, section
       │   ├─ Validate fields
       │   ├─ Create Firebase account
       │   ├─ Save profile to Firebase
       │   │  (name, grade_level, section, email)
       │   └─ → QUESTION_12.TSCN
       │
       ├─→ [Log In Link] → LOGIN
```

---

## KEY FEATURES

### Navigation Handler
- Central point for all scene transitions
- Methods: `go_to_*()` functions for each screen
- Prevents accidental duplicate scenes

### Profile Manager
- Wraps FirebaseAuthManager calls
- Safe null checking
- Caches profile fields

### Edit Profile Handler
- Auto-loads current user profile
- Validates name & email
- Saves changes to Firebase
- Shows success feedback

### Settings Navigation
- Directs to all sub-screens
- Logout clears session and goes to login

### Terms & Privacy (Dual Path)
- Works in Settings context (returns to Settings)
- Works in Signup context (returns to Signup)
- Auto-detects context via tree metadata
- Checkbox required (button disabled until checked)

### Signup Navigation (UPDATED)
- Integrated terms/privacy links
- Saves profile immediately after signup
- Collects: name, grade_level, section, email

---

## PROFILE SAVING WORKFLOW

1. **During Signup:**
   - User fills: name, grade, section, email
   - User checks terms checkbox
   - [Sign Up] button creates Firebase account
   - ProfileManager.save_user_profile() saves:
     ```
     {
       "name": "user input",
       "grade_level": "Grade 6",
       "section": "(1) Jose Rizal",
       "email": "user@gmail.com"
     }
     ```
   - Success → question_12.tscn

2. **During Edit Profile:**
   - User navigates to Edit Profile
   - profile_handler loads current profile
   - User modifies fields
   - [Save] validates and saves to Firebase
   - Success → back to Settings

3. **Admin Dashboard Access:**
   - Admin can view all saved profiles
   - See: name, grade, section, email per user
   - Update reflected in real-time

---

## TESTING CHECKLIST

- [ ] Add app_setup.gd to Autoload
- [ ] Navigate: Settings → Edit Profile → Save → Settings
- [ ] Navigate: Settings → About → Back → Settings
- [ ] Navigate: Settings → Terms → Check box → Agree → Settings
- [ ] Navigate: Settings → Privacy → Check box → Agree → Settings
- [ ] Navigate: Settings → Help & Support → Back → Settings
- [ ] Navigate: Settings → Log Out → Login
- [ ] Signup → Terms Link → Check → Agree → Signup
- [ ] Signup → Privacy Link → Check → Agree → Signup
- [ ] Signup → Fill all fields → Sign Up → Verify profile saved in Firebase
- [ ] Admin dashboard shows saved profile data
- [ ] Edit profile → Change name/email → Save → Verify in Firebase

---

## TROUBLESHOOTING

### "Button not found" warnings
- Check button names match script expectations
- Verify button parent paths are correct
- Can customize paths in each script's _ready()

### Profile not saving
- Verify FirebaseAuthManager is initialized
- Check Firebase rules allow write access
- Verify user ID is properly set

### Navigation not working
- Ensure app_setup.gd is in Autoload
- Check scene file names match in navigation_handler.gd
- Verify scenes exist at specified paths

### Checkbox not enabling button
- Verify CheckBox node is found
- Ensure button has _agree_button reference
- Check Signal connections in _ready()

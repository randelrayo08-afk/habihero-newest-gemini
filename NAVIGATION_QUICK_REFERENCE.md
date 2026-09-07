# NAVIGATION SYSTEM - QUICK REFERENCE

## All Scripts & Their Purposes

| Script | Attached To | Purpose |
|--------|------------|---------|
| app_setup.gd | Autoload | Initialize handlers globally |
| navigation_handler.gd | Autoload or tree root | Central navigation hub |
| profile_manager.gd | Autoload or tree root | Profile load/save |
| settings_navigation.gd | settings.tscn | Route to all settings screens |
| edit_profile_handler.gd | edit_profile.tscn | Load/edit/save profile |
| about_navigation.gd | about.tscn | Back to settings |
| terms_navigation.gd | terms.tscn | Terms (settings path) |
| privacy_navigation.gd | privacy.tscn | Privacy (settings path) |
| helpsupport_navigation.gd | helpsupport.tscn | Back to settings |
| terms_signup_navigation.gd | terms_signup.tscn | Terms (signup path) |
| privacy_signup_navigation.gd | privacy_signup.tscn | Privacy (signup path) |
| signup_navigation.gd | signup.tscn | Signup + profile save |

---

## All Controls & Connections

### SETTINGS (settings.tscn)
```
Settings_Navigation.gd watches for:
  ├─ EditButton → go_to_edit_profile()
  ├─ AboutButton → go_to_about()
  ├─ TermsButton → go_to_terms()
  ├─ PrivacyButton → go_to_privacy()
  ├─ HelpButton → go_to_help_support()
  └─ LogoutButton → go_to_login()
```

### EDIT PROFILE (edit_profile.tscn)
```
Edit_Profile_Handler.gd manages:
  ├─ Input: Panel/VBoxContainer/NameEdit/LineEdit
  ├─ Input: Panel/VBoxContainer/GradeEdit/LineEdit
  ├─ Input: Panel/VBoxContainer/SectionEdit/LineEdit
  ├─ Input: Panel/VBoxContainer/EmailEdit/LineEdit
  ├─ Button: SaveButton → _on_save_pressed() → go_to_settings()
  └─ Button: BackButton → go_to_settings()
```

### ABOUT (about.tscn)
```
About_Navigation.gd manages:
  └─ Button: BackButton → go_to_settings()
```

### TERMS (terms.tscn)
```
Terms_Navigation.gd manages:
  ├─ Checkbox: Panel/VBoxContainer/AgreeCheckBox
  ├─ Button: Panel/VBoxContainer/AgreeButton (disabled until checked)
  ├─ Button: BackButton → go_to_settings()
  └─ [Agree] → go_to_settings()
```

### PRIVACY (privacy.tscn)
```
Privacy_Navigation.gd manages:
  ├─ Checkbox: Panel/VBoxContainer/AgreeCheckBox
  ├─ Button: Panel/VBoxContainer/AgreeButton (disabled until checked)
  ├─ Button: BackButton → go_to_settings()
  └─ [Agree] → go_to_settings()
```

### HELP & SUPPORT (helpsupport.tscn)
```
Helpsupport_Navigation.gd manages:
  └─ Button: BackButton → go_to_settings()
```

### TERMS SIGNUP (terms_signup.tscn)
```
Terms_Signup_Navigation.gd manages:
  ├─ Checkbox: Panel/VBoxContainer/AgreeCheckBox
  ├─ Button: Panel/VBoxContainer/AgreeButton (disabled until checked)
  ├─ Button: BackButton → go_to_signup()
  └─ [Agree] → go_to_signup()
```

### PRIVACY SIGNUP (privacy_signup.tscn)
```
Privacy_Signup_Navigation.gd manages:
  ├─ Checkbox: Panel/VBoxContainer/AgreeCheckBox
  ├─ Button: Panel/VBoxContainer/AgreeButton (disabled until checked)
  ├─ Button: BackButton → go_to_signup()
  └─ [Agree] → go_to_signup()
```

### SIGNUP (signup.tscn)
```
Signup_Navigation.gd manages:
  ├─ Link: termslink → _on_terms_link_pressed() → go_to_terms_signup()
  ├─ Link: privacylink → _on_privacy_link_pressed() → go_to_privacy_signup()
  ├─ Button: SignUp → collect payload → create account → save_profile → question_12.tscn
  └─ Link: Log In → go_to_login()
```

---

## Navigation Chains

### Settings Flow
```
Settings
  → Edit Profile [Save] → Settings
  → About [Back] → Settings
  → Terms [Agree] → Settings
  → Privacy [Agree] → Settings
  → Help [Back] → Settings
  → Logout → Login
```

### Signup Flow
```
Signup
  → Terms Link → Terms Signup [Agree] → Signup
  → Privacy Link → Privacy Signup [Agree] → Signup
  → Sign Up [Complete] → Save Profile → question_12.tscn
  → Log In → Login
```

---

## Profile Data Saved

When user signs up or edits profile:
```json
{
  "name": "John Doe",
  "grade_level": "Grade 6",
  "section": "(1) Jose Rizal",
  "email": "john@gmail.com"
}
```

Saved to Firebase at:
- `users/{user_id}/profile/`

---

## How It Works

1. **AppSetup Autoload**
   - Runs at startup
   - Creates NavigationHandler & ProfileManager
   - Makes them globally accessible

2. **Navigation Handler**
   - Single source for all scene changes
   - Prevents duplicate scene loading
   - Manages context (is_from_signup flags)

3. **Profile Manager**
   - Delegates to FirebaseAuthManager
   - Safe null checking
   - Can be used from any scene

4. **Scene Navigation Scripts**
   - Each scene has its own handler
   - Finds NavigationHandler via get_tree().root
   - Calls navigation methods
   - Manages local UI (buttons, inputs)

5. **Profile Handler**
   - Auto-loads profile on scene open
   - Validates before saving
   - Updates Firebase
   - Redirects after save

---

## Direct Function Calls

From any scene, navigate using:

```gdscript
# Get the navigation handler
var nav = get_tree().root.get_node_or_null("NavigationHandler")

# Call navigation methods
nav.go_to_settings()
nav.go_to_edit_profile()
nav.go_to_about()
nav.go_to_terms()
nav.go_to_privacy()
nav.go_to_terms_signup()
nav.go_to_privacy_signup()
nav.go_to_help_support()
nav.go_to_login()
nav.go_to_signup()
nav.navigate_to_scene("res://custom_scene.tscn")
```

---

## Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| Buttons not found | Wrong node name | Update path in script |
| Profile not saving | Auth manager not ready | Wait for _ready() |
| No navigation | AppSetup not in Autoload | Add to Autoload |
| Checkbox not enabling button | Signal not connected | Check _ready() execution |
| Scene file not found | Wrong path | Verify scene file exists |

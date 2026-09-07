# Navigation & Profile System - Complete Setup Guide

## Step 1: Add AppSetup as Autoload
1. Go to **Project → Project Settings → Autoload**
2. Add `app_setup.gd` with name `AppSetup`
3. This will initialize NavigationHandler and ProfileManager globally

## SETTINGS.TSCN Setup

### Script to Attach: `settings_navigation.gd`

### Required Buttons (in Panel/VBoxContainer or similar):
- `EditButton` - When clicked → goes to edit_profile.tscn
- `AboutButton` - When clicked → goes to about.tscn
- `TermsButton` - When clicked → goes to terms.tscn
- `PrivacyButton` - When clicked → goes to privacy.tscn
- `HelpButton` - When clicked → goes to helpsupport.tscn
- `LogoutButton` - When clicked → goes to login.tscn

### Flow:
```
Settings (start)
  ├→ Edit Profile → [Save] → Settings
  ├→ About → [Back] → Settings
  ├→ Terms → [Agree & Continue] → Settings
  ├→ Privacy → [Agree & Continue] → Settings
  ├→ Help & Support → [Back] → Settings
  └→ Logout → Login
```

---

## EDIT_PROFILE.TSCN Setup

### Script to Attach: `edit_profile_handler.gd`

### Required UI Elements:
- **Input Fields** (LineEdit nodes):
  - `Panel/VBoxContainer/NameEdit/LineEdit` - User name
  - `Panel/VBoxContainer/GradeEdit/LineEdit` - Grade level
  - `Panel/VBoxContainer/SectionEdit/LineEdit` - Section
  - `Panel/VBoxContainer/EmailEdit/LineEdit` - Email

- **Buttons**:
  - `Panel/VBoxContainer/SaveButton` - Saves profile to Firebase → goes back to Settings
  - `BackButton` - Goes back to Settings without saving

### Features:
- Auto-loads current user profile when scene opens
- Validates name and email before saving
- Saves to Firebase
- Updates reflected in admin dashboard

### Flow:
```
Settings → Edit Profile (loads current data)
  ├→ [Modify fields]
  ├→ [Click Save] → Validate → Save to Firebase → Settings
  └→ [Click Back] → Settings (no save)
```

---

## ABOUT.TSCN Setup

### Script to Attach: `about_navigation.gd`

### Required Buttons:
- `BackButton` - Goes back to Settings

### Flow:
```
Settings → About
  └→ [Back Button] → Settings
```

---

## TERMS.TSCN Setup

### Script to Attach: `terms_navigation.gd`

### Required UI Elements:
- `Panel/VBoxContainer/AgreeCheckBox` - CheckBox for agreement
- `Panel/VBoxContainer/AgreeButton` - Agree & Continue button (disabled until checkbox is checked)
- `BackButton` - Go back

### Features:
- Checkbox MUST be checked
- "Agree & Continue" button is DISABLED until checkbox is checked
- Auto-detects if coming from Settings or Signup
- Returns to appropriate screen

### Flow:
```
Settings → Terms
  ├→ [Check checkbox] → Enable Agree button
  ├→ [Click Agree] → Settings
  └→ [Back] → Settings

Signup → Terms (signup)
  ├→ [Check checkbox] → Enable Agree button
  ├→ [Click Agree] → Signup
  └→ [Back] → Signup
```

---

## PRIVACY.TSCN Setup

### Script to Attach: `privacy_navigation.gd`

### Required UI Elements:
- `Panel/VBoxContainer/AgreeCheckBox` - CheckBox for agreement
- `Panel/VBoxContainer/AgreeButton` - Agree & Continue button (disabled until checkbox is checked)
- `BackButton` - Go back

### Features:
- Same as Terms - checkbox required
- Auto-detects if coming from Settings or Signup
- Returns to appropriate screen

### Flow:
```
Settings → Privacy
  ├→ [Check checkbox] → Enable Agree button
  ├→ [Click Agree] → Settings
  └→ [Back] → Settings

Signup → Privacy (signup)
  ├→ [Check checkbox] → Enable Agree button
  ├→ [Click Agree] → Signup
  └→ [Back] → Signup
```

---

## HELPSUPPORT.TSCN Setup

### Script to Attach: `helpsupport_navigation.gd`

### Required Buttons:
- `BackButton` - Goes back to Settings

### Flow:
```
Settings → Help & Support
  └→ [Back Button] → Settings
```

---

## SIGNUP.TSCN Setup

### Script Already Attached: `signup_navigation.gd` (UPDATED)

### Required UI Elements:
- Name, Email, Password fields (already exist)
- Grade & Section selectors (already exist)
- Sign Up button (already exists)
- "Log In" link (already exists)
- `termslink` - LinkButton for Terms
- `termslink/privacylink` or `privacylink` - LinkButton for Privacy
- `CheckBox` - Terms & conditions agreement checkbox

### Features:
- Collects name, grade, section, email
- Links to Terms and Privacy pages
- Saves profile to Firebase after signup
- Auto-redirects after successful signup

### Flow:
```
Signup (start)
  ├→ [Click Terms link] → Terms (signup)
  │   └→ [Agree] → Signup
  ├→ [Click Privacy link] → Privacy (signup)
  │   └→ [Agree] → Signup
  ├→ [Fill all fields + accept terms + Sign Up]
  │   ├→ Validate fields
  │   ├→ Create Firebase account
  │   ├→ Save profile (name, grade, section, email)
  │   └→ [Success] → question_12.tscn
  └→ [Log In link] → Login
```

---

## TERMS_SIGNUP.TSCN Setup

### Script to Attach: `terms_signup_navigation.gd`

### Required UI Elements:
- `Panel/VBoxContainer/AgreeCheckBox` - CheckBox for agreement
- `Panel/VBoxContainer/AgreeButton` - Agree & Continue button (disabled until checked)
- `BackButton` - Go back

### Features:
- ONLY used during signup flow
- Returns to Signup screen after agreement
- Checkbox required before enabling Agree button

### Flow:
```
Signup → Terms (signup)
  ├→ [Check checkbox] → Enable Agree button
  ├→ [Click Agree] → Signup
  └→ [Back] → Signup
```

---

## PRIVACY_SIGNUP.TSCN Setup

### Script to Attach: `privacy_signup_navigation.gd`

### Required UI Elements:
- `Panel/VBoxContainer/AgreeCheckBox` - CheckBox for agreement
- `Panel/VBoxContainer/AgreeButton` - Agree & Continue button (disabled until checked)
- `BackButton` - Go back

### Features:
- ONLY used during signup flow
- Returns to Signup screen after agreement
- Checkbox required before enabling Agree button

### Flow:
```
Signup → Privacy (signup)
  ├→ [Check checkbox] → Enable Agree button
  ├→ [Click Agree] → Signup
  └→ [Back] → Signup
```

---

## LOGIN.TSCN Setup

### No script changes needed
- Existing login flow continues as-is
- Users sign in and proceed to question_12.tscn

---

## COMPLETE NAVIGATION SUMMARY

```
SETTINGS FLOW:
Settings (hub)
  ├→ Edit Profile ←→ Settings
  ├→ About → Settings
  ├→ Terms → Settings
  ├→ Privacy → Settings
  ├→ Help & Support → Settings
  └→ Log Out → Login

SIGNUP FLOW:
Signup (hub)
  ├→ Terms (signup) → Signup
  ├→ Privacy (signup) → Signup
  ├→ Log In → Login
  └→ [Signup Complete] → Save Profile → question_12.tscn

LOGIN:
Login → [Authenticate] → question_12.tscn
```

---

## Quick Checklist

- [ ] Add `app_setup.gd` to Autoload as "AppSetup"
- [ ] Attach `settings_navigation.gd` to `settings.tscn`
- [ ] Attach `edit_profile_handler.gd` to `edit_profile.tscn`
- [ ] Attach `about_navigation.gd` to `about.tscn`
- [ ] Attach `terms_navigation.gd` to `terms.tscn`
- [ ] Attach `privacy_navigation.gd` to `privacy.tscn`
- [ ] Attach `helpsupport_navigation.gd` to `helpsupport.tscn`
- [ ] Attach `terms_signup_navigation.gd` to `terms_signup.tscn`
- [ ] Attach `privacy_signup_navigation.gd` to `privacy_signup.tscn`
- [ ] Verify button paths in each script
- [ ] Test Settings flow
- [ ] Test Signup flow
- [ ] Verify profile saves to Firebase
- [ ] Verify admin can see saved profiles

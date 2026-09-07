# HabiHero API Reference - New Functions

## Firebase Auth Manager (`firebase_auth_manager.gd`)

### Level Management

#### `load_level(user_id: String, callback: Callable)`
**Description:** Retrieve user's current level from Firebase

**Parameters:**
- `user_id`: User identifier (email or ID)
- `callback`: Function(ok: bool, level: Variant) - Called with result

**Example:**
```gdscript
auth_manager.load_level("user@email.com", func(ok, level):
    if ok:
        print("Current level: ", level)
)
```

**Returns:** Level (1-based), defaults to 1

---

#### `save_level(user_id: String, level: int, callback: Callable)`
**Description:** Save user's level to Firebase

**Parameters:**
- `user_id`: User identifier
- `level`: New level (auto-clamped to min 1)
- `callback`: Optional completion callback

**Example:**
```gdscript
auth_manager.save_level("user@email.com", 5, func(ok, _):
    if ok:
        print("Level saved!")
)
```

---

#### `add_experience(user_id: String, amount: int, callback: Callable)`
**Description:** Add experience points and auto-level up if threshold reached

**Parameters:**
- `user_id`: User identifier
- `amount`: EXP amount to add (auto-clamped to ≥0)
- `callback`: Function(ok: bool, new_exp: int) - Called with new total

**Example:**
```gdscript
auth_manager.add_experience("user@email.com", 50, func(ok, new_exp):
    print("New experience: ", new_exp)
    if new_exp >= 100:
        print("Level up!")
)
```

**Auto-Levels Up When:** Experience ≥ (level × 100)

---

#### `_check_and_update_level(user_id: String, current_experience: int)`
**Description:** Internal function that checks if level up needed and updates

**Note:** Called automatically by `add_experience()`, no need to call directly

---

### Mood Management

#### `get_todays_mood(user_id: String, callback: Callable)`
**Description:** Get the user's mood for today (if already set)

**Parameters:**
- `user_id`: User identifier
- `callback`: Function(ok: bool, mood: String) - "not_set" if not set today

**Example:**
```gdscript
auth_manager.get_todays_mood("user@email.com", func(ok, mood):
    if ok and mood != "not_set":
        print("Today's mood: ", mood)
    else:
        print("No mood set today")
)
```

**Returns:** Mood string (happy, sad, angry, calm, excited, angel) or "not_set"

---

#### `get_weekly_moods(user_id: String, callback: Callable)`
**Description:** Get all moods from last 7 days

**Parameters:**
- `user_id`: User identifier
- `callback`: Function(ok: bool, moods: Array[String]) - 7 entries, oldest to newest

**Example:**
```gdscript
auth_manager.get_weekly_moods("user@email.com", func(ok, moods):
    if ok:
        for i in range(moods.size()):
            print("Day %d: %s" % [i, moods[i] if moods[i] else "not set"])
)
```

**Returns:** Array of 7 mood strings (empty string for missing days)

---

## Admin Helper (`admin_helper.gd`)

### Journal Management

#### `get_all_journal_entries(callback: Callable)`
**Description:** Retrieve all journal entries from all users (admin function)

**Parameters:**
- `callback`: Function(ok: bool, entries: Dictionary) - Structure: {user_id: {entry_key: {journal data}}}

**Example:**
```gdscript
admin_helper.get_all_journal_entries(func(ok, entries):
    if ok:
        print("Total users: ", entries.keys().size())
        for user_key in entries:
            print("User: ", user_key, " has ", entries[user_key].keys().size(), " entries")
)
```

---

#### `get_user_journals(user_identifier: String, callback: Callable)`
**Description:** Get all journal entries for a specific user

**Parameters:**
- `user_identifier`: User email or ID
- `callback`: Function(ok: bool, journals: Dictionary) - {entry_key: {journal data}}

**Example:**
```gdscript
admin_helper.get_user_journals("user@email.com", func(ok, journals):
    if ok:
        for key in journals:
            var entry = journals[key]
            print(entry.created_at + ": " + entry.entry)
)
```

---

#### `export_journal_report(output_path: String)`
**Description:** Export all journals to a text file

**Parameters:**
- `output_path`: File path (default: "user://journal_report.txt")

**Example:**
```gdscript
admin_helper.export_journal_report("user://my_journals.txt")
# File created with all journals formatted
```

---

### Mood Analytics

#### `get_all_mood_entries(callback: Callable)`
**Description:** Retrieve all mood entries from all users for analysis

**Parameters:**
- `callback`: Function(ok: bool, moods: Dictionary) - Structure: {user_id: {mood_key: {mood data}}}

**Example:**
```gdscript
admin_helper.get_all_mood_entries(func(ok, moods):
    if ok:
        for user in moods:
            var mood_count = moods[user].keys().size()
            print(user + ": " + str(mood_count) + " mood entries")
)
```

---

### User Tracking

#### `get_user_level_and_exp(user_identifier: String, callback: Callable)`
**Description:** Get user's level, experience, and streak stats

**Parameters:**
- `user_identifier`: User email or ID
- `callback`: Function(ok: bool, stats: Dictionary) - {level, experience, checkin_streak, last_checkin_date}

**Example:**
```gdscript
admin_helper.get_user_level_and_exp("user@email.com", func(ok, stats):
    if ok:
        print("Level: ", stats.level)
        print("EXP: ", stats.experience)
        print("Streak: ", stats.checkin_streak + " days")
)
```

---

## Scene Navigation Scripts

### Myjournal Navigation (`myjournal_navigation.gd`)

####`_save_entry()`
**Description:** Save current journal entry to Firebase

**Triggers:**
- Clear text input
- Reload journal list
- Show error if failed

---

#### `_load_saved_entries()`
**Description:** Load and display user's journal history (auto-called at startup)

**Display:** Shows up to 10 most recent entries, newest first

---

### Moodcheck Navigation (`moodcheck_navigation.gd`)

#### `_check_today_mood_exists()`
**Description:** Check if user already submitted mood today

**Shows:** Info message if mood already set

---

#### `_on_continue_pressed()`
**Enhanced to:**
- Validate mood selection
- Add experience reward (+10 EXP)
- Save with daily validation
- Transition to home screen

---

## Data Structure Reference

### Journal Entry Object
```gdscript
{
    "user_id": "user@email.com",
    "entry": "Journal text (max 300 chars)",
    "created_at": "2026-08-29 10:30:45",
    "timestamp": "1234567890_123"
}
```

### Mood Entry Object
```gdscript
{
    "mood": "happy|sad|angry|calm|excited|angel",
    "date": "2026-08-29",
    "selected_at": "2026-08-29 10:30:45",
    "saved_at": "2026-08-29 10:30:45",
    "scene": "moodcheck",
    "user_id": "user@email.com"
}
```

### User Profile Object
```gdscript
{
    "level": 1,
    "experience": 0,
    "coin_balance": 0,
    "checkin_streak": 0,
    "last_checkin_date": "2026-08-29",
    "created_at": "2026-08-29 10:00:00",
    "updated_at": "2026-08-29 10:30:45"
}
```

---

## Common Usage Patterns

### Pattern 1: Add Experience (Common)
```gdscript
var auth_manager = get_tree().root.get_node("FirebaseAuthManager")
var user_id = get_tree().root.get_node("UserSession").get_current_user_id()
auth_manager.add_experience(user_id, 50, func(ok, new_exp):
    if ok:
        print("Added 50 EXP, now at: ", new_exp)
)
```

### Pattern 2: Check User Level (Admin)
```gdscript
var admin = get_node("AdminHelper")
admin.get_user_level_and_exp("user@email.com", func(ok, stats):
    print("User is Level %d with %d EXP" % [stats.level, stats.experience])
)
```

### Pattern 3: Export All Data (Admin)
```gdscript
var admin = get_node("AdminHelper")
admin.export_journal_report()  # Uses default path
admin.get_all_mood_entries(func(ok, moods):
    print("Mood data retrieved for analysis")
)
```

### Pattern 4: Display Level on UI
```gdscript
auth_manager.load_level(user_id, func(ok, level):
    if ok:
        _level_label.text = "Level " + str(level)
)
auth_manager.load_experience(user_id, func(ok, exp):
    if ok:
        var required = level * 100
        _progress_bar.value = float(exp) / float(required)
)
```

---

## Error Handling

All callbacks follow pattern:
```gdscript
callback(ok: bool, data: Variant)
```

Where:
- `ok`: true if operation succeeded
- `data`: Result data or error info

Example:
```gdscript
func(ok, result):
    if ok:
        # Success - use result
        print(result)
    else:
        # Failure - result contains error
        print("Error: ", result)
```

---

## Firebase Paths Used

```
/users/{uid}/profile/          - User stats (level, exp, etc.)
/users/{uid}/journal/          - All journal entries
/users/{uid}/moodcheck/        - All mood entries
/users/{uid}/progress/         - Progress tracking
/sessions/current/             - Active session
```

---

## Permissions Required

For admin functions to work, Firebase rules must allow:
- `read: /users/**` (at minimum for admin accounts)
- Recommended: Role-based security in Firebase Console

---

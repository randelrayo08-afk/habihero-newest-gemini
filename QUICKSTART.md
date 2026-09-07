# HabiHero Journal & Leveling System - Quick Start Guide

## 🎯 What's New

Your HabiHero app now has a complete journal system, experience/leveling mechanics, and real-time mood tracking - all integrated with Firebase!

---

## ✨ Feature Highlights

### 1. **Journal System** 📓
- Users can write and save journal entries (up to 300 characters)
- Entries are automatically synced to Firebase
- Entry history displays the 10 most recent entries
- Admin can view all submissions with timestamps
- **File:** `myjournal_navigation.gd`

### 2. **Experience & Leveling** 🆙
- Users earn experience points for daily actions (e.g., mood check = +10 EXP)
- Automatic level up when experience threshold is reached
- **Level-up formula:** Level × 100 EXP required
  - Level 1 → 100 EXP
  - Level 2 → 200 EXP
  - Level 3 → 300 EXP (etc.)
- Real-time display on home screen Panel 4
- **Files:** `firebase_auth_manager.gd`, `homebut.gd`

### 3. **Mood Tracking** 🎭
- Daily mood check with 6 emotions: happy, sad, angry, calm, excited, angel
- Daily validation (prevents duplicate submissions)
- Mood data synced to Firebase
- Real-time display on home screen with color coding
- Weekly mood history tracking
- **Files:** `moodcheck_navigation.gd`, `firebase_auth_manager.gd`

### 4. **Firebase Sync** ☁️
- All user data automatically synced to Firebase
- Local caching for offline support
- Async callbacks for all operations
- **Data stored at:** `/users/{uid}/journal/`, `/users/{uid}/profile/`, `/users/{uid}/moodcheck/`

### 5. **Admin Features** 🛠️
- View all journal submissions from all users
- Track user level and experience progression
- Export journal reports to file
- Mood analytics access
- **File:** `admin_helper.gd`

---

## 🚀 Getting Started

### For End Users:

#### 1. **Write a Journal Entry**
   - Open **My Journal**
   - Type your journal entry (max 300 characters)
   - Click **SAVE**
   - Entry instantly appears in history and syncs to Firebase

#### 2. **Check Your Mood**
   - Open **Mood Check**
   - Select your current mood
   - Click **Continue**
   - Earn **+10 EXP** and see level progression

#### 3. **Track Your Progress**
   - View **Level** display on home screen
   - See **EXP Progress Bar** (auto-fills as you level up)
   - Check **Today's Mood** status

### For Admins:

#### 1. **View All Journals**
```gdscript
var admin = get_node("AdminHelper")
admin.get_all_journal_entries(func(ok, entries):
    if ok:
        for user in entries:
            for date_key in entries[user]:
                var entry = entries[user][date_key]
                print(user + ": " + entry.entry)
)
```

#### 2. **Export Journal Report**
```gdscript
var admin = get_node("AdminHelper")
admin.export_journal_report("user://journal_report.txt")
# Opens: user://journal_report.txt
```

#### 3. **Check User's Level/EXP**
```gdscript
var admin = get_node("AdminHelper")
admin.get_user_level_and_exp("user@email.com", func(ok, stats):
    print("Level: ", stats.level)
    print("EXP: ", stats.experience)
    print("Streak: ", stats.checkin_streak)
)
```

#### 4. **Get All Mood Data**
```gdscript
var admin = get_node("AdminHelper")
admin.get_all_mood_entries(func(ok, all_moods):
    if ok:
        for user in all_moods:
            for mood_key in all_moods[user]:
                var mood = all_moods[user][mood_key]
                print(user + " mood: " + mood.mood)
)
```

---

## 📊 Firebase Data Structure

### User Profile
```
users/user@email_com/profile/
├── level: 1
├── experience: 50
├── checkin_streak: 3
├── last_checkin_date: "2026-08-29"
└── created_at: "2026-08-29T10:00:00Z"
```

### Journal Entries
```
users/user@email_com/journal/
├── entry_1234567890_123:
│   ├── entry: "Today was great..."
│   ├── user_id: "user@email.com"
│   ├── created_at: "2026-08-29 10:30:45"
│   └── timestamp: "1234567890_123"
└── entry_1234567891_456: {...}
```

### Mood Entries
```
users/user@email_com/moodcheck/
├── mood_1234567890_123:
│   ├── mood: "happy"
│   ├── date: "2026-08-29"
│   ├── selected_at: "2026-08-29 10:30:45"
│   └── saved_at: "2026-08-29 10:30:45"
└── mood_1234567891_456: {...}
```

---

## 🔧 Configuration

### Experience Rewards
Edit `moodcheck_navigation.gd` line ~190:
```gdscript
if _auth_manager.has_method("add_experience"):
    _auth_manager.add_experience(user_id, 10, func(_ok, _exp):  # Change 10 to different value
        print("Mood check reward: +10 EXP")
    )
```

### Level-Up Threshold
Edit `firebase_auth_manager.gd` line ~420:
```gdscript
var exp_required: int = level * 100  # Change formula here
```

### UI Update Frequency
Edit `homebut.gd` line ~20:
```gdscript
timer.wait_time = 30.0  # Change 30 to different seconds
```

---

## ✅ Testing

### Quick Test Checklist:

1. **Journal**: Write entry → Click Save → Entry appears in list
2. **Level**: Add experience → Level should increase automatically
3. **Mood**: Select mood → Home screen shows "Today's Mood: [emotion]"
4. **Firebase**: Go offline → Make changes → Go online → Changes sync
5. **Admin**: Call export function → Opens file with all submissions

---

## 📝 Modified Files

- ✅ `firebase_auth_manager.gd` - Backend (added 7 new functions)
- ✅ `myjournal_navigation.gd` - Journal UI (improved save/load)
- ✅ `moodcheck_navigation.gd` - Mood UI (added validation & rewards)
- ✅ `homebut.gd` - Home display (added level/exp/mood display)
- ✅ `admin_helper.gd` - Admin features (added journal/mood viewing)
- ✅ `home_data_manager.gd` - Helper (new file, optional)

---

## 🐛 Troubleshooting

### Journal not saving?
- Check Firebase auth token is valid
- Verify `FirebaseAuthManager` is in scene tree
- Check console for error messages

### Level not updating?
- Experience must reach `level × 100` to level up
- Level checks automatically after experience changes
- Check profile in Firebase to verify data saved

### Mood not showing on home?
- Mood check must be done today (checks date)
- Home screen refreshes every 30 seconds
- Check console for `get_todays_mood` results

### Admin functions not working?
- Ensure `FirebaseRTDB` is properly initialized
- Check Firebase permissions allow read access
- Verify `admin_helper.gd` is added to scene

---

## 🎓 Developer Notes

### Adding New Experience Rewards
1. Find where you want to reward EXP
2. Get user_id from session
3. Call: `auth_manager.add_experience(user_id, amount, callback)`

### Adding New Mood Types
Edit `moodcheck.tscn` to add more buttons, they'll automatically register as moods

### Custom Admin Reports
Extend `admin_helper.gd` with new export functions following the pattern

### Real-Time Updates
All functions use callbacks - subscribe to changes in your UI code

---

## 📞 Support

For issues or questions:
1. Check console output for error messages
2. Review Firebase rules and permissions
3. Check internet connection for sync failures
4. Verify all nodes are in scene tree

---

## 🎉 You're All Set!

Your journal, leveling, and mood tracking system is ready to use. Start by:
1. Running the app
2. Writing a journal entry
3. Checking your mood
4. Watching your level increase!

Happy habituating! 🚀

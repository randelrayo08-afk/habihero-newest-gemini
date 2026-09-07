# SHOP SYSTEM - COMPLETE SETUP GUIDE

## Overview
The shop system allows users to:
- View available items to purchase
- Scroll horizontally through items (left/right buttons)
- Buy items using coins
- See real-time coin balance updates
- All purchases saved to Firebase

---

## Setup Instructions

### Step 1: Attach Script to Shop Scene
1. Open **Shop.tscn**
2. In the Inspector, attach `shop_handler.gd` to the root SHOP node
3. Save the scene

### Step 2: Create Required UI Elements

Your Shop.tscn needs these elements:

#### Coins Display Label
- Path: `Panel3/Label`
- Purpose: Shows current coin balance
- Initial text: "💰 Coins: 0"

#### Scroll Container & Items Container
- Path: `Panel4/Panel6/Panel` (ScrollContainer)
- The HBoxContainer inside it (will be created auto if missing)
- Purpose: Holds shop items horizontally

#### Scroll Buttons
- Left Button: `Panel4/Panel6/LeftButton`
- Right Button: `Panel4/Panel6/RightButton`
- Purpose: Navigate through items

### Step 3: Configure UI (Optional)

The shop_handler.gd will auto-create:
- ✅ Item panels with icons, names, descriptions
- ✅ Prices in coins
- ✅ BUY buttons for each item
- ✅ Proper styling and layout
- ✅ Scroll animations

---

## Shop Features

### 1. Items Display
```
Each item shows:
- Icon (emoji: 💊 ⭐ 🛡️ etc)
- Name (Power Potion, Golden Star, etc)
- Description
- Price (in coins)
- BUY button
```

### 2. Horizontal Scrolling
```
[LEFT] [Item 1] [Item 2] [Item 3] [RIGHT]
        ↑ Currently visible items
```

- Left arrow: Scroll left through items
- Right arrow: Scroll right through items
- Buttons auto-enable/disable based on position
- Smooth animation (0.3 seconds)

### 3. Purchase System
```
User clicks BUY
  ↓
Check if has enough coins
  ↓
If YES: Deduct coins + Save to Firebase + Show "✨ Purchased!"
If NO: Show "😢 Not enough coins!"
```

### 4. Coin Balance
- Displays: `💰 Coins: XXX`
- Updates in real-time after purchase
- Loads from Firebase on startup

---

## How the Shop Works

### On Scene Load:
1. Load user ID from FirebaseAuthManager
2. Load user's coin balance
3. Display coins balance
4. Create shop item UI panels
5. Setup scroll buttons

### When User Clicks BUY:
1. Get item price
2. Check if user has enough coins
3. If YES:
   - Calculate new balance
   - Save to Firebase
   - Update UI
   - Show success message
4. If NO:
   - Show error message

### Scroll Navigation:
1. User clicks LEFT/RIGHT button
2. Calculate which items to show
3. Animate scroll to new position
4. Update button states (enable/disable)

---

## Default Shop Items

The shop comes with 5 default items:

| # | Name | Price | Icon | Description |
|----|------|-------|------|-------------|
| 1 | Power Potion | 100 | 💊 | Boost your power! |
| 2 | Speed Scroll | 150 | 📜 | Move faster! |
| 3 | Shield Stone | 200 | 🛡️ | Protect yourself! |
| 4 | Golden Star | 250 | ⭐ | Rare treasure! |
| 5 | Magic Wand | 300 | ✨ | Cast spells! |

You can modify these in `_shop_items` array in shop_handler.gd

---

## Firebase Integration

### Data Structure
```
users/
  {user_id}/
    profile/
      coin_balance: 1000
```

### Methods Used
- `load_coin_balance(user_id, callback)` - Get current coins
- `save_coin_balance(user_id, amount, callback)` - Save new balance

---

## Customization

### Add More Items
Edit `shop_handler.gd` line ~22-26:
```gdscript
var _shop_items: Array = [
    {"id": "item_1", "name": "New Item", "price": 500, "icon": "🎁", "description": "Special gift!"},
    # Add more items...
]
```

### Change Items Per View
Edit line ~35:
```gdscript
var _items_per_view: int = 3  # Change to 2, 4, 5, etc.
```

### Modify Item Panel Size
Edit line ~114 in `_create_item_panel()`:
```gdscript
item_panel.custom_minimum_size = Vector2(200, 250)  # Change width/height
```

### Change Scroll Speed
Edit line ~174:
```gdscript
tween.tween_property(_scroll_container, "scroll_horizontal", target_scroll, 0.3)
                                                                        ↑
                                                                   Time in seconds
```

---

## Troubleshooting

### Problem: Items not showing
**Solution:** Verify Panel4/Panel6/Panel exists in Shop.tscn
- Create the structure if missing

### Problem: Buy button not working
**Solution:** Check FirebaseAuthManager is initialized
- Verify user is logged in
- Check Firebase Realtime Database has write permissions

### Problem: Coins not updating
**Solution:** Check coin_balance field in Firebase
- Verify path: `users/{user_id}/profile/coin_balance`
- Check database rules allow write access

### Problem: Scroll buttons not appearing
**Solution:** Create buttons in scene
- Create `Panel4/Panel6/LeftButton` (Button node)
- Create `Panel4/Panel6/RightButton` (Button node)
- Script will wire them automatically

### Problem: Script doesn't find buttons
**Solution:** Verify node paths match exactly
- Check exact path in Inspector
- Update path in script if different

---

## API Methods (For Programmers)

### Load Shop
```gdscript
# Automatically called in _ready()
_initialize_shop()
```

### Programmatic Purchase
```gdscript
var item = {"id": "item_1", "name": "test", "price": 100}
_on_buy_pressed(item)
```

### Update Coins Display
```gdscript
_user_coins = 500
_update_coins_display()
```

### Check Coins
```gdscript
if _user_coins >= 100:
    print("User can afford item")
```

---

## Complete Shop.tscn Example Structure

```
SHOP (Control)
├── Panel (background)
├── Panel2 (navigation buttons)
├── Panel3 (coins display)
│   └── Label (shows: "💰 Coins: XXX")
└── Panel4 (shop container)
    └── Panel6 (scroll area)
        ├── LeftButton (scroll left)
        ├── Panel (ScrollContainer content)
        │   └── HBoxContainer (created by script)
        │       ├── Item Panel 1
        │       ├── Item Panel 2
        │       ├── Item Panel 3
        │       └── ... more items
        └── RightButton (scroll right)
```

---

## Testing Checklist

- [ ] Attach shop_handler.gd to Shop.tscn
- [ ] Run game and go to shop
- [ ] Coins display shows current balance
- [ ] Items appear in scroll view
- [ ] Click LEFT button → items scroll left
- [ ] Click RIGHT button → items scroll right
- [ ] Click BUY on an item
- [ ] If enough coins: Purchase succeeds, coins updated
- [ ] If not enough coins: See error message
- [ ] Verify Firebase saved new balance
- [ ] Restart and verify coins persisted

---

## Summary

**The shop system is now fully functional with:**
- ✅ 5 built-in items
- ✅ Smooth horizontal scrolling
- ✅ Buy mechanism with coin deduction
- ✅ Firebase integration
- ✅ Real-time updates
- ✅ User-friendly UI
- ✅ Auto-creation of UI elements

**Just attach the script and run!** 🛍️

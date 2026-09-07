# SHOP SYSTEM - QUICK REFERENCE

## One-Step Setup
1. Attach **shop_handler.gd** to the root SHOP node in Shop.tscn
2. Done! 🎉

---

## UI Structure Required

```
Panel3
└── Label ← Shows coins "💰 Coins: XXX"

Panel4/Panel6
├── LeftButton ← Scroll left
├── Panel ← ScrollContainer with HBoxContainer inside
└── RightButton ← Scroll right
```

---

## What Happens Automatically

✅ Items created dynamically with:
- Icon + Name + Description
- Price display
- BUY button
- Nice styling

✅ Left/Right buttons:
- Enable/disable based on position
- Smooth scroll animation

✅ Coins system:
- Loads on startup
- Updates after purchase
- Saves to Firebase

---

## User Flow

```
1. User sees shop with 5 items
2. User clicks LEFT/RIGHT to browse
3. User clicks BUY on an item
4. If enough coins:
   ✨ Purchase confirmed
   Coins updated
   Saved to Firebase
5. If not enough coins:
   😢 Error message
```

---

## Shop Items (Default)

| Icon | Item | Price |
|------|------|-------|
| 💊 | Power Potion | 100 |
| 📜 | Speed Scroll | 150 |
| 🛡️ | Shield Stone | 200 |
| ⭐ | Golden Star | 250 |
| ✨ | Magic Wand | 300 |

Edit in `_shop_items` array to change items

---

## Firebase Data

```
users/{user_id}/profile/coin_balance = 1000
```

Automatically:
- Loaded on startup
- Updated after purchase
- Displayed in UI

---

## Customization Shortcuts

**More/fewer items visible:**
Line 35: `var _items_per_view: int = 3`

**Item panel size:**
Line 114: `custom_minimum_size = Vector2(200, 250)`

**Scroll speed:**
Line 174: `.tween_property(..., 0.3)` ← seconds

**Add new items:**
Edit `_shop_items` array with:
```
{"id": "item_X", "name": "Name", "price": 100, "icon": "🎁", "description": "Text"}
```

---

## Common Issues & Quick Fixes

| Issue | Fix |
|-------|-----|
| Items not showing | Verify `Panel4/Panel6/Panel` exists |
| Buy not working | Check user logged in + Firebase connected |
| Coins not updating | Verify `coin_balance` in Firebase profile |
| Buttons not found | Create Button nodes for LeftButton/RightButton |
| Scroll too fast/slow | Adjust time value in scroll animation |

---

## Files

- **shop_handler.gd** - Main shop script (attach to Shop.tscn)
- **firebase_auth_manager.gd** - Has new `save_coin_balance()` method
- **SHOP_SETUP_GUIDE.md** - Detailed setup (this file)

---

## That's It! 

Your shop is now fully functional with:
- Dynamic item creation
- Left/right scrolling
- Purchase system
- Coin management
- Firebase integration

**Attach and run!** 🛍️

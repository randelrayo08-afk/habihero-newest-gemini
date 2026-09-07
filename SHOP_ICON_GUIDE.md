# Shop Icon Guide & Functions

## Icon Categories & Recommendations

### **Health & Potions** 💊
- `💊` - Power Potion (Health boost)
- `🩹` - Healing Band (Minor heal)
- `🧪` - Potion (Generic magic items)
- `💉` - Vaccine/Shield (Protection)

### **Movement & Speed** 🏃
- `📜` - Speed Scroll (Movement boost)
- `⚡` - Lightning/Energy (Fast movement)
- `🚀` - Rocket (Super speed)
- `🌪️` - Tornado (Quick escape)

### **Defense & Armor** 🛡️
- `🛡️` - Shield Stone (Defense)
- `🪨` - Rock/Stone (Protection)
- `🔐` - Lock/Safe (Security)
- `⚙️` - Gear/Armor (Equipment)

### **Rare & Premium** 🌟
- `⭐` - Golden Star (Rare treasure)
- `💎` - Diamond (Premium item)
- `👑` - Crown (Royalty/Premium)
- `🏆` - Trophy (Achievement)

### **Magic & Spells** ✨
- `✨` - Magic Wand (Spells)
- `🔮` - Crystal Orb (Mystical power)
- `🪄` - Wand (Spell casting)
- `🌌` - Galaxy (Cosmic power)

### **Blessings & Buffs** 🌟
- `🌟` - Divine Blessing (Permanent buff)
- `🙏` - Prayer/Blessing (Spirit)
- `☀️` - Sun (Light/Blessing)
- `🕯️` - Candle (Holy light)

### **Companions & Pets** 🐕
- `🐕` - Pet Companion (Dog friend)
- `🐱` - Cat (Cat companion)
- `🦜` - Parrot (Bird companion)
- `🐉` - Dragon (Epic companion)

### **Educational & Knowledge** 📚
- `📚` - Books (Knowledge)
- `🧠` - Brain (Wisdom)
- `📖` - Open Book (Learning)
- `🎓` - Graduation Cap (Education)

### **Entertainment & Games** 🎮
- `🎮` - Game Controller (Gaming)
- `🎯` - Target (Aim/Skill)
- `🎲` - Dice (Chance)
- `🎪` - Circus (Entertainment)

### **Fishing & Outdoor** 🎣
- `🎣` - Fishing Rod (Fishing items)
- `🌿` - Plant (Nature)
- `🏕️` - Camping (Outdoor)
- `⛺` - Tent (Adventure)

### **Decorations & Style** 🌹
- `🌹` - Rose (Decoration)
- `🎨` - Palette (Art/Style)
- `🖼️` - Painting (Decoration)
- `✨` - Sparkles (Beauty)

---

## Current Shop Items

```
┌─────────────────────────────────────────────────────┐
│ ITEM 1: Power Potion                   Price: 100   │
│ Icon: 💊                                            │
│ Description: Boost your stats!                      │
│ Category: Health & Potions                          │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ITEM 2: Speed Scroll                   Price: 150   │
│ Icon: 📜                                            │
│ Description: Move 50% faster!                       │
│ Category: Movement & Speed                          │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ITEM 3: Shield Stone                   Price: 200   │
│ Icon: 🛡️                                            │
│ Description: Reduce damage taken!                   │
│ Category: Defense & Armor                           │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ITEM 4: Golden Star                    Price: 250   │
│ Icon: ⭐                                            │
│ Description: Rare treasure!                        │
│ Category: Rare & Premium                           │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ITEM 5: Magic Wand                     Price: 300   │
│ Icon: ✨                                            │
│ Description: Cast powerful spells!                  │
│ Category: Magic & Spells                            │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ITEM 6: Divine Blessing                Price: 350   │
│ Icon: 🌟                                            │
│ Description: Permanent buff!                        │
│ Category: Blessings & Buffs                         │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ITEM 7: Pet Companion                  Price: 400   │
│ Icon: 🐕                                            │
│ Description: Get a loyal friend!                    │
│ Category: Companions & Pets                         │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ITEM 8: Crystal Orb                    Price: 500   │
│ Icon: 🔮                                            │
│ Description: Ultimate power!                        │
│ Category: Magic & Spells                            │
└─────────────────────────────────────────────────────┘
```

---

## Shop Functions Reference

### **Core Shop Functions**

#### `_initialize_shop() -> void`
- **Purpose**: Creates all shop item UI panels at startup
- **Behavior**: Loops through `_shop_items` array and creates panels for each
- **Called In**: `_ready()`

#### `_create_item_panel(item: Dictionary) -> void`
- **Purpose**: Creates individual item UI display panel
- **Creates**: PanelContainer with icon, name, description, price, buy button
- **Parameters**:
  - `item`: Dictionary with `id`, `name`, `price`, `icon`, `description`

#### `_on_buy_pressed(item: Dictionary) -> void`
- **Purpose**: Handles purchase button click
- **Logic**:
  1. Check if user has enough coins
  2. If not, show error message
  3. If yes, deduct coins from balance
  4. Save new balance to Firebase
  5. Show success message
- **Firebase Call**: `save_coin_balance(user_id, new_balance, callback)`

#### `_load_coin_balance() -> void`
- **Purpose**: Loads user's current coin balance from Firebase
- **Firebase Call**: `load_coin_balance(user_id, callback)`
- **Updates**: `_user_coins` variable and UI label

#### `_update_coins_display() -> void`
- **Purpose**: Updates coin count label in UI
- **Display Format**: "💰 Coins: {amount}"

---

## Scroll Functions

#### `_on_scroll_left() -> void`
- **Purpose**: Scroll shop items to the left
- **Logic**:
  1. Decrease `_scroll_index` by 1 (if > 0)
  2. Animate scroll using tween
  3. Update button states (enable/disable)

#### `_on_scroll_right() -> void`
- **Purpose**: Scroll shop items to the right
- **Logic**:
  1. Increase `_scroll_index` by 1
  2. Check bounds against items per view
  3. Animate scroll using tween
  4. Update button states

#### `_animate_scroll() -> void`
- **Purpose**: Smooth animation for horizontal scrolling
- **Animation Details**:
  - Duration: 0.3 seconds
  - Easing: Cubic out
  - Target: Horizontal scroll position

#### `_update_scroll_buttons() -> void`
- **Purpose**: Enable/disable left/right buttons based on scroll position
- **Logic**:
  - Left button disabled if at start (`_scroll_index <= 0`)
  - Right button disabled if at end

---

## Key Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `_auth_manager` | Node | Reference to FirebaseAuthManager |
| `_current_user_id` | String | Logged-in user's ID |
| `_user_coins` | int | Current coin balance |
| `_scroll_container` | ScrollContainer | UI scroll container |
| `_items_container` | HBoxContainer | Container for items |
| `_coin_label` | Label | Coin display label |
| `_scroll_index` | int | Current scroll position |
| `_items_per_view` | int | Items visible at once (2) |
| `_shop_items` | Array | Item database |

---

## Firebase Integration

### **Coin Balance Path**
```
users/{user_id}/profile/coin_balance
```

### **Startup Coins**
- **Amount**: 10 coins
- **When**: On user signup completion
- **Location**: `firebase_auth_manager.gd` sign_up() function
- **Code**: `"coin_balance": 10` added to profile payload

### **Purchase Flow**
1. User clicks BUY button on item
2. `_on_buy_pressed()` checks coin balance
3. If sufficient, send new balance to Firebase
4. `save_coin_balance(user_id, new_balance, callback)` saves to DB
5. UI updates locally with new balance

---

## How to Add More Items

1. Add to `_shop_items` array in `shop_handler.gd`:
```gdscript
{"id": "unique_id", "name": "Item Name", "price": 500, "icon": "🎨", "description": "Item description!"}
```

2. Choose icon from categories above
3. Set appropriate price
4. Call `_initialize_shop()` to refresh display

---

## Node Paths (shop.tscn structure)

```
Control
├── Panel3 (Coin label container)
│   └── Label (Coin display)
├── Panel4 (Shop container)
│   └── Panel6 (Scroll area)
│       ├── LeftButton
│       ├── Panel (ScrollContainer)
│       │   └── HBoxContainer (Item panels go here)
│       └── RightButton
```

---

## Troubleshooting

**Issue**: Items not showing
- **Check**: `_items_container` is properly referenced
- **Fix**: Verify node paths match in `_ready()`

**Issue**: Coins not updating
- **Check**: FirebaseAuthManager autoload exists
- **Fix**: Verify `save_coin_balance()` method exists

**Issue**: Scroll buttons not working
- **Check**: Button signals are connected and `_scroll_index` is updating
- **Fix**: Verify node paths for buttons

**Issue**: Purchase not deducting coins
- **Check**: Firebase write permission for `/profile/coin_balance`
- **Fix**: Update Firebase security rules if needed

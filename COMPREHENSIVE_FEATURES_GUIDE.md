# AdventureHabi - Comprehensive Features Implementation Guide

## System Overview

This document describes the complete implementation of Shop, Notifications, and Real-Time Task Sync features.

---

## 1. SHOP SYSTEM (`shop_handler.gd`)

### Features
- **Item Browsing**: Horizontal scrolling shop with emoji icons
- **Purchase System**: One-click purchase confirmation dialog
- **Coin Balance**: Real-time coin tracking from Firebase
- **Toast Notifications**: Visual feedback for transactions
- **Purchase Persistence**: All purchases saved to Firebase

### How It Works

#### Initialization
```gdscript
func _ready() -> void
    # 1. Resolves Firebase Auth Manager
    # 2. Loads user ID from session
    # 3. Loads user's coin balance from Firebase
    # 4. Initializes shop UI with 8 items
    # 5. Sets up purchase confirmation dialog
```

#### Purchase Flow
1. **User clicks BUY button** → `_on_buy_pressed(item)`
2. **Confirmation dialog shows** → Asks for confirmation
3. **User confirms** → `_on_confirmed_purchase()`
4. **Coins validated** → Check if user has enough coins
5. **Purchase saved** → `save_coin_balance()` called
6. **UI updated** → Coin display refreshed
7. **Toast shown** → Success/failure message

### Database Structure
```
users/
  {user_id}/
    purchases/
      {item_id}: {purchase_data}
    coins: {balance}
```

### Key Methods
- `_load_user_data()` - Get current user ID
- `_load_coin_balance()` - Fetch coins from Firebase
- `_initialize_shop()` - Create shop UI
- `_on_buy_pressed(item)` - Handle purchase initiation
- `_on_confirmed_purchase()` - Process confirmed purchase
- `_update_coins_display()` - Refresh coin counter

---

## 2. NOTIFICATION SYSTEM (`notification_handler.gd`)

### Features
- **Real-time Polling**: Updates every 10 seconds
- **Multiple Notification Types**:
  - Reward notifications
  - Admin/Counselor messages
  - Chat reminders
  - Task assignments
  - System notifications
- **Interactive Cards**: Click to navigate to relevant scene
- **Unread Tracking**: Track unread notification count
- **Auto-refresh**: Timer-based polling with minute precision

### Notification Panel Structure
```
Panel/  (Red container)
  Panel3  → Rewards Notifications
  Panel4  → Admin/Counselor Notifications
  Panel5  → Chat Reminders
  Panel6  → Goal Tasks
  Panel7  → System Notifications
```

### How It Works

#### Load Flow
1. **_ready()** → Setup panels and timers
2. **_setup_refresh_timer()** → Creates 10-second timer
3. **_load_all_notifications()** → Called on _ready and every 10 seconds
4. **_load_*_notifications()** → Load each type from Firebase
5. **_display_notifications_in_panel()** → Render cards

#### Task Notification Example Flow
```gdscript
_load_goal_task_notifications()
  ↓
Firebase: users/{user_key}/tasks
  ↓
Filter incomplete tasks (completed == false)
  ↓
For each task:
    - Create notification card
    - Add click handler
    - Increment unread count
  ↓
_display_notifications_in_panel()
  ↓
User clicks task → _navigate_to_task(task_id)
```

#### Real-Time Response
- **10-second polling cycle** ensures near-real-time updates
- When admin assigns a task, it appears in user's notifications within 10 seconds
- Auto-refresh based on system time

### Database Structure
```
users/
  {user_key}/
    tasks/
      {task_id}:
        task_id: string
        assigned_at: datetime
        completed: boolean
        completion_date: datetime
    notifications/
      {notif_id}:
        id: string
        type: "task_assigned"
        task_id: string
        message: string
        created_at: datetime
        read: boolean
```

### Key Methods
- `_load_all_notifications()` - Master loader
- `_load_goal_task_notifications()` - Load assigned tasks
- `_load_admin_request_notifications()` - Load counselor messages
- `_create_notification_card()` - Create visual card
- `_navigate_to_task(task_id)` - Navigate to task when clicked
- `_mark_notification_read()` - Update read status

---

## 3. TASK MANAGEMENT SYSTEM

### 3A. Admin Helper (`admin_helper.gd`)

Admin functions for task management - can be called from admin dashboard.

#### Create Task
```gdscript
admin_helper.create_task(
    title = "Complete Your Reading",
    description = "Read one chapter of your favorite book",
    category = "Academic",
    difficulty = "Easy",
    estimated_time = "15 mins",
    coins_reward = 10,
    exp_reward = 25,
    callback = func(ok, task_data):
        print("Task created:", ok, task_data)
)
```

#### Assign to Single User
```gdscript
admin_helper.assign_task_to_user(
    task_id = "task_xyz",
    user_id = "user_123",
    callback = func(ok):
        print("Task assigned:", ok)
)
```

#### Broadcast to All Users
```gdscript
admin_helper.assign_task_to_all_users(
    task_id = "task_xyz",
    callback = func(ok, stats):
        print("Assigned to:", stats["assigned"], "/", stats["total"], "users")
)
```

#### Mark Task Complete
```gdscript
admin_helper.mark_task_complete(
    user_id = "user_123",
    task_id = "task_xyz",
    proof = {"screenshot_path": "path/to/image"},
    callback = func(ok):
        print("Task marked complete:", ok)
)
```

#### Get Task Completions
```gdscript
admin_helper.get_task_completions(
    task_id = "task_xyz",
    callback = func(ok, completions):
        for user_id in completions:
            print(user_id, "completed task")
)
```

### 3B. Firebase Task Manager (`firebase_task_manager.gd`)

Lower-level Firebase operations for task sync.

#### Create Task
```gdscript
task_manager.create_task(
    title, description, category, difficulty, due_date,
    coins_reward, exp_reward,
    callback
)
```

#### Fetch User Tasks
```gdscript
task_manager.fetch_user_tasks(
    user_id = "user_123",
    callback = func(ok, tasks):
        for task_id in tasks:
            print(task_id, tasks[task_id])
)
```

---

## 4. COMPLETE END-TO-END FLOW: Task Assignment from Admin to User

### Step 1: Admin Creates Task (Admin Dashboard)
```
Admin clicks "Create Task" 
  → admin_helper.create_task()
  → Firebase: admin/tasks/{task_id} ← CREATED
  → Console: "Task created: {data}"
```

### Step 2: Admin Broadcasts to Users
```
Admin clicks "Assign to All"
  → admin_helper.assign_task_to_all_users(task_id)
  → For each user:
      - Firebase: users/{user_key}/tasks/{task_id} ← ASSIGNED
      - Firebase: users/{user_key}/notifications/{notif_id} ← NOTIF SENT
```

### Step 3: User's Device - Automatic Refresh (~10 seconds)
```
notification_handler._refresh_timer.timeout()
  → _load_all_notifications()
  → _load_goal_task_notifications()
  → Firebase: users/{user_key}/tasks
  → NEW TASK DETECTED
  → notification_handler._display_notifications_in_panel()
  → UI: Task card appears in Goal Tasks panel
```

### Step 4: User Clicks Task
```
User clicks task notification card
  → _navigate_to_task(task_id)
  → Change scene to: res://a_itask.tscn
  → Task details load and display
```

### Step 5: User Completes Task
```
User fills form + uploads proof
  → Submit button clicked
  → a_itask_navigation._submit_task()
  → auth_manager.save_task_proof()
  → Firebase: users/{user_key}/tasks/{task_id}: {completed: true}
  → Console: "Task marked complete"
```

### Step 6: Admin Reviews Completions
```
Admin dashboard:
  → admin_helper.get_task_completions(task_id)
  → Firebase: queries all users
  → Returns: {user_123: {...}, user_456: {...}}
  → Admin dashboard shows completion stats
```

---

## 5. DATABASE SCHEMA

### Admin Tasks
```json
{
  "admin": {
    "tasks": {
      "task_read_001": {
        "id": "task_read_001",
        "title": "Complete Your Reading",
        "description": "Read one chapter",
        "category": "Academic",
        "difficulty": "Easy",
        "estimated_time": "15 mins",
        "coins": 10,
        "exp": 25,
        "created_at": "2026-08-29 10:00:00",
        "status": "active",
        "assigned_to": ["user_123", "user_456"]
      }
    }
  }
}
```

### User Tasks
```json
{
  "users": {
    "user_key_123": {
      "tasks": {
        "task_read_001": {
          "task_id": "task_read_001",
          "assigned_at": "2026-08-29 10:00:00",
          "completed": false,
          "completion_date": ""
        }
      },
      "notifications": {
        "notif_1234567890": {
          "id": "notif_1234567890",
          "type": "task_assigned",
          "task_id": "task_read_001",
          "title": "New Task Assigned",
          "message": "A new task has been assigned to you!",
          "created_at": "2026-08-29 10:00:01",
          "read": false
        }
      }
    }
  }
}
```

---

## 6. REAL-TIME RESPONSIVENESS

### Polling Strategy
- **Interval**: 10 seconds
- **Method**: Timer-based `HTTPRequest.request()` with `_db.read_json()`
- **Scope**: Only loads changes relevant to current user

### Performance Optimization
- Minimal network overhead (small JSON payloads)
- Only incomplete tasks loaded
- Notification cards created on-demand
- Old cards cleaned before refresh

### Limitations & Future Improvements
- **Current**: Polling every 10 seconds
- **Future**: Implement Firebase Cloud Messaging (FCM) for instant push notifications
- **Alternative**: WebSocket connection for true real-time sync

---

## 7. TESTING YOUR IMPLEMENTATION

### Test 1: Shop Purchase Flow
1. Open Shop scene
2. View coin balance
3. Click BUY on any item
4. Confirm purchase
5. Verify coin deduction
6. Check Firebase: `users/{user_key}/coins`

### Test 2: Task Assignment and Notification
1. Admin creates task via `admin_helper.create_task()`
2. Admin broadcasts via `assign_task_to_all_users()`
3. Open Notification scene
4. Wait max 10 seconds
5. Verify "Goal Tasks" panel shows new task
6. Click task → Navigate to task scene

### Test 3: Task Completion
1. Complete task form
2. Upload proof image
3. Submit
4. Verify Firebase: `users/{user_key}/tasks/{task_id}/completed = true`
5. Admin dashboard shows completion status

### Test 4: Coin Reward
1. Complete task
2. System awards coins automatically
3. Verify Firebase: `users/{user_key}/coins` increased
4. Shop scene shows updated balance

---

## 8. INTEGRATION CHECKLIST

- ✅ Shop Handler: Complete with Firebase integration
- ✅ Notification Handler: Real-time polling (10-second interval)
- ✅ Admin Helper: Full task management API
- ✅ Firebase Task Manager: Low-level task operations
- ✅ Notification System: Task-click navigation
- ✅ Database: Schema design documented
- ✅ Error Handling: Fallbacks implemented
- ✅ UI/UX: Toast messages, confirmation dialogs
- ✅ Performance: Optimized queries, minimal payloads
- ✅ Code Quality: No compilation errors

---

## 9. TROUBLESHOOTING

### Issue: Tasks Not Appearing in Notifications
1. Check Firebase path: `users/{user_key}/tasks/{task_id}`
2. Verify `completed == false`
3. Check notification panel is initialized
4. Verify timer is running: `print(_refresh_timer.is_stopped())`

### Issue: Coin Balance Not Updating
1. Verify `_auth_manager` is resolved
2. Check Firebase method: `load_coin_balance()` exists
3. Verify path: `users/{user_key}/coins` exists
4. Check callback is being called

### Issue: Slow Notifications
1. Reduce polling interval (current: 10 seconds)
2. Implement caching to avoid full reload
3. Consider Firebase Realtime Database listeners instead of polling

---

**Documentation Generated**: August 29, 2026
**Version**: 1.0
**Status**: Production Ready ✓

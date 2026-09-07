# Action Plan - What You Need to Do

## Current Status
- ✅ Chat system fully implemented in `guidance.tscn` and `guidance_chat.gd`
- ✅ Firebase rules updated in `database.rules.json`
- ✅ Admin functions added to `admin_helper.gd`
- ⏳ **YOUR ACTION NEEDED**: Publish rules to Firebase Console

---

## STEP 1: Publish Firebase Rules (CRITICAL - 5 minutes)

### What to Do:
1. Open [Firebase Console](https://console.firebase.google.com)
2. Find your project (should be listed on home page)
3. Click on it
4. In left sidebar, click **Realtime Database**
5. Look for the **Rules** tab (next to Data tab)
6. Click on Rules tab
7. You should see JSON rules editor

### Copy New Rules:
1. In VS Code, open `database.rules.json` in your project
2. Select ALL (Ctrl+A)
3. Copy (Ctrl+C)

### Paste New Rules:
1. Back in Firebase Console Rules editor
2. Select ALL (Ctrl+A)
3. Delete (or paste over)
4. Paste (Ctrl+V)
5. You should see new rules with `/conversations`, `/messages`, `/users` sections

### Publish:
1. Look for **Publish** button (usually blue, bottom right)
2. Click it
3. You should see message: ✓ Rules published successfully
4. **Wait 10-15 seconds** for changes to propagate

---

## STEP 2: Test Student Chat (10 minutes)

### In Your Game:
1. Run the game (F5)
2. Navigate to **Guidance** screen (click Guidance button)
3. You should see:
   - Chat area (empty at first)
   - Text input field at bottom
   - SEND button

### Send Test Message:
1. Click in TextEdit field
2. Type: `Hello counselor, testing this chat system`
3. Click SEND button
4. Message should appear in chat UI (red bubble, on right side)

### Check Console:
1. Open Godot Debug Console (View → Toggle Debug Console)
2. Should see messages like:
   ```
   Guidance chat: creating conversation url: ...
   Guidance chat: sending to: /conversations/conv_...
   Guidance chat: message sent successfully to conversation node
   ```

---

## STEP 3: Verify Message in Firebase (5 minutes)

### In Firebase Console:
1. Go back to Firebase Console
2. Click **Realtime Database** → **Data** tab (not Rules)
3. You should see folder structure on left
4. Click on **conversations** folder
5. Expand it (click arrow)
6. You should see new conversation with ID like `conv_student_1_1725...`
7. Click to expand
8. Click on **messages**
9. You should see your message with structure:
   ```json
   {
	 "id": "msg_1725...",
	 "conversationId": "conv_student_1_...",
	 "senderId": "guest_user",
	 "receiverId": "admin_1",
	 "message": "Hello counselor, testing this chat system",
	 "timestamp": "2026-08-29T14:30:45Z",
	 "read": false,
	 "type": "text"
   }
   ```

### Also Check Messages Path:
1. Go back to root folder
2. Click on **messages** folder (at root level, not under conversations)
3. Should see same message there too
4. This is automatic duplication for admin queries

✅ **If you see this, the chat system is working!**

---

## STEP 4: Test Admin Reply (5 minutes)

### Add Message Manually in Firebase:
1. In Firebase Console, under `/conversations/{convId}/messages/`
2. Right-click on messages folder
3. Click **Add child**
4. For key, enter: `msg_admin_reply_001`
5. For value, select **JSON** and paste:
   ```json
   {
	 "id": "msg_admin_reply_001",
	 "conversationId": "conv_student_1_1725...",
	 "senderId": "admin_1",
	 "receiverId": "guest_user",
	 "message": "Hi there! Thanks for testing. I'm here to help - what do you need?\n\nBest regards,\nGuidance Counselor",
	 "timestamp": "2026-08-29T14:35:00Z",
	 "read": false,
	 "type": "text"
   }
   ```

**IMPORTANT:** You need to set the exact conversationId that was created in STEP 3

### Duplicate to Messages Path:
1. Also add same message to `/messages/msg_admin_reply_001`
2. Same JSON structure as above

### Back in Game:
1. After 3 seconds, message should appear in chat (gray bubble, on left side)
3. Should show "Guidance Counselor" as sender
4. Message text should display

✅ **If you see the reply in the chat, admin messaging works!**

---

## STEP 5: Verify Journal Still Works (5 minutes)

### Test Journal Save:
1. In game, navigate to **My Journal**
2. Write entry: "Testing that save still works with new rules"
3. Click **SAVE**
4. Should see: "✓ Entry saved!"

### Verify in Firebase:
1. Firebase Console → Realtime Database → Data
2. Navigate to `/users/...../journal`
3. Should see new entry with your text

✅ **Journal working with new rules**

---

## STEP 6: Verify Mood Check Still Works (5 minutes)

### Test Mood Check:
1. In game, navigate to mood check
2. Select a mood (e.g., "Happy")
3. Click **Continue**
4. Should see: "✓ Entry saved!" or similar

### Verify in Firebase:
1. Firebase Console → Realtime Database → Data
2. Navigate to `/users/...../moodcheck`
3. Should see new mood entry with date

✅ **Mood tracking working with new rules**

---

## STEP 7: Optional - Test Admin Functions (10 minutes)

### In Godot Script:
Create a test scene with this code:

```gdscript
extends Node

var admin_helper: Node

func _ready():
	admin_helper = AdminHelper.new()  # Or however you load it
	
	# Test 1: Get all conversations
	admin_helper.get_all_conversations(func(ok, convs):
		if ok:
			print("Conversations count: ", convs.size())
			for conv_id in convs.keys():
				var conv = convs[conv_id]
				print("- ", conv_id, " from student: ", conv.get("userId"))
	)
	
	# Test 2: Get unread messages
	admin_helper.get_unread_messages(func(ok, unread):
		if ok:
			print("Unread messages: ", unread.size())
			for msg_id in unread.keys():
				var msg = unread[msg_id]
				print("- [", msg.get("timestamp"), "] ", msg.get("senderId"), ": ", msg.get("message"))
	)
	
	# Test 3: Send admin reply
	admin_helper.send_admin_reply(
		"conv_student_1_1725...",  # Replace with actual convId
		"guest_user",              # Student ID
		"Thanks for the test! This is an automated reply.",
		func(ok, msg):
			if ok:
				print("✓ Reply sent!")
			else:
				print("✗ Failed to send reply")
	)
```

---

## That's It! 🎉

### What You've Accomplished:
- ✅ Published Firebase rules (allows chat/journal/mood to work)
- ✅ Tested student sending message
- ✅ Verified message stores in Firebase
- ✅ Tested admin reply
- ✅ Verified student receives reply
- ✅ Confirmed journal saves
- ✅ Confirmed mood tracking works
- ✅ Tested admin functions

### What's Next:
1. **Build Admin Dashboard** (separate from app)
   - View all conversations
   - Reply to messages
   - View student journals
   - See mood tracking
   - Export reports
   
2. **Production Hardening**
   - Add user authentication
   - Implement admin access control
   - Add message encryption
   - Monitor Firebase usage

---

## Troubleshooting

### Chat message stays "Saving..." forever
→ Firebase rules not published. Do Step 1 again.

### "Permission denied" error
→ Same as above. Rules must be published.

### Can't find message in Firebase after sending
→ Check console output. Look for "Permission denied" or HTTP errors.

### Admin reply not appearing in chat after 10 seconds
→ Check `/messages/{msgId}` exists at root and under `/conversations/{convId}/messages/`
→ Check receiverId matches student ID
→ Check timestamp is ISO format

### Journal/Mood saves failing
→ Check timestamp in error message
→ Usually means senderId/receiverId is wrong format
→ Check it's in `/users/{email}/journal` or `/moodcheck`

---

## Important Notes

1. **Database URL**: Change `https://adv-habi-default-rtdb.firebaseio.com` if your project uses different URL
2. **Admin ID**: Currently hardcoded as `"admin_1"` - change if you want different identifier
3. **Polling Interval**: 3 seconds is good balance. Can reduce to 1-2 for more real-time feel
4. **Guest Users**: System allows guest (not authenticated) to send messages. Add auth rules when needed.
5. **Data Duplication**: Messages intentionally stored in two places (for easy admin queries)

---

## Files Reference

- `database.rules.json` - Rules to publish to Firebase
- `guidance.tscn` - Chat UI scene
- `guidance_chat.gd` - Chat logic (student side)
- `admin_helper.gd` - Admin functions (new)
- `CHAT_SYSTEM_GUIDE.md` - Detailed technical documentation
- `FIREBASE_RULES_QUICK_FIX.md` - Rule deployment guide

---

## Getting Help

1. **Firebase Console Shows Error**: Click on it for full error message
2. **Godot Console Shows Error**: Look for "Permission denied" or HTTP error code
3. **Check Network Tab**: Developer Tools → Network → See actual HTTP responses
4. **Read Console Output**: guidance_chat.gd logs everything to console

---

## Success Indicators

✅ Chat message appears in Firebase `/conversations` → **Rules working**
✅ Student receives admin reply → **Polling working**
✅ Message marked as read → **Read status working**
✅ Journal/Mood saves → **User-scoped paths working**
✅ Admin functions execute → **Everything working**

You're all set! Start with Step 1. 🚀

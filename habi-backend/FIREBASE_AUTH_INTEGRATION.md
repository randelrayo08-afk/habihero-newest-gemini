# Firebase Authentication Integration Guide
# How to properly use Firebase Auth with Habi

## Current Setup

You already have:
✅ Firebase Auth configured in `firebase_manager.gd`
✅ Sign up / Sign in methods
✅ Token storage (`current_user_token`)
✅ Backend API integration

## What Needs to Change

Your authentication token from Firebase needs to be passed to your backend API calls.

---

## Step 1: Update Backend API to Accept Auth Token

In your `backend_api.gd` (or similar), add authentication header:

```gdscript
func save_profile(user_id: String, user_data: Dictionary) -> void:
	var url = "http://localhost:5000/api/users"
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % FirebaseManager.current_user_token
	]
	
	var body = {
		"uid": user_id,
		"email": FirebaseManager.current_user_email,
		"displayName": user_data.get("name", ""),
		"age": user_data.get("age", ""),
		"pronouns": user_data.get("pronouns", []),
		"interests": user_data.get("areas", [])
	}
	
	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_request_completed.bind(request, "save_profile"))
	request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
```

## Step 2: Update Backend Server to Validate Tokens

Add this middleware to `server.js`:

```javascript
// Middleware to verify Firebase token
async function verifyFirebaseToken(req, res, next) {
  const token = req.headers.authorization?.split(' ')[1];
  
  if (!token) {
    return res.status(401).json({ error: 'No authentication token' });
  }
  
  try {
    const decodedToken = await admin.auth().verifyIdToken(token);
    req.user = decodedToken;
    next();
  } catch (error) {
    res.status(401).json({ error: 'Invalid token' });
  }
}

// Use middleware on protected routes
app.post('/api/users', verifyFirebaseToken, async (req, res) => {
  // User is authenticated, uid matches token
  const uid = req.user.uid;
  // ... rest of the endpoint
});
```

## Step 3: Ensure Complete Authentication Flow

### Login Flow:
1. User enters email/password
2. Firebase Auth signs them in → returns `idToken`
3. Store the `idToken` in `FirebaseManager.current_user_token`
4. Include `idToken` in all backend API calls
5. Backend verifies token and processes request

### Example:
```gdscript
# In login.gd after successful authentication
func _on_auth_success(user_data: Dictionary) -> void:
	# Firebase Manager now has:
	# - current_user_id
	# - current_user_token (idToken)
	# - current_user_email
	
	# Now you can safely call backend API
	var profile_data = {
		"name": "John Doe",
		"age": 18,
		"pronouns": ["he", "him"]
	}
	
	# This will include the auth token
	FirebaseManager.save_profile_via_backend(profile_data)
```

## Step 4: Test Authentication

1. **Start your backend server:**
   ```powershell
   cd "c:\Users\paolo\Documents\signup\habi-backend"
   node server.js
   ```

2. **Test in your Godot app:**
   - Sign up with email/password
   - Try to save user profile
   - Check backend logs for successful auth

3. **Verify in Firebase Console:**
   - Go to Authentication users
   - User should appear after signup

---

## File Changes Required

### Files to Update:
- [ ] `backend_api.gd` - Add "Authorization: Bearer" header
- [ ] `server.js` - Add token verification middleware
- [ ] `firebase_manager.gd` - Ensure token is saved after auth

### Files Already Good:
- ✅ `firebase_manager.gd` - Has auth methods
- ✅ `login.gd` - Has login flow
- ✅ `firebase_config.gd` - Has API key

---

## Security Best Practices

✅ **Do:**
- Store token in `current_user_token`
- Send token in Authorization header
- Verify token on backend
- Use HTTPS in production

❌ **Don't:**
- Use `null` or empty token
- Store password in variables
- Bypass token verification
- Use same token after logout

---

## Quick Checklist

- [ ] Backend server running on port 5000
- [ ] Backend has token verification middleware
- [ ] Godot app saves Firebase idToken
- [ ] Godot app sends token in Authorization header
- [ ] Firebase Rules require auth

Once all these are in place, your app will be fully authenticated and secure! 🔐

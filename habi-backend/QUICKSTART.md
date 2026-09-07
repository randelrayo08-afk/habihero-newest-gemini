## Quick Start Guide

### Running the Server

1. **Navigate to backend directory:**
   ```powershell
   Push-Location "c:\Users\paolo\Documents\signup\habi-backend"
   ```

2. **Install dependencies (first time only):**
   ```powershell
   npm install
   ```

3. **Start the server:**
   ```powershell
   node server.js
   ```
   Or with auto-reload in development:
   ```powershell
   npm run dev
   ```

4. **Test the server:**
   - Open browser: http://localhost:5000/health
   - Should return: `{ "status": "Server is running", "timestamp": "..." }`

---

### Key Files

| File | Purpose |
|------|---------|
| `server.js` | Main Express server with all API endpoints |
| `package.json` | Dependencies and scripts |
| `.env` | Environment variables (gitignored) |
| `API.md` | Complete API documentation with examples |
| `DATABASE_SCHEMA.md` | Firebase database structure |
| `utils.js` | Helper functions for validation |

---

### Database Features

✅ **Users** - Profile management (name, age, interests, pronouns)
✅ **Moods** - Track emotional states with intensity levels
✅ **Journal** - Create, read, update, delete journal entries
✅ **Habits** - Track daily habits with streak counter

---

### Example API Calls

**Log a mood:**
```bash
curl -X POST http://localhost:5000/api/moods \
  -H "Content-Type: application/json" \
  -d '{
    "uid": "user123",
    "mood": "happy",
    "intensity": 8,
    "notes": "Great day!"
  }'
```

**Create a journal entry:**
```bash
curl -X POST http://localhost:5000/api/journal \
  -H "Content-Type: application/json" \
  -d '{
    "uid": "user123",
    "title": "Today",
    "content": "Had an amazing day",
    "mood": "happy"
  }'
```

**Create a habit:**
```bash
curl -X POST http://localhost:5000/api/habits \
  -H "Content-Type: application/json" \
  -d '{
    "uid": "user123",
    "name": "Morning Run",
    "description": "5km run every morning",
    "frequency": "daily",
    "color": "#FF6B6B"
  }'
```

---

### Firebase Console

Check your data in real-time:
1. Go to: https://console.firebase.google.com/
2. Select project: `habits-64801`
3. Navigate to Realtime Database
4. View live data updates

---

### Next Steps

1. **Frontend Integration** - Connect your Godot app to these endpoints
2. **Authentication** - Add Firebase Auth integration
3. **Validation** - Implement request validation middleware
4. **Error Handling** - Add comprehensive error handling
5. **Logging** - Add request logging for debugging
6. **Deployment** - Deploy to Firebase Functions or Heroku

---

### Troubleshooting

**Port 5000 already in use:**
```powershell
# Find process using port 5000
netstat -ano | findstr :5000
# Kill process (replace PID with actual process ID)
taskkill /PID <PID> /F
```

**Firebase not initializing:**
- Check `.env` file has correct credentials
- Verify FIREBASE_PRIVATE_KEY has escaped newlines

**npm install issues:**
```powershell
rm -r node_modules
npm install
```

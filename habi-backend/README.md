# Habi Backend Server

Node.js + Express backend for the Habi application with Firebase integration.

## Setup Instructions

### 1. Install Dependencies

```bash
npm install
```

### 2. Environment Configuration

A `.env` file has been created with your Firebase credentials. It's already gitignored.

### 3. Start the Server

**Development mode (with auto-reload):**
```bash
npm run dev
```

**Production mode:**
```bash
npm start
```

The server will run on `http://localhost:5000`

### Gemini Live voice

The Godot app uses the backend WebSocket endpoint `/ws/gemini`. Configure the backend before running it:

```env
GEMINI_API_KEY=your_key_from_google_ai_studio
GEMINI_LIVE_MODEL=models/gemini-2.5-flash-native-audio-latest
GEMINI_VOICE_NAME=Puck
```

The API key stays on the backend and is never bundled into the APK. In the Godot project, set the `HabiBackend` autoload `base_url` to the deployed HTTPS backend URL. The voice client converts that URL to `wss://` automatically. `http://localhost:5000` only works when testing on the same computer.

Railway can run the backend without `serviceAccountKey.json`; set `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, and `FIREBASE_PRIVATE_KEY` as Railway variables. Store the private key with literal `\n` line breaks in the value.

## API Endpoints

For detailed API documentation, see [API.md](API.md)

### Health Check
- **GET** `/health` - Server status

### User Management
- **POST** `/api/users` - Create/Update user profile
- **GET** `/api/users/:uid` - Get user profile
- **PATCH** `/api/users/:uid` - Update user profile

### Mood Tracking
- **POST** `/api/moods` - Log mood entry
- **GET** `/api/moods/:uid` - Get mood history

### Journal Entries
- **POST** `/api/journal` - Create entry
- **GET** `/api/journal/:uid` - Get all entries
- **GET** `/api/journal/:uid/:entryId` - Get single entry
- **PATCH** `/api/journal/:uid/:entryId` - Update entry
- **DELETE** `/api/journal/:uid/:entryId` - Delete entry

### Habit Tracking
- **POST** `/api/habits` - Create habit
- **GET** `/api/habits/:uid` - Get all habits
- **POST** `/api/habits/:uid/:habitId/complete` - Mark habit complete
- **DELETE** `/api/habits/:uid/:habitId` - Delete habit

## Project Structure

```
habi-backend/
├── server.js                 # Main server entry point
├── package.json             # Dependencies & scripts
├── .env                     # Environment variables (gitignored)
├── .env.example            # Example environment template
├── .gitignore              # Git ignore rules
└── README.md               # This file
```

## Next Steps

1. ✅ Install dependencies: `npm install`
2. ✅ Start server: `npm run dev`
3. Add database models for habits, journal entries, moods, etc.
4. Implement authentication endpoints
5. Add data validation & error handling
6. Deploy to production (Firebase Functions, Heroku, etc.)

## Important Security Notes

⚠️ **CRITICAL**: Your Firebase credentials are now in `.env` (gitignored). 
- Never commit `.env` to version control
- Never share credentials publicly
- Consider rotating credentials if they were exposed in git history

## Dependencies

- **express** - Web framework
- **firebase-admin** - Firebase backend SDK
- **cors** - Cross-origin resource sharing
- **dotenv** - Environment variable management

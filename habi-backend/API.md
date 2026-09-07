// API Documentation

## Habi Backend API

Base URL: `http://localhost:5000`

---

### Health Check

**GET** `/health`
- Returns server status
- No authentication required

**Response:**
```json
{
  "status": "Server is running",
  "timestamp": "2026-03-30T10:00:00.000Z"
}
```

---

### User Management

#### Create/Update User Profile

**POST** `/api/users`

**Request Body:**
```json
{
  "uid": "user123",
  "email": "user@example.com",
  "displayName": "John Doe",
  "pronouns": "he/him",
  "age": 18,
  "interests": ["gaming", "music", "reading"]
}
```

**Response:** `201 Created`
```json
{
  "message": "User created successfully",
  "uid": "user123"
}
```

#### Get User Profile

**GET** `/api/users/:uid`

**Response:** `200 OK`
```json
{
  "email": "user@example.com",
  "displayName": "John Doe",
  "pronouns": "he/him",
  "age": 18,
  "interests": ["gaming", "music"],
  "createdAt": "2026-03-30T10:00:00.000Z",
  "updatedAt": "2026-03-30T10:00:00.000Z"
}
```

#### Update User Profile

**PATCH** `/api/users/:uid`

**Request Body:** (any fields to update)
```json
{
  "displayName": "Jane Doe",
  "age": 19
}
```

**Response:** `200 OK`
```json
{
  "message": "User updated successfully",
  "uid": "user123"
}
```

---

### Mood Tracking

#### Log Mood

**POST** `/api/moods`

**Request Body:**
```json
{
  "uid": "user123",
  "mood": "happy",
  "intensity": 8,
  "notes": "Had a great day today!"
}
```

**Response:** `201 Created`
```json
{
  "message": "Mood logged successfully",
  "moodId": "mood_abc123"
}
```

#### Get Mood History

**GET** `/api/moods/:uid`

**Response:** `200 OK`
```json
[
  {
    "id": "mood_abc123",
    "mood": "happy",
    "intensity": 8,
    "notes": "Had a great day today!",
    "timestamp": "2026-03-30T10:00:00.000Z"
  },
  {
    "id": "mood_xyz789",
    "mood": "calm",
    "intensity": 7,
    "notes": "Feeling peaceful",
    "timestamp": "2026-03-29T10:00:00.000Z"
  }
]
```

---

### Journal Entries

#### Create Journal Entry

**POST** `/api/journal`

**Request Body:**
```json
{
  "uid": "user123",
  "title": "My First Entry",
  "content": "Today was an amazing day. I accomplished my goals and felt great.",
  "mood": "happy"
}
```

**Response:** `201 Created`
```json
{
  "message": "Journal entry created",
  "entryId": "entry_abc123"
}
```

#### Get All Journal Entries

**GET** `/api/journal/:uid`

**Response:** `200 OK`
```json
[
  {
    "id": "entry_abc123",
    "title": "My First Entry",
    "content": "Today was an amazing day...",
    "mood": "happy",
    "timestamp": "2026-03-30T10:00:00.000Z",
    "updatedAt": "2026-03-30T10:00:00.000Z"
  }
]
```

#### Get Single Journal Entry

**GET** `/api/journal/:uid/:entryId`

**Response:** `200 OK`
```json
{
  "id": "entry_abc123",
  "title": "My First Entry",
  "content": "Today was an amazing day...",
  "mood": "happy",
  "timestamp": "2026-03-30T10:00:00.000Z",
  "updatedAt": "2026-03-30T10:00:00.000Z"
}
```

#### Update Journal Entry

**PATCH** `/api/journal/:uid/:entryId`

**Request Body:**
```json
{
  "title": "Updated Title",
  "content": "Updated content..."
}
```

**Response:** `200 OK`

#### Delete Journal Entry

**DELETE** `/api/journal/:uid/:entryId`

**Response:** `200 OK`
```json
{
  "message": "Entry deleted successfully"
}
```

---

### Habits

#### Create Habit

**POST** `/api/habits`

**Request Body:**
```json
{
  "uid": "user123",
  "name": "Morning Meditation",
  "description": "Meditate for 10 minutes each morning",
  "frequency": "daily",
  "color": "#FF6B6B"
}
```

**Response:** `201 Created`
```json
{
  "message": "Habit created",
  "habitId": "habit_abc123"
}
```

#### Get All Habits

**GET** `/api/habits/:uid`

**Response:** `200 OK`
```json
[
  {
    "id": "habit_abc123",
    "name": "Morning Meditation",
    "description": "Meditate for 10 minutes each morning",
    "frequency": "daily",
    "color": "#FF6B6B",
    "completed": 15,
    "streak": 5,
    "createdAt": "2026-03-20T10:00:00.000Z"
  }
]
```

#### Mark Habit as Completed

**POST** `/api/habits/:uid/:habitId/complete`

**Response:** `200 OK`
```json
{
  "message": "Habit marked as completed"
}
```

#### Delete Habit

**DELETE** `/api/habits/:uid/:habitId`

**Response:** `200 OK`
```json
{
  "message": "Habit deleted"
}
```

---

### Error Responses

All endpoints may return error responses in the following format:

**400 Bad Request**
```json
{
  "error": "uid and name are required"
}
```

**404 Not Found**
```json
{
  "error": "User not found"
}
```

**500 Internal Server Error**
```json
{
  "error": "Error message details"
}
```

// Firebase Real-time Database Schema Documentation
// This defines the structure for the Habi app data

/*
DATABASE STRUCTURE:
==================

users/
  {uid}/
    ├── email (string)
    ├── displayName (string)
    ├── pronouns (string)
    ├── age (number)
    ├── interests (array)
    ├── createdAt (timestamp)
    └── updatedAt (timestamp)

moods/
  {uid}/
    {moodId}/
      ├── mood (string) - "happy", "sad", "anxious", etc.
      ├── intensity (number) - 1-10 scale
      ├── notes (string)
      └── timestamp (ISO string)

journal/
  {uid}/
    {entryId}/
      ├── title (string)
      ├── content (string)
      ├── mood (string) - optional mood associated with entry
      ├── timestamp (ISO string)
      └── updatedAt (ISO string)

habits/
  {uid}/
    {habitId}/
      ├── name (string)
      ├── description (string)
      ├── frequency (string) - "daily", "weekly", "monthly"
      ├── color (string) - hex color code
      ├── completed (number)
      ├── streak (number)
      ├── lastCompleted (ISO string, optional)
      └── createdAt (ISO string)

*/

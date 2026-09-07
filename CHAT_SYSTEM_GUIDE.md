# HabiHero Guidance Chat System - End-to-End Implementation

## Overview

This document describes the end-to-end chat system for HabiHero that enables real-time communication between students and guidance counselors (admins) using Firebase Realtime Database.

## System Architecture

### Components

1. **Student Side (`guidance.tscn` + `guidance_chat.gd`)**
   - Godot scene for student chat interface
   - Handles sending messages to admin
   - Polls for admin responses in real-time
   - Uses Firebase Realtime Database for message storage

2. **Admin Side (`admin_chat_interface.gd` + `admin_panel_example.gd`)**
   - Reusable admin chat interface script
   - Example admin panel implementation
   - Manages multiple student conversations
   - Sends/receives messages in real-time

3. **Firebase Realtime Database**
   - Shared database for both student and admin sides
   - Stores conversations and messages
   - Enables real-time synchronization

## Database Structure

### Conversations Node
```
conversations/{conversationId}: {
  "id": "conv_user123_1234567890",
  "userId": "user123",
  "userName": "John Doe",
  "studentName": "John Doe", 
  "studentEmail": "john@example.com",
  "lastMessage": "Hello, how can I help?",
  "lastMessageAt": "2024-01-15 10:30:00",
  "unread": 0,
  "createdAt": "2024-01-15 10:00:00",
  "messages": {
    "msg_1234567890_12345": {
      "id": "msg_1234567890_12345",
      "conversationId": "conv_user123_1234567890",
      "senderId": "user123",
      "receiverId": "admin_1",
      "senderName": "John Doe",
      "message": "I need help with my homework",
      "timestamp": "2024-01-15 10:05:00",
      "read": false,
      "type": "text"
    }
  }
}
```

### Messages Node (for cross-platform compatibility)
```
messages/{messageId}: {
  "id": "msg_1234567890_12345",
  "conversationId": "conv_user123_1234567890",
  "senderId": "user123",
  "receiverId": "admin_1", 
  "senderName": "John Doe",
  "message": "I need help with my homework",
  "timestamp": "2024-01-15 10:05:00",
  "read": false,
  "type": "text"
}
```

## Key Features

### Real-Time Communication
- **Polling Interval**: 2 seconds for near real-time updates
- **Immediate Updates**: Messages trigger immediate poll after sending
- **Message Deduplication**: Tracks known message IDs to prevent duplicates

### End-to-End Message Flow
1. **Student sends message**:
   - Message written to `conversations/{convId}/messages/{msgId}`
   - Conversation metadata updated (lastMessage, lastMessageAt)
   - Message also written to `messages/{msgId}` for admin compatibility
   - Immediate poll triggered to check for admin response

2. **Admin receives message**:
   - Admin interface polls conversation every 2 seconds
   - New messages detected and displayed
   - Admin can view message history and respond

3. **Admin sends reply**:
   - Message written to same conversation structure
   - Student side polls and receives the reply
   - Both sides maintain synchronized message history

### User Identification
- **Student ID**: Resolved from session/auth system
- **Admin ID**: Fixed as "admin_1"
- **Conversation ID**: Generated as `conv_{sanitizedUserId}_{timestamp}`

## Implementation Details

### Student Side (`guidance_chat.gd`)

**Key Functions:**
- `_load_or_create_conversation()`: Finds existing conversation or creates new one
- `_on_send_pressed()`: Sends student message to Firebase
- `_poll_messages()`: Polls for new admin messages
- `_render_message()`: Displays messages in chat UI

**Configuration:**
```gdscript
const DEFAULT_FIREBASE_DB_URL: String = "https://adv-habi-default-rtdb.firebaseio.com"
const ADMIN_ID: String = "admin_1"
const POLL_INTERVAL_SEC: float = 2.0
```

### Admin Side (`admin_chat_interface.gd`)

**Key Functions:**
- `get_all_conversations()`: Retrieves all student conversations
- `load_conversation(conversation_id)`: Loads specific conversation
- `send_message(message_text)`: Sends admin reply
- `_poll_messages()`: Polls for new student messages

**Signals:**
- `conversation_loaded(conversation_data)`: Emitted when conversation loaded
- `message_received(message)`: Emitted when new message received
- `message_sent(success, message_data)`: Emitted when message sent
- `conversations_updated(conversations)`: Emitted when conversation list updated

## Setup Instructions

### 1. Firebase Configuration
Ensure your Firebase Realtime Database is configured with the correct rules:
```json
{
  "rules": {
    ".read": true,
    ".write": true,
    "conversations": {
      ".indexOn": ["userId", "lastMessageAt"]
    },
    "messages": {
      ".indexOn": ["conversationId", "timestamp"]
    }
  }
}
```

### 2. Student Side Setup
1. The `guidance.tscn` scene is already configured with `guidance_chat.gd`
2. Ensure Firebase RTDB node exists in your scene tree
3. Configure database URL in Firebase RTDB node or use default

### 3. Admin Side Setup
1. Add `admin_chat_interface.gd` as a child node to your admin panel
2. Connect to the signals provided by the interface
3. Use `admin_panel_example.gd` as a reference implementation
4. Create your UI with the required elements:
   - Conversation list display
   - Chat message display
   - Message input field
   - Send button

### 4. Custom Admin Panel Example
```gdscript
extends Control

var _admin_chat: Node

func _ready() -> void:
    # Create admin chat interface
    _admin_chat = preload("res://admin_chat_interface.gd").new()
    add_child(_admin_chat)
    
    # Connect signals
    _admin_chat.conversations_updated.connect(_on_conversations_updated)
    _admin_chat.message_received.connect(_on_message_received)
    _admin_chat.message_sent.connect(_on_message_sent)
    
    # Load conversations
    _admin_chat.get_all_conversations()

func _on_conversations_updated(conversations: Dictionary) -> void:
    # Update your conversation list UI
    pass

func _on_message_received(message: Dictionary) -> void:
    # Display new message in chat UI
    pass

func _on_message_sent(success: bool, message_data: Dictionary) -> void:
    # Handle send confirmation
    pass

func send_admin_message(text: String) -> void:
    _admin_chat.send_message(text)
```

## Testing the System

### 1. Student Side Testing
1. Run the HabiHero application
2. Navigate to the Guidance Counselor section
3. Send a test message
4. Check Firebase console to verify message storage
5. Verify conversation structure in database

### 2. Admin Side Testing
1. Create a test scene using `admin_panel_example.tscn`
2. Run the admin panel
3. Verify conversation list loads
4. Select a conversation and send a reply
5. Check Firebase console for message storage
6. Verify student side receives the message

### 3. End-to-End Testing
1. Start student application
2. Start admin panel
3. Student sends message
4. Admin receives and responds
5. Student receives admin response
6. Verify message history on both sides

## Troubleshooting

### Messages not appearing
- Check Firebase database URL configuration
- Verify Firebase database rules allow read/write
- Check network connectivity
- Review debug logs for error messages

### Conversation not found
- Verify user ID resolution is working
- Check conversation ID generation
- Ensure proper path sanitization
- Review Firebase database structure

### Real-time updates not working
- Verify polling timer is running
- Check polling interval configuration
- Ensure HTTP requests are completing successfully
- Review message deduplication logic

## Security Considerations

1. **Authentication**: Implement proper Firebase Authentication
2. **Database Rules**: Set appropriate Firebase security rules
3. **Input Validation**: Sanitize all user inputs
4. **Rate Limiting**: Consider implementing rate limiting for API calls
5. **Data Privacy**: Ensure student data is properly protected

## Future Enhancements

1. **WebSocket Support**: Replace polling with Firebase Realtime Database listeners
2. **Push Notifications**: Add notifications for new messages
3. **File Sharing**: Enable file/image sharing in chats
4. **Message Encryption**: Implement end-to-end encryption
5. **Offline Support**: Add offline message queuing
6. **Typing Indicators**: Show when user is typing
7. **Read Receipts**: Implement proper read receipt system

## Support

For issues or questions:
1. Check Firebase console for database errors
2. Review Godot debug output for error messages
3. Verify network connectivity
4. Check Firebase service account configuration
# LiveKit demo (Godot)

Quick steps to test LiveKit from Godot using the installed `godot-livekit` plugin and the local backend.

1. Configure backend environment (in `adventure-habi/habi-backend/.env`):

```
LIVEKIT_URL=https://your-livekit-server
LIVEKIT_API_KEY=your_api_key
LIVEKIT_API_SECRET=your_api_secret
```

2. Start the backend server:

```powershell
cd adventure-habi\habi-backend
npm run start
```

3. In Godot Editor: open the project, enable the plugin (Project → Project Settings → Plugins → Godot LiveKit).

4. Open the example scene: `res://godot_examples/livekit_demo.tscn` and run it.

5. The demo will request a token from the backend (`/api/livekit/token`) and connect to the LiveKit server. Watch the output for `LiveKit room connected`.

Test UI scene

- A lightweight test UI is also available: `res://godot_examples/livekit_test_ui.tscn`.
- Open it to enter backend URL and room name, click `Request Token & Connect`, and watch the status and token fields.

If you want me to wire the backend `.env` values automatically or add a helper endpoint to create a short-lived test token for the Godot client, tell me and I will add it.

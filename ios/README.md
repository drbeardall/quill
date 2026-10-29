# Quill for iPhone

A Quill app plus a Quill keyboard. Tap the mic on the keyboard in any app, talk, tap again, and the
cleaned-up text is typed where you are. Speech recognition (Whisper) runs on the iPhone; Claude
cleanup uses your API key, same as the Mac app.

## Put it on your iPhone (about 15 minutes the first time)

You need: Xcode, your iPhone and its cable, and your Apple ID.

1. **Create the Xcode project.** In Terminal:
   ```bash
   cd ~/quill/ios && chmod +x setup.sh && ./setup.sh
   ```
   Xcode opens and fetches WhisperKit (wait for the progress bar at the top to finish).

2. **Sign it with your Apple ID.** In Xcode's left sidebar click **Quill** (the blue icon at the top).
   - Under **TARGETS** select **Quill** → **Signing & Capabilities** → **Team**: choose your name.
     (No team listed? Choose **Add an Account…** and sign in with your Apple ID.)
   - Select **QuillKeyboard** and choose the same Team.

3. **Connect your iPhone** with the cable and unlock it. Tap **Trust** if asked.
   If Xcode says Developer Mode is needed: on the iPhone go to **Settings › Privacy & Security ›
   Developer Mode**, turn it on and restart the phone.

4. **Run it.** At the top of Xcode, pick your iPhone from the device menu, then press **▶**.
   The first build takes a few minutes.
   If the iPhone says *Untrusted Developer*: **Settings › General › VPN & Device Management** →
   your Apple ID → **Trust**, then press ▶ again.

5. **Finish on the iPhone.** Open Quill. It downloads the speech model the first time (a few
   hundred MB, stay on Wi-Fi). Then go to **Settings tab › Set up the Quill keyboard** and follow
   the steps (turn on Quill and **Allow Full Access**). Paste your Claude API key in Settings too.

## Using the keyboard

- In any app, tap and hold 🌐 and choose **Quill**.
- Tap the **mic**, talk, tap again. The first time, iPhone hops to the Quill app to switch the
  microphone on: tap **◀** in the top-left corner to go back, then talk. For the next few minutes
  (Settings › Keyboard session) the mic works right inside the keyboard, with the orange dot showing.
- **Write / Rewrite**: select text, tap it, say what to change ("make this more formal"). With nothing
  selected, say what to write.
- Style chips (Clean, Formal, Casual, Texting, Clinical) set the tone for the next dictation.
- The snippet button lists your snippets to insert with one tap; you can also say them.

## Good to know

- **Free Apple ID vs paid developer account:** with a free account, apps you install from Xcode
  stop opening after 7 days (just press ▶ again), and some accounts can't use the "App Groups"
  feature the keyboard needs. If Xcode shows an App Groups signing error, you'll need the $99/year
  Apple Developer Program, which you'd also need to sell the app.
- **"Bundle identifier is not available":** someone already uses `com.drbeardall.quill`. Change
  `com.drbeardall` in `project.yml` (and `group.com.drbeardall.quill` in `project.yml`,
  `Shared/QuillSettings.swift`), then run `./setup.sh` again.
- **Patient information:** audio and transcription stay on the iPhone. With Claude cleanup on,
  the transcribed text goes to Anthropic. Turn cleanup off for charting unless you have a BAA.

## Files

```
project.yml          Xcode project definition (XcodeGen)
Shared/              settings, prompts and keyboard↔app bridge (used by both targets)
App/                 Quill app: microphone, WhisperKit, Claude, settings screens
Keyboard/            Quill keyboard extension
```

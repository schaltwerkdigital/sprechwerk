# Setup

## 1. Install

Install or update with `install.sh` (see the README), or build it:

```bash
brew install xcodegen
git clone https://github.com/schaltwerkdigital/sprechwerk.git
cd sprechwerk
./build.sh --install --run
```

The app is installed to `/Applications/Sprechwerk.app` and appears in the menu bar.

## 2. Permissions

- **Microphone:** to record.
- **Accessibility:** to paste into the app you are using. Without it, results stay on the clipboard.

If paste stops working after an update or rebuild, open **System Settings > Privacy & Security > Accessibility**, remove old Sprechwerk entries, add the current app and restart Sprechwerk.

## 3. Local Speech Model

Open **Settings > Modelle > Spracherkennung**, pick a model and load it once:

- **Parakeet Ultra** (recommended on Apple silicon): fast, 25 European languages, about 630 MB.
- **Whisper Large v3 Turbo / Small:** about 100 languages, slower.

After a macOS update the first dictation can take a few minutes while macOS prepares the model for the Neural Engine. Sprechwerk shows a hint; keep it running.

## 4. Writing Modes

Sprechwerk+, $%&! and :) need a language model:

- **Apple Intelligence** (macOS 26, turned on in System Settings): runs on your Mac. Nothing to configure.
- **Your own model provider** (optional): **Settings > Modelle > Modell-Anbieter**, choose a provider, paste your API key, test the connection. Local servers such as Ollama or LM Studio work via "Eigene Adresse".

## 5. Shortcuts

`fn` shortcuts only work on Apple keyboards. For other keyboards set your own shortcut per mode in **Settings > Allgemein > Tastenkürzel** (e.g. `⌃⌥D` or `F13`). An own shortcut replaces the `fn` shortcut of that mode. `fn` itself cannot be part of an own shortcut.

**Halten:** hold to record, release to process. **Drücken:** press to start, press again or `Esc` to stop.

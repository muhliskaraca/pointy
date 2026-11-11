# Pointy

Zeig auf etwas am Mac, halte **^** und tippe **1**, und eine kleine Blase geht direkt am Mauszeiger auf. Du sagst oder tippst, was du willst, und Claude Code sieht, worauf du zeigst: den Text unter dem Mauszeiger, deine Markierung, die Webadresse und ein Bild der Stelle. Mit einem Klick auf **Einsetzen** landet Claudes Antwort genau in dem Feld, auf das du gezeigt hast.

Gebaut in der Rubrik „Cody baut“: Cody kann nicht programmieren, er beschreibt nur, was er will, und Claude baut es (Vibe Coding).

> Inoffiziell. Nicht von Anthropic. „Claude“ ist eine Marke von Anthropic.
>
> **English below:** [English](#english)

## Was es kann

| Tasten | Was passiert |
|---|---|
| ^ halten + 1 | Blase am Mauszeiger öffnen, nochmal: abschicken oder zuhören |
| ^ halten + 2 | einen Bildausschnitt aufziehen, den Claude ansehen soll |
| ⌘ Enter oder Knopf „Einsetzen“ | Claudes Text an der gezeigten Stelle einfügen |
| Knopf „Im Terminal weiter“ | dasselbe Gespräch im Terminal fortsetzen |

Die Oberfläche folgt der Mac-Sprache (Deutsch oder Englisch). Selbst wählen: ein Wort, `de` oder `en`, in `~/Library/Application Support/Pointy/sprache`.

Das ^ ist die Taste links neben der 1 (deutsche Tastatur). Auf US-Tastaturen ist es die Taste mit ` und ~.

Beispiele: Auf eine Nachricht zeigen und sagen „Antworte freundlich, dass ich morgen kann“, dann Einsetzen. Einen Absatz markieren und „Mach das kürzer“. Mit ^ + 2 ein Diagramm aufziehen und fragen „Was sagt mir das?“.

## Was du brauchst

1. Einen Mac mit macOS 14 (Sonoma) oder neuer.
2. **Claude Code**, installiert und angemeldet. Im Terminal muss `claude` laufen. Anleitung: https://claude.com/claude-code
3. Die Entwicklerwerkzeuge von Apple: im Terminal `xcode-select --install` (einmalig, ein paar Minuten).

## Installieren, Schritt für Schritt

1. Diesen Ordner herunterladen (grüner Knopf „Code“ > „Download ZIP“) und entpacken, oder `git clone`.
2. Terminal öffnen und in den Ordner wechseln: `cd ~/Downloads/pointy-main` (nach „Download ZIP“ heißt der Ordner `pointy-main`, nach `git clone` nur `pointy`).
3. Bauen und starten: `./build.sh --start`
4. Oben in der Menüleiste erscheint ein Mauszeiger-Symbol. Das ist Pointy.
5. macOS fragt nach Rechten. Alle in **Systemeinstellungen > Datenschutz & Sicherheit**:
   - **Bedienungshilfen**: Pointy einschalten. Nötig für die Tasten, den Text unter dem Mauszeiger und das Einsetzen.
   - **Bildschirmaufnahme**: Pointy einschalten. Nötig, damit Claude die Stelle sieht.
   - **Mikrofon** und **Spracherkennung**: erst beim ersten Sprechen. Wer nur tippt, braucht sie nicht.
6. Nach dem Erlauben Pointy einmal neu starten: Menüleiste > Beenden, dann `open ~/Applications/Pointy.app`.
7. Ausprobieren: auf irgendeinen Text zeigen, ^ halten, 1 tippen, „Was steht hier?“ sagen oder tippen.

Pointy startet ab jetzt bei jeder Anmeldung mit. Abschalten: Menüleiste > Autostart ausschalten.

## Was Claude darf

Claude läuft im Hintergrund als `claude -p` in deinem Benutzerordner. Ab Werk darf es **nur lesen**: Es sieht den Kontext, antwortet und formuliert Texte, ändert aber nichts auf deinem Mac. Wer mehr will, startet Pointy so:

```
launchctl setenv POINTY_PERMISSION_MODE acceptEdits   # darf Dateien ändern
open ~/Applications/Pointy.app
```

Werte wie bei Claude Code: `default` (nur lesen, Standard), `acceptEdits`, `auto`. Liegt `claude` nicht im normalen Pfad, zeigt `POINTY_CLAUDE=/pfad/zu/claude` auf den richtigen Ort.

Dauerhaft und ohne Terminal geht es mit zwei kleinen Dateien im Ordner `~/Library/Application Support/Pointy/`:

- `rechte`: ein Wort, `acceptEdits` oder `auto`. Gilt ab dem nächsten Start von Pointy.
- `regeln.md`: eigene Regeln für Claude, eine pro Zeile, zum Beispiel „Mails nur als Entwurf ablegen“ oder „Antworte immer auf Englisch“. Gilt ab der nächsten Frage.

Beide Dateien bleiben auf deinem Mac.

Was Claude an Kontext bekommt, bleibt auf deinem Mac und geht nur an Claude Code, so wie alles, was du im Terminal mit Claude machst. Bilder landen in `~/Library/Caches/Pointy` (nur die letzten 10), das Protokoll in `~/Library/Logs/Pointy.log`.

## Wenn etwas nicht geht

- **Blase geht nicht auf**: Bedienungshilfen für Pointy an? Danach Pointy neu starten. Im Protokoll muss „Bedienungshilfen erlaubt“ stehen.
- **Claude sieht kein Bild**: Bildschirmaufnahme erlauben, Pointy neu starten.
- **Fehler bei Claude**: im Terminal `claude` starten und prüfen, ob du angemeldet bist.
- **Nach jedem Neubau fragt macOS wieder nach Rechten**: das liegt an der Ad-hoc-Signatur. Mit eigener Apple-Development-Identität bleiben die Rechte: `POINTY_SIGN_ID="Apple Development: …" ./build.sh` (Liste: `security find-identity -p codesigning -v`).
- **Einsetzen landet nicht**: manche Apps nehmen kein Einfügen von außen an. Dann den Text in der Blase kopieren.

## Selbsttests

```
~/Applications/Pointy.app/Contents/MacOS/Pointy --oeffnen        # Blase öffnen
~/Applications/Pointy.app/Contents/MacOS/Pointy --test "Was steht hier?"
~/Applications/Pointy.app/Contents/MacOS/Pointy --ausschnitt     # Ausschnitt aufziehen
~/Applications/Pointy.app/Contents/MacOS/Pointy --einsetzen      # letzte Antwort einsetzen
~/Applications/Pointy.app/Contents/MacOS/Pointy --schliessen     # Blase schließen
```

## Aufbau

Eine einzige Datei: `Sources/main.swift` (AppKit + SwiftUI, etwa 1200 Zeilen). Bedienungshilfen-Schnittstelle für Text und Markierung, `screencapture` für Bilder, Apples Spracherkennung, Claude Code per `claude -p --output-format stream-json`. Bauen ohne Xcode-Projekt, nur `swiftc` in `build.sh`.

## Lizenz

MIT, siehe `LICENSE`.

---

## English

Point at anything on your Mac, hold the key left of **1** and press **1**, and a small bubble opens right at the mouse pointer. Say or type what you want, and Claude Code sees what you are pointing at: the text under the mouse pointer, your selection, the web address and a picture of the spot. Click **Insert** and Claude's answer lands in exactly the field you pointed at.

Built for the series "Cody Builds": Cody can't code, he only describes what he wants, and Claude builds it (vibe coding).

### What it does

| Keys | What happens |
|---|---|
| hold the key left of 1, press 1 | open the bubble at the mouse pointer; again: send or listen |
| hold the key left of 1, press 2 | drag a screen region for Claude to look at |
| ⌘ Return or the **Insert** button | type Claude's text into the spot you pointed at |
| **Continue in Terminal** button | continue the same conversation in the Terminal |

The key left of 1 is ` on US keyboards, § on many international Apple keyboards and ^ on German keyboards.

Examples: point at a message and say "Reply kindly that tomorrow works for me", then Insert. Select a paragraph and say "Make this shorter". Drag a frame around a chart with key + 2 and ask "What does this tell me?".

### Language

Pointy follows your Mac's language: German if German comes first, English otherwise. To choose yourself, put one word, `en` or `de`, into the file `~/Library/Application Support/Pointy/sprache`, then restart Pointy:

```
mkdir -p ~/Library/Application\ Support/Pointy && echo en > ~/Library/Application\ Support/Pointy/sprache
```

For one session only: `launchctl setenv POINTY_LANG en`.

### What you need

1. A Mac with macOS 14 (Sonoma) or newer.
2. **Claude Code**, installed and signed in. `claude` must run in the Terminal. Guide: https://claude.com/claude-code
3. Apple's developer tools: in the Terminal, `xcode-select --install` (once, a few minutes).

### Install, step by step

1. Download this folder (green "Code" button > "Download ZIP") and unzip it, or `git clone`.
2. Open the Terminal and go into the folder: `cd ~/Downloads/pointy-main` (adjust the path).
3. Build and start: `./build.sh --start`
4. A mouse pointer icon appears in the menu bar. That's Pointy.
5. macOS asks for permissions. All of them are in **System Settings > Privacy & Security**:
   - **Accessibility**: switch Pointy on. Needed for the keys, the text under the mouse pointer and inserting.
   - **Screen Recording** (on newer macOS: Screen & System Audio Recording): switch Pointy on. Needed so Claude can see the spot.
   - **Microphone** and **Speech Recognition**: only the first time you talk. If you only type, you don't need them.
6. After allowing, restart Pointy once: menu bar > Quit, then `open ~/Applications/Pointy.app`.
7. Try it: point at any text, hold the key left of 1, press 1, say or type "What does this say?".

From now on Pointy starts every time you log in. To stop that: menu bar > Turn off autostart.

### What Claude may do

Claude runs in the background as `claude -p` in your home folder. Out of the box it may **only read**: it sees the context, answers and writes texts, but changes nothing on your Mac. If you want more, start Pointy like this:

```
launchctl setenv POINTY_PERMISSION_MODE acceptEdits   # may edit files
open ~/Applications/Pointy.app
```

Values as in Claude Code: `default` (read only, the default), `acceptEdits`, `auto`. If `claude` is not on the normal path, point `POINTY_CLAUDE=/path/to/claude` to it.

Permanently and without the Terminal, use two small files in `~/Library/Application Support/Pointy/`:

- `rechte`: one word, `acceptEdits` or `auto`. Applies from the next start of Pointy.
- `regeln.md`: your own rules for Claude, one per line, for example "Only save emails as drafts" or "Always answer in English". Applies from the next question.

Both files stay on your Mac.

The context Claude gets stays on your Mac and only goes to Claude Code, just like everything you do with Claude in the Terminal. Pictures go to `~/Library/Caches/Pointy` (only the last 10), the log to `~/Library/Logs/Pointy.log`.

### If something fails

- **The bubble won't open**: is Accessibility on for Pointy? Then restart Pointy.
- **Claude sees no picture**: allow Screen Recording, restart Pointy.
- **Error from Claude**: start `claude` in the Terminal and check that you are signed in.
- **macOS asks for permissions again after every rebuild**: that's the ad-hoc signature. With your own Apple Development identity the permissions stay: `POINTY_SIGN_ID="Apple Development: …" ./build.sh` (list: `security find-identity -p codesigning -v`).
- **Insert doesn't land**: some apps don't accept pasting from outside. Then copy the text from the bubble.

### Under the hood

One single file: `Sources/main.swift` (AppKit + SwiftUI, about 1,200 lines). Accessibility API for text and selection, `screencapture` for pictures, Apple's speech recognition, Claude Code via `claude -p --output-format stream-json`. Built without an Xcode project, just `swiftc` in `build.sh`.

MIT license, see `LICENSE`. Unofficial. Not made by Anthropic. "Claude" is a trademark of Anthropic.

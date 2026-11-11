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
2. Ein Claude-Abo (Pro oder höher), Claude Code ist darin enthalten.
3. Einmalig etwa 15 Minuten. Vorkenntnisse brauchst du nicht.

## Das Terminal, kurz erklärt

Alle Befehle unten tippst du nicht ab, sondern kopierst sie ins Terminal, ein Fenster für Befehle.

- Öffnen: ⌘ und Leertaste drücken, „Terminal“ tippen, Enter.
- Befehl einfügen: den Befehl hier kopieren (⌘C), ins Terminal klicken, einfügen (⌘V), Enter.
- Warten, bis das Terminal wieder bereit ist (eine neue Zeile, die mit `%` endet), dann der nächste Befehl.

## Installieren, Schritt für Schritt

Hast du Claude Code schon (im Terminal läuft `claude`), fang bei Schritt 3 an.

1. Claude Code installieren:
   ```
   curl -fsSL https://claude.ai/install.sh | bash
   ```
2. Claude Code einmal starten und anmelden. Den Fragen folgen (Pfeiltasten, Enter), der Browser geht zum Anmelden auf. Danach `/exit` tippen, Enter:
   ```
   ~/.local/bin/claude
   ```
3. Entwicklerwerkzeuge von Apple installieren. Im Fenster, das aufgeht, „Installieren“ klicken und warten (ein paar Minuten). Steht im Terminal „already installed“, ist alles schon da:
   ```
   xcode-select --install
   ```
4. Pointy laden, bauen und starten (ein Befehl, dauert etwa eine Minute):
   ```
   cd ~/Downloads && curl -fsSL -o pointy.zip https://github.com/muhliskaraca/pointy/archive/refs/heads/main.zip && unzip -oq pointy.zip && cd pointy-main && ./build.sh --start
   ```
   Oben in der Menüleiste erscheint ein Mauszeiger-Symbol. Das ist Pointy. (Wer lieber klickt: grüner Knopf „Code“ > „Download ZIP“, dann `cd ~/Downloads/pointy-main` und `./build.sh --start`.)
5. Rechte geben, alle unter **Apfel-Menü > Systemeinstellungen > Datenschutz & Sicherheit**:
   - **Bedienungshilfen**: Pointy einschalten. Nötig für die Tasten, den Text unter dem Mauszeiger und das Einsetzen.
   - **Bildschirmaufnahme** (auf neueren Macs mit „Systemaudio“ im Namen): Pointy einschalten. Nötig, damit Claude die Stelle sieht.
   - **Mikrofon** und **Spracherkennung**: erst beim ersten Sprechen. Wer nur tippt, braucht sie nicht.
6. Pointy neu starten, damit die Rechte greifen:
   ```
   killall Pointy; sleep 1; open ~/Applications/Pointy.app
   ```
7. Ausprobieren: auf irgendeinen Text zeigen, ^ halten, 1 tippen, „Was steht hier?“ sagen oder tippen.

Neue Fassung von Pointy holen: Befehl aus Schritt 4 noch einmal.

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

Zwei Dateien: `Sources/main.swift` (AppKit + SwiftUI, etwa 1300 Zeilen) und `Sources/HoerenNeu.swift` (Apples neue Spracherkennung ab macOS 26, ältere Macs nehmen die bisherige). Bedienungshilfen-Schnittstelle für Text und Markierung, `screencapture` für Bilder, Apples Spracherkennung, Claude Code per `claude -p --output-format stream-json`. Bauen ohne Xcode-Projekt, nur `swiftc` in `build.sh`.

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
2. A Claude subscription (Pro or higher), Claude Code is included.
3. About 15 minutes, once. No experience needed.

### The Terminal, in short

You don't type the commands below, you copy them into the Terminal, a window for commands.

- Open it: press ⌘ and Space, type "Terminal", Return.
- Paste a command: copy it here (⌘C), click into the Terminal, paste (⌘V), Return.
- Wait until the Terminal is ready again (a new line ending in `%`), then the next command.

### Install, step by step

Already have Claude Code (`claude` runs in the Terminal)? Start at step 3.

1. Install Claude Code:
   ```
   curl -fsSL https://claude.ai/install.sh | bash
   ```
2. Start Claude Code once and sign in. Follow the questions (arrow keys, Return), the browser opens for signing in. Then type `/exit`, Return:
   ```
   ~/.local/bin/claude
   ```
3. Install Apple's developer tools. In the window that opens, click "Install" and wait (a few minutes). If the Terminal says "already installed", you have them:
   ```
   xcode-select --install
   ```
4. Download, build and start Pointy (one command, takes about a minute):
   ```
   cd ~/Downloads && curl -fsSL -o pointy.zip https://github.com/muhliskaraca/pointy/archive/refs/heads/main.zip && unzip -oq pointy.zip && cd pointy-main && ./build.sh --start
   ```
   A mouse pointer icon appears in the menu bar. That's Pointy. (Prefer clicking? Green "Code" button > "Download ZIP", then `cd ~/Downloads/pointy-main` and `./build.sh --start`.)
5. Give permissions, all under **Apple menu > System Settings > Privacy & Security**:
   - **Accessibility**: switch Pointy on. Needed for the keys, the text under the mouse pointer and inserting.
   - **Screen Recording** (on newer macOS: Screen & System Audio Recording): switch Pointy on. Needed so Claude can see the spot.
   - **Microphone** and **Speech Recognition**: only the first time you talk. If you only type, you don't need them.
6. Restart Pointy so the permissions apply:
   ```
   killall Pointy; sleep 1; open ~/Applications/Pointy.app
   ```
7. Try it: point at any text, hold the key left of 1, press 1, say or type "What does this say?".

Get a new version of Pointy: run the command from step 4 again.

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

Two files: `Sources/main.swift` (AppKit + SwiftUI, about 1,300 lines) and `Sources/HoerenNeu.swift` (Apple's new speech recognition from macOS 26 on, older Macs use the previous one). Accessibility API for text and selection, `screencapture` for pictures, Apple's speech recognition, Claude Code via `claude -p --output-format stream-json`. Built without an Xcode project, just `swiftc` in `build.sh`.

MIT license, see `LICENSE`. Unofficial. Not made by Anthropic. "Claude" is a trademark of Anthropic.

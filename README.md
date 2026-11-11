# Pointy

Zeig auf etwas am Mac, halte **^** und tippe **1**, und eine kleine Blase geht direkt am Mauszeiger auf. Du sagst oder tippst, was du willst, und Claude Code sieht, worauf du zeigst: den Text unter dem Mauszeiger, deine Markierung, die Webadresse und ein Bild der Stelle. Mit einem Klick auf **Einsetzen** landet Claudes Antwort genau in dem Feld, auf das du gezeigt hast.

Gebaut in der Rubrik „Cody baut“: Cody kann nicht programmieren, er beschreibt nur, was er will, und Claude baut es (Vibe Coding).

> Inoffiziell. Nicht von Anthropic. „Claude“ ist eine Marke von Anthropic.

## Was es kann

| Tasten | Was passiert |
|---|---|
| ^ halten + 1 | Blase am Mauszeiger öffnen, nochmal: abschicken oder zuhören |
| ^ halten + 2 | einen Bildausschnitt aufziehen, den Claude ansehen soll |
| ⌘ Enter oder Knopf „Einsetzen“ | Claudes Text an der gezeigten Stelle einfügen |
| Knopf „Im Terminal weiter“ | dasselbe Gespräch im Terminal fortsetzen |

Das ^ ist die Taste links neben der 1 (deutsche Tastatur). Auf US-Tastaturen ist es die Taste mit ` und ~.

Beispiele: Auf eine Nachricht zeigen und sagen „Antworte freundlich, dass ich morgen kann“, dann Einsetzen. Einen Absatz markieren und „Mach das kürzer“. Mit ^ + 2 ein Diagramm aufziehen und fragen „Was sagt mir das?“.

## Was du brauchst

1. Einen Mac mit macOS 14 (Sonoma) oder neuer.
2. **Claude Code**, installiert und angemeldet. Im Terminal muss `claude` laufen. Anleitung: https://claude.com/claude-code
3. Die Entwicklerwerkzeuge von Apple: im Terminal `xcode-select --install` (einmalig, ein paar Minuten).

## Installieren, Schritt für Schritt

1. Diesen Ordner herunterladen (grüner Knopf „Code“ > „Download ZIP“) und entpacken, oder `git clone`.
2. Terminal öffnen und in den Ordner wechseln: `cd ~/Downloads/pointy` (Pfad anpassen).
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

Eine einzige Datei: `Sources/main.swift` (AppKit + SwiftUI, etwa 1000 Zeilen). Bedienungshilfen-Schnittstelle für Text und Markierung, `screencapture` für Bilder, Apples Spracherkennung, Claude Code per `claude -p --output-format stream-json`. Bauen ohne Xcode-Projekt, nur `swiftc` in `build.sh`.

## Lizenz

MIT, siehe `LICENSE`.

---

## English, short

Point at anything on your Mac, hold **^** (the key left of 1; on US keyboards the ` key) and press **1**: a bubble opens at the mouse cursor. Speak or type, and Claude Code sees what you point at (text under the cursor, selection, URL, a screenshot of the spot). **Einsetzen** (insert) types Claude's answer into the field you pointed at. ^ + 2 lets you drag a screen region for Claude to look at.

Needs macOS 14+, Claude Code installed and signed in, and `xcode-select --install`. Then `./build.sh --start` and allow Accessibility and Screen Recording in System Settings. By default Claude may only read; set `POINTY_PERMISSION_MODE` to `acceptEdits` or `auto` for more. The UI is in German for now.

Unofficial. Not made by Anthropic.

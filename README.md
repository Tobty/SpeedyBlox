# SpeedyBlox – Geschicklichkeits-Parcours für Roblox

Ein Parkour-Spiel hoch über einem Lavasee. Der ganze Parcours wird beim Spielstart
**per Skript gebaut** – du musst in Roblox Studio nichts von Hand bauen.

## Die Abschnitte

| # | Abschnitt | Was ist zu tun? |
|---|-----------|-----------------|
| 1 | Sprungsteine | Über kleine, leicht ansteigende Steine springen |
| 2 | Lavasteg | Schmaler Steg, Lavablöcke überspringen |
| 3 | Schwebeplattformen | Plattformen fahren hin und her – Timing! |
| 4 | Drehbalken | Über rotierende Lavabalken springen (zuerst einer, dann ein Kreuz) |
| 5 | Laufband | Gegen ein rückwärts laufendes Band anrennen, Hindernissen ausweichen |
| 6 | Bröckelplatten | Platten zerfallen kurz nach dem Betreten – nicht stehen bleiben |
| 7 | Blinkplatten | Zwei Gruppen erscheinen abwechselnd, durchsichtig = gleich weg |
| 8 | Sprungfeld | Grünes Feld schleudert dich aufs Hochplateau |
| 9 | Balancierbalken | Schmale Balken mit pendelnden Lavakugeln |
| 🏁 | Ziel | Zeit wird gestoppt, Konfetti, Bestzeit wird gespeichert |

Dazu: 8 Checkpoints, Stoppuhr (startet am Starttor), Todeszähler, Bestenliste
(Tab-Taste) und ein **↺ Nochmal**-Feld im Ziel für einen neuen Lauf.

## Einbau in Roblox Studio (ohne Zusatztools)

1. Roblox Studio öffnen → **Neu** → Vorlage **Baseplate** (oder **Classic Baseplate**).
2. Im Explorer rechts auf **ServerScriptService** → **+** → **Script**.
   Den Inhalt von [`src/server/Parcours.server.lua`](src/server/Parcours.server.lua) hineinkopieren.
3. Im Explorer **StarterPlayer** aufklappen → auf **StarterPlayerScripts** → **+** → **LocalScript**.
   Den Inhalt von [`src/client/HUD.client.lua`](src/client/HUD.client.lua) hineinkopieren.
4. **Play** (F5) drücken – du startest auf der blauen Glasplattform.

Optional, damit Bestzeiten dauerhaft gespeichert werden: Spiel veröffentlichen und unter
*Spieleinstellungen → Sicherheit* **„Enable Studio Access to API Services“** einschalten.
Ohne das läuft alles genauso, nur die Bestzeit gilt dann bloß für die aktuelle Sitzung.

## Mit Rojo

Rojo ist über [Aftman](https://github.com/LPGhatguy/aftman) in `aftman.toml` festgelegt.
Einmalig im Projektordner installieren, danach starten:

```bash
aftman install
```

```bash
rojo serve
```

In Roblox Studio im Rojo-Plugin auf **Connect** klicken.

Die Datei `default.project.json` legt beide Skripte an die richtigen Stellen.

## Anpassen

Oben im Server-Skript stehen die wichtigsten Stellschrauben:

- `BASIS_Y` – Höhe des Parcours, `LAVA_Y` – Höhe des Lavasees
- `SPRUNGKRAFT` – wie hoch das Sprungfeld schleudert
- `FARBEN` – alle Farben an einer Stelle

Jeder Abschnitt ist ein eigener, kommentierter Block (`-- 1) SPRUNGSTEINE`, `-- 2) LAVASTEG` …).
Abstände, Geschwindigkeiten (`tempo`) und Weiten (`weite`) lassen sich dort direkt ändern,
oder man kopiert einen Block, um den Parcours zu verlängern.

# Lumi Go-Stop

[한국어](README.md) | **English**

A Delphi FMX implementation of **Go-Stop (Gostop / Matgo)**, Korea's classic hwatu (flower card) game — full 2–4 player game core, UI, and AI opponents.

![Title screen](docs/screenshots/title.png)

## Why I built this

This project is a roughly 40-year-old unfinished assignment.

Long before the 386, back in the days of the **IBM XT (8086)**, I tried to write a Go-Stop game in Turbo Pascal. It failed. Over the following decades I tried again a few more times — about once per era. The reasons were always similar: life got busy making a living, or I hit a wall I couldn't clear alone, whether it was the rules or the UI. Each time, I put it down.

Years passed, and now I'm closing in on retirement age. But these days, thanks to AI, every day feels fun again — things that used to take months of solo grinding can now be tried out in a matter of days. Then one day, digging through an old hard drive, I found a chunk of source code from one of those abandoned attempts. I dusted it off, opened it back up, and this time rebuilt it from scratch with **Claude Code**, vibe-coding the whole way.

For a 40-year homework assignment, it turned out pretty well.

**Time to build**: squeezed in during the idle gaps of my day job (waiting on builds, deploys, that kind of thing) — roughly **5 days** total. Not bad for something that had been on hold for 40 years.

**How it was built**: with the **Claude Code CLI**, alternating between **Opus 4.8** and **Sonnet 5**.

### What I noticed along the way

Coding with AI is clearly faster, and it breezes through hard problems that would've kept me stuck for days on my own. But the actual essence of programming — defining the problem, and figuring out how to solve it — is still on the human side of the table. At least for now.

Given how fast AI is moving, it's not hard to imagine a near future where "build me a Go-Stop game, research the rules yourself" is all it takes.

### Some closing thoughts

Forty years after I first tried, I ended up with something close to production quality. And yet, now that it's actually done, there's a certain hollowness to it that's hard to deny. Maybe that's just the fate of being a developer in the age of AI.

## What it can do

- **2 / 3 / 4-player modes** — 4-player includes the traditional "sell your gwang" (광팔기) negotiation phase
- **Full rule set** — captures · bbeok (stuck pair) · ttadak (double capture) · jjok (snipe) · sseul (sweep) · self-bbeok · chain-bbeok · first-bbeok · shake · bomb · bomb penalty (flip-only turns) · chongtong (four-of-a-kind instant win) · three-bbeok instant win · go/stop · nagari (draw)
- **Scoring** — brights, animals (godori), ribbons (hong-dan/cheong-dan/cho-dan), junk (double-junk/triple-junk), pibak/gwangbak/gobak/meongbak penalties, dual interpretation of the September "gukjin" card (winner gets max score, loser gets whichever interpretation avoids pibak)
- **AI opponents** — a single skill dial drives mistake rate, go/stop judgment, determinized Monte Carlo lookahead, and defensive play; 20 characters with personas, speech bubbles, and mood-based avatars
- **Save / resume** — auto-saves on exit, resumes right where you left off
- **Sound & animation** — situational sound effects, staged card animations
- **In-app help** — open the manual and rulebook straight from the title screen in your browser

## Documentation

- [Game Rules (canonical)](docs/game-rules.md) — the rules as actually implemented in the engine
- [The Complete Go-Stop Guide](docs/gostop-guide.html) — a friendly, illustrated walkthrough of card reading, scoring, special events, and bonus rules
- [User Manual](docs/gostop-manual.html) — a screen-by-screen walkthrough from the title screen to settlement

In-app, the **User Manual / Rules** buttons on the title screen open the same documents directly in your browser (`bin\help\`).

## Build

- Delphi 13 (RAD Studio 37.0), Win64 target
- `powershell -ExecutionPolicy Bypass -File build.ps1` → `bin\Gostop.exe` (plus `bin\assets` and `bin\help` sync)
- The core rules/scoring engine (`Gostop.Cards`, `Gostop.Deck`, `Gostop.Score`, `Gostop.Play`, etc.) has no FMX dependency and can be compiled and verified standalone with `dcc64`

## Structure

```
src/
  Gostop.dpr, Main.pas/.fmx     Entry point (the form just delegates to the board control)
  engine/                       Game engine + UI
    Gostop.Cards / Deck / Deal    Card model · shuffling · dealing
    Gostop.Score / Play           Scoring · turn engine (full rules)
    Gostop.AI                     Skill-driven Monte Carlo AI
    Gostop.FourPlayer / FourGame  4-player gwang-sale mode
    Gostop.Characters             Character personas · dialogue
    Gostop.Board.pas              Main UI (rendering · input · animation)
    Gostop.SaveGame / Settings    Save data · settings (gostop.ini)
    Gostop.Audio                  Sound playback
assets/                        Hwatu card art, avatars, audio
docs/                          Canonical rules, guide, user manual
help/                          Help docs the app opens (synced to bin\help on build)
```

## License

- Code: **[PolyForm Noncommercial License 1.0.0](LICENSE)** — noncommercial use only
- The 48 hwatu card images: Wikimedia Commons, **CC BY-SA 4.0** (`assets/hwatu/attribution.tsv`)
- Sound effects: **Kenney.nl**, CC0
- Bonus cards and card backs: original work (free to use)
- Avatar art: generated with **Google Gemini**

## Contact

Bug reports or questions: **civilian7@gmail.com**

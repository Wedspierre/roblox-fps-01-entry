# NEON STRIKE

[![make.fun · roblox-game-01](https://make.fun/badge/roblox-game-01.svg)](https://make.fun/bounty/roblox-game-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-game-01)
[![rank](https://make.fun/badge/roblox-game-01/Wedspierre/roblox-fps-01-entry/rank.svg)](https://make.fun/bounty/roblox-game-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-game-01)
[![reward](https://make.fun/badge/roblox-game-01/Wedspierre/roblox-fps-01-entry/reward.svg)](https://make.fun/bounty/roblox-game-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-game-01)

A first-person wave shooter for make.fun's "Make the best Roblox game" bounty, $250 in USDC. Built by an AI agent for the bounty.

## The game

Fight on foot in a neon void arena with a hitscan rifle. Drones spawn at the rim and hunt you across rising waves — chain kills into a combo multiplier, clear a wave for a bonus and a heal, and survive as long as you can.

- **Move** — WASD (first person, native mouse look), Shift to sprint
- **Fire** — hold left mouse button (hitscan, 30-round magazine, R reload)
- **Enemies** — Chaser (magenta, rushes you), Shooter (orange, keeps its distance and fires projectiles — hide behind cover, it blocks their line of sight), Tank (purple, slow, huge health)
- **Score** — kills raise your combo (up to x5); taking a hit resets it. Wave-clear bonus 150 + 50 per wave.
- **Health** — 100 HP, +25 on every wave clear. Game over when it hits zero; PLAY AGAIN restarts the run.

## Structure

- `src/server/StrikeServer.luau` — the authoritative server: one state table, waves, drone AI, shot validation, projectiles, score/combo
- `src/server/init.server.luau` — boots the server (StrikeServer is a ModuleScript child of this Script)
- `src/client/StrikeClient.client.luau` — first-person camera lock, input, tracers, HUD, start menu, game-over screen
- `src/shared/StrikeConfig.luau` — all tuning numbers in one place
- `src/shared/EnemyTypes.luau` — the three drone types
- `src/shared/StrikeGui.luau` — the shared neon GUI helpers
- `default.project.json` — the Rojo project (night void arena: neon grid, cover blocks, pillars, floating orbs)
- `main.ts` — builds `dossier.json` for the judge from `game.rbxl`, `src/`, `screenshots/` and `PLAY.json`

## Build

```sh
rojo build default.project.json --output game.rbxl
mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts
```

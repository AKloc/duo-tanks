# Duo Tanks

A two-player artillery game for the iPhone Duo, inspired by the classic DOS game Scorched Earth.

Take turns lobbing shells at each other across hills you can blow apart. Account for wind, dig the ground out from under your opponent, and watch them fall.

## The hinge is the cannon

Hold the Duo half-open like a tiny laptop: the battlefield is on the top half and the controls are on the bottom. Opening or closing the phone raises or lowers your barrel, with a light haptic tick every 5°. It reads the hinge through UIKit's `UIHingeInteraction` (iOS 27.1).

Flat or folded, aim by dragging on the battlefield or using the angle stepper.

## Firing

Press and hold the big arcade **FIRE** button to charge your shot: the ring around it fills from 0 to 100% over two seconds. Let go to fire. Your last shot's power stays on screen as a reference.

## Sound and feel

All sound is synthesized in code and panned across the stereo speakers to where things happen: the launch booms from the shooter's side, each shell whistles across the screen (pitching down as it falls), and the explosion lands where it hits. Blasts shake the screen and thump the haptics, and nukes flash the sky.

## Matches and the shop

A match is several rounds (5 by default). Health resets each round, but unused ammo and gear carry over. Between rounds each player visits the shop.

You earn **$40 per point of damage** to opponents, **$2,500 per kill** (including knocking the ground out from under someone), **$4,000 for winning the round** and **$1,000** for playing it.

## Weapons

| Weapon | Price | Direct hit | What it does |
|---|---|---|---|
| Baby Missile | free, unlimited | 60 | Small blast |
| Missile | $3,000 for 3 | 80 | Medium blast |
| Baby Nuke | $6,000 | 100 | Big blast |
| Nuke | $12,000 | 150 | Huge blast and a blinding flash |
| MIRV | $8,000 | 50 each | Splits into 5 warheads at the top of its arc |
| Death's Head | $16,000 | 70 each | Splits into 9 heavy warheads |
| Funky Bomb | $7,000 | 60 + 40 per bomblet | Scatters bomblets on impact |
| Roller | $4,000 for 2 | 70 | Rolls downhill, then explodes |
| Sandhog | $4,000 for 2 | 55 | Tunnels under the target, then explodes |
| Napalm | $7,000 | burns | Burning fuel that flows downhill |
| Leapfrog | $5,000 for 2 | 45 × 3 | Bounces twice, exploding each time |
| Dirt Clod | $2,000 for 3 | 0 | A ball of dirt; bury your opponent |
| Riot Charge | $2,000 for 2 | 0 | Blasts away dirt in front of you |
| Tracer | $500 for 5 | 0 | Leaves its path on screen for aiming |

## Gear

| Item | Price | What it does |
|---|---|---|
| Parachute | $3,000 for 2 | Opens automatically when you fall; no fall damage |
| Shield | $8,000 | A bubble that absorbs 60 damage (raise it on your turn) |
| Repair Kit | $4,000 | Restores 35 health on your turn |

Tanks that lose the ground under them fall and take damage, and destroyed tanks cook off in a small blast.

## Run it

Requires Xcode 27.1+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open DuoTanks.xcodeproj
```

Pick the **iPhone Duo** simulator or your device and press Run. To install on a real phone, set your team under Signing & Capabilities.

## License

MIT

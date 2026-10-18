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
| Plasma Blast | $9,000 | 90 | A huge energy blast; no fire, no smoke |
| Laser | $10,000 | 90 | A straight beam that ignores gravity and wind and burns through hills |
| Roller | $4,000 for 2 | 70 | Rolls downhill, then explodes |
| Heavy Roller | $7,000 | 100 | A bigger, deadlier Roller |
| Sandhog | $4,000 for 2 | 55 | Tunnels under the target, then explodes |
| Napalm | $7,000 | burns | Burning fuel that flows downhill |
| Hot Napalm | $11,000 | burns | More fuel that burns hotter and longer |
| Leapfrog | $5,000 for 2 | 45 × 3 | Bounces twice, exploding each time |
| Dirt Clod | $2,000 for 3 | 0 | A ball of dirt; bury your opponent |
| Ton of Dirt | $4,000 | 0 | A huge mound; bury them completely |
| Liquid Dirt | $4,000 for 2 | 0 | Flows downhill and fills the valley level |
| Riot Charge | $2,000 for 2 | 0 | Blasts away dirt in front of you |
| Tracer | $500 for 5 | 0 | Leaves its path on screen for aiming |

## Gear

| Item | Price | What it does |
|---|---|---|
| Parachute | $3,000 for 2 | Opens automatically when you fall; no fall damage |
| Shield | $8,000 | A bubble that absorbs 60 damage (raise it on your turn) |
| Repair Kit | $4,000 | Restores 35 health on your turn |
| Fuel | $1,500 for 60 | Drive your tank on your turn; everyone starts with 30 |

Tanks that lose the ground under them fall and take damage. Blasts rock nearby tanks and bounce them on their tracks, tanks sit tilted on slopes, and destroyed tanks cook off and throw their turrets.

## Driving

Hold the ◀ ▶ arrows on your turn to drive. Driving burns fuel and doesn't end your turn. Gentle slopes are fine, steep ones stop you, and driving off a cliff hurts unless you have a parachute.

## Kill cam

The shot that ends a round plays again in slow motion: the camera rides along with the shell, drops into bullet time as it reaches the victim, and holds on the wreck. Because the simulation is deterministic, the replay is the exact same shot. Tap Skip to move on.

## Playing the computer

Choose **Vs computer** on the title screen and pick Easy, Normal or Hard. The computer predicts its shots with the same physics as the game, misjudges the wind and adds aiming error according to difficulty, and tightens its aim over repeated shots the way a person brackets a target. It raises shields, patches itself up, picks weapons to suit the terrain, avoids shots that would hit itself, and does its own shopping between rounds.

## Worlds and weather

Pick a world on the title screen, or let each round roll a random one:

- **Moonlit Hills:** grass, pines and a full moon.
- **Desert Dusk:** mesas, saguaros and a setting sun.
- **Snowy Night:** falling snow, snowy peaks and frosted pines.
- **The Moon:** 40% gravity and no wind; shots float and carry farther. Earth hangs in the sky.

Weather can be clear, rain or storm (lightning and thunder), or left on auto. You can also set wind strength, terrain roughness, rounds, starting cash, volume and haptics.

## Run it

Requires Xcode 27.1+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open DuoTanks.xcodeproj
```

Pick the **iPhone Duo** simulator or your device and press Run. To install on a real phone, set your team under Signing & Capabilities.

## App icon

The icon is drawn in code by `Tools/make_icon.swift`. To regenerate it:

```sh
swift Tools/make_icon.swift Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Tests

The physics, terrain, economy and the computer's aiming are covered by Swift Testing suites in `Tests/`. Gameplay tests fire real shots through the game's fixed-step simulation on known terrain.

```sh
xcodegen generate
xcodebuild test -project DuoTanks.xcodeproj -scheme DuoTanks -destination 'platform=iOS Simulator,name=iPhone Duo'
```

## License

MIT

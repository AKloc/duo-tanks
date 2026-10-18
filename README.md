# Duo Tanks

A two-player artillery game for the iPhone Duo, inspired by the classic DOS game Scorched Earth.

Take turns lobbing shells at each other across hills you can blow apart. Account for wind, dig the ground out from under your opponent, and watch them fall.

## The hinge is the cannon

Hold the Duo half-open like a tiny laptop: the battlefield is on the top half and the controls are on the bottom. Opening or closing the phone raises or lowers your barrel. It reads the hinge through UIKit's `UIHingeInteraction` (iOS 27.1).

Flat or folded, aim by dragging on the battlefield or using the angle stepper.

## Firing

Press and hold the big arcade **FIRE** button to charge your shot: the ring around it fills from 0 to 100% over two seconds. Let go to fire. Your last shot's power stays on screen as a reference.

## Sound and feel

All sound is synthesized in code and panned across the stereo speakers to where things happen: the launch booms from the shooter's side, each shell whistles across the screen (pitching down as it falls), and the explosion lands where it hits. Blasts shake the screen and thump the haptics, and nukes flash the sky.

## Weapons

| Weapon | Ammo | Direct-hit damage | What it does |
|---|---|---|---|
| Baby Missile | ∞ | 60 | Small blast |
| Missile | 5 | 80 | Medium blast |
| Baby Nuke | 2 | 100 | Big blast |
| Nuke | 1 | 150 | Huge blast |
| MIRV | 2 | 50 each | Splits into 5 warheads at the top of its arc |
| Death's Head | 1 | 70 each | Splits into 9 heavy warheads |
| Funky Bomb | 2 | 60 + 40 per bomblet | Scatters bomblets on impact |
| Dirt Clod | 3 | 0 | Adds a ball of dirt; bury your opponent |

Tanks that lose the ground under them fall and take damage.

## Run it

Requires Xcode 27.1+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open DuoTanks.xcodeproj
```

Pick the **iPhone Duo** simulator or your device and press Run. To install on a real phone, set your team under Signing & Capabilities.

## License

MIT

# Duo Tanks

A two-player artillery game for the iPhone Duo, inspired by the classic DOS game Scorched Earth.

Take turns lobbing shells at each other across hills you can blow apart. Account for wind, dig the ground out from under your opponent, and watch them fall.

## The hinge is the cannon

Hold the Duo half-open like a tiny laptop: the battlefield is on the top half and the controls are on the bottom. Opening or closing the phone raises or lowers your barrel. It reads the hinge through UIKit's `UIHingeInteraction` (iOS 27.1).

Flat or folded, aim by dragging on the battlefield or using the angle stepper.

## Weapons

| Weapon | Ammo | What it does |
|---|---|---|
| Baby Missile | ∞ | Small blast |
| Missile | 5 | Medium blast |
| Baby Nuke | 2 | Big blast |
| Nuke | 1 | Huge blast |
| MIRV | 2 | Splits into 5 warheads at the top of its arc |
| Death's Head | 1 | Splits into 9 heavy warheads |
| Funky Bomb | 2 | Scatters bomblets on impact |
| Dirt Clod | 3 | Adds a ball of dirt; bury your opponent |

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

# Duo Tanks

A Scorched Earth–style artillery game for the iPhone Duo. Lob shells across destructible hills, account for the wind, and blow your opponent off the map.

## Features

- Two players on one phone, or against the computer (Easy, Normal, Hard)
- Multi-round matches with a shop: 20 weapons including MIRVs, Nukes, Napalm, Rollers and Lasers, plus shields, parachutes, repair kits and fuel
- Destructible terrain, wind, falling damage, burial and driving
- Four worlds (including the low-gravity Moon), weather, a kill cam and dynamic music

## Built for the Duo

- **Half-open:** the hinge aims your barrel, and shots get a chase camera on top with a mini-map below.
- **Flat on a table:** each player gets their own half of the screen, facing them.
- **Folded:** pass the phone between turns; your turn and shop stay hidden until the next player unfolds it.

## Run it

Requires Xcode 27.1+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open DuoTanks.xcodeproj
```

Run tests with `xcodebuild test -project DuoTanks.xcodeproj -scheme DuoTanks -destination 'platform=iOS Simulator,name=iPhone Duo'`.

## License

MIT

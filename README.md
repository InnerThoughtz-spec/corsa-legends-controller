# corsa-legends-controller

INS-ui speed, grip, suspension, high-speed stability, and Swerve automation controller for Corsa Legends on Matcha.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/corsa-legends-controller/main/corsa_ins_ui.lua"))()
```

Version 32 pins the current INS-ui revision and removes the obsolete cleanup-source patch that broke when the library renamed its implementation. It retains score-safe traffic passes, rebuilt-chassis recovery after Retry, stationary-farm recovery, and non-collidable generated `SideTrash` piles.

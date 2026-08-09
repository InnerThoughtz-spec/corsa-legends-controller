# corsa-legends-controller

INS-ui speed, grip, suspension, high-speed stability, and Swerve automation controller for Corsa Legends on Matcha.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/corsa-legends-controller/main/corsa_ins_ui.lua"))()
```

Version 31 restores score-producing traffic passes by despawning only an imminent car in the player's current lane. It also refreshes rebuilt chassis references after Retry and automatically recovers a stationary farm without disturbing an active score. Adjacent traffic stays alive for near-miss scoring, while generated `SideTrash` meshes and proxies remain non-collidable.

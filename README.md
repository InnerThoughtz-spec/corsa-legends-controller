# corsa-legends-controller

INS-ui speed, grip, suspension, high-speed stability, and Swerve automation controller for Corsa Legends on Matcha.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/corsa-legends-controller/main/corsa_ins_ui.lua"))()
```

Version 30 restores score-producing traffic passes by despawning only an imminent car in the player's current lane. Adjacent traffic stays alive for near-miss scoring, while generated `SideTrash` meshes and proxies remain non-collidable. It also includes stable lane control, verified Retry recovery, and click-only Anti-AFK.

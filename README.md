# Vehicle controllers

NonUI vehicle controllers for Matcha. Corsa Legends and Ghost Driver are separate scripts, so loading one does not mix game-specific remotes or vehicle assumptions into the other.

## Corsa Legends

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/corsa-legends-controller/main/corsa_ins_ui.lua"))()
```

Version 35 replaces INS-ui with the pinned NonUI library. Loading or respawning never arms Swerve propulsion, Retry only resumes a run that was explicitly active, and lane stabilization preserves the car's existing forward speed. Enable **Autofarm** or press **Initialize from current position** when you actually want the 370 MPH controller to start.

## Ghost Driver

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/corsa-legends-controller/main/ghost_driver_nonui.lua"))()
```

Ghost Driver includes hold-only nitro, velocity stability, a traffic-guided near-miss autofarm, targeted crash-detector protection, anti-AFK, and a live A-Chassis tuner. Autofarm is always off when the script loads.

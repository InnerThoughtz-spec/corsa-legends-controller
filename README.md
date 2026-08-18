# corsa-legends-controller

NonUI speed, grip, suspension, high-speed stability, and Swerve automation controller for Corsa Legends on Matcha.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/corsa-legends-controller/main/corsa_ins_ui.lua"))()
```

Version 35 replaces INS-ui with the pinned NonUI library. Loading or respawning never arms Swerve propulsion, Retry only resumes a run that was explicitly active, and lane stabilization preserves the car's existing forward speed. Enable **Autofarm** or press **Initialize from current position** when you actually want the 370 MPH controller to start.

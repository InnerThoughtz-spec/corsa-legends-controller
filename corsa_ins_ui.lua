-- Corsa Legends Controller using INS-ui
-- Menu: P | Nitro: hold Left Shift

local oldToken = (_G.__CorsaBoostToken or 0) + 1
_G.__CorsaBoostToken = oldToken
_G.__CorsaBoost = true
_G.__CorsaHack = false

if _G.__CorsaUI then
    pcall(function() _G.__CorsaUI:Destroy() end)
end

local Lib = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.min.lua"
))() or INSui

local State = {
    enabled = true,
    nitroEnabled = true,
    nitroHeld = false,
    accel = 180,
    maxSpeed = 420,
    lowGripRate = 85,
    highGripRate = 30,
    highSpeed = 180,
    maxRise = 16,
    weight = 2300,
    weightDist = 48,
    cgHeight = -0.15,
    gripFactor = 2.75,
    maxFriction = 5.5,
    suspensionLength = 1.90,
    preload = 0.35,
    stiffness = 58,
    damping = 8600,
}

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local token = oldToken
local currentCar
local currentSeat
local currentAddress

local win = Lib:CreateWindow({
    title = "Corsa Controller",
    subtitle = "stable chassis v7",
    size = Vector2.new(720, 540),
    menuKey = "p",
    configName = "corsa-controller",
    configFolder = "corsa-controller",
    accentA = Color3.fromRGB(84, 168, 255),
    accentB = Color3.fromRGB(105, 255, 202),
    backgroundEffect = "Rain",
    backgroundEffectColor = Color3.fromRGB(84, 168, 255),
    opacity = 0.96,
    rounding = 1.2,
    rowLines = true,
    smartFps = true,
    gameInput = true,
    autoSave = true,
    startOpen = true,
    keybindOverlay = true,
})

_G.__CorsaUI = win

local function flatUnit(v)
    local flat = Vector3.new(v.X, 0, v.Z)
    return flat.Magnitude > 0.001 and flat.Unit or nil
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function getCar()
    local storage = game.Workspace:FindFirstChild("AVehicleStorage")
    return storage and storage:FindFirstChild(player.Name)
end

local function buildTune()
    return {
        peakTq = "12000",
        redlineTq = "9000",
        idleTq = "1200",
        peakTqRPM = "8000",
        redline = "30000",
        shiftRPM = "28000",
        bhpLimit = "999999999",
        TBoost = "80",
        SPeakboost = "80",
        FinalDrive = "5",

        weight = tostring(State.weight),
        weightdist = tostring(State.weightDist),
        carHeight = tostring(State.cgHeight),
        gripFactor = tostring(State.gripFactor),
        maxFriction = tostring(State.maxFriction),
        frontDF = "0",
        rearDF = "0",

        FLength = tostring(State.suspensionLength),
        RLength = tostring(State.suspensionLength + 0.02),
        FPreCompress = tostring(State.preload),
        RPreCompress = tostring(State.preload),
        FCompressLim = "0.12",
        RCompressLim = "0.12",
        FExtensionLim = "0.30",
        RExtensionLim = "0.30",
        FStiff = tostring(State.stiffness),
        RStiff = tostring(State.stiffness - 2),
        FDamp = tostring(State.damping),
        RDamp = tostring(State.damping + 200),
        FSwayBar = "14",
        RSwayBar = "12",

        SteerDecay = "75",
        MinSteer = "7",
        SteerD = "650",
        SteerP = "90000",
        SteerMaxTorque = "75000",
        fCamber = "-1.2",
        rCamber = "-0.8",
        fToe = "0",
        rToe = "0",
    }
end

local function applyTune(car, notifyUser)
    local stats = car and car:FindFirstChild("Stats")
    if not stats then
        if notifyUser then
            Lib:Notify("Corsa", "No vehicle Stats folder found", 3, "error")
        end
        return false
    end

    local changed = 0
    for name, value in pairs(buildTune()) do
        local stat = stats:FindFirstChild(name)
        if stat and pcall(function() stat.Value = value end) then
            changed = changed + 1
        end
    end

    local addGrip = stats:FindFirstChild("addGripFactor")
    if addGrip then
        pcall(function() addGrip.Value = true end)
    end

    if notifyUser then
        Lib:Notify(
            "Chassis tuned",
            tostring(changed) .. " values applied; respawn for geometry changes",
            4,
            "success"
        )
    end

    return true
end

local function findSeat(car)
    local seat = car:FindFirstChild("DriveSeat")
    if seat then return seat end

    for _, item in ipairs(car:GetDescendants()) do
        if item.ClassName == "VehicleSeat" or item.ClassName == "Seat" then
            return item
        end
    end
end

local function captureCar(car)
    currentCar = car
    currentAddress = car and car.Address
    currentSeat = nil

    if car then
        applyTune(car, false)
        currentSeat = findSeat(car)
        Lib:Notify("Vehicle ready", car.Name, 2, "success")
    end
end

local drive = win:Tab("Drive", "gauge")
local main = drive:Section("Controller", "Left", "master controls and nitro")

main:Toggle("Enabled", true, function(on)
    State.enabled = on
    Lib:Notify("Corsa", on and "controller enabled" or "controller paused", 2,
        on and "success" or "warning")
end)

local nitro = main:Toggle("Nitro enabled", true, function(on)
    State.nitroEnabled = on
end)

nitro:AddKeybind("leftshift", "Hold", function(on)
    State.nitroHeld = on
end)

main:Slider("Nitro acceleration", 180, 10, 0, 400, "", function(v)
    State.accel = v
end)

main:Slider("Maximum speed", 420, 10, 100, 650, "", function(v)
    State.maxSpeed = v
end)

local live = drive:Section("Live vehicle", "Right")
live:Label(function()
    return "Car: " .. (currentCar and currentCar.Name or "waiting")
end)
live:Label(function()
    local velocity = currentSeat and currentSeat.AssemblyLinearVelocity
    return "Speed: " .. tostring(velocity and math.floor(velocity.Magnitude) or 0)
end)
live:Label(function()
    return "Nitro: " .. (State.nitroHeld and "active" or "ready")
end)
live:Info("Press P to toggle the menu. Hold Left Shift for nitro. UI input passes through when the pointer is outside the window.")

local handling = win:Tab("Handling", "sliders")
local grip = handling:Section("Stability assist", "Left")

grip:Slider("Low-speed grip", 85, 5, 10, 150, "", function(v)
    State.lowGripRate = v
end)
grip:Slider("High-speed grip", 30, 5, 5, 80, "", function(v)
    State.highGripRate = v
end)
grip:Slider("High-speed threshold", 180, 10, 80, 350, "", function(v)
    State.highSpeed = v
end)
grip:Slider("Maximum rise speed", 16, 1, 4, 40, "", function(v)
    State.maxRise = v
end)

local tires = handling:Section("Tires", "Right")
tires:Slider("Grip factor", 2.75, 0.05, 0.5, 6, "x", function(v)
    State.gripFactor = v
end)
tires:Slider("Maximum friction", 5.5, 0.1, 1, 10, "x", function(v)
    State.maxFriction = v
end)
tires:Button("Apply tire settings", function()
    applyTune(getCar(), true)
end)
tires:Info("Extreme friction can cause snapping or shaking. Raise it gradually.")

local chassis = win:Tab("Chassis", "wrench")
local mass = chassis:Section("Mass and balance", "Left")

mass:Slider("Weight", 2300, 50, 1200, 3500, "", function(v)
    State.weight = v
end)
mass:Slider("Front weight", 48, 1, 35, 65, "%", function(v)
    State.weightDist = v
end)
mass:Slider("Center of gravity", -0.15, 0.05, -0.5, 0.5, "", function(v)
    State.cgHeight = v
end)

local suspension = chassis:Section("Suspension", "Right")
suspension:Slider("Ride length", 1.90, 0.05, 1.2, 2.5, "", function(v)
    State.suspensionLength = v
end)
suspension:Slider("Preload", 0.35, 0.01, 0.05, 0.6, "", function(v)
    State.preload = v
end)
suspension:Slider("Spring stiffness", 58, 1, 20, 100, "", function(v)
    State.stiffness = v
end)
suspension:Slider("Damping", 8600, 100, 3000, 14000, "", function(v)
    State.damping = v
end)
suspension:Button("Apply chassis settings", function()
    applyTune(getCar(), true)
end)
suspension:Info("Respawn the vehicle after changing weight, ride length, preload, stiffness, or center of gravity.")

local system = win:Tab("System", "settings")
local actions = system:Section("Actions", "Left")
actions:Button("Apply complete tune", function()
    applyTune(getCar(), true)
end)
actions:Button("Center menu", function()
    win:Center()
end)
actions:Button("Stop controller", function()
    State.enabled = false
    _G.__CorsaBoost = false
    _G.__CorsaBoostToken = _G.__CorsaBoostToken + 1
    Lib:Notify("Corsa", "controller stopped", 2, "warning")
end):SetRisk()

local about = system:Section("Information", "Right")
about:Info("The spawn watcher applies the tune before A-Chassis finishes its 0.1 second initialization. Keep this script running before respawning the car.")
about:Label("Menu key: P")
about:Label("Nitro key: Left Shift")

win:AddSettingsTab("cog")

task.spawn(function()
    while _G.__CorsaBoostToken == token do
        local car = getCar()
        local address = car and car.Address

        if address ~= currentAddress then
            captureCar(car)
        end

        task.wait(car and 0.20 or 0.01)
    end
end)

local existing = getCar()
if existing then captureCar(existing) end

task.spawn(function()
    local dt = 1 / 15

    while _G.__CorsaBoostToken == token do
        local seat = currentSeat

        if State.enabled and seat then
            local velocity = seat.AssemblyLinearVelocity
            local forward = flatUnit(seat.CFrame.LookVector)
            local right = flatUnit(seat.CFrame.RightVector)

            if forward and right then
                local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
                local speed = horizontal.Magnitude
                local forwardSpeed = horizontal:Dot(forward)
                local lateralSpeed = horizontal:Dot(right)
                local output = velocity
                local changed = false

                if math.abs(lateralSpeed) > 0.5 then
                    local rate = speed >= State.highSpeed
                        and State.highGripRate or State.lowGripRate
                    local correction = clamp(
                        lateralSpeed * 0.20,
                        -rate * dt,
                        rate * dt
                    )
                    output = output - right * correction
                    changed = true
                end

                if speed >= State.highSpeed and output.Y > State.maxRise then
                    output = Vector3.new(output.X, State.maxRise, output.Z)
                    changed = true
                end

                local boosting = State.nitroEnabled and State.nitroHeld
                if boosting and forwardSpeed < State.maxSpeed then
                    local push = math.min(
                        State.accel * dt,
                        State.maxSpeed - forwardSpeed
                    )
                    output = output + forward * push
                    changed = true
                end

                if changed then
                    seat.AssemblyLinearVelocity = output
                end
            end
        end

        task.wait(dt)
    end
end)

Lib:Notify("Corsa Controller", "Loaded successfully - press P", 4, "success")

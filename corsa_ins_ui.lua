-- Corsa Legends Controller using INS-ui
-- Menu: P | Nitro: hold Left Shift
-- Includes Swerve traffic farming, anti-AFK, and forced-induction tuning

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

    turbos = 2,
    turboBoost = 24,
    turboIdle = 12,
    turboPeakRPM = 2800,
    turboCurve = 0.63,
    turboEfficiency = 5,
    turboSpoolUp = 0.96,
    turboSpoolDown = 0.96,

    superchargers = 1,
    superPeakBoost = 40.25,
    superPeakRPM = 3000,
    superIdleBoost = 10,
    superIdleCurve = 0.50,
    superRedlineBoost = 6,
    superRedlineCurve = 0.50,
    superEfficiency = 11.27,
    superResponse = 0.60,

    swerveEnabled = false,
    swerveAutoEnter = true,
    swerveSpeed = 220,
    swerveAcceleration = 90,
    swerveAvoidDistance = 300,
    swerveLaneSpeed = 18,
    swerveLaneAcceleration = 28,
    swerveWeaveDelay = 6,
    swerveKeepStraight = true,
    trafficNoCollision = true,

    antiAfk = true,
    antiAfkInterval = 55,
}

_G.__CorsaState = State

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local token = oldToken
local currentCar
local currentSeat
local currentRoot
local currentAddress
local swerveCarAddress
local swerveLane = 2
local swerveNextWeave = 0
local swerveLanes = { 4805.187, 4821.565, 4837.794 }
local swerveStartZ = 19215
local swerveForward = Vector3.new(0, 0, 1)
local swerveFaulted = false
local ghostedTrafficParts = {}
local collisionParts = {}
local collisionPartAddresses = {}
local collisionGcCache

local win = Lib:CreateWindow({
    title = "Corsa Controller",
    subtitle = "stable chassis + Swerve v9",
    size = Vector2.new(720, 540),
    menuKey = "p",
    configName = "corsa-controller-v9",
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
        Turbochargers = tostring(State.turbos),
        TBoost = tostring(State.turboBoost),
        TIdle = tostring(State.turboIdle),
        TPeakRPM = tostring(State.turboPeakRPM),
        TCurve = tostring(State.turboCurve),
        TEff = tostring(State.turboEfficiency),
        TSpoolInc = tostring(State.turboSpoolUp),
        TSpoolDec = tostring(State.turboSpoolDown),

        Superchargers = tostring(State.superchargers),
        SPeakboost = tostring(State.superPeakBoost),
        SPeakRPM = tostring(State.superPeakRPM),
        SIdleBoost = tostring(State.superIdleBoost),
        SIdleCurve = tostring(State.superIdleCurve),
        SRedlineBoost = tostring(State.superRedlineBoost),
        SRedlineCurve = tostring(State.superRedlineCurve),
        SEfficiency = tostring(State.superEfficiency),
        SResponseSResponse = tostring(State.superResponse),
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

local function findVehicleRoot(car)
    local body = car and car:FindFirstChild("Body")
    local weight = body and body:FindFirstChild("#Weight")
    return weight or (car and findSeat(car))
end

local function playerIsInCar(seat)
    local character = player.Character
    local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
    return characterRoot and seat
        and (characterRoot.Position - seat.Position).Magnitude < 10
end

local function nearestSwerveLane(x)
    local best = 1
    local bestDistance = math.huge

    for i = 1, #swerveLanes do
        local distance = math.abs(x - swerveLanes[i])
        if distance < bestDistance then
            best = i
            bestDistance = distance
        end
    end

    return best
end

local function resolveSwerveCourse()
    local traffic = game.Workspace:FindFirstChild("AITraffic")
    local generated = traffic and traffic:FindFirstChild("GenRoad")
    if not generated then return false end

    for _, road in ipairs(generated:GetChildren()) do
        if road.Name == "Road" then
            local found = {}
            local firstZ

            for _, laneName in ipairs({ "Lane1", "Lane2", "Lane3" }) do
                local lane = road:FindFirstChild(laneName)
                if lane then
                    found[#found + 1] = lane.Position.X
                    firstZ = firstZ or lane.Position.Z
                end
            end

            if #found == 3 then
                table.sort(found)
                swerveLanes = found
                swerveStartZ = firstZ + 42
                return true
            end
        end
    end

    return false
end


local function enterSwerveCourse(notifyUser)
    local car = getCar()
    local seat = car and findSeat(car)
    local root = car and findVehicleRoot(car)
    if not (seat and root) then
        if notifyUser then
            Lib:Notify("Swerve", "Spawn a car and sit in the driver seat first", 4, "warning")
        end
        return false
    end

    if not playerIsInCar(seat) then
        if notifyUser then
            Lib:Notify("Swerve", "Sit in the driver seat before starting", 4, "warning")
        end
        return false
    end

    resolveSwerveCourse()
    swerveLane = nearestSwerveLane(root.Position.X)
    swerveNextWeave = tick() + State.swerveWeaveDelay
    swerveFaulted = false

    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local swerveRemotes = remotes and remotes:FindFirstChild("SwerveRemotes")
    local scoreStart = swerveRemotes and swerveRemotes:FindFirstChild("ScoreStart")
    if scoreStart then
        pcall(function() scoreStart:FireServer() end)
    end

    swerveCarAddress = car.Address
    if notifyUser then
        Lib:Notify("Swerve", "Autofarm initialized at the car's current position", 3, "success")
    end
    return true
end

local function stabilizeSwerveCar(root)
    if not root then return end
    swerveLane = nearestSwerveLane(root.Position.X)
    pcall(function()
        local velocity = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(
            0,
            clamp(velocity.Y, -4, State.maxRise),
            math.max(velocity.Z, 45)
        )
    end)
end

_G.__CorsaStartSwerve = function()
    State.enabled = true
    State.swerveEnabled = true
    return enterSwerveCourse(true)
end

_G.__CorsaStopSwerve = function()
    State.swerveEnabled = false
    Lib:Notify("Swerve", "autofarm stopped", 2, "warning")
end

local function updateSwerveLane()
    local root = currentRoot
    if not (State.swerveEnabled and root) then return end

    if State.swerveKeepStraight then
        return
    end

    local traffic = game.Workspace:FindFirstChild("AITraffic")
    local cars = traffic and traffic:FindFirstChild("Car")
    if not cars then return end

    local position = root.Position
    local clearance = { math.huge, math.huge, math.huge }

    for _, car in ipairs(cars:GetChildren()) do
        local part = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart", true)
        if part then
            local ahead = part.Position.Z - position.Z
            if ahead > -12 then
                local lane = nearestSwerveLane(part.Position.X)
                clearance[lane] = math.min(clearance[lane], math.max(0, ahead))
            end
        end
    end

    local now = tick()
    local blocked = clearance[swerveLane] < State.swerveAvoidDistance
    if now < swerveNextWeave then return end

    local bestLane = swerveLane
    local bestScore = -math.huge

    for lane = 1, 3 do
        local laneClearance = math.min(clearance[lane], State.swerveAvoidDistance * 3)
        local changePenalty = math.abs(lane - swerveLane) * 12
        local repeatPenalty = lane == swerveLane and (blocked and 80 or 25) or 0
        local score = laneClearance - changePenalty - repeatPenalty

        if score > bestScore then
            bestLane = lane
            bestScore = score
        end
    end

    if not blocked then
        local weaveLane = swerveLane % 3 + 1
        if clearance[weaveLane] > State.swerveAvoidDistance * 0.8 then
            bestLane = weaveLane
        end
    end

    swerveLane = bestLane
    swerveNextWeave = now + (blocked and 0.9 or State.swerveWeaveDelay)
end

local function disableTrafficCollisions()
    if not State.trafficNoCollision then return 0 end

    local traffic = game.Workspace:FindFirstChild("AITraffic")
    local cars = traffic and traffic:FindFirstChild("Car")
    if not cars then return 0 end

    local changed = 0
    for _, car in ipairs(cars:GetChildren()) do
        for _, part in ipairs(car:GetDescendants()) do
            if part.ClassName == "Part"
                or part.ClassName == "MeshPart"
                or part.ClassName == "UnionOperation" then
                local address = part.Address
                if part.Name == "Collide" and not collisionPartAddresses[address] then
                    collisionPartAddresses[address] = true
                    collisionParts[#collisionParts + 1] = part
                end
                if not ghostedTrafficParts[address] or part.CanCollide then
                    pcall(function() part.CanCollide = false end)
                    ghostedTrafficParts[address] = true
                    changed = changed + 1
                end
            end
        end
    end

    return changed
end

local function captureCar(car)
    currentCar = car
    currentAddress = car and car.Address
    currentSeat = nil
    currentRoot = nil

    if car then
        applyTune(car, false)
        currentSeat = findSeat(car)
        currentRoot = findVehicleRoot(car)
        Lib:Notify("Vehicle ready", car.Name, 2, "success")

        if State.swerveEnabled and State.swerveAutoEnter then
            task.delay(0.25, function()
                if _G.__CorsaBoostToken == token then
                    enterSwerveCourse(false)
                end
            end)
        end
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
    local velocity = currentRoot and currentRoot.AssemblyLinearVelocity
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

local induction = win:Tab("Boost", "gauge")
local turbo = induction:Section("Turbochargers", "Left", "count, boost curve, and spool")

turbo:Slider("Turbo count", 2, 1, 0, 8, "", function(v)
    State.turbos = math.floor(v + 0.5)
end)
turbo:Slider("Turbo boost", 24, 1, 0, 150, "", function(v)
    State.turboBoost = v
end)
turbo:Slider("Turbo idle boost", 12, 1, 0, 60, "", function(v)
    State.turboIdle = v
end)
turbo:Slider("Turbo peak RPM", 2800, 100, 1000, 15000, "", function(v)
    State.turboPeakRPM = v
end)
turbo:Slider("Boost curve", 0.63, 0.01, 0.10, 1.50, "", function(v)
    State.turboCurve = v
end)
turbo:Slider("Turbo efficiency", 5, 0.25, 1, 20, "", function(v)
    State.turboEfficiency = v
end)
turbo:Slider("Spool up", 0.96, 0.01, 0.05, 2, "", function(v)
    State.turboSpoolUp = v
end)
turbo:Slider("Spool down", 0.96, 0.01, 0.05, 2, "", function(v)
    State.turboSpoolDown = v
end)
turbo:Button("Apply turbo tune", function()
    applyTune(getCar(), true)
end)

local super = induction:Section("Superchargers", "Right", "count, boost curve, and response")
super:Slider("Supercharger count", 1, 1, 0, 8, "", function(v)
    State.superchargers = math.floor(v + 0.5)
end)
super:Slider("Super peak boost", 40.25, 0.25, 0, 150, "", function(v)
    State.superPeakBoost = v
end)
super:Slider("Super peak RPM", 3000, 100, 1000, 15000, "", function(v)
    State.superPeakRPM = v
end)
super:Slider("Super idle boost", 10, 1, 0, 80, "", function(v)
    State.superIdleBoost = v
end)
super:Slider("Idle curve", 0.50, 0.01, 0.10, 1.50, "", function(v)
    State.superIdleCurve = v
end)
super:Slider("Redline boost", 6, 1, 0, 80, "", function(v)
    State.superRedlineBoost = v
end)
super:Slider("Redline curve", 0.50, 0.01, 0.10, 1.50, "", function(v)
    State.superRedlineCurve = v
end)
super:Slider("Super efficiency", 11.27, 0.25, 1, 20, "", function(v)
    State.superEfficiency = v
end)
super:Slider("Response", 0.60, 0.01, 0.05, 2, "", function(v)
    State.superResponse = v
end)
super:Button("Apply supercharger tune", function()
    applyTune(getCar(), true)
end)

local automation = win:Tab("Automation", "settings")
local swerve = automation:Section("Swerve autofarm", "Left", "lane-aware traffic farming")

swerve:Toggle("Autofarm enabled", false, function(on)
    State.swerveEnabled = on
    if on then State.enabled = true end
    if on and State.swerveAutoEnter then
        if not enterSwerveCourse(true) then
            Lib:Notify("Swerve", "autofarm armed; waiting for the driver seat", 3, "warning")
        end
    else
        Lib:Notify("Swerve", on and "autofarm armed" or "autofarm stopped", 2,
            on and "success" or "warning")
    end
end)
swerve:Toggle("Initialize on car spawn", true, function(on)
    State.swerveAutoEnter = on
end)
swerve:Slider("Farm speed", 220, 10, 100, 400, "", function(v)
    State.swerveSpeed = v
end)
swerve:Slider("Acceleration", 90, 5, 30, 180, "", function(v)
    State.swerveAcceleration = v
end)
swerve:Slider("Avoid distance", 300, 10, 120, 500, "", function(v)
    State.swerveAvoidDistance = v
end)
swerve:Slider("Lane-change speed", 18, 1, 8, 35, "", function(v)
    State.swerveLaneSpeed = v
end)
swerve:Slider("Lane smoothing", 28, 1, 10, 60, "", function(v)
    State.swerveLaneAcceleration = v
end)
swerve:Slider("Weave delay", 6, 0.5, 2, 12, "s", function(v)
    State.swerveWeaveDelay = v
end)
swerve:Toggle("Keep car straight", true, function(on)
    State.swerveKeepStraight = on
    if on and currentRoot then
        swerveLane = nearestSwerveLane(currentRoot.Position.X)
    end
end)
swerve:Button("Initialize from current position", function()
    _G.__CorsaStartSwerve()
end)
swerve:Button("Stop autofarm", function()
    _G.__CorsaStopSwerve()
end)
swerve:Button("Stabilize current lane", function()
    stabilizeSwerveCar(currentRoot)
end)
swerve:Button("Reapply traffic ghosting", function()
    local changed = disableTrafficCollisions()
    Lib:Notify("Swerve", tostring(changed) .. " AI traffic parts ghosted", 3, "success")
end)
swerve:Label(function()
    return "Target lane: " .. tostring(swerveLane)
end)
swerve:Label(function()
    if not State.swerveEnabled then return "Farm: stopped" end
    if not currentRoot then return "Farm: waiting for car" end
    if not State.enabled then return "Farm: master controller paused" end
    return "Farm: running"
end)
swerve:Label("AI traffic collision: disabled")
swerve:Label(function()
    local gui = player:FindFirstChild("PlayerGui")
    local purchase = gui and gui:FindFirstChild("PurchaseGUI")
    local hesi = purchase and purchase:FindFirstChild("HesiUI")
    local score = hesi and hesi:FindFirstChild("Score")
    return "Swerve score: " .. (score and tostring(score.Text) or "0")
end)

local idle = automation:Section("Anti-AFK", "Right", "small input pulse while idle")
idle:Toggle("Anti-AFK enabled", true, function(on)
    State.antiAfk = on
end)
idle:Slider("Pulse interval", 55, 5, 30, 110, "s", function(v)
    State.antiAfkInterval = v
end)
idle:Info("Sends a one-pixel mouse pulse at the selected interval. It does not press a driving key.")
idle:Info("Swerve uses the game's real traffic, ScoreStart, telemetry, and payout flow. Enter the Swerve area normally, then enable the farm.")

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
    State.swerveEnabled = false
    State.antiAfk = false
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

task.spawn(function()
    while _G.__CorsaBoostToken == token do
        disableTrafficCollisions()
        task.wait(0.40)
    end
end)

task.spawn(function()
    collisionGcCache = getgc("collisionsEnabledBySpeed")
end)

local collisionHeartbeat
collisionHeartbeat = game:GetService("RunService").Heartbeat:Connect(function()
    if _G.__CorsaBoostToken ~= token then
        collisionHeartbeat:Disconnect()
        return
    end

    if not State.trafficNoCollision then return end

    if collisionGcCache then
        pcall(function()
            applygc(collisionGcCache, "collisionsEnabledBySpeed", true)
        end)
    end

    for i = 1, #collisionParts do
        local part = collisionParts[i]
        if part and part.CanCollide then
            pcall(function() part.CanCollide = false end)
        end
    end
end)

task.spawn(function()
    while _G.__CorsaBoostToken == token do
        if State.swerveEnabled then
            if State.swerveAutoEnter and currentCar and currentCar.Address ~= swerveCarAddress then
                enterSwerveCourse(false)
            end
            updateSwerveLane()
        end
        task.wait(0.12)
    end
end)

task.spawn(function()
    local lastPulse = tick()

    while _G.__CorsaBoostToken == token do
        if State.antiAfk and tick() - lastPulse >= State.antiAfkInterval then
            pcall(function()
                mousemoverel(1, 0)
                task.wait(0.05)
                mousemoverel(-1, 0)
            end)
            lastPulse = tick()
        end
        task.wait(1)
    end
end)

local existing = getCar()
if existing then captureCar(existing) end

task.spawn(function()
    local dt = 1 / 15

    while _G.__CorsaBoostToken == token do
        local seat = currentSeat
        local root = currentRoot
        local orientation = seat or root

        if State.enabled and root and orientation then
            local velocity = root.AssemblyLinearVelocity
            local forward = State.swerveEnabled and swerveForward
                or flatUnit(orientation.CFrame.LookVector)
            local right = State.swerveEnabled and Vector3.new(1, 0, 0)
                or flatUnit(orientation.CFrame.RightVector)

            if forward and right then
                local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
                local speed = horizontal.Magnitude
                local forwardSpeed = horizontal:Dot(forward)
                local lateralSpeed = horizontal:Dot(right)
                local output = velocity
                local changed = false

                if State.swerveEnabled then
                    local position = root.Position
                    if position.Y < -15 then
                        State.swerveEnabled = false
                        if not swerveFaulted then
                            swerveFaulted = true
                            Lib:Notify(
                                "Swerve stopped",
                                "Vehicle fell below the road; respawn it before retrying",
                                5,
                                "error"
                            )
                        end
                    else
                        local targetX = swerveLanes[swerveLane]
                        local desiredX = clamp(
                            (targetX - position.X) * 2.5,
                            -State.swerveLaneSpeed,
                            State.swerveLaneSpeed
                        )
                        local lateralStep = State.swerveLaneAcceleration * dt
                        local newX = output.X + clamp(
                            desiredX - output.X,
                            -lateralStep,
                            lateralStep
                        )
                        local newZ = output.Z + clamp(
                            State.swerveSpeed - output.Z,
                            -State.swerveAcceleration * dt,
                            State.swerveAcceleration * dt
                        )
                        local newY = math.min(output.Y, State.maxRise)
                        output = Vector3.new(newX, newY, newZ)
                        changed = true
                    end
                elseif math.abs(lateralSpeed) > 0.5 then
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

                local boosting = not State.swerveEnabled
                    and State.nitroEnabled and State.nitroHeld
                if boosting and forwardSpeed < State.maxSpeed then
                    local push = math.min(
                        State.accel * dt,
                        State.maxSpeed - forwardSpeed
                    )
                    output = output + forward * push
                    changed = true
                end

                if changed then
                    root.AssemblyLinearVelocity = output
                end
            end
        end

        task.wait(dt)
    end
end)

Lib:Notify("Corsa Controller", "Loaded successfully - press P", 4, "success")

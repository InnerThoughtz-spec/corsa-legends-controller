-- Ghost Driver Controller using NonUI
-- Live-mapped for Ghost Driver / A-Chassis on Matcha.
-- Reload-safe: executing the file again stops the previous controller first.

if _G.__GhostDriverStop then
    pcall(_G.__GhostDriverStop)
end
if _G.__GhostDriverUI then
    pcall(function()
        _G.__GhostDriverUI:Destroy()
    end)
end

local token = (_G.__GhostDriverToken or 0) + 1
_G.__GhostDriverToken = token

local NON_UI_URL = "https://raw.githubusercontent.com/neaxusxgod-png/NonUI/3b13bca61d9e103e1259f92b7f8dd0f39713777a/NonUI.lua"
local uiSource = game:HttpGet(NON_UI_URL)
local uiLoader = assert(loadstring(uiSource), "NonUI source did not compile")
local Non = uiLoader() or NonUI

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local lp = Players.LocalPlayer

local MPH_PER_STUD = 0.35
local CONTROL_DT = 0.125
local TRAFFIC_REFRESH = 0.50
local INFO_REFRESH = 0.40
local AFK_INTERVAL = 19 * 60

local State = {
    running = true,
    controllerEnabled = true,
    nitroEnabled = true,
    nitroHeld = false,
    nitroAcceleration = 115,
    manualMaxMPH = 260,
    stabilityEnabled = true,
    lateralDamping = 0.60,
    verticalDamping = 0.45,

    farmEnabled = false,
    farmArmed = false,
    farmTargetMPH = 225,
    farmAcceleration = 125,
    farmLateralGain = 1.35,
    farmLateralLimit = 28,
    passOffset = 7.5,
    passMode = "Alternate",
    passSign = 1,
    autoReacquire = true,
    reacquireDistance = 900,
    reacquireCooldown = 8,
    lastReacquire = -100,
    stallStarted = nil,
    guideAddress = nil,
    guideDistance = nil,
    lastDirection = nil,
    farmStatus = "stopped",

    crashGuard = true,
    antiAfk = true,
    lastAfk = os.clock(),
    afkStatus = "waiting",

    car = nil,
    carAddress = nil,
    seat = nil,
    carName = "not detected",
    traffic = {},
    trafficCount = 0,
    collisionEntries = {},
    tuneBusy = false,
    tuneStatus = "ready",
    tuneProfile = "generic mapped values",
    tuneProfileAddress = nil,
}
_G.__GhostDriverState = State

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function safeAddress(instance)
    if not instance then return nil end
    local ok, address = pcall(function()
        return instance.Address
    end)
    if ok and address ~= nil then
        return tostring(address)
    end
    return tostring(instance)
end

local function flatUnit(vector)
    if not vector then return nil end
    local flat = Vector3.new(vector.X, 0, vector.Z)
    local magnitude = flat.Magnitude
    if magnitude < 0.001 then return nil end
    return flat / magnitude
end

local function notify(title, content, icon, duration)
    pcall(function()
        Non:Notify({
            Title = title,
            Content = content,
            Icon = icon or "info",
            Duration = duration or 4,
        })
    end)
end

local function findOwnCar()
    local interface = lp.PlayerGui and lp.PlayerGui:FindFirstChild("A-Chassis Interface")
    if interface then
        local carValue = interface:FindFirstChild("Car")
        if carValue then
            local ok, car = pcall(function()
                return carValue.Value
            end)
            if ok and car and car:FindFirstChild("DriveSeat") then
                return car
            end
        end
    end

    local prefix = lp.Name .. "_"
    local children = Workspace:GetChildren()
    for i = 1, #children do
        local child = children[i]
        local name = child.Name or ""
        if string.sub(name, 1, #prefix) == prefix and child:FindFirstChild("DriveSeat") then
            return child
        end
    end
    return nil
end

local COLLISION_NAMES = {
    TrafficCollisionFront = true,
    TrafficCollisionRear = true,
    TrafficCollisionLeft = true,
    TrafficCollisionRight = true,
}

local function restoreCrashDetectors()
    local entries = State.collisionEntries
    for i = 1, #entries do
        local entry = entries[i]
        pcall(function()
            entry.part.Size = entry.size
            entry.part.CanCollide = entry.canCollide
        end)
    end
    State.collisionEntries = {}
    _G.__GhostDriverCollisionEntries = State.collisionEntries
end

local function captureCrashDetectors(car)
    restoreCrashDetectors()
    if not car then return end

    local descendants = car:GetDescendants()
    for i = 1, #descendants do
        local object = descendants[i]
        if COLLISION_NAMES[object.Name] then
            local ok, size, canCollide = pcall(function()
                return object.Size, object.CanCollide
            end)
            if ok and size then
                State.collisionEntries[#State.collisionEntries + 1] = {
                    part = object,
                    address = safeAddress(object),
                    size = size,
                    canCollide = canCollide,
                }
            end
        end
    end
    _G.__GhostDriverCollisionEntries = State.collisionEntries
end

local function applyCrashGuard()
    local entries = State.collisionEntries
    for i = 1, #entries do
        local entry = entries[i]
        pcall(function()
            entry.part.CanCollide = false
            entry.part.Size = Vector3.new(0.05, 0.05, 0.05)
        end)
    end
end

local function refreshCar()
    local car = findOwnCar()
    local address = safeAddress(car)
    if address ~= State.carAddress then
        restoreCrashDetectors()
        State.car = car
        State.carAddress = address
        State.seat = car and car:FindFirstChild("DriveSeat") or nil
        State.carName = car and car.Name or "not detected"
        State.farmArmed = false
        State.farmStatus = car and "vehicle changed; waiting for route" or "waiting for vehicle"
        State.guideAddress = nil
        State.lastDirection = nil
        if car then
            captureCrashDetectors(car)
            if State.crashGuard then applyCrashGuard() end
        end
    elseif car then
        State.car = car
        State.seat = car:FindFirstChild("DriveSeat")
    else
        State.car = nil
        State.seat = nil
        State.carName = "not detected"
    end
end

local function refreshTraffic()
    local folder = Workspace:FindFirstChild("TrafficFolder")
    local cache = {}
    if folder then
        local models = folder:GetChildren()
        for i = 1, #models do
            local model = models[i]
            local core = model:FindFirstChild("CoreHitbox")
            if core then
                cache[#cache + 1] = {
                    model = model,
                    core = core,
                    address = safeAddress(core),
                }
            end
        end
    end
    State.traffic = cache
    State.trafficCount = #cache
end

local function readPosition(instance)
    local ok, position = pcall(function()
        return instance.Position
    end)
    if ok then return position end
    return nil
end

local function readDirection(instance)
    local ok, direction = pcall(function()
        return flatUnit(instance.CFrame.LookVector)
    end)
    if ok then return direction end
    return nil
end

local function nearestTraffic(position)
    local best = nil
    local bestDistance = math.huge
    for i = 1, #State.traffic do
        local item = State.traffic[i]
        local corePosition = readPosition(item.core)
        if corePosition then
            local distance = (corePosition - position).Magnitude
            if distance < bestDistance then
                best = item
                bestDistance = distance
            end
        end
    end
    return best, bestDistance
end

local function chooseGuide(seatPosition)
    local reference = State.lastDirection
    if not reference and State.seat then
        local ok, look = pcall(function()
            return State.seat.CFrame.LookVector
        end)
        if ok then reference = flatUnit(look) end
    end

    local best = nil
    local bestScore = math.huge
    local bestDistance = math.huge
    for i = 1, #State.traffic do
        local item = State.traffic[i]
        local position = readPosition(item.core)
        local direction = readDirection(item.core)
        if position and direction then
            local delta = position - seatPosition
            local distance = delta.Magnitude
            local alignment = reference and direction:Dot(reference) or 1
            local ahead = delta:Dot(direction)
            if alignment > 0.15 and ahead > -35 and distance < 750 then
                local score = distance
                if ahead < 12 then score = score + 100 end
                if ahead > 450 then score = score + 80 end
                score = score + (1 - alignment) * 180
                if score < bestScore then
                    best = item
                    bestScore = score
                    bestDistance = distance
                end
            end
        end
    end

    if not best then
        best, bestDistance = nearestTraffic(seatPosition)
    end
    return best, bestDistance
end

local function updatePassSign()
    if State.passMode == "Right only" then
        State.passSign = 1
    elseif State.passMode == "Left only" then
        State.passSign = -1
    else
        State.passSign = -State.passSign
        if State.passSign == 0 then State.passSign = 1 end
    end
end

local function acquireTrafficRoute(reason)
    local seat = State.seat
    if not seat or #State.traffic == 0 then
        State.farmArmed = false
        State.farmStatus = "waiting for car and traffic"
        return false, "waiting for car and traffic"
    end

    local now = os.clock()
    if now - State.lastReacquire < State.reacquireCooldown then
        State.farmStatus = "route recovery cooling down"
        return false, "reacquire cooling down"
    end

    local seatPosition = readPosition(seat)
    if not seatPosition then
        State.farmStatus = "seat position unavailable"
        return false, State.farmStatus
    end
    local guide = nearestTraffic(seatPosition)
    if not guide then
        State.farmStatus = "no traffic route found"
        return false, State.farmStatus
    end

    local position = readPosition(guide.core)
    local direction = readDirection(guide.core)
    if not position or not direction then
        State.farmStatus = "traffic route unreadable"
        return false, State.farmStatus
    end

    if State.passMode == "Right only" then
        State.passSign = 1
    elseif State.passMode == "Left only" then
        State.passSign = -1
    end

    local right = Vector3.new(-direction.Z, 0, direction.X)
    local target = position - direction * 45 + right * (State.passOffset * State.passSign)
    target = Vector3.new(target.X, position.Y - 1.55, target.Z)

    local routeCFrame = CFrame.new(
        target.X, target.Y, target.Z,
        right.X, 0, -direction.X,
        0, 1, 0,
        right.Z, 0, -direction.Z
    )
    local ok, writeError = pcall(function()
        seat.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        seat.CFrame = routeCFrame
    end)
    if not ok then
        State.farmStatus = "route placement failed: " .. tostring(writeError)
        return false, State.farmStatus
    end

    State.lastReacquire = now
    State.lastDirection = direction
    State.guideAddress = guide.address
    State.farmArmed = true
    State.farmStatus = reason or "route acquired"
    State.stallStarted = nil
    State.tuneStatus = reason or State.tuneStatus
    return true, "route acquired"
end

local function armFarm(reason)
    if not State.farmEnabled then return end
    refreshCar()
    refreshTraffic()
    if State.farmArmed then
        notify("Ghost Driver", "Autofarm is already armed on the live route.", "play", 3)
        return
    end
    local ok, message = acquireTrafficRoute(reason or "manual start")
    if ok then
        notify("Ghost Driver", "Autofarm armed on the live traffic route.", "play", 4)
    else
        notify("Ghost Driver", message .. "; it will retry automatically.", "info", 4)
    end
end

local function currentMPH()
    local seat = State.seat
    if not seat then return 0 end
    local ok, velocity = pcall(function()
        return seat.AssemblyLinearVelocity
    end)
    if not ok or not velocity then return 0 end
    return velocity.Magnitude * MPH_PER_STUD
end

local function controlFarm()
    local seat = State.seat
    if not seat or not State.farmEnabled or not State.farmArmed then return end

    local seatPosition = readPosition(seat)
    if not seatPosition then return end
    local guide, distance = chooseGuide(seatPosition)
    State.guideDistance = distance

    if not guide or distance > State.reacquireDistance then
        State.farmStatus = guide and "guide too far; recovering" or "no guide; recovering"
        if State.autoReacquire then
            acquireTrafficRoute("lost route")
        end
        return
    end

    local guidePosition = readPosition(guide.core)
    local direction = readDirection(guide.core)
    if not guidePosition or not direction then return end

    if State.guideAddress ~= guide.address then
        State.guideAddress = guide.address
        updatePassSign()
    end
    State.lastDirection = direction

    local right = Vector3.new(-direction.Z, 0, direction.X)
    local targetLine = guidePosition + right * (State.passOffset * State.passSign)
    local lateralError = (targetLine - seatPosition):Dot(right)
    local lateralSpeed = clamp(
        lateralError * State.farmLateralGain,
        -State.farmLateralLimit,
        State.farmLateralLimit
    )

    local ok, velocity = pcall(function()
        return seat.AssemblyLinearVelocity
    end)
    if not ok or not velocity then return end

    local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
    local forwardSpeed = horizontal:Dot(direction)
    local targetSpeed = State.farmTargetMPH / MPH_PER_STUD
    local accelerationStep = State.farmAcceleration * CONTROL_DT
    local nextForward = forwardSpeed + clamp(targetSpeed - forwardSpeed, -accelerationStep, accelerationStep)
    local vertical = clamp(velocity.Y * 0.30, -4, 4)
    local desired = direction * nextForward + right * lateralSpeed + Vector3.new(0, vertical, 0)

    pcall(function()
        seat.AssemblyLinearVelocity = desired
    end)

    if horizontal.Magnitude < 20 then
        if not State.stallStarted then State.stallStarted = os.clock() end
        if State.autoReacquire and os.clock() - State.stallStarted > 2 then
            acquireTrafficRoute("stall recovery")
        end
    else
        State.stallStarted = nil
    end
end

local function controlManual()
    local seat = State.seat
    if not seat or not State.controllerEnabled or State.farmEnabled then return end

    local ok, velocity, look = pcall(function()
        return seat.AssemblyLinearVelocity, seat.CFrame.LookVector
    end)
    if not ok or not velocity or not look then return end
    local forward = flatUnit(look)
    if not forward then return end

    local nextVelocity = velocity
    if State.nitroEnabled and State.nitroHeld then
        local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
        local forwardSpeed = horizontal:Dot(forward)
        local maxSpeed = State.manualMaxMPH / MPH_PER_STUD
        local push = math.min(State.nitroAcceleration * CONTROL_DT, math.max(0, maxSpeed - forwardSpeed))
        if push > 0 then
            nextVelocity = nextVelocity + forward * push
        end
    end

    if State.stabilityEnabled then
        local horizontal = Vector3.new(nextVelocity.X, 0, nextVelocity.Z)
        local forwardSpeed = horizontal:Dot(forward)
        local forwardComponent = forward * forwardSpeed
        local lateral = horizontal - forwardComponent
        local stabilizedHorizontal = forwardComponent + lateral * State.lateralDamping
        nextVelocity = Vector3.new(
            stabilizedHorizontal.X,
            clamp(nextVelocity.Y * State.verticalDamping, -12, 12),
            stabilizedHorizontal.Z
        )
    end

    pcall(function()
        seat.AssemblyLinearVelocity = nextVelocity
    end)
end

local BaseDefaults = {
    Horsepower = 450,
    Turbochargers = 2,
    T_Boost = 7,
    T_BoostLag = 125,
    Superchargers = 0,
    S_Boost = 7,
    S_Sensitivity = 0.05,
    Weight = 3239,
    WeightDist = 55,
    CGHeight = 0.8,
    SteerDecay = 250,
    MinSteer = 30,
    SteerSpeed = 0.09,
    ReturnSpeed = 0.1,
    TCSThreshold = 20,
    TCSGradient = 20,
    TCSLimit = 10,
    FinalDrive = 3.545,
    ShiftUpTime = 0.25,
    ShiftDnTime = 0.125,
    BrakeForce = 3000,
}

local Defaults = {}
local Applied = {}
for key, value in pairs(BaseDefaults) do
    Defaults[key] = value
    Applied[key] = value
end

local TuneProfiles = {
    ["Wulfbrecht RZ7"] = {
        Horsepower = 450,
        Weight = 3239,
    },
    ["Weinchen V20"] = {
        Horsepower = 800,
        Weight = 3439,
    },
    ["Weinchen V80"] = {
        Horsepower = 900,
        Weight = 3939,
    },
    ["Weinchen V120"] = {
        Horsepower = 550,
        Turbochargers = 1,
        Weight = 3360,
        FinalDrive = 2.5,
    },
    ["Eisenhardt G43"] = {
        Horsepower = 700,
        Weight = 3939,
    },
    ["Voss RT8"] = {
        Horsepower = 1000,
        Weight = 4559,
        BrakeForce = 5000,
    },
    ["Rangy Helly"] = {
        Horsepower = 1300,
        Turbochargers = 0,
        Superchargers = 1,
        Weight = 5575,
        FinalDrive = 3.2,
        BrakeForce = 9000,
    },
}

local Desired = {
    Horsepower = 1200,
    Turbochargers = 2,
    T_Boost = 25,
    T_BoostLag = 90,
    Superchargers = 0,
    S_Boost = 15,
    S_Sensitivity = 0.05,
    Weight = 3600,
    WeightDist = 55,
    CGHeight = 0.65,
    SteerDecay = 220,
    MinSteer = 45,
    SteerSpeed = 0.075,
    ReturnSpeed = 0.09,
    TCSThreshold = 10,
    TCSGradient = 10,
    TCSLimit = 5,
    FinalDrive = 3.8,
    ShiftUpTime = 0.18,
    ShiftDnTime = 0.10,
    BrakeForce = 3800,
}

local POWER_FIELDS = {
    "Horsepower", "Turbochargers", "T_Boost", "T_BoostLag",
    "Superchargers", "S_Boost", "S_Sensitivity",
}

local HANDLING_FIELDS = {
    "Weight", "WeightDist", "CGHeight", "SteerDecay", "MinSteer",
    "SteerSpeed", "ReturnSpeed", "TCSThreshold", "TCSGradient",
    "TCSLimit", "FinalDrive", "ShiftUpTime", "ShiftDnTime", "BrakeForce",
}

local function syncTuneProfile()
    if State.tuneProfileAddress == State.carAddress then return end

    for key, value in pairs(BaseDefaults) do
        Defaults[key] = value
    end

    local profileName = "generic mapped values"
    for carName, overrides in pairs(TuneProfiles) do
        if string.find(State.carName or "", carName, 1, true) then
            profileName = carName
            for key, value in pairs(overrides) do
                Defaults[key] = value
            end
            break
        end
    end

    for key, value in pairs(Defaults) do
        Applied[key] = value
    end
    State.tuneProfileAddress = State.carAddress
    State.tuneProfile = profileName
    State.tuneStatus = "ready - " .. profileName
end

local function applyTuneFields(fields, source)
    if State.tuneBusy then
        notify("Tuner busy", "Wait for the current tuning pass to finish.", "info", 3)
        return
    end
    syncTuneProfile()
    if type(setgc) ~= "function" then
        State.tuneStatus = "setgc unavailable"
        notify("Tuner unavailable", "This executor does not expose setgc.", "x", 5)
        return
    end

    State.tuneBusy = true
    State.tuneStatus = "applying " .. source
    notify("Ghost Driver tuner", "Applying changed values; the live table scan can take a moment.", "settings", 5)

    task.spawn(function()
        local changedFields = 0
        local matchedTables = 0
        local failed = 0
        for i = 1, #fields do
            if _G.__GhostDriverToken ~= token then break end
            local key = fields[i]
            local oldValue = Applied[key]
            local newValue = Desired[key]
            if newValue ~= nil and oldValue ~= nil and newValue ~= oldValue then
                local ok, result = pcall(function()
                    return setgc(key, newValue, oldValue)
                end)
                local matches = ok and tonumber(result) or 0
                if matches and matches > 0 then
                    Applied[key] = newValue
                    changedFields = changedFields + 1
                    matchedTables = matchedTables + matches
                else
                    failed = failed + 1
                end
                task.wait()
            end
        end
        State.tuneBusy = false
        State.tuneStatus = string.format("%s: %d changed, %d unmatched", source, changedFields, failed)
        notify(
            "Tuning finished",
            string.format("%d values changed across %d live matches. Respawn the car if a cached value does not update immediately.", changedFields, matchedTables),
            "check",
            6
        )
    end)
end

local function restoreTune()
    syncTuneProfile()
    for key, value in pairs(Defaults) do Desired[key] = value end
    local fields = {}
    for key in pairs(Defaults) do fields[#fields + 1] = key end
    applyTuneFields(fields, "stock restore")
end

local Window = Non:CreateWindow({
    Title = "Ghost Driver",
    Author = "vehicle controller v1",
    Theme = "Dark",
    Size = {720, 540},
    MinSize = {620, 440},
    Resizable = true,
    ToggleKey = "p",
    Footer = "P toggles menu",
    OpenButton = {
        Title = "Ghost Driver",
        OnlyIcon = false,
        Draggable = true,
        Scale = 1,
    },
})
_G.__GhostDriverUI = Window

local VehicleBand = Window:Section({Title = "Vehicle"})
local DriveTab = VehicleBand:Tab({Title = "Drive", Icon = "gauge"})
local FarmTab = VehicleBand:Tab({Title = "Autofarm", Icon = "route"})
local PowerTab = VehicleBand:Tab({Title = "Power", Icon = "zap"})
local HandlingTab = VehicleBand:Tab({Title = "Handling", Icon = "settings"})
local SafetyTab = VehicleBand:Tab({Title = "Safety", Icon = "shield"})

DriveTab:Section({Title = "Manual boost"})
DriveTab:Toggle({
    Title = "Controller enabled",
    Desc = "Master switch for manual boost and stability.",
    Default = true,
    Callback = function(on) State.controllerEnabled = on end,
})
DriveTab:Toggle({
    Title = "Nitro enabled",
    Desc = "Nitro only pushes while the hold key is active.",
    Default = true,
    Callback = function(on)
        State.nitroEnabled = on
        if not on then State.nitroHeld = false end
    end,
})
DriveTab:Keybind({
    Title = "Nitro hold key",
    Desc = "Hold Left Shift while driving.",
    Default = "leftshift",
    Mode = "hold",
    Callback = function(_, active)
        State.nitroHeld = active == true
    end,
})
DriveTab:Slider({
    Title = "Nitro acceleration",
    Min = 20,
    Max = 300,
    Default = State.nitroAcceleration,
    Step = 5,
    Rounding = 0,
    Suffix = " studs/s2",
    Callback = function(value) State.nitroAcceleration = value end,
})
DriveTab:Slider({
    Title = "Manual speed cap",
    Min = 100,
    Max = 400,
    Default = State.manualMaxMPH,
    Step = 5,
    Rounding = 0,
    Suffix = " MPH",
    Callback = function(value) State.manualMaxMPH = value end,
})

DriveTab:Section({Title = "Stability"})
DriveTab:Toggle({
    Title = "Velocity stability",
    Desc = "Damps sideways and vertical velocity without adding forward speed.",
    Default = true,
    Callback = function(on) State.stabilityEnabled = on end,
})
DriveTab:Slider({
    Title = "Lateral carry",
    Desc = "Lower values remove sliding more aggressively.",
    Min = 0.1,
    Max = 1,
    Default = State.lateralDamping,
    Step = 0.05,
    Rounding = 2,
    Callback = function(value) State.lateralDamping = value end,
})
DriveTab:Slider({
    Title = "Vertical carry",
    Desc = "Lower values settle bumps faster.",
    Min = 0.1,
    Max = 1,
    Default = State.verticalDamping,
    Step = 0.05,
    Rounding = 2,
    Callback = function(value) State.verticalDamping = value end,
})
local DriveStatus = DriveTab:Paragraph({
    Title = "Vehicle: waiting",
    Desc = "No acceleration is applied until nitro is held or autofarm is enabled.",
    Icon = "info",
})

FarmTab:Section({Title = "Traffic near-miss farm"})
FarmTab:Toggle({
    Title = "Autofarm",
    Desc = "Explicitly arms route placement and traffic-guided propulsion.",
    Default = false,
    Callback = function(on)
        State.farmEnabled = on
        State.nitroHeld = false
        if on then
            State.farmArmed = false
            State.lastReacquire = -100
            task.spawn(function()
                task.wait(0.1)
                armFarm("toggle start")
            end)
        else
            State.farmArmed = false
            State.farmStatus = "stopped"
            State.guideAddress = nil
            State.stallStarted = nil
            notify("Ghost Driver", "Autofarm stopped; vehicle propulsion released.", "pause", 3)
        end
    end,
})
FarmTab:Button({
    Title = "Acquire traffic route now",
    Desc = "One controlled placement behind the nearest live traffic car.",
    Callback = function()
        State.farmEnabled = true
        State.lastReacquire = -100
        task.spawn(function() armFarm("manual route acquire") end)
    end,
})
FarmTab:Slider({
    Title = "Farm target speed",
    Min = 90,
    Max = 320,
    Default = State.farmTargetMPH,
    Step = 5,
    Rounding = 0,
    Suffix = " MPH",
    Callback = function(value) State.farmTargetMPH = value end,
})
FarmTab:Slider({
    Title = "Farm acceleration",
    Min = 40,
    Max = 250,
    Default = State.farmAcceleration,
    Step = 5,
    Rounding = 0,
    Suffix = " studs/s2",
    Callback = function(value) State.farmAcceleration = value end,
})
FarmTab:Dropdown({
    Title = "Passing pattern",
    Values = {"Alternate", "Right only", "Left only"},
    Default = "Alternate",
    Multi = false,
    SearchBarEnabled = false,
    Callback = function(value)
        State.passMode = value
        if value == "Right only" then State.passSign = 1 end
        if value == "Left only" then State.passSign = -1 end
    end,
})
FarmTab:Slider({
    Title = "Near-miss offset",
    Desc = "Distance from traffic center; 7-9 studs is the useful range.",
    Min = 5,
    Max = 12,
    Default = State.passOffset,
    Step = 0.25,
    Rounding = 2,
    Suffix = " studs",
    Callback = function(value) State.passOffset = value end,
})
FarmTab:Slider({
    Title = "Lane correction strength",
    Min = 0.5,
    Max = 3,
    Default = State.farmLateralGain,
    Step = 0.05,
    Rounding = 2,
    Callback = function(value) State.farmLateralGain = value end,
})
FarmTab:Slider({
    Title = "Maximum sideways speed",
    Min = 8,
    Max = 50,
    Default = State.farmLateralLimit,
    Step = 1,
    Rounding = 0,
    Suffix = " studs/s",
    Callback = function(value) State.farmLateralLimit = value end,
})
FarmTab:Toggle({
    Title = "Automatic route recovery",
    Desc = "Allows a single reposition after route loss or a two-second stall.",
    Default = true,
    Callback = function(on) State.autoReacquire = on end,
})
local FarmStatus = FarmTab:Paragraph({
    Title = "Autofarm: stopped",
    Desc = "Traffic is kept alive because its side hitboxes generate the payout.",
    Icon = "route",
})

PowerTab:Section({Title = "A-Chassis power table"})
PowerTab:Input({
    Title = "Horsepower",
    Default = tostring(Desired.Horsepower),
    Callback = function(value)
        local number = tonumber(value)
        if number then Desired.Horsepower = clamp(number, 100, 10000) end
    end,
})
PowerTab:Slider({
    Title = "Turbochargers",
    Min = 0,
    Max = 8,
    Default = Desired.Turbochargers,
    Step = 1,
    Rounding = 0,
    Callback = function(value) Desired.Turbochargers = value end,
})
PowerTab:Slider({
    Title = "Turbo boost",
    Min = 0,
    Max = 100,
    Default = Desired.T_Boost,
    Step = 1,
    Rounding = 0,
    Suffix = " PSI",
    Callback = function(value) Desired.T_Boost = value end,
})
PowerTab:Slider({
    Title = "Turbo lag",
    Min = 0,
    Max = 400,
    Default = Desired.T_BoostLag,
    Step = 5,
    Rounding = 0,
    Callback = function(value) Desired.T_BoostLag = value end,
})
PowerTab:Slider({
    Title = "Superchargers",
    Min = 0,
    Max = 8,
    Default = Desired.Superchargers,
    Step = 1,
    Rounding = 0,
    Callback = function(value) Desired.Superchargers = value end,
})
PowerTab:Slider({
    Title = "Supercharger boost",
    Min = 0,
    Max = 100,
    Default = Desired.S_Boost,
    Step = 1,
    Rounding = 0,
    Suffix = " PSI",
    Callback = function(value) Desired.S_Boost = value end,
})
PowerTab:Slider({
    Title = "Supercharger sensitivity",
    Min = 0.01,
    Max = 0.5,
    Default = Desired.S_Sensitivity,
    Step = 0.01,
    Rounding = 2,
    Callback = function(value) Desired.S_Sensitivity = value end,
})
PowerTab:Button({
    Title = "Apply power tune",
    Desc = "Changes only values that differ from the mapped stock table.",
    Callback = function() applyTuneFields(POWER_FIELDS, "power tune") end,
})
local PowerStatus = PowerTab:Paragraph({
    Title = "Tuner: ready",
    Desc = "Mapped from the live A-Chassis tune. Idle throttle stays stock so the car never self-accelerates.",
    Icon = "info",
})

HandlingTab:Section({Title = "Grip and steering"})
HandlingTab:Input({
    Title = "Vehicle weight",
    Default = tostring(Desired.Weight),
    Callback = function(value)
        local number = tonumber(value)
        if number then Desired.Weight = clamp(number, 500, 10000) end
    end,
})
HandlingTab:Slider({
    Title = "Center of gravity height",
    Min = 0.1,
    Max = 2,
    Default = Desired.CGHeight,
    Step = 0.05,
    Rounding = 2,
    Callback = function(value) Desired.CGHeight = value end,
})
HandlingTab:Slider({
    Title = "Weight distribution",
    Min = 35,
    Max = 65,
    Default = Desired.WeightDist,
    Step = 1,
    Rounding = 0,
    Suffix = "% front",
    Callback = function(value) Desired.WeightDist = value end,
})
HandlingTab:Slider({
    Title = "Minimum steering",
    Min = 5,
    Max = 70,
    Default = Desired.MinSteer,
    Step = 1,
    Rounding = 0,
    Callback = function(value) Desired.MinSteer = value end,
})
HandlingTab:Slider({
    Title = "Steering decay",
    Min = 50,
    Max = 500,
    Default = Desired.SteerDecay,
    Step = 5,
    Rounding = 0,
    Callback = function(value) Desired.SteerDecay = value end,
})
HandlingTab:Slider({
    Title = "Steering speed",
    Min = 0.02,
    Max = 0.25,
    Default = Desired.SteerSpeed,
    Step = 0.005,
    Rounding = 3,
    Callback = function(value) Desired.SteerSpeed = value end,
})
HandlingTab:Slider({
    Title = "Steering return speed",
    Min = 0.02,
    Max = 0.25,
    Default = Desired.ReturnSpeed,
    Step = 0.005,
    Rounding = 3,
    Callback = function(value) Desired.ReturnSpeed = value end,
})
HandlingTab:Slider({
    Title = "TCS threshold",
    Min = 0,
    Max = 100,
    Default = Desired.TCSThreshold,
    Step = 1,
    Rounding = 0,
    Callback = function(value) Desired.TCSThreshold = value end,
})
HandlingTab:Slider({
    Title = "TCS gradient",
    Min = 0,
    Max = 100,
    Default = Desired.TCSGradient,
    Step = 1,
    Rounding = 0,
    Callback = function(value) Desired.TCSGradient = value end,
})
HandlingTab:Slider({
    Title = "TCS power limit",
    Min = 0,
    Max = 100,
    Default = Desired.TCSLimit,
    Step = 1,
    Rounding = 0,
    Callback = function(value) Desired.TCSLimit = value end,
})
HandlingTab:Slider({
    Title = "Final drive",
    Min = 1,
    Max = 8,
    Default = Desired.FinalDrive,
    Step = 0.05,
    Rounding = 2,
    Callback = function(value) Desired.FinalDrive = value end,
})
HandlingTab:Input({
    Title = "Brake force",
    Default = tostring(Desired.BrakeForce),
    Callback = function(value)
        local number = tonumber(value)
        if number then Desired.BrakeForce = clamp(number, 500, 15000) end
    end,
})
HandlingTab:Button({
    Title = "Apply handling tune",
    Callback = function() applyTuneFields(HANDLING_FIELDS, "handling tune") end,
})
HandlingTab:Button({
    Title = "Restore mapped stock tune",
    Callback = restoreTune,
})
HandlingTab:Paragraph({
    Title = "A-Chassis note",
    Desc = "Power values usually update live. Steering, brakes, and weight may be cached when the drive script starts; respawn the car after applying those values.",
    Icon = "info",
})

SafetyTab:Section({Title = "Protection and cleanup"})
SafetyTab:Toggle({
    Title = "Crash detector guard",
    Desc = "Shrinks only the four crash-reset detectors. Near-miss score hitboxes and AI traffic remain active.",
    Default = true,
    Callback = function(on)
        State.crashGuard = on
        if on then
            applyCrashGuard()
        else
            restoreCrashDetectors()
            if State.car then captureCrashDetectors(State.car) end
        end
    end,
})
SafetyTab:Toggle({
    Title = "Anti-AFK",
    Desc = "One mouse click every 19 minutes; it never moves the pointer or presses a drive key.",
    Default = true,
    Callback = function(on)
        State.antiAfk = on
        State.lastAfk = os.clock()
        State.afkStatus = on and "waiting" or "disabled"
    end,
})
SafetyTab:Button({
    Title = "Stop autofarm now",
    Callback = function()
        State.farmEnabled = false
        State.farmArmed = false
        State.farmStatus = "stopped"
        State.nitroHeld = false
        notify("Ghost Driver", "Autofarm and nitro input stopped.", "pause", 3)
    end,
})
local SafetyStatus = SafetyTab:Paragraph({
    Title = "Safety: active",
    Desc = "All edited crash detector sizes are restored when the script is stopped or reloaded.",
    Icon = "shield",
})

local function stopController(destroyUI)
    if not State.running then return end
    State.running = false
    State.farmEnabled = false
    State.farmArmed = false
    State.farmStatus = "unloaded"
    State.nitroHeld = false
    restoreCrashDetectors()
    if _G.__GhostDriverToken == token then
        _G.__GhostDriverToken = token + 1
    end
    if destroyUI and _G.__GhostDriverUI then
        pcall(function()
            _G.__GhostDriverUI:Destroy()
        end)
        _G.__GhostDriverUI = nil
    end
end

_G.__GhostDriverStop = function()
    stopController(false)
end

SafetyTab:Button({
    Title = "Unload controller",
    Desc = "Stops every loop, restores crash detectors, and closes the UI.",
    Callback = function()
        notify("Ghost Driver", "Controller unloaded and detector sizes restored.", "check", 3)
        task.delay(0.15, function() stopController(true) end)
    end,
})

local function getPlayerValue(name)
    local object = lp:FindFirstChild(name)
    if not object then return 0 end
    local ok, value = pcall(function() return object.Value end)
    if ok then return tonumber(value) or 0 end
    return 0
end

task.spawn(function()
    while _G.__GhostDriverToken == token and State.running do
        pcall(refreshCar)
        pcall(refreshTraffic)
        if State.crashGuard then pcall(applyCrashGuard) end
        if State.farmEnabled and not State.farmArmed and State.autoReacquire then
            pcall(function() acquireTrafficRoute("background acquire") end)
        end
        task.wait(TRAFFIC_REFRESH)
    end
end)

task.spawn(function()
    while _G.__GhostDriverToken == token and State.running do
        if State.farmEnabled then
            pcall(controlFarm)
        else
            pcall(controlManual)
        end
        task.wait(CONTROL_DT)
    end
end)

task.spawn(function()
    while _G.__GhostDriverToken == token and State.running do
        if State.antiAfk and os.clock() - State.lastAfk >= AFK_INTERVAL then
            local ok = false
            if type(mouse1click) == "function" then
                ok = pcall(function() mouse1click() end)
            end
            State.lastAfk = os.clock()
            State.afkStatus = ok and "clicked" or "mouse1click unavailable"
        end
        task.wait(5)
    end
end)

task.spawn(function()
    while _G.__GhostDriverToken == token and State.running do
        local mph = currentMPH()
        local bestCombo = getPlayerValue("BestCombo")
        local bestPoints = getPlayerValue("BestPts")
        local guideText = State.guideDistance and (tostring(math.floor(State.guideDistance)) .. " studs") or "none"
        local farmWord = State.farmEnabled and (State.farmArmed and "armed" or "waiting") or "stopped"
        local afkRemaining = math.max(0, AFK_INTERVAL - (os.clock() - State.lastAfk))
        syncTuneProfile()

        pcall(function()
            DriveStatus:SetTitle("Vehicle: " .. State.carName)
            DriveStatus:SetDesc(string.format(
                "Speed: %.0f MPH | Nitro: %s | Stability: %s\nNo propulsion is applied unless nitro is held or autofarm is armed.",
                mph,
                State.nitroHeld and "held" or "idle",
                State.stabilityEnabled and "on" or "off"
            ))
        end)
        pcall(function()
            FarmStatus:SetTitle("Autofarm: " .. farmWord)
            FarmStatus:SetDesc(string.format(
                "Traffic: %d | Guide: %s | Best combo: %d | Best points: %d\n%s | Crash guard keeps the side scoring hitboxes intact.",
                State.trafficCount,
                guideText,
                bestCombo,
                bestPoints,
                State.farmStatus
            ))
        end)
        pcall(function()
            PowerStatus:SetTitle("Tuner: " .. State.tuneStatus)
            PowerStatus:SetDesc(
                "Stock matcher: " .. State.tuneProfile .. ". Values change only after Apply; idle throttle remains stock at 3."
            )
        end)
        pcall(function()
            SafetyStatus:SetTitle("Safety: " .. (State.crashGuard and "guarded" or "stock"))
            SafetyStatus:SetDesc(string.format(
                "Crash detectors: %d | Anti-AFK: %s | next click in %dm %02ds",
                #State.collisionEntries,
                State.antiAfk and State.afkStatus or "disabled",
                math.floor(afkRemaining / 60),
                math.floor(afkRemaining % 60)
            ))
        end)
        task.wait(INFO_REFRESH)
    end
end)

pcall(function() DriveTab:Select() end)
notify(
    "Ghost Driver loaded",
    "Boost is hold-only and autofarm is disarmed. Press P to toggle the NonUI window.",
    "check",
    6
)

print("[Ghost Driver] NonUI controller loaded; autofarm is OFF.")
print("[Ghost Driver] Hold Left Shift for nitro. Press P for UI.")
print("[Ghost Driver] Stop with: _G.__GhostDriverStop()")

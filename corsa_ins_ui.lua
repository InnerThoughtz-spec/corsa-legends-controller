-- Corsa Legends Controller using INS-ui
-- Menu: P | Nitro: hold Left Shift
-- Includes Swerve traffic farming, anti-AFK, and forced-induction tuning

local oldToken = (_G.__CorsaBoostToken or 0) + 1
_G.__CorsaBoostToken = oldToken
_G.__CorsaBoost = true
_G.__CorsaHack = false

if _G.__CorsaRestoreWheels then
    pcall(_G.__CorsaRestoreWheels)
end
if _G.__CorsaRestoreTrafficProxies then
    pcall(_G.__CorsaRestoreTrafficProxies)
end

if _G.__CorsaUI then
    pcall(function() _G.__CorsaUI:Destroy() end)
end

local uiSource = game:HttpGet(
    "https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.lua"
)

local imageCleanupHook = [[
function ui:HideWindowImages()
    local function hideImage(img)
        if img then pcall(function() img.Visible = false end) end
    end

    for _, tab in ipairs(ProjectState.tabs or {}) do
        hideImage(tab._img)
        hideImage(tab._imgA)
        for _, sub in ipairs(tab.subs or {}) do
            hideImage(sub._img)
            hideImage(sub._imgA)
        end
        for _, section in ipairs(tab.sections or {}) do
            for _, item in ipairs(section.items or {}) do
                hideImage(item._img)
                hideImage(item._ddImg)
            end
        end
    end

    hideImage(ProjectState._gearImg)
    hideImage(ProjectState.bgImg)
    hideImage(ProjectState.avatarImg)
    hideImage(ProjectState.logoImg)
    hideImage(ProjectState.iconImg)
    return self
end
]]

local patchedSource, hookCount = string.gsub(uiSource, "function ui:Destroy%(%)", function()
    return imageCleanupHook .. "\nfunction ui:Destroy()"
end, 1)
assert(hookCount == 1, "INS-ui cleanup hook could not be installed")
uiSource = patchedSource

local uiLoader = assert(loadstring(uiSource))
local Lib = uiLoader() or INSui
local MPH_PER_STUD_PER_SECOND = 0.626342
local SWERVE_MAX_MPH = 370
local MICRO_SWERVE_MAX_WIDTH = 1.75
local MICRO_SWERVE_MAX_HOLD = 0.18
local SWERVE_MAX_LATERAL_SPEED = 5
local SWERVE_MAX_LATERAL_ACCELERATION = 36

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
    horsepowerLimit = 999999999,

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
    swerveTargetMPH = SWERVE_MAX_MPH,
    swerveSpeed = SWERVE_MAX_MPH / MPH_PER_STUD_PER_SECOND,
    swerveAcceleration = 150,
    swerveLaneSpeed = 5,
    swerveLaneAcceleration = 36,
    microSwerveEnabled = true,
    microSwerveWidth = 1.25,
    microSwerveHold = 0.15,
    microSwervePause = 1.00,
    microSwerveLateralSpeed = 3.0,
    microSwerveAcceleration = 18,
    microSwervePhase = "center",
    microSwerveCount = 0,
    laneAlternation = true,
    laneSwitchPause = 0.85,
    laneTransitionSpeed = 5,
    laneTransitionAcceleration = 30,
    laneSwitching = false,
    groundTrackLock = false,
    groundTrackHeight = 0,
    groundTrackCorrections = 0,
    groundTrackStrength = 2.4,
    groundTrackDamping = 0.85,
    groundTrackMaxVerticalSpeed = 2.5,
    groundTrackVerticalAcceleration = 12,
    groundTrackHeightError = 0,
    groundTrackVerticalSpeed = 0,
    groundTrackFallbacks = 0,
    groundTrackStatus = "legacy",
    avoidLeftRail = true,
    leftRailGuardActive = false,
    leftRailCorrections = 0,
    targetLane = 2,
    trafficNoCollision = true,
    trafficDetected = 0,
    trafficAhead = math.huge,
    trafficGhosted = 0,
    trafficModels = 0,
    trafficCollidable = 0,
    trafficProxiesDetached = 0,
    crashGuard = true,
    crashGuardActive = false,
    crashGuardDistance = 120,
    crashGuardSpeed = 0,
    serverGhostProtection = true,
    serverGhostCutoff = 350,
    serverGhostsRemoved = 0,
    serverGhostResets = 0,
    autoRetry = true,
    retryCount = 0,
    retryArmed = false,
    retryReason = "monitoring",
    retryState = "monitoring",
    retryAttempts = 0,
    retrySignalFrames = 0,
    retryPending = false,
    autoPayout = true,
    autoPayoutScore = 2000000,
    payoutCycles = 0,
    payoutInProgress = false,

    fullTuneStatCount = 0,
    fullTuneOverrideCount = 0,
    fullTuneSelected = "none",
    fullTuneSelectedType = "none",

    antiAfk = true,
    antiAfkInterval = 19 * 60,
    antiAfkClicks = 0,
    antiAfkNextIn = 19 * 60,
    antiAfkStatus = "waiting",
}

_G.__CorsaState = State

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
local swerveRemotes = remotesFolder and remotesFolder:FindFirstChild("SwerveRemotes")
local token = oldToken
local currentCar
local currentSeat
local currentRoot
local currentAddress
local swerveCarAddress
local swerveLane = 2
local swerveMicroOffset = 0
local swerveMicroDirection = 1
local swerveMicroReturnAt = 0
local swerveMicroNextAt = 0
local swerveMicroRecoverUntil = 0
local swerveMicroNeedsRecovery = false
local swerveLanes = { 4805.187, 4821.565, 4837.794 }
local swerveStartZ = 19215
local swerveForward = Vector3.new(0, 0, 1)
local swerveGroundY
local swerveNextLaneSwitchAt = 0
local swerveLaneSwitching = false
local swerveLeftBoundaryX = 4814
local swerveFaulted = false
local ghostedTrafficParts = {}
local collisionParts = {}
local collisionPartAddresses = {}
local collisionModels = {}
local collisionModelAddresses = {}
local playerWheelParts = {}
local detachedTrafficProxies = {}
local detachedTrafficProxyAddresses = {}
local removedServerGhostIds = {}
local lastCharacterSpeed
local lastCrashGuardWrite = 0
local lastServerGhostPrune = 0
local lastRetryClick = 0
local lastObservedSwerveScore = 0
local retryArmedUntil = 0
local retryDetectionSuppressedUntil = 0
local retrySignalLatchedUntil = 0
local retrySignalFrames = 0
local retryPending = false
local retryVerifyingMotion = false
local retryRunId = 0
local swerveControlSuppressedUntil = 0
local antiAfkNextAt = tick() + State.antiAfkInterval
local fullTuneOverrides = {}
local fullTuneOriginals = {}
local fullTuneNames = {}
local fullTuneCarKey
local fullTuneSelected
local fullTunePendingValue = ""
local fullTuneDropdown
local fullTuneValueBox
local groundLockToggle

local win = Lib:CreateWindow({
    title = "Corsa Controller",
    subtitle = "full-corridor ghost cleanup + stable lanes v28",
    size = Vector2.new(720, 540),
    menuKey = "p",
    configName = "corsa-controller-v28",
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

task.spawn(function()
    while _G.__CorsaBoostToken == token do
        if not win:IsOpen() then
            win:HideWindowImages()
        end
        task.wait(0.05)
    end
end)

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
        bhpLimit = tostring(State.horsepowerLimit),
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

local editableValueClasses = {
    StringValue = true,
    NumberValue = true,
    IntValue = true,
    BoolValue = true,
}

local function safeTuneText(value)
    local text = tostring(value == nil and "" or value)
    text = text:gsub("[%z\1-\8\11\12\14-\31]", "?")
    if #text > 160 then text = text:sub(1, 160) end
    return text
end

local function getStatsFolder(car)
    return car and car:FindFirstChild("Stats")
end

local function relativeStatPath(stats, stat)
    local prefix = stats:GetFullName() .. "."
    local fullName = stat:GetFullName()
    if fullName:sub(1, #prefix) == prefix then
        return fullName:sub(#prefix + 1)
    end
    return stat.Name
end

local function resolveStat(car, path)
    local node = getStatsFolder(car)
    if not (node and path and path ~= "") then return nil end
    for segment in tostring(path):gmatch("[^%.]+") do
        node = node and node:FindFirstChild(segment)
        if not node then return nil end
    end
    return node
end

local function recountFullTuneOverrides()
    local count = 0
    for _ in pairs(fullTuneOverrides) do count = count + 1 end
    State.fullTuneOverrideCount = count
    return count
end

local function coerceStatValue(stat, text)
    local className = stat.ClassName
    if className == "StringValue" then
        return true, tostring(text or "")
    elseif className == "NumberValue" then
        local number = tonumber(text)
        if number == nil then return false, nil, "Enter a valid number" end
        return true, number
    elseif className == "IntValue" then
        local number = tonumber(text)
        if number == nil then return false, nil, "Enter a valid integer" end
        number = number >= 0 and math.floor(number + 0.5)
            or math.ceil(number - 0.5)
        return true, number
    elseif className == "BoolValue" then
        local value = tostring(text or ""):lower()
        if value == "true" or value == "1" or value == "yes" or value == "on" then
            return true, true
        elseif value == "false" or value == "0" or value == "no" or value == "off" then
            return true, false
        end
        return false, nil, "Use true/false, 1/0, yes/no, or on/off"
    end
    return false, nil, "Unsupported value type: " .. tostring(className)
end

local function writeFullTuneStat(car, path, text, remember, notifyUser)
    local stat = resolveStat(car, path)
    if not (stat and editableValueClasses[stat.ClassName]) then
        if notifyUser then
            Lib:Notify("Full tune", "Stat is unavailable on the current car", 3, "error")
        end
        return false
    end

    local valid, value, message = coerceStatValue(stat, text)
    if not valid then
        if notifyUser then Lib:Notify("Full tune", message, 3, "error") end
        return false
    end

    local ok = pcall(function() stat.Value = value end)
    if not ok then
        if notifyUser then
            Lib:Notify("Full tune", "The game rejected that value", 3, "error")
        end
        return false
    end

    if remember then
        fullTuneOverrides[path] = {
            className = stat.ClassName,
            value = value,
        }
        recountFullTuneOverrides()
    end

    if path == "bhpLimit" then
        local hp = tonumber(value)
        if hp then State.horsepowerLimit = hp end
    end
    if notifyUser then
        Lib:Notify(
            "Full tune",
            tostring(path) .. " = " .. safeTuneText(value),
            3,
            "success"
        )
    end
    return true
end

local function selectFullTuneStat(path)
    local stat = resolveStat(getCar(), path)
    fullTuneSelected = path
    State.fullTuneSelected = path or "none"
    State.fullTuneSelectedType = stat and stat.ClassName or "unavailable"
    fullTunePendingValue = stat and safeTuneText(stat.Value) or ""
    if fullTuneValueBox then fullTuneValueBox:Set(fullTunePendingValue) end
end

local function refreshFullTuneCatalog(car, resetOriginals)
    local stats = getStatsFolder(car)
    if not stats then
        fullTuneNames = {}
        State.fullTuneStatCount = 0
        if fullTuneDropdown then fullTuneDropdown:UpdateChoices({}) end
        return 0
    end

    local carKey = tostring(car.Address or car.Name)
    if resetOriginals or carKey ~= fullTuneCarKey then
        fullTuneOriginals = {}
        fullTuneCarKey = carKey
    end

    local names = {}
    for _, stat in ipairs(stats:GetDescendants()) do
        if editableValueClasses[stat.ClassName] then
            local path = relativeStatPath(stats, stat)
            names[#names + 1] = path
            if fullTuneOriginals[path] == nil then
                fullTuneOriginals[path] = {
                    className = stat.ClassName,
                    value = stat.Value,
                }
            end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    fullTuneNames = names
    State.fullTuneStatCount = #names

    if fullTuneDropdown then fullTuneDropdown:UpdateChoices(names) end
    local selectedStillExists = fullTuneSelected
        and resolveStat(car, fullTuneSelected) ~= nil
    if not selectedStillExists then fullTuneSelected = names[1] end
    if fullTuneSelected then
        if fullTuneDropdown then fullTuneDropdown:Set({ fullTuneSelected }) end
        selectFullTuneStat(fullTuneSelected)
    end
    return #names
end

local function applyFullTuneOverrides(car)
    local changed = 0
    for path, entry in pairs(fullTuneOverrides) do
        if writeFullTuneStat(car, path, entry.value, false, false) then
            changed = changed + 1
        end
    end
    return changed
end

local function restoreSelectedFullTuneStat()
    local original = fullTuneSelected and fullTuneOriginals[fullTuneSelected]
    if not original then return false end
    local restored = writeFullTuneStat(
        getCar(),
        fullTuneSelected,
        original.value,
        false,
        false
    )
    if restored then
        fullTuneOverrides[fullTuneSelected] = nil
        recountFullTuneOverrides()
        selectFullTuneStat(fullTuneSelected)
    end
    return restored
end

local function restoreAllFullTuneStats()
    local car = getCar()
    local restored = 0
    for path, original in pairs(fullTuneOriginals) do
        if writeFullTuneStat(car, path, original.value, false, false) then
            restored = restored + 1
        end
    end
    fullTuneOverrides = {}
    recountFullTuneOverrides()
    if fullTuneSelected then selectFullTuneStat(fullTuneSelected) end
    return restored
end

_G.__CorsaSetStat = function(path, value)
    return writeFullTuneStat(getCar(), tostring(path or ""), value, true, true)
end

_G.__CorsaRefreshStats = function()
    return refreshFullTuneCatalog(getCar(), false)
end

_G.__CorsaListStats = function()
    refreshFullTuneCatalog(getCar(), false)
    local copy = {}
    for i = 1, #fullTuneNames do copy[i] = fullTuneNames[i] end
    return copy
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
                -- Keep the entire vehicle well inside the middle lane. The
                -- boundary sits past the Lane1/Lane2 midpoint toward Lane2.
                swerveLeftBoundaryX = (found[1] + found[2]) * 0.5 + 1.5
                swerveStartZ = firstZ + 42
                return true
            end
        end
    end

    return false
end

local function getSwerveRemote(name)
    if not swerveRemotes or not swerveRemotes.Parent then
        remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
        swerveRemotes = remotesFolder and remotesFolder:FindFirstChild("SwerveRemotes")
    end
    return swerveRemotes and swerveRemotes:FindFirstChild(name)
end

local function resetServerGhosts()
    if not State.serverGhostProtection then return false end
    local ghostReset = getSwerveRemote("GhostReset")
    if not ghostReset then return false end

    local ok = pcall(function()
        ghostReset:FireServer()
    end)
    if ok then
        removedServerGhostIds = {}
        State.serverGhostResets = State.serverGhostResets + 1
    end
    return ok
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

    -- Retry can rebuild the A-Chassis internals without replacing the outer car
    -- model. Always promote the freshly resolved seat/root into the controller.
    currentCar = car
    currentAddress = car.Address
    currentSeat = seat
    currentRoot = root

    resolveSwerveCourse()
    -- Lane 1 is permanently forbidden. Only the middle and right lanes are used.
    local detectedLane = nearestSwerveLane(root.Position.X)
    swerveLane = math.max(2, math.min(3, detectedLane))
    State.targetLane = swerveLane
    swerveGroundY = root.Position.Y
    State.groundTrackHeight = swerveGroundY
    State.groundTrackCorrections = 0
    State.groundTrackHeightError = 0
    State.groundTrackVerticalSpeed = root.AssemblyLinearVelocity.Y
    State.groundTrackStatus = State.groundTrackLock
        and "soft velocity lock armed" or "legacy"
    swerveLaneSwitching = false
    State.laneSwitching = false
    swerveNextLaneSwitchAt = tick() + State.laneSwitchPause
    swerveMicroOffset = 0
    swerveMicroDirection = 1
    swerveMicroReturnAt = 0
    swerveMicroNextAt = tick() + 0.60
    swerveMicroRecoverUntil = 0
    swerveMicroNeedsRecovery = false
    State.microSwervePhase = "center"
    State.microSwerveCount = 0
    -- A Retry rebuild can leave one frame of stale lateral velocity behind. Keep
    -- the controller neutral until the replacement seat/root has settled.
    swerveControlSuppressedUntil = tick() + 1.25
    swerveFaulted = false
    State.serverGhostsRemoved = 0
    resetServerGhosts()

    local heliStart = getSwerveRemote("HeliStart")
    if heliStart then
        pcall(function() heliStart:FireServer() end)
    end
    local scoreStart = getSwerveRemote("ScoreStart")
    if scoreStart then
        pcall(function() scoreStart:FireServer() end)
    end

    swerveCarAddress = car.Address
    retryArmedUntil = 0
    retryDetectionSuppressedUntil = tick() + 4
    retrySignalLatchedUntil = 0
    retrySignalFrames = 0
    lastObservedSwerveScore = 0
    State.retryArmed = false
    State.retryReason = "monitoring"
    State.retryState = retryPending and "finalizing restart" or "monitoring"
    State.retrySignalFrames = 0
    if notifyUser then
        Lib:Notify("Swerve", "Autofarm initialized at the car's current position", 3, "success")
    end
    return true
end

local function stabilizeSwerveCar(root)
    if not root then return end
    local detectedLane = nearestSwerveLane(root.Position.X)
    swerveLane = math.max(2, math.min(3, detectedLane))
    State.targetLane = swerveLane
    swerveGroundY = root.Position.Y
    State.groundTrackHeight = swerveGroundY
    swerveLaneSwitching = false
    State.laneSwitching = false
    swerveNextLaneSwitchAt = tick() + State.laneSwitchPause
    pcall(function()
        local velocity = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(
            0,
            State.groundTrackLock and 0 or clamp(velocity.Y, -4, State.maxRise),
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
    retryRunId = retryRunId + 1
    retryPending = false
    State.retryPending = false
    State.retryState = "stopped"
    State.swerveEnabled = false
    swerveMicroOffset = 0
    swerveMicroRecoverUntil = 0
    swerveMicroNeedsRecovery = false
    State.microSwervePhase = "center"
    if _G.__CorsaRestoreWheels then pcall(_G.__CorsaRestoreWheels) end
    Lib:Notify("Swerve", "autofarm stopped", 2, "warning")
end

local function chooseMicroSwerveDirection()
    local root = currentRoot
    if root then
        local position = root.Position
        local bestAhead = math.huge
        local bestDirection

        for i = 1, #collisionModels do
            local car = collisionModels[i]
            local part = car and car.PrimaryPart
            if part then
                local ahead = part.Position.Z - position.Z
                if ahead > State.serverGhostCutoff + 15 and ahead < 280
                    and ahead < bestAhead then
                    local difference = part.Position.X - position.X
                    if math.abs(difference) > 5 then
                        bestAhead = ahead
                        bestDirection = difference > 0 and 1 or -1
                    end
                end
            end
        end

        if bestDirection then
            swerveMicroDirection = bestDirection
            return bestDirection
        end
    end

    swerveMicroDirection = -swerveMicroDirection
    return swerveMicroDirection
end

local function updateMicroSwerve()
    local now = tick()
    if not (State.swerveEnabled and State.microSwerveEnabled) then
        swerveMicroOffset = 0
        swerveMicroRecoverUntil = 0
        swerveMicroNeedsRecovery = false
        State.microSwervePhase = "center"
        swerveMicroNextAt = now + State.microSwervePause
        return 0
    end

    if swerveMicroOffset ~= 0 then
        if now >= swerveMicroReturnAt then
            swerveMicroOffset = 0
            swerveMicroRecoverUntil = now + 0.35
            State.microSwervePhase = "center"
            swerveMicroNextAt = now + State.microSwervePause
        end
    elseif now >= swerveMicroNextAt and not swerveMicroNeedsRecovery then
        local direction = chooseMicroSwerveDirection()
        swerveMicroOffset = direction * State.microSwerveWidth
        swerveMicroReturnAt = now + State.microSwerveHold
        swerveMicroNeedsRecovery = true
        State.microSwervePhase = direction < 0 and "A tap" or "D tap"
        State.microSwerveCount = State.microSwerveCount + 1
    end

    return swerveMicroOffset
end

local function updateTwoLaneTarget(positionX)
    local now = tick()
    swerveLane = math.max(2, math.min(3, swerveLane))

    if not State.laneAlternation then
        swerveLaneSwitching = false
        State.laneSwitching = false
        State.microSwervePhase = swerveLane == 2 and "middle lane" or "right lane"
        State.targetLane = swerveLane
        return
    end

    local laneCenter = swerveLanes[swerveLane]
    local settled = math.abs(positionX - laneCenter) <= 0.35

    if swerveLaneSwitching then
        if settled then
            swerveLaneSwitching = false
            State.laneSwitching = false
            State.microSwervePhase = swerveLane == 2
                and "settled middle" or "settled right"
            swerveNextLaneSwitchAt = now + State.laneSwitchPause
        end
    elseif settled and now >= swerveNextLaneSwitchAt then
        swerveLane = swerveLane == 2 and 3 or 2
        swerveLaneSwitching = true
        State.laneSwitching = true
        State.targetLane = swerveLane
        State.microSwerveCount = State.microSwerveCount + 1
        State.microSwervePhase = swerveLane == 2
            and "right -> middle" or "middle -> right"
    end

    State.targetLane = swerveLane
end

local lastGroundTrackFallback = 0

local function disableExperimentalGroundLock(reason)
    if not State.groundTrackLock then return end
    State.groundTrackLock = false
    State.groundTrackFallbacks = State.groundTrackFallbacks + 1
    State.groundTrackStatus = "fallback: " .. tostring(reason)
    swerveLaneSwitching = false
    State.laneSwitching = false
    swerveMicroOffset = 0
    swerveMicroRecoverUntil = 0
    swerveMicroNeedsRecovery = false
    swerveMicroNextAt = tick() + State.microSwervePause

    if groundLockToggle then
        pcall(function() groundLockToggle:Set(false) end)
    end
    if tick() - lastGroundTrackFallback > 2 then
        lastGroundTrackFallback = tick()
        Lib:Notify(
            "Ground lock fallback",
            tostring(reason) .. "; legacy controller restored",
            4,
            "warning"
        )
    end
end

local function softGroundVerticalVelocity(root, velocity, dt)
    local position = root.Position
    if not swerveGroundY then
        swerveGroundY = position.Y
        State.groundTrackHeight = swerveGroundY
    end

    local heightError = swerveGroundY - position.Y
    local verticalSpeed = velocity.Y
    local upY = root.CFrame.UpVector.Y
    State.groundTrackHeightError = heightError
    State.groundTrackVerticalSpeed = verticalSpeed

    if math.abs(heightError) > 4 then
        disableExperimentalGroundLock("unsafe road-height difference")
        return clamp(verticalSpeed, -3, 3), false
    end
    if math.abs(verticalSpeed) > 8 then
        disableExperimentalGroundLock("unsafe vertical speed")
        return clamp(verticalSpeed, -3, 3), false
    end
    if upY < 0.55 then
        disableExperimentalGroundLock("vehicle tilt exceeded safe limit")
        return clamp(verticalSpeed, -3, 3), false
    end

    local desired = heightError * State.groundTrackStrength
        - verticalSpeed * State.groundTrackDamping
    desired = clamp(
        desired,
        -State.groundTrackMaxVerticalSpeed,
        State.groundTrackMaxVerticalSpeed
    )
    local maxStep = State.groundTrackVerticalAcceleration * dt
    local result = verticalSpeed + clamp(
        desired - verticalSpeed,
        -maxStep,
        maxStep
    )
    result = clamp(
        result,
        -State.groundTrackMaxVerticalSpeed,
        State.groundTrackMaxVerticalSpeed
    )

    if math.abs(result - verticalSpeed) > 0.05 then
        State.groundTrackCorrections = State.groundTrackCorrections + 1
    end
    State.groundTrackStatus = "soft velocity lock"
    return result, true
end

local function buildLegacySwerveVelocity(velocity, position, dt)
    swerveLane = math.max(2, math.min(3, swerveLane))
    State.targetLane = swerveLane
    swerveLaneSwitching = false
    State.laneSwitching = false

    local laneGap = math.min(
        swerveLanes[2] - swerveLanes[1],
        swerveLanes[3] - swerveLanes[2]
    )
    local safeMargin = math.max(2, laneGap * 0.22)
    local safeLeft = swerveLanes[1] - 1.5
    local safeRight = swerveLanes[3] + safeMargin
    local microOffset = updateMicroSwerve()
    local lightTapActive = microOffset ~= 0 or swerveMicroNeedsRecovery
    local lateralAcceleration = lightTapActive
        and State.microSwerveAcceleration
        or math.min(State.swerveLaneAcceleration, SWERVE_MAX_LATERAL_ACCELERATION)
    local lateralSpeedLimit = lightTapActive
        and math.min(State.microSwerveLateralSpeed, 4)
        or math.min(State.swerveLaneSpeed, SWERVE_MAX_LATERAL_SPEED)
    local laneCenterX = swerveLanes[swerveLane]
    local targetX = clamp(laneCenterX + microOffset, safeLeft, safeRight)
    local lateralError = targetX - position.X
    local stoppingSpeed = math.sqrt(math.max(
        0,
        2 * lateralAcceleration * math.abs(lateralError)
    ))
    local desiredX = math.min(lateralSpeedLimit, stoppingSpeed)
    if lateralError < 0 then desiredX = -desiredX end
    if math.abs(lateralError) < 0.15 then desiredX = 0 end

    local lateralStep = math.min(
        lateralAcceleration * dt,
        lightTapActive and 1.5 or 5
    )
    local newX = velocity.X + clamp(
        desiredX - velocity.X,
        -lateralStep,
        lateralStep
    )
    newX = clamp(newX, -lateralSpeedLimit, lateralSpeedLimit)

    if position.X <= swerveLanes[1] - 1.5 then
        newX = math.max(newX, 5)
    elseif position.X <= swerveLanes[1] + 2 then
        newX = math.max(newX, 2.5)
    end

    if microOffset == 0
        and math.abs(position.X - laneCenterX) < 0.25
        and math.abs(newX) < 0.50 then
        swerveMicroNeedsRecovery = false
    end

    local newZ = velocity.Z + clamp(
        State.swerveSpeed - velocity.Z,
        -State.swerveAcceleration * dt,
        State.swerveAcceleration * dt
    )
    local output = Vector3.new(
        newX,
        clamp(velocity.Y, -3, State.maxRise),
        newZ
    )
    -- Forward acceleration and lateral centering have independent limits.
    -- Combining them into one delta cap delayed X sign reversals at high speed.
    return output
end

local function buildExperimentalSwerveVelocity(root, velocity, dt)
    local position = root.Position
    local newY, safe = softGroundVerticalVelocity(root, velocity, dt)
    if not safe then
        return buildLegacySwerveVelocity(velocity, position, dt)
    end
    updateTwoLaneTarget(position.X)

    local laneGap = math.min(
        swerveLanes[2] - swerveLanes[1],
        swerveLanes[3] - swerveLanes[2]
    )
    local safeRight = swerveLanes[3] + laneGap * 0.20
    local lateralAcceleration = swerveLaneSwitching
        and State.laneTransitionAcceleration
        or math.min(State.swerveLaneAcceleration, SWERVE_MAX_LATERAL_ACCELERATION)
    local lateralSpeedLimit = swerveLaneSwitching
        and State.laneTransitionSpeed
        or math.min(State.swerveLaneSpeed, SWERVE_MAX_LATERAL_SPEED)
    local laneCenterX = swerveLanes[swerveLane]
    local targetX = clamp(laneCenterX, swerveLeftBoundaryX, safeRight)
    local lateralError = targetX - position.X
    local stoppingSpeed = math.sqrt(math.max(
        0,
        2 * lateralAcceleration * math.abs(lateralError)
    ))
    local desiredX = math.min(lateralSpeedLimit, stoppingSpeed)
    if lateralError < 0 then desiredX = -desiredX end
    if math.abs(lateralError) < 0.15 then desiredX = 0 end

    local lateralStep = math.min(
        lateralAcceleration * dt,
        swerveLaneSwitching and 2.5 or 5
    )
    local newX = velocity.X + clamp(
        desiredX - velocity.X,
        -lateralStep,
        lateralStep
    )
    newX = clamp(newX, -lateralSpeedLimit, lateralSpeedLimit)
    if position.X <= swerveLeftBoundaryX + 0.5 then
        newX = math.max(newX, 4)
    end
    if not swerveLaneSwitching
        and math.abs(position.X - laneCenterX) < 0.20
        and math.abs(newX) < 0.75 then
        newX = 0
    end

    local newZ = velocity.Z + clamp(
        State.swerveSpeed - velocity.Z,
        -State.swerveAcceleration * dt,
        State.swerveAcceleration * dt
    )
    local output = Vector3.new(newX, newY, newZ)
    -- Keep the vertical, lateral, and forward controllers independent so one
    -- axis can never consume another axis's correction budget.
    return output
end

local function updateSwerveLane()
    local root = currentRoot
    if not (State.swerveEnabled and root) then return end

    local traffic = game.Workspace:FindFirstChild("AITraffic")
    local cars = traffic and traffic:FindFirstChild("Car")
    if not cars then return end

    local position = root.Position
    local clearance = { math.huge, math.huge, math.huge }
    local detected = 0

    for _, car in ipairs(cars:GetChildren()) do
        local part = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart", true)
        if part then
            local ahead = part.Position.Z - position.Z
            if ahead > -12 then
                local lane = nearestSwerveLane(part.Position.X)
                local lateralDistance = math.abs(part.Position.X - swerveLanes[lane])
                if lateralDistance <= 8 then
                    detected = detected + 1
                    clearance[lane] = math.min(clearance[lane], math.max(0, ahead))
                end
            end
        end
    end

    State.trafficDetected = detected
    State.trafficAhead = clearance[swerveLane]
end

local function getTrafficContainer()
    local traffic = game.Workspace:FindFirstChild("AITraffic")
    if not traffic then return nil end

    local direct = traffic:FindFirstChild("Car")
    if direct then return direct end

    -- Fall back to structure instead of relying on the folder retaining one name.
    for _, folder in ipairs(traffic:GetChildren()) do
        for _, candidate in ipairs(folder:GetChildren()) do
            if candidate.ClassName == "Model"
                and string.sub(candidate.Name, 1, 5) == "AICar" then
                return folder
            end
        end
    end
end

local function isTrafficPart(part)
    local className = part.ClassName
    return className == "Part"
        or className == "MeshPart"
        or className == "UnionOperation"
end

local function cacheTrafficModel(car)
    local address = car.Address
    if not address or collisionModelAddresses[address] then return 0 end

    collisionModelAddresses[address] = true
    collisionModels[#collisionModels + 1] = car
    pcall(function() car:SetAttribute("CollisionEnforced", false) end)

    local added = 0
    for _, part in ipairs(car:GetDescendants()) do
        if isTrafficPart(part) then
            local partAddress = part.Address
            if part.Name == "Collide" then
                if partAddress and not detachedTrafficProxyAddresses[partAddress] then
                    detachedTrafficProxyAddresses[partAddress] = true
                    detachedTrafficProxies[#detachedTrafficProxies + 1] = {
                        part = part,
                        parent = car,
                    }
                end
                pcall(function()
                    part.CanCollide = false
                    part.Parent = ReplicatedStorage
                end)
            elseif partAddress and not collisionPartAddresses[partAddress] then
                collisionPartAddresses[partAddress] = true
                collisionParts[#collisionParts + 1] = part
                ghostedTrafficParts[partAddress] = true
                added = added + 1
                pcall(function() part.CanCollide = false end)
            else
                pcall(function() part.CanCollide = false end)
            end
        end
    end

    State.trafficProxiesDetached = #detachedTrafficProxies
    return added
end

local function discoverTrafficModels()
    if not State.trafficNoCollision then return end
    local cars = getTrafficContainer()
    if not cars then return end

    for _, car in ipairs(cars:GetChildren()) do
        cacheTrafficModel(car)
    end
end

local function restorePlayerWheels()
    for i = 1, #playerWheelParts do
        local wheel = playerWheelParts[i]
        if wheel then
            pcall(function() wheel.CanCollide = true end)
        end
    end
end

_G.__CorsaRestoreWheels = function()
    restorePlayerWheels()
end

local function restoreTrafficProxies()
    for i = 1, #detachedTrafficProxies do
        local entry = detachedTrafficProxies[i]
        if entry and entry.part and entry.parent then
            pcall(function()
                entry.part.Parent = entry.parent
                entry.part.CanCollide = true
            end)
        end
    end

    detachedTrafficProxies = {}
    detachedTrafficProxyAddresses = {}
    State.trafficProxiesDetached = 0
end

_G.__CorsaRestoreTrafficProxies = restoreTrafficProxies

local function enforceTrafficGhosting()
    if not State.trafficNoCollision then return end

    -- Discovery runs before physics. An AI car can no longer remain solid for
    -- the old 0.15 second polling window after it spawns.
    discoverTrafficModels()

    for i = 1, #collisionModels do
        local car = collisionModels[i]
        if car then
            pcall(function() car:SetAttribute("CollisionEnforced", false) end)
        end
    end

    for i = 1, #collisionParts do
        local part = collisionParts[i]
        if part then
            pcall(function()
                if part.CanCollide then part.CanCollide = false end
            end)
        end
    end

    restorePlayerWheels()
end

local function getCharacterRoot()
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function trafficIsClose(root)
    if not root then return false end
    local position = root.Position

    for i = 1, #collisionModels do
        local car = collisionModels[i]
        local part = car and car.PrimaryPart
        if part then
            local ahead = part.Position.Z - position.Z
            local lateral = math.abs(part.Position.X - position.X)
            if ahead > -35
                and ahead < State.crashGuardDistance
                and lateral < 12 then
                return true
            end
        end
    end

    return false
end

local function removeImminentServerGhosts()
    local root = currentRoot
    if not (State.serverGhostProtection and State.swerveEnabled and root) then
        return
    end

    local ghostDespawn = getSwerveRemote("GhostDespawn")
    if not ghostDespawn then return end

    local now = tick()
    if now - lastServerGhostPrune >= 30 then
        lastServerGhostPrune = now
        for ghostId, removedAt in pairs(removedServerGhostIds) do
            if now - removedAt > 180 then
                removedServerGhostIds[ghostId] = nil
            end
        end
    end

    local position = root.Position
    local corridorLeft = swerveLanes[1] - 10
    local corridorRight = swerveLanes[3] + 10
    for i = 1, #collisionModels do
        local car = collisionModels[i]
        local part = car and car.PrimaryPart
        if part then
            local ahead = part.Position.Z - position.Z
            local insideCourse = part.Position.X >= corridorLeft
                and part.Position.X <= corridorRight
            if ahead > -50
                and ahead <= State.serverGhostCutoff
                and insideCourse then
                local ghostId = car:GetAttribute("GhostId")
                local key = ghostId and tostring(ghostId)
                if key and not removedServerGhostIds[key] then
                    local ok = pcall(function()
                        ghostDespawn:FireServer(key)
                    end)
                    if ok then
                        removedServerGhostIds[key] = tick()
                        State.serverGhostsRemoved = State.serverGhostsRemoved + 1
                    end
                end
            end
        end
    end
end

local function enforceCrashGuard()
    local root = currentRoot
    local characterRoot = getCharacterRoot()
    local active = State.crashGuard
        and State.swerveEnabled
        and root
        and characterRoot
        and trafficIsClose(root)

    State.crashGuardActive = active == true
    if not active then return end

    local now = tick()
    if now - lastCrashGuardWrite < 1 / 30 then return end
    lastCrashGuardWrite = now

    local stableSpeed = lastCharacterSpeed or characterRoot.Velocity.Magnitude
    if stableSpeed < 30 then return end

    local velocity = root.AssemblyLinearVelocity
    local guardLateralLimit = math.min(
        State.swerveLaneSpeed,
        SWERVE_MAX_LATERAL_SPEED
    )
    local lateral = clamp(
        velocity.X,
        -guardLateralLimit,
        guardLateralLimit
    )
    local forward = math.sqrt(math.max(0, stableSpeed * stableSpeed - lateral * lateral))
    local guardedVelocity = Vector3.new(lateral, 0, forward)

    pcall(function()
        characterRoot.Velocity = guardedVelocity
    end)
    State.crashGuardSpeed = stableSpeed
end

local function updateCharacterSpeedReference()
    local characterRoot = getCharacterRoot()
    if not characterRoot then
        lastCharacterSpeed = nil
        State.crashGuardSpeed = 0
        return
    end

    local speed = characterRoot.Velocity.Magnitude
    if not lastCharacterSpeed or math.abs(speed - lastCharacterSpeed) < 8 then
        lastCharacterSpeed = speed
        State.crashGuardSpeed = speed
    end
end

local function rebuildTrafficCache()
    collisionParts = {}
    collisionPartAddresses = {}
    collisionModels = {}
    collisionModelAddresses = {}
    ghostedTrafficParts = {}

    discoverTrafficModels()
    enforceTrafficGhosting()

    local remaining = 0
    for i = 1, #collisionParts do
        local part = collisionParts[i]
        if part then
            pcall(function()
                if part.CanCollide then remaining = remaining + 1 end
            end)
        end
    end

    State.trafficModels = #collisionModels
    State.trafficGhosted = #collisionParts
    State.trafficCollidable = remaining
    return #collisionModels, #collisionParts, remaining
end

local function disableTrafficCollisions()
    local _, parts = rebuildTrafficCache()
    return parts
end

local function getSwerveGui()
    local gui = player:FindFirstChild("PlayerGui")
    local purchase = gui and gui:FindFirstChild("PurchaseGUI")
    return purchase and purchase:FindFirstChild("HesiUI")
end

local guiObjectClasses = {
    Frame = true,
    ScrollingFrame = true,
    TextLabel = true,
    TextButton = true,
    TextBox = true,
    ImageLabel = true,
    ImageButton = true,
    VideoFrame = true,
    ViewportFrame = true,
}

local function retryIsOnScreen(retry)
    if not retry then return false end

    local node = retry
    while node do
        local className = node.ClassName
        if guiObjectClasses[className] then
            local visible = node.Visible
            if visible == false then return false end
        elseif className == "ScreenGui" and node.Enabled == false then
            return false
        end
        node = node.Parent
    end

    local position = retry.AbsolutePosition
    local size = retry.AbsoluteSize
    if not position or not size or size.X < 2 or size.Y < 2 then return false end

    local camera = game.Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize
    if not viewport then return true end

    local centerX = position.X + size.X * 0.5
    local centerY = position.Y + size.Y * 0.5
    return centerX >= 0 and centerX <= viewport.X
        and centerY >= 0 and centerY <= viewport.Y
end

local function clickRetryButton(retry)
    local position = retry.AbsolutePosition
    local size = retry.AbsoluteSize
    local mouse = player:GetMouse()
    local oldX = mouse and mouse.X
    local oldY = mouse and mouse.Y

    local ok = pcall(function()
        task.spawn(function()
            mousemoveabs(position.X + size.X * 0.5, position.Y + size.Y * 0.5)
            -- Give Roblox a frame to register hover before the down/up gesture.
            task.wait(0.06)
            mouse1press()
            task.wait(0.05)
            mouse1release()
            task.wait(0.04)
            if oldX and oldY then mousemoveabs(oldX, oldY) end
        end)
    end)
    return ok
end

local function clickSwerveRetry(force)
    if not (force or State.autoRetry) then return false end
    if State.payoutInProgress then return false end
    if retryPending then return false end
    if not force and not State.retryArmed then return false end
    if tick() - lastRetryClick < 0.90 then return false end

    local hesi = getSwerveGui()
    local retry = hesi and hesi:FindFirstChild("Retry")
    if not retryIsOnScreen(retry) then return false end
    if not clickRetryButton(retry) then return false end

    lastRetryClick = tick()
    retryPending = true
    retryRunId = retryRunId + 1
    local thisRetry = retryRunId
    State.retryPending = true
    State.retryState = "Retry click sent"
    State.retryAttempts = 1
    State.retryArmed = false
    State.retryReason = "restart pending"
    retryArmedUntil = 0
    State.enabled = true
    -- Never steer or accelerate a vehicle while Retry is rebuilding it.
    State.swerveEnabled = false
    swerveControlSuppressedUntil = tick() + 6
    swerveFaulted = false

    task.spawn(function()
        -- Matcha cannot read GuiObject.Visible. Completion is therefore based on
        -- the supported Fail BoolValue plus a stable occupied replacement root,
        -- never on the Retry button retaining an on-screen rectangle.
        task.wait(0.85)
        if _G.__CorsaBoostToken ~= token or retryRunId ~= thisRetry then return end

        local liveHesi = getSwerveGui()
        local failed = liveHesi and liveHesi:FindFirstChild("Fail")
        if failed and failed.Value == true then
            local liveRetry = liveHesi:FindFirstChild("Retry")
            if liveRetry and clickRetryButton(liveRetry) then
                State.retryAttempts = 2
                lastRetryClick = tick()
                task.wait(0.85)
            end
        end

        if _G.__CorsaBoostToken ~= token or retryRunId ~= thisRetry then return end
        State.retryState = "waiting for stable vehicle"

        local restarted = false
        local stableFrames = 0
        local settleDeadline = tick() + 4.0
        while _G.__CorsaBoostToken == token
            and retryRunId == thisRetry
            and tick() < settleDeadline do
            local car = getCar()
            local seat = car and findSeat(car)
            local root = car and findVehicleRoot(car)
            local stable = false
            if seat and root and playerIsInCar(seat) then
                local velocity = root.AssemblyLinearVelocity
                local currentHesi = getSwerveGui()
                local currentFail = currentHesi and currentHesi:FindFirstChild("Fail")
                local failActive = currentFail and currentFail.Value == true
                stable = root.Position.Y > -15
                    and root.CFrame.UpVector.Y > 0.60
                    and math.abs(velocity.Y) < 8
                    and not failActive
            end

            if stable then
                stableFrames = stableFrames + 1
                if stableFrames >= 3 then
                    currentCar = car
                    currentAddress = car.Address
                    currentSeat = seat
                    currentRoot = root
                    State.enabled = true
                    State.swerveEnabled = true
                    swerveControlSuppressedUntil = tick() + 1.25
                    if enterSwerveCourse(false) then
                        retryVerifyingMotion = true
                        State.retryState = "verifying forward motion"
                        local startZ = root.Position.Z
                        local motionDeadline = tick() + 2.75
                        while _G.__CorsaBoostToken == token
                            and retryRunId == thisRetry
                            and tick() < motionDeadline do
                            local liveVelocity = root.AssemblyLinearVelocity
                            if math.abs(liveVelocity.Z) > 12
                                or math.abs(root.Position.Z - startZ) > 2 then
                                restarted = true
                                break
                            end
                            task.wait(0.10)
                        end
                        retryVerifyingMotion = false
                        if restarted then break end

                        State.swerveEnabled = false
                        if State.retryAttempts < 2 then
                            local retryHesi = getSwerveGui()
                            local retryButton = retryHesi
                                and retryHesi:FindFirstChild("Retry")
                            if retryButton and clickRetryButton(retryButton) then
                                State.retryAttempts = 2
                                lastRetryClick = tick()
                                stableFrames = 0
                                settleDeadline = tick() + 4.0
                                State.retryState = "second Retry click sent"
                                task.wait(0.85)
                            else
                                break
                            end
                        else
                            break
                        end
                    else
                        State.swerveEnabled = false
                    end
                end
            else
                stableFrames = 0
            end
            task.wait(0.15)
        end

        retryPending = false
        retryVerifyingMotion = false
        State.retryPending = false
        retrySignalFrames = 0
        State.retrySignalFrames = 0
        retrySignalLatchedUntil = 0
        retryArmedUntil = 0
        retryDetectionSuppressedUntil = tick() + 4

        if restarted then
            State.retryCount = State.retryCount + 1
            State.retryState = "recovered"
            State.retryReason = "monitoring"
            Lib:Notify("Swerve", "Retry confirmed; vehicle settled and farm resumed", 3, "success")
        else
            State.swerveEnabled = false
            State.retryState = "Retry did not unlock motion"
            State.retryReason = "manual Retry/respawn required"
            Lib:Notify(
                "Swerve Retry",
                "Retry did not unlock forward motion after two attempts; autofarm remains paused",
                4,
                "warning"
            )
        end
    end)

    return true
end

_G.__CorsaRetrySwerve = function()
    return clickSwerveRetry(true)
end

local function readSwerveScore()
    local hesi = getSwerveGui()
    local score = hesi and hesi:FindFirstChild("Score")
    if not score then return 0 end
    return tonumber((tostring(score.Text):gsub("[^%d%-]", ""))) or 0
end

local function updateRetryArm()
    local score = readSwerveScore()
    local now = tick()
    if retryPending then
        State.retryArmed = false
        State.retryReason = "restart pending"
        return
    end
    if now < retryDetectionSuppressedUntil then
        lastObservedSwerveScore = score
        retryArmedUntil = 0
        State.retryArmed = false
        State.retryReason = "restart settling"
        return
    end
    if State.payoutInProgress then
        lastObservedSwerveScore = score
        retryArmedUntil = 0
        State.retryArmed = false
        State.retryReason = "2M payout"
        return
    end

    local hesi = getSwerveGui()
    local failed = hesi and hesi:FindFirstChild("Fail")
    local failPulse = failed and failed.Value == true
    local scoreCollapsed = lastObservedSwerveScore >= 5000 and score <= 250

    if failPulse or scoreCollapsed then
        retrySignalLatchedUntil = now + 1.5
    end

    local signalConfirmed = now < retrySignalLatchedUntil
    if signalConfirmed then
        retrySignalFrames = retrySignalFrames + 1
    else
        retrySignalFrames = 0
    end
    State.retrySignalFrames = retrySignalFrames
    local retryConfirmed = signalConfirmed and retrySignalFrames >= 3

    if retryConfirmed then
        retryArmedUntil = now + 2.0
        if failPulse then
            State.retryReason = "confirmed Fail signal"
        elseif scoreCollapsed then
            State.retryReason = "confirmed score reset"
        else
            State.retryReason = "confirmed game failure"
        end
    end

    if score > lastObservedSwerveScore then
        lastObservedSwerveScore = score
    end
    State.retryArmed = signalConfirmed and now < retryArmedUntil
    if not State.retryArmed then
        State.retryReason = "monitoring"
    end
end

local function cycleSwervePayout(force)
    if not State.swerveEnabled then return false end
    if not (force or State.autoPayout) then return false end
    if State.payoutInProgress then return false end
    if not force and readSwerveScore() < State.autoPayoutScore then return false end

    State.payoutInProgress = true
    task.spawn(function()
        local finalize = getSwerveRemote("SwerveFinalize")
        local scoreStop = getSwerveRemote("ScoreStop")
        local heliStop = getSwerveRemote("HeliStop")

        if finalize then
            pcall(function() finalize:FireServer("EndMinigame") end)
        end
        task.wait(0.12)
        if scoreStop then
            pcall(function() scoreStop:FireServer("EndRun") end)
        end
        if heliStop then
            pcall(function() heliStop:FireServer() end)
        end

        task.wait(0.75)
        local restarted = false
        for _ = 1, 6 do
            if _G.__CorsaBoostToken ~= token then return end
            if enterSwerveCourse(false) then
                restarted = true
                break
            end
            task.wait(0.50)
        end

        if restarted then
            State.payoutCycles = State.payoutCycles + 1
            Lib:Notify(
                "Swerve payout",
                "2,000,000-point run cashed out; next run started",
                3,
                "success"
            )
        else
            Lib:Notify(
                "Swerve payout",
                "Run cashed out; waiting for a valid driver seat to restart",
                4,
                "warning"
            )
        end
        State.payoutInProgress = false
    end)
    return true
end

_G.__CorsaCashOutSwerve = cycleSwervePayout

local function captureCar(car)
    restorePlayerWheels()
    playerWheelParts = {}
    currentCar = car
    currentAddress = car and car.Address
    currentSeat = nil
    currentRoot = nil

    if car then
        refreshFullTuneCatalog(car, true)
        applyTune(car, false)
        applyFullTuneOverrides(car)
        refreshFullTuneCatalog(car, false)
        currentSeat = findSeat(car)
        currentRoot = findVehicleRoot(car)
        local wheels = car:FindFirstChild("Wheels")
        if wheels then
            for _, wheel in ipairs(wheels:GetChildren()) do
                if isTrafficPart(wheel) then
                    playerWheelParts[#playerWheelParts + 1] = wheel
                end
            end
        end
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
    local mph = velocity and velocity.Magnitude * MPH_PER_STUD_PER_SECOND or 0
    return "Speed: " .. tostring(math.floor(mph + 0.5)) .. " MPH"
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

local fullTune = win:Tab("Full Tune", "sliders")
local powerTune = fullTune:Section(
    "Powertrain quick tune",
    "Left",
    "horsepower, torque, and RPM limits"
)

local function liveStatText(path, fallback)
    local stat = resolveStat(getCar(), path)
    return stat and safeTuneText(stat.Value) or tostring(fallback)
end

local powerInputs = {
    bhpLimit = liveStatText("bhpLimit", State.horsepowerLimit),
    peakTq = liveStatText("peakTq", 12000),
    redlineTq = liveStatText("redlineTq", 9000),
    idleTq = liveStatText("idleTq", 1200),
    peakTqRPM = liveStatText("peakTqRPM", 8000),
    redline = liveStatText("redline", 30000),
    shiftRPM = liveStatText("shiftRPM", 28000),
}

powerTune:Textbox("Horsepower limit", powerInputs.bhpLimit, function(v)
    powerInputs.bhpLimit = v
end, "Edits the car's bhpLimit value")
powerTune:Textbox("Peak torque", powerInputs.peakTq, function(v)
    powerInputs.peakTq = v
end)
powerTune:Textbox("Redline torque", powerInputs.redlineTq, function(v)
    powerInputs.redlineTq = v
end)
powerTune:Textbox("Idle torque", powerInputs.idleTq, function(v)
    powerInputs.idleTq = v
end)
powerTune:Textbox("Peak torque RPM", powerInputs.peakTqRPM, function(v)
    powerInputs.peakTqRPM = v
end)
powerTune:Textbox("Redline RPM", powerInputs.redline, function(v)
    powerInputs.redline = v
end)
powerTune:Textbox("Shift RPM", powerInputs.shiftRPM, function(v)
    powerInputs.shiftRPM = v
end)

powerTune:Button("Apply complete power tune", function()
    local fields = {
        { "bhpLimit", powerInputs.bhpLimit },
        { "peakTq", powerInputs.peakTq },
        { "redlineTq", powerInputs.redlineTq },
        { "idleTq", powerInputs.idleTq },
        { "peakTqRPM", powerInputs.peakTqRPM },
        { "redline", powerInputs.redline },
        { "shiftRPM", powerInputs.shiftRPM },
    }

    for _, field in ipairs(fields) do
        if tonumber(field[2]) == nil then
            Lib:Notify(
                "Power tune",
                tostring(field[1]) .. " needs a valid number",
                3,
                "error"
            )
            return
        end
    end
    if tonumber(powerInputs.bhpLimit) <= 0 then
        Lib:Notify("Power tune", "Horsepower must be above zero", 3, "error")
        return
    end

    local applied = 0
    for _, field in ipairs(fields) do
        if writeFullTuneStat(getCar(), field[1], field[2], true, false) then
            applied = applied + 1
        end
    end
    refreshFullTuneCatalog(getCar(), false)
    Lib:Notify(
        "Power tune",
        tostring(applied) .. "/" .. tostring(#fields)
            .. " power values applied and saved for respawn",
        4,
        applied == #fields and "success" or "warning"
    )
end)
powerTune:Info(
    "These limits are applied immediately. The game's drivetrain may need a vehicle respawn before every change is reflected."
)

local everyStat = fullTune:Section(
    "Every car stat",
    "Right",
    "search all values exposed by this vehicle"
)

refreshFullTuneCatalog(getCar(), false)
local initialFullTuneChoices = #fullTuneNames > 0
    and fullTuneNames or { "No car Stats folder detected" }

fullTuneDropdown = everyStat:Dropdown(
    "Search/select stat",
    fullTuneSelected and { fullTuneSelected } or {},
    initialFullTuneChoices,
    false,
    function(values)
        local selected = values and values[1]
        if selected and resolveStat(getCar(), selected) then
            selectFullTuneStat(selected)
        end
    end,
    "Search by stat name, then select one to edit",
    true
)

fullTuneValueBox = everyStat:Textbox(
    "Selected value",
    fullTunePendingValue,
    function(v)
        fullTunePendingValue = v
    end,
    "Numbers use ordinary decimal text; booleans accept true/false or 1/0"
)

everyStat:Button("Apply selected value", function()
    if not fullTuneSelected then
        Lib:Notify("Full tune", "Select a stat first", 3, "error")
        return
    end
    if writeFullTuneStat(
        getCar(),
        fullTuneSelected,
        fullTunePendingValue,
        true,
        true
    ) then
        selectFullTuneStat(fullTuneSelected)
    end
end)

everyStat:Button("Reload stat list and current value", function()
    local count = refreshFullTuneCatalog(getCar(), false)
    Lib:Notify(
        "Full tune",
        tostring(count) .. " editable values found on this car",
        3,
        count > 0 and "success" or "warning"
    )
end)

everyStat:Button("Restore selected session value", function()
    if restoreSelectedFullTuneStat() then
        Lib:Notify("Full tune", "Selected stat restored", 3, "success")
    else
        Lib:Notify("Full tune", "No session backup for that stat", 3, "error")
    end
end)

everyStat:Button("Restore all session values", function()
    local restored = restoreAllFullTuneStats()
    Lib:Notify(
        "Full tune",
        tostring(restored) .. " values restored; custom overrides cleared",
        4,
        restored > 0 and "success" or "warning"
    )
end)

everyStat:Label(function()
    return "Car stats: " .. tostring(State.fullTuneStatCount)
        .. " | staged overrides: " .. tostring(State.fullTuneOverrideCount)
end)
everyStat:Label(function()
    return "Selected: " .. tostring(State.fullTuneSelected)
        .. " [" .. tostring(State.fullTuneSelectedType) .. "]"
end)
everyStat:Info(
    "The list is generated from the current car, including drivetrain, gears, boost, tires, suspension, steering, brakes, weight, sounds, IDs, and model-specific settings."
)

local automation = win:Tab("Automation", "settings")
local swerve = automation:Section("Swerve autofarm", "Left", "safe-lane traffic phasing")

swerve:Toggle("Autofarm enabled", false, function(on)
    State.swerveEnabled = on
    if on then State.enabled = true end
    if not on and retryPending then
        retryRunId = retryRunId + 1
        retryPending = false
        State.retryPending = false
        State.retryState = "stopped"
    end
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
swerve:Slider("Farm target speed", 370, 10, 150, 370, " MPH", function(v)
    local target = math.min(v, SWERVE_MAX_MPH)
    State.swerveTargetMPH = target
    State.swerveSpeed = target / MPH_PER_STUD_PER_SECOND
end)
swerve:Slider("Acceleration", 150, 5, 30, 240, "", function(v)
    State.swerveAcceleration = v
end)
swerve:Slider("Lane centering speed", 5, 0.5, 3, 5, "", function(v)
    State.swerveLaneSpeed = math.min(v, SWERVE_MAX_LATERAL_SPEED)
end)
swerve:Slider("Lane centering brake", 36, 2, 18, 36, "", function(v)
    State.swerveLaneAcceleration = math.min(v, SWERVE_MAX_LATERAL_ACCELERATION)
end)
swerve:Divider("Legacy stable method (default)")
swerve:Toggle("Legacy light-tap scoring", true, function(on)
    State.microSwerveEnabled = on
    if not on then
        swerveMicroOffset = 0
        swerveMicroRecoverUntil = 0
        swerveMicroNeedsRecovery = false
        State.microSwervePhase = "legacy centered"
    end
end)
swerve:Info("The legacy controller changes velocity only. It is the default fallback and never writes the vehicle body's CFrame.")

swerve:Divider("Experimental ground rail")
groundLockToggle = swerve:Toggle("Use experimental soft lock", false, function(on)
    if on and currentRoot then
        local upY = currentRoot.CFrame.UpVector.Y
        local verticalSpeed = currentRoot.AssemblyLinearVelocity.Y
        if upY < 0.75 or math.abs(verticalSpeed) > 5 then
            State.groundTrackLock = false
            State.groundTrackStatus = "enable rejected: reset vehicle first"
            Lib:Notify(
                "Ground lock",
                "Vehicle is tilted or airborne; Retry/respawn before enabling",
                4,
                "error"
            )
            if groundLockToggle then
                pcall(function() groundLockToggle:Set(false) end)
            end
            return
        end
    end

    State.groundTrackLock = on
    swerveLane = math.max(2, math.min(3, swerveLane))
    swerveLaneSwitching = false
    State.laneSwitching = false
    swerveNextLaneSwitchAt = tick() + State.laneSwitchPause
    swerveMicroOffset = 0
    swerveMicroRecoverUntil = 0
    swerveMicroNeedsRecovery = false
    if on and currentRoot then
        swerveGroundY = currentRoot.Position.Y
        State.groundTrackHeight = swerveGroundY
        State.groundTrackCorrections = 0
        State.groundTrackHeightError = 0
        State.groundTrackVerticalSpeed = currentRoot.AssemblyLinearVelocity.Y
        State.groundTrackStatus = "soft velocity lock armed"
    else
        State.groundTrackStatus = "legacy"
        State.microSwervePhase = "legacy centered"
        swerveMicroNextAt = tick() + State.microSwervePause
    end
    Lib:Notify(
        "Swerve controller",
        on and "experimental ground rail enabled" or "legacy stable method restored",
        3,
        on and "warning" or "success"
    )
end)
swerve:Toggle("Alternate middle/right lanes", true, function(on)
    State.laneAlternation = on
    swerveLane = math.max(2, math.min(3, swerveLane))
    swerveLaneSwitching = false
    State.laneSwitching = false
    swerveNextLaneSwitchAt = tick() + State.laneSwitchPause
end)
swerve:Slider("Pause after each lane", 0.85, 0.05, 0.25, 2.5, "s", function(v)
    State.laneSwitchPause = v
end)
swerve:Slider("Lane transition speed", 5, 0.5, 3, 5, "", function(v)
    State.laneTransitionSpeed = math.min(v, SWERVE_MAX_LATERAL_SPEED)
end)
swerve:Slider("Lane transition brake", 30, 2, 12, 36, "", function(v)
    State.laneTransitionAcceleration = math.min(v, SWERVE_MAX_LATERAL_ACCELERATION)
end)
swerve:Slider("Height lock strength", 2.4, 0.1, 0.5, 4, "", function(v)
    State.groundTrackStrength = v
end)
swerve:Slider("Vertical damping", 0.85, 0.05, 0.2, 1.5, "", function(v)
    State.groundTrackDamping = v
end)
swerve:Slider("Maximum vertical speed", 2.5, 0.25, 1, 5, "", function(v)
    State.groundTrackMaxVerticalSpeed = v
end)
swerve:Info("Soft-lock mode never writes CFrame or position. It uses bounded vertical velocity, locks out lane 1, alternates middle/right, and automatically falls back to legacy if the car tilts, clips, or gains unsafe vertical speed.")
swerve:Button("Initialize from current position", function()
    _G.__CorsaStartSwerve()
end)
swerve:Button("Stop autofarm", function()
    _G.__CorsaStopSwerve()
end)
swerve:Button("Stabilize current lane", function()
    stabilizeSwerveCar(currentRoot)
end)
swerve:Toggle("Auto-click Retry", true, function(on)
    State.autoRetry = on
end)
swerve:Toggle("Auto cash-out at 2M", true, function(on)
    State.autoPayout = on
end)
swerve:Button("Cash out and restart now", function()
    local started = cycleSwervePayout(true)
    if not started then
        Lib:Notify("Swerve payout", "A payout cycle is already running", 2, "warning")
    end
end)
swerve:Toggle("Crash detector guard", true, function(on)
    State.crashGuard = on
    if not on then State.crashGuardActive = false end
end)
swerve:Toggle("Server crash-hitbox guard", true, function(on)
    State.serverGhostProtection = on
    if on and State.swerveEnabled then resetServerGhosts() end
end)
swerve:Slider("Server ghost cutoff", 350, 10, 100, 500, " studs", function(v)
    State.serverGhostCutoff = v
end)
swerve:Button("Click Retry now", function()
    if not clickSwerveRetry(true) then
        Lib:Notify("Swerve", "Retry screen is not active", 2, "warning")
    end
end)
swerve:Button("Reapply traffic ghosting", function()
    local models, parts, remaining = rebuildTrafficCache()
    Lib:Notify(
        "Swerve",
        tostring(models) .. " AI cars found; " .. tostring(parts)
            .. " parts held non-collidable; " .. tostring(remaining) .. " remaining",
        4,
        remaining == 0 and "success" or "warning"
    )
end)
swerve:Button("Reset server traffic ghosts", function()
    local ok = resetServerGhosts()
    Lib:Notify(
        "Swerve",
        ok and "Server traffic ghosts cleared" or "GhostReset remote was unavailable",
        3,
        ok and "success" or "warning"
    )
end)
swerve:Label(function()
    return "Target lane: " .. tostring(swerveLane)
        .. " | lane 1 permanently locked"
end)
swerve:Label(function()
    return State.leftRailGuardActive
        and ("LEFT RAIL RECOVERY | corrections: "
            .. tostring(State.leftRailCorrections))
        or ("Left-rail hard guard: armed | corrections: "
            .. tostring(State.leftRailCorrections))
end)
swerve:Label(function()
    local actual = currentRoot and currentRoot.AssemblyLinearVelocity.Magnitude
        * MPH_PER_STUD_PER_SECOND or 0
    return "Farm speed: " .. tostring(math.floor(actual + 0.5))
        .. " / " .. tostring(State.swerveTargetMPH) .. " MPH"
end)
swerve:Label(function()
    return (State.groundTrackLock and "Lane cycle: " or "Legacy taps: ")
        .. tostring(State.microSwervePhase)
        .. " | actions: " .. tostring(State.microSwerveCount)
end)
swerve:Label(function()
    if not State.groundTrackLock then
        return "Controller: legacy stable | soft lock: "
            .. tostring(State.groundTrackStatus)
            .. " | fallbacks: " .. tostring(State.groundTrackFallbacks)
    end
    return "Controller: EXPERIMENTAL soft rail"
        .. " | Y error: "
        .. tostring(math.floor(State.groundTrackHeightError * 100 + 0.5) / 100)
        .. " | Y speed: "
        .. tostring(math.floor(State.groundTrackVerticalSpeed * 100 + 0.5) / 100)
        .. " | corrections: " .. tostring(State.groundTrackCorrections)
end)
swerve:Label(function()
    if not State.swerveEnabled then return "Farm: stopped" end
    if not currentRoot then return "Farm: waiting for car" end
    if not State.enabled then return "Farm: master controller paused" end
    return "Farm: running"
end)
swerve:Label(function()
    return "AI traffic: " .. tostring(State.trafficModels) .. " cars | "
        .. tostring(State.trafficGhosted) .. " parts | "
        .. tostring(State.trafficCollidable) .. " collidable remaining"
end)
swerve:Label(function()
    return "AI hitboxes removed: " .. tostring(State.trafficProxiesDetached)
        .. " | player wheels: always solid"
end)
swerve:Label(function()
    local speed = math.floor((State.crashGuardSpeed or 0) * 10 + 0.5) / 10
    return State.crashGuardActive
        and ("Crash detector guard: ACTIVE at " .. tostring(speed))
        or ("Crash detector guard: armed | reference " .. tostring(speed))
end)
swerve:Label(function()
    return "Server crash ghosts removed: " .. tostring(State.serverGhostsRemoved)
        .. " | resets: " .. tostring(State.serverGhostResets)
        .. " | cutoff: " .. tostring(State.serverGhostCutoff)
end)
swerve:Label(function()
    local ahead = State.trafficAhead
    local nearest = ahead == math.huge and "clear" or (tostring(math.floor(ahead + 0.5)) .. " studs")
    return "Traffic: " .. tostring(State.trafficDetected)
        .. " tracked | target lane " .. nearest
        .. " | pre-physics ghosting active"
end)
swerve:Label(function()
    return "Retries recovered: " .. tostring(State.retryCount)
        .. " | " .. (State.retryArmed
            and ("ARMED: " .. tostring(State.retryReason))
            or tostring(State.retryState))
        .. (State.retryPending
            and (" | click attempt " .. tostring(State.retryAttempts)) or "")
end)
swerve:Label(function()
    local remaining = math.max(0, State.autoPayoutScore - readSwerveScore())
    return State.payoutInProgress
        and "2M payout: cashing out and restarting"
        or ("2M payout cycles: " .. tostring(State.payoutCycles)
            .. " | remaining: " .. tostring(remaining))
end)
swerve:Label(function()
    local hesi = getSwerveGui()
    local score = hesi and hesi:FindFirstChild("Score")
    return "Swerve score: " .. (score and tostring(score.Text) or "0")
end)

local idle = automation:Section("Anti-AFK", "Right", "one click every 19 minutes")
idle:Toggle("Anti-AFK enabled", true, function(on)
    State.antiAfk = on
    antiAfkNextAt = tick() + State.antiAfkInterval
    State.antiAfkNextIn = State.antiAfkInterval
    State.antiAfkStatus = on and "waiting" or "disabled"
end)
idle:Slider("Click interval", 19, 1, 5, 30, " min", function(v)
    State.antiAfkInterval = v * 60
    antiAfkNextAt = tick() + State.antiAfkInterval
    State.antiAfkNextIn = State.antiAfkInterval
end)
idle:Label(function()
    local minutes = math.floor((State.antiAfkNextIn or 0) / 60)
    local seconds = math.floor((State.antiAfkNextIn or 0) % 60)
    return "Next click: " .. tostring(minutes) .. "m " .. tostring(seconds)
        .. "s | clicks sent: " .. tostring(State.antiAfkClicks)
end)
idle:Info("Sends one normal mouse click every 19 minutes by default. It does not move the pointer or press a driving key.")
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
    if _G.__CorsaRestoreWheels then pcall(_G.__CorsaRestoreWheels) end
    if _G.__CorsaRestoreTrafficProxies then
        pcall(_G.__CorsaRestoreTrafficProxies)
    end
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
        local liveRoot = car and findVehicleRoot(car)
        local liveRootAddress = liveRoot and liveRoot.Address
        local cachedRootAddress = currentRoot and currentRoot.Address

        if address ~= currentAddress
            or liveRootAddress ~= cachedRootAddress then
            captureCar(car)
        end

        task.wait(car and 0.20 or 0.01)
    end
end)

task.spawn(function()
    while _G.__CorsaBoostToken == token do
        rebuildTrafficCache()
        task.wait(1.0)
    end
end)

task.spawn(function()
    while _G.__CorsaBoostToken == token do
        if State.autoPayout then cycleSwervePayout(false) end
        updateRetryArm()
        if State.autoRetry then clickSwerveRetry(false) end
        task.wait(0.08)
    end
end)

local runService = game:GetService("RunService")
local collisionStepped
local collisionHeartbeat

collisionStepped = runService.Stepped:Connect(function()
    if _G.__CorsaBoostToken ~= token then
        restorePlayerWheels()
        restoreTrafficProxies()
        collisionStepped:Disconnect()
        return
    end

    enforceTrafficGhosting()
    removeImminentServerGhosts()
    enforceCrashGuard()
end)

collisionHeartbeat = runService.Heartbeat:Connect(function()
    if _G.__CorsaBoostToken ~= token then
        restorePlayerWheels()
        collisionHeartbeat:Disconnect()
        return
    end

    -- The second pass catches anything the game's speed-based traffic toggle
    -- changed during the frame. The Stepped pass is the one that protects physics.
    enforceTrafficGhosting()
    updateCharacterSpeedReference()
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
    while _G.__CorsaBoostToken == token do
        local now = tick()
        if State.antiAfk then
            State.antiAfkNextIn = math.max(0, antiAfkNextAt - now)
            if now >= antiAfkNextAt then
                local ok = pcall(function() mouse1click() end)
                if ok then
                    State.antiAfkClicks = State.antiAfkClicks + 1
                    State.antiAfkStatus = "clicked"
                else
                    State.antiAfkStatus = "click unavailable"
                end
                antiAfkNextAt = tick() + State.antiAfkInterval
                State.antiAfkNextIn = State.antiAfkInterval
            end
        else
            antiAfkNextAt = now + State.antiAfkInterval
            State.antiAfkNextIn = State.antiAfkInterval
        end
        task.wait(1)
    end
end)

local existing = getCar()
if existing then captureCar(existing) end

task.spawn(function()
    local dt = 1 / 20

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

                if retryPending and not retryVerifyingMotion then
                    output = Vector3.new(
                        0,
                        clamp(velocity.Y, -3, State.maxRise),
                        velocity.Z
                    )
                    changed = true
                elseif State.swerveEnabled then
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
                    elseif State.avoidLeftRail
                        and position.X < swerveLeftBoundaryX then
                        swerveLane = 2
                        State.targetLane = 2
                        swerveLaneSwitching = false
                        State.laneSwitching = false
                        swerveMicroOffset = 0
                        swerveMicroNeedsRecovery = false
                        State.leftRailGuardActive = true
                        State.leftRailCorrections = State.leftRailCorrections + 1
                        State.microSwervePhase = "LEFT RAIL RECOVERY"
                        local emergencyX = clamp(
                            (swerveLanes[2] - position.X) * 2.5,
                            8,
                            14
                        )
                        local saferForward = math.min(State.swerveSpeed, 360)
                        local emergencyZ = velocity.Z + clamp(
                            saferForward - velocity.Z,
                            -State.swerveAcceleration * dt,
                            State.swerveAcceleration * dt
                        )
                        output = Vector3.new(
                            emergencyX,
                            clamp(velocity.Y, -3, State.maxRise),
                            emergencyZ
                        )
                        changed = true
                    elseif tick() < swerveControlSuppressedUntil then
                        -- During spawn/Retry settling, discard inherited lateral
                        -- motion and leave lane selection untouched. This is the
                        -- guard that prevents the instant launch toward lane 1.
                        output = Vector3.new(
                            0,
                            clamp(velocity.Y, -3, State.maxRise),
                            velocity.Z
                        )
                        State.microSwervePhase = "spawn settling"
                        State.leftRailGuardActive = false
                        changed = true
                    else
                        State.leftRailGuardActive = false
                        output = State.groundTrackLock
                            and buildExperimentalSwerveVelocity(root, velocity, dt)
                            or buildLegacySwerveVelocity(velocity, position, dt)
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

                local boosting = not retryPending and not State.swerveEnabled
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

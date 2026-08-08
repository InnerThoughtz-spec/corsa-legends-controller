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
local SWERVE_MAX_LATERAL_SPEED = 6
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
    swerveLaneSpeed = 6,
    swerveLaneAcceleration = 36,
    microSwerveEnabled = true,
    microSwerveWidth = 1.25,
    microSwerveHold = 0.15,
    microSwervePause = 1.00,
    microSwerveLateralSpeed = 3.0,
    microSwerveAcceleration = 18,
    microSwervePhase = "center",
    microSwerveCount = 0,
    avoidLeftRail = true,
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
    serverGhostCutoff = 100,
    serverGhostsRemoved = 0,
    serverGhostResets = 0,
    autoRetry = true,
    retryCount = 0,
    retryArmed = false,
    retryReason = "monitoring",
    autoPayout = true,
    autoPayoutScore = 2000000,
    payoutCycles = 0,
    payoutInProgress = false,

    antiAfk = true,
    antiAfkInterval = 55,
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
local lastRetryClick = 0
local lastObservedSwerveScore = 0
local retryArmedUntil = 0
local retryDetectionSuppressedUntil = 0

local win = Lib:CreateWindow({
    title = "Corsa Controller",
    subtitle = "stable chassis + Swerve v19",
    size = Vector2.new(720, 540),
    menuKey = "p",
    configName = "corsa-controller-v19",
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
    -- The center/right lanes keep the farm away from the trash-lined left rail.
    local detectedLane = nearestSwerveLane(root.Position.X)
    swerveLane = State.avoidLeftRail and math.max(2, detectedLane) or detectedLane
    State.targetLane = swerveLane
    swerveMicroOffset = 0
    swerveMicroDirection = 1
    swerveMicroReturnAt = 0
    swerveMicroNextAt = tick() + 0.60
    swerveMicroRecoverUntil = 0
    swerveMicroNeedsRecovery = false
    State.microSwervePhase = "center"
    State.microSwerveCount = 0
    swerveFaulted = false
    State.serverGhostsRemoved = 0
    resetServerGhosts()

    local scoreStart = getSwerveRemote("ScoreStart")
    if scoreStart then
        pcall(function() scoreStart:FireServer() end)
    end

    swerveCarAddress = car.Address
    retryArmedUntil = 0
    retryDetectionSuppressedUntil = tick() + 2.5
    lastObservedSwerveScore = 0
    State.retryArmed = false
    State.retryReason = "monitoring"
    if notifyUser then
        Lib:Notify("Swerve", "Autofarm initialized at the car's current position", 3, "success")
    end
    return true
end

local function stabilizeSwerveCar(root)
    if not root then return end
    local detectedLane = nearestSwerveLane(root.Position.X)
    swerveLane = State.avoidLeftRail and math.max(2, detectedLane) or detectedLane
    State.targetLane = swerveLane
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

    local position = root.Position
    for i = 1, #collisionModels do
        local car = collisionModels[i]
        local part = car and car.PrimaryPart
        if part then
            local ahead = part.Position.Z - position.Z
            local lateral = math.abs(part.Position.X - position.X)
            if ahead > -25
                and ahead <= State.serverGhostCutoff
                and lateral < 14 then
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

    local clicked = false
    local ok = pcall(function()
        mousemoveabs(position.X + size.X * 0.5, position.Y + size.Y * 0.5)
        mouse1click()
        clicked = true
        if oldX and oldY then mousemoveabs(oldX, oldY) end
    end)
    return ok and clicked
end

local function clickSwerveRetry(force)
    if not State.autoRetry then return false end
    if State.payoutInProgress then return false end
    if not force and tick() >= retryArmedUntil then return false end
    if tick() - lastRetryClick < 0.75 then return false end

    local hesi = getSwerveGui()
    local retry = hesi and hesi:FindFirstChild("Retry")
    if not retryIsOnScreen(retry) then return false end
    if not clickRetryButton(retry) then return false end

    lastRetryClick = tick()
    State.retryCount = State.retryCount + 1
    State.enabled = true
    State.swerveEnabled = true
    swerveFaulted = false

    task.delay(0.30, function()
        if _G.__CorsaBoostToken == token then
            enterSwerveCourse(false)
        end
    end)

    -- Some high-score Retry animations briefly swallow the first click.
    task.delay(0.18, function()
        if _G.__CorsaBoostToken == token and retryIsOnScreen(retry) then
            clickRetryButton(retry)
        end
    end)

    Lib:Notify("Swerve", "Retry clicked; autofarm resumed", 2, "success")
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
    if tick() < retryDetectionSuppressedUntil then
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
        retryArmedUntil = tick() + 2.5
        State.retryReason = failPulse and "Fail signal" or "score reset detected"
    end

    if score > lastObservedSwerveScore then
        lastObservedSwerveScore = score
    end
    State.retryArmed = tick() < retryArmedUntil
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
        applyTune(car, false)
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

local automation = win:Tab("Automation", "settings")
local swerve = automation:Section("Swerve autofarm", "Left", "safe-lane traffic phasing")

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
swerve:Slider("Farm target speed", 370, 10, 150, 370, " MPH", function(v)
    local target = math.min(v, SWERVE_MAX_MPH)
    State.swerveTargetMPH = target
    State.swerveSpeed = target / MPH_PER_STUD_PER_SECOND
end)
swerve:Slider("Acceleration", 150, 5, 30, 240, "", function(v)
    State.swerveAcceleration = v
end)
swerve:Slider("Lane centering speed", 6, 0.5, 3, 6, "", function(v)
    State.swerveLaneSpeed = math.min(v, SWERVE_MAX_LATERAL_SPEED)
end)
swerve:Slider("Lane centering brake", 36, 2, 18, 36, "", function(v)
    State.swerveLaneAcceleration = math.min(v, SWERVE_MAX_LATERAL_ACCELERATION)
end)
swerve:Toggle("Avoid left guard rail", true, function(on)
    State.avoidLeftRail = on
    if on and swerveLane < 2 then swerveLane = 2 end
    State.targetLane = swerveLane
end)
swerve:Toggle("Micro-swerve taps", true, function(on)
    State.microSwerveEnabled = on
    if not on then
        swerveMicroOffset = 0
        swerveMicroRecoverUntil = 0
        swerveMicroNeedsRecovery = false
        State.microSwervePhase = "center"
    end
end)
swerve:Slider("Light tap width", 1.25, 0.25, 0.5, 1.75, " studs", function(v)
    State.microSwerveWidth = math.min(v, MICRO_SWERVE_MAX_WIDTH)
end)
swerve:Slider("Light tap hold", 0.15, 0.01, 0.08, 0.18, "s", function(v)
    State.microSwerveHold = math.min(v, MICRO_SWERVE_MAX_HOLD)
end)
swerve:Slider("Tap strength", 3.0, 0.25, 1.5, 4.0, "", function(v)
    State.microSwerveLateralSpeed = math.min(v, 4.0)
end)
swerve:Slider("Time between taps", 1.00, 0.05, 0.60, 2.0, "s", function(v)
    State.microSwervePause = v
end)
swerve:Info("Light-tap mode adds a brief, low-strength A/D nudge and eases back to lane center. It never performs a full lane change.")
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
swerve:Slider("Server ghost cutoff", 100, 5, 60, 160, " studs", function(v)
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
        .. (State.avoidLeftRail and " | left rail locked out" or "")
end)
swerve:Label(function()
    local actual = currentRoot and currentRoot.AssemblyLinearVelocity.Magnitude
        * MPH_PER_STUD_PER_SECOND or 0
    return "Farm speed: " .. tostring(math.floor(actual + 0.5))
        .. " / " .. tostring(State.swerveTargetMPH) .. " MPH"
end)
swerve:Label(function()
    return "Micro-swerve: " .. tostring(State.microSwervePhase)
        .. " | taps: " .. tostring(State.microSwerveCount)
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
            or "watching score + Fail")
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
                        local laneGap = math.min(
                            swerveLanes[2] - swerveLanes[1],
                            swerveLanes[3] - swerveLanes[2]
                        )
                        local safeMargin = math.max(2, laneGap * 0.22)
                        local safeLeft = State.avoidLeftRail
                            and (swerveLanes[1] - 1.5)
                            or (swerveLanes[1] - safeMargin)
                        local safeRight = swerveLanes[3] + safeMargin

                        local microOffset = updateMicroSwerve()
                        local lightTapActive = microOffset ~= 0
                            or swerveMicroNeedsRecovery
                        local lateralAcceleration = lightTapActive
                            and State.microSwerveAcceleration
                            or math.min(
                                State.swerveLaneAcceleration,
                                SWERVE_MAX_LATERAL_ACCELERATION
                            )
                        local lateralSpeedLimit = lightTapActive
                            and math.min(State.microSwerveLateralSpeed, 4)
                            or math.min(
                                State.swerveLaneSpeed,
                                SWERVE_MAX_LATERAL_SPEED
                            )
                        local laneCenterX = swerveLanes[swerveLane]
                        local targetX = clamp(
                            laneCenterX + microOffset,
                            safeLeft,
                            safeRight
                        )
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
                        local newX = output.X + clamp(
                            desiredX - output.X,
                            -lateralStep,
                            lateralStep
                        )
                        newX = clamp(newX, -lateralSpeedLimit, lateralSpeedLimit)

                        -- Never let a leftward velocity carry the car into the
                        -- trash-lined guard rail. From lane 1, always recover right.
                        if State.avoidLeftRail then
                            if position.X <= swerveLanes[1] - 1.5 then
                                newX = math.max(newX, 5)
                            elseif position.X <= swerveLanes[1] + 2 then
                                newX = math.max(newX, 2.5)
                            end
                        end

                        if microOffset == 0
                            and math.abs(position.X - laneCenterX) < 0.25
                            and math.abs(newX) < 0.50 then
                            swerveMicroNeedsRecovery = false
                        end
                        local newZ = output.Z + clamp(
                            State.swerveSpeed - output.Z,
                            -State.swerveAcceleration * dt,
                            State.swerveAcceleration * dt
                        )
                        local newY = clamp(output.Y, -3, State.maxRise)
                        output = Vector3.new(newX, newY, newZ)

                        -- The game fails Swerve when speed changes by 10 or more
                        -- in one frame. Keep every controller correction below it.
                        local velocityDelta = output - velocity
                        if velocityDelta.Magnitude > 7.5 then
                            output = velocity + velocityDelta.Unit * 7.5
                        end
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

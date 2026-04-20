local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

local TOGGLE_KEY = Enum.KeyCode.LeftAlt
local SIMPLE_BAT_KEY = Enum.KeyCode.Period
local GROUND_MODE_KEY = Enum.KeyCode.LeftShift
local PANIC_MODE_KEY = Enum.KeyCode.Backquote
local FAST_KEY = Enum.KeyCode.Space

local AUTO_START_ON_RESPAWN = true

local NORMAL_SPEED = 110
local FAST_SPEED = 600
local SUPER_FAST_SPEED = 2000
local SUPER_FAST_HOLD_TIME = 5

local SIMPLE_FAST_SPEED = 500
local SIMPLE_SUPER_FAST_SPEED = 1800
local SIMPLE_SUPER_FAST_HOLD_TIME = 5

local EXIT_FORWARD_GLIDE = 0
local EXIT_UPWARD_GLIDE = 0
local EXIT_RECOVER_NOCLIP_TIME = 0.03
local EXIT_RECOVER_ANCHOR_TIME = 0.02

local CAMERA_SENSITIVITY = 0.0025
local MAX_PITCH = math.rad(85)
local DOUBLE_TAP_TIME = 0.35

local CAMERA_BIND_NAME = "BatStyleObserverCamera"
local SIMPLE_CAMERA_BIND_NAME = "SimpleBatCamera"
local CAST_BIND_PRIORITY = Enum.ContextActionPriority.High.Value + 100

local BELOW_CAMERA_OFFSET = 90
local NORMAL_SAFE_PARK_Y = 50000
local PANIC_SAFE_PARK_Y = 4.999999721059845e+27
local GROUND_MODE_FIXED_Y = 623
local SPAWN_STABILIZE_TIME = 0.2
local SPAWN_TELEPORT_RELEASE_DELAY = 0.03
local SPAWN_POST_TELEPORT_CAMERA_DELAY = 0.05
local SPAWN_SAFE_Y = 50000
local EXIT_RELEASE_DELAY = 0

local POSITION_REFRESH_INTERVAL = 0.08
local MIN_MOVE_DISTANCE = 4
local MAX_TELEPORT_STEP = 16

local OVERHEAD_CHECK_DISTANCE = 24
local SIDE_CHECK_DISTANCE = 10
local MIN_SIDE_HITS = 2
local EXPOSURE_CHECK_DISTANCE = 30
local MAX_VISIBLE_RAYS = 1
local DOWNWARD_GROUND_CHECK = 16
local UPWARD_SAMPLE_EXTRA = 2
local MULTI_HEIGHT_OFFSETS = {1, 3, 5}

local GROUND_MODE_MAX_RAY_UP = 400
local GROUND_MODE_MAX_RAY_DOWN = 2500

local DANGER_SPEED_THRESHOLD = 140
local DANGER_DISTANCE_THRESHOLD = 90
local DANGER_LOOKAHEAD_TIME = 0.45
local DANGER_CLOSE_DISTANCE = 20
local DANGER_DOT_THRESHOLD = 0.55

local EXIT_PROBE_UP = 8
local EXIT_PROBE_DOWN = 28
local EXIT_FORWARD_OFFSET = 2.5
local EXIT_GROUND_CLEARANCE = 1.5
local EXIT_WALL_CHECK_DISTANCE = 4

local COLOR_TOLERANCE = 16
local GROUND_GREEN_LOCK_TOLERANCE = 3

local CAST_BINDINGS = {
    { name = "BatStyleCastQ", input = Enum.KeyCode.Q },
    { name = "BatStyleCastThree", input = Enum.KeyCode.Three },
    { name = "BatStyleCastT", input = Enum.KeyCode.T },
    { name = "BatStyleCastV", input = Enum.KeyCode.V },
    { name = "BatStyleCastG", input = Enum.KeyCode.G },
    { name = "BatStyleCastTwo", input = Enum.KeyCode.Two },
    { name = "BatStyleCastZ", input = Enum.KeyCode.Z },
    { name = "BatStyleCastB", input = Enum.KeyCode.B },
    { name = "BatStyleCastMouse2", input = Enum.UserInputType.MouseButton2 },
    { name = "BatStyleCastOne", input = Enum.KeyCode.One },
    { name = "BatStyleCastE", input = Enum.KeyCode.E },
    { name = "BatStyleCastR", input = Enum.KeyCode.R },
    { name = "BatStyleCastF", input = Enum.KeyCode.F },
    { name = "BatStyleCastC", input = Enum.KeyCode.C },
}

local state = {
    active = false,
    groundMode = false,
    panicMode = false,
    transitioning = false,

    simpleBatActive = false,
    simpleTransitioning = false,

    freeCamPart = nil,
    simpleFreeCamPart = nil,
    castBindingsEnabled = false,

    savedCanCollide = {},

    camPosition = nil,
    camYaw = 0,
    camPitch = 0,

    simpleCamPosition = nil,
    simpleCamYaw = 0,
    simpleCamPitch = 0,

    originalCameraType = nil,
    originalCameraSubject = nil,
    originalMouseBehavior = nil,
    originalMouseIconEnabled = nil,

    originalWalkSpeed = nil,
    originalJumpPower = nil,
    originalAutoRotate = nil,
    originalPlatformStand = nil,

    simpleOriginalCameraType = nil,
    simpleOriginalCameraSubject = nil,
    simpleOriginalMouseBehavior = nil,
    simpleOriginalMouseIconEnabled = nil,
    simpleOriginalRootCFrame = nil,
    simpleOriginalRootPosition = nil,

    lastToggleTap = 0,
    lastSimpleTap = 0,
    refreshTimer = 0,
    boostHoldTime = 0,
    simpleBoostHoldTime = 0,

    targetPosition = nil,
    safeParkPosition = nil,

    lastHealth = nil,
    healthConn = nil,
    simpleLastHealth = nil,
    simpleHealthConn = nil,

    autoStartToken = 0,
    hasSeenFirstCharacter = false,
    pendingRespawnCameraCFrame = nil,
    pendingRespawnRestoreCamera = false,
    respawnFreefallActive = false,
    tabHeld = false,

    ui = {
        screenGui = nil,
        dot = nil,
        stroke = nil,
    },
}

local stopObserverMode
local stopSimpleBat

local function getCamera()
    return workspace.CurrentCamera
end

local function getCharacter()
    return player.Character or player.CharacterAdded:Wait()
end

local function getHumanoid(character)
    return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRoot(character)
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function waitForCharacterReady(timeout)
    local startTime = tick()

    while true do
        local character = player.Character
        local humanoid = getHumanoid(character)
        local root = getRoot(character)
        local camera = getCamera()

        if character and humanoid and root and camera then
            return character, humanoid, root, camera
        end

        if timeout and tick() - startTime >= timeout then
            return nil, nil, nil, nil
        end

        task.wait()
    end
end

local function flattenLookVector(look)
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude <= 0.001 then
        return Vector3.new(0, 0, -1)
    end
    return flatLook.Unit
end

local function uprightCFrameFromPositionAndLook(position, look)
    local flatLook = flattenLookVector(look)
    return CFrame.new(position, position + flatLook)
end

local function uprightFromCFrame(cf, positionOverride)
    local pos = positionOverride or cf.Position
    return uprightCFrameFromPositionAndLook(pos, cf.LookVector)
end

local function ensureStatusUI()
    if state.ui.screenGui and state.ui.screenGui.Parent then
        return
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BatStyleObserverStatus"
    screenGui.ResetOnSpawn = false
    screenGui.Enabled = false

    local ok = pcall(function()
        screenGui.Parent = CoreGui
    end)
    if not ok then
        screenGui.Parent = player:WaitForChild("PlayerGui")
    end

    local dot = Instance.new("Frame")
    dot.Name = "ModeDot"
    dot.Size = UDim2.new(0, 10, 0, 10)
    dot.AnchorPoint = Vector2.new(0.5, 1)
    dot.Position = UDim2.new(0.5, 0, 1, -30)
    dot.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    dot.BorderSizePixel = 0
    dot.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = dot

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Transparency = 0.2
    stroke.Parent = dot

    state.ui.screenGui = screenGui
    state.ui.dot = dot
    state.ui.stroke = stroke
end


local function setStatusUIVisible(visible)
    ensureStatusUI()
    if state.ui.screenGui then
        state.ui.screenGui.Enabled = visible
    end
end

local function refreshStatusUIVisibility()
    setStatusUIVisible(state.active or state.simpleBatActive)
end

local function setStatusDotColorByPosition(character)
    ensureStatusUI()
    refreshStatusUIVisibility()

    if not state.ui.dot or not (state.active or state.simpleBatActive) then
        return
    end

    local root = getRoot(character)
    if not root then
        return
    end

    local y = root.Position.Y

    if state.groundMode then
        if math.abs(y - GROUND_MODE_FIXED_Y) <= GROUND_GREEN_LOCK_TOLERANCE then
            state.ui.dot.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        else
            state.ui.dot.BackgroundColor3 = Color3.fromRGB(120, 255, 120)
        end
        return
    end

    if math.abs(y - PANIC_SAFE_PARK_Y) <= COLOR_TOLERANCE then
        state.ui.dot.BackgroundColor3 = Color3.fromRGB(170, 0, 255)
        return
    end

    if math.abs(y - NORMAL_SAFE_PARK_Y) <= COLOR_TOLERANCE then
        state.ui.dot.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        return
    end

    if state.simpleBatActive then
        state.ui.dot.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
        return
    end

    if state.active then
        state.ui.dot.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        return
    end
end

local function getObserverCFrame()
    return CFrame.new(state.camPosition)
        * CFrame.Angles(0, state.camYaw, 0)
        * CFrame.Angles(state.camPitch, 0, 0)
end

local function getSimpleObserverCFrame()
    return CFrame.new(state.simpleCamPosition)
        * CFrame.Angles(0, state.simpleCamYaw, 0)
        * CFrame.Angles(state.simpleCamPitch, 0, 0)
end

local function ensureFreeCam(camera)
    if state.freeCamPart and state.freeCamPart.Parent then
        return state.freeCamPart
    end

    local freeCamPart = Instance.new("Part")
    freeCamPart.Name = "BatStyleObserverCam"
    freeCamPart.Anchored = true
    freeCamPart.CanCollide = false
    freeCamPart.CanTouch = false
    freeCamPart.CanQuery = false
    freeCamPart.Transparency = 1
    freeCamPart.Size = Vector3.new(1, 1, 1)
    freeCamPart.CFrame = camera.CFrame
    freeCamPart.Parent = workspace

    local pitch, yaw = camera.CFrame:ToOrientation()
    state.camPosition = freeCamPart.Position
    state.camYaw = yaw
    state.camPitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
    state.freeCamPart = freeCamPart

    return freeCamPart
end

local function ensureSimpleFreeCam(camera)
    if state.simpleFreeCamPart and state.simpleFreeCamPart.Parent then
        return state.simpleFreeCamPart
    end

    local freeCamPart = Instance.new("Part")
    freeCamPart.Name = "SimpleBatCam"
    freeCamPart.Anchored = true
    freeCamPart.CanCollide = false
    freeCamPart.CanTouch = false
    freeCamPart.CanQuery = false
    freeCamPart.Transparency = 1
    freeCamPart.Size = Vector3.new(1, 1, 1)
    freeCamPart.CFrame = camera.CFrame
    freeCamPart.Parent = workspace

    local pitch, yaw = camera.CFrame:ToOrientation()
    state.simpleCamPosition = freeCamPart.Position
    state.simpleCamYaw = yaw
    state.simpleCamPitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
    state.simpleFreeCamPart = freeCamPart

    return freeCamPart
end

local function saveMovementState(humanoid)
    state.originalWalkSpeed = humanoid.WalkSpeed
    state.originalJumpPower = humanoid.JumpPower
    state.originalAutoRotate = humanoid.AutoRotate
    state.originalPlatformStand = humanoid.PlatformStand
end

local function restoreMovementState(humanoid)
    if not humanoid then
        return
    end

    if state.originalWalkSpeed ~= nil then
        humanoid.WalkSpeed = state.originalWalkSpeed
    end
    if state.originalJumpPower ~= nil then
        humanoid.JumpPower = state.originalJumpPower
    end
    humanoid.AutoRotate = state.originalAutoRotate == nil and true or state.originalAutoRotate
    humanoid.PlatformStand = state.originalPlatformStand == nil and false or state.originalPlatformStand
end

local function zeroRootVelocities(root)
    if not root then
        return
    end
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end



local function plainReleaseHumanoid(humanoid, root)
    if not humanoid or not root then
        return
    end

    root.Anchored = false
    zeroRootVelocities(root)
    humanoid.PlatformStand = false
    humanoid.Sit = false
    humanoid.AutoRotate = true
    humanoid:Move(Vector3.zero, false)
end

local function instantReleaseHumanoid(humanoid, root, targetCFrame)
    if not humanoid or not root then
        return
    end

    local finalCFrame = targetCFrame and uprightFromCFrame(targetCFrame) or uprightFromCFrame(root.CFrame)
    local originalAnchored = root.Anchored

    root.Anchored = true
    root.CFrame = finalCFrame
    zeroRootVelocities(root)

    humanoid.PlatformStand = false
    humanoid.Sit = false
    humanoid.AutoRotate = true
    humanoid:Move(Vector3.zero, false)

    if EXIT_RELEASE_DELAY <= 0 then
        root.Anchored = originalAnchored
        zeroRootVelocities(root)
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end)
        return
    end

    task.delay(EXIT_RELEASE_DELAY, function()
        if humanoid.Parent and root.Parent then
            root.Anchored = originalAnchored
            zeroRootVelocities(root)
            humanoid.PlatformStand = false
            humanoid.Sit = false
            humanoid.AutoRotate = true
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Running)
            end)
        end
    end)
end

local function syncSimpleCameraFromObserver()
    if not state.camPosition then
        return
    end

    state.simpleCamPosition = state.camPosition
    state.simpleCamYaw = state.camYaw
    state.simpleCamPitch = state.camPitch

    if state.simpleFreeCamPart then
        state.simpleFreeCamPart.CFrame = getObserverCFrame()
    end
end

local function syncObserverCameraFromSimple()
    if not state.simpleCamPosition then
        return
    end

    state.camPosition = state.simpleCamPosition
    state.camYaw = state.simpleCamYaw
    state.camPitch = state.simpleCamPitch

    if state.freeCamPart then
        state.freeCamPart.CFrame = getObserverCFrame()
    end
end

local function getCurrentSharedCameraCFrame()
    if state.active and state.camPosition then
        return getObserverCFrame()
    end
    if state.simpleBatActive and state.simpleCamPosition then
        return getSimpleObserverCFrame()
    end
    local camera = getCamera()
    return camera and camera.CFrame or nil
end


local function stopAllModesAtCurrentCamera()
    local sharedCamera = getCurrentSharedCameraCFrame()
    local character = player.Character
    local root = getRoot(character)
    local humanoid = getHumanoid(character)

    if sharedCamera and root then
        root.CFrame = uprightFromCFrame(sharedCamera, sharedCamera.Position)
        zeroRootVelocities(root)
    end

    if state.active then
        stopObserverMode(true, true)
    elseif state.simpleBatActive then
        stopSimpleBat()
    end

    if not state.active and state.simpleBatActive then
        stopSimpleBat()
    end

    character = player.Character
    root = getRoot(character)
    humanoid = getHumanoid(character)

    if sharedCamera and root then
        root.CFrame = uprightFromCFrame(sharedCamera, sharedCamera.Position)
        zeroRootVelocities(root)
    end

    if humanoid and root then
        plainReleaseHumanoid(humanoid, root)
    end

    if not state.active and not state.simpleBatActive then
        refreshStatusUIVisibility()
    end
end

local function hardRecoverHumanoid(humanoid, root, faceCFrame)
    if not humanoid or not root then
        return
    end

    local targetCFrame = faceCFrame and uprightFromCFrame(faceCFrame) or uprightFromCFrame(root.CFrame)
    local originalAnchored = root.Anchored

    humanoid.PlatformStand = false
    humanoid.Sit = false
    humanoid.AutoRotate = true
    humanoid:Move(Vector3.zero, false)

    root.Anchored = true
    root.CFrame = targetCFrame
    zeroRootVelocities(root)

    pcall(function()
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)

    task.delay(EXIT_RECOVER_ANCHOR_TIME, function()
        if humanoid.Parent and root.Parent then
            root.CFrame = targetCFrame
            zeroRootVelocities(root)
            humanoid.PlatformStand = false
            humanoid.Sit = false
            humanoid.AutoRotate = true
            humanoid:Move(Vector3.zero, false)
            root.Anchored = originalAnchored
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Running)
            end)
        end
    end)

    task.delay(0.12, function()
        if humanoid.Parent and root.Parent then
            root.CFrame = uprightFromCFrame(root.CFrame)
            zeroRootVelocities(root)
            humanoid.PlatformStand = false
            humanoid.Sit = false
            humanoid.AutoRotate = true
            humanoid:Move(Vector3.zero, false)
        end
    end)

    task.delay(0.22, function()
        if humanoid.Parent and root.Parent then
            root.CFrame = uprightFromCFrame(root.CFrame)
            zeroRootVelocities(root)
            humanoid.PlatformStand = false
            humanoid.Sit = false
            humanoid.AutoRotate = true
        end
    end)
end

local function castActionHandler()
    return Enum.ContextActionResult.Pass
end

local function setCastBindingsEnabled(enabled)
    if enabled == state.castBindingsEnabled then
        return
    end

    state.castBindingsEnabled = enabled

    for _, binding in ipairs(CAST_BINDINGS) do
        if enabled then
            ContextActionService:BindActionAtPriority(
                binding.name,
                castActionHandler,
                false,
                CAST_BIND_PRIORITY,
                binding.input
            )
        else
            ContextActionService:UnbindAction(binding.name)
        end
    end
end

local function getFlatDistance(a, b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function stepTowards(current, goal, maxStep)
    local delta = goal - current
    local distance = delta.Magnitude
    if distance <= maxStep or distance <= 0.001 then
        return goal
    end
    return current + delta.Unit * maxStep
end

local function moveRootTo(root, position)
    root.CFrame = CFrame.new(position)
    zeroRootVelocities(root)
end

local function moveRootToward(root, goalPosition, stepDistance)
    local current = root.Position
    local nextPosition = stepTowards(current, goalPosition, stepDistance)
    moveRootTo(root, nextPosition)
end

local function saveCollisionState(character)
    table.clear(state.savedCanCollide)
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            state.savedCanCollide[descendant] = descendant.CanCollide
        end
    end
end

local function setCharacterNoClip(character, enabled)
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if enabled then
                descendant.CanCollide = false
            else
                local original = state.savedCanCollide[descendant]
                if original == nil then
                    descendant.CanCollide = true
                else
                    descendant.CanCollide = original
                end
            end
        end
    end
end

local function makeRayParams(character)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local exclude = {character}
    if state.freeCamPart then
        table.insert(exclude, state.freeCamPart)
    end
    if state.simpleFreeCamPart then
        table.insert(exclude, state.simpleFreeCamPart)
    end

    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = true
    return params
end

local function getSamplePoint(position, root, extraY)
    local halfHeight = math.max(root.Size.Y * 0.5, 2.5)
    return position + Vector3.new(0, halfHeight + (extraY or 0), 0)
end

local function hasGroundSupport(character, position)
    local root = getRoot(character)
    if not root then
        return false
    end

    local params = makeRayParams(character)
    local samplePoint = position + Vector3.new(0, 2, 0)
    return workspace:Raycast(samplePoint, Vector3.new(0, -DOWNWARD_GROUND_CHECK, 0), params) ~= nil
end

local function hasOverheadCover(character, position)
    local root = getRoot(character)
    if not root then
        return false
    end

    local params = makeRayParams(character)
    for _, extraY in ipairs(MULTI_HEIGHT_OFFSETS) do
        local samplePoint = getSamplePoint(position, root, extraY + UPWARD_SAMPLE_EXTRA)
        if not workspace:Raycast(samplePoint, Vector3.new(0, OVERHEAD_CHECK_DISTANCE, 0), params) then
            return false
        end
    end

    return true
end

local function getSideHits(character, position)
    local root = getRoot(character)
    if not root then
        return 0
    end

    local params = makeRayParams(character)
    local directions = {
        Vector3.new(1, 0, 0),
        Vector3.new(-1, 0, 0),
        Vector3.new(0, 0, 1),
        Vector3.new(0, 0, -1),
    }

    local bestHits = 0

    for _, extraY in ipairs(MULTI_HEIGHT_OFFSETS) do
        local samplePoint = getSamplePoint(position, root, extraY)
        local hits = 0
        for _, dir in ipairs(directions) do
            if workspace:Raycast(samplePoint, dir * SIDE_CHECK_DISTANCE, params) then
                hits += 1
            end
        end
        if hits > bestHits then
            bestHits = hits
        end
    end

    return bestHits
end

local function getVisibleRayCount(character, position)
    local root = getRoot(character)
    if not root then
        return math.huge
    end

    local params = makeRayParams(character)
    local offsets = {
        Vector3.new(EXPOSURE_CHECK_DISTANCE, 0, 0),
        Vector3.new(-EXPOSURE_CHECK_DISTANCE, 0, 0),
        Vector3.new(0, 0, EXPOSURE_CHECK_DISTANCE),
        Vector3.new(0, 0, -EXPOSURE_CHECK_DISTANCE),
        Vector3.new(EXPOSURE_CHECK_DISTANCE, 8, EXPOSURE_CHECK_DISTANCE),
        Vector3.new(-EXPOSURE_CHECK_DISTANCE, 8, EXPOSURE_CHECK_DISTANCE),
        Vector3.new(EXPOSURE_CHECK_DISTANCE, 8, -EXPOSURE_CHECK_DISTANCE),
        Vector3.new(-EXPOSURE_CHECK_DISTANCE, 8, -EXPOSURE_CHECK_DISTANCE),
        Vector3.new(EXPOSURE_CHECK_DISTANCE, 14, 0),
        Vector3.new(-EXPOSURE_CHECK_DISTANCE, 14, 0),
        Vector3.new(0, 14, EXPOSURE_CHECK_DISTANCE),
        Vector3.new(0, 14, -EXPOSURE_CHECK_DISTANCE),
    }

    local worstVisibleCount = 0

    for _, extraY in ipairs(MULTI_HEIGHT_OFFSETS) do
        local target = getSamplePoint(position, root, extraY)
        local visibleCount = 0
        for _, offset in ipairs(offsets) do
            local origin = target + offset
            local direction = target - origin
            local result = workspace:Raycast(origin, direction, params)

            if not result then
                visibleCount += 1
            else
                local distanceToTarget = (result.Position - target).Magnitude
                if distanceToTarget <= 1.5 then
                    visibleCount += 1
                end
            end

            if visibleCount > MAX_VISIBLE_RAYS then
                return visibleCount
            end
        end
        if visibleCount > worstVisibleCount then
            worstVisibleCount = visibleCount
        end
    end

    return worstVisibleCount
end

local function isPositionCovered(character, position)
    return hasGroundSupport(character, position)
        and hasOverheadCover(character, position)
        and getSideHits(character, position) >= MIN_SIDE_HITS
        and getVisibleRayCount(character, position) <= MAX_VISIBLE_RAYS
end

local function isGroundModePositionUsable(character, position)
    local params = makeRayParams(character)
    local upHit = workspace:Raycast(position, Vector3.new(0, GROUND_MODE_MAX_RAY_UP, 0), params)
    if not upHit then
        return false
    end

    local downHit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -GROUND_MODE_MAX_RAY_DOWN, 0), params)
    return downHit ~= nil
end

local function getDesiredHiddenPosition()
    return state.camPosition + Vector3.new(0, -BELOW_CAMERA_OFFSET, 0)
end

local function setNormalSafePark(character)
    local root = getRoot(character)
    if not root or not state.camPosition then
        return
    end

    state.panicMode = false
    state.safeParkPosition = Vector3.new(state.camPosition.X, NORMAL_SAFE_PARK_Y, state.camPosition.Z)
    state.targetPosition = state.safeParkPosition
    moveRootTo(root, state.targetPosition)
end

local function setPanicSafePark(character)
    local root = getRoot(character)
    if not root or not state.camPosition then
        return
    end

    state.panicMode = true
    state.groundMode = false
    state.safeParkPosition = Vector3.new(state.camPosition.X, PANIC_SAFE_PARK_Y, state.camPosition.Z)
    state.targetPosition = state.safeParkPosition
    moveRootTo(root, state.targetPosition)
end

local function getCurrentFlightSpeed(deltaTime)
    if UserInputService:IsKeyDown(FAST_KEY) then
        state.boostHoldTime = math.min(state.boostHoldTime + deltaTime, SUPER_FAST_HOLD_TIME)
        local alpha = state.boostHoldTime / SUPER_FAST_HOLD_TIME
        local eased = alpha * alpha * (3 - 2 * alpha)
        return FAST_SPEED + (SUPER_FAST_SPEED - FAST_SPEED) * eased
    end

    state.boostHoldTime = 0
    return NORMAL_SPEED
end

local function getSimpleFlightSpeed(deltaTime)
    if UserInputService:IsKeyDown(FAST_KEY) then
        state.simpleBoostHoldTime = math.min(state.simpleBoostHoldTime + deltaTime, SIMPLE_SUPER_FAST_HOLD_TIME)
        local alpha = state.simpleBoostHoldTime / SIMPLE_SUPER_FAST_HOLD_TIME
        local eased = alpha * alpha * (3 - 2 * alpha)
        return SIMPLE_FAST_SPEED + (SIMPLE_SUPER_FAST_SPEED - SIMPLE_FAST_SPEED) * eased
    end

    state.simpleBoostHoldTime = 0
    return NORMAL_SPEED
end

local function isIncomingDanger(character)
    local myRoot = getRoot(character)
    if not myRoot then
        return false
    end

    local myPos = myRoot.Position

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            local otherRoot = getRoot(otherPlayer.Character)
            if otherRoot then
                local velocity = otherRoot.AssemblyLinearVelocity
                local speed = velocity.Magnitude
                if speed >= DANGER_SPEED_THRESHOLD then
                    local offset = myPos - otherRoot.Position
                    local distance = offset.Magnitude
                    if distance <= DANGER_DISTANCE_THRESHOLD and distance > 0.001 then
                        local directionToMe = offset.Unit
                        local velocityDir = velocity.Unit
                        local approachDot = velocityDir:Dot(directionToMe)
                        if approachDot >= DANGER_DOT_THRESHOLD then
                            local predictedPos = otherRoot.Position + velocity * DANGER_LOOKAHEAD_TIME
                            if (myPos - predictedPos).Magnitude <= DANGER_CLOSE_DISTANCE then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end


local function destroyLocalEffects()
    pcall(function()
        local playerScripts = player:FindFirstChild("PlayerScripts")
        if playerScripts and playerScripts:FindFirstChild("EFFECTS") then
            playerScripts.EFFECTS:Destroy()
        end
    end)
end

local function safeSpawnTeleport(root, humanoid, position)
    if not root or not humanoid then
        return
    end

    local originalAnchored = root.Anchored
    local character = humanoid.Parent

    root.Anchored = true
    humanoid.PlatformStand = false
    humanoid.Sit = false
    humanoid.AutoRotate = true
    humanoid:Move(Vector3.zero, false)

    if character then
        character:PivotTo(CFrame.new(position))
    else
        root.CFrame = CFrame.new(position)
    end
    root.CFrame = uprightFromCFrame(root.CFrame, position)
    zeroRootVelocities(root)

    task.delay(SPAWN_TELEPORT_RELEASE_DELAY, function()
        if root.Parent and humanoid.Parent then
            root.Anchored = originalAnchored
            zeroRootVelocities(root)
            humanoid.PlatformStand = false
            humanoid.Sit = false
            humanoid.AutoRotate = true
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
            end)
        end
    end)
end

local function enterPanicMode(character)
    if not state.active or not state.camPosition then
        return
    end

    destroyLocalEffects()

    state.panicMode = true
    state.groundMode = false
    state.refreshTimer = POSITION_REFRESH_INTERVAL
    state.targetPosition = nil
    state.safeParkPosition = nil
    setPanicSafePark(character)
end

local function exitPanicMode()
    state.panicMode = false
    state.refreshTimer = POSITION_REFRESH_INTERVAL
    state.targetPosition = nil
    state.safeParkPosition = nil
end

local function disconnectHealthMonitor()
    if state.healthConn then
        state.healthConn:Disconnect()
        state.healthConn = nil
    end
    state.lastHealth = nil
end

local function disconnectSimpleHealthMonitor()
    if state.simpleHealthConn then
        state.simpleHealthConn:Disconnect()
        state.simpleHealthConn = nil
    end
    state.simpleLastHealth = nil
end

local function triggerDamagePanic()
    if state.active then
        enterPanicMode(player.Character)
    end
end

local function connectHealthMonitor(character)
    disconnectHealthMonitor()

    local humanoid = getHumanoid(character)
    if not humanoid then
        return
    end

    state.lastHealth = humanoid.Health
    state.healthConn = humanoid.HealthChanged:Connect(function(newHealth)
        if state.lastHealth ~= nil and newHealth < state.lastHealth and newHealth > 0 and state.active then
            triggerDamagePanic()
        end
        state.lastHealth = newHealth
    end)
end

local function connectSimpleHealthMonitor(character)
    disconnectSimpleHealthMonitor()

    local humanoid = getHumanoid(character)
    if not humanoid then
        return
    end

    state.simpleLastHealth = humanoid.Health
    state.simpleHealthConn = humanoid.HealthChanged:Connect(function(newHealth)
        if not state.simpleBatActive then
            state.simpleLastHealth = newHealth
            return
        end

        local previous = state.simpleLastHealth or newHealth
        state.simpleLastHealth = newHealth
        if newHealth < previous then
            stopSimpleBat()
        end
    end)
end

local function updateGroundMode(character, deltaTime)
    local root = getRoot(character)
    if not root or not state.camPosition then
        return
    end

    setCharacterNoClip(character, true)

    if isIncomingDanger(character) then
        enterPanicMode(character)
        return
    end

    state.refreshTimer += deltaTime
    local desired = Vector3.new(state.camPosition.X, GROUND_MODE_FIXED_Y, state.camPosition.Z)

    local shouldRefresh = false
    if state.refreshTimer >= POSITION_REFRESH_INTERVAL then
        shouldRefresh = true
    elseif not state.targetPosition then
        shouldRefresh = true
    elseif getFlatDistance(state.targetPosition, desired) >= MIN_MOVE_DISTANCE then
        shouldRefresh = true
    end

    if shouldRefresh then
        state.refreshTimer = 0
        state.targetPosition = desired
    end

    if not state.targetPosition then
        state.targetPosition = desired
    end

    moveRootTo(root, state.targetPosition)
end

local function updateAirMode(character, deltaTime)
    local root = getRoot(character)
    if not root or not state.camPosition then
        return
    end

    setCharacterNoClip(character, false)

    if state.panicMode then
        state.safeParkPosition = Vector3.new(state.camPosition.X, PANIC_SAFE_PARK_Y, state.camPosition.Z)
        state.targetPosition = state.safeParkPosition
        moveRootTo(root, state.targetPosition)
        return
    end

    if isIncomingDanger(character) then
        enterPanicMode(character)
        return
    end

    state.refreshTimer += deltaTime
    local desired = getDesiredHiddenPosition()

    local shouldRefresh = false
    if state.refreshTimer >= POSITION_REFRESH_INTERVAL then
        shouldRefresh = true
    elseif not state.targetPosition then
        shouldRefresh = true
    elseif getFlatDistance(state.targetPosition, desired) >= MIN_MOVE_DISTANCE then
        shouldRefresh = true
    end

    if shouldRefresh then
        state.refreshTimer = 0
        if isPositionCovered(character, desired) then
            state.targetPosition = desired
            state.safeParkPosition = nil
        else
            setNormalSafePark(character)
            return
        end
    end

    if not state.targetPosition then
        setNormalSafePark(character)
        return
    end

    if state.targetPosition.Y == NORMAL_SAFE_PARK_Y then
        state.safeParkPosition = Vector3.new(state.camPosition.X, NORMAL_SAFE_PARK_Y, state.camPosition.Z)
        state.targetPosition = state.safeParkPosition
        moveRootTo(root, state.targetPosition)
        return
    end

    if not isPositionCovered(character, state.targetPosition) then
        setNormalSafePark(character)
        return
    end

    if getFlatDistance(root.Position, state.targetPosition) >= 1.5 then
        moveRootToward(root, state.targetPosition, MAX_TELEPORT_STEP)
    else
        moveRootTo(root, state.targetPosition)
    end

    if not isPositionCovered(character, root.Position) then
        setNormalSafePark(character)
    end
end

local function getExitLookVector()
    return flattenLookVector(getObserverCFrame().LookVector)
end

local function getSafeExitCFrame(character)
    local root = getRoot(character)
    if not root or not state.camPosition then
        return nil
    end

    local params = makeRayParams(character)
    local flatLook = getExitLookVector()

    local desiredBase = state.camPosition + flatLook * EXIT_FORWARD_GLIDE + Vector3.new(0, EXIT_UPWARD_GLIDE, 0)
    local rayOrigin = desiredBase + Vector3.new(0, EXIT_PROBE_UP, 0)
    local rayDirection = Vector3.new(0, -(EXIT_PROBE_UP + EXIT_PROBE_DOWN), 0)

    local groundHit = workspace:Raycast(rayOrigin, rayDirection, params)
    local finalPos

    if groundHit then
        finalPos = groundHit.Position + Vector3.new(0, (root.Size.Y * 0.5) + EXIT_GROUND_CLEARANCE, 0)
    else
        finalPos = desiredBase + Vector3.new(0, (root.Size.Y * 0.5) + 2, 0)
    end

    local wallCheckOrigin = finalPos + Vector3.new(0, 2, 0)
    local wallHit = workspace:Raycast(wallCheckOrigin, flatLook * EXIT_WALL_CHECK_DISTANCE, params)
    if wallHit then
        finalPos = finalPos - flatLook * EXIT_FORWARD_OFFSET
    end

    return CFrame.new(finalPos, finalPos + flatLook)
end

local function updateObserver(deltaTime)
    if not state.active or not state.freeCamPart or not state.camPosition then
        return
    end

    local camera = getCamera()
    if not camera then
        return
    end

    local mouseDelta = UserInputService:GetMouseDelta()
    state.camYaw -= mouseDelta.X * CAMERA_SENSITIVITY
    state.camPitch = math.clamp(state.camPitch - mouseDelta.Y * CAMERA_SENSITIVITY, -MAX_PITCH, MAX_PITCH)

    local observerCFrame = getObserverCFrame()
    local moveVector = Vector3.zero

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector += observerCFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector -= observerCFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector -= observerCFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector += observerCFrame.RightVector end

    local speed = getCurrentFlightSpeed(deltaTime)
    if moveVector.Magnitude > 0 then
        state.camPosition += moveVector.Unit * speed * deltaTime
        observerCFrame = getObserverCFrame()
    end

    state.freeCamPart.CFrame = observerCFrame

    if not state.simpleBatActive then
        camera.CFrame = observerCFrame
    end

    local character = player.Character
    local humanoid = getHumanoid(character)
    local root = getRoot(character)
    if not character or not humanoid or not root then
        return
    end

    if state.respawnFreefallActive then
        setStatusDotColorByPosition(character)
        return
    end

    if state.groundMode then
        updateGroundMode(character, deltaTime)
    else
        updateAirMode(character, deltaTime)
    end

    setStatusDotColorByPosition(character)
end

local function updateSimpleBat(deltaTime)
    if not state.simpleBatActive or not state.simpleFreeCamPart or not state.simpleCamPosition then
        return
    end

    local camera = getCamera()
    if not camera then
        return
    end

    if state.active then
        syncSimpleCameraFromObserver()
        camera.CFrame = getObserverCFrame()
        return
    end

    local mouseDelta = UserInputService:GetMouseDelta()
    state.simpleCamYaw -= mouseDelta.X * CAMERA_SENSITIVITY
    state.simpleCamPitch = math.clamp(state.simpleCamPitch - mouseDelta.Y * CAMERA_SENSITIVITY, -MAX_PITCH, MAX_PITCH)

    local observerCFrame = getSimpleObserverCFrame()
    local moveVector = Vector3.zero

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector += observerCFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector -= observerCFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector -= observerCFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector += observerCFrame.RightVector end

    local speed = getSimpleFlightSpeed(deltaTime)
    if moveVector.Magnitude > 0 then
        state.simpleCamPosition += moveVector.Unit * speed * deltaTime
        observerCFrame = getSimpleObserverCFrame()
    end

    state.simpleFreeCamPart.CFrame = observerCFrame
    camera.CFrame = observerCFrame

    local character = player.Character
    local root = getRoot(character)
    if root and state.simpleOriginalRootPosition then
        local heldCFrame = state.simpleOriginalRootCFrame or CFrame.new(state.simpleOriginalRootPosition)
        root.CFrame = uprightFromCFrame(heldCFrame, state.simpleOriginalRootPosition)
        zeroRootVelocities(root)
    end

    if character then
        setStatusDotColorByPosition(character)
    end
end

local function cleanupObserverState()
    RunService:UnbindFromRenderStep(CAMERA_BIND_NAME)
    setCastBindingsEnabled(false)

    if state.freeCamPart then
        state.freeCamPart:Destroy()
        state.freeCamPart = nil
    end

    disconnectHealthMonitor()

    state.active = false
    state.groundMode = false
    state.panicMode = false
    state.transitioning = false
    state.refreshTimer = 0
    state.targetPosition = nil
    state.safeParkPosition = nil
    state.boostHoldTime = 0
    state.respawnFreefallActive = false
    state.camPosition = nil
    state.camYaw = 0
    state.camPitch = 0
    refreshStatusUIVisibility()
end

local function cleanupSimpleBatState()
    RunService:UnbindFromRenderStep(SIMPLE_CAMERA_BIND_NAME)

    if state.simpleFreeCamPart then
        state.simpleFreeCamPart:Destroy()
        state.simpleFreeCamPart = nil
    end

    disconnectSimpleHealthMonitor()

    state.simpleBatActive = false
    state.simpleTransitioning = false
    state.simpleBoostHoldTime = 0
    state.simpleCamPosition = nil
    state.simpleCamYaw = 0
    state.simpleCamPitch = 0
    state.simpleOriginalRootCFrame = nil
    state.simpleOriginalRootPosition = nil
    refreshStatusUIVisibility()
end

local function startObserverMode()
    if state.active or state.transitioning then
        return
    end

    state.transitioning = true

    local character, humanoid, root, camera = waitForCharacterReady(5)
    if not character or not humanoid or not root or not camera then
        state.transitioning = false
        return
    end

    ensureStatusUI()
    refreshStatusUIVisibility()
    saveCollisionState(character)

    state.active = true
    state.groundMode = false
    state.panicMode = false
    state.refreshTimer = 0
    state.targetPosition = nil
    state.safeParkPosition = nil
    state.boostHoldTime = 0
    state.respawnFreefallActive = false

    state.originalCameraType = camera.CameraType
    state.originalCameraSubject = humanoid
    state.originalMouseBehavior = UserInputService.MouseBehavior
    state.originalMouseIconEnabled = UserInputService.MouseIconEnabled

    saveMovementState(humanoid)
    connectHealthMonitor(character)

    if state.simpleBatActive and state.simpleFreeCamPart and state.simpleCamPosition then
        ensureFreeCam(camera)
        syncObserverCameraFromSimple()
        state.freeCamPart.CFrame = getObserverCFrame()
    else
        ensureFreeCam(camera)
    end

    local desired = getDesiredHiddenPosition()
    if desired and isPositionCovered(character, desired) then
        state.targetPosition = desired
        moveRootTo(root, desired)
    else
        setNormalSafePark(character)
    end

    if not state.simpleBatActive then
        camera.CameraType = Enum.CameraType.Scriptable
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled = false
    end

    setCastBindingsEnabled(true)
    RunService:BindToRenderStep(CAMERA_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, updateObserver)

    setStatusDotColorByPosition(character)
    state.transitioning = false
end

local function startObserverModeFromSpawn()
    if state.active or state.transitioning or state.simpleBatActive or state.simpleTransitioning then
        return
    end

    state.transitioning = true

    local character, humanoid, root, camera = waitForCharacterReady(5)
    if not character or not humanoid or not root or not camera then
        state.transitioning = false
        return
    end

    task.wait(SPAWN_STABILIZE_TIME)
    RunService.RenderStepped:Wait()

    camera = getCamera()
    character = player.Character
    humanoid = getHumanoid(character)
    root = getRoot(character)

    if not camera or not character or not humanoid or not root then
        state.transitioning = false
        return
    end

    ensureStatusUI()
    refreshStatusUIVisibility()
    saveCollisionState(character)

    local restoreCameraCFrame = state.pendingRespawnRestoreCamera and state.pendingRespawnCameraCFrame or nil

    state.active = true
    state.groundMode = false
    state.panicMode = false
    state.refreshTimer = 0
    state.targetPosition = nil
    state.safeParkPosition = nil
    state.boostHoldTime = 0
    state.respawnFreefallActive = true

    state.originalCameraType = camera.CameraType
    state.originalCameraSubject = humanoid
    state.originalMouseBehavior = UserInputService.MouseBehavior
    state.originalMouseIconEnabled = UserInputService.MouseIconEnabled

    saveMovementState(humanoid)
    connectHealthMonitor(character)

    local rootPos = root.Position
    local flatLook = flattenLookVector(root.CFrame.LookVector)
    local spawnCameraPos = rootPos - flatLook * 12 + Vector3.new(0, 6, 0)
    local spawnCameraCFrame = CFrame.new(spawnCameraPos, rootPos + Vector3.new(0, 3, 0))
    local desiredCameraCFrame = restoreCameraCFrame or spawnCameraCFrame

    -- Keep vision stable first, before moving the character away.
    camera.CameraType = Enum.CameraType.Custom
    camera.CameraSubject = humanoid
    camera.CFrame = spawnCameraCFrame
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = true

    local panicTeleportPosition = Vector3.new(desiredCameraCFrame.Position.X, SPAWN_SAFE_Y, desiredCameraCFrame.Position.Z)
    safeSpawnTeleport(root, humanoid, panicTeleportPosition)

    task.wait(SPAWN_POST_TELEPORT_CAMERA_DELAY)
    RunService.RenderStepped:Wait()

    if not player.Character or player.Character ~= character then
        state.transitioning = false
        return
    end

    local freeCamPart = Instance.new("Part")
    freeCamPart.Name = "BatStyleObserverCam"
    freeCamPart.Anchored = true
    freeCamPart.CanCollide = false
    freeCamPart.CanTouch = false
    freeCamPart.CanQuery = false
    freeCamPart.Transparency = 1
    freeCamPart.Size = Vector3.new(1, 1, 1)
    freeCamPart.CFrame = desiredCameraCFrame
    freeCamPart.Parent = workspace

    local pitch, yaw = desiredCameraCFrame:ToOrientation()
    state.camPosition = desiredCameraCFrame.Position
    state.camYaw = yaw
    state.camPitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
    state.freeCamPart = freeCamPart

    state.pendingRespawnCameraCFrame = nil
    state.pendingRespawnRestoreCamera = false

    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = desiredCameraCFrame
    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    UserInputService.MouseIconEnabled = false

    setCastBindingsEnabled(true)
    RunService:BindToRenderStep(CAMERA_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, updateObserver)

    setStatusDotColorByPosition(character)
    state.transitioning = false
end

stopObserverMode = function(skipExitPlacement, forceStopSimpleBat)
    if state.transitioning then
        return
    end

    state.transitioning = true

    local character = player.Character
    local humanoid = getHumanoid(character)
    local root = getRoot(character)
    local camera = getCamera()
    local keepSimpleBatRunning = state.simpleBatActive and not forceStopSimpleBat

    local exitCFrame = nil
    if state.active and state.camPosition and character and not keepSimpleBatRunning then
        exitCFrame = getSafeExitCFrame(character)
    end

    if character then
        setCharacterNoClip(character, true)
    end

    if keepSimpleBatRunning then
        syncSimpleCameraFromObserver()
        if root and state.simpleCamPosition then
            local releaseCFrame = CFrame.new(state.simpleCamPosition, state.simpleCamPosition + flattenLookVector(getSimpleObserverCFrame().LookVector))
            root.CFrame = uprightFromCFrame(releaseCFrame, state.simpleCamPosition)
            zeroRootVelocities(root)
            state.simpleOriginalRootCFrame = root.CFrame
            state.simpleOriginalRootPosition = root.Position
        end
    elseif not skipExitPlacement and exitCFrame and root then
        root.CFrame = uprightFromCFrame(exitCFrame)
        zeroRootVelocities(root)
    end

    restoreMovementState(humanoid)

    if camera then
        if keepSimpleBatRunning and state.simpleFreeCamPart then
            camera.CameraType = Enum.CameraType.Scriptable
            camera.CFrame = getSimpleObserverCFrame()
        else
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = humanoid or state.originalCameraSubject
        end
    end

    if keepSimpleBatRunning then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled = false
    else
        UserInputService.MouseBehavior = state.originalMouseBehavior or Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = state.originalMouseIconEnabled == nil and true or state.originalMouseIconEnabled
    end

    if humanoid and root then
        plainReleaseHumanoid(humanoid, root)
    end

    cleanupObserverState()

    if keepSimpleBatRunning and character then
        setStatusDotColorByPosition(character)
    end

    if character then
        task.delay(0, function()
            if character.Parent then
                setCharacterNoClip(character, false)
            end
        end)
    end
end

local function startSimpleBat()
    if state.simpleBatActive or state.simpleTransitioning then
        return
    end

    state.simpleTransitioning = true

    local character, humanoid, root, camera = waitForCharacterReady(5)
    if not character or not humanoid or not root or not camera then
        state.simpleTransitioning = false
        return
    end

    state.simpleBatActive = true
    state.simpleBoostHoldTime = 0

    ensureStatusUI()
    refreshStatusUIVisibility()

    state.simpleOriginalRootCFrame = uprightFromCFrame(root.CFrame)
    state.simpleOriginalRootPosition = root.Position

    state.simpleOriginalCameraType = camera.CameraType
    state.simpleOriginalCameraSubject = humanoid
    state.simpleOriginalMouseBehavior = UserInputService.MouseBehavior
    state.simpleOriginalMouseIconEnabled = UserInputService.MouseIconEnabled

    ensureSimpleFreeCam(camera)

    if not state.active then
        root.CFrame = uprightFromCFrame(state.simpleOriginalRootCFrame, state.simpleOriginalRootPosition)
        zeroRootVelocities(root)
    end

    camera.CameraType = Enum.CameraType.Scriptable
    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    UserInputService.MouseIconEnabled = false

    connectSimpleHealthMonitor(character)
    RunService:BindToRenderStep(SIMPLE_CAMERA_BIND_NAME, Enum.RenderPriority.Camera.Value + 2, updateSimpleBat)

    setStatusDotColorByPosition(character)
    state.simpleTransitioning = false
end

stopSimpleBat = function()
    if state.simpleTransitioning or not state.simpleBatActive then
        return
    end

    state.simpleTransitioning = true

    local character = player.Character
    local humanoid = getHumanoid(character)
    local root = getRoot(character)
    local camera = getCamera()

    if root and state.simpleOriginalRootPosition and not state.active then
        local restoreCFrame = state.simpleOriginalRootCFrame or CFrame.new(state.simpleOriginalRootPosition)
        restoreCFrame = uprightFromCFrame(restoreCFrame, state.simpleOriginalRootPosition)
        root.CFrame = restoreCFrame
        zeroRootVelocities(root)
    end

    if camera then
        if state.active and state.freeCamPart then
            camera.CameraType = Enum.CameraType.Scriptable
            camera.CFrame = getObserverCFrame()
        else
            camera.CameraType = state.simpleOriginalCameraType or Enum.CameraType.Custom
            camera.CameraSubject = humanoid or state.simpleOriginalCameraSubject
        end
    end

    if not state.active then
        UserInputService.MouseBehavior = state.simpleOriginalMouseBehavior or Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = state.simpleOriginalMouseIconEnabled == nil and true or state.simpleOriginalMouseIconEnabled
    end

    if humanoid and root and not state.active then
        plainReleaseHumanoid(humanoid, root)
    end

    cleanupSimpleBatState()

    if character then
        setStatusDotColorByPosition(character)
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.KeyCode == SIMPLE_BAT_KEY then
        local now = tick()
        if now - state.lastSimpleTap <= DOUBLE_TAP_TIME then
            state.lastSimpleTap = 0
            if state.simpleBatActive and state.active then
                stopAllModesAtCurrentCamera()
            elseif state.simpleBatActive then
                stopSimpleBat()
            else
                startSimpleBat()
            end
        else
            state.lastSimpleTap = now
        end
        return
    end

    if input.KeyCode == Enum.KeyCode.F1 then
        if state.active or state.simpleBatActive then
            stopAllModesAtCurrentCamera()
        end
        return
    end

    if input.KeyCode == Enum.KeyCode.Tab then
        state.tabHeld = true
        return
    end

    if input.KeyCode == TOGGLE_KEY then
        local now = tick()
        if now - state.lastToggleTap <= DOUBLE_TAP_TIME then
            state.lastToggleTap = 0
            if state.active then
                stopObserverMode(false, state.simpleBatActive and state.tabHeld)
            else
                startObserverMode()
            end
        else
            state.lastToggleTap = now
        end
        return
    end

    if input.KeyCode == GROUND_MODE_KEY and state.active then
        state.groundMode = not state.groundMode
        state.panicMode = false
        state.refreshTimer = POSITION_REFRESH_INTERVAL
        state.targetPosition = nil
        state.safeParkPosition = nil
        return
    end

    if input.KeyCode == PANIC_MODE_KEY and state.active then
        if state.panicMode then
            exitPanicMode()
        else
            enterPanicMode(player.Character)
        end
        return
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == FAST_KEY then
        state.boostHoldTime = 0
        state.simpleBoostHoldTime = 0
    elseif input.KeyCode == Enum.KeyCode.Tab then
        state.tabHeld = false
    end
end)

player.CharacterAdded:Connect(function(character)
    state.autoStartToken += 1
    local myToken = state.autoStartToken
    local wasUsingBatBeforeRespawn = state.active or state.simpleBatActive

    local sharedCameraBeforeRespawn = getCurrentSharedCameraCFrame()
    if wasUsingBatBeforeRespawn and sharedCameraBeforeRespawn then
        state.pendingRespawnCameraCFrame = sharedCameraBeforeRespawn
        state.pendingRespawnRestoreCamera = true
    else
        state.pendingRespawnCameraCFrame = nil
        state.pendingRespawnRestoreCamera = false
    end

    state.panicMode = false
    state.groundMode = false

    stopSimpleBat()
    stopObserverMode(true)

    connectHealthMonitor(character)
    connectSimpleHealthMonitor(character)

    state.hasSeenFirstCharacter = true

    if AUTO_START_ON_RESPAWN and wasUsingBatBeforeRespawn then
        task.defer(function()
            local timeoutStart = tick()
            while myToken == state.autoStartToken do
                local currentCharacter = player.Character
                local humanoid = getHumanoid(currentCharacter)
                local root = getRoot(currentCharacter)
                local camera = getCamera()

                if currentCharacter == character and humanoid and root and camera then
                    startObserverModeFromSpawn()
                    return
                end

                if tick() - timeoutStart > 5 then
                    return
                end

                task.wait()
            end
        end)
    end
end)

if player.Character then
    state.hasSeenFirstCharacter = true
    connectHealthMonitor(player.Character)
    connectSimpleHealthMonitor(player.Character)

    if AUTO_START_ON_RESPAWN then
        task.defer(function()
            if not state.active and not state.transitioning then
                startObserverModeFromSpawn()
            end
        end)
    end
end

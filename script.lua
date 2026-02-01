vanilla_model.ARMOR:setVisible(true)
vanilla_model.CAPE:setVisible(true)
vanilla_model.ELYTRA:setVisible(true)

config:setName("polyblobcat_orbit_config")

---- Variables
-- model
local MAX_ORBIT_BLOBS = 15

local function _clampInt(n, lo, hi)
  if type(n) ~= "number" then
    return lo
  end
  n = math.floor(n + 0.5)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function _clampNum(n, lo, hi)
  if type(n) ~= "number" then
    return lo
  end
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local orbitCount = _clampInt(config:load("orbitCount") or 1, 1, MAX_ORBIT_BLOBS)

-- Movement customization (kept within safe limits)
local DEFAULT_ORBIT_RADIUS = 0.9
local DEFAULT_ORBIT_BLOB_HEIGHT = 0.18

local orbitRadius = _clampNum(config:load("orbitRadius") or DEFAULT_ORBIT_RADIUS, 0.1, 3.0)
-- Adds to the orbit's vertical center (blocks). Positive = higher.
local orbitHeightOffset = _clampNum(config:load("orbitHeightOffset") or 0.0, -2.0, 2.0)
-- Vertical blob amplitude of blobs on the ring (blocks).
local orbitBlobHeight = _clampNum(config:load("orbitBlobHeight") or DEFAULT_ORBIT_BLOB_HEIGHT, 0.0, 1.5)
-- Multiplies base orbit speed (0 = freeze).
local orbitSpeed = _clampNum(config:load("orbitSpeed") or 1.0, 0.0, 5.0)

-- These parts must exist in the model:
-- WORLD.blob, WORLD.blob2, WORLD.blob3, WORLD.blob4, WORLD.blob5,
-- WORLD.blob6, WORLD.blob7, WORLD.blob8, WORLD.blob9, WORLD.blob10
local blobs = {}
local function _refreshBlobParts()
  blobs[1] = models.model.WORLD.blob
  for i = 2, MAX_ORBIT_BLOBS do
    blobs[i] = models.model.WORLD["blob" .. i]
  end
end

_refreshBlobParts()

-- Lower = closer to feet (relative to eye height)
local BASE_OFFSET = 2.5
-- Smoothing factors (0..1). Higher = snappier, lower = smoother
local HEIGHT_SMOOTH = 0.1
local POS_SMOOTH = 1
local ROT_SMOOTH = 0.45
-- Extra smoothing just for player position (helps jump jitter)
local PLAYER_POS_SMOOTH = 0.15
-- Extra smoothing just for crouch/stand height (applies like player-pos smoothing)
local BASE_H_SMOOTH = 0.18
-- Low-health speed boost (multiplies orbit speed). Does not change base speed at full health.
local LOW_HP_SPEED_BOOST = 5.0
local HP_SPEED_SMOOTH = 0.12
-- Landing bounce tuning
local LAND_BOUNCE_STRENGTH = 0.80
local LAND_BOUNCE_SPRING = 0.25
local LAND_BOUNCE_DAMPING = 0.82

-- Toggleable state variables
local orbitToggled = config:load("orbitToggled") or true
local firstPersonOrbitToggled = config:load("firstPersonOrbitToggled") or false
local healthSpeedToggled = config:load("healthSpeedToggled") or false
-- If true: remove X/Z lerp so blobs don't lag behind; keep Y smoothing.
local xzNoLerpToggled = config:load("xzNoLerpToggled") or false

-- Shared implementation (pings call into these)
local function _implOrbitState(state)
  orbitToggled = (state == true)
  config:save("orbitToggled", orbitToggled)
end

local function _implFirstPersonOrbitState(state)
  firstPersonOrbitToggled = (state == true)
  config:save("firstPersonOrbitToggled", firstPersonOrbitToggled)
end

local function _implHealthSpeedState(state)
  healthSpeedToggled = (state == true)
  config:save("healthSpeedToggled", healthSpeedToggled)
end

local function _implXZNoLerpState(state)
  xzNoLerpToggled = (state == true)
  config:save("xzNoLerpToggled", xzNoLerpToggled)
end

local function _implOrbitCount(count)
  orbitCount = _clampInt(count, 1, MAX_ORBIT_BLOBS)
  config:save("orbitCount", orbitCount)
end

local function _implOrbitRadius(radius)
  orbitRadius = _clampNum(radius, 0.1, 3.0)
  config:save("orbitRadius", orbitRadius)
end

local function _implOrbitHeightOffset(h)
  orbitHeightOffset = _clampNum(h, -2.0, 2.0)
  config:save("orbitHeightOffset", orbitHeightOffset)
end

local function _implOrbitBlobHeight(h)
  orbitBlobHeight = _clampNum(h, 0.0, 1.5)
  config:save("orbitBlobHeight", orbitBlobHeight)
end

local function _implOrbitSpeed(s)
  orbitSpeed = _clampNum(s, 0.0, 5.0)
  config:save("orbitSpeed", orbitSpeed)
end

---- ping functions for serverside updating
local function _resolveTextureByName(textureName)
  if not textureName then
    return nil
  end

  -- Common fast paths
  local tex = textures[textureName]
  if tex then
    return tex
  end

  if textures.getTexture then
    local ok, t = pcall(function()
      return textures:getTexture(textureName)
    end)
    if ok and t then
      return t
    end
  end

  -- Fallback: search texture list by display name
  if textures.getTextures then
    local ok, list = pcall(function()
      return textures:getTextures()
    end)
    if ok and type(list) == "table" then
      for _, t in ipairs(list) do
        if t and t.getName and t:getName() == textureName then
          return t
        end
      end
    end
  end

  return nil
end

local function _implBlobTexture(textureName)
  _refreshBlobParts()
  local tex = _resolveTextureByName(textureName)
  if not tex then
    return
  end

  for i = 1, MAX_ORBIT_BLOBS do
    if blobs[i] then
      blobs[i]:setPrimaryTexture("CUSTOM", tex)
    end
  end
  config:save("blob_texture", textureName)
end

local function _implBlobTextureForIndex(index, textureName)
  _refreshBlobParts()
  index = _clampInt(index, 1, MAX_ORBIT_BLOBS)
  local tex = _resolveTextureByName(textureName)
  if not tex then
    return
  end

  if blobs[index] then
    blobs[index]:setPrimaryTexture("CUSTOM", tex)
  end
  config:save("blob_texture_" .. index, textureName)
end

function pings.setBlobTexture(textureName) _implBlobTexture(textureName) end
function pings.setBlobTextureForIndex(index, textureName) _implBlobTextureForIndex(index, textureName) end
function pings.setOrbitState(state) _implOrbitState(state) end
function pings.setOrbitCount(count) _implOrbitCount(count) end
function pings.setHealthSpeedState(state) _implHealthSpeedState(state) end
function pings.setFirstPersonOrbitState(state) _implFirstPersonOrbitState(state) end
function pings.setXZNoLerpState(state) _implXZNoLerpState(state) end

-- Batched sync (reduces network spam on world join / periodic resync)
local function _applySyncPayload(payload)
  if type(payload) ~= "table" then
    return
  end

  if payload.orbitToggled ~= nil then
    _implOrbitState(payload.orbitToggled)
  end
  if payload.firstPersonOrbitToggled ~= nil then
    _implFirstPersonOrbitState(payload.firstPersonOrbitToggled)
  end
  if payload.healthSpeedToggled ~= nil then
    _implHealthSpeedState(payload.healthSpeedToggled)
  end
  if payload.xzNoLerpToggled ~= nil then
    _implXZNoLerpState(payload.xzNoLerpToggled)
  end
  if payload.orbitCount ~= nil then
    _implOrbitCount(payload.orbitCount)
  end

  if payload.orbitRadius ~= nil then
    _implOrbitRadius(payload.orbitRadius)
  end
  if payload.orbitHeightOffset ~= nil then
    _implOrbitHeightOffset(payload.orbitHeightOffset)
  end
  if payload.orbitBlobHeight ~= nil then
    _implOrbitBlobHeight(payload.orbitBlobHeight)
  end
  if payload.orbitSpeed ~= nil then
    _implOrbitSpeed(payload.orbitSpeed)
  end

  -- textures (global first, then per-blob overrides)
  if payload.blob_texture ~= nil then
    _implBlobTexture(payload.blob_texture)
  end
  local per = payload.blob_textures
  if type(per) == "table" then
    for i, texName in pairs(per) do
      if texName ~= nil then
        _implBlobTextureForIndex(i, texName)
      end
    end
  end
end

function pings.syncAllSettings(payload)
  _applySyncPayload(payload)
end

-- Action wheel setup
local mainPage = action_wheel:newPage()
action_wheel:setPage(mainPage)

-- Texture page is referenced by blobSelectPage, so declare it first.
local texturePage = action_wheel:newPage()

-- Movement settings page (keeps main page under the action wheel slot limit)
local movementPage = action_wheel:newPage()

-- Blob select page (used for per-blob texture selection)
local blobSelectPage
local selectedBlobIndex = 1

local blobSelectActions = {}

local function _getBlobTextureNameForIndex(index)
  index = _clampInt(index, 1, MAX_ORBIT_BLOBS)
  return config:load("blob_texture_" .. index) or config:load("blob_texture")
end

local function _refreshBlobSelectPageVisuals()
  for i = 1, MAX_ORBIT_BLOBS do
    local a = blobSelectActions[i]
    if a then
      local texName = _getBlobTextureNameForIndex(i)
      local tex
      if texName then
        tex = _resolveTextureByName(texName)
      end

      if texName and tex and a.setTexture then
        pcall(function()
          a:title("Select blob " .. i .. " (" .. texName .. ")")
        end)
        pcall(function()
          a:setTexture(tex, 0, 0, 128, 256, 0.15)
        end)
      else
        pcall(function()
          a:title("Select blob " .. i .. " (none)")
        end)
        pcall(function()
          if a.item then
            a:item("minecraft:barrier")
          end
        end)
      end
    end
  end
end

local function _rebuildBlobSelectPage()
  blobSelectPage = action_wheel:newPage()
  blobSelectActions = {}

  local shown = _clampInt(orbitCount, 1, MAX_ORBIT_BLOBS)
  if selectedBlobIndex > shown then
    selectedBlobIndex = shown
  end

  for i = 1, shown do
    local a = blobSelectPage:newAction()
    pcall(function()
      a:title("Select blob " .. i)
    end)
    a:onLeftClick(function()
      selectedBlobIndex = i
      pcall(_refreshBlobSelectPageVisuals)
      action_wheel:setPage(texturePage)
    end)
    a:onRightClick(function()
      action_wheel:setPage(mainPage)
    end)
    blobSelectActions[i] = a
  end

  -- Defer visuals refresh to entity_init/RunInit; still safe to attempt.
  pcall(_refreshBlobSelectPageVisuals)
end

_rebuildBlobSelectPage()

-- Generate textures page actions from available textures
for i, texture in ipairs(textures:getTextures()) do
  local a = texturePage:newAction()
  local texName = texture:getName()
  a:title(texName)
  a:setTexture(texture, 0, 0, 128, 256, 0.15)
  a:onLeftClick(function()
    local idx = selectedBlobIndex or 1
    -- Apply locally immediately (some Figura/network setups don't execute self-pings).
    _implBlobTextureForIndex(idx, texName)
    pcall(function()
      pings.setBlobTextureForIndex(idx, texName)
    end)
    _refreshBlobSelectPageVisuals()
  end)
  a:onRightClick(function()
    action_wheel:setPage(blobSelectPage)
  end)
end

-- Main page actions (avoid chaining for compatibility)
local switchBlob = mainPage:newAction()
switchBlob:title("Switch per-blob textures")
switchBlob:item("minecraft:pink_dye")
switchBlob:hoverColor(1, 0, 1)
switchBlob:onLeftClick(function()
  action_wheel:setPage(blobSelectPage)
end)

local openMovement = mainPage:newAction()
openMovement:title("Movement settings")
openMovement:item("minecraft:compass")
openMovement:hoverColor(0.2, 0.9, 1)
openMovement:onLeftClick(function()
  action_wheel:setPage(movementPage)
end)

local toggleOrbit = mainPage:newAction()
toggleOrbit:title("Show blobs")
toggleOrbit:toggleTitle("Hide blobs")
toggleOrbit:item("red_wool")
toggleOrbit:toggleItem("green_wool")
local _suppress_actionwheel_net = false
toggleOrbit:setOnToggle(function(state)
  _implOrbitState(state)
  if not _suppress_actionwheel_net then
    pcall(function() pings.setOrbitState(state) end)
  end
end)
toggleOrbit:setToggled(orbitToggled)

local firstPersonOrbitToggle = mainPage:newAction()
firstPersonOrbitToggle:title("Show first person blobs")
firstPersonOrbitToggle:toggleTitle("Hide first person blobs")
firstPersonOrbitToggle:item("red_wool")
firstPersonOrbitToggle:toggleItem("green_wool")
firstPersonOrbitToggle:setOnToggle(function(state)
  _implFirstPersonOrbitState(state)
  if not _suppress_actionwheel_net then
    pcall(function() pings.setFirstPersonOrbitState(state) end)
  end
end)
firstPersonOrbitToggle:setToggled(firstPersonOrbitToggled)

local healthSpeedToggle = mainPage:newAction()
healthSpeedToggle:title("Enable low HP boost")
healthSpeedToggle:toggleTitle("Disable low HP boost")
healthSpeedToggle:item("red_wool")
healthSpeedToggle:toggleItem("green_wool")
healthSpeedToggle:setOnToggle(function(state)
  _implHealthSpeedState(state)
  if not _suppress_actionwheel_net then
    pcall(function() pings.setHealthSpeedState(state) end)
  end
end)
healthSpeedToggle:setToggled(healthSpeedToggled)

local xzNoLerpToggle = mainPage:newAction()
xzNoLerpToggle:title("Follow player")
xzNoLerpToggle:toggleTitle("Stuck to player")
xzNoLerpToggle:item("red_wool")
xzNoLerpToggle:toggleItem("green_wool")
xzNoLerpToggle:setOnToggle(function(state)
  _implXZNoLerpState(state)
  if not _suppress_actionwheel_net then
    pcall(function() pings.setXZNoLerpState(state) end)
  end
end)
xzNoLerpToggle:setToggled(xzNoLerpToggled)

-- Avoid chaining here: some Figura versions don't return self from click handlers.
local orbitCountAction = mainPage:newAction()
orbitCountAction:title("Blobs: " .. orbitCount .. "/" .. MAX_ORBIT_BLOBS .. " (L:+ R:-)")
orbitCountAction:item("minecraft:ender_pearl")
orbitCountAction:onLeftClick(function()
  local newCount = orbitCount + 1
  _implOrbitCount(newCount)
  pcall(function() pings.setOrbitCount(newCount) end)
  pcall(_rebuildBlobSelectPage)
  orbitCountAction:title("Blobs: " .. orbitCount .. "/" .. MAX_ORBIT_BLOBS .. " (L:+ R:-)")
end)
orbitCountAction:onRightClick(function()
  local newCount = orbitCount - 1
  _implOrbitCount(newCount)
  pcall(function() pings.setOrbitCount(newCount) end)
  pcall(_rebuildBlobSelectPage)
  orbitCountAction:title("Blobs: " .. orbitCount .. "/" .. MAX_ORBIT_BLOBS .. " (L:+ R:-)")
end)

local orbitRadiusAction = movementPage:newAction()
orbitRadiusAction:title(string.format("Radius: %.2f (L:+ R:-)", orbitRadius))
orbitRadiusAction:item("minecraft:compass")
orbitRadiusAction:onLeftClick(function()
  _implOrbitRadius(orbitRadius + 0.1)
  orbitRadiusAction:title(string.format("Radius: %.2f (L:+ R:-)", orbitRadius))
  if not _suppress_actionwheel_net then
    pcall(function() pings.syncAllSettings({ orbitRadius = orbitRadius }) end)
  end
end)
orbitRadiusAction:onRightClick(function()
  _implOrbitRadius(orbitRadius - 0.1)
  orbitRadiusAction:title(string.format("Radius: %.2f (L:+ R:-)", orbitRadius))
  if not _suppress_actionwheel_net then
    pcall(function() pings.syncAllSettings({ orbitRadius = orbitRadius }) end)
  end
end)

local orbitHeightAction = movementPage:newAction()
orbitHeightAction:title(string.format("Height: %.2f (L:+ R:-)", orbitHeightOffset))
orbitHeightAction:item("minecraft:ladder")
orbitHeightAction:onLeftClick(function()
  _implOrbitHeightOffset(orbitHeightOffset + 0.1)
  orbitHeightAction:title(string.format("Height: %.2f (L:+ R:-)", orbitHeightOffset))
  if not _suppress_actionwheel_net then
    pcall(function() pings.syncAllSettings({ orbitHeightOffset = orbitHeightOffset }) end)
  end
end)
orbitHeightAction:onRightClick(function()
  _implOrbitHeightOffset(orbitHeightOffset - 0.1)
  orbitHeightAction:title(string.format("Height: %.2f (L:+ R:-)", orbitHeightOffset))
  if not _suppress_actionwheel_net then
    pcall(function() pings.syncAllSettings({ orbitHeightOffset = orbitHeightOffset }) end)
  end
end)

local orbitBlobHeightAction = movementPage:newAction()
orbitBlobHeightAction:title(string.format("Blob height: %.2f (L:+ R:-)", orbitBlobHeight))
orbitBlobHeightAction:item("minecraft:feather")
orbitBlobHeightAction:onLeftClick(function()
  _implOrbitBlobHeight(orbitBlobHeight + 0.05)
  orbitBlobHeightAction:title(string.format("Blob height: %.2f (L:+ R:-)", orbitBlobHeight))
  if not _suppress_actionwheel_net then
    pcall(function() pings.syncAllSettings({ orbitBlobHeight = orbitBlobHeight }) end)
  end
end)
orbitBlobHeightAction:onRightClick(function()
  _implOrbitBlobHeight(orbitBlobHeight - 0.05)
  orbitBlobHeightAction:title(string.format("Blob height: %.2f (L:+ R:-)", orbitBlobHeight))
  if not _suppress_actionwheel_net then
    pcall(function() pings.syncAllSettings({ orbitBlobHeight = orbitBlobHeight }) end)
  end
end)

local orbitSpeedAction = movementPage:newAction()
orbitSpeedAction:title(string.format("Orbit speed: %.2fx (L:+ R:-)", orbitSpeed))
orbitSpeedAction:item("minecraft:clock")
orbitSpeedAction:onLeftClick(function()
  _implOrbitSpeed(orbitSpeed + 0.1)
  orbitSpeedAction:title(string.format("Orbit speed: %.2fx (L:+ R:-)", orbitSpeed))
  if not _suppress_actionwheel_net then
    pcall(function() pings.syncAllSettings({ orbitSpeed = orbitSpeed }) end)
  end
end)
orbitSpeedAction:onRightClick(function()
  _implOrbitSpeed(orbitSpeed - 0.1)
  orbitSpeedAction:title(string.format("Orbit speed: %.2fx (L:+ R:-)", orbitSpeed))
  if not _suppress_actionwheel_net then
    pcall(function() pings.syncAllSettings({ orbitSpeed = orbitSpeed }) end)
  end
end)

local backFromMovement = movementPage:newAction()
backFromMovement:title("Back")
backFromMovement:item("minecraft:arrow")
backFromMovement:onLeftClick(function()
  action_wheel:setPage(mainPage)
end)

---- Math functions
local function _lerp(a, b, t)
  return a + (b - a) * t
end

local function _vlerp(a, b, t)
  return a * (1 - t) + b * t
end

local function _ease(t)
  -- smoothstep: eases in/out (more "gradual" than linear)
  return t * t * (3 - 2 * t)
end

-- Deterministic "random" (0..1) based on blob index.
-- Keeps each blob's variation stable across frames/sessions.
local function _rand01(i, salt)
  salt = salt or 0
  local x = math.sin((i * 12.9898) + (salt * 78.233)) * 43758.5453
  return x - math.floor(x)
end

local texture = nil

-- Re-send settings periodically so servers/others pick them up.
-- 20 ticks/sec -> 200 ticks = 10 seconds.
local SYNC_INTERVAL_TICKS = 200

local function _syncAllSettingsToPing()
  local payload = {
    orbitToggled = orbitToggled,
    firstPersonOrbitToggled = firstPersonOrbitToggled,
    healthSpeedToggled = healthSpeedToggled,
    xzNoLerpToggled = xzNoLerpToggled,
    orbitCount = orbitCount,
    orbitRadius = orbitRadius,
    orbitHeightOffset = orbitHeightOffset,
    orbitBlobHeight = orbitBlobHeight,
    orbitSpeed = orbitSpeed,
  }

  local globalTex = config:load("blob_texture")
  if globalTex then
    payload.blob_texture = globalTex
  end

  local per = {}
  for i = 1, MAX_ORBIT_BLOBS do
    local t_i = config:load("blob_texture_" .. i)
    if t_i then
      per[i] = t_i
    end
  end
  if next(per) ~= nil then
    payload.blob_textures = per
  end

  pcall(function()
    pings.syncAllSettings(payload)
  end)
end

function RunInit()
  --player functions goes here
  ---- Initialization ----
  -- restore texture from config
  texture = config:load("blob_texture")

  _refreshBlobParts()
  -- Back-compat: apply saved global texture first (if any), then override per-blob.
  if texture then
    _implBlobTexture(texture)
  end
  for i = 1, MAX_ORBIT_BLOBS do
    local t_i = config:load("blob_texture_" .. i)
    if t_i then
      _implBlobTextureForIndex(i, t_i)
    end
  end

  -- restore toggled states from config
  local savedOrbit = config:load("orbitToggled")
  if savedOrbit == nil then savedOrbit = true end
  _implOrbitState(savedOrbit)
  _implFirstPersonOrbitState(config:load("firstPersonOrbitToggled") or false)
  _implHealthSpeedState(config:load("healthSpeedToggled") or false)
  _implXZNoLerpState(config:load("xzNoLerpToggled") or false)

  -- Avoid emitting extra pings if setToggled triggers callbacks on some Figura versions.
  _suppress_actionwheel_net = true
  if toggleOrbit then
    pcall(function()
      toggleOrbit:setToggled(orbitToggled)
    end)
  end
  if firstPersonOrbitToggle then
    pcall(function()
      firstPersonOrbitToggle:setToggled(firstPersonOrbitToggled)
    end)
  end
  if healthSpeedToggle then
    pcall(function()
      healthSpeedToggle:setToggled(healthSpeedToggled)
    end)
  end
  if xzNoLerpToggle then
    pcall(function()
      xzNoLerpToggle:setToggled(xzNoLerpToggled)
    end)
  end
  _suppress_actionwheel_net = false

  orbitCount = _clampInt(config:load("orbitCount") or orbitCount, 1, MAX_ORBIT_BLOBS)

  _implOrbitRadius(config:load("orbitRadius") or orbitRadius)
  _implOrbitHeightOffset(config:load("orbitHeightOffset") or orbitHeightOffset)
  _implOrbitBlobHeight(config:load("orbitBlobHeight") or orbitBlobHeight)
  _implOrbitSpeed(config:load("orbitSpeed") or orbitSpeed)

  pcall(_rebuildBlobSelectPage)
  if orbitCountAction then
    pcall(function()
      orbitCountAction:title("Blobs: " .. orbitCount .. "/" .. MAX_ORBIT_BLOBS .. " (L:+ R:-)")
    end)
  end

  if orbitRadiusAction then
    pcall(function()
      orbitRadiusAction:title(string.format("Radius: %.2f (L:+ R:-)", orbitRadius))
    end)
  end
  if orbitHeightAction then
    pcall(function()
      orbitHeightAction:title(string.format("Height: %.2f (L:+ R:-)", orbitHeightOffset))
    end)
  end
  if orbitBlobHeightAction then
    pcall(function()
      orbitBlobHeightAction:title(string.format("Blob height: %.2f (L:+ R:-)", orbitBlobHeight))
    end)
  end
  if orbitSpeedAction then
    pcall(function()
      orbitSpeedAction:title(string.format("Orbit speed: %.2fx (L:+ R:-)", orbitSpeed))
    end)
  end

  pcall(_refreshBlobSelectPageVisuals)
end

function events.entity_init()
  RunInit()
  _syncAllSettingsToPing()
end

-- Movement math variables
local _eye_h_smoothed
local _base_h_prev
local _base_h_curr
local _base_h_smoothed
local _p_smoothed
local _smoothed_pos
local _smoothed_rot

local _p_tick_prev
local _p_tick_curr
local _vy_prev
local _on_ground_prev
local _on_ground_curr
local _bounce_offset = 0
local _bounce_vel = 0

local _hp_speed_mult
local _orbit_phase_prev
local _orbit_phase_curr
local _spin_phase_prev
local _spin_phase_curr

--tick event, called 20 times per second
function events.tick()
  if world and world.getTime and (world.getTime() % SYNC_INTERVAL_TICKS == 0) then
    RunInit()
    _syncAllSettingsToPing()
  end

  -- Smooth changes in eye height (crouch/stand) so the orbit doesn't snap.
  if not player then
    return
  end

  -- Track tick-to-tick vertical motion for landing bounce
  if player.getPos then
    local p = player:getPos()
    if _p_tick_curr == nil then
      _p_tick_prev = p
      _p_tick_curr = p
    else
      _p_tick_prev = _p_tick_curr
      _p_tick_curr = p
    end

    if _p_tick_prev ~= nil then
      local vy = _p_tick_curr.y - _p_tick_prev.y

      -- Fast landing detection:
      -- Prefer air->ground transition (fires immediately on landing tick),
      -- otherwise fall back to a velocity-based heuristic.
      local landed = false

      if player.isOnGround then
        _on_ground_prev = _on_ground_curr
        _on_ground_curr = player:isOnGround()
        landed = (_on_ground_curr == true) and (_on_ground_prev == false)
      else
        landed = (_vy_prev or 0) < -0.08 and math.abs(vy) < 0.01
      end

      if landed then
        local impact = -(_vy_prev or 0)
        if impact < 0 then impact = 0 end
        _bounce_vel = _bounce_vel + impact * LAND_BOUNCE_STRENGTH
      end

      _vy_prev = vy
    end
  end

  -- spring update (tick-based)
  _bounce_vel = _bounce_vel - _bounce_offset * LAND_BOUNCE_SPRING
  _bounce_vel = _bounce_vel * LAND_BOUNCE_DAMPING
  _bounce_offset = _bounce_offset + _bounce_vel

  local eye_h = 1.62
  if player.getEyeHeight then
    eye_h = player:getEyeHeight()
  end

  local eye_h_target = eye_h
  if _eye_h_smoothed == nil then
    _eye_h_smoothed = eye_h_target
  else
    _eye_h_smoothed = _lerp(_eye_h_smoothed, eye_h_target, HEIGHT_SMOOTH)
  end

  local base_h_target = _eye_h_smoothed - BASE_OFFSET + (orbitHeightOffset or 0)
  if _base_h_curr == nil then
    _base_h_prev = base_h_target
    _base_h_curr = base_h_target
  else
    _base_h_prev = _base_h_curr
    _base_h_curr = _lerp(_base_h_curr, base_h_target, HEIGHT_SMOOTH)
  end

  -- Health-based orbit speed multiplier (smoothed to avoid jitter)
  -- Linear vs HP%: full HP -> 1x, 0 HP -> (1 + LOW_HP_SPEED_BOOST)x.
  local target_mult = 1
  if healthSpeedToggled and player.getHealth and player.getMaxHealth then
    local hp = player:getHealth()
    local max_hp = player:getMaxHealth()
    if type(hp) == "number" and type(max_hp) == "number" and max_hp > 0 then
      local hp_ratio = math.max(0, math.min(1, hp / max_hp))
      local low = 1 - hp_ratio
      target_mult = 1 + low * LOW_HP_SPEED_BOOST
    end
  end
  if _hp_speed_mult == nil then
    _hp_speed_mult = target_mult
  else
    _hp_speed_mult = _lerp(_hp_speed_mult, target_mult, HP_SPEED_SMOOTH)
  end

  -- Integrate orbit phase so changing speed doesn't "jump" the angle.
  local speed = 0.01 * (orbitSpeed or 1) -- keep base speed; apply multiplier
  if _orbit_phase_curr == nil then
    _orbit_phase_prev = 0
    _orbit_phase_curr = 0
  else
    _orbit_phase_prev = _orbit_phase_curr
  end
  _orbit_phase_curr = _orbit_phase_curr + (speed * (_hp_speed_mult or 1) * 2 * math.pi)

  -- Integrate model spin phase (degrees) so HP-based speed changes don't jitter.
  local rot_speed = 8 -- keep current base rotation speed (do NOT change this value)
  if _spin_phase_curr == nil then
    _spin_phase_prev = 0
    _spin_phase_curr = 0
  else
    _spin_phase_prev = _spin_phase_curr
  end
  _spin_phase_curr = _spin_phase_curr + (rot_speed * (_hp_speed_mult or 1))
end

function events.render(delta, context)
  _refreshBlobParts()
  local hideFirstPerson = (context == "FIRST_PERSON" and user:getName() == player:getName() and not firstPersonOrbitToggled)
  for i = 1, MAX_ORBIT_BLOBS do
    if blobs[i] then
      local shouldShow = orbitToggled and (not hideFirstPerson) and (i <= orbitCount)
      blobs[i]:setVisible(shouldShow)
    end
  end

  local p_raw = player:getPos(delta)
  local p_smooth = _ease(PLAYER_POS_SMOOTH)
  _p_smoothed = _p_smoothed and _vlerp(_p_smoothed, p_raw, p_smooth) or p_raw
  local p = _p_smoothed
  local eye_h = 1.62
  if player.getEyeHeight then
    eye_h = player:getEyeHeight()
  end
  -- lower than eye height (so it doesn't hover too high)
  local base_h
  if _base_h_prev ~= nil and _base_h_curr ~= nil then
    base_h = _lerp(_base_h_prev, _base_h_curr, delta or 0)
  else
    base_h = eye_h - BASE_OFFSET + (orbitHeightOffset or 0)
  end

  -- Apply the same eased smoothing technique used for player position
  local base_h_smooth = _ease(BASE_H_SMOOTH)
  _base_h_smoothed = _base_h_smoothed and _lerp(_base_h_smoothed, base_h, base_h_smooth) or base_h
  base_h = _base_h_smoothed

  -- Add a small landing bounce (vertical offset)
  local bounce = _bounce_offset or 0

  local t = 0
  if world and world.getTime then
    t = world.getTime() + (delta or 0)
  elseif world and world.getTimeOfDay then
    t = world.getTimeOfDay() + (delta or 0)
  end

  local radius = (orbitRadius or 0.9) -- blocks
  local ang
  if _orbit_phase_prev ~= nil and _orbit_phase_curr ~= nil then
    ang = _lerp(_orbit_phase_prev, _orbit_phase_curr, delta or 0)
  else
    local speed = 0.01 * (orbitSpeed or 1) -- keep base speed; apply multiplier
    ang = t * speed * 2 * math.pi
  end

  if type(_smoothed_pos) ~= "table" then
    _smoothed_pos = {}
  end
  if type(_smoothed_rot) ~= "table" then
    _smoothed_rot = {}
  end

  -- 3D orbit: circle + vertical blob (a gentle helix)
  local y_amp = (orbitBlobHeight or 0.18) -- blocks (smaller = up/down closer together)
  local count = math.max(1, orbitCount)

  for i = 1, orbitCount do
    local b = blobs[i]
    if b then
      local offset = (i - 1) / count * (2 * math.pi)

      -- Per-blob "physics": keep the same orbit slot, but add a small drift.
      -- This preserves formation while making each blob feel a bit different.
      local ang_i = ang + offset
      local y = math.sin(ang_i * 1.6) * y_amp
      local orbit = vec(math.cos(ang_i) * radius, y, math.sin(ang_i) * radius)

      local drift_phase = (_rand01(i, 10) - 0.5) * 6.28
      -- Lower = slower drift (t is in ticks)
      local drift_rate = 0.12 + _rand01(i, 11) * 0.10
      local drift_amp = 0.025 + _rand01(i, 12) * 0.020 -- blocks
      local drift_y_amp = 0.010 + _rand01(i, 13) * 0.012 -- blocks
      local drift = vec(
        math.sin((t * drift_rate) + drift_phase) * drift_amp,
        math.sin((t * drift_rate * 1.15) + drift_phase * 1.7) * drift_y_amp,
        math.cos((t * drift_rate) + drift_phase) * drift_amp
      )

      local target_pos = (p + vec(0, base_h + bounce, 0) + orbit + drift) * 16
      local target_pos_raw = (p_raw + vec(0, base_h + bounce, 0) + orbit + drift) * 16
      local pos_smooth = _ease(math.max(0, math.min(1, POS_SMOOTH * (0.05 + _rand01(i, 15) * 0.16))))
      local sm = _smoothed_pos[i] and _vlerp(_smoothed_pos[i], target_pos, pos_smooth) or target_pos
      if xzNoLerpToggled then
        sm = vec(target_pos_raw.x, sm.y, target_pos_raw.z)
      end
      _smoothed_pos[i] = sm
      b:setPos(sm)
    end
  end

  -- rotate the model itself (independent spin)
  local spin_y
  if _spin_phase_prev ~= nil and _spin_phase_curr ~= nil then
    spin_y = _lerp(_spin_phase_prev, _spin_phase_curr, delta or 0)
  else
    local rot_speed = 8 -- keep current base rotation speed (do NOT change this value)
    spin_y = t * rot_speed
  end
  local rot_smooth = _ease(ROT_SMOOTH)
  for i = 1, orbitCount do
    local b = blobs[i]
    if b then
      local offset = (i - 1) / math.max(1, orbitCount) * (2 * math.pi)
      local ang_i = ang + offset

      -- Per-blob stable variation so they don't all rotate identically.
      local wobble_phase = (_rand01(i, 1) - 0.5) * 1.2
      local wobble_mul_x = 0.85 + _rand01(i, 2) * 0.35
      local wobble_mul_z = 0.85 + _rand01(i, 3) * 0.35
      local spin_offset = (_rand01(i, 4) - 0.5) * 40 -- degrees
      local spin_rate_mul = 0.85 + _rand01(i, 5) * 0.35
      local wobble_rate_mul = 0.85 + _rand01(i, 6) * 0.45

      local wobble_x = math.sin((ang_i + wobble_phase) * 1.6 * wobble_rate_mul) * 12 * wobble_mul_x
      local wobble_z = math.cos((ang_i + wobble_phase) * 1.6 * wobble_rate_mul) * 8 * wobble_mul_z
      local target_rot = vec(wobble_x, (spin_y * spin_rate_mul) + spin_offset, wobble_z)
      _smoothed_rot[i] = _smoothed_rot[i] and _vlerp(_smoothed_rot[i], target_rot, rot_smooth) or target_rot
      b:setRot(_smoothed_rot[i])
    end
  end
end

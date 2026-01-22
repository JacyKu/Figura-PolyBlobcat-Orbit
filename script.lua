vanilla_model.ARMOR:setVisible(true)
vanilla_model.CAPE:setVisible(true)
vanilla_model.ELYTRA:setVisible(true)

config:setName("polyblobcat_orbit_config")

---- Variables
-- model
local blob = models.model.WORLD.blob

-- Lower = closer to feet (relative to eye height)
local BASE_OFFSET = 2.5
-- Smoothing factors (0..1). Higher = snappier, lower = smoother
local HEIGHT_SMOOTH = 0.1
local POS_SMOOTH = 0.25
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

---- ping functions for serverside updating
function pings.setBlobTexture(textureName)
  blob:setPrimaryTexture("CUSTOM", textures[textureName])
  config:save("blob_texture", textureName)
end

function pings.setOrbitState(state)
  models.model.WORLD.blob:setVisible(state)
  orbitToggled = state
  config:save("orbitToggled", state)
end

function pings.setHealthSpeedState(state)
  healthSpeedToggled = state
  config:save("healthSpeedToggled", state)
end

-- toggles first person visibility of the orbiting blob
function pings.setFirstPersonOrbitState(state)
  firstPersonOrbitToggled = state
  config:save("firstPersonOrbitToggled", state)
end

-- Action wheel setup
local mainPage = action_wheel:newPage()
action_wheel:setPage(mainPage)

-- Generate textures page actions from available textures
local texturePage = action_wheel:newPage()
for i, texture in ipairs(textures:getTextures()) do
  texturePage:newAction()
      :title(texture:getName())
      :setTexture(texture, 0, 0, 128, 256, 0.15)
      :onLeftClick(function()
        pings.setBlobTexture(texture:getName())
      end)
      :onRightClick(function()
        action_wheel:setPage(mainPage)
      end)
end

local switchBlob = mainPage:newAction()
    :title("Switch blob textures")
    :item("minecraft:pink_dye")
    :hoverColor(1, 0, 1)
    :onLeftClick(function() action_wheel:setPage(texturePage) end)

local toggleOrbit = mainPage:newAction()
    :title("disabled orbit")
    :toggleTitle("enabled orbit")
    :item("red_wool")
    :toggleItem("green_wool")
    :setOnToggle(pings.setOrbitState)
    :setToggled(orbitToggled)

local firstPersonOrbitToggle = mainPage:newAction()
    :title("first person orbit disabled")
    :toggleTitle("first person orbit enabled")
    :item("red_wool")
    :toggleItem("green_wool")
    :setOnToggle(pings.setFirstPersonOrbitState)
    :setToggled(firstPersonOrbitToggled)

local healthSpeedToggle = mainPage:newAction()
    :title("health speed disabled")
    :toggleTitle("health speed enabled")
    :item("red_wool")
    :toggleItem("green_wool")
    :setOnToggle(pings.setHealthSpeedState)
    :setToggled(healthSpeedToggled)

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

local texture = nil

function RunInit()
  --player functions goes here
  ---- Initialization ----
  -- restore texture from config
  if (config:load("blob_texture")) then
    texture = config:load("blob_texture")
  end

  pings.setBlobTexture(texture)

  -- restore toggled states from config
  pings.setOrbitState(config:load("orbitToggled"))
  pings.setHealthSpeedState(config:load("healthSpeedToggled") or false)
end

function events.entity_init()
  RunInit()
end

function events.tick()
  if (world.getTime() % 200 == 0) then
    RunInit()
  end
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

  local base_h_target = _eye_h_smoothed - BASE_OFFSET
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
  local speed = 0.01 -- keep current base speed (do NOT change this value)
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
  if (orbitToggled == true) then
    blob:setVisible(true)
  end
  if (context == "FIRST_PERSON" and user:getName() == player:getName() and not firstPersonOrbitToggled) then
    blob:setVisible(false)
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
    base_h = eye_h - BASE_OFFSET
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

  local radius = 0.9 -- blocks
  local ang
  if _orbit_phase_prev ~= nil and _orbit_phase_curr ~= nil then
    ang = _lerp(_orbit_phase_prev, _orbit_phase_curr, delta or 0)
  else
    local speed = 0.01 -- keep current base speed (do NOT change this value)
    ang = t * speed * 2 * math.pi
  end

  -- 3D orbit: circle + vertical bob (a gentle helix)
  local y_amp = 0.18 -- blocks (smaller = up/down closer together)
  local y = math.sin(ang * 1.6) * y_amp
  local orbit = vec(math.cos(ang) * radius, y, math.sin(ang) * radius)

  -- Smooth the final world-space position to reduce jitter
  local target_pos = (p + vec(0, base_h + bounce, 0) + orbit) * 16
  local pos_smooth = _ease(POS_SMOOTH)
  _smoothed_pos = _smoothed_pos and _vlerp(_smoothed_pos, target_pos, pos_smooth) or target_pos
  blob:setPos(_smoothed_pos)

  -- rotate the model itself (independent spin)
  local spin_y
  if _spin_phase_prev ~= nil and _spin_phase_curr ~= nil then
    spin_y = _lerp(_spin_phase_prev, _spin_phase_curr, delta or 0)
  else
    local rot_speed = 8 -- keep current base rotation speed (do NOT change this value)
    spin_y = t * rot_speed
  end
  local wobble_x = math.sin(ang * 1.6) * 12
  local wobble_z = math.cos(ang * 1.6) * 8
  -- Smooth rotation a bit as well
  local target_rot = vec(wobble_x, spin_y, wobble_z)
  local rot_smooth = _ease(ROT_SMOOTH)
  _smoothed_rot = _smoothed_rot and _vlerp(_smoothed_rot, target_rot, rot_smooth) or target_rot
  blob:setRot(_smoothed_rot)
end

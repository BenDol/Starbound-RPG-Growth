require "/scripts/util.lua"
require "/scripts/interp.lua"

-- Melee primary ability
BladeDance = WeaponAbility:new()

function BladeDance:init()
  self.comboStep = 1

  self.energyUsage = self.energyUsage or 0

  self:computeDamageAndCooldowns()

  self.weapon:setStance(self.stances.idle)

  self.edgeTriggerTimer = 0
  self.flashTimer = 0
  self.cooldownTimer = self.cooldowns[1]

  self.killTimer = 0
  self.damageGivenUpdate = 5
  self.weapon.active = false

  self.animKeyPrefix = self.animKeyPrefix or ""

  self.weapon.onLeaveAbility = function()
    animator.setPartTag("blade", "directives", "")
    animator.setPartTag("handle", "directives", "")
    if self.weapon.active then
      self.weapon:setStance(self.stances.idleActive)
    else
      self.weapon:setStance(self.stances.idle)
    end
  end
end

-- Ticks on every update regardless if this is the active ability
function BladeDance:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  self.movingForward = mcontroller.facingDirection() == mcontroller.movingDirection()
  self.notMoving = not (mcontroller.running() or mcontroller.walking())
  self.crouched = mcontroller.crouching()
  self.aerial = not mcontroller.onGround() and not mcontroller.groundMovement()

  if self.cooldownTimer > 0 then
    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)
    if self.cooldownTimer == 0 then
      self:readyFlash()
    end
  end

  if self.flashTimer > 0 then
    self.flashTimer = math.max(0, self.flashTimer - self.dt)
    if self.flashTimer == 0 then
      animator.setGlobalTag("bladeDirectives", "")
    end
  end

  if self.weapon.stance.flipx then
    animator.setPartTag("blade", "directives", "?flipx")
    animator.setPartTag("handle", "directives", "?flipx")
    animator.setPartTag("sheath", "directives", "?flipx")
  else
    --[[animator.setPartTag("blade", "directives", "")
    animator.setPartTag("handle", "directives", "")
    animator.setPartTag("sheath", "directives", "")]]
  end

  self:updateDamageGiven()

  self.killTimer = math.max(self.killTimer - dt, 0)

  self.edgeTriggerTimer = math.max(0, self.edgeTriggerTimer - dt)
  if self.lastFireMode ~= (self.activatingFireMode or self.abilitySlot) and fireMode == (self.activatingFireMode or self.abilitySlot) then
    self.edgeTriggerTimer = self.edgeTriggerGrace
  end
  self.lastFireMode = fireMode

  if not self.weapon.currentAbility then
    if self:shouldActivate() then
      self.currentFireMode = self.fireMode
      self:setState(self.windup)
    else

    end
  end
end

function BladeDance:updateDamageGiven()
  local notifications = nil
  notifications, self.damageGivenUpdate = status.inflictedDamageSince(self.damageGivenUpdate)
  if notifications then
    for _,notification in pairs(notifications) do
      if "ivrpgsamuraikatana" == notification.damageSourceKind then
        if notification.healthLost > 0 and notification.damageDealt > notification.healthLost then
          self.killTimer = math.min(self.killTimer + 2.5, 10)
        end
      end
    end
  end
end

-- State: windup
function BladeDance:windup()
  if not self.weapon.active then
    self.comboType = "Unsheathe"
  elseif self.fireMode == "primary" then
    if not self.movingForward and not self.notMoving then
      self.comboType = "Backstep"
    elseif self.aerial then
      self.comboType = "Dive"
    else
      self.comboType = "Primary"
    end
  else --alt
    if self.movingForward and not self.notMoving then
      self.comboType = "Lunge"
    elseif self.crouched then
      self.comboType = "Sheathe"
    else
      self.comboType = "Rise"
    end
  end

  local stance = self.stances["windup"..self.comboType]

  if not self.weapon.active then
    animator.setAnimationState("sheath", "transitionOff")
    animator.playSound("unsheathe")
  end

  self.weapon:setStance(stance)

  if stance.flipx and stance.flipy then
    animator.setPartTag("blade", "directives", "?flipxy")
    animator.setPartTag("handle", "directives", "?flipxy")
  elseif stance.flipx and not stance.flipy then
    animator.setPartTag("blade", "directives", "?flipx")
    animator.setPartTag("handle", "directives", "?flipx")
  elseif stance.flipy and not stance.flipx then
    animator.setPartTag("blade", "directives", "?flipy")
    animator.setPartTag("handle", "directives", "?flipy")
  else
    animator.setPartTag("blade", "directives", "")
    animator.setPartTag("handle","directives", "")
  end
  self.edgeTriggerTimer = 0

  if stance.hold then
    while self.fireMode == (self.activatingFireMode or self.abilitySlot) do
      coroutine.yield()
    end
  else
    util.wait(stance.duration)
  end

  if self.energyUsage then
    status.overConsumeResource("energy", self.energyUsage)
  end

  if self.stances["preslash"..self.comboType] then
    self:setState(self.preslash)
  else
    self:setState(self.fire)
  end
end

-- State: wait
-- waiting for next combo input
function BladeDance:wait()
  local stance = self.stances["wait"..self.comboType]

  self.weapon:setStance(stance)
  if stance.flipx and stance.flipy then
    animator.setPartTag("blade", "directives", "?flipxy")
    animator.setPartTag("handle", "directives", "?flipxy")
  elseif stance.flipx and not stance.flipy then
    animator.setPartTag("blade", "directives", "?flipx")
    animator.setPartTag("handle", "directives", "?flipx")
  elseif stance.flipy and not stance.flipx then
    animator.setPartTag("blade", "directives", "?flipy")
    animator.setPartTag("handle", "directives", "?flipy")
  else
    animator.setPartTag("blade", "directives", "")
    animator.setPartTag("handle","directives", "")
  end
  util.wait(stance.duration, function()
    if self:shouldActivate() then
      self:setState(self.windup)
      return
    end
  end)

  self.cooldownTimer = math.max(0, self.cooldowns[self.comboStep - 1] - stance.duration)
  self.comboStep = 1
end

-- State: preslash
-- brief frame in between windup and fire
function BladeDance:preslash()
  local stance = self.stances["preslash"..self.comboType]


  self.weapon:setStance(stance)
  self.weapon:updateAim()
  if stance.flipx and stance.flipy then
    animator.setPartTag("blade", "directives", "?flipxy")
    animator.setPartTag("handle", "directives", "?flipxy")
  elseif stance.flipx and not stance.flipy then
    animator.setPartTag("blade", "directives", "?flipx")
    animator.setPartTag("handle", "directives", "?flipx")
  elseif stance.flipy and not stance.flipx then
    animator.setPartTag("blade", "directives", "?flipy")
    animator.setPartTag("handle", "directives", "?flipy")
  else
    animator.setPartTag("blade", "directives", "")
    animator.setPartTag("handle","directives", "")
  end
  util.wait(stance.duration)

  self:setState(self.fire)
end

-- State: fire
function BladeDance:fire()
  local stance = self.stances["fire"..self.comboType]

  self.weapon:setStance(stance)
  self.weapon:updateAim()
  if stance.flipx and stance.flipy then
    animator.setPartTag("blade", "directives", "?flipxy")
    animator.setPartTag("handle", "directives", "?flipxy")
  elseif stance.flipx and not stance.flipy then
    animator.setPartTag("blade", "directives", "?flipx")
    animator.setPartTag("handle", "directives", "?flipx")
  elseif stance.flipy and not stance.flipx then
    animator.setPartTag("blade", "directives", "?flipy")
    animator.setPartTag("handle", "directives", "?flipy")
  else
    animator.setPartTag("blade", "directives", "")
    animator.setPartTag("handle","directives", "")
  end
  local animStateKey = self.animKeyPrefix .. "fire" .. self.comboType
  animator.setAnimationState("swoosh", animStateKey)
  animator.playSound(animStateKey)

  local swooshKey = self.animKeyPrefix .. (self.elementalType or self.weapon.elementalType) .. "swoosh"
  animator.setParticleEmitterOffsetRegion(swooshKey, self.swooshOffsetRegions[self.comboStep])
  animator.burstParticleEmitter(swooshKey)

  if self.comboType == "Backstep" then
    mcontroller.setVelocity({-mcontroller.facingDirection() * 100, 1})
  elseif self.comboType == "Lunge" then
    mcontroller.setVelocity({mcontroller.facingDirection() * 100, 1})
  elseif self.comboType == "Rise" then
    mcontroller.setVelocity({0, 100})
  elseif self.comboType == "Dive" then
    mcontroller.setVelocity({mcontroller.facingDirection() * 20, -100})
  end

  util.wait(stance.duration, function()
    local damageArea = partDamageArea("swoosh")
    if self.comboType ~= "Dive" then
      self.weapon:setDamage(self.stepDamageConfig[self.comboStep], damageArea)
    end
    if self.comboType == "Rise" then
      mcontroller.controlApproachYVelocity(0, 500)
    elseif self.comboType == "Lunge" or self.comboType == "Backstep" then
      mcontroller.controlApproachXVelocity(0, 500)
    elseif self.comboType == "Dive" and mcontroller.onGround() then
      return true
    end
  end)

  if self.comboStep < self.comboSteps then
    self.comboStep = self.comboStep + 1
    self:setState(self.wait)
  elseif not self.weapon.active then
    self.comboStep = 1
    self:setState(self.cooldown)
  else
    self.cooldownTimer = self.cooldowns[self.comboStep]
    self.comboStep = 1
  end
end

function BladeDance:cooldown()
  self.weapon:setStance(self.stances.toIdle)
  self.weapon:updateAim()
  self.weapon.active = true

  local progress = 0
  util.wait(self.stances.toIdle.duration, function()
    local from = self.stances.toIdle.weaponOffset or {0,0}
    local to = self.stances.idleActive.weaponOffset or {0,0}
    self.weapon.weaponOffset = {interp.linear(progress, from[1], to[1]), interp.linear(progress, from[2], to[2])}

    self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(progress, self.stances.toIdle.weaponRotation, self.stances.idleActive.weaponRotation))
    self.weapon.relativeArmRotation = util.toRadians(interp.linear(progress, self.stances.toIdle.armRotation, self.stances.idleActive.armRotation))

    if progress >= 0.5 then
      animator.setPartTag("blade", "directives", "")
      animator.setPartTag("handle", "directives", "")
    end

    progress = math.min(1.0, progress + (self.dt / self.stances.toIdle.duration))
  end)
end

function BladeDance:shouldActivate()
  if self.cooldownTimer == 0 and (self.energyUsage == 0 or not status.resourceLocked("energy")) then
    if self.comboStep > 1 then
      return self.edgeTriggerTimer > 0
    else
      return self.fireMode == "primary" or self.fireMode == "alt"
    end
  end
end

function BladeDance:readyFlash()
  animator.setGlobalTag("bladeDirectives", self.flashDirectives)
  self.flashTimer = self.flashTime
end

function BladeDance:computeDamageAndCooldowns()
  local attackTimes = {}
  self.comboTypes = {"Unsheathe", "Primary", "Rise", "Dive", "Backstep", "Lunge", "Sheathe"}
  for _,i in ipairs(self.comboTypes) do
    local attackTime = self.stances["windup"..i].duration + self.stances["fire"..i].duration
    if self.stances["preslash"..i] then
      attackTime = attackTime + self.stances["preslash"..i].duration
    end
    table.insert(attackTimes, attackTime)
  end

  self.cooldowns = {}
  local totalAttackTime = 0
  local totalDamageFactor = 0
  for i, attackTime in ipairs(attackTimes) do
    self.stepDamageConfig[i] = util.mergeTable(copy(self.damageConfig), self.stepDamageConfig[i])
    self.stepDamageConfig[i].timeoutGroup = "primary"..i

    local damageFactor = self.stepDamageConfig[i].baseDamageFactor
    self.stepDamageConfig[i].baseDamage = damageFactor * self.baseDps * self.fireTime

    totalAttackTime = totalAttackTime + attackTime
    totalDamageFactor = totalDamageFactor + damageFactor

    local targetTime = totalDamageFactor * self.fireTime
    local speedFactor = 1.0 * (self.comboSpeedFactor ^ i)
    table.insert(self.cooldowns, (targetTime - totalAttackTime) * speedFactor)
  end
end

 
function BladeDance:uninit()
  self.weapon:setDamage()
end

require "/tech/distortionsphere/distortionsphere.lua"
require "/scripts/rect.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"
require "/scripts/keybinds.lua"
require "/tech/ivrpgopenrpgui.lua"

function init()
  ivrpg_ttShortcut.initialize()
  initCommonParameters()

  self.ignorePlatforms = config.getParameter("ignorePlatforms")
  self.damageDisableTime = config.getParameter("damageDisableTime")
  self.damageDisableTimer = 0

  self.headingAngle = nil

  self.normalCollisionSet = {"Block", "Dynamic"}
  if self.ignorePlatforms then
    self.platformCollisionSet = self.normalCollisionSet
  else
    self.platformCollisionSet = {"Block", "Dynamic", "Platform"}
  end

  self.fireTimer = 0
  self.fireBlockTime = config.getParameter("fireBlockTime")
  self.poisonEnergyCost = config.getParameter("poisonEnergyCost")
  self.foodCostPerSecond = config.getParameter("foodCostPerSecond")
  
  self.damageListener = damageListener("damageTaken", function(notifications)
    for _, notification in pairs(notifications) do
      if notification.healthLost > 0 and notification.sourceEntityId ~= entity.id() then
        damaged()
        return
      end
    end
  end)
  self.consumeOn = nil

  Bind.create("primaryFire", spawnPoison)
end

function update(args)
  restoreStoredPosition()

  if not self.specialLast and args.moves["special1"] then
    attemptActivation()
  end
  self.specialLast = args.moves["special1"]
  self.pressConsume = args.moves["altFire"]

  if not args.moves["special1"] then
    self.forceTimer = nil
  end

  self.damageDisableTimer = math.max(0, self.damageDisableTimer - args.dt)

  self.damageListener:update()

  if self.active then

    --Consume Effect
    self.healthFull = (status.resourceMax("health") == status.resource("health"))
    self.energyFull = (status.resourceMax("energy") == status.resource("energy"))
    if self.pressConsume and (not self.healthFull or not self.energyFull) and status.consumeResource("food", self.foodCostPerSecond * args.dt) then
      activateConsume()
    else
      deactivateConsume()
    end

    local groundDirection
    if self.damageDisableTimer == 0 then
      groundDirection = findGroundDirection()
    end

    status.setPersistentEffects("roguetoxicsphereimmune",{
      {stat = "poisonStatusImmunity", amount = 1},
      {stat = "poisonResistance", amount = 2}
    })

    if groundDirection then
      if not self.headingAngle then
        self.headingAngle = (math.atan(groundDirection[2], groundDirection[1]) + math.pi / 2) % (math.pi * 2)
      end

      local moveX = 0
      if args.moves["right"] then moveX = moveX + 1 end
      if args.moves["left"] then moveX = moveX - 1 end
      if moveX ~= 0 then
        -- find any collisions in the moving direction, and adjust heading angle *up* until there is no collision
        -- this makes the heading direction follow concave corners
        local adjustment = 0
        for a = 0, math.pi, math.pi / 4 do
          local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.25, 0}, self.headingAngle + (moveX * a)))
          adjustment = moveX * a
          if not world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
            break
          end
        end
        self.headingAngle = self.headingAngle + adjustment

        -- find empty space in the moving direction and adjust heading angle *down* until it collides
        -- adjust to the angle *before* the collision occurs
        -- this makes the heading direction follow convex corners
        adjustment = 0
        for a = 0, -math.pi, -math.pi / 4 do
          local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.25, 0}, self.headingAngle + (moveX * a)))
          if world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
            break
          end
          adjustment = moveX * a
        end
        self.headingAngle = self.headingAngle + adjustment

        -- apply a gravitation like force in the ground direction, while moving in the controlled direction
        -- Note: this ground force causes weird collision when moving up slopes, result is you move faster up slopes
        local groundAngle = self.headingAngle - (math.pi / 2)
        mcontroller.controlApproachVelocity(vec2.withAngle(groundAngle, self.ballSpeed), 1500)

        local moveDirection = vec2.rotate({moveX, 0}, self.headingAngle)
        mcontroller.controlApproachVelocityAlongAngle(math.atan(moveDirection[2], moveDirection[1]), self.ballSpeed, 2200)

        self.angularVelocity = -moveX * self.ballSpeed
      else
        mcontroller.controlApproachVelocity({0,0}, 2000)
        self.angularVelocity = 0
      end

      mcontroller.controlDown()
      updateAngularVelocity(args.dt)

      self.transformedMovementParameters.gravityEnabled = false
    else
      updateAngularVelocity(args.dt)
      self.transformedMovementParameters.gravityEnabled = true
    end

    mcontroller.controlParameters(self.transformedMovementParameters)
    status.setResourcePercentage("energyRegenBlock", 1.0)

    updateRotationFrame(args.dt)

    checkForceDeactivate(args.dt)
  else
    self.headingAngle = nil
    deactivateConsume()
    status.clearPersistentEffects("roguetoxicsphereimmune")
  end

  updateTransformFade(args.dt)

  self.lastPosition = mcontroller.position()

  if self.fireTimer > 0 then
    self.fireTimer = math.max(0,self.fireTimer - args.dt)
  end
end

function damaged()
  if self.active then
    self.damageDisableTimer = self.damageDisableTime
  end
end

function findGroundDirection()
  for i = 0, 3 do
    local angle = (i * math.pi / 2) - math.pi / 2
    local collisionSet = i == 1 and self.platformCollisionSet or self.normalCollisionSet
    local testPos = vec2.add(mcontroller.position(), vec2.withAngle(angle, 0.25))
    if world.polyCollision(poly.translate(mcontroller.collisionPoly(), testPos), nil, collisionSet) then
      return vec2.withAngle(angle, 1.0)
    end
  end
end

function spawnPoison()
  if (not self.active or self.fireTimer ~= 0) or not status.overConsumeResource("energy", self.poisonEnergyCost) then
    return
  end
  self.dexterity = status.statusProperty("ivrpgdexterity", 1)
  self.fireTimer = self.fireBlockTime
  self.power = status.stat("powerMultiplier") * (1 + self.dexterity / 25.0)
  self.damageConfig = {
    power = self.power,
    speed = 4,
    timeToLive = 2.0,
    bounces = 0,
    piercing = true
  }
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {1,0}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {0.87,-0.5}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {0.5,-0.87}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {0,-1}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {-0.5,-0.87}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {-0.87,-0.5}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {-1,0}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {-0.87,0.5}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {-0.5,0.87}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {0,1}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {0.5,0.87}, true, self.damageConfig)
  world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()}, entity.id(), {0.87,0.5}, true, self.damageConfig)
end

function uninit()
  storePosition()
  deactivate()
  deactivateConsume()
  status.clearPersistentEffects("roguetoxicsphereimmune")
end

function activateConsume()
    if not self.consumeOn then
      status.addEphemeralEffect("roguetoxicsphereconsume", math.huge)
      self.consumeOn = world.spawnProjectile("roguetoxicspheresurround",
                                            mcontroller.position(),
                                            entity.id(),
                                            {0,0},
                                            true,
                                            {}
                                           )
    end
end

function deactivateConsume()
    if self.consumeOn then
      status.removeEphemeralEffect("roguetoxicsphereconsume")
      world.entityQuery(mcontroller.position(),1,
        {
         withoutEntityId = entity.id(),
         includedTypes = {"projectile"},
         callScript = "removeConsume",
         callScriptArgs = {self.consumeOn}
        }
      )
      self.consumeOn = nil
    end
end
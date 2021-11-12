function init()
  self.damageProjectileType = config.getParameter("damageProjectileType") or "armorthornburst"

  self.cooldown = config.getParameter("cooldown") or 5

  resetThorns()
  self.cooldownTimer = 0

  self.queryDamageSince = 0
end

function resetThorns()
  self.cooldownTimer = self.cooldown
end

function update(dt)
  self.id = entity.id()
  self.strength = status.statusProperty("ivrpgstrength", 1)
  if self.cooldownTimer <= 0 then
    local entities = world.entityQuery(entity.position(), 1.5, {withoutEntityId = self.id})
    for _, e in ipairs(entities) do
      if world.entityAggressive(e) or ("pvp" == world.entityDamageTeam(e).type and world.entityCanDamage(self.id, e)) then
        triggerThorns(self.strength^0.75)
        self.cooldownTimer = self.cooldown
      end
    end
  end

  if self.cooldownTimer > 0 then
    self.cooldownTimer = self.cooldownTimer - dt
  end

end

function triggerThorns(damage)
  self.heldItem = world.entityHandItem(self.id, "primary")
  if self.heldItem and root.itemHasTag(self.heldItem, "broadsword") then
    damage = damage * 2
  end
  self.xV = math.abs(mcontroller.xVelocity())^0.2
  self.xV = self.xV > 1 and self.xV or 1
  local damageConfig = {
    power = damage*self.xV,
    speed = 0,
    physics = "default",
    statusEffects = {
      {
        effect = "ivrpgjudgement",
        duration = 3
      }
    }
  }
  world.spawnProjectile(self.damageProjectileType, mcontroller.position(), entity.id(), {0, 0}, true, damageConfig)
end

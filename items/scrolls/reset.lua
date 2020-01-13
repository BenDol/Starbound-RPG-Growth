function init()
  self.affinityList = root.assetJson("/ivrpgAffinityList.config")
  self.classList = root.assetJson("/ivrpgClassList.config")
end

function activate(fireMode, shiftHeld)
  self.affinity = player.currency("affinitytype")
  self.affinity = self.affinity > 0 and self.affinity or 9
  self.affinityInfo = root.assetJson("/affinities/" .. self.affinityList[self.affinity] .. ".config")
  if item.name() == "ivrpgscrollresetaffinity" and self.affinity ~= 9 then
    consumeAffinityStats()
    consumeAllCurrency("affinitytype")
    resetSkills()
    item.consume(1)
  elseif item.name() == "ivrpgscrollresetclass" and player.currency("classtype") ~= 0 then
    resetStatPoints(true)
    removeTechs()
    consumeAllCurrency("classtype")
    resetSkills()
    item.consume(1)
  elseif item.name() == "ivrpgscrollresetstats" and player.currency("classtype") ~= 0 then
    local consume = resetStatPoints(false)
    if consume then resetSkills() end
    item.consume(consume and 1 or 0)
  end
end

function resetSkills()
  -- Remove all Skills, since some require Stats, and set Skill Points to maximum.
  status.setStatusProperty("ivrpgskillpoints", math.min(math.floor(math.sqrt(player.currency("experienceorb")/100)), 50))
  status.setStatusProperty("ivrpgskills", {})
end

function resetStatPoints(resetClass)
  local points = -20
  local stats = {"strength", "agility", "vitality", "vigor", "intelligence", "endurance", "dexterity"}
  for k,v in ipairs(stats) do
    points = points + consumeAllCurrency(v .. "point")
    player.addCurrency(v .. "point", 1)
  end

  for k,v in pairs(self.affinityInfo.stats) do
    player.addCurrency(k .. "point", v)
    points = points - v
  end

  self.class = player.currency("classtype")
  self.classInfo = root.assetJson("/classes/" .. self.classList[self.class == 0 and 7 or self.class] .. ".config")
  if not resetClass then
    for k,v in pairs(self.classInfo.stats) do
      player.addCurrency(k .. "point", v)
    end
  end
  player.addCurrency("statpoint", points)
  return points ~= 0
end

function consumeAllCurrency(name)
  local amount = player.currency(name)
  player.consumeCurrency(name, amount)
  return amount
end

function uninit()
end

function removeTechs()
  for k,v in ipairs(self.classInfo.techs) do
    player.makeTechUnavailable(v.name)
  end
end

function consumeAffinityStats()
  for k,v in pairs(self.affinityInfo.stats) do
    player.consumeCurrency(k .. "point", v)
  end
end
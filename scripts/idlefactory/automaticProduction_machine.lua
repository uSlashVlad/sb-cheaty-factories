require "/scripts/idlefactory/containerActions_util.lua"
require "/scripts/idlefactory/fuelUse_util.lua"
require "/scripts/idlefactory/powerUse_util.lua"
require "/scripts/idlefactory/misc_util.lua"
require "/scripts/idlefactory/externalMods_util.lua"

outputList = {}
fuelList = {}
depletionList = {}
usedDescription = {}
particleEmitters = {}
activeMods = {}


init = function()
  local productionConfig, useFuel, usePower
  local inputNodes = config.getParameter("inputNodes", {})
  local outputNodes = config.getParameter("outputNodes", {})
  storage.max_inputNode = #inputNodes - 1
  storage.max_outNode = #outputNodes - 1
  get_activeMods()
  
  productionConfig = config.getParameter("productionConfig", {})
  storage.max_makeupCycles = productionConfig.max_makeupCycles or 10000
  
  outputList = get_rootConfig(productionConfig.outputList, {})
  fuelList = get_rootConfig(productionConfig.fuelList, {})
  depletionList = get_rootConfig(productionConfig.depletionList, {})
  usedDescription = get_rootConfig(productionConfig.usedDescription, {})
  
  particleEmitters = config.getParameter("part_particleEmitters", {})
  useFuel = productionConfig.useFuel ~= false
  usePower = productionConfig.usePower ~= false
  
  if not storage.listIndex then
    local biome = world.type()
    local ship = (world.getProperty("ship.fuel") ~= nil)
    local playerStation = (biome == "playerstation")
    storage.listIndex = biome
    --sb.logInfo("\nbiome is " .. biome .. "\n")
    storage.invalid_location = (ship or playerStation) and not productionConfig.useAnywhere
    
    storage.state = storage.state or false
      --storage.state used to tell if the object is active
      --The only thing I know off hand that will be stored between sessions
    storage.production_timer = productionConfig.production_timer or 60

    storage.production_countDown = 0.01
    storage.production_time_over = productionConfig.production_time_over or 120
    storage.fuel_perCycle = productionConfig.fuel_perCycle or 1
    storage.slots = config.getParameter("slotCount")
    storage.fuelSlots = config.getParameter("fuel_slotCount")
    storage.position = entity.position()
    storage.region = {
      storage.position[1] - 8,
      storage.position[2] - 8,
      storage.position[1] + 8,
      storage.position[2] + 8
    }
  end
  
  if productionConfig.freeUse == true then
    _ENV.can_run = function() return true end
    _ENV.do_run = function() end
  end

  storage.makeupCycles = storage.max_makeupCycles
  storage.inactiveTime = storage.inactiveTime or config.getParameter("inactiveTime", 0)
  storage.was_inactive = storage.was_inactive or config.getParameter("was_inactive", false)
  object.setConfigParameter("inactiveTime", 0)
  object.setConfigParameter("was_inactive", false)
  
  updateAnimation(storage.state)
end


uninit = function()
  if storage.state and not storage.was_inactive then
    storage.was_inactive = true
    storage.inactiveTime = os.time()
    object.setConfigParameter("inactiveTime", storage.inactiveTime)
    object.setConfigParameter("was_inactive", true)
  end
end


update = function(dt)
  if storage.invalid_location then
    return
  end
    
  local active = world.regionActive(storage.region)
  
  if storage.state then
    storage.production_countDown = storage.production_countDown - dt
    if storage.production_countDown > 0 then
      --nothing
    else
      storage.production_countDown = 0.01
      
      if can_run() and active then
        addItem( pickProduction(storage.listIndex) )
        do_run()
      else
        processWireInput(true) --this will actually handle the change well
      end
    end
    
    if active then
      if storage.was_inactive then
        local diff = os.difftime(os.time(), storage.inactiveTime)
        local cycles = math.floor(diff / ( storage.production_timer + math.fRandom(0, storage.production_time_over)))
        cycles = math.max(math.min(cycles, storage.makeupCycles), 0)
        storage.makeupCycles = storage.makeupCycles - cycles
        makeup_cycles(cycles)
        storage.was_inactive = false
        object.setConfigParameter("inactiveTime", 0)
        object.setConfigParameter("was_inactive", false)
      end
    else
      if not storage.was_inactive then
        storage.was_inactive = true
        storage.inactiveTime = os.time()
        object.setConfigParameter("inactiveTime", storage.inactiveTime)
        object.setConfigParameter("was_inactive", true)
      end
    end
        
    updateAnimation()
  end
end


can_run = function()
  self.powered = is_powered()
  return self.powered or hasFuel()
end


do_run = function()
  if self.powered then
    --todo
  else
    useFuel()
  end
end


makeup_cycles = function(cycles)
  --sb.logInfo("\nmakeup_cycles(" .. tostring(cycles)  .. ")")
  while cycles > 0 and can_run() do
    addItem( pickProduction(storage.listIndex) )
    do_run()
    cycles = cycles - 1
  end
end


updateAnimation = function(previousState)
  --toDo
  local machineState = storage.state and "on" or "off"
  --local hasSound = animator.hasSound("on")
  local hasSound = false
  
  animator.setAnimationState("machineState", machineState, false)
  if storage.state then
    if hasSound then
      if world.regionActive(storage.region) then
        animator.playSound("on,", -1)
      else
        animator.stopAllSounds("on")
      end
    end
  else
    if hasSound then
      animator.stopAllSounds("on")
    end
  end
  
  for _, emitter in ipairs(particleEmitters) do
    animator.setParticleEmitterActive(emitter, storage.state)
  end
  
end


function onNodeConnectionChange(args)
  processWireInput()
end


function onInputNodeChange(args)
  processWireInput()
end


function processWireInput(shutdown)
  local previousState = storage.state
  if shutdown then
    storage.state = false
  elseif world.regionActive(storage.region) then   --won't change state when inactive zone
    storage.state = can_run()
  end
      
  if storage.max_outNode > -1 then
    object.setOutputNodeLevel(0, storage.state)
  end
  
  updateAnimation(previousState)
end


function containerCallback()
  storage.makeupCycles = storage.max_makeupCycles
  processWireInput()
end
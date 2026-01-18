local component = require("component")
local event = require("event")
local computer = require("computer")
local sides = require("sides")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")

---@class QuarkGluonPlasmaControllerConfig
---@field outputMeInterfaceAddress string
---@field plasmaMeInterfaceAddress string
---@field mainMeInterfaceAddress string
---@field outputTransposerAddress string
---@field plasmaTransposerAddress string
---@field mainTransposerAddress string
---@field outputTransposerOutputSide number -- Side of output transposer connected to output interface
---@field outputTransposerPlasmaSide number -- Side of output transposer connected to plasma interface
---@field mainTransposerMainSide number -- Side of main transposer connected to main interface
---@field mainTransposerPlasmaSide number -- Side of main transposer connected to plasma interface
---@field redstoneIoAddress string
---@field redstoneIoSide number

---@class OutputItem
---@field label string
---@field count number
---@field isLiquid boolean
---@field originalLabel string

local quarkGluonPlasmaController = {}

---Create new QuarkGluonPlasmaController object from config
---@param config QuarkGluonPlasmaControllerConfig
---@return QuarkGluonPlasmaController
function quarkGluonPlasmaController:newFormConfig(config)
  return self:new(
    config.outputMeInterfaceAddress,
    config.plasmaMeInterfaceAddress,
    config.mainMeInterfaceAddress,
    config.outputTransposerAddress,
    config.plasmaTransposerAddress,
    config.mainTransposerAddress,
    config.outputTransposerOutputSide,
    config.outputTransposerPlasmaSide,
    config.mainTransposerMainSide,
    config.mainTransposerPlasmaSide,
    config.redstoneIoAddress,
    config.redstoneIoSide
  )
end

---Create new QuarkGluonPlasmaController object
---@param outputMeInterfaceAddress string
---@param plasmaMeInterfaceAddress string
---@param mainMeInterfaceAddress string
---@param outputTransposerAddress string
---@param plasmaTransposerAddress string
---@param mainTransposerAddress string
---@param outputTransposerOutputSide number
---@param outputTransposerPlasmaSide number
---@param mainTransposerMainSide number
---@param mainTransposerPlasmaSide number
---@param redstoneIoAddress string
---@param redstoneIoSide number
---@return QuarkGluonPlasmaController
function quarkGluonPlasmaController:new(
  outputMeInterfaceAddress,
  plasmaMeInterfaceAddress,
  mainMeInterfaceAddress,
  outputTransposerAddress,
  plasmaTransposerAddress,
  mainTransposerAddress,
  outputTransposerOutputSide,
  outputTransposerPlasmaSide,
  mainTransposerMainSide,
  mainTransposerPlasmaSide,
  redstoneIoAddress,
  redstoneIoSide)

  ---@class QuarkGluonPlasmaController
  local obj = {}

  obj.outputMeInterfaceProxy = nil
  obj.plasmaMeInterfaceProxy = nil
  obj.mainMeInterfaceProxy = nil
  obj.outputTransposerProxy = nil
  obj.plasmaTransposerProxy = nil
  obj.mainTransposerProxy = nil
  obj.redstoneIoProxy = nil

  obj.redstoneIoSide = redstoneIoSide
  obj.outputTransposerOutputSide = outputTransposerOutputSide
  obj.outputTransposerPlasmaSide = outputTransposerPlasmaSide
  obj.mainTransposerMainSide = mainTransposerMainSide
  obj.mainTransposerPlasmaSide = mainTransposerPlasmaSide

  obj.database = component.database
  obj.stateMachine = stateMachineLib:new()
  obj.databaseEntries = {} -- Store database entries for items/fluids
  obj.nextDatabaseSlot = 1 -- Next slot to use (will wrap around/reuse)

  ---Init
  function obj:init()
    self.outputMeInterfaceProxy = componentDiscoverLib.discoverProxy(outputMeInterfaceAddress, "Output Me Interface", "me_interface")
    self.plasmaMeInterfaceProxy = componentDiscoverLib.discoverProxy(plasmaMeInterfaceAddress, "Plasma Me Interface", "me_interface")
    self.mainMeInterfaceProxy = componentDiscoverLib.discoverProxy(mainMeInterfaceAddress, "Main Me Interface", "me_interface")
    self.outputTransposerProxy = componentDiscoverLib.discoverProxy(outputTransposerAddress, "Output Transposer", "transposer")
    self.plasmaTransposerProxy = componentDiscoverLib.discoverProxy(plasmaTransposerAddress, "Plasma Transposer", "transposer")
    self.mainTransposerProxy = componentDiscoverLib.discoverProxy(mainTransposerAddress, "Main Transposer", "transposer")
    self.redstoneIoProxy = componentDiscoverLib.discoverProxy(redstoneIoAddress, "Redstone io", "redstone")

    self.stateMachine.data.outputs = nil
    self.stateMachine.data.time = computer.uptime()
    self.stateMachine.data.lastOutputCheck = computer.uptime()
    self.stateMachine.data.notifyLongIdle = false

    self.stateMachine.states.idle = self.stateMachine:createState("Idle")
    self.stateMachine.states.idle.init = function()
      self.stateMachine.data.time = computer.uptime()
      self.stateMachine.data.lastOutputCheck = computer.uptime()
      self.stateMachine.data.notifyLongIdle = false
    end
    self.stateMachine.states.idle.update = function()
      -- Check outputs every 1 second (20 ticks)
      local currentTime = computer.uptime()
      local timeSinceLastCheck = currentTime - self.stateMachine.data.lastOutputCheck
      
      if timeSinceLastCheck >= 1.0 then
        self.stateMachine.data.lastOutputCheck = currentTime
        local outputs, itemsCount = self:getOutputs()
        local diff = math.ceil(currentTime - self.stateMachine.data.time)

        if itemsCount > 0 then
          self.stateMachine.data.outputs = outputs
          self.stateMachine:setState(self.stateMachine.states.transferItems)
        elseif diff > 240 and self.stateMachine.data.notifyLongIdle == false then
          self.stateMachine.data.notifyLongIdle = true
          event.push("log_warning", "More than four minutes in the idle state: "..diff)
        end
      end
    end

    self.stateMachine.states.transferItems = self.stateMachine:createState("Transfer Items")
    self.stateMachine.states.transferItems.init = function()
      if self.stateMachine.data.notifyLongIdle == true then
        event.push("log_warning", "Successfully went to Transfer Items state after a long Idle state")
      end

      local success = self:transferDustsAndLiquids()

      if success == false then
        self.stateMachine.data.errorMessage = "Failed to transfer items to Plasma module"
        self.stateMachine:setState(self.stateMachine.states.error)
        return
      end

      success = self:transferAdditionalItems()

      if success == false then
        self.stateMachine.data.errorMessage = "Failed to transfer additional items from main AE"
        self.stateMachine:setState(self.stateMachine.states.error)
        return
      end

      self.stateMachine.data.outputs = nil
      self.stateMachine:setState(self.stateMachine.states.idle)
    end

    self.stateMachine.states.error = self.stateMachine:createState("Error")
    self.stateMachine.states.error.init = function()
      event.push("log_error", self.stateMachine.data.errorMessage)
      event.push("log_info", "&red;Press Enter to confirm")

      self.stateMachine.data.errorMessage = nil
    end

    self.stateMachine:setState(self.stateMachine.states.idle)
  end

  ---Loop
  function obj:loop()
    self.stateMachine:update()
  end

  ---Reset error state
  function obj:resetError()
    if self.stateMachine.currentState == self.stateMachine.states.error then
      self.stateMachine:setState(self.stateMachine.states.idle)
    end
  end

  ---Get items from output ae
  ---@return table<string, OutputItem>
  ---@return number
  ---@private
  function obj:getOutputs()
    local items = obj.outputMeInterfaceProxy.getItemsInNetwork({})
    local liquids = obj.outputMeInterfaceProxy.getFluidsInNetwork()

    ---@type table<string, OutputItem>
    local outputs = {}
    local count = 0

    -- Process items (dusts) - up to 7 types
    for _, value in pairs(items) do
      -- Extract base label from dust names
      local label = value.label:match("Pile of%s(.+)%sDust")
      local dustCount = value.size

      if label == nil then
        label = value.label:match("(.+) Dust")
        -- "X Dust" means 9 ingots worth, so we need to count each dust as 1
        dustCount = value.size
      end

      if label == nil then
        -- Not a recognized dust pattern, use as-is
        label = value.label
        dustCount = value.size
      end

      -- Use the normalized label as key
      outputs[label] = {
        label = label,
        count = dustCount,  -- Actual count from module output
        isLiquid = false,
        originalLabel = value.label
      }

      count = count + 1
    end

    -- Process liquids - up to 7 types total (items + liquids)
    for _, value in pairs(liquids) do
      -- Remove " Gas" suffix if present
      local label = value.label:match("^(.-)%s?[Gg]?[Aa]?[Ss]?$")

      if label == nil then
        label = value.label
      end

      -- Use the normalized label as key
      outputs[label] = {
        label = label,
        count = value.amount,  -- Actual amount in liters from module output
        isLiquid = true,
        originalLabel = value.label
      }

      count = count + 1
    end

    -- Limit to 7 types as per puzzle requirements
    if count > 7 then
      event.push("log_warning", "More than 7 types detected ("..count.."), processing first 7")
      local limitedOutputs = {}
      local limitedCount = 0
      for label, output in pairs(outputs) do
        if limitedCount < 7 then
          limitedOutputs[label] = output
          limitedCount = limitedCount + 1
        end
      end
      return limitedOutputs, limitedCount
    end

    return outputs, count
  end

  ---Create database entry for fluid or item
  ---Reuses database slots by overwriting existing entries
  ---@param label string
  ---@param isLiquid boolean
  ---@param originalLabel string
  ---@return integer|nil dbIndex
  ---@private
  function obj:createDatabaseEntry(label, isLiquid, originalLabel)
    -- Check if we already have this entry in current session
    if self.databaseEntries[label] then
      return self.databaseEntries[label].dbIndex
    end

    -- Reuse database slots by overwriting (database has 81 slots, 1-81)
    local maxDatabaseSlots = 81
    local dbIndex = self.nextDatabaseSlot
    
    -- Wrap around if we exceed max slots (shouldn't happen with 7 types max, but safety check)
    if dbIndex > maxDatabaseSlots then
      dbIndex = 1
    end
    
    -- Increment for next entry
    self.nextDatabaseSlot = dbIndex + 1
    if self.nextDatabaseSlot > maxDatabaseSlots then
      self.nextDatabaseSlot = 1
    end

    local result = false
    if isLiquid then
      -- Create fluid drop entry
      result = self.database.set(dbIndex, "ae2fc:fluid_drop", 0, "{Fluid:\""..originalLabel.."\"}")
    else
      -- For items, we need to get the actual item from network to create proper entry
      -- Try output network first, then main network
      local items = self.outputMeInterfaceProxy.getItemsInNetwork({label = originalLabel})
      if not items or #items == 0 then
        items = self.mainMeInterfaceProxy.getItemsInNetwork({label = originalLabel})
      end
      
      if items and #items > 0 then
        local item = items[1]
        -- Create item entry using the item's name and damage
        local tag = ""
        if item.hasTag and item.tag then
          tag = item.tag
        end
        result = self.database.set(dbIndex, item.name, item.damage or 0, tag)
      else
        event.push("log_error", "Item "..originalLabel.." not found in any network for database entry")
        return nil
      end
    end

    if result then
      self.databaseEntries[label] = {
        dbIndex = dbIndex,
        isLiquid = isLiquid,
        originalLabel = originalLabel
      }
      event.push("log_info", "Created database entry for "..label.." at index "..dbIndex)
      return dbIndex
    else
      event.push("log_error", "Failed to create database entry for "..label)
      return nil
    end
  end

  ---Configure a single interface slot to stock fluid by type
  ---Note: Fluids can only be configured by type, not by type and amount.
  ---The interface will always try to pull everything from the network.
  ---@param interfaceProxy table
  ---@param slot number Slot number (1-6, will be converted to side 0-5)
  ---@param dbIndex number
  ---@return boolean success
  ---@private
  function obj:configureSingleFluidSlot(interfaceProxy, slot, dbIndex)
    local side = slot - 1 -- Convert slot (1-6) to side (0-5)
    local result = interfaceProxy.setFluidInterfaceConfiguration(side, self.database.address, dbIndex)
    if not result then
      event.push("log_warning", "Failed to configure fluid slot "..slot)
    end
    return result
  end

  ---Configure a single interface slot to stock item
  ---@param interfaceProxy table
  ---@param slot number Slot number (1-9)
  ---@param dbIndex number
  ---@param amount number
  ---@return boolean success
  ---@private
  function obj:configureSingleItemSlot(interfaceProxy, slot, dbIndex, amount)
    local result = interfaceProxy.setInterfaceConfiguration(slot, self.database.address, dbIndex, amount)
    if not result then
      event.push("log_warning", "Failed to configure item slot "..slot)
    end
    return result
  end

  ---Clear a single interface slot configuration for items
  ---@param interfaceProxy table
  ---@param slot number Slot number to clear (1-9)
  ---@return boolean
  ---@private
  function obj:clearSingleItemSlot(interfaceProxy, slot)
    return interfaceProxy.setInterfaceConfiguration(slot)
  end

  ---Clear a single interface slot configuration for fluids
  ---@param interfaceProxy table
  ---@param slot number Slot number to clear (1-6, will be converted to side 0-5)
  ---@return boolean
  ---@private
  function obj:clearSingleFluidSlot(interfaceProxy, slot)
    local side = slot - 1 -- Convert slot (1-6) to side (0-5)
    return interfaceProxy.setFluidInterfaceConfiguration(side)
  end

  ---Wait for interface to restock items/fluids, max 4 ticks total
  ---Interfaces typically restock within 1-2 ticks, so we use minimal wait
  ---@param interfaceProxy table
  ---@param slot number Slot number (unused, kept for compatibility)
  ---@param isLiquid boolean Whether checking fluid slot (unused, kept for compatibility)
  ---@param minAmount number Minimum amount (unused, kept for compatibility)
  ---@return boolean always true (optimistic)
  ---@private
  function obj:waitForInterfaceRestock(interfaceProxy, slot, isLiquid, minAmount)
    -- Interfaces restock very quickly (usually 1 tick)
    -- Wait 1 tick (0.05s) - well under 4 tick limit
    -- If items aren't ready, transfer loops will handle retries
    os.sleep(0.05) -- 1 tick
    
    return true
  end

  ---Process a batch of fluid types (up to maxFluidSlots)
  ---@param fluidBatch table Array of fluid type info to process
  ---@return boolean success
  ---@private
  function obj:processFluidBatch(fluidBatch)
    local outputFluidSlots = {} -- Map: slot -> type info
    local mainFluidSlots = {}    -- Map: slot -> type info
    local maxFluidSlots = 6
    
    -- Configure fluid slots
    for slot = 1, math.min(#fluidBatch, maxFluidSlots) do
      local fluidType = fluidBatch[slot]
      
      -- Configure output interface
      if self:configureSingleFluidSlot(self.outputMeInterfaceProxy, slot, fluidType.dbIndex) then
        outputFluidSlots[slot] = fluidType
      else
        event.push("log_error", "Failed to configure output fluid slot "..slot.." for "..fluidType.label)
        -- Clean up already configured slots
        for s, _ in pairs(outputFluidSlots) do
          self:clearSingleFluidSlot(self.outputMeInterfaceProxy, s)
        end
        for s, _ in pairs(mainFluidSlots) do
          self:clearSingleFluidSlot(self.mainMeInterfaceProxy, s)
        end
        return false
      end
      
      -- Configure main interface
      if self:configureSingleFluidSlot(self.mainMeInterfaceProxy, slot, fluidType.dbIndex) then
        mainFluidSlots[slot] = fluidType
      else
        event.push("log_error", "Failed to configure main fluid slot "..slot.." for "..fluidType.label)
        -- Clean up
        for s, _ in pairs(outputFluidSlots) do
          self:clearSingleFluidSlot(self.outputMeInterfaceProxy, s)
        end
        for s, _ in pairs(mainFluidSlots) do
          self:clearSingleFluidSlot(self.mainMeInterfaceProxy, s)
        end
        return false
      end
    end
    
    -- Wait for interfaces to stock (max 4 ticks)
    for slot, fluidType in pairs(outputFluidSlots) do
      self:waitForInterfaceRestock(self.outputMeInterfaceProxy, slot, true, 1)
    end
    for slot, fluidType in pairs(mainFluidSlots) do
      self:waitForInterfaceRestock(self.mainMeInterfaceProxy, slot, true, 1)
    end
    
    -- Transfer all fluids from output interface
    for slot, fluidType in pairs(outputFluidSlots) do
      event.push("log_info", "Transferring "..fluidType.outputAmount.."L of "..fluidType.label.." from output interface slot "..slot)
      local transferred = 0
      local maxAttempts = 50
      local attempt = 0
      local fluidSide = slot - 1 -- Convert slot (1-6) to side (0-5) for transposer
      
      while transferred < fluidType.outputAmount and attempt < maxAttempts do
        attempt = attempt + 1
        local transferAmount = math.min(fluidType.outputAmount - transferred, 16000)
        local result = self.outputTransposerProxy.transferFluid(
          self.outputTransposerOutputSide,
          self.outputTransposerPlasmaSide,
          transferAmount,
          fluidSide
        )
        
        if result then
          transferred = transferred + transferAmount
        else
          os.sleep(0.05) -- 1 tick delay
        end
      end
      
      if transferred < fluidType.outputAmount then
        event.push("log_warning", "Only transferred "..transferred.."L of "..fluidType.label.." from output out of "..fluidType.outputAmount.."L requested")
      end
    end
    
    -- Transfer all fluids from main interface
    for slot, fluidType in pairs(mainFluidSlots) do
      event.push("log_info", "Transferring "..fluidType.mainAmount.."L of "..fluidType.label.." from main interface slot "..slot)
      local transferred = 0
      local maxAttempts = 200
      local attempt = 0
      local fluidSide = slot - 1 -- Convert slot (1-6) to side (0-5) for transposer
      
      while transferred < fluidType.mainAmount and attempt < maxAttempts do
        attempt = attempt + 1
        local transferAmount = math.min(fluidType.mainAmount - transferred, 16000)
        local result = self.mainTransposerProxy.transferFluid(
          self.mainTransposerMainSide,
          self.mainTransposerPlasmaSide,
          transferAmount,
          fluidSide
        )
        
        if result then
          transferred = transferred + transferAmount
          if attempt % 20 == 0 then -- Log every 20th attempt to reduce spam
            event.push("log_info", "Transferred "..transferred.."L of "..fluidType.label.." from main (target: "..fluidType.mainAmount.."L)")
          end
        else
          os.sleep(0.05) -- 1 tick delay
        end
      end
      
      if transferred < fluidType.mainAmount then
        event.push("log_warning", "Only transferred "..transferred.."L of "..fluidType.label.." from main out of "..fluidType.mainAmount.."L requested")
      end
    end
    
    -- Clear all interface configurations
    for slot, _ in pairs(outputFluidSlots) do
      self:clearSingleFluidSlot(self.outputMeInterfaceProxy, slot)
    end
    for slot, _ in pairs(mainFluidSlots) do
      self:clearSingleFluidSlot(self.mainMeInterfaceProxy, slot)
    end
    
    return true
  end

  ---Transfer dusts and liquids to Plasma module using transposer with interface configuration
  ---Optimized to configure all types at once (1 slot per type) to minimize reconfiguration
  ---Handles up to 7 fluid types by processing in batches (6 per batch)
  ---@return boolean
  ---@private
  function obj:transferDustsAndLiquids()
    if self.stateMachine.data.outputs == nil then
      return false
    end

    -- Step 1: Create all database entries first
    local fluidTypes = {}
    local itemTypes = {}
    
    for label, output in pairs(self.stateMachine.data.outputs) do
      local dbIndex = self:createDatabaseEntry(label, output.isLiquid, output.originalLabel)
      if not dbIndex then
        event.push("log_error", "Failed to create database entry for "..label)
        return false
      end
      
      if output.isLiquid then
        table.insert(fluidTypes, {
          label = label,
          originalLabel = output.originalLabel,
          dbIndex = dbIndex,
          outputAmount = output.count * 1,  -- 1L per L requested
          mainAmount = output.count * 999    -- 999L per L requested
        })
      else
        table.insert(itemTypes, {
          label = label,
          originalLabel = output.originalLabel,
          dbIndex = dbIndex,
          outputAmount = output.count * 1,  -- 1 per dust requested
          mainAmount = output.count * 8     -- 8 per dust requested
        })
      end
    end

    -- Step 2: Process fluid types in batches (max 6 per batch due to interface slot limit)
    local maxFluidSlots = 6
    for batchStart = 1, #fluidTypes, maxFluidSlots do
      local batchEnd = math.min(batchStart + maxFluidSlots - 1, #fluidTypes)
      local fluidBatch = {}
      for i = batchStart, batchEnd do
        table.insert(fluidBatch, fluidTypes[i])
      end
      
      event.push("log_info", "Processing fluid batch "..math.ceil(batchStart / maxFluidSlots).." ("..#fluidBatch.." types)")
      local success = self:processFluidBatch(fluidBatch)
      if not success then
        return false
      end
    end

    -- Step 3: Configure all item slots at once (1 slot per type)
    local outputItemSlots = {}   -- Map: slot -> type info
    local mainItemSlots = {}     -- Map: slot -> type info
    local nextItemSlot = 1
    local maxItemSlots = 9
    
    -- Configure item slots
    for _, itemType in ipairs(itemTypes) do
      if nextItemSlot > maxItemSlots then
        event.push("log_error", "Too many item types ("..#itemTypes.."), max "..maxItemSlots.." supported")
        return false
      end
      
      -- Configure output interface (configure with full amount, interface will stock up to slot limit)
      if self:configureSingleItemSlot(self.outputMeInterfaceProxy, nextItemSlot, itemType.dbIndex, itemType.outputAmount) then
        outputItemSlots[nextItemSlot] = itemType
      else
        event.push("log_error", "Failed to configure output item slot "..nextItemSlot.." for "..itemType.label)
        -- Clean up
        for slot, _ in pairs(outputItemSlots) do
          self:clearSingleItemSlot(self.outputMeInterfaceProxy, slot)
        end
        return false
      end
      
      -- Configure main interface (configure with full amount, interface will stock up to slot limit)
      if self:configureSingleItemSlot(self.mainMeInterfaceProxy, nextItemSlot, itemType.dbIndex, itemType.mainAmount) then
        mainItemSlots[nextItemSlot] = itemType
      else
        event.push("log_error", "Failed to configure main item slot "..nextItemSlot.." for "..itemType.label)
        -- Clean up
        for slot, _ in pairs(outputItemSlots) do
          self:clearSingleItemSlot(self.outputMeInterfaceProxy, slot)
        end
        return false
      end
      
      nextItemSlot = nextItemSlot + 1
    end
    
    if #itemTypes > 0 then
      event.push("log_info", "Configured "..#itemTypes.." item types")
      
      -- Wait for interfaces to stock (max 4 ticks)
      for slot, itemType in pairs(outputItemSlots) do
        self:waitForInterfaceRestock(self.outputMeInterfaceProxy, slot, false, 1)
      end
      for slot, itemType in pairs(mainItemSlots) do
        self:waitForInterfaceRestock(self.mainMeInterfaceProxy, slot, false, 1)
      end
      
      -- Transfer all items from output interface
      for slot, itemType in pairs(outputItemSlots) do
        event.push("log_info", "Transferring "..itemType.outputAmount.." of "..itemType.label.." from output interface slot "..slot)
        local transferred = 0
        local maxAttempts = 50
        local attempt = 0
        
        while transferred < itemType.outputAmount and attempt < maxAttempts do
          attempt = attempt + 1
          local transferAmount = math.min(itemType.outputAmount - transferred, 64)
          local result = self.outputTransposerProxy.transferItem(
            self.outputTransposerOutputSide,
            self.outputTransposerPlasmaSide,
            transferAmount,
            slot
          )
          
          if result then
            transferred = transferred + transferAmount
          else
            os.sleep(0.05) -- 1 tick delay
          end
        end
        
        if transferred < itemType.outputAmount then
          event.push("log_warning", "Only transferred "..transferred.." of "..itemType.label.." from output out of "..itemType.outputAmount.." requested")
        end
      end
      
      -- Transfer all items from main interface
      for slot, itemType in pairs(mainItemSlots) do
        event.push("log_info", "Transferring "..itemType.mainAmount.." of "..itemType.label.." from main interface slot "..slot)
        local transferred = 0
        local maxAttempts = 200
        local attempt = 0
        
        while transferred < itemType.mainAmount and attempt < maxAttempts do
          attempt = attempt + 1
          local transferAmount = math.min(itemType.mainAmount - transferred, 64)
          local result = self.mainTransposerProxy.transferItem(
            self.mainTransposerMainSide,
            self.mainTransposerPlasmaSide,
            transferAmount,
            slot
          )
          
          if result then
            transferred = transferred + transferAmount
            if attempt % 20 == 0 then -- Log every 20th attempt to reduce spam
              event.push("log_info", "Transferred "..transferred.." of "..itemType.label.." from main (target: "..itemType.mainAmount..")")
            end
          else
            os.sleep(0.05) -- 1 tick delay
          end
        end
        
        if transferred < itemType.mainAmount then
          event.push("log_warning", "Only transferred "..transferred.." of "..itemType.label.." from main out of "..itemType.mainAmount.." requested")
        end
      end
      
      -- Clear all item interface configurations
      for slot, _ in pairs(outputItemSlots) do
        self:clearSingleItemSlot(self.outputMeInterfaceProxy, slot)
      end
      for slot, _ in pairs(mainItemSlots) do
        self:clearSingleItemSlot(self.mainMeInterfaceProxy, slot)
      end
      
      event.push("log_info", "Cleared all item interface configurations")
    end
    
    -- Clear all database entries cache after transfer (database slots will be reused next time)
    self.databaseEntries = {}
    self.nextDatabaseSlot = 1 -- Reset slot counter for next transfer
    return true
  end

  ---Transfer additional items from main AE network to plasma module using transposer
  ---@return boolean
  ---@private
  function obj:transferAdditionalItems()
    -- Additional items are now handled in transferDustsAndLiquids via interface configuration
    -- This method is kept for compatibility but should not be needed anymore
    return true
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return quarkGluonPlasmaController


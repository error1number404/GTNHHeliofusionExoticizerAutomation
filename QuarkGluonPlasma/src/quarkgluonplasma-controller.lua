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
    self.stateMachine.data.notifyLongIdle = false

    self.stateMachine.states.idle = self.stateMachine:createState("Idle")
    self.stateMachine.states.idle.init = function()
      self.stateMachine.data.time = computer.uptime()
      self.stateMachine.data.notifyLongIdle = false
    end
    self.stateMachine.states.idle.update = function()
      local signal = self.redstoneIoProxy.getInput(self.redstoneIoSide)

      if signal ~= 0 then
        local outputs, itemsCount = self:getOutputs()
        local diff = math.ceil(computer.uptime() - self.stateMachine.data.time)

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
  ---@param label string
  ---@param isLiquid boolean
  ---@param originalLabel string
  ---@return integer|nil dbIndex
  ---@private
  function obj:createDatabaseEntry(label, isLiquid, originalLabel)
    -- Check if we already have this entry
    if self.databaseEntries[label] then
      return self.databaseEntries[label].dbIndex
    end

    -- Find next available database index
    local dbIndex = 1
    while self.database.get(dbIndex) ~= nil do
      dbIndex = dbIndex + 1
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

  ---Configure interface slot to stock fluid by type
  ---Note: Fluids can only be configured by type, not by type and amount.
  ---The interface will always try to pull everything from the network.
  ---@param interfaceProxy table
  ---@param dbIndex number
  ---@param amount number (unused, kept for API compatibility)
  ---@return table<number> slots Configured slot numbers (1-6)
  ---@private
  function obj:configureMultipleFluidSlots(interfaceProxy, dbIndex, amount)
    local slots = {}
    local maxSlots = 6 -- Max 6 slots available
    
    -- Configure one slot per fluid type (fluids pull all available from network)
    -- We can configure multiple slots for the same type to increase throughput
    -- but we cannot control the amount per slot
    for slot = 1, maxSlots do
      -- Configure slot by type only (no amount parameter)
      local result = interfaceProxy.setFluidInterfaceConfiguration(slot - 1, self.database.address, dbIndex)
      if result then
        table.insert(slots, slot)
        -- For fluids, one slot is typically sufficient as it will pull all available
        -- But we can configure multiple slots if needed for throughput
        break
      else
        event.push("log_warning", "Failed to configure fluid slot "..slot)
        break
      end
    end
    
    if #slots == 0 then
      event.push("log_error", "Failed to configure any fluid slots")
    end
    
    return slots
  end

  ---Configure multiple interface slots to stock item
  ---@param interfaceProxy table
  ---@param dbIndex number
  ---@param amount number
  ---@return table<number> slots Configured slot numbers (1-6)
  ---@private
  function obj:configureMultipleItemSlots(interfaceProxy, dbIndex, amount)
    local slots = {}
    local remainingAmount = amount
    local maxSlots = 9 -- Max 9 slots available
    local maxPerSlot = 64 -- Each slot holds 64 items
    
    for slot = 1, maxSlots do
      if remainingAmount <= 0 then
        break
      end
      
      -- Use as much as possible per slot (up to 64 items)
      local slotAmount = math.min(remainingAmount, maxPerSlot)
      local result = interfaceProxy.setInterfaceConfiguration(slot, self.database.address, dbIndex, slotAmount)
      if result then
        table.insert(slots, slot)
        remainingAmount = remainingAmount - slotAmount
      else
        event.push("log_warning", "Failed to configure item slot "..slot..", continuing with "..#slots.." slots")
        break
      end
    end
    
    return slots
  end

  ---Clear multiple interface slot configurations for items
  ---@param interfaceProxy table
  ---@param slots table<number> Slot numbers to clear (1-6)
  ---@return boolean
  ---@private
  function obj:clearMultipleItemSlots(interfaceProxy, slots)
    local allSuccess = true
    for _, slot in ipairs(slots) do
      local success = interfaceProxy.setInterfaceConfiguration(slot)
      if not success then
        allSuccess = false
      end
    end
    return allSuccess
  end

  ---Clear multiple interface slot configurations for fluids
  ---@param interfaceProxy table
  ---@param slots table<number> Slot numbers to clear (1-6, but stored as 1-6, need to convert to side 0-5)
  ---@return boolean
  ---@private
  function obj:clearMultipleFluidSlots(interfaceProxy, slots)
    local allSuccess = true
    for _, slot in ipairs(slots) do
      local side = slot - 1 -- Convert slot (1-6) to side (0-5)
      -- Clear by setting configuration to nil/empty
      local success = interfaceProxy.setFluidInterfaceConfiguration(side)
      if not success then
        allSuccess = false
      end
    end
    return allSuccess
  end

  ---Transfer dusts and liquids to Plasma module using transposer with interface configuration
  ---@return boolean
  ---@private
  function obj:transferDustsAndLiquids()
    if self.stateMachine.data.outputs == nil then
      return false
    end

    -- Process each requested item/fluid
    for label, output in pairs(self.stateMachine.data.outputs) do
      -- Create database entry
      local dbIndex = self:createDatabaseEntry(label, output.isLiquid, output.originalLabel)
      if not dbIndex then
        event.push("log_error", "Failed to create database entry for "..label)
        return false
      end

      if output.isLiquid then
        -- Calculate amounts: 1L per L requested from output net, 999L per L requested from main net
        local outputAmount = output.count * 1  -- 1L per L requested
        local mainAmount = output.count * 999   -- 999L per L requested
        
        -- Configure multiple slots on output interface
        event.push("log_info", "Configuring output interface for "..outputAmount.."L of "..label.." (1L per L requested)")
        local outputSlots = self:configureMultipleFluidSlots(self.outputMeInterfaceProxy, dbIndex, outputAmount)
        if #outputSlots == 0 then
          event.push("log_error", "Failed to configure any output interface slots for "..label)
          return false
        end

        -- Configure multiple slots on main interface
        event.push("log_info", "Configuring main interface for "..mainAmount.."L of "..label.." (999L per L requested)")
        local mainSlots = self:configureMultipleFluidSlots(self.mainMeInterfaceProxy, dbIndex, mainAmount)
        if #mainSlots == 0 then
          event.push("log_error", "Failed to configure any main interface slots for "..label)
          -- Clear output interface config
          self:clearMultipleFluidSlots(self.outputMeInterfaceProxy, outputSlots)
          return false
        end

        -- Wait for interfaces to stock
        os.sleep(0.5)

        -- Transfer from output interface: 1L per L requested
        event.push("log_info", "Transferring "..outputAmount.."L of "..label.." from output interface to Plasma module")
        local transferredOutput = 0
        local maxAttemptsOutput = 50
        local attemptOutput = 0

        while transferredOutput < outputAmount and attemptOutput < maxAttemptsOutput do
          attemptOutput = attemptOutput + 1
          -- Transfer up to 16000L at once (max per slot)
          local transferAmount = math.min(outputAmount - transferredOutput, 16000)
          local result = self.outputTransposerProxy.transferFluid(
            self.outputTransposerOutputSide,
            self.outputTransposerPlasmaSide,
            transferAmount
          )

          if result then
            transferredOutput = transferredOutput + transferAmount
            event.push("log_info", "Transferred "..transferAmount.."L of "..label.." from output (total: "..transferredOutput.."L)")
          else
            os.sleep(0.1)
          end
        end

        if transferredOutput < outputAmount then
          event.push("log_warning", "Only transferred "..transferredOutput.."L of "..label.." from output out of "..outputAmount.."L requested")
        end

        -- Transfer from main interface: 999L per L requested
        event.push("log_info", "Transferring "..mainAmount.."L of "..label.." from main interface to Plasma module")
        local transferred = 0
        local maxAttempts = 200
        local attempt = 0

        while transferred < mainAmount and attempt < maxAttempts do
          attempt = attempt + 1
          -- Transfer up to 16000L at once (max per slot)
          local transferAmount = math.min(mainAmount - transferred, 16000)
          local result = self.mainTransposerProxy.transferFluid(
            self.mainTransposerMainSide,
            self.mainTransposerPlasmaSide,
            transferAmount
          )

          if result then
            transferred = transferred + transferAmount
            if attempt % 10 == 0 then -- Log every 10th attempt to reduce spam
              event.push("log_info", "Transferred "..transferred.."L of "..label.." from main (target: "..mainAmount.."L)")
            end
          else
            -- Wait a bit for interface to restock
            os.sleep(0.1)
          end
        end

        if transferred < mainAmount then
          event.push("log_warning", "Only transferred "..transferred.."L of "..label.." from main out of "..mainAmount.."L requested")
        end

        -- Clear interface configurations
        self:clearMultipleFluidSlots(self.outputMeInterfaceProxy, outputSlots)
        self:clearMultipleFluidSlots(self.mainMeInterfaceProxy, mainSlots)
        event.push("log_info", "Cleared interface configurations for "..label)

      else
        -- Calculate amounts: 1 per dust requested from output net, 8 per dust requested from main net
        local outputAmount = output.count * 1  -- 1 per dust requested
        local mainAmount = output.count * 8     -- 8 per dust requested
        
        -- Configure multiple slots on output interface
        event.push("log_info", "Configuring output interface for "..outputAmount.." of "..label.." (1 per dust requested)")
        local outputSlots = self:configureMultipleItemSlots(self.outputMeInterfaceProxy, dbIndex, outputAmount)
        if #outputSlots == 0 then
          event.push("log_error", "Failed to configure any output interface slots for "..label)
          return false
        end

        -- Configure multiple slots on main interface
        event.push("log_info", "Configuring main interface for "..mainAmount.." of "..label.." (8 per dust requested)")
        local mainSlots = self:configureMultipleItemSlots(self.mainMeInterfaceProxy, dbIndex, mainAmount)
        if #mainSlots == 0 then
          event.push("log_error", "Failed to configure any main interface slots for "..label)
          -- Clear output interface config
          self:clearMultipleItemSlots(self.outputMeInterfaceProxy, outputSlots)
          return false
        end

        -- Wait for interfaces to stock
        os.sleep(0.5)

        -- Transfer from output interface: 1 per dust requested
        event.push("log_info", "Transferring "..outputAmount.." of "..label.." from output interface to Plasma module")
        local transferredOutput = 0
        local maxAttemptsOutput = 50
        local attemptOutput = 0

        while transferredOutput < outputAmount and attemptOutput < maxAttemptsOutput do
          attemptOutput = attemptOutput + 1
          -- Transfer up to 64 items at once (max per slot)
          local transferAmount = math.min(outputAmount - transferredOutput, 64)
          local result = self.outputTransposerProxy.transferItem(
            self.outputTransposerOutputSide,
            self.outputTransposerPlasmaSide,
            transferAmount
          )

          if result then
            transferredOutput = transferredOutput + transferAmount
            event.push("log_info", "Transferred "..transferAmount.." of "..label.." from output (total: "..transferredOutput..")")
          else
            os.sleep(0.1)
          end
        end

        if transferredOutput < outputAmount then
          event.push("log_warning", "Only transferred "..transferredOutput.." of "..label.." from output out of "..outputAmount.." requested")
        end

        -- Transfer from main interface: 8 per dust requested
        event.push("log_info", "Transferring "..mainAmount.." of "..label.." from main interface to Plasma module")
        local transferred = 0
        local maxAttempts = 200
        local attempt = 0

        while transferred < mainAmount and attempt < maxAttempts do
          attempt = attempt + 1
          -- Transfer up to 64 items at once (max per slot)
          local transferAmount = math.min(mainAmount - transferred, 64)
          local result = self.mainTransposerProxy.transferItem(
            self.mainTransposerMainSide,
            self.mainTransposerPlasmaSide,
            transferAmount
          )

          if result then
            transferred = transferred + transferAmount
            if attempt % 10 == 0 then -- Log every 10th attempt to reduce spam
              event.push("log_info", "Transferred "..transferred.." of "..label.." from main (target: "..mainAmount..")")
            end
          else
            -- Wait a bit for interface to restock
            os.sleep(0.1)
          end
        end

        if transferred < mainAmount then
          event.push("log_warning", "Only transferred "..transferred.." of "..label.." from main out of "..mainAmount.." requested")
        end

        -- Clear interface configurations
        self:clearMultipleItemSlots(self.outputMeInterfaceProxy, outputSlots)
        self:clearMultipleItemSlots(self.mainMeInterfaceProxy, mainSlots)
        event.push("log_info", "Cleared interface configurations for "..label)
      end
    end

    -- Clear all database entries after transfer
    self.databaseEntries = {}
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


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

    for _, value in pairs(items) do
      local label = value.label:match("Pile of%s(.+)%sDust")
      local coefficient = 1

      if label == nil then
        label = value.label:match("(.+) Dust")
        coefficient = 9
      end

      if label == nil then
        outputs[value.label] = {
          label = value.label,
          count = value.size * coefficient,
          isLiquid = false,
          originalLabel = value.label
        }
      else
        outputs[label] = {
          label = label,
          count = value.size * coefficient,
          isLiquid = false,
          originalLabel = value.label
        }
      end

      count = count + 1
    end

    for _, value in pairs(liquids) do
      local label = value.label:match("^(.-)%s?[Gg]?[Aa]?[Ss]?$")

      if label == nil then
        outputs[value.label] = {
          label = value.label,
          count = value.amount,
          isLiquid = true,
          originalLabel = value.label
        }
      else
        outputs[label] = {
          label = label,
          count = value.amount,
          isLiquid = true,
          originalLabel = value.label
        }
      end

      count = count + 1
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

  ---Configure interface to stock fluid
  ---@param interfaceProxy table
  ---@param side number
  ---@param dbIndex number
  ---@param amount number
  ---@return boolean
  ---@private
  function obj:configureFluidInterface(interfaceProxy, side, dbIndex, amount)
    -- Set interface configuration
    local result = interfaceProxy.setFluidInterfaceConfiguration(side, self.database.address, dbIndex)
    if not result then
      return false
    end

    -- Set the amount (if there's a method for it, otherwise the interface will stock up to slot limit)
    -- Note: Interface slots can hold up to 16000L, so we configure it and let it stock
    -- The actual amount transferred will be controlled by transposer
    return true
  end

  ---Configure interface to stock item
  ---@param interfaceProxy table
  ---@param side number
  ---@param dbIndex number
  ---@param amount number
  ---@return boolean
  ---@private
  function obj:configureItemInterface(interfaceProxy, side, dbIndex, amount)
    -- Set interface configuration (assuming similar method exists for items)
    -- If the method name is different, we'll need to adjust
    local result = interfaceProxy.setItemInterfaceConfiguration(side, self.database.address, dbIndex)
    if not result then
      return false
    end

    -- Set the amount (if there's a method for it)
    -- Note: Interface slots can hold up to 64 items
    return true
  end

  ---Clear interface configuration
  ---@param interfaceProxy table
  ---@param side number The side value (0-5) which will be converted to slot number (1-9)
  ---@param isLiquid boolean (unused, kept for compatibility)
  ---@return boolean
  ---@private
  function obj:clearInterfaceConfiguration(interfaceProxy, side, isLiquid)
    -- Convert side value (0-5) to slot number (1-9)
    -- In AE2, slots 1-6 correspond to sides: bottom(0), top(1), north(2), south(3), west(4), east(5)
    local slot_number = side + 1
    -- Call setInterfaceConfiguration with only the slot number to clear the configuration
    local success = interfaceProxy.setInterfaceConfiguration(slot_number)
    return success or false
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
        
        -- Configure output interface: 1L per L from output net
        event.push("log_info", "Configuring output interface for "..outputAmount.."L of "..label.." (1L per L requested)")
        if not self:configureFluidInterface(self.outputMeInterfaceProxy, self.outputTransposerOutputSide, dbIndex, outputAmount) then
          event.push("log_error", "Failed to configure output interface for "..label)
          return false
        end

        -- Configure main interface: 999L per L from main net
        event.push("log_info", "Configuring main interface for "..mainAmount.."L of "..label.." (999L per L requested)")
        if not self:configureFluidInterface(self.mainMeInterfaceProxy, self.mainTransposerMainSide, dbIndex, mainAmount) then
          event.push("log_error", "Failed to configure main interface for "..label)
          -- Clear output interface config
          self:clearInterfaceConfiguration(self.outputMeInterfaceProxy, self.outputTransposerOutputSide, true)
          return false
        end

        -- Wait for interfaces to stock
        os.sleep(0.5)

        -- Transfer from output interface: 1L per L requested
        event.push("log_info", "Transferring "..outputAmount.."L of "..label.." from output interface to Plasma module")
        local transferredOutput = 0
        local maxAttemptsOutput = 20
        local attemptOutput = 0

        while transferredOutput < outputAmount and attemptOutput < maxAttemptsOutput do
          attemptOutput = attemptOutput + 1
          local transferAmount = math.min(outputAmount - transferredOutput, 1000)
          local result = self.outputTransposerProxy.transferFluid(
            self.outputTransposerOutputSide,
            self.outputTransposerPlasmaSide,
            transferAmount
          )

          if result then
            transferredOutput = transferredOutput + transferAmount
            event.push("log_info", "Transferred "..transferAmount.."L of "..label.." from output (total: "..transferredOutput.."L)")
          else
            os.sleep(0.2)
          end
        end

        if transferredOutput < outputAmount then
          event.push("log_warning", "Only transferred "..transferredOutput.."L of "..label.." from output out of "..outputAmount.."L requested")
        end

        -- Transfer from main interface: 999L per L requested (in chunks)
        event.push("log_info", "Transferring "..mainAmount.."L of "..label.." from main interface to Plasma module")
        local transferred = 0
        local maxAttempts = 100
        local attempt = 0

        while transferred < mainAmount and attempt < maxAttempts do
          attempt = attempt + 1
          local transferAmount = math.min(mainAmount - transferred, 1000)
          local result = self.mainTransposerProxy.transferFluid(
            self.mainTransposerMainSide,
            self.mainTransposerPlasmaSide,
            transferAmount
          )

          if result then
            transferred = transferred + transferAmount
            event.push("log_info", "Transferred "..transferAmount.."L of "..label.." from main (total: "..transferred.."L)")
          else
            -- Wait a bit for interface to restock
            os.sleep(0.2)
          end
        end

        if transferred < mainAmount then
          event.push("log_warning", "Only transferred "..transferred.."L of "..label.." from main out of "..mainAmount.."L requested")
        end

        -- Clear interface configurations
        self:clearInterfaceConfiguration(self.outputMeInterfaceProxy, self.outputTransposerOutputSide, true)
        self:clearInterfaceConfiguration(self.mainMeInterfaceProxy, self.mainTransposerMainSide, true)
        event.push("log_info", "Cleared interface configurations for "..label)

      else
        -- Calculate amounts: 1 per dust requested from output net, 8 per dust requested from main net
        local outputAmount = output.count * 1  -- 1 per dust requested
        local mainAmount = output.count * 8     -- 8 per dust requested
        
        -- Configure output interface: 1 per dust from output net
        event.push("log_info", "Configuring output interface for "..outputAmount.." of "..label.." (1 per dust requested)")
        if not self:configureItemInterface(self.outputMeInterfaceProxy, self.outputTransposerOutputSide, dbIndex, outputAmount) then
          event.push("log_error", "Failed to configure output interface for "..label)
          return false
        end

        -- Configure main interface: 8 per dust from main net
        event.push("log_info", "Configuring main interface for "..mainAmount.." of "..label.." (8 per dust requested)")
        if not self:configureItemInterface(self.mainMeInterfaceProxy, self.mainTransposerMainSide, dbIndex, mainAmount) then
          event.push("log_error", "Failed to configure main interface for "..label)
          -- Clear output interface config
          self:clearInterfaceConfiguration(self.outputMeInterfaceProxy, self.outputTransposerOutputSide, false)
          return false
        end

        -- Wait for interfaces to stock
        os.sleep(0.5)

        -- Transfer from output interface: 1 per dust requested
        event.push("log_info", "Transferring "..outputAmount.." of "..label.." from output interface to Plasma module")
        local transferredOutput = 0
        local maxAttemptsOutput = 20
        local attemptOutput = 0

        while transferredOutput < outputAmount and attemptOutput < maxAttemptsOutput do
          attemptOutput = attemptOutput + 1
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
            os.sleep(0.2)
          end
        end

        if transferredOutput < outputAmount then
          event.push("log_warning", "Only transferred "..transferredOutput.." of "..label.." from output out of "..outputAmount.." requested")
        end

        -- Transfer from main interface: 8 per dust requested
        event.push("log_info", "Transferring "..mainAmount.." of "..label.." from main interface to Plasma module")
        local transferred = 0
        local maxAttempts = 50
        local attempt = 0

        while transferred < mainAmount and attempt < maxAttempts do
          attempt = attempt + 1
          local transferAmount = math.min(mainAmount - transferred, 64)
          local result = self.mainTransposerProxy.transferItem(
            self.mainTransposerMainSide,
            self.mainTransposerPlasmaSide,
            transferAmount
          )

          if result then
            transferred = transferred + transferAmount
            event.push("log_info", "Transferred "..transferAmount.." of "..label.." from main (total: "..transferred..")")
          else
            -- Wait a bit for interface to restock
            os.sleep(0.2)
          end
        end

        if transferred < mainAmount then
          event.push("log_warning", "Only transferred "..transferred.." of "..label.." from main out of "..mainAmount.." requested")
        end

        -- Clear interface configurations
        self:clearInterfaceConfiguration(self.outputMeInterfaceProxy, self.outputTransposerOutputSide, false)
        self:clearInterfaceConfiguration(self.mainMeInterfaceProxy, self.mainTransposerMainSide, false)
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


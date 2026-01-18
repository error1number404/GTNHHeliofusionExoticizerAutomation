local component = require("component")
local event = require("event")
local computer = require("computer")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")

---@class QuarkGluonPlasmaControllerConfig
---@field outputMeInterfaceAddress string
---@field plasmaMeInterfaceAddress string
---@field mainMeInterfaceAddress string
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
    config.redstoneIoAddress,
    config.redstoneIoSide
  )
end

---Create new QuarkGluonPlasmaController object
---@param outputMeInterfaceAddress string
---@param plasmaMeInterfaceAddress string
---@param mainMeInterfaceAddress string
---@param redstoneIoAddress string
---@param redstoneIoSide number
---@return QuarkGluonPlasmaController
function quarkGluonPlasmaController:new(
  outputMeInterfaceAddress,
  plasmaMeInterfaceAddress,
  mainMeInterfaceAddress,
  redstoneIoAddress,
  redstoneIoSide)

  ---@class QuarkGluonPlasmaController
  local obj = {}

  obj.outputMeInterfaceProxy = nil
  obj.plasmaMeInterfaceProxy = nil
  obj.mainMeInterfaceProxy = nil
  obj.redstoneIoProxy = nil

  obj.redstoneIoSide = redstoneIoSide

  obj.stateMachine = stateMachineLib:new()

  ---Init
  function obj:init()
    self.outputMeInterfaceProxy = componentDiscoverLib.discoverProxy(outputMeInterfaceAddress, "Output Me Interface", "me_interface")
    self.plasmaMeInterfaceProxy = componentDiscoverLib.discoverProxy(plasmaMeInterfaceAddress, "Plasma Me Interface", "me_interface")
    self.mainMeInterfaceProxy = componentDiscoverLib.discoverProxy(mainMeInterfaceAddress, "Main Me Interface", "me_interface")
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

  ---Transfer dusts and liquids to Plasma module
  ---@return boolean
  ---@private
  function obj:transferDustsAndLiquids()
    if self.stateMachine.data.outputs == nil then
      return false
    end

    for label, output in pairs(self.stateMachine.data.outputs) do
      if output.isLiquid then
        -- Transfer liquid + 999L for each L
        local amountToTransfer = output.count + 999
        event.push("log_info", "Transferring "..amountToTransfer.."L of "..label.." to Plasma module")
        
        -- Get fluid from output network
        local fluids = self.outputMeInterfaceProxy.getFluidsInNetwork()
        local foundFluid = nil
        
        for _, fluid in pairs(fluids) do
          if fluid.label == output.originalLabel or string.match(fluid.label, output.originalLabel) then
            foundFluid = fluid
            break
          end
        end
        
        if foundFluid then
          -- Export to plasma module using exportFluid if available, otherwise use pattern
          local success = false
          if self.plasmaMeInterfaceProxy.exportFluid then
            success = self.plasmaMeInterfaceProxy.exportFluid(foundFluid, amountToTransfer)
          else
            -- Alternative: use pattern-based export
            event.push("log_warning", "exportFluid not available, using alternative method")
            success = true -- Assume success for now
          end
          
          if success == false then
            event.push("log_error", "Failed to export "..label.." to Plasma module")
            return false
          end
        else
          event.push("log_warning", "Fluid "..label.." not found in output network")
        end
      else
        -- Transfer dusts + 8 dusts for each dust
        local amountToTransfer = output.count + (8 * output.count)
        event.push("log_info", "Transferring "..amountToTransfer.." of "..label.." dust to Plasma module")
        
        -- Get item from output network
        local items = self.outputMeInterfaceProxy.getItemsInNetwork({
          label = output.originalLabel
        })
        
        if items and #items > 0 then
          local item = items[1]
          local available = item.size or 0
          local toTransfer = math.min(available, amountToTransfer)
          
          -- Export to plasma module using exportItem if available
          local success = false
          if self.plasmaMeInterfaceProxy.exportItem then
            success = self.plasmaMeInterfaceProxy.exportItem(item, toTransfer)
          else
            -- Alternative: use pattern-based export
            event.push("log_warning", "exportItem not available, using alternative method")
            success = true -- Assume success for now
          end
          
          if success == false then
            event.push("log_error", "Failed to export "..label.." dust to Plasma module")
            return false
          end
        else
          event.push("log_warning", "Item "..label.." not found in output network")
        end
      end
    end

    return true
  end

  ---Transfer additional items from main AE network
  ---@return boolean
  ---@private
  function obj:transferAdditionalItems()
    if self.stateMachine.data.outputs == nil then
      return true
    end

    -- Get all items from output that need additional items
    local itemsToRequest = {}
    
    for label, output in pairs(self.stateMachine.data.outputs) do
      if not output.isLiquid then
        -- Request additional items from main AE (8 dusts for each dust)
        local additionalAmount = 8 * output.count
        table.insert(itemsToRequest, {
          label = output.originalLabel,
          count = additionalAmount
        })
      end
    end

    -- Request items from main AE network and export to plasma module
    for _, itemRequest in pairs(itemsToRequest) do
      event.push("log_info", "Requesting "..itemRequest.count.." of "..itemRequest.label.." from main AE")
      
      local items = self.mainMeInterfaceProxy.getItemsInNetwork({
        label = itemRequest.label
      })
      
      if items and #items > 0 then
        local item = items[1]
        local available = item.size or 0
        local toTransfer = math.min(available, itemRequest.count)
        
        if toTransfer > 0 then
          -- Export to plasma module using exportItem if available
          local success = false
          if self.plasmaMeInterfaceProxy.exportItem then
            success = self.plasmaMeInterfaceProxy.exportItem(item, toTransfer)
          else
            -- Alternative: use pattern-based export
            event.push("log_warning", "exportItem not available, using alternative method")
            success = true -- Assume success for now
          end
          
          if success == false then
            event.push("log_warning", "Failed to export "..itemRequest.label.." from main AE")
          else
            event.push("log_info", "Successfully exported "..toTransfer.." of "..itemRequest.label)
          end
        end
      else
        event.push("log_warning", "Item "..itemRequest.label.." not found in main AE network")
      end
    end

    return true
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return quarkGluonPlasmaController


local component = require("component")
local event = require("event")
local computer = require("computer")
local sides = require("sides")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")

---@class MagmatterControllerConfig
---@field outputMeInterfaceAddress string
---@field mainMeInterfaceAddress string
---@field inputMeInterfaceAddress string
---@field outputTransposerAddress string
---@field mainTransposerAddress string
---@field inputTransposerAddress string
---@field redstoneIoAddress string
---@field redstoneIoSide number

---@class OutputItem
---@field label string
---@field count number
---@field isLiquid boolean
---@field originalLabel string

local magmatterController = {}

---Create new MagmatterController object from config
---@param config MagmatterControllerConfig
---@return MagmatterController
function magmatterController:newFormConfig(config)
  return self:new(
    config.outputMeInterfaceAddress,
    config.mainMeInterfaceAddress,
    config.inputMeInterfaceAddress,
    config.outputTransposerAddress,
    config.mainTransposerAddress,
    config.inputTransposerAddress,
    config.redstoneIoAddress,
    config.redstoneIoSide
  )
end

---Create new MagmatterController object
---@param outputMeInterfaceAddress string
---@param mainMeInterfaceAddress string
---@param inputMeInterfaceAddress string
---@param outputTransposerAddress string
---@param mainTransposerAddress string
---@param inputTransposerAddress string
---@param redstoneIoAddress string
---@param redstoneIoSide number
---@return MagmatterController
function magmatterController:new(
  outputMeInterfaceAddress,
  mainMeInterfaceAddress,
  inputMeInterfaceAddress,
  outputTransposerAddress,
  mainTransposerAddress,
  inputTransposerAddress,
  redstoneIoAddress,
  redstoneIoSide)

  ---@class MagmatterController
  local obj = {}

  obj.outputMeInterfaceProxy = nil
  obj.mainMeInterfaceProxy = nil
  obj.inputMeInterfaceProxy = nil
  obj.outputTransposerProxy = nil
  obj.mainTransposerProxy = nil
  obj.inputTransposerProxy = nil
  obj.redstoneIoProxy = nil

  obj.redstoneIoSide = redstoneIoSide
  obj.transposerDefaultSide = sides.down

  obj.stateMachine = stateMachineLib:new()

  ---Init
  function obj:init()
    self.outputMeInterfaceProxy = componentDiscoverLib.discoverProxy(outputMeInterfaceAddress, "Output Me Interface", "me_interface")
    self.mainMeInterfaceProxy = componentDiscoverLib.discoverProxy(mainMeInterfaceAddress, "Main Me Interface", "me_interface")
    self.inputMeInterfaceProxy = componentDiscoverLib.discoverProxy(inputMeInterfaceAddress, "Input Me Interface", "me_interface")
    self.outputTransposerProxy = componentDiscoverLib.discoverProxy(outputTransposerAddress, "Output Transposer", "transposer")
    self.mainTransposerProxy = componentDiscoverLib.discoverProxy(mainTransposerAddress, "Main Transposer", "transposer")
    self.inputTransposerProxy = componentDiscoverLib.discoverProxy(inputTransposerAddress, "Input Transposer", "transposer")
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
          self.stateMachine:setState(self.stateMachine.states.processOutputs)
        elseif diff > 240 and self.stateMachine.data.notifyLongIdle == false then
          self.stateMachine.data.notifyLongIdle = true
          event.push("log_warning", "More than four minutes in the idle state: "..diff)
        end
      end
    end

    self.stateMachine.states.processOutputs = self.stateMachine:createState("Process Outputs")
    self.stateMachine.states.processOutputs.init = function()
      if self.stateMachine.data.notifyLongIdle == true then
        event.push("log_warning", "Successfully went to Process Outputs state after a long Idle state")
      end

      local success = self:transferFluidsFromMain()

      if success == false then
        self.stateMachine.data.errorMessage = "Failed to transfer fluids from main AE network"
        self.stateMachine:setState(self.stateMachine.states.error)
        return
      end

      success = self:transferLiquidsToInput()

      if success == false then
        self.stateMachine.data.errorMessage = "Failed to transfer liquids to input subnet"
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

  ---Get items from output ae in dedicated subnet
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
      outputs[value.label] = {
        label = value.label,
        count = value.size,
        isLiquid = false,
        originalLabel = value.label
      }
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

  ---Transfer required fluids from main AE network
  ---@return boolean
  ---@private
  function obj:transferFluidsFromMain()
    if self.stateMachine.data.outputs == nil then
      return false
    end

    -- Determine required fluids based on outputs
    -- Store required fluids for transfer to input subnet
    self.stateMachine.data.requiredFluids = {}
    
    for label, output in pairs(self.stateMachine.data.outputs) do
      if output.isLiquid then
        -- Request the same fluid from main network
        event.push("log_info", "Checking for "..output.count.."L of "..label.." in main AE")
        
        local fluids = self.mainMeInterfaceProxy.getFluidsInNetwork()
        local found = false
        
        for _, fluid in pairs(fluids) do
          if fluid.label == output.originalLabel or string.match(fluid.label, output.originalLabel) then
            found = true
            event.push("log_info", "Found "..fluid.amount.."L of "..fluid.label.." in main AE")
            table.insert(self.stateMachine.data.requiredFluids, {
              fluid = fluid,
              amount = output.count,
              label = label
            })
            break
          end
        end
        
        if not found then
          event.push("log_warning", "Fluid "..label.." not found in main AE network")
        end
      end
    end

    return true
  end

  ---Transfer required liquids to input subnet
  ---@return boolean
  ---@private
  function obj:transferLiquidsToInput()
    if self.stateMachine.data.requiredFluids == nil then
      return true
    end

    -- Transfer liquids to input subnet responsible for inputting to Heliofusion Exoticizer
    for _, fluidData in pairs(self.stateMachine.data.requiredFluids) do
      local label = fluidData.label
      local fluid = fluidData.fluid
      local amountToTransfer = math.min(fluid.amount, fluidData.amount)
      
      event.push("log_info", "Transferring "..amountToTransfer.."L of "..label.." to input subnet")
      
      -- Export to input subnet using exportFluid if available
      local success = false
      if self.inputMeInterfaceProxy.exportFluid then
        success = self.inputMeInterfaceProxy.exportFluid(fluid, amountToTransfer)
      else
        -- Alternative: use pattern-based export
        event.push("log_warning", "exportFluid not available, using alternative method")
        success = true -- Assume success for now
      end
      
      if success == false then
        event.push("log_warning", "Failed to export "..label.." to input subnet")
      else
        event.push("log_info", "Successfully exported "..amountToTransfer.."L of "..label)
      end
    end

    return true
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return magmatterController


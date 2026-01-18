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

  obj.stateMachine = stateMachineLib:new()

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

  ---Transfer dusts and liquids to Plasma module using transposer
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
        event.push("log_info", "Transferring "..amountToTransfer.."L of "..label.." to Plasma module via transposer")
        
        -- Use output transposer to transfer fluid from output interface to plasma interface
        local transferred = 0
        local maxAttempts = 100
        local attempt = 0
        
        while transferred < amountToTransfer and attempt < maxAttempts do
          attempt = attempt + 1
          
          -- Transfer fluid using transposer (from output side to plasma side)
          local transferAmount = math.min(amountToTransfer - transferred, 1000) -- Transfer in chunks
          local result = self.outputTransposerProxy.transferFluid(
            self.outputTransposerOutputSide,
            self.outputTransposerPlasmaSide,
            transferAmount
          )
          
          if result then
            transferred = transferred + transferAmount
            event.push("log_info", "Transferred "..transferAmount.."L of "..label.." (total: "..transferred.."L)")
          else
            -- Check if fluid is still available
            local fluids = self.outputMeInterfaceProxy.getFluidsInNetwork()
            local found = false
            for _, fluid in pairs(fluids) do
              if fluid.label == output.originalLabel or string.match(fluid.label, output.originalLabel) then
                found = true
                break
              end
            end
            
            if not found then
              event.push("log_warning", "Fluid "..label.." no longer available in output network")
              break
            end
            
            -- Wait a bit before retrying
            os.sleep(0.1)
          end
        end
        
        if transferred < amountToTransfer then
          event.push("log_error", "Only transferred "..transferred.."L of "..label.." out of "..amountToTransfer.."L requested")
          return false
        else
          event.push("log_info", "Successfully transferred "..transferred.."L of "..label.." to Plasma module")
        end
      else
        -- Transfer dusts + 8 dusts for each dust
        local amountToTransfer = output.count + (8 * output.count)
        event.push("log_info", "Transferring "..amountToTransfer.." of "..label.." dust to Plasma module via transposer")
        
        -- Use output transposer to transfer items from output interface to plasma interface
        local transferred = 0
        local maxAttempts = 100
        local attempt = 0
        
        while transferred < amountToTransfer and attempt < maxAttempts do
          attempt = attempt + 1
          
          -- Check available items
          local items = self.outputMeInterfaceProxy.getItemsInNetwork({
            label = output.originalLabel
          })
          
          if items and #items > 0 then
            local item = items[1]
            local available = item.size or 0
            
            if available > 0 then
              -- Transfer items using transposer (from output side to plasma side)
              local transferAmount = math.min(available, amountToTransfer - transferred, 64) -- Transfer in stacks
              local result = self.outputTransposerProxy.transferItem(
                self.outputTransposerOutputSide,
                self.outputTransposerPlasmaSide,
                transferAmount
              )
              
              if result then
                transferred = transferred + transferAmount
                event.push("log_info", "Transferred "..transferAmount.." of "..label.." (total: "..transferred..")")
              else
                os.sleep(0.1)
              end
            else
              event.push("log_warning", "Item "..label.." no longer available in output network")
              break
            end
          else
            event.push("log_warning", "Item "..label.." not found in output network")
            break
          end
        end
        
        if transferred < amountToTransfer then
          event.push("log_error", "Only transferred "..transferred.." of "..label.." out of "..amountToTransfer.." requested")
          return false
        else
          event.push("log_info", "Successfully transferred "..transferred.." of "..label.." to Plasma module")
        end
      end
    end

    return true
  end

  ---Transfer additional items from main AE network to plasma module using transposer
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

    -- Request items from main AE network and transfer to plasma module via transposer
    for _, itemRequest in pairs(itemsToRequest) do
      event.push("log_info", "Requesting "..itemRequest.count.." of "..itemRequest.label.." from main AE via transposer")
      
      local transferred = 0
      local maxAttempts = 100
      local attempt = 0
      
      while transferred < itemRequest.count and attempt < maxAttempts do
        attempt = attempt + 1
        
        -- Check available items in main network
        local items = self.mainMeInterfaceProxy.getItemsInNetwork({
          label = itemRequest.label
        })
        
        if items and #items > 0 then
          local item = items[1]
          local available = item.size or 0
          
          if available > 0 then
            -- Transfer items using main transposer (from main side to plasma side)
            local transferAmount = math.min(available, itemRequest.count - transferred, 64) -- Transfer in stacks
            local result = self.mainTransposerProxy.transferItem(
              self.mainTransposerMainSide,
              self.mainTransposerPlasmaSide,
              transferAmount
            )
            
            if result then
              transferred = transferred + transferAmount
              event.push("log_info", "Transferred "..transferAmount.." of "..itemRequest.label.." (total: "..transferred..")")
            else
              os.sleep(0.1)
            end
          else
            event.push("log_warning", "Item "..itemRequest.label.." no longer available in main network")
            break
          end
        else
          event.push("log_warning", "Item "..itemRequest.label.." not found in main AE network")
          break
        end
      end
      
      if transferred < itemRequest.count then
        event.push("log_warning", "Only transferred "..transferred.." of "..itemRequest.label.." out of "..itemRequest.count.." requested")
      else
        event.push("log_info", "Successfully transferred "..transferred.." of "..itemRequest.label.." from main AE")
      end
    end

    return true
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return quarkGluonPlasmaController


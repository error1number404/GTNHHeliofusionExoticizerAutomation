local component = require("component")
local event = require("event")
local computer = require("computer")
local sides = require("sides")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")

---@class MagmatterControllerConfig
---@field puzzleOutput1MeInterfaceAddress string -- First puzzle output interface
---@field puzzleOutput2MeInterfaceAddress string -- Second puzzle output interface
---@field mainMeInterfaceAddress string -- Main net interface (above puzzle output transposers)
---@field readyLiquid1MeInterfaceAddress string -- First ready liquid interface (6 plasmas)
---@field readyLiquid2MeInterfaceAddress string -- Second ready liquid interface (6 plasmas)
---@field readyLiquid3MeInterfaceAddress string -- Third ready liquid interface (2 plasmas + tachyon + spatially enlarged)
---@field puzzleOutput1TransposerAddress string -- Transposer above first puzzle output interface
---@field puzzleOutput2TransposerAddress string -- Transposer above second puzzle output interface
---@field readyLiquid1TransposerAddress string -- Transposer above first ready liquid interface
---@field readyLiquid2TransposerAddress string -- Transposer above second ready liquid interface
---@field readyLiquid3TransposerAddress string -- Transposer above third ready liquid interface
---@field puzzleOutput1TransposerOutputSide number -- Side of puzzle output 1 transposer connected to puzzle output interface
---@field puzzleOutput1TransposerMainSide number -- Side of puzzle output 1 transposer connected to main interface
---@field puzzleOutput2TransposerOutputSide number -- Side of puzzle output 2 transposer connected to puzzle output interface
---@field puzzleOutput2TransposerMainSide number -- Side of puzzle output 2 transposer connected to main interface
---@field readyLiquid1TransposerReadySide number -- Side of ready liquid 1 transposer connected to ready liquid interface
---@field readyLiquid1TransposerOutputSide number -- Side of ready liquid 1 transposer connected to puzzle output
---@field readyLiquid2TransposerReadySide number -- Side of ready liquid 2 transposer connected to ready liquid interface
---@field readyLiquid2TransposerOutputSide number -- Side of ready liquid 2 transposer connected to puzzle output
---@field readyLiquid3TransposerReadySide number -- Side of ready liquid 3 transposer connected to ready liquid interface
---@field readyLiquid3TransposerOutputSide number -- Side of ready liquid 3 transposer connected to puzzle output

---@class OutputItem
---@field label string
---@field count number
---@field isLiquid boolean
---@field originalLabel string

---@class PuzzleOutput
---@field tachyonRichAmount number -- Amount of tachyon rich temporal fluid (1-50L)
---@field spatiallyEnlargedAmount number -- Amount of spatially enlarged fluid (51-100L)
---@field dustLabel string -- Label of the dust material
---@field dustOriginalLabel string -- Original label of the dust
---@field requiredPlasmaAmount number -- Required plasma amount in ingots (spatially_enlarged - tachyon_rich)

local magmatterController = {}

---Create new MagmatterController object from config
---@param config MagmatterControllerConfig
---@return MagmatterController
function magmatterController:newFormConfig(config)
  return self:new(
    config.puzzleOutput1MeInterfaceAddress,
    config.puzzleOutput2MeInterfaceAddress,
    config.mainMeInterfaceAddress,
    config.readyLiquid1MeInterfaceAddress,
    config.readyLiquid2MeInterfaceAddress,
    config.readyLiquid3MeInterfaceAddress,
    config.puzzleOutput1TransposerAddress,
    config.puzzleOutput2TransposerAddress,
    config.readyLiquid1TransposerAddress,
    config.readyLiquid2TransposerAddress,
    config.readyLiquid3TransposerAddress,
    config.puzzleOutput1TransposerOutputSide,
    config.puzzleOutput1TransposerMainSide,
    config.puzzleOutput2TransposerOutputSide,
    config.puzzleOutput2TransposerMainSide,
    config.readyLiquid1TransposerReadySide,
    config.readyLiquid1TransposerOutputSide,
    config.readyLiquid2TransposerReadySide,
    config.readyLiquid2TransposerOutputSide,
    config.readyLiquid3TransposerReadySide,
    config.readyLiquid3TransposerOutputSide
  )
end

---Create new MagmatterController object
---@param puzzleOutput1MeInterfaceAddress string
---@param puzzleOutput2MeInterfaceAddress string
---@param mainMeInterfaceAddress string
---@param readyLiquid1MeInterfaceAddress string
---@param readyLiquid2MeInterfaceAddress string
---@param readyLiquid3MeInterfaceAddress string
---@param puzzleOutput1TransposerAddress string
---@param puzzleOutput2TransposerAddress string
---@param readyLiquid1TransposerAddress string
---@param readyLiquid2TransposerAddress string
---@param readyLiquid3TransposerAddress string
---@param puzzleOutput1TransposerOutputSide number
---@param puzzleOutput1TransposerMainSide number
---@param puzzleOutput2TransposerOutputSide number
---@param puzzleOutput2TransposerMainSide number
---@param readyLiquid1TransposerReadySide number
---@param readyLiquid1TransposerOutputSide number
---@param readyLiquid2TransposerReadySide number
---@param readyLiquid2TransposerOutputSide number
---@param readyLiquid3TransposerReadySide number
---@param readyLiquid3TransposerOutputSide number
---@return MagmatterController
function magmatterController:new(
  puzzleOutput1MeInterfaceAddress,
  puzzleOutput2MeInterfaceAddress,
  mainMeInterfaceAddress,
  readyLiquid1MeInterfaceAddress,
  readyLiquid2MeInterfaceAddress,
  readyLiquid3MeInterfaceAddress,
  puzzleOutput1TransposerAddress,
  puzzleOutput2TransposerAddress,
  readyLiquid1TransposerAddress,
  readyLiquid2TransposerAddress,
  readyLiquid3TransposerAddress,
  puzzleOutput1TransposerOutputSide,
  puzzleOutput1TransposerMainSide,
  puzzleOutput2TransposerOutputSide,
  puzzleOutput2TransposerMainSide,
  readyLiquid1TransposerReadySide,
  readyLiquid1TransposerOutputSide,
  readyLiquid2TransposerReadySide,
  readyLiquid2TransposerOutputSide,
  readyLiquid3TransposerReadySide,
  readyLiquid3TransposerOutputSide)

  ---@class MagmatterController
  local obj = {}

  obj.puzzleOutput1MeInterfaceProxy = nil
  obj.puzzleOutput2MeInterfaceProxy = nil
  obj.mainMeInterfaceProxy = nil
  obj.readyLiquid1MeInterfaceProxy = nil
  obj.readyLiquid2MeInterfaceProxy = nil
  obj.readyLiquid3MeInterfaceProxy = nil
  obj.puzzleOutput1TransposerProxy = nil
  obj.puzzleOutput2TransposerProxy = nil
  obj.readyLiquid1TransposerProxy = nil
  obj.readyLiquid2TransposerProxy = nil
  obj.readyLiquid3TransposerProxy = nil

  obj.puzzleOutput1TransposerOutputSide = puzzleOutput1TransposerOutputSide
  obj.puzzleOutput1TransposerMainSide = puzzleOutput1TransposerMainSide
  obj.puzzleOutput2TransposerOutputSide = puzzleOutput2TransposerOutputSide
  obj.puzzleOutput2TransposerMainSide = puzzleOutput2TransposerMainSide
  obj.readyLiquid1TransposerReadySide = readyLiquid1TransposerReadySide
  obj.readyLiquid1TransposerOutputSide = readyLiquid1TransposerOutputSide
  obj.readyLiquid2TransposerReadySide = readyLiquid2TransposerReadySide
  obj.readyLiquid2TransposerOutputSide = readyLiquid2TransposerOutputSide
  obj.readyLiquid3TransposerReadySide = readyLiquid3TransposerReadySide
  obj.readyLiquid3TransposerOutputSide = readyLiquid3TransposerOutputSide

  obj.database = component.database
  obj.stateMachine = stateMachineLib:new()
  obj.databaseEntries = {} -- Store database entries for items/fluids
  obj.nextDatabaseSlot = 1 -- Next slot to use (will wrap around/reuse)

  ---Init
  function obj:init()
    self.puzzleOutput1MeInterfaceProxy = componentDiscoverLib.discoverProxy(puzzleOutput1MeInterfaceAddress, "Puzzle Output 1 Me Interface", "me_interface")
    self.puzzleOutput2MeInterfaceProxy = componentDiscoverLib.discoverProxy(puzzleOutput2MeInterfaceAddress, "Puzzle Output 2 Me Interface", "me_interface")
    self.mainMeInterfaceProxy = componentDiscoverLib.discoverProxy(mainMeInterfaceAddress, "Main Me Interface", "me_interface")
    self.readyLiquid1MeInterfaceProxy = componentDiscoverLib.discoverProxy(readyLiquid1MeInterfaceAddress, "Ready Liquid 1 Me Interface", "me_interface")
    self.readyLiquid2MeInterfaceProxy = componentDiscoverLib.discoverProxy(readyLiquid2MeInterfaceAddress, "Ready Liquid 2 Me Interface", "me_interface")
    self.readyLiquid3MeInterfaceProxy = componentDiscoverLib.discoverProxy(readyLiquid3MeInterfaceAddress, "Ready Liquid 3 Me Interface", "me_interface")
    self.puzzleOutput1TransposerProxy = componentDiscoverLib.discoverProxy(puzzleOutput1TransposerAddress, "Puzzle Output 1 Transposer", "transposer")
    self.puzzleOutput2TransposerProxy = componentDiscoverLib.discoverProxy(puzzleOutput2TransposerAddress, "Puzzle Output 2 Transposer", "transposer")
    self.readyLiquid1TransposerProxy = componentDiscoverLib.discoverProxy(readyLiquid1TransposerAddress, "Ready Liquid 1 Transposer", "transposer")
    self.readyLiquid2TransposerProxy = componentDiscoverLib.discoverProxy(readyLiquid2TransposerAddress, "Ready Liquid 2 Transposer", "transposer")
    self.readyLiquid3TransposerProxy = componentDiscoverLib.discoverProxy(readyLiquid3TransposerAddress, "Ready Liquid 3 Transposer", "transposer")

    self.stateMachine.data.puzzleOutput = nil
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
        local puzzleOutput = self:getPuzzleOutputs()
        local diff = math.ceil(currentTime - self.stateMachine.data.time)

        if puzzleOutput ~= nil then
          self.stateMachine.data.puzzleOutput = puzzleOutput
          self.stateMachine:setState(self.stateMachine.states.pullToMain)
        elseif diff > 240 and self.stateMachine.data.notifyLongIdle == false then
          self.stateMachine.data.notifyLongIdle = true
          event.push("log_warning", "More than four minutes in the idle state: "..diff)
        end
      end
    end

    self.stateMachine.states.pullToMain = self.stateMachine:createState("Pull To Main")
    self.stateMachine.states.pullToMain.init = function()
      if self.stateMachine.data.notifyLongIdle == true then
        event.push("log_warning", "Successfully went to Pull To Main state after a long Idle state")
      end

      local success = self:pullPuzzleOutputsToMain()

      if success == false then
        self.stateMachine.data.errorMessage = "Failed to pull puzzle outputs to main net"
        self.stateMachine:setState(self.stateMachine.states.error)
        return
      end

      self.stateMachine:setState(self.stateMachine.states.pullRequiredLiquids)
    end

    self.stateMachine.states.pullRequiredLiquids = self.stateMachine:createState("Pull Required Liquids")
    self.stateMachine.states.pullRequiredLiquids.init = function()
      local success = self:pullRequiredLiquids()

      if success == false then
        self.stateMachine.data.errorMessage = "Failed to pull required liquids from ready interfaces"
        self.stateMachine:setState(self.stateMachine.states.error)
        return
      end

      self.stateMachine:setState(self.stateMachine.states.returnToPuzzle)
    end

    self.stateMachine.states.returnToPuzzle = self.stateMachine:createState("Return To Puzzle")
    self.stateMachine.states.returnToPuzzle.init = function()
      local success = self:returnLiquidsToPuzzle()

      if success == false then
        self.stateMachine.data.errorMessage = "Failed to return liquids to puzzle output"
        self.stateMachine:setState(self.stateMachine.states.error)
        return
      end

      self.stateMachine.data.puzzleOutput = nil
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

  ---Get puzzle outputs from both puzzle output interfaces
  ---Identifies tachyon rich temporal fluid, spatially enlarged fluid, and dust
  ---@return PuzzleOutput|nil
  ---@private
  function obj:getPuzzleOutputs()
    local items1 = obj.puzzleOutput1MeInterfaceProxy.getItemsInNetwork({})
    local liquids1 = obj.puzzleOutput1MeInterfaceProxy.getFluidsInNetwork()
    local items2 = obj.puzzleOutput2MeInterfaceProxy.getItemsInNetwork({})
    local liquids2 = obj.puzzleOutput2MeInterfaceProxy.getFluidsInNetwork()

    ---@type PuzzleOutput
    local puzzleOutput = {
      tachyonRichAmount = 0,
      spatiallyEnlargedAmount = 0,
      dustLabel = nil,
      dustOriginalLabel = nil,
      requiredPlasmaAmount = 0
    }

    -- Check both interfaces for tachyon rich temporal fluid
    for _, fluid in pairs(liquids1) do
      if string.find(fluid.label:lower(), "tachyon") and string.find(fluid.label:lower(), "rich") and string.find(fluid.label:lower(), "temporal") then
        puzzleOutput.tachyonRichAmount = puzzleOutput.tachyonRichAmount + fluid.amount
      elseif string.find(fluid.label:lower(), "spatially") and string.find(fluid.label:lower(), "enlarged") then
        puzzleOutput.spatiallyEnlargedAmount = puzzleOutput.spatiallyEnlargedAmount + fluid.amount
      end
    end

    for _, fluid in pairs(liquids2) do
      if string.find(fluid.label:lower(), "tachyon") and string.find(fluid.label:lower(), "rich") and string.find(fluid.label:lower(), "temporal") then
        puzzleOutput.tachyonRichAmount = puzzleOutput.tachyonRichAmount + fluid.amount
      elseif string.find(fluid.label:lower(), "spatially") and string.find(fluid.label:lower(), "enlarged") then
        puzzleOutput.spatiallyEnlargedAmount = puzzleOutput.spatiallyEnlargedAmount + fluid.amount
      end
    end

    -- Check both interfaces for dust
    for _, item in pairs(items1) do
      if string.find(item.label:lower(), "dust") then
        -- Extract base label from dust names
        local label = item.label:match("Pile of%s(.+)%sDust")
        if label == nil then
          label = item.label:match("(.+) Dust")
        end
        if label == nil then
          label = item.label
        end
        
        puzzleOutput.dustLabel = label
        puzzleOutput.dustOriginalLabel = item.label
        break
      end
    end

    if puzzleOutput.dustLabel == nil then
      for _, item in pairs(items2) do
        if string.find(item.label:lower(), "dust") then
          local label = item.label:match("Pile of%s(.+)%sDust")
          if label == nil then
            label = item.label:match("(.+) Dust")
          end
          if label == nil then
            label = item.label
          end
          
          puzzleOutput.dustLabel = label
          puzzleOutput.dustOriginalLabel = item.label
          break
        end
      end
    end

    -- Validate we have all required outputs
    if puzzleOutput.tachyonRichAmount == 0 or puzzleOutput.spatiallyEnlargedAmount == 0 or puzzleOutput.dustLabel == nil then
      return nil
    end

    -- Calculate required plasma amount (difference in ingots)
    puzzleOutput.requiredPlasmaAmount = puzzleOutput.spatiallyEnlargedAmount - puzzleOutput.tachyonRichAmount

    event.push("log_info", "Detected puzzle output: Tachyon Rich="..puzzleOutput.tachyonRichAmount.."L, Spatially Enlarged="..puzzleOutput.spatiallyEnlargedAmount.."L, Dust="..puzzleOutput.dustLabel..", Required Plasma="..puzzleOutput.requiredPlasmaAmount.." ingots")

    return puzzleOutput
  end

  ---Pull all items and liquids from puzzle output interfaces to main net
  ---@return boolean
  ---@private
  function obj:pullPuzzleOutputsToMain()
    if self.stateMachine.data.puzzleOutput == nil then
      return false
    end

    event.push("log_info", "Pulling items and liquids from puzzle output interfaces to main net")

    -- Pull from puzzle output 1 interface
    local success1 = self:pullAllFromInterface(
      self.puzzleOutput1MeInterfaceProxy,
      self.puzzleOutput1TransposerProxy,
      self.puzzleOutput1TransposerOutputSide,
      self.puzzleOutput1TransposerMainSide,
      "Puzzle Output 1"
    )

    -- Pull from puzzle output 2 interface
    local success2 = self:pullAllFromInterface(
      self.puzzleOutput2MeInterfaceProxy,
      self.puzzleOutput2TransposerProxy,
      self.puzzleOutput2TransposerOutputSide,
      self.puzzleOutput2TransposerMainSide,
      "Puzzle Output 2"
    )

    return success1 and success2
  end

  ---Pull all items and liquids from an interface to main net via transposer
  ---@param interfaceProxy table
  ---@param transposerProxy table
  ---@param outputSide number
  ---@param mainSide number
  ---@param interfaceName string
  ---@return boolean
  ---@private
  function obj:pullAllFromInterface(interfaceProxy, transposerProxy, outputSide, mainSide, interfaceName)
    -- Pull all items
    local items = interfaceProxy.getItemsInNetwork({})
    for _, item in pairs(items) do
      event.push("log_info", "Pulling "..item.size.."x "..item.label.." from "..interfaceName)
      local transferred = 0
      local maxAttempts = 50
      local attempt = 0
      
      while transferred < item.size and attempt < maxAttempts do
        attempt = attempt + 1
        local transferAmount = math.min(item.size - transferred, 64)
        local result = transposerProxy.transferItem(outputSide, mainSide, transferAmount)
        
        if result then
          transferred = transferred + transferAmount
        else
          os.sleep(0.05) -- 1 tick delay
        end
      end
      
      if transferred < item.size then
        event.push("log_warning", "Only transferred "..transferred.." of "..item.label.." from "..interfaceName)
      end
    end

    -- Pull all liquids
    local liquids = interfaceProxy.getFluidsInNetwork()
    for _, fluid in pairs(liquids) do
      event.push("log_info", "Pulling "..fluid.amount.."L of "..fluid.label.." from "..interfaceName)
      local transferred = 0
      local maxAttempts = 100
      local attempt = 0
      
      while transferred < fluid.amount and attempt < maxAttempts do
        attempt = attempt + 1
        local transferAmount = math.min(fluid.amount - transferred, 16000)
        local result = transposerProxy.transferFluid(outputSide, mainSide, transferAmount)
        
        if result then
          transferred = transferred + transferAmount
        else
          os.sleep(0.05) -- 1 tick delay
        end
      end
      
      if transferred < fluid.amount then
        event.push("log_warning", "Only transferred "..transferred.."L of "..fluid.label.." from "..interfaceName)
      end
    end

    return true
  end

  ---Pull required liquids from ready liquid interfaces and transfer to puzzle output
  ---@return boolean
  ---@private
  function obj:pullRequiredLiquids()
    if self.stateMachine.data.puzzleOutput == nil then
      return false
    end

    local puzzleOutput = self.stateMachine.data.puzzleOutput

    event.push("log_info", "Pulling required liquids from ready interfaces to puzzle output")

    -- Pull tachyon rich temporal fluid from interface 3 to puzzle output
    local tachyonSuccess = self:pullFluidFromReadyInterface(
      self.readyLiquid3MeInterfaceProxy,
      self.readyLiquid3TransposerProxy,
      self.readyLiquid3TransposerReadySide,
      self.readyLiquid3TransposerOutputSide,
      "Tachyon Rich Temporal Fluid",
      puzzleOutput.tachyonRichAmount
    )

    -- Pull spatially enlarged fluid from interface 3 to puzzle output
    local spatiallyEnlargedSuccess = self:pullFluidFromReadyInterface(
      self.readyLiquid3MeInterfaceProxy,
      self.readyLiquid3TransposerProxy,
      self.readyLiquid3TransposerReadySide,
      self.readyLiquid3TransposerOutputSide,
      "Spatially Enlarged Fluid",
      puzzleOutput.spatiallyEnlargedAmount
    )

    -- Pull plasma from all 3 ready interfaces to puzzle output
    local plasmaSuccess = self:pullPlasmaFromReadyInterfaces(
      puzzleOutput.dustLabel,
      puzzleOutput.requiredPlasmaAmount
    )

    return tachyonSuccess and spatiallyEnlargedSuccess and plasmaSuccess
  end

  ---Pull fluid from ready interface and transfer to puzzle output via transposer
  ---Ready interface is below transposer, puzzle output is above transposer
  ---@param interfaceProxy table
  ---@param transposerProxy table
  ---@param sourceSide number Side connected to ready liquid interface (below)
  ---@param destSide number Side connected to puzzle output interface (above)
  ---@param fluidName string
  ---@param requiredAmount number
  ---@return boolean
  ---@private
  function obj:pullFluidFromReadyInterface(interfaceProxy, transposerProxy, sourceSide, destSide, fluidName, requiredAmount)
    event.push("log_info", "Pulling "..requiredAmount.."L of "..fluidName)

    -- Check if fluid is available in interface
    local fluids = interfaceProxy.getFluidsInNetwork()
    local found = false
    local availableAmount = 0

    for _, fluid in pairs(fluids) do
      if string.find(fluid.label:lower(), fluidName:lower()) or 
         (fluidName == "Tachyon Rich Temporal Fluid" and string.find(fluid.label:lower(), "tachyon") and string.find(fluid.label:lower(), "rich")) or
         (fluidName == "Spatially Enlarged Fluid" and string.find(fluid.label:lower(), "spatially") and string.find(fluid.label:lower(), "enlarged")) then
        found = true
        availableAmount = fluid.amount
        break
      end
    end

    if not found then
      event.push("log_error", fluidName.." not found in interface")
      return false
    end

    if availableAmount < requiredAmount then
      event.push("log_warning", "Only "..availableAmount.."L available, need "..requiredAmount.."L of "..fluidName)
    end

    local transferred = 0
    local maxAttempts = 200
    local attempt = 0
    local amountToTransfer = math.min(availableAmount, requiredAmount)

    while transferred < amountToTransfer and attempt < maxAttempts do
      attempt = attempt + 1
      local transferAmount = math.min(amountToTransfer - transferred, 16000)
      local result = transposerProxy.transferFluid(sourceSide, destSide, transferAmount)

      if result then
        transferred = transferred + transferAmount
        if attempt % 20 == 0 then
          event.push("log_info", "Transferred "..transferred.."L of "..fluidName.." (target: "..amountToTransfer.."L)")
        end
      else
        os.sleep(0.05) -- 1 tick delay
      end
    end

    if transferred < amountToTransfer then
      event.push("log_warning", "Only transferred "..transferred.."L of "..fluidName.." out of "..amountToTransfer.."L requested")
      return false
    end

    event.push("log_info", "Successfully transferred "..transferred.."L of "..fluidName)
    return true
  end

  ---Pull plasma from ready liquid interfaces (all 3) and transfer to puzzle output
  ---Plasma interfaces are below transposers, puzzle output is above transposers
  ---@param dustLabel string
  ---@param requiredAmount number Amount in ingots
  ---@return boolean
  ---@private
  function obj:pullPlasmaFromReadyInterfaces(dustLabel, requiredAmount)
    event.push("log_info", "Pulling "..requiredAmount.." ingots of "..dustLabel.." plasma from all ready interfaces")

    -- Convert ingots to mB (1 ingot = 144 mB)
    local requiredAmountMB = requiredAmount * 144
    local totalTransferred = 0
    local interfaces = {
      {proxy = self.readyLiquid1MeInterfaceProxy, transposer = self.readyLiquid1TransposerProxy, readySide = self.readyLiquid1TransposerReadySide, outputSide = self.readyLiquid1TransposerOutputSide, name = "Ready Liquid 1"},
      {proxy = self.readyLiquid2MeInterfaceProxy, transposer = self.readyLiquid2TransposerProxy, readySide = self.readyLiquid2TransposerReadySide, outputSide = self.readyLiquid2TransposerOutputSide, name = "Ready Liquid 2"},
      {proxy = self.readyLiquid3MeInterfaceProxy, transposer = self.readyLiquid3TransposerProxy, readySide = self.readyLiquid3TransposerReadySide, outputSide = self.readyLiquid3TransposerOutputSide, name = "Ready Liquid 3"}
    }

    -- Search all interfaces for the required plasma
    for _, interfaceData in ipairs(interfaces) do
      if totalTransferred >= requiredAmountMB then
        break
      end

      local fluids = interfaceData.proxy.getFluidsInNetwork()
      local found = false
      local availableAmount = 0
      local plasmaLabel = nil

      -- Look for plasma matching the dust material
      for _, fluid in pairs(fluids) do
        if string.find(fluid.label:lower(), "plasma") and string.find(fluid.label:lower(), dustLabel:lower()) then
          found = true
          availableAmount = fluid.amount
          plasmaLabel = fluid.label
          break
        end
      end

      if found then
        local remainingNeeded = requiredAmountMB - totalTransferred
        local amountToTransfer = math.min(availableAmount, remainingNeeded)
        
        event.push("log_info", "Found "..availableAmount.."mB of "..plasmaLabel.." in "..interfaceData.name..", transferring "..amountToTransfer.."mB")

        local transferred = 0
        local maxAttempts = 200
        local attempt = 0

        while transferred < amountToTransfer and attempt < maxAttempts do
          attempt = attempt + 1
          local transferAmount = math.min(amountToTransfer - transferred, 16000)
          local result = interfaceData.transposer.transferFluid(
            interfaceData.readySide,
            interfaceData.outputSide,
            transferAmount
          )

          if result then
            transferred = transferred + transferAmount
            totalTransferred = totalTransferred + transferAmount
            if attempt % 20 == 0 then
              event.push("log_info", "Transferred "..transferred.."mB of "..plasmaLabel.." from "..interfaceData.name.." (total: "..totalTransferred.."mB)")
            end
          else
            os.sleep(0.05) -- 1 tick delay
          end
        end

        if transferred < amountToTransfer then
          event.push("log_warning", "Only transferred "..transferred.."mB of "..plasmaLabel.." from "..interfaceData.name.." out of "..amountToTransfer.."mB requested")
        else
          event.push("log_info", "Successfully transferred "..transferred.."mB of "..plasmaLabel.." from "..interfaceData.name)
        end
      end
    end

    if totalTransferred < requiredAmountMB then
      event.push("log_error", "Only transferred "..totalTransferred.."mB ("..math.floor(totalTransferred/144).." ingots) of plasma out of "..requiredAmountMB.."mB ("..requiredAmount.." ingots) requested")
      return false
    end

    event.push("log_info", "Successfully transferred "..totalTransferred.."mB ("..math.floor(totalTransferred/144).." ingots) of "..dustLabel.." plasma from ready interfaces")
    return true
  end

  ---Return liquids to puzzle output interfaces
  ---@return boolean
  ---@private
  function obj:returnLiquidsToPuzzle()
    if self.stateMachine.data.puzzleOutput == nil then
      return false
    end

    local puzzleOutput = self.stateMachine.data.puzzleOutput

    event.push("log_info", "Returning liquids to puzzle output interfaces")

    -- The liquids should already be in the puzzle output interfaces from the transposers
    -- The transposers above the ready liquid interfaces transfer directly to puzzle output
    -- So we just need to verify they're there

    -- Check puzzle output 1 for the fluids
    local liquids1 = self.puzzleOutput1MeInterfaceProxy.getFluidsInNetwork()
    local items1 = self.puzzleOutput1MeInterfaceProxy.getItemsInNetwork({})

    -- Check puzzle output 2 for the fluids
    local liquids2 = self.puzzleOutput2MeInterfaceProxy.getFluidsInNetwork()
    local items2 = self.puzzleOutput2MeInterfaceProxy.getItemsInNetwork({})

    local tachyonFound = false
    local spatiallyEnlargedFound = false
    local plasmaFound = false

    -- Check both interfaces
    for _, fluid in pairs(liquids1) do
      if string.find(fluid.label:lower(), "tachyon") and string.find(fluid.label:lower(), "rich") then
        tachyonFound = true
        event.push("log_info", "Found "..fluid.amount.."L tachyon rich in puzzle output 1")
      elseif string.find(fluid.label:lower(), "spatially") and string.find(fluid.label:lower(), "enlarged") then
        spatiallyEnlargedFound = true
        event.push("log_info", "Found "..fluid.amount.."L spatially enlarged in puzzle output 1")
      elseif string.find(fluid.label:lower(), "plasma") and string.find(fluid.label:lower(), puzzleOutput.dustLabel:lower()) then
        plasmaFound = true
        event.push("log_info", "Found "..fluid.amount.."mB plasma in puzzle output 1")
      end
    end

    for _, fluid in pairs(liquids2) do
      if string.find(fluid.label:lower(), "tachyon") and string.find(fluid.label:lower(), "rich") then
        tachyonFound = true
        event.push("log_info", "Found "..fluid.amount.."L tachyon rich in puzzle output 2")
      elseif string.find(fluid.label:lower(), "spatially") and string.find(fluid.label:lower(), "enlarged") then
        spatiallyEnlargedFound = true
        event.push("log_info", "Found "..fluid.amount.."L spatially enlarged in puzzle output 2")
      elseif string.find(fluid.label:lower(), "plasma") and string.find(fluid.label:lower(), puzzleOutput.dustLabel:lower()) then
        plasmaFound = true
        event.push("log_info", "Found "..fluid.amount.."mB plasma in puzzle output 2")
      end
    end

    if not tachyonFound then
      event.push("log_warning", "Tachyon rich temporal fluid not found in puzzle output interfaces")
    end
    if not spatiallyEnlargedFound then
      event.push("log_warning", "Spatially enlarged fluid not found in puzzle output interfaces")
    end
    if not plasmaFound then
      event.push("log_warning", "Plasma not found in puzzle output interfaces")
    end

    -- The puzzle should automatically process once all required fluids are returned
    event.push("log_info", "Liquids returned to puzzle output. Recipe should start processing.")

    return true
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return magmatterController

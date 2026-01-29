local component = require("component")
local event = require("event")
local computer = require("computer")
local sides = require("sides")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")

-- Constants
local PLASMA_CONVERSION_FACTOR = 144 -- mB per ingot
local MAX_FLUID_TRANSFER = 16000 -- Maximum mB per transfer
local SMALL_FLUID_TRANSFER = 10 -- Small retry amount in mB
local MAX_ITEM_STACK_SIZE = 64
local MAX_TRANSFER_ATTEMPTS = 200
local MAX_ITEM_TRANSFER_ATTEMPTS = 50
local MAX_FLUID_TRANSFER_ATTEMPTS = 100
local CONSECUTIVE_FAILURE_THRESHOLD = 3
local MAX_CONSECUTIVE_FAILURES = 5
local PROGRESS_REPORT_INTERVAL = 20
local IDLE_CHECK_INTERVAL = 0.1 -- seconds
local IDLE_WARNING_THRESHOLD = 240 -- seconds (4 minutes)
local TRANSFER_DELAY_SHORT = 0.05 -- seconds
local TRANSFER_DELAY_MEDIUM = 0.1 -- seconds
local TRANSFER_DELAY_LONG = 0.2 -- seconds

---@class MagmatterControllerConfig
---@field puzzleOutput1MeInterfaceAddress string -- First puzzle output interface
---@field puzzleOutput2MeInterfaceAddress string -- Second puzzle output interface
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
---@field requiredPlasmaAmount number -- Required plasma amount in mB ((spatially_enlarged - tachyon_rich) * 144)

local magmatterController = {}

-- Helper functions for fluid matching
local function getFluidNameToCheck(fluid)
  local fluidLabel = fluid.label or ""
  local fluidName = fluid.name or ""
  return (fluidLabel ~= "" and fluidLabel or fluidName):lower()
end

local function isTachyonRichTemporalFluid(fluidName)
  return string.find(fluidName, "tachyon") and 
         string.find(fluidName, "rich") and 
         string.find(fluidName, "temporal")
end

local function isSpatiallyEnlargedFluid(fluidName)
  return string.find(fluidName, "spatially") and 
         string.find(fluidName, "enlarged")
end

local function isPlasmaFluid(fluidName, dustLabel)
  -- Check that it's a plasma fluid
  if not string.find(fluidName, "plasma") then
    return false
  end
  
  -- Extract the material name (everything before "Plasma")
  -- Examples: "Draconium Plasma" -> "Draconium"
  --           "Awakened Draconium Plasma" -> "Awakened Draconium"
  local materialName = fluidName:match("^(.+)%s+plasma")
  if not materialName then
    return false
  end
  
  -- Normalize: trim spaces and convert to lowercase
  materialName = materialName:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local dustLabelLower = dustLabel:lower()
  
  -- Require exact match: "Draconium" should match "Draconium Plasma"
  -- but NOT "Awakened Draconium Plasma"
  -- This prevents "Draconium" from matching "Awakened Draconium"
  return materialName == dustLabelLower
end

local function extractDustLabel(itemLabel)
  local label = itemLabel:match("Pile of%s(.+)%sDust")
  if label == nil then
    label = itemLabel:match("(.+) Dust")
  end
  if label == nil then
    label = itemLabel
  end
  return label
end

local function convertTankIndexToSideIndex(tankIndex)
  -- Convert tank index (1-6) to side index (0-5): tank 1 = side 0 (down), tank 2 = side 1 (up), etc.
  return tankIndex - 1
end

---Create new MagmatterController object from config
---@param config MagmatterControllerConfig
---@return MagmatterController
function magmatterController:newFormConfig(config)
  return self:new(
    config.puzzleOutput1MeInterfaceAddress,
    config.puzzleOutput2MeInterfaceAddress,
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
      local currentTime = computer.uptime()
      local timeSinceLastCheck = currentTime - self.stateMachine.data.lastOutputCheck
      
      if timeSinceLastCheck >= IDLE_CHECK_INTERVAL then
        self.stateMachine.data.lastOutputCheck = currentTime
        local puzzleOutput = self:getPuzzleOutputs()
        local diff = math.ceil(currentTime - self.stateMachine.data.time)

        if puzzleOutput ~= nil then
          self.stateMachine.data.puzzleOutput = puzzleOutput
          self.stateMachine:setState(self.stateMachine.states.pullToMain)
        elseif diff > IDLE_WARNING_THRESHOLD and not self.stateMachine.data.notifyLongIdle then
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

  ---Log interface contents for debugging
  ---@param items table
  ---@param fluids table
  ---@param interfaceName string
  ---@private
  function obj:logInterfaceContents(items, fluids, interfaceName)
    if #items > 0 or #fluids > 0 then
      event.push("log_debug", interfaceName.." - Items: "..#items..", Liquids: "..#fluids)
      for _, item in pairs(items) do
        event.push("log_debug", "  Item: "..(item.label or item.name or "Unknown").." x"..(item.size or 0))
      end
      for _, fluid in pairs(fluids) do
        event.push("log_debug", "  Fluid: "..(fluid.label or fluid.name or "Unknown").." "..(fluid.amount or 0).."L")
      end
    end
  end

  ---Process fluids from interface and update puzzle output
  ---@param fluids table
  ---@param puzzleOutput PuzzleOutput
  ---@private
  function obj:processFluidsFromInterface(fluids, puzzleOutput)
    for _, fluid in pairs(fluids) do
      if not fluid then
        goto continue
      end
      
      local fluidNameToCheck = getFluidNameToCheck(fluid)
      local fluidLabel = fluid.label or ""
      local fluidName = fluid.name or ""
      
      event.push("log_debug", "Checking fluid: '"..fluidNameToCheck.."' (name='"..fluidName.."', label='"..fluidLabel.."')")
      
      if isTachyonRichTemporalFluid(fluidNameToCheck) then
        event.push("log_debug", "  -> Matched Tachyon Rich Temporal Fluid, amount: "..(fluid.amount or 0))
        puzzleOutput.tachyonRichAmount = puzzleOutput.tachyonRichAmount + (fluid.amount or 0)
      elseif isSpatiallyEnlargedFluid(fluidNameToCheck) then
        event.push("log_debug", "  -> Matched Spatially Enlarged Fluid, amount: "..(fluid.amount or 0))
        puzzleOutput.spatiallyEnlargedAmount = puzzleOutput.spatiallyEnlargedAmount + (fluid.amount or 0)
      else
        event.push("log_debug", "  -> No match")
      end
      
      ::continue::
    end
  end

  ---Find dust in items and update puzzle output
  ---@param items table
  ---@param puzzleOutput PuzzleOutput
  ---@return boolean true if dust was found
  ---@private
  function obj:findDustInItems(items, puzzleOutput)
    for _, item in pairs(items) do
      if item and item.label and string.find(item.label:lower(), "dust") then
        puzzleOutput.dustLabel = extractDustLabel(item.label)
        puzzleOutput.dustOriginalLabel = item.label
        return true
      end
    end
    return false
  end

  ---Get puzzle outputs from both puzzle output interfaces
  ---Checks interface inventory directly, not network content
  ---Identifies tachyon rich temporal fluid, spatially enlarged fluid, and dust
  ---@return PuzzleOutput|nil
  ---@private
  function obj:getPuzzleOutputs()
    -- Check interface 1 inventory directly using transposer
    local items1, liquids1 = self:getInterfaceContents(
      self.puzzleOutput1TransposerProxy,
      self.puzzleOutput1TransposerOutputSide
    )
    
    -- Check interface 2 inventory directly using transposer
    local items2, liquids2 = self:getInterfaceContents(
      self.puzzleOutput2TransposerProxy,
      self.puzzleOutput2TransposerOutputSide
    )

    -- Debug: Log what we found
    self:logInterfaceContents(items1, liquids1, "Puzzle Output 1")
    self:logInterfaceContents(items2, liquids2, "Puzzle Output 2")

    ---@type PuzzleOutput
    local puzzleOutput = {
      tachyonRichAmount = 0,
      spatiallyEnlargedAmount = 0,
      dustLabel = nil,
      dustOriginalLabel = nil,
      requiredPlasmaAmount = 0
    }

    -- Process fluids from both interfaces
    self:processFluidsFromInterface(liquids1, puzzleOutput)
    self:processFluidsFromInterface(liquids2, puzzleOutput)

    -- Find dust in items (check interface 1 first, then interface 2)
    if not self:findDustInItems(items1, puzzleOutput) then
      self:findDustInItems(items2, puzzleOutput)
    end

    -- Debug: Log detected values before validation
    event.push("log_debug", "Detection summary - Tachyon Rich: "..puzzleOutput.tachyonRichAmount.."mB, Spatially Enlarged: "..puzzleOutput.spatiallyEnlargedAmount.."mB, Dust: "..(puzzleOutput.dustLabel or "nil"))

    -- Validate we have all required outputs
    if puzzleOutput.tachyonRichAmount == 0 or puzzleOutput.spatiallyEnlargedAmount == 0 or puzzleOutput.dustLabel == nil then
      local missing = {}
      if puzzleOutput.tachyonRichAmount == 0 then
        table.insert(missing, "Tachyon Rich Temporal Fluid")
      end
      if puzzleOutput.spatiallyEnlargedAmount == 0 then
        table.insert(missing, "Spatially Enlarged Fluid")
      end
      if puzzleOutput.dustLabel == nil then
        table.insert(missing, "Dust")
      end
      event.push("log_debug", "Puzzle output incomplete. Missing: "..table.concat(missing, ", "))
      return nil
    end

    -- Calculate required plasma amount
    -- Note: Detected amounts are in mB from transposer
    -- The absolute difference (spatial - tachyon) multiplied by PLASMA_CONVERSION_FACTOR gives the required plasma amount in mB
    local differenceMB = math.abs(puzzleOutput.spatiallyEnlargedAmount - puzzleOutput.tachyonRichAmount)
    puzzleOutput.requiredPlasmaAmount = differenceMB * PLASMA_CONVERSION_FACTOR

    event.push("log_info", "Detected puzzle output: Tachyon Rich="..puzzleOutput.tachyonRichAmount.."mB, Spatially Enlarged="..puzzleOutput.spatiallyEnlargedAmount.."mB, Dust="..puzzleOutput.dustLabel..", Required Plasma="..puzzleOutput.requiredPlasmaAmount.."mB ("..math.floor(puzzleOutput.requiredPlasmaAmount/PLASMA_CONVERSION_FACTOR).." ingots)")

    return puzzleOutput
  end

  ---Get items and fluids from interface inventory directly using transposer
  ---@param transposerProxy table
  ---@param interfaceSide number
  ---@return table items Array of items
  ---@return table fluids Array of fluids
  ---@private
  function obj:getInterfaceContents(transposerProxy, interfaceSide)
    local items = {}
    local fluids = {}
    
    -- Get items from interface inventory slots
    local inventorySize = transposerProxy.getInventorySize(interfaceSide)
    if inventorySize and inventorySize > 0 then
      for slot = 1, inventorySize do
        local stack = transposerProxy.getStackInSlot(interfaceSide, slot)
        if stack and stack.size and stack.size > 0 then
          table.insert(items, {
            label = stack.label or stack.name or "Unknown",
            size = stack.size,
            name = stack.name
          })
        end
      end
    end
    
    -- Get fluids from interface fluid tanks
    local tankCount = transposerProxy.getTankCount(interfaceSide)
    if tankCount and tankCount > 0 then
      for tank = 1, tankCount do
        local fluid = transposerProxy.getFluidInTank(interfaceSide, tank)
        if fluid and fluid.amount and fluid.amount > 0 then
          table.insert(fluids, {
            name = fluid.name or "Unknown",
            amount = fluid.amount,
            label = fluid.label or fluid.name or "Unknown"
          })
        end
      end
    end
    
    return items, fluids
  end

  ---Pull all items and liquids from puzzle output interfaces to main net
  ---Pulls from interface inventory directly, not network
  ---@return boolean
  ---@private
  function obj:pullPuzzleOutputsToMain()
    if self.stateMachine.data.puzzleOutput == nil then
      return false
    end

    event.push("log_info", "Pulling items and liquids from puzzle output interfaces to main net")

    -- Pull from puzzle output 1 interface inventory
    local success1 = self:pullAllFromInterfaceInventory(
      self.puzzleOutput1TransposerProxy,
      self.puzzleOutput1TransposerOutputSide,
      self.puzzleOutput1TransposerMainSide,
      "Puzzle Output 1"
    )

    -- Pull from puzzle output 2 interface inventory
    local success2 = self:pullAllFromInterfaceInventory(
      self.puzzleOutput2TransposerProxy,
      self.puzzleOutput2TransposerOutputSide,
      self.puzzleOutput2TransposerMainSide,
      "Puzzle Output 2"
    )

    return success1 and success2
  end

  ---Transfer a single item stack from interface to main net
  ---@param transposerProxy table
  ---@param outputSide number
  ---@param mainSide number
  ---@param slot number
  ---@param stack table
  ---@param interfaceName string
  ---@private
  function obj:transferItemStack(transposerProxy, outputSide, mainSide, slot, stack, interfaceName)
    event.push("log_info", "Pulling "..stack.size.."x "..(stack.label or stack.name or "Unknown").." from "..interfaceName.." slot "..slot)
    
    local transferred = 0
    local attempt = 0
    
    while transferred < stack.size and attempt < MAX_ITEM_TRANSFER_ATTEMPTS do
      attempt = attempt + 1
      local transferAmount = math.min(stack.size - transferred, MAX_ITEM_STACK_SIZE)
      local result = transposerProxy.transferItem(outputSide, mainSide, transferAmount, slot)
      
      if result then
        transferred = transferred + transferAmount
      else
        os.sleep(TRANSFER_DELAY_SHORT)
      end
    end
    
    if transferred < stack.size then
      event.push("log_warning", "Only transferred "..transferred.." of "..(stack.label or stack.name).." from "..interfaceName)
    end
  end

  ---Pull all items from interface inventory slots
  ---@param transposerProxy table
  ---@param outputSide number
  ---@param mainSide number
  ---@param interfaceName string
  ---@private
  function obj:pullItemsFromInterface(transposerProxy, outputSide, mainSide, interfaceName)
    local inventorySize = transposerProxy.getInventorySize(outputSide)
    if not inventorySize or inventorySize == 0 then
      return
    end
    
    for slot = 1, inventorySize do
      local stack = transposerProxy.getStackInSlot(outputSide, slot)
      if stack and stack.size and stack.size > 0 then
        self:transferItemStack(transposerProxy, outputSide, mainSide, slot, stack, interfaceName)
      end
    end
  end

  ---Transfer fluid from a single tank with retry logic
  ---@param transposerProxy table
  ---@param outputSide number
  ---@param mainSide number
  ---@param tank number
  ---@param interfaceName string
  ---@private
  function obj:transferFluidFromTank(transposerProxy, outputSide, mainSide, tank, interfaceName)
    local attempt = 0
    local consecutiveFailures = 0
    local lastFluidName = nil
    
    while attempt < MAX_FLUID_TRANSFER_ATTEMPTS do
      attempt = attempt + 1
      local fluid = transposerProxy.getFluidInTank(outputSide, tank)
      
      if not fluid or not fluid.amount or fluid.amount == 0 then
        break -- Tank is empty
      end
      
      local currentFluidName = fluid.label or fluid.name or "Unknown"
      
      -- Check if fluid type changed (multiple fluids in same tank)
      if lastFluidName and lastFluidName ~= currentFluidName then
        event.push("log_info", "Fluid type changed in tank "..tank.." from "..lastFluidName.." to "..currentFluidName)
        consecutiveFailures = 0
      end
      lastFluidName = currentFluidName
      
      if attempt == 1 then
        event.push("log_info", "Pulling "..fluid.amount.."mB of "..currentFluidName.." from "..interfaceName.." tank "..tank)
      end
      
      -- Calculate transfer amount based on failure count
      local maxTransfer = MAX_FLUID_TRANSFER
      if consecutiveFailures > 0 then
        maxTransfer = math.max(100, MAX_FLUID_TRANSFER / (consecutiveFailures + 1))
      end
      
      local transferAmount = math.min(fluid.amount, maxTransfer)
      local fluidSide = convertTankIndexToSideIndex(tank)
      local result = transposerProxy.transferFluid(outputSide, mainSide, transferAmount, fluidSide)
      
      if result then
        consecutiveFailures = 0
        os.sleep(TRANSFER_DELAY_SHORT)
      else
        consecutiveFailures = consecutiveFailures + 1
        
        -- Try smaller amount after multiple failures
        if consecutiveFailures >= CONSECUTIVE_FAILURE_THRESHOLD then
          local smallAmount = math.min(fluid.amount, SMALL_FLUID_TRANSFER)
          local smallResult = transposerProxy.transferFluid(outputSide, mainSide, smallAmount, fluidSide)
          
          if smallResult then
            consecutiveFailures = 0
            event.push("log_info", "Successfully transferred "..smallAmount.."mB using smaller amount")
            os.sleep(TRANSFER_DELAY_SHORT)
          else
            event.push("log_warning", "Failed to transfer "..transferAmount.."mB of "..currentFluidName.." from "..interfaceName.." tank "..tank.." (attempt "..attempt..", consecutive failures: "..consecutiveFailures..")")
            
            if consecutiveFailures >= MAX_CONSECUTIVE_FAILURES then
              event.push("log_error", "Giving up on transferring "..currentFluidName.." from "..interfaceName.." tank "..tank.." after "..consecutiveFailures.." consecutive failures. Fluid may be incompatible or destination may be full.")
              break
            end
            
            os.sleep(TRANSFER_DELAY_LONG)
          end
        else
          event.push("log_warning", "Failed to transfer "..transferAmount.."mB of "..currentFluidName.." from "..interfaceName.." tank "..tank.." (attempt "..attempt..")")
          os.sleep(TRANSFER_DELAY_MEDIUM)
        end
      end
    end
    
    -- Final check for remaining fluid
    local remainingFluid = transposerProxy.getFluidInTank(outputSide, tank)
    if remainingFluid and remainingFluid.amount and remainingFluid.amount > 0 then
      event.push("log_warning", "Still "..remainingFluid.amount.."mB of "..(remainingFluid.label or remainingFluid.name).." remaining in "..interfaceName.." tank "..tank)
    end
  end

  ---Pull all liquids from interface fluid tanks
  ---@param transposerProxy table
  ---@param outputSide number
  ---@param mainSide number
  ---@param interfaceName string
  ---@private
  function obj:pullFluidsFromInterface(transposerProxy, outputSide, mainSide, interfaceName)
    local tankCount = transposerProxy.getTankCount(outputSide)
    if not tankCount or tankCount == 0 then
      return
    end
    
    for tank = 1, tankCount do
      self:transferFluidFromTank(transposerProxy, outputSide, mainSide, tank, interfaceName)
    end
  end

  ---Pull all items and liquids from interface inventory to main net via transposer
  ---Reads directly from interface inventory slots/tanks, not network
  ---@param transposerProxy table
  ---@param outputSide number
  ---@param mainSide number
  ---@param interfaceName string
  ---@return boolean
  ---@private
  function obj:pullAllFromInterfaceInventory(transposerProxy, outputSide, mainSide, interfaceName)
    self:pullItemsFromInterface(transposerProxy, outputSide, mainSide, interfaceName)
    self:pullFluidsFromInterface(transposerProxy, outputSide, mainSide, interfaceName)
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
      self.readyLiquid3TransposerProxy,
      self.readyLiquid3TransposerReadySide,
      self.readyLiquid3TransposerOutputSide,
      "Tachyon Rich Temporal Fluid",
      puzzleOutput.tachyonRichAmount
    )

    -- Pull spatially enlarged fluid from interface 3 to puzzle output
    local spatiallyEnlargedSuccess = self:pullFluidFromReadyInterface(
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

  ---Find fluid in interface tanks by name
  ---@param transposerProxy table
  ---@param sourceSide number
  ---@param fluidName string
  ---@return boolean found
  ---@return number availableAmount
  ---@return number tankIndex
  ---@private
  function obj:findFluidInTanks(transposerProxy, sourceSide, fluidName)
    local tankCount = transposerProxy.getTankCount(sourceSide)
    if not tankCount or tankCount == 0 then
      return false, 0, nil
    end
    
    for tank = 1, tankCount do
      local fluid = transposerProxy.getFluidInTank(sourceSide, tank)
      if fluid and fluid.amount and fluid.amount > 0 then
        local fluidLabel = fluid.label or fluid.name or ""
        local fluidLabelLower = fluidLabel:lower()
        local fluidNameLower = fluidName:lower()
        
        if string.find(fluidLabelLower, fluidNameLower) or 
           (fluidName == "Tachyon Rich Temporal Fluid" and isTachyonRichTemporalFluid(fluidLabelLower)) or
           (fluidName == "Spatially Enlarged Fluid" and isSpatiallyEnlargedFluid(fluidLabelLower)) then
          return true, fluid.amount, tank
        end
      end
    end
    
    return false, 0, nil
  end

  ---Transfer fluid with retry logic
  ---@param transposerProxy table
  ---@param sourceSide number
  ---@param destSide number
  ---@param tankIndex number
  ---@param amountToTransfer number
  ---@param fluidName string
  ---@return number transferred
  ---@private
  function obj:transferFluidWithRetry(transposerProxy, sourceSide, destSide, tankIndex, amountToTransfer, fluidName)
    local transferred = 0
    local attempt = 0
    
    while transferred < amountToTransfer and attempt < MAX_TRANSFER_ATTEMPTS do
      attempt = attempt + 1
      
      -- Refresh fluid state to get current amount
      local currentFluid = transposerProxy.getFluidInTank(sourceSide, tankIndex)
      if not currentFluid or not currentFluid.amount or currentFluid.amount == 0 then
        event.push("log_warning", "Fluid "..fluidName.." no longer available in source tank")
        break
      end
      
      local remainingNeeded = amountToTransfer - transferred
      local transferAmount = math.min(currentFluid.amount, remainingNeeded, MAX_FLUID_TRANSFER)
      local fluidSide = convertTankIndexToSideIndex(tankIndex)
      local result = transposerProxy.transferFluid(sourceSide, destSide, transferAmount, fluidSide)

      if result then
        transferred = transferred + transferAmount
        if attempt % PROGRESS_REPORT_INTERVAL == 0 then
          event.push("log_info", "Transferred "..transferred.."mB of "..fluidName.." (target: "..amountToTransfer.."mB)")
        end
        os.sleep(TRANSFER_DELAY_SHORT)
      else
        event.push("log_warning", "Transfer attempt "..attempt.." failed for "..fluidName)
        os.sleep(TRANSFER_DELAY_MEDIUM)
      end
    end
    
    return transferred
  end

  ---Pull fluid from ready interface inventory and transfer to puzzle output via transposer
  ---Ready interface is below transposer, puzzle output is above transposer
  ---Checks interface inventory directly, not network
  ---@param transposerProxy table
  ---@param sourceSide number Side connected to ready liquid interface (below)
  ---@param destSide number Side connected to puzzle output interface (above)
  ---@param fluidName string
  ---@param requiredAmount number Amount in mB
  ---@return boolean
  ---@private
  function obj:pullFluidFromReadyInterface(transposerProxy, sourceSide, destSide, fluidName, requiredAmount)
    event.push("log_info", "Pulling "..requiredAmount.."mB of "..fluidName)

    local found, availableAmount, tankIndex = self:findFluidInTanks(transposerProxy, sourceSide, fluidName)

    if not found then
      event.push("log_error", fluidName.." not found in interface inventory")
      return false
    end

    if availableAmount < requiredAmount then
      event.push("log_warning", "Only "..availableAmount.."mB available, need "..requiredAmount.."mB of "..fluidName)
    end

    local amountToTransfer = math.min(availableAmount, requiredAmount)
    local transferred = self:transferFluidWithRetry(transposerProxy, sourceSide, destSide, tankIndex, amountToTransfer, fluidName)

    if transferred < amountToTransfer then
      event.push("log_warning", "Only transferred "..transferred.."mB of "..fluidName.." out of "..amountToTransfer.."mB requested")
      return false
    end

    event.push("log_info", "Successfully transferred "..transferred.."mB of "..fluidName)
    return true
  end

  ---Find plasma in interface tanks by dust label
  ---@param transposerProxy table
  ---@param readySide number
  ---@param dustLabel string
  ---@return boolean found
  ---@return number availableAmount
  ---@return string plasmaLabel
  ---@return number tankIndex
  ---@private
  function obj:findPlasmaInTanks(transposerProxy, readySide, dustLabel)
    local tankCount = transposerProxy.getTankCount(readySide)
    if not tankCount or tankCount == 0 then
      return false, 0, nil, nil
    end
    
    for tank = 1, tankCount do
      local fluid = transposerProxy.getFluidInTank(readySide, tank)
      if fluid and fluid.amount and fluid.amount > 0 then
        local fluidLabel = fluid.label or fluid.name or ""
        local fluidNameLower = fluidLabel:lower()
        
        if isPlasmaFluid(fluidNameLower, dustLabel) then
          return true, fluid.amount, fluidLabel, tank
        end
      end
    end
    
    return false, 0, nil, nil
  end

  ---Pull plasma from ready liquid interfaces (all 3) and transfer to puzzle output
  ---Plasma interfaces are below transposers, puzzle output is above transposers
  ---@param dustLabel string
  ---@param requiredAmountMB number Amount in mB
  ---@return boolean
  ---@private
  function obj:pullPlasmaFromReadyInterfaces(dustLabel, requiredAmountMB)
    local ingots = math.floor(requiredAmountMB / PLASMA_CONVERSION_FACTOR)
    event.push("log_info", "Pulling "..requiredAmountMB.."mB ("..ingots.." ingots) of "..dustLabel.." plasma from all ready interfaces")
    
    local totalTransferred = 0
    local interfaces = {
      {transposer = self.readyLiquid1TransposerProxy, readySide = self.readyLiquid1TransposerReadySide, outputSide = self.readyLiquid1TransposerOutputSide, name = "Ready Liquid 1"},
      {transposer = self.readyLiquid2TransposerProxy, readySide = self.readyLiquid2TransposerReadySide, outputSide = self.readyLiquid2TransposerOutputSide, name = "Ready Liquid 2"},
      {transposer = self.readyLiquid3TransposerProxy, readySide = self.readyLiquid3TransposerReadySide, outputSide = self.readyLiquid3TransposerOutputSide, name = "Ready Liquid 3"}
    }

    -- Search all interfaces for the required plasma
    for _, interfaceData in ipairs(interfaces) do
      if totalTransferred >= requiredAmountMB then
        break
      end

      local found, availableAmount, plasmaLabel, tankIndex = self:findPlasmaInTanks(
        interfaceData.transposer,
        interfaceData.readySide,
        dustLabel
      )

      if found then
        local remainingNeeded = requiredAmountMB - totalTransferred
        local amountToTransfer = math.min(availableAmount, remainingNeeded)
        
        event.push("log_info", "Found "..availableAmount.."mB of "..plasmaLabel.." in "..interfaceData.name..", transferring "..amountToTransfer.."mB")

        local transferred = self:transferFluidWithRetry(
          interfaceData.transposer,
          interfaceData.readySide,
          interfaceData.outputSide,
          tankIndex,
          amountToTransfer,
          plasmaLabel
        )
        
        totalTransferred = totalTransferred + transferred

        if transferred < amountToTransfer then
          event.push("log_warning", "Only transferred "..transferred.."mB of "..plasmaLabel.." from "..interfaceData.name.." out of "..amountToTransfer.."mB requested")
        else
          event.push("log_info", "Successfully transferred "..transferred.."mB of "..plasmaLabel.." from "..interfaceData.name)
        end
      end
    end

    if totalTransferred < requiredAmountMB then
      local transferredIngots = math.floor(totalTransferred / PLASMA_CONVERSION_FACTOR)
      local requiredIngots = math.floor(requiredAmountMB / PLASMA_CONVERSION_FACTOR)
      event.push("log_error", "Only transferred "..totalTransferred.."mB ("..transferredIngots.." ingots) of plasma out of "..requiredAmountMB.."mB ("..requiredIngots.." ingots) requested")
      return false
    end

    local totalIngots = math.floor(totalTransferred / PLASMA_CONVERSION_FACTOR)
    event.push("log_info", "Successfully transferred "..totalTransferred.."mB ("..totalIngots.." ingots) of "..dustLabel.." plasma from ready interfaces")
    return true
  end

  ---Check for specific fluid in liquids list
  ---@param fluids table
  ---@param fluidName string
  ---@param interfaceName string
  ---@return boolean found
  ---@private
  function obj:checkForFluidInLiquids(fluids, fluidName, interfaceName)
    for _, fluid in pairs(fluids) do
      if not fluid then
        goto continue
      end
      
      local fluidNameToCheck = getFluidNameToCheck(fluid)
      local isMatch = false
      
      if fluidName == "Tachyon Rich Temporal Fluid" then
        isMatch = isTachyonRichTemporalFluid(fluidNameToCheck)
      elseif fluidName == "Spatially Enlarged Fluid" then
        isMatch = isSpatiallyEnlargedFluid(fluidNameToCheck)
      end
      
      if isMatch then
        event.push("log_info", "Found "..(fluid.amount or 0).."mB "..fluidName:lower().." in "..interfaceName)
        return true
      end
      
      ::continue::
    end
    
    return false
  end

  ---Return liquids to puzzle output interfaces
  ---Verifies liquids are in interface inventory, not network
  ---@return boolean
  ---@private
  function obj:returnLiquidsToPuzzle()
    if self.stateMachine.data.puzzleOutput == nil then
      return false
    end

    event.push("log_info", "Verifying liquids in puzzle output interfaces")

    -- The liquids should already be in the puzzle output interfaces from the transposers
    -- The transposers above the ready liquid interfaces transfer directly to puzzle output
    -- So we just need to verify they're there by checking interface inventory

    -- Check puzzle output 1 interface inventory
    local _, liquids1 = self:getInterfaceContents(
      self.puzzleOutput1TransposerProxy,
      self.puzzleOutput1TransposerOutputSide
    )

    -- Check puzzle output 2 interface inventory
    local _, liquids2 = self:getInterfaceContents(
      self.puzzleOutput2TransposerProxy,
      self.puzzleOutput2TransposerOutputSide
    )

    -- Check both interfaces for required fluids
    -- Note: Plasmas are in ready liquid interfaces, not puzzle output
    -- Puzzle output only contains tachyon, spatially enlarged fluid, and dust
    local tachyonFound = self:checkForFluidInLiquids(liquids1, "Tachyon Rich Temporal Fluid", "puzzle output 1") or
                         self:checkForFluidInLiquids(liquids2, "Tachyon Rich Temporal Fluid", "puzzle output 2")
    
    local spatiallyEnlargedFound = self:checkForFluidInLiquids(liquids1, "Spatially Enlarged Fluid", "puzzle output 1") or
                                  self:checkForFluidInLiquids(liquids2, "Spatially Enlarged Fluid", "puzzle output 2")

    if not tachyonFound then
      event.push("log_warning", "Tachyon rich temporal fluid not found in puzzle output interfaces")
    end
    if not spatiallyEnlargedFound then
      event.push("log_warning", "Spatially enlarged fluid not found in puzzle output interfaces")
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

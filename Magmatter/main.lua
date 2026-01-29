local keyboard = require("keyboard")
local computer = require("computer")

local programLib = require("lib.program-lib")
local guiLib = require("lib.gui-lib")

local scrollList = require("lib.gui-widgets.scroll-list")

package.loaded.config = nil
local config = require("config")

local version = require("version")

local repository = "your-username/godforgeqgp"
local archiveName = "Magmatter"

local program = programLib:new(config.logger, config.enableAutoUpdate, version, repository, archiveName)
local gui = guiLib:new(program)

local mainTemplate = {
  width = 60,
  background = gui.palette.black,
  foreground = gui.palette.white,
  widgets = {
    logsScrollList = scrollList:new("logsScrollList", "logs", keyboard.keys.up, keyboard.keys.down)
  },
  lines = {
    "Magmatter Controller",
    "Status: $state$",
    "",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#",
    "#logsScrollList#"
  }
}

local function init()
  gui:setTemplate(mainTemplate)
  os.sleep(0.1)
  config.controller:init()
end

local function loop()
  while true do
    config.controller:loop()
    -- Very small sleep to minimize delay between state transitions
    -- State transitions happen immediately in init functions, so this just prevents CPU spinning
    os.sleep(0.05)
  end
end

local function guiLoop()
  -- Only render GUI when stuck (error state or idle for too long)
  local currentState = config.controller.stateMachine.currentState
  local stateName = currentState ~= nil and currentState.name or "nil"
  local isStuck = false
  
  if stateName == "Error" then
    -- Always render when in error state
    isStuck = true
  elseif stateName == "Idle" then
    -- Render if idle for more than 4 minutes (stuck/idle warning threshold)
    local currentTime = computer.uptime()
    local timeInIdle = currentTime - (config.controller.stateMachine.data.time or 0)
    if timeInIdle > 240 then -- IDLE_WARNING_THRESHOLD
      isStuck = true
    end
  end
  
  if isStuck then
    gui:render({
      state = stateName,
      logs = config.logger.handlers[2]["logs"].list
    })
  end
end

local function errorButtonHandler()
  config.controller:resetError()
end

local function clearErrorList()
  ---@type ScrollListLoggerHandler|LoggerHandler
  local logger = config.logger.handlers[2]
  logger:clearList()
end

program:registerInit(init)
program:registerThread(loop)
program:registerTimer(guiLoop, math.huge, 1)
program:registerKeyHandler(keyboard.keys.enter, errorButtonHandler)
program:registerKeyHandler(keyboard.keys.delete, clearErrorList)
program:start()


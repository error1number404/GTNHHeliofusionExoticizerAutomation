local keyboard = require("keyboard")

local programLib = require("lib.program-lib")
local guiLib = require("lib.gui-lib")

local scrollList = require("lib.gui-widgets.scroll-list")

package.loaded.config = nil
local config = require("config")

local version = require("version")

local repository = "your-username/godforgeqgp"
local archiveName = "QuarkGluonPlasma"

local program = programLib:new(config.logger, config.enableAutoUpdate, version, repository, archiveName)
local gui = guiLib:new(program)

local logo = {
"  ____            _    _       _   _             ____  _           _   _       _   _  ____  ",
" / ___|_   _  ___| | _| | __ _| | | |_   _ _ __ |  _ \\| | __ _ ___| |_(_) __ _| | | |/ ___| ",
"| |  _| | | |/ __| |/ / |/ _` | | | | | | | '_ \\| |_) | |/ _` / __| __| |/ _` | | | |\\___ \\ ",
"| |_| | |_| | (__|   <| | (_| | | | | |_| | | | |  __/| | (_| \\__ \\ |_| | (_| | |_| | ___) |",
" \\____|\\__,_|\\___|_|\\_\\_|\\__,_|_| |_|\\__,_|_| |_|_|   |_|\\__,_|___/\\__|_|\\__,_|\\___/ |____/ ",
"                                                                                              ",
"  ____  _                   ____  _                           ",
" / ___|| |_ __ _ _ __   ___|  _ \\| | __ _ _ __   __ _  ___   ",
" \\___ \\| __/ _` | '_ \\ / _ \\ |_) | |/ _` | '_ \\ / _` |/ _ \\  ",
"  ___) | || (_| | | | |  __/  __/| | (_| | | | | (_| |  __/  ",
" |____/ \\__\\__,_|_| |_|\\___|_|   |_|\\__,_|_| |_|\\__, |\\___|  ",
"                                                |___/          "
}

local mainTemplate = {
  width = 60,
  background = gui.palette.black,
  foreground = gui.palette.white,
  widgets = {
    logsScrollList = scrollList:new("logsScrollList", "logs", keyboard.keys.up, keyboard.keys.down)
  },
  lines = {
    "QuarkGluonPlasma Controller",
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
    os.sleep(1)
  end
end

local function guiLoop()
  gui:render({
    state = config.controller.stateMachine.currentState ~= nil and config.controller.stateMachine.currentState.name or "nil",
    logs = config.logger.handlers[2]["logs"].list
  })
end

local function errorButtonHandler()
  config.controller:resetError()
end

local function clearErrorList()
  ---@type ScrollListLoggerHandler|LoggerHandler
  local logger = config.logger.handlers[2]
  logger:clearList()
end

program:registerLogo(logo)
program:registerInit(init)
program:registerThread(loop)
program:registerTimer(guiLoop, math.huge, 1)
program:registerKeyHandler(keyboard.keys.enter, errorButtonHandler)
program:registerKeyHandler(keyboard.keys.delete, clearErrorList)
program:start()


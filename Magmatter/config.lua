local sides = require("sides")

local loggerLib = require("lib.logger-lib")
local fileLoggerHandler = require("lib.logger-handler.file-logger-handler-lib")
local scrollListLoggerHandler = require("lib.logger-handler.scroll-list-logger-handler-lib")

local magmatterController = require("src.magmatter-controller")

local config = {
  enableAutoUpdate = false, -- Enable auto update on start

  logger = loggerLib:newFormConfig({
    name = "Magmatter Control",
    timeZone = 3, -- Your time zone
    handlers = {
      fileLoggerHandler:newFormConfig({
        logLevel = "info",
        messageFormat = "{Time:%d.%m.%Y %H:%M:%S} [{LogLevel}]: {Message}",
        filePath = "logs.log"
      }),
      scrollListLoggerHandler:newFormConfig({
        logLevel = "debug",
        logsListSize = 32
      }),
    }
  }),

  controller = magmatterController:newFormConfig({
    outputMeInterfaceAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", -- Address of me interface in dedicated subnet connected to Heliofusion Exoticizer output.
    mainMeInterfaceAddress = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", -- Address of me interface connected to main AE network.
    inputMeInterfaceAddress = "cccccccc-cccc-cccc-cccc-cccccccccccc", -- Address of me interface in subnet responsible for inputting liquids to Heliofusion Exoticizer.
    outputTransposerAddress = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", -- Address of transposer connected to output adapter.
    mainTransposerAddress = "ffffffff-ffff-ffff-ffff-ffffffffffff", -- Address of transposer connected to main adapter.
    inputTransposerAddress = "gggggggg-gggg-gggg-gggg-gggggggggggg", -- Address of transposer connected to input adapter.
    mainTransposerMainSide = sides.down, -- Side of main transposer connected to main interface.
    mainTransposerInputSide = sides.up, -- Side of main transposer connected to input interface.
    redstoneIoAddress = "dddddddd-dddd-dddd-dddd-dddddddddddd", -- Redstone IO Address.
    redstoneIoSide = sides.east -- Side of the redstone IO which connected to ME Level Emitter or other controller.
  })
}

return config


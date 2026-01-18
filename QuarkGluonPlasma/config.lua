local sides = require("sides")

local loggerLib = require("lib.logger-lib")
local fileLoggerHandler = require("lib.logger-handler.file-logger-handler-lib")
local scrollListLoggerHandler = require("lib.logger-handler.scroll-list-logger-handler-lib")

local quarkGluonPlasmaController = require("src.quarkgluonplasma-controller")

local config = {
  enableAutoUpdate = false, -- Enable auto update on start

  logger = loggerLib:newFormConfig({
    name = "QuarkGluonPlasma Control",
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

  controller = quarkGluonPlasmaController:newFormConfig({
    outputMeInterfaceAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", -- Address of me interface connected to Heliofusion Exoticizer output.
    plasmaMeInterfaceAddress = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", -- Address of me interface connected to Plasma module dedicated AE.
    mainMeInterfaceAddress = "cccccccc-cccc-cccc-cccc-cccccccccccc", -- Address of me interface connected to main AE network.
    outputTransposerAddress = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", -- Address of transposer connected to output adapter.
    plasmaTransposerAddress = "ffffffff-ffff-ffff-ffff-ffffffffffff", -- Address of transposer connected to plasma adapter.
    mainTransposerAddress = "gggggggg-gggg-gggg-gggg-gggggggggggg", -- Address of transposer connected to main adapter.
    outputTransposerOutputSide = sides.down, -- Side of output transposer connected to output interface.
    outputTransposerPlasmaSide = sides.up, -- Side of output transposer connected to plasma interface.
    mainTransposerMainSide = sides.down, -- Side of main transposer connected to main interface.
    mainTransposerPlasmaSide = sides.up, -- Side of main transposer connected to plasma interface.
    redstoneIoAddress = "dddddddd-dddd-dddd-dddd-dddddddddddd", -- Redstone IO Address.
    redstoneIoSide = sides.east -- Side of the redstone IO which connected to ME Level Emitter or other controller.
  })
}

return config


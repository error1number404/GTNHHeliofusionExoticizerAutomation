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
    puzzleOutput1MeInterfaceAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", -- Address of first puzzle output me interface.
    puzzleOutput2MeInterfaceAddress = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", -- Address of second puzzle output me interface.
    mainMeInterfaceAddress = "cccccccc-cccc-cccc-cccc-cccccccccccc", -- Address of main me interface (above puzzle output transposers).
    readyLiquid1MeInterfaceAddress = "dddddddd-dddd-dddd-dddd-dddddddddddd", -- Address of first ready liquid me interface (6 plasmas).
    readyLiquid2MeInterfaceAddress = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", -- Address of second ready liquid me interface (6 plasmas).
    readyLiquid3MeInterfaceAddress = "ffffffff-ffff-ffff-ffff-ffffffffffff", -- Address of third ready liquid me interface (2 plasmas + tachyon + spatially enlarged).
    puzzleOutput1TransposerAddress = "11111111-1111-1111-1111-111111111111", -- Address of transposer above first puzzle output interface.
    puzzleOutput2TransposerAddress = "22222222-2222-2222-2222-222222222222", -- Address of transposer above second puzzle output interface.
    readyLiquid1TransposerAddress = "33333333-3333-3333-3333-333333333333", -- Address of transposer above first ready liquid interface.
    readyLiquid2TransposerAddress = "44444444-4444-4444-4444-444444444444", -- Address of transposer above second ready liquid interface.
    readyLiquid3TransposerAddress = "55555555-5555-5555-5555-555555555555", -- Address of transposer above third ready liquid interface.
    puzzleOutput1TransposerOutputSide = sides.down, -- Side of puzzle output 1 transposer connected to puzzle output interface.
    puzzleOutput1TransposerMainSide = sides.up, -- Side of puzzle output 1 transposer connected to main interface.
    puzzleOutput2TransposerOutputSide = sides.down, -- Side of puzzle output 2 transposer connected to puzzle output interface.
    puzzleOutput2TransposerMainSide = sides.up, -- Side of puzzle output 2 transposer connected to main interface.
    readyLiquid1TransposerReadySide = sides.down, -- Side of ready liquid 1 transposer connected to ready liquid interface.
    readyLiquid1TransposerOutputSide = sides.up, -- Side of ready liquid 1 transposer connected to puzzle output.
    readyLiquid2TransposerReadySide = sides.down, -- Side of ready liquid 2 transposer connected to ready liquid interface.
    readyLiquid2TransposerOutputSide = sides.up, -- Side of ready liquid 2 transposer connected to puzzle output.
    readyLiquid3TransposerReadySide = sides.down, -- Side of ready liquid 3 transposer connected to ready liquid interface.
    readyLiquid3TransposerOutputSide = sides.up -- Side of ready liquid 3 transposer connected to puzzle output.
  })
}

return config


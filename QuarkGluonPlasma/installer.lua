local shell = require("shell")
local filesystem = require("filesystem")

local repo = "https://raw.githubusercontent.com/error1number404/GTNHHeliofusionExoticizerAutomation/"
local branch = "master"

local files = {
  "QuarkGluonPlasma/main.lua",
  "QuarkGluonPlasma/version.lua",
  "QuarkGluonPlasma/src/quarkgluonplasma-controller.lua",
  "QuarkGluonPlasma/lib/component-discover-lib.lua",
  "QuarkGluonPlasma/lib/gui-lib.lua",
  "QuarkGluonPlasma/lib/list-lib.lua",
  "QuarkGluonPlasma/lib/logger-lib.lua",
  "QuarkGluonPlasma/lib/program-lib.lua",
  "QuarkGluonPlasma/lib/state-machine-lib.lua",
  "QuarkGluonPlasma/lib/gui-widgets/scroll-list.lua",
  "QuarkGluonPlasma/lib/logger-handler/discord-logger-handler-lib.lua",
  "QuarkGluonPlasma/lib/logger-handler/file-logger-handler-lib.lua",
  "QuarkGluonPlasma/lib/logger-handler/scroll-list-logger-handler-lib.lua",
}

local dirs = {"QuarkGluonPlasma/src", "QuarkGluonPlasma/lib", "QuarkGluonPlasma/lib/gui-widgets", "QuarkGluonPlasma/lib/logger-handler"}

-- Create directories
for _, dir in ipairs(dirs) do
  local path = shell.getWorkingDirectory() .. "/" .. dir
  if not filesystem.exists(path) then
    filesystem.makeDirectory(path)
  end
end

-- Download all files
for _, file in ipairs(files) do
  local url = repo .. branch .. "/" .. file
  local path = shell.getWorkingDirectory() .. "/" .. file
  
  if filesystem.exists(path) then
    filesystem.remove(path)
  end
  
  print("Downloading " .. file .. "...")
  shell.execute("wget -fq " .. url .. " " .. path)
end

-- Download config only if it doesn't exist
local configPath = shell.getWorkingDirectory() .. "/config.lua"
if not filesystem.exists(configPath) then
  print("Downloading default config.lua...")
  shell.execute("wget -fq " .. repo .. branch .. "QuarkGluonPlasma/config.lua " .. configPath)
else
  print("Config.lua already exists - preserved")
end

print("\nInstallation complete!")


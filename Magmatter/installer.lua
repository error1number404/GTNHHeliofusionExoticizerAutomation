local shell = require("shell")
local filesystem = require("filesystem")

local repo = "https://raw.githubusercontent.com/error1number404/GTNHHeliofusionExoticizerAutomation/"
local branch = "master"

local files = {
  "Magmatter/main.lua",
  "Magmatter/version.lua",
  "Magmatter/src/magmatter-controller.lua",
  "Magmatter/lib/component-discover-lib.lua",
  "Magmatter/lib/gui-lib.lua",
  "Magmatter/lib/list-lib.lua",
  "Magmatter/lib/logger-lib.lua",
  "Magmatter/lib/program-lib.lua",
  "Magmatter/lib/state-machine-lib.lua",
  "Magmatter/lib/gui-widgets/scroll-list.lua",
  "Magmatter/lib/logger-handler/discord-logger-handler-lib.lua",
  "Magmatter/lib/logger-handler/file-logger-handler-lib.lua",
  "Magmatter/lib/logger-handler/scroll-list-logger-handler-lib.lua",
}

local dirs = {"Magmatter/src", "Magmatter/lib", "Magmatter/lib/gui-widgets", "Magmatter/lib/logger-handler"}

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
local configPath = shell.getWorkingDirectory() .. "/Magmatter/config.lua"
if not filesystem.exists(configPath) then
  print("Downloading default config.lua...")
  shell.execute("wget -fq " .. repo .. branch .. "/Magmatter/config.lua " .. configPath)
else
  print("Config.lua already exists - preserved")
end

print("\nInstallation complete!")


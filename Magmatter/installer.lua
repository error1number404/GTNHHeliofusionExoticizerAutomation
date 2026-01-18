local shell = require("shell")
local filesystem = require("filesystem")

local repo = "https://raw.githubusercontent.com/error1number404/GTNHMagmatterAutomation/"
local branch = "master"

local files = {
  "main.lua",
  "version.lua",
  "src/magmatter-controller.lua",
  "lib/component-discover-lib.lua",
  "lib/gui-lib.lua",
  "lib/list-lib.lua",
  "lib/logger-lib.lua",
  "lib/program-lib.lua",
  "lib/state-machine-lib.lua",
  "lib/gui-widgets/scroll-list.lua",
  "lib/logger-handler/discord-logger-handler-lib.lua",
  "lib/logger-handler/file-logger-handler-lib.lua",
  "lib/logger-handler/scroll-list-logger-handler-lib.lua",
}

local dirs = {"src", "lib", "lib/gui-widgets", "lib/logger-handler"}

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
  shell.execute("wget -fq " .. repo .. branch .. "/config.lua " .. configPath)
else
  print("Config.lua already exists - preserved")
end

print("\nInstallation complete!")
os.sleep(2)
shell.execute("reboot")


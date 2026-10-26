---
sidebar_position: 2
---

# Installation

### Method 1 - HTTP request in the Studio console

1. In Roblox Studio, select the folder where you keep your third party modules / utilities.
2. Run this in the command bar:

```lua
local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")

local parent = Selection:Get()[1] or game:GetService("ReplicatedStorage")

local function createModule(name, url)
    local module = Instance.new("ModuleScript")
    module.Name = name
    module.Source = HttpService:GetAsync(url)
    module.Parent = parent
    return module
end

local baseUrl = "https://raw.githubusercontent.com/Dyscarn/Dysconnect/refs/heads/main/src/"

local main = createModule("Dysconnect", `{baseUrl}init.luau`)
createModule("DataTypes", `{baseUrl}DataTypes.luau`).Parent = main
```

### Method 2 - Manual

Visit the latest release.

Under Assets, download the Dysconnect release file, if one is provided.

Choose the method that matches your workflow:

Using sync tools like Rojo or Argon? Add the downloaded file to your project and update your Rojo configuration as needed.

Using Roblox Studio? Drop the file into the workspace and move it somewhere under ReplicatedStorage.

### Method 3 - Git Submodule

Add the Dysconnect repository as a Git submodule, ideally inside a folder named submodules.

Update your sync tool project configuration to include the module.

Sync your project with Roblox Studio.

### Method 4 - Package Manager

Dysconnect currently supports [Wally](https://github.com/UpliftGames/wally/). For support in other package managers, contact Dyscarn in the Discord (top-right) or open a request issue in GitHub.

---

## Next

See the [API reference](/api/Dysconnect) for the complete list of available methods and their parameters.
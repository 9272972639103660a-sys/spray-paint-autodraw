--!strict
-- Security & Remote Protocol Handler for Spray Paint!
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Security = {}

local cachedErrorModule = nil
local cachedScriptPath = nil

local function getErrorModule()
    if cachedErrorModule ~= nil then
        return cachedErrorModule
    end

    local success, module = pcall(function()
        local printFolder = ReplicatedStorage:FindFirstChild("Modules")
        if printFolder then
            local p = printFolder:FindFirstChild("Print")
            if p then
                local em = p:FindFirstChild("ErrorModule")
                if em and em:IsA("ModuleScript") then
                    return require(em)
                end
            end
        end
        return nil
    end)

    if success and module then
        cachedErrorModule = module
    else
        cachedErrorModule = false
    end

    return cachedErrorModule
end

local function getLocalScriptFullName(): string?
    if cachedScriptPath then
        return cachedScriptPath
    end

    local lp = Players.LocalPlayer
    if not lp then return nil end

    local pg = lp:FindFirstChild("PlayerGui")
    if pg then
        local paintGui = pg:FindFirstChild("PaintGui")
        if paintGui then
            local ls = paintGui:FindFirstChild("LocalScript")
            if ls then
                cachedScriptPath = ls:GetFullName()
                return cachedScriptPath
            end
        end
    end

    return "Players." .. lp.Name .. ".PlayerGui.PaintGui.LocalScript"
end

-- Returns security arguments (number, hash) or fallback tokens
function Security.getSecurityArgs(): (number, any)
    local errMod = getErrorModule()
    local serverTime = Workspace:GetServerTimeNow()

    if errMod and typeof(errMod) == "function" then
        local scriptPath = getLocalScriptFullName()
        local success, hash = pcall(function()
            return errMod(scriptPath, serverTime * 72000)
        end)

        if success and hash then
            return serverTime, hash
        end
    end

    -- Legacy fallback token
    return 300000, 300000
end

-- Finds the SprayPaint tool in character or backpack
function Security.findSprayPaintTool(): Tool?
    local lp = Players.LocalPlayer
    if not lp then return nil end

    local char = lp.Character
    if char then
        local tool = char:FindFirstChild("SprayPaint")
        if tool and tool:IsA("Tool") then
            return tool
        end
    end

    local bp = lp:FindFirstChild("Backpack")
    if bp then
        local tool = bp:FindFirstChild("SprayPaint")
        if tool and tool:IsA("Tool") then
            return tool
        end
    end

    return nil
end

-- Finds the Remote used for painting (SendPaintInfo)
function Security.findPaintRemote(tool: Tool?): (Instance?, string?)
    local currentTool = tool or Security.findSprayPaintTool()
    if currentTool then
        local remote = currentTool:FindFirstChild("SendPaintInfo")
        if remote then
            if remote:IsA("RemoteFunction") then
                return remote, "InvokeServer"
            elseif remote:IsA("RemoteEvent") then
                return remote, "FireServer"
            end
        end
    end

    -- Check ReplicatedStorage in case remotes moved
    local rsRemotes = ReplicatedStorage:FindFirstChild("Remotes")
    if rsRemotes then
        local paintRemote = rsRemotes:FindFirstChild("SendPaintInfo") or rsRemotes:FindFirstChild("Paint")
        if paintRemote then
            if paintRemote:IsA("RemoteFunction") then
                return paintRemote, "InvokeServer"
            elseif paintRemote:IsA("RemoteEvent") then
                return paintRemote, "FireServer"
            end
        end
    end

    return nil, nil
end

return Security

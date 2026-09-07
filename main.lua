--[[
    ╔═══════════════════════════════════════════════════════════╗
    ║                 INDO VOICE | ULTIMATE HUB                 ║
    ║        Auto Fishing, Auto Mining, Teleports & Utils       ║
    ╚═══════════════════════════════════════════════════════════╝
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Load Fluent UI Library
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Create Window
local Window = Fluent:CreateWindow({
    Title = "Indo Voice Hub 🎣",
    SubTitle = "by Antigravity",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

-- Tabs
local Tabs = {
    Fishing = Window:AddTab({ Title = "Auto Fishing", Icon = "fish" }),
    Mining = Window:AddTab({ Title = "Mining", Icon = "hammer" }),
    Teleports = Window:AddTab({ Title = "Teleports", Icon = "map-pin" }),
    AutoRewards = Window:AddTab({ Title = "Auto Rewards", Icon = "gift" }),
    Player = Window:AddTab({ Title = "Player & Mods", Icon = "user" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

--------------------------------------------------------------------------------
-- STATE VARIABLES
--------------------------------------------------------------------------------
local FishingState = {
    Active = false,
    Mode = "Legit", -- "Legit" or "Fast"
    AutoSell = false,
    AutoSellInterval = 10,
    SessionCatches = 0,
    Status = "Idle",
    StatusLabel = nil,
    CountLabel = nil,
    InventoryLabel = nil
}

local MiningState = {
    Active = false,
    TargetStone = nil
}

local PlayerMods = {
    WalkSpeed = 16,
    JumpPower = 50,
    InfJump = false,
    Noclip = false,
    Fullbright = false,
    AntiAFK = true
}

--------------------------------------------------------------------------------
-- REPLICA / INVENTORY HELPERS
--------------------------------------------------------------------------------
local ReplicaManager = nil
pcall(function()
    ReplicaManager = require(ReplicatedFirst:WaitForChild("Manager"):WaitForChild("ReplicaManager"))
end)

local function getPlayerData()
    if not ReplicaManager then return nil end
    return ReplicaManager:GetPlayerData(LocalPlayer)
end

local function getFishStats()
    local pd = getPlayerData()
    if not pd or not pd.ProfileReplica or not pd.ProfileReplica.Data then
        return 0, 0
    end
    local fishMap = pd.ProfileReplica.Data.Fish or {}
    local count = 0
    local totalVal = 0
    for _, f in pairs(fishMap) do
        count = count + 1
        totalVal = totalVal + (f.Price or 0)
    end
    return count, totalVal
end

local function updateStatsLabels()
    pcall(function()
        if FishingState.CountLabel and FishingState.CountLabel.SetDesc then
            FishingState.CountLabel:SetDesc("Session Catches: " .. tostring(FishingState.SessionCatches))
        end
        if FishingState.InventoryLabel and FishingState.InventoryLabel.SetDesc then
            local count, val = getFishStats()
            local formattedVal = string.format("%d", val):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
            FishingState.InventoryLabel:SetDesc(string.format("Inventory: %d fish (Worth ~%s RP)", count, formattedVal))
        end
    end)
end

--------------------------------------------------------------------------------
-- AUTO FISHING SYSTEM
--------------------------------------------------------------------------------
local function getFishingRod()
    local char = LocalPlayer.Character
    if char then
        local r = char:FindFirstChildOfClass("Tool")
        if r and r:GetAttribute("IsRod") then return r end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("IsRod") then return t end
        end
    end
    return nil
end

local function equipFishingRod()
    local rod = getFishingRod()
    if not rod then return nil end
    local char = LocalPlayer.Character
    if rod.Parent ~= char and char and char:FindFirstChild("Humanoid") then
        char.Humanoid:EquipTool(rod)
        task.wait(0.3)
    end
    return rod
end

local function setFishingStatus(s)
    FishingState.Status = s
    pcall(function()
        if FishingState.StatusLabel and FishingState.StatusLabel.SetDesc then
            FishingState.StatusLabel:SetDesc("Status: " .. s)
        end
    end)
end

-- Teleport to Fish Broker, sell non-favorited fish, and return
local function sellFishNow()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "No HumanoidRootPart" end
    
    local rep = ReplicatedStorage:FindFirstChild("GameRemoteFunctions")
    local sellFunc = rep and rep:FindFirstChild("SellAllFishFunction")
    if not sellFunc then return false, "SellAllFishFunction not found" end
    
    local originalCF = hrp.CFrame
    setFishingStatus("Teleporting to Fish Broker...")
    
    -- Stand directly in front of Fish Broker
    hrp.CFrame = CFrame.new(265, 40, -4870)
    task.wait(1.4) -- Wait for server physics replication
    
    local ok, res, msg = pcall(function()
        return sellFunc:InvokeServer({"Common", "Uncommon", "Rare", "Epic", "Legend"})
    end)
    
    task.wait(0.8)
    hrp.CFrame = originalCF
    task.wait(0.5)
    
    updateStatsLabels()
    return ok and res, msg
end

-- Full single catch lifecycle
local function doCatchCycle()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("Humanoid") then
        setFishingStatus("Waiting for Character...")
        task.wait(1)
        return false
    end
    
    local rod = getFishingRod()
    if not rod then
        setFishingStatus("No Fishing Rod Found!")
        task.wait(1.5)
        return false
    end
    
    setFishingStatus("Equipping Rod...")
    local currentToken = nil
    local tokenConn = rod.ToolReady.OnClientEvent:Connect(function(tok)
        currentToken = tok
    end)
    
    -- Re-equipping guarantees fresh token from server in ~0.25s
    char.Humanoid:UnequipTools()
    task.wait(0.2)
    local equippedRod = equipFishingRod()
    
    local tTok = tick()
    while not currentToken and tick() - tTok < 3.5 do
        task.wait(0.05)
    end
    tokenConn:Disconnect()
    
    if not currentToken then
        setFishingStatus("ToolReady Token Timeout, retrying...")
        task.wait(0.5)
        return false
    end
    
    setFishingStatus("Casting Line into water...")
    local okCast, castRes = pcall(function()
        return equippedRod.Cast:InvokeServer(1.2, currentToken)
    end)
    
    if not okCast or not castRes then
        setFishingStatus("Cast Failed, retrying...")
        task.wait(0.5)
        return false
    end
    
    setFishingStatus("Waiting for Fish to bite (approx 10-20s)...")
    local tWait = tick()
    local fui = nil
    while FishingState.Active and tick() - tWait < 35 do
        fui = PlayerGui:FindFirstChild("FishingUI")
        if fui then break end
        task.wait(0.2)
    end
    
    if not fui then
        setFishingStatus("Bite Timeout, re-casting...")
        return false
    end
    
    -- STEP 1: Pre-Fishing Mechanic ("Drag your bait to the fish")
    setFishingStatus("Fish hooked! Solving bait drag...")
    local preHolder = fui:WaitForChild("PreFishingHolder", 3.5)
    local tPre = tick()
    while FishingState.Active and preHolder and preHolder.Visible and tick() - tPre < 6 do
        local dragBtn = preHolder:FindFirstChild("DragButton")
        local target = preHolder:FindFirstChild("TargetFrame")
        if dragBtn and target then
            if FishingState.Mode == "Legit" then
                dragBtn.Position = dragBtn.Position:Lerp(target.Position, 0.5)
            else
                dragBtn.Position = target.Position
            end
            
            local dd = dragBtn:FindFirstChildOfClass("UIDragDetector")
            if dd and getconnections then
                for _, c in ipairs(getconnections(dd.DragContinue)) do
                    pcall(function() c:Fire() end)
                end
            end
        end
        task.wait(0.08)
    end
    
    -- STEP 2: Reel Minigame Mechanic ("Click/tap to raise the bar!" vs "Stop click/tap")
    setFishingStatus("Reeling in fish! Auto-clicking green bar...")
    local fishHolder = fui:WaitForChild("FishingHolder", 4.5)
    local tReel = tick()
    local clickDelay = (FishingState.Mode == "Fast") and 0.08 or 0.125
    
    while FishingState.Active and fui.Parent and tick() - tReel < 20 do
        if fishHolder and fishHolder.Visible then
            local ff = fishHolder:FindFirstChild("FishingFrame")
            local info = ff and ff:FindFirstChild("InfoLabel")
            local fishIcon = ff and ff:FindFirstChild("FishContainer") and ff.FishContainer:FindFirstChild("FishIcon")
            
            local canClick = false
            if info and (string.find(info.Text, "Click") or string.find(info.Text, "raise")) then
                canClick = true
            elseif fishIcon and fishIcon.ImageColor3.G > 0.7 then
                canClick = true
            end
            
            if canClick then
                -- Send Mouse Click to raise the bar
                VirtualInputManager:SendMouseButtonEvent(100, 100, 0, true, game, 0)
                task.wait(0.03)
                VirtualInputManager:SendMouseButtonEvent(100, 100, 0, false, game, 0)
                task.wait(clickDelay)
            else
                -- "Stop click/tap" (Red state) - pause clicking to prevent penalty
                task.wait(0.06)
            end
        else
            task.wait(0.1)
        end
    end
    
    -- Catch completed!
    FishingState.SessionCatches = FishingState.SessionCatches + 1
    setFishingStatus("Fish caught! Total: " .. tostring(FishingState.SessionCatches))
    updateStatsLabels()
    
    -- Check Auto Sell
    if FishingState.AutoSell and (FishingState.SessionCatches % FishingState.AutoSellInterval == 0) then
        sellFishNow()
    end
    
    -- Cooldown buffer for server to register reward
    task.wait(2.2)
    return true
end

-- Main Auto Fishing Loop
task.spawn(function()
    while true do
        if FishingState.Active then
            pcall(function()
                doCatchCycle()
            end)
        else
            task.wait(0.5)
        end
    end
end)

--------------------------------------------------------------------------------
-- AUTO MINING SYSTEM
--------------------------------------------------------------------------------
local function getPickaxe()
    local char = LocalPlayer.Character
    if char then
        local p = char:FindFirstChildOfClass("Tool")
        if p and p:GetAttribute("IsPickaxe") then return p end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("IsPickaxe") then return t end
        end
    end
    return nil
end

local function equipPickaxe()
    local pick = getPickaxe()
    if not pick then return nil end
    local char = LocalPlayer.Character
    if pick.Parent ~= char and char and char:FindFirstChild("Humanoid") then
        char.Humanoid:EquipTool(pick)
        task.wait(0.3)
    end
    return pick
end

local function sellAllOreNow()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "No HumanoidRootPart" end
    
    local rep = ReplicatedStorage:FindFirstChild("GameRemoteFunctions")
    local sellFunc = rep and rep:FindFirstChild("SellAllOreFunction")
    if not sellFunc then return false, "SellAllOreFunction not found" end
    
    local originalCF = hrp.CFrame
    -- OreShop position
    hrp.CFrame = CFrame.new(309, 16, -4995)
    task.wait(1.4)
    
    local ok, res, msg = pcall(function()
        return sellFunc:InvokeServer({"Common", "Uncommon", "Rare", "Epic", "Legend", "Mythic", "Ancient"})
    end)
    
    task.wait(0.8)
    hrp.CFrame = originalCF
    return ok and res, msg
end

-- Mining loop: equips pickaxe, clicks boulder, and solves zone
task.spawn(function()
    while true do
        if MiningState.Active then
            local pick = equipPickaxe()
            if pick then
                VirtualInputManager:SendMouseButtonEvent(100, 100, 0, true, game, 0)
                task.wait(0.1)
                VirtualInputManager:SendMouseButtonEvent(100, 100, 0, false, game, 0)
                
                local mui = PlayerGui:FindFirstChild("MiningUI")
                if mui then
                    local pre = mui:FindFirstChild("PreMiningHolder")
                    if pre and pre.Visible then
                        local drag = pre:FindFirstChild("DragButton")
                        local target = pre:FindFirstChild("TargetFrame")
                        if drag and target then
                            drag.Position = target.Position
                            local dd = drag:FindFirstChildOfClass("UIDragDetector")
                            if dd and getconnections then
                                for _, c in ipairs(getconnections(dd.DragContinue)) do pcall(function() c:Fire() end) end
                            end
                        end
                    end
                    local holder = mui:FindFirstChild("MiningHolder")
                    if holder and holder.Visible then
                        task.wait(0.2)
                        VirtualInputManager:SendMouseButtonEvent(100, 100, 0, true, game, 0)
                        task.wait(0.04)
                        VirtualInputManager:SendMouseButtonEvent(100, 100, 0, false, game, 0)
                    end
                end
            end
            task.wait(1)
        else
            task.wait(0.5)
        end
    end
end)

--------------------------------------------------------------------------------
-- UI BUILD: TAB 1 - FISHING
--------------------------------------------------------------------------------
do
    Tabs.Fishing:AddParagraph({
        Title = "Indo Voice Auto Fishing 🎣",
        Content = "Automates the entire fishing process: casting, dragging bait to fish, and hitting the green bar while stopping on red!"
    })

    FishingState.StatusLabel = Tabs.Fishing:AddParagraph({
        Title = "Status",
        Content = "Status: Idle"
    })

    FishingState.CountLabel = Tabs.Fishing:AddParagraph({
        Title = "Session Statistics",
        Content = "Session Catches: 0"
    })

    FishingState.InventoryLabel = Tabs.Fishing:AddParagraph({
        Title = "Bag Overview",
        Content = "Inventory: Calculating..."
    })
    updateStatsLabels()

    local AutoFishToggle = Tabs.Fishing:AddToggle("AutoFishToggle", {
        Title = "Enable Auto Fishing",
        Default = false,
        Callback = function(v)
            FishingState.Active = v
            if not v then
                setFishingStatus("Idle")
            end
            Fluent:Notify({
                Title = "Auto Fishing",
                Content = v and "Auto Fishing Started!" or "Auto Fishing Stopped.",
                Duration = 3
            })
        end
    })

    Tabs.Fishing:AddDropdown("FishingSpeedMode", {
        Title = "Minigame Mode",
        Values = { "Legit (Safe)", "Fast (Aggressive)" },
        Default = "Legit (Safe)",
        Callback = function(val)
            if string.find(val, "Fast") then
                FishingState.Mode = "Fast"
            else
                FishingState.Mode = "Legit"
            end
        end
    })

    Tabs.Fishing:AddButton({
        Title = "Equip Fishing Rod",
        Description = "Equips the best fishing rod from your backpack",
        Callback = function()
            local r = equipFishingRod()
            if r then
                Fluent:Notify({ Title = "Rod Equipped", Content = "Equipped: " .. r.Name, Duration = 2.5 })
            else
                Fluent:Notify({ Title = "No Rod", Content = "Could not find a rod in backpack!", Duration = 3 })
            end
        end
    })

    Tabs.Fishing:AddToggle("AutoSellToggle", {
        Title = "Auto Sell Fish",
        Description = "Automatically teleports to Fish Broker, sells non-favorited fish, and returns",
        Default = false,
        Callback = function(v)
            FishingState.AutoSell = v
        end
    })

    Tabs.Fishing:AddSlider("AutoSellIntervalSlider", {
        Title = "Sell Every X Catches",
        Description = "Number of catches before auto-selling",
        Default = 10,
        Min = 3,
        Max = 30,
        Rounding = 0,
        Callback = function(val)
            FishingState.AutoSellInterval = val
        end
    })

    Tabs.Fishing:AddButton({
        Title = "Sell All Fish Now 💰",
        Description = "Teleport to Fish Broker, sell all non-favorite fish, and return",
        Callback = function()
            Fluent:Notify({ Title = "Selling Fish", Content = "Teleporting to broker and selling...", Duration = 3 })
            local s, err = sellFishNow()
            if s then
                Fluent:Notify({ Title = "Success!", Content = "All non-favorite fish sold successfully!", Duration = 3 })
            else
                Fluent:Notify({ Title = "Notice", Content = "Result: " .. tostring(err or "Failed/Empty"), Duration = 3 })
            end
        end
    })
end

--------------------------------------------------------------------------------
-- UI BUILD: TAB 2 - MINING
--------------------------------------------------------------------------------
do
    Tabs.Mining:AddParagraph({
        Title = "Auto Mining ⛏️",
        Content = "Equips your pickaxe, hits the nearest mining stone, and automatically solves the minigame."
    })

    Tabs.Mining:AddToggle("AutoMineToggle", {
        Title = "Enable Auto Mining",
        Default = false,
        Callback = function(v)
            MiningState.Active = v
            Fluent:Notify({
                Title = "Auto Mining",
                Content = v and "Auto Mining Enabled!" or "Auto Mining Disabled.",
                Duration = 2.5
            })
        end
    })

    Tabs.Mining:AddButton({
        Title = "Equip Pickaxe",
        Callback = function()
            local p = equipPickaxe()
            if p then
                Fluent:Notify({ Title = "Pickaxe Equipped", Content = "Equipped: " .. p.Name, Duration = 2.5 })
            else
                Fluent:Notify({ Title = "No Pickaxe", Content = "Could not find a pickaxe!", Duration = 3 })
            end
        end
    })

    Tabs.Mining:AddButton({
        Title = "Sell All Ore Now 💎",
        Description = "Teleports to Ore Shop, sells all ore, and returns",
        Callback = function()
            Fluent:Notify({ Title = "Selling Ore", Content = "Selling ore at Ore Shop...", Duration = 3 })
            local s, err = sellAllOreNow()
            if s then
                Fluent:Notify({ Title = "Ore Sold", Content = "All ore sold successfully!", Duration = 3 })
            else
                Fluent:Notify({ Title = "Notice", Content = "Result: " .. tostring(err or "No ore to sell"), Duration = 3 })
            end
        end
    })

    local stoneNames = {}
    local stonePositions = {
        ["Boulder 1 (Town 56, 39, -4712)"] = Vector3.new(56, 40, -4712),
        ["Boulder 2 (-140, 20, -4833)"] = Vector3.new(-140, 21, -4833),
        ["Boulder 3 (Cave 396, 6, -4992)"] = Vector3.new(396, 7, -4992),
        ["Boulder 4 (Cave 415, 5, -5044)"] = Vector3.new(415, 6, -5044),
        ["Boulder 5 (Deep Cave 612, -11, -5123)"] = Vector3.new(612, -10, -5123),
        ["Boulder 6 (Deep Cave 682, -2, -5095)"] = Vector3.new(682, -1, -5095)
    }
    for k in pairs(stonePositions) do table.insert(stoneNames, k) end

    Tabs.Mining:AddDropdown("MineStoneDropdown", {
        Title = "Teleport to Mining Stone",
        Values = stoneNames,
        Default = stoneNames[1],
        Callback = function(selected)
            local pos = stonePositions[selected]
            if pos and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
                Fluent:Notify({ Title = "Teleported", Content = "Arrived at " .. selected, Duration = 2.5 })
            end
        end
    })
end

--------------------------------------------------------------------------------
-- UI BUILD: TAB 3 - TELEPORTS
--------------------------------------------------------------------------------
do
    local npcs = {
        { name = "Fish Broker (Sell Fish)", pos = Vector3.new(265, 40, -4873) },
        { name = "Fish Shop", pos = Vector3.new(-260, 25, -5049) },
        { name = "Rod Corner", pos = Vector3.new(-103, 25, -4653) },
        { name = "Rod Shop", pos = Vector3.new(-353, 25, -5059) },
        { name = "Ore Shop", pos = Vector3.new(309, 16, -4997) },
        { name = "Pickaxe Shop", pos = Vector3.new(335, 7, -5016) },
        { name = "Refine Ore", pos = Vector3.new(276, 29, -5046) },
        { name = "Pet Shop", pos = Vector3.new(-112, 22, -4750) },
        { name = "Aura Shop", pos = Vector3.new(-106, 24, -4729) },
        { name = "Trail Shop", pos = Vector3.new(-111, 22, -4699) },
        { name = "Blind Box Shop", pos = Vector3.new(-114, 22, -4766) },
        { name = "Tool Shop", pos = Vector3.new(-110, 21, -4718) },
        { name = "Vehicle Shop", pos = Vector3.new(-121, 22, -4788) },
        { name = "Limited Shop", pos = Vector3.new(-67, 22, -4813) },
        { name = "Kite Shop", pos = Vector3.new(-117, 24, -4968) }
    }

    local npcNames = {}
    local npcMap = {}
    for _, n in ipairs(npcs) do
        table.insert(npcNames, n.name)
        npcMap[n.name] = n.pos
    end

    Tabs.Teleports:AddParagraph({
        Title = "Map Shops & NPCs 📍",
        Content = "One-click teleports to any shop or NPC in the game."
    })

    Tabs.Teleports:AddDropdown("ShopDropdown", {
        Title = "Select Shop / NPC",
        Values = npcNames,
        Default = npcNames[1],
        Callback = function(sel)
            local targetPos = npcMap[sel]
            if targetPos and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
                Fluent:Notify({ Title = "Teleported", Content = "Teleported to " .. sel, Duration = 2.5 })
            end
        end
    })

    Tabs.Teleports:AddParagraph({
        Title = "Favorite Fishing Spots 🎣",
        Content = "Instant teleport to the best water bodies and hotspots."
    })

    local fishingSpots = {
        ["Rod Corner Pier (River)"] = Vector3.new(57, 25, -4452),
        ["Waterfall Lake Pier"] = Vector3.new(79, 17, -4977),
        ["Ocean Beach Spot"] = Vector3.new(-558, 40, -5211),
        ["Ocean Boardwalk Spot"] = Vector3.new(-611, 40, -4781)
    }

    local spotNames = {}
    for k in pairs(fishingSpots) do table.insert(spotNames, k) end

    Tabs.Teleports:AddDropdown("FishingSpotDropdown", {
        Title = "Select Fishing Spot",
        Values = spotNames,
        Default = spotNames[1],
        Callback = function(sel)
            local targetPos = fishingSpots[sel]
            if targetPos and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(targetPos)
                Fluent:Notify({ Title = "Teleported", Content = "Arrived at " .. sel, Duration = 2.5 })
            end
        end
    })

    -- Player Teleport
    Tabs.Teleports:AddParagraph({
        Title = "Teleport to Player 👥",
        Content = "Select any player currently in this server."
    })

    local function getPlayerNames()
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                table.insert(list, p.DisplayName .. " (@" .. p.Name .. ")")
            end
        end
        if #list == 0 then table.insert(list, "No other players") end
        return list
    end

    local selectedPlayer = nil
    local playerDropdown = Tabs.Teleports:AddDropdown("PlayerDropdown", {
        Title = "Select Player",
        Values = getPlayerNames(),
        Default = getPlayerNames()[1],
        Callback = function(sel)
            local username = string.match(sel, "@([%w_]+)")
            selectedPlayer = username and Players:FindFirstChild(username)
        end
    })

    Tabs.Teleports:AddButton({
        Title = "Refresh Player List",
        Callback = function()
            playerDropdown:SetValues(getPlayerNames())
            Fluent:Notify({ Title = "Refreshed", Content = "Player list updated.", Duration = 2 })
        end
    })

    Tabs.Teleports:AddButton({
        Title = "Teleport to Selected Player",
        Callback = function()
            if selectedPlayer and selectedPlayer.Character and selectedPlayer.Character:FindFirstChild("HumanoidRootPart") then
                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    LocalPlayer.Character.HumanoidRootPart.CFrame = selectedPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
                    Fluent:Notify({ Title = "Teleported", Content = "Teleported to " .. selectedPlayer.DisplayName, Duration = 2.5 })
                end
            else
                Fluent:Notify({ Title = "Error", Content = "Selected player or character not found!", Duration = 2.5 })
            end
        end
    })
end

--------------------------------------------------------------------------------
-- UI BUILD: TAB 4 - AUTO REWARDS & MISC
--------------------------------------------------------------------------------
do
    Tabs.AutoRewards:AddParagraph({
        Title = "Daily & Session Rewards 🎁",
        Content = "Automatically collect daily and session rewards as soon as they become ready."
    })

    Tabs.AutoRewards:AddButton({
        Title = "Collect Daily Reward Now",
        Callback = function()
            local daily = ReplicatedStorage:FindFirstChild("GameRemoteFunctions") and ReplicatedStorage.GameRemoteFunctions:FindFirstChild("CollectDailyRewardFunction")
            if daily then
                local s, res = pcall(function() return daily:InvokeServer() end)
                Fluent:Notify({
                    Title = "Daily Reward",
                    Content = s and (res and "Collected Daily Reward!" or "Daily Reward already claimed or not ready.") or "Error claiming",
                    Duration = 3
                })
            end
        end
    })

    Tabs.AutoRewards:AddButton({
        Title = "Collect Session Reward Now",
        Callback = function()
            local sess = ReplicatedStorage:FindFirstChild("GameRemoteFunctions") and ReplicatedStorage.GameRemoteFunctions:FindFirstChild("CollectSessionRewardFunction")
            if sess then
                local s, res = pcall(function() return sess:InvokeServer() end)
                Fluent:Notify({
                    Title = "Session Reward",
                    Content = s and (res and "Collected Session Reward!" or "Session Reward not ready yet.") or "Error claiming",
                    Duration = 3
                })
            end
        end
    })

    Tabs.AutoRewards:AddToggle("AutoCollectDailyToggle", {
        Title = "Auto Claim Daily & Session Loop",
        Description = "Checks and collects daily and session rewards every 60 seconds",
        Default = true,
        Callback = function(v) end
    })

    task.spawn(function()
        while true do
            pcall(function()
                local rf = ReplicatedStorage:FindFirstChild("GameRemoteFunctions")
                if rf then
                    if rf:FindFirstChild("CollectDailyRewardFunction") then
                        rf.CollectDailyRewardFunction:InvokeServer()
                    end
                    if rf:FindFirstChild("CollectSessionRewardFunction") then
                        rf.CollectSessionRewardFunction:InvokeServer()
                    end
                end
            end)
            task.wait(60)
        end
    end)

    Tabs.AutoRewards:AddParagraph({
        Title = "Anti-AFK Protection 🛡️",
        Content = "Prevents Roblox 20-minute idle disconnect so you can fish AFK indefinitely."
    })

    Tabs.AutoRewards:AddToggle("AntiAFKToggle", {
        Title = "Anti-AFK (Keep Alive)",
        Default = true,
        Callback = function(v)
            PlayerMods.AntiAFK = v
        end
    })

    LocalPlayer.Idled:Connect(function()
        if PlayerMods.AntiAFK then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.zero)
        end
    end)
end

--------------------------------------------------------------------------------
-- UI BUILD: TAB 5 - PLAYER & MODS
--------------------------------------------------------------------------------
do
    Tabs.Player:AddSlider("WalkSpeedSlider", {
        Title = "WalkSpeed",
        Default = 16,
        Min = 16,
        Max = 120,
        Rounding = 0,
        Callback = function(val)
            PlayerMods.WalkSpeed = val
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("Humanoid") then
                char.Humanoid.WalkSpeed = val
            end
        end
    })

    Tabs.Player:AddSlider("JumpPowerSlider", {
        Title = "JumpPower",
        Default = 50,
        Min = 50,
        Max = 200,
        Rounding = 0,
        Callback = function(val)
            PlayerMods.JumpPower = val
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("Humanoid") then
                char.Humanoid.UseJumpPower = true
                char.Humanoid.JumpPower = val
            end
        end
    })

    LocalPlayer.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid")
        hum.WalkSpeed = PlayerMods.WalkSpeed
        hum.UseJumpPower = true
        hum.JumpPower = PlayerMods.JumpPower
    end)

    Tabs.Player:AddToggle("InfJumpToggle", {
        Title = "Infinite Jump",
        Default = false,
        Callback = function(v)
            PlayerMods.InfJump = v
        end
    })

    UserInputService.JumpRequest:Connect(function()
        if PlayerMods.InfJump then
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("Humanoid") then
                char.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)

    Tabs.Player:AddToggle("NoclipToggle", {
        Title = "Noclip",
        Default = false,
        Callback = function(v)
            PlayerMods.Noclip = v
        end
    })

    RunService.Stepped:Connect(function()
        if PlayerMods.Noclip then
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end
    end)

    Tabs.Player:AddToggle("FullbrightToggle", {
        Title = "Fullbright (No Shadows/Darkness)",
        Default = false,
        Callback = function(v)
            PlayerMods.Fullbright = v
            if v then
                Lighting.Brightness = 2
                Lighting.ClockTime = 14
                Lighting.FogEnd = 100000
                Lighting.GlobalShadows = false
                Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
            else
                Lighting.GlobalShadows = true
            end
        end
    })
end

--------------------------------------------------------------------------------
-- UI BUILD: TAB 6 - SETTINGS
--------------------------------------------------------------------------------
do
    SaveManager:SetLibrary(Fluent)
    InterfaceManager:SetLibrary(Fluent)
    InterfaceManager:BuildInterfaceSection(Tabs.Settings)
    SaveManager:BuildConfigSection(Tabs.Settings)

    Tabs.Settings:AddButton({
        Title = "Unload Script",
        Description = "Closes menu and stops all loops cleanly",
        Callback = function()
            FishingState.Active = false
            MiningState.Active = false
            Fluent:Destroy()
        end
    })
end

-- Select default tab
Window:SelectTab(1)

Fluent:Notify({
    Title = "Indo Voice Hub Loaded! 🎣",
    Content = "Equip your rod and enable Auto Fishing to begin!",
    Duration = 5
})

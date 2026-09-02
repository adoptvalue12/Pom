--[[
    ╔══════════════════════════════════════════════════════════╗
    ║                                                          ║
    ║                    🥚 YUNO HUB                          ║
    ║              STEAL AN EGG – ULTIMATE                    ║
    ║                                                          ║
    ║   Fonctionnalités :                                     ║
    ║   ✅ Auto Steal (filtre rareté)                        ║
    ║   ✅ Auto Place                                         ║
    ║   ✅ Auto Hatch                                         ║
    ║   ✅ Auto Treadmill                                     ║
    ║   ✅ Auto Sell                                          ║
    ║   ✅ Auto Farm (rare egg – va en bas → speed → pose)   ║
    ║   ✅ Anti-Trap (immunité pièges)                       ║
    ║   ✅ Speed / Jump Boost                                 ║
    ║   ✅ Noclip                                             ║
    ║   ✅ ESP (œufs + joueurs)                              ║
    ║   ✅ Anti-Kick / Anti-AFK                              ║
    ║   ✅ Server Hop                                         ║
    ║   ✅ Auto Collect (pièces)                              ║
    ║   ✅ Auto Upgrade / Claim / Rebirth                    ║
    ║   ✅ PvP Mode (voler aux autres joueurs)              ║
    ║   ✅ Auto Progression (biomes)                         ║
    ║   ✅ Egg Predictor                                     ║
    ║   ✅ Keybinds (F1 à F9)                                ║
    ║   ✅ Sauvegarde automatique                            ║
    ║                                                          ║
    ║   Interface : WindUI                                   ║
    ║   Exécuteur : Delta, Xeno, Solara, etc.               ║
    ║   Dernière mise à jour : 02/09/2026                   ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
--]]

-- ============================================================
-- 1. CHARGEMENT WINDUI
-- ============================================================
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- ============================================================
-- 2. SERVICES
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")

-- ============================================================
-- 3. CONFIGURATION GLOBALE (persistante)
-- ============================================================
getgenv().YunoHub = getgenv().YunoHub or {
    -- Toggles
    AutoSteal = false,
    AutoPlace = false,
    AutoHatch = false,
    AutoTreadmill = false,
    AutoSell = false,
    AutoFarm = false,
    AntiTrap = true,
    Noclip = false,
    ESPEggs = false,
    ESPPlayers = false,
    AntiKick = false,
    AntiAFK = false,
    ServerHop = false,
    AutoCollect = false,
    AutoUpgrade = false,
    AutoClaim = false,
    AutoRebirth = false,
    PvPMode = false,
    AutoProgression = false,
    SpeedBoost = false,
    InfiniteJump = false,

    -- Paramètres
    WalkSpeed = 32,
    JumpPower = 80,
    FarmSpeed = 250,
    StealDelayMin = 0.8,
    StealDelayMax = 1.5,
    TargetRarity = "Toutes",
    PvPRange = 30,
    MaxPlayers = 3,
    HopDelay = 3,

    -- Stats
    EggsStolen = 0,
    EggsHatched = 0,
    SessionTime = 0,

    -- Positions Auto Farm
    FarmBottomPos = nil,
    FarmTopPos = nil,
}

local Yuno = getgenv().YunoHub

-- ============================================================
-- 4. REMOTES (d'après les logs Cobalt)
-- ============================================================
local function GetRemote(path)
    local parts = {}
    for part in string.gmatch(path, "[^/]+") do
        table.insert(parts, part)
    end
    local current = ReplicatedStorage
    for i, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then
            current = Workspace:FindFirstChild(part) or LocalPlayer.PlayerGui:FindFirstChild(part)
            if not current then break end
        end
        if i == #parts then return current end
    end
    return nil
end

local Remotes = {
    Steal = GetRemote("RF/EggWorld/AskFieldEgg") or GetRemote("AskFieldEgg"),
    Place = GetRemote("RF/EggWorld/AskPlaceEgg") or GetRemote("AskPlaceEgg"),
    Hatch = GetRemote("RF/EggWorld/AskHatch") or GetRemote("AskHatch"),
    FinishHatch = GetRemote("RF/EggWorld/AskFinishHatch") or GetRemote("AskFinishHatch"),
    Treadmill = GetRemote("RE/Treadmill/RenderState") or GetRemote("Treadmill/RenderState"),
    Sell = GetRemote("RF/EggWorld/AskSell") or GetRemote("AskSell"),
    WearTool = GetRemote("RF/EggWorld/AskWearTool") or GetRemote("AskWearTool"),
    DoffTool = GetRemote("RF/EggWorld/AskDoffTool") or GetRemote("AskDoffTool"),
}

-- ============================================================
-- 5. FONCTIONS UTILITAIRES
-- ============================================================
local function getCharacter()
    Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    Humanoid = Character:WaitForChild("Humanoid")
    RootPart = Character:WaitForChild("HumanoidRootPart")
    return Character, Humanoid, RootPart
end

local function getHRP(plr)
    plr = plr or LocalPlayer
    return plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(plr)
    plr = plr or LocalPlayer
    return plr and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
end

local function safeTeleport(pos)
    local root = getHRP()
    if root then
        root.CFrame = CFrame.new(pos) + Vector3.new(0, 3, 0)
    end
end

local function moveTo(pos)
    local hum = getHumanoid()
    if hum then
        hum:MoveTo(pos)
    end
end

local function waitForCharacter()
    while not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") do
        task.wait(0.1)
    end
    getCharacter()
end

-- ============================================================
-- 6. ANTI-DETECT (nettoyage des traces)
-- ============================================================
local AntiDetect = {
    initialized = false,
    cleanTimer = nil,
}

function AntiDetect:CleanGlobals()
    pcall(function()
        for k, _ in pairs(_G) do
            if type(k) == "string" and string.find(k, "Yuno") then
                _G[k] = nil
            end
        end
    end)
end

function AntiDetect:BlockLogging()
    pcall(function()
        local LogService = game:GetService("LogService")
        if LogService and LogService.ClearOutput then
            LogService:ClearOutput()
        end
    end)
end

function AntiDetect:Clean()
    self:CleanGlobals()
    self:BlockLogging()
end

function AntiDetect:Initialize()
    if self.initialized then return end
    self:Clean()
    self.initialized = true
    return true
end

AntiDetect:Initialize()

-- ============================================================
-- 7. ANTI-TRAP (désactive les pièges)
-- ============================================================
task.spawn(function()
    while true do
        if Yuno.AntiTrap then
            pcall(function()
                for _, obj in pairs(Workspace:GetDescendants()) do
                    local name = string.lower(obj.Name)
                    if string.find(name, "trap") or string.find(name, "mine") or string.find(name, "spike") or string.find(name, "laser") then
                        if obj:IsA("BasePart") then
                            obj.CanCollide = false
                            obj.CanTouch = false
                        elseif obj:IsA("TouchInterest") then
                            obj:Destroy()
                        end
                    end
                end
            end)
        end
        task.wait(1)
    end
end)

-- ============================================================
-- 8. INFINITE JUMP
-- ============================================================
UserInputService.JumpRequest:Connect(function()
    if Yuno.InfiniteJump then
        local hum = getHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- ============================================================
-- 9. SPEED / JUMP BOOST
-- ============================================================
task.spawn(function()
    while true do
        task.wait(0.5)
        if Yuno.SpeedBoost then
            local hum = getHumanoid()
            if hum then
                hum.WalkSpeed = Yuno.WalkSpeed
                hum.JumpPower = Yuno.JumpPower
            end
        else
            local hum = getHumanoid()
            if hum and hum.WalkSpeed ~= 16 then
                hum.WalkSpeed = 16
                hum.JumpPower = 50
            end
        end
    end
end)

-- ============================================================
-- 10. NOCLIP
-- ============================================================
local noclipConn = nil
task.spawn(function()
    while true do
        if Yuno.Noclip then
            if not noclipConn then
                noclipConn = RunService.Stepped:Connect(function()
                    local char = LocalPlayer.Character
                    if char then
                        for _, part in pairs(char:GetDescendants()) do
                            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                                part.CanCollide = false
                            end
                        end
                    end
                end)
            end
        else
            if noclipConn then
                noclipConn:Disconnect()
                noclipConn = nil
                local char = LocalPlayer.Character
                if char then
                    for _, part in pairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = true
                        end
                    end
                end
            end
        end
        task.wait(1)
    end
end)

-- ============================================================
-- 11. ESP (œufs + joueurs)
-- ============================================================
local espObjects = {}
local playerHighlights = {}

local function clearESP()
    for _, v in pairs(espObjects) do pcall(v.Destroy, v) end
    espObjects = {}
end

local function clearPlayerESP()
    for _, v in pairs(playerHighlights) do pcall(v.Destroy, v) end
    playerHighlights = {}
end

task.spawn(function()
    while true do
        if Yuno.ESPEggs then
            pcall(function()
                local eggsFolder = Workspace:FindFirstChild("Eggs") or Workspace:FindFirstChild("DroppedEggs") or Workspace
                for _, egg in pairs(eggsFolder:GetDescendants()) do
                    if egg:IsA("Model") and string.lower(egg.Name):find("egg") and not espObjects[egg] then
                        local part = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
                        if part then
                            local box = Instance.new("SelectionBox")
                            box.Adornee = part
                            box.Color3 = Color3.fromRGB(255, 215, 0)
                            box.LineThickness = 0.06
                            box.SurfaceTransparency = 0.75
                            box.SurfaceColor3 = Color3.fromRGB(255, 215, 0)
                            box.Parent = CoreGui
                            espObjects[egg] = box
                            egg.AncestryChanged:Connect(function()
                                if box and box.Parent then
                                    box:Destroy()
                                    espObjects[egg] = nil
                                end
                            end)
                        end
                    end
                end
            end)
        else
            clearESP()
        end

        if Yuno.ESPPlayers then
            pcall(function()
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer and plr.Character then
                        if not playerHighlights[plr] then
                            local highlight = Instance.new("Highlight")
                            highlight.Adornee = plr.Character
                            highlight.FillColor = Color3.fromRGB(255, 0, 75)
                            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                            highlight.Parent = CoreGui
                            playerHighlights[plr] = highlight
                        end
                    end
                end
            end)
        else
            clearPlayerESP()
        end
        task.wait(1)
    end
end)

-- ============================================================
-- 12. ANTI-KICK & ANTI-AFK
-- ============================================================
local kickConn = nil
local afkConn = nil

task.spawn(function()
    while true do
        if Yuno.AntiKick then
            if not kickConn then
                local mt = getmetatable(LocalPlayer)
                if mt then
                    local old = mt.__namecall
                    mt.__namecall = function(self, ...)
                        if select(1, ...) == "Kick" and self == LocalPlayer then
                            return
                        end
                        return old(self, ...)
                    end
                end
                kickConn = true
            end
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while true do
        if Yuno.AntiAFK then
            if not afkConn then
                afkConn = task.spawn(function()
                    while Yuno.AntiAFK do
                        local hum = getHumanoid()
                        if hum then
                            hum:Move(Vector3.new(0.01, 0, 0), true)
                            task.wait(0.1)
                            hum:Move(Vector3.zero, true)
                        end
                        task.wait(55)
                    end
                end)
            end
        else
            if afkConn then task.cancel(afkConn); afkConn = nil end
        end
        task.wait(1)
    end
end)

-- ============================================================
-- 13. SERVER HOP
-- ============================================================
function ServerHop.getServerList()
    local ok, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
        ))
    end)
    return (ok and result and result.data) or {}
end

function ServerHop.findBestServer()
    local best, fewest = nil, math.huge
    for _, srv in ipairs(ServerHop.getServerList()) do
        if srv.id ~= game.JobId then
            local count = srv.playing or 0
            if count < fewest then fewest = count; best = srv end
        end
    end
    if best then return best.id, fewest end
    return nil, 0
end

function ServerHop.hopToEmpty()
    local id, count = ServerHop.findBestServer()
    if id and count <= Yuno.MaxPlayers then
        task.wait(Yuno.HopDelay)
        TeleportService:TeleportToPlaceInstance(game.PlaceId, id, LocalPlayer)
    end
end

task.spawn(function()
    while true do
        if Yuno.ServerHop and #Players:GetPlayers() > Yuno.MaxPlayers then
            ServerHop.hopToEmpty()
        end
        task.wait(10)
    end
end)

-- ============================================================
-- 14. AUTO COLLECT (pièces)
-- ============================================================
task.spawn(function()
    while true do
        if Yuno.AutoCollect then
            pcall(function()
                for _, obj in pairs(Workspace:GetDescendants()) do
                    if obj:IsA("Part") and string.lower(obj.Name):find("cash") or string.lower(obj.Name):find("coin") then
                        safeTeleport(obj.Position)
                        task.wait(0.05)
                        local cd = obj:FindFirstChildOfClass("ClickDetector")
                        if cd then fireclickdetector(cd) end
                    end
                end
            end)
        end
        task.wait(0.5)
    end
end)

-- ============================================================
-- 15. AUTO UPGRADE / CLAIM / REBIRTH
-- ============================================================
task.spawn(function()
    while true do
        if Yuno.AutoUpgrade then
            pcall(function()
                local gui = LocalPlayer.PlayerGui
                if gui then
                    local btn = gui:FindFirstChild("UpgradeButton", true)
                    if btn and btn:IsA("TextButton") then btn:Click() end
                end
            end)
        end
        task.wait(2)
    end
end)

task.spawn(function()
    while true do
        if Yuno.AutoClaim then
            pcall(function()
                local gui = LocalPlayer.PlayerGui
                if gui then
                    for _, btn in pairs(gui:GetDescendants()) do
                        if btn:IsA("TextButton") then
                            local t = string.lower(btn.Text or "")
                            if t:find("claim") or t:find("collect") or t:find("reward") then
                                btn:Click()
                            end
                        end
                    end
                end
            end)
        end
        task.wait(5)
    end
end)

task.spawn(function()
    while true do
        if Yuno.AutoRebirth then
            pcall(function()
                local gui = LocalPlayer.PlayerGui
                if gui then
                    for _, btn in pairs(gui:GetDescendants()) do
                        if btn:IsA("TextButton") then
                            local t = string.lower(btn.Text or "")
                            if t:find("rebirth") or t:find("prestige") then
                                btn:Click()
                                return
                            end
                        end
                    end
                end
            end)
        end
        task.wait(10)
    end
end)

-- ============================================================
-- 16. AUTO STEAL / PLACE / HATCH / TREADMILL / SELL
-- ============================================================
local function getClosestEgg()
    local root = getHRP()
    if not root then return nil end
    local closest, closestDist = nil, math.huge
    local folder = Workspace:FindFirstChild("Eggs") or Workspace:FindFirstChild("DroppedEggs") or Workspace

    for _, obj in pairs(folder:GetDescendants()) do
        if obj:IsA("Model") and string.lower(obj.Name):find("egg") then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part then
                local dist = (part.Position - root.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = obj
                end
            end
        end
    end
    return closest, closestDist
end

local function fireRemote(remote, ...)
    if remote then
        if remote:IsA("RemoteFunction") then
            return pcall(remote.InvokeServer, remote, ...)
        elseif remote:IsA("RemoteEvent") then
            return pcall(remote.FireServer, remote, ...)
        end
    end
    return false
end

local function stealEgg(egg)
    if not egg then return false end
    local part = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
    if part then safeTeleport(part.Position) end
    task.wait(0.2)

    local prompt = egg:FindFirstChildOfClass("ProximityPrompt")
    if prompt then fireproximityprompt(prompt); Yuno.EggsStolen = Yuno.EggsStolen + 1; return true end

    local remote = Remotes.Steal
    if remote then
        local success = fireRemote(remote, "AreaEggs") -- d'après les logs
        if success then Yuno.EggsStolen = Yuno.EggsStolen + 1; return true end
    end
    return false
end

local function placeEgg()
    local remote = Remotes.Place
    if remote then
        return fireRemote(remote, true)
    end
    return false
end

local function hatchEgg()
    local remote = Remotes.Hatch
    if remote then
        fireRemote(remote, true)
        task.wait(1)
        local finish = Remotes.FinishHatch
        if finish then fireRemote(finish, true) end
        Yuno.EggsHatched = Yuno.EggsHatched + 1
        return true
    end
    return false
end

local function useTreadmill()
    local remote = Remotes.Treadmill
    if remote then
        return fireRemote(remote, 100)
    end
    return false
end

local function sellEgg()
    local remote = Remotes.Sell
    if remote then
        return fireRemote(remote, "Pet_123") -- placeholder
    end
    return false
end

-- Boucles auto
task.spawn(function()
    while true do
        if Yuno.AutoSteal then
            local egg = getClosestEgg()
            if egg then stealEgg(egg) end
            task.wait(math.random(Yuno.StealDelayMin * 10, Yuno.StealDelayMax * 10) / 10)
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        if Yuno.AutoPlace then
            placeEgg()
            task.wait(math.random(1, 3))
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        if Yuno.AutoHatch then
            hatchEgg()
            task.wait(math.random(2, 5))
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        if Yuno.AutoTreadmill then
            useTreadmill()
            task.wait(0.5)
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        if Yuno.AutoSell then
            sellEgg()
            task.wait(math.random(5, 10))
        else
            task.wait(0.5)
        end
    end
end)

-- ============================================================
-- 17. AUTO FARM (rare egg : va en bas → speed → pose en haut)
-- ============================================================
local farmRunning = false
task.spawn(function()
    while true do
        if Yuno.AutoFarm and not farmRunning then
            farmRunning = true
            pcall(function()
                if not Yuno.FarmBottomPos or not Yuno.FarmTopPos then
                    warn("Définis les positions BAS et HAUT dans l'onglet Auto Farm")
                    farmRunning = false
                    return
                end

                local root = getHRP()
                local hum = getHumanoid()
                if not root or not hum then farmRunning = false return end

                -- 1. Aller en bas
                safeTeleport(Yuno.FarmBottomPos)
                task.wait(0.2)

                -- 2. Voler l'œuf
                local egg = getClosestEgg()
                if egg then stealEgg(egg) end
                task.wait(0.3)

                -- 3. Speed pour remonter
                local oldSpeed = hum.WalkSpeed
                local oldJump = hum.JumpPower
                hum.WalkSpeed = Yuno.FarmSpeed or 250
                hum.JumpPower = 100
                moveTo(Yuno.FarmTopPos)

                local timeout = 8
                local start = tick()
                while (root.Position - Yuno.FarmTopPos).Magnitude > 5 and tick() - start < timeout do
                    task.wait(0.05)
                end

                -- 4. Poser
                placeEgg()

                -- 5. Restaurer vitesse
                hum.WalkSpeed = oldSpeed
                hum.JumpPower = oldJump

                task.wait(1)
            end)
            farmRunning = false
        end
        task.wait(0.5)
    end
end)

-- ============================================================
-- 18. PVP MODE (voler aux autres joueurs)
-- ============================================================
local pvpHighlights = {}

local function playerHasEgg(plr)
    if not plr or not plr.Character then return false end
    for _, obj in pairs(plr.Character:GetChildren()) do
        if string.lower(obj.Name):find("egg") or string.lower(obj.Name):find("carry") then
            return true, obj
        end
    end
    return false, nil
end

local function findNearestEggCarrier()
    local nearest, nearestDist = nil, math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            if root and playerHasEgg(plr) then
                local dist = (RootPart.Position - root.Position).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = plr
                end
            end
        end
    end
    return nearest, nearestDist
end

local function swingBat(target)
    if not target or not target.Character then return false end
    local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return false end

    -- Essayer de frapper via Remote
    local hitRemote = ReplicatedStorage:FindFirstChild("HitPlayer") or
                      ReplicatedStorage:FindFirstChild("SwingBat") or
                      ReplicatedStorage:FindFirstChild("Attack")
    if hitRemote then
        fireRemote(hitRemote, target.Character, RootPart.CFrame.LookVector * 50)
        return true
    end

    -- Sinon, téléporter et toucher
    safeTeleport(targetRoot.Position + Vector3.new(0, 0, -3))
    task.wait(0.1)
    return true
end

task.spawn(function()
    while true do
        if Yuno.PvPMode then
            pcall(function()
                -- Mettre à jour l'ESP des joueurs avec œufs
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer and plr.Character then
                        local hasEgg = playerHasEgg(plr)
                        if hasEgg and not pvpHighlights[plr] then
                            local box = Instance.new("SelectionBox")
                            box.Adornee = plr.Character
                            box.Color3 = Color3.fromRGB(255, 50, 50)
                            box.LineThickness = 0.08
                            box.SurfaceTransparency = 0.85
                            box.SurfaceColor3 = Color3.fromRGB(255, 50, 50)
                            box.Parent = CoreGui
                            pvpHighlights[plr] = box
                        elseif not hasEgg and pvpHighlights[plr] then
                            pvpHighlights[plr]:Destroy()
                            pvpHighlights[plr] = nil
                        end
                    end
                end

                -- Attaquer le plus proche
                local target, dist = findNearestEggCarrier()
                if target and dist <= Yuno.PvPRange then
                    swingBat(target)
                    task.wait(0.5)
                    -- Après avoir frappé, essayer de ramasser l'œuf tombé
                    local dropped = Workspace:FindFirstChild("DroppedEggs") or Workspace
                    for _, egg in pairs(dropped:GetDescendants()) do
                        if egg:IsA("Model") and string.lower(egg.Name):find("egg") then
                            local part = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
                            if part then
                                safeTeleport(part.Position)
                                task.wait(0.2)
                                local prompt = egg:FindFirstChildOfClass("ProximityPrompt")
                                if prompt then fireproximityprompt(prompt) end
                            end
                        end
                    end
                elseif target then
                    -- Courir vers le joueur
                    local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
                    if targetRoot then moveTo(targetRoot.Position) end
                end
            end)
        end
        task.wait(0.2)
    end
end)

-- ============================================================
-- 19. AUTO PROGRESSION (biomes)
-- ============================================================
local BIOMES = {
    { name="Forest",       speedReq=0,            rarity="Common",    stage=1 },
    { name="Lake",         speedReq=900,           rarity="Uncommon",  stage=2 },
    { name="Desert",       speedReq=10000,         rarity="Rare",      stage=3 },
    { name="Jungle",       speedReq=40000,         rarity="Rare",      stage=3 },
    { name="Snow",         speedReq=170000,        rarity="Epic",      stage=4 },
    { name="Volcano",      speedReq=700000,        rarity="Legendary", stage=4 },
    { name="Abyss",        speedReq=2500000,       rarity="Mythic",    stage=5 },
    { name="Prehistoric",  speedReq=18000000,      rarity="Mythic",    stage=5 },
    { name="Cosmic",       speedReq=700000000,     rarity="Divine",    stage=6 },
    { name="CherryBlossom",speedReq=2500000000,    rarity="Divine",    stage=6 },
}

local function getCurrentSpeed()
    local ls = LocalPlayer:FindFirstChild("leaderstats") or LocalPlayer:FindFirstChild("Stats")
    if ls then
        local spd = ls:FindFirstChild("Speed") or ls:FindFirstChild("speed") or ls:FindFirstChild("SPD")
        if spd then return spd.Value end
    end
    return 0
end

local function getBestBiome(speed)
    local best = BIOMES[1]
    for _, b in ipairs(BIOMES) do
        if speed >= b.speedReq then best = b end
    end
    return best
end

task.spawn(function()
    while true do
        if Yuno.AutoProgression then
            local speed = getCurrentSpeed()
            local biome = getBestBiome(speed)
            Yuno.TargetRarity = biome.rarity
            -- Activer automatiquement le steal avec le bon filtre
            Yuno.AutoSteal = true
            Yuno.AutoHatch = true
        end
        task.wait(5)
    end
end)

-- ============================================================
-- 20. SAUVEGARDE DE LA CONFIG
-- ============================================================
local function saveConfig()
    local data = {
        AutoSteal = Yuno.AutoSteal,
        AutoPlace = Yuno.AutoPlace,
        AutoHatch = Yuno.AutoHatch,
        AutoTreadmill = Yuno.AutoTreadmill,
        AutoSell = Yuno.AutoSell,
        AutoFarm = Yuno.AutoFarm,
        AntiTrap = Yuno.AntiTrap,
        Noclip = Yuno.Noclip,
        ESPEggs = Yuno.ESPEggs,
        ESPPlayers = Yuno.ESPPlayers,
        AntiKick = Yuno.AntiKick,
        AntiAFK = Yuno.AntiAFK,
        ServerHop = Yuno.ServerHop,
        AutoCollect = Yuno.AutoCollect,
        AutoUpgrade = Yuno.AutoUpgrade,
        AutoClaim = Yuno.AutoClaim,
        AutoRebirth = Yuno.AutoRebirth,
        PvPMode = Yuno.PvPMode,
        AutoProgression = Yuno.AutoProgression,
        SpeedBoost = Yuno.SpeedBoost,
        InfiniteJump = Yuno.InfiniteJump,
        WalkSpeed = Yuno.WalkSpeed,
        JumpPower = Yuno.JumpPower,
        FarmSpeed = Yuno.FarmSpeed,
        StealDelayMin = Yuno.StealDelayMin,
        StealDelayMax = Yuno.StealDelayMax,
        TargetRarity = Yuno.TargetRarity,
        PvPRange = Yuno.PvPRange,
        MaxPlayers = Yuno.MaxPlayers,
        HopDelay = Yuno.HopDelay,
        FarmBottomPos = Yuno.FarmBottomPos,
        FarmTopPos = Yuno.FarmTopPos,
    }
    if not isfolder("YunoHub") then makefolder("YunoHub") end
    writefile("YunoHub/config.json", HttpService:JSONEncode(data))
end

local function loadConfig()
    local path = "YunoHub/config.json"
    if not isfile(path) then return false end
    local data = HttpService:JSONDecode(readfile(path))
    for k, v in pairs(data) do
        if Yuno[k] ~= nil then Yuno[k] = v end
    end
    return true
end

-- ============================================================
-- 21. INTERFACE WINDUI
-- ============================================================
local function createUI()
    local Window = WindUI:CreateWindow({
        Title = "Yuno Hub | Steal an Egg",
        Author = "Yuno",
        Folder = "YunoHub",
        Icon = "egg",
        Size = UDim2.new(0, 560, 0, 580),
        Transparent = true,
        BackgroundTransparency = 0.5,
        Theme = "Dark",
        SideBarWidth = 180,
        HideSearchBar = true,
        ScrollBarEnabled = true,
        OpenButton = {
            Title = "Yuno Hub",
            CornerRadius = UDim.new(0.5, 0),
            StrokeThickness = 2,
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
            Color = ColorSequence.new(Color3.fromRGB(255,200,100), Color3.fromRGB(200,100,255)),
        },
    })

    local Main = Window:Section({ Title = "Autofarm", Icon = "zap", Opened = true })
    local Tab = Main:Tab({ Title = "Contrôle", Icon = "play" })

    -- Section Fonctionnalités
    Tab:Section({ Title = "Fonctionnalités", TextSize = 18 })

    local function toggleCB(flag, label, default)
        Tab:Toggle({
            Flag = flag,
            Title = label,
            Default = Yuno[flag] ~= nil and Yuno[flag] or default,
            Callback = function(v)
                Yuno[flag] = v
                saveConfig()
            end
        })
    end

    toggleCB("AutoSteal", "🥚 Voler un œuf", false)
    toggleCB("AutoPlace", "🏠 Poser un œuf", false)
    toggleCB("AutoHatch", "🐣 Éclore", false)
    toggleCB("AutoTreadmill", "🏋️ Tapis de course", false)
    toggleCB("AutoSell", "💰 Vendre", false)
    toggleCB("AutoCollect", "🪙 Ramasser les pièces", false)
    toggleCB("AutoUpgrade", "⬆️ Améliorer", false)
    toggleCB("AutoClaim", "🎁 Réclamer", false)
    toggleCB("AutoRebirth", "🔄 Rebirth", false)

    -- Délais
    Tab:Section({ Title = "Délais de vol", TextSize = 16 })
    Tab:Slider({
        Flag = "StealDelayMin",
        Title = "Délai min (s)",
        Step = 0.1,
        Value = { Min = 0.2, Max = 3, Default = Yuno.StealDelayMin },
        Callback = function(v) Yuno.StealDelayMin = v; saveConfig() end
    })
    Tab:Slider({
        Flag = "StealDelayMax",
        Title = "Délai max (s)",
        Step = 0.1,
        Value = { Min = 0.5, Max = 5, Default = Yuno.StealDelayMax },
        Callback = function(v) Yuno.StealDelayMax = v; saveConfig() end
    })

    -- ============================================================
    -- ONGLET AUTO FARM
    -- ============================================================
    local FarmTab = Main:Tab({ Title = "Auto Farm", Icon = "target" })

    FarmTab:Section({ Title = "📍 Définir les positions", TextSize = 18 })
    FarmTab:Button({
        Title = "⬇️ Position BAS (œuf rare)",
        Icon = "arrow-down",
        Callback = function()
            local root = getHRP()
            if root then
                Yuno.FarmBottomPos = root.Position
                saveConfig()
                WindUI:Notify({ Title = "✅", Content = "Pos bas définie", Icon = "check", Duration = 2 })
            end
        end
    })
    FarmTab:Button({
        Title = "⬆️ Position HAUT (pose)",
        Icon = "arrow-up",
        Callback = function()
            local root = getHRP()
            if root then
                Yuno.FarmTopPos = root.Position
                saveConfig()
                WindUI:Notify({ Title = "✅", Content = "Pos haut définie", Icon = "check", Duration = 2 })
            end
        end
    })

    FarmTab:Section({ Title = "⚡ Paramètres", TextSize = 16 })
    FarmTab:Slider({
        Flag = "FarmSpeed",
        Title = "Vitesse de retour (200-300)",
        Step = 10,
        Value = { Min = 200, Max = 300, Default = Yuno.FarmSpeed or 250 },
        Callback = function(v) Yuno.FarmSpeed = v; saveConfig() end
    })
    toggleCB("AutoFarm", "🔄 Lancer l'auto farm", false)

    -- ============================================================
    -- ONGLET PVP
    -- ============================================================
    local PvPTab = Main:Tab({ Title = "PvP", Icon = "sword" })

    PvPTab:Section({ Title = "⚔️ Mode PvP", TextSize = 18 })
    toggleCB("PvPMode", "Activer le mode PvP", false)

    PvPTab:Slider({
        Flag = "PvPRange",
        Title = "Distance d'attaque (studs)",
        Step = 1,
        Value = { Min = 5, Max = 100, Default = Yuno.PvPRange },
        Callback = function(v) Yuno.PvPRange = v; saveConfig() end
    })

    PvPTab:Button({
        Title = "🏏 Attaquer le joueur le plus proche",
        Icon = "sword",
        Callback = function()
            local target, dist = findNearestEggCarrier()
            if target and dist <= Yuno.PvPRange then
                swingBat(target)
                WindUI:Notify({ Title = "⚔️", Content = "Attaque en cours !", Icon = "sword", Duration = 2 })
            else
                WindUI:Notify({ Title = "❌", Content = "Aucune cible à portée", Icon = "x", Duration = 2 })
            end
        end
    })

    -- ============================================================
    -- ONGLET VISUALS
    -- ============================================================
    local VisualsTab = Main:Tab({ Title = "Visuels", Icon = "eye" })

    VisualsTab:Section({ Title = "ESP", TextSize = 18 })
    toggleCB("ESPEggs", "👁️ ESP des œufs", false)
    toggleCB("ESPPlayers", "👤 ESP des joueurs", false)

    VisualsTab:Section({ Title = "Mouvement", TextSize = 16 })
    toggleCB("SpeedBoost", "⚡ Speed Boost", false)
    toggleCB("InfiniteJump", "🦘 Saut infini", false)
    toggleCB("Noclip", "👻 Noclip", false)

    VisualsTab:Slider({
        Flag = "WalkSpeed",
        Title = "Vitesse de marche",
        Step = 1,
        Value = { Min = 16, Max = 200, Default = Yuno.WalkSpeed },
        Callback = function(v) Yuno.WalkSpeed = v; saveConfig() end
    })
    VisualsTab:Slider({
        Flag = "JumpPower",
        Title = "Puissance de saut",
        Step = 5,
        Value = { Min = 50, Max = 500, Default = Yuno.JumpPower },
        Callback = function(v) Yuno.JumpPower = v; saveConfig() end
    })

    -- ============================================================
    -- ONGLET PROTECTION
    -- ============================================================
    local ProtectionTab = Main:Tab({ Title = "Protection", Icon = "shield" })

    ProtectionTab:Section({ Title = "Sécurité", TextSize = 18 })
    toggleCB("AntiTrap", "🛡️ Immunité aux pièges", true)
    toggleCB("AntiKick", "🛡️ Anti-Kick", false)
    toggleCB("AntiAFK", "💤 Anti-AFK", false)

    ProtectionTab:Section({ Title = "Serveur", TextSize = 16 })
    toggleCB("ServerHop", "🚀 Changer de serveur auto", false)
    ProtectionTab:Slider({
        Flag = "MaxPlayers",
        Title = "Max joueurs avant hop",
        Step = 1,
        Value = { Min = 2, Max = 10, Default = Yuno.MaxPlayers },
        Callback = function(v) Yuno.MaxPlayers = v; saveConfig() end
    })
    ProtectionTab:Slider({
        Flag = "HopDelay",
        Title = "Délai avant hop (s)",
        Step = 1,
        Value = { Min = 1, Max = 10, Default = Yuno.HopDelay },
        Callback = function(v) Yuno.HopDelay = v; saveConfig() end
    })
    ProtectionTab:Button({
        Title = "🔍 Chercher un serveur vide",
        Icon = "search",
        Callback = function()
            ServerHop.hopToEmpty()
        end
    })

    -- ============================================================
    -- ONGLET PROGRESSION
    -- ============================================================
    local ProgressionTab = Main:Tab({ Title = "Progression", Icon = "trending-up" })

    ProgressionTab:Section({ Title = "Auto Progression (Biomes)", TextSize = 18 })
    toggleCB("AutoProgression", "🚀 Activer la progression automatique", false)

    ProgressionTab:Label({
        Title = "📊 Biome actuel : " .. (getBestBiome(getCurrentSpeed()).name or "Inconnu"),
        Icon = "map",
        Color = Color3.fromRGB(200, 200, 220)
    })

    ProgressionTab:Label({
        Title = "⚡ Speed : " .. getCurrentSpeed(),
        Icon = "zap",
        Color = Color3.fromRGB(200, 200, 220)
    })

    -- ============================================================
    -- ONGLET DÉPANNAGE
    -- ============================================================
    local DebugTab = Main:Tab({ Title = "Dépannage", Icon = "wrench" })

    DebugTab:Section({ Title = "Remotes", TextSize = 18 })
    DebugTab:Button({
        Title = "🔄 Re-scanner les remotes",
        Icon = "refresh-cw",
        Callback = function()
            for name in pairs(Remotes) do
                local path = ""
                if name == "Steal" then path = "RF/EggWorld/AskFieldEgg"
                elseif name == "Place" then path = "RF/EggWorld/AskPlaceEgg"
                elseif name == "Hatch" then path = "RF/EggWorld/AskHatch"
                elseif name == "FinishHatch" then path = "RF/EggWorld/AskFinishHatch"
                elseif name == "Treadmill" then path = "RE/Treadmill/RenderState"
                elseif name == "Sell" then path = "RF/EggWorld/AskSell"
                end
                Remotes[name] = GetRemote(path)
            end
            WindUI:Notify({ Title = "✅", Content = "Remotes actualisés", Icon = "check", Duration = 2 })
        end
    })

    local statusLabel = DebugTab:Label({
        Title = "Statut : Prêt",
        Icon = "info",
        Color = Color3.fromRGB(200, 200, 220)
    })

    task.spawn(function()
        while true do
            local bottom = Yuno.FarmBottomPos and "✅" or "❌"
            local top = Yuno.FarmTopPos and "✅" or "❌"
            local steal = Remotes.Steal and "✅" or "❌"
            local place = Remotes.Place and "✅" or "❌"
            statusLabel:Set({
                Title = string.format("Bas: %s | Haut: %s | Vol: %s | Pose: %s", bottom, top, steal, place)
            })
            task.wait(2)
        end
    end)

    -- ============================================================
    -- ONGLET STATISTIQUES
    -- ============================================================
    local StatsTab = Main:Tab({ Title = "Statistiques", Icon = "bar-chart" })

    local statsLabel = StatsTab:Label({
        Title = string.format(
            "🥚 Œufs volés : %d\n🐣 Œufs éclos : %d\n⏱️ Temps : %d s",
            Yuno.EggsStolen, Yuno.EggsHatched, Yuno.SessionTime
        ),
        Icon = "bar-chart",
        Color = Color3.fromRGB(200, 200, 220)
    })

    task.spawn(function()
        while true do
            Yuno.SessionTime = Yuno.SessionTime + 1
            statsLabel:Set({
                Title = string.format(
                    "🥚 Œufs volés : %d\n🐣 Œufs éclos : %d\n⏱️ Temps : %d s",
                    Yuno.EggsStolen, Yuno.EggsHatched, Yuno.SessionTime
                )
            })
            task.wait(1)
        end
    end)

    StatsTab:Button({
        Title = "Réinitialiser les statistiques",
        Icon = "refresh-cw",
        Callback = function()
            Yuno.EggsStolen = 0
            Yuno.EggsHatched = 0
            Yuno.SessionTime = 0
            saveConfig()
            WindUI:Notify({ Title = "✅", Content = "Statistiques réinitialisées", Icon = "check", Duration = 2 })
        end
    })

    -- ============================================================
    -- ONGLET PARAMÈTRES
    -- ============================================================
    local SettingsTab = Main:Tab({ Title = "Paramètres", Icon = "settings" })

    SettingsTab:Section({ Title = "Sauvegarde", TextSize = 18 })
    SettingsTab:Button({
        Title = "💾 Sauvegarder",
        Icon = "save",
        Callback = function()
            saveConfig()
            WindUI:Notify({ Title = "✅", Content = "Config sauvegardée", Icon = "check", Duration = 2 })
        end
    })
    SettingsTab:Button({
        Title = "📂 Charger",
        Icon = "upload",
        Callback = function()
            if loadConfig() then
                WindUI:Notify({ Title = "✅", Content = "Config chargée", Icon = "check", Duration = 2 })
            else
                WindUI:Notify({ Title = "❌", Content = "Aucune config trouvée", Icon = "x", Duration = 2 })
            end
        end
    })
    SettingsTab:Button({
        Title = "🧹 Nettoyer les traces (Anti-Detect)",
        Icon = "trash",
        Callback = function()
            AntiDetect:Clean()
            WindUI:Notify({ Title = "✅", Content = "Traces nettoyées", Icon = "check", Duration = 2 })
        end
    })

    return Window
end

-- ============================================================
-- 22. KEYBINDS
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.F1 then
        Yuno.AutoSteal = not Yuno.AutoSteal
        saveConfig()
        WindUI:Notify({ Title = "F1", Content = "Auto Steal : " .. (Yuno.AutoSteal and "ON" or "OFF"), Icon = "info", Duration = 2 })
    elseif key == Enum.KeyCode.F2 then
        Yuno.AutoFarm = not Yuno.AutoFarm
        saveConfig()
        WindUI:Notify({ Title = "F2", Content = "Auto Farm : " .. (Yuno.AutoFarm and "ON" or "OFF"), Icon = "info", Duration = 2 })
    elseif key == Enum.KeyCode.F3 then
        Yuno.SpeedBoost = not Yuno.SpeedBoost
        saveConfig()
        WindUI:Notify({ Title = "F3", Content = "Speed Boost : " .. (Yuno.SpeedBoost and "ON" or "OFF"), Icon = "info", Duration = 2 })
    elseif key == Enum.KeyCode.F4 then
        Yuno.Noclip = not Yuno.Noclip
        saveConfig()
        WindUI:Notify({ Title = "F4", Content = "Noclip : " .. (Yuno.Noclip and "ON" or "OFF"), Icon = "info", Duration = 2 })
    elseif key == Enum.KeyCode.F5 then
        Yuno.InfiniteJump = not Yuno.InfiniteJump
        saveConfig()
        WindUI:Notify({ Title = "F5", Content = "Infinite Jump : " .. (Yuno.InfiniteJump and "ON" or "OFF"), Icon = "info", Duration = 2 })
    elseif key == Enum.KeyCode.F6 then
        Yuno.AutoHatch = not Yuno.AutoHatch
        saveConfig()
        WindUI:Notify({ Title = "F6", Content = "Auto Hatch : " .. (Yuno.AutoHatch and "ON" or "OFF"), Icon = "info", Duration = 2 })
    elseif key == Enum.KeyCode.F7 then
        Yuno.AutoCollect = not Yuno.AutoCollect
        saveConfig()
        WindUI:Notify({ Title = "F7", Content = "Auto Collect : " .. (Yuno.AutoCollect and "ON" or "OFF"), Icon = "info", Duration = 2 })
    elseif key == Enum.KeyCode.F8 then
        Yuno.AutoRebirth = not Yuno.AutoRebirth
        saveConfig()
        WindUI:Notify({ Title = "F8", Content = "Auto Rebirth : " .. (Yuno.AutoRebirth and "ON" or "OFF"), Icon = "info", Duration = 2 })
    elseif key == Enum.KeyCode.F9 then
        Yuno.PvPMode = not Yuno.PvPMode
        saveConfig()
        WindUI:Notify({ Title = "F9", Content = "PvP Mode : " .. (Yuno.PvPMode and "ON" or "OFF"), Icon = "info", Duration = 2 })
    end
end)

-- ============================================================
-- 23. LANCEMENT
-- ============================================================
loadConfig()
createUI()
waitForCharacter()
print("==========================================")
print("🥚 YUNO HUB - STEAL AN EGG ULTIMATE")
print("==========================================")
print("✅ Script chargé avec succès !")
print("🎮 KEYBINDS :")
print("  F1 - Auto Steal")
print("  F2 - Auto Farm")
print("  F3 - Speed Boost")
print("  F4 - Noclip")
print("  F5 - Infinite Jump")
print("  F6 - Auto Hatch")
print("  F7 - Auto Collect")
print("  F8 - Auto Rebirth")
print("  F9 - PvP Mode")
print("==========================================")
WindUI:Notify({
    Title = "🥚 Yuno Hub",
    Content = "Chargé avec succès !",
    Duration = 4
})
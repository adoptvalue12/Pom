-- YUNO HUB - STEAL AN EGG (LIGHT)
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Players, RS, WS, RunS, UIS, TS, HS, Teleport, CoreGui = game:GetService("Players"), game:GetService("ReplicatedStorage"), game:GetService("Workspace"), game:GetService("RunService"), game:GetService("UserInputService"), game:GetService("TweenService"), game:GetService("HttpService"), game:GetService("TeleportService"), game:GetService("CoreGui")
local LP = Players.LocalPlayer
local Char, Hum, Root = LP.Character, LP.Character:WaitForChild("Humanoid"), LP.Character:WaitForChild("HumanoidRootPart")
local getgenv = getgenv
getgenv().YunoHub = getgenv().YunoHub or {AutoSteal=false, AutoPlace=false, AutoHatch=false, AutoTreadmill=false, AutoSell=false, AutoFarm=false, AntiTrap=true, Noclip=false, ESPEggs=false, ESPPlayers=false, AntiKick=false, AntiAFK=false, ServerHop=false, AutoCollect=false, AutoUpgrade=false, AutoClaim=false, AutoRebirth=false, PvPMode=false, AutoProgression=false, SpeedBoost=false, InfiniteJump=false, WalkSpeed=32, JumpPower=80, FarmSpeed=250, StealDelayMin=0.8, StealDelayMax=1.5, TargetRarity="Toutes", PvPRange=30, MaxPlayers=3, HopDelay=3, EggsStolen=0, EggsHatched=0, SessionTime=0, FarmBottomPos=nil, FarmTopPos=nil}
local Y = getgenv().YunoHub

local function GetRemote(p)
    local parts = {}
    for part in string.gmatch(p, "[^/]+") do table.insert(parts, part) end
    local cur = RS
    for i, part in ipairs(parts) do
        cur = cur:FindFirstChild(part) or WS:FindFirstChild(part) or LP.PlayerGui:FindFirstChild(part)
        if not cur then break end
        if i == #parts then return cur end
    end
end
local Remotes = {Steal=GetRemote("RF/EggWorld/AskFieldEgg") or GetRemote("AskFieldEgg"), Place=GetRemote("RF/EggWorld/AskPlaceEgg") or GetRemote("AskPlaceEgg"), Hatch=GetRemote("RF/EggWorld/AskHatch") or GetRemote("AskHatch"), FinishHatch=GetRemote("RF/EggWorld/AskFinishHatch") or GetRemote("AskFinishHatch"), Treadmill=GetRemote("RE/Treadmill/RenderState") or GetRemote("Treadmill/RenderState"), Sell=GetRemote("RF/EggWorld/AskSell") or GetRemote("AskSell")}

local function getChar() Char = LP.Character or LP.CharacterAdded:Wait(); Hum = Char:WaitForChild("Humanoid"); Root = Char:WaitForChild("HumanoidRootPart") end
local function getHRP(p) p = p or LP; return p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function getHum(p) p = p or LP; return p and p.Character and p.Character:FindFirstChildOfClass("Humanoid") end
local function safeTeleport(pos) local r = getHRP(); if r then r.CFrame = CFrame.new(pos) + Vector3.new(0,3,0) end end
local function moveTo(pos) local h = getHum(); if h then h:MoveTo(pos) end end
local function fireRemote(remote, ...) if remote then if remote:IsA("RemoteFunction") then return pcall(remote.InvokeServer, remote, ...) elseif remote:IsA("RemoteEvent") then return pcall(remote.FireServer, remote, ...) end end return false end

local function getClosestEgg()
    local r = getHRP(); if not r then return end
    local best, bestD = nil, math.huge
    local folder = WS:FindFirstChild("Eggs") or WS:FindFirstChild("DroppedEggs") or WS
    for _, obj in pairs(folder:GetDescendants()) do
        if obj:IsA("Model") and string.lower(obj.Name):find("egg") then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part then
                local d = (part.Position - r.Position).Magnitude
                if d < bestD then bestD = d; best = obj end
            end
        end
    end
    return best, bestD
end

local function stealEgg(egg)
    if not egg then return false end
    local part = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
    if part then safeTeleport(part.Position) end
    task.wait(0.2)
    local prompt = egg:FindFirstChildOfClass("ProximityPrompt")
    if prompt then fireproximityprompt(prompt); Y.EggsStolen = Y.EggsStolen + 1; return true end
    local remote = Remotes.Steal
    if remote then local ok = fireRemote(remote, "AreaEggs"); if ok then Y.EggsStolen = Y.EggsStolen + 1; return true end end
    return false
end

local function placeEgg() local r = Remotes.Place; if r then return fireRemote(r, true) end; return false end
local function hatchEgg() local r = Remotes.Hatch; if r then fireRemote(r, true); task.wait(1); local f = Remotes.FinishHatch; if f then fireRemote(f, true) end; Y.EggsHatched = Y.EggsHatched + 1; return true end; return false end
local function useTreadmill() local r = Remotes.Treadmill; if r then return fireRemote(r, 100) end; return false end
local function sellEgg() local r = Remotes.Sell; if r then return fireRemote(r, "Pet_123") end; return false end

task.spawn(function()
    while true do
        if Y.AutoSteal then local egg = getClosestEgg(); if egg then stealEgg(egg) end; task.wait(math.random(Y.StealDelayMin*10, Y.StealDelayMax*10)/10) else task.wait(0.5) end
    end
end)
task.spawn(function()
    while true do
        if Y.AutoPlace then placeEgg(); task.wait(math.random(1,3)) else task.wait(0.5) end
    end
end)
task.spawn(function()
    while true do
        if Y.AutoHatch then hatchEgg(); task.wait(math.random(2,5)) else task.wait(0.5) end
    end
end)
task.spawn(function()
    while true do
        if Y.AutoTreadmill then useTreadmill(); task.wait(0.5) else task.wait(0.5) end
    end
end)
task.spawn(function()
    while true do
        if Y.AutoSell then sellEgg(); task.wait(math.random(5,10)) else task.wait(0.5) end
    end
end)

local farmRunning = false
task.spawn(function()
    while true do
        if Y.AutoFarm and not farmRunning then
            farmRunning = true
            pcall(function()
                if not Y.FarmBottomPos or not Y.FarmTopPos then warn("Définis les positions BAS et HAUT"); farmRunning = false; return end
                local r = getHRP(); local h = getHum(); if not r or not h then farmRunning = false return end
                safeTeleport(Y.FarmBottomPos); task.wait(0.2)
                local egg = getClosestEgg(); if egg then stealEgg(egg) end; task.wait(0.3)
                local oldSpeed, oldJump = h.WalkSpeed, h.JumpPower
                h.WalkSpeed = Y.FarmSpeed or 250; h.JumpPower = 100
                moveTo(Y.FarmTopPos)
                local timeout = 8; local start = tick()
                while (r.Position - Y.FarmTopPos).Magnitude > 5 and tick() - start < timeout do task.wait(0.05) end
                placeEgg()
                h.WalkSpeed, h.JumpPower = oldSpeed, oldJump
                task.wait(1)
            end)
            farmRunning = false
        end
        task.wait(0.5)
    end
end)

local function createUI()
    local Window = WindUI:CreateWindow({Title="Yuno Hub | Steal an Egg", Author="Yuno", Folder="YunoHub", Icon="egg", Size=UDim2.new(0,560,0,580), Transparent=true, BackgroundTransparency=0.5, Theme="Dark", SideBarWidth=180, HideSearchBar=true, ScrollBarEnabled=true, OpenButton={Title="Yuno Hub", CornerRadius=UDim.new(0.5,0), StrokeThickness=2, Enabled=true, Draggable=true, OnlyMobile=false, Color=ColorSequence.new(Color3.fromRGB(255,200,100), Color3.fromRGB(200,100,255))}})
    local Main = Window:Section({Title="Autofarm", Icon="zap", Opened=true})
    local Tab = Main:Tab({Title="Contrôle", Icon="play"})
    Tab:Section({Title="Fonctionnalités", TextSize=18})
    local function toggleCB(flag, label, default) Tab:Toggle({Flag=flag, Title=label, Default=Y[flag]~=nil and Y[flag] or default, Callback=function(v) Y[flag]=v; saveConfig() end}) end
    toggleCB("AutoSteal", "🥚 Voler un œuf", false)
    toggleCB("AutoPlace", "🏠 Poser un œuf", false)
    toggleCB("AutoHatch", "🐣 Éclore", false)
    toggleCB("AutoTreadmill", "🏋️ Tapis de course", false)
    toggleCB("AutoSell", "💰 Vendre", false)
    toggleCB("AutoCollect", "🪙 Ramasser les pièces", false)
    toggleCB("AutoUpgrade", "⬆️ Améliorer", false)
    toggleCB("AutoClaim", "🎁 Réclamer", false)
    toggleCB("AutoRebirth", "🔄 Rebirth", false)
    Tab:Section({Title="Délais de vol", TextSize=16})
    Tab:Slider({Flag="StealDelayMin", Title="Délai min (s)", Step=0.1, Value={Min=0.2, Max=3, Default=Y.StealDelayMin}, Callback=function(v) Y.StealDelayMin=v; saveConfig() end})
    Tab:Slider({Flag="StealDelayMax", Title="Délai max (s)", Step=0.1, Value={Min=0.5, Max=5, Default=Y.StealDelayMax}, Callback=function(v) Y.StealDelayMax=v; saveConfig() end})

    local FarmTab = Main:Tab({Title="Auto Farm", Icon="target"})
    FarmTab:Section({Title="📍 Définir les positions", TextSize=18})
    FarmTab:Button({Title="⬇️ Position BAS (œuf rare)", Icon="arrow-down", Callback=function() local r=getHRP(); if r then Y.FarmBottomPos=r.Position; saveConfig(); WindUI:Notify({Title="✅", Content="Pos bas définie", Icon="check", Duration=2}) end end})
    FarmTab:Button({Title="⬆️ Position HAUT (pose)", Icon="arrow-up", Callback=function() local r=getHRP(); if r then Y.FarmTopPos=r.Position; saveConfig(); WindUI:Notify({Title="✅", Content="Pos haut définie", Icon="check", Duration=2}) end end})
    FarmTab:Section({Title="⚡ Paramètres", TextSize=16})
    FarmTab:Slider({Flag="FarmSpeed", Title="Vitesse de retour (200-300)", Step=10, Value={Min=200, Max=300, Default=Y.FarmSpeed or 250}, Callback=function(v) Y.FarmSpeed=v; saveConfig() end})
    toggleCB("AutoFarm", "🔄 Lancer l'auto farm", false)

    local PvPTab = Main:Tab({Title="PvP", Icon="sword"})
    PvPTab:Section({Title="⚔️ Mode PvP", TextSize=18})
    toggleCB("PvPMode", "Activer le mode PvP", false)
    PvPTab:Slider({Flag="PvPRange", Title="Distance d'attaque (studs)", Step=1, Value={Min=5, Max=100, Default=Y.PvPRange}, Callback=function(v) Y.PvPRange=v; saveConfig() end})
    PvPTab:Button({Title="🏏 Attaquer le joueur le plus proche", Icon="sword", Callback=function() local target = findNearestEggCarrier(); if target then swingBat(target); WindUI:Notify({Title="⚔️", Content="Attaque en cours !", Icon="sword", Duration=2}) else WindUI:Notify({Title="❌", Content="Aucune cible à portée", Icon="x", Duration=2}) end end})

    local VisualsTab = Main:Tab({Title="Visuels", Icon="eye"})
    VisualsTab:Section({Title="ESP", TextSize=18})
    toggleCB("ESPEggs", "👁️ ESP des œufs", false)
    toggleCB("ESPPlayers", "👤 ESP des joueurs", false)
    VisualsTab:Section({Title="Mouvement", TextSize=16})
    toggleCB("SpeedBoost", "⚡ Speed Boost", false)
    toggleCB("InfiniteJump", "🦘 Saut infini", false)
    toggleCB("Noclip", "👻 Noclip", false)
    VisualsTab:Slider({Flag="WalkSpeed", Title="Vitesse de marche", Step=1, Value={Min=16, Max=200, Default=Y.WalkSpeed}, Callback=function(v) Y.WalkSpeed=v; saveConfig() end})
    VisualsTab:Slider({Flag="JumpPower", Title="Puissance de saut", Step=5, Value={Min=50, Max=500, Default=Y.JumpPower}, Callback=function(v) Y.JumpPower=v; saveConfig() end})

    local ProtectionTab = Main:Tab({Title="Protection", Icon="shield"})
    ProtectionTab:Section({Title="Sécurité", TextSize=18})
    toggleCB("AntiTrap", "🛡️ Immunité aux pièges", true)
    toggleCB("AntiKick", "🛡️ Anti-Kick", false)
    toggleCB("AntiAFK", "💤 Anti-AFK", false)
    ProtectionTab:Section({Title="Serveur", TextSize=16})
    toggleCB("ServerHop", "🚀 Changer de serveur auto", false)
    ProtectionTab:Slider({Flag="MaxPlayers", Title="Max joueurs avant hop", Step=1, Value={Min=2, Max=10, Default=Y.MaxPlayers}, Callback=function(v) Y.MaxPlayers=v; saveConfig() end})
    ProtectionTab:Slider({Flag="HopDelay", Title="Délai avant hop (s)", Step=1, Value={Min=1, Max=10, Default=Y.HopDelay}, Callback=function(v) Y.HopDelay=v; saveConfig() end})
    ProtectionTab:Button({Title="🔍 Chercher un serveur vide", Icon="search", Callback=function() ServerHop.hopToEmpty() end})

    local ProgressionTab = Main:Tab({Title="Progression", Icon="trending-up"})
    ProgressionTab:Section({Title="Auto Progression (Biomes)", TextSize=18})
    toggleCB("AutoProgression", "🚀 Activer la progression automatique", false)
    ProgressionTab:Label({Title="📊 Biome actuel : "..(getBestBiome(getCurrentSpeed()).name or "Inconnu"), Icon="map", Color=Color3.fromRGB(200,200,220)})
    ProgressionTab:Label({Title="⚡ Speed : "..getCurrentSpeed(), Icon="zap", Color=Color3.fromRGB(200,200,220)})

    local DebugTab = Main:Tab({Title="Dépannage", Icon="wrench"})
    DebugTab:Section({Title="Remotes", TextSize=18})
    DebugTab:Button({Title="🔄 Re-scanner les remotes", Icon="refresh-cw", Callback=function() for name in pairs(Remotes) do local path = ""; if name=="Steal" then path="RF/EggWorld/AskFieldEgg" elseif name=="Place" then path="RF/EggWorld/AskPlaceEgg" elseif name=="Hatch" then path="RF/EggWorld/AskHatch" elseif name=="FinishHatch" then path="RF/EggWorld/AskFinishHatch" elseif name=="Treadmill" then path="RE/Treadmill/RenderState" elseif name=="Sell" then path="RF/EggWorld/AskSell" end; Remotes[name]=GetRemote(path) end; WindUI:Notify({Title="✅", Content="Remotes actualisés", Icon="check", Duration=2}) end})
    local statusLabel = DebugTab:Label({Title="Statut : Prêt", Icon="info", Color=Color3.fromRGB(200,200,220)})
    task.spawn(function() while true do local b=Y.FarmBottomPos and "✅" or "❌"; local t=Y.FarmTopPos and "✅" or "❌"; local s=Remotes.Steal and "✅" or "❌"; local p=Remotes.Place and "✅" or "❌"; statusLabel:Set({Title=string.format("Bas: %s | Haut: %s | Vol: %s | Pose: %s", b,t,s,p)}); task.wait(2) end end)

    local StatsTab = Main:Tab({Title="Statistiques", Icon="bar-chart"})
    local statsLabel = StatsTab:Label({Title=string.format("🥚 Œufs volés : %d\n🐣 Œufs éclos : %d\n⏱️ Temps : %d s", Y.EggsStolen, Y.EggsHatched, Y.SessionTime), Icon="bar-chart", Color=Color3.fromRGB(200,200,220)})
    task.spawn(function() while true do Y.SessionTime = Y.SessionTime + 1; statsLabel:Set({Title=string.format("🥚 Œufs volés : %d\n🐣 Œufs éclos : %d\n⏱️ Temps : %d s", Y.EggsStolen, Y.EggsHatched, Y.SessionTime)}); task.wait(1) end end)
    StatsTab:Button({Title="Réinitialiser les statistiques", Icon="refresh-cw", Callback=function() Y.EggsStolen=0; Y.EggsHatched=0; Y.SessionTime=0; saveConfig(); WindUI:Notify({Title="✅", Content="Statistiques réinitialisées", Icon="check", Duration=2}) end})

    local SettingsTab = Main:Tab({Title="Paramètres", Icon="settings"})
    SettingsTab:Section({Title="Sauvegarde", TextSize=18})
    SettingsTab:Button({Title="💾 Sauvegarder", Icon="save", Callback=function() saveConfig(); WindUI:Notify({Title="✅", Content="Config sauvegardée", Icon="check", Duration=2}) end})
    SettingsTab:Button({Title="📂 Charger", Icon="upload", Callback=function() if loadConfig() then WindUI:Notify({Title="✅", Content="Config chargée", Icon="check", Duration=2}) else WindUI:Notify({Title="❌", Content="Aucune config trouvée", Icon="x", Duration=2}) end end})
    SettingsTab:Button({Title="🧹 Nettoyer les traces", Icon="trash", Callback=function() AntiDetect:Clean(); WindUI:Notify({Title="✅", Content="Traces nettoyées", Icon="check", Duration=2}) end})
    return Window
end

local function saveConfig()
    local data = {AutoSteal=Y.AutoSteal, AutoPlace=Y.AutoPlace, AutoHatch=Y.AutoHatch, AutoTreadmill=Y.AutoTreadmill, AutoSell=Y.AutoSell, AutoFarm=Y.AutoFarm, AntiTrap=Y.AntiTrap, Noclip=Y.Noclip, ESPEggs=Y.ESPEggs, ESPPlayers=Y.ESPPlayers, AntiKick=Y.AntiKick, AntiAFK=Y.AntiAFK, ServerHop=Y.ServerHop, AutoCollect=Y.AutoCollect, AutoUpgrade=Y.AutoUpgrade, AutoClaim=Y.AutoClaim, AutoRebirth=Y.AutoRebirth, PvPMode=Y.PvPMode, AutoProgression=Y.AutoProgression, SpeedBoost=Y.SpeedBoost, InfiniteJump=Y.InfiniteJump, WalkSpeed=Y.WalkSpeed, JumpPower=Y.JumpPower, FarmSpeed=Y.FarmSpeed, StealDelayMin=Y.StealDelayMin, StealDelayMax=Y.StealDelayMax, TargetRarity=Y.TargetRarity, PvPRange=Y.PvPRange, MaxPlayers=Y.MaxPlayers, HopDelay=Y.HopDelay, FarmBottomPos=Y.FarmBottomPos, FarmTopPos=Y.FarmTopPos}
    if not isfolder("YunoHub") then makefolder("YunoHub") end
    writefile("YunoHub/config.json", HS:JSONEncode(data))
end

local function loadConfig()
    local path = "YunoHub/config.json"
    if not isfile(path) then return false end
    local data = HS:JSONDecode(readfile(path))
    for k, v in pairs(data) do if Y[k] ~= nil then Y[k] = v end end
    return true
end

-- Anti-Detect
local AntiDetect = {}
function AntiDetect:Clean() pcall(function() for k in pairs(_G) do if type(k)=="string" and string.find(k,"Yuno") then _G[k]=nil end end; local ls = game:GetService("LogService"); if ls and ls.ClearOutput then ls:ClearOutput() end end) end
AntiDetect:Clean()

-- Anti-Trap
task.spawn(function() while true do if Y.AntiTrap then pcall(function() for _, obj in pairs(WS:GetDescendants()) do local n=string.lower(obj.Name); if string.find(n, "trap") or string.find(n, "mine") or string.find(n, "spike") or string.find(n, "laser") then if obj:IsA("BasePart") then obj.CanCollide=false; obj.CanTouch=false elseif obj:IsA("TouchInterest") then obj:Destroy() end end end end) end; task.wait(1) end end)

-- Infinite Jump
UIS.JumpRequest:Connect(function() if Y.InfiniteJump then local h=getHum(); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end end end)

-- Speed & Jump
task.spawn(function() while true do task.wait(0.5); local h=getHum(); if h then if Y.SpeedBoost then h.WalkSpeed=Y.WalkSpeed; h.JumpPower=Y.JumpPower else if h.WalkSpeed~=16 then h.WalkSpeed=16; h.JumpPower=50 end end end end end)

-- Noclip
local noclipConn
task.spawn(function() while true do if Y.Noclip then if not noclipConn then noclipConn=RunS.Stepped:Connect(function() local c=LP.Character; if c then for _, part in pairs(c:GetDescendants()) do if part:IsA("BasePart") and part.Name~="HumanoidRootPart" then part.CanCollide=false end end end end) end else if noclipConn then noclipConn:Disconnect(); noclipConn=nil; local c=LP.Character; if c then for _, part in pairs(c:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide=true end end end end end; task.wait(1) end end)

-- ESP
local espObjects, playerHighlights = {}, {}
local function clearESP() for _, v in pairs(espObjects) do pcall(v.Destroy, v) end; espObjects={} end
local function clearPlayerESP() for _, v in pairs(playerHighlights) do pcall(v.Destroy, v) end; playerHighlights={} end
task.spawn(function()
    while true do
        if Y.ESPEggs then
            pcall(function()
                local folder = WS:FindFirstChild("Eggs") or WS:FindFirstChild("DroppedEggs") or WS
                for _, egg in pairs(folder:GetDescendants()) do
                    if egg:IsA("Model") and string.lower(egg.Name):find("egg") and not espObjects[egg] then
                        local part = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
                        if part then
                            local box = Instance.new("SelectionBox")
                            box.Adornee = part; box.Color3 = Color3.fromRGB(255,215,0); box.LineThickness=0.06; box.SurfaceTransparency=0.75; box.SurfaceColor3=Color3.fromRGB(255,215,0); box.Parent=CoreGui
                            espObjects[egg] = box
                            egg.AncestryChanged:Connect(function() if box and box.Parent then box:Destroy(); espObjects[egg]=nil end end)
                        end
                    end
                end
            end)
        else clearESP() end
        if Y.ESPPlayers then
            pcall(function()
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr ~= LP and plr.Character and not playerHighlights[plr] then
                        local hl = Instance.new("Highlight")
                        hl.Adornee = plr.Character; hl.FillColor = Color3.fromRGB(255,0,75); hl.OutlineColor = Color3.fromRGB(255,255,255); hl.Parent = CoreGui
                        playerHighlights[plr] = hl
                    end
                end
            end)
        else clearPlayerESP() end
        task.wait(1)
    end
end)

-- Anti-Kick & Anti-AFK
local kickConn, afkConn
task.spawn(function() while true do if Y.AntiKick then if not kickConn then local mt = getmetatable(LP); if mt then local old = mt.__namecall; mt.__namecall = function(self, ...) if select(1,...)=="Kick" and self==LP then return end; return old(self, ...) end; kickConn=true end end end; task.wait(1) end end)
task.spawn(function() while true do if Y.AntiAFK then if not afkConn then afkConn=task.spawn(function() while Y.AntiAFK do local h=getHum(); if h then h:Move(Vector3.new(0.01,0,0),true); task.wait(0.1); h:Move(Vector3.zero,true) end; task.wait(55) end end) end else if afkConn then task.cancel(afkConn); afkConn=nil end end; task.wait(1) end end)

-- Server Hop
local ServerHop = {}
function ServerHop.getServerList() local ok, result = pcall(function() return HS:JSONDecode(game:HttpGet(string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId))) end); return (ok and result and result.data) or {} end
function ServerHop.findBestServer() local best, fewest = nil, math.huge; for _, srv in ipairs(ServerHop.getServerList()) do if srv.id ~= game.JobId then local count = srv.playing or 0; if count < fewest then fewest=count; best=srv end end end; if best then return best.id, fewest end; return nil, 0 end
function ServerHop.hopToEmpty() local id, count = ServerHop.findBestServer(); if id and count <= Y.MaxPlayers then task.wait(Y.HopDelay); Teleport:TeleportToPlaceInstance(game.PlaceId, id, LP) end end
task.spawn(function() while true do if Y.ServerHop and #Players:GetPlayers() > Y.MaxPlayers then ServerHop.hopToEmpty() end; task.wait(10) end end)

-- Auto Collect
task.spawn(function() while true do if Y.AutoCollect then pcall(function() for _, obj in pairs(WS:GetDescendants()) do if obj:IsA("Part") and (string.lower(obj.Name):find("cash") or string.lower(obj.Name):find("coin")) then safeTeleport(obj.Position); task.wait(0.05); local cd = obj:FindFirstChildOfClass("ClickDetector"); if cd then fireclickdetector(cd) end end end end) end; task.wait(0.5) end end)

-- Auto Upgrade/Claim/Rebirth
task.spawn(function() while true do if Y.AutoUpgrade then pcall(function() local gui = LP.PlayerGui; if gui then local btn = gui:FindFirstChild("UpgradeButton", true); if btn and btn:IsA("TextButton") then btn:Click() end end end) end; task.wait(2) end end)
task.spawn(function() while true do if Y.AutoClaim then pcall(function() local gui = LP.PlayerGui; if gui then for _, btn in pairs(gui:GetDescendants()) do if btn:IsA("TextButton") then local t = string.lower(btn.Text or ""); if t:find("claim") or t:find("collect") or t:find("reward") then btn:Click() end end end end end) end; task.wait(5) end end)
task.spawn(function() while true do if Y.AutoRebirth then pcall(function() local gui = LP.PlayerGui; if gui then for _, btn in pairs(gui:GetDescendants()) do if btn:IsA("TextButton") then local t = string.lower(btn.Text or ""); if t:find("rebirth") or t:find("prestige") then btn:Click(); return end end end end end) end; task.wait(10) end end)

-- PvP
local pvpHighlights = {}
local function playerHasEgg(plr) if not plr or not plr.Character then return false end; for _, obj in pairs(plr.Character:GetChildren()) do if string.lower(obj.Name):find("egg") or string.lower(obj.Name):find("carry") then return true, obj end end; return false, nil end
local function findNearestEggCarrier() local nearest, nearestDist = nil, math.huge; for _, plr in pairs(Players:GetPlayers()) do if plr ~= LP and plr.Character then local r = plr.Character:FindFirstChild("HumanoidRootPart"); if r and playerHasEgg(plr) then local d = (Root.Position - r.Position).Magnitude; if d < nearestDist then nearestDist = d; nearest = plr end end end end; return nearest, nearestDist end
local function swingBat(target) if not target or not target.Character then return false end; local tr = target.Character:FindFirstChild("HumanoidRootPart"); if not tr then return false end; local hr = RS:FindFirstChild("HitPlayer") or RS:FindFirstChild("SwingBat") or RS:FindFirstChild("Attack"); if hr then fireRemote(hr, target.Character, Root.CFrame.LookVector * 50); return true end; safeTeleport(tr.Position + Vector3.new(0,0,-3)); task.wait(0.1); return true end
task.spawn(function() while true do if Y.PvPMode then pcall(function() for _, plr in pairs(Players:GetPlayers()) do if plr ~= LP and plr.Character then local has = playerHasEgg(plr); if has and not pvpHighlights[plr] then local box = Instance.new("SelectionBox"); box.Adornee=plr.Character; box.Color3=Color3.fromRGB(255,50,50); box.LineThickness=0.08; box.SurfaceTransparency=0.85; box.SurfaceColor3=Color3.fromRGB(255,50,50); box.Parent=CoreGui; pvpHighlights[plr]=box; elseif not has and pvpHighlights[plr] then pvpHighlights[plr]:Destroy(); pvpHighlights[plr]=nil end end end; local target, dist = findNearestEggCarrier(); if target and dist <= Y.PvPRange then swingBat(target); task.wait(0.5); local dropped = WS:FindFirstChild("DroppedEggs") or WS; for _, egg in pairs(dropped:GetDescendants()) do if egg:IsA("Model") and string.lower(egg.Name):find("egg") then local part = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart"); if part then safeTeleport(part.Position); task.wait(0.2); local prompt = egg:FindFirstChildOfClass("ProximityPrompt"); if prompt then fireproximityprompt(prompt) end end end end elseif target then local tr = target.Character:FindFirstChild("HumanoidRootPart"); if tr then moveTo(tr.Position) end end end); end; task.wait(0.2) end end)

-- Auto Progression
local BIOMES = {{name="Forest", speedReq=0, rarity="Common", stage=1}, {name="Lake", speedReq=900, rarity="Uncommon", stage=2}, {name="Desert", speedReq=10000, rarity="Rare", stage=3}, {name="Jungle", speedReq=40000, rarity="Rare", stage=3}, {name="Snow", speedReq=170000, rarity="Epic", stage=4}, {name="Volcano", speedReq=700000, rarity="Legendary", stage=4}, {name="Abyss", speedReq=2500000, rarity="Mythic", stage=5}, {name="Prehistoric", speedReq=18000000, rarity="Mythic", stage=5}, {name="Cosmic", speedReq=700000000, rarity="Divine", stage=6}, {name="CherryBlossom", speedReq=2500000000, rarity="Divine", stage=6}}
local function getCurrentSpeed() local ls = LP:FindFirstChild("leaderstats") or LP:FindFirstChild("Stats"); if ls then local spd = ls:FindFirstChild("Speed") or ls:FindFirstChild("speed") or ls:FindFirstChild("SPD"); if spd then return spd.Value end end; return 0 end
local function getBestBiome(speed) local best = BIOMES[1]; for _, b in ipairs(BIOMES) do if speed >= b.speedReq then best = b end end; return best end
task.spawn(function() while true do if Y.AutoProgression then local speed = getCurrentSpeed(); local biome = getBestBiome(speed); Y.TargetRarity = biome.rarity; Y.AutoSteal = true; Y.AutoHatch = true end; task.wait(5) end end)

-- Keybinds
UIS.InputBegan:Connect(function(input, gp) if gp then return end; local key = input.KeyCode; if key == Enum.KeyCode.F1 then Y.AutoSteal = not Y.AutoSteal; saveConfig(); WindUI:Notify({Title="F1", Content="Auto Steal : "..(Y.AutoSteal and "ON" or "OFF"), Icon="info", Duration=2}) elseif key == Enum.KeyCode.F2 then Y.AutoFarm = not Y.AutoFarm; saveConfig(); WindUI:Notify({Title="F2", Content="Auto Farm : "..(Y.AutoFarm and "ON" or "OFF"), Icon="info", Duration=2}) elseif key == Enum.KeyCode.F3 then Y.SpeedBoost = not Y.SpeedBoost; saveConfig(); WindUI:Notify({Title="F3", Content="Speed Boost : "..(Y.SpeedBoost and "ON" or "OFF"), Icon="info", Duration=2}) elseif key == Enum.KeyCode.F4 then Y.Noclip = not Y.Noclip; saveConfig(); WindUI:Notify({Title="F4", Content="Noclip : "..(Y.Noclip and "ON" or "OFF"), Icon="info", Duration=2}) elseif key == Enum.KeyCode.F5 then Y.InfiniteJump = not Y.InfiniteJump; saveConfig(); WindUI:Notify({Title="F5", Content="Infinite Jump : "..(Y.InfiniteJump and "ON" or "OFF"), Icon="info", Duration=2}) elseif key == Enum.KeyCode.F6 then Y.AutoHatch = not Y.AutoHatch; saveConfig(); WindUI:Notify({Title="F6", Content="Auto Hatch : "..(Y.AutoHatch and "ON" or "OFF"), Icon="info", Duration=2}) elseif key == Enum.KeyCode.F7 then Y.AutoCollect = not Y.AutoCollect; saveConfig(); WindUI:Notify({Title="F7", Content="Auto Collect : "..(Y.AutoCollect and "ON" or "OFF"), Icon="info", Duration=2}) elseif key == Enum.KeyCode.F8 then Y.AutoRebirth = not Y.AutoRebirth; saveConfig(); WindUI:Notify({Title="F8", Content="Auto Rebirth : "..(Y.AutoRebirth and "ON" or "OFF"), Icon="info", Duration=2}) elseif key == Enum.KeyCode.F9 then Y.PvPMode = not Y.PvPMode; saveConfig(); WindUI:Notify({Title="F9", Content="PvP Mode : "..(Y.PvPMode and "ON" or "OFF"), Icon="info", Duration=2}) end end)

-- Load and run
loadConfig()
createUI()
getChar()
WindUI:Notify({Title="🥚 Yuno Hub", Content="Chargé avec succès !", Duration=4})
print("YUNO HUB LOADED")
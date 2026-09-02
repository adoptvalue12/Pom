--[[
    YUNO HUB | Steal an Egg
    Interface WindUI + Auto Farm (Rare Egg)
    - Auto Steal / Place / Hatch / Treadmill / Sell
    - Auto Farm : va au fond → vole l'œuf rare → speed 200~300 → pose au début
    - Sauvegarde automatique des paramètres
    - Compatible Delta, Xeno, Solara
--]]

-- ============================================================
-- CHARGEMENT WINDUI
-- ============================================================
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- ============================================================
-- SERVICES & VARIABLES GLOBALES
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

getgenv().YunoSteal = getgenv().YunoSteal or {
    AutoSteal = false,
    AutoPlace = false,
    AutoHatch = false,
    AutoTreadmill = false,
    AutoSell = false,
    AutoFarm = false,
    FarmSpeed = 250,
    StealDelayMin = 0.8,
    StealDelayMax = 1.5,
}
local Yuno = getgenv().YunoSteal

-- Positions de l'auto farm (stockées en mémoire)
local FarmBottomPos = nil  -- Position tout en bas (œuf rare)
local FarmTopPos = nil     -- Position de départ (poser l'œuf)

-- ============================================================
-- FONCTION POUR TROUVER LES REMOTES
-- ============================================================
local function FindRemote(pattern)
    local found = {}
    local function search(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                if string.find(string.lower(child.Name), string.lower(pattern)) then
                    table.insert(found, child)
                end
            end
            if #child:GetChildren() > 0 then search(child) end
        end
    end
    search(ReplicatedStorage)
    search(LocalPlayer.PlayerGui)
    search(game:GetService("Workspace"))
    return found
end

local Remotes = {
    Steal = FindRemote("Steal") or FindRemote("StealEgg") or FindRemote("Grab"),
    Place = FindRemote("Place") or FindRemote("PlaceEgg") or FindRemote("Build"),
    Hatch = FindRemote("Hatch") or FindRemote("Incubate") or FindRemote("Start"),
    Treadmill = FindRemote("Treadmill") or FindRemote("Run") or FindRemote("Exercise"),
    Sell = FindRemote("Sell") or FindRemote("Trade") or FindRemote("Collect"),
}

print("=== YUNO HUB - REMOTES TROUVÉS ===")
for name, remote in pairs(Remotes) do
    if remote and #remote > 0 then
        print(name .. " : " .. remote[1].Name .. " ✅")
    else
        print(name .. " : ❌ Aucun trouvé")
    end
end

-- ============================================================
-- FONCTIONS DE FARM (boucles existantes)
-- ============================================================
local function AutoStealLoop()
    while Yuno.AutoSteal do
        task.wait(math.random(Yuno.StealDelayMin * 10, Yuno.StealDelayMax * 10) / 10)
        local remote = Remotes.Steal
        if remote and #remote > 0 then
            pcall(remote[1].FireServer, remote[1])
        end
    end
end

local function AutoPlaceLoop()
    while Yuno.AutoPlace do
        task.wait(math.random(1, 3))
        local remote = Remotes.Place
        if remote and #remote > 0 then
            pcall(remote[1].FireServer, remote[1])
        end
    end
end

local function AutoHatchLoop()
    while Yuno.AutoHatch do
        task.wait(math.random(2, 5))
        local remote = Remotes.Hatch
        if remote and #remote > 0 then
            pcall(remote[1].FireServer, remote[1])
        end
    end
end

local function AutoTreadmillLoop()
    while Yuno.AutoTreadmill do
        task.wait(0.5)
        local remote = Remotes.Treadmill
        if remote and #remote > 0 then
            pcall(remote[1].FireServer, remote[1])
        end
    end
end

local function AutoSellLoop()
    while Yuno.AutoSell do
        task.wait(math.random(5, 10))
        local remote = Remotes.Sell
        if remote and #remote > 0 then
            pcall(remote[1].FireServer, remote[1])
        end
    end
end

-- ============================================================
-- 🆕 NOUVELLE FONCTION : AUTO FARM (ŒUF RARE)
-- ============================================================
local function AutoFarmLoop()
    while Yuno.AutoFarm do
        if not FarmBottomPos or not FarmTopPos then
            warn("⚠️ Définis d'abord les positions bas et haut dans l'onglet 'Auto Farm' !")
            break
        end

        local char = LocalPlayer.Character
        if not char then task.wait(1) continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then task.wait(1) continue end

        -- 1. Téléportation instantanée tout en bas (là où est l'œuf rare)
        root.CFrame = CFrame.new(FarmBottomPos) + Vector3.new(0, 3, 0)
        task.wait(0.2)

        -- 2. Voler l'œuf
        local stealRemote = Remotes.Steal
        if stealRemote and #stealRemote > 0 then
            pcall(stealRemote[1].FireServer, stealRemote[1])
            -- Si ça ne marche pas, essaie avec un argument : pcall(stealRemote[1].FireServer, stealRemote[1], "Nest")
        end
        task.wait(0.3)

        -- 3. Activer la vitesse de ouf (200~300) et remonter en courant
        local oldSpeed = hum.WalkSpeed
        local oldJump = hum.JumpPower
        hum.WalkSpeed = Yuno.FarmSpeed or 250
        hum.JumpPower = 100
        hum:MoveTo(FarmTopPos)

        -- Attendre d'arriver en haut (ou timeout 8s)
        local timeout = 8
        local startTime = tick()
        while (root.Position - FarmTopPos).Magnitude > 5 and tick() - startTime < timeout do
            task.wait(0.05)
        end

        -- 4. Poser l'œuf au début
        local placeRemote = Remotes.Place
        if placeRemote and #placeRemote > 0 then
            pcall(placeRemote[1].FireServer, placeRemote[1])
        end

        -- 5. Remettre la vitesse normale
        hum.WalkSpeed = oldSpeed
        hum.JumpPower = oldJump

        task.wait(1) -- petite pause avant de recommencer
    end
end

-- ============================================================
-- SAUVEGARDE DE LA CONFIG
-- ============================================================
local function saveConfig()
    local data = {
        AutoSteal = Yuno.AutoSteal,
        AutoPlace = Yuno.AutoPlace,
        AutoHatch = Yuno.AutoHatch,
        AutoTreadmill = Yuno.AutoTreadmill,
        AutoSell = Yuno.AutoSell,
        AutoFarm = Yuno.AutoFarm,
        FarmSpeed = Yuno.FarmSpeed,
        StealDelayMin = Yuno.StealDelayMin,
        StealDelayMax = Yuno.StealDelayMax,
        -- On sauvegarde aussi les positions
        FarmBottomPos = FarmBottomPos,
        FarmTopPos = FarmTopPos,
    }
    local json = game:GetService("HttpService"):JSONEncode(data)
    if not isfolder("YunoSteal") then makefolder("YunoSteal") end
    writefile("YunoSteal/config.json", json)
end

local function loadConfig()
    local path = "YunoSteal/config.json"
    if not isfile(path) then return false end
    local data = game:GetService("HttpService"):JSONDecode(readfile(path))
    for k, v in pairs(data) do
        if Yuno[k] ~= nil then Yuno[k] = v end
        if k == "FarmBottomPos" then FarmBottomPos = v end
        if k == "FarmTopPos" then FarmTopPos = v end
    end
    return true
end

-- ============================================================
-- FONCTION ESPIONNE POUR TROUVER LES ARGUMENTS DES REMOTES
-- ============================================================
local function SpyRemotes()
    WindUI:Notify({ Title = "Spy", Content = "Regarde la console (F9) et interagis !", Icon = "eye", Duration = 4 })
    local oldFire = ReplicatedStorage.FindFirstChild("RemoteEvent") and ReplicatedStorage.RemoteEvent.FireServer
    if not oldFire then
        -- On espionne tous les RemoteEvents trouvés
        for _, remote in pairs(Remotes) do
            if remote and #remote > 0 then
                local r = remote[1]
                local old = r.FireServer
                r.FireServer = function(self, ...)
                    print("[SPY] Remote:", self.Name, "| Args:", ...)
                    return old(self, ...)
                end
            end
        end
    end
end

-- ============================================================
-- INTERFACE WINDUI (avec le nouvel onglet Auto Farm)
-- ============================================================
local function createUI()
    local Window = WindUI:CreateWindow({
        Title = "Yuno Hub | Steal an Egg",
        Author = "Yuno",
        Folder = "YunoSteal",
        Icon = "egg",
        Size = UDim2.new(0, 520, 0, 520),
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

    -- ============================
    -- ONGLET CONTRÔLE (classique)
    -- ============================
    local Tab = Main:Tab({ Title = "Contrôle", Icon = "play" })

    Tab:Section({ Title = "Fonctionnalités", TextSize = 18 })
    Tab:Toggle({
        Flag = "AutoSteal",
        Title = "Voler un œuf",
        Default = Yuno.AutoSteal,
        Callback = function(v) Yuno.AutoSteal = v saveConfig() if v then task.spawn(AutoStealLoop) end end
    })
    Tab:Toggle({
        Flag = "AutoPlace",
        Title = "Poser un œuf",
        Default = Yuno.AutoPlace,
        Callback = function(v) Yuno.AutoPlace = v saveConfig() if v then task.spawn(AutoPlaceLoop) end end
    })
    Tab:Toggle({
        Flag = "AutoHatch",
        Title = "Éclore",
        Default = Yuno.AutoHatch,
        Callback = function(v) Yuno.AutoHatch = v saveConfig() if v then task.spawn(AutoHatchLoop) end end
    })
    Tab:Toggle({
        Flag = "AutoTreadmill",
        Title = "Tapis de course",
        Default = Yuno.AutoTreadmill,
        Callback = function(v) Yuno.AutoTreadmill = v saveConfig() if v then task.spawn(AutoTreadmillLoop) end end
    })
    Tab:Toggle({
        Flag = "AutoSell",
        Title = "Vendre (collecter)",
        Default = Yuno.AutoSell,
        Callback = function(v) Yuno.AutoSell = v saveConfig() if v then task.spawn(AutoSellLoop) end end
    })

    Tab:Section({ Title = "Délais de vol", TextSize = 16 })
    Tab:Slider({
        Flag = "StealDelayMin",
        Title = "Délai min (s)",
        Step = 0.1,
        Value = { Min = 0.2, Max = 3, Default = Yuno.StealDelayMin },
        Callback = function(v) Yuno.StealDelayMin = v saveConfig() end
    })
    Tab:Slider({
        Flag = "StealDelayMax",
        Title = "Délai max (s)",
        Step = 0.1,
        Value = { Min = 0.5, Max = 5, Default = Yuno.StealDelayMax },
        Callback = function(v) Yuno.StealDelayMax = v saveConfig() end
    })

    -- ============================
    -- 🆕 ONGLET AUTO FARM (ŒUF RARE)
    -- ============================
    local FarmTab = Main:Tab({ Title = "Auto Farm", Icon = "target" })

    FarmTab:Section({ Title = "📍 Définir les positions", TextSize = 18 })
    FarmTab:Button({
        Title = "⬇️ Position BAS (œuf rare)",
        Icon = "arrow-down",
        Callback = function()
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                FarmBottomPos = char.HumanoidRootPart.Position
                saveConfig()
                WindUI:Notify({ Title = "✅ Pos bas", Content = "Définie !", Icon = "check", Duration = 2 })
            end
        end
    })
    FarmTab:Button({
        Title = "⬆️ Position HAUT (début / pose)",
        Icon = "arrow-up",
        Callback = function()
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                FarmTopPos = char.HumanoidRootPart.Position
                saveConfig()
                WindUI:Notify({ Title = "✅ Pos haut", Content = "Définie !", Icon = "check", Duration = 2 })
            end
        end
    })

    FarmTab:Section({ Title = "⚡ Paramètres de vitesse", TextSize = 16 })
    FarmTab:Slider({
        Flag = "FarmSpeed",
        Title = "Vitesse de retour (200 ~ 300)",
        Step = 10,
        Value = { Min = 200, Max = 300, Default = Yuno.FarmSpeed or 250 },
        Callback = function(v) Yuno.FarmSpeed = v saveConfig() end
    })

    FarmTab:Toggle({
        Flag = "AutoFarm",
        Title = "🔄 Lancer l'auto farm (boucle)",
        Default = Yuno.AutoFarm,
        Callback = function(v)
            Yuno.AutoFarm = v
            saveConfig()
            if v then
                if not FarmBottomPos or not FarmTopPos then
                    WindUI:Notify({ Title = "⚠️ Erreur", Content = "Définis les positions d'abord !", Icon = "x", Duration = 3 })
                    Yuno.AutoFarm = false
                    saveConfig()
                    return
                end
                task.spawn(AutoFarmLoop)
            end
        end
    })

    -- ============================
    -- ONGLET DÉPANNAGE
    -- ============================
    local DebugTab = Main:Tab({ Title = "Dépannage", Icon = "wrench" })
    DebugTab:Section({ Title = "Remotes & Spy", TextSize = 18 })
    DebugTab:Button({
        Title = "🔍 Espionner les remotes (console F9)",
        Icon = "eye",
        Callback = SpyRemotes
    })
    DebugTab:Button({
        Title = "🔄 Re-scanner les remotes",
        Icon = "refresh-cw",
        Callback = function()
            for name in pairs(Remotes) do
                Remotes[name] = FindRemote(name) or FindRemote(string.lower(name))
            end
            WindUI:Notify({ Title = "Scan", Content = "Remotes actualisés !", Icon = "check", Duration = 2 })
        end
    })

    local statusInfo = DebugTab:Label({
        Title = "Infos : ",
        Icon = "info",
        Color = Color3.fromRGB(200, 200, 220)
    })
    task.spawn(function()
        while true do
            local bottom = FarmBottomPos and "✅" or "❌"
            local top = FarmTopPos and "✅" or "❌"
            local steal = (Remotes.Steal and #Remotes.Steal > 0) and "✅" or "❌"
            local place = (Remotes.Place and #Remotes.Place > 0) and "✅" or "❌"
            statusInfo:Set({
                Title = string.format("Bas: %s | Haut: %s | Vol: %s | Pose: %s", bottom, top, steal, place)
            })
            task.wait(2)
        end
    end)

    -- ============================
    -- ONGLET PARAMÈTRES
    -- ============================
    local Settings = Main:Tab({ Title = "Paramètres", Icon = "settings" })
    Settings:Section({ Title = "Sauvegarde", TextSize = 18 })
    Settings:Button({
        Title = "💾 Sauvegarder",
        Icon = "save",
        Callback = function()
            saveConfig()
            WindUI:Notify({ Title = "Config", Content = "Sauvegardée !", Icon = "check", Duration = 2 })
        end
    })
    Settings:Button({
        Title = "📂 Charger",
        Icon = "upload",
        Callback = function()
            if loadConfig() then
                -- Met à jour les toggles et sliders
                local tab = Window:GetTab("Contrôle")
                if tab then
                    local flags = {"AutoSteal", "AutoPlace", "AutoHatch", "AutoTreadmill", "AutoSell"}
                    for _, f in ipairs(flags) do
                        local toggle = tab:GetFlag(f)
                        if toggle then toggle:Set(Yuno[f]) end
                    end
                end
                local farmTab = Window:GetTab("Auto Farm")
                if farmTab then
                    local toggle = farmTab:GetFlag("AutoFarm")
                    if toggle then toggle:Set(Yuno.AutoFarm) end
                    local slider = farmTab:GetFlag("FarmSpeed")
                    if slider then slider:Set(Yuno.FarmSpeed) end
                end
                WindUI:Notify({ Title = "Config", Content = "Chargée !", Icon = "check", Duration = 2 })
            else
                WindUI:Notify({ Title = "Erreur", Content = "Aucune config trouvée.", Icon = "x", Duration = 2 })
            end
        end
    })

    return Window
end

-- ============================================================
-- LANCEMENT
-- ============================================================
local function run()
    loadConfig()
    createUI()
    print("✅ Yuno Hub v2 (Auto Farm Rare Egg) chargé !")
    print("📌 Va dans l'onglet 'Auto Farm' pour définir les positions.")
    print("📌 Si les remotes ne marchent pas, utilise le bouton 'Espionner'.")
end

task.spawn(run)
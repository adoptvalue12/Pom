--[[
    YUNO HUB | Steal an Egg
    Interface WindUI
    Remotes identifiés via Cobalt Spy
    - Auto Steal (AskFieldEgg)
    - Auto Place (AskPlaceEgg)
    - Auto Hatch (AskHatch + AskFinishHatch)
    - Auto Treadmill (Treadmill/RenderState)
    - Auto Sell (AskSell à ajouter si trouvé)
    - Auto Farm (va en bas → vole → speed → pose en haut)
--]]

-- ============================================================
-- CHARGEMENT WINDUI
-- ============================================================
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- CONFIG PERSISTANTE
-- ============================================================
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

-- Positions pour l'auto farm
local FarmBottomPos = nil
local FarmTopPos = nil

-- ============================================================
-- REMOTES EXACTS (d'après tes logs)
-- ============================================================
-- Pour être sûr, on utilise des noms complets (avec le dossier)
local function GetRemote(path)
    local parts = {}
    for part in string.gmatch(path, "[^/]+") do
        table.insert(parts, part)
    end
    local current = ReplicatedStorage
    for i, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then
            -- Cherche aussi dans Workspace et PlayerGui
            current = Workspace:FindFirstChild(part) or LocalPlayer.PlayerGui:FindFirstChild(part)
            if not current then break end
        end
        if i == #parts then
            return current
        end
    end
    return nil
end

local Remotes = {
    Steal = GetRemote("RF/EggWorld/AskFieldEgg") or GetRemote("AskFieldEgg"),
    Place = GetRemote("RF/EggWorld/AskPlaceEgg") or GetRemote("AskPlaceEgg"),
    Hatch = GetRemote("RF/EggWorld/AskHatch") or GetRemote("AskHatch"),
    FinishHatch = GetRemote("RF/EggWorld/AskFinishHatch") or GetRemote("AskFinishHatch"),
    Treadmill = GetRemote("RE/Treadmill/RenderState") or GetRemote("Treadmill/RenderState"),
    Sell = GetRemote("RF/EggWorld/AskSell") or GetRemote("AskSell"), -- à confirmer
}

-- Affichage dans la console
print("=== YUNO HUB - REMOTES CHARGÉS ===")
for name, remote in pairs(Remotes) do
    if remote then
        print(name .. " : ✅ " .. remote.Name)
    else
        print(name .. " : ❌ Introuvable")
    end
end

-- ============================================================
-- FONCTIONS DE BOUCLE
-- ============================================================

local function AutoStealLoop()
    while Yuno.AutoSteal do
        task.wait(math.random(Yuno.StealDelayMin * 10, Yuno.StealDelayMax * 10) / 10)
        local remote = Remotes.Steal
        if remote then
            -- D'après tes logs, les arguments sont souvent : "AreaEggs" ou 1
            pcall(remote.InvokeServer, remote, "AreaEggs") -- ou remote:FireServer("AreaEggs")
        end
    end
end

local function AutoPlaceLoop()
    while Yuno.AutoPlace do
        task.wait(math.random(1, 3))
        local remote = Remotes.Place
        if remote then
            pcall(remote.InvokeServer, remote, true) -- ou FireServer(true)
        end
    end
end

local function AutoHatchLoop()
    while Yuno.AutoHatch do
        task.wait(math.random(2, 5))
        local remote = Remotes.Hatch
        if remote then
            pcall(remote.InvokeServer, remote, true) -- démarrer l'éclosion
            task.wait(1)
            local finish = Remotes.FinishHatch
            if finish then
                pcall(finish.InvokeServer, finish, true) -- terminer l'éclosion
            end
        end
    end
end

local function AutoTreadmillLoop()
    while Yuno.AutoTreadmill do
        task.wait(0.5)
        local remote = Remotes.Treadmill
        if remote then
            -- D'après les logs, il y a des arguments comme 100 (vitesse)
            pcall(remote.FireServer, remote, 100) -- ou InvokeServer
        end
    end
end

local function AutoSellLoop()
    while Yuno.AutoSell do
        task.wait(math.random(5, 10))
        local remote = Remotes.Sell
        if remote then
            -- Il faudra l'ID du pet, on met un placeholder
            pcall(remote.InvokeServer, remote, "Pet_123")
        end
    end
end

-- ============================================================
-- AUTO FARM (ŒUF RARE) - avec les bons remotes
-- ============================================================
local function AutoFarmLoop()
    while Yuno.AutoFarm do
        if not FarmBottomPos or not FarmTopPos then
            warn("⚠️ Définis les positions BAS et HAUT dans l'onglet Auto Farm")
            break
        end

        local char = LocalPlayer.Character
        if not char then task.wait(1) continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then task.wait(1) continue end

        -- 1. Téléportation tout en bas
        root.CFrame = CFrame.new(FarmBottomPos) + Vector3.new(0, 3, 0)
        task.wait(0.2)

        -- 2. Voler l'œuf (AskFieldEgg avec argument "AreaEggs")
        local steal = Remotes.Steal
        if steal then
            pcall(steal.InvokeServer, steal, "AreaEggs")
        end
        task.wait(0.3)

        -- 3. Speed boost pour remonter
        local oldSpeed = hum.WalkSpeed
        local oldJump = hum.JumpPower
        hum.WalkSpeed = Yuno.FarmSpeed or 250
        hum.JumpPower = 100
        hum:MoveTo(FarmTopPos)

        -- Attendre d'arriver en haut
        local timeout = 8
        local startTime = tick()
        while (root.Position - FarmTopPos).Magnitude > 5 and tick() - startTime < timeout do
            task.wait(0.05)
        end

        -- 4. Poser l'œuf (AskPlaceEgg avec argument true)
        local place = Remotes.Place
        if place then
            pcall(place.InvokeServer, place, true)
        end

        -- 5. Restaurer la vitesse
        hum.WalkSpeed = oldSpeed
        hum.JumpPower = oldJump

        task.wait(1)
    end
end

-- ============================================================
-- SAUVEGARDE
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
        FarmBottomPos = FarmBottomPos,
        FarmTopPos = FarmTopPos,
    }
    if not isfolder("YunoSteal") then makefolder("YunoSteal") end
    writefile("YunoSteal/config.json", game:GetService("HttpService"):JSONEncode(data))
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
-- INTERFACE WINDUI
-- ============================================================
local function createUI()
    local Window = WindUI:CreateWindow({
        Title = "Yuno Hub | Steal an Egg",
        Author = "Yuno",
        Folder = "YunoSteal",
        Icon = "egg",
        Size = UDim2.new(0, 520, 0, 550),
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

    Tab:Section({ Title = "Fonctionnalités", TextSize = 18 })
    Tab:Toggle({
        Flag = "AutoSteal",
        Title = "Voler un œuf (AskFieldEgg)",
        Default = Yuno.AutoSteal,
        Callback = function(v) Yuno.AutoSteal = v saveConfig() if v then task.spawn(AutoStealLoop) end end
    })
    Tab:Toggle({
        Flag = "AutoPlace",
        Title = "Poser un œuf (AskPlaceEgg)",
        Default = Yuno.AutoPlace,
        Callback = function(v) Yuno.AutoPlace = v saveConfig() if v then task.spawn(AutoPlaceLoop) end end
    })
    Tab:Toggle({
        Flag = "AutoHatch",
        Title = "Éclore (AskHatch + AskFinishHatch)",
        Default = Yuno.AutoHatch,
        Callback = function(v) Yuno.AutoHatch = v saveConfig() if v then task.spawn(AutoHatchLoop) end end
    })
    Tab:Toggle({
        Flag = "AutoTreadmill",
        Title = "Tapis de course (Treadmill/RenderState)",
        Default = Yuno.AutoTreadmill,
        Callback = function(v) Yuno.AutoTreadmill = v saveConfig() if v then task.spawn(AutoTreadmillLoop) end end
    })
    Tab:Toggle({
        Flag = "AutoSell",
        Title = "Vendre (AskSell - à tester)",
        Default = Yuno.AutoSell,
        Callback = function(v) Yuno.AutoSell = v saveConfig() if v then task.spawn(AutoSellLoop) end end
    })

    Tab:Section({ Title = "Délais", TextSize = 16 })
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

    -- Auto Farm
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
                WindUI:Notify({ Title = "✅", Content = "Pos bas définie", Icon = "check", Duration = 2 })
            end
        end
    })
    FarmTab:Button({
        Title = "⬆️ Position HAUT (pose)",
        Icon = "arrow-up",
        Callback = function()
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                FarmTopPos = char.HumanoidRootPart.Position
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
        Callback = function(v) Yuno.FarmSpeed = v saveConfig() end
    })
    FarmTab:Toggle({
        Flag = "AutoFarm",
        Title = "🔄 Lancer l'auto farm",
        Default = Yuno.AutoFarm,
        Callback = function(v)
            Yuno.AutoFarm = v
            saveConfig()
            if v then
                if not FarmBottomPos or not FarmTopPos then
                    WindUI:Notify({ Title = "⚠️", Content = "Définis les positions d'abord !", Icon = "x", Duration = 3 })
                    Yuno.AutoFarm = false
                    saveConfig()
                    return
                end
                task.spawn(AutoFarmLoop)
            end
        end
    })

    -- Dépannage
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
            WindUI:Notify({ Title = "Scan", Content = "Remotes actualisés", Icon = "check", Duration = 2 })
        end
    })

    -- Status
    local status = DebugTab:Label({
        Title = "Statut : Prêt",
        Icon = "info",
        Color = Color3.fromRGB(200, 200, 220)
    })
    task.spawn(function()
        while true do
            local bottom = FarmBottomPos and "✅" or "❌"
            local top = FarmTopPos and "✅" or "❌"
            local steal = Remotes.Steal and "✅" or "❌"
            local place = Remotes.Place and "✅" or "❌"
            status:Set({
                Title = string.format("Bas: %s | Haut: %s | Vol: %s | Pose: %s", bottom, top, steal, place)
            })
            task.wait(2)
        end
    end)

    -- Paramètres
    local Settings = Main:Tab({ Title = "Paramètres", Icon = "settings" })
    Settings:Section({ Title = "Sauvegarde", TextSize = 18 })
    Settings:Button({
        Title = "💾 Sauvegarder",
        Icon = "save",
        Callback = function() saveConfig() WindUI:Notify({ Title = "Config", Content = "Sauvegardée", Icon = "check", Duration = 2 }) end
    })
    Settings:Button({
        Title = "📂 Charger",
        Icon = "upload",
        Callback = function()
            if loadConfig() then
                WindUI:Notify({ Title = "Config", Content = "Chargée", Icon = "check", Duration = 2 })
            else
                WindUI:Notify({ Title = "Erreur", Content = "Aucune config", Icon = "x", Duration = 2 })
            end
        end
    })

    return Window
end

-- ============================================================
-- LANCEMENT
-- ============================================================
loadConfig()
createUI()
print("✅ Yuno Hub chargé avec les remotes de Cobalt !")
print("📌 Si ça ne marche pas, utilise 'Re-scanner' ou vérifie les arguments.")
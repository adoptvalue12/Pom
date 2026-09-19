-- ============================================================
-- Yuno Hub - Pet & Toy Spawner + Visual Trade
-- Equip, Ride, Fly, Rename, Pet Wear, Thèmes (dans le 1er onglet)
-- Ajout visuel local dans le trade (l'autre joueur ne le voit pas)
-- ============================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

pcall(function() setthreadidentity(2) end)

-- ============================================================
-- Chargement des modules
-- ============================================================
local Fsys = require(ReplicatedStorage:WaitForChild("Fsys"))
local load = Fsys.load

local ClientData = load("ClientData")
local InventoryDB = load("InventoryDB")
local KindDB = load("KindDB")
local DownloadClient = load("DownloadClient")
local UIManager = load("UIManager")
local RouterClient = load("RouterClient")

if not ClientData or not InventoryDB or not KindDB then
    error("Modules requis non chargés")
end

-- ============================================================
-- Anti-Stack
-- ============================================================
do
    local ok, HashHelper = pcall(function() return load("BackpackItemStackHashHelper") end)
    if ok and HashHelper and HashHelper.get_item_data_hash and not HashHelper._antiStackInstalled then
        HashHelper._antiStackInstalled = true
        local _orig = HashHelper.get_item_data_hash
        HashHelper.get_item_data_hash = function(item_data)
            if item_data and item_data.unique then
                return "nostack_" .. item_data.unique
            end
            return _orig(item_data)
        end
    end
end

-- ============================================================
-- Moteur des pets
-- ============================================================
local AilmentsClient    = nil; pcall(function() AilmentsClient   = load("new:AilmentsClient") end)
local AilmentsDB        = nil; pcall(function() AilmentsDB        = load("new:AilmentsDB") end)
local BPPetRigs         = nil; pcall(function() BPPetRigs         = load("new:PetRigs") end)
local EquipPermissions  = nil; pcall(function() EquipPermissions  = load("EquipPermissions") end)
local ClientToolManager = nil; pcall(function() ClientToolManager = load("ClientToolManager") end)
local InteriorsM        = nil; pcall(function() InteriorsM        = load("InteriorsM") end)
local AnimationManager  = nil; pcall(function() AnimationManager  = load("AnimationManager") end)

local SpawnedPets = {}
local EquippedPet = nil
local CurrentRideId = nil
local RideAnimationTrack = nil
local PetAilmentsCache = {}
local MegaNeonConnections = {}
local PetModelCache = {}

local NewnessGroups = {
    mega_neon_flyable_rideable = 990000,
    mega_neon_flyable = 980000,
    mega_neon_rideable = 970000,
    mega_neon = 960000,
    neon_flyable_rideable = 950000,
    neon_flyable = 940000,
    neon_rideable = 930000,
    neon = 920000,
    flyable_rideable = 910000,
    flyable = 900000,
    rideable = 890000,
    regular = 880000,
}

local function GetPropertyGroup(p)
    local m,n,f,r = p.mega_neon or false, p.neon or false, p.flyable or false, p.rideable or false
    if m then
        if f and r then return "mega_neon_flyable_rideable" elseif f then return "mega_neon_flyable"
        elseif r then return "mega_neon_rideable" else return "mega_neon" end
    elseif n then
        if f and r then return "neon_flyable_rideable" elseif f then return "neon_flyable"
        elseif r then return "neon_rideable" else return "neon" end
    else
        if f and r then return "flyable_rideable" elseif f then return "flyable"
        elseif r then return "rideable" else return "regular" end
    end
end

local function BPApplyNeon(petModel, kind)
    pcall(function()
        local petModelInstance = petModel:FindFirstChild("PetModel") or petModel
        local petData = InventoryDB.pets and InventoryDB.pets[kind]
        if not petData or not petData.neon_parts then return end
        for neonPart, cfg in pairs(petData.neon_parts) do
            local part = BPPetRigs.get(petModelInstance).get_geo_part(petModelInstance, neonPart)
            if part then
                part.Material = Enum.Material.Neon
                if cfg.Color then part.Color = cfg.Color end
            end
        end
    end)
end

local function BPApplyMegaNeon(petModel, kind)
    pcall(function()
        local petModelInstance = petModel:FindFirstChild("PetModel") or petModel
        local petData = InventoryDB.pets and InventoryDB.pets[kind]
        if not petData or not petData.neon_parts then return end
        for neonPart, cfg in pairs(petData.neon_parts) do
            local part = BPPetRigs.get(petModelInstance).get_geo_part(petModelInstance, neonPart)
            if part then
                part.Material = Enum.Material.Neon
                if cfg.Color then
                    local h, s, v = cfg.Color:ToHSV()
                    part.Color = Color3.fromHSV(h, math.min(s * 1.3, 1), math.min(v * 1.4, 1))
                else
                    part.Color = Color3.fromRGB(170, 0, 255)
                end
            end
        end
    end)
end

local function BPStopMegaNeon(uid)
    local c = MegaNeonConnections[uid]
    if c then pcall(function() c:Disconnect() end); MegaNeonConnections[uid] = nil end
end

local function BPApplyNeonVisuals(petModel, petData)
    local kindKey = petData.kind or petData.id
    if petData.properties.mega_neon then
        BPApplyMegaNeon(petModel, kindKey)
        BPStopMegaNeon(petData.unique)
        local hue = 0
        local mi = petModel:FindFirstChild("PetModel") or petModel
        local conn
        conn = RunService.Heartbeat:Connect(function(dt)
            if not petModel.Parent then
                conn:Disconnect(); MegaNeonConnections[petData.unique] = nil; return
            end
            hue = (hue + dt * 0.3) % 1
            local petDb = InventoryDB.pets and InventoryDB.pets[kindKey]
            if petDb and petDb.neon_parts then
                for neonPart in pairs(petDb.neon_parts) do
                    pcall(function()
                        local part = BPPetRigs.get(mi).get_geo_part(mi, neonPart)
                        if part then part.Color = Color3.fromHSV(hue, 1, 1) end
                    end)
                end
            end
        end)
        MegaNeonConnections[petData.unique] = conn
    elseif petData.properties.neon then
        BPApplyNeon(petModel, kindKey)
    end
end

local function BPUpdateData(key, action)
    pcall(function() setthreadidentity(2) end)
    local cur = ClientData.get(key)
    local cloned = table.clone(cur or {})
    local result = action(cloned)
    ClientData.predict(key, result)
    pcall(function() setthreadidentity(8) end)
    return result
end

local function BPFindIndex(array, checker)
    for i, v in pairs(array) do
        if checker(v, i) then return i end
    end
end

local function BPFetchPetModel(kind)
    if PetModelCache[kind] then return PetModelCache[kind] end
    local model = DownloadClient.promise_download_copy("Pets", kind):expect()
    PetModelCache[kind] = model
    return model
end

local function BPRegisterWrapper(w)
    BPUpdateData("pet_char_wrappers", function(ws)
        w.unique = #ws + 1; w.index = #ws + 1
        ws[#ws + 1] = w; return ws
    end)
end

local function BPRegisterState(s)
    BPUpdateData("pet_state_managers", function(ms)
        ms[#ms + 1] = s; return ms
    end)
end

local function BPRemoveWrapper(uid)
    BPUpdateData("pet_char_wrappers", function(ws)
        local i = BPFindIndex(ws, function(w) return w.pet_unique == uid end)
        if i then table.remove(ws, i)
            for j = i, #ws do ws[j].unique = j; ws[j].index = j end
        end
        return ws
    end)
end

local function BPRemoveState(uid)
    local pet = SpawnedPets[uid]
    if not pet or not pet.model then return end
    BPUpdateData("pet_state_managers", function(ms)
        local i = BPFindIndex(ms, function(m) return m.char == pet.model end)
        if i then table.remove(ms, i) end; return ms
    end)
end

local function BPClearPetStates(uid)
    local pet = SpawnedPets[uid]
    if not pet or not pet.model then return end
    BPUpdateData("pet_state_managers", function(ms)
        local i = BPFindIndex(ms, function(m) return m.char == pet.model end)
        if i then local u = table.clone(ms); u[i] = table.clone(u[i]); u[i].states = {}; return u end
        return ms
    end)
end

local function BPSetPetState(uid, id)
    local pet = SpawnedPets[uid]
    if not pet or not pet.model then return end
    BPUpdateData("pet_state_managers", function(ms)
        local i = BPFindIndex(ms, function(m) return m.char == pet.model end)
        if i then local u = table.clone(ms); u[i] = table.clone(u[i]); u[i].states = {{id=id}}; return u end
        return ms
    end)
end

local function BPClearPlayerStates()
    BPUpdateData("state_manager", function(s)
        local u = table.clone(s); u.states = {}; u.is_sitting = false; return u
    end)
end

local function BPSetPlayerState(id)
    BPUpdateData("state_manager", function(s)
        local u = table.clone(s); u.states = {{id=id}}; u.is_sitting = true; return u
    end)
end

local function BPAttachRideConstraint(petModel)
    local char = Players.LocalPlayer.Character
    if not char or not char.PrimaryPart then return false end
    local ridePos = petModel:FindFirstChild("RidePosition", true)
    if not ridePos then return false end
    local att = Instance.new("Attachment")
    att.Parent = ridePos; att.Position = Vector3.new(0, 1.237, 0); att.Name = "SourceAttachment"
    local rc = Instance.new("RigidConstraint")
    rc.Name = "StateConnection"; rc.Attachment0 = att
    rc.Attachment1 = char.PrimaryPart.RootAttachment; rc.Parent = char
    return true
end

local function BPDismount()
    if not CurrentRideId then return end
    local pet = SpawnedPets[CurrentRideId]
    if pet and pet.model then
        if RideAnimationTrack then RideAnimationTrack:Stop(); RideAnimationTrack:Destroy(); RideAnimationTrack = nil end
        local att = pet.model:FindFirstChild("SourceAttachment", true)
        if att then att:Destroy() end
        local char = Players.LocalPlayer.Character
        if char then
            for _, p in pairs(char:GetDescendants()) do
                if p:IsA("BasePart") and p:GetAttribute("HaveMass") then p.Massless = false end
            end
        end
        BPClearPetStates(CurrentRideId); BPClearPlayerStates()
        pet.model:ScaleTo(1)
    end
    CurrentRideId = nil
end

local function BPMount(uid, playerState, petState)
    local pet = SpawnedPets[uid]
    if not pet or not pet.model then return end
    local char = Players.LocalPlayer.Character
    if not char or not char.PrimaryPart or not char:FindFirstChild("Humanoid") then return end
    BPDismount(); CurrentRideId = uid
    BPSetPetState(uid, petState); BPSetPlayerState(playerState)
    pet.model:ScaleTo(2); BPAttachRideConstraint(pet.model)
    if AnimationManager then
        RideAnimationTrack = char.Humanoid.Animator:LoadAnimation(AnimationManager.get_track("PlayerRidingPet"))
        char.Humanoid.Sit = true
        for _, p in pairs(char:GetDescendants()) do
            if p:IsA("BasePart") and not p.Massless then p.Massless = true; p:SetAttribute("HaveMass", true) end
        end
        RideAnimationTrack:Play()
    end
end

local function BPUnequip(petData)
    local pet = SpawnedPets[petData.unique]
    if not pet or not pet.model then return end
    if CurrentRideId == petData.unique then BPDismount() end
    BPStopMegaNeon(petData.unique)
    BPRemoveWrapper(petData.unique); BPRemoveState(petData.unique)
    pet.model:Destroy(); pet.model = nil
    if EquippedPet and EquippedPet.unique == petData.unique then EquippedPet = nil end
    PetAilmentsCache[petData.unique] = nil
    task.wait(0.15); if AilmentsClient then pcall(AilmentsClient.on_ailments_changed, Players.LocalPlayer) end
end

local function BPEquip(petData, options)
    if petData.category ~= "pets" then return end
    if EquippedPet then BPUnequip(EquippedPet) end
    for _, w in pairs(ClientData.get("pet_char_wrappers") or {}) do
        if w.controller == Players.LocalPlayer then
            pcall(function() RouterClient.get("ToolAPI/Unequip"):InvokeServer(w.pet_unique) end)
        end
    end
    if not SpawnedPets[petData.unique] then
        SpawnedPets[petData.unique] = { data = petData, model = nil }
    else
        SpawnedPets[petData.unique].data = petData
    end
    local petModel = BPFetchPetModel(petData.kind):Clone()
    local spawnCFrame = options and options.spawn_cframe
    if spawnCFrame then
        pcall(function() petModel:PivotTo(spawnCFrame) end)
        petModel:SetAttribute("HasSpawnCFrame", true)
    end
    petModel.Parent = workspace
    SpawnedPets[petData.unique].model = petModel
    BPApplyNeonVisuals(petModel, petData)
    EquippedPet = petData
    local loc = nil
    if InteriorsM then pcall(function() loc = InteriorsM.get_current_location() end) end
    local destId = (loc and loc.destination_id) or "housing"
    local fullDestId = (loc and loc.full_destination_id) or destId
    local subDestId = loc and loc.sub_destination_id
    task.defer(function()
        BPRegisterWrapper({
            char = petModel, mega_neon = petData.properties.mega_neon or false,
            neon = petData.properties.neon or false,
            player = Players.LocalPlayer, entity_controller = Players.LocalPlayer,
            controller = Players.LocalPlayer, rp_name = petData.properties.rp_name or "",
            pet_trick_level = petData.properties.pet_trick_level or 0,
            pet_unique = petData.unique, pet_id = petData.id,
            location = { full_destination_id = fullDestId, destination_id = destId,
                sub_destination_id = subDestId, house_owner = Players.LocalPlayer },
            pet_progression = {
                age = petData.properties.age or math.random(1, 6),
                xp = petData.properties.xp or 0,
                friendship_level = petData.properties.friendship_level or 1,
                friendship_xp = petData.properties.friendship_xp or 0,
                percentage = math.random(0, 99) / 100,
            },
            are_colors_sealed = false, is_pet = true,
        })
        BPRegisterState({
            char = petModel, player = Players.LocalPlayer,
            store_key = "pet_state_managers",
            is_sitting = false, chars_connected_to_me = {}, states = {},
        })
        task.wait(0.1)
        pcall(function()
            BPUpdateData("pet_char_wrappers", function(ws)
                for _, w in pairs(ws) do
                    if w.pet_unique == petData.unique then w.rp_name = petData.properties.rp_name or "" end
                end
                return ws
            end)
        end)
        task.wait(0.15); if AilmentsClient then pcall(AilmentsClient.on_ailments_changed, Players.LocalPlayer) end
    end)
end

-- Hook RouterClient
local OriginalRouterGet = RouterClient.get
RouterClient.get = function(endpoint)
    if endpoint == "ToolAPI/Equip" then
        return { InvokeServer = function(_, uid, opts)
            local pet = SpawnedPets[uid]
            if not pet then return OriginalRouterGet("ToolAPI/Equip"):InvokeServer(uid, opts) end
            BPEquip(pet.data, opts); return true, { action = "equip", is_server = true }
        end }
    elseif endpoint == "ToolAPI/Unequip" then
        return { InvokeServer = function(_, uid)
            local pet = SpawnedPets[uid]
            if not pet then return OriginalRouterGet("ToolAPI/Unequip"):InvokeServer(uid) end
            BPUnequip(pet.data); return true, { action = "unequip", is_server = true }
        end }
    elseif endpoint == "AdoptAPI/RidePet" then
        return { InvokeServer = function(_, pd)
            local pet = SpawnedPets[pd.pet_unique]
            if not pet then return OriginalRouterGet("AdoptAPI/RidePet"):InvokeServer(pd) end
            BPMount(pd.pet_unique, "PlayerRidingPet", "PetBeingRidden"); return true
        end }
    elseif endpoint == "AdoptAPI/FlyPet" then
        return { InvokeServer = function(_, pd)
            local pet = SpawnedPets[pd.pet_unique]
            if not pet then return OriginalRouterGet("AdoptAPI/FlyPet"):InvokeServer(pd) end
            BPMount(pd.pet_unique, "PlayerFlyingPet", "PetBeingFlown"); return true
        end }
    elseif endpoint == "AdoptAPI/ExitSeatStates" then
        return { FireServer = function()
            if CurrentRideId then BPDismount(); return true end
            return OriginalRouterGet("AdoptAPI/ExitSeatStates"):FireServer()
        end }
    elseif endpoint == "SettingsAPI/SetPetRoleplayName" then
        return { InvokeServer = function(_, uid, name)
            local pet = SpawnedPets[uid]
            if not pet then return OriginalRouterGet("SettingsAPI/SetPetRoleplayName"):InvokeServer(uid, name) end
            pcall(function() setthreadidentity(2) end)
            local inv = ClientData.get("inventory")
            if inv and inv.pets and inv.pets[uid] then inv.pets[uid].properties.rp_name = name end
            if pet.data then pet.data.properties.rp_name = name end
            pcall(function() setthreadidentity(8) end)
            BPUpdateData("pet_char_wrappers", function(ws)
                for _, w in pairs(ws) do if w.pet_unique == uid then w.rp_name = name end end
                return ws
            end)
            return true
        end }
    else
        return OriginalRouterGet(endpoint)
    end
end

for _, w in pairs(ClientData.get("pet_char_wrappers") or {}) do
    pcall(function() OriginalRouterGet("ToolAPI/Unequip"):InvokeServer(w.pet_unique) end)
end

if EquipPermissions then
    local origCanEquip = EquipPermissions.can_equip_client
    EquipPermissions.can_equip_client = function(item)
        if item and item.unique and SpawnedPets[item.unique] then return true end
        return origCanEquip(item)
    end
end

if ClientToolManager then
    local origCTMEquip = ClientToolManager.equip
    ClientToolManager.equip = function(item, options)
        if item and item.unique and SpawnedPets[item.unique] and SpawnedPets[item.unique].data then
            local full = SpawnedPets[item.unique].data
            for k, v in pairs(full) do if item[k] == nil then item[k] = v end end
        end
        return origCTMEquip(item, options)
    end
end

local origGetServer = ClientData.get_server
ClientData.get_server = function(player, key, ...)
    local data = origGetServer(player, key, ...)
    if key == "ailments_manager" and player == Players.LocalPlayer and AilmentsDB then
        local loc; if InteriorsM then pcall(function() loc = InteriorsM.get_current_location() end) end
        if loc and (loc.destination_id == "Cave" or loc.full_destination_id == "Cave") then return data end
        local ad = {}
        if data then for k, v in pairs(data) do ad[k] = type(v) == "table" and table.clone(v) or v end end
        ad.ailments = ad.ailments or {}
        for uid, info in pairs(SpawnedPets) do
            if info and info.model then
                if PetAilmentsCache[uid] then
                    ad.ailments[uid] = PetAilmentsCache[uid]
                else
                    local types = {}
                    for kind in pairs(AilmentsDB) do
                        if kind ~= "at_work" and kind ~= "mystery" and kind ~= "walking" then
                            table.insert(types, kind)
                        end
                    end
                    local petAilments = {}
                    local used = {}
                    for i = 1, math.min(math.random(2,4), #types) do
                        local ak
                        repeat ak = types[math.random(1, #types)] until not used[ak]
                        used[ak] = true
                        petAilments[HttpService:GenerateGUID(false)] = {
                            components = {}, created_timestamp = os.time(), kind = ak,
                            progress = 0, rate = 0, rate_timestamp = os.time(), sort_order = i * 100,
                        }
                    end
                    PetAilmentsCache[uid] = petAilments
                    ad.ailments[uid] = petAilments
                end
            end
        end
        return ad
    end
    return data
end

-- ============================================================
-- Helpers de spawn
-- ============================================================
local petFlags = { F = false, R = false, N = false, M = false }
local selectedAge = 6
local lastSpawnedUnique = nil

function FindPetKind(petName)
    if not petName or petName == "" then return nil end
    for id, item in pairs(InventoryDB.pets or {}) do
        if item.name and item.name:lower() == petName:lower() then
            return id
        end
    end
    return nil
end

function FindToyKind(toyName)
    if not toyName or toyName == "" then return nil end
    for id, item in pairs(InventoryDB.toys or {}) do
        if item.name and item.name:lower() == toyName:lower() then
            return id
        end
    end
    return nil
end

function FindPetWearKind(wearName)
    if not wearName or wearName == "" then return nil end
    for id, item in pairs(InventoryDB.pet_accessories or {}) do
        if item.name and item.name:lower() == wearName:lower() then
            return id
        end
    end
    return nil
end

function BPCreateInventoryItem(itemId, category, properties)
    local uniqueId = HttpService:GenerateGUID(false)
    local kd = KindDB[itemId]
    if not kd then return nil end
    properties = properties or {}
    local newnessValue
    if category == "pets" then
        local gk = GetPropertyGroup(properties)
        NewnessGroups[gk] = (NewnessGroups[gk] or 990000) - 1
        newnessValue = NewnessGroups[gk]
        if properties.rp_name == nil then properties.rp_name = "" end
        if properties.xp == nil then properties.xp = 0 end
    else
        newnessValue = math.random(1, 900000)
    end
    local itemData = {
        unique = uniqueId,
        category = category,
        id = itemId,
        kind = kd.kind or itemId,
        newness_order = newnessValue,
        properties = properties,
        _source = "yuno_hub",
    }
    pcall(function() setthreadidentity(2) end)
    local inv = ClientData.get("inventory")
    if inv and inv[category] then
        inv[category][uniqueId] = itemData
    end
    pcall(function() setthreadidentity(8) end)
    task.defer(function()
        pcall(function()
            if UIManager and UIManager.apps and UIManager.apps.BackpackApp then
                UIManager.apps.BackpackApp:refresh_rendered_items()
            end
        end)
    end)
    if category == "pets" then
        SpawnedPets[uniqueId] = { data = itemData, model = nil }
        lastSpawnedUnique = uniqueId
    end
    return itemData
end

function SpawnPetByName(petName)
    local kind = FindPetKind(petName)
    if not kind then return nil, "Pet introuvable : " .. petName end
    local props = {
        flyable = petFlags.F,
        rideable = petFlags.R,
        neon = petFlags.N,
        mega_neon = petFlags.M,
        age = selectedAge,
        xp = 0,
        rp_name = "",
    }
    local item = BPCreateInventoryItem(kind, "pets", props)
    if item then
        lastSpawnedUnique = item.unique
        return item, "Spawn : " .. petName
    else
        return nil, "Échec du spawn : " .. petName
    end
end

function SpawnToyByName(toyName)
    local kind = FindToyKind(toyName)
    if not kind then return nil, "Jouet introuvable : " .. toyName end
    local props = {}
    local item = BPCreateInventoryItem(kind, "toys", props)
    if item then
        return item, "Spawn : " .. toyName
    else
        return nil, "Échec du spawn : " .. toyName
    end
end

function SpawnAllVariants(petName)
    local kind = FindPetKind(petName)
    if not kind then return 0, "Pet introuvable" end
    local count = 0
    local variants = {
        { F=true,  R=true,  N=false, M=true  },
        { F=true,  R=true,  N=true,  M=false },
        { F=true,  R=true,  N=false, M=false },
    }
    for i = 1, 2 do
        local f = math.random(0,1) == 1
        local r = math.random(0,1) == 1
        local roll = math.random(1,3)
        table.insert(variants, {F=f, R=r, N=(roll==2), M=(roll==3)})
    end
    for _, v in ipairs(variants) do
        local props = {
            flyable = v.F,
            rideable = v.R,
            neon = v.N,
            mega_neon = v.M,
            age = 6,
            xp = 0,
            rp_name = "",
        }
        BPCreateInventoryItem(kind, "pets", props)
        count = count + 1
    end
    return count, count .. " variantes de " .. petName .. " spawnées"
end

function SpawnRandomHighTier()
    local HIGH_TIER_NAMES = {
        "Bat Dragon", "Shadow Dragon", "Giraffe", "Frost Dragon", "Owl", "Parrot",
        "Balloon Unicorn", "Crow", "African Wild Dog", "Giant Panda", "HaeTae",
        "Cryptid", "Evil Unicorn", "Blazing Lion", "Hedgehog", "Orchid Butterfly",
        "Diamond Butterfly", "Dalmatian", "Arctic Reindeer", "Mini Pig",
        "Jekyll Hydra", "Hot Doggo", "Mermicorn", "Pelican", "Cow",
        "Strawberry Shortcake Bat Dragon", "Goose", "Chocolate Chip Bat Dragon",
        "Cabbit", "Turtle", "Peppermint Penguin", "Monkey King",
        "Undead Jousting Horse", "Flamingo", "Kangaroo"
    }
    local name = HIGH_TIER_NAMES[math.random(1, #HIGH_TIER_NAMES)]
    return SpawnPetByName(name)
end

function SpawnRandomPets(amount)
    amount = amount or 50
    local HIGH_TIER_NAMES = {
        "Bat Dragon", "Shadow Dragon", "Giraffe", "Frost Dragon", "Owl", "Parrot",
        "Balloon Unicorn", "Crow", "African Wild Dog", "Giant Panda", "HaeTae",
        "Cryptid", "Evil Unicorn", "Blazing Lion", "Hedgehog", "Orchid Butterfly",
        "Diamond Butterfly", "Dalmatian", "Arctic Reindeer", "Mini Pig",
        "Jekyll Hydra", "Hot Doggo", "Mermicorn", "Pelican", "Cow",
        "Strawberry Shortcake Bat Dragon", "Goose", "Chocolate Chip Bat Dragon",
        "Cabbit", "Turtle", "Peppermint Penguin", "Monkey King",
        "Undead Jousting Horse", "Flamingo", "Kangaroo"
    }
    local highTierKinds = {}
    for _, name in ipairs(HIGH_TIER_NAMES) do
        local k = FindPetKind(name)
        if k then highTierKinds[k] = true end
    end
    local allKinds = {}
    for id, item in pairs(InventoryDB.pets or {}) do
        if item.name and not highTierKinds[id] then
            table.insert(allKinds, id)
        end
    end
    if #allKinds == 0 then return 0, "Aucun pet trouvé" end
    local count = 0
    for i = 1, amount do
        local kind = allKinds[math.random(1, #allKinds)]
        local props = {
            flyable = petFlags.F,
            rideable = petFlags.R,
            neon = petFlags.N,
            mega_neon = petFlags.M,
            age = selectedAge,
            xp = 0,
            rp_name = "",
        }
        BPCreateInventoryItem(kind, "pets", props)
        count = count + 1
    end
    return count, count .. " pets aléatoires spawnés"
end

-- ============================================================
-- AJOUT VISUEL LOCAL DANS LE TRADE (l'autre joueur ne voit pas)
-- ============================================================
local TradeAppRef = UIManager.apps and UIManager.apps.TradeApp

local function visualAddPetToMyOffer(petName, flags)
    if not TradeAppRef then return false, "TradeApp indisponible" end
    local state
    pcall(function() state = TradeAppRef:_get_local_trade_state() end)
    if not state then return false, "Pas de trade en cours" end
    local myOffer = (state.sender == Players.LocalPlayer) and state.sender_offer or state.recipient_offer
    if not myOffer then return false, "Offre locale indisponible" end
    if #myOffer.items >= 18 then return false, "Offre pleine" end
    local kind = FindPetKind(petName)
    if not kind then return false, "Pet introuvable" end

    local petItem = {
        category = "pets",
        kind = kind,
        unique = "visual_" .. HttpService:GenerateGUID(false),
        properties = {
            flyable   = flags.F or false,
            rideable  = flags.R or false,
            neon      = flags.N or false,
            mega_neon = flags.M or false,
            age       = selectedAge or 6,
            xp        = 0,
            rp_name   = "",
        },
        _visual_only = true,
    }
    table.insert(myOffer.items, petItem)

    -- Reset negotiated state and bump version
    state.sender_offer.negotiated = false
    state.recipient_offer.negotiated = false
    state.offer_version = (state.offer_version or 1) + 1

    -- Refresh UI locally
    pcall(function()
        if TradeAppRef.refresh_all then TradeAppRef:refresh_all() end
    end)
    pcall(function()
        if TradeAppRef._render_message_in_trade_chat then
            TradeAppRef:_render_message_in_trade_chat(nil, "You added " .. petName .. " (visual only).", false)
        end
    end)
    return true, "Ajouté visuellement : " .. petName
end

-- Bloque l'envoi serveur quand l'objet est _visual_only
do
    local AddItemRemote = RouterClient.get and RouterClient.get("TradeAPI/AddItem")
    if AddItemRemote then
        local mt = getrawmetatable(AddItemRemote)
        if mt then
            local oldNamecall = mt.__namecall
            pcall(setreadonly, mt, false)
            mt.__namecall = function(self, ...)
                if self == AddItemRemote and getnamecallmethod() == "FireServer" then
                    local args = {...}
                    local firstArg = args[1]
                    if type(firstArg) == "table" and firstArg._visual_only then
                        return
                    end
                end
                return oldNamecall(self, ...)
            end
            pcall(setreadonly, mt, true)
        end
    end
end

-- ============================================================
-- Système de thèmes (dans le 1er onglet, plus de tab dédiée)
-- ============================================================
local THEMES = {
    Default = {
        bg = Color3.fromRGB(20,20,30),
        titleBg = Color3.fromRGB(40,30,60),
        accent = Color3.fromRGB(108,75,171),
        text = Color3.fromRGB(255,255,255),
        buttonBg = Color3.fromRGB(45,45,65),
        tabActiveBg = Color3.fromRGB(60,50,80),
        tabInactiveBg = Color3.fromRGB(40,40,60),
        stroke = Color3.fromRGB(180,130,255),
    },
    White = {
        bg = Color3.fromRGB(240,240,245),
        titleBg = Color3.fromRGB(210,210,220),
        accent = Color3.fromRGB(140,140,160),
        text = Color3.fromRGB(30,30,40),
        buttonBg = Color3.fromRGB(220,220,230),
        tabActiveBg = Color3.fromRGB(230,230,240),
        tabInactiveBg = Color3.fromRGB(205,205,215),
        stroke = Color3.fromRGB(160,160,180),
    },
    Gold = {
        bg = Color3.fromRGB(30,25,15),
        titleBg = Color3.fromRGB(55,45,25),
        accent = Color3.fromRGB(220,180,90),
        text = Color3.fromRGB(255,250,230),
        buttonBg = Color3.fromRGB(55,48,30),
        tabActiveBg = Color3.fromRGB(75,60,35),
        tabInactiveBg = Color3.fromRGB(45,38,22),
        stroke = Color3.fromRGB(230,190,100),
    },
    "WhiteGold" and WhiteGold = nil, -- placeholder retiré
    Rose = {
        bg = Color3.fromRGB(30,20,25),
        titleBg = Color3.fromRGB(60,30,50),
        accent = Color3.fromRGB(220,100,150),
        text = Color3.fromRGB(255,255,255),
        buttonBg = Color3.fromRGB(55,40,50),
        tabActiveBg = Color3.fromRGB(70,45,60),
        tabInactiveBg = Color3.fromRGB(50,35,45),
        stroke = Color3.fromRGB(255,150,200),
    },
    DarkGold = {
        bg = Color3.fromRGB(10,10,15),
        titleBg = Color3.fromRGB(25,20,15),
        accent = Color3.fromRGB(200,160,80),
        text = Color3.fromRGB(255,255,230),
        buttonBg = Color3.fromRGB(30,28,25),
        tabActiveBg = Color3.fromRGB(45,35,25),
        tabInactiveBg = Color3.fromRGB(30,25,20),
        stroke = Color3.fromRGB(200,160,80),
    },
}
-- Retirer la clé placeholder invalide si elle existe
THEMES["WhiteGold"] = nil

local FONTS = {
    "Gotham", "SourceSans", "FredokaOne", "Roboto", "Arial", "ComicSans", "Bangers", "Lato"
}

local currentTheme = "Default"
local currentFont = "Gotham"

local function applyThemeAndFont(themeName, fontName)
    currentTheme = themeName or currentTheme
    currentFont = fontName or currentFont
    local theme = THEMES[currentTheme]
    if not theme then return end
    local font = Enum.Font[currentFont] or Enum.Font.Gotham

    local function updateDescendants(obj)
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            obj.Font = font
            if obj:IsA("TextButton") or obj:IsA("TextLabel") then
                if obj ~= closeBtn and obj ~= titleLabel then
                    obj.TextColor3 = theme.text
                end
            end
        end
        if obj:IsA("UIStroke") then
            if obj ~= closeBtn then
                obj.Color = theme.stroke
            end
        end
        if obj:IsA("Frame") then
            if obj == mainFrame then
                obj.BackgroundColor3 = theme.bg
            elseif obj == titleBar then
                obj.BackgroundColor3 = theme.titleBg
            elseif obj:IsA("Frame") and obj:FindFirstChild("Layout") then
                if obj.BackgroundTransparency < 1 then
                    obj.BackgroundColor3 = theme.buttonBg
                end
            end
        end
        if obj:IsA("TextButton") and obj ~= closeBtn and obj ~= titleLabel then
            obj.BackgroundColor3 = theme.buttonBg
            obj.TextColor3 = theme.text
        end
        for _, child in ipairs(obj:GetChildren()) do
            updateDescendants(child)
        end
    end

    updateDescendants(mainFrame)

    petsTab.BackgroundColor3 = (currentTab == "Pets") and theme.tabActiveBg or theme.tabInactiveBg
    petsTab.TextColor3 = theme.text
    petsStroke.Color = theme.stroke
    toysTab.BackgroundColor3 = (currentTab == "Toys") and theme.tabActiveBg or theme.tabInactiveBg
    toysTab.TextColor3 = theme.text
    toysStroke.Color = theme.stroke

    glow.Color = theme.accent
    titleLabel.TextColor3 = theme.text

    for _, btn in ipairs(themeButtons) do
        btn.BackgroundColor3 = theme.buttonBg
        btn.TextColor3 = theme.text
    end
    fontDropdownBtn.BackgroundColor3 = theme.buttonBg
    fontDropdownBtn.TextColor3 = theme.text
    for _, btn in ipairs(fontOptionButtons) do
        btn.BackgroundColor3 = theme.buttonBg
        btn.TextColor3 = theme.text
    end
end

-- ============================================================
-- GUI
-- ============================================================
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "YunoHub"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 300, 0, 460)
mainFrame.Position = UDim2.new(0.5, -150, 0.5, -230)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = gui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

local glow = Instance.new("UIStroke")
glow.Color = Color3.fromRGB(108, 75, 171)
glow.Thickness = 2
glow.Transparency = 0.4
glow.Parent = mainFrame

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 28)
titleBar.BackgroundColor3 = Color3.fromRGB(40, 30, 60)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10, 0, 0)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -50, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Yuno Hub"
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextColor3 = Color3.fromRGB(255, 220, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 1, 0)
closeBtn.Position = UDim2.new(1, -28, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
closeBtn.Parent = titleBar
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

local dragging = false
local dragStart, startPos
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local delta = input.Position - dragStart
    mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 1, -36)
content.Position = UDim2.new(0, 8, 0, 34)
content.BackgroundTransparency = 1
content.Parent = mainFrame

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 6)
contentLayout.FillDirection = Enum.FillDirection.Vertical
contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
contentLayout.Parent = content

-- ============================================================
-- Onglets : Pets / Toys uniquement
-- ============================================================
local tabContainer = Instance.new("Frame")
tabContainer.Size = UDim2.new(1, 0, 0, 28)
tabContainer.BackgroundTransparency = 1
tabContainer.LayoutOrder = 0
tabContainer.Parent = content

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 6)
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.Parent = tabContainer

local petsTab = Instance.new("TextButton")
petsTab.Size = UDim2.new(0, 70, 1, 0)
petsTab.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
petsTab.Text = "Pets"
petsTab.Font = Enum.Font.GothamBold
petsTab.TextSize = 12
petsTab.TextColor3 = Color3.fromRGB(255, 255, 255)
petsTab.Parent = tabContainer
Instance.new("UICorner", petsTab).CornerRadius = UDim.new(0, 6)
local petsStroke = Instance.new("UIStroke")
petsStroke.Color = Color3.fromRGB(180, 130, 255)
petsStroke.Thickness = 1.5
petsStroke.Transparency = 0.2
petsStroke.Parent = petsTab

local toysTab = Instance.new("TextButton")
toysTab.Size = UDim2.new(0, 70, 1, 0)
toysTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
toysTab.Text = "Toys"
toysTab.Font = Enum.Font.GothamBold
toysTab.TextSize = 12
toysTab.TextColor3 = Color3.fromRGB(255, 255, 255)
toysTab.Parent = tabContainer
Instance.new("UICorner", toysTab).CornerRadius = UDim.new(0, 6)
local toysStroke = Instance.new("UIStroke")
toysStroke.Color = Color3.fromRGB(180, 130, 255)
toysStroke.Thickness = 1.5
toysStroke.Transparency = 0.6
toysStroke.Parent = toysTab

-- ============================================================
-- Panel Pets (avec ScrollingFrame pour les thèmes)
-- ============================================================
local petsPanel = Instance.new("ScrollingFrame")
petsPanel.Size = UDim2.new(1, 0, 1, -28)
petsPanel.BackgroundTransparency = 1
petsPanel.BorderSizePixel = 0
petsPanel.ScrollBarThickness = 3
petsPanel.ScrollBarImageColor3 = Color3.fromRGB(120, 90, 200)
petsPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
petsPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
petsPanel.ScrollingDirection = Enum.ScrollingDirection.Y
petsPanel.LayoutOrder = 1
petsPanel.Visible = true
petsPanel.Parent = content

local petsLayout = Instance.new("UIListLayout")
petsLayout.SortOrder = Enum.SortOrder.LayoutOrder
petsLayout.Padding = UDim.new(0, 5)
petsLayout.Parent = petsPanel

local petsPad = Instance.new("UIPadding")
petsPad.PaddingTop = UDim.new(0, 2)
petsPad.PaddingBottom = UDim.new(0, 10)
petsPad.PaddingLeft = UDim.new(0, 4)
petsPad.PaddingRight = UDim.new(0, 6)
petsPad.Parent = petsPanel

local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, 0, 0, 26)
nameBox.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
nameBox.Text = ""
nameBox.PlaceholderText = "Nom du pet..."
nameBox.Font = Enum.Font.SourceSans
nameBox.TextSize = 12
nameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
nameBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 160)
nameBox.ClearTextOnFocus = false
nameBox.TextXAlignment = Enum.TextXAlignment.Left
nameBox.LayoutOrder = 0
nameBox.Parent = petsPanel
Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 6)
local namePad = Instance.new("UIPadding")
namePad.PaddingLeft = UDim.new(0, 10)
namePad.PaddingRight = UDim.new(0, 10)
namePad.Parent = nameBox
local nameGlow = Instance.new("UIStroke")
nameGlow.Color = Color3.fromRGB(100, 100, 180)
nameGlow.Thickness = 1.5
nameGlow.Transparency = 0.3
nameGlow.Parent = nameBox

local flagsRow = Instance.new("Frame")
flagsRow.Size = UDim2.new(1, 0, 0, 28)
flagsRow.BackgroundTransparency = 1
flagsRow.LayoutOrder = 1
flagsRow.Parent = petsPanel
local flagsLayout = Instance.new("UIListLayout")
flagsLayout.FillDirection = Enum.FillDirection.Horizontal
flagsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
flagsLayout.Padding = UDim.new(0, 6)
flagsLayout.Parent = flagsRow

local flagDefs = {
    { key="F", label="Fly",  off=Color3.fromRGB(30,30,45), on=Color3.fromRGB(60,120,255) },
    { key="R", label="Ride", off=Color3.fromRGB(30,30,45), on=Color3.fromRGB(255,80,80) },
    { key="N", label="Neon", off=Color3.fromRGB(30,30,45), on=Color3.fromRGB(40,220,120) },
    { key="M", label="Mega", off=Color3.fromRGB(30,30,45), on=Color3.fromRGB(180,60,255) },
}
local flagButtons = {}
for _, def in ipairs(flagDefs) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 40, 1, 0)
    btn.BackgroundColor3 = def.off
    btn.Text = def.label
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = Color3.fromRGB(150, 150, 180)
    btn.Parent = flagsRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = Color3.fromRGB(80, 80, 120)
    stroke.Thickness = 1
    stroke.Parent = btn
    flagButtons[def.key] = { btn = btn, stroke = stroke, def = def }
    btn.MouseButton1Click:Connect(function()
        local k = def.key
        if k == "M" and not petFlags.M then petFlags.N = false end
        if k == "N" and not petFlags.N then petFlags.M = false end
        petFlags[k] = not petFlags[k]
        for key, ref in pairs(flagButtons) do
            local on = petFlags[key]
            ref.btn.BackgroundColor3 = on and ref.def.on or ref.def.off
            ref.btn.TextColor3 = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,150,180)
            ref.stroke.Color = on and ref.def.on or Color3.fromRGB(80,80,120)
        end
    end)
end

local ageRow = Instance.new("Frame")
ageRow.Size = UDim2.new(1, 0, 0, 24)
ageRow.BackgroundTransparency = 1
ageRow.LayoutOrder = 2
ageRow.Parent = petsPanel
local ageLayout = Instance.new("UIListLayout")
ageLayout.FillDirection = Enum.FillDirection.Horizontal
ageLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
ageLayout.Padding = UDim.new(0, 4)
ageLayout.Parent = ageRow

local ageLabels = { "NB", "Jr", "PT", "T", "PoT", "FG" }
local ageValues = { 1, 2, 3, 4, 5, 6 }
local ageButtons = {}
for i, label in ipairs(ageLabels) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 28, 1, 0)
    btn.BackgroundColor3 = (selectedAge == ageValues[i]) and Color3.fromRGB(80, 50, 130) or Color3.fromRGB(35,35,50)
    btn.Text = label
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.TextColor3 = (selectedAge == ageValues[i]) and Color3.fromRGB(255,255,255) or Color3.fromRGB(160,160,180)
    btn.Parent = ageRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = (selectedAge == ageValues[i]) and Color3.fromRGB(160,100,220) or Color3.fromRGB(80,80,120)
    stroke.Thickness = 1
    stroke.Parent = btn
    local val = ageValues[i]
    btn.MouseButton1Click:Connect(function()
        selectedAge = val
        for idx, ref in ipairs(ageButtons) do
            local on = ref.value == selectedAge
            ref.btn.BackgroundColor3 = on and Color3.fromRGB(80,50,130) or Color3.fromRGB(35,35,50)
            ref.btn.TextColor3 = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(160,160,180)
            ref.stroke.Color = on and Color3.fromRGB(160,100,220) or Color3.fromRGB(80,80,120)
        end
    end)
    table.insert(ageButtons, { btn = btn, stroke = stroke, value = val })
end

local spawnRow = Instance.new("Frame")
spawnRow.Size = UDim2.new(1, 0, 0, 26)
spawnRow.BackgroundTransparency = 1
spawnRow.LayoutOrder = 3
spawnRow.Parent = petsPanel
local srLayout = Instance.new("UIListLayout")
srLayout.FillDirection = Enum.FillDirection.Horizontal
srLayout.Padding = UDim.new(0, 5)
srLayout.SortOrder = Enum.SortOrder.LayoutOrder
srLayout.Parent = spawnRow

local function makeBtn(text, color, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.48, 0, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    btn.Text = text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.LayoutOrder = order
    btn.Parent = spawnRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = color or Color3.fromRGB(140, 100, 220)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.3
    stroke.Parent = btn
    return btn
end

local spawnBtn = makeBtn("Spawn Pet", Color3.fromRGB(80, 180, 255), 1)
local highBtn = makeBtn("High Tier", Color3.fromRGB(255, 200, 80), 2)

spawnBtn.MouseButton1Click:Connect(function()
    local name = nameBox.Text
    if name == "" then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Entre un nom de pet.", Duration = 3})
        return
    end
    local item, msg = SpawnPetByName(name)
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = msg, Duration = 3})
end)

highBtn.MouseButton1Click:Connect(function()
    local item, msg = SpawnRandomHighTier()
    if item then nameBox.Text = item.kind end
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = msg, Duration = 3})
end)

local varBtn = Instance.new("TextButton")
varBtn.Size = UDim2.new(1, 0, 0, 24)
varBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
varBtn.Text = "Spawn All Variants"
varBtn.Font = Enum.Font.GothamBold
varBtn.TextSize = 10
varBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
varBtn.LayoutOrder = 4
varBtn.Parent = petsPanel
Instance.new("UICorner", varBtn).CornerRadius = UDim.new(0, 6)
local vStroke = Instance.new("UIStroke")
vStroke.Color = Color3.fromRGB(60, 200, 100)
vStroke.Thickness = 1.5
vStroke.Transparency = 0.3
vStroke.Parent = varBtn
varBtn.MouseButton1Click:Connect(function()
    local name = nameBox.Text
    if name == "" then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Entre un nom de pet.", Duration = 3})
        return
    end
    local count, msg = SpawnAllVariants(name)
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = msg, Duration = 3})
end)

local randBtn = Instance.new("TextButton")
randBtn.Size = UDim2.new(1, 0, 0, 24)
randBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
randBtn.Text = "Spawn 50 Random Pets"
randBtn.Font = Enum.Font.GothamBold
randBtn.TextSize = 10
randBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
randBtn.LayoutOrder = 5
randBtn.Parent = petsPanel
Instance.new("UICorner", randBtn).CornerRadius = UDim.new(0, 6)
local rStroke = Instance.new("UIStroke")
rStroke.Color = Color3.fromRGB(80, 180, 255)
rStroke.Thickness = 1.5
rStroke.Transparency = 0.3
rStroke.Parent = randBtn
randBtn.MouseButton1Click:Connect(function()
    local count, msg = SpawnRandomPets(50)
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = msg, Duration = 3})
end)

-- ============================================================
-- Séparateur + Section Contrôles
-- ============================================================
local function makeSectionLabel(text, order)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextColor3 = Color3.fromRGB(200, 180, 255)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = order
    lbl.Parent = petsPanel
    return lbl
end

makeSectionLabel("🐾 Contrôles du pet", 6)

local controlsPanel = Instance.new("Frame")
controlsPanel.Size = UDim2.new(1, 0, 0, 110)
controlsPanel.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
controlsPanel.BackgroundTransparency = 0.2
controlsPanel.LayoutOrder = 7
controlsPanel.Parent = petsPanel
Instance.new("UICorner", controlsPanel).CornerRadius = UDim.new(0, 6)
local cpStroke = Instance.new("UIStroke")
cpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
cpStroke.Color = Color3.fromRGB(160, 100, 220)
cpStroke.Thickness = 1
cpStroke.Transparency = 0.3
cpStroke.Parent = controlsPanel

local cpLayout = Instance.new("UIListLayout")
cpLayout.SortOrder = Enum.SortOrder.LayoutOrder
cpLayout.Padding = UDim.new(0, 4)
cpLayout.Parent = controlsPanel

local equipInfo = Instance.new("TextLabel")
equipInfo.Size = UDim2.new(1, 0, 0, 16)
equipInfo.BackgroundTransparency = 1
equipInfo.Text = "Aucun pet équipé"
equipInfo.Font = Enum.Font.GothamBold
equipInfo.TextSize = 10
equipInfo.TextColor3 = Color3.fromRGB(200, 200, 220)
equipInfo.TextXAlignment = Enum.TextXAlignment.Center
equipInfo.LayoutOrder = 0
equipInfo.Parent = controlsPanel

local ctrlRow = Instance.new("Frame")
ctrlRow.Size = UDim2.new(1, 0, 0, 22)
ctrlRow.BackgroundTransparency = 1
ctrlRow.LayoutOrder = 1
ctrlRow.Parent = controlsPanel
local crLayout = Instance.new("UIListLayout")
crLayout.FillDirection = Enum.FillDirection.Horizontal
crLayout.Padding = UDim.new(0, 4)
crLayout.SortOrder = Enum.SortOrder.LayoutOrder
crLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
crLayout.Parent = ctrlRow

local function makeCtrlBtn(text, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 50, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    btn.Text = text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.LayoutOrder = order
    btn.Parent = ctrlRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = Color3.fromRGB(160, 100, 220)
    stroke.Thickness = 1
    stroke.Transparency = 0.3
    stroke.Parent = btn
    return btn
end

local equipBtn = makeCtrlBtn("Équiper", 1)
local rideBtn = makeCtrlBtn("Ride", 2)
local flyBtn = makeCtrlBtn("Fly", 3)
local unequipBtn = makeCtrlBtn("Retirer", 4)

local renameRow = Instance.new("Frame")
renameRow.Size = UDim2.new(1, 0, 0, 22)
renameRow.BackgroundTransparency = 1
renameRow.LayoutOrder = 2
renameRow.Parent = controlsPanel
local rrLayout = Instance.new("UIListLayout")
rrLayout.FillDirection = Enum.FillDirection.Horizontal
rrLayout.Padding = UDim.new(0, 4)
rrLayout.SortOrder = Enum.SortOrder.LayoutOrder
rrLayout.Parent = renameRow

local renameBox = Instance.new("TextBox")
renameBox.Size = UDim2.new(0.6, 0, 1, 0)
renameBox.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
renameBox.Text = ""
renameBox.PlaceholderText = "Nouveau nom..."
renameBox.Font = Enum.Font.SourceSans
renameBox.TextSize = 10
renameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
renameBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 160)
renameBox.ClearTextOnFocus = false
renameBox.TextXAlignment = Enum.TextXAlignment.Left
renameBox.LayoutOrder = 1
renameBox.Parent = renameRow
Instance.new("UICorner", renameBox).CornerRadius = UDim.new(0, 4)
local rPad = Instance.new("UIPadding")
rPad.PaddingLeft = UDim.new(0, 6)
rPad.PaddingRight = UDim.new(0, 6)
rPad.Parent = renameBox

local renameBtn = Instance.new("TextButton")
renameBtn.Size = UDim2.new(0.35, 0, 1, 0)
renameBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
renameBtn.Text = "Renommer"
renameBtn.Font = Enum.Font.GothamBold
renameBtn.TextSize = 9
renameBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
renameBtn.LayoutOrder = 2
renameBtn.Parent = renameRow
Instance.new("UICorner", renameBtn).CornerRadius = UDim.new(0, 4)
local rStroke = Instance.new("UIStroke")
rStroke.Color = Color3.fromRGB(160, 100, 220)
rStroke.Thickness = 1
rStroke.Transparency = 0.3
rStroke.Parent = renameBtn

local function updatePetControls(item)
    if item and item.unique and SpawnedPets[item.unique] then
        equipInfo.Text = "Équipé : " .. (item.kind or "Inconnu")
    else
        equipInfo.Text = "Aucun pet équipé"
    end
end

equipBtn.MouseButton1Click:Connect(function()
    if not lastSpawnedUnique then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Aucun pet spawn.", Duration = 3})
        return
    end
    local petData = ClientData.get("inventory").pets[lastSpawnedUnique]
    if not petData then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Pet introuvable dans l'inventaire.", Duration = 3})
        return
    end
    BPEquip(petData)
    updatePetControls(petData)
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Équipé " .. (petData.kind or "pet"), Duration = 3})
end)

rideBtn.MouseButton1Click:Connect(function()
    if not EquippedPet then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Aucun pet équipé.", Duration = 3})
        return
    end
    if not EquippedPet.properties.rideable then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Ce pet n'est pas montable.", Duration = 3})
        return
    end
    BPMount(EquippedPet.unique, "PlayerRidingPet", "PetBeingRidden")
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "En train de monter le pet.", Duration = 2})
end)

flyBtn.MouseButton1Click:Connect(function()
    if not EquippedPet then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Aucun pet équipé.", Duration = 3})
        return
    end
    if not EquippedPet.properties.flyable then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Ce pet n'est pas volable.", Duration = 3})
        return
    end
    BPMount(EquippedPet.unique, "PlayerFlyingPet", "PetBeingFlown")
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "En train de voler.", Duration = 2})
end)

unequipBtn.MouseButton1Click:Connect(function()
    if not EquippedPet then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Aucun pet équipé.", Duration = 3})
        return
    end
    BPUnequip(EquippedPet)
    updatePetControls(nil)
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Pet retiré.", Duration = 2})
end)

renameBtn.MouseButton1Click:Connect(function()
    if not EquippedPet then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Aucun pet équipé.", Duration = 3})
        return
    end
    local newName = renameBox.Text
    if newName == "" then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Entre un nom.", Duration = 3})
        return
    end
    local success, err = pcall(function()
        RouterClient.get("SettingsAPI/SetPetRoleplayName"):InvokeServer(EquippedPet.unique, newName)
    end)
    if success then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Pet renommé en " .. newName, Duration = 3})
        renameBox.Text = ""
    else
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Échec du renommage : " .. tostring(err), Duration = 3})
    end
end)

-- ============================================================
-- Section Pet Wear
-- ============================================================
makeSectionLabel("🪄 Pet Wear", 8)

local wearRow = Instance.new("Frame")
wearRow.Size = UDim2.new(1, 0, 0, 26)
wearRow.BackgroundTransparency = 1
wearRow.LayoutOrder = 9
wearRow.Parent = petsPanel
local wearRowLayout = Instance.new("UIListLayout")
wearRowLayout.FillDirection = Enum.FillDirection.Horizontal
wearRowLayout.Padding = UDim.new(0, 5)
wearRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
wearRowLayout.Parent = wearRow

local wearBox = Instance.new("TextBox")
wearBox.Size = UDim2.new(0.65, 0, 1, 0)
wearBox.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
wearBox.Text = ""
wearBox.PlaceholderText = "Nom du pet wear..."
wearBox.Font = Enum.Font.SourceSans
wearBox.TextSize = 11
wearBox.TextColor3 = Color3.fromRGB(255, 255, 255)
wearBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 160)
wearBox.ClearTextOnFocus = false
wearBox.TextXAlignment = Enum.TextXAlignment.Left
wearBox.LayoutOrder = 1
wearBox.Parent = wearRow
Instance.new("UICorner", wearBox).CornerRadius = UDim.new(0, 6)
local wPad = Instance.new("UIPadding")
wPad.PaddingLeft = UDim.new(0, 8)
wPad.PaddingRight = UDim.new(0, 8)
wPad.Parent = wearBox
local wGlow = Instance.new("UIStroke")
wGlow.Color = Color3.fromRGB(220, 180, 255)
wGlow.Thickness = 1.5
wGlow.Transparency = 0.3
wGlow.Parent = wearBox

local wearEquipBtn = Instance.new("TextButton")
wearEquipBtn.Size = UDim2.new(0.33, 0, 1, 0)
wearEquipBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
wearEquipBtn.Text = "Ajouter"
wearEquipBtn.Font = Enum.Font.GothamBold
wearEquipBtn.TextSize = 10
wearEquipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
wearEquipBtn.LayoutOrder = 2
wearEquipBtn.Parent = wearRow
Instance.new("UICorner", wearEquipBtn).CornerRadius = UDim.new(0, 6)
local weStroke = Instance.new("UIStroke")
weStroke.Color = Color3.fromRGB(220, 180, 255)
weStroke.Thickness = 1.5
weStroke.Transparency = 0.3
weStroke.Parent = wearEquipBtn

local function equipPetWear(wearName)
    if not EquippedPet then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Équipe un pet d'abord.", Duration = 3})
        return
    end
    local wearId = FindPetWearKind(wearName)
    if not wearId then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Pet wear introuvable : " .. wearName, Duration = 3})
        return
    end
    task.spawn(function()
        pcall(setthreadidentity, 2)
        local PAEquip = load("PetAccessoryEquipHelper")
        local DL = load("DownloadClient")
        local wearEntry = InventoryDB.pet_accessories and InventoryDB.pet_accessories[wearId]
        if not wearEntry then
            game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Entrée pet wear manquante.", Duration = 3})
            pcall(setthreadidentity, 8)
            return
        end
        local petEntry = SpawnedPets[EquippedPet.unique]
        local petModel = petEntry and petEntry.model
        if not petModel then
            game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Modèle du pet introuvable.", Duration = 3})
            pcall(setthreadidentity, 8)
            return
        end
        local ok, accessoryAsset = pcall(function()
            return DL.promise_download_copy("PetAvatarResources", wearEntry.model_handle):expect()
        end)
        if not ok or not accessoryAsset then
            game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Échec du téléchargement.", Duration = 3})
            pcall(setthreadidentity, 8)
            return
        end
        local success, result = pcall(function()
            return PAEquip.equip_accessory({
                pet_model            = petModel,
                accessory_base_asset = accessoryAsset,
                accessory_item_entry = wearEntry,
                play_poof_effect     = true,
                is_mannequin         = false,
            })
        end)
        pcall(setthreadidentity, 8)
        if success and result then
            game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = wearName .. " équipé sur le pet !", Duration = 4})
        else
            game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Échec de l'équipement.", Duration = 3})
        end
    end)
end

wearEquipBtn.MouseButton1Click:Connect(function()
    local wearName = wearBox.Text
    if wearName == "" then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Entre un nom de pet wear.", Duration = 3})
        return
    end
    equipPetWear(wearName)
end)

-- ============================================================
-- Ajout visuel dans un trade
-- ============================================================
makeSectionLabel("🎭 Ajout visuel dans le trade", 10)

local visualRow = Instance.new("Frame")
visualRow.Size = UDim2.new(1, 0, 0, 26)
visualRow.BackgroundTransparency = 1
visualRow.LayoutOrder = 11
visualRow.Parent = petsPanel
local visualLayout = Instance.new("UIListLayout")
visualLayout.FillDirection = Enum.FillDirection.Horizontal
visualLayout.Padding = UDim.new(0, 5)
visualLayout.SortOrder = Enum.SortOrder.LayoutOrder
visualLayout.Parent = visualRow

local visualPetBox = Instance.new("TextBox")
visualPetBox.Size = UDim2.new(0.65, 0, 1, 0)
visualPetBox.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
visualPetBox.Text = ""
visualPetBox.PlaceholderText = "Nom du pet..."
visualPetBox.Font = Enum.Font.SourceSans
visualPetBox.TextSize = 11
visualPetBox.TextColor3 = Color3.fromRGB(255, 255, 255)
visualPetBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 160)
visualPetBox.ClearTextOnFocus = false
visualPetBox.TextXAlignment = Enum.TextXAlignment.Left
visualPetBox.LayoutOrder = 1
visualPetBox.Parent = visualRow
Instance.new("UICorner", visualPetBox).CornerRadius = UDim.new(0, 6)
local vpPad = Instance.new("UIPadding")
vpPad.PaddingLeft = UDim.new(0, 8)
vpPad.PaddingRight = UDim.new(0, 8)
vpPad.Parent = visualPetBox
local vpGlow = Instance.new("UIStroke")
vpGlow.Color = Color3.fromRGB(80, 200, 255)
vpGlow.Thickness = 1.5
vpGlow.Transparency = 0.3
vpGlow.Parent = visualPetBox

local visualBtn = Instance.new("TextButton")
visualBtn.Size = UDim2.new(0.33, 0, 1, 0)
visualBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
visualBtn.Text = "Ajouter"
visualBtn.Font = Enum.Font.GothamBold
visualBtn.TextSize = 10
visualBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
visualBtn.LayoutOrder = 2
visualBtn.Parent = visualRow
Instance.new("UICorner", visualBtn).CornerRadius = UDim.new(0, 6)
local vbStroke = Instance.new("UIStroke")
vbStroke.Color = Color3.fromRGB(80, 200, 255)
vbStroke.Thickness = 1.5
vbStroke.Transparency = 0.3
vbStroke.Parent = visualBtn

visualBtn.MouseButton1Click:Connect(function()
    local name = visualPetBox.Text
    if name == "" then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Entre un nom de pet.", Duration = 3})
        return
    end
    local ok, msg = visualAddPetToMyOffer(name, {
        F = petFlags.F, R = petFlags.R, N = petFlags.N, M = petFlags.M,
    })
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = tostring(msg), Duration = 3})
end)

-- ============================================================
-- Section Thèmes (scroll dans le 1er onglet)
-- ============================================================
makeSectionLabel("🎨 Thèmes", 12)

local themeRow = Instance.new("Frame")
themeRow.Size = UDim2.new(1, 0, 0, 30)
themeRow.BackgroundTransparency = 1
themeRow.LayoutOrder = 13
themeRow.Parent = petsPanel
local themeRowLayout = Instance.new("UIListLayout")
themeRowLayout.FillDirection = Enum.FillDirection.Horizontal
themeRowLayout.Padding = UDim.new(0, 6)
themeRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
themeRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
themeRowLayout.Parent = themeRow

local themeButtons = {}
for _, themeName in ipairs({"Default", "White", "Gold", "Rose", "DarkGold"}) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 55, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    btn.Text = themeName
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Parent = themeRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(160, 100, 220)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.3
    stroke.Parent = btn
    table.insert(themeButtons, btn)
    btn.MouseButton1Click:Connect(function()
        applyThemeAndFont(themeName, currentFont)
    end)
end

-- Section police
makeSectionLabel("✒️ Police", 14)

local fontDropdownBtn = Instance.new("TextButton")
fontDropdownBtn.Size = UDim2.new(0.6, 0, 0, 26)
fontDropdownBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
fontDropdownBtn.Text = currentFont
fontDropdownBtn.Font = Enum.Font.GothamBold
fontDropdownBtn.TextSize = 11
fontDropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
fontDropdownBtn.LayoutOrder = 15
fontDropdownBtn.Parent = petsPanel
Instance.new("UICorner", fontDropdownBtn).CornerRadius = UDim.new(0, 6)
local fdStroke = Instance.new("UIStroke")
fdStroke.Color = Color3.fromRGB(160, 100, 220)
fdStroke.Thickness = 1.5
fdStroke.Transparency = 0.3
fdStroke.Parent = fontDropdownBtn

local fontListFrame = Instance.new("Frame")
fontListFrame.Size = UDim2.new(0.6, 0, 0, 120)
fontListFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
fontListFrame.BorderSizePixel = 0
fontListFrame.Visible = false
fontListFrame.LayoutOrder = 16
fontListFrame.Parent = petsPanel
Instance.new("UICorner", fontListFrame).CornerRadius = UDim.new(0, 6)
local flStroke = Instance.new("UIStroke")
flStroke.Color = Color3.fromRGB(160, 100, 220)
flStroke.Thickness = 1
flStroke.Transparency = 0.3
flStroke.Parent = fontListFrame

local fontScroll = Instance.new("ScrollingFrame")
fontScroll.Size = UDim2.new(1, -4, 1, -4)
fontScroll.Position = UDim2.new(0, 2, 0, 2)
fontScroll.BackgroundTransparency = 1
fontScroll.BorderSizePixel = 0
fontScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
fontScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
fontScroll.ScrollBarThickness = 3
fontScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
fontScroll.Parent = fontListFrame
local flLayout = Instance.new("UIListLayout")
flLayout.SortOrder = Enum.SortOrder.LayoutOrder
flLayout.Padding = UDim.new(0, 2)
flLayout.Parent = fontScroll

local fontOptionButtons = {}
for _, fontName in ipairs(FONTS) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 20)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    btn.Text = fontName
    btn.Font = Enum.Font[fontName] or Enum.Font.Gotham
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Parent = fontScroll
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    local st = Instance.new("UIStroke")
    st.Color = Color3.fromRGB(160, 100, 220)
    st.Thickness = 1
    st.Transparency = 0.5
    st.Parent = btn
    table.insert(fontOptionButtons, btn)
    btn.MouseButton1Click:Connect(function()
        currentFont = fontName
        applyThemeAndFont(currentTheme, currentFont)
        fontDropdownBtn.Text = currentFont
        fontListFrame.Visible = false
    end)
end

fontDropdownBtn.MouseButton1Click:Connect(function()
    fontListFrame.Visible = not fontListFrame.Visible
end)

-- ============================================================
-- Panel Toys
-- ============================================================
local toysPanel = Instance.new("Frame")
toysPanel.Size = UDim2.new(1, 0, 1, -28)
toysPanel.BackgroundTransparency = 1
toysPanel.LayoutOrder = 2
toysPanel.Visible = false
toysPanel.Parent = content

local toysLayout = Instance.new("UIListLayout")
toysLayout.SortOrder = Enum.SortOrder.LayoutOrder
toysLayout.Padding = UDim.new(0, 6)
toysLayout.Parent = toysPanel

local toysPad = Instance.new("UIPadding")
toysPad.PaddingTop = UDim.new(0, 6)
toysPad.PaddingLeft = UDim.new(0, 6)
toysPad.PaddingRight = UDim.new(0, 8)
toysPad.Parent = toysPanel

local toysTitle = Instance.new("TextLabel")
toysTitle.Size = UDim2.new(1, 0, 0, 20)
toysTitle.BackgroundTransparency = 1
toysTitle.Text = "🪀 Toys"
toysTitle.Font = Enum.Font.GothamBold
toysTitle.TextSize = 13
toysTitle.TextColor3 = Color3.fromRGB(220, 200, 255)
toysTitle.TextXAlignment = Enum.TextXAlignment.Left
toysTitle.LayoutOrder = 0
toysTitle.Parent = toysPanel

local toyNameBox = Instance.new("TextBox")
toyNameBox.Size = UDim2.new(1, 0, 0, 26)
toyNameBox.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
toyNameBox.Text = ""
toyNameBox.PlaceholderText = "Nom du jouet..."
toyNameBox.Font = Enum.Font.SourceSans
toyNameBox.TextSize = 12
toyNameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
toyNameBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 160)
toyNameBox.ClearTextOnFocus = false
toyNameBox.TextXAlignment = Enum.TextXAlignment.Left
toyNameBox.LayoutOrder = 1
toyNameBox.Parent = toysPanel
Instance.new("UICorner", toyNameBox).CornerRadius = UDim.new(0, 6)
local tPad = Instance.new("UIPadding")
tPad.PaddingLeft = UDim.new(0, 10)
tPad.PaddingRight = UDim.new(0, 10)
tPad.Parent = toyNameBox
local tGlow = Instance.new("UIStroke")
tGlow.Color = Color3.fromRGB(100, 100, 180)
tGlow.Thickness = 1.5
tGlow.Transparency = 0.3
tGlow.Parent = toyNameBox

local toySpawnBtn = Instance.new("TextButton")
toySpawnBtn.Size = UDim2.new(1, 0, 0, 26)
toySpawnBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
toySpawnBtn.Text = "Spawn Toy"
toySpawnBtn.Font = Enum.Font.GothamBold
toySpawnBtn.TextSize = 12
toySpawnBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toySpawnBtn.LayoutOrder = 2
toySpawnBtn.Parent = toysPanel
Instance.new("UICorner", toySpawnBtn).CornerRadius = UDim.new(0, 6)
local tsStroke = Instance.new("UIStroke")
tsStroke.Color = Color3.fromRGB(140, 100, 220)
tsStroke.Thickness = 1.5
tsStroke.Transparency = 0.3
tsStroke.Parent = toySpawnBtn

toySpawnBtn.MouseButton1Click:Connect(function()
    local name = toyNameBox.Text
    if name == "" then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Entre un nom de jouet.", Duration = 3})
        return
    end
    local item, msg = SpawnToyByName(name)
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = msg, Duration = 3})
end)

-- ============================================================
-- Commutation des onglets
-- ============================================================
local currentTab = "Pets"
local function switchTab(tab)
    currentTab = tab
    if tab == "Pets" then
        petsPanel.Visible = true
        toysPanel.Visible = false
        petsTab.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
        petsStroke.Transparency = 0.2
        toysTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        toysStroke.Transparency = 0.6
    else
        petsPanel.Visible = false
        toysPanel.Visible = true
        petsTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        petsStroke.Transparency = 0.6
        toysTab.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
        toysStroke.Transparency = 0.2
    end
    applyThemeAndFont(currentTheme, currentFont)
end

petsTab.MouseButton1Click:Connect(function() switchTab("Pets") end)
toysTab.MouseButton1Click:Connect(function() switchTab("Toys") end)

switchTab("Pets")
applyThemeAndFont("Default", "Gotham")

print("Yuno Hub chargé avec succès !")
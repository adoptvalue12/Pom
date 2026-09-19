-- ============================================================
-- Yuno Hub - Complete Pet Spawner + Engine
-- Equip, Ride, Fly, Rename, Neon, Mega, Ailments (fake quests)
-- Polished UI with draggable title bar.
-- Theme Tab with color schemes and font selection.
-- FIX: Layout - panels now stack correctly; tabs switch properly.
-- ============================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

pcall(function() setthreadidentity(2) end)

-- ============================================================
-- Module Loading
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
    error("Required modules not loaded (ClientData, InventoryDB, KindDB)")
end

-- ============================================================
-- Anti‑Stack
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
-- Pet Engine (from MockTrade.lua PETS TAB)
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

-- Neon / Mega visual helpers
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

-- ClientData update helpers
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
    -- Unequip any existing server-side pets
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

-- Unequip existing pets on load
for _, w in pairs(ClientData.get("pet_char_wrappers") or {}) do
    pcall(function() OriginalRouterGet("ToolAPI/Unequip"):InvokeServer(w.pet_unique) end)
end

-- EquipPermissions: allow equipping our spawned pets
if EquipPermissions then
    local origCanEquip = EquipPermissions.can_equip_client
    EquipPermissions.can_equip_client = function(item)
        if item and item.unique and SpawnedPets[item.unique] then return true end
        return origCanEquip(item)
    end
end

-- ClientToolManager: fill missing fields
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

-- ailments_manager hook for fake quests
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
-- Spawn Helpers (Pet and Toy)
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
    if not kind then return nil, "Pet not found: " .. petName end
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
        return item, "Spawned " .. petName
    else
        return nil, "Failed to spawn " .. petName
    end
end

function SpawnToyByName(toyName)
    local kind = FindToyKind(toyName)
    if not kind then return nil, "Toy not found: " .. toyName end
    local props = {}
    local item = BPCreateInventoryItem(kind, "toys", props)
    if item then
        return item, "Spawned " .. toyName
    else
        return nil, "Failed to spawn " .. toyName
    end
end

function SpawnAllVariants(petName)
    local kind = FindPetKind(petName)
    if not kind then return 0, "Pet not found" end
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
    return count, "Spawned " .. count .. " variants of " .. petName
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
    if #allKinds == 0 then return 0, "No non-high-tier pets found" end
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
    return count, "Spawned " .. count .. " random pets"
end

-- ============================================================
-- Theme & Font System
-- ============================================================
local THEMES = {
    Default = {
        bg = Color3.fromRGB(20,20,30),
        titleBg = Color3.fromRGB(40,30,60),
        accent = Color3.fromRGB(108,75,171),
        text = Color3.fromRGB(255,255,255),
        textSecondary = Color3.fromRGB(200,200,220),
        buttonBg = Color3.fromRGB(45,45,65),
        tabActiveBg = Color3.fromRGB(60,50,80),
        tabInactiveBg = Color3.fromRGB(40,40,60),
        stroke = Color3.fromRGB(180,130,255),
    },
    Rose = {
        bg = Color3.fromRGB(30,20,25),
        titleBg = Color3.fromRGB(60,30,50),
        accent = Color3.fromRGB(220,100,150),
        text = Color3.fromRGB(255,255,255),
        textSecondary = Color3.fromRGB(220,200,210),
        buttonBg = Color3.fromRGB(55,40,50),
        tabActiveBg = Color3.fromRGB(70,45,60),
        tabInactiveBg = Color3.fromRGB(50,35,45),
        stroke = Color3.fromRGB(255,150,200),
    },
    WhiteGold = {
        bg = Color3.fromRGB(240,235,230),
        titleBg = Color3.fromRGB(220,210,190),
        accent = Color3.fromRGB(200,170,100),
        text = Color3.fromRGB(30,30,30),
        textSecondary = Color3.fromRGB(80,80,80),
        buttonBg = Color3.fromRGB(210,200,185),
        tabActiveBg = Color3.fromRGB(230,215,190),
        tabInactiveBg = Color3.fromRGB(200,190,175),
        stroke = Color3.fromRGB(200,170,100),
    },
    DarkGold = {
        bg = Color3.fromRGB(10,10,15),
        titleBg = Color3.fromRGB(25,20,15),
        accent = Color3.fromRGB(200,160,80),
        text = Color3.fromRGB(255,255,230),
        textSecondary = Color3.fromRGB(200,200,180),
        buttonBg = Color3.fromRGB(30,28,25),
        tabActiveBg = Color3.fromRGB(45,35,25),
        tabInactiveBg = Color3.fromRGB(30,25,20),
        stroke = Color3.fromRGB(200,160,80),
    },
}

local FONTS = {
    "Gotham",
    "SourceSans",
    "FredokaOne",
    "Roboto",
    "Arial",
    "ComicSans",
    "Bangers",
    "Lato"
}

local currentTheme = "Default"
local currentFont = "Gotham"

-- Apply theme and font to all GUI elements
local function applyThemeAndFont(themeName, fontName)
    currentTheme = themeName or currentTheme
    currentFont = fontName or currentFont
    local theme = THEMES[currentTheme]
    if not theme then return end
    local font = Enum.Font[currentFont] or Enum.Font.Gotham

    -- Iterate through all descendants of mainFrame and update
    local function updateDescendants(obj)
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            if obj:IsA("TextLabel") and obj.Name == "Title" then
                -- keep title text color? we'll update anyway.
            end
            obj.Font = font
            -- For text buttons, we need to update TextColor3 only if not a specific override
            if obj:IsA("TextButton") or obj:IsA("TextLabel") then
                if obj:IsA("TextLabel") and (obj.Name == "TitleLabel" or obj.Name == "Title") then
                    -- keep specific color? we'll update to theme text
                end
                obj.TextColor3 = theme.text
            end
        end
        -- Update UIStroke colors
        if obj:IsA("UIStroke") then
            obj.Color = theme.stroke
        end
        -- Update frames backgrounds (main, title, panels)
        if obj:IsA("Frame") then
            if obj == mainFrame then
                obj.BackgroundColor3 = theme.bg
            elseif obj == titleBar then
                obj.BackgroundColor3 = theme.titleBg
            elseif obj:IsA("Frame") and obj.Parent == content then
                -- tabs container and panels
                if obj == tabContainer then
                    -- don't change background
                elseif obj == petsPanel or obj == toysPanel or obj == themePanel then
                    -- panels are transparent
                elseif obj:IsA("Frame") and obj:FindFirstChild("Layout") then
                    -- controls panels
                    if obj.BackgroundTransparency < 1 then
                        obj.BackgroundColor3 = theme.buttonBg
                    end
                end
            end
        end
        -- Update buttons
        if obj:IsA("TextButton") then
            if obj == closeBtn then
                -- keep close color
            else
                obj.BackgroundColor3 = theme.buttonBg
                if obj:IsA("TextButton") then
                    obj.TextColor3 = theme.text
                end
            end
        end
        -- Recurse
        for _, child in ipairs(obj:GetChildren()) do
            updateDescendants(child)
        end
    end

    updateDescendants(mainFrame)

    -- Update tab buttons specifically
    petsTab.BackgroundColor3 = (currentTab == "Pets") and theme.tabActiveBg or theme.tabInactiveBg
    petsTab.TextColor3 = theme.text
    petsStroke.Color = theme.stroke
    toysTab.BackgroundColor3 = (currentTab == "Toys") and theme.tabActiveBg or theme.tabInactiveBg
    toysTab.TextColor3 = theme.text
    toysStroke.Color = theme.stroke
    themeTab.BackgroundColor3 = (currentTab == "Theme") and theme.tabActiveBg or theme.tabInactiveBg
    themeTab.TextColor3 = theme.text
    themeStroke.Color = theme.stroke

    -- Update outer glow
    glow.Color = theme.accent

    -- Update title label
    titleLabel.TextColor3 = theme.text

    -- Update theme selection buttons (if exist)
    for _, btn in ipairs(themeButtons) do
        btn.BackgroundColor3 = theme.buttonBg
        btn.TextColor3 = theme.text
    end

    -- Update font dropdown button
    fontDropdownBtn.BackgroundColor3 = theme.buttonBg
    fontDropdownBtn.TextColor3 = theme.text

    -- Update font option buttons in dropdown
    for _, btn in ipairs(fontOptionButtons) do
        btn.BackgroundColor3 = theme.buttonBg
        btn.TextColor3 = theme.text
    end
end

-- ============================================================
-- GUI – Yuno Hub (Polished) - LAYOUT FIXED
-- ============================================================

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "YunoHub"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = playerGui

-- Main Frame with rounded corners and shadow
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 280, 0, 420)
mainFrame.Position = UDim2.new(0.5, -140, 0.5, -210)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = gui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

-- Outer glow (UIStroke)
local glow = Instance.new("UIStroke")
glow.Color = Color3.fromRGB(108, 75, 171)
glow.Thickness = 2
glow.Transparency = 0.4
glow.Parent = mainFrame

-- Title Bar
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

-- Dragging
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

-- Content container (no list layout, we'll manually position children)
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 1, -36)
content.Position = UDim2.new(0, 8, 0, 34)
content.BackgroundTransparency = 1
content.Parent = mainFrame

-- ============================================================
-- Tabs: Pets / Toys / Theme
-- ============================================================
local tabContainer = Instance.new("Frame")
tabContainer.Size = UDim2.new(1, 0, 0, 28)
tabContainer.Position = UDim2.new(0, 0, 0, 0)
tabContainer.BackgroundTransparency = 1
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

local themeTab = Instance.new("TextButton")
themeTab.Size = UDim2.new(0, 70, 1, 0)
themeTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
themeTab.Text = "Theme"
themeTab.Font = Enum.Font.GothamBold
themeTab.TextSize = 12
themeTab.TextColor3 = Color3.fromRGB(255, 255, 255)
themeTab.Parent = tabContainer
Instance.new("UICorner", themeTab).CornerRadius = UDim.new(0, 6)
local themeStroke = Instance.new("UIStroke")
themeStroke.Color = Color3.fromRGB(180, 130, 255)
themeStroke.Thickness = 1.5
themeStroke.Transparency = 0.6
themeStroke.Parent = themeTab

-- Panel container (fills remaining space)
local panelContainer = Instance.new("Frame")
panelContainer.Size = UDim2.new(1, 0, 1, -28)
panelContainer.Position = UDim2.new(0, 0, 0, 28)
panelContainer.BackgroundTransparency = 1
panelContainer.Parent = content

-- Panels (all fill panelContainer, only one visible at a time)
local petsPanel = Instance.new("Frame")
petsPanel.Size = UDim2.new(1, 0, 1, 0)
petsPanel.Position = UDim2.new(0, 0, 0, 0)
petsPanel.BackgroundTransparency = 1
petsPanel.Visible = true
petsPanel.Parent = panelContainer

local toysPanel = Instance.new("Frame")
toysPanel.Size = UDim2.new(1, 0, 1, 0)
toysPanel.Position = UDim2.new(0, 0, 0, 0)
toysPanel.BackgroundTransparency = 1
toysPanel.Visible = false
toysPanel.Parent = panelContainer

local themePanel = Instance.new("Frame")
themePanel.Size = UDim2.new(1, 0, 1, 0)
themePanel.Position = UDim2.new(0, 0, 0, 0)
themePanel.BackgroundTransparency = 1
themePanel.Visible = false
themePanel.Parent = panelContainer

-- ============================================================
-- Pets Panel
-- ============================================================
local petsLayout = Instance.new("UIListLayout")
petsLayout.SortOrder = Enum.SortOrder.LayoutOrder
petsLayout.Padding = UDim.new(0, 5)
petsLayout.Parent = petsPanel

-- Pet name input with glow
local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, 0, 0, 26)
nameBox.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
nameBox.Text = ""
nameBox.PlaceholderText = "Enter Pet Name"
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

-- Flags row
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

-- Age row
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

-- Spawn buttons row
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
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Enter a pet name.", Duration = 3})
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

-- Additional buttons: All Variants & Random
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
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Enter a pet name first.", Duration = 3})
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
-- Pet Controls (Equip, Ride, Fly, Unequip, Rename)
-- ============================================================
local controlsPanel = Instance.new("Frame")
controlsPanel.Size = UDim2.new(1, 0, 0, 100)
controlsPanel.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
controlsPanel.BackgroundTransparency = 0.2
controlsPanel.LayoutOrder = 6
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
equipInfo.Text = "No pet equipped"
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

local equipBtn = makeCtrlBtn("Equip", 1)
local rideBtn = makeCtrlBtn("Ride", 2)
local flyBtn = makeCtrlBtn("Fly", 3)
local unequipBtn = makeCtrlBtn("Unequip", 4)

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
renameBox.PlaceholderText = "New name..."
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
renameBtn.Text = "Rename"
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

-- Control functions
local function updatePetControls(item)
    if item and item.unique and SpawnedPets[item.unique] then
        equipInfo.Text = "Equipped: " .. (item.kind or "Unknown")
    else
        equipInfo.Text = "No pet equipped"
    end
end

-- Equip last spawned
equipBtn.MouseButton1Click:Connect(function()
    if not lastSpawnedUnique then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "No pet spawned yet.", Duration = 3})
        return
    end
    local petData = ClientData.get("inventory").pets[lastSpawnedUnique]
    if not petData then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Pet not found in inventory.", Duration = 3})
        return
    end
    BPEquip(petData)
    updatePetControls(petData)
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Equipped " .. (petData.kind or "pet"), Duration = 3})
end)

rideBtn.MouseButton1Click:Connect(function()
    if not EquippedPet then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "No pet equipped.", Duration = 3})
        return
    end
    if not EquippedPet.properties.rideable then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "This pet is not rideable.", Duration = 3})
        return
    end
    BPMount(EquippedPet.unique, "PlayerRidingPet", "PetBeingRidden")
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Riding pet.", Duration = 2})
end)

flyBtn.MouseButton1Click:Connect(function()
    if not EquippedPet then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "No pet equipped.", Duration = 3})
        return
    end
    if not EquippedPet.properties.flyable then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "This pet is not flyable.", Duration = 3})
        return
    end
    BPMount(EquippedPet.unique, "PlayerFlyingPet", "PetBeingFlown")
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Flying pet.", Duration = 2})
end)

unequipBtn.MouseButton1Click:Connect(function()
    if not EquippedPet then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "No pet equipped.", Duration = 3})
        return
    end
    BPUnequip(EquippedPet)
    updatePetControls(nil)
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Unequipped pet.", Duration = 2})
end)

renameBtn.MouseButton1Click:Connect(function()
    if not EquippedPet then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "No pet equipped.", Duration = 3})
        return
    end
    local newName = renameBox.Text
    if newName == "" then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Enter a name.", Duration = 3})
        return
    end
    local success, err = pcall(function()
        RouterClient.get("SettingsAPI/SetPetRoleplayName"):InvokeServer(EquippedPet.unique, newName)
    end)
    if success then
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Pet renamed to " .. newName, Duration = 3})
        renameBox.Text = ""
    else
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Rename failed: " .. tostring(err), Duration = 3})
    end
end)

-- ============================================================
-- Toys Panel
-- ============================================================
local toysLayout = Instance.new("UIListLayout")
toysLayout.SortOrder = Enum.SortOrder.LayoutOrder
toysLayout.Padding = UDim.new(0, 4)
toysLayout.Parent = toysPanel

local toyNameBox = Instance.new("TextBox")
toyNameBox.Size = UDim2.new(1, 0, 0, 26)
toyNameBox.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
toyNameBox.Text = ""
toyNameBox.PlaceholderText = "Enter Toy Name"
toyNameBox.Font = Enum.Font.SourceSans
toyNameBox.TextSize = 12
toyNameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
toyNameBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 160)
toyNameBox.ClearTextOnFocus = false
toyNameBox.TextXAlignment = Enum.TextXAlignment.Left
toyNameBox.LayoutOrder = 0
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
toySpawnBtn.LayoutOrder = 1
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
        game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = "Enter a toy name.", Duration = 3})
        return
    end
    local item, msg = SpawnToyByName(name)
    game.StarterGui:SetCore("SendNotification", {Title = "Yuno Hub", Text = msg, Duration = 3})
end)

-- ============================================================
-- Theme Panel
-- ============================================================
local themeLayout = Instance.new("UIListLayout")
themeLayout.SortOrder = Enum.SortOrder.LayoutOrder
themeLayout.Padding = UDim.new(0, 6)
themeLayout.Parent = themePanel

-- Label for Theme
local themeLabel = Instance.new("TextLabel")
themeLabel.Size = UDim2.new(1, 0, 0, 20)
themeLabel.BackgroundTransparency = 1
themeLabel.Text = "Select Theme"
themeLabel.Font = Enum.Font.GothamBold
themeLabel.TextSize = 12
themeLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
themeLabel.TextXAlignment = Enum.TextXAlignment.Center
themeLabel.LayoutOrder = 0
themeLabel.Parent = themePanel

-- Theme buttons (grid layout)
local themeBtnContainer = Instance.new("Frame")
themeBtnContainer.Size = UDim2.new(1, 0, 0, 80)
themeBtnContainer.BackgroundTransparency = 1
themeBtnContainer.LayoutOrder = 1
themeBtnContainer.Parent = themePanel
local tbcLayout = Instance.new("UIListLayout")
tbcLayout.FillDirection = Enum.FillDirection.Horizontal
tbcLayout.SortOrder = Enum.SortOrder.LayoutOrder
tbcLayout.Padding = UDim.new(0, 8)
tbcLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tbcLayout.Parent = themeBtnContainer

local themeButtons = {}
for _, themeName in ipairs({"Default", "Rose", "WhiteGold", "DarkGold"}) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 55, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    btn.Text = themeName
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Parent = themeBtnContainer
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(160, 100, 220)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.3
    stroke.Parent = btn
    table.insert(themeButtons, btn)
    btn.MouseButton1Click:Connect(function()
        applyThemeAndFont(themeName, currentFont)
        themeLabel.Text = "Current Theme: " .. themeName
    end)
end

-- Font selection
local fontLabel = Instance.new("TextLabel")
fontLabel.Size = UDim2.new(1, 0, 0, 20)
fontLabel.BackgroundTransparency = 1
fontLabel.Text = "Font: " .. currentFont
fontLabel.Font = Enum.Font.GothamBold
fontLabel.TextSize = 12
fontLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
fontLabel.TextXAlignment = Enum.TextXAlignment.Center
fontLabel.LayoutOrder = 2
fontLabel.Parent = themePanel

local fontDropdownBtn = Instance.new("TextButton")
fontDropdownBtn.Size = UDim2.new(0.6, 0, 0, 26)
fontDropdownBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
fontDropdownBtn.Text = currentFont
fontDropdownBtn.Font = Enum.Font.GothamBold
fontDropdownBtn.TextSize = 12
fontDropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
fontDropdownBtn.LayoutOrder = 3
fontDropdownBtn.Parent = themePanel
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
fontListFrame.LayoutOrder = 4
fontListFrame.Parent = themePanel
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
        fontLabel.Text = "Font: " .. currentFont
        fontListFrame.Visible = false
    end)
end

-- Toggle font list
fontDropdownBtn.MouseButton1Click:Connect(function()
    fontListFrame.Visible = not fontListFrame.Visible
end)

-- ============================================================
-- Tab switching (FIXED - uses panelContainer)
-- ============================================================
local currentTab = "Pets"
local function switchTab(tab)
    currentTab = tab
    if tab == "Pets" then
        petsPanel.Visible = true
        toysPanel.Visible = false
        themePanel.Visible = false
        petsTab.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
        petsStroke.Transparency = 0.2
        toysTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        toysStroke.Transparency = 0.6
        themeTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        themeStroke.Transparency = 0.6
    elseif tab == "Toys" then
        petsPanel.Visible = false
        toysPanel.Visible = true
        themePanel.Visible = false
        petsTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        petsStroke.Transparency = 0.6
        toysTab.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
        toysStroke.Transparency = 0.2
        themeTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        themeStroke.Transparency = 0.6
    else -- Theme
        petsPanel.Visible = false
        toysPanel.Visible = false
        themePanel.Visible = true
        petsTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        petsStroke.Transparency = 0.6
        toysTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        toysStroke.Transparency = 0.6
        themeTab.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
        themeStroke.Transparency = 0.2
    end
end

petsTab.MouseButton1Click:Connect(function() switchTab("Pets") end)
toysTab.MouseButton1Click:Connect(function() switchTab("Toys") end)
themeTab.MouseButton1Click:Connect(function() switchTab("Theme") end)

switchTab("Pets")

-- Apply default theme and font
applyThemeAndFont("Default", "Gotham")

print("Yuno Hub with full pet engine and theme system loaded successfully!")
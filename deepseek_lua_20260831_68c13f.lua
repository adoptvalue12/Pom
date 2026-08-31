--[[
    YUNO AUTOFARM | ADOPT ME - VERSION ULTIME
    - Gestion des affections (toutes)
    - Quêtes automatiques (manger, boire, caresser, jouer, dormir)
    - Détection intelligente des quêtes via l'interface
    - Mode bébé supporté
    - Recherche de nourriture/eau gratuite dans toute la map
    - Interface WindUI avec réglages
]]

-- ============================================================
-- CHARGEMENT WINDUI
-- ============================================================
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- ============================================================
-- SERVICES
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- MODULES (avec fallback)
-- ============================================================
local AilmentsManager, InteriorsM, ClientDataModule
local success, err = pcall(function()
    AilmentsManager = require(ReplicatedStorage.new.modules.Ailments.AilmentsClient)
    InteriorsM = require(ReplicatedStorage.ClientModules.Core.InteriorsM.InteriorsM)
    ClientDataModule = require(ReplicatedStorage.ClientModules.Core.ClientData)
end)
if not success then warn("Modules manquants:", err) return end

-- ============================================================
-- CONFIG
-- ============================================================
getgenv().Yuno = getgenv().Yuno or {}
local Yuno = getgenv().Yuno
Yuno.autofarmEnabled = (Yuno.autofarmEnabled == nil) and false or Yuno.autofarmEnabled
Yuno.questEnabled = (Yuno.questEnabled == nil) and true or Yuno.questEnabled
Yuno.questInterval = Yuno.questInterval or 5  -- secondes entre chaque vérif
Yuno.configName = Yuno.configName or "default"

-- ============================================================
-- MAPPINGS
-- ============================================================
local LOCATION_MAPPING = {
    dirty = "far_away_platform", hungry = "far_away_platform", sleepy = "far_away_platform",
    thirsty = "far_away_platform", sick = "housing", play = "far_away_platform",
    camping = "MainMap", bored = "MainMap", beach_party = "MainMap",
    ride = "far_away_platform", walk = "far_away_platform",
    school = "School", pizza_party = "PizzaShop", salon = "Salon", toilet = "far_away_platform",
}
local STATIC_MAP_TARGETS = {
    camping = "StaticMap.Campsite.CampsiteOrigin",
    bored = "StaticMap.Park.BoredAilmentTarget",
    beach_party = "StaticMap.Beach.BeachPartyAilmentTarget",
}

-- ============================================================
-- REMOTES
-- ============================================================
local API = ReplicatedStorage:WaitForChild("API")
local ToolEquipRemote = API:WaitForChild("ToolAPI/Equip")
local PetObjectCreateRemote = API:WaitForChild("PetObjectAPI/CreatePetObject")
local HoldBabyRemote = API:WaitForChild("AdoptAPI/HoldBaby")
local BuyItemRemote = API:WaitForChild("ShopAPI/BuyItem")
local UnequipRemote = API:WaitForChild("ToolAPI/Unequip")
local EjectBabyRemote = API:WaitForChild("AdoptAPI/EjectBaby")
local activateFurniture = API:WaitForChild("HousingAPI/ActivateFurniture")

-- ============================================================
-- ÉTAT
-- ============================================================
local isProcessingAilment = false
local ailmentsToProcess = {}
local activeAilments = {}
local queuedAilments = {}
local AilmentPlatform = nil
local statusLabelUI, ailmentListUI, questStatusUI, questSliderUI

-- ============================================================
-- UTILITAIRES
-- ============================================================
local function getAilmentIdFromInstance(a) return a and a.kind or "UNKNOWN" end
local function getEntityDisplayInfo(ref)
    if not ref then return "Inconnu", "N/A" end
    if not ref.is_pet then return LocalPlayer.Name.."'s Baby", tostring(LocalPlayer.UserId) end
    local inv = ClientDataModule.get("inventory")
    if inv and inv.pets and inv.pets[ref.pet_unique] then
        return tostring(inv.pets[ref.pet_unique].id), tostring(ref.pet_unique)
    end
    return "Animal", tostring(ref.pet_unique)
end
local function createEntityReference(player, isPet, petUnique) return { player=player, is_pet=isPet, pet_unique=petUnique } end
local function waitForData()
    local data = ClientDataModule.get_data()
    while not data do task.wait(0.2); data = ClientDataModule.get_data() end
    return data
end
local function findDeep(parent, name)
    for _, c in ipairs(parent:GetChildren()) do
        if c.Name == name then return c end
        if c:IsA("Folder") or c:IsA("Model") then
            local found = findDeep(c, name)
            if found then return found end
        end
    end
end
local function getFirstPetModel()
    local folder = Workspace:FindFirstChild("Pets") or Workspace:WaitForChild("Pets", 5)
    if folder then
        for _, p in ipairs(folder:GetChildren()) do if p:IsA("Model") then return p end end
    end
    return nil
end
local function safeTeleportToCFrame(cf)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    local pet = getFirstPetModel()
    root.CFrame = cf
    if pet and pet:FindFirstChild("PrimaryPart") then pet.PrimaryPart.CFrame = cf end
end
local function createAilmentPlatform()
    if AilmentPlatform and AilmentPlatform.Parent then return end
    AilmentPlatform = Instance.new("Part")
    AilmentPlatform.Name = "AilmentPlatform"
    AilmentPlatform.Anchored = true
    AilmentPlatform.CanCollide = true
    AilmentPlatform.Transparency = 0
    AilmentPlatform.Size = Vector3.new(2048, 4, 2048)
    AilmentPlatform.CFrame = CFrame.new(-100000, 1000, -100000)
    AilmentPlatform.Color = Color3.fromRGB(80,200,120)
    AilmentPlatform.Parent = Workspace
end
local function destroyAilmentPlatform()
    if AilmentPlatform and AilmentPlatform.Parent then AilmentPlatform:Destroy(); AilmentPlatform = nil end
end
local function teleportToInteriors() end

-- ============================================================
-- DÉTECTION BÉBÉ
-- ============================================================
local function isBaby()
    local char = LocalPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local babyVal = LocalPlayer:FindFirstChild("Baby")
    if babyVal and babyVal:IsA("BoolValue") then return babyVal.Value end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root and root.Size.Y < 2 then return true end
    return false
end

-- ============================================================
-- QUÊTES : RECHERCHE DE NOURRITURE/EAU GRATUITE (dans toute la map)
-- ============================================================
local function findFreeFoodBowl()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj:FindFirstChild("TouchInterest") then
            local n = obj.Name:lower()
            if n:find("food") or n:find("bowl") or n:find("manger") then return obj end
        end
    end
    return nil
end
local function findFreeWaterBowl()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj:FindFirstChild("TouchInterest") then
            local n = obj.Name:lower()
            if n:find("water") or n:find("drink") or n:find("boire") then return obj end
        end
    end
    return nil
end
local function interactWithBowl(bowl)
    if not bowl then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    root.CFrame = bowl.CFrame * CFrame.new(0,3,2)
    task.wait(0.2)
    local prompt = bowl:FindFirstChildOfClass("ProximityPrompt")
    if prompt then fireproximityprompt(prompt); return true end
    -- Sinon, on essaie via le mobilier (maison)
    local furnitureFolder = Workspace:FindFirstChild("HouseInteriors")
    if furnitureFolder then
        local furniture = furnitureFolder:FindFirstChild("furniture")
        if furniture then
            for _, child in ipairs(furniture:GetChildren()) do
                if child:IsA("Model") and child:FindFirstChild(bowl.Name) then
                    local fid = child.Name
                    local args = { LocalPlayer, fid, "UseBlock", { cframe = root.CFrame }, getFirstPetModel() }
                    local ok = pcall(activateFurniture.InvokeServer, activateFurniture, unpack(args))
                    if ok then return true end
                end
            end
        end
    end
    return false
end
local function eat() return interactWithBowl(findFreeFoodBowl()) end
local function drink() return interactWithBowl(findFreeWaterBowl()) end

-- ============================================================
-- QUÊTE : CARESSER
-- ============================================================
local function petAnimal()
    local pet = getFirstPetModel()
    if not pet then return false end
    -- Essayer via HoldBabyRemote (parfois fonctionne)
    local ok, _ = pcall(HoldBabyRemote.FireServer, HoldBabyRemote, pet)
    if ok then return true end
    -- Essayer via CreatePetObject avec réaction "Pet"
    if PetObjectCreateRemote then
        local args = { "__Enum_PetObjectCreatorType_3", { reaction_name = "PetReaction", pet_unique = pet.Name } }
        ok, _ = pcall(PetObjectCreateRemote.InvokeServer, PetObjectCreateRemote, unpack(args))
        if ok then return true end
    end
    return false
end

-- ============================================================
-- LECTURE DES QUÊTES DEPUIS L'INTERFACE
-- ============================================================
local function getCurrentQuests()
    local quests = {}
    local gui = PlayerGui:FindFirstChild("DailyQuests") or PlayerGui:FindFirstChild("Quests")
    if gui then
        -- Parcours de tous les TextLabels ou boutons
        for _, child in ipairs(gui:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                local txt = child.Text:lower()
                if child.Name:find("Quest") or txt:find("quête") or txt:find("mission") then
                    if txt:find("manger") or txt:find("eat") then table.insert(quests, {type="eat", priority=1})
                    elseif txt:find("boire") or txt:find("drink") then table.insert(quests, {type="drink", priority=2})
                    elseif txt:find("caresser") or txt:find("pet") then table.insert(quests, {type="pet", priority=3})
                    elseif txt:find("jouer") or txt:find("play") then table.insert(quests, {type="play", priority=4})
                    elseif txt:find("dormir") or txt:find("sleep") then table.insert(quests, {type="sleep", priority=5})
                    else table.insert(quests, {type="other", priority=99, text=txt}) end
                end
            end
        end
    end
    -- Si aucune quête détectée, on simule selon les besoins
    if #quests == 0 then
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health < 80 then table.insert(quests, {type="eat", priority=1}) end
            -- Si en mode bébé, ajouter boire
            if isBaby() then table.insert(quests, {type="drink", priority=2}) end
        end
    end
    table.sort(quests, function(a,b) return a.priority < b.priority end)
    return quests
end

-- ============================================================
-- EXÉCUTION D'UNE QUÊTE
-- ============================================================
local function executeQuest(quest)
    if not quest then return false end
    local t = quest.type
    if t == "eat" then return eat()
    elseif t == "drink" then return drink()
    elseif t == "pet" then return petAnimal()
    elseif t == "play" then
        local pet = getFirstPetModel()
        if pet and PetObjectCreateRemote then
            local args = { "__Enum_PetObjectCreatorType_1", { reaction_name = "ThrowToyReaction", unique_id = "squeaky_bone_default" } }
            local ok = pcall(PetObjectCreateRemote.InvokeServer, PetObjectCreateRemote, unpack(args))
            if ok then return true end
        end
        return false
    elseif t == "sleep" then
        local furnitureFolder = Workspace:FindFirstChild("HouseInteriors")
        if furnitureFolder then
            local furniture = furnitureFolder:FindFirstChild("furniture")
            if furniture then
                for _, child in ipairs(furniture:GetChildren()) do
                    if child:IsA("Model") and (child.Name:find("Bed") or child.Name:find("Crib")) then
                        local fid = child.Name
                        local char = LocalPlayer.Character
                        if char then
                            local root = char:FindFirstChild("HumanoidRootPart")
                            if root then
                                local args = { LocalPlayer, fid, "Seat1", { cframe = root.CFrame }, getFirstPetModel() }
                                local ok = pcall(activateFurniture.InvokeServer, activateFurniture, unpack(args))
                                if ok then return true end
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    return false
end

-- ============================================================
-- BOUCLE QUÊTES (avec intervalle réglable)
-- ============================================================
task.spawn(function()
    while true do
        if Yuno.autofarmEnabled and Yuno.questEnabled then
            local quests = getCurrentQuests()
            if #quests > 0 then
                local best = quests[1]
                if questStatusUI then questStatusUI.Text = "Quête: " .. (best.type or "inconnue") end
                local ok = executeQuest(best)
                if ok then
                    -- Attendre un peu pour la validation
                    task.wait(0.5)
                end
            else
                if questStatusUI then questStatusUI.Text = "Aucune quête" end
            end
        end
        task.wait(Yuno.questInterval or 5)
    end
end)

-- ============================================================
-- GESTION DES AFFECTIONS (reprise de l'original, avec délais réduits)
-- ============================================================
local function handleSickAilment(data)
    local doorId = "MainDoor"
    local settings = { house_owner = LocalPlayer }
    task.wait(3)
    InteriorsM.enter_smooth("housing", doorId, settings, nil)
    task.wait(0.5)
    local ShopRemote = BuyItemRemote
    local PetRemote = PetObjectCreateRemote
    if not ShopRemote or not PetRemote then return end
    local serverData = ClientDataModule.get_data()
    local playerData = serverData and serverData[LocalPlayer.Name]
    local petUniqueId
    if playerData and playerData.inventory and playerData.inventory.pets then
        for id,_ in pairs(playerData.inventory.pets) do petUniqueId = id; break end
    end
    if not petUniqueId then return end
    local completed = false
    local conn = AilmentsManager.get_ailment_completed_signal():Connect(function(inst, key)
        if key == data.entityUniqueKey and inst == data.ailmentInstance then completed = true end
    end)
    local timeout = 60
    local start = os.time()
    while not completed and (os.time()-start) < timeout do
        local buyArgs = { "food", "healing_apple", { buy_count=1 } }
        pcall(ShopRemote.InvokeServer, ShopRemote, unpack(buyArgs))
        task.wait(0.5)
        local curData = waitForData()
        local curPlayer = curData[LocalPlayer.Name]
        local foodUniqueId
        if curPlayer and curPlayer.inventory and curPlayer.inventory.food then
            for id, item in pairs(curPlayer.inventory.food) do
                if item.id == "healing_apple" then foodUniqueId = id; break end
            end
        end
        if foodUniqueId then
            local args = { "__Enum_PetObjectCreatorType_2", { additional_consume_uniques = {}, pet_unique = petUniqueId, unique_id = foodUniqueId } }
            pcall(PetRemote.InvokeServer, PetRemote, unpack(args))
        end
        task.wait(2)
    end
    conn:Disconnect()
    InteriorsM.enter_smooth("housing", doorId, { house_owner = LocalPlayer }, nil)
    task.wait(0.5)
end

local function handleAilmentOnPlatform(data)
    if not AilmentsManager then return end
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    local pet = getFirstPetModel()
    local target = AilmentPlatform
    if not target then return end
    local cf = target.CFrame * CFrame.new(0,5,0)
    root.CFrame = cf
    if pet and pet:FindFirstChild("PrimaryPart") then pet.PrimaryPart.CFrame = cf end
    task.wait(0.3)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local ailmentId = data.ailmentId
    local furnitureMapping = {
        hungry = "PetFoodBowl", thirsty = "PetWaterBowl", dirty = "CheapPetBathtub",
        sleepy = "BasicCrib", toilet = "Toilet"
    }
    local fName = furnitureMapping[ailmentId]
    if fName then
        local fFolder = Workspace:FindFirstChild("HouseInteriors")
        if fFolder then
            local furniture = fFolder:FindFirstChild("furniture")
            if furniture then
                local found = findDeep(furniture, fName)
                if found then
                    local fParent = found.Parent
                    local parts = string.split(fParent.Name, "/")
                    local fid = parts[#parts]
                    local cframe = char:WaitForChild("Head").CFrame
                    local action = (fName == "Toilet") and "Seat1" or "UseBlock"
                    local args = { LocalPlayer, fid, action, { cframe = cframe }, pet }
                    pcall(activateFurniture.InvokeServer, activateFurniture, unpack(args))
                end
            end
        end
    elseif ailmentId == "play" then
        local PetRemote = PetObjectCreateRemote
        if not PetRemote then return end
        local serverData = ClientDataModule.get_data()
        local playerData = serverData and serverData[LocalPlayer.Name]
        local itemUniqueId
        if playerData and playerData.inventory and playerData.inventory.toys then
            for id, item in pairs(playerData.inventory.toys) do
                if item.id == "squeaky_bone_default" then itemUniqueId = id; break end
            end
        end
        if not itemUniqueId then return end
        local completed = false
        local conn = AilmentsManager.get_ailment_completed_signal():Connect(function(inst,key)
            if key == data.entityUniqueKey and inst == data.ailmentInstance then completed = true end
        end)
        local timeout = 60
        local start = os.time()
        while not completed and (os.time()-start) < timeout do
            local args = { "__Enum_PetObjectCreatorType_1", { reaction_name = "ThrowToyReaction", unique_id = itemUniqueId } }
            pcall(PetRemote.InvokeServer, PetRemote, unpack(args))
            task.wait(5)
        end
        conn:Disconnect()
    elseif ailmentId == "walk" then
        local entry = activeAilments[data.entityUniqueKey] and activeAilments[data.entityUniqueKey][ailmentId]
        if entry then entry.petModel = pet end
        pcall(HoldBabyRemote.FireServer, HoldBabyRemote, pet)
    elseif ailmentId == "ride" then
        local serverData = ClientDataModule.get_data()
        local playerData = serverData and serverData[LocalPlayer.Name]
        if playerData and playerData.inventory and playerData.inventory.strollers then
            local firstId
            for id,_ in pairs(playerData.inventory.strollers) do firstId = id; break end
            if firstId then
                local entry = activeAilments[data.entityUniqueKey] and activeAilments[data.entityUniqueKey][ailmentId]
                if entry then entry.unequipItemId = firstId end
                pcall(ToolEquipRemote.InvokeServer, ToolEquipRemote, firstId)
            end
        end
    end
    local completed = false
    local conn = AilmentsManager.get_ailment_completed_signal():Connect(function(inst,key)
        if key == data.entityUniqueKey and inst == data.ailmentInstance then completed = true end
    end)
    local timeout = 60
    local start = os.time()
    while not completed and (os.time()-start) < timeout do
        if ailmentId == "walk" or ailmentId == "ride" then
            if hum and hum.Parent then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
        task.wait(0.5)
    end
    conn:Disconnect()
    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(0.5)
end

local function teleportToStaticMap(data)
    if not AilmentsManager then return end
    local path = STATIC_MAP_TARGETS[data.ailmentId]
    if not path then return end
    local target = Workspace:FindFirstChild(path)
    if not target then
        local parts = string.split(path, ".")
        local current = Workspace
        for _, p in ipairs(parts) do
            current = current:FindFirstChild(p)
            if not current then return end
        end
        target = current
    end
    if not target then return end
    safeTeleportToCFrame(target.CFrame * CFrame.new(0,5,0))
    local completed = false
    local conn = AilmentsManager.get_ailment_completed_signal():Connect(function(inst,key)
        if key == data.entityUniqueKey and inst == data.ailmentInstance then completed = true end
    end)
    local timeout = 60
    local start = os.time()
    while not completed and (os.time()-start) < timeout do task.wait(0.5) end
    conn:Disconnect()
    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(0.5)
end

local function handleInteriorAilment(data, location)
    InteriorsM.enter_smooth(location, "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(0.5)
    local ailmentId = data.ailmentId
    local furnitureName
    if ailmentId == "pizza_party" then furnitureName = "PizzaTable"
    elseif ailmentId == "salon" then furnitureName = "SalonChair"
    elseif ailmentId == "school" then furnitureName = "SchoolDesk" end
    if furnitureName then
        local interior = Workspace:FindFirstChild("Interiors")
        if interior then
            local loc = interior:FindFirstChild(location)
            if loc then
                local int = loc:FindFirstChild("Interior")
                if int then
                    local part = findDeep(int, furnitureName)
                    if part and part.Parent then
                        local fid = part.Parent.Name
                        local args = { LocalPlayer, fid, "Seat1", { cframe = LocalPlayer.Character.HumanoidRootPart.CFrame }, getFirstPetModel() }
                        pcall(activateFurniture.InvokeServer, activateFurniture, unpack(args))
                    end
                end
            end
        end
    end
    local completed = false
    local conn = AilmentsManager.get_ailment_completed_signal():Connect(function(inst,key)
        if key == data.entityUniqueKey and inst == data.ailmentInstance then completed = true end
    end)
    local timeout = 60
    local start = os.time()
    while not completed and (os.time()-start) < timeout do task.wait(0.5) end
    conn:Disconnect()
    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(0.5)
end

local function cleanupAilment(entry)
    local id = entry.StoredAilmentId
    if id == "ride" and entry.unequipItemId and UnequipRemote then
        pcall(UnequipRemote.InvokeServer, UnequipRemote, entry.unequipItemId)
    elseif id == "walk" and entry.petModel and EjectBabyRemote then
        pcall(EjectBabyRemote.FireServer, EjectBabyRemote, entry.petModel)
    end
end

local function processAilment(data)
    if not AilmentsManager or not Yuno.autofarmEnabled then isProcessingAilment = false; return end
    isProcessingAilment = true
    local success, err = pcall(function()
        local id = data.ailmentId
        local loc = LOCATION_MAPPING[id]
        if not loc then return end
        if id == "sick" then
            handleSickAilment(data)
        elseif loc == "far_away_platform" then
            InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
            task.wait(0.5)
            handleAilmentOnPlatform(data)
        elseif id == "camping" or id == "bored" or id == "beach_party" then
            InteriorsM.enter_smooth("MainMap", "MainDoor", { fade_in_length=0.5, fade_out_length=0.4, fade_color=Color3.new(0,0,0) }, nil)
            task.wait(0.5)
            teleportToStaticMap(data)
        elseif loc == "PizzaShop" or loc == "School" or loc == "Salon" then
            handleInteriorAilment(data, loc)
        end
    end)
    if not success then warn("Erreur traitement:", err) end
    isProcessingAilment = false
end

local function handleNextAilment()
    if Yuno.autofarmEnabled and not isProcessingAilment and #ailmentsToProcess > 0 then
        local data = table.remove(ailmentsToProcess, 1)
        task.spawn(processAilment, data)
    end
end

local function updateAilmentListUI()
    if not ailmentListUI then return end
    local lines = {}
    for entityKey, map in pairs(activeAilments) do
        for id, entry in pairs(map) do
            local name, _ = getEntityDisplayInfo(entry.EntityRef)
            table.insert(lines, string.format("%s: %s", name, id))
        end
    end
    ailmentListUI.Text = (#lines == 0) and "Aucune affection active." or "Affections:\n" .. table.concat(lines, "\n")
end

local function logAilmentAdded(instance, key, ref)
    local id = getAilmentIdFromInstance(instance)
    if not activeAilments[key] then activeAilments[key] = {} end
    if not activeAilments[key][id] then
        activeAilments[key][id] = { AilmentInstance = instance, EntityRef = ref, StoredAilmentId = id }
    else
        activeAilments[key][id].AilmentInstance = instance
    end
    updateAilmentListUI()
end

local function logAilmentRemoved(instance, key, ref)
    local idToRemove = getAilmentIdFromInstance(instance)
    local found = activeAilments[key] and activeAilments[key][idToRemove]
    if not found then
        for curId, entry in pairs(activeAilments[key] or {}) do
            if entry.AilmentInstance == instance then
                idToRemove = curId
                found = entry
                break
            end
        end
    end
    if found then
        activeAilments[key][idToRemove] = nil
        if next(activeAilments[key]) == nil then activeAilments[key] = nil end
        updateAilmentListUI()
    end
end

local function onAilmentCreated(instance, key)
    local isPet = string.len(key) > 10
    local ref = createEntityReference(LocalPlayer, isPet, key)
    local id = getAilmentIdFromInstance(instance)
    local qKey = key .. "_" .. id
    logAilmentAdded(instance, key, ref)
    if Yuno.autofarmEnabled and LOCATION_MAPPING[id] and not queuedAilments[qKey] then
        queuedAilments[qKey] = true
        table.insert(ailmentsToProcess, { ailmentId = id, entityUniqueKey = key, entityRef = ref, ailmentInstance = instance })
        if not isProcessingAilment then handleNextAilment() end
    end
end

local function onAilmentComplete(instance, key, reason)
    local isPet = string.len(key) > 10
    local ref = createEntityReference(LocalPlayer, isPet, key)
    logAilmentRemoved(instance, key, ref)
    local entry = activeAilments[key] and activeAilments[key][getAilmentIdFromInstance(instance)]
    if entry then cleanupAilment(entry) end
    isProcessingAilment = false
    task.spawn(handleNextAilment)
end

local function initialAilmentScan()
    activeAilments = {}
    local localEntity = createEntityReference(LocalPlayer, false, nil)
    local ailments = AilmentsManager.get_ailments_for_pet(localEntity)
    if ailments then
        for _, inst in pairs(ailments) do onAilmentCreated(inst, tostring(LocalPlayer.UserId)) end
    end
    local inv = ClientDataModule.get("inventory")
    if inv and inv.pets then
        for petId,_ in pairs(inv.pets) do
            local petRef = createEntityReference(LocalPlayer, true, petId)
            local petsAil = AilmentsManager.get_ailments_for_pet(petRef)
            if petsAil then
                for _, inst in pairs(petsAil) do onAilmentCreated(inst, petId) end
            end
        end
    end
end

-- ============================================================
-- SAUVEGARDE
-- ============================================================
local function saveConfig()
    local data = {
        autofarmEnabled = Yuno.autofarmEnabled,
        questEnabled = Yuno.questEnabled,
        questInterval = Yuno.questInterval,
        configName = Yuno.configName,
    }
    local json = game:GetService("HttpService"):JSONEncode(data)
    if not isfolder("YunoAutofarm") then makefolder("YunoAutofarm") end
    writefile("YunoAutofarm/config.json", json)
end

local function loadConfig()
    local path = "YunoAutofarm/config.json"
    if not isfile(path) then return false end
    local json = readfile(path)
    local data = game:GetService("HttpService"):JSONDecode(json)
    if data.autofarmEnabled ~= nil then Yuno.autofarmEnabled = data.autofarmEnabled end
    if data.questEnabled ~= nil then Yuno.questEnabled = data.questEnabled end
    if data.questInterval then Yuno.questInterval = data.questInterval end
    if data.configName then Yuno.configName = data.configName end
    return true
end

-- ============================================================
-- INTERFACE WINDUI
-- ============================================================
local function createUI()
    local Window = WindUI:CreateWindow({
        Title = "Yuno Autofarm | Adopt Me",
        Author = "Yuno",
        Folder = "YunoAutofarm",
        Icon = "heart",
        Size = UDim2.new(0, 480, 0, 480),
        Transparent = true,
        BackgroundTransparency = 0.5,
        Theme = "Dark",
        SideBarWidth = 180,
        HideSearchBar = true,
        ScrollBarEnabled = true,
        OpenButton = {
            Title = "Yuno Autofarm",
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

    Tab:Section({ Title = "Gestion", TextSize = 18, FontWeight = Enum.FontWeight.SemiBold })
    Tab:Toggle({
        Flag = "AutofarmToggle",
        Title = "Activer l'autofarm",
        Default = Yuno.autofarmEnabled,
        Callback = function(v)
            Yuno.autofarmEnabled = v
            saveConfig()
            if v then
                createAilmentPlatform()
                if #ailmentsToProcess == 0 then initialAilmentScan() else handleNextAilment() end
                if statusLabelUI then statusLabelUI.Text = "● Actif"; statusLabelUI.TextColor3 = Color3.fromRGB(0,255,100) end
            else
                destroyAilmentPlatform()
                ailmentsToProcess = {}; queuedAilments = {}; isProcessingAilment = false; activeAilments = {}
                updateAilmentListUI()
                if statusLabelUI then statusLabelUI.Text = "● Arrêté"; statusLabelUI.TextColor3 = Color3.fromRGB(255,100,100) end
            end
        end
    })
    Tab:Toggle({
        Flag = "QuestToggle",
        Title = "Gérer les quêtes automatiquement",
        Default = Yuno.questEnabled,
        Callback = function(v) Yuno.questEnabled = v; saveConfig() end
    })
    -- Slider pour l'intervalle des quêtes
    questSliderUI = Tab:Slider({
        Flag = "QuestInterval",
        Title = "Intervalle vérification quêtes (s)",
        Step = 1,
        Value = { Min = 2, Max = 30, Default = Yuno.questInterval },
        Callback = function(v) Yuno.questInterval = v; saveConfig() end
    })

    Tab:Section({ Title = "Statut", TextSize = 16, FontWeight = Enum.FontWeight.Medium })
    statusLabelUI = Tab:Label({ Title = "● " .. (Yuno.autofarmEnabled and "Actif" or "Arrêté"), Icon = "circle", Color = Yuno.autofarmEnabled and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,100,100) })
    questStatusUI = Tab:Label({ Title = "Quête: Aucune", Icon = "clipboard", Color = Color3.fromRGB(255,200,100) })

    Tab:Section({ Title = "Affections actives", TextSize = 16, FontWeight = Enum.FontWeight.Medium })
    ailmentListUI = Tab:Label({ Title = "Aucune affection active.", Icon = "list", Color = Color3.fromRGB(200,200,220) })

    Tab:Button({ Title = "Scanner maintenant", Icon = "refresh-cw", Callback = function()
        if Yuno.autofarmEnabled then initialAilmentScan(); WindUI:Notify({ Title="Scan", Content="Recherche en cours...", Icon="info", Duration=3 })
        else WindUI:Notify({ Title="Erreur", Content="Autofarm désactivé.", Icon="x", Duration=3 }) end
    end })

    local Settings = Main:Tab({ Title = "Paramètres", Icon = "settings" })
    Settings:Section({ Title = "Sauvegarde", TextSize = 18, FontWeight = Enum.FontWeight.SemiBold })
    Settings:Button({ Title = "Sauvegarder", Icon = "save", Callback = function() saveConfig(); WindUI:Notify({ Title="Config", Content="Sauvegardée !", Icon="check", Duration=3 }) end })
    Settings:Button({ Title = "Charger", Icon = "upload", Callback = function()
        if loadConfig() then
            WindUI:Notify({ Title="Config", Content="Chargée !", Icon="check", Duration=3 })
            local toggle = Tab:GetFlag("AutofarmToggle")
            if toggle then toggle:Set(Yuno.autofarmEnabled) end
            local qtoggle = Tab:GetFlag("QuestToggle")
            if qtoggle then qtoggle:Set(Yuno.questEnabled) end
            if questSliderUI then questSliderUI:Set(Yuno.questInterval) end
        else WindUI:Notify({ Title="Erreur", Content="Aucune configuration.", Icon="x", Duration=3 }) end
    end })

    return Window
end

-- ============================================================
-- LANCEMENT
-- ============================================================
local function runMainLogic()
    loadConfig()
    createUI()
    AilmentsManager.get_ailment_created_signal():Connect(onAilmentCreated)
    AilmentsManager.get_ailment_completed_signal():Connect(onAilmentComplete)
    if Yuno.autofarmEnabled then
        createAilmentPlatform()
        task.wait(0.5)
        initialAilmentScan()
        if statusLabelUI then statusLabelUI.Text = "● Actif"; statusLabelUI.TextColor3 = Color3.fromRGB(0,255,100) end
    end
    print("✅ Yuno Autofarm chargé avec succès !")
end

task.spawn(runMainLogic)
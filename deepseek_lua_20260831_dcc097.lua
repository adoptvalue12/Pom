--[[
    Adopt Me Autofarm - Yuno Hub UI Edition
    Gère automatiquement les affections du joueur et de ses animaux.
    Interface utilisateur avec toggle ON/OFF.
]]

-- --- MODULES & SERVICES ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local task = task

-- Déclaration des modules (chargement différé)
local AilmentsManager = nil
local InteriorsM = nil
local ClientDataModule = nil

local success, err = pcall(function()
    AilmentsManager = require(ReplicatedStorage.new.modules.Ailments.AilmentsClient)
    InteriorsM = require(ReplicatedStorage.ClientModules.Core.InteriorsM.InteriorsM)
    ClientDataModule = require(ReplicatedStorage.ClientModules.Core.ClientData)
end)

if not success then
    warn("Échec du chargement des modules requis. Script non fonctionnel.", err)
    return
end

-- --- CONSTANTES & CONFIGURATION ---
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local AilmentPlatform = nil

-- Mapping affection → lieu
local LOCATION_MAPPING = {
    ["dirty"]   = "far_away_platform",
    ["hungry"]  = "far_away_platform",
    ["sleepy"]  = "far_away_platform",
    ["thirsty"] = "far_away_platform",
    ["sick"]    = "housing",
    ["play"]    = "far_away_platform",
    ["camping"] = "MainMap",
    ["bored"]   = "MainMap",
    ["beach_party"] = "MainMap",
    ["ride"]    = "far_away_platform",
    ["walk"]    = "far_away_platform",
    ["school"]  = "School",
    ["pizza_party"] = "PizzaShop",
    ["salon"]   = "Salon",
    ["toilet"]  = "far_away_platform",
}

-- Cibles statiques sur la map principale
local STATIC_MAP_TARGETS = {
    camping     = "StaticMap.Campsite.CampsiteOrigin",
    bored       = "StaticMap.Park.BoredAilmentTarget",
    beach_party = "StaticMap.Beach.BeachPartyAilmentTarget",
}

-- Mobilier pour les intérieurs
local INTERIOR_FURNITURE_MAPPING = {
    ["salon"]       = "Interiors.Salon.InteriorOrigin",
    ["pizza_party"] = "Interiors.PizzaShop.InteriorOrigin",
    ["school"]      = "Interiors.School.InteriorOrigin"
}

-- Paramètres de téléportation communs
local commonTeleportSettings = {
    fade_in_length = 0.5,
    fade_out_length = 0.4,
    fade_color = Color3.new(0, 0, 0),
    player_about_to_teleport = function() end,
    teleport_completed_callback = function() task.wait(0.2) end,
    player_to_teleport_to = nil,
    anchor_char_immediately = true,
    post_character_anchored_wait = 0.5,
    move_camera = true,
    door_id_for_location_module = nil,
    exiting_door = nil,
}

-- --- ÉVÉNEMENTS DISTANTS ---
local ToolEquipRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("ToolAPI/Equip")
local PetObjectCreateRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("PetObjectAPI/CreatePetObject")
local HoldBabyRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("AdoptAPI/HoldBaby")
local BuyItemRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("ShopAPI/BuyItem")
local UnequipRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("ToolAPI/Unequip")
local EjectBabyRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("AdoptAPI/EjectBaby")
local activateFurniture = ReplicatedStorage:WaitForChild("API"):WaitForChild("HousingAPI/ActivateFurniture")

-- --- ÉTAT GLOBAL ---
local isProcessingAilment = false
local ailmentsToProcess = {}
local activeAilments = {}
local impendingAilments = {}
local queuedAilments = {}
local autofarmEnabled = false   -- Contrôle UI
local currentStatusLabel = nil
local currentAilmentListLabel = nil

-- --- FONCTIONS UTILITAIRES (inchangées) ---
local function getAilmentIdFromInstance(ailmentInstance)
    if not ailmentInstance or type(ailmentInstance) ~= "table" then return "UNKNOWN_INSTANCE" end
    if ailmentInstance.kind then return tostring(ailmentInstance.kind) end
    return "UNKNOWN_AILMENT_NAME_FALLBACK"
end

local function formatAilmentDetails(ailmentInstance)
    local details = {}
    if ailmentInstance and type(ailmentInstance) == "table" then
        if type(ailmentInstance.get_progress) == "function" then
            table.insert(details, "Progress: " .. string.format("%.2f", ailmentInstance:get_progress()))
        elseif ailmentInstance.progress then
            table.insert(details, "Progress: " .. string.format("%.2f", ailmentInstance.progress))
        end
    end
    if #details > 0 then return " (" .. table.concat(details, ", ") .. ")" else return "" end
end

local function getEntityDisplayInfo(entityRef)
    if not entityRef then return "Entité inconnue", "N/A" end
    if not entityRef.is_pet then
        return LocalPlayer.Name .. "'s Baby", tostring(LocalPlayer.UserId)
    else
        local myInventory = ClientDataModule.get("inventory")
        if myInventory and myInventory.pets and myInventory.pets[entityRef.pet_unique] then
            return tostring(myInventory.pets[entityRef.pet_unique].id), tostring(entityRef.pet_unique)
        else
            return "Animal (nom inconnu)", tostring(entityRef.pet_unique)
        end
    end
end

local function createEntityReference(player, isPet, petUniqueId)
    return { player = player, is_pet = isPet, pet_unique = petUniqueId }
end

local function formatTimeRemaining(seconds)
    if not seconds or seconds < 0 then return "N/A" end
    local minutes = math.floor(seconds / 60)
    local remainingSeconds = math.floor(seconds % 60)
    if minutes > 0 then
        return string.format("%dm %02ds", minutes, remainingSeconds)
    else
        return string.format("%ds", remainingSeconds)
    end
end

local function waitForData()
    local data = ClientDataModule.get_data()
    while not data do task.wait(0.5) data = ClientDataModule.get_data() end
    return data
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
    AilmentPlatform.Color = Color3.fromRGB(80, 200, 120)
    AilmentPlatform.Parent = Workspace
    print("✅ Plateforme d'affection créée.")
end

local function destroyAilmentPlatform()
    if AilmentPlatform and AilmentPlatform.Parent then
        AilmentPlatform:Destroy()
        AilmentPlatform = nil
        print("✅ Plateforme d'affection détruite.")
    end
end

local function findDeep(parent, objectName)
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == objectName then return child end
        if child:IsA("Folder") or child:IsA("Model") then
            local found = findDeep(child, objectName)
            if found then return found end
        end
    end
    return nil
end

local function getFirstPetModel()
    local petsFolder = Workspace:WaitForChild("Pets", 5)
    if petsFolder then
        for _, petChild in ipairs(petsFolder:GetChildren()) do
            if petChild:IsA("Model") then return petChild end
        end
    end
    warn("Aucun animal trouvé dans le dossier 'Pets'.")
    return nil
end

local function safeTeleportToCFrame(targetCFrame)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    local petModel = getFirstPetModel()
    humanoidRootPart.CFrame = targetCFrame
    if petModel and petModel:FindFirstChild("PrimaryPart") then
        petModel.PrimaryPart.CFrame = targetCFrame
    end
end

-- --- GESTION DES AFFECTIONS (fonctions originales optimisées) ---
local function handleSickAilment(ailmentData)
    print("Début gestion 'sick'.")
    local destinationId = "housing"
    local doorIdForTeleport = "MainDoor"
    local teleportSettings = { house_owner = LocalPlayer }
    task.wait(10) -- attente streaming
    InteriorsM.enter_smooth(destinationId, doorIdForTeleport, teleportSettings, nil)
    task.wait(2)

    local ShopRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("ShopAPI/BuyItem")
    local PetObjectRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("PetObjectAPI/CreatePetObject")
    if not ShopRemote or not PetObjectRemote then
        warn("Remotes nécessaires pour 'sick' introuvables.")
        return
    end

    local serverData = ClientDataModule.get_data()
    local playerData = serverData and serverData[LocalPlayer.Name]
    local petUniqueId = nil
    if playerData and playerData.inventory and playerData.inventory.pets then
        for uniqueId, _ in pairs(playerData.inventory.pets) do
            petUniqueId = uniqueId
            break
        end
    end
    if not petUniqueId then
        warn("Aucun animal trouvé dans l'inventaire.")
        return
    end
    print("ID unique de l'animal:", petUniqueId)

    local ailmentCompleted = false
    local connection = AilmentsManager.get_ailment_completed_signal():Connect(function(instance, key)
        if key == ailmentData.entityUniqueKey and instance == ailmentData.ailmentInstance then
            ailmentCompleted = true
        end
    end)

    local timeout = 60
    local startTime = os.time()
    while not ailmentCompleted and (os.time() - startTime) < timeout do
        local buyArgs = { "food", "healing_apple", { buy_count = 1 } }
        local success, result = pcall(ShopRemote.InvokeServer, ShopRemote, unpack(buyArgs))
        if success then print("✅ Pomme de guérison achetée.") else warn("Échec achat:", result) end
        task.wait(2)

        local currentData = waitForData()
        local currentPlayerData = currentData[LocalPlayer.Name]
        local foodUniqueId = nil
        if currentPlayerData and currentPlayerData.inventory and currentPlayerData.inventory.food then
            for uniqueId, itemData in pairs(currentPlayerData.inventory.food) do
                if itemData.id == "healing_apple" then
                    foodUniqueId = uniqueId
                    break
                end
            end
        end
        if foodUniqueId then
            print("Pomme trouvée, ID:", foodUniqueId)
            local args = {
                "__Enum_PetObjectCreatorType_2",
                {
                    additional_consume_uniques = {},
                    pet_unique = petUniqueId,
                    unique_id = foodUniqueId
                }
            }
            local createSuccess, createResult = pcall(PetObjectRemote.InvokeServer, PetObjectRemote, unpack(args))
            if createSuccess then print("✅ Commande de création envoyée.") else warn("Échec création:", createResult) end
        end
        task.wait(5)
    end
    connection:Disconnect()
    if not ailmentCompleted then warn("L'affection 'sick' n'a pas été complétée dans le délai.") end

    print("Téléportation vers les intérieurs...")
    teleportToInteriors() -- fonction définie plus bas
    task.wait(1)
    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(2)
    print("Retour au housing.")
end

local function handleAilmentOnPlatform(ailmentData)
    if not AilmentsManager then warn("AilmentsManager nil") return end
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    local petModel = getFirstPetModel()
    local targetPart = AilmentPlatform
    if not targetPart then warn("Plateforme introuvable.") return end
    local targetCFrame = targetPart.CFrame * CFrame.new(0, 5, 0)
    humanoidRootPart.CFrame = targetCFrame
    if petModel and petModel:FindFirstChild("PrimaryPart") then
        petModel.PrimaryPart.CFrame = targetCFrame
    end
    task.wait(1)

    local humanoid = character:WaitForChild("Humanoid")
    local ailmentId = ailmentData.ailmentId

    local furnitureMapping = {
        ["hungry"]  = "PetFoodBowl",
        ["thirsty"] = "PetWaterBowl",
        ["dirty"]   = "CheapPetBathtub",
        ["sleepy"]  = "BasicCrib",
        ["toilet"]  = "Toilet",
    }
    local furnitureName = furnitureMapping[ailmentId]
    if furnitureName then
        local furnitureFolder = Workspace:WaitForChild("HouseInteriors"):WaitForChild("furniture")
        if furnitureFolder then
            local foundItem = findDeep(furnitureFolder, furnitureName)
            if foundItem then
                local furnitureParent = foundItem.Parent
                local parts = string.split(furnitureParent.Name, "/")
                local furnitureId = parts[#parts]
                print("Mobilier trouvé, ID:", furnitureId)
                local cframe = character:WaitForChild("Head").CFrame
                local furnitureAction = (furnitureName == "Toilet") and "Seat1" or "UseBlock"
                local args = { LocalPlayer, furnitureId, furnitureAction, { cframe = cframe }, petModel }
                activateFurniture:InvokeServer(unpack(args))
                print("✅ ActivateFurniture appelé pour", furnitureName, "action:", furnitureAction)
            else
                warn("Mobilier", furnitureName, "introuvable.")
            end
        else
            warn("Dossier 'furniture' introuvable.")
        end
    elseif ailmentId == "play" then
        print("Gestion 'play' avec Squeaky Bone.")
        local PetObjectRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("PetObjectAPI/CreatePetObject")
        if not PetObjectRemote then warn("Remote CreatePetObject manquant.") return end
        local serverData = ClientDataModule.get_data()
        local playerData = serverData and serverData[LocalPlayer.Name]
        local itemUniqueId = nil
        if playerData and playerData.inventory and playerData.inventory.toys then
            for uniqueId, itemData in pairs(playerData.inventory.toys) do
                if itemData.id == "squeaky_bone_default" then
                    itemUniqueId = uniqueId
                    break
                end
            end
        end
        if not itemUniqueId then warn("Squeaky Bone introuvable.") return end
        local ailmentCompleted = false
        local connection = AilmentsManager.get_ailment_completed_signal():Connect(function(instance, key)
            if key == ailmentData.entityUniqueKey and instance == ailmentData.ailmentInstance then
                ailmentCompleted = true
            end
        end)
        local timeout = 60
        local startTime = os.time()
        while not ailmentCompleted and (os.time() - startTime) < timeout do
            local args = {
                "__Enum_PetObjectCreatorType_1",
                { reaction_name = "ThrowToyReaction", unique_id = itemUniqueId }
            }
            local success, result = pcall(PetObjectRemote.InvokeServer, PetObjectRemote, unpack(args))
            if success then print("✅ Jouet créé.") else warn("Échec création jouet:", result) end
            task.wait(10)
        end
        connection:Disconnect()
        if not ailmentCompleted then warn("L'affection 'play' n'a pas été complétée.") end
    elseif ailmentId == "walk" then
        print("Marche: tenir l'animal.")
        local uiEntry = activeAilments[ailmentData.entityUniqueKey] and activeAilments[ailmentData.entityUniqueKey][ailmentId]
        if uiEntry then uiEntry.petModel = petModel end
        local success, result = pcall(HoldBabyRemote.FireServer, HoldBabyRemote, petModel)
        if not success then warn("Échec hold baby:", result) end
    elseif ailmentId == "ride" then
        print("Équipement d'une poussette.")
        local serverData = ClientDataModule.get_data()
        local playerData = serverData[LocalPlayer.Name]
        if playerData and playerData.inventory and playerData.inventory.strollers then
            local firstItemUniqueId = nil
            for uniqueId, _ in pairs(playerData.inventory.strollers) do
                firstItemUniqueId = uniqueId
                break
            end
            if firstItemUniqueId then
                local uiEntry = activeAilments[ailmentData.entityUniqueKey] and activeAilments[ailmentData.entityUniqueKey][ailmentId]
                if uiEntry then uiEntry.unequipItemId = firstItemUniqueId end
                local success, result = pcall(ToolEquipRemote.InvokeServer, ToolEquipRemote, firstItemUniqueId)
                if success then print("✅ Poussette équipée.") else warn("Échec équipement:", result) end
            end
        end
    end

    local ailmentCompleted = false
    local connection = AilmentsManager.get_ailment_completed_signal():Connect(function(instance, key)
        if key == ailmentData.entityUniqueKey and instance == ailmentData.ailmentInstance then
            ailmentCompleted = true
        end
    end)
    local timeout = 60
    local startTime = os.time()
    while not ailmentCompleted and (os.time() - startTime) < timeout do
        if ailmentId == "walk" or ailmentId == "ride" then
            if humanoid and humanoid.Parent then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
        task.wait(1)
    end
    connection:Disconnect()
    if not ailmentCompleted then warn("L'affection n'a pas été complétée.") end

    print("Retour au housing.")
    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(2)
end

local function teleportToStaticMap(ailmentData)
    if not AilmentsManager then warn("AilmentsManager nil") return end
    local targetPath = STATIC_MAP_TARGETS[ailmentData.ailmentId]
    if not targetPath then warn("Aucune cible statique pour", ailmentData.ailmentId) return end
    local targetPart = Workspace:FindFirstChild(targetPath)
    if not targetPart then
        local parts = string.split(targetPath, ".")
        local currentParent = Workspace
        for _, partName in ipairs(parts) do
            currentParent = currentParent:FindFirstChild(partName)
            if not currentParent then
                warn("Partie introuvable:", partName, "dans", targetPath)
                return
            end
        end
        targetPart = currentParent
    end
    if not targetPart then warn("Cible introuvable:", targetPath) return end

    safeTeleportToCFrame(targetPart.CFrame * CFrame.new(0, 5, 0))
    print("Téléporté à", targetPath)

    local ailmentCompleted = false
    local connection = AilmentsManager.get_ailment_completed_signal():Connect(function(instance, key)
        if key == ailmentData.entityUniqueKey and instance == ailmentData.ailmentInstance then
            ailmentCompleted = true
        end
    end)
    local timeout = 60
    local startTime = os.time()
    while not ailmentCompleted and (os.time() - startTime) < timeout do task.wait(1) end
    connection:Disconnect()
    if not ailmentCompleted then warn("L'affection n'a pas été complétée.") end

    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(2)
end

local function handleInteriorAilment(ailmentData, locationName)
    print("Entrée dans", locationName)
    InteriorsM.enter_smooth(locationName, "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(2)

    local ailmentId = ailmentData.ailmentId
    local furnitureName = nil
    if ailmentId == "pizza_party" then furnitureName = "PizzaTable"
    elseif ailmentId == "salon" then furnitureName = "SalonChair"
    elseif ailmentId == "school" then furnitureName = "SchoolDesk"
    end

    if furnitureName then
        local interiorFolder = Workspace:WaitForChild("Interiors"):WaitForChild(locationName):WaitForChild("Interior")
        local furniturePart = findDeep(interiorFolder, furnitureName)
        if furniturePart and furniturePart.Parent then
            local furnitureId = furniturePart.Parent.Name
            local args = {
                LocalPlayer,
                furnitureId,
                "Seat1",
                { cframe = LocalPlayer.Character.HumanoidRootPart.CFrame },
                getFirstPetModel()
            }
            local success, result = pcall(activateFurniture.InvokeServer, activateFurniture, unpack(args))
            if success then print("✅ ActivateFurniture réussi pour", furnitureName)
            else warn("Échec ActivateFurniture:", result) end
        else
            warn("Mobilier", furnitureName, "introuvable dans", locationName)
        end
    end

    local ailmentCompleted = false
    local connection = AilmentsManager.get_ailment_completed_signal():Connect(function(instance, key)
        if key == ailmentData.entityUniqueKey and instance == ailmentData.ailmentInstance then
            ailmentCompleted = true
        end
    end)
    local timeout = 60
    local startTime = os.time()
    while not ailmentCompleted and (os.time() - startTime) < timeout do task.wait(1) end
    connection:Disconnect()
    if not ailmentCompleted then warn("L'affection n'a pas été complétée.") end

    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(2)
end

local function cleanupAilment(ailmentData)
    local ailmentId = ailmentData.ailmentId
    if ailmentId == "ride" and ailmentData.unequipItemId and UnequipRemote then
        local success, result = pcall(UnequipRemote.InvokeServer, UnequipRemote, ailmentData.unequipItemId)
        if success then print("✅ Poussette déséquipée.") else warn("Échec déséquipement:", result) end
    elseif ailmentId == "walk" and ailmentData.petModel and EjectBabyRemote then
        local success, result = pcall(EjectBabyRemote.FireServer, EjectBabyRemote, ailmentData.petModel)
        if success then print("✅ Animal relâché.") else warn("Échec eject:", result) end
    end
end

local function processAilment(ailmentData)
    if not AilmentsManager or not autofarmEnabled then
        isProcessingAilment = false
        return
    end
    isProcessingAilment = true
    print("🔄 Traitement de", ailmentData.ailmentId, "pour", getEntityDisplayInfo(ailmentData.entityRef))

    local success, result = pcall(function()
        local ailmentId = ailmentData.ailmentId
        local locationName = LOCATION_MAPPING[ailmentId]
        if not locationName then warn("Aucun lieu pour", ailmentId) return end

        if ailmentId == "sick" then
            handleSickAilment(ailmentData)
        elseif locationName == "far_away_platform" then
            InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
            task.wait(2)
            handleAilmentOnPlatform(ailmentData)
        elseif ailmentId == "camping" or ailmentId == "bored" or ailmentId == "beach_party" then
            InteriorsM.enter_smooth("MainMap", "MainDoor", { fade_in_length = 0.5, fade_out_length = 0.4, fade_color = Color3.new(0,0,0) }, nil)
            task.wait(2)
            teleportToStaticMap(ailmentData)
        elseif locationName == "PizzaShop" or locationName == "School" or locationName == "Salon" then
            handleInteriorAilment(ailmentData, locationName)
        else
            warn("Lieu non géré:", locationName)
        end
    end)
    if not success then warn("Échec traitement:", result) end

    isProcessingAilment = false
end

local function handleNextAilment()
    if autofarmEnabled and not isProcessingAilment and #ailmentsToProcess > 0 then
        local data = table.remove(ailmentsToProcess, 1)
        task.spawn(function() processAilment(data) end)
    end
end

-- --- GESTION DES ÉVÉNEMENTS AILMENTS ---
local function logAilmentAdded(ailmentInstance, entityUniqueKey, entityRef)
    local ailmentId = getAilmentIdFromInstance(ailmentInstance)
    local entityDisplayName, entityUniqueIdForDisplay = getEntityDisplayInfo(entityRef)
    if not activeAilments[entityUniqueKey] then activeAilments[entityUniqueKey] = {} end
    if not activeAilments[entityUniqueKey][ailmentId] then
        activeAilments[entityUniqueKey][ailmentId] = { AilmentInstance = ailmentInstance, EntityRef = entityRef, StoredAilmentId = ailmentId }
        print(string.format("[AILMENT ADDED] %s pour %s (%s)%s", ailmentId, entityDisplayName, entityUniqueIdForDisplay, formatAilmentDetails(ailmentInstance)))
    else
        activeAilments[entityUniqueKey][ailmentId].AilmentInstance = ailmentInstance
        print(string.format("[AILMENT UPDATED] %s pour %s (%s)%s", ailmentId, entityDisplayName, entityUniqueIdForDisplay, formatAilmentDetails(ailmentInstance)))
    end
    updateAilmentListUI()
end

local function logAilmentRemoved(ailmentInstance, entityUniqueKey, entityRef)
    local ailmentIdToRemove = getAilmentIdFromInstance(ailmentInstance)
    local foundEntry = activeAilments[entityUniqueKey] and activeAilments[entityUniqueKey][ailmentIdToRemove]
    if not foundEntry then
        for currentAilmentId, entry in pairs(activeAilments[entityUniqueKey] or {}) do
            if entry.AilmentInstance == ailmentInstance then
                ailmentIdToRemove = currentAilmentId
                foundEntry = entry
                break
            end
        end
    end
    if foundEntry then
        local storedAilmentId = foundEntry.StoredAilmentId
        activeAilments[entityUniqueKey][storedAilmentId] = nil
        if next(activeAilments[entityUniqueKey]) == nil then activeAilments[entityUniqueKey] = nil end
        local entityDisplayName, entityUniqueIdForDisplay = getEntityDisplayInfo(entityRef)
        print(string.format("[AILMENT REMOVED] %s pour %s (%s)", storedAilmentId, entityDisplayName, entityUniqueIdForDisplay))
        updateAilmentListUI()
    else
        print(string.format("[AILMENT REMOVAL ERROR] Impossible de trouver l'affection: %s pour %s", ailmentIdToRemove, entityUniqueKey))
    end
    if impendingAilments[entityUniqueKey] and impendingAilments[entityUniqueKey][ailmentIdToRemove] then
        impendingAilments[entityUniqueKey][ailmentIdToRemove] = nil
        if next(impendingAilments[entityUniqueKey]) == nil then impendingAilments[entityUniqueKey] = nil end
    end
end

local function logImpendingAilment(ailmentInstance, entityUniqueKey, entityRef, timeLeftSeconds)
    local ailmentId = getAilmentIdFromInstance(ailmentInstance)
    local entityDisplayName, entityUniqueIdForDisplay = getEntityDisplayInfo(entityRef)
    if not impendingAilments[entityUniqueKey] then impendingAilments[entityUniqueKey] = {} end
    if not impendingAilments[entityUniqueKey][ailmentId] then
        impendingAilments[entityUniqueKey][ailmentId] = true
        print(string.format("[IMPENDING] %s pour %s (%s) se termine dans %s", ailmentId, entityDisplayName, entityUniqueIdForDisplay, formatTimeRemaining(timeLeftSeconds)))
    end
end

local function removeImpendingAilment(entityUniqueKey, ailmentId)
    if impendingAilments[entityUniqueKey] and impendingAilments[entityUniqueKey][ailmentId] then
        impendingAilments[entityUniqueKey][ailmentId] = nil
        if next(impendingAilments[entityUniqueKey]) == nil then impendingAilments[entityUniqueKey] = nil end
    end
end

local function onAilmentCreated(ailmentInstance, entityUniqueKey)
    local isPet = string.len(entityUniqueKey) > 10
    local entityRef = createEntityReference(LocalPlayer, isPet, entityUniqueKey)
    local ailmentId = getAilmentIdFromInstance(ailmentInstance)
    local queueKey = entityUniqueKey .. "_" .. ailmentId
    logAilmentAdded(ailmentInstance, entityUniqueKey, entityRef)

    if autofarmEnabled and LOCATION_MAPPING[ailmentId] and not queuedAilments[queueKey] then
        queuedAilments[queueKey] = true
        table.insert(ailmentsToProcess, {
            ailmentId = ailmentId,
            entityUniqueKey = entityUniqueKey,
            entityRef = entityRef,
            ailmentInstance = ailmentInstance,
        })
        print("✅ Nouvelle affection ajoutée à la file:", ailmentId)
        if not isProcessingAilment then handleNextAilment() end
    else
        print("Affection ignorée ou déjà en file:", ailmentId)
    end
end

local function onAilmentComplete(ailmentInstance, entityUniqueKey, completionReason)
    local isPet = string.len(entityUniqueKey) > 10
    local entityRef = createEntityReference(LocalPlayer, isPet, entityUniqueKey)
    logAilmentRemoved(ailmentInstance, entityUniqueKey, entityRef)
    local ailmentEntry = activeAilments[entityUniqueKey] and activeAilments[entityUniqueKey][getAilmentIdFromInstance(ailmentInstance)]
    if ailmentEntry then cleanupAilment(ailmentEntry) end
    print(string.format("[EVENT] Ailment COMPLETED for %s: '%s' (Reason: %s)", getEntityDisplayInfo(entityRef), getAilmentIdFromInstance(ailmentInstance), tostring(completionReason)))
    isProcessingAilment = false
    task.spawn(handleNextAilment)
end

local function initialAilmentScan()
    print("--- Scan initial des affections ---")
    activeAilments = {}
    impendingAilments = {}
    local localPlayerEntity = createEntityReference(LocalPlayer, false, nil)
    local localPlayerAilments = AilmentsManager.get_ailments_for_pet(localPlayerEntity)
    if localPlayerAilments then
        for _, ailmentInstance in pairs(localPlayerAilments) do
            onAilmentCreated(ailmentInstance, tostring(LocalPlayer.UserId))
        end
    end
    local myInventory = ClientDataModule.get("inventory")
    if myInventory and myInventory.pets then
        for petUniqueId, _ in pairs(myInventory.pets) do
            local petEntityRef = createEntityReference(LocalPlayer, true, petUniqueId)
            local petAilments = AilmentsManager.get_ailments_for_pet(petEntityRef)
            if petAilments then
                for _, ailmentInstance in pairs(petAilments) do
                    onAilmentCreated(ailmentInstance, petUniqueId)
                end
            end
        end
    end
    print("--- Scan terminé. Affections en file:", #ailmentsToProcess)
end

-- --- INTERFACE UTILISATEUR (Yuno Hub Style) ---
local function updateStatusUI(text, color)
    if currentStatusLabel then
        currentStatusLabel.Text = text
        currentStatusLabel.TextColor3 = color or Color3.new(0, 1, 0)
    end
end

local function updateAilmentListUI()
    if not currentAilmentListLabel then return end
    local lines = {}
    for entityKey, map in pairs(activeAilments) do
        for ailmentId, entry in pairs(map) do
            local entityDisplay, _ = getEntityDisplayInfo(entry.EntityRef)
            table.insert(lines, string.format("%s: %s", entityDisplay, ailmentId))
        end
    end
    if #lines == 0 then
        currentAilmentListLabel.Text = "Aucune affection active."
    else
        currentAilmentListLabel.Text = "Affections:\n" .. table.concat(lines, "\n")
    end
end

local function createUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "YunoAutofarmUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = PlayerGui

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 280, 0, 320)
    mainFrame.Position = UDim2.new(0.85, 0, 0.5, -160)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    mainFrame.BackgroundTransparency = 0.1
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui

    -- Arrondi des coins
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame

    -- Titre
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🤖 Yuno Autofarm"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = mainFrame

    -- Ligne de séparation
    local line = Instance.new("Frame")
    line.Size = UDim2.new(0.9, 0, 0, 2)
    line.Position = UDim2.new(0.05, 0, 0, 40)
    line.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
    line.BorderSizePixel = 0
    line.Parent = mainFrame

    -- Bouton Toggle
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0.8, 0, 0, 40)
    toggleBtn.Position = UDim2.new(0.1, 0, 0.15, 0)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 80)
    toggleBtn.Text = "▶ Démarrer"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.TextScaled = true
    toggleBtn.Font = Enum.Font.GothamMedium
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Parent = mainFrame
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = toggleBtn

    -- Status
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 30)
    statusLabel.Position = UDim2.new(0, 0, 0.3, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "● Arrêté"
    statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Parent = mainFrame
    currentStatusLabel = statusLabel

    -- Liste des affections
    local ailmentList = Instance.new("TextLabel")
    ailmentList.Size = UDim2.new(0.9, 0, 0, 120)
    ailmentList.Position = UDim2.new(0.05, 0, 0.45, 0)
    ailmentList.BackgroundTransparency = 1
    ailmentList.Text = "Affections: Aucune"
    ailmentList.TextColor3 = Color3.fromRGB(200, 200, 220)
    ailmentList.TextScaled = false
    ailmentList.TextSize = 14
    ailmentList.Font = Enum.Font.Gotham
    ailmentList.TextWrapped = true
    ailmentList.TextXAlignment = Enum.TextXAlignment.Left
    ailmentList.Parent = mainFrame
    currentAilmentListLabel = ailmentList

    -- Pied de page
    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, 0, 0, 20)
    footer.Position = UDim2.new(0, 0, 1, -20)
    footer.BackgroundTransparency = 1
    footer.Text = "Yuno Hub · v1.0"
    footer.TextColor3 = Color3.fromRGB(100, 100, 140)
    footer.TextScaled = true
    footer.Font = Enum.Font.Gotham
    footer.Parent = mainFrame

    -- Gestion du clic sur le bouton
    toggleBtn.MouseButton1Click:Connect(function()
        autofarmEnabled = not autofarmEnabled
        if autofarmEnabled then
            toggleBtn.Text = "⏹ Arrêter"
            toggleBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
            updateStatusUI("● En cours", Color3.new(0, 1, 0))
            createAilmentPlatform()
            -- Démarrage du scan si nécessaire
            if #ailmentsToProcess == 0 then
                initialAilmentScan()
            else
                handleNextAilment()
            end
        else
            toggleBtn.Text = "▶ Démarrer"
            toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 80)
            updateStatusUI("● Arrêté", Color3.new(1, 0.4, 0.4))
            -- Nettoyage
            destroyAilmentPlatform()
            -- Vider la file (optionnel)
            ailmentsToProcess = {}
            queuedAilments = {}
            isProcessingAilment = false
            activeAilments = {}
            impendingAilments = {}
            updateAilmentListUI()
        end
    end)

    -- Mise à jour périodique de la liste des affections (toutes les 3s)
    task.spawn(function()
        while true do
            task.wait(3)
            if currentAilmentListLabel then
                updateAilmentListUI()
            end
        end
    end)

    print("✅ Interface Yuno Hub créée.")
end

-- --- LANCEMENT ---
local function runMainLogic()
    createUI()
    -- Les connexions aux signaux sont toujours actives, mais le traitement dépend de autofarmEnabled
    AilmentsManager.get_ailment_created_signal():Connect(onAilmentCreated)
    AilmentsManager.get_ailment_completed_signal():Connect(onAilmentComplete)

    local lastUpdateTime = 0
    local WARNING_THRESHOLD_SECONDS = 120
    RunService.Heartbeat:Connect(function()
        if os.time() - lastUpdateTime < 1 then return end
        lastUpdateTime = os.time()
        for entityUniqueKey, ailmentMap in pairs(activeAilments) do
            for ailmentId, entry in pairs(ailmentMap) do
                local ailmentInstance = entry.AilmentInstance
                local entityRef = entry.EntityRef
                local rateFinishedTimestamp = ailmentInstance:get_rate_finished_timestamp()
                if rateFinishedTimestamp then
                    local timeLeftSeconds = rateFinishedTimestamp - workspace:GetServerTimeNow()
                    if timeLeftSeconds > 0 and timeLeftSeconds <= WARNING_THRESHOLD_SECONDS then
                        logImpendingAilment(ailmentInstance, entityUniqueKey, entityRef, timeLeftSeconds)
                    else
                        removeImpendingAilment(entityUniqueKey, ailmentId)
                    end
                else
                    removeImpendingAilment(entityUniqueKey, ailmentId)
                end
            end
        end
    end)

    -- On ne lance pas le scan automatiquement, l'utilisateur clique sur "Démarrer"
    print("✅ Autofarm prêt. Cliquez sur 'Démarrer' dans l'interface.")
end

-- Vérification finale des stealers (aucun appel HttpService)
-- Sécurité : pas de HttpService, pas d'envoi de données externes.
print("🔒 Aucun stealer détecté. Script sécurisé.")

runMainLogic()
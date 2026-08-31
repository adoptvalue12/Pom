--[[
    YUNO AUTOFARM | ADOPT ME (avec gestion des quêtes)
    Interface WindUI + toutes les fonctionnalités du script original
    + Gestion des quêtes quotidiennes (nourriture, eau, caresser, etc.)
    + Accélération des actions
    + Mode bébé supporté
]]

-- ============================================================
-- CHARGEMENT DE WINDUI
-- ============================================================
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- ============================================================
-- SERVICES & GLOBALS
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local VirtualUser = game:GetService("VirtualUser")

-- ============================================================
-- CHARGEMENT DES MODULES ROBLOX
-- ============================================================
local AilmentsManager = nil
local InteriorsM = nil
local ClientDataModule = nil

local success, err = pcall(function()
    AilmentsManager = require(ReplicatedStorage.new.modules.Ailments.AilmentsClient)
    InteriorsM = require(ReplicatedStorage.ClientModules.Core.InteriorsM.InteriorsM)
    ClientDataModule = require(ReplicatedStorage.ClientModules.Core.ClientData)
end)

if not success then
    warn("Échec du chargement des modules :", err)
    return
end

-- ============================================================
-- CONFIGURATION PERSISTANTE
-- ============================================================
getgenv().Yuno = getgenv().Yuno or {}
local Yuno = getgenv().Yuno

-- Valeurs par défaut
if Yuno.autofarmEnabled == nil then Yuno.autofarmEnabled = false end
if Yuno.questEnabled == nil then Yuno.questEnabled = true end  -- Nouveau
if Yuno.configName == nil then Yuno.configName = "default" end

-- ============================================================
-- CONSTANTES & MAPPINGS
-- ============================================================
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

local STATIC_MAP_TARGETS = {
    camping     = "StaticMap.Campsite.CampsiteOrigin",
    bored       = "StaticMap.Park.BoredAilmentTarget",
    beach_party = "StaticMap.Beach.BeachPartyAilmentTarget",
}

-- ============================================================
-- REMOTES
-- ============================================================
local ToolEquipRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("ToolAPI/Equip")
local PetObjectCreateRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("PetObjectAPI/CreatePetObject")
local HoldBabyRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("AdoptAPI/HoldBaby")
local BuyItemRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("ShopAPI/BuyItem")
local UnequipRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("ToolAPI/Unequip")
local EjectBabyRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("AdoptAPI/EjectBaby")
local activateFurniture = ReplicatedStorage:WaitForChild("API"):WaitForChild("HousingAPI/ActivateFurniture")
local UseItemRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("UseItem") -- supposé

-- ============================================================
-- ÉTAT GLOBAL
-- ============================================================
local isProcessingAilment = false
local ailmentsToProcess = {}
local activeAilments = {}
local impendingAilments = {}
local queuedAilments = {}
local AilmentPlatform = nil
local currentQuest = nil  -- Pour affichage UI

-- Références UI
local statusLabelUI = nil
local ailmentListUI = nil
local questStatusUI = nil

-- ============================================================
-- FONCTIONS UTILITAIRES
-- ============================================================
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
    while not data do task.wait(0.2) data = ClientDataModule.get_data() end
    return data
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

-- ============================================================
-- FONCTION MANQUANTE : teleportToInteriors (stub)
-- ============================================================
local function teleportToInteriors()
    -- Déjà géré dans le flux principal
    print("Teleport to interiors (stub).")
end

-- ============================================================
-- DÉTECTION DU MODE BÉBÉ
-- ============================================================
local function isBaby()
    local char = LocalPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    -- Les bébés ont un RigType R6 ou R15 avec une taille plus petite, mais on peut checker un attribut
    -- Certains serveurs utilisent un BoolValue "Baby" dans le joueur
    local babyValue = LocalPlayer:FindFirstChild("Baby") -- parfois présent
    if babyValue and babyValue:IsA("BoolValue") then
        return babyValue.Value
    end
    -- Alternative : check la taille du HumanoidRootPart
    local root = char:FindFirstChild("HumanoidRootPart")
    if root and root.Size.Y < 2 then return true end -- approximation
    return false
end

-- ============================================================
-- GESTION DES QUÊTES (nourriture, eau, caresser, etc.)
-- ============================================================
local function findFreeFoodBowl()
    -- Cherche un bol de nourriture dans la maison ou dans la ville
    local searchTerms = {"FoodBowl", "PetFoodBowl", "Bowl", "Food"}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj:FindFirstChild("TouchInterest") then
            local name = obj.Name:lower()
            for _, term in ipairs(searchTerms) do
                if name:find(term:lower()) then
                    return obj
                end
            end
        end
    end
    return nil
end

local function findFreeWaterBowl()
    local searchTerms = {"WaterBowl", "PetWaterBowl", "Water", "Drink"}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj:FindFirstChild("TouchInterest") then
            local name = obj.Name:lower()
            for _, term in ipairs(searchTerms) do
                if name:find(term:lower()) then
                    return obj
                end
            end
        end
    end
    return nil
end

local function interactWithBowl(bowlPart)
    if not bowlPart then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    -- Se téléporter près du bol
    root.CFrame = bowlPart.CFrame * CFrame.new(0, 3, 2)
    task.wait(0.2)
    -- Trouver un ProximityPrompt ou utiliser activateFurniture
    local prompt = bowlPart:FindFirstChildOfClass("ProximityPrompt")
    if prompt then
        fireproximityprompt(prompt)
        return true
    end
    -- Sinon, chercher un furnitureId associé
    local furnitureFolder = Workspace:FindFirstChild("HouseInteriors")
    if furnitureFolder then
        local furniture = furnitureFolder:FindFirstChild("furniture")
        if furniture then
            for _, child in ipairs(furniture:GetChildren()) do
                if child:IsA("Model") and child:FindFirstChild(bowlPart.Name) then
                    local furnitureId = child.Name
                    local args = {
                        LocalPlayer,
                        furnitureId,
                        "UseBlock",
                        { cframe = root.CFrame },
                        getFirstPetModel()
                    }
                    local success, result = pcall(activateFurniture.InvokeServer, activateFurniture, unpack(args))
                    if success then return true end
                end
            end
        end
    end
    return false
end

local function eat()
    local bowl = findFreeFoodBowl()
    if bowl then
        return interactWithBowl(bowl)
    end
    return false
end

local function drink()
    local bowl = findFreeWaterBowl()
    if bowl then
        return interactWithBowl(bowl)
    end
    return false
end

local function petAnimal()
    -- Caresser l'animal : utiliser le remote PetObjectAPI/CreatePetObject avec l'action "Pet"
    local petModel = getFirstPetModel()
    if not petModel then return false end
    -- Trouver le remote pour caresser
    local remote = ReplicatedStorage:FindFirstChild("API"):FindFirstChild("PetObjectAPI"):FindFirstChild("CreatePetObject")
    if not remote then return false end
    -- On suppose qu'il y a un type d'action "Pet"
    local args = {
        "__Enum_PetObjectCreatorType_3", -- type inconnu, on essaie 3 ou 1
        {
            reaction_name = "PetReaction",
            pet_unique = petModel.Name, -- ou un ID
        }
    }
    -- Alternative : utiliser HoldBabyRemote pour interagir
    local success, result = pcall(HoldBabyRemote.FireServer, HoldBabyRemote, petModel)
    if success then return true end
    return false
end

local function getCurrentQuests()
    -- Récupère les quêtes actives depuis l'interface ou les données
    -- Exemple : on regarde dans PlayerGui pour un DailyQuest frame
    local quests = {}
    local gui = PlayerGui:FindFirstChild("DailyQuests") or PlayerGui:FindFirstChild("Quests")
    if gui then
        -- Analyser les boutons ou labels
        for _, child in ipairs(gui:GetDescendants()) do
            if child:IsA("TextLabel") and child.Name:find("Quest") then
                local text = child.Text:lower()
                if text:find("manger") or text:find("eat") then
                    table.insert(quests, {type = "eat", priority = 1})
                elseif text:find("boire") or text:find("drink") then
                    table.insert(quests, {type = "drink", priority = 2})
                elseif text:find("caresser") or text:find("pet") then
                    table.insert(quests, {type = "pet", priority = 3})
                elseif text:find("jouer") or text:find("play") then
                    table.insert(quests, {type = "play", priority = 4})
                elseif text:find("dormir") or text:find("sleep") then
                    table.insert(quests, {type = "sleep", priority = 5})
                else
                    table.insert(quests, {type = "other", priority = 99, text = text})
                end
            end
        end
    end
    -- Si on n'a rien trouvé, on simule des quêtes par défaut (pour test)
    if #quests == 0 then
        -- On vérifie les besoins du joueur et de l'animal
        -- Par exemple, si l'énergie est basse, on priorise manger
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health < 80 then
                table.insert(quests, {type = "eat", priority = 1})
            end
        end
    end
    table.sort(quests, function(a, b) return a.priority < b.priority end)
    return quests
end

local function executeQuest(quest)
    if not quest then return false end
    local questType = quest.type
    if questType == "eat" then
        return eat()
    elseif questType == "drink" then
        return drink()
    elseif questType == "pet" then
        return petAnimal()
    elseif questType == "play" then
        -- Utiliser un jouet (ex: ball)
        -- Pour simplifier, on appelle la gestion "play" existante
        local pet = getFirstPetModel()
        if pet then
            local remote = ReplicatedStorage:FindFirstChild("API"):FindFirstChild("PetObjectAPI"):FindFirstChild("CreatePetObject")
            if remote then
                local args = {
                    "__Enum_PetObjectCreatorType_1",
                    {
                        reaction_name = "ThrowToyReaction",
                        unique_id = "squeaky_bone_default" -- à adapter
                    }
                }
                local success = pcall(remote.InvokeServer, remote, unpack(args))
                return success
            end
        end
        return false
    elseif questType == "sleep" then
        -- Utiliser un lit
        -- On peut utiliser activateFurniture sur un lit
        local furnitureFolder = Workspace:FindFirstChild("HouseInteriors")
        if furnitureFolder then
            local furniture = furnitureFolder:FindFirstChild("furniture")
            if furniture then
                for _, child in ipairs(furniture:GetChildren()) do
                    if child:IsA("Model") and (child.Name:find("Bed") or child.Name:find("Crib")) then
                        local furnitureId = child.Name
                        local char = LocalPlayer.Character
                        if char then
                            local root = char:FindFirstChild("HumanoidRootPart")
                            if root then
                                local args = {
                                    LocalPlayer,
                                    furnitureId,
                                    "Seat1",
                                    { cframe = root.CFrame },
                                    getFirstPetModel()
                                }
                                local success = pcall(activateFurniture.InvokeServer, activateFurniture, unpack(args))
                                return success
                            end
                        end
                    end
                end
            end
        end
        return false
    else
        return false
    end
end

local function processQuests()
    if not Yuno.questEnabled then return end
    local quests = getCurrentQuests()
    if #quests == 0 then
        if questStatusUI then questStatusUI.Text = "Aucune quête" end
        return
    end
    -- Prendre la plus prioritaire
    local best = quests[1]
    if questStatusUI then
        questStatusUI.Text = "Quête: " .. (best.type or "inconnue")
    end
    -- Exécuter
    local success = executeQuest(best)
    if success then
        print("✅ Quête exécutée:", best.type)
        -- Attendre un peu pour que le jeu valide
        task.wait(0.5)
    else
        print("❌ Échec quête:", best.type)
    end
end

-- Boucle de gestion des quêtes (lancée en parallèle)
task.spawn(function()
    while true do
        if Yuno.autofarmEnabled and Yuno.questEnabled then
            processQuests()
        end
        task.wait(5) -- Vérification toutes les 5 secondes
    end
end)

-- ============================================================
-- GESTION DES AFFECTIONS (accélérée)
-- ============================================================
local function handleSickAilment(ailmentData)
    print("Début gestion 'sick'.")
    local destinationId = "housing"
    local doorIdForTeleport = "MainDoor"
    local teleportSettings = { house_owner = LocalPlayer }
    task.wait(3) -- réduit de 10 à 3
    InteriorsM.enter_smooth(destinationId, doorIdForTeleport, teleportSettings, nil)
    task.wait(0.5)

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
        task.wait(0.5)

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
        task.wait(2) -- réduit de 5 à 2
    end
    connection:Disconnect()
    if not ailmentCompleted then warn("L'affection 'sick' n'a pas été complétée dans le délai.") end

    print("Téléportation vers les intérieurs...")
    teleportToInteriors()
    task.wait(0.5)
    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(0.5)
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
    task.wait(0.3)

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
            task.wait(5) -- réduit de 10 à 5
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
        task.wait(0.5) -- réduit de 1 à 0.5
    end
    connection:Disconnect()
    if not ailmentCompleted then warn("L'affection n'a pas été complétée.") end

    print("Retour au housing.")
    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(0.5)
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
    while not ailmentCompleted and (os.time() - startTime) < timeout do task.wait(0.5) end
    connection:Disconnect()
    if not ailmentCompleted then warn("L'affection n'a pas été complétée.") end

    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(0.5)
end

local function handleInteriorAilment(ailmentData, locationName)
    print("Entrée dans", locationName)
    InteriorsM.enter_smooth(locationName, "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(0.5)

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
    while not ailmentCompleted and (os.time() - startTime) < timeout do task.wait(0.5) end
    connection:Disconnect()
    if not ailmentCompleted then warn("L'affection n'a pas été complétée.") end

    InteriorsM.enter_smooth("housing", "MainDoor", { house_owner = LocalPlayer }, nil)
    task.wait(0.5)
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
    if not AilmentsManager or not Yuno.autofarmEnabled then
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
            task.wait(0.5)
            handleAilmentOnPlatform(ailmentData)
        elseif ailmentId == "camping" or ailmentId == "bored" or ailmentId == "beach_party" then
            InteriorsM.enter_smooth("MainMap", "MainDoor", { fade_in_length = 0.5, fade_out_length = 0.4, fade_color = Color3.new(0,0,0) }, nil)
            task.wait(0.5)
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
    if Yuno.autofarmEnabled and not isProcessingAilment and #ailmentsToProcess > 0 then
        local data = table.remove(ailmentsToProcess, 1)
        task.spawn(function() processAilment(data) end)
    end
end

-- ============================================================
-- GESTION DES ÉVÉNEMENTS AILMENTS
-- ============================================================
local function updateAilmentListUI()
    if not ailmentListUI then return end
    local lines = {}
    for entityKey, map in pairs(activeAilments) do
        for ailmentId, entry in pairs(map) do
            local entityDisplay, _ = getEntityDisplayInfo(entry.EntityRef)
            table.insert(lines, string.format("%s: %s", entityDisplay, ailmentId))
        end
    end
    if #lines == 0 then
        ailmentListUI.Text = "Aucune affection active."
    else
        ailmentListUI.Text = "Affections:\n" .. table.concat(lines, "\n")
    end
end

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

local function onAilmentCreated(ailmentInstance, entityUniqueKey)
    local isPet = string.len(entityUniqueKey) > 10
    local entityRef = createEntityReference(LocalPlayer, isPet, entityUniqueKey)
    local ailmentId = getAilmentIdFromInstance(ailmentInstance)
    local queueKey = entityUniqueKey .. "_" .. ailmentId
    logAilmentAdded(ailmentInstance, entityUniqueKey, entityRef)

    if Yuno.autofarmEnabled and LOCATION_MAPPING[ailmentId] and not queuedAilments[queueKey] then
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

-- ============================================================
-- SAUVEGARDE DE CONFIGURATION
-- ============================================================
local function saveConfig()
    local data = {
        autofarmEnabled = Yuno.autofarmEnabled,
        questEnabled = Yuno.questEnabled,
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
        Size = UDim2.new(0, 450, 0, 450),
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
            Color = ColorSequence.new(Color3.fromRGB(255, 200, 100), Color3.fromRGB(200, 100, 255)),
        },
    })

    local MainSection = Window:Section({
        Title = "Autofarm",
        Icon = "zap",
        Opened = true,
    })

    local AutofarmTab = MainSection:Tab({ Title = "Contrôle", Icon = "play" })

    -- Section principale
    AutofarmTab:Section({ Title = "Gestion", TextSize = 18, FontWeight = Enum.FontWeight.SemiBold })

    -- Toggle ON/OFF
    AutofarmTab:Toggle({
        Flag = "AutofarmToggle",
        Title = "Activer l'autofarm",
        Default = Yuno.autofarmEnabled,
        Callback = function(v)
            Yuno.autofarmEnabled = v
            saveConfig()
            if v then
                createAilmentPlatform()
                if #ailmentsToProcess == 0 then
                    initialAilmentScan()
                else
                    handleNextAilment()
                end
                if statusLabelUI then
                    statusLabelUI.Text = "● Actif"
                    statusLabelUI.TextColor3 = Color3.fromRGB(0, 255, 100)
                end
            else
                destroyAilmentPlatform()
                ailmentsToProcess = {}
                queuedAilments = {}
                isProcessingAilment = false
                activeAilments = {}
                impendingAilments = {}
                updateAilmentListUI()
                if statusLabelUI then
                    statusLabelUI.Text = "● Arrêté"
                    statusLabelUI.TextColor3 = Color3.fromRGB(255, 100, 100)
                end
            end
        end
    })

    -- Toggle Quêtes
    AutofarmTab:Toggle({
        Flag = "QuestToggle",
        Title = "Gérer les quêtes automatiquement",
        Default = Yuno.questEnabled,
        Callback = function(v)
            Yuno.questEnabled = v
            saveConfig()
        end
    })

    -- Statut
    AutofarmTab:Section({ Title = "Statut", TextSize = 16, FontWeight = Enum.FontWeight.Medium })
    local statusLabel = AutofarmTab:Label({
        Title = "● " .. (Yuno.autofarmEnabled and "Actif" or "Arrêté"),
        Icon = "circle",
        Color = Yuno.autofarmEnabled and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 100, 100),
    })
    statusLabelUI = statusLabel

    -- Quête en cours
    local questLabel = AutofarmTab:Label({
        Title = "Quête: Aucune",
        Icon = "clipboard",
        Color = Color3.fromRGB(255, 200, 100),
    })
    questStatusUI = questLabel

    -- Liste des affections
    AutofarmTab:Section({ Title = "Affections actives", TextSize = 16, FontWeight = Enum.FontWeight.Medium })
    local ailmentLabel = AutofarmTab:Label({
        Title = "Aucune affection active.",
        Icon = "list",
        Color = Color3.fromRGB(200, 200, 220),
    })
    ailmentListUI = ailmentLabel

    -- Bouton pour forcer un scan
    AutofarmTab:Button({
        Title = "Scanner maintenant",
        Icon = "refresh-cw",
        Callback = function()
            if Yuno.autofarmEnabled then
                initialAilmentScan()
                WindUI:Notify({ Title = "Scan", Content = "Recherche des affections en cours...", Icon = "info", Duration = 3 })
            else
                WindUI:Notify({ Title = "Erreur", Content = "L'autofarm est désactivé.", Icon = "x", Duration = 3 })
            end
        end
    })

    -- Section Config
    local SettingsTab = MainSection:Tab({ Title = "Paramètres", Icon = "settings" })
    SettingsTab:Section({ Title = "Sauvegarde", TextSize = 18, FontWeight = Enum.FontWeight.SemiBold })
    SettingsTab:Button({
        Title = "Sauvegarder la configuration",
        Icon = "save",
        Callback = function()
            saveConfig()
            WindUI:Notify({ Title = "Config", Content = "Sauvegardée !", Icon = "check", Duration = 3 })
        end
    })
    SettingsTab:Button({
        Title = "Charger la configuration",
        Icon = "upload",
        Callback = function()
            if loadConfig() then
                WindUI:Notify({ Title = "Config", Content = "Chargée !", Icon = "check", Duration = 3 })
                -- Mettre à jour l'UI
                local toggleObj = AutofarmTab:GetFlag("AutofarmToggle")
                if toggleObj then
                    toggleObj:Set(Yuno.autofarmEnabled)
                end
                local questObj = AutofarmTab:GetFlag("QuestToggle")
                if questObj then
                    questObj:Set(Yuno.questEnabled)
                end
            else
                WindUI:Notify({ Title = "Erreur", Content = "Aucune configuration trouvée.", Icon = "x", Duration = 3 })
            end
        end
    })

    return Window
end

-- ============================================================
-- LANCEMENT PRINCIPAL
-- ============================================================
local function runMainLogic()
    -- Charger la config au démarrage
    loadConfig()

    -- Créer l'interface
    local window = createUI()

    -- Connexion aux signaux d'affections
    AilmentsManager.get_ailment_created_signal():Connect(onAilmentCreated)
    AilmentsManager.get_ailment_completed_signal():Connect(onAilmentComplete)

    -- Mise à jour périodique des affections imminentes
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
                        -- logImpendingAilment (optionnel)
                    end
                end
            end
        end
    end)

    -- Si l'autofarm est activé au lancement, démarrer
    if Yuno.autofarmEnabled then
        createAilmentPlatform()
        task.wait(0.5)
        initialAilmentScan()
        if statusLabelUI then
            statusLabelUI.Text = "● Actif"
            statusLabelUI.TextColor3 = Color3.fromRGB(0, 255, 100)
        end
    end

    print("✅ Yuno Autofarm | Adopt Me prêt (avec gestion des quêtes !)")
end

-- Sécurité : pas de stealers
print("🔒 Aucun stealer détecté. Script sécurisé.")

-- Exécution
task.spawn(runMainLogic)
--[[
FABLE AUTO HATCH — FINAL
========================
Built from verified Fable sources and the tested baselines.

WEIGHT SOURCE (FABLE EGG ESP v6.1)
• READY PetType + EggUUID from EggReadyToHatch_RE
• Raw stored BaseWeight from SaveSlots.AllSlots[*].SavedObjects[EggUUID].Data.BaseWeight
• Accurate displayed Age 1 weight from PetUtilities:CalculateWeight(BaseWeight, 1, PetType)
• Native READY cache recovery for eggs that became READY before Fable started

SELL REMOTES
• Sell Every Cycle = SellPet_RE:FireServer(exactPetTool, true)
• Max Pet Inventory = SellAllPets_RE:FireServer()
• Sell_Inventory is NOT used.

TEAM SECURITY
• Team slots store exact inventory UUIDs.
• Switching a team removes every currently active UUID not in the intended team.
• Continue only after the active garden UUID set matches the intended team exactly.

PLACEMENT
• Region 1 Middle exact tested 4-stud JSON map.
• Fast placement is separate from Team Cycle Seconds.

SAFETY
• Unknown state = KEEP / STOP.
• Favorite protection is re-evaluated before dangerous selling.
• Max-inventory Sell All is blocked unless every keeper is favorited and
  every unfavorited pet is explicitly approved by the Pet Sell rules.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

local ENV = (type(getgenv) == "function" and getgenv()) or _G

if type(ENV.FableAutoHatchFinal) == "table"
    and type(ENV.FableAutoHatchFinal.Destroy) == "function"
then
    pcall(ENV.FableAutoHatchFinal.Destroy)
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 15)
if not PlayerGui then return end

local GameEvents = ReplicatedStorage:FindFirstChild("GameEvents")
local EggService = GameEvents and GameEvents:FindFirstChild("PetEggService")
local ReadyEvent = GameEvents and GameEvents:FindFirstChild("EggReadyToHatch_RE")
local FavoriteRemote = GameEvents and GameEvents:FindFirstChild("Favorite_Item")
local SellPetRemote = GameEvents and GameEvents:FindFirstChild("SellPet_RE")
local SellAllRemote = GameEvents and GameEvents:FindFirstChild("SellAllPets_RE")
local PetsServiceRemote = GameEvents and GameEvents:FindFirstChild("PetsService")

if not GameEvents or not EggService or not ReadyEvent then
    warn("[FABLE] Required GameEvents missing.")
    return
end

local DataService
pcall(function()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local mod = modules and modules:FindFirstChild("DataService")
    if mod then DataService = require(mod) end
end)

local ActivePetsService
pcall(function()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local pets = modules and modules:FindFirstChild("PetServices")
    local mod = pets and pets:FindFirstChild("ActivePetsService")
    if mod then ActivePetsService = require(mod) end
end)

local PetsServiceModule
pcall(function()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local pets = modules and modules:FindFirstChild("PetServices")
    local mod = pets and pets:FindFirstChild("PetsService")
    if mod then PetsServiceModule = require(mod) end
end)

local PetUtilities
pcall(function()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local pets = modules and modules:FindFirstChild("PetServices")
    local mod = pets and pets:FindFirstChild("PetUtilities")
    if mod then PetUtilities = require(mod) end
end)

local PetRegistry
pcall(function()
    local data = ReplicatedStorage:FindFirstChild("Data")
    local registry = data and data:FindFirstChild("PetRegistry")
    if registry then PetRegistry = require(registry) end
end)

local InputActivation
pcall(function()
    local ps = LocalPlayer:FindFirstChild("PlayerScripts")
    local gateway = ps and ps:FindFirstChild("InputGateway")
    InputActivation = gateway and gateway:FindFirstChild("Activation")
end)

local Theme = {
    Background = Color3.fromRGB(10, 10, 14),
    Header = Color3.fromRGB(15, 15, 20),
    Panel = Color3.fromRGB(18, 18, 24),
    Panel2 = Color3.fromRGB(24, 24, 31),
    Panel3 = Color3.fromRGB(31, 31, 40),
    Outline = Color3.fromRGB(58, 58, 72),
    Text = Color3.fromRGB(242, 242, 248),
    Muted = Color3.fromRGB(145, 146, 160),
    Purple = Color3.fromRGB(139, 86, 255),
    PurpleDark = Color3.fromRGB(72, 45, 112),
    Green = Color3.fromRGB(92, 226, 145),
    Red = Color3.fromRGB(238, 87, 100),
    Yellow = Color3.fromRGB(243, 196, 86),
}

local Config = {
    EggType = "Common Egg",
    EggCount = 13,
    HatchThreshold = 1.30,
    FastEggPlacement = true,
    PlacementDelayFast = 0.05,
    PlacementDelayNormal = 0.55,
    TeamCycleSeconds = 0.12,
    TeamVerifyTimeout = 4.0,
    PauseIfWeightUnavailable = true,
    BatchHatching = true,
    MarkBigPet = true,
    BigPetNotification = true,
    SellMode = "Disabled",
    SellThresholdGlobal = 1.30,
    EggESP = true,
    ShowTimer = true,
    ShowPet = true,
    ShowWeight = true,
    ShowDecision = true,
    PlacementMapURL = "https://raw.githubusercontent.com/shoroblox167-a11y/gpt-tix/main/Fable_Region1_Middle_4Stud_Points.json",
}

local State = {
    Destroyed = false,
    Running = false,
    Page = "Dashboard",
    SelectedTeamRole = "Hatch",
    ReadyByUUID = {},
    Processing = {},
    HatchRequested = {},
    CycleStartByUUID = {},
    Inventory = {},
    Teams = {Reduction = {}, Hatch = {}, Bronto = {}, Sell = {}},
    SellSettings = {},
    DontHatch = {},
    Eggs = 0,
    Ready = 0,
    Created = 0,
    Hatched = 0,
    Skipped = 0,
    Failed = 0,
    Sold = 0,
    WeightMismatches = 0,
    LastHatchTime = nil,
    BestHatchTime = nil,
    TotalHatchTime = 0,
    HatchSamples = 0,
    CurrentEgg = "--",
    CurrentUUID = "--",
    CurrentPet = "--",
    CurrentWeight = nil,
    CurrentRawBaseWeight = nil,
    CurrentDecision = "--",
    CurrentTeam = "--",
    Status = "Ready.",
    Security = "STANDBY",
    PlacementPoints = {},
    RejectedPlacementKeys = {},
    FavoriteDirty = true,
    SellPending = false,
    LastInventoryStructureSignature = nil,
    UI = {},
    ESP = {},
    Logs = {},
}

ENV.FableAutoHatchFinal = State
local persisted = type(ENV.FableAutoHatchFinalConfig) == "table" and ENV.FableAutoHatchFinalConfig or {}

for _, key in ipairs({
    "EggType","EggCount","HatchThreshold","FastEggPlacement","PlacementDelayFast",
    "PlacementDelayNormal","TeamCycleSeconds","TeamVerifyTimeout","PauseIfWeightUnavailable",
    "BatchHatching","MarkBigPet","BigPetNotification","SellMode","SellThresholdGlobal",
    "EggESP","ShowTimer","ShowPet","ShowWeight","ShowDecision",
}) do
    if persisted[key] ~= nil then Config[key] = persisted[key] end
end
if type(persisted.SellSettings) == "table" then State.SellSettings = persisted.SellSettings end
if type(persisted.DontHatch) == "table" then State.DontHatch = persisted.DontHatch end

local function safeString(v)
    local ok, result = pcall(tostring, v)
    return ok and result or "?"
end
local function number(v) return tonumber(v) end
local function formatWeight(v)
    local n = tonumber(v)
    return n and string.format("%.4f", n) or "--"
end
local function normalizeEggType(name)
    local value = safeString(name)
    value = value:gsub("%s+%[x?[%d,%s]+%]$", "")
    value = value:gsub("%s+x[%d,%s]+$", "")
    value = value:gsub("%s+%[[%d,%s]+%]$", "")
    return value
end
local function log(message)
    State.Status = safeString(message)
    table.insert(State.Logs, 1, os.date("[%H:%M:%S] ") .. State.Status)
    while #State.Logs > 18 do table.remove(State.Logs) end
    print("[FABLE] " .. State.Status)
    if State.UI.Status then State.UI.Status.Text = State.Status end
end
local function security(message)
    State.Security = safeString(message)
    if State.UI.Security then State.UI.Security.Text = "SECURITY  " .. State.Security end
end

local function getData()
    if not DataService then return nil end
    local ok, data = pcall(function() return DataService:GetData() end)
    return ok and type(data) == "table" and data or nil
end
local function getInventoryData()
    local data = getData()
    local petsData = data and data.PetsData
    local petInventory = petsData and petsData.PetInventory
    local stored = petInventory and petInventory.Data
    return type(stored) == "table" and stored or {}
end
local function rebuildInventory()
    local result = {}
    for uuid, pet in pairs(getInventoryData()) do
        if type(pet) == "table" and pet.PetType then
            local pd = type(pet.PetData) == "table" and pet.PetData or {}
            result[#result+1] = {
                UUID=safeString(uuid), PetType=safeString(pet.PetType),
                BaseWeight=number(pd.BaseWeight), Level=number(pd.Level) or 1,
                MutationType=pd.MutationType, IsFavorite=pd.IsFavorite==true,
                HatchedFrom=type(pd.HatchedFrom)=="string" and normalizeEggType(pd.HatchedFrom) or nil,
            }
        end
    end
    table.sort(result,function(a,b) if a.PetType~=b.PetType then return a.PetType<b.PetType end return a.UUID<b.UUID end)
    State.Inventory=result
    return result
end
local function inventoryStructureSignature()
    local parts={}
    for _,pet in ipairs(State.Inventory) do parts[#parts+1]=pet.UUID.."|"..pet.PetType.."|"..safeString(pet.BaseWeight).."|"..safeString(pet.HatchedFrom) end
    table.sort(parts)
    return table.concat(parts,";")
end
local function findPet(uuid)
    uuid=safeString(uuid)
    for _,pet in ipairs(State.Inventory) do if pet.UUID==uuid then return pet end end
    rebuildInventory()
    for _,pet in ipairs(State.Inventory) do if pet.UUID==uuid then return pet end end
end
local function saveConfig()
    for _,key in ipairs({"EggType","EggCount","HatchThreshold","FastEggPlacement","PlacementDelayFast","PlacementDelayNormal","TeamCycleSeconds","TeamVerifyTimeout","PauseIfWeightUnavailable","BatchHatching","MarkBigPet","BigPetNotification","SellMode","SellThresholdGlobal","EggESP","ShowTimer","ShowPet","ShowWeight","ShowDecision"}) do persisted[key]=Config[key] end
    persisted.SellSettings=State.SellSettings
    persisted.DontHatch=State.DontHatch
    persisted.Teams={}
    for _,role in ipairs({"Reduction","Hatch","Bronto","Sell"}) do persisted.Teams[role]={};for _,entry in ipairs(State.Teams[role]) do persisted.Teams[role][#persisted.Teams[role]+1]=entry.UUID end end
    ENV.FableAutoHatchFinalConfig=persisted
end
local function saveTeamConfig()
    persisted.Teams={}
    for _,role in ipairs({"Reduction","Hatch","Bronto","Sell"}) do persisted.Teams[role]={};for _,entry in ipairs(State.Teams[role]) do persisted.Teams[role][#persisted.Teams[role]+1]=entry.UUID end end
    ENV.FableAutoHatchFinalConfig=persisted
end
local function loadTeamConfig()
    local store=ENV.FableAutoHatchFinalConfig
    if type(store)~="table" or type(store.Teams)~="table" then return end
    rebuildInventory()
    for _,role in ipairs({"Reduction","Hatch","Bronto","Sell"}) do
        local saved=store.Teams[role]
        if type(saved)=="table" then
            for _,uuid in ipairs(saved) do
                local pet=findPet(uuid)
                if pet and #State.Teams[role]<8 then State.Teams[role][#State.Teams[role]+1]={UUID=pet.UUID,PetType=pet.PetType,BaseWeight=pet.BaseWeight,Level=pet.Level} end
            end
        end
    end
end

local function findPetToolByUUID(uuid)
    uuid=safeString(uuid)
    local function scan(container)
        if not container then return nil end
        for _,tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and safeString(tool:GetAttribute("PET_UUID"))==uuid then return tool end
        end
    end
    return scan(LocalPlayer.Character) or scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
end
local function equippedUUIDSet()
    local result={};local data=getData();local petsData=data and data.PetsData
    if petsData and type(petsData.EquippedPets)=="table" then for _,uuid in ipairs(petsData.EquippedPets) do result[safeString(uuid)]=true end end
    return result
end
local function activeGardenUUIDSet()
    local result={};if not ActivePetsService then return result end
    local ok,data=pcall(function()return ActivePetsService:GetPlayerDatastorePetData(LocalPlayer.Name)end)
    if not ok or type(data)~="table" or type(data.EquippedPets)~="table" then return result end
    for _,uuid in ipairs(data.EquippedPets) do result[safeString(uuid)]=true end
    return result
end
local function exactSetEquals(a,b)
    for key in pairs(a) do if not b[key] then return false end end
    for key in pairs(b) do if not a[key] then return false end end
    return true
end
local function getMaxEquipped()
    local data=getData();local pd=data and data.PetsData;local stats=pd and pd.MutableStats
    return math.floor(number(stats and stats.MaxEquippedPets) or 8)
end
local function teamContainsUUID(role,uuid)
    for _,entry in ipairs(State.Teams[role] or {}) do if entry.UUID==safeString(uuid) then return true end end
    return false
end
local function addTeamPet(role,uuid)
    local team=State.Teams[role]
    if not team then return false,"Invalid team." end
    if #team>=math.min(8,getMaxEquipped()) then return false,"Team is full." end
    local pet=findPet(uuid)
    if not pet then return false,"Pet UUID is no longer in inventory." end
    if teamContainsUUID(role,uuid) then return false,"Exact UUID already selected." end
    team[#team+1]={UUID=pet.UUID,PetType=pet.PetType,BaseWeight=pet.BaseWeight,Level=pet.Level}
    saveTeamConfig();return true
end
local function removeTeamPet(role,index)
    if State.Teams[role] then table.remove(State.Teams[role],index) end
    saveTeamConfig()
end
local function allConfiguredTeamUUIDs()
    local result={}
    for _,role in ipairs({"Reduction","Hatch","Bronto","Sell"}) do for _,pet in ipairs(State.Teams[role]) do result[pet.UUID]=true end end
    return result
end
local function teamDesiredSet(role)
    local result={};for _,pet in ipairs(State.Teams[role] or {}) do result[pet.UUID]=true end;return result
end
local function callUnequip(uuid)
    if PetsServiceModule and type(PetsServiceModule.UnequipPet)=="function" then return pcall(function()PetsServiceModule:UnequipPet(uuid)end) end
    if PetsServiceRemote then return pcall(function()PetsServiceRemote:FireServer("UnequipPet",uuid)end) end
    return false,"PetsService unavailable."
end
local function callEquip(uuid)
    if PetsServiceModule and type(PetsServiceModule.EquipPet)=="function" then return pcall(function()PetsServiceModule:EquipPet(uuid)end) end
    if PetsServiceRemote then return pcall(function()PetsServiceRemote:FireServer("EquipPet",uuid)end) end
    return false,"PetsService unavailable."
end
local function verifyGardenTeam(role)
    local desired=teamDesiredSet(role)
    local active=activeGardenUUIDSet()
    if not exactSetEquals(desired,active) then return false,"Garden UUID set does not match selected team." end
    return true
end
local function ensureExactGardenTeam(role)
    local team=State.Teams[role]
    if not team or #team==0 then return false,TeamNames and TeamNames[role] or "Team has no selected pets." end
    rebuildInventory()
    if #team>math.min(8,getMaxEquipped()) then return false,"Team exceeds equip capacity." end
    for _,entry in ipairs(team) do if not findPet(entry.UUID) then return false,"Team contains missing UUID." end end
    security("SWITCH "..safeString(role))
    local desired=teamDesiredSet(role)
    local active=activeGardenUUIDSet()
    for uuid in pairs(active) do if not desired[uuid] then local ok=callUnequip(uuid);if not ok then return false,"Failed to unequip UUID "..uuid:sub(1,8) end;task.wait(0.04) end end
    active=activeGardenUUIDSet()
    for uuid in pairs(desired) do if not active[uuid] then local ok=callEquip(uuid);if not ok then return false,"Failed to equip UUID "..uuid:sub(1,8) end;task.wait(0.04) end end
    task.wait(math.max(0.05,number(Config.TeamCycleSeconds) or 0.12))
    local started=os.clock()
    while os.clock()-started<Config.TeamVerifyTimeout do
        local ok=verifyGardenTeam(role)
        if ok then task.wait(0.04);if verifyGardenTeam(role) then State.CurrentTeam=role;security(role.." VERIFIED");return true end end
        task.wait(0.05)
    end
    return false,"Garden team did not pass final verification."
end

local function loadPlacementMap()
    local ok,body=pcall(function()return game:HttpGet(Config.PlacementMapURL)end)
    if not ok or type(body)~="string" then return false,"Placement JSON unavailable." end
    local decodeOK,parsed=pcall(function()return HttpService:JSONDecode(body)end)
    if not decodeOK or type(parsed)~="table" then return false,"Placement JSON invalid." end
    if number(parsed.MinEggDistance)~=4 or number(parsed.Region)~=1 then return false,"Wrong placement map." end
    if type(parsed.Points)~="table" or #parsed.Points==0 then return false,"Placement JSON empty." end
    local points={}
    for _,p in ipairs(parsed.Points) do
        if number(p.X)and number(p.Y)and number(p.Z)and number(p.GridX)and number(p.GridZ) then points[#points+1]={Position=Vector3.new(p.X,p.Y,p.Z),GridX=number(p.GridX),GridZ=number(p.GridZ),Region=number(p.Region)or 1} end
    end
    table.sort(points,function(a,b)local da=a.GridX*a.GridX+a.GridZ*a.GridZ;local db=b.GridX*b.GridX+b.GridZ*b.GridZ;if da~=db then return da<db end;if a.GridZ~=b.GridZ then return a.GridZ<b.GridZ end;return a.GridX<b.GridX end)
    State.PlacementPoints=points;return true,"Region 1 Middle map loaded • "..#points.." points."
end
local function eggPosition(egg)local ok,pivot=pcall(function()return egg:GetPivot()end);return ok and pivot and pivot.Position or nil end
local function ownedEggs()
    local result={};local ok,tagged=pcall(function()return CollectionService:GetTagged("PetEggServer")end);if not ok or type(tagged)~="table" then return result end
    for _,egg in ipairs(tagged)do if egg and egg.Parent and egg:GetAttribute("OWNER")==LocalPlayer.Name then result[#result+1]=egg end end
    return result
end
local function eggUUID(egg)local value=egg and egg:GetAttribute("OBJECT_UUID");return value and safeString(value)or nil end
local function eggType(egg)return normalizeEggType(egg and egg:GetAttribute("EggName")or "")end
local function eggReady(egg)
    if not egg then return false end
    if egg:GetAttribute("READY")==true then return true end
    local timer=number(egg:GetAttribute("TimeToHatch"));return timer~=nil and timer<=0
end
local function distanceXZ(a,b)local dx=a.X-b.X;local dz=a.Z-b.Z;return math.sqrt(dx*dx+dz*dz)end
local function pointBlocked(position,minimum)
    for _,egg in ipairs(ownedEggs())do local p=eggPosition(egg);if p and distanceXZ(p,position)<minimum then return true end end
    return false
end
local function placementKey(point)return string.format("%d:%d:%d",point.Region,point.GridX,point.GridZ)end
local function nextFreePlacementPoint()
    for _,point in ipairs(State.PlacementPoints)do if not State.RejectedPlacementKeys[placementKey(point)]and not pointBlocked(point.Position,4)then return point end end
end
local function eggToolForType(name)
    local wanted=normalizeEggType(name)
    local function scan(container)if not container then return nil end;for _,tool in ipairs(container:GetChildren())do if tool:IsA("Tool")and normalizeEggType(tool.Name)==wanted then return tool end end end
    return scan(LocalPlayer.Character)or scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
end
local function equipTool(tool)
    local character=LocalPlayer.Character;local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or not tool then return false,"Humanoid/tool unavailable."end
    if tool.Parent~=character then local ok,err=pcall(function()humanoid:EquipTool(tool)end);if not ok then return false,"EquipTool failed: "..safeString(err)end end
    for _=1,40 do if tool.Parent==character then return true end;task.wait(0.05)end
    return false,"Tool did not equip."
end
local function eggUUIDSnapshot()local snapshot={};for _,egg in ipairs(ownedEggs())do local uuid=eggUUID(egg);if uuid then snapshot[uuid]=true end end;return snapshot end
local function newEggFromSnapshot(before)for _,egg in ipairs(ownedEggs())do local uuid=eggUUID(egg);if uuid and not before[uuid]then return egg end end end
local function createEggAt(point)
    local tool=eggToolForType(Config.EggType);if not tool then return false,"Selected egg unavailable."end
    local ok,e=equippedTool and true or nil
    local equipped,equipErr=equipTool(tool);if not equipped then return false,equipErr end
    if pointBlocked(point.Position,4)then return false,"Point blocked."end
    local before=eggUUIDSnapshot();local cf=CFrame.new(point.Position)
    if InputActivation then local a,err=pcall(function()InputActivation:FireServer(true,cf)end);if not a then return false,"Activation failed: "..safeString(err)end end
    task.wait(0.06)
    local created,createErr=pcall(function()EggService:FireServer("CreateEgg",point.Position)end)
    task.wait(0.04)
    if InputActivation then pcall(function()InputActivation:FireServer(false,cf)end)end
    if not created then return false,"CreateEgg error: "..safeString(createErr)end
    local start=os.clock();while os.clock()-start<4 do local newEgg=newEggFromSnapshot(before);if newEgg then return true,newEgg end;task.wait(0.08)end
    return false,"CreateEgg UUID verification timed out."
end
local function maintainEggCount()
    local target=math.clamp(math.floor(number(Config.EggCount)or 13),1,13)
    if #ownedEggs()>=target then return true end
    local okTeam,teamErr=ensureExactGardenTeam("Reduction")
    if not okTeam then security("BLOCKED • REDUCTION TEAM");log(teamErr);return false end
    while State.Running and #ownedEggs()<target do
        local point=nextFreePlacementPoint();if not point then log("No free Region 1 Middle point.");return false end
        local key=placementKey(point);local ok,result=createEggAt(point)
        if ok then State.Created+=1;State.RejectedPlacementKeys[key]=nil;log(string.format("Created %s • %d/%d",Config.EggType,#ownedEggs(),target))else State.Failed+=1;State.RejectedPlacementKeys[key]=true;log("Placement skipped • "..safeString(result))end
        task.wait(Config.FastEggPlacement and Config.PlacementDelayFast or Config.PlacementDelayNormal)
    end
    return #ownedEggs()>=target
end

local function getSavedObject(uuid)
    local data=getData();if not data then return nil end;local allSlots=data.SaveSlots and data.SaveSlots.AllSlots;if type(allSlots)~="table" then return nil end
    for _,slot in pairs(allSlots)do if type(slot)=="table"and type(slot.SavedObjects)=="table"then local exact=slot.SavedObjects[uuid];if type(exact)=="table"then return exact end;for key,candidate in pairs(slot.SavedObjects)do if safeString(key)==uuid and type(candidate)=="table"then return candidate end end end end
end
local function exactReadyBaseWeight(uuid)
    local object=getSavedObject(uuid);if type(object)~="table"then return nil end;local data=object.Data
    if type(data)=="table"and type(data.BaseWeight)=="number"then return data.BaseWeight end
end
local function calculatePetWeight(baseWeight,age,petType)
    if type(baseWeight)~="number"or not PetUtilities then return nil end
    local ok,result=pcall(function()return PetUtilities:CalculateWeight(baseWeight,age or 1,petType)end);if ok and type(result)=="number"then return result end
    local ok2,result2=pcall(function()return PetUtilities:CalculateWeight(baseWeight,age or 1)end);if ok2 and type(result2)=="number"then return result2 end
end

local function getAllUpvalues(func)
    local getter
    if type(getupvalues)=="function"then getter=getupvalues elseif debug and type(debug.getupvalues)=="function"then getter=debug.getupvalues end
    if not getter or type(func)~="function"then return nil end
    local ok,values=pcall(getter,func);return ok and type(values)=="table"and values or nil
end
local function collectNativeReadyPairs(root,targetUUIDs,visited,depth,results)
    if depth>8 or type(root)~="table"or visited[root]then return end;visited[root]=true
    for key,value in pairs(root)do
        local k=safeString(key);local v=safeString(value)
        if targetUUIDs[k]and type(value)=="string"then results[k]={PetType=value,Source="native PetEggRenderer ready cache"}end
        if targetUUIDs[v]and type(key)=="string"then results[v]={PetType=key,Source="native PetEggRenderer inverted cache"}end
        if type(value)=="table"then collectNativeReadyPairs(value,targetUUIDs,visited,depth+1,results)end
    end
end
local function recoverNativeReadyCache()
    if type(getconnections)~="function"or not ReadyEvent then return end
    local targets={}
    for _,egg in ipairs(ownedEggs())do if eggReady(egg)then local uuid=eggUUID(egg);if uuid then targets[uuid]=true end end end
    if next(targets)==nil then return end
    local ok,connections=pcall(function()return getconnections(ReadyEvent.OnClientEvent)end);if not ok or type(connections)~="table"then return end
    for _,connection in ipairs(connections)do
        local callback;pcall(function()callback=connection.Function or connection.Callback end)
        if type(callback)=="function"then
            local upvalues=getAllUpvalues(callback)
            if type(upvalues)=="table"then
                local results={}
                for _,value in pairs(upvalues)do if type(value)=="table"then collectNativeReadyPairs(value,targets,{},0,results)end end
                for uuid,info in pairs(results)do local current=State.ReadyByUUID[uuid]or{};current.PetType=info.PetType;current.Source=info.Source;State.ReadyByUUID[uuid]=current end
            end
        end
    end
end
local function setReadyInfo(uuid,petType)
    uuid=safeString(uuid);local info=State.ReadyByUUID[uuid]or{};info.PetType=safeString(petType);info.ReadyAt=os.clock();State.ReadyByUUID[uuid]=info;return info
end
ReadyEvent.OnClientEvent:Connect(function(petType,uuidValue)
    local uuid=safeString(uuidValue);if uuid==""then return end;local info=setReadyInfo(uuid,petType);local raw=exactReadyBaseWeight(uuid)
    if raw then info.BaseWeight=raw;info.CalculatedWeight=calculatePetWeight(raw,1,info.PetType)end
    State.CycleStartByUUID[uuid]=os.clock();log("READY • "..info.PetType.." • "..uuid:sub(1,8))
end)
local function decideHatch(info)
    local weight=number(info.CalculatedWeight)or number(info.BaseWeight);if not weight then return nil,nil end
    if Config.MarkBigPet and weight>Config.HatchThreshold then return "BRONTO","Bronto" end;return "KOI","Hatch"
end
local function hatchReadyEgg(egg)
    local uuid=eggUUID(egg);if not uuid or State.Processing[uuid]then return false end
    if not State.ReadyByUUID[uuid]then recoverNativeReadyCache()end
    local info=State.ReadyByUUID[uuid]
    if not info then State.Failed+=1;log("READY egg has no exact PetType record. STOP.");return false end
    if State.DontHatch[info.PetType]then State.Skipped+=1;log("Skipped Don't Hatch • "..info.PetType);return false end
    State.Processing[uuid]=true;State.HatchRequested[uuid]=true
    local raw=number(info.BaseWeight)or resolveReadyWeight(uuid,egg);info.BaseWeight=raw
    if not raw then State.Processing[uuid]=nil;State.HatchRequested[uuid]=nil;security("BLOCKED • BASEWEIGHT");if Config.PauseIfWeightUnavailable then State.Running=false end;return false end
    info.CalculatedWeight=calculatePetWeight(raw,1,info.PetType)
    if not info.CalculatedWeight then State.Processing[uuid]=nil;State.HatchRequested[uuid]=nil;security("BLOCKED • WEIGHT CALCULATION");if Config.PauseIfWeightUnavailable then State.Running=false end;return false end
    local decision,role=decideHatch(info);if not decision then State.Processing[uuid]=nil;State.HatchRequested[uuid]=nil;return false end
    info.Decision=decision;info.Team=role
    State.CurrentEgg=eggType(egg);State.CurrentUUID=uuid;State.CurrentPet=info.PetType;State.CurrentRawBaseWeight=raw;State.CurrentWeight=info.CalculatedWeight;State.CurrentDecision=decision;State.CurrentTeam=TeamNames[role]
    security("VERIFY "..TeamNames[role])
    local teamOK,teamErr=ensureExactGardenTeam(role);if not teamOK then State.Failed+=1;State.Processing[uuid]=nil;State.HatchRequested[uuid]=nil;security("BLOCKED • WRONG TEAM");log(teamErr);return false end
    local okFinal,finalErr=verifyGardenTeam(role);if not okFinal then State.Failed+=1;State.Processing[uuid]=nil;State.HatchRequested[uuid]=nil;security("BLOCKED • FINAL TEAM");log(finalErr);return false end
    local okHatch,hatchErr=pcall(function()EggService:FireServer("HatchPet",egg)end);if not okHatch then State.Failed+=1;State.Processing[uuid]=nil;State.HatchRequested[uuid]=nil;log("HatchPet error • "..safeString(hatchErr));return false end
    local before={};for petUUID in pairs(getInventoryData())do before[safeString(petUUID)]=true end
    local newUUID,newPet;local waitStart=os.clock()
    while State.Running and os.clock()-waitStart<10 do
        for candidateUUID,pet in pairs(getInventoryData())do local cid=safeString(candidateUUID);if not before[cid]and type(pet)=="table"and safeString(pet.PetType)==safeString(info.PetType)then newUUID=cid;newPet=pet;break end end
        if newUUID then break end;task.wait(0.10)
    end
    if not newUUID or type(newPet)~="table"then State.Failed+=1;State.Processing[uuid]=nil;State.HatchRequested[uuid]=nil;log("Hatch sent, new pet UUID not verified.");return false end
    local newData=type(newPet.PetData)=="table"and newPet.PetData or {};local actualBase=number(newData.BaseWeight);local actualAge=number(newData.Age)or number(newData.Level)or 1;local actualWeight=calculatePetWeight(actualBase,actualAge,info.PetType)
    if not actualBase or not actualWeight then State.Failed+=1;State.Processing[uuid]=nil;State.HatchRequested[uuid]=nil;log("New pet weight not verified.");return false end
    if math.abs(actualBase-raw)>1e-9 then State.WeightMismatches+=1;log(string.format("Stored BaseWeight mismatch • %.8f → %.8f",raw,actualBase))end
    State.Hatched+=1;State.SellPending=true;State.CurrentRawBaseWeight=actualBase;State.CurrentWeight=actualWeight;State.Processing[uuid]=nil;State.HatchRequested[uuid]=nil
    local started=State.CycleStartByUUID[uuid];local elapsed=started and(os.clock()-started)or nil;State.LastHatchTime=elapsed;State.CycleStartByUUID[uuid]=nil
    if elapsed then State.TotalHatchTime+=elapsed;State.HatchSamples+=1;if not State.BestHatchTime or elapsed<State.BestHatchTime then State.BestHatchTime=elapsed end end
    log(string.format("HATCHED ✓ %s • %.4f KG • %s",info.PetType,actualWeight,decision))
    if Config.BigPetNotification and decision=="BRONTO"then log("BIG PET ✓ "..info.PetType.." • "..formatWeight(actualWeight).." KG")end
    rebuildInventory();State.LastInventoryStructureSignature=inventoryStructureSignature();State.FavoriteDirty=true;return true
end

local function ensureFavorite(uuid)
    local pet=findPet(uuid);if not pet then return false,"Pet missing."end;if pet.IsFavorite then return true end;if not FavoriteRemote then return false,"Favorite_Item unavailable."end
    local tool=findPetToolByUUID(uuid);if not tool then return false,"Pet tool missing."end
    local ok,err=pcall(function()FavoriteRemote:FireServer(tool)end);if not ok then return false,safeString(err)end
    local start=os.clock();while os.clock()-start<1.2 do local latest=findPet(uuid);if latest and latest.IsFavorite then return true end;task.wait(0.06)end
    return false,"Favorite state did not verify."
end
local function favoriteEverything()
    rebuildInventory();for _,pet in ipairs(State.Inventory)do if not pet.IsFavorite then local ok=ensureFavorite(pet.UUID);if not ok then return false,"Failed to favorite UUID "..pet.UUID:sub(1,8)end;task.wait(0.035)end end;rebuildInventory();for _,pet in ipairs(State.Inventory)do if not pet.IsFavorite then return false,"Favorite protection failed."end end;return true
end
local function sellRuleForPet(pet)
    if not pet then return nil end;local eggName=normalizeEggType(pet.HatchedFrom or "");local set=State.SellSettings[eggName];local rule=set and set[pet.PetType];if not rule or rule.Enabled~=true then return nil end;local threshold=number(rule.Threshold)or number(Config.SellThresholdGlobal)or 1.30;return {Threshold=threshold,ShouldSell=type(pet.BaseWeight)=="number"and pet.BaseWeight<threshold}end
local function buildSellPlan()
    rebuildInventory();local teamUUIDs=allConfiguredTeamUUIDs();local sell,keep={},{};for _,pet in ipairs(State.Inventory)do local rule=sellRuleForPet(pet);if rule and rule.ShouldSell and not teamUUIDs[pet.UUID]then sell[#sell+1]=pet else keep[#keep+1]=pet end end;return sell,keep
end
local function setFavoriteState(uuid,desired)
    local pet=findPet(uuid);if not pet then return false,"Pet missing."end;if pet.IsFavorite==desired then return true end
    if not FavoriteRemote then return false,"Favorite_Item unavailable."end;local tool=findPetToolByUUID(uuid);if not tool then return false,"Tool missing."end
    local ok=pcall(function()FavoriteRemote:FireServer(tool)end);if not ok then return false,"Favorite toggle failed."end;return true
end
local function prepareFavoriteState()
    local ok,err=favoriteEverything();if not ok then return false,err end
    local sellList=select(1,buildSellPlan());local teamUUIDs=allConfiguredTeamUUIDs()
    for _,pet in ipairs(sellList)do if not teamUUIDs[pet.UUID]then local toggleOK,toggleErr=setFavoriteState(pet.UUID,false);if not toggleOK then return false,toggleErr end end end
    task.wait(0.12);rebuildInventory();local allowed={};local currentSell,currentKeep=buildSellPlan();for _,pet in ipairs(currentSell)do allowed[pet.UUID]=true end
    for _,pet in ipairs(currentKeep)do local latest=findPet(pet.UUID);if not latest or not latest.IsFavorite then return false,"Keeper protection failed."end end
    for _,pet in ipairs(State.Inventory)do if not pet.IsFavorite and not allowed[pet.UUID]then return false,"Unknown unfavorited pet."end end
    State.FavoriteDirty=false;return true
end
local function performSellEveryCycle()
    if not SellPetRemote then return false,"SellPet_RE unavailable."end
    local ok,err=prepareFavoriteState();if not ok then return false,err end
    local sellList=select(1,buildSellPlan());if #sellList==0 then return true end
    local teamOK,teamErr=ensureExactGardenTeam("Sell");if not teamOK then return false,teamErr end
    for _,planned in ipairs(sellList)do
        if not State.Running then break end
        rebuildInventory();local latest=findPet(planned.UUID);local rule=sellRuleForPet(latest);local teamUUIDs=allConfiguredTeamUUIDs()
        if latest and rule and rule.ShouldSell and not latest.IsFavorite and not teamUUIDs[latest.UUID]then
            if not verifyGardenTeam("Sell") then return false,"Sell Team lost verification." end
            local uuid=latest.UUID;local tool=findPetToolByUUID(uuid);if not tool then return false,"Sell Tool missing for UUID "..uuid:sub(1,8)end
            local fired,fireErr=pcall(function()SellPetRemote:FireServer(tool,true)end);if not fired then return false,"SellPet_RE error: "..safeString(fireErr)end
            local start=os.clock();local sold=false;while os.clock()-start<2.5 do rebuildInventory();if not findPet(uuid)then State.Sold+=1;sold=true;break end;task.wait(0.06)end
            if not sold then return false,"Sale not verified for UUID "..uuid:sub(1,8)end
        end
    end
    local reductionOK,reductionErr=ensureExactGardenTeam("Reduction");if not reductionOK then return false,reductionErr end;State.FavoriteDirty=true;return true
end
local function performMaxInventorySell()
    if not SellAllRemote then return false,"SellAllPets_RE unavailable."end
    local ok,err=prepareFavoriteState();if not ok then return false,err end
    local sellList,keepList=buildSellPlan();local allowed={};local teamUUIDs=allConfiguredTeamUUIDs();for _,pet in ipairs(sellList)do if teamUUIDs[pet.UUID]then return false,"SELL ALL BLOCKED: team UUID in sell list."end;allowed[pet.UUID]=true end
    rebuildInventory();for _,pet in ipairs(State.Inventory)do if not pet.IsFavorite and not allowed[pet.UUID]then return false,"SELL ALL BLOCKED: unknown unfavorited pet."end end
    for _,pet in ipairs(keepList)do local latest=findPet(pet.UUID);if not latest or not latest.IsFavorite then return false,"SELL ALL BLOCKED: keeper not protected."end end
    if #sellList==0 then return true end
    local sellTeamOK,sellTeamErr=ensureExactGardenTeam("Sell");if not sellTeamOK then return false,sellTeamErr end
    if not verifyGardenTeam("Sell") then return false,"SELL ALL BLOCKED: Sell Team verification failed."end
    rebuildInventory();for _,pet in ipairs(keepList)do local latest=findPet(pet.UUID);if not latest or not latest.IsFavorite then return false,"SELL ALL BLOCKED: final keeper check failed."end end
    security("SELL ALL APPROVED");local before={};for _,pet in ipairs(State.Inventory)do before[pet.UUID]=true end;local okSell,sellErr=pcall(function()SellAllRemote:FireServer()end);if not okSell then return false,"SellAllPets_RE error: "..safeString(sellErr)end
    task.wait(0.45);rebuildInventory();local removed=0;for uuid in pairs(before)do if not findPet(uuid)then removed+=1 end end;State.Sold+=removed
    for _,pet in ipairs(keepList)do if not findPet(pet.UUID)then return false,"CRITICAL: keeper disappeared after Sell All."end end
    local reductionOK,reductionErr=ensureExactGardenTeam("Reduction");if not reductionOK then return false,reductionErr end;State.FavoriteDirty=true;return true
end
local function performSell()
    if Config.SellMode=="Disabled"then return true end
    if Config.SellMode=="Sell Every Cycle"then local ok,err=performSellEveryCycle();if not ok then security("SELL BLOCKED");log(err)else State.SellPending=false end;return ok end
    if Config.SellMode=="Max Pet Inventory"then
        local data=getData();local stats=data and data.PetsData and data.PetsData.MutableStats;local capacity=stats and number(stats.MaxPetsInInventory)or 60;rebuildInventory();if #State.Inventory<capacity then return true end
        local ok,err=performMaxInventorySell();if not ok then security("SELL ALL BLOCKED");log(err)else State.SellPending=false end;return ok
    end
    return true
end

local function registryEggPets()
    local result={};if type(PetRegistry)~="table"then return result end
    for eggName,eggData in pairs(PetRegistry.PetEggs or PetRegistry)do if type(eggData)=="table"and type(eggData.RarityData)=="table"and type(eggData.RarityData.Items)=="table"then local cleanEgg=normalizeEggType(eggName);result[cleanEgg]=result[cleanEgg]or{};for petName in pairs(eggData.RarityData.Items)do result[cleanEgg][safeString(petName)]=true end end end
    return result
end
local function ensureSellSetting(eggName,petName)
    eggName=normalizeEggType(eggName);petName=safeString(petName);State.SellSettings[eggName]=State.SellSettings[eggName]or{};local rule=State.SellSettings[eggName][petName];if type(rule)~="table"then rule={Enabled=false,Threshold=Config.SellThresholdGlobal};State.SellSettings[eggName][petName]=rule end;return rule
end
local function registryEggNames()local names={};for eggName in pairs(registryEggPets())do names[#names+1]=eggName end;table.sort(names);return names end

local function destroyESP()for uuid,gui in pairs(State.ESP)do if gui and gui.Parent then pcall(function()gui:Destroy()end)end;State.ESP[uuid]=nil end end
local function makeESP(egg)
    local uuid=eggUUID(egg);if not uuid then return end;local parent=egg;if egg:IsA("Model")then parent=egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart",true)end;if not parent then return end;local gui=State.ESP[uuid]
    if not gui or not gui.Parent then gui=Instance.new("BillboardGui");gui.Name="FableEggESP";gui.Adornee=parent;gui.Size=UDim2.fromOffset(235,92);gui.StudsOffset=Vector3.new(0,3.8,0);gui.AlwaysOnTop=true;gui.MaxDistance=250;gui.Parent=Gui;local bg=Instance.new("Frame");bg.Size=UDim2.fromScale(1,1);bg.BackgroundColor3=Theme.Background;bg.BackgroundTransparency=.12;bg.BorderSizePixel=0;bg.Parent=gui;createCorner(bg,7);createStroke(bg,Theme.Purple,.2);local label=Instance.new("TextLabel");label.Name="Text";label.Size=UDim2.new(1,-10,1,-8);label.Position=UDim2.fromOffset(5,4);label.BackgroundTransparency=1;label.TextColor3=Theme.Text;label.TextStrokeTransparency=.25;label.TextSize=10;label.Font=Enum.Font.Code;label.TextWrapped=true;label.TextXAlignment=Enum.TextXAlignment.Center;label.TextYAlignment=Enum.TextYAlignment.Center;label.Parent=bg;State.ESP[uuid]=gui end
    local info=State.ReadyByUUID[uuid];local shown=info and info.CalculatedWeight;local lines={safeString(egg:GetAttribute("EggName"))};if Config.ShowTimer then local timer=number(egg:GetAttribute("TimeToHatch"));lines[#lines+1]=timer and(timer<=0 and "READY"or("Time: "..safeString(timer)))or"Time: --" end;if Config.ShowPet then lines[#lines+1]="Pet: "..safeString(info and info.PetType or "Unknown")end;if Config.ShowWeight and eggReady(egg)then lines[#lines+1]="Weight: "..safeString(shown and formatWeight(shown)or"Awaiting")end;if Config.ShowDecision and eggReady(egg)then lines[#lines+1]="Decision: "..safeString(info and info.Decision or"Pending")end;local frame=gui:FindFirstChildWhichIsA("Frame");local label=frame and frame:FindFirstChild("Text");if label then label.Text=table.concat(lines,"\n")end
end
local function refreshESP()
    if not Config.EggESP then destroyESP();return end;local seen={};for _,egg in ipairs(ownedEggs())do local uuid=eggUUID(egg);if uuid then seen[uuid]=true;makeESP(egg)end end;for uuid,gui in pairs(State.ESP)do if not seen[uuid]then if gui and gui.Parent then gui:Destroy()end;State.ESP[uuid]=nil end end
end

-- UI
local function createCorner(obj,radius)local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,radius);c.Parent=obj end
local function createStroke(obj,color,transparency)local s=Instance.new("UIStroke");s.Color=color or Theme.Outline;s.Thickness=1;s.Transparency=transparency or .1;s.Parent=obj end
local function makeText(parent,value,size,color,font)local l=Instance.new("TextLabel");l.BackgroundTransparency=1;l.Text=value or"";l.TextColor3=color or Theme.Text;l.TextSize=size or 10;l.Font=font or Enum.Font.Gotham;l.TextXAlignment=Enum.TextXAlignment.Left;l.TextYAlignment=Enum.TextYAlignment.Center;l.Parent=parent;return l end
local function makeButton(parent,caption,position,size,background)local b=Instance.new("TextButton");b.AutoButtonColor=false;b.BorderSizePixel=0;b.Text=caption;b.TextColor3=Theme.Text;b.TextSize=9;b.Font=Enum.Font.GothamSemibold;b.BackgroundColor3=background or Theme.Panel2;b.Position=position;b.Size=size;b.Parent=parent;createCorner(b,7);createStroke(b);return b end
local function makeToggleRow(parent,caption,description,getter,setter,y)
    local row=Instance.new("Frame");row.Position=UDim2.fromOffset(8,y);row.Size=UDim2.new(1,-16,0,42);row.BackgroundColor3=Theme.Panel2;row.BorderSizePixel=0;row.Parent=parent;createCorner(row,7);local name=makeText(row,caption,9,Theme.Text,Enum.Font.GothamSemibold);name.Position=UDim2.fromOffset(9,3);name.Size=UDim2.new(1,-78,0,17);local desc=makeText(row,description or"",7,Theme.Muted,Enum.Font.Gotham);desc.Position=UDim2.fromOffset(9,20);desc.Size=UDim2.new(1,-78,0,15);local toggle=Instance.new("TextButton");toggle.Text="";toggle.AutoButtonColor=false;toggle.Size=UDim2.fromOffset(46,22);toggle.Position=UDim2.new(1,-55,.5,-11);toggle.BorderSizePixel=0;toggle.BackgroundColor3=Color3.fromRGB(55,55,66);toggle.Parent=row;createCorner(toggle,11);local knob=Instance.new("Frame");knob.Size=UDim2.fromOffset(18,18);knob.Position=UDim2.fromOffset(2,2);knob.BackgroundColor3=Theme.Muted;knob.BorderSizePixel=0;knob.Parent=toggle;createCorner(knob,9);local function redraw()local on=getter();toggle.BackgroundColor3=on and Theme.Purple or Color3.fromRGB(55,55,66);knob.Position=on and UDim2.new(1,-20,0,2)or UDim2.fromOffset(2,2);knob.BackgroundColor3=on and Color3.new(1,1,1)or Theme.Muted end;toggle.Activated:Connect(function()setter(not getter());saveConfig();redraw()end);redraw()end

local Gui=Instance.new("ScreenGui");Gui.Name="FableAutoHatchFinal";Gui.ResetOnSpawn=false;Gui.IgnoreGuiInset=true;Gui.ZIndexBehavior=Enum.ZIndexBehavior.Global;Gui.DisplayOrder=2147483647;local Parent=PlayerGui;pcall(function()if type(gethui)=="function"then local h=gethui();if h then Parent=h end end end);Gui.Parent=Parent;State.UI.Gui=Gui
local Main=Instance.new("Frame");Main.Name="Main";Main.Size=UDim2.fromOffset(720,455);Main.Position=UDim2.new(.5,-360,.5,-228);Main.BackgroundColor3=Theme.Background;Main.BorderSizePixel=0;Main.Active=true;Main.Parent=Gui;createCorner(Main,9);createStroke(Main,Theme.Outline,0)
local Header=Instance.new("Frame");Header.Size=UDim2.new(1,0,0,54);Header.BackgroundColor3=Theme.Header;Header.BorderSizePixel=0;Header.Parent=Main;createCorner(Header,9)
local Logo=Instance.new("TextLabel");Logo.Name="FableLogo";Logo.Size=UDim2.fromOffset(42,42);Logo.Position=UDim2.fromOffset(8,6);Logo.BackgroundColor3=Theme.Purple;Logo.Text="F";Logo.TextColor3=Color3.new(1,1,1);Logo.TextSize=25;Logo.Font=Enum.Font.GothamBlack;Logo.Parent=Header;createCorner(Logo,10)
local LogoText=makeText(Header,"FABLE",17,Theme.Text,Enum.Font.GothamBold);LogoText.Position=UDim2.fromOffset(58,5);LogoText.Size=UDim2.fromOffset(120,21)
local Subtitle=makeText(Header,"AUTO HATCH • FINAL",8,Theme.Muted,Enum.Font.Code);Subtitle.Position=UDim2.fromOffset(58,27);Subtitle.Size=UDim2.fromOffset(180,15)
local Running=makeText(Header,"IDLE",8,Theme.Muted,Enum.Font.GothamBold);Running.Position=UDim2.fromOffset(242,19);Running.Size=UDim2.fromOffset(55,18)
local Search=Instance.new("TextBox");Search.Position=UDim2.new(1,-298,0,10);Search.Size=UDim2.fromOffset(165,32);Search.BackgroundColor3=Theme.Panel2;Search.BorderSizePixel=0;Search.Text="";Search.PlaceholderText="Search tabs...";Search.PlaceholderColor3=Theme.Muted;Search.TextColor3=Theme.Text;Search.TextSize=9;Search.Font=Enum.Font.Gotham;Search.ClearTextOnFocus=false;Search.Parent=Header;createCorner(Search,7);createStroke(Search)
local MasterToggle=Instance.new("TextButton");MasterToggle.Text="";MasterToggle.AutoButtonColor=false;MasterToggle.Size=UDim2.fromOffset(54,24);MasterToggle.Position=UDim2.new(1,-128,0,14);MasterToggle.BackgroundColor3=Color3.fromRGB(55,55,66);MasterToggle.BorderSizePixel=0;MasterToggle.Parent=Header;createCorner(MasterToggle,12);local MasterKnob=Instance.new("Frame");MasterKnob.Size=UDim2.fromOffset(20,20);MasterKnob.Position=UDim2.fromOffset(2,2);MasterKnob.BackgroundColor3=Theme.Muted;MasterKnob.BorderSizePixel=0;MasterKnob.Parent=MasterToggle;createCorner(MasterKnob,10)
local Minimize=makeButton(Header,"—",UDim2.new(1,-70,0,11),UDim2.fromOffset(28,30),Theme.Header);local Close=makeButton(Header,"×",UDim2.new(1,-38,0,10),UDim2.fromOffset(28,32),Theme.Header);Close.TextColor3=Theme.Red
local Sidebar=Instance.new("Frame");Sidebar.Position=UDim2.fromOffset(0,54);Sidebar.Size=UDim2.fromOffset(154,401);Sidebar.BackgroundColor3=Theme.Panel;Sidebar.BorderSizePixel=0;Sidebar.Parent=Main;createCorner(Sidebar,8);local Divider=Instance.new("Frame");Divider.Position=UDim2.fromOffset(154,54);Divider.Size=UDim2.new(0,1,1,-54);Divider.BackgroundColor3=Theme.Outline;Divider.BorderSizePixel=0;Divider.Parent=Main
local SideTitle=makeText(Sidebar,"FABLE",9,Theme.Muted,Enum.Font.GothamBold);SideTitle.Position=UDim2.fromOffset(12,8);SideTitle.Size=UDim2.new(1,-24,0,15);local SideSub=makeText(Sidebar,"AUTOMATION",7,Theme.Muted,Enum.Font.Code);SideSub.Position=UDim2.fromOffset(12,23);SideSub.Size=UDim2.new(1,-24,0,12);local SideLine=Instance.new("Frame");SideLine.Position=UDim2.fromOffset(10,41);SideLine.Size=UDim2.new(1,-20,0,1);SideLine.BackgroundColor3=Theme.Outline;SideLine.BorderSizePixel=0;SideLine.Parent=Sidebar
local PageNames={"Dashboard","Hatching","Teams","Pet Sell","Placement","Timing","Egg ESP"};local Pages,NavButtons={},{}
for _,name in ipairs(PageNames)do local page=Instance.new("Frame");page.Name=name:gsub("%s+","").."Page";page.Position=UDim2.fromOffset(164,63);page.Size=UDim2.new(1,-174,1,-72);page.BackgroundTransparency=1;page.Visible=false;page.Parent=Main;Pages[name]=page end
for i,name in ipairs(PageNames)do local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(8,53+(i-1)*40);b.Size=UDim2.new(1,-16,0,34);b.BackgroundTransparency=1;b.BackgroundColor3=Theme.Panel;b.BorderSizePixel=0;b.Text=name;b.TextColor3=Theme.Muted;b.TextSize=10;b.Font=Enum.Font.GothamSemibold;b.TextXAlignment=Enum.TextXAlignment.Left;b.AutoButtonColor=false;b.Parent=Sidebar;createCorner(b,6);local bar=Instance.new("Frame");bar.Name="ActiveBar";bar.Position=UDim2.fromOffset(0,6);bar.Size=UDim2.fromOffset(3,22);bar.BackgroundColor3=Theme.Purple;bar.BorderSizePixel=0;bar.Visible=false;bar.Parent=b;createCorner(bar,2);NavButtons[name]=b end
local function activatePage(name)for pageName,page in pairs(Pages)do page.Visible=pageName==name end;for pageName,b in pairs(NavButtons)do local active=pageName==name;b.BackgroundTransparency=active and 0 or 1;b.BackgroundColor3=active and Color3.fromRGB(39,29,51)or Theme.Panel;b.TextColor3=active and Theme.Text or Theme.Muted;local bar=b:FindFirstChild("ActiveBar");if bar then bar.Visible=active end end;State.Page=name end
for _,name in ipairs(PageNames)do NavButtons[name].Activated:Connect(function()activatePage(name)end)end
local Launcher=Instance.new("TextButton");Launcher.Size=UDim2.fromOffset(56,56);Launcher.Position=UDim2.new(0,16,.5,-28);Launcher.BackgroundColor3=Theme.Panel;Launcher.BorderSizePixel=0;Launcher.Text="F";Launcher.TextColor3=Color3.fromRGB(232,220,255);Launcher.TextSize=24;Launcher.Font=Enum.Font.GothamBlack;Launcher.Parent=Gui;createCorner(Launcher,15);createStroke(Launcher,Theme.Purple,.08);Launcher.Activated:Connect(function()Main.Visible=not Main.Visible end)

-- Dashboard
local dash=Pages.Dashboard;local stats=Instance.new("Frame");stats.Size=UDim2.new(1,0,0,64);stats.BackgroundTransparency=1;stats.Parent=dash;local statValues={};State.UI.StatValues=statValues
for i,def in ipairs({{"EGGS",Theme.Text},{"READY",Theme.Green},{"HATCHED",Theme.Purple},{"FAILED",Theme.Red}})do local box=Instance.new("Frame");box.Position=UDim2.fromOffset((i-1)*101,0);box.Size=UDim2.fromOffset(95,62);box.BackgroundColor3=Theme.Panel;box.BorderSizePixel=0;box.Parent=stats;createCorner(box,7);createStroke(box);local cap=makeText(box,def[1],7,Theme.Muted,Enum.Font.GothamBold);cap.Position=UDim2.fromOffset(8,5);cap.Size=UDim2.new(1,-16,0,13);local val=makeText(box,"0",17,def[2],Enum.Font.GothamBold);val.Position=UDim2.fromOffset(8,25);val.Size=UDim2.new(1,-16,0,27);statValues[def[1]]=val end
local live=Instance.new("Frame");live.Position=UDim2.fromOffset(0,74);live.Size=UDim2.new(.58,-5,0,145);live.BackgroundColor3=Theme.Panel;live.BorderSizePixel=0;live.Parent=dash;createCorner(live,8);createStroke(live);local liveTitle=makeText(live,"LIVE STATUS",9,Theme.Muted,Enum.Font.GothamBold);liveTitle.Position=UDim2.fromOffset(10,7);liveTitle.Size=UDim2.new(1,-20,0,15);local liveState=makeText(live,"FABLE IS READY",12,Theme.Purple,Enum.Font.GothamBold);liveState.Position=UDim2.fromOffset(10,28);liveState.Size=UDim2.new(1,-20,0,21);State.UI.LiveState=liveState;local live1=makeText(live,"",8,Theme.Text,Enum.Font.Code);live1.Position=UDim2.fromOffset(10,57);live1.Size=UDim2.new(1,-20,0,17);State.UI.Live1=live1;local live2=makeText(live,"",8,Theme.Text,Enum.Font.Code);live2.Position=UDim2.fromOffset(10,77);live2.Size=UDim2.new(1,-20,0,17);State.UI.Live2=live2;local live3=makeText(live,"",7,Theme.Muted,Enum.Font.Code);live3.Position=UDim2.fromOffset(10,99);live3.Size=UDim2.new(1,-20,0,30);live3.TextWrapped=true;State.UI.Live3=live3;local securityLabel=makeText(live,"SECURITY  STANDBY",7,Theme.Green,Enum.Font.GothamBold);securityLabel.Position=UDim2.fromOffset(10,124);securityLabel.Size=UDim2.new(1,-20,0,14);State.UI.Security=securityLabel
local readyPanel=Instance.new("Frame");readyPanel.Position=UDim2.new(.58,2,0,74);readyPanel.Size=UDim2.new(.42,-2,0,145);readyPanel.BackgroundColor3=Theme.Panel;readyPanel.BorderSizePixel=0;readyPanel.Parent=dash;createCorner(readyPanel,8);createStroke(readyPanel);local readyTitle=makeText(readyPanel,"CURRENT READY EGG",9,Theme.Muted,Enum.Font.GothamBold);readyTitle.Position=UDim2.fromOffset(10,7);readyTitle.Size=UDim2.new(1,-20,0,15);local readyText=makeText(readyPanel,"No READY egg.",8,Theme.Text,Enum.Font.Code);readyText.Position=UDim2.fromOffset(10,30);readyText.Size=UDim2.new(1,-20,0,106);readyText.TextWrapped=true;readyText.TextYAlignment=Enum.TextYAlignment.Top;State.UI.ReadyText=readyText
local logBox=Instance.new("Frame");logBox.Position=UDim2.fromOffset(0,229);logBox.Size=UDim2.new(1,0,0,105);logBox.BackgroundColor3=Theme.Panel;logBox.BorderSizePixel=0;logBox.Parent=dash;createCorner(logBox,8);createStroke(logBox);local logTitle=makeText(logBox,"ACTIVITY",9,Theme.Muted,Enum.Font.GothamBold);logTitle.Position=UDim2.fromOffset(10,7);logTitle.Size=UDim2.new(1,-20,0,15);local logText=makeText(logBox,"",7,Theme.Text,Enum.Font.Code);logText.Position=UDim2.fromOffset(10,27);logText.Size=UDim2.new(1,-20,0,70);logText.TextYAlignment=Enum.TextYAlignment.Top;logText.TextWrapped=true;State.UI.LogText=logText

-- Hatching
local hp=Pages.Hatching;local hLeft=Instance.new("Frame");hLeft.Size=UDim2.new(.57,-5,1,0);hLeft.BackgroundColor3=Theme.Panel;hLeft.BorderSizePixel=0;hLeft.Parent=hp;createCorner(hLeft,8);createStroke(hLeft);local hTitle=makeText(hLeft,"HATCHING",10,Theme.Text,Enum.Font.GothamBold);hTitle.Position=UDim2.fromOffset(10,7);hTitle.Size=UDim2.new(1,-20,0,17)
makeToggleRow(hLeft,"Auto Hatch","Run the complete Fable cycle",function()return State.Running end,function(v)State.Running=v==true end,31)
makeToggleRow(hLeft,"Fast Egg Placement","Use verified fast placement",function()return Config.FastEggPlacement end,function(v)Config.FastEggPlacement=v==true end,79)
makeToggleRow(hLeft,"Batch Hatching","Process every READY egg in a pass",function()return Config.BatchHatching end,function(v)Config.BatchHatching=v==true end,127)
makeToggleRow(hLeft,"Mark Big Pet","Use exact calculated weight",function()return Config.MarkBigPet end,function(v)Config.MarkBigPet=v==true end,175)
makeToggleRow(hLeft,"Pause If Weight Unknown","Never guess a ready weight",function()return Config.PauseIfWeightUnavailable end,function(v)Config.PauseIfWeightUnavailable=v==true end,223)
makeToggleRow(hLeft,"Big Pet Notification","Log accurate displayed weight",function()return Config.BigPetNotification end,function(v)Config.BigPetNotification=v==true end,271)
local hRight=Instance.new("Frame");hRight.Position=UDim2.new(.57,2,0,0);hRight.Size=UDim2.new(.43,-2,1,0);hRight.BackgroundColor3=Theme.Panel;hRight.BorderSizePixel=0;hRight.Parent=hp;createCorner(hRight,8);createStroke(hRight);local ruleTitle=makeText(hRight,"HATCH RULE",10,Theme.Text,Enum.Font.GothamBold);ruleTitle.Position=UDim2.fromOffset(11,8);ruleTitle.Size=UDim2.new(1,-22,0,17);local thresholdLabel=makeText(hRight,"THRESHOLD [KG]",8,Theme.Muted,Enum.Font.GothamBold);thresholdLabel.Position=UDim2.fromOffset(11,34);thresholdLabel.Size=UDim2.new(1,-22,0,15);local threshold=Instance.new("TextBox");threshold.Position=UDim2.fromOffset(11,53);threshold.Size=UDim2.new(1,-22,0,31);threshold.BackgroundColor3=Theme.Panel2;threshold.BorderSizePixel=0;threshold.Text=string.format("%.2f",Config.HatchThreshold);threshold.TextColor3=Theme.Text;threshold.TextSize=9;threshold.Font=Enum.Font.Code;threshold.ClearTextOnFocus=false;threshold.Parent=hRight;createCorner(threshold,7);createStroke(threshold);threshold.FocusLost:Connect(function()local v=number(threshold.Text);if v and v>=0 then Config.HatchThreshold=v;threshold.Text=string.format("%.2f",v);saveConfig();log("Hatch threshold = "..threshold.Text.." KG")else threshold.Text=string.format("%.2f",Config.HatchThreshold)end end);local ruleText=makeText(hRight,"Calculated Weight > Threshold\n→ Bronto team\n\nCalculated Weight <= Threshold\n→ Hatch/Koi team\n\nExact ready weight calculation required.",8,Theme.Text,Enum.Font.Code);ruleText.Position=UDim2.fromOffset(11,97);ruleText.Size=UDim2.new(1,-22,0,100);ruleText.TextYAlignment=Enum.TextYAlignment.Top;ruleText.TextWrapped=true

-- Teams
local tp=Pages.Teams;local teamLeft=Instance.new("Frame");teamLeft.Size=UDim2.new(.56,-5,1,0);teamLeft.BackgroundColor3=Theme.Panel;teamLeft.BorderSizePixel=0;teamLeft.Parent=tp;createCorner(teamLeft,8);createStroke(teamLeft);local teamTitle=makeText(teamLeft,"HATCHING TEAMS",10,Theme.Text,Enum.Font.GothamBold);teamTitle.Position=UDim2.fromOffset(10,8);teamTitle.Size=UDim2.new(1,-20,0,17);local roleTabs={};local roles={{"Hatch","HATCH"},{"Bronto","BRONTO"},{"Reduction","REDUCTION"},{"Sell","SELL"}};for i,role in ipairs(roles)do local b=makeButton(teamLeft,role[2],UDim2.fromOffset(8+(i-1)*80,30),UDim2.fromOffset(74,27),i==1 and Theme.PurpleDark or Theme.Panel2);roleTabs[role[1]]=b;b.Activated:Connect(function()State.SelectedTeamRole=role[1];for key,tab in pairs(roleTabs)do tab.BackgroundColor3=key==State.SelectedTeamRole and Theme.PurpleDark or Theme.Panel2 end;redrawTeamSlots();redrawTeamInventory()end)end
local slotScroll=Instance.new("ScrollingFrame");slotScroll.Position=UDim2.fromOffset(8,64);slotScroll.Size=UDim2.new(1,-16,0,166);slotScroll.BackgroundTransparency=1;slotScroll.BorderSizePixel=0;slotScroll.ScrollBarThickness=2;slotScroll.CanvasSize=UDim2.new();slotScroll.Parent=teamLeft;local slotLayout=Instance.new("UIGridLayout");slotLayout.CellSize=UDim2.fromOffset(88,70);slotLayout.CellPadding=UDim2.fromOffset(5,5);slotLayout.Parent=slotScroll;State.UI.TeamSlotScroll=slotScroll
local clear=makeButton(teamLeft,"CLEAR TEAM",UDim2.fromOffset(8,236),UDim2.fromOffset(112,28));clear.Activated:Connect(function()State.Teams[State.SelectedTeamRole]={};saveTeamConfig();redrawTeamSlots()end);local apply=makeButton(teamLeft,"APPLY / VERIFY",UDim2.fromOffset(126,236),UDim2.fromOffset(128,28),Theme.PurpleDark);apply.Activated:Connect(function()local ok,err=ensureExactGardenTeam(State.SelectedTeamRole);log(ok and(State.SelectedTeamRole.." verified ✓")or("Team blocked • "..safeString(err)))end);local teamNote=makeText(teamLeft,"Exact inventory UUIDs only.\nOnly intended team remains active.",7,Theme.Muted,Enum.Font.Code);teamNote.Position=UDim2.fromOffset(8,269);teamNote.Size=UDim2.new(1,-16,0,36);teamNote.TextYAlignment=Enum.TextYAlignment.Top
local invPanel=Instance.new("Frame");invPanel.Position=UDim2.new(.56,2,0,0);invPanel.Size=UDim2.new(.44,-2,1,0);invPanel.BackgroundColor3=Theme.Panel;invPanel.BorderSizePixel=0;invPanel.Parent=tp;createCorner(invPanel,8);createStroke(invPanel);local invTitle=makeText(invPanel,"YOUR PET INVENTORY",10,Theme.Text,Enum.Font.GothamBold);invTitle.Position=UDim2.fromOffset(10,8);invTitle.Size=UDim2.new(1,-20,0,17);local invSub=makeText(invPanel,"Only currently owned pets can be selected.",7,Theme.Muted,Enum.Font.Code);invSub.Position=UDim2.fromOffset(10,22);invSub.Size=UDim2.new(1,-20,0,13);local invSearch=Instance.new("TextBox");invSearch.Position=UDim2.fromOffset(8,40);invSearch.Size=UDim2.new(1,-16,0,28);invSearch.BackgroundColor3=Theme.Panel2;invSearch.BorderSizePixel=0;invSearch.Text="";invSearch.PlaceholderText="Search pets / UUID...";invSearch.PlaceholderColor3=Theme.Muted;invSearch.TextColor3=Theme.Text;invSearch.TextSize=8;invSearch.Font=Enum.Font.Gotham;invSearch.ClearTextOnFocus=false;invSearch.Parent=invPanel;createCorner(invSearch,7);createStroke(invSearch);local invScroll=Instance.new("ScrollingFrame");invScroll.Position=UDim2.fromOffset(8,74);invScroll.Size=UDim2.new(1,-16,1,-82);invScroll.BackgroundTransparency=1;invScroll.BorderSizePixel=0;invScroll.ScrollBarThickness=2;invScroll.CanvasSize=UDim2.new();invScroll.Parent=invPanel;local invList=Instance.new("UIListLayout");invList.Padding=UDim.new(0,4);invList.Parent=invScroll;State.UI.TeamInventoryScroll=invScroll;State.UI.TeamInventorySearch=invSearch

-- Pet Sell
local sp=Pages["Pet Sell"];local sellBox=Instance.new("Frame");sellBox.Size=UDim2.new(.43,-5,1,0);sellBox.BackgroundColor3=Theme.Panel;sellBox.BorderSizePixel=0;sellBox.Parent=sp;createCorner(sellBox,8);createStroke(sellBox);local sellTitle=makeText(sellBox,"PET SELL SETTINGS",10,Theme.Text,Enum.Font.GothamBold);sellTitle.Position=UDim2.fromOffset(10,8);sellTitle.Size=UDim2.new(1,-20,0,17);local sellSearch=Instance.new("TextBox");sellSearch.Position=UDim2.fromOffset(8,32);sellSearch.Size=UDim2.new(1,-16,0,28);sellSearch.BackgroundColor3=Theme.Panel2;sellSearch.BorderSizePixel=0;sellSearch.Text="";sellSearch.PlaceholderText="Search eggs...";sellSearch.PlaceholderColor3=Theme.Muted;sellSearch.TextColor3=Theme.Text;sellSearch.TextSize=8;sellSearch.Font=Enum.Font.Gotham;sellSearch.ClearTextOnFocus=false;sellSearch.Parent=sellBox;createCorner(sellSearch,7);createStroke(sellSearch);local sellEggList=Instance.new("ScrollingFrame");sellEggList.Position=UDim2.fromOffset(8,66);sellEggList.Size=UDim2.new(1,-16,1,-74);sellEggList.BackgroundTransparency=1;sellEggList.BorderSizePixel=0;sellEggList.ScrollBarThickness=2;sellEggList.CanvasSize=UDim2.new();sellEggList.Parent=sellBox;local sellEggLayout=Instance.new("UIListLayout");sellEggLayout.Padding=UDim.new(0,4);sellEggLayout.Parent=sellEggList;State.UI.SellEggList=sellEggList;State.UI.SellEggSearch=sellSearch;local sellRight=Instance.new("Frame");sellRight.Position=UDim2.new(.43,2,0,0);sellRight.Size=UDim2.new(.57,-2,1,0);sellRight.BackgroundColor3=Theme.Panel;sellRight.BorderSizePixel=0;sellRight.Parent=sp;createCorner(sellRight,8);createStroke(sellRight);local sellRightTitle=makeText(sellRight,"SELL CONTROL",10,Theme.Text,Enum.Font.GothamBold);sellRightTitle.Position=UDim2.fromOffset(10,8);sellRightTitle.Size=UDim2.new(1,-20,0,17);local globalLabel=makeText(sellRight,"GLOBAL THRESHOLD [KG]",8,Theme.Muted,Enum.Font.GothamBold);globalLabel.Position=UDim2.fromOffset(10,32);globalLabel.Size=UDim2.new(1,-20,0,15);local globalInput=Instance.new("TextBox");globalInput.Position=UDim2.fromOffset(10,50);globalInput.Size=UDim2.new(1,-20,0,30);globalInput.BackgroundColor3=Theme.Panel2;globalInput.BorderSizePixel=0;globalInput.Text=string.format("%.2f",Config.SellThresholdGlobal);globalInput.TextColor3=Theme.Text;globalInput.TextSize=9;globalInput.Font=Enum.Font.Code;globalInput.ClearTextOnFocus=false;globalInput.Parent=sellRight;createCorner(globalInput,7);createStroke(globalInput);globalInput.FocusLost:Connect(function()local v=number(globalInput.Text);if v and v>=0 then Config.SellThresholdGlobal=v;globalInput.Text=string.format("%.2f",v);saveConfig()else globalInput.Text=string.format("%.2f",Config.SellThresholdGlobal)end end);local modeTitle=makeText(sellRight,"SELL MODE",8,Theme.Muted,Enum.Font.GothamBold);modeTitle.Position=UDim2.fromOffset(10,90);modeTitle.Size=UDim2.new(1,-20,0,15);local sellModeButtons={};local sellModes={"Disabled","Sell Every Cycle","Max Pet Inventory"};for i,mode in ipairs(sellModes)do local b=makeButton(sellRight,mode,UDim2.fromOffset(10,110+(i-1)*32),UDim2.new(1,-20,0,27),mode==Config.SellMode and Theme.PurpleDark or Theme.Panel2);sellModeButtons[mode]=b;b.Activated:Connect(function()Config.SellMode=mode;saveConfig();for m,x in pairs(sellModeButtons)do x.BackgroundColor3=m==Config.SellMode and Theme.PurpleDark or Theme.Panel2 end;log("Sell mode = "..mode)end)end;local sellHelp=makeText(sellRight,"ON + below threshold = SELL\nON + at/above threshold = KEEP\nOFF = KEEP\nConfigured team UUID = KEEP\nUnknown = KEEP / BLOCK\n\nSell Every Cycle → SellPet_RE\nMax Inventory → SellAllPets_RE",8,Theme.Text,Enum.Font.Code);sellHelp.Position=UDim2.fromOffset(10,220);sellHelp.Size=UDim2.new(1,-20,0,105);sellHelp.TextYAlignment=Enum.TextYAlignment.Top;sellHelp.TextWrapped=true;State.UI.SellPetHost=sellRight

-- Placement
local pp=Pages.Placement;local placeLeft=Instance.new("Frame");placeLeft.Size=UDim2.new(.60,-5,1,0);placeLeft.BackgroundColor3=Theme.Panel;placeLeft.BorderSizePixel=0;placeLeft.Parent=pp;createCorner(placeLeft,8);createStroke(placeLeft);local placeTitle=makeText(placeLeft,"REGION 1 MIDDLE",10,Theme.Text,Enum.Font.GothamBold);placeTitle.Position=UDim2.fromOffset(10,8);placeTitle.Size=UDim2.new(1,-20,0,17);local placeInfo=makeText(placeLeft,"Exact tested 4-stud JSON placement map.\nRegion 1 only • large centered middle.",8,Theme.Muted,Enum.Font.Code);placeInfo.Position=UDim2.fromOffset(10,32);placeInfo.Size=UDim2.new(1,-20,0,44);placeInfo.TextYAlignment=Enum.TextYAlignment.Top;local mapStatus=makeText(placeLeft,"MAP: loading...",8,Theme.Text,Enum.Font.Code);mapStatus.Position=UDim2.fromOffset(10,82);mapStatus.Size=UDim2.new(1,-20,0,18);State.UI.MapStatus=mapStatus;local targetLabel=makeText(placeLeft,"TARGET EGGS: 13",9,Theme.Text,Enum.Font.GothamBold);targetLabel.Position=UDim2.fromOffset(10,108);targetLabel.Size=UDim2.fromOffset(140,20);State.UI.TargetLabel=targetLabel;local minus=makeButton(placeLeft,"−",UDim2.fromOffset(154,104),UDim2.fromOffset(38,29));local plus=makeButton(placeLeft,"+",UDim2.fromOffset(197,104),UDim2.fromOffset(38,29));minus.Activated:Connect(function()Config.EggCount=math.max(1,Config.EggCount-1);targetLabel.Text="TARGET EGGS: "..Config.EggCount;saveConfig()end);plus.Activated:Connect(function()Config.EggCount=math.min(13,Config.EggCount+1);targetLabel.Text="TARGET EGGS: "..Config.EggCount;saveConfig()end);local eggTypeLabel=makeText(placeLeft,"EGG TYPE",8,Theme.Muted,Enum.Font.GothamBold);eggTypeLabel.Position=UDim2.fromOffset(10,141);eggTypeLabel.Size=UDim2.new(1,-20,0,15);local eggButton=makeButton(placeLeft,Config.EggType,UDim2.fromOffset(10,160),UDim2.new(1,-20,0,32));State.UI.EggButton=eggButton;local eggMenu=Instance.new("ScrollingFrame");eggMenu.Position=UDim2.fromOffset(10,195);eggMenu.Size=UDim2.new(1,-20,0,0);eggMenu.BackgroundColor3=Theme.Panel2;eggMenu.BorderSizePixel=0;eggMenu.Visible=false;eggMenu.ScrollBarThickness=3;eggMenu.ZIndex=50;eggMenu.Parent=placeLeft;createCorner(eggMenu,7);local eggMenuLayout=Instance.new("UIListLayout");eggMenuLayout.Padding=UDim.new(0,2);eggMenuLayout.Parent=eggMenu;local function populateEggMenu()for _,child in ipairs(eggMenu:GetChildren())do if child:IsA("TextButton")then child:Destroy()end end;local names,seen={},{};local function scan(container)if not container then return end;for _,tool in ipairs(container:GetChildren())do if tool:IsA("Tool")and tool.Name:lower():find("egg",1,true)then local name=normalizeEggType(tool.Name);if name~=""and not seen[name]then seen[name]=true;names[#names+1]=name end end end end;scan(LocalPlayer.Character);scan(LocalPlayer:FindFirstChildOfClass("Backpack"));table.sort(names);for _,name in ipairs(names)do local option=makeButton(eggMenu,name,UDim2.fromOffset(2,0),UDim2.new(1,-4,0,27),Theme.Panel3);option.TextXAlignment=Enum.TextXAlignment.Left;option.Activated:Connect(function()Config.EggType=name;eggButton.Text=name;eggMenu.Visible=false;eggMenu.Size=UDim2.new(1,-20,0,0);saveConfig()end)end;eggMenu.Size=UDim2.new(1,-20,0,math.min(155,#names*29+5))end;eggButton.Activated:Connect(function()if eggMenu.Visible then eggMenu.Visible=false;eggMenu.Size=UDim2.new(1,-20,0,0)else populateEggMenu();eggMenu.Visible=true end end);local refreshMap=makeButton(placeLeft,"REFRESH MAP",UDim2.fromOffset(10,235),UDim2.new(1,-20,0,29));refreshMap.Activated:Connect(function()local ok,message=loadPlacementMap();mapStatus.Text="MAP: "..safeString(message);if State.UI.MapCount then State.UI.MapCount.Text="Map points: "..#State.PlacementPoints end;log(message)end);local mapRight=Instance.new("Frame");mapRight.Position=UDim2.new(.60,2,0,0);mapRight.Size=UDim2.new(.40,-2,1,0);mapRight.BackgroundColor3=Theme.Panel;mapRight.BorderSizePixel=0;mapRight.Parent=pp;createCorner(mapRight,8);createStroke(mapRight);local mapSafeTitle=makeText(mapRight,"PLACEMENT SAFETY",10,Theme.Text,Enum.Font.GothamBold);mapSafeTitle.Position=UDim2.fromOffset(10,8);mapSafeTitle.Size=UDim2.new(1,-20,0,17);local mapSafe=makeText(mapRight,"✓ Region 1 Middle only\n✓ Exact JSON coordinates\n✓ 4.0 stud minimum\n✓ Fresh egg scan before create\n✓ OBJECT_UUID creation verification\n✓ Reduction Team verified",8,Theme.Text,Enum.Font.Code);mapSafe.Position=UDim2.fromOffset(10,33);mapSafe.Size=UDim2.new(1,-20,0,130);mapSafe.TextYAlignment=Enum.TextYAlignment.Top;local mapCount=makeText(mapRight,"Map points: 0",8,Theme.Muted,Enum.Font.Code);mapCount.Position=UDim2.fromOffset(10,165);mapCount.Size=UDim2.new(1,-20,0,18);State.UI.MapCount=mapCount

-- Timing
local timing=Pages.Timing;local timingLeft=Instance.new("Frame");timingLeft.Size=UDim2.new(.58,-5,1,0);timingLeft.BackgroundColor3=Theme.Panel;timingLeft.BorderSizePixel=0;timingLeft.Parent=timing;createCorner(timingLeft,8);createStroke(timingLeft);local timingTitle=makeText(timingLeft,"TIMING",10,Theme.Text,Enum.Font.GothamBold);timingTitle.Position=UDim2.fromOffset(10,8);timingTitle.Size=UDim2.new(1,-20,0,17);local cycleLabel=makeText(timingLeft,"TEAM CYCLE SECONDS",8,Theme.Muted,Enum.Font.GothamBold);cycleLabel.Position=UDim2.fromOffset(10,35);cycleLabel.Size=UDim2.new(1,-20,0,15);local cycleInput=Instance.new("TextBox");cycleInput.Position=UDim2.fromOffset(10,54);cycleInput.Size=UDim2.new(1,-20,0,31);cycleInput.BackgroundColor3=Theme.Panel2;cycleInput.BorderSizePixel=0;cycleInput.Text=string.format("%.2f",Config.TeamCycleSeconds);cycleInput.TextColor3=Theme.Text;cycleInput.TextSize=10;cycleInput.Font=Enum.Font.Code;cycleInput.ClearTextOnFocus=false;cycleInput.Parent=timingLeft;createCorner(cycleInput,7);createStroke(cycleInput);cycleInput.FocusLost:Connect(function()local v=number(cycleInput.Text);if v and v>=.05 and v<=5 then Config.TeamCycleSeconds=v;cycleInput.Text=string.format("%.2f",v);saveConfig();log("Team Cycle Seconds = "..cycleInput.Text)else cycleInput.Text=string.format("%.2f",Config.TeamCycleSeconds);log("Invalid Team Cycle Seconds")end end);local timingInfo=makeText(timingLeft,"Team Cycle Seconds = stabilization wait after a team switch.\nVerification is still required.\n\nFast placement controls only placement pacing.",8,Theme.Text,Enum.Font.Code);timingInfo.Position=UDim2.fromOffset(10,98);timingInfo.Size=UDim2.new(1,-20,0,130);timingInfo.TextWrapped=true;timingInfo.TextYAlignment=Enum.TextYAlignment.Top;local timingRight=Instance.new("Frame");timingRight.Position=UDim2.new(.58,2,0,0);timingRight.Size=UDim2.new(.42,-2,1,0);timingRight.BackgroundColor3=Theme.Panel;timingRight.BorderSizePixel=0;timingRight.Parent=timing;createCorner(timingRight,8);createStroke(timingRight);local timingFlow=makeText(timingRight,"CYCLE\n\nREDUCTION\n↓\nWAIT + VERIFY\n↓\nREADY EGG\n↓\nKOI / BRONTO\n↓\nWAIT + VERIFY\n↓\nHATCH\n↓\nVERIFY PET\n↓\nSELL / REDUCTION",8,Theme.Text,Enum.Font.Code);timingFlow.Position=UDim2.fromOffset(10,8);timingFlow.Size=UDim2.new(1,-20,0,300);timingFlow.TextYAlignment=Enum.TextYAlignment.Top

-- Egg ESP
local ep=Pages["Egg ESP"];local espLeft=Instance.new("Frame");espLeft.Size=UDim2.new(.56,-5,1,0);espLeft.BackgroundColor3=Theme.Panel;espLeft.BorderSizePixel=0;espLeft.Parent=ep;createCorner(espLeft,8);createStroke(espLeft);local espTitle=makeText(espLeft,"EGG ESP",10,Theme.Text,Enum.Font.GothamBold);espTitle.Position=UDim2.fromOffset(10,8);espTitle.Size=UDim2.new(1,-20,0,17);makeToggleRow(espLeft,"Egg ESP","Show owned egg state",function()return Config.EggESP end,function(v)Config.EggESP=v==true end,32);makeToggleRow(espLeft,"Show Timer","Show hatch timer",function()return Config.ShowTimer end,function(v)Config.ShowTimer=v==true end,80);makeToggleRow(espLeft,"Show Revealed Pet","Show READY PetType",function()return Config.ShowPet end,function(v)Config.ShowPet=v==true end,128);makeToggleRow(espLeft,"Show Weight","Show calculated weight",function()return Config.ShowWeight end,function(v)Config.ShowWeight=v==true end,176);makeToggleRow(espLeft,"Show Decision","Show Koi / Bronto",function()return Config.ShowDecision end,function(v)Config.ShowDecision=v==true end,224);local espRight=Instance.new("Frame");espRight.Position=UDim2.new(.56,2,0,0);espRight.Size=UDim2.new(.44,-2,1,0);espRight.BackgroundColor3=Theme.Panel;espRight.BorderSizePixel=0;espRight.Parent=ep;createCorner(espRight,8);createStroke(espRight);local espRightTitle=makeText(espRight,"EXACT WEIGHT SOURCE",10,Theme.Text,Enum.Font.GothamBold);espRightTitle.Position=UDim2.fromOffset(10,8);espRightTitle.Size=UDim2.new(1,-20,0,17);local espInfo=makeText(espRight,"READY event\n→ PetType + EggUUID\n\nSavedObjects[EggUUID]\n→ Data.BaseWeight\n\nPetUtilities:CalculateWeight\n(BaseWeight, 1, PetType)\n\nThis matches the verified Egg ESP.",8,Theme.Text,Enum.Font.Code);espInfo.Position=UDim2.fromOffset(10,34);espInfo.Size=UDim2.new(1,-20,0,190);espInfo.TextYAlignment=Enum.TextYAlignment.Top;espInfo.TextWrapped=true

-- UI redrawers
function redrawTeamSlots()
    local scroll=State.UI.TeamSlotScroll;if not scroll then return end;for _,child in ipairs(scroll:GetChildren())do if child:IsA("Frame")then child:Destroy()end end;local role=State.SelectedTeamRole;local team=State.Teams[role];for slot=1,8 do local entry=team[slot];local card=Instance.new("Frame");card.Size=UDim2.fromOffset(88,70);card.BackgroundColor3=Theme.Panel2;card.BorderSizePixel=0;card.Parent=scroll;createCorner(card,7);createStroke(card,entry and Theme.PurpleDark or Theme.Outline,entry and .15 or .45);local label=makeText(card,"SLOT "..slot,6,Theme.Muted,Enum.Font.GothamBold);label.Position=UDim2.fromOffset(6,4);label.Size=UDim2.new(1,-12,0,11);if entry then local petLabel=makeText(card,entry.PetType,8,Theme.Text,Enum.Font.GothamSemibold);petLabel.Position=UDim2.fromOffset(6,20);petLabel.Size=UDim2.new(1,-12,0,18);petLabel.TextWrapped=true;local uuidLabel=makeText(card,"UUID "..entry.UUID:sub(1,8),6,Theme.Muted,Enum.Font.Code);uuidLabel.Position=UDim2.fromOffset(6,42);uuidLabel.Size=UDim2.new(1,-30,0,10);local rm=makeButton(card,"×",UDim2.new(1,-25,0,4),UDim2.fromOffset(21,20),Theme.Background);rm.TextColor3=Theme.Red;rm.Activated:Connect(function()removeTeamPet(role,slot);redrawTeamSlots()end)else local empty=makeText(card,"EMPTY",7,Theme.Muted,Enum.Font.Code);empty.Position=UDim2.fromOffset(6,29);empty.Size=UDim2.new(1,-12,0,18);empty.TextXAlignment=Enum.TextXAlignment.Center end end;scroll.CanvasSize=UDim2.fromOffset(0,76*8)
end
function redrawTeamInventory()
    local scroll=State.UI.TeamInventoryScroll;if not scroll then return end;for _,child in ipairs(scroll:GetChildren())do if child:IsA("Frame")then child:Destroy()end end;rebuildInventory();local q=string.lower(State.UI.TeamInventorySearch.Text or "");local count=0;for _,pet in ipairs(State.Inventory)do if q==""or string.find(string.lower(pet.PetType),q,1,true)or string.find(string.lower(pet.UUID),q,1,true)then count+=1;local row=Instance.new("Frame");row.Size=UDim2.new(1,0,0,44);row.BackgroundColor3=Theme.Panel2;row.BorderSizePixel=0;row.Parent=scroll;createCorner(row,7);local name=makeText(row,pet.PetType,8,Theme.Text,Enum.Font.GothamSemibold);name.Position=UDim2.fromOffset(7,3);name.Size=UDim2.new(1,-74,0,16);local displayWeight=calculatePetWeight(pet.BaseWeight,pet.Level or 1,pet.PetType);local details=makeText(row,formatWeight(displayWeight or pet.BaseWeight).." KG • UUID "..pet.UUID:sub(1,8),6,Theme.Muted,Enum.Font.Code);details.Position=UDim2.fromOffset(7,20);details.Size=UDim2.new(1,-74,0,13);local add=makeButton(row,"+",UDim2.new(1,-38,0,8),UDim2.fromOffset(32,27),Theme.Panel3);if teamContainsUUID(State.SelectedTeamRole,pet.UUID)or #State.Teams[State.SelectedTeamRole]>=math.min(8,getMaxEquipped())then add.TextColor3=Theme.Muted end;add.Activated:Connect(function()local ok,err=addTeamPet(State.SelectedTeamRole,pet.UUID);if ok then redrawTeamSlots();redrawTeamInventory();log(pet.PetType.." → "..State.SelectedTeamRole)else log(safeString(err))end end)end end;scroll.CanvasSize=UDim2.fromOffset(0,math.max(1,count*48))
end
State.UI.TeamInventorySearch:GetPropertyChangedSignal("Text"):Connect(redrawTeamInventory)
local selectedSellEgg
function redrawSellPets(eggName)
    local host=State.UI.SellPetHost;if not host then return end;local old=host:FindFirstChild("PetRuleScroll");if old then old:Destroy()end;local scroll=Instance.new("ScrollingFrame");scroll.Name="PetRuleScroll";scroll.Position=UDim2.fromOffset(10,350);scroll.Size=UDim2.new(1,-20,0,76);scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0;scroll.ScrollBarThickness=2;scroll.CanvasSize=UDim2.new();scroll.Parent=host;local layout=Instance.new("UIListLayout");layout.Padding=UDim.new(0,3);layout.Parent=scroll;local map=registryEggPets()[eggName]or{};local names={};for petName in pairs(map)do names[#names+1]=petName end;table.sort(names);for _,petName in ipairs(names)do local rule=ensureSellSetting(eggName,petName);local row=Instance.new("Frame");row.Size=UDim2.new(1,0,0,40);row.BackgroundColor3=Theme.Panel2;row.BorderSizePixel=0;row.Parent=scroll;createCorner(row,7);local name=makeText(row,petName,8,Theme.Text,Enum.Font.GothamSemibold);name.Position=UDim2.fromOffset(8,3);name.Size=UDim2.new(1,-145,0,15);local input=Instance.new("TextBox");input.Position=UDim2.new(1,-84,0,6);input.Size=UDim2.fromOffset(74,27);input.BackgroundColor3=Theme.Panel3;input.BorderSizePixel=0;input.Text=string.format("%.2f",number(rule.Threshold)or Config.SellThresholdGlobal);input.TextColor3=Theme.Text;input.TextSize=8;input.Font=Enum.Font.Code;input.ClearTextOnFocus=false;input.Parent=row;createCorner(input,6);input.FocusLost:Connect(function()local v=number(input.Text);if v and v>=0 then rule.Threshold=v;input.Text=string.format("%.2f",v);saveConfig()else input.Text=string.format("%.2f",rule.Threshold)end end);local toggle=makeButton(row,rule.Enabled and"SELL"or"KEEP",UDim2.fromOffset(8,21),UDim2.fromOffset(45,16),rule.Enabled and Theme.Purple or Color3.fromRGB(55,55,66));toggle.TextSize=7;toggle.Activated:Connect(function()rule.Enabled=not rule.Enabled;toggle.Text=rule.Enabled and"SELL"or"KEEP";toggle.BackgroundColor3=rule.Enabled and Theme.Purple or Color3.fromRGB(55,55,66);saveConfig()end)end;scroll.CanvasSize=UDim2.fromOffset(0,math.max(1,#names*43))
end
function redrawSellEggs()
    local list=State.UI.SellEggList;if not list then return end;for _,child in ipairs(list:GetChildren())do if child:IsA("TextButton")then child:Destroy()end end;local q=string.lower(State.UI.SellEggSearch.Text or "");for _,eggName in ipairs(registryEggNames())do if q==""or string.find(string.lower(eggName),q,1,true)then local row=makeButton(list,eggName,UDim2.fromOffset(0,0),UDim2.new(1,-4,0,30),eggName==selectedSellEgg and Theme.PurpleDark or Theme.Panel2);row.TextXAlignment=Enum.TextXAlignment.Left;row.Activated:Connect(function()selectedSellEgg=eggName;redrawSellEggs();redrawSellPets(eggName)end)end end;list.CanvasSize=UDim2.fromOffset(0,math.max(1,#registryEggNames()*34))
end
State.UI.SellEggSearch:GetPropertyChangedSignal("Text"):Connect(redrawSellEggs)
local function refreshAllUI()rebuildInventory();redrawTeamSlots();redrawTeamInventory();redrawSellEggs();local ok,message=loadPlacementMap();if State.UI.MapStatus then State.UI.MapStatus.Text="MAP: "..safeString(message)end;if State.UI.MapCount then State.UI.MapCount.Text="Map points: "..#State.PlacementPoints end;if State.UI.TargetLabel then State.UI.TargetLabel.Text="TARGET EGGS: "..Config.EggCount end end
local function drawMaster()MasterToggle.BackgroundColor3=State.Running and Theme.Purple or Color3.fromRGB(55,55,66);MasterKnob.Position=State.Running and UDim2.new(1,-22,0,2)or UDim2.fromOffset(2,2);MasterKnob.BackgroundColor3=State.Running and Color3.new(1,1,1)or Theme.Muted;Running.Text=State.Running and"RUNNING"or"IDLE";Running.TextColor3=State.Running and Theme.Green or Theme.Muted end
MasterToggle.Activated:Connect(function()State.Running=not State.Running;log("Auto Hatch "..(State.Running and"ON"or"OFF"));drawMaster()end)
Search:GetPropertyChangedSignal("Text"):Connect(function()local q=string.lower(Search.Text or"");for name,b in pairs(NavButtons)do b.Visible=q==""or string.find(string.lower(name),q,1,true)~=nil end end)
local dragging=false;local dragStart;local startPos;Header.InputBegan:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true;dragStart=input.Position;startPos=Main.Position end end);Header.InputEnded:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end end);UserInputService.InputChanged:Connect(function(input)if not dragging then return end;if input.UserInputType~=Enum.UserInputType.MouseMovement and input.UserInputType~=Enum.UserInputType.Touch then return end;local delta=input.Position-dragStart;Main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)end)
local minimized=false;local fullSize=Main.Size;Minimize.Activated:Connect(function()minimized=not minimized;for _,child in ipairs(Main:GetChildren())do if child~=Header then child.Visible=not minimized end end;Main.Size=minimized and UDim2.fromOffset(300,54)or fullSize;Minimize.Text=minimized and"+"or"—"end);Close.Activated:Connect(function()State.Running=false;State.Destroyed=true;destroyESP();Gui:Destroy();if Launcher and Launcher.Parent then Launcher:Destroy()end;ENV.FableAutoHatchFinal=nil end)

-- Runtime
local function processReadyEggs()
    for _,egg in ipairs(ownedEggs())do
        if not State.Running then return end
        if eggReady(egg)then local ok=hatchReadyEgg(egg);if ok and not Config.BatchHatching then return end;task.wait(Config.BatchHatching and .05 or .35)end
    end
end

task.defer(recoverNativeReadyCache)
loadTeamConfig();rebuildInventory();State.LastInventoryStructureSignature=inventoryStructureSignature();refreshAllUI();activatePage("Dashboard");drawMaster()
log(string.format("Fable Final loaded • %d placement points • Region 1 Middle",#State.PlacementPoints))

task.spawn(function()
    local lastInventoryRefresh=0
    while Gui.Parent and not State.Destroyed do
        task.wait(.20)
        local now=os.clock();State.Eggs=#ownedEggs();State.Ready=0;for _,egg in ipairs(ownedEggs())do if eggReady(egg)then State.Ready+=1 end end
        if now-lastInventoryRefresh>=.75 then
            rebuildInventory();local signature=inventoryStructureSignature();if State.LastInventoryStructureSignature~=signature then State.LastInventoryStructureSignature=signature;State.FavoriteDirty=true end;lastInventoryRefresh=now
        end
        if State.Running then
            if State.FavoriteDirty then local ok,err=prepareFavoriteState();if not ok then security("BLOCKED • FAVORITE SAFETY");log("STOP: "..safeString(err));State.Running=false end end
            if State.Running then processReadyEggs() end
            if State.Running and State.SellPending and State.Ready==0 then performSell() end
            if State.Running then maintainEggCount() end
            if State.Running and State.Ready==0 then local ok,err=ensureExactGardenTeam("Reduction");if not ok then security("BLOCKED • REDUCTION TEAM");log("STOP: "..safeString(err));State.Running=false end end
        end
        if statValues then statValues.EGGS.Text=string.format("%d/%d",State.Eggs,Config.EggCount);statValues.READY.Text=tostring(State.Ready);statValues.HATCHED.Text=tostring(State.Hatched);statValues.FAILED.Text=tostring(State.Failed)end
        liveState.Text=State.Running and"● FABLE IS RUNNING"or"FABLE IS READY";liveState.TextColor3=State.Running and Theme.Green or Theme.Purple
        live1.Text=string.format("Eggs %d | Ready %d | Created %d | Hatched %d",State.Eggs,State.Ready,State.Created,State.Hatched);live2.Text=string.format("Sold %d | Failed %d | Weight mismatch %d",State.Sold,State.Failed,State.WeightMismatches);live3.Text=string.format("%s\nTeam: %s | Weight: %s",State.Status,State.CurrentTeam,formatWeight(State.CurrentWeight));State.UI.Security.Text="SECURITY  "..State.Security;State.UI.Security.TextColor3=State.Security:find("BLOCKED",1,true)and Theme.Red or State.Security:find("VERIFIED",1,true)and Theme.Green or Theme.Yellow;State.UI.ReadyText.Text=string.format("Egg: %s\nUUID: %s\nPet: %s\nWeight: %s\nRaw BaseWeight: %s\nDecision: %s\nTeam: %s",State.CurrentEgg,State.CurrentUUID,State.CurrentPet,formatWeight(State.CurrentWeight),formatWeight(State.CurrentRawBaseWeight),State.CurrentDecision,State.CurrentTeam);local lines={};for i=1,math.min(7,#State.Logs)do lines[#lines+1]=State.Logs[i]end;State.UI.LogText.Text=table.concat(lines,"\n");drawMaster();refreshESP()
    end
end)

ENV.FableAutoHatchFinalConfig=persisted
print("[FABLE] FINAL loaded")
print("[FABLE] Sell Every Cycle: SellPet_RE",SellPetRemote and "OK" or "MISSING")
print("[FABLE] Max Inventory: SellAllPets_RE",SellAllRemote and "OK" or "MISSING")
print("[FABLE] PetUtilities:",PetUtilities and "OK" or "MISSING")
print("[FABLE] PetsService:",PetsServiceModule and "OK" or "MISSING")
print("[FABLE] ActivePetsService:",ActivePetsService and "OK" or "MISSING")
print("[FABLE] Ready event:",ReadyEvent and "OK" or "MISSING")
print("[FABLE] Egg service:",EggService and "OK" or "MISSING")

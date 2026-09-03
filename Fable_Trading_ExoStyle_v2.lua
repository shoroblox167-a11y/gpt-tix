-- FABLE // Trading v2
-- A compact Exo-style trading UI: 30/70 shell, left navigation,
-- two-column groupboxes, code font, purple accent, draggable/minimizable.
-- Trading only; no Garden Ascension.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local TradeEvents = GameEvents:WaitForChild("TradeEvents")
local DataService = require(ReplicatedStorage.Modules:WaitForChild("DataService"))
local TradingController = require(ReplicatedStorage.Modules.TradeControllers:WaitForChild("TradingController"))
local TradeData = require(ReplicatedStorage.Data:WaitForChild("TradeData"))
local InvEnums = require(ReplicatedStorage.Data.EnumRegistry:WaitForChild("InventoryServiceEnums"))

local SendRequest = TradeEvents:WaitForChild("SendRequest")
local RespondRequest = TradeEvents:WaitForChild("RespondRequest")
local AddItem = TradeEvents:WaitForChild("AddItem")
local AcceptRemote = TradeEvents:WaitForChild("Accept")
local ConfirmRemote = TradeEvents:WaitForChild("Confirm")
local DeclineRemote = TradeEvents:WaitForChild("Decline")
local FavoriteRemote = GameEvents:FindFirstChild("Favorite_Item")
local GiftRemote = GameEvents:FindFirstChild("PetGiftingService")

local PetRegistry
pcall(function() PetRegistry = require(ReplicatedStorage.Data.PetRegistry) end)

local Config = {
    AutoSendTicket = false,
    AutoAcceptRequest = true,
    AutoAcceptTrade = true,
    AutoConfirmTrade = true,
    AutoUnfavorite = true,
    SkipLocked = true,
    GiftSystem = false,
    MinLevel = 0,
    MaxLevel = 100,
    MinWeight = 0,
    MaxWeight = math.huge,
    Pets = {},
    Mutations = {},
    Rarities = {},
}

local Stats = {Sent=0,Requests=0,Accepts=0,Confirms=0,Added=0,Unfav=0,Failed=0}
local LastAction = "Ready"
local Running = true
local LastSend = 0
local LastAccept = 0
local LastConfirm = 0
local LastAdd = 0
local TradeSeen

local T = {
    Background = Color3.fromRGB(15,15,15),
    Main = Color3.fromRGB(25,25,25),
    Accent = Color3.fromRGB(125,85,255),
    Outline = Color3.fromRGB(40,40,40),
    Text = Color3.fromRGB(255,255,255),
    Muted = Color3.fromRGB(125,125,135),
    Success = Color3.fromRGB(92,225,145),
    Danger = Color3.fromRGB(255,70,90),
    Warn = Color3.fromRGB(240,195,85),
    Font = Enum.Font.Code,
}

local function uiCorner(o,r)
    local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 6) c.Parent=o return c
end
local function uiStroke(o,c,tr,w)
    local s=Instance.new("UIStroke") s.Color=c or T.Outline s.Transparency=tr or 0 s.Thickness=w or 1 s.Parent=o return s
end
local function mkLabel(p,text,size,color,h)
    local l=Instance.new("TextLabel") l.BackgroundTransparency=1 l.Text=text or "" l.TextSize=size or 13 l.TextColor3=color or T.Text l.Font=T.Font l.Size=UDim2.new(1,0,0,h or 20) l.TextXAlignment=Enum.TextXAlignment.Left l.Parent=p return l
end
local function mkButton(p,text,h)
    local b=Instance.new("TextButton") b.Size=UDim2.new(1,0,0,h or 34) b.BackgroundColor3=T.Main b.BorderSizePixel=0 b.Text=text b.TextColor3=T.Text b.Font=T.Font b.TextSize=12 b.AutoButtonColor=false b.Parent=p uiCorner(b,5) uiStroke(b,T.Outline,.15)
    b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(.1),{BackgroundColor3=T.Main:Lerp(T.Accent,.10)}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(.1),{BackgroundColor3=T.Main}):Play() end)
    return b
end
local function mkToggle(p,text,default,callback)
    local b=Instance.new("TextButton") b.Size=UDim2.new(1,0,0,33) b.BackgroundColor3=T.Main b.BorderSizePixel=0 b.Text="" b.Parent=p b.AutoButtonColor=false uiCorner(b,6) uiStroke(b,T.Outline,.2)
    local l=mkLabel(b,text,12,T.Text,33) l.Position=UDim2.fromOffset(9,0) l.Size=UDim2.new(1,-70,1,0)
    local pill=Instance.new("Frame") pill.AnchorPoint=Vector2.new(1,.5) pill.Position=UDim2.new(1,-9,.5,0) pill.Size=UDim2.fromOffset(46,20) pill.BackgroundColor3=T.Outline pill.BorderSizePixel=0 pill.Parent=b uiCorner(pill,10)
    local dot=Instance.new("Frame") dot.Size=UDim2.fromOffset(16,16) dot.AnchorPoint=Vector2.new(.5,.5) dot.Position=UDim2.new(0,10,.5,0) dot.BackgroundColor3=T.Muted dot.BorderSizePixel=0 dot.Parent=pill uiCorner(dot,8)
    local state=default==true
    local function draw()
        TweenService:Create(pill,TweenInfo.new(.12),{BackgroundColor3=state and T.Accent or T.Outline}):Play()
        TweenService:Create(dot,TweenInfo.new(.12),{Position=UDim2.new(0,state and 36 or 10,.5,0),BackgroundColor3=state and T.Text or T.Muted}):Play()
    end
    b.Activated:Connect(function() state=not state draw() if callback then callback(state) end end) draw()
    return function() return state end
end
local function mkInput(p,caption,value,numeric)
    local holder=Instance.new("Frame") holder.Size=UDim2.new(1,0,0,49) holder.BackgroundTransparency=1 holder.Parent=p
    mkLabel(holder,caption,11,T.Muted,16)
    local b=Instance.new("TextBox") b.Position=UDim2.fromOffset(0,18) b.Size=UDim2.new(1,0,0,30) b.BackgroundColor3=T.Main b.BorderSizePixel=0 b.Text=tostring(value or "") b.PlaceholderText=caption b.PlaceholderColor3=T.Muted b.TextColor3=T.Text b.Font=T.Font b.TextSize=12 b.ClearTextOnFocus=false b.Parent=holder uiCorner(b,5) uiStroke(b,T.Outline,.12)
    local pad=Instance.new("UIPadding") pad.PaddingLeft=UDim.new(0,8) pad.Parent=b
    if numeric then b:GetPropertyChangedSignal("Text"):Connect(function() local n=b.Text:gsub("[^%d%.%-]","") if n~=b.Text then b.Text=n end end) end
    return b
end

-- shell
local parent=(gethui and gethui()) or CoreGui
local old=parent:FindFirstChild("Fable_Trading_v2") if old then old:Destroy() end
local Gui=Instance.new("ScreenGui") Gui.Name="Fable_Trading_v2" Gui.IgnoreGuiInset=true Gui.ResetOnSpawn=false Gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling Gui.Parent=parent
local Main=Instance.new("Frame") Main.Size=UDim2.fromOffset(720,480) Main.Position=UDim2.new(.5,-360,.5,-240) Main.BackgroundColor3=T.Background Main.BorderSizePixel=0 Main.Active=true Main.Parent=Gui uiCorner(Main,5) uiStroke(Main,T.Outline,0)
local topLine=Instance.new("Frame",Main) topLine.Size=UDim2.new(1,0,0,1) topLine.Position=UDim2.fromOffset(0,48) topLine.BackgroundColor3=T.Outline topLine.BorderSizePixel=0
local sideLine=Instance.new("Frame",Main) sideLine.Size=UDim2.new(0,1,1,-69) sideLine.Position=UDim2.new(.3,0,0,49) sideLine.BackgroundColor3=T.Outline sideLine.BorderSizePixel=0
local bottomLine=Instance.new("Frame",Main) bottomLine.Size=UDim2.new(1,0,0,1) bottomLine.Position=UDim2.new(0,0,1,-21) bottomLine.BackgroundColor3=T.Outline bottomLine.BorderSizePixel=0

local Header=Instance.new("Frame",Main) Header.Size=UDim2.new(1,0,0,48) Header.BackgroundTransparency=1
local title=mkLabel(Header,"FABLE",20,T.Text,48) title.Size=UDim2.new(.3,0,1,0) title.TextXAlignment=Enum.TextXAlignment.Center
local desc=mkLabel(Header,"TRADING",10,T.Muted,16) desc.Position=UDim2.new(.3,12,0,5) desc.Size=UDim2.new(.26,0,0,16)
local search=Instance.new("TextBox",Header) search.Position=UDim2.new(.56,0,.5,-14) search.Size=UDim2.new(.28,0,0,28) search.BackgroundColor3=T.Main search.BorderSizePixel=0 search.PlaceholderText="Search..." search.PlaceholderColor3=T.Muted search.TextColor3=T.Text search.Font=T.Font search.TextSize=12 search.ClearTextOnFocus=false uiCorner(search,6) uiStroke(search,T.Outline,.15)
local sp=Instance.new("UIPadding",search) sp.PaddingLeft=UDim.new(0,9)
local Min=mkButton(Header,"—",28) Min.Size=UDim2.fromOffset(30,28) Min.Position=UDim2.new(1,-68,0,10) Min.TextXAlignment=Enum.TextXAlignment.Center
local Close=mkButton(Header,"×",28) Close.Size=UDim2.fromOffset(30,28) Close.Position=UDim2.new(1,-34,0,10) Close.TextXAlignment=Enum.TextXAlignment.Center Close.TextColor3=T.Danger

local Footer=mkLabel(Main,"Fable  •  Trading",9,T.Muted,20) Footer.Position=UDim2.new(0,0,1,-20) Footer.TextXAlignment=Enum.TextXAlignment.Center

local Sidebar=Instance.new("ScrollingFrame",Main) Sidebar.Position=UDim2.fromOffset(0,49) Sidebar.Size=UDim2.new(.3,0,1,-70) Sidebar.BackgroundColor3=T.Background Sidebar.BorderSizePixel=0 Sidebar.ScrollBarThickness=0 Sidebar.AutomaticCanvasSize=Enum.AutomaticSize.Y
local sidePad=Instance.new("UIPadding",Sidebar) sidePad.PaddingTop=UDim.new(0,8) sidePad.PaddingLeft=UDim.new(0,6) sidePad.PaddingRight=UDim.new(0,6)
local sideList=Instance.new("UIListLayout",Sidebar) sideList.Padding=UDim.new(0,2)

local Content=Instance.new("Frame",Main) Content.Position=UDim2.new(.3,1,0,49) Content.Size=UDim2.new(.7,-1,1,-70) Content.BackgroundColor3=T.Background Content.BorderSizePixel=0
local pages,buttons={},{}
local function makePage(name)
    local p=Instance.new("Frame",Content) p.Name=name p.Size=UDim2.fromScale(1,1) p.BackgroundTransparency=1 p.Visible=false pages[name]=p
    local left=Instance.new("ScrollingFrame",p) left.Position=UDim2.fromOffset(7,7) left.Size=UDim2.new(.5,-10,1,-14) left.BackgroundTransparency=1 left.BorderSizePixel=0 left.ScrollBarThickness=2 left.ScrollBarImageColor3=T.Accent left.AutomaticCanvasSize=Enum.AutomaticSize.Y
    local right=Instance.new("ScrollingFrame",p) right.Position=UDim2.new(.5,3,0,7) right.Size=UDim2.new(.5,-10,1,-14) right.BackgroundTransparency=1 right.BorderSizePixel=0 right.ScrollBarThickness=2 right.ScrollBarImageColor3=T.Accent right.AutomaticCanvasSize=Enum.AutomaticSize.Y
    for _,sc in ipairs({left,right}) do
        local pad=Instance.new("UIPadding",sc) pad.PaddingLeft=UDim.new(0,2) pad.PaddingRight=UDim.new(0,4) pad.PaddingBottom=UDim.new(0,10)
        local list=Instance.new("UIListLayout",sc) list.Padding=UDim.new(0,7)
    end
    return p,left,right
end
local TradePage,TL,TR=makePage("Trading")
local PetPage,PL,PR=makePage("Pet Filters")
local StatsPage,SL,SR=makePage("Stats")

local function tab(name,icon)
    local b=Instance.new("TextButton",Sidebar) b.Size=UDim2.new(1,0,0,40) b.BackgroundColor3=T.Background b.BackgroundTransparency=1 b.Text="" b.AutoButtonColor=false uiCorner(b,4)
    local i=mkLabel(b,icon,14,T.Accent,40) i.Position=UDim2.fromOffset(7,0) i.Size=UDim2.fromOffset(22,40) i.TextXAlignment=Enum.TextXAlignment.Center
    local t=mkLabel(b,name,14,T.Text,40) t.Position=UDim2.fromOffset(33,0) t.Size=UDim2.new(1,-40,1,0) t.TextTransparency=.5
    b.Activated:Connect(function()
        for n,p in pairs(pages) do p.Visible=(n==name) end
        for n,x in pairs(buttons) do
            local a=n==name x.BackgroundTransparency=a and 0 or 1 x.BackgroundColor3=a and Color3.fromRGB(43,30,65) or T.Background
            for _,c in ipairs(x:GetChildren()) do if c:IsA("TextLabel") then c.TextTransparency=a and 0 or .5 end end
        end
    end)
    buttons[name]=b return b
end

tab("Trading","◇") tab("Pet Filters","◆") tab("Stats","▣")

local function group(parent,titleText,description,icon)
    local box=Instance.new("Frame") box.Size=UDim2.new(1,0,0,0) box.AutomaticSize=Enum.AutomaticSize.Y box.BackgroundColor3=Color3.fromRGB(12,12,13) box.BorderSizePixel=0 box.Parent=parent uiCorner(box,8) uiStroke(box,Color3.fromRGB(72,72,72),.2)
    local h=Instance.new("Frame",box) h.Size=UDim2.new(1,0,0,46) h.BackgroundTransparency=1
    local ic=mkLabel(h,icon or "□",14,T.Accent,28) ic.Position=UDim2.fromOffset(8,8) ic.Size=UDim2.fromOffset(28,28) ic.TextXAlignment=Enum.TextXAlignment.Center
    local tt=mkLabel(h,titleText,14,T.Text,18) tt.Position=UDim2.fromOffset(42,6) tt.Size=UDim2.new(1,-50,0,18)
    if description then local dd=mkLabel(h,description,9,T.Muted,16) dd.Position=UDim2.fromOffset(42,25) dd.Size=UDim2.new(1,-50,0,16) end
    local inner=Instance.new("Frame",box) inner.Size=UDim2.new(1,0,0,0) inner.AutomaticSize=Enum.AutomaticSize.Y inner.BackgroundColor3=Color3.fromRGB(11,11,12) inner.BorderSizePixel=0
    local pad=Instance.new("UIPadding",inner) pad.PaddingLeft=UDim.new(0,6) pad.PaddingRight=UDim.new(0,6) pad.PaddingBottom=UDim.new(0,8)
    local list=Instance.new("UIListLayout",inner) list.Padding=UDim.new(0,6)
    return inner
end

local tgt=group(TL,"Target Player","Player to trade with","◇")
local Target=mkInput(tgt,"Username","",false)
local targetState=mkLabel(tgt,"Target: NONE",10,T.Muted,18)
local find=mkButton(tgt,"FIND / REFRESH",32)

local auto=group(TL,"Automation","Trade request and state actions","◆")
mkToggle(auto,"Auto Accept Requests",Config.AutoAcceptRequest,function(v) Config.AutoAcceptRequest=v end)
mkToggle(auto,"Auto Accept Trade",Config.AutoAcceptTrade,function(v) Config.AutoAcceptTrade=v end)
mkToggle(auto,"Auto Confirm Trade",Config.AutoConfirmTrade,function(v) Config.AutoConfirmTrade=v end)
mkToggle(auto,"Auto Send Trading Ticket",Config.AutoSendTicket,function(v) Config.AutoSendTicket=v end)

local actions=group(TL,"Actions","Manual controls","□")
local sendBtn=mkButton(actions,"SEND TRADE REQUEST",32)
local acceptBtn=mkButton(actions,"ACCEPT CURRENT REQUEST",32)
local confirmBtn=mkButton(actions,"CONFIRM CURRENT TRADE",32)
local declineBtn=mkButton(actions,"DECLINE CURRENT TRADE",32)

local extra=group(TL,"Extra","Optional helpers","▣")
mkToggle(extra,"Auto Unfavorite Matching Pets",Config.AutoUnfavorite,function(v) Config.AutoUnfavorite=v end)
mkToggle(extra,"Skip Locked / Favorite Pets",Config.SkipLocked,function(v) Config.SkipLocked=v end)
mkToggle(extra,"Gift System",Config.GiftSystem,function(v) Config.GiftSystem=v end)

local live=group(TR,"Live State","Always-visible status","▣")
local LiveText=mkLabel(live,"Trade: IDLE\nTarget: NONE\nTicket: CHECKING\nAction: Ready",11,T.Muted,70) LiveText.TextWrapped=true

local quick=group(TR,"Quick Info","Current configuration","◇")
local QuickText=mkLabel(quick,"Level: 0 - 100\nWeight: 0 - ∞\nPets: ALL\nMutations: ALL\nRarity: ALL",10,T.Muted,80) QuickText.TextWrapped=true

local gift=group(TR,"Gift","Pet gifting helper","◆")
local giftBtn=mkButton(gift,"GIFT TO TARGET",32)

group(PR,"Pet Selection","Filter pet names; blank = all","◆")
local PetNames=mkInput(PR,"Pet names (comma separated)","",false)
group(PR,"Mutation / Rarity","Filter live PetData fields","◇")
local Mutations=mkInput(PR,"MutationType (comma separated)","",false)
local Rarities=mkInput(PR,"Rarity (comma separated)","",false)
local Range=group(PR,"Level / Weight","Numeric ranges","▣")
local MinLevel=mkInput(Range,"Min Level",0,true)
local MaxLevel=mkInput(Range,"Max Level",100,true)
local MinWeight=mkInput(Range,"Min BaseWeight",0,true)
local MaxWeight=mkInput(Range,"Max BaseWeight",999999,true)
local MatchInfo=mkLabel(PP or PR,"",10,T.Muted,28)

local function split(text)
    local set={}
    for part in string.gmatch(string.lower(text or ""),"[^,]+") do
        part=part:gsub("^%s+",""):gsub("%s+$","") if part~="" then set[part]=true end
    end
    return set
end

for _,box in ipairs({PetNames,Mutations,Rarities,MinLevel,MaxLevel,MinWeight,MaxWeight}) do
    box.FocusLost:Connect(function()
        Config.Pets=split(PetNames.Text)
        Config.Mutations=split(Mutations.Text)
        Config.Rarities=split(Rarities.Text)
        Config.MinLevel=math.max(0,tonumber(MinLevel.Text) or 0)
        Config.MaxLevel=math.max(Config.MinLevel,tonumber(MaxLevel.Text) or 100)
        Config.MinWeight=math.max(0,tonumber(MinWeight.Text) or 0)
        Config.MaxWeight=math.max(Config.MinWeight,tonumber(MaxWeight.Text) or math.huge)
    end)
end

local statsBox=group(SL,"Trade Stats","Session totals","▣")
local StatsText=mkLabel(statsBox,"",11,T.Text,105) StatsText.TextWrapped=true
local actBox=group(SL,"Activity","Latest operation","□")
local ActivityText=mkLabel(actBox,"",10,T.Muted,70) ActivityText.TextWrapped=true
mkButton(SL,"RESET STATS",32).Activated:Connect(function() for k in pairs(Stats) do Stats[k]=0 end LastAction="Stats reset" end)
local filterBox=group(SR,"Filter Snapshot","Active pet matching","◇")
local FilterText=mkLabel(filterBox,"",10,T.Muted,80) FilterText.TextWrapped=true

local function setTarget()
    local q=string.lower((Target.Text or ""):gsub("^%s+",""):gsub("%s+$",""))
    if q=="" then targetState.Text="Target: NONE" targetState.TextColor3=T.Muted return nil end
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer then
            local n,d=string.lower(p.Name),string.lower(p.DisplayName)
            if n==q or d==q or string.find(n,q,1,true) then
                Target.Text=p.Name targetState.Text="Target: @"..p.Name targetState.TextColor3=T.Success return p
            end
        end
    end
    targetState.Text="Target: NOT FOUND" targetState.TextColor3=T.Danger
end
find.Activated:Connect(setTarget)
Target.FocusLost:Connect(setTarget)

sendBtn.Activated:Connect(function()
    local p=setTarget()
    if not p then LastAction="Target not found" return end
    local ok=pcall(function() SendRequest:FireServer(p) end)
    if ok then Stats.Sent+=1 LastAction="Request sent" else Stats.Failed+=1 LastAction="Request failed" end
end)
acceptBtn.Activated:Connect(function()
    local ok=pcall(function() AcceptRemote:FireServer() end)
    if ok then Stats.Accepts+=1 LastAction="Accept sent" else Stats.Failed+=1 LastAction="Accept failed" end
end)
confirmBtn.Activated:Connect(function()
    if not TradingController.CurrentTradeReplicator then LastAction="No active trade" return end
    local ok=pcall(function() ConfirmRemote:FireServer() end)
    if ok then Stats.Confirms+=1 LastAction="Confirm sent" else Stats.Failed+=1 LastAction="Confirm failed" end
end)
declineBtn.Activated:Connect(function() local ok=pcall(function() DeclineRemote:FireServer() end) LastAction=ok and "Trade declined" or "Decline failed" end)
giftBtn.Activated:Connect(function()
    local p=setTarget()
    if not p or not GiftRemote then LastAction="Target/Gift remote unavailable" return end
    local ok=pcall(function() GiftRemote:FireServer("GivePet",p) end)
    LastAction=ok and "Gift request sent" or "Gift request failed"
end)

TradeEvents.SendRequest.OnClientEvent:Connect(function(requestId,sender)
    if not Running or not Config.AutoAcceptRequest then return end
    local ok=pcall(function() RespondRequest:FireServer(requestId,true) end)
    if ok then Stats.Requests+=1 LastAction="Accepted @"..tostring(sender and sender.Name or "player") else Stats.Failed+=1 LastAction="Request accept failed" end
end)

local function inventory()
    local ok,data=pcall(function() return DataService:GetData() end)
    if not ok or not data then return {} end
    return data.PetsData and data.PetsData.PetInventory and data.PetsData.PetInventory.Data or {}
end
local function rarity(petType)
    local e=PetRegistry and PetRegistry.PetList and PetRegistry.PetList[petType]
    return e and (e.Rarity or e.RarityName) or ""
end
local function matches(uuid,pet)
    local pd=pet and pet.PetData if not pd then return false end
    local lvl=tonumber(pd.Level) or 0 local w=tonumber(pd.BaseWeight) or 0
    if lvl<Config.MinLevel or lvl>Config.MaxLevel or w<Config.MinWeight or w>Config.MaxWeight then return false end
    local lowerType=string.lower(pet.PetType or "") local lowerMut=string.lower(tostring(pd.MutationType or "")) local lowerRare=string.lower(rarity(pet.PetType))
    if next(Config.Pets) and not Config.Pets[lowerType] and not Config.Pets[pet.PetType] then return false end
    if next(Config.Mutations) and not Config.Mutations[lowerMut] and not Config.Mutations[pd.MutationType] then return false end
    if next(Config.Rarities) and not Config.Rarities[lowerRare] and not Config.Rarities[rarity(pet.PetType)] then return false end
    if Config.SkipLocked and pet.tradeLock and pet.tradeLock.Type=="Permanent" then return false end
    if Config.SkipLocked and not Config.AutoUnfavorite and pd.IsFavorite==true then return false end
    return true
end
local function toolByUUID(uuid)
    for _,c in ipairs({LocalPlayer.Character,LocalPlayer.Backpack}) do
        if c then for _,o in ipairs(c:GetChildren()) do if o:IsA("Tool") and (o:GetAttribute("PET_UUID")==uuid or o:GetAttribute(InvEnums.ITEM_UUID)==uuid) then return o end end end
    end
end
local function unfavorite(uuid)
    if not FavoriteRemote then return end
    local tool=toolByUUID(uuid)
    if tool and tool:GetAttribute(InvEnums.Favorite)==true then
        local ok=pcall(function() FavoriteRemote:FireServer(tool) end)
        if ok then Stats.Unfav+=1 end
    end
end
local function addMatching()
    local rep=TradingController.CurrentTradeReplicator if not rep then return end
    local trade=rep:GetData() if not trade then return end
    local me=table.find(trade.players,LocalPlayer) if not me then return end
    local offer=trade.offers[me] if not offer then return end
    local existing={} local count=0
    for _,item in pairs(offer.items or {}) do existing[item.id]=true count+=1 end
    local limit=tonumber(TradeData.ItemLimit) or 6
    if count>=limit then return end
    for uuid,pet in pairs(inventory()) do
        if count>=limit then break end
        if not existing[uuid] and matches(uuid,pet) then
            if Config.AutoUnfavorite and pet.PetData.IsFavorite==true then unfavorite(uuid) task.wait(.04) end
            local ok=pcall(function() AddItem:FireServer("Pet",uuid) end)
            if ok then Stats.Added+=1 count+=1 existing[uuid]=true LastAction="Added "..tostring(pet.PetType) end
            task.wait(.05)
        end
    end
end
local function findTicket()
    for _,c in ipairs({LocalPlayer.Character,LocalPlayer.Backpack}) do if c then for _,o in ipairs(c:GetChildren()) do if o:IsA("Tool") and string.find(string.lower(o.Name),"trading ticket",1,true) then return o end end end end
end
local function sendTicket()
    if os.clock()-LastSend<4 or TradingController.CurrentTradeReplicator then return end
    local p=setTarget() if not p then return end local ticket=findTicket() if not ticket then LastAction="Trading Ticket not found" return end
    local hum=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") if not hum then return end
    if ticket.Parent~=LocalPlayer.Character then pcall(function() hum:EquipTool(ticket) end) task.wait(.12) end
    LastSend=os.clock()
    local ok=pcall(function() SendRequest:FireServer(p) end)
    if ok then Stats.Sent+=1 LastAction="Ticket request sent" else Stats.Failed+=1 LastAction="Ticket request failed" end
end
local function processTrade()
    local rep=TradingController.CurrentTradeReplicator if not rep then return end
    local trade=rep:GetData() if not trade then return end
    local me=table.find(trade.players,LocalPlayer) if not me then return end
    local other=me==1 and 2 or 1
    local a,b=trade.states[me],trade.states[other]
    local elapsed=workspace:GetServerTimeNow()-(trade.lastChange or 0)
    local cd=tonumber(TradeData.ButtonCooldown) or 5
    if TradeSeen~=TradingController.CurrentTradeId then TradeSeen=TradingController.CurrentTradeId LastAccept=0 LastConfirm=0 LastAdd=0 end
    if Config.AutoUnfavorite and os.clock()-LastAdd>.5 then addMatching() LastAdd=os.clock() end
    if Config.AutoAcceptTrade and a=="None" and elapsed>=cd and os.clock()-LastAccept>.7 then
        local ok=pcall(function() AcceptRemote:FireServer() end) LastAccept=os.clock() if ok then Stats.Accepts+=1 LastAction="Auto accept sent" else Stats.Failed+=1 end
    end
    if Config.AutoConfirmTrade and a=="Accepted" and (b=="Accepted" or b=="Confirmed") and elapsed>=cd and os.clock()-LastConfirm>.7 then
        local ok=pcall(function() ConfirmRemote:FireServer() end) LastConfirm=os.clock() if ok then Stats.Confirms+=1 LastAction="Auto confirm sent" else Stats.Failed+=1 end
    end
end

-- minimize / close / drag
local minimized=false
Min.Activated:Connect(function()
    minimized=not minimized
    Sidebar.Visible=not minimized Content.Visible=not minimized Footer.Visible=not minimized bottomLine.Visible=not minimized sideLine.Visible=not minimized search.Visible=not minimized
    TweenService:Create(Main,TweenInfo.new(.16,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=minimized and UDim2.fromOffset(720,48) or UDim2.fromOffset(720,480)}):Play()
    Min.Text=minimized and "+" or "—"
end)
Close.Activated:Connect(function() Running=false Gui:Destroy() end)
local dragging=false dragStart startPosition dragInput
Header.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true dragStart=input.Position startPosition=Main.Position input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end) end end)
Header.InputChanged:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end end)
UserInputService.InputChanged:Connect(function(input) if dragging and input==dragInput then local d=input.Position-dragStart Main.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+d.X,startPosition.Y.Scale,startPosition.Y.Offset+d.Y) end end)

-- live render
local function setPage(n)
    for k,p in pairs(pages) do p.Visible=(k==n) end
    for k,b in pairs(buttons) do local a=k==n b.BackgroundTransparency=a and 0 or 1 b.BackgroundColor3=a and Color3.fromRGB(43,30,65) or T.Background for _,c in ipairs(b:GetChildren()) do if c:IsA("TextLabel") then c.TextTransparency=a and 0 or .5 end end end
end
setPage("Trading")

task.spawn(function()
    while Running do
        Config.Pets=split(PetNames.Text) Config.Mutations=split(Mutations.Text) Config.Rarities=split(Rarities.Text)
        Config.MinLevel=math.max(0,tonumber(MinLevel.Text) or 0) Config.MaxLevel=math.max(Config.MinLevel,tonumber(MaxLevel.Text) or 100)
        Config.MinWeight=math.max(0,tonumber(MinWeight.Text) or 0) Config.MaxWeight=math.max(Config.MinWeight,tonumber(MaxWeight.Text) or math.huge)
        local target=findTarget() local rep=TradingController.CurrentTradeReplicator local ticket=findTicket()
        LiveText.Text=string.format("Trade: %s\nTarget: %s\nTicket: %s\nAction: %s",rep and "ACTIVE" or "IDLE",target and ("@"..target.Name) or "NONE",ticket and "FOUND" or "MISSING",LastAction)
        StatsText.Text=string.format("Tickets sent      %d\nRequests accepted %d\nTrades accepted   %d\nConfirmed         %d\nPets added        %d\nUnfavorited       %d\nFailures          %d",Stats.Sent,Stats.Requests,Stats.Accepts,Stats.Confirms,Stats.Added,Stats.Unfav,Stats.Failed)
        ActivityText.Text=string.format("Last: %s\nTarget: %s\nTrade: %s",LastAction,target and ("@"..target.Name) or "NONE",rep and "ACTIVE" or "IDLE")
        QuickText.Text=string.format("Level: %d - %d\nWeight: %s - %s\nPets: %s\nMutations: %s\nRarity: %s",Config.MinLevel,Config.MaxLevel,tostring(Config.MinWeight),tostring(Config.MaxWeight),next(Config.Pets) and "SELECTED" or "ALL",next(Config.Mutations) and "SELECTED" or "ALL",next(Config.Rarities) and "SELECTED" or "ALL")
        local count=0 for uuid,pet in pairs(inventory()) do if matches(uuid,pet) then count+=1 end end
        MatchInfo.Text="Matching inventory: "..count.." pets"
        FilterText.Text=string.format("Matching pets: %d\nLevel: %d-%d\nBaseWeight: %s-%s\nMutation filter: %s",count,Config.MinLevel,Config.MaxLevel,tostring(Config.MinWeight),tostring(Config.MaxWeight),next(Config.Mutations) and "ON" or "OFF")
        pcall(processTrade)
        if Config.AutoSendTicket then pcall(sendTicket) end
        task.wait(.18)
    end
end)

_G.FableTrading={
    Config=Config,
    Stats=Stats,
    SendRequest=function(p) return SendRequest:FireServer(p) end,
    Accept=function() return AcceptRemote:FireServer() end,
    Confirm=function() return ConfirmRemote:FireServer() end,
    Decline=function() return DeclineRemote:FireServer() end,
    Gift=function(p) if GiftRemote then return GiftRemote:FireServer("GivePet",p) end end,
}

print("[FABLE] Exo-style Trading v2 loaded")

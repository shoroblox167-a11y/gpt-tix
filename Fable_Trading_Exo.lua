-- FABLE // Trading
-- Exo-style UI shell for the verified trading backend.
-- The backend is loaded from the companion file in the same GitHub repo.

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Root = (gethui and gethui()) or CoreGui

pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/shoroblox167-a11y/gpt-tix/main/TinapayHub_Trading_Compact_Reliable.lua"))()
end)

task.wait(0.2)

for _, name in ipairs({"Fable_Trading", "Fable_Trading_v2"}) do
    local old = Root:FindFirstChild(name) or CoreGui:FindFirstChild(name)
    if old then old:Destroy() end
end

local Backend = getgenv and getgenv().FableTrading or _G.FableTrading
local Config = Backend and Backend.Config or {
    AutoSendTicket=false, AutoAcceptRequest=true, AutoAcceptTrade=true,
    AutoConfirmTrade=true, AutoUnfavorite=true, SkipLockedPets=true,
    GiftSystem=false, MinLevel=0, MaxLevel=100, MinWeight=0, MaxWeight=math.huge,
    Pets={}, Mutations={}, Rarities={}
}
local Stats = Backend and Backend.Stats or {Sent=0,Requests=0,Accepts=0,Confirms=0,Added=0,Unfav=0,Failed=0}

local Theme = {
    Background = Color3.fromRGB(15,15,15),
    Main = Color3.fromRGB(25,25,25),
    Surface = Color3.fromRGB(18,18,20),
    Content = Color3.fromRGB(16,16,17),
    Outline = Color3.fromRGB(40,40,40),
    Accent = Color3.fromRGB(125,85,255),
    AccentSoft = Color3.fromRGB(48,34,72),
    Text = Color3.fromRGB(245,245,245),
    Muted = Color3.fromRGB(132,132,142),
    Green = Color3.fromRGB(92,225,145),
    Red = Color3.fromRGB(255,72,92),
    Font = Enum.Font.Code,
}

local function corner(o,r)
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,r or 6)
    c.Parent=o
    return c
end

local function outline(o,c,tr,w)
    local s=Instance.new("UIStroke")
    s.Color=c or Theme.Outline
    s.Transparency=tr or 0
    s.Thickness=w or 1
    s.Parent=o
    return s
end

local function text(p,s,sz,color,h)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.Text=s or ""
    l.TextSize=sz or 13
    l.TextColor3=color or Theme.Text
    l.Font=Theme.Font
    l.Size=UDim2.new(1,0,0,h or 20)
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.Parent=p
    return l
end

local function button(p,s,h)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(1,0,0,h or 32)
    b.BackgroundColor3=Theme.Main
    b.BorderSizePixel=0
    b.Text=s
    b.TextColor3=Theme.Text
    b.Font=Theme.Font
    b.TextSize=12
    b.AutoButtonColor=false
    b.Parent=p
    corner(b,6)
    outline(b,Theme.Outline,.15)
    return b
end

local function input(p,caption,value,numeric)
    local holder=Instance.new("Frame")
    holder.Size=UDim2.new(1,0,0,48)
    holder.BackgroundTransparency=1
    holder.Parent=p
    text(holder,caption,10,Theme.Muted,15)
    local b=Instance.new("TextBox")
    b.Position=UDim2.fromOffset(0,17)
    b.Size=UDim2.new(1,0,0,30)
    b.BackgroundColor3=Theme.Main
    b.BorderSizePixel=0
    b.Text=tostring(value or "")
    b.PlaceholderText=caption
    b.PlaceholderColor3=Theme.Muted
    b.TextColor3=Theme.Text
    b.Font=Theme.Font
    b.TextSize=12
    b.ClearTextOnFocus=false
    b.Parent=holder
    corner(b,6)
    outline(b,Theme.Outline,.12)
    local pad=Instance.new("UIPadding")
    pad.PaddingLeft=UDim.new(0,8)
    pad.Parent=b
    if numeric then
        b:GetPropertyChangedSignal("Text"):Connect(function()
            local filtered=b.Text:gsub("[^%d%.%-]","")
            if filtered~=b.Text then b.Text=filtered end
        end)
    end
    return b
end

local oldGui=Root:FindFirstChild("Fable_Trading_Exo")
if oldGui then oldGui:Destroy() end
local Gui=Instance.new("ScreenGui")
Gui.Name="Fable_Trading_Exo"
Gui.IgnoreGuiInset=true
Gui.ResetOnSpawn=false
Gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
Gui.Parent=Root

local Main=Instance.new("Frame")
Main.Size=UDim2.fromOffset(720,480)
Main.Position=UDim2.new(.5,-360,.5,-240)
Main.BackgroundColor3=Theme.Background
Main.BorderSizePixel=0
Main.Active=true
Main.Parent=Gui
corner(Main,5)
outline(Main,Theme.Outline)

local topLine=Instance.new("Frame",Main)
topLine.Size=UDim2.new(1,0,0,1)
topLine.Position=UDim2.fromOffset(0,48)
topLine.BackgroundColor3=Theme.Outline
topLine.BorderSizePixel=0
local sideLine=Instance.new("Frame",Main)
sideLine.Size=UDim2.new(0,1,1,-69)
sideLine.Position=UDim2.new(.30,0,0,49)
sideLine.BackgroundColor3=Theme.Outline
sideLine.BorderSizePixel=0
local bottomLine=Instance.new("Frame",Main)
bottomLine.Size=UDim2.new(1,0,0,1)
bottomLine.Position=UDim2.new(0,0,1,-21)
bottomLine.BackgroundColor3=Theme.Outline
bottomLine.BorderSizePixel=0

local Header=Instance.new("Frame",Main)
Header.Size=UDim2.new(1,0,0,48)
Header.BackgroundTransparency=1

local brand=text(Header,"FABLE",20,Theme.Text,48)
brand.Size=UDim2.new(.30,0,1,0)
brand.TextXAlignment=Enum.TextXAlignment.Center

local current=text(Header,"TRADING",10,Theme.Muted,20)
current.Position=UDim2.new(.30,12,0,4)
current.Size=UDim2.new(.20,0,0,20)

local search=Instance.new("TextBox",Header)
search.Position=UDim2.new(.50,0,.5,-14)
search.Size=UDim2.new(.30,0,0,28)
search.BackgroundColor3=Theme.Main
search.BorderSizePixel=0
search.PlaceholderText="Search..."
search.PlaceholderColor3=Theme.Muted
search.TextColor3=Theme.Text
search.Font=Theme.Font
search.TextSize=12
search.ClearTextOnFocus=false
corner(search,6)
outline(search,Theme.Outline,.15)
local sp=Instance.new("UIPadding",search)
sp.PaddingLeft=UDim.new(0,9)

local Min=button(Header,"—",28)
Min.Size=UDim2.fromOffset(30,28)
Min.Position=UDim2.new(1,-68,0,10)
Min.TextXAlignment=Enum.TextXAlignment.Center
local Close=button(Header,"×",28)
Close.Size=UDim2.fromOffset(30,28)
Close.Position=UDim2.new(1,-34,0,10)
Close.TextXAlignment=Enum.TextXAlignment.Center
Close.TextColor3=Theme.Red

local Footer=text(Main,"Fable  •  Trading",9,Theme.Muted,20)
Footer.Position=UDim2.new(0,0,1,-20)
Footer.TextXAlignment=Enum.TextXAlignment.Center

local Sidebar=Instance.new("ScrollingFrame",Main)
Sidebar.Position=UDim2.fromOffset(0,49)
Sidebar.Size=UDim2.new(.30,0,1,-70)
Sidebar.BackgroundColor3=Theme.Background
Sidebar.BorderSizePixel=0
Sidebar.ScrollBarThickness=0
Sidebar.AutomaticCanvasSize=Enum.AutomaticSize.Y
local sidePad=Instance.new("UIPadding",Sidebar)
sidePad.PaddingTop=UDim.new(0,8)
sidePad.PaddingLeft=UDim.new(0,6)
sidePad.PaddingRight=UDim.new(0,6)
local sideList=Instance.new("UIListLayout",Sidebar)
sideList.Padding=UDim.new(0,2)

local Content=Instance.new("Frame",Main)
Content.Position=UDim2.new(.30,1,0,49)
Content.Size=UDim2.new(.70,-1,1,-70)
Content.BackgroundColor3=Theme.Content
Content.BorderSizePixel=0

local pages={}
local nav={}
local function makePage(name)
    local p=Instance.new("Frame",Content)
    p.Name=name
    p.Size=UDim2.fromScale(1,1)
    p.BackgroundTransparency=1
    p.Visible=false
    local left=Instance.new("ScrollingFrame",p)
    left.Position=UDim2.fromOffset(7,7)
    left.Size=UDim2.new(.5,-10,1,-14)
    left.BackgroundTransparency=1
    left.BorderSizePixel=0
    left.ScrollBarThickness=2
    left.ScrollBarImageColor3=Theme.Accent
    left.AutomaticCanvasSize=Enum.AutomaticSize.Y
    local right=Instance.new("ScrollingFrame",p)
    right.Position=UDim2.new(.5,3,0,7)
    right.Size=UDim2.new(.5,-10,1,-14)
    right.BackgroundTransparency=1
    right.BorderSizePixel=0
    right.ScrollBarThickness=2
    right.ScrollBarImageColor3=Theme.Accent
    right.AutomaticCanvasSize=Enum.AutomaticSize.Y
    for _,sc in ipairs({left,right}) do
        local pad=Instance.new("UIPadding",sc)
        pad.PaddingLeft=UDim.new(0,2)
        pad.PaddingRight=UDim.new(0,4)
        pad.PaddingBottom=UDim.new(0,10)
        local list=Instance.new("UIListLayout",sc)
        list.Padding=UDim.new(0,7)
    end
    pages[name]={Frame=p,Left=left,Right=right}
    return pages[name]
end

local trade=makePage("Trading")
local filters=makePage("Filters")
local stats=makePage("Stats")

local function navButton(name,icon)
    local b=Instance.new("TextButton",Sidebar)
    b.Size=UDim2.new(1,0,0,40)
    b.BackgroundColor3=Theme.Background
    b.BackgroundTransparency=1
    b.BorderSizePixel=0
    b.Text=""
    b.AutoButtonColor=false
    corner(b,4)
    local i=text(b,icon,14,Theme.Accent,40)
    i.Size=UDim2.fromOffset(24,40)
    i.Position=UDim2.fromOffset(6,0)
    i.TextXAlignment=Enum.TextXAlignment.Center
    local l=text(b,name,14,Theme.Text,40)
    l.Position=UDim2.fromOffset(34,0)
    l.Size=UDim2.new(1,-40,1,0)
    l.TextTransparency=.5
    nav[name]=b
    b.Activated:Connect(function()
        for n,v in pairs(pages) do v.Frame.Visible=(n==name) end
        for n,v in pairs(nav) do
            local active=n==name
            v.BackgroundTransparency=active and 0 or 1
            v.BackgroundColor3=active and Theme.AccentSoft or Theme.Background
            for _,child in ipairs(v:GetChildren()) do
                if child:IsA("TextLabel") then child.TextTransparency=active and 0 or .5 end
            end
        end
        current.Text=string.upper(name)
    end)
    return b
end

navButton("Trading","◇")
navButton("Filters","◆")
navButton("Stats","▣")

local function group(parent,titleText,descText,icon)
    local box=Instance.new("Frame")
    box.Size=UDim2.new(1,0,0,0)
    box.AutomaticSize=Enum.AutomaticSize.Y
    box.BackgroundColor3=Color3.fromRGB(12,12,13)
    box.BorderSizePixel=0
    box.Parent=parent
    corner(box,8)
    outline(box,Color3.fromRGB(72,72,72),.2)
    local head=Instance.new("Frame",box)
    head.Size=UDim2.new(1,0,0,44)
    head.BackgroundTransparency=1
    local ic=text(head,icon or "□",14,Theme.Accent,28)
    ic.Size=UDim2.fromOffset(28,28)
    ic.Position=UDim2.fromOffset(8,7)
    ic.TextXAlignment=Enum.TextXAlignment.Center
    local tt=text(head,titleText,14,Theme.Text,18)
    tt.Position=UDim2.fromOffset(42,5)
    tt.Size=UDim2.new(1,-50,0,18)
    if descText then
        local d=text(head,descText,9,Theme.Muted,15)
        d.Position=UDim2.fromOffset(42,23)
        d.Size=UDim2.new(1,-50,0,15)
    end
    local inner=Instance.new("Frame",box)
    inner.Size=UDim2.new(1,0,0,0)
    inner.AutomaticSize=Enum.AutomaticSize.Y
    inner.BackgroundColor3=Color3.fromRGB(11,11,12)
    inner.BorderSizePixel=0
    local pad=Instance.new("UIPadding",inner)
    pad.PaddingLeft=UDim.new(0,6)
    pad.PaddingRight=UDim.new(0,6)
    pad.PaddingBottom=UDim.new(0,8)
    local list=Instance.new("UIListLayout",inner)
    list.Padding=UDim.new(0,6)
    return inner
end

local targetGroup=group(trade.Left,"Target Player","Select an online player","◇")
local targetButton=button(targetGroup,"No player selected",32)
local playerList=Instance.new("ScrollingFrame",targetGroup)
playerList.Size=UDim2.new(1,0,0,0)
playerList.AutomaticSize=Enum.AutomaticSize.Y
playerList.CanvasSize=UDim2.new()
playerList.AutomaticCanvasSize=Enum.AutomaticSize.Y
playerList.BackgroundColor3=Theme.Surface
playerList.BorderSizePixel=0
playerList.Visible=false
playerList.ScrollBarThickness=2
playerList.ScrollBarImageColor3=Theme.Accent
corner(playerList,6)
local ppl=Instance.new("UIListLayout",playerList)
ppl.Padding=UDim.new(0,2)
local function refreshPlayers()
    for _,c in ipairs(playerList:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer then
            local b=button(playerList,"@"..p.Name,28)
            b.TextXAlignment=Enum.TextXAlignment.Left
            b.Activated:Connect(function()
                targetButton.Text="@"..p.Name
                _G.FableTradingTarget=p
                playerList.Visible=false
            end)
        end
    end
end
refreshPlayers()
Players.PlayerAdded:Connect(refreshPlayers)
Players.PlayerRemoving:Connect(refreshPlayers)
targetButton.Activated:Connect(function() refreshPlayers() playerList.Visible=not playerList.Visible end)

local auto=group(trade.Left,"Automation","Verified trading actions","◆")
toggle(auto,"Auto Accept Requests",Config.AutoAcceptRequest,function(v) Config.AutoAcceptRequest=v end)
toggle(auto,"Auto Accept Trade",Config.AutoAcceptTrade,function(v) Config.AutoAcceptTrade=v end)
toggle(auto,"Auto Confirm Trade",Config.AutoConfirmTrade,function(v) Config.AutoConfirmTrade=v end)
toggle(auto,"Auto Send Trading Ticket",Config.AutoSendTicket,function(v) Config.AutoSendTicket=v end)

local item=group(trade.Right,"Item Handling","Pet selection behavior","▣")
toggle(item,"Auto Unfavorite Matching Pets",Config.AutoUnfavorite,function(v) Config.AutoUnfavorite=v end)
toggle(item,"Skip Locked Pets",Config.SkipLocked,function(v) Config.SkipLocked=v end)
toggle(item,"Gift System",Config.GiftSystem,function(v) Config.GiftSystem=v end)

local actions=group(trade.Right,"Actions","Manual controls","□")
local send=button(actions,"SEND TRADE REQUEST",34)
local accept=button(actions,"ACCEPT CURRENT REQUEST",34)
local confirm=button(actions,"CONFIRM CURRENT TRADE",34)
local decline=button(actions,"DECLINE CURRENT TRADE",34)
local gift=button(actions,"GIFT TO SELECTED PLAYER",34)

local live=group(trade.Right,"Live Status","Current state","◇")
local Live=text(live,"Trade: IDLE\nTarget: NONE\nTicket: CHECKING\nAction: Ready",10,Theme.Muted,64)
Live.TextWrapped=true

local pf=group(filters.Left,"Pet Selection","Comma-separated, blank = all","◆")
local PetNames=input(pf,"Pet names","",false)
local mr=group(filters.Left,"Mutation / Rarity","Uses live pet data","◇")
local Mutations=input(mr,"MutationType","",false)
local Rarities=input(mr,"Rarity","",false)
local rg=group(filters.Right,"Level Range","PetData.Level","▣")
local MinLevel=input(rg,"Min Level",0,true)
local MaxLevel=input(rg,"Max Level",100,true)
local wg=group(filters.Right,"Weight Range","PetData.BaseWeight","▣")
local MinWeight=input(wg,"Min BaseWeight",0,true)
local MaxWeight=input(wg,"Max BaseWeight",999999,true)
local MatchInfo=text(filters.Right,"Filter entries: 0",10,Theme.Muted,22)

local st=group(stats.Left,"Trade Stats","Session","▣")
local StatsText=text(st,"",11,Theme.Text,105)
StatsText.TextWrapped=true
local ac=group(stats.Left,"Activity","Latest operation","□")
local ActivityText=text(ac,"",10,Theme.Muted,70)
ActivityText.TextWrapped=true
local sn=group(stats.Right,"Filter Snapshot","Active filters","◇")
local Snapshot=text(sn,"",10,Theme.Muted,85)
Snapshot.TextWrapped=true
button(stats.Right,"RESET STATS",32).Activated:Connect(function() for k in pairs(Stats) do Stats[k]=0 end end)

local function split(value)
    local set={}
    for part in string.gmatch(string.lower(value or ""),"[^,]+") do
        part=part:gsub("^%s+",""):gsub("%s+$","")
        if part~="" then set[part]=true end
    end
    return set
end
local function refreshFilters()
    Config.Pets=split(PetNames.Text)
    Config.Mutations=split(Mutations.Text)
    Config.Rarities=split(Rarities.Text)
    Config.MinLevel=math.max(0,tonumber(MinLevel.Text) or 0)
    Config.MaxLevel=math.max(Config.MinLevel,tonumber(MaxLevel.Text) or 100)
    Config.MinWeight=math.max(0,tonumber(MinWeight.Text) or 0)
    Config.MaxWeight=math.max(Config.MinWeight,tonumber(MaxWeight.Text) or math.huge)
end
for _,b in ipairs({PetNames,Mutations,Rarities,MinLevel,MaxLevel,MinWeight,MaxWeight}) do b.FocusLost:Connect(refreshFilters) end

local function targetPlayer()
    local p=_G.FableTradingTarget
    if p and p.Parent==Players then return p end
    local q=string.lower((targetButton.Text or ""):gsub("^@",""))
    if q=="" or q=="no player selected" then return nil end
    for _,x in ipairs(Players:GetPlayers()) do if x~=LocalPlayer and (string.lower(x.Name)==q or string.lower(x.DisplayName)==q) then return x end end
end

send.Activated:Connect(function() local p=targetPlayer() if p and Backend and Backend.SendRequest then Backend.SendRequest(p) end end)
accept.Activated:Connect(function() if Backend and Backend.Accept then Backend.Accept() end end)
confirm.Activated:Connect(function() if Backend and Backend.Confirm then Backend.Confirm() end end)
decline.Activated:Connect(function() if Backend and Backend.Decline then Backend.Decline() end end)
gift.Activated:Connect(function() local p=targetPlayer() if p and Backend and Backend.Gift then Backend.Gift(p) end end)

local minimized=false
local dragging=false
local dragStart
local startPosition
local dragInput
Header.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true dragStart=input.Position startPosition=Main.Position
        input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
    end
end)
Header.InputChanged:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input==dragInput then
        local d=input.Position-dragStart
        Main.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+d.X,startPosition.Y.Scale,startPosition.Y.Offset+d.Y)
    end
end)
Min.Activated:Connect(function()
    minimized=not minimized
    Sidebar.Visible=not minimized Content.Visible=not minimized Footer.Visible=not minimized bottomLine.Visible=not minimized sideLine.Visible=not minimized search.Visible=not minimized
    TweenService:Create(Main,TweenInfo.new(.17,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=minimized and UDim2.fromOffset(720,48) or UDim2.fromOffset(720,480)}):Play()
    Min.Text=minimized and "+" or "—"
end)
Close.Activated:Connect(function() Running=false Gui:Destroy() end)

nav.Trading:Activate()

print("[FABLE] Exo-style Trading UI v3 loaded")

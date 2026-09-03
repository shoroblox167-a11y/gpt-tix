-- Fable Trading UI
-- Exo-inspired Trading tab: compact, draggable, minimizable, grouped controls.
-- Verified game-facing remotes/data are retained; UI is intentionally trading-only.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local TS=game:GetService("TweenService")
local LP=Players.LocalPlayer
local Modules=RS:WaitForChild("Modules")
local GE=RS:WaitForChild("GameEvents")
local TE=GE:WaitForChild("TradeEvents")
local DataService=require(Modules:WaitForChild("DataService"))
local TradingController=require(Modules.TradeControllers:WaitForChild("TradingController"))
local TradeData=require(RS.Data:WaitForChild("TradeData"))
local InvEnums=require(RS.Data.EnumRegistry:WaitForChild("InventoryServiceEnums"))
local PetRegistry=pcall(function() return require(RS.Data.PetRegistry) end) and require(RS.Data.PetRegistry) or nil

local SendRequest=TE:WaitForChild("SendRequest")
local RespondRequest=TE:WaitForChild("RespondRequest")
local AddItem=TE:WaitForChild("AddItem")
local FavoriteRemote=GE:FindFirstChild("Favorite_Item")

local C={AutoSend=false,AutoRequest=true,AutoAccept=true,AutoConfirm=true,AutoUnfavorite=true,SkipLocked=true,MinLevel=0,MaxLevel=100,MinWeight=0,MaxWeight=math.huge,Pet={},Mutation={},Rarity={}}
local S={Sent=0,Requests=0,Accepts=0,Confirms=0,Added=0,Unfav=0,Failed=0}
local running=true

-- ================= UI / Exo-inspired =================
local old=(gethui and gethui():FindFirstChild("Fable_Trading")) or game:GetService("CoreGui"):FindFirstChild("Fable_Trading")
if old then old:Destroy() end
local Gui=Instance.new("ScreenGui")
Gui.Name="Fable_Trading";Gui.ResetOnSpawn=false;Gui.IgnoreGuiInset=true
Gui.Parent=(gethui and gethui()) or game:GetService("CoreGui")

local Main=Instance.new("Frame");Main.Size=UDim2.fromOffset(570,410);Main.Position=UDim2.new(.5,-285,.5,-205);Main.BackgroundColor3=Color3.fromRGB(18,18,23);Main.BorderSizePixel=0;Main.Parent=Gui
Instance.new("UICorner",Main).CornerRadius=UDim.new(0,10)
local Outline=Instance.new("UIStroke",Main);Outline.Color=Color3.fromRGB(105,78,180);Outline.Thickness=1
local Header=Instance.new("Frame",Main);Header.Size=UDim2.new(1,0,0,48);Header.BackgroundColor3=Color3.fromRGB(24,22,31);Header.BorderSizePixel=0
Instance.new("UICorner",Header).CornerRadius=UDim.new(0,10)
local Brand=Instance.new("TextLabel",Header);Brand.BackgroundTransparency=1;Brand.Position=UDim2.fromOffset(16,5);Brand.Size=UDim2.new(1,-110,0,22);Brand.Text="FABLE";Brand.Font=Enum.Font.GothamBold;Brand.TextSize=15;Brand.TextColor3=Color3.fromRGB(220,205,255);Brand.TextXAlignment=Enum.TextXAlignment.Left
local Sub=Instance.new("TextLabel",Header);Sub.BackgroundTransparency=1;Sub.Position=UDim2.fromOffset(16,26);Sub.Size=UDim2.new(1,-110,0,16);Sub.Text="Trading System";Sub.Font=Enum.Font.Gotham;Sub.TextSize=9;Sub.TextColor3=Color3.fromRGB(125,120,140);Sub.TextXAlignment=Enum.TextXAlignment.Left
local Min=Instance.new("TextButton",Header);Min.Size=UDim2.fromOffset(30,28);Min.Position=UDim2.new(1,-68,0,10);Min.Text="—";Min.Font=Enum.Font.GothamBold;Min.TextSize=16;Min.TextColor3=Color3.fromRGB(210,210,220);Min.BackgroundColor3=Color3.fromRGB(38,35,48);Instance.new("UICorner",Min).CornerRadius=UDim.new(0,7)
local Close=Instance.new("TextButton",Header);Close.Size=UDim2.fromOffset(30,28);Close.Position=UDim2.new(1,-34,0,10);Close.Text="×";Close.Font=Enum.Font.GothamBold;Close.TextSize=18;Close.TextColor3=Color3.fromRGB(255,125,145);Close.BackgroundColor3=Color3.fromRGB(48,29,37);Instance.new("UICorner",Close).CornerRadius=UDim.new(0,7)

local Sidebar=Instance.new("Frame",Main);Sidebar.Position=UDim2.fromOffset(10,58);Sidebar.Size=UDim2.fromOffset(125,342);Sidebar.BackgroundColor3=Color3.fromRGB(22,21,28);Sidebar.BorderSizePixel=0;Instance.new("UICorner",Sidebar).CornerRadius=UDim.new(0,8)
local Content=Instance.new("Frame",Main);Content.Position=UDim2.fromOffset(145,58);Content.Size=UDim2.new(1,-155,1,-68);Content.BackgroundTransparency=1
local Page=Instance.new("ScrollingFrame",Content);Page.Size=UDim2.fromScale(1,1);Page.BackgroundTransparency=1;Page.BorderSizePixel=0;Page.ScrollBarThickness=2;Page.CanvasSize=UDim2.new();Page.AutomaticCanvasSize=Enum.AutomaticSize.Y
local Pad=Instance.new("UIPadding",Page);Pad.PaddingLeft=UDim.new(0,3);Pad.PaddingRight=UDim.new(0,7);Pad.PaddingBottom=UDim.new(0,8)
local List=Instance.new("UIListLayout",Page);List.Padding=UDim.new(0,7)

local function button(parent,text,h)
 local b=Instance.new("TextButton",parent);b.Size=UDim2.new(1,0,0,h or 32);b.BackgroundColor3=Color3.fromRGB(30,29,38);b.BorderSizePixel=0;b.Text=text;b.TextColor3=Color3.fromRGB(190,187,205);b.Font=Enum.Font.GothamMedium;b.TextSize=10;b.TextXAlignment=Enum.TextXAlignment.Left;Instance.new("UICorner",b).CornerRadius=UDim.new(0,7);return b
end
local function label(parent,text)
 local l=Instance.new("TextLabel",parent);l.Size=UDim2.new(1,0,0,18);l.BackgroundTransparency=1;l.Text=text;l.TextColor3=Color3.fromRGB(150,145,165);l.Font=Enum.Font.GothamBold;l.TextSize=9;l.TextXAlignment=Enum.TextXAlignment.Left;return l
end
local function toggle(parent,text,default)
 local b=button(parent,(default and "●  " or "○  ")..text,30);local state=default
 local function draw() b.Text=(state and "●  " or "○  ")..text;b.TextColor3=state and Color3.fromRGB(211,195,255) or Color3.fromRGB(160,158,175);b.BackgroundColor3=state and Color3.fromRGB(48,37,70) or Color3.fromRGB(30,29,38) end
 b.Activated:Connect(function() state=not state;draw() end);draw();return function() return state end
end
local function input(parent,text,default)
 local f=Instance.new("TextBox",parent);f.Size=UDim2.new(1,0,0,30);f.BackgroundColor3=Color3.fromRGB(27,26,34);f.BorderSizePixel=0;f.PlaceholderText=text;f.Text=default or "";f.TextColor3=Color3.fromRGB(230,228,240);f.PlaceholderColor3=Color3.fromRGB(105,102,120);f.Font=Enum.Font.Gotham;f.TextSize=10;f.ClearTextOnFocus=false;Instance.new("UICorner",f).CornerRadius=UDim.new(0,7);return f
end
local function group(title,desc)
 local g=Instance.new("Frame",Page);g.Size=UDim2.new(1,0,0,0);g.AutomaticSize=Enum.AutomaticSize.Y;g.BackgroundColor3=Color3.fromRGB(22,21,28);g.BorderSizePixel=0;Instance.new("UICorner",g).CornerRadius=UDim.new(0,8);local p=Instance.new("UIPadding",g);p.PaddingTop=UDim.new(0,9);p.PaddingBottom=UDim.new(0,9);p.PaddingLeft=UDim.new(0,10);p.PaddingRight=UDim.new(0,10);local l=label(g,title);l.Size=UDim2.new(1,0,0,16);if desc then local d=label(g,desc);d.Font=Enum.Font.Gotham;d.TextColor3=Color3.fromRGB(105,102,120);d.Size=UDim2.new(1,0,0,16) end;local inner=Instance.new("Frame",g);inner.Size=UDim2.new(1,0,0,0);inner.AutomaticSize=Enum.AutomaticSize.Y;inner.BackgroundTransparency=1;local il=Instance.new("UIListLayout",inner);il.Padding=UDim.new(0,5);return inner end

local tabButtons={};local function tab(name,icon)
 local b=button(Sidebar,(icon or "").."  "..name,34);b.TextXAlignment=Enum.TextXAlignment.Left;tabButtons[name]=b;return b end
local TradeTab=tab("Trade","◈");local PetsTab=tab("Pets","◆");local FiltersTab=tab("Filters","◇");local StatsTab=tab("Stats","▣")
local pages={}
local function newPage() local p=Instance.new("Frame",Page);p.Size=UDim2.new(1,0,0,0);p.AutomaticSize=Enum.AutomaticSize.Y;p.BackgroundTransparency=1;local l=Instance.new("UIListLayout",p);l.Padding=UDim.new(0,7);return p end
for _,n in ipairs({"Trade","Pets","Filters","Stats"}) do pages[n]=newPage() end
local function show(n)
 for k,p in pairs(pages) do p.Visible=k==n end
 for k,b in pairs(tabButtons) do b.BackgroundColor3=k==n and Color3.fromRGB(64,47,92) or Color3.fromRGB(30,29,38);b.TextColor3=k==n and Color3.fromRGB(225,210,255) or Color3.fromRGB(185,182,200) end
end
TradeTab.Activated:Connect(function()show("Trade")end);PetsTab.Activated:Connect(function()show("Pets")end);FiltersTab.Activated:Connect(function()show("Filters")end);StatsTab.Activated:Connect(function()show("Stats")end)

local g=group("TARGET","Choose the player to trade with")
local Target=input(g,"Username"," ")
local Find=button(g,"  Find player",30)
Find.Activated:Connect(function() local q=string.lower(Target.Text:gsub("%s+",""));for _,p in ipairs(Players:GetPlayers()) do if p~=LP and (string.lower(p.Name)==q or string.lower(p.DisplayName)==q or string.find(string.lower(p.Name),q,1,true)) then Target.Text=p.Name;break end end end)
local st=group("TRADE AUTOMATION","Actions used during the verified trade state machine")
local getReq=toggle(st,"Auto Accept Requests",true)
local getAccept=toggle(st,"Auto Accept Trade",true)
local getConfirm=toggle(st,"Auto Confirm Trade",true)
local getSend=toggle(st,"Auto Send Ticket",false)
local getUnfav=toggle(st,"Auto Unfavorite Matching Pets",true)
local getSkip=toggle(st,"Skip Locked/Favorite Pets",true)
local status=Instance.new("TextLabel",g);status.Size=UDim2.new(1,0,0,24);status.BackgroundColor3=Color3.fromRGB(25,30,29);status.Text="●  Ready";status.TextColor3=Color3.fromRGB(95,230,145);status.Font=Enum.Font.GothamMedium;status.TextSize=9;status.TextXAlignment=Enum.TextXAlignment.Left;Instance.new("UICorner",status).CornerRadius=UDim.new(0,6)
local function setStatus(t,bad) status.Text="●  "..t;status.TextColor3=bad and Color3.fromRGB(255,110,125) or Color3.fromRGB(95,230,145) end

local pg=group("PET SELECTION","Matching uses the live PetData fields")
local petInfo=label(pg,"Selected pets: ALL");petInfo.Font=Enum.Font.Gotham
local mg=group("MUTATION / RARITY","Optional filters")
local mutInfo=label(mg,"Mutations: ALL   •   Rarity: ALL");mutInfo.Font=Enum.Font.Gotham

local fg=group("LEVEL / WEIGHT","Only matching pets are offered")
local minL=input(fg,"Min Level","0");local maxL=input(fg,"Max Level","100");local minW=input(fg,"Min Weight","0");local maxW=input(fg,"Max Weight","999999")
local sg=group("LIVE STATUS","Current automation state")
local live=label(sg,"Trade: IDLE\nTarget: NONE\nTicket: CHECKING");live.Font=Enum.Font.Gotham;live.TextWrapped=true;live.Size=UDim2.new(1,0,0,42)
local statg=group("COUNTERS","Session statistics")
local stat=label(statg,"Sent 0   Requests 0   Accept 0   Confirm 0\nAdded 0   Unfav 0   Failed 0");stat.Font=Enum.Font.Gotham;stat.TextWrapped=true;stat.Size=UDim2.new(1,0,0,34)

local function refreshConfig()
 C.AutoRequest=getReq();C.AutoAccept=getAccept();C.AutoConfirm=getConfirm();C.AutoSend=getSend();C.AutoUnfavorite=getUnfav();C.SkipLocked=getSkip();C.MinLevel=math.max(0,tonumber(minL.Text)or 0);C.MaxLevel=math.max(C.MinLevel,tonumber(maxL.Text)or 100);C.MinWeight=math.max(0,tonumber(minW.Text)or 0);C.MaxWeight=math.max(C.MinWeight,tonumber(maxW.Text)or math.huge)
end
for _,x in ipairs({minL,maxL,minW,maxW}) do x.FocusLost:Connect(refreshConfig) end

local function data() local ok,d=pcall(function()return DataService:GetData()end);return ok and d or nil end
local function inventory() local d=data();return d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {} end
local function rarity(t) local e=PetRegistry and PetRegistry.PetList and PetRegistry.PetList[t];return e and (e.Rarity or e.RarityName) end
local function match(uuid,p)
 local d=p and p.PetData;if not d then return false end
 local lv=tonumber(d.Level)or 0;local w=tonumber(d.BaseWeight)or 0;local r=rarity(p.PetType)
 if lv<C.MinLevel or lv>C.MaxLevel or w<C.MinWeight or w>C.MaxWeight then return false end
 if next(C.Pet) and not C.Pet[p.PetType] then return false end
 if next(C.Mutation) and not C.Mutation[d.MutationType] then return false end
 if next(C.Rarity) and not C.Rarity[r] then return false end
 if C.SkipLocked and not C.AutoUnfavorite and d.IsFavorite==true then return false end
 return true
end
local function targetPlayer() local q=string.lower((Target.Text or ""):gsub("^%s+",""):gsub("%s+$",""));if q==""then return nil end;for _,p in ipairs(Players:GetPlayers())do if p~=LP and (string.lower(p.Name)==q or string.lower(p.DisplayName)==q or string.find(string.lower(p.Name),q,1,true))then return p end end end
local function ticket() for _,c in ipairs({LP.Character,LP.Backpack})do if c then for _,o in ipairs(c:GetChildren())do if o:IsA("Tool") and string.find(string.lower(o.Name),"trading ticket",1,true)then return o end end end end end
local function unfav(uuid)
 if not FavoriteRemote then return end
 for _,c in ipairs({LP.Character,LP.Backpack})do if c then for _,o in ipairs(c:GetChildren())do if o:IsA("Tool") and (o:GetAttribute(InvEnums.ITEM_UUID)==uuid or o:GetAttribute("PET_UUID")==uuid) and o:GetAttribute(InvEnums.Favorite)==true then local ok=pcall(function()FavoriteRemote:FireServer(o)end);if ok then S.Unfav+=1 end;return end end end end
end
local function addPets()
 local rep=TradingController.CurrentTradeReplicator;if not rep then return end;local t=rep:GetData();if not t or not t.players or not t.offers then return end;local i=table.find(t.players,LP);if not i then return end
 local items=t.offers[i].items or {};local have={};for _,x in pairs(items)do have[x.id]=true end;local limit=tonumber(TradeData.ItemLimit)or 12
 for uuid,p in pairs(inventory())do if #items>=limit then break end;if not have[uuid] and match(uuid,p)then if C.AutoUnfavorite and p.PetData.IsFavorite then unfav(uuid);task.wait(.12)end;local ok=pcall(function()AddItem:FireServer("Pet",uuid)end);if ok then have[uuid]=true;S.Added+=1;items[#items+1]=uuid else S.Failed+=1 end end end
end
local lastRep=nil;local lastRequest=0
local function send()
 local tp=targetPlayer();if not tp or TradingController.CurrentTradeReplicator or os.clock()-lastRequest<4 then return end;if not ticket()then setStatus("Trading Ticket not found",true);return end;lastRequest=os.clock();local ok=pcall(function()SendRequest:FireServer(tp)end);if ok then S.Sent+=1;setStatus("Request sent to @"..tp.Name)else S.Failed+=1;setStatus("Request failed",true)end
end
RespondRequest.OnClientEvent:Connect(function(sender)if not C.AutoRequest or typeof(sender)~="Instance"or not sender:IsA("Player")then return end;local ok=pcall(function()RespondRequest:FireServer(sender,true)end);if ok then S.Requests+=1;setStatus("Accepted @"..sender.Name.."'s request")else S.Failed+=1 end end)
local function process()
 local rep=TradingController.CurrentTradeReplicator;if not rep then lastRep=nil;return end;local t=rep:GetData();if not t or not t.players or not t.states then return end;if lastRep~=rep then lastRep=rep;setStatus("Trade opened")end;local i=table.find(t.players,LP);if not i then return end;local j=i==1 and 2 or 1;local me=t.states[i];local other=t.states[j];local elapsed=workspace:GetServerTimeNow()-(tonumber(t.lastChange)or 0);local cd=tonumber(TradeData.ButtonCooldown)or 5
 if me=="None"then addPets();if other~="None"and C.AutoAccept and elapsed>=cd then local ok=pcall(function()TradingController:Accept()end);if ok then S.Accepts+=1 end end
 elseif me=="Processing"then setStatus("Trade processing...")
 elseif me=="Accepted"then if C.AutoConfirm and other=="Accepted"and elapsed>=cd then local ok=pcall(function()TradingController:Confirm()end);if ok then S.Confirms+=1 end elseif C.AutoConfirm and other=="Confirmed"and elapsed>=cd then pcall(function()TradingController:Confirm()end)end
 elseif me=="Confirmed"and other=="Confirmed"then setStatus("Trade complete") end
end

local minimized=false
Min.Activated:Connect(function()minimized=not minimized;Sidebar.Visible=not minimized;Content.Visible=not minimized;Main.Size=minimized and UDim2.fromOffset(570,48)or UDim2.fromOffset(570,410);Min.Text=minimized and "+"or"—"end)
Close.Activated:Connect(function()running=false;Gui:Destroy()end)
local drag=false;local ds;local dp
Header.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;dp=Main.Position;i.Changed:Connect(function()if i.UserInputState==Enum.UserInputState.End then drag=false end end)end end)
UIS.InputChanged:Connect(function(i)if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;Main.Position=UDim2.new(dp.X.Scale,dp.X.Offset+d.X,dp.Y.Scale,dp.Y.Offset+d.Y)end end)

show("Trade")
task.spawn(function()while running do refreshConfig();if C.AutoSend then pcall(send)end;pcall(process);local tp=targetPlayer();live.Text=string.format("Trade: %s\nTarget: %s\nTicket: %s",TradingController.CurrentTradeReplicator and "ACTIVE"or"IDLE",tp and("@"..tp.Name)or"NONE",ticket()and"FOUND"or"NONE");stat.Text=string.format("Sent %d   Requests %d   Accept %d   Confirm %d\nAdded %d   Unfav %d   Failed %d",S.Sent,S.Requests,S.Accepts,S.Confirms,S.Added,S.Unfav,S.Failed);task.wait(.2)end end)
print("[Fable] Exo-inspired Trading UI loaded")
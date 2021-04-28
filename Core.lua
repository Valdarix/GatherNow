local WTN = LibStub("AceAddon-3.0"):NewAddon("GatherNow", "AceEvent-3.0")

local DEFAULT_NOTIFY_SOUND = "Sound\\Spells\\Spell_TimePortal_Teleport.ogg"
local EMPTY_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Background"
local WTNframe,fontstring,fontstring2,fontstring3,bR1,teR1,bR2,teR2,bR3,teR3,MapExport

local _,MYFACTION,MYCONTINENT,MYLEVEL,isTracking,MsgTrack,lastPrompt
local prof1,prof2,archaeology,fishing,cooking,firstAid,Herbalism,Mining,Skinning,TrackName
local name,icon,skillLevel,maxSkillLevel,numAbilities,spelloffset,skillLine,skillModifier
local Rname,link,quality,iLevel,reqLevel,class,subclass,maxStack,equipSlot,texture,vendorPrice

local BUTTON1_HORZ_OFFSET,BUTTON1_VERT_OFFSET = -24,	10
local BUTTON2_HORZ_OFFSET,BUTTON2_VERT_OFFSET =   0,	10
local BUTTON3_HORZ_OFFSET,BUTTON3_VERT_OFFSET =  24,	10
local RBUTTON_WIDTH,RBUTTON_HEIGHT,PBUTTON_WIDTH,PBUTTON_HEIGHT	= 20, 20, 24, 24 -- resource/profession button size

local MINING_SKILLID,HERBALISM_SKILLID,SKINNING_SKILLID = 186,182,393
local MINING_NAME,HERBALISM_NAME,SKINNING_NAME,MAX_PROFESSION_SKILL = "","",""
local MINING_TRACKING,MINING_TRACKING_ID = "Interface\\Icons\\Spell_Nature_Earthquake",nil
local HERBALISM_TRACKING,HERBALISM_TRACKING_ID = "Interface\\Icons\\INV_Misc_Flower_02",nil
local localizedContinents,localizedRankData,minimapTracking,localizedMapData = {},{},{},nil

-- ACE3 Standard functions------------------------------------------------------
-- Grabbed need information on init
local defaults = {
	point = "CENTER",
	relativeTo = "UIParent",
	relativePoint = "CENTER",
	x = 0,
	y = 0,
	loc = {},
}
function WTN:OnInitialize()
	GatherNowDB = GatherNowDB or CopyTable(defaults)
	if not GatherNowDB.loc then GatherNowDB.loc = {} end
	localizedMapData = GatherNowDB.loc
	if not GatherNowDB.dbver then
		GatherNowDB.loc = wipe(GatherNowDB.loc or {})
		GatherNowDB.dbver = 2
	end
	-- metatables can give us events for read (__index) or write (__newindex) access to a table
	-- allowing us to dymanically return data for missing keys and optionally save them back to the table.
	setmetatable(localizedMapData, 
	{__index = function(t,k) -- this function only runs when we try to read a key from localizedMapData that doesn't yet exist
		if WorldMapFrame:IsShown() then return end
		local name = GetMapNameByID(k)
		if not name then return end
		local oldID = GetCurrentMapAreaID()
		SetMapByID(k)
		local minL,maxL = GetCurrentMapLevelRange()
		local numCont = GetCurrentMapContinent()
		local pvpType = GetZonePVPInfo()
		SetMapByID(oldID)
		local nameCont = numCont and localizedContinents[numCont]
		if minL and maxL then
			if minL ~= maxL then
				name = ("%s (%d-%d) %s"):format(name,minL,maxL,nameCont or "")
			else
				name = ("%s (%d) %s"):format(name,maxL,nameCont or "")
			end
		end
		local data = {}
		data.desc = name
		data.cont = localizedContinents[numCont] and numCont
		data.faction = (not pvpType or (pvpType == "friendly" or pvpType == "sanctuary")) and MYFACTION or "EnemyFaction"
		rawset(t,k,data)
		return data
	end})
	SlashCmdList["GATHERNOW"] = WTN.Slasher
	SLASH_GATHERNOW1 = "/gathernow"
end

function WTN.Slasher(option)
	local option = option and option:lower() or ""
	if option == "toggle" then
		GatherNow:SetShown(not GatherNow:IsShown())
	elseif option == "resetcache" then
		GatherNowDB.loc = wipe(GatherNowDB.loc or {})
		print("GatherNow: Cached zones wiped.")
	elseif option == "_exportmaps" then -- developer function, don't include in help
		WTN:ExportMapsToCSV()
	else -- unknown command; show help
		print("GatherNow: available commands")
		print("    /gathernow toggle")
		print("        (hides or shows the frame)")
		print("    /gathernow resetcache")
		print("        (clears cached zones; useful in the event of another Cataclysm or Blizzard adjusting zone levels)")
	end
end

function WTN:OnEnable()
	MYFACTION, _ = UnitFactionGroup("player")
	WTN:Create()
	WTN:CacheContinents(GetMapContinents())
	WTN:CacheTrainerRanks()
	WTN:CheckProfs()
	WTN:RegisterEvent("CHAT_MSG_SKILL","SkillUpdate")
	WTN:RegisterEvent("SKILL_LINES_CHANGED","SkillUpdate")
	WTN:RegisterEvent("PLAYER_LOGOUT")
	WTN:RegisterEvent("MINIMAP_UPDATE_TRACKING")
	print("GatherNow loaded successfully. /gathernow for options")
end

function WTN:OnDisable()
	WTN:UnregisterEvent("CHAT_MSG_SKILL")
	WTN:UnregisterEvent("SKILL_LINES_CHANGED")
	WTN:UnregisterEvent("MINIMAP_UPDATE_TRACKING")
	WTN:PLAYER_LOGOUT() -- save our position before we disable the event that saves it
	WTN:UnregisterEvent("PLAYER_LOGOUT")
end
------------------------------------------------------------------------------

-- Registered Events -------------------------------------------------------
-- Handle skill up and update the display
function WTN:SkillUpdate()
	if isTracking then
		WTN:SkillTrackCreate(MsgTrack)
		fontstring2:SetFormattedText("%d/%d",skillLevel,maxSkillLevel)
		WTN:Location(MsgTrack)
		WTN:SkillNowCheck()
	end
end
function WTN:MINIMAP_UPDATE_TRACKING()
	local track_name, track_texture, active, category, nested
	if MINING_TRACKING_ID or HERBALISM_TRACKING_ID then -- already discovered, check directly
		if MINING_TRACKING_ID then
			track_name, track_texture, active, category, nested = GetTrackingInfo(MINING_TRACKING_ID)
			minimapTracking["mining"] = active -- variable name is misleading, this will evaluate to true if tracking or nil/false if not
		end
		if HERBALISM_TRACKING_ID then
			track_name, track_texture, active, category, nested = GetTrackingInfo(HERBALISM_TRACKING_ID)
			minimapTracking["herbalism"] = active
		end
	else -- do a full scan of tracking types
		for i=1,GetNumTrackingTypes() do
			track_name, track_texture, active, category, nested = GetTrackingInfo(i)
			if (track_texture) then
				if track_texture == MINING_TRACKING then
					minimapTracking["mining"] = active
					MINING_TRACKING_ID = i
				end
				if track_texture == HERBALISM_TRACKING then
					minimapTracking["herbalism"] = active
					HERBALISM_TRACKING_ID = i
				end
			end
		end
	end
	if not isTracking then -- only automate if we're not manually tracking something
		if minimapTracking["mining"] and Mining then
			if GatherNowMiningBtn then GatherNowMiningBtn:OnMouseUp("LeftButton") end
		elseif minimapTracking["herbalism"] and Herbalism then
			if GatherNowHerbBtn then GatherNowHerbBtn:OnMouseUp("LeftButton") end
		elseif Skinning then
			if GatherNowSkinningBtn then GatherNowSkinningBtn:OnMouseUp("LeftButton") end
		end
	end
end
-- Save the screens position on logout
function WTN:PLAYER_LOGOUT()
	GatherNowDB.point, GatherNowDB.relativeTo, GatherNowDB.relativePoint, GatherNowDB.x, GatherNowDB.y = WTNframe:GetPoint()
end
------------------------------------------------------------------------------

--GatherNow Functions--------------------------------------------------------
-- Create the container on login
function WTN:Create()
	-- if we've already created the frame (this is a re-enable not a first run) do nothing
	if (WTNframe) and WTNframe:IsObjectType("Frame") then return end
	
	WTNframe = CreateFrame("Frame", "GatherNow", UIParent)
	WTNframe:SetWidth(125)
	WTNframe:SetHeight(80)
	WTNframe:SetFrameStrata("Background")
	if (GatherNowDB.point) then
		WTNframe:SetPoint(GatherNowDB.point, (_G[GatherNowDB.relativeTo] or UIParent), GatherNowDB.relativePoint, GatherNowDB.x, GatherNowDB.y)
	else
		WTNframe:SetPoint("CENTER", 0, 0)
	end

	WTNframe:EnableMouse(true)
	WTNframe:SetMovable(true)
	WTNframe:RegisterForDrag("LeftButton")

	local t = WTNframe:CreateTexture(nil,"BACKGROUND")
	t:SetTexture(EMPTY_TEXTURE)
	t:SetAllPoints(WTNframe)
	WTNframe.texture = t

	WTNframe:SetScript("OnDragStart",
	function(WTNframe, button)
		WTNframe:StartMoving()
	end)

	WTNframe:SetScript("OnDragStop",
	function(WTNframe, button)
		WTNframe:StopMovingOrSizing()
		-- get container position and save it here NYI
	end)

	fontstring = WTNframe:CreateFontString(nil,nil, "GameFontNormalSmall")
	fontstring2 = WTNframe:CreateFontString(nil,nil, "GameFontNormalSmall")
	fontstring3 = WTNframe:CreateFontString(nil,nil, "GameFontNormalSmall")
	fontstring2:SetFont(STANDARD_TEXT_FONT, 12, "")
	fontstring2:SetPoint("CENTER", 0, 30)

	fontstring3:SetFont(STANDARD_TEXT_FONT, 12, "")
	fontstring3:SetPoint("CENTER", 0, 30)
	fontstring3:SetText("Welcome to \n GatherNow.")

	-- Create First Container button with default data and hide it
	bR1 = CreateFrame("Button", "GatherNowContainerbtn1", WTNframe)
	bR1:SetWidth(RBUTTON_WIDTH)
	bR1:SetHeight(RBUTTON_HEIGHT)
	bR1:SetPoint("CENTER", BUTTON1_HORZ_OFFSET, BUTTON1_VERT_OFFSET)
	teR1 = bR1:CreateTexture(nil,"BACKGROUND")
	bR1.texture = teR1
	teR1:SetTexture(EMPTY_TEXTURE)
	teR1:SetAllPoints(bR1)
	bR1.texture = teR1
	bR1.TOOLTIP_TITLE = ""
	bR1.TOOLTIP_TEXT = ""
	bR1:SetScript("OnEnter",
	function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetText(self.TOOLTIP_TITLE)
		GameTooltip:AddLine(self.TOOLTIP_TEXT,1,1,1)
		GameTooltip:Show()
	end)
	bR1:SetScript("OnLeave",GameTooltip_Hide)
	bR1.ClearData = function(bR1) -- create a function that allows us to 'reset' our button and store it on the button itself.
		bR1.TOOLTIP_TITLE = ""
		bR1.TOOLTIP_TEXT = ""
		bR1.texture:SetTexture(EMPTY_TEXTURE) 
	end

	-- Create Second Container button
	bR2 = CreateFrame("Button", "GatherNowContainerbtn2", WTNframe)
	bR2:SetWidth(RBUTTON_WIDTH)
	bR2:SetHeight(RBUTTON_HEIGHT)
	bR2:SetPoint("CENTER", BUTTON2_HORZ_OFFSET, BUTTON2_VERT_OFFSET)
	teR2 = bR2:CreateTexture(nil,"BACKGROUND")
	bR2.texture = teR2
	teR2:SetTexture(EMPTY_TEXTURE)
	teR2:SetAllPoints(bR2)
	bR2.texture = teR2
	bR2.TOOLTIP_TITLE = ""
	bR2.TOOLTIP_TEXT = ""
	bR2:SetScript("OnEnter",
	function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetText(self.TOOLTIP_TITLE)
		GameTooltip:AddLine(self.TOOLTIP_TEXT,1,1,1)
		GameTooltip:Show()
	end)
	bR2:SetScript("OnLeave",GameTooltip_Hide)
	bR2.ClearData = function(bR2) 
		bR2.TOOLTIP_TITLE = ""
		bR2.TOOLTIP_TEXT = ""
		bR2.texture:SetTexture(EMPTY_TEXTURE) 
	end
	
	-- Create Third and final container
	bR3 = CreateFrame("Button", "GatherNowContainerbtn3", WTNframe)
	bR3:SetWidth(RBUTTON_WIDTH)
	bR3:SetHeight(RBUTTON_HEIGHT)
	bR3:SetPoint("CENTER", BUTTON3_HORZ_OFFSET, BUTTON3_VERT_OFFSET)
	teR3 = bR3:CreateTexture(nil,"BACKGROUND")
	bR3.texture = teR3
	teR3:SetTexture(EMPTY_TEXTURE)
	teR3:SetAllPoints(bR3)
	bR3.texture = teR3
	bR3.TOOLTIP_TITLE = ""
	bR3.TOOLTIP_TEXT = ""
	bR3:SetScript("OnEnter",
	function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetText(self.TOOLTIP_TITLE)
		GameTooltip:AddLine(self.TOOLTIP_TEXT,1,1,1)
		GameTooltip:Show()
	end)
	bR3:SetScript("OnLeave",GameTooltip_Hide)
	bR3.ClearData = function(bR3) 
		bR3.TOOLTIP_TITLE = ""
		bR3.TOOLTIP_TEXT = ""
		bR3.texture:SetTexture(EMPTY_TEXTURE) 
	end

end

function WTN:CreateHerbButton()
	WTN:SkillTrackCreate(Herbalism)
	local b = CreateFrame("Button", "GatherNowHerbBtn", WTNframe)
	b:SetWidth(PBUTTON_WIDTH)
	b:SetHeight(PBUTTON_HEIGHT)
	b:SetPoint("CENTER", -75, 25)
	local t = b:CreateTexture(nil,"BACKGROUND")
	t:SetTexture(icon)
	t:SetAllPoints(b)
	b.texture = t
	b:RegisterForClicks("AnyUp", "AnyDown")
	b.OnMouseUp = function(self,button)
		fontstring3:SetText(HERBALISM_NAME)
		isTracking = true
		TrackName = HERBALISM_NAME
		MsgTrack = Herbalism
		WTN:SkillTrackCreate(Herbalism)
		fontstring2:SetFormattedText("%d/%d",skillLevel,maxSkillLevel)
		WTN:Location(MsgTrack)
		if HERBALISM_TRACKING_ID then
			local _,_,active = GetTrackingInfo(HERBALISM_TRACKING_ID)
			if not active then
				SetTracking(HERBALISM_TRACKING_ID,true)
			end
		end
	end
	b:SetScript("OnMouseUp",b.OnMouseUp)
end

function WTN:CreateMiningButton()
	WTN:SkillTrackCreate(Mining)
	local b = CreateFrame("Button", "GatherNowMiningBtn", WTNframe)
	b:SetWidth(PBUTTON_WIDTH)
	b:SetHeight(PBUTTON_HEIGHT)
	b:SetPoint("CENTER", -75, 0)
	local t = b:CreateTexture(nil,"BACKGROUND")
	t:SetTexture(icon)
	t:SetAllPoints(b)
	b.texture = t
	b:RegisterForClicks("AnyUp", "AnyDown")
	b.OnMouseUp = function(self,button)
		fontstring3:SetText(MINING_NAME)
		isTracking =  true
		TrackName = MINING_NAME
		MsgTrack = Mining
		WTN:SkillTrackCreate(Mining)
		fontstring2:SetFormattedText("%d/%d",skillLevel,maxSkillLevel)
		WTN:Location(MsgTrack)
		if MINING_TRACKING_ID then
			local _,_,active = GetTrackingInfo(MINING_TRACKING_ID)
			if not active then
				SetTracking(MINING_TRACKING_ID,true)
			end
		end
	end
	b:SetScript("OnMouseUp",b.OnMouseUp)
end

function WTN:CreateSkinningButton()
	WTN:SkillTrackCreate(Skinning)
	local b = CreateFrame("Button", "GatherNowSkinningBtn", WTNframe)
	b:SetWidth(PBUTTON_WIDTH)
	b:SetHeight(PBUTTON_HEIGHT)
	b:SetPoint("CENTER", -75, -25)
	local t = b:CreateTexture(nil,"BACKGROUND")
	t:SetTexture(icon)
	t:SetAllPoints(b)
	b.texture = t
	b:RegisterForClicks("AnyUp", "AnyDown")
	b.OnMouseUp = function(self,button)
		fontstring3:SetText(SKINNING_NAME)
		isTracking =  true
		TrackName = SKINNING_NAME
		MsgTrack = Skinning
		WTN:SkillTrackCreate(Skinning)
		fontstring2:SetFormattedText("%d/%d",skillLevel,maxSkillLevel)
		WTN:Location(MsgTrack)
	end
	b:SetScript("OnMouseUp",b.OnMouseUp)
end

-- the ellipsis ... is a special variable name used to hold an unknown number of arguments
-- select("#",...) gives us the number of arguments passed and allows us to traverse the list
function WTN:CacheContinents(...) 
	for i=1,select("#",...) do
		localizedContinents[i] = select(i,...)
	end
end


function WTN:SkinLevelToNPCLevel(skill)
	--[[orange at just the skill, yellow at +25, green at +50, grey at +75
		Skinning skill 1-99: (skill level) /10 + 10 = highest level skinnable mob. 
		Skinning skill 100-364: (skill level) /5 = highest level skinnable mob. 
		Skinning skill 365-439 Mob 74-80 = 10-points needed per level. 73:365,74:375,75:385,76:395,77:405,78:415,79:425,80:435
		Skinning skill 440-469 Mob 81-83 = 5-points needed per level. 81:440,82:445,83:450
		Skinning skill 470-590 Mob 83+ = 20-points needed per level. 84:470,85:490,86:510,87:530,88:550,89:570,90:590 (Cata/MoP breakpoints not verified)
	]]
	local maxLevel,medLevel,minLevel,skillToLevel
	do
		skillToLevel = function(num)
			if num >= 470 then
				return floor((num-470)/20+84)
			elseif num >= 440 then
				return floor(min((num-440)/5+81,83))
			elseif num >= 365 then
				return floor((num-365)/10+73)
			elseif num >= 100 then
				return floor(num/5)
			elseif num > 10 then
				return floor(num/10+10)
			elseif num >= 1 then
				return 10
			end
		end
	end
	maxLevel = skillToLevel(skill)
	medLevel = skill > 50 and skillToLevel(skill-50)+1 or 10
	minLevel = skill > 75 and skillToLevel(skill-75)+1 or 10
	return maxLevel,medLevel,minLevel
end

function WTN:CacheTrainerRanks()
	local numRanks = #PROFESSION_RANKS
	MAX_PROFESSION_SKILL = PROFESSION_RANKS[numRanks][1]
	-- store all the skills where a higher rank can be trained ordered from high to low.
	-- so we can later loop and compare with our own skill to the steps.
	-- as soon as we find a threshold we have passed (going down) we know we can train the skill at the previous iteration (ie the immediately higher)
	for rank=numRanks,1,-1 do
		local minTrainerSkill,maxTrainerSkill
		if rank > 1 then
			maxTrainerSkill = PROFESSION_RANKS[rank-1][1]
			minTrainerSkill = maxTrainerSkill - 25
			tinsert(localizedRankData,{minTrainerSkill,maxTrainerSkill,PROFESSION_RANKS[rank][2]}) -- eg. 500,525,"Zen Master"
		end
	end
end

function WTN:CheckProfs()
	prof1, prof2, archaeology, fishing, cooking, firstAid = GetProfessions();
	-- Get Trade skill One
	MsgTrack = "" -- Clear data to prevent wrong skill info from displaying
	if (prof1) then
		WTN:SkillTrackCreate(prof1)
		if skillLine == HERBALISM_SKILLID then
			Herbalism = prof1
			HERBALISM_NAME = name
			WTN:CreateHerbButton()
		end
		if skillLine == MINING_SKILLID then
			Mining = prof1
			MINING_NAME = name
			WTN:CreateMiningButton()
		end
		if skillLine == SKINNING_SKILLID then
			Skinning = prof1
			SKINNING_NAME = name
			WTN:CreateSkinningButton()
		end
	end
	if (prof2) then
		WTN:SkillTrackCreate(prof2)
		if skillLine == HERBALISM_SKILLID then
			Herbalism = prof2
			HERBALISM_NAME = name
			WTN:CreateHerbButton()
		end
		if skillLine == MINING_SKILLID then
			Mining = prof2
			MINING_NAME = name
			WTN:CreateMiningButton()
		end
		if skillLine == SKINNING_SKILLID then
			Skinning = prof2
			SKINNING_NAME = name
			WTN:CreateSkinningButton()
		end
	end
	if not (Herbalism or Mining or Skinning) then
		GatherNow:Hide()
	else
		WTN:MINIMAP_UPDATE_TRACKING()
	end
end

-- Get the professions information for displaying the skill level
function WTN:SkillTrackCreate(prof)
	if not tonumber(prof) then return end
	name, icon, skillLevel, maxSkillLevel, numAbilities, spelloffset, skillLine, skillModifier = GetProfessionInfo(prof)
end

-- see WTN:CacheContinents() for an explanation of the ellipsis variable ...
-- here we use it to pass an arbitrary number of mapIDs for which we want to
-- process the zones and spit out recommendations for the player.
function WTN:GetRecommendedAreas(...)
	-- zone = {desc="zone (l - l) continent",cont=continentID,faction="Alliance"|"Horde"}
	local numIDs = select("#",...) -- the number of zones we passed
	local output = ""
	for i=1,numIDs do
		-- select(i,...) will return the mapID at position i in the list of mapIDs we gave this function, eg. 30 if we passed the mapID for Elwynn Forest
		-- localizedMapData has our metatable magic so if the information for Elwynn is not already stored in our table
		-- the __index function of the metatable will try to get them from wow API, return them and store them in our SV for future lookups.
		local zone = localizedMapData[select(i,...)] 
		if (zone) then
			local description = zone.desc
			local continent = zone.cont
			local faction = zone.faction
			if (description) then
				if (not faction) or (not MYFACTION) or (MYFACTION == "Neutral") or (faction == MYFACTION) then
					if (not continent) or (not MYCONTINENT) or (continent == MYCONTINENT) then
						output = ("%s\n%s"):format(description,output) -- put same continent zones as the one we're on at the top
					else
						output = ("%s%s\n"):format(output,description) -- other continent zones at the bottom of the tooltip
					end
				end
			end
		end
	end
	if output ~= "" then
		output = output:gsub("\n$","") -- strip trailing newline if found
	end
	return output
end

-- Get the details of the resource that is being gathered
function WTN:GetResource(itemID,button)
	Rname, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemID)
	if not (Rname) then Rname = ("|cffff0000<%s>|r\nClick the Profession Icon to refresh."):format(RETRIEVING_ITEM_INFO); texture = GetItemIcon(itemID) end
	button.TOOLTIP_TITLE = Rname
	button.texture:SetTexture(texture)
end

-- check and Notify user to skill up. Used for all three professions
function WTN:SkillNowCheck()
	local now = GetTime()
	if not lastPrompt or (now - lastPrompt) > 2 then -- throttle prompts
		lastPrompt = now
	else
		return
	end
	if skillLevel and maxSkillLevel and name then
		if skillLevel == maxSkillLevel then
			if MAX_PROFESSION_SKILL > maxSkillLevel then
				PlaySoundFile(DEFAULT_NOTIFY_SOUND, "Master")
				print(("You will not gain more skill in %s. Visit a trainer!"):format(name))
			end
		end
		-- this is where we traverse the stored trainer ranks from high to low
		-- until we find a range that contains our current skill
		-- then we prompt the user to train the one right above.
		-- data is a table with entries in the form of {1=minTrainSkill,2=maxTrainSkill,3=higherRankName}
		-- so data[1] can be 500, data[2] 525, data[3] "Zen Master"
		if skillLevel < maxSkillLevel then 
			for i,data in ipairs(localizedRankData) do
				if skillLevel >= data[1] and maxSkillLevel <= data[2] then
					PlaySoundFile(DEFAULT_NOTIFY_SOUND, "Master")
					print(("You can learn a new %s rank: %q!"):format(name,data[3]))
					break
				end
			end
		end
	end
end

-- Tell user closest and best place to mine
function WTN:Location(profession)
	if not isTracking then return end
	MYCONTINENT = GetCurrentMapContinent()
	MYLEVEL = UnitLevel("player")
	fontstring3:SetFont(STANDARD_TEXT_FONT, 12, "")
	fontstring3:SetPoint("CENTER", 0, -13)

	-- 1. Clearing/reseting one of the 3 resource buttons is as simple as doing
	-- bRx:ClearData()
	-- 2. Setting the icon, tooltip title and text is also as simple as doing
	-- WTN:GetResource(itemID,bRx)
	-- bRx:TOOLTIP_TEXT = WTN:GetRecommendedAreas(mapID1,mapID2,etc)
	if profession == Mining then
		WTN:SetMiningInfo()
	elseif profession == Herbalism then
		WTN:SetHerbalismInfo()
	elseif profession == Skinning then
		WTN:SetSkinningInfo()
	end
	
end

function WTN:SetMiningInfo()
	if skillLevel <= 49 then
		bR1:ClearData()
		bR1:Show()
		-- Copper
		WTN:GetResource(2770,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(30,27,41,464,684,20,462,4,9,544)
		-- "Elwynn Forest 1-10  \n Dun Morogh 1-10"
		-- "Teldrassil 1-10 \n Azuremyst Isle 1-10 \n Gilneas 5-12"
		-- "Tristfal Glades 1-10 \n Eversong Woods 1-10"
		-- "Durotar 1-10 \n Mulgore 1-10 \n The Lost Isles 5-12"

		bR3:ClearData()
	end
	-- Beyond startZone
	if skillLevel > 49 and skillLevel <= 99 then
		bR1:ClearData()
		bR1:Show()
		-- Copper
		WTN:GetResource(2771,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(24,43) -- "Hillsbrad Foothills 20-25"-- "Ashenvale 20-25"

		bR3:ClearData()
	end
	if skillLevel > 99 and skillLevel <= 149 then
		bR1:ClearData()
		bR1:Show()

		WTN:GetResource(2772,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(22,121) -- "Western Plaguelands 35-40"-- "Feralas 35-40"

		bR3:ClearData()
	end
	if skillLevel > 149 and skillLevel <= 199 then
		bR1:ClearData()
		bR1:Show()
		-- Copper
		WTN:GetResource(3858,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(17,182) -- "Badlands 45-48"-- "Felwood 45-50"

		bR3:ClearData()
	end
	if skillLevel > 199 and skillLevel <= 274 then
		bR1:ClearData()
		bR1:Show()
		-- Copper
		WTN:GetResource(10620,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(19,281) -- "Blasted Lands 54-60"-- "Winterspring 50-55"

		bR3:ClearData()
	end
	if skillLevel > 274 and skillLevel <= 324 then
		bR1:ClearData()
		bR1:Show()
		-- Copper
		WTN:GetResource(23424,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(465) -- "Hellfire Peninsula 58-63"

		bR3:ClearData()
	end
	if skillLevel > 324 and skillLevel <= 349 then
		bR1:ClearData()
		bR1:Show()
		-- Copper
		WTN:GetResource(23425,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(477) -- "Nagrand 64-67"

		bR3:ClearData()
	end
	if skillLevel > 349 and skillLevel <= 399 then
		bR1:ClearData()
		bR1:Show()

		WTN:GetResource(36909,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(491,486) -- "Howling Fjord 68-72 \n Borean Tundra 68-72 "

		bR3:ClearData()
	end
	if skillLevel > 399 and skillLevel <= 424 then
		bR1:ClearData()
		bR1:Show()
		-- Copper
		WTN:GetResource(36912,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(493) -- "Sholzar Basin 76-78 "

		bR3:ClearData()
	end
	if skillLevel > 424 and skillLevel <= 474 then
		bR1:ClearData()
		bR1:Show()
		-- Copper
		WTN:GetResource(53038,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(606) -- "Mount Hyjal 80-82"

		bR3:ClearData()
	end
	if skillLevel > 474 and skillLevel <= 499 then
		WTN:GetResource(52185,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(700,640) -- "Twilight Highlands 84-85 \n Deepholm 82-83"
		bR1:Show()

		WTN:GetResource(53038,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(640,606) -- "Deepholm 82-83 \n Mount Hyjal 80-82"

		bR3:ClearData()
	end
	if skillLevel > 499 and skillLevel <= 549 then
		WTN:GetResource(72092,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(806,857,807,809,858,811) -- "Jade Forest \nKrasarang Wilds \nValley of the Four Winds \nKun-Lai Summit \n Dread Waste \nVale of Eternal Blossom "
		bR1:Show()

		
		bR2:ClearData()

		bR3:ClearData()
	end
	if skillLevel > 549 and skillLevel <= 599 then
		WTN:GetResource(72092,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(806,857,807,809,858,811) -- "Jade Forest \nKrasarang Wilds \nValley of the Four Winds \nKun-Lai Summit \n Dread Waste \nVale of Eternal Blossom "
		bR1:Show()

		WTN:GetResource(72093,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(858,810,887) -- "Dread Wastes \nTownlong Steppes\nSiege of Niuzao Temple"

		bR3:ClearData()
	end
	if skillLevel > 599 then
		WTN:GetResource(72092,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(806,857,807,809,858,811) -- "Jade Forest \nKrasarang Wilds \nValley of the Four Winds \nKun-Lai Summit \n Dread Waste \nVale of Eternal Blossom "
		bR1:Show()

		WTN:GetResource(72094,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(858,810,811,807,806) 
		
		WTN:GetResource(72103,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(858,810,811,807,806)
	end
end
function WTN:SetHerbalismInfo()
	if skillLevel <= 14 then	-- Starter Zone farming
		-- Peacebloom
		WTN:GetResource(2447,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(30,27,41,464,684,20,462,4,9,544) 
		-- "Elwynn Forest 1-10  \n Dun Morogh 1-10"
		-- "Teldrassil 1-10 \n Azuremyst Isle 1-10 \n Gilneas 5-12"
		-- "Tristfal Glades 1-10 \n Eversong Woods 1-10"
		-- "Durotar 1-10 \n Mulgore 1-10 \n The Lost Isles 5-12"
		bR1:Show()
		-- Silverleaf
		WTN:GetResource(765,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(30,27,41,464,684,20,462,4,9,544)

		bR3:ClearData()
	end
	if skillLevel > 14 and skillLevel <= 49 then -- Start Zone w/ Earthroot available
		-- peacebloom
		WTN:GetResource(2447,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(30,27,41,464,684,20,462,4,9,544)
		bR1:Show()
		-- Silverleaf
		WTN:GetResource(765,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(30,27,41,464,684,20,462,4,9,544)
		-- Earthroot
		WTN:GetResource(2449,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(30,27,41,464,684,20,462,4,9,544)
	end
	if skillLevel > 49 and skillLevel <= 69 then
		-- Earthroot
		WTN:GetResource(2449,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(39,36,35,30,27,42,476,41,464,684,21,463,20,462,11,181,4,9,544) 
		-- "Westfall 10-15 \n Redridge Mountains 15-20 \n Loch Modan 10-20 \n Elwynn Forest 1-10  \n Dun Morogh 1-10"
		-- "Darkshore 10-20 \n Bloodmyst Isle 11-20 \n Teldrassil 1-10 \n Azuremyst Isle 1-10 \n Gilneas 5-12"
		-- "Silverpine Foest 10-20\n Ghostlands 10-20 \n Trisfal Glades 1-10 \n Eversong Woods 1-10 "
		-- "Norhtern Barrens 10-20 \n Azshara 10-20 \n Durotar 1-10 \n Mulgore 1-10 \n The Lost Isles 5-12"
		bR1:Show()
		-- Mageroyal
		WTN:GetResource(785,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(39,36,35,42,476,21,463,11,181) 
		-- "Westfall 10-15 \n Redridge Mountains 15-20 \n Loch Modan 10-20"
		-- "Darkshore 10-20 \n Bloodmyst Isle 11-20 "
		-- "Silverpine Foest 10-20\n Ghostlands 10-20"
		-- "Norhtern Barrens 10-20 \n Azshara 10-20"

		-- Not Needed Empty Data
		bR3:ClearData()
	end
	if skillLevel > 69 and skillLevel <= 84 then
		-- Earthroot
		WTN:GetResource(2449,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(39,36,35,42,476,21,463,11,181)
		bR1:Show()
		-- Mageroyal
		WTN:GetResource(785,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(39,36,35,42,476,21,463,11,181)
		-- Briarthorn
		WTN:GetResource(2450,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(39,36,35,42,476,21,463) 
		-- "Westfall 10-15 \n Redridge Mountains 15-20 \n Loch Modan 10-20"
		-- "Darkshore 10-20 \n Bloodmyst Isle 11-20 "
		-- "Silverpine Foest 10-20\n Ghostlands 10-20"
	end
	if skillLevel > 84 and skillLevel <= 149 then
		-- Mageroyal
		WTN:GetResource(785,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(24,40,34,39,36,35,42,476,21,463,11,181) 
		-- "Hillsbrad Foothills 20-35 \n Wetlands 20-35 \n Duskwood 20-25 \n Westfall 10- 15 \n Redridge Mountains 15 - 20 \n Loch Modan 10-20"
		-- "Hillsbrad Foothills 20-35 \n Darkshore 10-20 \n Bloodmyst Isle 11-20"
		-- "Hillsbrad Foothills 20-35 \n Wetlands 20-35 \n Duskwood 20-25 \n Silverpine Foest 10-20\n Ghostlands 10-20"
		-- "Hillsbrad Foothills 20-35 \n Norhtern Barrens 10-20 \n Azshara 10-20"
		bR1:Show()
		-- Briarthorn
		WTN:GetResource(2450,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(24,39,36,35,42,476,21,463,11,181) 
		-- "Hillsbrad Foothills 20-35 \n Westfall 10-15 \n Redridge Mountains 15-20 \n Loch Modan 10-20"
		-- "Hillsbrad Foothills 20-35 \n Darkshore 10-20 \n Bloodmyst Isle 11-20 "
		-- "Hillsbrad Foothills 20-35 \n Silverpine Foest 10-20\n Ghostlands 10-20"
		-- "Hillsbrad Foothills 20-35 \n Norhtern Barrens 10-20 \n Azshara 10-20"
		-- Bruiseweed
		WTN:GetResource(2453,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(24,37,40,43,81) 
		-- "Hillsbrad Foothills 20-35 \n Northern Stranglethorn 25-30 \n Wetlands 20-25"
		-- "Hillsbrad Foothills 20-35 \n Ashenvale 20-25 \n Stonetalon Mountains 25-30"
	end
	if skillLevel > 149 and skillLevel <= 159 then
		-- Liferoot
		WTN:GetResource(3357,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(22) -- "Western Plaguelands 35-40"
		bR1:Show()
		-- None
		bR2:ClearData()
		-- None
		bR3:ClearData()
	end
	if skillLevel > 159 and skillLevel <= 184 then
		-- Liferoot
		WTN:GetResource(3357,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(22) -- "Western Plaguelands 35-40"
		bR1:Show()
		-- Fadeleaf
		WTN:GetResource(3818,bR2)
		bR2.TOOLTIP_TEXT = EASTERN_KINGDOM_LOCATION1
		-- None
		bR3:ClearData()
	end
	if skillLevel > 184 and skillLevel <= 229 then
		-- Liferoot
		WTN:GetResource(3357,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(22) -- "Western Plaguelands 35-40"
		bR1:Show()
		-- Fadeleaf
		WTN:GetResource(3818,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(22) -- "Western Plaguelands 35-40"
		-- Khadgar's Whisker
		WTN:GetResource(3358,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(22) -- "Western Plaguelands 35-40"
	end
	if skillLevel > 229 and skillLevel <= 259 then
		-- Khadgar's Whisker
		WTN:GetResource(3358,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(23) -- "Eastern Plaguelands 40-45"
		bR1:Show()
		-- Sungrass
		WTN:GetResource(8838,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(23) -- "Eastern Plaguelands 40-45"
		-- None
		bR3:ClearData()
	end
	if skillLevel > 259 and skillLevel <= 269 then
		-- Golden Sansam
		WTN:GetResource(13464,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(19) -- "Blasted Lands 54-60"
		bR1:Show()
		-- None
		bR2:ClearData()
		-- None
		bR3:ClearData()
	end
	if skillLevel > 269 and skillLevel <= 279 then
		-- Golden Sansam
		WTN:GetResource(13464,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(19) -- "Blasted Lands 54-60"
		bR1:Show()
		-- Dreamfoil
		WTN:GetResource(13463,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(19) -- "Blasted Lands 54-60"
		-- None
		bR3:ClearData()
	end
	if skillLevel > 279 and skillLevel <= 299 then
		-- Golden Sansam
		WTN:GetResource(13464,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(19) -- "Blasted Lands 54-60"
		bR1:Show()
		-- Dreamfoil
		WTN:GetResource(13463,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(19) -- "Blasted Lands 54-60"
		-- Mountain Silversage
		WTN:GetResource(13465,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(19) -- "Blasted Lands 54-60"
	end
	if skillLevel > 299 and skillLevel <= 314 then
		-- Dreamfoil
		WTN:GetResource(13463,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(465) -- "Hellfire Peninsula 58-63"
		bR1:Show()
		-- Felweed
		WTN:GetResource(22785,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(465) -- "Hellfire Peninsula 58-63"
		-- Mountain Silversage
		bR3:ClearData()
	end
	if skillLevel > 314 and skillLevel <= 359 then
		-- Felweed
		WTN:GetResource(22785,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(465) -- "Hellfire Peninsula 58-63"
		bR1:Show()
		-- Dreaming Glory
		WTN:GetResource(22786,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(465) -- "Hellfire Peninsula 58-63"
		-- Mountain Silversage
		bR3:ClearData()
	end
	if skillLevel > 359 and skillLevel <= 374 then
		-- Goldclover
		WTN:GetResource(36901,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(491,486) -- "Howling Fjord 68-72 \n Borean Tundra 68-72"
		bR1:Show()
		-- None
		bR2:ClearData()
		-- None
		bR3:ClearData()
	end
	if skillLevel > 374 and skillLevel <= 399  then
		-- Goldclover
		WTN:GetResource(36901,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(491,486) -- "Howling Fjord 68-72 \n Borean Tundra 68-72"
		bR1:Show()
		-- Tigerlilly
		WTN:GetResource(36904,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(491,486) -- "Howling Fjord 68-72 \n Borean Tundra 68-72"
		-- None
		bR3:ClearData()
	end
	if skillLevel > 399 and skillLevel <= 449  then
		-- Goldclover
		WTN:GetResource(36901,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(493) -- "Sholzar Basin 76-78"
		bR1:Show()
		-- Tigerlilly
		WTN:GetResource(36904,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(493) -- "Sholzar Basin 76-78"
		-- Adder's Tongue
		WTN:GetResource(36903,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(493) -- "Sholzar Basin 76-78"
	end
	if skillLevel > 449 and skillLevel <= 474  then
		-- Cinderbloom
		WTN:GetResource(52983,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(606) -- "Mount Hyjal 80-82"
		bR1:Show()
		-- Azshara's Veil
		WTN:GetResource(52985,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(606,613) -- EASTERN_KINGDOM_LOCATION1.." \n Vashj'ir 80-82"
		-- Stormvine
		WTN:GetResource(52984,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(606,613) -- EASTERN_KINGDOM_LOCATION1.." \n Vashj'ir 80-82"
	end
	if skillLevel > 474 and skillLevel <= 499  then
		-- Cinderbloom
		WTN:GetResource(52983,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(640) -- "Deepholm 82-83"
		bR1:Show()
		-- Heartblossom
		WTN:GetResource(52986,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(640) -- "Deepholm 82-83"

		-- Green Tea Leaf
		WTN:GetResource(72234,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(806,807) -- "The Jade Forest\nValley of the Four Winds"
	end
	if skillLevel > 499 and skillLevel <= 539 then
		-- Green Tea Leaf
		WTN:GetResource(72234,bR1)
		bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(806,807) -- "The Jade Forest\nValley of the Four Winds"
		bR1:Show()
		
		-- Rain Poppy
		WTN:GetResource(72237,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(806,811) -- "The Jade Forest\nVale of Eternal Blossoms"

		-- none
		bR3:ClearData()
	end
	if skillLevel > 539 and skillLevel <= 579 then
		-- none
		bR1:ClearData()
		bR1:Show()
		
		-- Rain Poppy
		WTN:GetResource(72237,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(806,811) -- "The Jade Forest\nVale of Eternal Blossoms"
		
		-- Silkweed
		WTN:GetResource(72235,bR3)
		bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(807,857) -- "Valley of the Four winds\nKrasarang Wilds"
	end
	if skillLevel > 579 and skillLevel <=600 then
		-- none
		bR1:ClearData()
		bR1:Show()
		
		-- Snow Lily
		WTN:GetResource(79010,bR2)
		bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(809) -- "Kun-Lai Summit"
		
		-- none
		bR3:ClearData()		
	end
end
function WTN:SetSkinningInfo()
	-- minLevel = level of NPC that we can gain skillups from at green skinning difficulty
	-- medLevel = level of NPC that we can gain skillups from at yellow skinning difficulty
	-- maxLevel = maximum level of NPC that we can currently skin.
	-- these are used to make alternate recommendations according to player level
	local maxLevel,medLevel,minLevel = WTN:SkinLevelToNPCLevel(skillLevel)
	local level,skillColor -- skillColor not used anywhere yet but might prove useful
	if (MYLEVEL+2 >= maxLevel) then
		level = maxLevel
		skillColor = QuestDifficultyColors["verydifficult"] -- orange
	elseif (MYLEVEL+2 > medLevel) then
		level = medLevel
		skillColor = QuestDifficultyColors["difficult"] -- yellow
	elseif (MYLEVEL+2 > minLevel) then
		level = minLevel
		skillColor = QuestDifficultyColors["standard"] -- green
	else
		skillColor = QuestDifficultyColors["impossible"] -- red
	end
	if (level) then
		if level <= 15 then
			-- ruined leather scraps
			WTN:GetResource(2934,bR1)
			bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(30,4,181,27,684,462,9,20,41,464) 
			-- Elwynn Forest:30 Durotar:4 Aszhara:181 Dun Morogh:27 Ruins of Gilneas:684 Eversong Woods:462 Mulgore:9 Tirisfal Glades:20 Teldrassil:41 Azuremist Isle:464
			bR1:Show()
			
			-- light leather
			WTN:GetResource(2318,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(42,34,39,11,36,35) 
			-- Darkshore:42 Duskwood:34 Westfall:39 Northern Barrens:11 Redridge Mountains:36 Loch Modan:35
			
			-- none
			bR3:ClearData()
		end
		if level > 15 and level <= 25 then
			-- light leather
			WTN:GetResource(2318,bR1)
			bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(42,34,39,11,36,35) 
			-- Darkshore:42 Duskwood:34 Westfall:39 Northern Barrens:11 Redridge Mountains:36 Loch Modan:35
			bR1:Show()

			-- medium Leather
			WTN:GetResource(2319,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(37,40,16,607,81,43,34) 
			-- Northern Stranglethorn:37 Wetlands:40 Arathi Highlands:16 Southern Barrens:607 Stonetalon Mountains:81 Ashenvale:43 Duskwood:34

			-- none
			bR3:ClearData()
		end
		if level > 25 and level <= 35 then
			-- medium leather
			WTN:GetResource(2319,bR1)
			bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(37,40,16,607,81,43,34) 
			-- Northern Stranglethorn:37 Wetlands:40 Arathi Highlands:16 Southern Barrens:607 Stonetalon Mountains:81 Ashenvale:43 Duskwood:34
			bR1:Show()

			-- heavy leather
			WTN:GetResource(4234,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(121,22,673,141,607) 
			-- Feralas:121 Western Plaguelands:22 The cape of stranglethorn:673 Dustwallow Marsh:141 Southern Barrens:607

			-- none
			bR3:ClearData()
		end
		if level > 35 and level <= 45 then
			-- heavy leather
			WTN:GetResource(4234,bR1)
			bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(121,22,673,141,607) 
			-- Feralas:121 Western Plaguelands:22 The cape of stranglethorn:673 Dustwallow Marsh:141 Southern Barrens:607
			bR1:Show()

			-- thick leather
			WTN:GetResource(4304,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(23,161,17,182) 
			-- Eastern Plaguelands:23 Tanaris:161 Badlands:17 Felwood:182 

			-- none
			bR3:ClearData()
		end
		if level > 45 and level <= 55 then
			-- thick leather
			WTN:GetResource(4304,bR1)
			bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(23,161,17,182) 
			-- Eastern Plaguelands:23 Tanaris:161 Badlands:17 Felwood:182
			bR1:Show()

			-- rugged leather
			WTN:GetResource(8170,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(281,201,38,161,19) 
			-- Winterspring:281 Un'goro Crater:201 Swamp of Sorrows:38 Silithus:161 Blasted Lands:19

			-- none
			bR3:ClearData()
		end
		if level > 55 and level <= 58 then
			-- rugged leather
			WTN:GetResource(8170,bR1)
			bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(281,201,38,161,19) 
			-- Winterspring:281 Un'goro Crater:201 Swamp of Sorrows:38 Silithus:161 Blasted Lands:19 
			bR1:Show()

			-- none
			bR2:ClearData()

			-- none
			bR2:ClearData()
		end
		if level > 58 and level <= 65 then
			-- none
			bR1:ClearData()
			bR1:Show()

			-- knothide leather scraps
			WTN:GetResource(25649,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(465,467,478,477) 
			-- Hellfire Peninsula:465 Zangarmarsh:467 Terokkar Forest:478 Nagrand:477

			-- none
			bR3:ClearData()
		end
		if level > 65 and level <= 71 then
			-- none
			bR1:ClearData()
			bR1:Show()

			-- knothide leather
			WTN:GetResource(21887,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(477,475,473,479) 
			-- Nagrand:477 Blade's Edge Mountains:475 Shadowmoon Valley:473 Netherstorm:479

			-- borean leather scraps
			WTN:GetResource(33567,bR3)
			bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(486,491) 
			-- Borean Tundra:486 Howling Fjord:491
		end
		if level > 71 and level <= 75 then
			-- none
			bR1:ClearData()
			bR1:Show()

			-- borean leather scraps
			WTN:GetResource(33567,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(486,491,488) 
			-- Borean Tundra:486 Howling Fjord:491 Dragonblight:488

			-- none
			bR3:ClearData()
		end
		if level > 75 and level <= 80 then
			-- none
			bR1:ClearData()
			bR1:Show()

			-- borean leather
			WTN:GetResource(33568,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(488,493,496) 
			-- Dragonblight:488 Sholazar Basin:493 Zul'Drak:496

			-- savage leather scraps
			WTN:GetResource(52977,bR3)
			bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(610,606,615,614) 
			-- Kelpthar Forest:610 Mount Hyjal:606 Shimmering Expanse:615 Abyssal Depths:614
		end
		if level > 80 and level <= 82 then
			-- borean leather
			WTN:GetResource(33568,bR1)
			bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(488,493,496) 
			-- Dragonblight:488 Sholazar Basin:493 Zul'Drak:496
			bR1:Show()

			-- savage leather scraps
			WTN:GetResource(52977,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(610,606,615,614,640) 
			-- Kelpthar Forest:610 Mount Hyjal:606 Shimmering Expanse:615 Abyssal Depths:614 Deepholm:640

			-- none
			bR3:ClearData()
		end
		if level > 82 and level <= 85 then
			-- none
			bR1:ClearData()
			bR1:Show()

			-- savage leather
			WTN:GetResource(52976,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(640,614,720,700) 
			-- Deepholm:640 Abyssal Depths:614 Uldum:720 Twilight Highlands:700

			-- sha-touched leather
			WTN:GetResource(72162,bR3)
			bR3.TOOLTIP_TEXT = WTN:GetRecommendedAreas(806,807) 
			-- The Jade Forest:806 Valley of the Four Winds:807
		end
		if level > 85 and level <= 87 then
			-- sha-touched leather
			WTN:GetResource(72162,bR1)
			bR1.TOOLTIP_TEXT = WTN:GetRecommendedAreas(806,807) 
			-- The Jade Forest:806 Valley of the Four Winds:807
			bR1:Show()

			-- none
			bR2:ClearData()

			-- none
			bR3:ClearData()
		end
		if level > 87 and level <= 90 then
			-- none
			bR1:ClearData()
			bR1:Show()

			-- exotic leather
			WTN:GetResource(72120,bR2)
			bR2.TOOLTIP_TEXT = WTN:GetRecommendedAreas(807,810,809,811) 
			-- Valley of the Four Winds:807 Townlong Steppes:810 Kun-lai Summit:809 Vale of Eternal Blossoms:811

			-- none
			bR3:ClearData()
		end
	else
		print("Level up some more. Creeps might be too strong for you.")
	end	
end

function WTN:ExportMapsToCSV()
	if not MapExport then
  	MapExport=CreateFrame("EditBox",nil,UIParent,"InputBoxTemplate")
	end
	local e=MapExport
	e:SetMaxLetters(0)
	e:SetPoint("CENTER",0,0)
	e:SetWidth(150)
	e:SetScript("OnEscapePressed",e.Hide)
	e:SetScript("OnEnterPressed",e.Hide)
	local c,z={GetMapContinents()},{}
	for k,v in ipairs(c) do
	  local n={GetMapZones(k)}
	  for i,m in ipairs(n) do
	    z[m]={k,v}
	  end
	end
	local t="\"MapName\",MapID,\"Continent\",ContinentID\n"
	for i=1,1100 do -- enough to get all MapIDs until 5.5, might need to bump the upper limit for next expansion.
	  local m=GetMapNameByID(i)
	  if (m) and m~="" and z[m] then
	    t=("%s%q,%d,%q,%d\n"):format(t,m,i,z[m][2],z[m][1])
	  end
	end
	t=t:gsub("\n$","")
	e:Show()
	e:SetFocus()
	e:SetText(t)
	e:HighlightText()
	print("Maps exported\nCtrl-C to copy\nPaste in a text editor and save as csv\nImport to a spreadsheet for sorting/search")
	print("Escape or Enter to regain keyboard control.")
end
--[[notes
2934 -- ruined leather scraps 1-15 NPC vanilla
2318 -- light leather L6-25 NPC vanilla
2319 -- medium leather L15-35 NPC vanilla
4234 -- heavy leather L30-45 NPC vanilla
4304 -- thick leather L35-55 NPC vanilla
8170 -- rugged leather L46-58 NPC vanilla
17012 -- core leather L62-63 NPC vanilla
25649 -- knothide leather scraps L58-65 NPC tbc
21887 -- knothide leather L65-71 NPC tbc
33567 -- borean leather scraps L67-75 NPC wlk
33568 -- borean leather L75-81 NPC wlk
52977 -- savage leather scraps L80-82 NPC cata
52976 -- savage leather L82-85 NPC cata
72162 -- sha-touched leather L84-87 NPC mop
72120 -- exotic leather L87-90 NPC mop
]]

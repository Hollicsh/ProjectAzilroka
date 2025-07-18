local PA, ACL, ACH = unpack(_G.ProjectAzilroka)
if PA.Classic then
	return
end

local EPB = PA:NewModule("EnhancedPetBattleUI", "AceEvent-3.0")
_G.EnhancedPetBattleUI, PA.EnhancedPetBattleUI = EPB, EPB
_G.BINDING_HEADER_ENHANCEDPETBATTLEUI = "EnhancedPetBattleUI"

EPB.Title, EPB.Description, EPB.Authors, EPB.isEnabled =
	"EnhancedPet Battle UI", ACL["An enhanced UI for pet battles"], "Azilroka", false

local floor, min, max, ceil, format = floor, min, max, ceil, format

function EPB.round(num, idp)
	local mult = 10 ^ (idp or 0)
	return floor(num * mult + 0.5) / mult
end

function EPB.clamp(num, minVal, maxVal)
	return min(max(num, minVal), maxVal)
end

local round, clamp = EPB.round, PA.Clamp

local C_AddOns_LoadAddOn = _G.C_AddOns.LoadAddOn
local C_AddOns_IsAddOnLoaded = _G.C_AddOns.IsAddOnLoaded
local C_Spell_GetSpellInfo = _G.C_Spell.GetSpellInfo
local C_Spell_GetSpellName = _G.C_Spell.GetSpellName
local C_Spell_GetSpellCooldown = _G.C_Spell.GetSpellCooldown
local C_Spell_GetSpellLink = _G.C_Spell.GetSpellLink
local C_Spell_GetSpellTexture = _G.C_Spell.GetSpellTexture
local C_Item_GetItemInfo = _G.C_Item.GetItemInfo
local C_Item_GetItemInfoInstant = _G.C_Item.GetItemInfoInstant
local C_Item_GetItemCount = _G.C_Item.GetItemCount
local C_Item_GetItemQualityColor = _G.C_Item.GetItemQualityColor

local UIParent, CreateFrame, GameTooltip = UIParent, CreateFrame, GameTooltip

local Enum_BattlePetOwner_Ally, Enum_BattlePetOwner_Enemy = Enum.BattlePetOwner.Ally, Enum.BattlePetOwner.Enemy

local UnitHealth = _G.UnitHealth
local InCombatLockdown = _G.InCombatLockdown
local AuraUtil_FindAuraByName = _G.AuraUtil.FindAuraByName

local C_PetBattles = C_PetBattles
local C_PetJournal = C_PetJournal

local BattlePetBreedID, BreedInfo, BreedData

EPB.Colors = {
	White = { 1, 1, 1 },
	Green = { 0, 1, 0 },
	Yellow = { 1, 1, 0 },
	Red = { 1, 0, 0 },
	Orange = { 1, 0.35, 0 },
	Black = { 0, 0, 0 },
}

EPB.TexturePath, EPB.TooltipHealthIcon, EPB.TooltipPowerIcon, EPB.TooltipSpeedIcon =
	[[Interface\AddOns\ProjectAzilroka\Media\Textures\]],
	[[|TInterface\PetBattles\PetBattle-StatIcons:16:16:0:0:32:32:16:32:16:32|t]],
	[[|TInterface\PetBattles\PetBattle-StatIcons:16:16:0:0:32:32:0:16:0:16|t]],
	[[|TInterface\PetBattles\PetBattle-StatIcons:16:16:0:0:32:32:0:16:16:32|t]]
EPB.Events = {
	"PLAYER_ENTERING_WORLD",
	"PET_BATTLE_MAX_HEALTH_CHANGED",
	"PET_BATTLE_HEALTH_CHANGED",
	"PET_BATTLE_AURA_APPLIED",
	"PET_BATTLE_AURA_CANCELED",
	"PET_BATTLE_AURA_CHANGED",
	"PET_BATTLE_XP_CHANGED",
	"PET_BATTLE_OPENING_START",
	"PET_BATTLE_OPENING_DONE",
	"PET_BATTLE_CLOSE",
	"BATTLE_PET_CURSOR_CLEAR",
	"PET_JOURNAL_LIST_UPDATE",
}

local E = PA.ElvUI and ElvUI[1]

function EPB:ChangePetBattlePetSelectionFrameState(state)
	if state and self.lastState then
		state = false
	end
	self.InSwitchMode = state
	local bf = _G.PetBattleFrame.BottomFrame
	local frame = bf.PetSelectionFrame
	if self.db.HideBlizzard then
		frame:Hide()
	else
		frame:SetShown(state)
	end
	for i = 1, _G.NUM_BATTLE_PET_ABILITIES do
		if bf.abilityButtons[i] then
			bf.abilityButtons[i]:SetShown(not state)
		end
	end
	bf.FlowFrame.SelectPetInstruction:SetShown(state)
	self.UpdateFrame(self.Ally)
	self.lastState = state
end

function EPB:HideBlizzard()
	if EPB.db["HideBlizzard"] then
		self.ActiveAlly:Hide()
		self.Ally2:Hide()
		self.Ally3:Hide()
		self.ActiveEnemy:Hide()
		self.Enemy2:Hide()
		self.Enemy3:Hide()
		self.TopVersusText:Hide()
	else
		self.ActiveAlly:Show()
		local AllyPets = C_PetBattles.GetNumPets(1)
		local EnemyPets = C_PetBattles.GetNumPets(2)
		if AllyPets > 1 then
			for i = 2, AllyPets do
				self["Ally" .. i]:Show()
			end
		end
		self.ActiveEnemy:Show()
		if EnemyPets > 1 then
			for i = 2, EnemyPets do
				self["Enemy" .. i]:Show()
			end
		end
		self.TopVersusText:Show()
	end
	self.BottomFrame.xpBar:Hide()
	self.BottomFrame.TurnTimer:SetShown(not (C_PetBattles.IsWildBattle() or C_PetBattles.IsPlayerNPC(2)))
end

function EPB:EnemyIconOnEnter()
	C_PetJournal.SetSearchFilter("")
	C_PetJournal.SetFilterChecked(_G.LE_PET_JOURNAL_FILTER_COLLECTED, true)
	C_PetJournal.SetFilterChecked(_G.LE_PET_JOURNAL_FILTER_NOT_COLLECTED, false)
	GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT", 2, 4)
	GameTooltip:ClearLines()
	local parent = self:GetParent()
	if parent.Owned ~= nil then
		GameTooltip:AddLine(parent.Owned)
	end
	for i = 1, C_PetJournal.GetNumPets(false) do
		local petID, speciesID, _, _, level = C_PetJournal.GetPetInfoByIndex(i)
		if speciesID == parent.TargetID and petID then
			local _, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(petID)
			local petLink = C_PetJournal.GetBattlePetLink(petID)
			if petLink then
				GameTooltip:AddLine(" ")
				local breed, breedIndex, h25, p25, s25 = ""
				--if _G.PetTracker then
				--	breedIndex = _G.PetTracker.Predict:Breed(speciesID, level, rarity, maxHealth, power, speed)
				--	breed = EPB.db["PetTrackerIcon"] and _G.PetTracker:GetBreedIcon(breedIndex, 1) or _G.PetTracker:GetBreedName(breedIndex)
				--	h25, p25, s25 = _G.PetTracker.Predict:Stats(speciesID, 25, rarity, breedIndex)
				--else
				if BattlePetBreedID then
					_G.BPBID_Options.format = 1 -- Forcing it, No Choice, I need this info
					breedIndex = _G.GetBreedID_Battle(parent)
					_G.BPBID_Options.format = 3 -- Forcing it, No Choice, I need this info
					breed = _G.GetBreedID_Battle(parent)
					h25 = ceil(
						(_G.BPBID_Arrays.BasePetStats[speciesID][1] + _G.BPBID_Arrays.BreedStats[breedIndex][1])
								* 25
								* ((_G.BPBID_Arrays.RealRarityValues[rarity] - 0.5) * 2 + 1)
								* 5
							+ 100
							- 0.5
					)
					p25 = ceil(
						(_G.BPBID_Arrays.BasePetStats[speciesID][2] + _G.BPBID_Arrays.BreedStats[breedIndex][2])
								* 25
								* ((_G.BPBID_Arrays.RealRarityValues[rarity] - 0.5) * 2 + 1)
							- 0.5
					)
					s25 = ceil(
						(_G.BPBID_Arrays.BasePetStats[speciesID][3] + _G.BPBID_Arrays.BreedStats[breedIndex][3])
								* 25
								* ((_G.BPBID_Arrays.RealRarityValues[rarity] - 0.5) * 2 + 1)
							- 0.5
					)
				end
				GameTooltip:AddDoubleLine(petLink, breed, 1, 1, 1, 1, 1, 1)
				GameTooltip:AddDoubleLine("Species ID", speciesID, 1, 1, 1, 1, 0, 0)
				if EPB.db["EnhanceTooltip"] and BattlePetBreedID then -- _G.PetTracker
					GameTooltip:AddDoubleLine(
						format("%s %d", _G.LEVEL, level),
						format("%s %d", _G.LEVEL, 25),
						1,
						1,
						1,
						1,
						1,
						1
					)
					GameTooltip:AddDoubleLine(format("%s %s", EPB.TooltipHealthIcon, maxHealth), h25, 1, 1, 1, 1, 1, 1)
					GameTooltip:AddDoubleLine(format("%s %s", EPB.TooltipPowerIcon, power), p25, 1, 1, 1, 1, 1, 1)
					GameTooltip:AddDoubleLine(format("%s %s", EPB.TooltipSpeedIcon, speed), s25, 1, 1, 1, 1, 1, 1)
					GameTooltip:AddDoubleLine("Breed Index", breedIndex, 1, 1, 1, 1, 1, 1)
					if EPB.db["LevelBreakdown"] then
						local baseStats = EPB:GetLevelBreakdown(petID)
						if baseStats then
							local hpds, pbds, sbds = unpack(baseStats)
							local spl = format(
								"%s%s %s%s %s%s",
								EPB.TooltipHealthIcon,
								round(hpds, 2),
								EPB.TooltipPowerIcon,
								round(pbds, 2),
								EPB.TooltipSpeedIcon,
								round(sbds, 2)
							)
							GameTooltip:AddLine(" ")
							GameTooltip:AddDoubleLine("Stats Per Level", spl, 1, 1, 1, 1, 1, 1)
						end
					end
				else
					local rightString = format(
						"%s%s %s%s %s%s",
						EPB.TooltipHealthIcon,
						maxHealth,
						EPB.TooltipPowerIcon,
						power,
						EPB.TooltipSpeedIcon,
						speed
					)
					GameTooltip:AddDoubleLine(format("%s %d", _G.LEVEL, level), rightString, 1, 1, 1, 1, 1, 1)
				end
			end
		end
	end
	GameTooltip:Show()
end

function EPB:InitPetFrameAPI()
	if PA.oUF and self.db.UseoUF then
		do
			local oUF = PA.oUF
			local ActivePetOwner, ActivePetIndex

			function EPB:CreateFrames()
				oUF:RegisterStyle("EPB_PBUF", function(frame, unit)
					frame:SetFrameLevel(5)
					EPB:ConstructPetFrame(frame, unit)
				end)

				oUF:SetActiveStyle("EPB_PBUF")

				for _, petType in pairs({ "Ally", "Enemy" }) do
					local frame = CreateFrame("frame", petType, UIParent)
					frame:SetSize(270, 380)
					frame:SetFrameStrata("BACKGROUND")
					frame:SetFrameLevel(0)

					frame.petOwner = petType == "Ally" and Enum_BattlePetOwner_Ally or Enum_BattlePetOwner_Enemy
					frame:SetPoint(
						unpack(
							petType == "Ally" and { "RIGHT", UIParent, "BOTTOM", -200, 400 }
								or { "LEFT", UIParent, "BOTTOM", 200, 400 }
						)
					)
					frame.Pets = {}

					for i = 1, 3 do
						ActivePetOwner = frame.petOwner
						ActivePetIndex = i
						frame.Pets[i] = oUF:Spawn("player", ("EPB_PBUF_team%d_pet%d"):format(frame.petOwner, i))
						frame.Pets[i]:SetParent(frame)
					end
					ActivePetOwner = frame.petOwner
					ActivePetIndex = 0
					frame.Pets.team = oUF:Spawn("player", ("EPB_PBUF_team%d_teamauras"):format(frame.petOwner))
					frame.Pets.team:SetParent(frame)
					for _, event in pairs(self.Events) do
						frame:RegisterEvent(event)
					end

					for i = 1, 3 do
						self:UpdatePetFrame(frame.Pets[i])
					end
					self:UpdatePetFrameAnchors(frame.Pets.team)
					frame:SetScript("OnEvent", EPB.UpdateFrame)

					_G.RegisterStateDriver(frame, "visibility", "[petbattle] show; hide")

					self:EnableMover(frame, frame.petOwner)

					self[petType] = frame
				end
			end

			function EPB:ConstructTagString(frame)
				local tagstr = frame.RaisedElementParent:CreateFontString(nil, "ARTWORK")
				return tagstr
			end

			function EPB:ConstructPetFrame(frame, unit)
				local petOwner = ActivePetOwner
				local petIndex = ActivePetIndex
				frame.pbouf_petinfo = { petOwner = petOwner, petIndex = petIndex }
				frame.unit = unit
				frame.PBAuras = {}
				frame.PBBuffs = self:ConstructBuffs(frame, petOwner, petIndex)
				frame.PBDebuffs = self:ConstructDebuffs(frame, petOwner, petIndex)
				if petIndex == 0 then
					_G.RegisterStateDriver(frame, "visibility", "[petbattle] show; hide")
					return
				end
				frame.RaisedElementParent = CreateFrame("Frame", nil, frame)
				frame.RaisedElementParent:SetFrameLevel(10000)
				PA:SetInside(frame.RaisedElementParent)

				frame.Name = self:ConstructTagString(frame)
				frame.PBHealth = self:ConstructHealth(frame, petOwner, petIndex)
				frame.PBExperience = self:ConstructExperience(frame, petOwner, petIndex)
				frame.PBPortrait = self:ConstructPotrait(frame, petOwner, petIndex)
				if PA.ElvUI then
					frame.PBCutaway = self:ConstructCutaway(frame, petOwner, petIndex)
				end
				frame.PBFamilyIcon = self:ConstructFamilyIcon(frame, petOwner, petIndex)
				frame.PBDeadIndicator = self:ConstructDeadIndicator(frame, petOwner, petIndex)
				frame.PBPower = self:ConstructPower(frame, petOwner, petIndex)
				frame.PBSpeed = self:ConstructSpeed(frame, petOwner, petIndex)
				frame.BreedID = self:ConstructTagString(frame)

				frame:HookScript("OnEnter", function()
					if _G.Rematch then
						local petInfo = frame.pbouf_petinfo
						_G.Rematch.cardManager:ShowCard(
							_G.Rematch.petCard,
							C_PetBattles.GetPetSpeciesID(petInfo.petOwner, petInfo.petIndex)
						)
					end
				end)
				frame:HookScript("OnLeave", function()
					if _G.Rematch then
						_G.Rematch.cardManager:HideCard(_G.Rematch.petCard)
					end
				end)

				frame:HookScript("OnClick", function()
					local petInfo = frame.pbouf_petinfo
					if _G.Rematch and not self.InSwitchMode then
						_G.Rematch.cardManager:LockCard(_G.Rematch.petCard)
					elseif
						self.InSwitchMode
						and petInfo.petOwner == Enum_BattlePetOwner_Ally
						and C_PetBattles.CanPetSwapIn(petInfo.petIndex)
					then
						C_PetBattles.ChangePet(petInfo.petIndex)
						EPB:ChangePetBattlePetSelectionFrameState(false)
					end
				end)

				PA:SetTemplate(frame, "Transparent")

				frame.BorderColor = { frame:GetBackdropBorderColor() }

				PA:CreateShadow(frame)
			end

			function EPB:ConstructHealth(frame, petOwner, petIndex)
				local health = CreateFrame("StatusBar", nil, frame)
				health.bg = health:CreateTexture(nil, "BORDER")
				health.bg:SetAllPoints()
				health.bg:SetTexture(ElvUI[1].media.blankTex)
				health.bg.multiplier = 0.35
				if EPB.CustomCreateBackdrop then
					EPB.CustomCreateBackdrop(health)
				else
					PA:CreateBackdrop(health)
				end
				health.colorClass = PA.ElvUI and E.db.unitframe.colors.healthclass
				health.colorSmooth = PA.ElvUI and E.db.unitframe.colors.colorhealthbyvalue or true
				health.isEnemy = petOwner == Enum_BattlePetOwner_Enemy

				local clipFrame = CreateFrame("Frame", nil, health)
				clipFrame:SetClipsChildren(true)
				clipFrame:SetAllPoints()
				clipFrame:EnableMouse(false)
				health.ClipFrame = clipFrame

				health:SetFrameLevel(frame:GetFrameLevel() + 5)
				health:SetReverseFill(petOwner == Enum_BattlePetOwner_Enemy)
				health.value = self:ConstructTagString(frame)
				if PA.ElvUI then
					health.PostUpdateColor = EPB.PostUpdateHealthColor
				end
				return health
			end

			function EPB:PostUpdateHealthColor(_, r, g, b)
				local parent = self:GetParent()
				local colors = E.db.unitframe.colors
				local newr, newg, newb -- fallback for bg if custom settings arent used
				if not b then
					r, g, b = colors.health.r, colors.health.g, colors.health.b
				end
				if colors.healthclass and colors.colorhealthbyvalue then
					local capColor = PA.MyClass == "PRIEST"
					if colors.healthclass and self.isEnemy then
						r = capColor and math.max(1 - r, 0.35) or 1 - r
						g = capColor and math.max(1 - g, 0.35) or 1 - g
						b = capColor and math.max(1 - b, 0.35) or 1 - b
					end
					newr, newg, newb = oUF:ColorGradient(self.cur or 1, self.max or 1, 1, 0, 0, 1, 1, 0, r, g, b)
					self:SetStatusBarColor(newr, newg, newb)
				elseif self.isEnemy then
					local color = parent.colors.reaction[HOSTILE_REACTION]
					if color then
						self:SetStatusBarColor(color[1], color[2], color[3])
					end
				end
				if self.bg then
					self.bg.multiplier = (colors.healthMultiplier > 0 and colors.healthMultiplier) or 0.35

					if colors.useDeadBackdrop and (self.cur or 1) == 0 then
						self.bg:SetVertexColor(
							colors.health_backdrop_dead.r,
							colors.health_backdrop_dead.g,
							colors.health_backdrop_dead.b
						)
					elseif colors.customhealthbackdrop then
						self.bg:SetVertexColor(
							colors.health_backdrop.r,
							colors.health_backdrop.g,
							colors.health_backdrop.b
						)
					elseif colors.classbackdrop then
						local _, Class = UnitClass("player")
						color = parent.colors.class[Class]
						if color and self.invertClassColor then
							for i = 1, 3 do
								color[i] = math.max(1 - color[i], 0.15)
							end
						end
						if color then
							self.bg:SetVertexColor(
								color[1] * self.bg.multiplier,
								color[2] * self.bg.multiplier,
								color[3] * self.bg.multiplier
							)
						end
					elseif newb then
						self.bg:SetVertexColor(
							newr * self.bg.multiplier,
							newg * self.bg.multiplier,
							newb * self.bg.multiplier
						)
					else
						self.bg:SetVertexColor(r * self.bg.multiplier, g * self.bg.multiplier, b * self.bg.multiplier)
					end
				end
			end

			function EPB:ConstructExperience(frame, petOwner, petIndex)
				local xp = CreateFrame("StatusBar", nil, frame)

				if EPB.CustomCreateBackdrop then
					EPB.CustomCreateBackdrop(xp)
				else
					PA:CreateBackdrop(xp)
				end

				xp.value = frame.RaisedElementParent:CreateFontString(nil, "ARTWORK")
				return xp
			end

			function EPB:ConstructPotrait(frame, petOwner, petIndex)
				local portrait = CreateFrame("PlayerModel", nil, frame)
				return portrait
			end

			function EPB:ConstructDeadIndicator(frame, petOwner, petIndex)
				local deadIndicator = frame.RaisedElementParent:CreateTexture(nil, "ARTWORK")
				deadIndicator.__owner = frame
				return deadIndicator
			end

			if PA.ElvUI then
				function EPB:ConstructCutaway(frame, petOwner, petIndex)
					local chealth = frame.PBHealth.ClipFrame:CreateTexture(nil, "ARTWORK")

					return { Health = chealth }
				end
			end

			function EPB:ConstructFamilyIcon(frame, petOwner, petIndex)
				local familyIcon = frame.RaisedElementParent:CreateTexture(nil, "ARTWORK")
				familyIcon.Tooltip = CreateFrame("frame", nil, frame)
				familyIcon.Tooltip:SetAllPoints(familyIcon)
				familyIcon.Tooltip:SetScript("OnEnter", function(_self)
					local _parent = _self:GetParent()
					local petInfo = _parent.pbouf_petinfo
					local petType = C_PetBattles.GetPetType(petInfo.petOwner, petInfo.petIndex)
					local auraID = _G.PET_BATTLE_PET_TYPE_PASSIVES[petType]
					_G.PetBattleAbilityTooltip_SetAuraID(petInfo.petOwner, petInfo.petIndex, auraID)
					_G.PetBattlePrimaryAbilityTooltip:ClearAllPoints()
					_G.PetBattlePrimaryAbilityTooltip:SetPoint("BOTTOMRIGHT", _parent, "TOPRIGHT", 0, 2)
					_G.PetBattlePrimaryAbilityTooltip:Show()
				end)
				familyIcon.Tooltip:SetScript("OnLeave", function()
					_G.PetBattlePrimaryAbilityTooltip:Hide()
				end)
				return familyIcon
			end

			function EPB:ConstructPower(frame, petOwner, petIndex)
				local power = frame.RaisedElementParent:CreateTexture(nil, "ARTWORK")
				power.__owner = frame
				power.value = frame.RaisedElementParent:CreateFontString(nil, "ARTWORK")
				return power
			end

			function EPB:ConstructSpeed(frame, petOwner, petIndex)
				local speed = frame.RaisedElementParent:CreateTexture(nil, "ARTWORK")
				speed.__owner = frame
				speed.value = frame.RaisedElementParent:CreateFontString(nil, "ARTWORK")
				speed.PostUpdate = self.PostUpdateSpeed
				return speed
			end

			function EPB:PostUpdatePower(event)
				if event == "PET_BATTLE_CLOSE" then
					self.oldPower = nil
					return
				end
				local petInfo = self.__owner.pbouf_petinfo
				local power = C_PetBattles.GetPower(petInfo.petOwner, petInfo.petIndex)
				if not self.oldPower then
					self.oldPower = power
				end
			end

			function EPB:PostUpdateSpeed(event)
				if event == "PET_BATTLE_CLOSE" then
					self.oldSpeed = nil
					return
				end
				local petInfo = self.__owner.pbouf_petinfo
				local activePet = C_PetBattles.GetActivePet(petInfo.petOwner)
				if activePet == petInfo.petIndex then
					local otherPetOwner = petInfo.petOwner == Enum_BattlePetOwner_Ally and Enum_BattlePetOwner_Enemy
						or Enum_BattlePetOwner_Ally
					local theirActivePet = C_PetBattles.GetActivePet(otherPetOwner)
					local mySpeed = C_PetBattles.GetSpeed(petInfo.petOwner, petInfo.petIndex)
					local theirSpeed = C_PetBattles.GetSpeed(otherPetOwner, theirActivePet)
					local color = EPB.Colors.Yellow
					if mySpeed > theirSpeed then
						color = EPB.Colors.Green
					elseif mySpeed < theirSpeed then
						color = EPB.Colors.Red
					end
					self:SetVertexColor(unpack(color))
				end
				local speed = C_PetBattles.GetSpeed(petInfo.petOwner, petInfo.petIndex)
				if not self.oldSpeed then
					self.oldSpeed = speed
				end
			end

			function EPB:ConstructBuffs(frame, petOwner, petIndex)
				local buffs = CreateFrame("Frame", nil, frame)
				buffs.size = 26
				buffs.num = 12
				buffs.numRow = 9
				buffs.spacing = 2
				buffs.initialAnchor = petOwner == Enum_BattlePetOwner_Ally and "TOPLEFT" or "TOPRIGHT"
				buffs["growth-y"] = "DOWN"
				buffs["growth-x"] = petOwner == Enum_BattlePetOwner_Ally and "RIGHT" or "LEFT"
				buffs.PostCreateIcon = self.PostCreateAura
				return buffs
			end

			function EPB:ConstructDebuffs(frame, petOwner, petIndex)
				local debuffs = CreateFrame("Frame", nil, frame)
				debuffs.size = 26
				debuffs.num = 12
				debuffs.spacing = 2
				debuffs.initialAnchor = petOwner == Enum_BattlePetOwner_Ally and "TOPRIGHT" or "TOPLEFT"
				debuffs["growth-y"] = "DOWN"
				debuffs["growth-x"] = petOwner == Enum_BattlePetOwner_Ally and "LEFT" or "RIGHT"
				debuffs.isDebuff = true
				debuffs.PostCreateIcon = self.PostCreateAura
				return debuffs
			end

			function EPB:PostCreateAura(button)
				PA:SetTemplate(button)

				local Font, FontSize, FontFlag =
					PA.Libs.LSM:Fetch("font", EPB.db["Font"]), EPB.db["FontSize"], EPB.db["FontFlag"]
				button.turnsRemaining:SetFont(Font, FontSize, FontFlag)
				button.icon:SetTexCoord(PA:TexCoords())
				PA:SetInside(button.icon)
				button:SetBackdropBorderColor(unpack(self.isDebuff and { 1, 0, 0 } or { 0, 1, 0 }))
			end

			function EPB:UpdatePetFrameMedia(frame)
				local NormTex = PA.Libs.LSM:Fetch("statusbar", EPB.db["StatusBarTexture"])
				local Font, FontSize, FontFlag =
					PA.Libs.LSM:Fetch("font", EPB.db["Font"]), EPB.db["FontSize"], EPB.db["FontFlag"]

				frame.Name:SetFont(Font, FontSize, FontFlag)
				frame.PBHealth:SetStatusBarTexture(NormTex)
				frame.PBHealth.value:SetFont(Font, FontSize, FontFlag)
				frame.PBPower.value:SetFont(Font, FontSize, FontFlag)
				frame.PBSpeed.value:SetFont(Font, FontSize, FontFlag)
				frame.PBCutaway.Health:SetTexture(NormTex)
				frame.BreedID:SetFont(Font, FontSize, FontFlag)
				frame.PBExperience.value:SetFont(Font, FontSize, FontFlag)
				frame.PBExperience:SetStatusBarTexture(NormTex)
				frame.PBExperience:SetStatusBarColor(0.24, 0.54, 0.78)
			end

			function EPB:UpdatePetFrameAnchors(frame)
				local Offset = EPB.db["TextOffset"]
				local petInfo = frame.pbouf_petinfo
				if petInfo.petIndex == 0 then
					local BuffPoint, DebuffPoint
					if petInfo.petOwner == Enum_BattlePetOwner_Ally then
						BuffPoint, DebuffPoint = "TOPLEFT", "TOPRIGHT"
					else
						BuffPoint, DebuffPoint = "TOPRIGHT", "TOPLEFT"
					end

					frame:SetSize(270, 26)
					frame.PBBuffs:SetSize(150, 26)
					frame.PBBuffs:SetPoint(BuffPoint, frame)
					frame.PBDebuffs:SetSize(150, 26)
					frame.PBDebuffs:SetPoint(DebuffPoint, frame)
					return
				end
				frame:Size(278, 80)
				frame.PBHealth:Size(270, 52)
				if petInfo.petOwner == Enum_BattlePetOwner_Ally then
					frame.PBHealth:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
				else
					frame.PBHealth:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
				end
				frame.PBHealth.value:SetPoint("BOTTOM", frame.PBHealth, "BOTTOM", 0, Offset + 8)
				frame.PBHealth.value:SetJustifyH("CENTER")
				frame.PBHealth.value:SetJustifyV("BOTTOM")
				frame.PBExperience:Size(270, 22)
				frame.PBExperience:SetPoint("TOP", frame.PBHealth, "BOTTOM")
				frame.PBExperience.value:SetPoint("CENTER", frame.PBExperience, "CENTER", 0, Offset)
				local texture = frame.PBHealth:GetStatusBarTexture()
				local ch = frame.PBCutaway.Health
				ch:ClearAllPoints()
				if petInfo.petOwner == Enum_BattlePetOwner_Ally then
					ch:SetPoint("TOPLEFT", texture, "TOPRIGHT")
					ch:SetPoint("BOTTOMLEFT", texture, "BOTTOMRIGHT")
				else
					ch:SetPoint("TOPRIGHT", texture, "TOPLEFT")
					ch:SetPoint("BOTTOMRIGHT", texture, "BOTTOMLEFT")
				end
				frame.PBHealth:PostUpdateColor()
				frame.PBDeadIndicator:SetPoint("BOTTOM", frame.PBHealth, "BOTTOM", 0, Offset)
				local portrait = frame.PBPortrait
				portrait:ClearAllPoints()
				portrait:SetFrameLevel(frame.PBHealth:GetFrameLevel())
				portrait:SetAllPoints(frame.PBHealth)
				if true then
					portrait:SetAlpha(0)
					portrait:SetAlpha(0.35)
					portrait:Show()
				else
					portrait:Hide()
				end
				frame.Name:SetPoint("TOP", frame.PBHealth, "TOP", 0, -Offset)
				frame.Name:SetJustifyH("CENTER")
				frame.Name:SetJustifyV("TOP")
				local PositioningSettings = {
					[Enum_BattlePetOwner_Ally] = {
						familyIconPoint = "TOPLEFT",
						buffsInitialPoint = "BOTTOMLEFT",
						buffsRelativePoint = "TOPLEFT",
						buffsOffsetX = 7,
						buffsOffsetY = 1,
						debuffsInitialPoint = "BOTTOMRIGHT",
						debuffsRelativePoint = "TOPRIGHT",
						debuffsOffsetX = -7,
						debuffsOffsetY = 28,
						breedIDPoint = "TOPRIGHT",
						statInitialPoint = "RIGHT",
						statRelativePoint = "LEFT",
						statOffsetX = -2,
						statJustifyH = "RIGHT",
					},
					[Enum_BattlePetOwner_Enemy] = {
						familyIconPoint = "TOPRIGHT",
						buffsInitialPoint = "BOTTOMRIGHT",
						buffsRelativePoint = "TOPRIGHT",
						buffsOffsetX = -7,
						buffsOffsetY = 1,
						debuffsInitialPoint = "BOTTOMLEFT",
						debuffsRelativePoint = "TOPLEFT",
						debuffsOffsetX = 7,
						debuffsOffsetY = 28,
						breedIDPoint = "TOPLEFT",
						statInitialPoint = "LEFT",
						statRelativePoint = "RIGHT",
						statOffsetX = 2,
						statJustifyH = "LEFT",
					},
				}
				local ps = PositioningSettings[petInfo.petOwner]
				frame.PBFamilyIcon:SetSize(20, 20)
				frame.PBFamilyIcon:SetPoint(ps.familyIconPoint, frame, ps.familyIconPoint, ps.buffsOffsetX, -4)
				frame.PBBuffs:SetSize(150, 26)
				frame.PBBuffs:SetPoint(
					ps.buffsInitialPoint,
					frame,
					ps.buffsRelativePoint,
					ps.buffsOffsetX,
					ps.buffsOffsetY
				)
				frame.PBDebuffs:SetSize(150, 26)
				frame.PBDebuffs:SetPoint(
					ps.debuffsInitialPoint,
					frame,
					ps.debuffsRelativePoint,
					ps.debuffsOffsetX,
					ps.debuffsOffsetY
				)
				frame.BreedID:SetJustifyV("TOP")
				frame.BreedID:SetJustifyH(ps.statJustifyH)
				frame.BreedID:SetPoint(ps.breedIDPoint, frame, ps.breedIDPoint, -ps.buffsOffsetX, -4)
				frame.PBPower:SetSize(16, 16)
				frame.PBPower:SetPoint("TOP", frame.BreedID, "BOTTOM", 0, -3)
				frame.PBPower.value:SetPoint(
					ps.statInitialPoint,
					frame.PBPower,
					ps.statRelativePoint,
					ps.statOffsetX,
					0
				)
				frame.PBPower.value:SetJustifyH(ps.statJustifyH)
				frame.PBSpeed:SetSize(16, 16)
				frame.PBSpeed:SetPoint("TOP", frame.PBPower, "BOTTOM", 0, -3)
				frame.PBSpeed.value:SetPoint(
					ps.statInitialPoint,
					frame.PBSpeed,
					ps.statRelativePoint,
					ps.statOffsetX,
					0
				)
				frame.PBSpeed.value:SetJustifyH(ps.statJustifyH)
			end

			function EPB:UpdatePetFrame(frame)
				local petInfo = frame.pbouf_petinfo
				_G.UnregisterUnitWatch(frame)
				frame:SetAttribute("unit", nil)
				if petInfo.petIndex == 0 then
					self:UpdatePetFrameAnchors(frame)
					return
				end
				self:UpdatePetFrameMedia(frame)
				self:UpdatePetFrameAnchors(frame)
			end

			function EPB:UpdatePetFrameTags(frame)
				local petInfo = frame.pbouf_petinfo
				frame:Tag(frame.Name, EPB.db.nameFormat)
				frame:Tag(frame.PBHealth.value, EPB.db.healthFormat)
				if petInfo.petOwner == Enum_BattlePetOwner_Ally then
					frame:Tag(frame.PBExperience.value, EPB.db.xpFormat)
				end
				frame:Tag(frame.PBPower.value, EPB.db.powerFormat)
				frame:Tag(frame.PBSpeed.value, EPB.db.speedFormat)
				if petInfo.petOwner == Enum_BattlePetOwner_Ally then
					frame:Tag(frame.BreedID, EPB.db.breedAllyFormat)
				else
					frame:Tag(frame.BreedID, EPB.db.breedEnemyFormat)
				end
			end

			function EPB:UpdateFrame(event)
				local inPetBattle = C_PetBattles.IsInBattle()
				if not inPetBattle then
					return
				end

				local wildBattle = C_PetBattles.IsWildBattle()
				EPB.lastBattleWasWild = wildBattle
				local numPets = C_PetBattles.GetNumPets(self.petOwner)

				for i = 1, numPets do
					local pet = self.Pets[i]
					local customName, petName = C_PetBattles.GetName(self.petOwner, i)
					local xp, maxXP = C_PetBattles.GetXP(self.petOwner, i)
					local level, hp, maxHP, icon =
						C_PetBattles.GetLevel(self.petOwner, i),
						C_PetBattles.GetHealth(self.petOwner, i),
						C_PetBattles.GetMaxHealth(self.petOwner, i),
						C_PetBattles.GetIcon(self.petOwner, i)
					local speciesID, petType, power, speed, rarity =
						C_PetBattles.GetPetSpeciesID(self.petOwner, i),
						C_PetBattles.GetPetType(self.petOwner, i),
						C_PetBattles.GetPower(self.petOwner, i),
						C_PetBattles.GetSpeed(self.petOwner, i),
						C_PetBattles.GetBreedQuality(self.petOwner, i)

					pet.PBFamilyIcon:SetDesaturated(hp == 0)

					if self.petOwner == Enum_BattlePetOwner_Enemy then
						pet.PBExperience:SetMinMaxValues(0, 1)
						pet.PBExperience:SetValue(0)
						pet.PBExperience.value:Hide()
					end

					if self.petOwner == Enum_BattlePetOwner_Enemy and wildBattle then
						local adjustedLevel = level
						if adjustedLevel > 20 then
							adjustedLevel = adjustedLevel - 2
						elseif adjustedLevel > 15 then
							adjustedLevel = adjustedLevel - 1
						end
						pet.TargetID, pet.Owned = speciesID, C_PetJournal.GetOwnedBattlePetString(speciesID)
						pet:SetBackdropBorderColor(unpack(pet.BorderColor))
						if pet.Owned == nil or pet.Owned == "Not Collected" then
							C_PetJournal.SetSearchFilter("")
							C_PetJournal.SetFilterChecked(_G.LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
							for j = 1, C_PetJournal.GetNumPets() do
								local _, species, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, obtainable =
									C_PetJournal.GetPetInfoByIndex(j)
								if obtainable and speciesID == species then
									pet:SetBackdropBorderColor(unpack(EPB.Colors.Red))
								end
							end
						else
							local ownedQuality, ownedLevel = EPB.GetHighestQuality(pet.TargetID)
							if rarity > ownedQuality then
								pet:SetBackdropBorderColor(unpack(EPB.Colors.Orange))
							elseif rarity >= ownedQuality and adjustedLevel > ownedLevel then
								pet:SetBackdropBorderColor(unpack(EPB.Colors.Yellow))
							end
						end
					else
						pet:SetBackdropBorderColor(unpack(EPB.Colors.Black))
					end

					if EPB.InSwitchMode and (self.petOwner == Enum_BattlePetOwner_Ally) and hp > 0 then
						local _, class = _G.UnitClass("player")
						local c = _G.RAID_CLASS_COLORS[class]
						PA.Libs.LCG.PixelGlow_Start(pet.RaisedElementParent, { c.r, c.g, c.b, 1 }, 8, -0.25, nil, 1)
					else
						PA.Libs.LCG.PixelGlow_Stop(pet.RaisedElementParent)
					end

					EPB:UpdatePetFrameTags(pet)

					_G.RegisterStateDriver(pet, "visibility", "[petbattle] show; hide")
				end

				if numPets < 3 then
					for i = numPets + 1, 3 do
						_G.RegisterStateDriver(self.Pets[i], "visibility", "hide")
					end
				end

				local point, relativePoint, xcoord, ycoord
				numPets = EPB.db["TeamAurasOnBottom"] and numPets or 1
				if EPB.db["GrowUp"] then
					if EPB.db["TeamAurasOnBottom"] then
						point, relativePoint, xcoord, ycoord = "BOTTOM", "TOP", 0, 34
					else
						point, relativePoint, xcoord, ycoord = "TOP", "BOTTOM", 0, -14
					end
				else
					if EPB.db["TeamAurasOnBottom"] then
						point, relativePoint, xcoord, ycoord = "TOP", "BOTTOM", 0, -14
					else
						point, relativePoint, xcoord, ycoord = "BOTTOM", "TOP", 0, 34
					end
				end
				self.Pets.team:ClearAllPoints()
				self.Pets.team:SetPoint(point, self.Pets[numPets], relativePoint, xcoord, ycoord)
				_G.RegisterStateDriver(self.Pets.team, "visibility", "[petbattle] show; hide")
			end
		end
	else
		do
			function EPB:CreateFrames()
				for _, petType in pairs({ "Ally", "Enemy" }) do
					local frame = CreateFrame("frame", petType, UIParent)
					frame:Hide()
					frame:SetSize(260, 188)
					frame:SetFrameStrata("BACKGROUND")
					frame:SetFrameLevel(0)

					frame.petOwner = petType == "Ally" and Enum_BattlePetOwner_Ally or Enum_BattlePetOwner_Enemy
					frame:SetPoint(
						unpack(
							petType == "Ally" and { "RIGHT", UIParent, "BOTTOM", -200, 200 }
								or { "LEFT", UIParent, "BOTTOM", 200, 200 }
						)
					)
					frame.Pets = {}

					for i = 1, 3 do
						frame.Pets[i] = self["Create" .. petType .. "UIFrame"](self, frame.petOwner, i, frame)
						frame.Pets[i].OldPower = 0
						frame.Pets[i].OldSpeed = 0
						self:UpdatePetFrame(frame.Pets[i])
					end

					for _, event in pairs(self.Events) do
						frame:RegisterEvent(event)
					end

					frame:SetScript("OnHide", EPB.FrameOnHide)
					frame:SetScript("OnEvent", EPB.UpdateFrame)

					_G.RegisterStateDriver(frame, "visibility", "[petbattle] show; hide")

					self:SetUpTeamAuras(frame, frame.petOwner)
					self:EnableMover(frame, frame.petOwner)

					self[petType] = frame
				end
			end

			function EPB:CreateAllyUIFrame(petOwner, petIndex, parent)
				local frame = self:CreateGenericUIFrame(petOwner, petIndex, parent)
				frame.Icon:SetPoint("LEFT", frame, "LEFT", 6, 0)
				frame.Icon.PetType:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
				frame.Icon.PetType.Tooltip:SetAllPoints(frame.Icon.PetType)
				frame.Level:SetPoint("BOTTOMRIGHT", frame.Icon, 0, 3)
				frame.Level:SetJustifyV("BOTTOM")
				frame.Level:SetJustifyH("RIGHT")
				frame.BreedID:SetPoint("TOPLEFT", frame.Icon, 3, -2)
				frame.BreedID:SetJustifyV("TOP")
				frame.BreedID:SetJustifyH("LEFT")
				frame.Health:SetPoint("LEFT", frame.Icon, "RIGHT", 8, 3)
				frame.Health.Text:SetJustifyV("TOP")
				frame.Health.Text:SetJustifyH("CENTER")
				frame.Experience:SetPoint("TOP", frame.Health, "BOTTOM", 0, -5)
				frame.Experience.Text:SetJustifyV("TOP")
				frame.Experience.Text:SetJustifyH("CENTER")
				frame.Icon.Power:SetPoint("TOPLEFT", frame.Health, "RIGHT", 4, 8)
				frame.Icon.Power:SetTexCoord(0, 0.5, 0, 0.5)
				frame.Power:SetPoint("LEFT", frame.Icon.Power, "RIGHT", 4, 2)
				frame.Icon.Speed:SetPoint("TOPLEFT", frame.Experience, "RIGHT", 4, 8)
				frame.Icon.Speed:SetTexCoord(0, 0.5, 0.5, 1)
				frame.Speed:SetPoint("LEFT", frame.Icon.Speed, "RIGHT", 4, 0)
				frame.Name:SetPoint("BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 4)
				frame.Name:SetJustifyH("LEFT")
				frame.Buff:SetPoint("TOPLEFT", frame, "TOPRIGHT", 3, 1)
				frame.Debuff:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 3, -1)

				return frame
			end

			function EPB:SetAuraTooltipScripts(frame)
				frame:SetScript("OnEnter", function(_self)
					local petOwner, petIndex, auraIndex = _self.petOwner, _self.petIndex, _self.auraIndex
					local auraID, _, turnsRemaining, isBuff = C_PetBattles.GetAuraInfo(petOwner, petIndex, auraIndex)

					if not auraID then
						return
					end
					local _, name, icon = C_PetBattles.GetAbilityInfoByID(auraID)
					GameTooltip:SetOwner(_self, "ANCHOR_TOPRIGHT", 2, 4)
					GameTooltip:ClearLines()
					GameTooltip:AddTexture(icon)
					GameTooltip:AddDoubleLine(name, auraID, isBuff and 0 or 1, isBuff and 1 or 0, 0, 1, 1, 0.7)
					GameTooltip:AddLine(" ")
					_G.PetBattleAbilityTooltip_SetAura(petOwner, petIndex, auraIndex)
					GameTooltip:AddLine(_G.PetBattlePrimaryAbilityTooltip.Description:GetText(), 1, 1, 1)
					GameTooltip:AddLine(" ")
					if turnsRemaining > 0 then
						local remaining = function(r)
							return r > 3 and self.Colors.Green or r > 2 and self.Colors.Yellow or self.Colors.Red
						end
						local c1, c2, c3 = unpack(remaining(turnsRemaining))
						GameTooltip:AddLine(turnsRemaining .. " |cffffffffTurns Remaining|r", c1, c2, c3)
					end
					GameTooltip:Show()
				end)
				frame:SetScript("OnLeave", _G.GameTooltip_Hide)
			end

			function EPB:CreateAuraFrame(parent, auraKey, petOwner, petIndex)
				local frame = CreateFrame("frame", nil, parent)
				frame.petOwner = petOwner
				frame.petIndex = petIndex
				PA:SetTemplate(frame)
				frame:SetBackdropBorderColor(unpack(auraKey == "Buff" and { 0, 1, 0 } or { 1, 0, 0 }))
				frame:Hide()
				frame:SetSize(28, 28)
				frame.Text = frame:CreateFontString(nil, "OVERLAY")
				frame.Text:SetPoint("CENTER")
				frame.Texture = frame:CreateTexture(nil, "ARTWORK")
				PA:SetInside(frame.Texture)
				frame.Texture:SetTexCoord(PA:TexCoords())
				EPB:SetAuraTooltipScripts(frame)
				return frame
			end

			function EPB:BuildAuraSet(frame, auraKey, petOwner, petIndex, point, relativePoint, xcoord)
				local auraFrame = CreateFrame("frame", nil, frame)
				auraFrame:SetSize(99, 30)
				_G.RegisterStateDriver(auraFrame, "visibility", "[petbattle] show; hide")

				for i = 1, 12 do
					local auraChildFrame = self:CreateAuraFrame(auraFrame, auraKey, petOwner, petIndex)

					if i == 1 then
						auraChildFrame:SetPoint(point, auraFrame, point, 0, 0)
					else
						auraChildFrame:SetPoint(point, auraFrame[i - 1], relativePoint, xcoord, 0)
					end

					auraFrame[i] = auraChildFrame
				end

				frame[auraKey] = auraFrame
			end

			function EPB:BuildAuras(frame, petOwner, petIndex)
				local point, relativePoint, xcoord
				if petOwner == Enum_BattlePetOwner_Ally then
					point, relativePoint, xcoord = "LEFT", "RIGHT", 3
				else
					point, relativePoint, xcoord = "RIGHT", "LEFT", -3
				end

				for _, auraKey in pairs({ "Buff", "Debuff" }) do
					self:BuildAuraSet(frame, auraKey, petOwner, petIndex, point, relativePoint, xcoord)
				end
			end

			function EPB:SetUpTeamAuras(parent, petOwner)
				local frame = CreateFrame("frame", nil, parent)
				frame.petOwner = petOwner
				frame.petIndex = 0
				frame:RegisterEvent("PET_BATTLE_AURA_APPLIED")
				frame:RegisterEvent("PET_BATTLE_AURA_CANCELED")
				frame:RegisterEvent("PET_BATTLE_AURA_CHANGED")
				frame:RegisterEvent("PET_BATTLE_OPENING_START")
				frame:SetScript("OnEvent", function(_self, event)
					if event == "PET_BATTLE_OPENING_START" then
						local numPets
						local point, relativePoint, xcoord, ycoord
						if _self.petOwner == Enum_BattlePetOwner_Ally then
							numPets = self.db["TeamAurasOnBottom"] and C_PetBattles.GetNumPets(1) or 1
						else
							numPets = self.db["TeamAurasOnBottom"] and C_PetBattles.GetNumPets(2) or 1
						end
						if EPB.db["GrowUp"] then
							if EPB.db["TeamAurasOnBottom"] then
								point, relativePoint, xcoord, ycoord = "BOTTOM", "TOP", 0, 4
							else
								point, relativePoint, xcoord, ycoord = "TOP", "BOTTOM", 0, -4
							end
						else
							if EPB.db["TeamAurasOnBottom"] then
								point, relativePoint, xcoord, ycoord = "TOP", "BOTTOM", 0, -4
							else
								point, relativePoint, xcoord, ycoord = "BOTTOM", "TOP", 0, 4
							end
						end

						_self:ClearAllPoints()
						_self:SetPoint(point, parent.Pets[numPets], relativePoint, xcoord, ycoord)
					end

					EPB:SetupAuras(_self, _self.petOwner, _self.petIndex)
				end)
				frame:SetSize(260, 30)
				frame:EnableMouse(false)

				EPB:BuildAuras(frame, petOwner, 0)

				local BuffPoint, DebuffPoint
				if petOwner == Enum_BattlePetOwner_Ally then
					BuffPoint, DebuffPoint = "TOPLEFT", "TOPRIGHT"
				else
					BuffPoint, DebuffPoint = "TOPRIGHT", "TOPLEFT"
				end

				frame.Buff:SetPoint(BuffPoint, frame)
				frame.Debuff:SetPoint(DebuffPoint, frame)
			end

			function EPB:EnableAura(frame, auraIndex, icon, turnsRemaining)
				frame.auraIndex = auraIndex
				frame:Show()
				frame.Text:SetFont(PA.Libs.LSM:Fetch("font", EPB.db["Font"]), 20, EPB.db["FontFlag"])
				frame.Text:SetText(turnsRemaining > 0 and turnsRemaining or "")
				frame.Texture:SetTexture(icon)
			end

			function EPB:SetupAuras(frame, owner, index)
				for i = 1, 12 do
					frame.Buff[i]:Hide()
					frame.Debuff[i]:Hide()
				end
				local BuffIndex, DebuffIndex = 1, 1
				for i = 1, 12 do
					local auraID, _, turnsRemaining, isBuff = C_PetBattles.GetAuraInfo(owner, index, i)
					if not auraID then
						return
					end
					local _, _, icon = C_PetBattles.GetAbilityInfoByID(auraID)
					if isBuff then
						self:EnableAura(frame.Buff[BuffIndex], i, icon, turnsRemaining)
						BuffIndex = BuffIndex + 1
					else
						self:EnableAura(frame.Debuff[DebuffIndex], i, icon, turnsRemaining)
						DebuffIndex = DebuffIndex + 1
					end
				end
			end

			function EPB:CreateGenericUIFrame(petOwner, petIndex, parent)
				local frame = CreateFrame("frame", nil, parent)
				frame.petOwner = petOwner
				frame.petIndex = petIndex
				frame:Hide()
				frame:SetSize(260, 60)
				frame:SetFrameLevel(parent:GetFrameLevel() + 1)
				PA:SetTemplate(frame, "Transparent")
				frame.BorderColor = { frame:GetBackdropBorderColor() }
				frame:EnableMouse(true)

				frame.Icon = CreateFrame("frame", nil, frame)
				PA:SetTemplate(frame.Icon, "Transparent")
				frame.Icon:SetFrameLevel(frame:GetFrameLevel() + 1)
				frame.Icon:SetSize(40, 40)

				frame.Icon.PetTexture = frame.Icon:CreateTexture(nil, "ARTWORK")
				frame.Icon.PetTexture:SetTexCoord(PA:TexCoords())
				PA:SetInside(frame.Icon.PetTexture)

				frame.Icon.PetModel = CreateFrame("PlayerModel", nil, frame.Icon)
				frame.Icon.PetModel:SetFrameLevel(frame.Icon:GetFrameLevel())
				frame.Icon.PetModel:SetAllPoints()

				frame.Icon.Dead = frame.Icon:CreateTexture(nil, "OVERLAY")
				frame.Icon.Dead:Hide()
				frame.Icon.Dead:SetTexture(self.TexturePath .. "Dead")
				PA:SetOutside(frame.Icon.Dead, frame.Icon, 8, 8)

				frame.Icon.PetType = frame:CreateTexture(nil, "ARTWORK")
				frame.Icon.PetType:SetSize(32, 32)
				frame.Icon.PetType.Tooltip = CreateFrame("frame", nil, frame)
				frame.Icon.PetType.Tooltip:SetSize(32, 32)
				frame.Icon.PetType.Tooltip:SetScript("OnEnter", function(_self)
					local _parent = _self:GetParent()
					local petType = C_PetBattles.GetPetType(_parent.petOwner, _parent.petIndex)
					local auraID = _G.PET_BATTLE_PET_TYPE_PASSIVES[petType]
					_G.PetBattleAbilityTooltip_SetAuraID(_parent.petOwner, _parent.petIndex, auraID)
					_G.PetBattlePrimaryAbilityTooltip:ClearAllPoints()
					_G.PetBattlePrimaryAbilityTooltip:SetPoint("BOTTOMRIGHT", _parent, "TOPRIGHT", 0, 2)
					_G.PetBattlePrimaryAbilityTooltip:Show()
				end)
				frame.Icon.PetType.Tooltip:SetScript("OnLeave", function()
					_G.PetBattlePrimaryAbilityTooltip:Hide()
				end)

				frame.Icon.Power = frame:CreateTexture(nil, "OVERLAY")
				frame.Icon.Power:SetTexture([[Interface\PetBattles\PetBattle-StatIcons]])
				frame.Icon.Power:SetSize(16, 16)

				frame.Icon.Speed = frame:CreateTexture(nil, "OVERLAY")
				frame.Icon.Speed:SetTexture([[Interface\PetBattles\PetBattle-StatIcons]])
				frame.Icon.Speed:SetSize(16, 16)

				frame.Power = frame:CreateFontString(nil, "OVERLAY")
				frame.Speed = frame:CreateFontString(nil, "OVERLAY")
				frame.Name = frame:CreateFontString(nil, "OVERLAY")
				frame.Level = frame.Icon:CreateFontString(nil, "OVERLAY")
				frame.BreedID = frame.Icon:CreateFontString(nil, "OVERLAY")

				frame.Health = CreateFrame("StatusBar", nil, frame)
				frame.Health:SetSize(150, 11)
				frame.Health:SetFrameLevel(frame:GetFrameLevel() + 2)
				PA:CreateBackdrop(frame.Health, "Transparent", true)
				frame.Health.Text = frame.Health:CreateFontString(nil, "OVERLAY")

				frame.Experience = CreateFrame("StatusBar", nil, frame)
				frame.Experience:SetSize(150, 11)
				frame.Experience:SetFrameLevel(frame:GetFrameLevel() + 2)
				PA:CreateBackdrop(frame.Experience, "Transparent")
				frame.Experience.Text = frame.Experience:CreateFontString(nil, "OVERLAY")

				self:BuildAuras(frame, petOwner, petIndex)

				if _G.Rematch then
					frame:SetScript("OnEnter", function()
						_G.Rematch.cardManager:ShowCard(
							_G.Rematch.petCard,
							C_PetBattles.GetPetSpeciesID(frame.petOwner, frame.petIndex)
						)
					end)
					frame:SetScript("OnLeave", function()
						_G.Rematch.cardManager:HideCard(_G.Rematch.petCard)
					end)
				end

				frame:SetScript("OnMouseDown", function()
					if _G.Rematch and not self.InSwitchMode then
						_G.Rematch.cardManager:LockCard(_G.Rematch.petCard)
					elseif
						self.InSwitchMode
						and frame.petOwner == Enum_BattlePetOwner_Ally
						and C_PetBattles.CanPetSwapIn(frame.petIndex)
					then
						C_PetBattles.ChangePet(frame.petIndex)
						EPB:ChangePetBattlePetSelectionFrameState(false)
					end
				end)

				PA:CreateShadow(frame)

				return frame
			end

			function EPB:UpdatePetFrame(frame)
				local Offset, NormTex, Font, FontSize, FontFlag =
					EPB.db.TextOffset,
					PA.Libs.LSM:Fetch("statusbar", EPB.db.StatusBarTexture),
					PA.Libs.LSM:Fetch("font", EPB.db.Font),
					EPB.db.FontSize,
					EPB.db.FontFlag

				frame.Name:SetFont(Font, FontSize, FontFlag)
				frame.Level:SetFont(Font, FontSize, FontFlag)
				frame.BreedID:SetFont(Font, FontSize, FontFlag)
				frame.Health:SetStatusBarTexture(NormTex)
				frame.Experience:SetStatusBarTexture(NormTex)
				frame.Experience:SetStatusBarColor(0.24, 0.54, 0.78)
				frame.Health.Text:SetFont(Font, FontSize, FontFlag)
				frame.Experience.Text:SetFont(Font, FontSize, FontFlag)
				frame.Power:SetFont(Font, FontSize, FontFlag)
				frame.Speed:SetFont(Font, FontSize, FontFlag)
				frame.Health.Text:SetPoint("TOP", frame.Health, "TOP", 0, Offset)
				frame.Experience.Text:SetPoint("TOP", frame.Experience, "TOP", 0, Offset)

				for j = 1, 6 do
					frame.Buff[j].Text:SetFont(Font, 20, FontFlag)
					frame.Debuff[j].Text:SetFont(Font, 20, FontFlag)
				end
			end

			function EPB:FrameOnHide()
				for i = 1, 3 do
					self.Pets[i]:Hide()
					self.Pets[i].Icon.PetTexture:SetDesaturated(false)
					self.Pets[i].Icon.Dead:Hide()
					self.Pets[i].Icon.Speed:SetVertexColor(unpack(EPB.Colors.Yellow))
					self.Pets[i].OldPower = 0
					self.Pets[i].OldSpeed = 0
				end
			end

			function EPB:CreateEnemyUIFrame(petOwner, petIndex, parent)
				local frame = self:CreateGenericUIFrame(petOwner, petIndex, parent)
				frame.Icon:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
				frame.Icon.PetType:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
				frame.Icon.PetType.Tooltip:SetAllPoints(frame.Icon.PetType)
				frame.Level:SetPoint("BOTTOMLEFT", frame.Icon, "BOTTOMLEFT", 4, 2)
				frame.Level:SetJustifyV("BOTTOM")
				frame.Level:SetJustifyH("LEFT")
				frame.BreedID:SetPoint("TOPRIGHT", frame.Icon, -1, -2)
				frame.BreedID:SetJustifyV("TOP")
				frame.BreedID:SetJustifyH("RIGHT")
				frame.Health:SetPoint("RIGHT", frame.Icon, "LEFT", -8, 3)
				frame.Health:SetReverseFill(true)
				frame.Health.Text:SetJustifyV("TOP")
				frame.Health.Text:SetJustifyH("CENTER")
				frame.Experience:SetPoint("TOP", frame.Health, "BOTTOM", 0, -5)
				frame.Experience:SetReverseFill(true)
				frame.Experience.Text:SetJustifyV("TOP")
				frame.Experience.Text:SetJustifyH("CENTER")
				frame.Icon.Power:SetPoint("TOPRIGHT", frame.Health, "LEFT", -4, 8)
				frame.Icon.Power:SetTexCoord(0, 0.5, 0, 0.5)
				frame.Power:SetPoint("RIGHT", frame.Health, "LEFT", -18, 0)
				frame.Icon.Speed:SetPoint("TOPRIGHT", frame.Experience, "LEFT", -4, 8)
				frame.Icon.Speed:SetTexCoord(0.5, 0, 0.5, 1)
				frame.Speed:SetPoint("RIGHT", frame.Experience, "LEFT", -18, 0)
				frame.Name:SetPoint("BOTTOMRIGHT", frame.Health, "TOPRIGHT", 2, 4)
				frame.Name:SetJustifyH("RIGHT")
				frame.Buff:SetPoint("TOPRIGHT", frame, "TOPLEFT", -3, 1)
				frame.Debuff:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -3, -1)
				frame.Icon:EnableMouse(true)
				frame.Icon:SetScript("OnEnter", EPB.EnemyIconOnEnter)
				frame.Icon:SetScript("OnLeave", _G.GameTooltip_Hide)

				return frame
			end

			function EPB:UpdateFrame(event)
				local inPetBattle = C_PetBattles.IsInBattle()
				if not inPetBattle then
					return
				end

				local wildBattle = C_PetBattles.IsWildBattle()
				EPB.lastBattleWasWild = wildBattle
				local numPets = C_PetBattles.GetNumPets(self.petOwner)

				for i = 1, numPets do
					local pet = self.Pets[i]
					local customName, petName = C_PetBattles.GetName(self.petOwner, i)
					local xp, maxXP = C_PetBattles.GetXP(self.petOwner, i)
					local level, hp, maxHP, icon =
						C_PetBattles.GetLevel(self.petOwner, i),
						C_PetBattles.GetHealth(self.petOwner, i),
						C_PetBattles.GetMaxHealth(self.petOwner, i),
						C_PetBattles.GetIcon(self.petOwner, i)
					local speciesID, petType, power, speed, rarity =
						C_PetBattles.GetPetSpeciesID(self.petOwner, i),
						C_PetBattles.GetPetType(self.petOwner, i),
						C_PetBattles.GetPower(self.petOwner, i),
						C_PetBattles.GetSpeed(self.petOwner, i),
						C_PetBattles.GetBreedQuality(self.petOwner, i)

					if pet.OldPower == 0 then
						pet.OldPower = power
					end
					if pet.OldSpeed == 0 then
						pet.OldSpeed = speed
					end

					local r, g, b = GetItemQualityColor(rarity - 1)
					pet.Name:SetTextColor(r, g, b)
					pet.Name:SetText(customName or petName)
					pet.Level:SetText(level)
					pet.Icon:SetBackdropBorderColor(r, g, b)

					local displayID = C_PetBattles.GetDisplayID(pet.petOwner, pet.petIndex)

					if EPB.db["3DPortrait"] and pet.displayID ~= displayID then
						pet.Icon.PetModel:SetDisplayInfo(displayID)
						pet.Icon.PetModel:SetCamDistanceScale(0.6)
						pet.Icon.PetModel:Show()
						pet.Icon.PetTexture:Hide()
						pet.displayID = displayID
					elseif not EPB.db["3DPortrait"] then
						pet.Icon.PetTexture:SetTexture(icon)
						pet.Icon.PetTexture:Show()
						pet.Icon.PetModel:Hide()
					end

					pet.Icon.PetType:SetTexture(EPB.TexturePath .. _G.PET_TYPE_SUFFIX[petType])
					if level == 25 or self.petOwner == Enum_BattlePetOwner_Enemy then
						pet.Experience:SetMinMaxValues(0, 1)
						pet.Experience:SetValue(0)
						pet.Experience.Text:Hide()
					else
						pet.Experience:SetMinMaxValues(0, maxXP)
						pet.Experience:SetValue(xp)
						pet.Experience.Text:SetFormattedText("%s / %s", xp, maxXP)
						pet.Experience.Text:Show()
					end
					pet.Power:SetText(power)
					pet.Speed:SetText(speed)
					pet.Health:SetStatusBarColor(EPB.HealthColorGradient((hp / maxHP), 1, 0, 0, 1, 1, 0, 0, 1, 0))
					pet.Health:SetMinMaxValues(0, maxHP)
					pet.Health:SetValue(hp)
					pet.Health.Text:SetFormattedText("%s / %s", hp, maxHP)
					pet.Power:SetTextColor(
						unpack(
							power > pet.OldPower and EPB.Colors.Green
								or power < pet.OldPower and EPB.Colors.Red
								or EPB.Colors.White
						)
					)
					pet.Speed:SetTextColor(
						unpack(
							speed > pet.OldSpeed and EPB.Colors.Green
								or speed < pet.OldSpeed and EPB.Colors.Red
								or EPB.Colors.White
						)
					)

					--if _G.PetTracker then
					--	local breed = _G.PetTracker.Predict:Breed(speciesID, level, rarity, maxHP, power, speed)
					--	pet.BreedID:SetText(EPB.db["PetTrackerIcon"] and _G.PetTracker:GetBreedIcon(breed, .9) or _G.PetTracker:GetBreedName(breed))
					--else
					if BattlePetBreedID then
						pet.BreedID:SetText(_G.GetBreedID_Battle(pet))
					end

					pet.Icon.Dead:SetShown(hp == 0)

					pet.Icon.PetTexture:SetDesaturated(hp == 0)

					EPB:SetupAuras(pet, self.petOwner, i)

					if self.petOwner == Enum_BattlePetOwner_Enemy and wildBattle then
						local adjustedLevel = level
						if adjustedLevel > 20 then
							adjustedLevel = adjustedLevel - 2
						elseif adjustedLevel > 15 then
							adjustedLevel = adjustedLevel - 1
						end
						pet.TargetID, pet.Owned = speciesID, C_PetJournal.GetOwnedBattlePetString(speciesID)
						pet:SetBackdropBorderColor(unpack(pet.BorderColor))
						if pet.Owned == nil or pet.Owned == "Not Collected" then
							C_PetJournal.SetSearchFilter("")
							C_PetJournal.SetFilterChecked(_G.LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
							for j = 1, C_PetJournal.GetNumPets() do
								local _, species, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, obtainable =
									C_PetJournal.GetPetInfoByIndex(j)
								if obtainable and speciesID == species then
									pet:SetBackdropBorderColor(unpack(EPB.Colors.Red))
								end
							end
						else
							local ownedQuality, ownedLevel = EPB.GetHighestQuality(pet.TargetID)
							if rarity > ownedQuality then
								pet:SetBackdropBorderColor(unpack(EPB.Colors.Orange))
							elseif rarity >= ownedQuality and adjustedLevel > ownedLevel then
								pet:SetBackdropBorderColor(unpack(EPB.Colors.Yellow))
							end
						end
					else
						pet:SetBackdropBorderColor(unpack(EPB.Colors.Black))
					end

					if EPB.InSwitchMode and (pet.petOwner == Enum_BattlePetOwner_Ally) and hp > 0 then
						local _, class = _G.UnitClass("player")
						local c = _G.RAID_CLASS_COLORS[class]
						PA.Libs.LCG.PixelGlow_Start(pet, { c.r, c.g, c.b, 1 }, 8, -0.25, nil, 1)
					else
						PA.Libs.LCG.PixelGlow_Stop(pet)
					end

					pet:Show()
				end

				local activeAlly = C_PetBattles.GetActivePet(Enum_BattlePetOwner_Ally)
				local activeEnemy = C_PetBattles.GetActivePet(Enum_BattlePetOwner_Enemy)
				local allySpeed = C_PetBattles.GetSpeed(Enum_BattlePetOwner_Ally, activeAlly)
				local enemySpeed = C_PetBattles.GetSpeed(Enum_BattlePetOwner_Enemy, activeEnemy)

				EPB.Ally.Pets[activeAlly].Icon.Speed:SetVertexColor(
					unpack(allySpeed > enemySpeed and EPB.Colors.Green or EPB.Colors.Red)
				)
				EPB.Enemy.Pets[activeEnemy].Icon.Speed:SetVertexColor(
					unpack(allySpeed < enemySpeed and EPB.Colors.Green or EPB.Colors.Red)
				)
			end
		end
	end
end

function EPB:UpdateAuraHolder()
	if not EPB.db["HideBlizzard"] then
		return
	end
	if not (self.petOwner and self.petIndex) then
		return
	end
	local nextFrame = 1
	for _ = 1, C_PetBattles.GetNumAuras(self.petOwner, self.petIndex) do
		local frame = self.frames[nextFrame]
		if frame then
			frame:Hide()
			nextFrame = nextFrame + 1
		end
	end
end

function EPB:GetOptions()
	local EnhancedPetBattleUI = ACH:Group(EPB.Title, EPB.Description, nil, nil, function(info)
		return EPB.db[info[#info]]
	end, function(info, value)
		EPB.db[info[#info]] = value
		EPB:Update()
	end)
	PA.Options.args.EnhancedPetBattleUI = EnhancedPetBattleUI

	EnhancedPetBattleUI.args.Description = ACH:Description(EPB.Description, 0)
	EnhancedPetBattleUI.args.Enable = ACH:Toggle(ACL["Enable"], nil, 1, nil, nil, nil, nil, function(info, value)
		EPB.db[info[#info]] = value
		if not EPB.isEnabled then
			EPB:Initialize()
		else
			_G.StaticPopup_Show("PROJECTAZILROKA_RL")
		end
	end)

	EnhancedPetBattleUI.args.General = ACH:Group(ACL["General"], nil, 2)
	EnhancedPetBattleUI.args.General.inline = true
	EnhancedPetBattleUI.args.General.args.HideBlizzard =
		ACH:Toggle(ACL["Hide Blizzard"], ACL["Hide the Blizzard Pet Frames during battles"], 1)
	EnhancedPetBattleUI.args.General.args.GrowUp =
		ACH:Toggle(ACL["Grow the frames upwards"], ACL["Grow the frames from bottom for first pet upwards"], 2)
	EnhancedPetBattleUI.args.General.args.TeamAurasOnBottom = ACH:Toggle(
		ACL["Team Aura On Bottom"],
		ACL["Place team auras on the bottom of the last pet shown (or top if Grow upwards is selected)"],
		3
	)
	EnhancedPetBattleUI.args.General.args.PetTrackerIcon = ACH:Toggle(
		ACL["Use PetTracker Icon"],
		ACL["Use PetTracker Icon instead of Breed ID"],
		4,
		nil,
		nil,
		nil,
		nil,
		nil,
		function()
			return not C_AddOns.IsAddOnLoaded("PetTracker")
		end
	)
	EnhancedPetBattleUI.args.General.args.EnhanceTooltip = ACH:Toggle(
		ACL["Enhance Tooltip"],
		ACL["Add More Detailed Info if BreedInfo is available."],
		5,
		nil,
		nil,
		nil,
		nil,
		nil,
		function()
			return not BattlePetBreedID
		end
	)
	EnhancedPetBattleUI.args.General.args.LevelBreakdown = ACH:Toggle(
		ACL["Level Breakdown"],
		ACL["Add Pet Level Breakdown if BreedInfo is available."],
		6,
		nil,
		nil,
		nil,
		nil,
		nil,
		function()
			return not (EPB.db.EnhanceTooltip and BattlePetBreedID)
		end
	)
	EnhancedPetBattleUI.args.General.args.UseoUF = ACH:Toggle(
		ACL["Use oUF for the pet frames"],
		ACL["Use the new PBUF library by Nihilistzsche included with ProjectAzilroka to create new pet frames using the oUF unitframe template system."],
		7,
		nil,
		nil,
		nil,
		nil,
		function(info, value)
			EPB.db[info[#info]] = value
			_G.StaticPopup_Show("PROJECTAZILROKA_RL")
		end,
		function()
			return not PA.oUF
		end
	)
	EnhancedPetBattleUI.args.General.args["3DPortrait"] = ACH:Toggle(
		ACL["3D Portraits"],
		ACL["Use the 3D pet model instead of a texture for the pet icons"],
		8,
		nil,
		nil,
		nil,
		nil,
		nil,
		function()
			return EPB.db.UseoUF
		end
	)
	EnhancedPetBattleUI.args.General.args.healthThreshold = ACH:Range(
		ACL["Health Threshold"],
		ACL["When the current health of any pet in your journal is under this percentage after a trainer battle, show the revive bar."],
		9,
		{ min = 0, max = 1, step = 0.01, isPercent = true }
	)
	EnhancedPetBattleUI.args.General.args.wildHealthThreshold = ACH:Range(
		ACL["Wild Health Threshold"],
		ACL["When the current health of any pet in your journal is under this percentage after a wild pet battle, show the revive bar."],
		10,
		{ min = 0, max = 1, step = 0.01, isPercent = true }
	)
	EnhancedPetBattleUI.args.General.args.StatusBarTexture = ACH:SharedMediaStatusbar(ACL["StatusBar Texture"], nil, 13)
	EnhancedPetBattleUI.args.General.args.Font = ACH:SharedMediaFont(ACL["Font"], nil, 14)
	EnhancedPetBattleUI.args.General.args.FontSize =
		ACH:Range(ACL["Font Size"], nil, 15, { min = 8, max = 24, step = 1 })
	EnhancedPetBattleUI.args.General.args.FontFlag = ACH:FontFlags(ACL["Font Flag"], nil, 16)
	EnhancedPetBattleUI.args.General.args.TextOffset =
		ACH:Range(ACL["Health/Experience Text Offset"], nil, 17, { min = -10, max = 10, step = 1 })
	EnhancedPetBattleUI.args.General.args.nameFormat = ACH:Input(
		ACL["Name Format"],
		nil,
		18,
		nil,
		"full",
		nil,
		nil,
		nil,
		function()
			return not EPB.db.UseoUF
		end
	)
	EnhancedPetBattleUI.args.General.args.healthFormat = ACH:Input(
		ACL["Health Format"],
		nil,
		19,
		nil,
		"full",
		nil,
		nil,
		nil,
		function()
			return not EPB.db.UseoUF
		end
	)
	EnhancedPetBattleUI.args.General.args.xpFormat = ACH:Input(
		ACL["Experience Format"],
		nil,
		20,
		nil,
		"full",
		nil,
		nil,
		nil,
		function()
			return not EPB.db.UseoUF
		end
	)
	EnhancedPetBattleUI.args.General.args.powerFormat = ACH:Input(
		ACL["Power Format"],
		nil,
		21,
		nil,
		"full",
		nil,
		nil,
		nil,
		function()
			return not EPB.db.UseoUF
		end
	)
	EnhancedPetBattleUI.args.General.args.speedFormat = ACH:Input(
		ACL["Speed Format"],
		nil,
		22,
		nil,
		"full",
		nil,
		nil,
		nil,
		function()
			return not EPB.db.UseoUF
		end
	)
	EnhancedPetBattleUI.args.General.args.breedAllyFormat = ACH:Input(
		ACL["Breed Format (Ally Team)"],
		nil,
		23,
		nil,
		"full",
		nil,
		nil,
		nil,
		function()
			return not EPB.db.UseoUF or not BattlePetBreedID
		end
	)
	EnhancedPetBattleUI.args.General.args.breedEnemyFormat = ACH:Input(
		ACL["Breed Format (Enemy Team)"],
		nil,
		24,
		nil,
		"full",
		nil,
		nil,
		nil,
		function()
			return not EPB.db.UseoUF or not BattlePetBreedID
		end
	)
end

function EPB:BuildProfile()
	PA.Defaults.profile.EnhancedPetBattleUI = {
		Enable = false,
		AlwaysShow = false,
		HideBlizzard = false,
		GrowUp = false,
		StatusBarTexture = "Blizzard Raid Bar",
		Font = "Arial Narrow",
		FontSize = 12,
		FontFlag = "OUTLINE",
		TextOffset = 2,
		EnhanceTooltip = true,
		LevelBreakdown = true,
		PetTrackerIcon = true,
		TeamAurasOnBottom = true,
		ShowNameplates = true,
		BreedIDOnNameplate = true,
		["3DPortrait"] = true,
		UseoUF = PA.oUF ~= nil,
		nameFormat = "[pbuf:qualitycolor][pbuf:smartlevel] [pbuf:name]",
		healthFormat = "[pbuf:health:current-percent]",
		xpFormat = "[pbuf:xp:current-max-percent]",
		powerFormat = "[pbuf:power:comparecolor][pbuf:power]",
		speedFormat = "[pbuf:speed:comparecolor][pbuf:speed]",
		breedAllyFormat = "[pbuf:breed][pbuf:breedicon]",
		breedEnemyFormat = "[pbuf:breedicon][pbuf:breed]",
		healthThreshold = 0.85,
		wildHealthThreshold = 0.65,
	}

	if PA.Tukui then
		PA.Defaults.profile.EnhancedPetBattleUI.StatusBarTexture = "Tukui"
		PA.Defaults.profile.EnhancedPetBattleUI.Font = "Tukui Pixel"
		PA.Defaults.profile.EnhancedPetBattleUI.FontFlag = "MONOCHROMEOUTLINE"
	elseif PA.ElvUI then
		PA.Defaults.profile.EnhancedPetBattleUI.StatusBarTexture = _G.ElvUI[1].private.general.normTex
		PA.Defaults.profile.EnhancedPetBattleUI.Font = _G.ElvUI[1].db.general.font
		PA.Defaults.profile.EnhancedPetBattleUI.FontFlag = "OUTLINE"
	end
end

EPB.BattlePetChallengeDebuffID = 143999

function EPB:InitHealingForbiddenCheck()
	EPB.BattlePetChallengeDebuffName = C_Spell_GetSpellName(EPB.BattlePetChallengeDebuffID)
end

function EPB:IsHealingForbidden()
	return AuraUtil_FindAuraByName(EPB.BattlePetChallengeDebuffName, "player", "HARMFUL") ~= nil
end

function EPB:SetHealthThresholdOverride(value)
	self.healthThresholdOverride = value
end

function EPB:ClearHealthThresholdOverride()
	self.healthThresholdOverride = nil
end

function EPB:GetHealthThresholdOverride()
	return self.healthThresholdOverride
end

function EPB:BlockHealing()
	self.healingBlocked = true
end

function EPB:UnblockHealing()
	self.healingBlocked = nil
end

function EPB:IsHealingBlocked()
	return self.healingBlocked
end

function EPB:CheckReviveBarVisibility()
	if EPB:IsHealingBlocked() or EPB:IsHealingForbidden() or UnitHealth("player") == 0 then
		if UnitHealth("player") == 0 then
			EPB:RegisterEvent("UNIT_HEALTH")
		end
		return false
	end

	local health, maxHealth, show, checkPercentage
	checkPercentage = EPB:GetHealthThresholdOverride() or EPB.db.healthThreshold
	if EPB.lastBattleWasWild then
		checkPercentage = EPB.db.wildHealthThreshold
	end
	for i = 1, C_PetJournal.GetNumPets() do
		local petID = C_PetJournal.GetPetInfoByIndex(i)
		if petID ~= nil then
			health, maxHealth = C_PetJournal.GetPetStats(petID)
			if health and maxHealth and health < (maxHealth * checkPercentage) then
				show = true
				break
			end
		end
	end

	return show
end

function EPB:CreateReviveBar()
	local holder = CreateFrame("frame", nil, UIParent)
	holder:SetSize(104, 50)
	holder:SetFrameStrata("BACKGROUND")
	holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	PA:SetTemplate(holder)
	PA:CreateShadow(holder)

	holder.buttons = {}

	if PA.ElvUI then
		_G.ElvUI[1]:CreateMover(
			holder,
			"PetBattleUIExtraActionButtonAnchor",
			"PetBattleUI ExtraAction",
			nil,
			nil,
			nil,
			"ALL,SOLO"
		)
	end

	return holder
end

function EPB:PLAYER_REGEN_ENABLED()
	self:UpdateReviveBar()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

function EPB:UNIT_HEALTH()
	if UnitHealth("player") > 0 then
		self:UpdateReviveBar()
		self:UnregisterEvent("UNIT_HEALTH")
	end
end

function EPB:UpdateReviveBar()
	if InCombatLockdown() then
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end

	_G.RegisterStateDriver(
		self.holder,
		"visibility",
		self:CheckReviveBarVisibility() and "[petbattle][combat] hide; show" or "hide"
	)
end

function EPB:CreateExtraActionButton(name)
	local Color = _G.RAID_CLASS_COLORS[select(2, _G.UnitClass("player"))]

	local Button = CreateFrame(
		"Button",
		"EPB" .. name .. "Button",
		self.holder,
		"ActionButtonTemplate, SecureActionButtonTemplate"
	)
	Button:SetMouseClickEnabled(true)
	Button:RegisterForClicks("AnyUp", "AnyDown")
	Button:SetSize(50, 50)
	PA:SetTemplate(Button)
	Button.BorderColor = { Button:GetBackdropBorderColor() }
	Button.icon:SetDrawLayer("ARTWORK")
	Button.icon:SetTexture("")
	PA:SetInside(Button.icon)
	Button.icon:SetTexCoord(PA:TexCoords())
	Button:SetNormalTexture("")
	Button:SetPushedTexture("")
	Button:SetHighlightTexture("")
	Button.cooldown = CreateFrame("Cooldown", nil, Button, "CooldownFrameTemplate")
	PA:SetInside(Button.cooldown)
	Button.cooldown:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	Button.cooldown:SetScript("OnEvent", function(_self)
		if Button.ID then
			local cdInfo = C_Spell_GetSpellCooldown(Button.ID)
			if cdInfo.duration and cdInfo.duration > 1.5 then
				_self:SetCooldown(cdInfo.startTime, cdInfo.duration)
			end
		end
	end)

	PA:RegisterCooldown(Button.cooldown)

	Button:SetScript("OnEnter", function(_self)
		_self:SetBackdropBorderColor(Color.r, Color.g, Color.b)
		GameTooltip:SetOwner(_self, "ANCHOR_TOPRIGHT", 2, 4)
		GameTooltip:ClearLines()
		if _self.HyperLink then
			GameTooltip:SetHyperlink(_self.HyperLink)
		end
		GameTooltip:Show()
	end)
	Button:SetScript("OnLeave", function(_self)
		_self:SetBackdropBorderColor(unpack(_self.BorderColor))
		GameTooltip:Hide()
	end)

	Button:Show()

	return Button
end

EPB.ReviveButtonCache = {}

function EPB:CreateReviveButton()
	local Revive = self:CreateExtraActionButton("Revive")
	Revive:SetPoint("LEFT", self.holder, "LEFT", 0, 0)
	Revive:SetAttribute("type", "spell")
	Revive.ID = 125439
	Revive:SetAttribute("spell", C_Spell_GetSpellName(Revive.ID))
	Revive.HyperLink = C_Spell_GetSpellLink(Revive.ID)
	Revive.icon:SetTexture(C_Spell_GetSpellTexture(Revive.ID))
	return Revive
end

function EPB:UpdateBandageButton(button)
	local Count = C_Item_GetItemCount(button.ID)
	button.Count:SetText(Count > 0 and Count or "")
	button.icon:SetDesaturated(Count == 0 and true or false)
end

function EPB:CreateBandageButton()
	local Bandage = self:CreateExtraActionButton("Bandage")
	Bandage:SetPoint("RIGHT", self.holder, "RIGHT", 0, 0)
	Bandage:SetAttribute("type", "item")
	Bandage.ID = 86143
	local _, _, _, _, icon = C_Item_GetItemInfoInstant(Bandage.ID)
	Bandage.icon:SetTexture(icon)
	Bandage:SetScript("OnShow", function(_self)
		self:UpdateBandageButton(_self)
	end)
	Item:CreateFromItemID(Bandage.ID):ContinueOnItemLoad(function()
		local itemName, itemLink = C_Item_GetItemInfo(Bandage.ID)
		if Bandage:GetAttribute("item") ~= itemName then
			Bandage:SetAttribute("item", itemName)
		end
		Bandage.HyperLink = itemLink
	end)
	return Bandage
end

function EPB:Update()
	local point, relativePoint, xcoord, ycoord

	local spacing = 4
	if EPB.db.UseoUF and PA.oUF then
		spacing = 56
	end

	if self.db["GrowUp"] then
		point, relativePoint, xcoord, ycoord = "BOTTOM", "TOP", 0, spacing
	else
		point, relativePoint, xcoord, ycoord = "TOP", "BOTTOM", 0, -spacing
	end

	for _, frame in pairs({ self.Ally, self.Enemy }) do
		for i = 1, 3 do
			frame.Pets[i]:ClearAllPoints()

			if i == 1 then
				frame.Pets[i]:SetPoint(point, frame, point, 0, 0)
			else
				frame.Pets[i]:SetPoint(point, frame.Pets[i - 1], relativePoint, xcoord, ycoord)
			end

			self:UpdatePetFrame(frame.Pets[i])
		end
		if EPB.db.UseoUF and PA.oUF then
			self:UpdatePetFrameAnchors(frame.Pets.team)
		end
	end
end

function EPB:DebugPrint(...)
	if self.Debug then
		print(...)
	end
end

function EPB:GetLevelBreakdown(petID)
	if not BreedData then
		return
	end

	if not petID or petID == "0x0000000000000000" then
		return 0, 10, 0
	end

	local speciesID, _, level, _, _, _, _, _, _, _, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByPetID(petID)

	if not canBattle then
		return 0, 10, 0
	end
	local health, _, power, speed, rarity = C_PetJournal.GetPetStats(petID)

	local baseStats = BreedData.speciesToBaseStatProfile[speciesID]

	if not baseStats then
		return false
	end

	local breedBonusPerLevel = {
		clamp(
			round((((health - 100) / 5) / BreedData.qualityMultiplier[rarity]) - level * baseStats[1], 1) / level,
			0,
			2
		),
		clamp(round((power / BreedData.qualityMultiplier[rarity]) - level * baseStats[2], 1) / level, 0, 2),
		clamp(round((speed / BreedData.qualityMultiplier[rarity]) - level * baseStats[3], 1) / level, 0, 2),
	}

	return breedBonusPerLevel
end

function EPB.GetHighestQuality(enemySpeciesID)
	local maxQuality, bestLevel = 0, 0
	for i = 1, C_PetJournal.GetNumPets() do
		local petID, speciesID, _, _, level = C_PetJournal.GetPetInfoByIndex(i, true)
		if petID and speciesID == enemySpeciesID then
			local quality = select(5, C_PetJournal.GetPetStats(petID))
			if quality then
				if maxQuality < quality then
					maxQuality = quality
				end
				if bestLevel < level then
					bestLevel = level
				end
			end
		end
	end
	return maxQuality, bestLevel
end

function EPB.HealthColorGradient(perc, ...)
	if perc >= 1 then
		return select(select("#", ...) - 2, ...)
	elseif perc <= 0 then
		return ...
	end

	local num = select("#", ...) / 3
	local segment, relperc = math.modf(perc * (num - 1))
	local r1, g1, b1, r2, g2, b2 = select((segment * 3) + 1, ...)

	return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
end

function EPB:UpdateTDBattlePetScriptAutoButton()
	_G.tdBattlePetScriptAutoButton:SetParent(self.Ally)
	_G.tdBattlePetScriptAutoButton:ClearAllPoints()
	_G.tdBattlePetScriptAutoButton:SetPoint("TOP", self.Ally, "BOTTOM", 0, -40)
	_G.tdBattlePetScriptAutoButton:Hide()
	_G.tdBattlePetScriptAutoButton:Show()

	if PA.ElvUI then
		_G.ElvUI[1]:CreateMover(
			_G.tdBattlePetScriptAutoButton,
			"tdBattlePetScriptAutoButtonMover",
			"tdBattlePetScript Auto Button",
			nil,
			nil,
			nil,
			"ALL,GENERAL,SOLO"
		)
	elseif PA.Tukui then
		_G.Tukui[1]["Movers"]:RegisterFrame(_G.tdBattlePetScriptAutoButton)
	end
end

function EPB:EnableMover(frame, petOwner)
	if PA.ElvUI then
		local isFriend = petOwner == Enum_BattlePetOwner_Ally
		_G.ElvUI[1]:CreateMover(
			frame,
			isFriend and "BattlePetMover" or "EnemyBattlePetMover",
			isFriend and "Battle Pet Frames" or "Enemy Battle Pet Frames",
			nil,
			nil,
			nil,
			"ALL,SOLO"
		)
	elseif PA.Tukui then
		_G.Tukui[1]["Movers"]:RegisterFrame(frame)
	end
end

function EPB:UpdateSettings()
	EPB.db = PA.db.EnhancedPetBattleUI
end

function EPB:Initialize()
	if EPB.db.Enable ~= true then
		return
	end

	EPB.isEnabled = true

	BattlePetBreedID = C_AddOns_IsAddOnLoaded("BattlePetBreedID")
	BreedInfo = LibStub("LibPetBreedInfo-1.0", true)

	EPB:InitHealingForbiddenCheck()

	EPB:InitPetFrameAPI()
	EPB:CreateFrames()

	if BreedInfo then
		BreedData = BreedInfo.breedData
	end

	EPB:Update()

	_G.hooksecurefunc("PetBattleAuraHolder_Update", EPB.UpdateAuraHolder)

	_G.PetBattleFrame:HookScript("OnEvent", EPB.HideBlizzard)

	EPB.holder = EPB:CreateReviveBar()
	EPB.holder.ReviveButton = EPB:CreateReviveButton()
	EPB.holder.BandageButton = EPB:CreateBandageButton()

	EPB:UpdateReviveBar()
	EPB:RegisterEvent("BAG_UPDATE", "UpdateReviveBar")
	EPB:RegisterEvent("PET_JOURNAL_LIST_UPDATE", "UpdateReviveBar")
	EPB:RegisterEvent("PET_BATTLE_CLOSE", "UpdateReviveBar")

	if not _G.PetTracker_Sets or _G.PetTracker_Sets.switcher == false then
		_G.PetBattlePetSelectionFrame_Show = function()
			_G.PetBattleFrame_UpdateActionBarLayout(_G.PetBattleFrame)
			EPB:ChangePetBattlePetSelectionFrameState(true)
		end

		_G.PetBattlePetSelectionFrame_Hide = function()
			EPB:ChangePetBattlePetSelectionFrameState(false)
		end
	end

	pcall(C_AddOns_LoadAddOn, "tdBattlePetScript")
	if C_AddOns_IsAddOnLoaded("tdBattlePetScript") then
		EPB:UpdateTDBattlePetScriptAutoButton()
	end
end

local PA = _G.ProjectAzilroka
if PA.ElvUI then return end

local MAJOR, MINOR = "LibElvUIPlugin-1.0", 14
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

--Cache global variables
--Lua functions
local pairs, tonumber = pairs, tonumber
local format, strsplit, gsub = format, strsplit, gsub
--WoW API / Variables
local CreateFrame = CreateFrame
local IsInGroup, IsInRaid = IsInGroup, IsInRaid
local GetAddOnMetadata = GetAddOnMetadata
local C_Timer = C_Timer
local RegisterAddonMessagePrefix = RegisterAddonMessagePrefix
local SendAddonMessage = SendAddonMessage
local LE_PARTY_CATEGORY_HOME = LE_PARTY_CATEGORY_HOME
local LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE

lib.plugins = {}
lib.index = 0
lib.prefix = "ElvUIPluginVC"

-- MULTI Language Support (Default Language: English)
local MSG_OUTDATED = "Your version of %s is out of date (latest is version %s). You can download the latest version from http://www.tukui.org"
local HDR_CONFIG = "Plugins"
local HDR_INFORMATION = "LibElvUIPlugin-1.0.%d - Plugins Loaded  (Green means you have current version, Red means out of date)"
local INFO_BY = "by"
local INFO_VERSION = "Version:"
local INFO_NEW = "Newest:"
local LIBRARY = "Library"

if GetLocale() == "deDE" then -- German Translation
	MSG_OUTDATED = "Deine Version von %s ist veraltet (akutelle Version ist %s). Du kannst die aktuelle Version von http://www.tukui.org herunterrladen."
	HDR_CONFIG = "Plugins"
	HDR_INFORMATION = "LibElvUIPlugin-1.0.%d - Plugins geladen (Grün bedeutet du hast die aktuelle Version, Rot bedeutet es ist veraltet)"
	INFO_BY = "von"
	INFO_VERSION = "Version:"
	INFO_NEW = "Neuste:"
	LIBRARY = "Bibliothek"
end

if GetLocale() == "ruRU" then -- Russian Translations
	MSG_OUTDATED = "Ваша версия %s устарела (последняя версия %s). Вы можете скачать последнюю версию на http://www.tukui.org"
	HDR_CONFIG = "Плагины"
	HDR_INFORMATION = "LibElvUIPlugin-1.0.%d - загруженные плагины (зеленый означает, что у вас последняя версия, красный - устаревшая)"
	INFO_BY = "от"
	INFO_VERSION = "Версия:"
	INFO_NEW = "Последняя:"
	LIBRARY = "Библиотека"
end

local function RGBToHex(r, g, b)
    r = r <= 1 and r >= 0 and r or 0
    g = g <= 1 and g >= 0 and g or 0
    b = b <= 1 and b >= 0 and b or 0

    return format('|cff%02x%02x%02x', r*255, g*255, b*255)
end

function lib:RegisterPlugin(name,callback)
	local plugin = {}
	plugin.name = name
	plugin.version = name == MAJOR and MINOR or GetAddOnMetadata(name, "Version")
	plugin.callback = callback
	lib.plugins[name] = plugin
	if not lib.vcframe then
		RegisterAddonMessagePrefix(lib.prefix)
		local f = CreateFrame('Frame')
		f:RegisterEvent("GROUP_ROSTER_UPDATE")
		f:RegisterEvent("CHAT_MSG_ADDON")
		f:SetScript('OnEvent', lib.VersionCheck)
		lib.vcframe = f
	end

	if not lib.ConfigFrame then
		local configFrame = CreateFrame("Frame")
		configFrame:RegisterEvent("ADDON_LOADED")
		configFrame:SetScript("OnEvent", function(self,event,addon)
			if addon == "Enhanced_Config" then
				for _, plugin in pairs(lib.plugins) do
					if plugin.callback then
						plugin.callback()
					end
				end
			end
		end)
		lib.ConfigFrame = configFrame
	else
		-- Need to update plugins list
		if name ~= MAJOR then
			self:GetPluginOptions()
			_G.Enhanced_Config.Options.args.plugins.args.plugins.name = lib:GeneratePluginList()
		end
		callback()
	end

	return plugin
end

function lib:GetPluginOptions()
	_G.Enhanced_Config.Options.args.plugins = {
        order = -10,
        type = "group",
        name = HDR_CONFIG,
        guiInline = false,
        args = {
            pluginheader = {
                order = 1,
                type = "header",
                name = format(HDR_INFORMATION, MINOR),
            },
            plugins = {
                order = 2,
                type = "description",
                name = lib:GeneratePluginList(),
            },
        }
    }
end

function lib:GenerateVersionCheckMessage()
	local list = ""
	for _, plugin in pairs(lib.plugins) do
		if plugin.name ~= MAJOR then
			list = list..plugin.name.."="..plugin.version..";"
		end
	end
	return list
end

local function SendPluginVersionCheck(self)
	lib:SendPluginVersionCheck(lib:GenerateVersionCheckMessage())
end

function lib:VersionCheck(event, prefix, message, channel, sender)
	if (event == "CHAT_MSG_ADDON") and sender and message and (message ~= "") and (prefix == lib.prefix) then
		local myRealm = gsub(PA.MyRealm,'[%s%-]','')
		local myName = PA.MyName..'-'..myRealm
		if sender == myName then return end
		if not self["pluginRecievedOutOfDateMessage"] then
			for _, p in pairs({strsplit(";",message)}) do
				if not p:match("^%s-$") then
					local name, version = p:match("([%w_]+)=([%d%p]+)")
					if lib.plugins[name] then
						local plugin = lib.plugins[name]
						if plugin.version ~= 'BETA' and version ~= nil and tonumber(version) ~= nil and plugin.version ~= nil and tonumber(plugin.version) ~= nil and tonumber(version) > tonumber(plugin.version) then
							plugin.old = true
							plugin.newversion = tonumber(version)
							local Pname = GetAddOnMetadata(plugin.name, "Title")
							print(format(MSG_OUTDATED,Pname,plugin.newversion))
							self["pluginRecievedOutOfDateMessage"] = true
						end
					end
				end
			end
		end
	else
		C_Timer.After(2, SendPluginVersionCheck)
	end
end

function lib:GeneratePluginList()
	local list = ""
	for _, plugin in pairs(lib.plugins) do
		if plugin.name ~= MAJOR then
			local author = GetAddOnMetadata(plugin.name, "Author")
			local Pname = GetAddOnMetadata(plugin.name, "Title") or plugin.name
			local color = plugin.old and RGBToHex(1,0,0) or RGBToHex(0,1,0)
			list = list .. Pname
			if author then
			  list = list .. " ".. INFO_BY .." " .. author
			end
			list = list .. color ..(plugin.isLib and " "..LIBRARY or " - " .. INFO_VERSION .." " .. plugin.version)
			if plugin.old then
			  list = list .. INFO_NEW .. plugin.newversion .. ")"
			end
			list = list .. "|r\n"
		end
	end
	return list
end

function lib:SendPluginVersionCheck(message)
	if not message or (message == "") then return end
	local plist = {strsplit(";",message)}
	local m = ""
	local delay = 1
	local ChatType = ((not IsInRaid(LE_PARTY_CATEGORY_HOME) and IsInRaid(LE_PARTY_CATEGORY_INSTANCE)) or (not IsInGroup(LE_PARTY_CATEGORY_HOME) and IsInGroup(LE_PARTY_CATEGORY_INSTANCE))) and "INSTANCE_CHAT" or (IsInRaid() and "RAID") or (IsInGroup() and "PARTY") or nil
	for _, p in pairs(plist) do
		if not p:match("^%s-$") then
			if(#(m .. p .. ";") < 230) then
				m = m .. p .. ";"
			else
				if ChatType then
					C_Timer.After(delay, function() SendAddonMessage(lib.prefix, m, ChatType) end)
				end
				m = p .. ";"
				delay = delay + 1
			end
		end
	end
	if m == "" then return end
	-- Send the last message
	if ChatType then
		C_Timer.After(delay, function() SendAddonMessage(lib.prefix, m, ChatType) end)
	end
end

lib:RegisterPlugin(MAJOR, lib.GetPluginOptions)
local addonName = ...
local languagesLabel = LANGUAGES_LABEL or "Languages"
local SEARCH_TIMEOUT = 10
local searchDeadline = 0

local fallbackNames = {
	deDE = "German",
	enUS = "English",
	esES = "Spanish (EU)",
	esMX = "Spanish (Latin American)",
	frFR = "French",
	itIT = "Italian",
	koKR = "Korean",
	ptBR = "Portuguese",
	ruRU = "Russian",
	zhCN = "Chinese (Simplified)",
	zhTW = "Chinese (Traditional)",
}

local function GetLanguageName(code)
	local key = code:upper()
	return _G["LFG_LIST_LANGUAGE_" .. key] or _G["LOCALE_DISPLAY_NAME_" .. key]
		or fallbackNames[code] or code
end

local function GetLanguages()
	local languages, seen = {}, {}
	local offered = C_LFGList.GetAvailableLanguageSearchFilter()
	if type(offered) ~= "table" then
		return languages, false
	end
	local defaults = C_LFGList.GetDefaultLanguageSearchFilter()
	if type(defaults) ~= "table" then
		defaults = {}
	end
	local clientLocale = GetLocale()
	local hasChoice = false
	for _, code in ipairs(offered) do
		if type(code) == "string" and not seen[code] then
			seen[code] = true
			local locked = code == clientLocale or defaults[code] == true
			languages[#languages + 1] = { code = code, name = GetLanguageName(code), locked = locked }
			hasChoice = hasChoice or not locked
		end
	end
	return languages, hasChoice
end

local function GetSearchCategory(browse)
	if browse:IsVisible() and not browse.searching and GetTime() >= searchDeadline then
		local categoryID = browse.CategoryDropdown:GetValue()
		if categoryID > 0 then
			return categoryID
		end
	end
end

local function GetLanguageFilter()
	local languages = GetLanguages()
	local selected = LFGLanguagesForeverDB
	local filter, hasExtraLanguage = {}, false
	for _, language in ipairs(languages) do
		if language.locked or selected[language.code] == true then
			filter[language.code] = true
			hasExtraLanguage = hasExtraLanguage or not language.locked
		end
	end
	return hasExtraLanguage and filter or nil
end

local function StartSearch(browse)
	local categoryID = GetSearchCategory(browse)
	if not categoryID then
		return false
	end

	local activityIDs = browse.ActivityDropdown.selectedValues
	if #activityIDs == 0 then
		activityIDs = LFGUtil_GetFilteredActivities(categoryID)
	end

	-- Call Search within the click handler. Forever can block a deferred call.
	-- Blizzard's results events redraw Browse.
	searchDeadline = GetTime() + SEARCH_TIMEOUT
	C_LFGList.Search(categoryID, 0, 0, GetLanguageFilter(), false, nil, activityIDs)
	return true
end

local function AddLanguagesMenu(owner, root)
	local browse = LFGBrowseFrame
	if not browse or owner ~= browse.OptionsButton then
		return
	end

	local languages, hasChoice = GetLanguages()
	local selected = LFGLanguagesForeverDB
	root:CreateDivider()
	local menu = root:CreateButton(languagesLabel)
	if #languages == 0 then
		menu:SetEnabled(false)
		menu:SetTitleAndTextTooltip(languagesLabel, "No additional search languages are available.")
		return
	end

	local function SetAll(value)
		for _, language in ipairs(languages) do
			if not language.locked then
				selected[language.code] = value or nil
			end
		end
		return MenuResponse.Refresh
	end

	if hasChoice then
		menu:CreateButton(SELECT_ALL or "Select all", SetAll, true)
		menu:CreateButton(UNSELECT_ALL or "Unselect all", SetAll, false)
		menu:CreateDivider()
	end

	table.sort(languages, function(a, b)
		if a.locked ~= b.locked then
			return a.locked
		end
		return strcmputf8i(a.name, b.name) < 0
	end)
	local function IsSelected(language)
		return language.locked or selected[language.code] == true
	end
	local function Toggle(language)
		if not language.locked then
			selected[language.code] = not IsSelected(language) or nil
		end
	end
	for _, language in ipairs(languages) do
		local checkbox = menu:CreateCheckbox(language.name, IsSelected, Toggle, language)
		if language.locked then
			checkbox:SetEnabled(false)
			checkbox:SetTitleAndTextTooltip(language.name, "Your game's language is always included in the search.")
		end
	end

	menu:CreateDivider()
	local search = menu:CreateButton(SEARCH or "Search", function()
		if StartSearch(browse) then
			return MenuResponse.CloseAll
		end
		return MenuResponse.Refresh
	end)
	search:SetEnabled(function()
		return GetSearchCategory(browse) ~= nil
	end)
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	if not (C_LFGList and C_LFGList.GetAvailableLanguageSearchFilter and C_LFGList.GetDefaultLanguageSearchFilter) then
		return
	end
	if type(LFGLanguagesForeverDB) ~= "table" then
		LFGLanguagesForeverDB = {}
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
	events:RegisterEvent("LFG_LIST_SEARCH_FAILED")
	events:RegisterEvent("ADDON_ACTION_BLOCKED")
	events:SetScript("OnEvent", function(_, event, source, action)
		if event == "ADDON_ACTION_BLOCKED" and (source ~= addonName or action ~= "Search()") then
			return
		end
		searchDeadline = 0
	end)
	Menu.ModifyMenu("MENU_LFG_LISTING_SETTINGS", AddLanguagesMenu)

	EventUtil.ContinueOnAddOnLoaded("Blizzard_GroupFinder_VanillaStyle", function()
		local browse = LFGBrowseFrame
		if not browse or not browse.RefreshButton then
			return
		end

		browse.RefreshButton:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			StartSearch(browse)
		end)
	end)
end)

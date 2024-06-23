local GUI = require("GUI")
local system = require("System")
local paths = require("Paths")
local filesystem = require("Filesystem")
local screen = require("Screen")

--------------------------------------------------------------------------------- Wallpaper panel object

local function wallpaperPanelDraw(panel)
	-- Fill background
	screen.drawRectangle(panel.x, panel.y, panel.width, panel.height, 0x161616, 0, " ")

	-- Display message if needed
	if panel.messageLines then
		local x0 = panel.x + math.floor(panel.width  / 2 -  panel.messageMaxLen / 2)
		local y0 = panel.y + math.floor(panel.height / 2 - #panel.messageLines  / 2)

		for i, line in pairs(panel.messageLines) do
			screen.drawText(x0, y0 + i, panel.colors.text, line)
		end
	end
end

local function wallpaperPanelSetMessage(panel, message)
	if not message then
		panel.messageLines = nil
		return
	end

	panel.messageLines, panel.messageMaxLen = {}, 0

	for line in message:gsub("\t", "    "):gmatch("[^\r\n]+") do
		table.insert(panel.messageLines, line)
		panel.messageMaxLen = math.max(panel.messageMaxLen, #line)
	end
end

local function wallpaperPanelNew(x, y, width, height, backgroundColor, textColor)
	local panel = GUI.panel(x, y, width, height, backgroundColor)
	panel.colors.text = textColor
	panel.draw = wallpaperPanelDraw
	panel.setMessage = wallpaperPanelSetMessage

	return panel
end

---------------------------------------------------------------------------------

local window = GUI.window(1, 1, 100, 30, 0xE1E1E1)
window.actionButtons = window:addChild(GUI.actionButtons(4, 2, true))

local workspace, window, menu = system.addWindow(window)
window.wallpaperPanel = window:addChild(wallpaperPanelNew(1, 1, 1, 1, 0x161616, 0xD2D2D2))

-- Left panel & layout
local leftPanel = system.addBlurredOrDefaultPanel(window, 1, 1, 30, 1)
window.wallpaperPanel.localX = leftPanel.width + 1

local layout = window:addChild(GUI.layout(1, 4, leftPanel.width, 1, 1, 1))
layout:setFitting(1, 1, true, false, 2, 0)
layout:setAlignment(1, 1, GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP)

window.actionButtons:moveToFront()

window.onResize = function(width, height)
	leftPanel.height = height
	layout.height = height
	window.wallpaperPanel.width, window.wallpaperPanel.height = width - leftPanel.width, height
end

---------------------------------------------------------------------------------

local configureFrom, configureTo

local function configure()
	-- Remove previously added controls from layout
	if configureFrom then
		layout:removeChildren(configureFrom, configureTo)
		configureFrom, configureTo = nil, nil
	end

	-- Add new controls if needed
	if window.wallpaperPanel.configure then
		configureFrom = #layout.children + 1
		window.wallpaperPanel.configure(layout)
		configureTo = #layout.children
	end
end

---------------------------------------------------------------------------------

-- Wallpaper selector & reload button
local selectorLayout = layout:addChild(GUI.layout(1, 1, layout.width, 3, 1, 1))
selectorLayout:setDirection(1, 1, GUI.DIRECTION_HORIZONTAL)

local comboBox = selectorLayout:addChild(GUI.comboBox(1, 1, selectorLayout.width - 8, 3, 0x323232, 0xD2D2D2, 0x323232, 0xA5A5A5))
local reloadButton = selectorLayout:addChild(GUI.button(1, 1, 6, 3, 0x323232, 0xD2D2D2, 0x323232, 0xA5A5A5, "🗘"))

-- Parsing /Wallpapers directory and adding each .wlp into the combobox
local files = filesystem.list(paths.system.wallpapers)
for i = 1, #files do
	local file = files[i]
	local path = paths.system.wallpapers .. file
	
	if filesystem.isDirectory(path) and filesystem.extension(path) == ".wlp" then
		comboBox:addItem(filesystem.hideExtension(file))
	end
end

local fpsLabel

-- Loading selected wallpaper
comboBox.onItemSelected = function(index)
	-- Resetting wallpaper panel that will be used as wallpaper render target
	window.wallpaperPanel.draw = wallpaperPanelDraw
	window.wallpaperPanel.eventHandler = nil
	window.wallpaperPanel.configure = nil

	window:resize(window.width, window.height)

	local result, reason = loadfile(paths.system.wallpapers .. files[index] .. "Main.lua")
	if not result then
		window.wallpaperPanel:setMessage("Unable to load wallpaper:\n \n" .. reason)
		return
	end

	result, reason = xpcall(result, debug.traceback, workspace, window.wallpaperPanel)
	if not result then
		window.wallpaperPanel:setMessage("Unable to execute wallpaper:\n \n" .. reason)
		return
	end

	local renderTimeSum, frameCount = 0, 0
	fpsLabel.text = "FPS: N/A"
	
	-- Hooking panel drawing function
	local oldDraw = window.wallpaperPanel.draw

	window.wallpaperPanel.draw = function(...)
		local startTime = computer.uptime()

		-- Trying to render wallpaper
		local result, reason = xpcall(oldDraw, debug.traceback, ...)

		-- Saving error message and leaving
		if not result then
			window.wallpaperPanel:setMessage("Wallpaper runtime error:\n \n" .. reason)
			window.wallpaperPanel.draw = wallpaperPanelDraw

			return
		end

		-- Calculating fps
		renderTimeSum = renderTimeSum + computer.uptime() - startTime
		frameCount = frameCount + 1

		if frameCount > 20 then
			fpsLabel.text = "FPS: " .. math.floor(1.0 / (renderTimeSum / frameCount))
			frameCount = 0
		end
	end

	configure()
end

reloadButton.onTouch = function(button)
	comboBox.onItemSelected(comboBox.selectedItem)
end

-- Fps meter
fpsLabel = layout:addChild(GUI.label(1, 1, 1, 1, 0xD2D2D2, ""))
fpsLabel:setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_CENTER)

-- Loading first wallpaper from list
reloadButton:onTouch()

menu:getItem(2).contextMenu:addItem("🗘", "Reload wallpaper", false, "^R").onTouch = reloadButton.onTouch

-- Overriding window event handler
local oldEventHandler = window.eventHandler
window.eventHandler = function(workspace, window, e1, e2, e3, e4, ...)
	if e1 == "key_down" then
		-- Ctrl+R
		if e4 == 19 then
			reloadButton:onTouch()
			return
		end
	end

	if oldEventHandler then
		oldEventHandler(workspace, window, e1, e2, e3, e4, ...)
	end
end

---------------------------------------------------------------------------------

workspace:draw()
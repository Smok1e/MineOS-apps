local GUI = require("GUI")
local system = require("System")
local paths = require("Paths")
local filesystem = require("Filesystem")
local screen = require("Screen")

---------------------------------------------------------------------------------

local workspace, window, menu = system.addWindow(GUI.filledWindow(1, 1, 100, 30, 0xE1E1E1))

local leftPanel = system.addBlurredOrDefaultPanel(window, 1, 1, 30, 1)
window.backgroundPanel.localX = leftPanel.width + 1

window.actionButtons.localX, window.actionButtons.localY = 4, 2
window.actionButtons:moveToFront()

local layout = window:addChild(GUI.layout(1, 4, leftPanel.width, 1, 1, 1))
layout:setFitting(1, 1, true, false, 2, 0)
layout:setAlignment(1, 1, GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP)

window.onResize = function(width, height)
	leftPanel.height = height
	layout.height = height
	window.backgroundPanel.width, window.backgroundPanel.height = width - leftPanel.width, height
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
	local wallpaper = system.getWallpaper()
	if wallpaper.configure then
		configureFrom = #layout.children + 1
		window.backgroundPanel.configure(layout)
		configureTo = #layout.children
	end
end

---------------------------------------------------------------------------------

local selectorLayout = layout:addChild(GUI.layout(1, 1, layout.width, 3, 1, 1))
selectorLayout:setDirection(1, 1, GUI.DIRECTION_HORIZONTAL)

local comboBox = selectorLayout:addChild(GUI.comboBox(1, 1, selectorLayout.width - 8, 3, 0x323232, 0xD2D2D2, 0x323232, 0xA5A5A5))
local reloadButton = selectorLayout:addChild(GUI.button(1, 1, 6, 3, 0x323232, 0xD2D2D2, 0x323232, 0xA5A5A5, "🗘"))

local label = layout:addChild(GUI.label(1, 1, 1, 1, 0xD2D2D2, ""))
label:setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_CENTER)

local files = filesystem.list(paths.system.wallpapers)
for i = 1, #files do
	local file = files[i]
	local path = paths.system.wallpapers .. file
	
	if filesystem.isDirectory(path) and filesystem.extension(path) == ".wlp" then
		comboBox:addItem(filesystem.hideExtension(file))
	end
end

comboBox.onItemSelected = function(index)
	local result, reason = loadfile(paths.system.wallpapers .. files[index] .. "Main.lua")
	if not result then
		GUI.alert(reason)
		return
	end

	result, reason = xpcall(result, debug.traceback, workspace, window.backgroundPanel)
	if not result then
		GUI.alert(reason)
		return
	end

	local renderTimeSum, frameCount = 0, 0
	label.text = "FPS: N/A"

	local oldDraw, wallpaperError = window.backgroundPanel.draw
	window.backgroundPanel.draw = function(...)
		local startTime = computer.uptime()

		local result, reason = xpcall(oldDraw, debug.traceback, ...)
		if not result then
			local lines, maxLen = {}, 0
			for line in reason:gsub("\t", "    "):gmatch("[^\r\n]+") do
				table.insert(lines, line)
				maxLen = math.max(maxLen, #line)
			end

			window.backgroundPanel.draw = function()
				screen.drawRectangle(
					window.backgroundPanel.x, 
					window.backgroundPanel.y, 
					window.backgroundPanel.width, 
					window.backgroundPanel.height, 
					0x161616, 
					0, 
					" "
				)

				for i, line in pairs(lines) do
					screen.drawText(
						window.backgroundPanel.x + math.floor(window.backgroundPanel.width  / 2 - maxLen / 2),
						window.backgroundPanel.y + math.floor(window.backgroundPanel.height / 2 - #lines / 2) + i,
						0xD2D2D2,
						line
					)
				end
			end

			return
		end

		renderTimeSum = renderTimeSum + computer.uptime() - startTime
		frameCount = frameCount + 1

		if frameCount > 20 then
			label.text = "FPS: " .. math.floor(1.0 / (renderTimeSum / frameCount))
			frameCount = 0
		end
	end

	configure()
end

reloadButton.onTouch = function(button)
	comboBox.onItemSelected(comboBox.selectedItem)
end

reloadButton:onTouch()

---------------------------------------------------------------------------------

window:resize(window.width, window.height)
workspace:draw()
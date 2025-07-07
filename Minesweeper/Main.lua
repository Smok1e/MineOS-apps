local GUI = require("GUI")
local system = require("System")
local screen = require("Screen")
local color = require("Color")
local text = require("Text")
local image = require("Image")
local filesystem = require("Filesystem")

--------------------------------------------------------------------------------- Constants

local CURRENT_SCRIPT_DIR = filesystem.path(system.getCurrentScript())

local TILE_TYPE = {
	DIGIT = 0,
	MINE  = 1
}

local TILE_COLOR = {
	BACKGROUND = {0xEDEDED, 0xBFBFBF},
	FOREGROUND = {
		DEFAULT = 0x242424,
		DIGIT = {
			0x0000FF,
			0x008000,
			0xFF0000,
			0x000080,
			0x800000,
			0x008080,
			0x000000,
			0x959595
		},
		EXPLODED_MINE = {
			0xFFFF00, 
			0xFF0000
		},
		DEFUSED_MINE = {
			0xFFFFFF,
			0x00B648
		},
		WRONG_MINE = 0xFFDB00
	}
}

local TILE_SYMBOL = {
	HIDDEN = '⬜',
	DIGIT = {'１', '２', '３', '４', '５', '６', '７', '８'},
	MARK = '⯄',
}

local localization = system.getCurrentScriptLocalization()

--------------------------------------------------------------------------------- Minefield

local function minefieldDraw(minefield)
	for x = 1, minefield.fieldWidth do
		for y = 1, minefield.fieldHeight do
			local background = TILE_COLOR.BACKGROUND[(x + y) % 2 + 1]
			local foreground = TILE_COLOR.FOREGROUND.DEFAULT
			local symbol = TILE_SYMBOL.HIDDEN

			local tile = minefield:getTile(x, y)

			if tile.revealed then
				if tile.digit then
					foreground = TILE_COLOR.FOREGROUND.DIGIT[tile.digit]
					symbol = TILE_SYMBOL.DIGIT[tile.digit]
				else
					symbol = nil
				end
			else
				if tile.marked then
					symbol = TILE_SYMBOL.MARK
				end

				if minefield.animating then
					local radius = (x - minefield.animationCenterX - 1) ^ 2 + (y - minefield.animationCenterY - 1) ^ 2

					if radius <= minefield.animationRadius then
						if tile.type == TILE_TYPE.MINE then
							symbol = TILE_SYMBOL.MARK
							
							local t = 2 * (minefield.animationRadius - radius) / minefield.maxRadius
							if t > 1 then
								t = 1
							end

							if tile.marked then
								foreground = color.transition(
									TILE_COLOR.FOREGROUND.DEFUSED_MINE[1],
									TILE_COLOR.FOREGROUND.DEFUSED_MINE[2], 
									t
								)
							else
								foreground = color.transition(
									TILE_COLOR.FOREGROUND.EXPLODED_MINE[1],
									TILE_COLOR.FOREGROUND.EXPLODED_MINE[2], 
									t
								)
							end
						elseif tile.marked then
							symbol = TILE_SYMBOL.MARK
							foreground = TILE_COLOR.FOREGROUND.WRONG_MINE
						end
					end
				end
			end

			if symbol then
				screen.set(
					minefield.x + 2 * (x - 1),
					minefield.y +      y - 1,
					background,
					foreground,
					symbol
				)
			else
				screen.drawRectangle(
					minefield.x + 2 * (x - 1),
					minefield.y +      y - 1,
					2,
					1,
					background,
					foreground,
					" "					
				)
			end
		end
	end
end

local function minefieldEventHandler(workspace, minefield, eventType, _, touchX, touchY, touchButton)
	if eventType ~= "drop" or minefield.animating then
		return
	end

	local x = math.floor((touchX - minefield.x) / 2) + 1
	local y = touchY - minefield.y + 1
	
	-- Left mouse button
	if touchButton == 0 then
		minefield:revealTile(x, y)	
	
	-- Right mouse button
	elseif touchButton == 1 then
		minefield:markTile(x, y)
	end
end

-- Returns tile reference by x and y
local function minefieldGetTile(minefield, x, y)
	return minefield.tiles[(y - 1) * minefield.fieldWidth + x]
end

-- Recursively reveals digits adjacent to {x, y}
local function minefieldRevealTile(minefield, x, y)
	if not minefield.generated then
		minefield:generate(x, y)
	end

	local tile = minefield:getTile(x, y)
	if tile.marked then
		return
	end

	if tile.type == TILE_TYPE.MINE then
		minefield:onMineExploded(x, y)
		return
	end

	if not tile.revealed then
		tile.revealed = true
		tile.marked = false

		minefield.revealedTileCount = minefield.revealedTileCount + 1
		minefield:checkGameStatus(x, y)
	end

	if not tile.digit then
		for adjacent_x = math.max(x - 1, 1), math.min(x + 1, minefield.fieldWidth) do
			for adjacent_y = math.max(y - 1, 1), math.min(y + 1, minefield.fieldHeight) do
				local adjacent_tile = minefield.tiles[(adjacent_y - 1) * minefield.fieldWidth + adjacent_x]

				if not adjacent_tile.revealed and not adjacent_tile.marked and adjacent_tile.type == TILE_TYPE.DIGIT then
					minefield:revealTile(adjacent_x, adjacent_y)
				end
			end
		end
	end
end

-- Toggles mine mark
local function minefieldMarkTile(minefield, x, y)
	local tile = minefield:getTile(x, y)
	if tile.revealed then
		return
	end

	tile.marked = not tile.marked
	if tile.marked then
		minefield.markedMineCount = minefield.markedMineCount + 1

		if tile.type == TILE_TYPE.MINE then
			minefield.defusedMineCount = minefield.defusedMineCount + 1
		end
	else
		minefield.markedMineCount = minefield.markedMineCount - 1

		if tile.type == TILE_TYPE.MINE then
			minefield.defusedMineCount = minefield.defusedMineCount - 1
		end		
	end

	minefield:checkGameStatus(x, y)
end

-- Initializes minefield with specified width, height and mine count
-- but actual mine positions are generated later in generate method
-- as their positions have to rely on first click position
local function minefieldInit(minefield, fieldWidth, fieldHeight, mineCount)
	if mineCount and mineCount >= fieldWidth * fieldHeight then
		error("Pizda!")
	end

	minefield.fieldWidth = fieldWidth or minefield.fieldWidth
	minefield.fieldHeight = fieldHeight or minefield.fieldHeight
	minefield.mineCount = mineCount or minefield.mineCount

	minefield.width = 2 * minefield.fieldWidth
	minefield.height = minefield.fieldHeight
	minefield.generated = false
	minefield.animating = false

	minefield.markedMineCount = 0
	minefield.defusedMineCount = 0
	minefield.revealedTileCount = 0

	-- Initialize tiles
	minefield.tiles = {}
	for i = 1, minefield.fieldWidth * minefield.fieldHeight do
		table.insert(minefield.tiles, {
			type = TILE_TYPE.DIGIT
		})
	end	

	if minefield.onInit then
		minefield.onInit()
	end
end

-- Generate mines
local function minefieldGenerate(minefield, exclude_x, exclude_y)
	for i = 1, minefield.mineCount do
		-- Find suitable mine location
		local mine_x, mine_y, mine_tile
		repeat
			mine_x = math.random(1, minefield.fieldWidth )
			mine_y = math.random(1, minefield.fieldHeight)
			
			mine_tile = minefield:getTile(mine_x, mine_y)
		until mine_tile.type ~= TILE_TYPE.MINE and not (mine_x == exclude_x and mine_y == exclude_y)

		mine_tile.type = TILE_TYPE.MINE

		-- Update surrounding digits
		for adjacent_x = math.max(mine_x - 1, 1), math.min(mine_x + 1, minefield.fieldWidth) do
			for adjacent_y = math.max(mine_y - 1, 1), math.min(mine_y + 1, minefield.fieldHeight) do
				local adjacent_tile = minefield.tiles[(adjacent_y - 1) * minefield.fieldWidth + adjacent_x]

				if adjacent_tile.type == TILE_TYPE.DIGIT then
					adjacent_tile.digit = (adjacent_tile.digit or 0) + 1
				end
			end
		end
	end

	minefield.generated = true
end

local function minefieldStartMinesAnimation(minefield, centerX, centerY, onAnimationEnded)
	if minefield.animating then
		return
	end

	-- Find maximum squared distance from the given point to minefield corner
	local function distanceTo(x, y)
		return (centerX - x) ^ 2 + (centerY - y) ^2
	end

	minefield.maxRadius = math.max(
		distanceTo(1,                    1                    ),
		distanceTo(1,                    minefield.fieldHeight),
		distanceTo(minefield.fieldWidth, 1                    ),
		distanceTo(minefield.fieldWidth, minefield.fieldHeight)
	)

	minefield.animating = true
	minefield.animationCenterX = centerX
	minefield.animationCenterY = centerY
	minefield.animationRadius = 0

	minefield:addAnimation(
		function(animation)
			minefield.animationRadius = animation.position * minefield.maxRadius * 1.5
		end,

		function(animation)
			animation:remove()
			onAnimationEnded()
		end
	):start(3)
end

local function minefieldOnMineExploded(minefield, centerX, centerY)
	minefield:startMinesAnimation(
		centerX,
		centerY,
		minefield.onGameLost
	)
end

local function minefieldOnMinesDefused(minefield, centerX, centerY)
	minefield:startMinesAnimation(
		centerX,
		centerY,
		minefield.onGameWon
	)
end

local function minefieldCheckGameStatus(minefield, centerX, centerY)
	if 
		minefield.revealedTileCount == minefield.fieldWidth * minefield.fieldHeight - minefield.mineCount 
		and minefield.markedMineCount == minefield.mineCount
	then
		minefield:onMinesDefused(centerX, centerY)
	end
end

-- Creates new minefield GUI object
local function minefieldNew()
	local minefield = GUI.object(1, 1, 1, 1)

	minefield.draw = minefieldDraw
	minefield.init = minefieldInit
	minefield.eventHandler = minefieldEventHandler
	minefield.getTile = minefieldGetTile
	minefield.revealTile = minefieldRevealTile
	minefield.markTile = minefieldMarkTile
	minefield.generate = minefieldGenerate
	minefield.startMinesAnimation = minefieldStartMinesAnimation
	minefield.onMineExploded = minefieldOnMineExploded
	minefield.onMinesDefused = minefieldOnMinesDefused
	minefield.checkGameStatus = minefieldCheckGameStatus

	return minefield
end

--------------------------------------------------------------------------------- Timer & mine counter

local function timerDraw(timer)
	if not timer.minefield.animating then
		timer.currentTime = computer.uptime() - timer.startTime
	end

	screen.drawText(
		timer.x + 1,
		timer.y + 1,
		0xFFFFFF,
		os.date("⌛ %M:%S", timer.currentTime)
	)

	local text = ("⯄ %d/%d"):format(timer.minefield.markedMineCount, timer.minefield.mineCount)
	screen.drawText(
		timer.x + timer.width - #text,
		timer.y + 1,
		0xFFFFFF,
		text
	)
end

local function timerReset(timer)
	timer.startTime = computer.uptime()
	timer.currentTime = 0
end

local function timerNew(x, y, width, minefield)
	local timer = GUI.object(x, y, width, 3)

	timer.minefield = minefield
	
	timer.draw = timerDraw
	timer.reset = timerReset

	minefield.onInit = function()
		timer:reset()
	end

	timer:reset()
	return timer
end

--------------------------------------------------------------------------------- Centered text box

local function centeredTextBoxDraw(textBox)
	for i = 1, #textBox.lines do
		screen.drawText(
			textBox.x + math.floor((textBox.width - unicode.len(textBox.lines[i])) / 2),
			textBox.y + i - 1,
			0x999999,
			textBox.lines[i]
		)
	end
end

local function centeredTextBoxNew(x, y, width, height, rawText)
	local textBox = GUI.object(x, y, width, height)
	textBox.lines = text.wrap(rawText, width)
	textBox.draw = centeredTextBoxDraw

	return textBox
end

--------------------------------------------------------------------------------- Layout

-- Window
local window = GUI.window(1, 1, 97, 22, 0x242424)
window.actionButtons = window:addChild(GUI.actionButtons(3, 2, true))

local workspace = system.addWindow(window)

-- Mode list
local modeListPanel = system.addBlurredOrDefaultPanel(window, 1, 1, 25, 1)
local modeList = window:addChild(GUI.list(1, 4, modeListPanel.width, 1, 4, 0))

-- Minefield
local minefieldPanel = window:addChild(GUI.panel(1 + modeListPanel.width, 1, 1, 1, 0x323232))
local minefield = window:addChild(minefieldNew())

local timer = window:addChild(timerNew(minefieldPanel.x, 1, 1, minefield))

--------------------------------------------------------------------------------- Hardcore mode

local function showSelfDestructingCardAlert(onAlertClosed)
	local container = GUI.addBackgroundContainer(workspace, true, false)

	local oldContainerRemove = container.remove
	container.remove = function()
		onAlertClosed()
		oldContainerRemove(container)
	end

	-- Background panel & layout
	local backgroundPanel = container:addChild(GUI.panel(1, 1, 32, 18, 0x242424))
	backgroundPanel.localX = math.floor((container.width  - backgroundPanel.width ) / 2)
	backgroundPanel.localY = math.floor((container.height - backgroundPanel.height) / 2)

	local layout = container:addChild(
		GUI.layout(
			backgroundPanel.localX, 
			backgroundPanel.localY + 1, 
			backgroundPanel.width, 
			backgroundPanel.height,
			1,
			1
		)
	)
	
	-- Self-Destructing card image
	layout:addChild(GUI.image(1, 1, image.load(CURRENT_SCRIPT_DIR .. "Assets/SelfDestructingCard.pic")))

	-- Message text
	layout:addChild(centeredTextBoxNew(1, 1, layout.width, 3, localization.selfDestructingCardRequired))

	-- Ok button
	layout:addChild(
		GUI.button(1, 1, backgroundPanel.width, 3, 0xE1E1E1, 0x555555, 0x880000, 0xFFFFFF, localization.ok)
	).onTouch = container.remove
end

local hardcoreModeSwitchAndLabel = window:addChild(
	GUI.switchAndLabel(
		1, 
		1, 
		modeListPanel.width - 2, 
		6, 
		0xFF0000, 
		0x161616, 
		0xEEEEEE, 
		0x999999, 
		localization.hardcoreMode, 
		false
	)
)

local hardcoreModeSwitch = hardcoreModeSwitchAndLabel.switch
local hardcoreModeLabel = hardcoreModeSwitchAndLabel.label

local function disableHardcoreMode()
	-- DIRTY hack to turn switch off with animation
	hardcoreModeSwitch.eventHandler(workspace, hardcoreModeSwitch, "touch")
end

local oldEventHandler = hardcoreModeSwitch.eventHandler
hardcoreModeSwitch.eventHandler = function(workspace, switch, eventType, ...)
	if eventType == "touch" then
		local colorFrom, colorTo = 0x999999, 0xAA0000
		if hardcoreModeSwitch.state then
			colorFrom, colorTo = colorTo, colorFrom
		end

		hardcoreModeLabel:addAnimation(
			function(animation)
				hardcoreModeLabel.colors.text = color.transition(colorFrom, colorTo, animation.position)
			end,

			function(animation)
				animation:remove()
			end
		):start(GUI.SWITCH_ANIMATION_DURATION)

	elseif eventType == "component_removed" then
		local _, componentType = ...
		if componentType == "self_destruct" then
			disableHardcoreMode()
		end
	end

	oldEventHandler(workspace, switch, eventType, ...)
end

hardcoreModeSwitch.onStateChanged = function()
	if hardcoreModeSwitch.state then
		if not component.isAvailable("self_destruct") then
			showSelfDestructingCardAlert(disableHardcoreMode)  
		end
	end
end

--------------------------------------------------------------------------------- Mode list

local function modeListItemDraw(item)
	if item.pressed then
		screen.drawRectangle(
			item.x, 
			item.y,
			1,
			item.height,
			0x323232,
			item.highlightColor,
			"▎"
		)

		screen.drawRectangle(
			item.x + 1,
			item.y,
			item.width - 1,
			item.height,
			0x323232,
			0,
			" "
		)
	end

	screen.drawText(item.x + 1, item.y + 1, 0xFFFFFF, item.text       )
	screen.drawText(item.x + 1, item.y + 2, 0x646464, item.description)
end

local function modeListItemChooseSettings(item)
	local container = GUI.addBackgroundContainer(workspace, true, true, localization.customGame)

	local layout = container.layout:addChild(GUI.layout(1, 1, 35, 12, 1, 3))
	layout:setDirection(1, 1, GUI.DIRECTION_HORIZONTAL)
	layout:setSpacing(1, 1, 0)

	-- Width & height
	local function addInput(width, placeholder)
		return layout:addChild(GUI.input(1, 1, width, 3, 0xE1E1E1, 0x696969, 0x969696, 0xE1E1E1, 0x2D2D2D, "", placeholder))
	end

	local widthInput = addInput(16, localization.width)
	layout:addChild(GUI.text(1, 1, 0xFFFFFF, " x "))
	local heightInput = addInput(16, localization.height)

	-- Mine count input
	local minesInput = layout:setPosition(1, 2, addInput(layout.width, localization.mineCount))

	-- Ok / cancel
	layout:setDirection(1, 3, GUI.DIRECTION_HORIZONTAL)
	layout:setSpacing(1, 3, 3)

	layout:setPosition(1, 3, layout:addChild(GUI.button(1, 1, 16, 3, 0xE1E1E1, 0x555555, 0x880000, 0xFFFFFF, localization.ok))).onTouch = function()
		local fieldWidth, fieldHeight, mineCount = tonumber(widthInput.text), tonumber(heightInput.text), tonumber(minesInput.text)
		if fieldWidth and fieldHeight and mineCount then
			local function clamp(value, min, max)
				if value < min then value = min end
				if value > max then value = max end

				return value
			end

			fieldWidth = clamp(fieldWidth, 2, 36)
			fieldHeight = clamp(fieldHeight, 2, 16)
			mineCount = clamp(mineCount, 1, fieldWidth * fieldHeight - 1)

			item.description = ("%dx%d, %d mines"):format(fieldWidth, fieldHeight, mineCount)

			minefield:init(fieldWidth, fieldHeight, mineCount)
			window:resize(window.width, window.height)
		end

		container:remove()
	end

	layout:setPosition(1, 3, layout:addChild(GUI.button(1, 1, 16, 3, 0xE1E1E1, 0x555555, 0x880000, 0xFFFFFF, localization.cancel))).onTouch = function()
		container:remove()
	end
end

local function addModeListItem(title, highlightColor, fieldWidth, fieldHeight, mineCount)
	local item = modeList:addItem(title)

	item.highlightColor = highlightColor

	if fieldWidth then
		item.description = ("%dx%d, %d %s"):format(fieldWidth, fieldHeight, mineCount, localization.mines)
	else
		item.description = "..."
	end

	item.draw = modeListItemDraw
	item.chooseSettings = modeListItemChooseSettings

	item.onTouch = function()
		if fieldWidth then
			minefield:init(fieldWidth, fieldHeight, mineCount)
			window:resize(window.width, window.height)
			timer:reset()
		else
			item:chooseSettings()
		end
	end

	return item
end

addModeListItem(localization.difficultyBeginner,     0xABABAB, 10, 10, 15)
addModeListItem(localization.difficultyIntermediate, 0xFFFF66, 16, 16, 40)
addModeListItem(localization.difficultyAdvanced,     0x66FFFF, 30, 16, 99)
addModeListItem(localization.difficultyCustom,       0xC354CD 	         )

--------------------------------------------------------------------------------- Game won / lost message box

local function gameStatusMessage(messageText)
	local container = GUI.addBackgroundContainer(workspace, true, false)

	local oldContainerRemove = container.remove
	container.remove = function()
		minefield:init()
		oldContainerRemove(container)
	end

	-- Background panel & layout
	local backgroundPanel = container:addChild(GUI.panel(1, 1, 32, 10, 0x242424))
	backgroundPanel.localX = math.floor((container.width  - backgroundPanel.width ) / 2)
	backgroundPanel.localY = math.floor((container.height - backgroundPanel.height) / 2)
	
	local layout = container:addChild(
		GUI.layout(
			backgroundPanel.localX, 
			backgroundPanel.localY + 1, 
			backgroundPanel.width, 
			backgroundPanel.height,
			1,
			1
		)
	)
	
	-- Status
	layout:addChild(centeredTextBoxNew(1, 1, layout.width, 3, messageText))
	
	layout:addChild(
		GUI.textBox(
			1,
			1,
			layout.width,
			2,
			nil,
			0x999999,
			{
				os.date(localization.time .. ": %M:%S", timer.currentTime),
				("%s: %d/%d (%.0f%%)"):format(
					localization.minesDefused, 
					minefield.defusedMineCount, 
					minefield.mineCount, 
					100 * minefield.defusedMineCount / minefield.mineCount
				)
			},
			1,
			1,
			0
		)
	)

	-- Ok button
	layout:setSpacing(1, 1, 1)
	
	layout:addChild(
		GUI.button(1, 1, backgroundPanel.width, 3, 0xE1E1E1, 0x555555, 0x880000, 0xFFFFFF, localization.ok)
	).onTouch = container.remove
end

minefield.onGameWon = function()
	gameStatusMessage(localization.gameWon)
end

minefield.onGameLost = function()
	gameStatusMessage(localization.gameLost)

	if hardcoreModeSwitch.state and component.isAvailable("self_destruct") then
		component.self_destruct.start()

		for i = 1, 4 do
			local startTime = computer.uptime()
			computer.beep(1000, 0.05)

			while computer.uptime() - startTime < 1 do
				computer.pullSignal(0)
			end
		end

		computer.beep(1000, 1)
	end
end

---------------------------------------------------------------------------------

window.onResize = function(width, height)
	modeListPanel.height = height
	modeList.height = height - 6

	minefieldPanel.width = width - modeListPanel.width
	minefieldPanel.height = height

	minefield.localX = modeList.width + math.floor((width - modeListPanel.width - minefield.width) / 2) + 1
	minefield.localY = math.floor((height - minefield.height) / 2) + 1

	timer.localY = minefieldPanel.height - 2
	timer.width = minefieldPanel.width

	hardcoreModeSwitchAndLabel.localY = height - 1
	hardcoreModeSwitchAndLabel.localX = 2
end

window.actionButtons:moveToFront()
modeList.children[1].onTouch()

---------------------------------------------------------------------------------

workspace:draw()
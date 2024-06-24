local screen = require("Screen")
local color = require("Color")
local filesystem = require("Filesystem")
local system = require("System")
local GUI = require("GUI")

--------------------------------------------------------------------------------

local workspace, wallpaper = select(1, ...), select(2, ...)

local configPath = filesystem.path(system.getCurrentScript()) .. "Config.cfg"

local config = {
	backgroundColor = 0x0F0F0F,
    dropColor = 0x00FF00,
	rainbow = false,
	interpolationPower = 3,
    dropAmount = 10,
    dropLength = 10,
    speed = 1,
    chars = "⢸⡇",
	braille = false
}

if filesystem.exists(configPath) then
	for key, value in pairs(filesystem.readTable(configPath)) do
		config[key] = value
	end
end

-- Precalculating colors to not to call color.transition for each pixel
local colors

local function updateColors()
	local function fillColorTransitionTable(tbl, foreground)
		local t

		for i = 1, config.dropLength do
			table.insert(
				tbl, 
				color.transition(
					config.backgroundColor, 
					foreground, 
					(i / config.dropLength)^config.interpolationPower
				)
			)
		end
	end

	colors = {}
	if config.rainbow then
		local count = 16

		for i = 1, count do
			colors[i] = {}
			fillColorTransitionTable(colors[i], color.RGBToInteger(color.HSBToRGB(360 * (i - 1) / (count - 1), 1, 1)))
		end
	else
		fillColorTransitionTable(colors, config.dropColor)
	end
end

updateColors()

local function saveConfig()
	filesystem.writeTable(configPath, config)
    updateColors()
end

local function randomChar(x, y)
	math.randomseed(y * wallpaper.width + x)
	math.random() -- ?
	
	if config.braille then
		return unicode.char(math.random(0x2800, 0x28FF))
	else
		local charIndex = math.random(unicode.wlen(config.chars))
		return unicode.sub(config.chars, charIndex, charIndex)
	end
end

--------------------------------------------------------------------------------

local drops, lastUpdateTime = {}, computer.uptime()

wallpaper.draw = function(wallpaper)
	-- Spawning drops
	while #drops < config.dropAmount do
        table.insert(drops, {
            x = math.random(0, wallpaper.width - 1),
            y = 0,
			speed = .5 + 2 * math.random() ^ 2
        })
    end

	-- Filling background
    screen.drawRectangle(wallpaper.x, wallpaper.y, wallpaper.width, wallpaper.height, config.backgroundColor, 0, " ")

	-- Rendering drops
    local drop, x, y, charIndex
    for i = 1, #drops do
        drop = drops[i]

		x = drop.x

		local colorTransitionTable
		if config.rainbow then
			local index = math.floor(#colors * x / wallpaper.width) + 1

			colorTransitionTable = colors[index]
		else
			colorTransitionTable = colors
		end

        for i = 1, config.dropLength do
            y = math.floor(drop.y) - config.dropLength + i

			screen.set(
				wallpaper.x + x,
				wallpaper.y + y,
				config.backgroundColor,
				colorTransitionTable[i],
				randomChar(x, y)
			)
        end
    end

	-- Updating
    local updateTime = computer.uptime()
	local deltaTime = updateTime - lastUpdateTime

    local i = 1
    while i <= #drops do
        drop = drops[i]

        drop.y = drop.y + deltaTime * drop.speed * config.speed * 10

        if drop.y - config.dropLength >= wallpaper.height then
            table.remove(drops, i)
        else
            i = i + 1
        end
    end

    lastUpdateTime = updateTime
end

--------------------------------------------------------------------------------

wallpaper.configure = function(layout)
	-- Background color picker
	layout:addChild(GUI.colorSelector(1, 1, 36, 3, config.backgroundColor, "Background color")).onColorSelected = function(_, object)
		config.backgroundColor = object.color
		saveConfig()
	end

	-- Foreground color settings
	local rainbowSwitch = layout:addChild(GUI.switchAndLabel(1, 1, 36, 6, 0x66DB80, 0xE1E1E1, 0xFFFFFF, 0xA5A5A5, "Rainbow", config.rainbow)).switch
	local dropColorSelector = layout:addChild(GUI.colorSelector(1, 1, 36, 3, config.dropColor, "Drop color"))

	rainbowSwitch.onStateChanged = function()
		config.rainbow = rainbowSwitch.state
		dropColorSelector.hidden = rainbowSwitch.state
		saveConfig()
	end

	dropColorSelector.hidden = config.rainbow
	dropColorSelector.onColorSelected = function(_, object)
		config.dropColor = object.color
		saveConfig()
	end

	-- Interpolation method selector
	layout:addChild(GUI.label(1, 1, 1, 1, 0xA5A5A5, "Interpolation method"):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP))
	
	local comboBox = layout:addChild(GUI.comboBox(1, 1, 36, 1, 0xE1E1E1, 0x696969, 0xD2D2D2, 0xA5A5A5))
	comboBox:addItem("Linear"   ).onTouch = function() config.interpolationPower = 1 saveConfig() end
	comboBox:addItem("Quadratic").onTouch = function() config.interpolationPower = 2 saveConfig() end
	comboBox:addItem("Cubic"    ).onTouch = function() config.interpolationPower = 3 saveConfig() end
	comboBox.selectedItem = config.interpolationPower

	-- Drop amount slider
	local dropAmountSlider = layout:addChild(
		GUI.slider(
			1, 1, 
			36,
			0x66DB80, 
			0xE1E1E1, 
			0xFFFFFF, 
			0xA5A5A5, 
			10, 50, 
			config.dropAmount, 
			false, 
			"Drop amount: "
		)
	)
	
	dropAmountSlider.roundValues = true
	dropAmountSlider.onValueChanged = function()
		config.dropAmount = math.floor(dropAmountSlider.value)
		saveConfig()
	end

	-- Speed slider
	local speedSlider = layout:addChild(
		GUI.slider(
			1, 1, 
			36,
			0x66DB80, 
			0xE1E1E1, 
			0xFFFFFF, 
			0xA5A5A5, 
			20, 200, 
			config.speed * 100,
			false, 
			"Speed: ",
			"%"
		)
	)

	speedSlider.roundValues = true
	speedSlider.onValueChanged = function()
		config.speed = speedSlider.value / 100
		saveConfig()
	end

	-- Characters input
	layout:addChild(GUI.label(1, 1, 1, 1, 0xA5A5A5, "Characters"):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP))

	local brailleSwitch = layout:addChild(GUI.switchAndLabel(1, 1, 36, 6, 0x66DB80, 0xE1E1E1, 0xFFFFFF, 0xA5A5A5, "Braille", config.braille)).switch

	local input = layout:addChild(GUI.input(1, 1, 36, 3, 0xE1E1E1, 0x696969, 0xA5A5A5, 0xE1E1E1, 0x2D2D2D, config.chars))
	input.onInputFinished = function()
		if #input.text > 0 then
			config.chars = input.text
			saveConfig()
		end
	end

	input.hidden = config.braille
	brailleSwitch.onStateChanged = function()
		config.braille = brailleSwitch.state
		input.hidden = config.braille
		saveConfig()
	end
end
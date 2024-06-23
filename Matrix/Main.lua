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
    dropAmount = 10,
    dropLength = 10,
    speed = 1,
    chars = "⢸⡇"
}

if filesystem.exists(configPath) then
	for key, value in pairs(filesystem.readTable(configPath)) do
		config[key] = value
	end
end

local colors
local function updateColors()
	local function fillColorTransitionTable(tbl, foreground)
		for i = 1, config.dropLength do
			table.insert(tbl, color.transition(config.backgroundColor, foreground, i / config.dropLength))
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

--------------------------------------------------------------------------------

local drops, lastUpdateTime = {}, computer.uptime()

local function randomChar()
    local i = math.random(#chars)
    return chars:sub(i, i)
end

wallpaper.draw = function(wallpaper)
	while #drops < config.dropAmount do
        table.insert(drops, {
            x = math.random(0, wallpaper.width - 1),
            y = 0,
			speed = .5 + math.random()
        })
    end

    screen.drawRectangle(wallpaper.x, wallpaper.y, wallpaper.width, wallpaper.height, config.backgroundColor, 0, " ")

    local drop, x, y, charIndex
    for i = 1, #drops do
        drop = drops[i]

		x = drop.x

		local colorTransitionTable
		if config.rainbow then
			local index = math.floor(#colors * x / wallpaper.width) + 1

			colorTransitionTable = colors[index]
			if not colorTransitionTable then
				GUI.alert(#colors, index, x, wallpaper.width, x - 1)
			end
		else
			colorTransitionTable = colors
		end

        for i = 1, config.dropLength do
            y = math.floor(drop.y) - config.dropLength + i

			math.randomseed(y * wallpaper.width + x)
			math.random() -- ?
			charIndex = math.random(unicode.wlen(config.chars))

			screen.set(
				wallpaper.x + x,
				wallpaper.y + y,
				config.backgroundColor,
				colorTransitionTable[i],
				unicode.sub(config.chars, charIndex, charIndex)
			)
        end
    end

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
	layout:addChild(GUI.colorSelector(1, 1, 36, 3, config.backgroundColor, "Background color")).onColorSelected = function(_, object)
		config.backgroundColor = object.color
		saveConfig()
	end

	local rainbowSwitch = layout:addChild(GUI.switchAndLabel(1, 1, 16, 6, 0x66DB80, 0x0, 0xF0F0F0, 0xC3C3C3, "Rainbow", config.rainbow)).switch
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

	local input = layout:addChild(GUI.input(1, 1, 36, 3, 0xEEEEEE, 0x555555, 0x999999, 0xFFFFFF, 0x2D2D2D, config.chars))
	input.onInputFinished = function()
		if #input.text > 0 then
			config.chars = input.text
			saveConfig()
		end
	end
end
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
    dropAmount = 10,
    dropLength = 10,
    speed = 1,
    chars = "01"
}

if filesystem.exists(configPath) then
	for key, value in pairs(filesystem.readTable(configPath)) do
		config[key] = value
	end
end

local colors

local function updateColors()
    colors = {}

    for i = 1, config.dropLength do
        table.insert(colors, color.transition(config.backgroundColor, config.dropColor, (i - 1) / (config.dropLength - 1)))
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
    --if #drops < config.dropAmount and math.random(3) == 1 then
        table.insert(drops, {
            x = math.random(0, wallpaper.width - 1),
            y = 0,
			speed = .5 + math.random()
        })
    end

    screen.drawRectangle(wallpaper.x, wallpaper.y, wallpaper.width, wallpaper.height, config.backgroundColor, 0, " ")

    local drop
    for i = 1, #drops do
        drop = drops[i]

        for i = 1, config.dropLength do
            local x, y = drop.x, math.floor(drop.y) - config.dropLength + i

			math.randomseed(y * wallpaper.width + x)

			math.random() -- ?
			local charIndex = math.random(unicode.wlen(config.chars))

			screen.set(
				wallpaper.x + x,
				wallpaper.y + y,
				config.backgroundColor,
				colors[i],
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

	layout:addChild(GUI.colorSelector(1, 1, 36, 3, config.dropColor, "Drop color")).onColorSelected = function(_, object)
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
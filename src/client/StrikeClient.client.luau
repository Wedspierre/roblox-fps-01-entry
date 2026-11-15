-- StrikeClient: the NEON STRIKE first-person client. Locks the camera
-- to first person (Roblox native mouse look + WASD), sends shots to the
-- server, draws tracers, and renders the HUD, the start menu and the
-- game-over screen. The server owns the game state; this file only
-- shows it and sends input.
--
-- NOTE: the GUI root here is a plain full-screen frame with
-- BackgroundTransparency = 1. An opaque full-screen frame would hide
-- the entire 3D arena behind a flat panel; menus dim the scene with
-- their own semi-transparent layers instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StrikeConfig = require(ReplicatedStorage.Shared.StrikeConfig)
local StrikeGui = require(ReplicatedStorage.Shared.StrikeGui)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- First person: native mouse look, WASD movement, no third-person body.
player.CameraMode = Enum.CameraMode.LockFirstPerson

-- The engine does not reliably lock the mouse by itself in Studio Play:
-- clicking the START button leaves the cursor free and the view never
-- turns. Lock it explicitly when gameplay starts, free it for menus.
local function setMouseLock(locked: boolean)
	UserInputService.MouseBehavior = if locked
		then Enum.MouseBehavior.LockCenter
		else Enum.MouseBehavior.Default
end

local remotes = ReplicatedStorage:WaitForChild("StrikeRemotes")

local Palette = StrikeConfig.Palette

-- Latest snapshot from the server (HUD source of truth).
local snap = {
	phase = "menu",
	wave = 0,
	score = 0,
	best = 0,
	combo = 0,
	comboFrac = 0,
	hp = StrikeConfig.PlayerMaxHealth,
	maxHp = StrikeConfig.PlayerMaxHealth,
	ammo = StrikeConfig.MagazineSize,
	mag = StrikeConfig.MagazineSize,
	reloading = false,
	alive = 0,
	queued = 0,
	intermission = 0,
	kills = 0,
}

local firing = false
local lastClientShot = 0
local sprinting = false
local lastPhase = "menu"

-- ============ GUI root (fully transparent, the arena shows through) ============
local gui = Instance.new("ScreenGui")
gui.Name = "StrikeGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local root = StrikeGui.newPlainFrame("Root", gui)
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1

-- ============ Crosshair + hitmarker (center of the screen) ============
local crosshair = Instance.new("Frame")
crosshair.Name = "Crosshair"
crosshair.Size = UDim2.new(0, 24, 0, 24)
crosshair.Position = UDim2.new(0.5, -12, 0.5, -12)
crosshair.BackgroundTransparency = 1
crosshair.Parent = root
local function crossLine(x, y, w, h)
	local line = Instance.new("Frame")
	line.BackgroundColor3 = Palette.White
	line.BorderSizePixel = 0
	line.Position = UDim2.new(0, x, 0, y)
	line.Size = UDim2.new(0, w, 0, h)
	line.Parent = crosshair
	return line
end
crossLine(11, 0, 2, 8)
crossLine(11, 16, 2, 8)
crossLine(0, 11, 8, 2)
crossLine(16, 11, 8, 2)
local dot = Instance.new("Frame")
dot.BackgroundColor3 = Palette.Cyan
dot.BorderSizePixel = 0
dot.Position = UDim2.new(0, 11, 0, 11)
dot.Size = UDim2.new(0, 2, 0, 2)
dot.Parent = crosshair

local hitmarker = StrikeGui.newLabel("Hitmarker", root, "✕", 34, Palette.Yellow, Enum.Font.GothamBlack)
hitmarker.Size = UDim2.new(0, 60, 0, 60)
hitmarker.Position = UDim2.new(0.5, -30, 0.5, -30)
hitmarker.TextTransparency = 1
hitmarker.Visible = false
local hitUntil = 0

-- ============ HUD: health bottom-left, ammo bottom-right, score top-right ============
local healthPanel = StrikeGui.newFrame("HealthPanel", root)
healthPanel.Size = UDim2.new(0, 260, 0, 64)
healthPanel.Position = UDim2.new(0, 20, 1, -84)
local healthLabel = StrikeGui.newLabel("HealthLabel", healthPanel, "HEALTH", 16, Palette.DimText)
healthLabel.Position = UDim2.new(0, 14, 0, 8)
healthLabel.Size = UDim2.new(0, 120, 0, 20)
healthLabel.TextXAlignment = Enum.TextXAlignment.Left
local healthBack, healthFill = StrikeGui.newBar("Health", healthPanel, Palette.Green)
healthBack.Position = UDim2.new(0, 14, 0, 32)
healthBack.Size = UDim2.new(0, 232, 0, 16)
local healthNumber = StrikeGui.newLabel("HealthNumber", healthPanel, "100", 20, Palette.White)
healthNumber.Position = UDim2.new(0, 150, 0, 6)
healthNumber.Size = UDim2.new(0, 96, 0, 22)
healthNumber.TextXAlignment = Enum.TextXAlignment.Right

local ammoLabel = StrikeGui.newTitleLabel("Ammo", root, "30 / 30", 44)
ammoLabel.Position = UDim2.new(1, -220, 1, -96)
ammoLabel.Size = UDim2.new(0, 200, 0, 56)
ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
local reloadLabel = StrikeGui.newLabel("Reloading", root, "RELOADING…  (R)", 20, Palette.Yellow)
reloadLabel.Position = UDim2.new(1, -220, 1, -140)
reloadLabel.Size = UDim2.new(0, 200, 0, 26)
reloadLabel.TextXAlignment = Enum.TextXAlignment.Right
reloadLabel.Visible = false

local scorePanel = StrikeGui.newFrame("ScorePanel", root)
scorePanel.Size = UDim2.new(0, 300, 0, 96)
scorePanel.Position = UDim2.new(1, -320, 0, 20)
local scoreLabel = StrikeGui.newLabel("Score", scorePanel, "SCORE 0", 28, Palette.White)
scoreLabel.Position = UDim2.new(0, 0, 0, 10)
scoreLabel.Size = UDim2.new(1, -16, 0, 36)
scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
local waveLabel = StrikeGui.newTitleLabel("Wave", scorePanel, "WAVE 1", 24)
waveLabel.Position = UDim2.new(0, 0, 0, 48)
waveLabel.Size = UDim2.new(1, -16, 0, 32)
waveLabel.TextXAlignment = Enum.TextXAlignment.Right
local comboLabel = StrikeGui.newLabel("Combo", root, "", 24, Palette.Yellow)
comboLabel.Position = UDim2.new(1, -320, 0, 128)
comboLabel.Size = UDim2.new(0, 300, 0, 30)
comboLabel.TextXAlignment = Enum.TextXAlignment.Right

local statusLabel = StrikeGui.newLabel("Status", root, "", 20, Palette.DimText)
statusLabel.Position = UDim2.new(0.5, -200, 0, 20)
statusLabel.Size = UDim2.new(0, 400, 0, 28)

-- Wave banner (big center text, fades on its own).
local banner = StrikeGui.newTitleLabel("Banner", root, "", 64)
banner.Size = UDim2.new(0, 700, 0, 90)
banner.Position = UDim2.new(0.5, -350, 0.3, -45)
banner.TextTransparency = 1
local bannerUntil = 0

-- Score popup near the crosshair (+100 on a kill).
local popup = StrikeGui.newLabel("ScorePopup", root, "", 26, Palette.Yellow)
popup.Size = UDim2.new(0, 200, 0, 34)
popup.Position = UDim2.new(0.5, 30, 0.5, -40)
popup.TextTransparency = 1
local popupUntil = 0

-- Damage vignette: full-screen red flash when hurt.
local hurtFlash = Instance.new("Frame")
hurtFlash.Name = "HurtFlash"
hurtFlash.Size = UDim2.fromScale(1, 1)
hurtFlash.BackgroundColor3 = Palette.Red
hurtFlash.BackgroundTransparency = 1
hurtFlash.BorderSizePixel = 0
hurtFlash.Parent = root

local function showBanner(text: string)
	banner.Text = text
	banner.TextTransparency = 0
	bannerUntil = os.clock() + 2
end

local function showPopup(text: string)
	popup.Text = text
	popup.TextTransparency = 0
	popupUntil = os.clock() + 1.2
end

local function showHitmarker(killed: boolean)
	hitmarker.TextColor3 = if killed then Palette.Red else Palette.Yellow
	hitmarker.TextTransparency = 0
	hitmarker.Visible = true
	hitUntil = os.clock() + 0.15
end

-- ============ Start menu ============
local startDim = StrikeGui.newDimLayer("StartDim", root)
local startPanel = StrikeGui.newFrame("StartPanel", root)
startPanel.Size = UDim2.new(0, 620, 0, 440)
startPanel.Position = UDim2.new(0.5, -310, 0.5, -220)
local startTitle = StrikeGui.newTitleLabel("Title", startPanel, "NEON STRIKE", 56)
startTitle.Position = UDim2.new(0, 0, 0, 24)
startTitle.Size = UDim2.new(1, 0, 0, 64)
local startSub = StrikeGui.newLabel(
	"Sub",
	startPanel,
	"First-person wave shooter in the void. Hold the arena, chain kills, survive.",
	18,
	Palette.DimText
)
startSub.Position = UDim2.new(0, 30, 0, 96)
startSub.Size = UDim2.new(1, -60, 0, 28)
local startHow = StrikeGui.newLabel(
	"How",
	startPanel,
	"WASD move  •  MOUSE aim  •  CLICK shoot  •  R reload  •  SHIFT sprint\n"
		.. "Magenta Chaser rushes you  •  Orange Shooter fires back — hide behind cover\n"
		.. "Purple Tank soaks bullets  •  Kills build your combo multiplier\n"
		.. "Clear a wave for a bonus and +25 health",
	18,
	Palette.White
)
startHow.Position = UDim2.new(0, 30, 0, 140)
startHow.Size = UDim2.new(1, -60, 0, 130)
local startButton = StrikeGui.newButton("StartButton", startPanel, "▶  START", Palette.Cyan, 34)
startButton.Position = UDim2.new(0.5, -160, 1, -100)
startButton.Size = UDim2.new(0, 320, 0, 64)
local startHint = StrikeGui.newLabel("Hint", startPanel, "v2 — click START, then look around with the mouse.", 14, Palette.DimText)
startHint.Position = UDim2.new(0, 0, 1, -28)
startHint.Size = UDim2.new(1, 0, 0, 20)

-- ============ Game-over screen ============
local endDim = StrikeGui.newDimLayer("EndDim", root)
endDim.Visible = false
local endPanel = StrikeGui.newFrame("EndPanel", root)
endPanel.Size = UDim2.new(0, 560, 0, 380)
endPanel.Position = UDim2.new(0.5, -280, 0.5, -190)
endPanel.Visible = false
local endTitle = StrikeGui.newTitleLabel("EndTitle", endPanel, "GAME OVER", 52)
endTitle.Position = UDim2.new(0, 0, 0, 24)
endTitle.Size = UDim2.new(1, 0, 0, 60)
local endScore = StrikeGui.newLabel("EndScore", endPanel, "", 26, Palette.White)
endScore.Position = UDim2.new(0, 0, 0, 100)
endScore.Size = UDim2.new(1, 0, 0, 36)
local endWave = StrikeGui.newLabel("EndWave", endPanel, "", 22, Palette.DimText)
endWave.Position = UDim2.new(0, 0, 0, 140)
endWave.Size = UDim2.new(1, 0, 0, 32)
local endBest = StrikeGui.newLabel("EndBest", endPanel, "", 22, Palette.Yellow)
endBest.Position = UDim2.new(0, 0, 0, 176)
endBest.Size = UDim2.new(1, 0, 0, 32)
local endKills = StrikeGui.newLabel("EndKills", endPanel, "", 20, Palette.DimText)
endKills.Position = UDim2.new(0, 0, 0, 212)
endKills.Size = UDim2.new(1, 0, 0, 30)
local againButton = StrikeGui.newButton("AgainButton", endPanel, "↻  PLAY AGAIN", Palette.Magenta, 30)
againButton.Position = UDim2.new(0.5, -150, 1, -92)
againButton.Size = UDim2.new(0, 300, 0, 60)

-- ============ Shooting ============
local function shootOnce()
	if snap.phase ~= "playing" then
		return
	end
	if snap.reloading then
		return
	end
	local now = os.clock()
	if now - lastClientShot < StrikeConfig.FireCooldown then
		return
	end
	lastClientShot = now
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	remotes:FireServer("Shoot", origin, direction)
	-- Visual-only tracer: a thin neon beam from the camera to the hit.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	if character then
		params.FilterDescendantsInstances = { character }
	end
	local result = Workspace:Raycast(origin, direction * StrikeConfig.MaxRange, params)
	local hitPoint = origin + direction * StrikeConfig.MaxRange
	if result then
		hitPoint = result.Position
	end
	local mid = (origin + hitPoint) / 2
	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.Material = Enum.Material.Neon
	beam.Color = Palette.Cyan
	beam.Size = Vector3.new(0.15, 0.15, (hitPoint - origin).Magnitude)
	beam.CFrame = CFrame.lookAt(mid, hitPoint)
	beam.Parent = Workspace
	task.delay(0.08, function()
		beam:Destroy()
	end)
end

local function setSprint(on: boolean)
	if on == sprinting then
		return
	end
	sprinting = on
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = if on then StrikeConfig.PlayerSprintSpeed else StrikeConfig.PlayerWalkSpeed
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		shootOnce()
	elseif input.KeyCode == Enum.KeyCode.R then
		remotes:FireServer("Reload")
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(true)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(false)
	end
end)

startButton.MouseButton1Click:Connect(function()
	startDim.Visible = false
	startPanel.Visible = false
	setMouseLock(true)
	remotes:FireServer("Start")
end)

againButton.MouseButton1Click:Connect(function()
	endDim.Visible = false
	endPanel.Visible = false
	setMouseLock(true)
	remotes:FireServer("Restart")
end)

-- Keep the walk speed right after every respawn.
player.CharacterAdded:Connect(function(character: Model)
	local humanoid = character:WaitForChild("Humanoid")
	if humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = StrikeConfig.PlayerWalkSpeed
	end
	sprinting = false
end)

-- ============ Server events ============
remotes.OnClientEvent:Connect(function(action: string, a: any, b: any, c: any)
	if action == "Snapshot" and typeof(a) == "table" then
		snap = a
	elseif action == "Hit" then
		if a == true then
			showHitmarker(b == true)
			if b == true and typeof(c) == "number" and c > 0 then
				showPopup("+" .. tostring(c))
			end
		end
	elseif action == "Hurt" then
		hurtFlash.BackgroundTransparency = 0.45
	elseif action == "Wave" and typeof(a) == "number" then
		showBanner("WAVE " .. tostring(a))
	end
end)

-- ============ HUD refresh + hold-to-fire loop ============
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if firing and snap.phase == "playing" then
		shootOnce()
	end
	-- Fades.
	if banner.TextTransparency < 1 and now > bannerUntil then
		banner.TextTransparency = 1
	end
	if popup.TextTransparency < 1 and now > popupUntil then
		popup.TextTransparency = 1
	end
	if hitmarker.Visible and now > hitUntil then
		hitmarker.Visible = false
		hitmarker.TextTransparency = 1
	end
	if hurtFlash.BackgroundTransparency < 1 then
		hurtFlash.BackgroundTransparency = math.min(hurtFlash.BackgroundTransparency + 0.03, 1)
	end
	-- HUD values.
	healthFill.Size = UDim2.fromScale(math.clamp(snap.hp / snap.maxHp, 0, 1), 1)
	healthFill.BackgroundColor3 = if snap.hp > 50 then Palette.Green elseif snap.hp > 25 then Palette.Yellow else Palette.Red
	healthNumber.Text = tostring(snap.hp)
	ammoLabel.Text = tostring(snap.ammo) .. " / " .. tostring(snap.mag)
	reloadLabel.Visible = snap.reloading
	scoreLabel.Text = "SCORE " .. tostring(snap.score)
	waveLabel.Text = "WAVE " .. tostring(math.max(snap.wave, 1))
	if snap.combo >= 2 then
		local mult = 1 + StrikeConfig.ComboStep * math.min(snap.combo - 1, StrikeConfig.ComboMaxLevel)
		comboLabel.Text = "COMBO x" .. tostring(snap.combo) .. "  (x" .. string.format("%.1f", mult) .. ")"
	else
		comboLabel.Text = ""
	end
	if snap.phase == "playing" then
		if snap.queued > 0 or snap.alive > 0 then
			statusLabel.Text = "DRONES LEFT: " .. tostring(snap.alive + snap.queued)
		else
			statusLabel.Text = ""
		end
	elseif snap.phase == "intermission" then
		statusLabel.Text = "WAVE CLEARED  •  NEXT WAVE IN " .. tostring(snap.intermission) .. "  •  +25 HEALTH"
	elseif snap.phase == "menu" then
		statusLabel.Text = ""
	else
		statusLabel.Text = ""
	end
	-- Mouse lock: enforce every frame while playing (the engine can
	-- drop the lock on its own in Studio, so a one-time set is not
	-- enough). Free on menus so START / PLAY AGAIN can be clicked.
	-- Skip while the Roblox menu is open (Esc) so it stays usable.
	if snap.phase == "playing" or snap.phase == "intermission" then
		if not GuiService.MenuIsOpen then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		lastPhase = snap.phase
	elseif snap.phase ~= lastPhase then
		lastPhase = snap.phase
		setMouseLock(false)
	end
	-- Screen visibility by phase.
	local inMenu = snap.phase == "menu"
	startDim.Visible = inMenu
	startPanel.Visible = inMenu
	local over = snap.phase == "over"
	endDim.Visible = over
	endPanel.Visible = over
	if over then
		endScore.Text = "SCORE  " .. tostring(snap.score)
		endWave.Text = "REACHED WAVE " .. tostring(snap.wave)
		endBest.Text = "BEST  " .. tostring(snap.best)
		endKills.Text = tostring(snap.kills) .. " DRONES DESTROYED"
	end
	local inGame = snap.phase == "playing" or snap.phase == "intermission"
	crosshair.Visible = inGame
	healthPanel.Visible = inGame
	ammoLabel.Visible = inGame
	scorePanel.Visible = inGame
	comboLabel.Visible = inGame
end)

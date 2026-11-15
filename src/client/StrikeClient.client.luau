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
local TweenService = game:GetService("TweenService")

local StrikeConfig = require(ReplicatedStorage.Shared.StrikeConfig)
local StrikeGui = require(ReplicatedStorage.Shared.StrikeGui)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- CameraMode stays Classic on purpose. LockFirstPerson makes the
-- engine capture the mouse to the screen center the moment the player
-- spawns — before START is even clicked — so the cursor freezes and
-- the START button cannot be reached. First person here is done
-- entirely by the manual camera below; the engine must never own it.
player.CameraMode = Enum.CameraMode.Classic

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
	ammoList = { StrikeConfig.Weapons[1].Mag, StrikeConfig.Weapons[2].Mag, StrikeConfig.Weapons[3].Mag },
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

-- Weapon + feel state. curWeapon is 1 Rifle, 2 SMG, 3 Shotgun.
local curWeapon = 1
local recoil = 0
local bobPhase = 0
local crossGap = 5
local scorePop = 0
local lastScoreShown = 0
local lastHitPoint: Vector3? = nil
local lastHitTime = 0

-- Manual first-person camera angles. The default camera module proved
-- unreliable in Studio Play (mouse lock alone did not turn the view),
-- so the client owns the camera now: yaw/pitch from the mouse delta,
-- camera glued to the head every frame.
local camYaw = 0
local camPitch = 0
local CAM_SENSITIVITY = 0.0035

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
local crossLines = {}
local function crossLine(x, y, w, h)
	local line = Instance.new("Frame")
	line.BackgroundColor3 = Palette.White
	line.BorderSizePixel = 0
	line.Position = UDim2.new(0, x, 0, y)
	line.Size = UDim2.new(0, w, 0, h)
	line.Parent = crosshair
	return line
end
crossLines.top = crossLine(11, 0, 2, 8)
crossLines.bottom = crossLine(11, 16, 2, 8)
crossLines.left = crossLine(0, 11, 8, 2)
crossLines.right = crossLine(16, 11, 8, 2)
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

-- Low-health pulse: red edges that throb while hp is critical.
local lowHp = Instance.new("Frame")
lowHp.Name = "LowHp"
lowHp.Size = UDim2.fromScale(1, 1)
lowHp.BackgroundColor3 = Palette.Red
lowHp.BackgroundTransparency = 1
lowHp.BorderSizePixel = 0
lowHp.Parent = root
local lowHpStroke = Instance.new("UIStroke")
lowHpStroke.Color = Palette.Red
lowHpStroke.Thickness = 18
lowHpStroke.Transparency = 1
lowHpStroke.Parent = lowHp

-- Kill feed (top-right, under the combo line).
local feedFrame = Instance.new("Frame")
feedFrame.Name = "KillFeed"
feedFrame.Size = UDim2.new(0, 300, 0, 120)
feedFrame.Position = UDim2.new(1, -320, 0, 168)
feedFrame.BackgroundTransparency = 1
feedFrame.Parent = root
local feedEntries = {}

-- Weapon bar (bottom-center): 1 Rifle, 2 SMG, 3 Shotgun.
local weaponBar = Instance.new("Frame")
weaponBar.Name = "WeaponBar"
weaponBar.Size = UDim2.new(0, 354, 0, 54)
weaponBar.Position = UDim2.new(0.5, -177, 1, -70)
weaponBar.BackgroundTransparency = 1
weaponBar.Parent = root
local weaponSlots = {}
for i, weapon in ipairs(StrikeConfig.Weapons) do
	local slot = StrikeGui.newFrame("Weapon" .. tostring(i), weaponBar)
	slot.Size = UDim2.new(0, 110, 0, 54)
	slot.Position = UDim2.new(0, (i - 1) * 122, 0, 0)
	local key = StrikeGui.newLabel("Key", slot, tostring(i), 14, Palette.DimText)
	key.Position = UDim2.new(0, 8, 0, 4)
	key.Size = UDim2.new(0, 20, 0, 18)
	key.TextXAlignment = Enum.TextXAlignment.Left
	local name = StrikeGui.newLabel("Name", slot, weapon.Name, 16, Palette.White)
	name.Position = UDim2.new(0, 28, 0, 4)
	name.Size = UDim2.new(0, 78, 0, 20)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local ammo = StrikeGui.newLabel("Ammo", slot, tostring(weapon.Mag), 14, weapon.Color)
	ammo.Position = UDim2.new(0, 8, 0, 26)
	ammo.Size = UDim2.new(0, 94, 0, 20)
	ammo.TextXAlignment = Enum.TextXAlignment.Left
	weaponSlots[i] = { slot = slot, ammo = ammo }
end

local function showBanner(text: string)
	banner.Text = text
	banner.TextTransparency = 0
	banner.Size = UDim2.new(0, 500, 0, 64)
	bannerUntil = os.clock() + 2
	TweenService:Create(banner, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 700, 0, 90),
	}):Play()
end

-- Floating damage number at the last tracer hit point.
local function showDamageNumber(text: string, color: Color3)
	local camera = Workspace.CurrentCamera
	local screenPos = nil
	if camera and lastHitPoint and os.clock() - lastHitTime < 0.5 then
		local v, onScreen = camera:WorldToViewportPoint(lastHitPoint)
		if onScreen then
			screenPos = Vector2.new(v.X, v.Y)
		end
	end
	local label = StrikeGui.newLabel("DmgNum", root, text, 22, color, Enum.Font.GothamBlack)
	label.Size = UDim2.new(0, 80, 0, 28)
	if screenPos then
		label.Position = UDim2.new(0, screenPos.X - 40 + math.random(-24, 24), 0, screenPos.Y - 14)
	else
		label.Position = UDim2.new(0.5, -10 + math.random(-24, 24), 0.5, -50)
	end
	label.TextTransparency = 0
	TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = label.Position + UDim2.new(0, 0, 0, -46),
		TextTransparency = 1,
	}):Play()
	task.delay(0.65, function()
		label:Destroy()
	end)
end

local function addKillFeed(text: string)
	local entry = StrikeGui.newLabel("Feed", feedFrame, text, 16, Palette.Yellow)
	entry.Size = UDim2.new(1, 0, 0, 22)
	entry.TextXAlignment = Enum.TextXAlignment.Right
	entry.BackgroundTransparency = 1
	table.insert(feedEntries, 1, entry)
	for i, e in ipairs(feedEntries) do
		e.Position = UDim2.new(0, 0, 0, (i - 1) * 24)
		e.Visible = i <= 4
	end
	task.delay(4, function()
		entry:Destroy()
		for i, e in ipairs(feedEntries) do
			if e == entry then
				table.remove(feedEntries, i)
				break
			end
		end
		for i, e in ipairs(feedEntries) do
			e.Position = UDim2.new(0, 0, 0, (i - 1) * 24)
		end
	end)
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
		.. "1 Rifle  •  2 SMG  •  3 Shotgun — each has its own ammo\n"
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
local startHint = StrikeGui.newLabel("Hint", startPanel, "v5 — humanoid enemies, 3 guns (1/2/3), brighter arena.", 14, Palette.DimText)
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

-- ============ Gun viewmodel (first-person, glued to the camera) ============
local viewmodel: Model? = nil
local muzzle: BasePart? = nil
local flashUntil = 0

local function vmPart(name: string, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false -- raycasts (tracers, server shots) must never hit the gun
	p.Material = material
	p.Color = color
	p.Size = size
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function buildViewmodel()
	if viewmodel then
		viewmodel:Destroy()
	end
	local weapon = StrikeConfig.Weapons[curWeapon]
	local model = Instance.new("Model")
	model.Name = "Viewmodel"
	local receiver = vmPart("Receiver", Vector3.new(0.16, 0.22, 0.5), Color3.fromRGB(25, 25, 35), Enum.Material.SmoothPlastic)
	local barrel = vmPart("Barrel", Vector3.new(0.08, 0.08, weapon.Barrel), weapon.Color, Enum.Material.Neon)
	local grip = vmPart("Grip", Vector3.new(0.12, 0.26, 0.14), Color3.fromRGB(25, 25, 35), Enum.Material.SmoothPlastic)
	local mag = vmPart("Mag", Vector3.new(0.1, 0.3, 0.16), weapon.Color, Enum.Material.Neon)
	local sight = vmPart("Sight", Vector3.new(0.05, 0.12, 0.05), Palette.White, Enum.Material.Neon)
	local flash = vmPart("Muzzle", Vector3.new(0.14, 0.14, 0.08), Palette.Yellow, Enum.Material.Neon)
	flash.Transparency = 1
	receiver.Parent = model
	barrel.Parent = model
	grip.Parent = model
	mag.Parent = model
	sight.Parent = model
	flash.Parent = model
	model.PrimaryPart = receiver
	-- Static offsets from the receiver; SetPrimaryPartCFrame keeps them.
	barrel.CFrame = receiver.CFrame * CFrame.new(0, 0.04, -(0.25 + weapon.Barrel / 2))
	grip.CFrame = receiver.CFrame * CFrame.new(0, -0.22, 0.12)
	mag.CFrame = receiver.CFrame * CFrame.new(0, -0.24, -0.05)
	sight.CFrame = receiver.CFrame * CFrame.new(0, 0.16, 0)
	flash.CFrame = receiver.CFrame * CFrame.new(0, 0.04, -(0.25 + weapon.Barrel + 0.04))
	local camera = Workspace.CurrentCamera
	if camera then
		model.Parent = camera
	end
	viewmodel = model
	muzzle = flash
end

buildViewmodel()

local function switchWeapon(i: number)
	if i == curWeapon then
		return
	end
	if snap.phase ~= "playing" and snap.phase ~= "intermission" then
		return
	end
	curWeapon = i
	buildViewmodel()
	for j, slot in ipairs(weaponSlots) do
		local stroke = slot.slot:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if j == curWeapon then Palette.Cyan else Palette.DimText
			stroke.Transparency = if j == curWeapon then 0.1 else 0.7
		end
	end
end

-- ============ Shooting ============
local function shootOnce()
	if snap.phase ~= "playing" then
		return
	end
	if snap.reloading then
		return
	end
	local weapon = StrikeConfig.Weapons[curWeapon]
	local now = os.clock()
	if now - lastClientShot < weapon.Cooldown then
		return
	end
	lastClientShot = now
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	remotes:FireServer("Shoot", origin, direction, curWeapon)
	recoil = 1
	flashUntil = now + 0.05
	if muzzle then
		muzzle.Transparency = 0
	end
	crossGap = math.min(crossGap + 7, 16)
	-- Visual-only tracer with the weapon's spread.
	local spread = Vector3.new(
		(math.random() - 0.5) * 2 * weapon.Spread,
		(math.random() - 0.5) * 2 * weapon.Spread,
		(math.random() - 0.5) * 2 * weapon.Spread
	)
	local shotDir = (direction + spread).Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	if character then
		params.FilterDescendantsInstances = { character }
	end
	local result = Workspace:Raycast(origin, shotDir * weapon.Range, params)
	local hitPoint = origin + shotDir * weapon.Range
	if result then
		hitPoint = result.Position
	end
	lastHitPoint = hitPoint
	lastHitTime = now
	local mid = (origin + hitPoint) / 2
	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.Material = Enum.Material.Neon
	beam.Color = weapon.Color
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
		remotes:FireServer("Reload", curWeapon)
	elseif input.KeyCode == Enum.KeyCode.One then
		switchWeapon(1)
	elseif input.KeyCode == Enum.KeyCode.Two then
		switchWeapon(2)
	elseif input.KeyCode == Enum.KeyCode.Three then
		switchWeapon(3)
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
	-- Face the camera the way the character spawns facing, so the first
	-- frame after (re)spawn does not snap the view around.
	local root = character:WaitForChild("HumanoidRootPart")
	if root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		camYaw = math.atan2(-look.X, -look.Z)
		camPitch = 0
	end
	sprinting = false
end)

-- ============ Server events ============
remotes.OnClientEvent:Connect(function(action: string, a: any, b: any, c: any, d: any)
	if action == "Snapshot" and typeof(a) == "table" then
		snap = a
	elseif action == "Hit" then
		if a == true then
			showHitmarker(b == true)
			if b == true then
				if typeof(c) == "number" and c > 0 then
					showPopup("+" .. tostring(c))
				end
				showDamageNumber("ELIMINATED", Palette.Red)
				if typeof(d) == "string" then
					addKillFeed("☠ " .. d .. "  +" .. tostring(c or 0))
				end
			else
				showDamageNumber("-1", Palette.Yellow)
			end
		end
	elseif action == "Hurt" then
		hurtFlash.BackgroundTransparency = 0.45
	elseif action == "Wave" and typeof(a) == "number" then
		showBanner("WAVE " .. tostring(a))
	end
end)

-- ============ HUD refresh + hold-to-fire loop ============
RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	-- Manual first-person camera: the client rotates the view itself
	-- from the mouse delta instead of trusting the default camera
	-- module. The delta is drained every frame but only applied while
	-- playing, so moving the mouse over a menu never spins the view.
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local delta = UserInputService:GetMouseDelta()
			if snap.phase == "playing" or snap.phase == "intermission" then
				camYaw -= delta.X * CAM_SENSITIVITY
				camPitch = math.clamp(camPitch - delta.Y * CAM_SENSITIVITY, -1.55, 1.55)
			end
			camera.CFrame = CFrame.new(head.Position)
				* CFrame.Angles(0, camYaw, 0)
				* CFrame.Angles(camPitch, 0, 0)
		end
	end
	-- Gun viewmodel: glued to the camera, kicks with recoil, bobs
	-- while moving. Re-parented if the camera object ever changes.
	if viewmodel and viewmodel.PrimaryPart then
		if camera and viewmodel.Parent ~= camera then
			viewmodel.Parent = camera
		end
		local moving = UserInputService:IsKeyDown(Enum.KeyCode.W)
			or UserInputService:IsKeyDown(Enum.KeyCode.A)
			or UserInputService:IsKeyDown(Enum.KeyCode.S)
			or UserInputService:IsKeyDown(Enum.KeyCode.D)
		if moving then
			bobPhase += dt * 10
		end
		recoil = math.max(recoil - dt * 5, 0)
		if camera then
			viewmodel:SetPrimaryPartCFrame(camera.CFrame
				* CFrame.new(0.42 + math.cos(bobPhase * 0.5) * 0.008, -0.34 + math.sin(bobPhase) * 0.012, -0.7 + recoil * 0.14)
				* CFrame.Angles(recoil * 0.07, 0, 0))
		end
		if muzzle and now > flashUntil then
			muzzle.Transparency = 1
		end
	end
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
	local weapon = StrikeConfig.Weapons[curWeapon]
	ammoLabel.Text = tostring(snap.ammoList[curWeapon]) .. " / " .. tostring(weapon.Mag)
	reloadLabel.Text = "RELOADING…  " .. weapon.Name
	reloadLabel.Visible = snap.reloading
	for i, slot in ipairs(weaponSlots) do
		slot.ammo.Text = tostring(snap.ammoList[i])
	end
	-- Crosshair breathes: opens when firing, settles back after.
	local targetGap = if firing and snap.phase == "playing" then 11 else 5
	crossGap += (targetGap - crossGap) * math.min(dt * 10, 1)
	crossLines.top.Position = UDim2.new(0, 11, 0, 12 - crossGap - 8)
	crossLines.bottom.Position = UDim2.new(0, 11, 0, 12 + crossGap)
	crossLines.left.Position = UDim2.new(0, 12 - crossGap - 8, 0, 11)
	crossLines.right.Position = UDim2.new(0, 12 + crossGap, 0, 11)
	-- Score pops bigger on a change.
	if snap.score ~= lastScoreShown then
		lastScoreShown = snap.score
		scorePop = 1
	end
	scorePop = math.max(scorePop - dt * 3, 0)
	scoreLabel.TextSize = 28 + scorePop * 8
	-- Low-health pulse.
	if snap.hp <= 30 and (snap.phase == "playing" or snap.phase == "intermission") then
		local pulse = 0.75 + math.sin(now * 5) * 0.15
		lowHp.BackgroundTransparency = pulse
		lowHpStroke.Transparency = pulse
	else
		lowHp.BackgroundTransparency = 1
		lowHpStroke.Transparency = 1
	end
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
	weaponBar.Visible = inGame
	feedFrame.Visible = inGame
end)

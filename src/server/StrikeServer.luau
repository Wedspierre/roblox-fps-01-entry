-- StrikeServer: the authoritative NEON STRIKE server. One state table
-- owns the whole run; the client renders the HUD and menus and sends
-- input. Enemies are glowing drone parts that hover above the floor and
-- hunt the nearest player; the server moves them, validates every shot,
-- and owns score, combo, waves and the game-over state.
--
-- NOTE: this file is a ModuleScript, required by init.server.luau as
-- require(script.StrikeServer). A .server.luau file can never be
-- required (Roblox only requires ModuleScripts).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StrikeConfig = require(ReplicatedStorage.Shared.StrikeConfig)
local EnemyTypes = require(ReplicatedStorage.Shared.EnemyTypes)

local StrikeServer = {}

-- The single state table. Everything about the run lives here.
local state = {
	phase = "menu", -- menu | playing | intermission | over
	wave = 0,
	score = 0,
	best = 0,
	combo = 0,
	comboTimer = 0,
	enemies = {}, -- {id, kind, def, part, barFill, hp, maxHp, lastTouch, lastShot, flashUntil}
	projectiles = {}, -- {part, vel, life, damage}
	spawnQueue = 0,
	spawnTimer = 0,
	intermissionTimer = 0,
	nextEnemyId = 1,
	kills = 0,
}

-- Per-player gun state.
local gun = {} -- [Player] = {ammo, reloading, reloadEnd, lastShot}

local remotes: RemoteEvent
local coverParts = {}

local function getGun(player: Player)
	local g = gun[player]
	if not g then
		g = { ammo = StrikeConfig.MagazineSize, reloading = false, reloadEnd = 0, lastShot = 0 }
		gun[player] = g
	end
	return g
end

local function getPlayerCharacter(player: Player): Model?
	local character = player.Character
	if character and character.Parent then
		return character
	end
	return nil
end

local function getPlayerHead(player: Player): BasePart?
	local character = getPlayerCharacter(player)
	if not character then
		return nil
	end
	return character:FindFirstChild("Head")
end

local function getPlayerHumanoid(player: Player): Humanoid?
	local character = getPlayerCharacter(player)
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- Nearest living player to a position (the drones hunt this one).
local function nearestPlayer(pos: Vector3): (Player?, Vector3?)
	local bestPlayer: Player? = nil
	local bestPos: Vector3? = nil
	local bestDist = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local head = getPlayerHead(player)
		local humanoid = getPlayerHumanoid(player)
		if head and humanoid and humanoid.Health > 0 then
			local d = (head.Position - pos).Magnitude
			if d < bestDist then
				bestDist = d
				bestPlayer = player
				bestPos = head.Position
			end
		end
	end
	return bestPlayer, bestPos
end

local function comboMultiplier(): number
	if state.combo <= 0 then
		return 1
	end
	return 1 + StrikeConfig.ComboStep * math.min(state.combo - 1, StrikeConfig.ComboMaxLevel)
end

local function hurtPlayer(player: Player, damage: number)
	local humanoid = getPlayerHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	-- Taking a hit resets the combo.
	state.combo = 0
	state.comboTimer = 0
	humanoid:TakeDamage(damage)
	remotes:FireClient(player, "Hurt")
	if humanoid.Health <= 0 then
		gameOver()
	end
end

function gameOver()
	if state.phase == "over" then
		return
	end
	state.phase = "over"
	if state.score > state.best then
		state.best = state.score
	end
	for _, enemy in ipairs(state.enemies) do
		enemy.part:Destroy()
	end
	state.enemies = {}
	for _, proj in ipairs(state.projectiles) do
		proj.part:Destroy()
	end
	state.projectiles = {}
end

local function clearField()
	for _, enemy in ipairs(state.enemies) do
		enemy.part:Destroy()
	end
	state.enemies = {}
	for _, proj in ipairs(state.projectiles) do
		proj.part:Destroy()
	end
	state.projectiles = {}
end

local function startWave(wave: number)
	state.wave = wave
	state.spawnQueue = StrikeConfig.WaveBaseEnemyCount + StrikeConfig.WaveEnemyStep * wave
	state.spawnTimer = 0.5
	state.phase = "playing"
	for _, player in ipairs(Players:GetPlayers()) do
		remotes:FireClient(player, "Wave", wave)
	end
end

-- (Re)start a run for the player who pressed the button.
local function resetRun(player: Player)
	clearField()
	state.score = 0
	state.combo = 0
	state.comboTimer = 0
	state.kills = 0
	state.wave = 0
	state.spawnQueue = 0
	local g = getGun(player)
	g.ammo = StrikeConfig.MagazineSize
	g.reloading = false
	-- Fresh body at the spawn pad, full health.
	pcall(function()
		player:LoadCharacter()
	end)
	local humanoid = getPlayerHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = StrikeConfig.PlayerWalkSpeed
	end
	startWave(1)
end

local function makeHealthBar(part: BasePart, sizeY: number): Frame
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.new(0, 64, 0, 10)
	billboard.StudsOffset = Vector3.new(0, sizeY / 2 + 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = StrikeConfig.Palette.Background
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = billboard
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = StrikeConfig.Palette.Green
	fill.BorderSizePixel = 0
	fill.Parent = back
	return fill
end

local function spawnEnemy(kind: string)
	local def = EnemyTypes[kind]
	local hpScale = 1 + StrikeConfig.EnemyHealthPerWave * math.max(state.wave - 1, 0)
	local maxHp = math.max(1, math.floor(def.Health * hpScale + 0.5))
	local point = StrikeConfig.SpawnPoints[math.random(1, #StrikeConfig.SpawnPoints)]
	local part = Instance.new("Part")
	part.Name = "Enemy_" .. kind .. "_" .. tostring(state.nextEnemyId)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = def.Color
	part.Shape = def.Shape
	part.Size = def.Size
	part.Position = Vector3.new(point.X, StrikeConfig.HoverY[kind], point.Z)
	part.Parent = Workspace
	local barFill = makeHealthBar(part, def.Size.Y)
	state.nextEnemyId += 1
	table.insert(state.enemies, {
		id = state.nextEnemyId,
		kind = kind,
		def = def,
		part = part,
		barFill = barFill,
		hp = maxHp,
		maxHp = maxHp,
		lastTouch = 0,
		lastShot = 0,
		flashUntil = 0,
	})
end

local function killEnemy(index: number, shooter: Player?)
	local enemy = state.enemies[index]
	if not enemy then
		return
	end
	enemy.part:Destroy()
	table.remove(state.enemies, index)
	state.kills += 1
	state.combo += 1
	state.comboTimer = StrikeConfig.ComboWindowSeconds
	local gain = math.floor(StrikeConfig.KillScore * comboMultiplier() + 0.5)
	state.score += gain
	if shooter then
		remotes:FireClient(shooter, "Hit", true, true, gain)
	end
end

local function damageEnemy(enemy, index: number, damage: number, shooter: Player?)
	enemy.hp -= damage
	enemy.flashUntil = os.clock() + 0.08
	enemy.barFill.Size = UDim2.fromScale(math.max(enemy.hp / enemy.maxHp, 0), 1)
	if enemy.hp <= 0 then
		killEnemy(index, shooter)
	elseif shooter then
		remotes:FireClient(shooter, "Hit", true, false, 0)
	end
end

-- Find the enemy whose part this is (raycast hits return the part).
local function findEnemyByPart(part: BasePart): (any, number?)
	for i, enemy in ipairs(state.enemies) do
		if enemy.part == part then
			return enemy, i
		end
	end
	return nil, nil
end

local function fireProjectile(from: Vector3, target: Vector3, damage: number, speed: number)
	local dir = (target - from)
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	local part = Instance.new("Part")
	part.Name = "Projectile"
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = StrikeConfig.Palette.Red
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.4, 1.4, 1.4)
	part.Position = from
	part.Parent = Workspace
	table.insert(state.projectiles, {
		part = part,
		vel = dir * speed,
		life = 5,
		damage = damage,
	})
end

local function onShoot(player: Player, origin: Vector3, direction: Vector3)
	if state.phase ~= "playing" then
		return
	end
	local head = getPlayerHead(player)
	local humanoid = getPlayerHumanoid(player)
	if not head or not humanoid or humanoid.Health <= 0 then
		return
	end
	local g = getGun(player)
	if g.reloading then
		return
	end
	local now = os.clock()
	if now - g.lastShot < StrikeConfig.FireCooldown then
		return
	end
	-- The shot must come from the shooter's own head (first person).
	if (origin - head.Position).Magnitude > 10 then
		return
	end
	if direction.Magnitude < 0.5 then
		return
	end
	g.lastShot = now
	if g.ammo <= 0 then
		g.reloading = true
		g.reloadEnd = now + StrikeConfig.ReloadSeconds
		return
	end
	g.ammo -= 1

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(origin, direction.Unit * StrikeConfig.MaxRange, params)
	if result then
		local enemy, index = findEnemyByPart(result.Instance)
		if enemy and index then
			damageEnemy(enemy, index, StrikeConfig.BulletDamage, player)
		end
	end
end

local function onReload(player: Player)
	local g = getGun(player)
	if g.reloading or g.ammo >= StrikeConfig.MagazineSize then
		return
	end
	g.reloading = true
	g.reloadEnd = os.clock() + StrikeConfig.ReloadSeconds
end

local function onClientAction(player: Player, action: string, a: any, b: any)
	if action == "Shoot" then
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			onShoot(player, a, b)
		end
	elseif action == "Reload" then
		onReload(player)
	elseif action == "Start" or action == "Restart" then
		if state.phase == "menu" or state.phase == "over" then
			resetRun(player)
		end
	end
end

local function updateEnemies(dt: number)
	local now = os.clock()
	for i = #state.enemies, 1, -1 do
		local enemy = state.enemies[i]
		local def = enemy.def
		local part = enemy.part
		if not part.Parent then
			table.remove(state.enemies, i)
		else
			-- Hit flash wears off.
			if now > enemy.flashUntil then
				part.Transparency = 0
			else
				part.Transparency = 0.5
			end
			local targetPlayer, targetPos = nearestPlayer(part.Position)
			if targetPlayer and targetPos then
				local toTarget = targetPos - part.Position
				local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
				local dist = flat.Magnitude
				local speed = def.Speed * (1 + StrikeConfig.EnemySpeedPerWave * math.max(state.wave - 1, 0))
				speed = math.min(speed, def.Speed * 1.6)
				local move = Vector3.new(0, 0, 0)
				if enemy.kind == "Shooter" then
					-- Keep its distance: close in when far, back off when near.
					if dist > def.PreferredMax then
						move = flat.Unit * speed * dt
					elseif dist < def.PreferredMin then
						move = -flat.Unit * speed * 0.8 * dt
					else
						-- Strafe slowly so it is not a still target.
						local side = Vector3.new(-flat.Z, 0, flat.X)
						if side.Magnitude > 0.01 then
							move = side.Unit * speed * 0.35 * dt * math.sin(now * 0.7)
						end
					end
					-- Fire when it can see the player (cover blocks the shot).
					if now - enemy.lastShot >= def.ShotCooldown and dist < 70 then
						local losParams = RaycastParams.new()
						losParams.FilterType = Enum.RaycastFilterType.Include
						losParams.FilterDescendantsInstances = coverParts
						local los = Workspace:Raycast(part.Position, targetPos - part.Position, losParams)
						if not los then
							enemy.lastShot = now
							fireProjectile(part.Position, targetPos, def.ProjectileDamage, def.ProjectileSpeed)
						end
					end
				else
					if dist > 0.01 then
						move = flat.Unit * speed * dt
					end
				end
				local hoverY = StrikeConfig.HoverY[enemy.kind]
				part.Position = Vector3.new(
					part.Position.X + move.X,
					hoverY + math.sin(now * 2 + enemy.id) * 0.4,
					part.Position.Z + move.Z
				)
				-- Contact damage (horizontal distance only; drones hover).
				if dist < def.ContactRadius and now - enemy.lastTouch >= def.ContactCooldown then
					enemy.lastTouch = now
					hurtPlayer(targetPlayer, def.ContactDamage)
				end
			end
		end
	end
end

local function updateProjectiles(dt: number)
	for i = #state.projectiles, 1, -1 do
		local proj = state.projectiles[i]
		proj.life -= dt
		local remove = proj.life <= 0
		if not remove then
			proj.part.Position += proj.vel * dt
			if proj.part.Position.Y < 0.3 then
				remove = true
			else
				local targetPlayer, targetPos = nearestPlayer(proj.part.Position)
				if targetPlayer and targetPos and (targetPos - proj.part.Position).Magnitude < 3 then
					hurtPlayer(targetPlayer, proj.damage)
					remove = true
				end
			end
		end
		if remove then
			proj.part:Destroy()
			table.remove(state.projectiles, i)
		end
	end
end

local function sendSnapshot()
	local hp = 0
	local maxHp = StrikeConfig.PlayerMaxHealth
	local ammo = StrikeConfig.MagazineSize
	local reloading = false
	local first = Players:GetPlayers()[1]
	if first then
		local humanoid = getPlayerHumanoid(first)
		if humanoid then
			hp = math.max(math.floor(humanoid.Health + 0.5), 0)
		end
		local g = gun[first]
		if g then
			ammo = g.ammo
			reloading = g.reloading
		end
	end
	local snapshot = {
		phase = state.phase,
		wave = state.wave,
		score = state.score,
		best = state.best,
		combo = state.combo,
		comboFrac = if state.combo > 0 then state.comboTimer / StrikeConfig.ComboWindowSeconds else 0,
		hp = hp,
		maxHp = maxHp,
		ammo = ammo,
		mag = StrikeConfig.MagazineSize,
		reloading = reloading,
		alive = #state.enemies,
		queued = state.spawnQueue,
		intermission = math.max(math.ceil(state.intermissionTimer), 0),
		kills = state.kills,
	}
	for _, player in ipairs(Players:GetPlayers()) do
		remotes:FireClient(player, "Snapshot", snapshot)
	end
end

local snapshotTimer = 0
local function onHeartbeat(dt: number)
	if state.phase == "playing" then
		-- Combo decay.
		if state.combo > 0 then
			state.comboTimer -= dt
			if state.comboTimer <= 0 then
				state.combo = 0
				state.comboTimer = 0
			end
		end
		-- Reload completion.
		local now = os.clock()
		for _, g in pairs(gun) do
			if g.reloading and now >= g.reloadEnd then
				g.reloading = false
				g.ammo = StrikeConfig.MagazineSize
			end
		end
		-- Spawning.
		if state.spawnQueue > 0 and #state.enemies < StrikeConfig.WaveMaxAlive then
			state.spawnTimer -= dt
			if state.spawnTimer <= 0 then
				state.spawnTimer = StrikeConfig.SpawnIntervalSeconds
				state.spawnQueue -= 1
				spawnEnemy(EnemyTypes.pickForWave(state.wave))
			end
		end
		updateEnemies(dt)
		updateProjectiles(dt)
		-- Wave cleared.
		if state.spawnQueue <= 0 and #state.enemies == 0 then
			local bonus = StrikeConfig.WaveClearBonus + StrikeConfig.WaveClearBonusPerWave * state.wave
			state.score += bonus
			-- Stray projectiles must not hang frozen in the air.
			for _, proj in ipairs(state.projectiles) do
				proj.part:Destroy()
			end
			state.projectiles = {}
			for _, player in ipairs(Players:GetPlayers()) do
				local humanoid = getPlayerHumanoid(player)
				if humanoid and humanoid.Health > 0 then
					humanoid.Health = math.min(humanoid.Health + StrikeConfig.WaveClearHeal, StrikeConfig.PlayerMaxHealth)
				end
			end
			state.phase = "intermission"
			state.intermissionTimer = StrikeConfig.IntermissionSeconds
		end
	elseif state.phase == "intermission" then
		state.intermissionTimer -= dt
		if state.intermissionTimer <= 0 then
			startWave(state.wave + 1)
		end
	end
	snapshotTimer -= dt
	if snapshotTimer <= 0 then
		snapshotTimer = 0.15
		pcall(sendSnapshot)
	end
end

function StrikeServer.start()
	-- Cover parts, for the shooters' line-of-sight checks.
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") and string.match(child.Name, "^Cover%d+$") then
			table.insert(coverParts, child)
		end
	end
	-- The single RemoteEvent every client talks through.
	remotes = Instance.new("RemoteEvent")
	remotes.Name = "StrikeRemotes"
	remotes.Parent = ReplicatedStorage
	remotes.OnServerEvent:Connect(onClientAction)

	Players.PlayerAdded:Connect(function(player: Player)
		getGun(player)
		-- Keep the gun state fresh if the character reloads.
		player.CharacterAdded:Connect(function(character: Model)
			local humanoid = character:WaitForChild("Humanoid")
			if humanoid:IsA("Humanoid") then
				humanoid.WalkSpeed = StrikeConfig.PlayerWalkSpeed
				humanoid.Died:Connect(function()
					if state.phase == "playing" then
						gameOver()
					end
				end)
			end
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		getGun(player)
	end

	math.randomseed(os.time())
	RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(onHeartbeat, dt)
		if not ok then
			warn("[StrikeServer] heartbeat error: " .. tostring(err))
		end
	end)
end

return StrikeServer

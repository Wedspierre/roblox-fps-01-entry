
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StrikeConfig = require(ReplicatedStorage.Shared.StrikeConfig)
local EnemyTypes = require(ReplicatedStorage.Shared.EnemyTypes)

local StrikeServer = {}

local state = {
	phase = "menu",
	wave = 0,
	score = 0,
	best = 0,
	combo = 0,
	comboTimer = 0,
	enemies = {},
	projectiles = {},
	spawnQueue = 0,
	spawnTimer = 0,
	intermissionTimer = 0,
	nextEnemyId = 1,
	kills = 0,
	credits = StrikeConfig.StartCredits,
}

local gun = {}

local remotes: RemoteEvent
local coverParts = {}

local function getGun(player: Player)
	local g = gun[player]
	if not g then
		g = {
			ammo = { StrikeConfig.Weapons[1].Mag, StrikeConfig.Weapons[2].Mag, StrikeConfig.Weapons[3].Mag },
			reloading = false,
			reloadEnd = 0,
			reloadWeapon = 1,
			lastShot = { 0, 0, 0 },
			armor = 0,
		}
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
	state.combo = 0
	state.comboTimer = 0
	local g = getGun(player)
	local absorbed = math.min(g.armor, math.ceil(damage * 0.5))
	g.armor -= absorbed
	humanoid:TakeDamage(damage - absorbed)
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
		enemy.model:Destroy()
	end
	state.enemies = {}
	for _, proj in ipairs(state.projectiles) do
		proj.part:Destroy()
	end
	state.projectiles = {}
end

local function clearField()
	for _, enemy in ipairs(state.enemies) do
		enemy.model:Destroy()
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

local function resetRun(player: Player)
	clearField()
	state.score = 0
	state.combo = 0
	state.comboTimer = 0
	state.kills = 0
	state.wave = 0
	state.spawnQueue = 0
	state.credits = StrikeConfig.StartCredits
	local g = getGun(player)
	g.ammo = { StrikeConfig.Weapons[1].Mag, StrikeConfig.Weapons[2].Mag, StrikeConfig.Weapons[3].Mag }
	g.reloading = false
	g.armor = 0
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

local function bodyPart(name: string, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Material = material
	p.Color = color
	p.Size = size
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function buildHumanoid(def, id: number): (Model, { BasePart })
	local s = def.Scale
	local dark = Color3.new(def.Color.R * 0.9, def.Color.G * 0.9, def.Color.B * 0.9)
	local model = Instance.new("Model")
	model.Name = "Enemy_" .. def.Name .. "_" .. tostring(id)
	local torso = bodyPart("Torso", Vector3.new(2, 2, 1) * s, dark, Enum.Material.SmoothPlastic)
	local head = bodyPart("Head", Vector3.new(1.2, 1.2, 1.2) * s, dark, Enum.Material.SmoothPlastic)
	local visor = bodyPart("Visor", Vector3.new(0.9, 0.25, 0.15) * s, StrikeConfig.Palette.White, Enum.Material.Neon)
	local armL = bodyPart("ArmL", Vector3.new(1, 2, 1) * s, def.Color, Enum.Material.Neon)
	local armR = bodyPart("ArmR", Vector3.new(1, 2, 1) * s, def.Color, Enum.Material.Neon)
	local legL = bodyPart("LegL", Vector3.new(1, 1, 1) * s, def.Color, Enum.Material.Neon)
	local legR = bodyPart("LegR", Vector3.new(1, 1, 1) * s, def.Color, Enum.Material.Neon)
	torso.Parent = model
	head.Parent = model
	visor.Parent = model
	armL.Parent = model
	armR.Parent = model
	legL.Parent = model
	legR.Parent = model
	local parts: { BasePart } = { torso = torso, head = head, visor = visor, armL = armL, armR = armR, legL = legL, legR = legR }
	if def.Name == "Shooter" then
		local gunPart = bodyPart("Gun", Vector3.new(0.25, 0.25, 1.4) * s, Color3.fromRGB(30, 30, 40), Enum.Material.SmoothPlastic)
		gunPart.Parent = model
		parts.gun = gunPart
	end
	model.PrimaryPart = torso
	return model, parts
end

local function spawnEnemy(kind: string)
	local def = EnemyTypes[kind]
	local hpScale = 1 + StrikeConfig.EnemyHealthPerWave * math.max(state.wave - 1, 0)
	local maxHp = math.max(1, math.floor(def.Health * hpScale + 0.5))
	local point = StrikeConfig.SpawnPoints[math.random(1, #StrikeConfig.SpawnPoints)]
	local id = state.nextEnemyId
	state.nextEnemyId += 1
	local model, parts = buildHumanoid(def, id)
	model.Parent = Workspace
	local barFill = makeHealthBar(parts.torso, def.Height)
	local pos = Vector3.new(point.X, 0, point.Z)
	table.insert(state.enemies, {
		id = id,
		kind = kind,
		def = def,
		model = model,
		parts = parts,
		pos = pos,
		yaw = 0,
		walkPhase = 0,
		barFill = barFill,
		hp = maxHp,
		maxHp = maxHp,
		lastTouch = 0,
		lastShot = 0,
		flashUntil = 0,
	})
end

local function killEnemy(index: number, shooter: Player?, headshot: boolean?)
	local enemy = state.enemies[index]
	if not enemy then
		return
	end
	enemy.model:Destroy()
	table.remove(state.enemies, index)
	state.kills += 1
	state.combo += 1
	state.comboTimer = StrikeConfig.ComboWindowSeconds
	local gain = math.floor(StrikeConfig.KillScore * comboMultiplier() + 0.5)
	state.score += gain
	state.credits = math.min(state.credits + StrikeConfig.KillCredits, StrikeConfig.CreditCap)
	if shooter then
		remotes:FireClient(shooter, "Hit", true, true, gain, enemy.kind, headshot)
	end
end

local function damageEnemy(enemy, index: number, damage: number, shooter: Player?, headshot: boolean?)
	enemy.hp -= damage
	enemy.flashUntil = os.clock() + 0.08
	enemy.barFill.Size = UDim2.fromScale(math.max(enemy.hp / enemy.maxHp, 0), 1)
	if enemy.hp <= 0 then
		killEnemy(index, shooter, headshot)
	elseif shooter then
		remotes:FireClient(shooter, "Hit", true, false, damage, enemy.kind, headshot)
	end
end

local function findEnemyByPart(part: BasePart): (any, number?)
	for i, enemy in ipairs(state.enemies) do
		if part:IsDescendantOf(enemy.model) then
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

local function onShoot(player: Player, origin: Vector3, direction: Vector3, weaponIndex: any)
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
	local wi = 1
	if typeof(weaponIndex) == "number" then
		wi = math.clamp(math.floor(weaponIndex), 1, #StrikeConfig.Weapons)
	end
	local weapon = StrikeConfig.Weapons[wi]
	local now = os.clock()
	if now - g.lastShot[wi] < weapon.Cooldown then
		return
	end
	if (origin - head.Position).Magnitude > 10 then
		return
	end
	if direction.Magnitude < 0.5 then
		return
	end
	g.lastShot[wi] = now
	if g.ammo[wi] <= 0 then
		g.reloading = true
		g.reloadWeapon = wi
		g.reloadEnd = now + weapon.Reload
		return
	end
	g.ammo[wi] -= 1

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	for _ = 1, weapon.Pellets do
		local spread = Vector3.new(
			(math.random() - 0.5) * 2 * weapon.Spread,
			(math.random() - 0.5) * 2 * weapon.Spread,
			(math.random() - 0.5) * 2 * weapon.Spread
		)
		local dir = (direction.Unit + spread).Unit
		local result = Workspace:Raycast(origin, dir * weapon.Range, params)
		if result then
			local enemy, index = findEnemyByPart(result.Instance)
			if enemy and index then
				local hs = result.Instance.Name == "Head"
				local dmg = weapon.Damage * (if hs then StrikeConfig.HeadshotMult else 1)
				damageEnemy(enemy, index, dmg, player, hs)
			end
		end
	end
end

local function onReload(player: Player, weaponIndex: any)
	local g = getGun(player)
	local wi = 1
	if typeof(weaponIndex) == "number" then
		wi = math.clamp(math.floor(weaponIndex), 1, #StrikeConfig.Weapons)
	end
	if g.reloading or g.ammo[wi] >= StrikeConfig.Weapons[wi].Mag then
		return
	end
	g.reloading = true
	g.reloadWeapon = wi
	g.reloadEnd = os.clock() + StrikeConfig.Weapons[wi].Reload
end

local function onBuy(player: Player, itemId: any)
	if state.phase ~= "intermission" then
		return
	end
	local item = StrikeConfig.Shop[itemId]
	if not item or state.credits < item.Price then
		return
	end
	local g = getGun(player)
	if itemId == "Light" or itemId == "Heavy" then
		if g.armor >= item.Armor then
			return
		end
		g.armor = item.Armor
	elseif itemId == "Medkit" then
		local h = getPlayerHumanoid(player)
		if not h or h.Health >= StrikeConfig.PlayerMaxHealth then
			return
		end
		h.Health = math.min(h.Health + item.Heal, StrikeConfig.PlayerMaxHealth)
	elseif itemId == "Ammo" then
		local full = true
		for i, w in ipairs(StrikeConfig.Weapons) do
			if g.ammo[i] < w.Mag then
				full = false
			end
		end
		if full then
			return
		end
		for i, w in ipairs(StrikeConfig.Weapons) do
			g.ammo[i] = w.Mag
		end
		g.reloading = false
	end
	state.credits -= item.Price
end

local function onClientAction(player: Player, action: string, a: any, b: any, c: any)
	if action == "Shoot" then
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			onShoot(player, a, b, c)
		end
	elseif action == "Reload" then
		onReload(player, a)
	elseif action == "Buy" then
		onBuy(player, a)
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
		local s = def.Scale
		if not enemy.model.Parent then
			table.remove(state.enemies, i)
		else
			local flash = now <= enemy.flashUntil
			for _, part in pairs(enemy.parts) do
				part.Transparency = if flash then 0.5 else 0
			end
			local chest = enemy.pos + Vector3.new(0, 2 * s, 0)
			local targetPlayer, targetPos = nearestPlayer(chest)
			if targetPlayer and targetPos then
				local toTarget = targetPos - chest
				local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
				local dist = flat.Magnitude
				local speed = def.Speed * (1 + StrikeConfig.EnemySpeedPerWave * math.max(state.wave - 1, 0))
				speed = math.min(speed, def.Speed * 1.6)
				local move = Vector3.new(0, 0, 0)
				if enemy.kind == "Shooter" then
					if dist > def.PreferredMax then
						move = flat.Unit * speed * dt
					elseif dist < def.PreferredMin then
						move = -flat.Unit * speed * 0.8 * dt
					else
						local side = Vector3.new(-flat.Z, 0, flat.X)
						if side.Magnitude > 0.01 then
							move = side.Unit * speed * 0.35 * dt * math.sin(now * 0.7)
						end
					end
					if now - enemy.lastShot >= def.ShotCooldown and dist < 70 then
						local losParams = RaycastParams.new()
						losParams.FilterType = Enum.RaycastFilterType.Include
						losParams.FilterDescendantsInstances = coverParts
						local los = Workspace:Raycast(chest, targetPos - chest, losParams)
						if not los then
							enemy.lastShot = now
							fireProjectile(chest, targetPos, def.ProjectileDamage, def.ProjectileSpeed)
						end
					end
				else
					if dist > 0.01 then
						move = flat.Unit * speed * dt
					end
				end
				enemy.pos += move
				for _, cover in ipairs(coverParts) do
					local c = cover.Position
					local hs = cover.Size / 2 + Vector3.new(1.2, 0, 1.2)
					local dx = enemy.pos.X - c.X
					local dz = enemy.pos.Z - c.Z
					if math.abs(dx) < hs.X and math.abs(dz) < hs.Z then
						if hs.X - math.abs(dx) < hs.Z - math.abs(dz) then
							enemy.pos = Vector3.new(c.X + math.sign(dx) * hs.X, 0, enemy.pos.Z)
						else
							enemy.pos = Vector3.new(enemy.pos.X, 0, c.Z + math.sign(dz) * hs.Z)
						end
					end
				end
				if dist > 0.01 then
					enemy.yaw = math.atan2(-flat.X, -flat.Z)
				end
				local moving = move.Magnitude > 0.01
				if moving then
					enemy.walkPhase += speed * dt * 1.4
				end
				local swing = if moving then math.sin(enemy.walkPhase) * 0.55 else 0
				local torsoCF = CFrame.new(enemy.pos.X, 2 * s, enemy.pos.Z) * CFrame.Angles(0, enemy.yaw, 0)
				local parts = enemy.parts
				parts.torso.CFrame = torsoCF
				parts.head.CFrame = torsoCF * CFrame.new(0, 1.6 * s, 0)
				parts.visor.CFrame = torsoCF * CFrame.new(0, 1.65 * s, -0.62 * s)
				parts.armL.CFrame = torsoCF * CFrame.new(-1.5 * s, 0.75 * s, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -1 * s, 0)
				parts.armR.CFrame = torsoCF * CFrame.new(1.5 * s, 0.75 * s, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -1 * s, 0)
				parts.legL.CFrame = torsoCF * CFrame.new(-0.5 * s, -1 * s, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -0.5 * s, 0)
				parts.legR.CFrame = torsoCF * CFrame.new(0.5 * s, -1 * s, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -0.5 * s, 0)
				if parts.gun then
					parts.gun.CFrame = torsoCF * CFrame.new(1.5 * s, -0.4 * s, -0.7 * s)
				end
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
	local ammoList = { StrikeConfig.Weapons[1].Mag, StrikeConfig.Weapons[2].Mag, StrikeConfig.Weapons[3].Mag }
	local reloading = false
	local armor = 0
	local px, pz = 0, 0
	local first = Players:GetPlayers()[1]
	if first then
		local humanoid = getPlayerHumanoid(first)
		if humanoid then
			hp = math.max(math.floor(humanoid.Health + 0.5), 0)
		end
		local head = getPlayerHead(first)
		if head then
			px = math.floor(head.Position.X)
			pz = math.floor(head.Position.Z)
		end
		local g = gun[first]
		if g then
			ammoList = { g.ammo[1], g.ammo[2], g.ammo[3] }
			reloading = g.reloading
			armor = g.armor
		end
	end
	local foes = {}
	for _, e in ipairs(state.enemies) do
		table.insert(foes, { math.floor(e.pos.X), math.floor(e.pos.Z), e.kind })
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
		ammoList = ammoList,
		reloading = reloading,
		alive = #state.enemies,
		queued = state.spawnQueue,
		intermission = math.max(math.ceil(state.intermissionTimer), 0),
		kills = state.kills,
		credits = state.credits,
		armor = armor,
		foes = foes,
		px = px,
		pz = pz,
	}
	for _, player in ipairs(Players:GetPlayers()) do
		remotes:FireClient(player, "Snapshot", snapshot)
	end
end

local snapshotTimer = 0
local function onHeartbeat(dt: number)
	if state.phase == "playing" then
		if state.combo > 0 then
			state.comboTimer -= dt
			if state.comboTimer <= 0 then
				state.combo = 0
				state.comboTimer = 0
			end
		end
		local now = os.clock()
		for _, g in pairs(gun) do
			if g.reloading and now >= g.reloadEnd then
				g.reloading = false
				g.ammo[g.reloadWeapon] = StrikeConfig.Weapons[g.reloadWeapon].Mag
			end
		end
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
		if state.spawnQueue <= 0 and #state.enemies == 0 then
			local bonus = StrikeConfig.WaveClearBonus + StrikeConfig.WaveClearBonusPerWave * state.wave
			state.score += bonus
			state.credits = math.min(state.credits + StrikeConfig.WaveClearCredits, StrikeConfig.CreditCap)
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
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") and string.match(child.Name, "^Cover%d+$") then
			table.insert(coverParts, child)
		end
	end
	remotes = Instance.new("RemoteEvent")
	remotes.Name = "StrikeRemotes"
	remotes.Parent = ReplicatedStorage
	remotes.OnServerEvent:Connect(onClientAction)

	Players.PlayerAdded:Connect(function(player: Player)
		getGun(player)
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

-- StrikeConfig: every tuning number of NEON STRIKE in one place.
-- The server and the client both require this module so the arena,
-- the speeds and the scoring never drift apart between the two sides.

local StrikeConfig = {}

-- Neon palette on a near-black background.
StrikeConfig.Palette = {
	Background = Color3.fromRGB(6, 6, 18),
	Arena = Color3.fromRGB(10, 10, 32),
	Cyan = Color3.fromRGB(0, 240, 255),
	Magenta = Color3.fromRGB(255, 0, 170),
	Yellow = Color3.fromRGB(255, 230, 0),
	White = Color3.fromRGB(235, 245, 255),
	Red = Color3.fromRGB(255, 45, 85),
	Green = Color3.fromRGB(0, 255, 150),
	Orange = Color3.fromRGB(255, 140, 0),
	Purple = Color3.fromRGB(180, 80, 255),
	DimText = Color3.fromRGB(140, 160, 200),
}

-- The playfield. Enemies spawn at the rim and hunt inward.
StrikeConfig.ArenaHalfSize = 68
StrikeConfig.ArenaFloorY = 0

-- Enemy drones hover above the floor so they fly OVER the low cover
-- blocks (cover tops sit at y = 3); the player hides behind cover on
-- the ground, the drones hunt from above.
StrikeConfig.HoverY = {
	Chaser = 5.5,
	Shooter = 5.5,
	Tank = 6.5,
}

-- Player.
StrikeConfig.PlayerMaxHealth = 100
StrikeConfig.PlayerWalkSpeed = 16
StrikeConfig.PlayerSprintSpeed = 26
StrikeConfig.WaveClearHeal = 25

-- Gun.
StrikeConfig.MagazineSize = 30
StrikeConfig.FireCooldown = 0.16 -- seconds between shots
StrikeConfig.ReloadSeconds = 1.8
StrikeConfig.BulletDamage = 1
StrikeConfig.MaxRange = 300

-- Waves. Each wave spawns more drones and tougher ones.
StrikeConfig.WaveBaseEnemyCount = 4
StrikeConfig.WaveEnemyStep = 2
StrikeConfig.WaveMaxAlive = 12
StrikeConfig.SpawnIntervalSeconds = 0.8
StrikeConfig.WaveClearBonus = 150
StrikeConfig.WaveClearBonusPerWave = 50
StrikeConfig.IntermissionSeconds = 5
StrikeConfig.EnemyHealthPerWave = 0.12 -- +12% health per wave, compounded
StrikeConfig.EnemySpeedPerWave = 0.03 -- +3% speed per wave, capped below

-- Scoring and combo. A kill raises the combo; taking a hit resets it.
StrikeConfig.KillScore = 100
StrikeConfig.ComboWindowSeconds = 5
StrikeConfig.ComboStep = 0.5 -- each combo level adds +50% score
StrikeConfig.ComboMaxLevel = 8

-- Spawn points around the arena rim (radius 55, every 45 degrees).
StrikeConfig.SpawnPoints = {}
for i = 0, 7 do
	local a = math.rad(i * 45)
	table.insert(StrikeConfig.SpawnPoints, Vector3.new(math.sin(a) * 55, 0, math.cos(a) * 55))
end

return StrikeConfig

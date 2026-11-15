local StrikeConfig = {}

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

StrikeConfig.ArenaHalfSize = 68
StrikeConfig.ArenaFloorY = 0

StrikeConfig.PlayerMaxHealth = 100
StrikeConfig.PlayerWalkSpeed = 16
StrikeConfig.PlayerSprintSpeed = 26
StrikeConfig.WaveClearHeal = 25
StrikeConfig.ScopeRange = 300

StrikeConfig.Weapons = {
	{ Name = "RIFLE", Damage = 12, Cooldown = 0.16, Mag = 30, Reload = 1.4, Pellets = 1, Spread = 0.012, Range = 300, Color = Color3.fromRGB(0, 240, 255), Barrel = 0.55 },
	{ Name = "SMG", Damage = 8, Cooldown = 0.08, Mag = 40, Reload = 1.1, Pellets = 1, Spread = 0.035, Range = 220, Color = Color3.fromRGB(255, 200, 80), Barrel = 0.35 },
	{ Name = "SHOTGUN", Damage = 7, Cooldown = 0.85, Mag = 6, Reload = 1.9, Pellets = 6, Spread = 0.07, Range = 130, Color = Color3.fromRGB(255, 90, 90), Barrel = 0.6 },
}

StrikeConfig.WaveBaseEnemyCount = 4
StrikeConfig.WaveEnemyStep = 2
StrikeConfig.WaveMaxAlive = 12
StrikeConfig.SpawnIntervalSeconds = 0.8
StrikeConfig.WaveClearBonus = 150
StrikeConfig.WaveClearBonusPerWave = 50
StrikeConfig.IntermissionSeconds = 15
StrikeConfig.EnemyHealthPerWave = 0.12
StrikeConfig.EnemySpeedPerWave = 0.03

StrikeConfig.KillScore = 100
StrikeConfig.ComboWindowSeconds = 5
StrikeConfig.ComboStep = 0.5
StrikeConfig.ComboMaxLevel = 8
StrikeConfig.HeadshotMult = 2
StrikeConfig.KillCredits = 100
StrikeConfig.WaveClearCredits = 300
StrikeConfig.StartCredits = 800
StrikeConfig.CreditCap = 2400
StrikeConfig.Shop = {
	Light = { Name = "LIGHT KEVLAR", Price = 400, Armor = 50 },
	Heavy = { Name = "HEAVY KEVLAR", Price = 800, Armor = 100 },
	Medkit = { Name = "MEDKIT", Price = 300, Heal = 50 },
	Ammo = { Name = "AMMO", Price = 200 },
}

StrikeConfig.SpawnPoints = {}
for i = 0, 7 do
	local a = math.rad(i * 45)
	table.insert(StrikeConfig.SpawnPoints, Vector3.new(math.sin(a) * 55, 0, math.cos(a) * 55))
end

return StrikeConfig

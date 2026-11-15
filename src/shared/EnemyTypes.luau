-- EnemyTypes: the three void-runner types. One table per type; the
-- server reads speed, health, scale, color and behavior from here so
-- a balance change is one number, not a hunt through the server.
-- Enemies are humanoid NPCs (head, torso, arms, legs) that walk the
-- arena floor; Height is the full body height for the health bar.

local StrikeConfig = require(script.Parent.StrikeConfig)

local EnemyTypes = {}

EnemyTypes.Chaser = {
	Name = "Chaser",
	Color = StrikeConfig.Palette.Magenta,
	Scale = 1,
	Height = 4.2,
	Health = 3,
	Speed = 14,
	ContactDamage = 10,
	ContactRadius = 3.5,
	ContactCooldown = 1,
	Score = 1,
}

EnemyTypes.Shooter = {
	Name = "Shooter",
	Color = StrikeConfig.Palette.Orange,
	Scale = 1,
	Height = 4.2,
	Health = 4,
	Speed = 8,
	ContactDamage = 8,
	ContactRadius = 3.5,
	ContactCooldown = 1,
	-- Keeps its distance: closes in past 30 studs, backs off under 20.
	PreferredMin = 20,
	PreferredMax = 30,
	ShotCooldown = 2.5,
	ProjectileSpeed = 45,
	ProjectileDamage = 8,
	Score = 1,
}

EnemyTypes.Tank = {
	Name = "Tank",
	Color = StrikeConfig.Palette.Purple,
	Scale = 1.35,
	Height = 5.7,
	Health = 14,
	Speed = 5,
	ContactDamage = 20,
	ContactRadius = 4.5,
	ContactCooldown = 1,
	Score = 1,
}

-- Wave composition: wave 1 is chasers only, shooters join at wave 2,
-- tanks at wave 3. Weights are the random pick table for later waves.
function EnemyTypes.pickForWave(wave: number): string
	if wave <= 1 then
		return "Chaser"
	end
	local roll = math.random()
	if wave == 2 then
		if roll < 0.6 then
			return "Chaser"
		else
			return "Shooter"
		end
	end
	if roll < 0.5 then
		return "Chaser"
	elseif roll < 0.8 then
		return "Shooter"
	else
		return "Tank"
	end
end

return EnemyTypes

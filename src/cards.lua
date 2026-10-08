local util = require("src.util")

local cards = {}

cards.list = {
    {
        id = "zombie",
        name = "Zombie",
        icon = "Z",
        cost = 3,
        kind = "unit",
        color = colors.green,
        unit = {
            maxHp = 550,
            damage = 80,
            moveSpeed = 7.4,
            attackRange = 2.5,
            attackCooldown = 1.00,
            aggroRange = 27,
            canAttackAir = false,
            targetMode = "any",
        },
    },
    {
        id = "skeleton",
        name = "Skeleton",
        icon = "S",
        cost = 3,
        kind = "unit",
        color = colors.white,
        unit = {
            maxHp = 190,
            damage = 36,
            moveSpeed = 7.5,
            attackRange = 15,
            preferredMinRange = 7,
            attackCooldown = 1.10,
            aggroRange = 30,
            canAttackAir = true,
            targetMode = "any",
            projectileSpeed = 58,
            projectileVisual = "arrow",
        },
    },
    {
        id = "iron_golem",
        name = "Iron Golem",
        icon = "G",
        cost = 5,
        kind = "unit",
        color = colors.lightGray,
        unit = {
            maxHp = 1350,
            damage = 110,
            moveSpeed = 4.2,
            attackRange = 3.0,
            attackCooldown = 1.50,
            aggroRange = 50,
            canAttackAir = false,
            targetMode = "buildings",
        },
    },
    {
        id = "bat_swarm",
        name = "Bat Swarm",
        icon = "B",
        cost = 2,
        kind = "unit",
        color = colors.purple,
        spawnCount = 3,
        spawnRadius = 3.5,
        unit = {
            maxHp = 45,
            damage = 24,
            moveSpeed = 10.0,
            attackRange = 2.2,
            attackCooldown = 0.85,
            aggroRange = 28,
            canAttackAir = true,
            targetMode = "any",
            flying = true,
        },
    },
    {
        id = "cannon",
        name = "Cannon",
        icon = "C",
        cost = 4,
        kind = "building",
        color = colors.gray,
        building = {
            maxHp = 618,
            damage = 64,
            attackRange = 27,
            attackCooldown = 0.95,
            canAttackAir = false,
            projectileSpeed = 48,
            projectileVisual = "cannonball",
            lifetime = 35,
        },
    },
    {
        id = "arrows",
        name = "Arrow Volley",
        icon = "A",
        cost = 4,
        kind = "spell",
        color = colors.yellow,
        placement = "anywhere",
        spell = {
            radius = 9,
            damage = 185,
            towerMultiplier = 0.35,
        },
    },
    {
        id = "creeper",
        name = "Creeper",
        icon = "X",
        cost = 4,
        kind = "unit",
        color = colors.lime,
        unit = {
            maxHp = 400,
            damage = 0,
            moveSpeed = 8.0,
            attackRange = 0,
            attackCooldown = 1.05,
            aggroRange = 27,
            canAttackAir = false,
            targetMode = "any",
            proximityExplosion = {
                triggerRange = 5.0,
                cancelRange = 7.0,
                fuseTime = 1.15,
                radius = 8,
                damage = 290,
            },
        },
    },
    {
        id = "slime",
        name = "Slime",
        icon = "L",
        cost = 3,
        kind = "unit",
        color = colors.lime,
        unit = {
            maxHp = 400,
            damage = 52,
            moveSpeed = 6.4,
            attackRange = 2.6,
            attackCooldown = 1.05,
            aggroRange = 27,
            canAttackAir = false,
            targetMode = "any",
            splitOnDeath = {
                count = 2,
                template = "mini_slime",
            },
        },
    },
    {
        id = "blaze",
        name = "Blaze",
        icon = "F",
        cost = 4,
        kind = "unit",
        color = colors.orange,
        unit = {
            maxHp = 270,
            damage = 64,
            moveSpeed = 7.1,
            attackRange = 17,
            attackCooldown = 1.20,
            aggroRange = 30,
            canAttackAir = true,
            targetMode = "any",
            projectileSpeed = 46,
            projectileVisual = "fireball",
            flying = true,
        },
    },
    {
        id = "witch",
        name = "Witch",
        icon = "W",
        cost = 4,
        kind = "unit",
        color = colors.purple,
        unit = {
            maxHp = 500,
            damage = 38,
            moveSpeed = 5.8,
            attackRange = 16,
            attackCooldown = 1.45,
            aggroRange = 29,
            canAttackAir = true,
            targetMode = "any",
            projectileSpeed = 38,
            projectileVisual = "potion",
            periodicSpawn = {
                template = "baby_zombie",
                interval = 10,
                initialDelay = 4,
                count = 1,
                radius = 3,
                maxAlive = 3,
            },
        },
    },
    {
        id = "enderman",
        name = "Enderman",
        icon = "E",
        cost = 5,
        kind = "unit",
        color = colors.magenta,
        unit = {
            maxHp = 620,
            damage = 95,
            moveSpeed = 7.0,
            attackRange = 2.8,
            attackCooldown = 1.10,
            aggroRange = 34,
            canAttackAir = false,
            targetMode = "any",
            teleport = {
                minRange = 9,
                maxRange = 32,
                cooldown = 6.0,
                stopRange = 3.2,
            },
        },
    },
    {
        id = "spider",
        name = "Spider",
        icon = "P",
        cost = 2,
        kind = "unit",
        color = colors.gray,
        unit = {
            maxHp = 250,
            damage = 38,
            moveSpeed = 10.5,
            attackRange = 2.2,
            attackCooldown = 0.80,
            aggroRange = 28,
            canAttackAir = false,
            targetMode = "any",
        },
    },
    {
        id = "snow_golem",
        name = "Snow Golem",
        icon = "N",
        cost = 3,
        kind = "unit",
        color = colors.white,
        unit = {
            maxHp = 250,
            damage = 26,
            moveSpeed = 5.8,
            attackRange = 18,
            attackCooldown = 1.05,
            aggroRange = 30,
            canAttackAir = true,
            targetMode = "any",
            projectileSpeed = 52,
            projectileVisual = "snowball",
            onHitSlow = {
                factor = 0.80,
                duration = 0.80,
            },
        },
    },
    {
        id = "villager",
        name = "Villager",
        icon = "V",
        cost = 7,
        kind = "unit",
        color = colors.brown,
        unit = {
            maxHp = 185,
            damage = 0,
            moveSpeed = 0,
            attackRange = 0,
            attackCooldown = 1,
            aggroRange = 0,
            canAttackAir = false,
            targetMode = "none",
            passive = true,
            lifetime = 50,
            emeraldBoost = 0.616,
        },
    },
    {
        id = "endermite",
        name = "Endermite",
        icon = "M",
        cost = 1,
        kind = "unit",
        color = colors.purple,
        unit = {
            maxHp = 105,
            damage = 18,
            moveSpeed = 9.2,
            attackRange = 1.8,
            attackCooldown = 0.85,
            aggroRange = 30,
            canAttackAir = false,
            targetMode = "any",
        },
    },
    {
        id = "wolf",
        name = "Wolf",
        icon = "D",
        cost = 3,
        kind = "unit",
        color = colors.lightGray,
        unit = {
            maxHp = 330,
            damage = 62,
            moveSpeed = 10.2,
            attackRange = 2.0,
            attackCooldown = 0.72,
            aggroRange = 28,
            canAttackAir = false,
            targetMode = "any",
        },
    },
    {
        id = "falling_anvil",
        name = "Falling Anvil",
        icon = "H",
        cost = 3,
        kind = "spell",
        color = colors.gray,
        placement = "anywhere",
        spell = {
            radius = 6.05,
            damage = 549,
            towerMultiplier = 0.35,
            delay = 3.0,
            groundOnly = false,
            visual = "anvil",
        },
    },
    {
        id = "nether_portal",
        name = "Nether Portal",
        icon = "O",
        cost = 3,
        kind = "building",
        color = colors.purple,
        building = {
            maxHp = 520,
            damage = 0,
            attackRange = 0,
            attackCooldown = 1,
            canAttackAir = false,
            targetMode = "none",
            passive = true,
            lifetime = 30,
            periodicSpawn = {
                template = "piglin",
                interval = 7.0,
                initialDelay = 2.0,
                count = 1,
                radius = 3,
                maxAlive = 2,
                effect = "portal_spawn",
                sound = "minecraft:block.portal.ambient",
                soundVolume = 0.45,
                soundPitch = 1.0,
            },
        },
    },
}

cards.internalUnits = {
    mini_slime = {
        name = "Mini Slime",
        icon = "l",
        color = colors.lime,
        maxHp = 110,
        damage = 22,
        moveSpeed = 7.3,
        attackRange = 2.2,
        attackCooldown = 0.90,
        aggroRange = 24,
        canAttackAir = false,
        targetMode = "any",
    },
    baby_zombie = {
        name = "Baby Zombie",
        icon = "z",
        color = colors.lime,
        maxHp = 135,
        damage = 27,
        moveSpeed = 9.6,
        attackRange = 1.8,
        attackCooldown = 0.80,
        aggroRange = 25,
        canAttackAir = false,
        targetMode = "any",
    },
    piglin = {
        name = "Piglin",
        icon = "Q",
        color = colors.orange,
        maxHp = 155,
        damage = 28,
        moveSpeed = 7.4,
        attackRange = 13.0,
        attackCooldown = 1.20,
        aggroRange = 30,
        canAttackAir = true,
        targetMode = "any",
        projectileSpeed = 54,
        projectileVisual = "crossbow_bolt",
        lifetime = 10.0,
        hybridAttack = {
            meleeRange = 2.6,
            meleeDamage = 58,
            meleeCooldown = 0.85,
            rangedDamage = 28,
            rangedCooldown = 1.20,
        },
    },
}

cards.byId = {}
for i, card in ipairs(cards.list) do
    card.collectionIndex = i
    cards.byId[card.id] = card
end

local DEFAULT_DECK = {
    "zombie",
    "skeleton",
    "iron_golem",
    "bat_swarm",
    "cannon",
    "arrows",
    "creeper",
    "slime",
}

cards.info = {
    zombie = {
        role = "All-round melee",
        description = "Reliable ground fighter with solid HP and damage. A simple baseline troop for pushes and defense.",
    },
    skeleton = {
        role = "Ranged kiter",
        description = "Fragile ranged unit that attacks air and ground. Tries to keep distance while shooting.",
    },
    iron_golem = {
        role = "Tower tank",
        description = "Huge tank that ignores troops and targets only buildings and towers. Slow but very durable.",
    },
    bat_swarm = {
        role = "Flying swarm",
        description = "Deploys three fast flying bats. Strong when the enemy cannot hit air, but each bat is fragile.",
    },
    cannon = {
        role = "Defensive building",
        description = "Stationary ground-only defense with long range. Excellent for pulling and stopping ground pushes.",
    },
    arrows = {
        role = "Area spell",
        description = "Damages every enemy in a target area anywhere on the arena. Deals reduced damage to towers.",
    },
    creeper = {
        role = "Explosive attacker",
        description = "Runs toward enemies, primes at close range and explodes after a short fuse. Can be killed before detonation.",
    },
    slime = {
        role = "Sticky melee",
        description = "Medium melee troop that splits into two Mini Slimes when killed, forcing the enemy to deal with extra bodies.",
    },
    blaze = {
        role = "Flying ranged",
        description = "Flying ranged attacker that can hit both air and ground. Good support damage but not very durable.",
    },
    witch = {
        role = "Summoner support",
        description = "Ranged support troop that periodically summons Baby Zombies. Becomes stronger the longer she survives.",
    },
    enderman = {
        role = "Backline assassin",
        description = "Melee attacker that teleports toward distant targets. Excellent at reaching vulnerable ranged units.",
    },
    spider = {
        role = "Fast melee",
        description = "Cheap and very fast ground attacker. Useful for pressure, chasing ranged troops and quick defense.",
    },
    snow_golem = {
        role = "Slow support",
        description = "Fragile ranged support that throws snowballs. Hits briefly slow enemy movement and it can attack air.",
    },
    villager = {
        role = "Economy support",
        description = "Stationary non-building unit. Boosts Emerald generation while alive, but is intentionally easy to remove.",
    },
    endermite = {
        role = "Cheap distraction",
        description = "Extremely cheap, fast and fragile melee unit. Best used to pull, distract and kite expensive enemies.",
    },
    wolf = {
        role = "Fast fighter",
        description = "Quick melee fighter with strong attack speed. Useful for punishing ranged troops and applying lane pressure.",
    },
    falling_anvil = {
        role = "Delayed area burst",
        description = "Marks a wide area for 3 seconds, then an anvil crashes down and hits every enemy inside, including flying units. A full-health Zombie survives a direct hit on exactly 1 HP.",
    },
    nether_portal = {
        role = "Spawner building",
        description = "Opens a temporary Nether Portal that periodically sends out short-lived Piglins. Piglins use a crossbow at range and an axe in melee.",
    },
}

function cards.getInfo(id)
    return cards.info[id]
end

function cards.get(id)
    return cards.byId[id]
end

function cards.getInternalUnit(id)
    local unit = cards.internalUnits[id]
    if not unit then return nil end
    return util.deepcopy(unit)
end

function cards.defaultDeck()
    return util.deepcopy(DEFAULT_DECK)
end

function cards.isValidDeck(deck)
    if type(deck) ~= "table" or #deck ~= 8 then return false end

    local seen = {}
    for _, id in ipairs(deck) do
        if not cards.byId[id] or seen[id] then return false end
        seen[id] = true
    end

    return true
end

return cards

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
            maxHp = 520,
            damage = 78,
            moveSpeed = 7.0,
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
            maxHp = 250,
            damage = 58,
            moveSpeed = 7.5,
            attackRange = 18,
            preferredMinRange = 8,
            attackCooldown = 0.90,
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
        cost = 6,
        kind = "unit",
        color = colors.lightGray,
        unit = {
            maxHp = 1450,
            damage = 135,
            moveSpeed = 4.2,
            attackRange = 3.0,
            attackCooldown = 1.40,
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
            maxHp = 115,
            damage = 35,
            moveSpeed = 10.0,
            attackRange = 2.2,
            attackCooldown = 0.75,
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
            maxHp = 760,
            damage = 72,
            attackRange = 29,
            attackCooldown = 0.85,
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
        cost = 3,
        kind = "spell",
        color = colors.yellow,
        placement = "anywhere",
        spell = {
            radius = 12,
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
            maxHp = 390,
            damage = 0,
            moveSpeed = 7.2,
            attackRange = 0,
            attackCooldown = 1.05,
            aggroRange = 27,
            canAttackAir = false,
            targetMode = "any",
            proximityExplosion = {
                triggerRange = 4.0,
                cancelRange = 6.5,
                fuseTime = 1.5,
                radius = 10,
                damage = 300,
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
            maxHp = 460,
            damage = 62,
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
            maxHp = 330,
            damage = 76,
            moveSpeed = 7.1,
            attackRange = 17,
            attackCooldown = 1.05,
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
        cost = 5,
        kind = "unit",
        color = colors.purple,
        unit = {
            maxHp = 560,
            damage = 38,
            moveSpeed = 5.8,
            attackRange = 16,
            attackCooldown = 1.45,
            aggroRange = 29,
            canAttackAir = false,
            targetMode = "any",
            projectileSpeed = 38,
            projectileVisual = "potion",
            periodicSpawn = {
                template = "baby_zombie",
                interval = 8,
                initialDelay = 4,
                count = 1,
                radius = 3,
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
            maxHp = 760,
            damage = 118,
            moveSpeed = 7.0,
            attackRange = 2.8,
            attackCooldown = 1.05,
            aggroRange = 34,
            canAttackAir = false,
            targetMode = "any",
            teleport = {
                minRange = 9,
                maxRange = 32,
                cooldown = 4.5,
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
            maxHp = 350,
            damage = 52,
            moveSpeed = 10.5,
            attackRange = 2.2,
            attackCooldown = 0.75,
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
            maxHp = 300,
            damage = 34,
            moveSpeed = 5.8,
            attackRange = 18,
            preferredMinRange = 7,
            attackCooldown = 0.95,
            aggroRange = 30,
            canAttackAir = true,
            targetMode = "any",
            projectileSpeed = 52,
            projectileVisual = "snowball",
            onHitSlow = {
                factor = 0.65,
                duration = 1.5,
            },
        },
    },
    {
        id = "villager",
        name = "Villager",
        icon = "V",
        cost = 8,
        kind = "unit",
        color = colors.brown,
        unit = {
            maxHp = 620,
            damage = 0,
            moveSpeed = 0,
            attackRange = 0,
            attackCooldown = 1,
            aggroRange = 0,
            canAttackAir = false,
            targetMode = "none",
            passive = true,
            lifetime = 60,
            emeraldBoost = 0.10,
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
        cost = 2,
        kind = "unit",
        color = colors.lightGray,
        unit = {
            maxHp = 315,
            damage = 58,
            moveSpeed = 10.2,
            attackRange = 2.0,
            attackCooldown = 0.72,
            aggroRange = 28,
            canAttackAir = false,
            targetMode = "any",
        },
    },
}

cards.internalUnits = {
    mini_slime = {
        name = "Mini Slime",
        icon = "l",
        color = colors.lime,
        maxHp = 150,
        damage = 30,
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

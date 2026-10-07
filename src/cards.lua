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
            damage = 62,
            moveSpeed = 7.2,
            attackRange = 2.4,
            attackCooldown = 1.05,
            aggroRange = 27,
            canAttackAir = false,
            targetMode = "any",
            deathDamage = {
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
}

cards.byId = {}
for i, card in ipairs(cards.list) do
    card.deckIndex = i
    cards.byId[card.id] = card
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
    local deck = {}
    for i, card in ipairs(cards.list) do
        deck[i] = card.id
    end
    return deck
end

return cards

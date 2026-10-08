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
            maxHp = 523,
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
            maxHp = 168,
            damage = 30,
            moveSpeed = 7.5,
            attackRange = 15.0,
            preferredMinRange = 7,
            retreatSpeedMultiplier = 0.85,
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
            maxHp = 1377,
            damage = 110,
            moveSpeed = 4.2,
            attackRange = 3.0,
            attackCooldown = 1.50,
            aggroRange = 50,
            canAttackAir = false,
            targetMode = "buildings",
        },
        evolution = {
            cycles = 2,
            name = "Diamond Golem",
            color = colors.cyan,
            description = "5% more HP. While walking, every 2s it stomps for 20 damage to nearby grounded enemy units.",
            statMultipliers = {
                maxHp = 1.05,
            },
            abilities = {
                visualVariant = "diamond_golem",
                groundPulse = {
                    interval = 2.0,
                    damage = 20,
                    radius = 8.0,
                    effect = "diamond_quake",
                },
            },
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
            damage = 17,
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
            cast = "arrows",
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
            maxHp = 404,
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
                fuseTime = 0.65,
                radius = 8,
                damage = 290,
            },
        },
        evolution = {
            cycles = 2,
            name = "Charged Creeper",
            color = colors.lightBlue,
            description = "Blue charged form with a larger 12-radius blast and double explosion damage. 4E cost stays unchanged.",
            abilities = {
                visualVariant = "charged_creeper",
                proximityExplosion = {
                    radius = 12,
                    damage = 580,
                    effectKind = "charged_explosion",
                    visualRadius = 16,
                    visualTtl = 0.90,
                    soundVolume = 1.0,
                    soundPitch = 0.82,
                },
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
            maxHp = 257,
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
        cost = 5,
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
                duration = 1.00,
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
        evolution = {
            cycles = 3,
            name = "Emerald Bank",
            color = colors.lime,
            description = "Produces Emeralds at the exact Villager rate, gains 5% HP and remains active 20 seconds longer.",
            statMultipliers = {
                maxHp = 1.05,
            },
            stats = {
                lifetime = 70,
            },
            abilities = {
                visualVariant = "emerald_bank",
            },
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
        evolution = {
            cycles = 4,
            name = "Mega Mite",
            color = colors.magenta,
            description = "Huge Endermite with exactly 5x HP. All other combat stats and the 1E cost stay unchanged.",
            statMultipliers = {
                maxHp = 5.0,
            },
            abilities = {
                visualVariant = "mega_mite",
            },
        },
    },
    {
        id = "guardian",
        name = "Guardian",
        devOnly = true,
        icon = "Q",
        cost = 6,
        kind = "unit",
        color = colors.cyan,
        placement = "water",
        unit = {
            maxHp = 90,
            damage = 0,
            moveSpeed = 0,
            attackRange = 18.0,
            attackCooldown = 0.25,
            aggroRange = 18.0,
            canAttackAir = true,
            targetMode = "any",
            waterOnly = true,
            beam = {
                baseDps = 35,
                maxDps = 350,
                rampSeconds = 4.0,
                tick = 0.25,
                chargeLossOnHit = 0.20,
            },
            spikeReflectFlying = 0.05,
        },
        evolution = {
            cycles = 2,
            name = "Elder Guardian",
            color = colors.lightGray,
            description = "2x HP and slows all enemy movement by 5% while alive. Beam, spikes, range and 6E cost stay unchanged.",
            statMultipliers = {
                maxHp = 2.0,
            },
            abilities = {
                visualVariant = "elder_guardian",
                globalEnemyMoveSlow = 0.05,
            },
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
            cast = "falling_anvil",
            radius = 6.05,
            damage = 549,
            towerMultiplier = 0.35,
            delay = 2.7,
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
            lifetime = 23,
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
        evolution = {
            cycles = 2,
            name = "Ghast Portal",
            color = colors.cyan,
            description = "Turquoise portal spawning exactly 2 Ghasts: fragile long-range flying splash artillery with primary-target slow.",
            abilities = {
                visualVariant = "ghast_portal",
                periodicSpawn = {
                    template = "ghast",
                    interval = 9.0,
                    initialDelay = 2.5,
                    count = 1,
                    radius = 4,
                    maxAlive = 2,
                    maxTotal = 2,
                    effect = "ghast_portal_spawn",
                    sound = "minecraft:entity.ghast.ambient",
                    soundVolume = 0.38,
                    soundPitch = 1.05,
                },
            },
        },
    },
    {
        id = "wither_skeleton",
        name = "Wither Skeleton",
        icon = "Y",
        cost = 3,
        kind = "unit",
        color = colors.gray,
        unit = {
            maxHp = 470,
            damage = 88,
            moveSpeed = 7.4,
            attackRange = 2.5,
            attackCooldown = 1.00,
            aggroRange = 27,
            canAttackAir = false,
            targetMode = "any",
        },
    },
    {
        id = "magma_cube",
        name = "Magma Cube",
        icon = "U",
        cost = 3,
        kind = "unit",
        color = colors.orange,
        unit = {
            maxHp = 380,
            damage = 54.6,
            moveSpeed = 6.4,
            attackRange = 2.6,
            attackCooldown = 1.05,
            aggroRange = 27,
            canAttackAir = false,
            targetMode = "any",
            splitOnDeath = {
                count = 2,
                template = "mini_magma_cube",
            },
        },
    },
    {
        id = "pillager_outpost",
        name = "Pillager Outpost",
        icon = "J",
        cost = 4,
        kind = "building",
        color = colors.brown,
        building = {
            maxHp = 463.5,
            damage = 48,
            attackRange = 27,
            attackCooldown = 0.95,
            canAttackAir = true,
            projectileSpeed = 48,
            projectileVisual = "crossbow_bolt",
            lifetime = 35,
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
    mini_magma_cube = {
        name = "Mini Magma Cube",
        icon = "u",
        color = colors.orange,
        maxHp = 104.5,
        damage = 23.1,
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
    ghast = {
        name = "Ghast",
        icon = "g",
        color = colors.white,
        maxHp = 220,
        damage = 130,
        moveSpeed = 4.8,
        attackRange = 24.0,
        attackCooldown = 2.80,
        aggroRange = 34,
        canAttackAir = true,
        targetMode = "any",
        projectileSpeed = 32,
        projectileVisual = "ghast_fireball",
        projectileSplashRadius = 5.5,
        projectileSplashEffect = "ghast_splash",
        projectileSlowPrimaryOnly = true,
        onHitSlow = {
            factor = 0.65,
            duration = 1.50,
        },
        flying = true,
    },
}

-- Keep experimental/dev cards fully registered for admin and diagnostics,
-- but expose only production-ready cards through cards.list. Normal lobby,
-- random decks, bot/simulation pools and deck validation all consume cards.list.
cards.all = cards.list
cards.list = {}
cards.byId = {}

for _, card in ipairs(cards.all) do
    cards.byId[card.id] = card

    if not card.devOnly then
        card.collectionIndex = #cards.list + 1
        cards.list[#cards.list + 1] = card
    else
        card.collectionIndex = nil
    end
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
        role = "Durable basic melee",
        description = "Reliable 3E ground fighter. Soaks hits well and wins many simple melee trades.",
        goodAgainst = "Spider, Endermite, fragile ground pressure",
        badAgainst = "Skeleton, Snow Golem, Blaze, strong kiting",
    },
    skeleton = {
        role = "Long-range kiter",
        description = "Fragile ranged unit that attacks air and ground and retreats when enemies get too close.",
        goodAgainst = "slow melee, Guardian, Iron Golem support pushes",
        badAgainst = "Arrows, Spider, Enderman, fast gap closers",
    },
    iron_golem = {
        role = "Building-focused tank",
        description = "Huge tank that ignores troops and walks only toward buildings and Crown Towers.",
        goodAgainst = "Cannon, Outpost, exposed Crown Towers",
        badAgainst = "Guardian, kiting buildings, high sustained damage",
    },
    bat_swarm = {
        role = "Flying swarm",
        description = "Three fast fragile flying attackers. Excellent DPS when the enemy lacks anti-air.",
        goodAgainst = "Iron Golem, Creeper, ground-only attackers",
        badAgainst = "Arrows, Blaze, Snow Golem, Pillager Outpost",
    },
    cannon = {
        role = "Ground defense",
        description = "Stationary ground-only defense that pulls and burns down approaching ground pushes.",
        goodAgainst = "Iron Golem, Zombie, Wither Skeleton, ground pressure",
        badAgainst = "Bat Swarm, Blaze, spells, air-heavy decks",
    },
    arrows = {
        role = "Instant area spell",
        description = "Immediate arena-targeted AoE. Excellent at removing fragile groups; reduced Crown Tower damage.",
        goodAgainst = "Bat Swarm, Skeleton, Spider, Endermite",
        badAgainst = "high-HP tanks, low-value single targets",
    },
    creeper = {
        role = "Kamikaze burst",
        description = "Runs into range, primes for 0.65s and explodes. Kill it before the fuse ends to deny the blast.",
        goodAgainst = "clustered ground units, grouped pushes",
        badAgainst = "Skeleton, Blaze, ranged focus fire",
    },
    slime = {
        role = "Split melee",
        description = "Medium melee body that becomes two Mini Slimes on death, forcing extra attacks to fully clear.",
        goodAgainst = "single-target attackers, attrition fights",
        badAgainst = "AoE spells, splash damage, strong ranged DPS",
    },
    blaze = {
        role = "Flying ranged support",
        description = "Fragile long-range flying damage dealer that attacks both air and ground from safety.",
        goodAgainst = "ground melee, slow pushes, unsupported tanks",
        badAgainst = "Skeleton, Arrows, Pillager Outpost, fast pressure",
    },
    witch = {
        role = "Summoner support",
        description = "Ranged support that attacks air/ground and continuously adds Baby Zombies during long fights.",
        goodAgainst = "slow pushes, single-target defenders, long fights",
        badAgainst = "Enderman, Falling Anvil, focused burst",
    },
    enderman = {
        role = "Backline assassin",
        description = "Teleports onto distant targets to bypass the frontline and punish vulnerable support units.",
        goodAgainst = "Skeleton, Witch, Snow Golem, ranged backlines",
        badAgainst = "Zombie, Slime, Magma Cube, durable melee",
    },
    spider = {
        role = "Fast melee pressure",
        description = "Cheap fast ground attacker that closes distance quickly and punishes fragile ranged units.",
        goodAgainst = "Skeleton, Snow Golem, fragile support",
        badAgainst = "Zombie, Wolf, Slime, AoE",
    },
    snow_golem = {
        role = "Ranged slow control",
        description = "Air/ground ranged support whose hits slow movement by 20%, helping your side control spacing.",
        goodAgainst = "slow melee, tanks, units that need to close distance",
        badAgainst = "Enderman, Spider, fast assassins",
    },
    villager = {
        role = "Emerald economy",
        description = "Stationary investment that increases Emerald generation by 61.6% while it survives.",
        goodAgainst = "slow passive games where it can survive",
        badAgainst = "early pressure, burst spells, direct lane aggression",
    },
    endermite = {
        role = "1E distraction",
        description = "Ultra-cheap fast body for pulling targets, cycling the deck and wasting expensive attacks.",
        goodAgainst = "slow single-target units, target pulling, cycle",
        badAgainst = "any AoE, towers, efficient swarm clear",
    },
    guardian = {
        role = "Water tank melter",
        description = "River-only Inferno beam with 18 range. Damage ramps while locked; hits reduce charge by 20%.",
        goodAgainst = "Iron Golem, high-HP tanks, slow expensive pushes",
        badAgainst = "Arrows, Skeleton, long-range focus fire",
    },
    wolf = {
        role = "Fast single-target fighter",
        description = "Fast ground melee with high attack speed. Strong at collapsing on exposed fragile units.",
        goodAgainst = "Skeleton, Snow Golem, Witch, fragile support",
        badAgainst = "tanks, swarms, strong defensive structures",
    },
    falling_anvil = {
        role = "Delayed area burst",
        description = "After a 2.7s warning, crushes every enemy in its radius for 549 damage, including flying units.",
        goodAgainst = "clustered pushes, support stacks, buildings",
        badAgainst = "fast moving units, spread formations, prediction misses",
    },
    nether_portal = {
        role = "Piglin spawner",
        description = "Passive building that creates three temporary Piglins with ranged anti-air and stronger ground melee.",
        goodAgainst = "slow value wars, mixed air/ground pressure",
        badAgainst = "burst damage, building focus, strong spell value",
    },
    wither_skeleton = {
        role = "Damage melee",
        description = "Zombie sidegrade with less HP but more hit damage. Trades durability for faster kills.",
        goodAgainst = "fragile melee, medium-health ground units",
        badAgainst = "kiting, flying units, ranged focus",
    },
    magma_cube = {
        role = "Damage split melee",
        description = "Slime sidegrade with slightly less HP and more damage before and after splitting.",
        goodAgainst = "single-target defenders, attrition, weak melee",
        badAgainst = "AoE spells, splash, ranged control",
    },
    pillager_outpost = {
        role = "Air + ground defense",
        description = "Defensive structure with lower stats than Cannon but the major advantage of shooting air and ground.",
        goodAgainst = "Bat Swarm, Blaze, mixed pushes",
        badAgainst = "Iron Golem, spells, heavy building pressure",
    },
}
function cards.getInfo(id)
    return cards.info[id]
end

function cards.get(id)
    return cards.byId[id]
end

function cards.isSelectable(cardOrId)
    local card = type(cardOrId) == "table" and cardOrId or cards.byId[cardOrId]
    return card ~= nil and card.devOnly ~= true
end

-- Evolution definitions are intentionally data-driven and live on the base
-- card as card.evolution. Cards without that table cannot enter the Evolution
-- Slot.
--
-- Every card may independently configure:
--   cycles        Number of normal successful plays before the evolved play.
--                 0 = every play is evolved, 1 = every second play, etc.
--   cost          Exact evolved Emerald cost, or a table with set/multiplier/
--                 delta. Shorthands costMultiplier and costDelta also work.
--   card/unit/... Numeric multipliers and direct overrides (legacy + explicit).
--   stats         Exact stat overrides on the active unit/building/spell data.
--   statMultipliers Numeric multipliers on active unit/building/spell stats.
--   abilities     Deep-merged ability data on unit/building/spell. This can
--                 add or replace any mechanic already understood by Game.lua
--                 (teleport, slow, split, proximity explosion, summons, etc.).
--   patch         Deep-merged into the whole evolved card for advanced cases.
--
-- Example:
-- evolution = {
--     cycles = 3,                 -- fourth successful play evolves
--     cost = { delta = 1 },       -- 3E base -> 4E evolved play
--     name = "Evolved Zombie",
--     statMultipliers = {
--         maxHp = 1.15,
--         damage = 1.10,
--     },
--     abilities = {
--         onHitSlow = { factor = 0.8, duration = 1.5 },
--     },
-- }
local function evolutionCard(cardOrId)
    if type(cardOrId) == "table" then return cardOrId end
    return cards.byId[cardOrId]
end

function cards.hasEvolution(cardOrId)
    local card = evolutionCard(cardOrId)
    return card ~= nil and type(card.evolution) == "table"
end

function cards.evolutionCycles(cardOrId)
    local card = evolutionCard(cardOrId)
    if not card or type(card.evolution) ~= "table" then return nil end

    local value = card.evolution.cycles
    if value == nil then value = card.evolution.normalPlays end
    if value == nil then value = 2 end

    return math.max(0, math.floor(tonumber(value) or 2))
end

function cards.evolutionPlayNumber(cardOrId)
    local cycles = cards.evolutionCycles(cardOrId)
    if cycles == nil then return nil end
    return cycles + 1
end

local function deepMerge(target, patch)
    if type(target) ~= "table" or type(patch) ~= "table" then return end

    for key, value in pairs(patch) do
        if type(value) == "table" and type(target[key]) == "table" then
            deepMerge(target[key], value)
        else
            target[key] = util.deepcopy(value)
        end
    end
end

local function applyEvolutionBlock(target, spec)
    if type(target) ~= "table" or type(spec) ~= "table" then return end

    if type(spec.multipliers) == "table" then
        for key, multiplier in pairs(spec.multipliers) do
            if type(target[key]) == "number" and type(multiplier) == "number" then
                target[key] = target[key] * multiplier
            end
        end
    end

    if type(spec.overrides) == "table" then
        for key, value in pairs(spec.overrides) do
            target[key] = util.deepcopy(value)
        end
    end
end

local function activePayload(card)
    if not card then return nil end
    if card.kind == "unit" then return card.unit end
    if card.kind == "building" then return card.building end
    if card.kind == "spell" then return card.spell end
    return nil
end

local function applyNumericMultipliers(target, multipliers)
    if type(target) ~= "table" or type(multipliers) ~= "table" then return end

    for key, multiplier in pairs(multipliers) do
        if type(target[key]) == "number" and type(multiplier) == "number" then
            target[key] = target[key] * multiplier
        end
    end
end

local function applyExactStats(target, stats)
    if type(target) ~= "table" or type(stats) ~= "table" then return end

    for key, value in pairs(stats) do
        target[key] = util.deepcopy(value)
    end
end

local function resolveEvolutionCost(baseCost, evo, fallbackCost)
    local cost = tonumber(fallbackCost) or tonumber(baseCost) or 0
    local hasExplicitCostRule = false

    if type(evo.costMultiplier) == "number" then
        cost = (tonumber(baseCost) or cost) * evo.costMultiplier
        hasExplicitCostRule = true
    end

    if type(evo.costDelta) == "number" then
        if not hasExplicitCostRule then cost = tonumber(baseCost) or cost end
        cost = cost + evo.costDelta
        hasExplicitCostRule = true
    end

    if type(evo.cost) == "number" then
        cost = evo.cost
        hasExplicitCostRule = true
    elseif type(evo.cost) == "table" then
        local spec = evo.cost
        local base = tonumber(baseCost) or cost

        if type(spec.multiplier) == "number" then
            cost = base * spec.multiplier
            hasExplicitCostRule = true
        else
            cost = base
        end

        if type(spec.delta) == "number" then
            cost = cost + spec.delta
            hasExplicitCostRule = true
        end

        if type(spec.set) == "number" then
            cost = spec.set
            hasExplicitCostRule = true
        end
    end

    if not hasExplicitCostRule then
        cost = tonumber(fallbackCost) or tonumber(baseCost) or 0
    end

    return math.max(0, cost)
end

function cards.evolvedCopy(cardOrId)
    local card = evolutionCard(cardOrId)
    if not card or type(card.evolution) ~= "table" then return nil end

    local evolved = util.deepcopy(card)
    local evo = card.evolution

    evolved.isEvolution = true
    evolved.evolutionBaseId = card.id
    evolved.name = evo.name or ("Evolved " .. tostring(card.name or card.id))
    evolved.icon = evo.icon or card.icon
    evolved.color = evo.color or card.color

    -- Existing per-section format remains supported.
    applyEvolutionBlock(evolved, evo.card)
    applyEvolutionBlock(evolved.unit, evo.unit)
    applyEvolutionBlock(evolved.building, evo.building)
    applyEvolutionBlock(evolved.spell, evo.spell)

    -- New concise format applies to whichever payload this card actually uses.
    local payload = activePayload(evolved)
    applyNumericMultipliers(payload, evo.statMultipliers)
    applyExactStats(payload, evo.stats)

    -- Ability data is deep-merged, so an evolution can add a complete existing
    -- mechanic or change only one property of an inherited mechanic.
    if payload and type(evo.abilities) == "table" then
        deepMerge(payload, evo.abilities)
    end

    -- Advanced whole-card patch supports spawnCount, placement, nested custom
    -- data and future mechanics without changing this evolution helper.
    if type(evo.patch) == "table" then
        deepMerge(evolved, evo.patch)
    end

    evolved.cost = resolveEvolutionCost(card.cost, evo, evolved.cost)

    if evolved.unit then evolved.unit.isEvolution = true end
    if evolved.building then evolved.building.isEvolution = true end
    if evolved.spell then evolved.spell.isEvolution = true end

    return evolved
end

function cards.evolutionCost(cardOrId)
    local evolved = cards.evolvedCopy(cardOrId)
    return evolved and evolved.cost or nil
end

function cards.evolutionCards(includeDevOnly)
    local out = {}
    local source = includeDevOnly and cards.all or cards.list

    for _, card in ipairs(source) do
        if cards.hasEvolution(card) then out[#out + 1] = card end
    end
    return out
end

function cards.adminSpawnCards()
    local out = {}

    for _, card in ipairs(cards.all) do
        out[#out + 1] = {
            key = card.id,
            card = card,
            isEvolution = false,
        }
    end

    for _, card in ipairs(cards.evolutionCards(true)) do
        local evolved = cards.evolvedCopy(card)
        if evolved then
            out[#out + 1] = {
                key = "evo:" .. card.id,
                card = evolved,
                baseId = card.id,
                isEvolution = true,
            }
        end
    end

    return out
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
        if not cards.isSelectable(id) or seen[id] then return false end
        seen[id] = true
    end

    return true
end

return cards

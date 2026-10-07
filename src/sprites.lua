local sprites = {}

-- Small, deliberately simple ASCII sprites for CC:Tweaked's 0.5 text scale.
-- "." is transparent. All other cells are rendered on a dark badge so mobs
-- remain visible on grass/water.

local defs = {
    zombie = {
        rows = {
            " Z ",
            "/|\\",
        },
    },
    skeleton = {
        rows = {
            " o ",
            "/S\\",
        },
    },
    iron_golem = {
        rows = {
            "[G]",
            "/|\\",
            "/ \\",
        },
    },
    bat_swarm = {
        rows = {
            "<B>",
        },
    },
    cannon = {
        rows = {
            "=> ",
            "[C]",
        },
    },
    creeper = {
        rows = {
            "[X]",
            "/ \\",
        },
    },
    slime = {
        rows = {
            "___",
            "[L]",
        },
    },
    mini_slime = {
        rows = {
            "[l]",
        },
    },
    arrows = {
        rows = {
            "\\|/",
            " A ",
        },
    },
    princess_tower = {
        rows = {
            " ^ ",
            "[T]",
            "/_\\",
        },
        tower = true,
    },
    king_tower = {
        rows = {
            "^K^",
            "[#]",
            "/_\\",
        },
        tower = true,
    },
    unknown = {
        rows = {
            "[?]",
        },
    },
}

local entityKeyByName = {
    ["Zombie"] = "zombie",
    ["Skeleton"] = "skeleton",
    ["Iron Golem"] = "iron_golem",
    ["Bat Swarm"] = "bat_swarm",
    ["Cannon"] = "cannon",
    ["Creeper"] = "creeper",
    ["Slime"] = "slime",
    ["Mini Slime"] = "mini_slime",
}

local function normalize(def)
    local width = 1
    for _, row in ipairs(def.rows) do
        width = math.max(width, #row)
    end
    def.width = width
    def.height = #def.rows
    return def
end

for _, def in pairs(defs) do
    normalize(def)
end

function sprites.forEntity(entity)
    if entity.kind == "tower" then
        if entity.towerType == "king" then
            return defs.king_tower
        end
        return defs.princess_tower
    end

    local key = entityKeyByName[entity.name]
    return defs[key] or defs.unknown
end

function sprites.forCard(card)
    if not card then return defs.unknown end
    return defs[card.id] or defs.unknown
end

function sprites.get(id)
    return defs[id] or defs.unknown
end

return sprites

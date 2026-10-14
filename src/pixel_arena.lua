local config = require("config")
local pixelbox = require("lib.pixelbox_lite")

local pixelArena = {}

local A = config.ARENA
local cache = setmetatable({}, { __mode = "k" })

local PALETTE = {
    K = colors.black,
    W = colors.white,
    S = colors.lightGray,
    D = colors.gray,
    G = colors.green,
    L = colors.lime,
    B = colors.blue,
    A = colors.lightBlue,
    C = colors.cyan,
    R = colors.red,
    Y = colors.yellow,
    N = colors.brown,
    P = colors.purple,
    M = colors.magenta,
    O = colors.orange,
    I = colors.pink,
}

local SPRITES = {
    -- Approved model revamp, adapted to the native ComputerCraft palette.
    -- T is the viewing player's team colour; dots leave terrain visible.
    zombie = {
        rows = {
            "..LLLLL..",
            "..LKLKL..",
            "..LLLLL..",
            "..LLGLL..",
            ".CCCCCCC.",
            "CC.CCC.CC",
            "LL.CBC.LL",
            "...BBB...",
            "...PPP...",
            "..PP.PP..",
            "..PP.PP..",
            ".PPP.PPP.",
        },
    },
    skeleton = {
        rows = {
            "...WWWWW...",
            "...WKWKW...",
            "...WWWWW...",
            "...WWKWW...",
            ".N...W.....",
            "N..WWWWW...",
            "N.W.W.W.W..",
            "N.WWWWW.W..",
            ".N..W.W.W..",
            "..N.WWW....",
            "....W.W....",
            "....W.W....",
            "...WW.WW...",
        },
    },
    wither_skeleton = {
        rows = {
            "...DDDDD....",
            "...DKDKD....",
            "...DKKKD....",
            "...DDKDD....",
            ".....D......",
            "....DDD...S.",
            "..DDDDDDDSS.",
            "..D.D.D.DS..",
            "..D.DDD.DS..",
            "..D.D.D.D...",
            "....DDD.....",
            "....D.D.....",
            "....D.D.....",
            "....D.D.....",
            "...DD.DD....",
        },
    },
    iron_golem = {
        rows = {
            "...WWWWW...",
            "...WRWRW...",
            "...WWWWW...",
            "...WWSWW...",
            "SSGWWWWWWSS",
            "SW.GWWWW.WS",
            "SW.WGWWW.WS",
            "SW.WWGWW.WS",
            "SW.WWWWW.WS",
            "SW..WWW..WS",
            "SS..WWW..SS",
            "....WWW....",
            "...WW.WW...",
            "...WS.SW...",
            "..WWS.SWW..",
        },
    },
    diamond_golem = {
        rows = {
            "...AAAAA...",
            "...AKAKA...",
            "...AAAAA...",
            "...AACAA...",
            "CWAAAAAAAWC",
            "CA.AAWAA.AC",
            "CA.AWAWA.AC",
            "CA.AACAA.AC",
            "CA.AAAAA.AC",
            "CA..AAA..AC",
            "CW..AAA..WC",
            "....ACA....",
            "...AA.AA...",
            "...AC.CA...",
            "..AAC.CAA..",
        },
    },
    bat_swarm = {
        rows = {
            "N...N...N...N",
            "NN..NNNNN..NN",
            "NNN.NKSKN.NNN",
            "NNNNNNNNNNNNN",
            ".DDNNNNNNNDD.",
            "...DPNNNPD...",
            ".....NNN.....",
        },
    },
    cannon = {
        rows = {
            ".......SSSS.",
            ".....SSDKDS.",
            "...SSSSDKDS.",
            "..SSSDDDSSS.",
            ".NSSDDDSS...",
            "NNNNNNNNNN..",
            "NDDNNNNDDN..",
            "DKDNNNNDKD..",
            "DDD....DDD..",
        },
    },
    pillager_outpost = {
        rows = {
            "....NNN....",
            "..NNNNNNN..",
            ".NNDDDDDNN.",
            "NNNNNNNNNNN",
            "..N.KKK.N..",
            "..N.KKK.N..",
            "..N.KKK.N..",
            ".NNNNNNNNN.",
            "..SSNNNSS..",
            "..SSNKNSS..",
            "..SSNKNSS..",
            "..SSNKNSS..",
            ".SSSNNNSSS.",
        },
    },
    creeper = {
        rows = {
            ".LLLLLLL.",
            ".LKLLLKL.",
            ".LLLLLLL.",
            ".LLLKLLL.",
            ".LLKKKLL.",
            ".LLKLKLL.",
            "...LLL...",
            "...LGL...",
            "...LLL...",
            "...GLL...",
            "..LL.LL..",
            "..LG.LG..",
            ".LLL.LLL.",
        },
    },
    charged_creeper = {
        rows = {
            ".A.........C.",
            "C...........A",
            ".A...........",
            "...LLLLLLL...",
            "C..LKLLLKL...",
            "...LLLLLLL..A",
            ".A.LLLKLLL...",
            "C..LLKKKLL...",
            ".A.LLKLKLL..C",
            ".....LLL...A.",
            ".....LGL....C",
            "A....LLL.....",
            ".....GLL....A",
            "....LL.LL....",
            "....LG.LG....",
            "...LLL.LLL...",
            ".............",
        },
    },
    slime = {
        rows = {
            ".LLLLL.",
            "LLLLLLL",
            "LGGGGGL",
            "LGKGKGL",
            "LGGGGGL",
            "LGGKGGL",
            "LLLLLLL",
        },
    },
    mini_slime = {
        rows = {
            "LLLL",
            "LKLK",
            "LLGL",
            "GGGG",
        },
    },
    magma_cube = {
        rows = {
            "NNNNNNN",
            "NRNNNRN",
            "NYNNNYN",
            "NNNNNNN",
            "ROOROOR",
            "NNRNRNN",
            "RNNONNR",
        },
    },
    mini_magma_cube = {
        rows = {
            "NNNN",
            "NYNY",
            "NRON",
            "RNNR",
        },
    },
    baby_zombie = {
        rows = {
            ".LLLLL.",
            ".LKLKL.",
            ".LLGLL.",
            "LCCCCCL",
            "L.CBC.L",
            "..PPP..",
            "..P.P..",
            ".PP.PP.",
        },
    },
    blaze = {
        rows = {
            "....YYYYY....",
            "..Y.YKYKY.Y..",
            "..Y.YYYYY.Y..",
            "......O......",
            "Y.....O.....Y",
            "Y..Y.....Y..Y",
            "...Y..O..Y...",
            ".Y....Y....Y.",
            ".Y....Y....Y.",
            "....O...O....",
        },
    },
    witch = {
        rows = {
            "....K.......",
            "...KPK......",
            "...PPP......",
            "..PPGPP.....",
            ".PPPPPPP....",
            ".PPPPPPP....",
            "...OOOOO....",
            "...OKOKO....",
            "...OOOOO....",
            "....ONO..W..",
            "..PPPPP.MMM.",
            "..PPPPP.MWM.",
            "..P.PPP.MMM.",
            "....PPP.....",
            "...PPPPP....",
            "...K...K....",
        },
    },
    evoker = {
        rows = {
            "...SSSSS...",
            "...SKSKS...",
            "...SSSSS...",
            "...SSNSS...",
            "....SNS....",
            "S.........S",
            "YKK.....KKY",
            "..KKYKYKK..",
            "...KYKYK...",
            "...KKYKK...",
            "...KKYKK...",
            "...KYKYK...",
            "..KYY.YYK..",
            "..KK...KK..",
        },
    },
    vex = {
        rows = {
            "W..AAAAA..W",
            ".W.ARARA.W.",
            "..WAAAAAW..",
            "...AAAA....",
            "S..AAAAA...",
            ".SAA.A.AA..",
            "..S..A.....",
            "....A.A....",
            ".....A.....",
        },
    },
    enderman = {
        rows = {
            "..KKKKK..",
            "..KPKPK..",
            "..KKKKK..",
            "..DKKKD..",
            ".D.KKK.D.",
            ".K.KDK.K.",
            ".K.KDK.K.",
            ".K.KKK.K.",
            ".K.KKK.K.",
            ".K.KKK.K.",
            ".K.KKK.K.",
            ".K.K.K.K.",
            ".D.K.K.D.",
            "...K.K...",
            "...K.K...",
            "...K.K...",
            "...D.D...",
        },
    },
    spider = {
        rows = {
            "....NNNNN....",
            "...DNNNNND...",
            "DD.DNNNNND.DD",
            "..DNDRRRDND..",
            ".DNDDKRKDDND.",
            "D.N..DDD..N.D",
            "D.N.......N.D",
            "..D.......D..",
        },
    },
    snow_golem = {
        rows = {
            "...OOOOO...",
            "...OKOKO...",
            "...OOKOO...",
            "...OKKKO...",
            ".....W.....",
            ".NN.WWW.NN.",
            "N..WWKWW..N",
            "...WWWWW...",
            "..WWWKWWW..",
            "..WWWWWWW..",
            "..WWWWWWS..",
        },
    },
    guardian = {
        rows = {
            "...O...O.....",
            "..OCCCCCO....",
            ".CCCCCCCCCO..",
            "OCCCWWWCCCC..",
            ".CCCWKWCCCC..",
            "OCCCWWWCCCC..",
            ".CCCCCCCCC.CC",
            "..OCCCCCO.CC.",
            "...O...O...C.",
        },
    },
    elder_guardian = {
        rows = {
            "....N...N......",
            "...NSSSSSN.....",
            "..SSSSSSSSSN...",
            ".NSSSWWWSSSS...",
            "NSSSSWKWSSSS...",
            ".SSSSWWWSSSS...",
            "NSSSSWWWSSSS...",
            ".SSSDDDDDSSS.SS",
            "..SSSSSSSSSSSS.",
            "...NSSSSSN..SS.",
            "....N...N....S.",
        },
    },
    villager = {
        rows = {
            "..OOOOO..",
            "..OGOGO..",
            "..OOOOO..",
            "..OONOO..",
            "...ONO...",
            "...ONO...",
            ".NNNNNNN.",
            ".NNOOONN.",
            "..NNNNN..",
            "..NNNNN..",
            "..NNNNN..",
            "..NNNNN..",
            "..DD.DD..",
        },
    },
    emerald_bank = {
        rows = {
            ".....L.....",
            "....LWL....",
            "....LGL....",
            "..SSLGLSS..",
            ".SSSSLSSSS.",
            "SSSSSSSSSSS",
            "LGGGGGGGGGL",
            "SGSSDDDSSGS",
            "SGSSDKDSSGS",
            "SGSSDKDSSGS",
            "SGSSDKDSSGS",
            "SSSSDKDSSSS",
            "SSSSSSSSSSS",
        },
    },
    endermite = {
        rows = {
            "..PPPP...",
            ".PMPPPP..",
            "RRPDPDPP.",
            ".P.P.P.P.",
        },
    },
    mega_mite = {
        rows = {
            "...PPPPPP....",
            "..PMPMPPPP...",
            ".PPDPPDPPPP..",
            "RRPDPPDPPDPP.",
            ".PPPPPPPPPPP.",
            "..P.P.P.P.P..",
        },
    },
    wolf = {
        rows = {
            "S.S..........S.",
            "S.S..........SS",
            "SSSS........SS.",
            "SKSSSRSSSSSSS..",
            "SSSSSRSSSSSSD..",
            "SSKSSRSSSSSSD..",
            "...SSSSSSSSS...",
            "...S.D..S.D....",
            "..SS.D.SS.D....",
        },
    },
    nether_portal = {
        rows = {
            "..PPKPP..",
            ".PKKKKKP.",
            ".KMPMPMK.",
            ".KPMMPMK.",
            ".KMMMPMK.",
            ".KMMPMMK.",
            ".KPMPMMK.",
            ".KMMPMPK.",
            ".KMPMMPK.",
            ".KMPMMMK.",
            ".KPMMMPK.",
            ".PKKKKKP.",
            "PPKKKKKPP",
        },
    },
    ghast_portal = {
        rows = {
            "..CCCCCCC..",
            ".CWWAAAWCC.",
            ".CAAAAAAAC.",
            ".CAWWWWWAC.",
            ".CAWKWKWAC.",
            ".CAWWWWWAC.",
            ".CAAWWWAAC.",
            ".CAWAWAWAC.",
            ".CAAAAAAAC.",
            ".CAAWAAAAC.",
            ".CAAAAAWAC.",
            ".CAAAAAAAC.",
            ".CCAAAAACC.",
            "CCWCCCCCWCC",
        },
    },
    ghast = {
        rows = {
            ".WWWWWWWWW.",
            "WWWWWWWWWWS",
            "WWWWWWWWWWS",
            "WSSWWWSSWWS",
            "WKWWWWWKWWS",
            "WWSSWSSWWWS",
            ".WWWKWWWWW.",
            "..W.W.W.W..",
            "..W.W.W.W..",
            "..W...W.W..",
            "...W..W....",
        },
    },
    piglin = {
        rows = {
            "..IIIII....",
            ".IIKIKII...",
            "..IIIII....",
            "...INNI....",
            "..NNNNN..Y.",
            ".ONNYNNOYY.",
            ".O.NNY.N.Y.",
            "...NNNN....",
            "...NNNN....",
            "...O.O.....",
            "..NN.NN....",
        },
    },
    princess_tower = {
        rows = {
            ".....NTTT..",
            ".....NTT...",
            ".....N.....",
            "S.S.S.S.S..",
            "SSSSSSSSS..",
            ".SWWWWWWS..",
            ".SWWWWTWS..",
            ".SWWKWTWS..",
            ".SWWKWTWS..",
            ".SWWWWTWS..",
            ".SWWWWTWS..",
            ".SWWWWWWS..",
            "SSSSSSSSSS.",
        },
    },
    king_tower = {
        rows = {
            "...Y.Y.Y...",
            "...YYYYY...",
            "S.SSSSSSS.S",
            "SSSSSSSSSSS",
            "SWWSWWWSWWS",
            "SWTSWWWSTWS",
            "SWTSWKWSTWS",
            "SWTSWKWSTWS",
            "SWTSWWWSTWS",
            "SWWSWWWSWWS",
            "SWWWWKWWWWS",
            "SWWWKKKWWWS",
            "SWWWKKKWWWS",
            "SSSSKKKSSSS",
            "SSSSSSSSSSS",
        },
    },
}

local NAME_TO_SPRITE = {
    ["Zombie"] = "zombie",
    ["Skeleton"] = "skeleton",
    ["Wither Skeleton"] = "wither_skeleton",
    ["Iron Golem"] = "iron_golem",
    ["Bat Swarm"] = "bat_swarm",
    ["Cannon"] = "cannon",
    ["Pillager Outpost"] = "pillager_outpost",
    ["Creeper"] = "creeper",
    ["Slime"] = "slime",
    ["Mini Slime"] = "mini_slime",
    ["Magma Cube"] = "magma_cube",
    ["Mini Magma Cube"] = "mini_magma_cube",
    ["Baby Zombie"] = "baby_zombie",
    ["Blaze"] = "blaze",
    ["Witch"] = "witch",
    ["Evoker"] = "evoker",
    ["Vex"] = "vex",
    ["Enderman"] = "enderman",
    ["Spider"] = "spider",
    ["Snow Golem"] = "snow_golem",
    ["Guardian"] = "guardian",
    ["Elder Guardian"] = "elder_guardian",
    ["Villager"] = "villager",
    ["Emerald Bank"] = "emerald_bank",
    ["Endermite"] = "endermite",
    ["Mega Mite"] = "mega_mite",
    ["Wolf"] = "wolf",
    ["Nether Portal"] = "nether_portal",
    ["Ghast Portal"] = "ghast_portal",
    ["Piglin"] = "piglin",
    ["Ghast"] = "ghast",
}

local function normalizeSprites()
    for _, sprite in pairs(SPRITES) do
        local width = 1
        for _, row in ipairs(sprite.rows) do width = math.max(width, #row) end
        sprite.width = width
        sprite.height = #sprite.rows
    end
end
normalizeSprites()

local function spriteFor(entity)
    if entity.visualVariant and SPRITES[entity.visualVariant] then
        return SPRITES[entity.visualVariant]
    end
    if entity.kind == "tower" then
        return entity.towerType == "king" and SPRITES.king_tower or SPRITES.princess_tower
    end
    return SPRITES[NAME_TO_SPRITE[entity.name]] or SPRITES.zombie
end

local function getSurface(monitor, rect)
    local w = rect.x2 - rect.x1 + 1
    local h = rect.y2 - rect.y1 + 1
    local cached = cache[monitor]

    if not cached
        or cached.x ~= rect.x1
        or cached.y ~= rect.y1
        or cached.w ~= w
        or cached.h ~= h
    then
        local win = window.create(monitor, rect.x1, rect.y1, w, h, true)
        win.setBackgroundColor(colors.black)
        win.clear()

        cached = {
            x = rect.x1,
            y = rect.y1,
            w = w,
            h = h,
            window = win,
            box = pixelbox.new(win, colors.green),
            lastBlitLines = {},
        }

        -- PixelBox still calculates the exact same image every frame, but
        -- unchanged text rows need not be transmitted to the monitor again.
        -- A thin terminal proxy handles this without modifying the bundled
        -- third-party PixelBox library or affecting its color selection.
        local cursorX, cursorY = 1, 1
        cached.box.term = {
            setCursorPos = function(x, y)
                cursorX, cursorY = x, y
            end,
            blit = function(chars, foreground, background)
                local signature = chars .. "\0" .. foreground .. "\0" .. background
                if cursorX ~= 1 or cached.lastBlitLines[cursorY] ~= signature then
                    win.setCursorPos(cursorX, cursorY)
                    win.blit(chars, foreground, background)
                    if cursorX == 1 then
                        cached.lastBlitLines[cursorY] = signature
                    else
                        cached.lastBlitLines[cursorY] = nil
                    end
                end
            end,
        }
        cache[monitor] = cached
    end

    return cached.box, cached
end

local function put(box, x, y, color)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if x >= 1 and x <= box.width and y >= 1 and y <= box.height then
        box.canvas[y][x] = color
    end
end

local function fillRect(box, x1, y1, x2, y2, color)
    x1 = math.max(1, math.floor(x1))
    y1 = math.max(1, math.floor(y1))
    x2 = math.min(box.width, math.ceil(x2))
    y2 = math.min(box.height, math.ceil(y2))
    for y = y1, y2 do
        local row = box.canvas[y]
        for x = x1, x2 do row[x] = color end
    end
end

local function drawLine(box, x1, y1, x2, y2, color)
    local dx, dy = x2 - x1, y2 - y1
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps < 1 then
        put(box, x1, y1, color)
        return
    end
    for i = 0, steps do
        local t = i / steps
        put(box, x1 + dx * t, y1 + dy * t, color)
    end
end

local function worldToPixel(box, playerId, x, y)
    local vx, vy = x, y
    if playerId == 2 then
        vx = A.width - vx
        vy = A.height - vy
    end
    local px = 1 + (vx / A.width) * (box.width - 1)
    local py = 1 + (vy / A.height) * (box.height - 1)
    return px, py
end

local function worldRadiusX(box, radius)
    return math.max(1, radius / A.width * box.width)
end

local function worldRadiusY(box, radius)
    return math.max(1, radius / A.height * box.height)
end

local function drawTerrain(box)
    box:clear(colors.green)

    local riverY1 = 1 + (A.riverTop / A.height) * (box.height - 1)
    local riverY2 = 1 + (A.riverBottom / A.height) * (box.height - 1)
    fillRect(box, 1, riverY1, box.width, riverY2, colors.blue)

    for _, bx in ipairs(A.bridgeCenters) do
        local x1 = 1 + ((bx - A.bridgeHalfWidth) / A.width) * (box.width - 1)
        local x2 = 1 + ((bx + A.bridgeHalfWidth) / A.width) * (box.width - 1)
        fillRect(box, x1, riverY1, x2, riverY2, colors.brown)

        -- small dark bridge rails for depth/readability
        drawLine(box, x1, riverY1, x1, riverY2, colors.gray)
        drawLine(box, x2, riverY1, x2, riverY2, colors.gray)
    end

    -- Keep the original geometry and all mixed boundary/rail texels above.
    -- Only decorate complete, solid 2x3 PixelBox cells. This preserves even
    -- the encoded land/water/bridge footprint at every monitor resolution.
    local towers = require("src.arena").towerBlueprints()
    local maxTileX = box.width / 2 - 1
    local maxTileY = box.height / 3 - 1
    local waterTop, waterBottom = math.floor(riverY1), math.ceil(riverY2)
    for y = 1, box.height - 2, 3 do
        for x = 1, box.width - 1, 2 do
            local base = box.canvas[y][x]
            local solid = true
            for dy = 0, 2 do
                for dx = 0, 1 do
                    if box.canvas[y + dy][x + dx] ~= base then solid = false end
                end
            end
            if solid then
                local tx = (x - 1) / 2
                local ty = (y - 1) / 3
                -- Mirror the surface pattern; never use the gameplay RNG.
                local cx = math.min(tx, maxTileX - tx)
                local cy = math.min(ty, maxTileY - ty)
                if base == colors.green then
                    local wx = (x - 0.5) / (box.width - 1) * A.width
                    local wy = y / (box.height - 1) * A.height
                    local stone = (y + 2 < waterTop and waterTop - (y + 2) <= 3)
                        or (y > waterBottom and y - waterBottom <= 3)
                    local quiet = false
                    for _, tower in ipairs(towers) do
                        local dx = math.abs(wx - tower.x)
                        local dy = math.abs(wy - tower.y)
                        if dx <= 12 and dy <= 18 then quiet = true end
                        -- Small stone foundations under the existing towers.
                        if dx <= 8 and dy <= 10 and (dx <= 6 or dy <= 8) then
                            stone = true
                        end
                        if tower.towerType == "princess" then
                            local bank = tower.y < A.riverTop
                                and A.riverTop or A.riverBottom
                            if wy >= math.min(tower.y, bank)
                                and wy <= math.max(tower.y, bank)
                            then
                                local nearest, distance = A.bridgeCenters[1], math.huge
                                for _, bridge in ipairs(A.bridgeCenters) do
                                    local d = math.abs(bridge - tower.x)
                                    if d < distance then nearest, distance = bridge, d end
                                end
                                local progress = (wy - tower.y) / (bank - tower.y)
                                local laneX = tower.x + (nearest - tower.x) * progress
                                if math.abs(wx - laneX) <= 3 and cy % 3 ~= 1 then
                                    stone = true
                                end
                            end
                        end
                    end
                    local color = colors.green
                    if stone then
                        color = colors.lightGray
                    elseif not quiet and (cx * 17 + cy * 23) % 37 == 0 then
                        color = colors.lime
                    end
                    fillRect(box, x, y, x + 1, y + 2, color)
                elseif base == colors.blue then
                    -- Wavelets stay entirely inside existing open-water cells.
                    local wave = (cx + cy * 3) % 11
                    if wave == 0 or wave == 1 then
                        fillRect(box, x, y + 1, x + 1, y + 1, colors.lightBlue)
                    end
                elseif base == colors.brown then
                    -- Plank seams/highlights stay inside the original deck.
                    local grain = cx % 4 == 0 and colors.orange or colors.gray
                    fillRect(box, x, y + 1, x + 1, y + 1, grain)
                end
            end
        end
    end
end

local function restoreTerrain(box, cached)
    if not cached.terrain then
        drawTerrain(box)
        cached.terrain = {}

        for y = 1, box.height do
            local source = box.canvas[y]
            local row = {}
            for x = 1, box.width do row[x] = source[x] end
            cached.terrain[y] = row
        end
        return
    end

    -- Arena geometry is static for the entire match. Restore the cached pixel
    -- background instead of recomputing river/bridge geometry every frame.
    for y = 1, box.height do
        local source = cached.terrain[y]
        local target = box.canvas[y]
        for x = 1, box.width do target[x] = source[x] end
    end
end

local function alignTexelX(x)
    return math.floor((x - 1) / 2) * 2 + 1
end

local function alignTexelY(y)
    return math.floor((y - 1) / 3) * 3 + 1
end

local function drawHp(box, entity, playerId, cx, topY, width)
    local ratio = math.max(0, math.min(1, entity.hp / math.max(1, entity.maxHp)))
    local maxW = entity.kind == "tower" and math.max(12, width + 4) or math.max(5, width)
    local filled = math.max(1, math.floor(maxW * ratio + 0.5))
    local x1 = math.floor(cx - maxW / 2)
    local y = math.floor(topY - 2)

    local barColor
    if entity.kind == "tower" then
        if ratio <= 0.25 then
            barColor = colors.red
        elseif ratio <= 0.55 then
            barColor = colors.yellow
        else
            barColor = colors.lime
        end
    else
        barColor = entity.owner == playerId and colors.lightBlue or colors.red
    end

    fillRect(box, x1, y, x1 + filled - 1, y + 1, barColor)
end

local function drawSprite(box, entity, playerId, frameClock)
    local sprite = spriteFor(entity)
    local cx, cy = worldToPixel(box, playerId, entity.x, entity.y)

    -- Snap the sprite origin to Pixelbox's 2x3 texel grid. This removes most
    -- edge shimmer/colour bleed while units are moving.
    local rawX = cx - sprite.width / 2
    local rawY = cy - sprite.height / 2
    local x1 = alignTexelX(rawX)
    local y1 = alignTexelY(rawY)

    local team = entity.owner == playerId and colors.lightBlue or colors.red
    local hpRatio = entity.hp / math.max(1, entity.maxHp or 1)
    local flash = entity.damageFlash and entity.damageFlash > 0
    local fuseBlink = entity.fuseRemaining
        and math.floor(entity.fuseRemaining * 10) % 2 == 0

    for rowIndex, row in ipairs(sprite.rows) do
        for col = 1, #row do
            local token = row:sub(col, col)
            if token ~= "." then
                local color = token == "T" and team or PALETTE[token]

                if color then
                    if flash then
                        color = colors.white
                    elseif fuseBlink and entity.proximityExplosion then
                        if token == "K" then
                            color = colors.black
                        elseif entity.visualVariant == "charged_creeper" then
                            color = colors.lightBlue
                        else
                            color = colors.white
                        end
                    elseif entity.visualVariant == "ghast_portal"
                        and (token == "A" or token == "C")
                    then
                        local shimmer = (math.floor(frameClock * 5) + rowIndex + col) % 2 == 0
                        color = shimmer and colors.cyan or colors.lightBlue
                    elseif entity.kind == "tower" and token == "T" then
                        -- Deterministic crack pixels make damaged towers look
                        -- visibly worn without losing their team silhouette.
                        if hpRatio <= 0.25 and (rowIndex + col * 2) % 5 == 0 then
                            color = colors.black
                        elseif hpRatio <= 0.55 and (rowIndex * 2 + col) % 7 == 0 then
                            color = colors.gray
                        end
                    end
                    put(box, x1 + col - 1, y1 + rowIndex - 1, color)
                end
            end
        end
    end

    drawHp(box, entity, playerId, x1 + sprite.width / 2, y1, sprite.width)
end

local function getEntityById(state, id)
    if not id then return nil end
    if state.entityById then
        local entity = state.entityById[id]
        return entity and entity.alive and entity or nil
    end
    for _, entity in ipairs(state.entities) do
        if entity.id == id and entity.alive then return entity end
    end
    return nil
end

local function drawProjectile(box, state, playerId, projectile)
    local px, py = worldToPixel(box, playerId, projectile.x, projectile.y)

    if projectile.visual == "arrow" then
        local target = getEntityById(state, projectile.targetId)
        local dx, dy = 1, 0
        if target then
            local tx, ty = worldToPixel(box, playerId, target.x, target.y)
            dx, dy = tx - px, ty - py
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then dx, dy = dx / length, dy / length end
        end
        drawLine(box, px - dx, py - dy, px + dx, py + dy, colors.white)
        put(box, px + dx, py + dy, colors.lightGray)
    elseif projectile.visual == "cannonball" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.gray)
        put(box, px, py, colors.lightGray)
    elseif projectile.visual == "tower_shot" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.yellow)
    elseif projectile.visual == "fireball" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.orange)
        put(box, px, py, colors.yellow)
    elseif projectile.visual == "ghast_fireball" then
        fillRect(box, px - 2, py - 2, px + 2, py + 2, colors.cyan)
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.lightBlue)
        put(box, px, py, colors.white)
    elseif projectile.visual == "potion" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.purple)
    elseif projectile.visual == "snowball" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.white)
    elseif projectile.visual == "crossbow_bolt" then
        local target = getEntityById(state, projectile.targetId)
        local dx, dy = 1, 0
        if target then
            local tx, ty = worldToPixel(box, playerId, target.x, target.y)
            dx, dy = tx - px, ty - py
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then dx, dy = dx / length, dy / length end
        end
        drawLine(box, px - dx, py - dy, px + dx * 1.5, py + dy * 1.5, colors.brown)
        put(box, px + dx * 1.5, py + dy * 1.5, colors.lightGray)
    else
        put(box, px, py, colors.white)
    end
end

local function drawExplosion(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 0.5)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local maxRx = worldRadiusX(box, effect.radius or 6)
    local maxRy = worldRadiusY(box, effect.radius or 6)
    local rx = math.max(2, maxRx * (0.25 + progress * 0.75))
    local ry = math.max(2, maxRy * (0.25 + progress * 0.75))
    local color = progress < 0.45 and colors.white
        or (progress < 0.75 and colors.yellow or colors.orange)

    for y = math.floor(-ry), math.ceil(ry) do
        for x = math.floor(-rx), math.ceil(rx) do
            local nx, ny = x / rx, y / ry
            local d = nx * nx + ny * ny
            if d <= 1 and d >= 0.45 then
                put(box, cx + x, cy + y, color)
            end
        end
    end
end

local function drawChargedExplosion(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 0.90)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local maxRx = worldRadiusX(box, effect.radius or 16)
    local maxRy = worldRadiusY(box, effect.radius or 16)
    local rx = math.max(3, maxRx * (0.20 + progress * 0.80))
    local ry = math.max(3, maxRy * (0.20 + progress * 0.80))

    local ringColor = progress < 0.35 and colors.white
        or (progress < 0.72 and colors.lightBlue or colors.cyan)

    for y = math.floor(-ry), math.ceil(ry) do
        for x = math.floor(-rx), math.ceil(rx) do
            local nx, ny = x / rx, y / ry
            local d = nx * nx + ny * ny
            if d <= 1 and d >= 0.30 then
                put(box, cx + x, cy + y, ringColor)
            end
        end
    end

    local sparkSpread = 3 + progress * math.max(rx, ry)
    for i = 1, 12 do
        local angle = i * 2.399
        put(
            box,
            cx + math.cos(angle) * sparkSpread,
            cy + math.sin(angle) * sparkSpread * 0.7,
            i % 3 == 0 and colors.white or colors.lightBlue
        )
    end

    drawLine(box, cx - 4, cy, cx + 4, cy, colors.white)
    drawLine(box, cx, cy - 4, cx, cy + 4, colors.cyan)
end

local function drawArrowVolley(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local rx = worldRadiusX(box, effect.radius or 10)
    local ry = worldRadiusY(box, effect.radius or 10)
    local duration = math.max(0.001, effect.duration or 0.45)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))

    for i = 1, 17 do
        local fx = ((i * 37) % 101) / 100 * 2 - 1
        local fy = ((i * 61) % 97) / 96 * 2 - 1
        if fx * fx + fy * fy <= 1 then
            local x = cx + fx * rx
            local baseY = cy + fy * ry
            local y = baseY - (1 - progress) * 10
            drawLine(box, x, y - 3, x, y + 2, colors.lightGray)
            put(box, x, y + 3, colors.white)
        end
    end
end

local function drawHit(box, playerId, effect)
    local x, y = worldToPixel(box, playerId, effect.x, effect.y)
    drawLine(box, x - 2, y, x + 2, y, colors.white)
    drawLine(box, x, y - 2, x, y + 2, colors.white)
end

local function drawRingEffect(box, playerId, effect, color)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local rx = math.max(2, worldRadiusX(box, effect.radius or 4))
    local ry = math.max(2, worldRadiusY(box, effect.radius or 4))

    for y = math.floor(-ry), math.ceil(ry) do
        for x = math.floor(-rx), math.ceil(rx) do
            local nx, ny = x / rx, y / ry
            local d = nx * nx + ny * ny
            if d <= 1 and d >= 0.5 then
                put(box, cx + x, cy + y, color)
            end
        end
    end
end

local function drawSparkle(box, playerId, effect, color)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 0.4)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local rise = progress * 5

    put(box, cx, cy - rise - 1, color)
    put(box, cx - 2, cy - rise + 1, color)
    put(box, cx + 2, cy - rise, color)
    put(box, cx, cy - rise + 2, colors.white)
end

local function drawTowerDown(box, playerId, effect)
    drawExplosion(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 0.7)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local spread = 2 + progress * 9

    for i = 1, 8 do
        local angle = i * 2.399
        local x = cx + math.cos(angle) * spread
        local y = cy + math.sin(angle) * spread * 0.65 + progress * 3
        put(box, x, y, i % 2 == 0 and colors.gray or colors.brown)
    end
end

local function drawAnvilWarning(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 3)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local rx = math.max(2, worldRadiusX(box, effect.radius or 5.5))
    local ry = math.max(2, worldRadiusY(box, effect.radius or 5.5))

    -- Pulsing landing marker.
    local pulse = math.floor(effect.ttl * 4) % 2 == 0
    local ringColor = pulse and colors.red or colors.orange
    for i = 0, 15 do
        local angle = i / 16 * math.pi * 2
        put(box, cx + math.cos(angle) * rx, cy + math.sin(angle) * ry, ringColor)
    end
    drawLine(box, cx - 2, cy, cx + 2, cy, colors.white)
    drawLine(box, cx, cy - 2, cx, cy + 2, colors.white)

    -- Anvil drops visibly from above during the three-second telegraph.
    local startY = math.max(2, cy - 30)
    local ay = startY + (cy - startY - 4) * progress
    fillRect(box, cx - 3, ay, cx + 3, ay + 1, colors.gray)
    fillRect(box, cx - 2, ay + 2, cx + 2, ay + 3, colors.lightGray)
    fillRect(box, cx - 1, ay + 4, cx + 1, ay + 5, colors.gray)
end

local function drawAnvilImpact(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    drawExplosion(box, playerId, effect)
    fillRect(box, cx - 4, cy - 2, cx + 4, cy - 1, colors.gray)
    fillRect(box, cx - 2, cy, cx + 2, cy + 2, colors.lightGray)
    drawLine(box, cx - 5, cy + 3, cx + 5, cy + 3, colors.brown)
end

local function drawDiamondQuake(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 0.55)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local maxRx = math.max(2, worldRadiusX(box, effect.radius or 8))
    local maxRy = math.max(2, worldRadiusY(box, effect.radius or 8))
    local rx = math.max(2, maxRx * (0.30 + progress * 0.70))
    local ry = math.max(2, maxRy * (0.30 + progress * 0.70))
    local ringColor = progress < 0.45 and colors.lightGray or colors.gray

    for i = 0, 18 do
        local angle = i / 18 * math.pi * 2
        put(
            box,
            cx + math.cos(angle) * rx,
            cy + math.sin(angle) * ry,
            ringColor
        )
    end

    local crack = math.max(2, math.floor(rx * 0.55))
    drawLine(box, cx - crack, cy, cx - 1, cy + 1, colors.brown)
    drawLine(box, cx + 1, cy - 1, cx + crack, cy, colors.brown)
    put(box, cx, cy, colors.cyan)
end

local function drawGuardianBeam(box, playerId, effect)
    local x1, y1 = worldToPixel(box, playerId, effect.x, effect.y)
    local x2, y2 = worldToPixel(box, playerId, effect.x2 or effect.x, effect.y2 or effect.y)
    local charge = math.max(0, math.min(1, effect.charge or 0))

    local beamColor
    if charge < 0.35 then
        beamColor = colors.cyan
    elseif charge < 0.70 then
        beamColor = colors.lightBlue
    else
        beamColor = colors.white
    end

    drawLine(box, x1, y1, x2, y2, beamColor)

    if charge >= 0.55 then
        drawLine(box, x1 + 1, y1, x2 + 1, y2, colors.cyan)
    end
    if charge >= 0.85 then
        put(box, x2, y2, colors.yellow)
        put(box, x2 + 1, y2, colors.white)
    end
end

local function drawEvokerFangs(box, playerId, effect, impact)
    if effect.mode == "ring" then
        drawRingEffect(
            box,
            playerId,
            effect,
            impact and colors.white or colors.yellow
        )

        local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
        local rx = math.max(2, worldRadiusX(box, effect.radius or 5))
        local ry = math.max(2, worldRadiusY(box, effect.radius or 5))
        for i = 0, 7 do
            local angle = (i / 8) * math.pi * 2
            local x = cx + math.cos(angle) * rx
            local y = cy + math.sin(angle) * ry
            put(box, x, y, impact and colors.lightGray or colors.orange)
            if impact then put(box, x, y - 1, colors.white) end
        end
        return
    end

    local x1, y1 = worldToPixel(box, playerId, effect.x, effect.y)
    local x2, y2 = worldToPixel(
        box,
        playerId,
        effect.x2 or effect.x,
        effect.y2 or effect.y
    )
    local color = impact and colors.white or colors.yellow
    drawLine(box, x1, y1, x2, y2, color)

    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1 then return end

    local nx, ny = -dy / length, dx / length
    local teeth = math.max(3, math.floor(length / 4))
    for i = 1, teeth do
        local t = i / (teeth + 1)
        local x = x1 + dx * t
        local y = y1 + dy * t
        local spread = impact and 2 or 1
        put(box, x, y, color)
        put(box, x + nx * spread, y + ny * spread, impact and colors.lightGray or colors.orange)
        put(box, x - nx * spread, y - ny * spread, impact and colors.lightGray or colors.orange)
    end
end

local function drawEffect(box, playerId, effect)
    if effect.kind == "arrows" then
        drawArrowVolley(box, playerId, effect)
    elseif effect.kind == "hit" then
        drawHit(box, playerId, effect)
    elseif effect.kind == "teleport" then
        drawRingEffect(box, playerId, effect, colors.magenta)
    elseif effect.kind == "splash" then
        drawRingEffect(box, playerId, effect, colors.purple)
    elseif effect.kind == "ghast_splash" then
        drawRingEffect(box, playerId, effect, colors.cyan)
        drawSparkle(box, playerId, effect, colors.white)
    elseif effect.kind == "charged_explosion" then
        drawChargedExplosion(box, playerId, effect)
    elseif effect.kind == "summon" then
        drawRingEffect(box, playerId, effect, colors.lime)
    elseif effect.kind == "portal_spawn" then
        drawRingEffect(box, playerId, effect, colors.magenta)
        drawSparkle(box, playerId, effect, colors.purple)
    elseif effect.kind == "ghast_portal_spawn" then
        drawRingEffect(box, playerId, effect, colors.cyan)
        drawSparkle(box, playerId, effect, colors.lightBlue)
    elseif effect.kind == "evolution_spawn" then
        drawRingEffect(box, playerId, effect, colors.magenta)
        drawSparkle(box, playerId, effect, colors.cyan)
    elseif effect.kind == "spawn" then
        local team = effect.owner == playerId and colors.lightBlue or colors.red
        drawRingEffect(box, playerId, effect, team)
    elseif effect.kind == "death" then
        drawRingEffect(box, playerId, effect, colors.lightGray)
    elseif effect.kind == "diamond_quake" then
        drawDiamondQuake(box, playerId, effect)
    elseif effect.kind == "guardian_beam" then
        drawGuardianBeam(box, playerId, effect)
    elseif effect.kind == "guardian_spike" then
        drawSparkle(box, playerId, effect, colors.cyan)
    elseif effect.kind == "evoker_summon" then
        drawRingEffect(box, playerId, effect, colors.lightBlue)
        drawSparkle(box, playerId, effect, colors.white)
    elseif effect.kind == "evoker_fangs_warning" then
        drawEvokerFangs(box, playerId, effect, false)
    elseif effect.kind == "evoker_fangs_impact" then
        drawEvokerFangs(box, playerId, effect, true)
    elseif effect.kind == "slow" then
        drawRingEffect(box, playerId, effect, colors.cyan)
    elseif effect.kind == "emerald" then
        drawSparkle(box, playerId, effect, colors.lime)
    elseif effect.kind == "tower_warning" then
        drawRingEffect(box, playerId, effect, colors.red)
    elseif effect.kind == "tower_down" then
        drawTowerDown(box, playerId, effect)
    elseif effect.kind == "anvil_warning" then
        drawAnvilWarning(box, playerId, effect)
    elseif effect.kind == "anvil_impact" then
        drawAnvilImpact(box, playerId, effect)
    else
        drawExplosion(box, playerId, effect)
    end
end

local renderOrderCache = setmetatable({}, { __mode = "k" })

local function orderedEntities(state)
    local cached = renderOrderCache[state]
    local entities = state.entities
    local tick = state.combatTick or 0
    local nextId = state.nextEntityId or 0
    local count = #entities

    if cached
        and cached.entities == entities
        and cached.tick == tick
        and cached.nextId == nextId
        and cached.count == count
    then
        return cached.list
    end

    local list = {}
    for _, entity in ipairs(entities) do
        if entity.alive then list[#list + 1] = entity end
    end

    table.sort(list, function(a, b)
        if a.y == b.y then return a.id < b.id end
        return a.y < b.y
    end)

    renderOrderCache[state] = {
        entities = entities,
        tick = tick,
        nextId = nextId,
        count = count,
        list = list,
    }
    return list
end

-- PixelBox's row-diff proxy suppresses terminal traffic but its encoder
-- still converts EVERY 2x3 texel on every redraw. Detect truly identical
-- logical-pixel frames before invoking that expensive encoder. Compare the
-- final canvas (including animated sprites/effects) rather than assuming a
-- combat tick implies a changed image. This preserves animation fidelity and
-- never relies on potentially stale entity IDs or wall-clock heuristics.
local function canvasChanged(box, cached)
    local previous = cached.framePixels
    local different = previous == nil
    if not previous then
        previous = {}
        cached.framePixels = previous
    end

    for y = 1, box.height do
        local source = box.canvas[y]
        local saved = previous[y]
        if not saved then
            saved = {}
            previous[y] = saved
            different = true
        end
        for x = 1, box.width do
            local color = source[x]
            if saved[x] ~= color then
                saved[x] = color
                different = true
            end
        end
    end
    return different
end

-- Cheap conservative invalidation: whenever any live entity changes
-- position/order, full conversion is necessary often enough that comparing
-- 110x120 pixels first is wasted work. The stored positions are bounded by
-- the live roster (not a growing ID map), and never gate frame correctness:
-- on a stationary roster canvasChanged still observes animation, effects,
-- projectiles, HP bars and other visual state.
local function rosterMoved(state, cached)
    local previous = cached.previousPositions
    local moved = previous == nil
    if not previous then
        previous = {}
        cached.previousPositions = previous
    end
    local n = 0
    for _, entity in ipairs(state.entities) do
        if entity.alive then
            n = n + 1
            local saved = previous[n]
            if not saved then
                saved = {}
                previous[n] = saved
                moved = true
            end
            if saved.id ~= entity.id
                or saved.x ~= entity.x
                or saved.y ~= entity.y
            then
                moved = true
                saved.id = entity.id
                saved.x = entity.x
                saved.y = entity.y
            end
        end
    end
    if #previous ~= n then
        moved = true
        for i = n + 1, #previous do previous[i] = nil end
    end
    return moved
end

function pixelArena.draw(monitor, state, playerId, rect, forceFullEncode)
    local box, cached = getSurface(monitor, rect)

    -- The countdown writes its overlay directly to the physical monitor.
    -- Force a full refresh when entering battle so cached rows cannot leave
    -- countdown digits visible, even if the background is otherwise static.
    local forceFrame = cached.lastPhase ~= state.phase
    if forceFrame then
        cached.lastBlitLines = {}
        cached.lastPhase = state.phase
    end

    restoreTerrain(box, cached)
    local frameClock = (os.clock and os.clock() or 0)
    local drawEntities = orderedEntities(state)

    if playerId == 1 then
        for _, entity in ipairs(drawEntities) do
            if entity.alive then
                drawSprite(box, entity, playerId, frameClock)
            end
        end
    else
        -- Mirroring reverses world Y. Preserve ID order for exact same-Y ties
        -- so overlap behavior remains identical to the old projected sort.
        local i = #drawEntities
        while i >= 1 do
            local y = drawEntities[i].y
            local first = i
            while first > 1 and drawEntities[first - 1].y == y do
                first = first - 1
            end
            for j = first, i do
                if drawEntities[j].alive then
                    drawSprite(box, drawEntities[j], playerId, frameClock)
                end
            end
            i = first - 1
        end
    end

    for _, projectile in ipairs(state.projectiles) do
        if projectile.alive then drawProjectile(box, state, playerId, projectile) end
    end

    for _, effect in ipairs(state.effects) do
        drawEffect(box, playerId, effect)
    end

    -- If every logical pixel matches, PixelBox would reproduce the exact
    -- same terminal rows. Avoid its conversion entirely. Forced renders
    -- remain necessary after phase transitions because countdown text was
    -- written outside the PixelBox renderer.
    -- Optional diagnostic oracle: bypass the frame cache entirely to
    -- compare cached and exhaustive PixelBox output under the SAME state.
    local moved = rosterMoved(state, cached)
    if forceFrame or forceFullEncode or moved then
        -- We did not compare/update the pixel snapshot. Never leave a stale
        -- snapshot behind: a unit can move back to the SAME old position,
        -- and skipping the return frame would otherwise leave ghost pixels.
        cached.framePixels = nil
        box:render()
    elseif canvasChanged(box, cached) then
        box:render()
    end
end

function pixelArena.getLogicalSize(monitor, rect)
    local box = getSurface(monitor, rect)
    return box.width, box.height
end

return pixelArena

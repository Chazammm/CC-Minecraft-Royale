-- Original Phase-1 art. Data only; deliberately absent from install.lua and all runtime imports.
return {
    ["assetSchema"] = 1,
    ["id"] = "ravager_rider",
    ["phase"] = "PHASE_1_ONLY",
    ["runtimeRegistered"] = false,
    ["format"] = "CC_ROYALE_PALETTE_TOKEN_ROWS",
    ["frameStatus"] = "PREPARED_STATIC_RASTER_NOT_LIVE_ANIMATION",
    ["runtimeDispatchStatus"] = "NOT_IMPLEMENTED_REQUIRES_PHASE_2",
    ["damageSemantics"] = "VISUAL_ONLY_NO_COMBAT_FUNCTIONS",
    ["frames"] = {
        ["crossbow_bolt"] = {
            ["width"] = 8,
            ["height"] = 3,
            ["rows"] = {
                "......S.",
                ".NNNNNSW",
                "......S.",
            },
        },
        ["muzzle"] = {
            ["width"] = 5,
            ["height"] = 3,
            ["rows"] = {
                "..Y..",
                ".WYW.",
                "..Y..",
            },
        },
        ["initial_impact_a"] = {
            ["width"] = 7,
            ["height"] = 7,
            ["rows"] = {
                "...S...",
                ".S...S.",
                "..WWW..",
                "S.WKW.S",
                "..WWW..",
                ".S...S.",
                "...S...",
            },
        },
        ["initial_impact_b"] = {
            ["width"] = 7,
            ["height"] = 7,
            ["rows"] = {
                "S.....S",
                "..S.S..",
                ".S...S.",
                "...D...",
                ".S...S.",
                "..S.S..",
                "S.....S",
            },
        },
    },
}

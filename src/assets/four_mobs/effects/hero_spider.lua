-- Original Phase-1 pixel data, now registered by src.mob_assets.
return {
    ["assetSchema"] = 1,
    ["id"] = "hero_spider",
    ["phase"] = "PHASE_2_RUNTIME",
    ["runtimeRegistered"] = true,
    ["format"] = "CC_ROYALE_PALETTE_TOKEN_ROWS",
    ["frameStatus"] = "LIVE_FRAME_DATA",
    ["runtimeDispatchStatus"] = "NOT_IMPLEMENTED_REQUIRES_PHASE_2",
    ["damageSemantics"] = "VISUAL_ONLY_NO_COMBAT_FUNCTIONS",
    ["frames"] = {
        ["web_projectile_a"] = {
            ["width"] = 5,
            ["height"] = 5,
            ["rows"] = {
                "..W..",
                ".WSW.",
                "WSWSW",
                ".WSW.",
                "..W..",
            },
        },
        ["web_projectile_b"] = {
            ["width"] = 5,
            ["height"] = 5,
            ["rows"] = {
                ".W.W.",
                "W.S.W",
                ".SWS.",
                "W.S.W",
                ".W.W.",
            },
        },
        ["web_hit_a"] = {
            ["width"] = 9,
            ["height"] = 9,
            ["rows"] = {
                "W...W...W",
                ".W..W..W.",
                "..W.W.W..",
                "...WWW...",
                "WWWWWWWWW",
                "...WWW...",
                "..W.W.W..",
                ".W..W..W.",
                "W...W...W",
            },
        },
        ["web_hit_b"] = {
            ["width"] = 9,
            ["height"] = 9,
            ["rows"] = {
                "..S...S..",
                "S..S.S..S",
                ".S.....S.",
                "..S...S..",
                "....W....",
                "..S...S..",
                ".S.....S.",
                "S..S.S..S",
                "..S...S..",
            },
        },
        ["web_status"] = {
            ["width"] = 3,
            ["height"] = 3,
            ["rows"] = {
                "WSW",
                "SWS",
                "WSW",
            },
        },
    },
}

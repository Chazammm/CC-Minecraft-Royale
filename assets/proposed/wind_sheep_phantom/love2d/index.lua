-- Portable static sprite metadata; not loaded by the CC:Tweaked game.
-- Anchors use LÖVE's zero-based image coordinates and a common base at y=240.
return {
    schema = 1,
    filter = { min = "nearest", mag = "nearest" },
    sprites = {
        breeze = {
            file = "breeze.png", width = 256, height = 256,
            anchorX = 128, anchorY = 240, pose = "idle", flyingPose = true,
        },
        adventure_sheep = {
            file = "adventure_sheep.png", width = 256, height = 256,
            anchorX = 128, anchorY = 240, pose = "idle",
        },
        phantom = {
            file = "phantom.png", width = 320, height = 256,
            anchorX = 160, anchorY = 240, pose = "idle", flyingPose = true,
        },
    },
}

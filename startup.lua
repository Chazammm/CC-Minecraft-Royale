-- CC-MINECRAFT-ROYALE-MANAGED-STARTUP
-- Optional startup entry point for a dedicated arena computer.
-- Remove/rename this file if you do not want the game to auto-start on reboot.
-- Never boot a potentially mixed-version installation after a power failure.
-- The installer creates this marker before modifying any managed file and
-- removes it only after a complete, successful apply.
if fs.exists(".cc_royale_installing") then
    printError("CC-Minecraft Royale: interrupted update detected.")
    printError("Run the installer again to recover before starting the game.")
    return
end

shell.run("main.lua")

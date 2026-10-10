local config = require("config")
local function line()
  print("----------------------------------------")
end

print("CC-Minecraft Royale - Hardware Diagnostic")
line()

local names = peripheral.getNames()
print("Visible peripherals: " .. tostring(#names))

if #names == 0 then
  print("NONE")
else
  for _, name in ipairs(names) do
    local pType = peripheral.getType(name)
    print(("- %-20s %s"):format(name, tostring(pType)))
  end
end

line()

local monitors = { peripheral.find("monitor") }
print("Monitors found: " .. tostring(#monitors))

for i, monitor in ipairs(monitors) do
  local name = peripheral.getName(monitor)
  local oldScale = monitor.getTextScale and monitor.getTextScale() or nil
  local diagnosticScale = config.TEXT_SCALE or 0.5
  if monitor.setTextScale then monitor.setTextScale(diagnosticScale) end
  local w, h = monitor.getSize()
  print(("Monitor %d: %s -> %dx%d @ %s"):format(
    i,
    tostring(name),
    w,
    h,
    tostring(diagnosticScale)
  ))
  if w < (config.MIN_RECOMMENDED_WIDTH or 1)
      or h < (config.MIN_RECOMMENDED_HEIGHT or 1)
  then
    print(("  WARNING: recommended minimum is %dx%d"):format(
      config.MIN_RECOMMENDED_WIDTH or 1,
      config.MIN_RECOMMENDED_HEIGHT or 1
    ))
  end
  if monitor.isColor then
    print("  Advanced/color: " .. tostring(monitor.isColor()))
  end
  if oldScale and monitor.setTextScale then monitor.setTextScale(oldScale) end
end

local speakers = { peripheral.find("speaker") }
print("Speakers found: " .. tostring(#speakers))

line()

if #names == 0 then
  print("No peripherals are reaching this computer.")
  print("")
  print("For remote monitors:")
  print("1. Put a WIRED MODEM directly on each monitor wall.")
  print("2. Put a WIRED MODEM on the arena computer.")
  print("3. Connect the modems with networking cable.")
  print("4. Right-click/activate the wired modems so they")
  print("   report that the peripheral/network is connected.")
  print("5. Run 'diagnose' again.")
elseif #monitors < 2 then
  print("The game needs TWO monitor peripherals.")
  print("Check that each 3x4 wall is one multiblock and that")
  print("both are exposed to the same wired network.")
elseif #monitors > 2
    and not (config.MONITOR_NAMES[1] and config.MONITOR_NAMES[2])
then
  print("More than two monitors found.")
  print("Set config.MONITOR_NAMES to the exact two arena monitors.")
else
  print("Basic monitor requirement satisfied.")
  print("You can now run: main")
end

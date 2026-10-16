-- Static quality gate: fixed audit entries must have actual CI-executed
-- regression files, and open optimizations must not be relabeled as fixes.
local function read(path)
    local f = assert(io.open(path, "r"), "Missing release gate file " .. path)
    local body = f:read("*a")
    f:close()
    return body
end

local registry = read("docs/AUDIT_REGISTER.md")
local policy = read("QUALITY_GATE.md")
local workflow = read(".github/workflows/lua-ci.yml")
local template = read(".github/pull_request_template.md")

local function luaInCI(testPath, runtime)
    if workflow:find(runtime .. " " .. testPath, 1, true) then return true end
    if not testPath:match('^tests/test_[%w_]+%.lua$') then return false end
    local body = workflow:match('\n%s*for test in tests/test_%*%.lua; do\n(.-)\n%s*done')
    return body and body:find(runtime .. ' "$test"', 1, true) ~= nil
end

local function pythonInCI(testPath)
    local name = testPath:match('^tests/(test_[%w_]+%.py)$')
    return name and (workflow:find('python3 -m unittest discover -s tests -p ' .. name, 1, true)
        or workflow:find("python3 -m unittest discover -s tests -p 'test_*.py'", 1, true))
end

local seen = {}
local fixed, open = 0, 0
for line in registry:gmatch("[^\r\n]+") do
    local id = line:match("^| (AF%-%d%d%d) |")
        or line:match("^| (OP%-%d%d%d) |")
    if id then
        assert(not seen[id], "Duplicate audit ID: " .. id)
        seen[id] = true
        if id:match("^AF%-") then
            fixed = fixed + 1
            assert(line:find("FIXED_CI", 1, true),
                "Fixed audit item must specify automated status: " .. id)
            local testCount = 0
            for testPath in line:gmatch("tests/[%w_]+%.[%w]+") do
                local content = read(testPath)
                assert(#content > 0, "Empty regression test: " .. testPath)
                assert(luaInCI(testPath, 'lua5.4')
                    or luaInCI(testPath, 'lua5.2') or pythonInCI(testPath),
                    id .. " regression not executed by CI: " .. testPath)
                testCount = testCount + 1
            end
            assert(testCount > 0, "Missing executable regression: " .. id)
        else
            open = open + 1
            assert(not line:find("FIXED_CI", 1, true),
                "Open optimization must not be marked fixed: " .. id)
        end
    end
end

assert(fixed >= 27, "Audit register lost iterative and historical audit findings")
assert(open >= 5, "Open measurement/hardware limitations were silently removed")
for _, testPath in ipairs({
    "tests/test_preset_false_returns.lua",
    "tests/test_installer_false_returns.lua",
    "tests/test_report_logout_false.lua",
    "tests/test_report_token_write_failures.lua",
    "tests/test_music_seek_failures.lua",
    "tests/test_core_invariant_stress.lua",
    "tests/test_preset_transaction_integrity.lua",
    "tests/test_atomic_token_reconfig.lua",
    "tests/test_token_backup_recovery.lua",
    "tests/test_report_transaction_integrity.lua",
    "tests/test_token_corrupt_active_fallback.lua",
    "tests/test_preset_recovery_matrix.lua",
}) do
    assert(luaInCI(testPath, 'lua5.2') and luaInCI(testPath, 'lua5.4'),
        "Deep-core diagnostic must run in BOTH Lua versions: " .. testPath)
end

assert(luaInCI('tests/test_audit_fixes_20261010.lua', 'lua5.4'),
    "Third-audit tests must be in CI")
assert(luaInCI('tests/test_release_gate.lua', 'lua5.4'),
    "Release gate must be self-enforcing in CI")
assert(policy:lower():find("hardware", 1, true)
    and policy:lower():find("reproducib", 1, true),
    "Quality process must document hardware and reproducibility requirements")
assert(template:find("Regression test", 1, true)
    and template:find("Hardware", 1, true),
    "PR template must require test/hardware evidence")

print(("Release gate passed: %d fixed audit IDs, %d tracked follow-ups")
    :format(fixed, open))

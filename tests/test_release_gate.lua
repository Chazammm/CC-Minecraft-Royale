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
            for testPath in line:gmatch("tests/[%w_]+%.lua") do
                local content = read(testPath)
                assert(#content > 0, "Empty regression test: " .. testPath)
                assert(workflow:find("lua5.4 " .. testPath, 1, true)
                    or workflow:find("lua5.2 " .. testPath, 1, true),
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

assert(fixed >= 9, "Audit register lost fixed findings")
assert(open >= 5, "Open measurement/hardware limitations were silently removed")
assert(workflow:find("tests/test_audit_fixes_20261010.lua", 1, true),
    "Third-audit tests must be in CI")
assert(workflow:find("tests/test_release_gate.lua", 1, true),
    "Release gate must be self-enforcing in CI")
assert(policy:lower():find("hardware", 1, true)
    and policy:lower():find("reproducib", 1, true),
    "Quality process must document hardware and reproducibility requirements")
assert(template:find("Regression test", 1, true)
    and template:find("Hardware", 1, true),
    "PR template must require test/hardware evidence")

print(("Release gate passed: %d fixed audit IDs, %d tracked follow-ups")
    :format(fixed, open))

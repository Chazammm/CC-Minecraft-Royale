local M = {}

local OWNER = "Chazammm"
local REPO = "CC-Minecraft-Royale"
local BRANCH = "main"

local TOKEN_DIR = ".cc_royale"
local TOKEN_FILE = TOKEN_DIR .. "/github_token.txt"
local API_BASE = ("https://api.github.com/repos/%s/%s"):format(OWNER, REPO)

local REPORTS = {
    { kind = "mechanics", path = "mechanics_report.txt" },
    { kind = "balance", path = "balance_results.txt" },
    { kind = "comparison", path = "comparison_results.txt" },
    { kind = "evolution", path = "evolution_results.txt" },
}

local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function readAll(path)
    if not fs.exists(path) or fs.isDir(path) then
        return nil, "File not found: " .. path
    end

    local handle = fs.open(path, "r")
    if not handle then return nil, "Could not open " .. path end

    local body = handle.readAll()
    handle.close()
    return body
end

local function writeAll(path, body)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local handle = fs.open(path, "w")
    if not handle then return false, "Could not write " .. path end

    handle.write(body)
    handle.close()
    return true
end

local function base64Encode(data)
    local out = {}

    for i = 1, #data, 3 do
        local a = data:byte(i) or 0
        local b = data:byte(i + 1) or 0
        local c = data:byte(i + 2) or 0
        local n = a * 65536 + b * 256 + c

        local i1 = math.floor(n / 262144) % 64 + 1
        local i2 = math.floor(n / 4096) % 64 + 1
        local i3 = math.floor(n / 64) % 64 + 1
        local i4 = n % 64 + 1

        out[#out + 1] = BASE64:sub(i1, i1)
        out[#out + 1] = BASE64:sub(i2, i2)

        if i + 1 <= #data then
            out[#out + 1] = BASE64:sub(i3, i3)
        else
            out[#out + 1] = "="
        end

        if i + 2 <= #data then
            out[#out + 1] = BASE64:sub(i4, i4)
        else
            out[#out + 1] = "="
        end
    end

    return table.concat(out)
end

local function apiHeaders(token)
    return {
        ["Accept"] = "application/vnd.github+json",
        ["Authorization"] = "Bearer " .. token,
        ["X-GitHub-Api-Version"] = "2022-11-28",
        ["User-Agent"] = "CC-Minecraft-Royale-report-sync",
    }
end

local function responseDetails(handle)
    if not handle then return nil, nil end

    local code = nil
    if handle.getResponseCode then
        code = select(1, handle.getResponseCode())
    end

    local body = handle.readAll and handle.readAll() or ""
    if handle.close then handle.close() end
    return code, body
end

local function githubGet(token, url)
    local response, err, failedResponse = http.get({
        url = url,
        headers = apiHeaders(token),
        timeout = 20,
    })

    if response then
        local code, body = responseDetails(response)
        return true, code, body
    end

    local code, body = responseDetails(failedResponse)
    return false, code, body ~= "" and body or tostring(err)
end

local function githubPut(token, url, body)
    local response, err, failedResponse = http.post({
        url = url,
        body = body,
        headers = {
            ["Accept"] = "application/vnd.github+json",
            ["Authorization"] = "Bearer " .. token,
            ["X-GitHub-Api-Version"] = "2022-11-28",
            ["User-Agent"] = "CC-Minecraft-Royale-report-sync",
            ["Content-Type"] = "application/json",
        },
        method = "PUT",
        timeout = 30,
    })

    if response then
        local code, responseBody = responseDetails(response)
        return code == 200 or code == 201, code, responseBody
    end

    local code, responseBody = responseDetails(failedResponse)
    return false, code, responseBody ~= "" and responseBody or tostring(err)
end

local function contentUrl(remotePath, includeRef)
    local url = API_BASE .. "/contents/" .. remotePath
    if includeRef then
        url = url .. "?ref=" .. textutils.urlEncode(BRANCH)
    end
    return url
end

local function remoteSha(token, remotePath)
    local ok, code, body = githubGet(token, contentUrl(remotePath, true))

    if not ok then
        if code == 404 then return nil end
        return nil, ("GitHub GET failed (HTTP %s): %s"):format(
            tostring(code or "?"),
            tostring(body or "unknown error")
        )
    end

    local decoded, decodeErr = textutils.unserializeJSON(body)
    if not decoded then
        return nil, "Could not parse GitHub response: " .. tostring(decodeErr)
    end

    return decoded.sha
end

local function putContent(token, remotePath, content, message, overwrite)
    local payload = {
        message = message,
        content = base64Encode(content),
        branch = BRANCH,
    }

    if overwrite then
        local sha, shaErr = remoteSha(token, remotePath)
        if shaErr then return false, shaErr end
        if sha then payload.sha = sha end
    end

    local body = textutils.serializeJSON(payload)
    local ok, code, responseBody = githubPut(
        token,
        contentUrl(remotePath, false),
        body
    )

    if not ok then
        local detail = tostring(responseBody or "")
        local parsed = textutils.unserializeJSON(detail)
        if parsed and parsed.message then detail = tostring(parsed.message) end

        return false, ("GitHub PUT failed for %s (HTTP %s): %s"):format(
            remotePath,
            tostring(code or "?"),
            detail ~= "" and detail or "unknown error"
        )
    end

    return true
end

local function epochStamp()
    if os.epoch then
        return tostring(os.epoch("utc"))
    end
    return tostring(math.floor(os.clock() * 1000))
end

function M.tokenPath()
    return TOKEN_FILE
end

function M.isConfigured()
    if not fs.exists(TOKEN_FILE) or fs.isDir(TOKEN_FILE) then return false end
    local token = readAll(TOKEN_FILE)
    return token ~= nil and #trim(token) >= 20
end

function M.readToken()
    local token, err = readAll(TOKEN_FILE)
    if not token then return nil, err end

    token = trim(token)
    if #token < 20 then
        return nil, "Stored GitHub token looks invalid. Run: report_sync setup"
    end

    return token
end

function M.verifyToken(token)
    if not http then return false, "HTTP API is disabled" end

    token = trim(token)
    if #token < 20 then return false, "Token is too short" end

    local ok, code, body = githubGet(token, API_BASE)
    if not ok then
        return false, ("GitHub authentication check failed (HTTP %s): %s"):format(
            tostring(code or "?"),
            tostring(body or "unknown error")
        )
    end

    return code == 200, code == 200 and "GitHub connection OK" or ("Unexpected HTTP " .. tostring(code))
end

function M.setupInteractive()
    print("GitHub report sync setup")
    print("------------------------")
    print("Repo: " .. OWNER .. "/" .. REPO)
    print("Use a fine-grained token restricted to this repo")
    print("with Contents: Read and write.")
    print("The token is stored only on this Minecraft computer at:")
    print("  " .. TOKEN_FILE)
    print("")
    write("Token: ")
    local token = trim(read("*"))

    local ok, message = M.verifyToken(token)
    if not ok then
        return false, message
    end

    local saved, saveErr = writeAll(TOKEN_FILE, token .. "\n")
    if not saved then return false, saveErr end

    return true, "Token saved locally. Report auto-sync is now enabled."
end

function M.clearToken()
    if fs.exists(TOKEN_FILE) then
        fs.delete(TOKEN_FILE)
    end
    return true
end

function M.upload(kind, localPath, token, stamp)
    if not http then return false, "HTTP API is disabled" end

    kind = trim(kind):lower()
    if kind == "" or kind:find("[^%w_-]") then
        return false, "Invalid report kind: " .. tostring(kind)
    end

    local content, readErr = readAll(localPath)
    if not content then return false, readErr end

    token = token or M.readToken()
    if not token then return false, "Report sync is not configured. Run: report_sync setup" end

    stamp = stamp or epochStamp()
    local fileName = fs.getName(localPath)
    local historyPath = ("reports/history/%s/%s_%s"):format(kind, stamp, fileName)
    local latestPath = "reports/latest/" .. fileName

    local ok, err = putContent(
        token,
        historyPath,
        content,
        ("Archive %s report %s"):format(kind, stamp),
        false
    )
    if not ok then return false, err end

    ok, err = putContent(
        token,
        latestPath,
        content,
        ("Update latest %s report"):format(kind),
        true
    )
    if not ok then
        return false, err .. " (history copy was uploaded successfully)"
    end

    return true, {
        kind = kind,
        localPath = localPath,
        historyPath = historyPath,
        latestPath = latestPath,
        stamp = stamp,
    }
end

function M.autoUpload(kind, localPath)
    if not M.isConfigured() then
        return false, "not_configured"
    end

    local token, err = M.readToken()
    if not token then return false, err end

    return M.upload(kind, localPath, token)
end

function M.syncAll()
    local token, tokenErr = M.readToken()
    if not token then return false, tokenErr end

    local stamp = epochStamp()
    local uploaded = {}
    local failures = {}

    for _, report in ipairs(REPORTS) do
        if fs.exists(report.path) and not fs.isDir(report.path) then
            local ok, result = M.upload(report.kind, report.path, token, stamp)
            if ok then
                uploaded[#uploaded + 1] = result
            else
                failures[#failures + 1] = report.path .. ": " .. tostring(result)
            end
        end
    end

    if #uploaded == 0 and #failures == 0 then
        return false, "No report files found yet."
    end

    return #failures == 0, {
        uploaded = uploaded,
        failures = failures,
        stamp = stamp,
    }
end

function M.reportDefinitions()
    local out = {}
    for i, report in ipairs(REPORTS) do
        out[i] = { kind = report.kind, path = report.path }
    end
    return out
end

return M

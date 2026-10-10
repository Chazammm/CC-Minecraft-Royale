local M = {}

local OWNER = "Chazammm"
local REPO = "CC-Minecraft-Royale"
local BRANCH = "main"

local TOKEN_DIR = ".cc_royale"
local TOKEN_FILE = TOKEN_DIR .. "/github_token.txt"
local API_BASE = ("https://api.github.com/repos/%s/%s"):format(OWNER, REPO)
local RAW_ROOT = ("https://raw.githubusercontent.com/%s/%s/"):format(
    OWNER,
    REPO
)

local REPORTS = {
    { kind = "mechanics", path = "mechanics_report.txt" },
    { kind = "balance", path = "balance_results.txt" },
    { kind = "comparison", path = "comparison_results.txt" },
    { kind = "evolution", path = "evolution_results.txt" },
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function readAll(path)
    if not fs.exists(path) or fs.isDir(path) then
        return nil, "File not found: " .. path
    end

    local opened, handle = pcall(fs.open, path, "r")
    if not opened or not handle then return nil, "Could not open " .. path end

    local okRead, body = pcall(handle.readAll)
    local okClose, closeResult = pcall(handle.close)
    if not okRead or type(body) ~= "string"
        or not okClose or closeResult == false
    then
        return nil, "Could not read and close " .. path
    end
    return body
end

-- Store credentials by staging, verifying and renaming; never open the
-- active credential in "w" mode. A failed reconfiguration must preserve the
-- previous usable token even after a process interruption.
local function safeTokenDelete(path)
    if not fs.exists(path) then return true end
    if fs.isDir(path) then return false end
    local ok, result = pcall(fs.delete, path)
    return ok and result ~= false and not fs.exists(path)
end

local function tokenMoveVerified(from, to, expected)
    local ok, result = pcall(fs.move, from, to)
    if not ok or result == false then return false end
    return not fs.exists(from) and readAll(to) == expected
end

local function writeAll(path, body)
    if not fs.move or not fs.delete then
        return false, "Credential transactions need filesystem move/delete"
    end
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        local okDir, resultDir = pcall(fs.makeDir, dir)
        if not okDir or resultDir == false then
            return false, "Could not create directory " .. dir
        end
    end

    local temporary, backup = path .. ".tmp", path .. ".bak"

    -- Previous power loss after old->backup: recover old credentials first,
    -- rather than treating the missing active token as an empty installation.
    if fs.exists(backup) and not fs.exists(path) then
        local recoverable = readAll(backup)
        if not recoverable or not tokenMoveVerified(backup, path, recoverable)
        then
            return false, "Existing token backup could not be recovered"
        end
    end

    local oldToken = nil
    if fs.exists(path) then
        oldToken = readAll(path)
        if not oldToken then
            return false, "Existing GitHub token cannot be read safely"
        end
    end

    if not safeTokenDelete(temporary) then
        return false, "Could not clear old token staging file"
    end
    if not safeTokenDelete(backup) then
        return false, "Could not clear stale token backup"
    end

    local opened, handle = pcall(fs.open, temporary, "w")
    if not opened or not handle then
        return false, "Could not stage new GitHub token"
    end

    local okWrite, resultWrite = pcall(handle.write, body)
    local okClose, resultClose = pcall(handle.close)
    if not okWrite or resultWrite == false
        or not okClose or resultClose == false
        or readAll(temporary) ~= body
    then
        safeTokenDelete(temporary)
        return false, "Could not stage/verify new GitHub token"
    end

    if oldToken then
        if not tokenMoveVerified(path, backup, oldToken) then
            if not fs.exists(path) and readAll(backup) == oldToken then
                tokenMoveVerified(backup, path, oldToken)
            end
            safeTokenDelete(temporary)
            return false, "Could not protect previous GitHub token"
        end
    end

    local promoted = tokenMoveVerified(temporary, path, body)
    if not promoted then
        -- A partial destination might still contain useful data; never
        -- delete an unreadable destination or the good .bak blindly.
        if fs.exists(path) and readAll(path) ~= nil then
            safeTokenDelete(path)
        end
        if not fs.exists(path) and oldToken
            and readAll(backup) == oldToken
        then
            tokenMoveVerified(backup, path, oldToken)
        end
        safeTokenDelete(temporary)
        return false, "Could not publish verified GitHub token"
    end

    -- A good active token is now present. If cleaning stale backup fails,
    -- setup still succeeded; the backup is retried on the next setup.
    safeTokenDelete(backup)
    return true
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

local function githubWrite(token, method, url, payload)
    local response, err, failedResponse = http.post({
        url = url,
        body = textutils.serializeJSON(payload or {}),
        headers = {
            ["Accept"] = "application/vnd.github+json",
            ["Authorization"] = "Bearer " .. token,
            ["X-GitHub-Api-Version"] = "2022-11-28",
            ["User-Agent"] = "CC-Minecraft-Royale-report-sync",
            ["Content-Type"] = "application/json",
        },
        method = method,
        timeout = 30,
    })

    if response then
        local code, responseBody = responseDetails(response)
        return code and code >= 200 and code < 300, code, responseBody
    end

    local code, responseBody = responseDetails(failedResponse)
    return false, code, responseBody ~= "" and responseBody or tostring(err)
end

local function remoteLatestMatches(path, content, revision)
    if not http or not http.get then return false end
    if type(revision) ~= "string" or revision == "" then return false end

    local response, _, failedResponse = http.get({
        url = RAW_ROOT .. revision .. "/" .. path,
        timeout = 10,
    })
    if not response then
        -- CC:Tweaked may return an HTTP failure handle even when the primary
        -- response is nil. Consume/close it so repeated sync attempts cannot
        -- leak response handles.
        responseDetails(failedResponse)
        return false
    end

    local code = response.getResponseCode
        and select(1, response.getResponseCode())
        or 200
    if code ~= 200 then
        if response.close then response.close() end
        return false
    end

    local body = response.readAll and response.readAll() or ""
    if response.close then response.close() end
    return body == content
end

local function decodeGithub(body, context)
    local decoded, decodeErr = textutils.unserializeJSON(body or "")
    if not decoded then
        return nil, (context or "GitHub response")
            .. " JSON error: " .. tostring(decodeErr)
    end
    return decoded
end

local function branchHeadSha(token)
    local ok, code, body = githubGet(
        token,
        API_BASE .. "/git/ref/heads/" .. BRANCH
    )
    if not ok or code ~= 200 then return nil end

    local ref = decodeGithub(body, "branch ref")
    return ref and ref.object and ref.object.sha or nil
end

local function commitFilesOnce(token, files, message)
    -- Git Data API lets history + latest move in one commit, avoiding two
    -- report-only commits for every benchmark upload.
    local ok, code, body = githubGet(
        token,
        API_BASE .. "/git/ref/heads/" .. BRANCH
    )
    if not ok or code ~= 200 then
        return false, ("Could not read %s HEAD (HTTP %s): %s"):format(
            BRANCH,
            tostring(code or "?"),
            tostring(body or "")
        )
    end

    local ref, refErr = decodeGithub(body, "branch ref")
    if not ref then return false, refErr end
    local parentSha = ref.object and ref.object.sha
    if not parentSha then return false, "GitHub branch ref had no commit SHA" end

    ok, code, body = githubGet(
        token,
        API_BASE .. "/git/commits/" .. parentSha
    )
    if not ok or code ~= 200 then
        return false, ("Could not read parent commit (HTTP %s): %s"):format(
            tostring(code or "?"),
            tostring(body or "")
        )
    end

    local parent, parentErr = decodeGithub(body, "parent commit")
    if not parent then return false, parentErr end
    local baseTree = parent.tree and parent.tree.sha
    if not baseTree then return false, "GitHub parent commit had no tree SHA" end

    local treeEntries = {}
    for _, file in ipairs(files) do
        local blobOk, blobCode, blobBody = githubWrite(
            token,
            "POST",
            API_BASE .. "/git/blobs",
            {
                content = file.content,
                encoding = "utf-8",
            }
        )
        if not blobOk then
            return false, ("Could not create blob for %s (HTTP %s): %s")
                :format(
                    file.path,
                    tostring(blobCode or "?"),
                    tostring(blobBody or "")
                )
        end

        local blob, blobErr = decodeGithub(blobBody, "blob")
        if not blob then return false, blobErr end

        treeEntries[#treeEntries + 1] = {
            path = file.path,
            mode = "100644",
            type = "blob",
            sha = blob.sha,
        }
    end

    local treeOk, treeCode, treeBody = githubWrite(
        token,
        "POST",
        API_BASE .. "/git/trees",
        {
            base_tree = baseTree,
            tree = treeEntries,
        }
    )
    if not treeOk then
        return false, ("Could not create report tree (HTTP %s): %s"):format(
            tostring(treeCode or "?"),
            tostring(treeBody or "")
        )
    end
    local tree, treeErr = decodeGithub(treeBody, "tree")
    if not tree then return false, treeErr end

    local commitOk, commitCode, commitBody = githubWrite(
        token,
        "POST",
        API_BASE .. "/git/commits",
        {
            message = message,
            tree = tree.sha,
            parents = { parentSha },
        }
    )
    if not commitOk then
        return false, ("Could not create report commit (HTTP %s): %s"):format(
            tostring(commitCode or "?"),
            tostring(commitBody or "")
        )
    end
    local commit, commitErr = decodeGithub(commitBody, "commit")
    if not commit then return false, commitErr end

    local refOk, refCode, refBody = githubWrite(
        token,
        "PATCH",
        API_BASE .. "/git/refs/heads/" .. BRANCH,
        {
            sha = commit.sha,
            force = false,
        }
    )
    if not refOk then
        return false, ("Could not advance %s (HTTP %s): %s"):format(
            BRANCH,
            tostring(refCode or "?"),
            tostring(refBody or "")
        )
    end

    return true, commit.sha
end

local function commitFiles(token, files, message)
    local ok, result = commitFilesOnce(token, files, message)
    if ok then return true, result end

    -- A report upload may race with a normal code push or another report.
    -- The non-force ref update fails safely; rebuild once on the new HEAD
    -- instead of making the user manually rerun the whole benchmark sync.
    if tostring(result):find("Could not advance", 1, true) then
        return commitFilesOnce(token, files, message)
    end

    return false, result
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

-- A power loss can leave the original token in .bak after the first
-- rename. Treat it as a readable fallback until a subsequent setup restores
-- it; never replace a present but unreadable active token implicitly.
local function readStoredToken()
    if fs.exists(TOKEN_FILE) then
        return readAll(TOKEN_FILE)
    end
    return readAll(TOKEN_FILE .. ".bak")
end

function M.isConfigured()
    local token = readStoredToken()
    return token ~= nil and #trim(token) >= 20
end

function M.readToken()
    local token, err = readStoredToken()
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

    if code ~= 200 then
        return false, "Unexpected HTTP " .. tostring(code)
    end

    local repo, decodeErr = decodeGithub(body, "repository")
    if not repo then return false, decodeErr end

    local permissions = repo.permissions or {}
    if permissions.push ~= true then
        return false,
            "Token can read the repo but cannot write it. "
            .. "Grant this repository Contents: Read and write."
    end

    return true, "GitHub connection OK (write access confirmed)"
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
    -- After a crash, .bak or .tmp may still hold a valid credential. Logout
    -- must not leave either secret behind or report success prematurely.
    for _, path in ipairs({
        TOKEN_FILE,
        TOKEN_FILE .. ".tmp",
        TOKEN_FILE .. ".bak",
    }) do
        if fs.exists(path) then
            if fs.isDir(path) then
                return false, "Token transaction path is a directory: " .. path
            end
            if not safeTokenDelete(path) then
                return false, "Could not remove local GitHub token file: " .. path
            end
        end
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

    local snapshotSha = branchHeadSha(token)
    if snapshotSha and remoteLatestMatches(latestPath, content, snapshotSha) then
        return true, {
            kind = kind,
            localPath = localPath,
            latestPath = latestPath,
            stamp = stamp,
            unchanged = true,
        }
    end

    local ok, commitOrErr = commitFiles(
        token,
        {
            { path = historyPath, content = content },
            { path = latestPath, content = content },
        },
        ("Sync %s report %s"):format(kind, stamp)
    )
    if not ok then return false, commitOrErr end

    return true, {
        kind = kind,
        localPath = localPath,
        historyPath = historyPath,
        latestPath = latestPath,
        stamp = stamp,
        commitSha = commitOrErr,
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
    local snapshotSha = branchHeadSha(token)
    local pending = {}
    local skipped = {}
    local commitEntries = {}
    local failures = {}

    for _, report in ipairs(REPORTS) do
        if fs.exists(report.path) and not fs.isDir(report.path) then
            local content, readErr = readAll(report.path)
            if content then
                local fileName = fs.getName(report.path)
                local historyPath =
                    ("reports/history/%s/%s_%s"):format(
                        report.kind,
                        stamp,
                        fileName
                    )
                local latestPath = "reports/latest/" .. fileName

                if snapshotSha
                    and remoteLatestMatches(latestPath, content, snapshotSha)
                then
                    skipped[#skipped + 1] = {
                        kind = report.kind,
                        localPath = report.path,
                        latestPath = latestPath,
                        stamp = stamp,
                        unchanged = true,
                    }
                else
                    commitEntries[#commitEntries + 1] = {
                        path = historyPath,
                        content = content,
                    }
                    commitEntries[#commitEntries + 1] = {
                        path = latestPath,
                        content = content,
                    }
                    pending[#pending + 1] = {
                        kind = report.kind,
                        localPath = report.path,
                        historyPath = historyPath,
                        latestPath = latestPath,
                        stamp = stamp,
                    }
                end
            else
                failures[#failures + 1] =
                    report.path .. ": " .. tostring(readErr)
            end
        end
    end

    if #pending == 0 and #skipped == 0 and #failures == 0 then
        return false, "No report files found yet."
    end

    local uploaded = {}
    if #pending > 0 then
        local ok, commitOrErr = commitFiles(
            token,
            commitEntries,
            ("Sync report batch %s"):format(stamp)
        )

        if ok then
            for _, result in ipairs(pending) do
                result.commitSha = commitOrErr
                uploaded[#uploaded + 1] = result
            end
        else
            failures[#failures + 1] =
                "GitHub batch commit: " .. tostring(commitOrErr)
        end
    end

    return #failures == 0, {
        uploaded = uploaded,
        failures = failures,
        skipped = skipped,
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

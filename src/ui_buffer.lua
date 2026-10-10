local ui = {}

function ui.newBuffer(
    width,
    height,
    defaultFg,
    defaultBg,
    skipZone,
    reusable
)
    local buffer = reusable
    if not buffer
        or buffer.width ~= width
        or buffer.height ~= height
    then
        buffer = {
            width = width,
            height = height,
            chars = {},
            fg = {},
            bg = {},
            flushChars = {},
            flushFg = {},
            flushBg = {},
            lastFlushLine = {},
        }
    end

    buffer.width = width
    buffer.height = height

    for y = 1, height do
        local skipped = skipZone
            and y >= skipZone.y1
            and y <= skipZone.y2

        if skipped then
            buffer.chars[y] = nil
            buffer.fg[y] = nil
            buffer.bg[y] = nil
            buffer.lastFlushLine[y] = nil
        else
            local chars = buffer.chars[y] or {}
            local fg = buffer.fg[y] or {}
            local bg = buffer.bg[y] or {}
            buffer.chars[y] = chars
            buffer.fg[y] = fg
            buffer.bg[y] = bg

            for x = 1, width do
                chars[x] = " "
                fg[x] = defaultFg or colors.white
                bg[x] = defaultBg or colors.black
            end
        end
    end

    return buffer
end

function ui.setCell(buffer, x, y, char, fg, bg)
    x = math.floor(x)
    y = math.floor(y)
    if x < 1 or x > buffer.width or y < 1 or y > buffer.height then return end
    if not buffer.chars[y] then return end

    buffer.chars[y][x] = (char or " "):sub(1, 1)
    if fg then buffer.fg[y][x] = fg end
    if bg then buffer.bg[y][x] = bg end
end

function ui.fill(buffer, x1, y1, x2, y2, bg, char, fg)
    x1 = math.max(1, math.floor(x1))
    y1 = math.max(1, math.floor(y1))
    x2 = math.min(buffer.width, math.floor(x2))
    y2 = math.min(buffer.height, math.floor(y2))

    for y = y1, y2 do
        for x = x1, x2 do
            ui.setCell(
                buffer,
                x,
                y,
                char or " ",
                fg or colors.white,
                bg
            )
        end
    end
end

function ui.writeText(buffer, x, y, text, fg, bg)
    text = tostring(text or "")
    for i = 1, #text do
        ui.setCell(
            buffer,
            x + i - 1,
            y,
            text:sub(i, i),
            fg or colors.white,
            bg
        )
    end
end

function ui.centered(buffer, y, text, fg, bg)
    local x = math.floor((buffer.width - #text) / 2) + 1
    ui.writeText(buffer, x, y, text, fg, bg)
end

function ui.flush(buffer, monitor, skipZone)
    for y = 1, buffer.height do
        local skipped = skipZone
            and y >= skipZone.y1
            and y <= skipZone.y2

        if not skipped then
            local chars = buffer.flushChars[y] or {}
            local fg = buffer.flushFg[y] or {}
            local bg = buffer.flushBg[y] or {}
            buffer.flushChars[y] = chars
            buffer.flushFg[y] = fg
            buffer.flushBg[y] = bg

            for x = 1, buffer.width do
                chars[x] = buffer.chars[y][x]
                fg[x] = colors.toBlit(buffer.fg[y][x])
                bg[x] = colors.toBlit(buffer.bg[y][x])
            end

            local charLine = table.concat(chars)
            local fgLine = table.concat(fg)
            local bgLine = table.concat(bg)
            local signature = charLine .. "\0" .. fgLine .. "\0" .. bgLine

            if buffer.lastFlushLine[y] ~= signature then
                monitor.setCursorPos(1, y)
                monitor.blit(charLine, fgLine, bgLine)
                buffer.lastFlushLine[y] = signature
            end
        end
    end
end

return ui

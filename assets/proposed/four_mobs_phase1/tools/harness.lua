-- Host-only renderer probe. Uses debug upvalues instead of changing production APIs.
local H={root='assets/proposed/four_mobs_phase1/'}
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local renderer=require('src.pixel_arena')
local function upvalue(fn,wanted,seen)
    seen=seen or {};if seen[fn] then return end;seen[fn]=true
    for i=1,math.huge do
        local name,value=debug.getupvalue(fn,i);if not name then break end
        if name==wanted then return value end
        if type(value)=='function' then
            local found=upvalue(value,wanted,seen);if found then return found end
        end
    end
end
H.sprites=assert(upvalue(renderer.draw,'SPRITES'))
H.palette=assert(upvalue(renderer.draw,'PALETTE'))
local getSurface=assert(upvalue(renderer.draw,'getSurface'))
local project=assert(upvalue(renderer.draw,'worldToPixel'))
local alignX=assert(upvalue(renderer.draw,'alignTexelX'))
local alignY=assert(upvalue(renderer.draw,'alignTexelY'))
local put=assert(upvalue(renderer.draw,'put'))
function H.read(kind,name)
    return assert(loadfile(H.root..kind..'/'..name..'.lua','t',{}))()
end
local function jsonString(s)
    return '"'..s:gsub('[%z\1-\31\\"]',function(c)
        if c=='"' then return '\\"' elseif c=='\\' then return '\\\\' end
        return ('\\u%04x'):format(c:byte())
    end)..'"'
end
function H.json(value)
    local t=type(value)
    if t=='string' then return jsonString(value) end
    if t=='number' then return ('%.17g'):format(value) end
    if t=='boolean' then return value and 'true' or 'false' end
    if t=='nil' then return 'null' end
    assert(t=='table','Unsupported JSON type')
    local keys={};for k in pairs(value)do keys[#keys+1]=k end
    local array=#value>0
    if array then for _,k in ipairs(keys)do if type(k)~='number' then array=false end end end
    local parts={}
    if array then for _,v in ipairs(value)do parts[#parts+1]=H.json(v)end
    else table.sort(keys);for _,k in ipairs(keys)do parts[#parts+1]=jsonString(k)..':'..H.json(value[k])end end
    return (array and '[' or '{')..table.concat(parts,',')..(array and ']' or '}')
end
function H.write(path,value)
    local f=assert(io.open(path,'w'));f:write(H.json(value),'\n');f:close()
end

function H.capture(frame,kind,options)
    options=options or {}
    local w,h=options.w or 51,options.h or 40
    local viewer,owner=options.viewer or 1,options.owner or 1
    local monitor={};local lines={};local calls=0
    local oldWindow=window
    window={create=function(_,_,_,width,height)
        local row=1
        return {getSize=function()return width,height end,
            getBackgroundColor=function()return colors.black end,setBackgroundColor=function()end,
            clear=function()end,setCursorPos=function(_,y)row=y end,
            blit=function(chars,fg,bg)
                assert(#chars==width and #fg==width and #bg==width)
                calls=calls+1;lines[row]={chars=chars,fg=fg,bg=bg}
            end}
    end}
    local saved=H.sprites.__phase1_preview
    H.sprites.__phase1_preview=frame
    local state={phase='battle',entities={},projectiles={},effects={}}
    local entity={id=1,alive=true,owner=owner,x=50,y=40,hp=options.hp or 100,maxHp=100,
        name='Unregistered asset preview',kind='unit',visualVariant='__phase1_preview',
        damageFlash=options.flash and 1 or nil}
    if kind=='unit' then state.entities={entity} end
    if options.target then
        state.entities={{id=2,alive=true,owner=3-owner,x=50,y=40,hp=100,maxHp=100,
            name='Zombie',kind='unit'}}
    end
    local rect={x1=1,y1=1,x2=w,y2=h}
    local ok,result=pcall(function()
        local function signature()
            local parts={};for y=1,h do
                local line=assert(lines[y]);parts[#parts+1]=line.chars..'@'..line.fg..'@'..line.bg
            end
            return table.concat(parts,'\n')
        end
        local emptySignature
        if options.nextFrame then
            local entities=state.entities;state.entities={}
            renderer.draw(monitor,state,viewer,rect);emptySignature=signature();state.entities=entities
        end
        renderer.draw(monitor,state,viewer,rect)
        local box=getSurface(monitor,rect)
        local cx,cy=project(box,viewer,50,40)
        local x1,y1=alignX(cx-frame.width/2),alignY(cy-frame.height/2)
        if kind~='unit' then
            for y,row in ipairs(frame.rows)do for x=1,#row do
                local token=row:sub(x,x)
                if token~='.' then put(box,x1+x-1,y1+y-1,H.palette[token])end
            end end
            box:render()
        end
        local canvas={};for y=1,box.height do
            local row={};for x=1,box.width do row[x]=box.canvas[y][x]end;canvas[y]=row
        end
        local firstCalls=calls
        if kind=='unit' then
            renderer.draw(monitor,state,viewer,rect)
            assert(calls==firstCalls,'Stationary asset defeated renderer cache')
        end
        local col1=math.max(1,math.floor((x1-1-4)/2)+1)
        local col2=math.min(w,math.floor((x1-1+frame.width+3)/2)+1)
        local row1=math.max(1,math.floor((y1-1-6)/3)+1)
        local row2=math.min(h,math.floor((y1-1+frame.height+3)/3)+1)
        local crop={}
        for y=row1,row2 do
            local source=assert(lines[y]);local bytes={}
            for x=col1,col2 do bytes[#bytes+1]=source.chars:byte(x)end
            crop[#crop+1]={bytes=bytes,fg=source.fg:sub(col1,col2),bg=source.bg:sub(col1,col2)}
        end
        local all={};for y=1,h do
            local source=assert(lines[y]);local bytes={}
            for x=1,w do bytes[x]=source.chars:byte(x)end
            all[y]={bytes=bytes,fg=source.fg,bg=source.bg}
        end
        local sequenceChecks=false
        if options.nextFrame then
            local before=signature();local previousCalls=calls
            H.sprites.__phase1_preview=options.nextFrame
            renderer.draw(monitor,state,viewer,rect)
            assert(signature()~=before and calls>previousCalls,'New pose stayed cached on the same monitor')
            H.sprites.__phase1_preview=frame
            renderer.draw(monitor,state,viewer,rect)
            assert(signature()==before,'Round-trip pose left ghost pixels')
            state.entities={};renderer.draw(monitor,state,viewer,rect)
            assert(signature()==emptySignature,'Removed preview left ghost pixels')
            sequenceChecks=true
        end
        return {rows=frame.rows,width=frame.width,height=frame.height,origin={x=x1,y=y1},
            terminalCrop=crop,terminal=all,canvas=canvas,
            pipeline=kind=='unit' and 'ACTUAL_ARENA_SPRITE_AND_PIXELBOX' or 'ISOLATED_ROW_OVERLAY_AND_ACTUAL_PIXELBOX',
            blitCalls=calls,viewer=viewer,owner=owner,sequenceChecks=sequenceChecks}
    end)
    H.sprites.__phase1_preview=saved;window=oldWindow;renderer.invalidate(monitor)
    if not ok then error(result,0)end
    return result
end
return H

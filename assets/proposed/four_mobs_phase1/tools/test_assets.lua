-- Isolated host-only QA. No new card, combat behavior or live asset is registered.
local H=require('assets.proposed.four_mobs_phase1.tools.harness')
local cards=require('src.cards')
local render=require('src.render')
local util=require('src.util')
local names={'ravager_rider','baby_ender_dragon','minoshroom','hero_spider'}
local checks,captures=0,0
local function check(ok,message)checks=checks+1;assert(ok,message)end
local function validate(frame)
    assert(type(frame)=='table','Frame must be a table')
    assert(util.isFiniteNumber(frame.width) and frame.width==math.floor(frame.width)
        and frame.width>=1 and frame.width<=16,'Invalid width')
    assert(util.isFiniteNumber(frame.height) and frame.height==math.floor(frame.height)
        and frame.height>=1 and frame.height<=18,'Invalid height')
    assert(type(frame.rows)=='table' and #frame.rows==frame.height,'Invalid row count')
    local visible=0
    for _,row in ipairs(frame.rows)do
        assert(type(row)=='string' and #row==frame.width,'Ragged frame')
        for i=1,#row do
            local t=row:sub(i,i)
            assert(t=='.' or t=='T' or H.palette[t],'Unknown palette token')
            if t~='.' then visible=visible+1 end
        end
    end
    assert(visible>0,'Empty frame')
end
local nibbleColors={};for i=0,15 do nibbleColors[('%x'):format(i)]=2^i end
local function encodedPixel(capture,x,y)
    local cell=capture.terminal[math.floor((y-1)/3)+1]
    local column=math.floor((x-1)/2)+1;local b=cell.bytes[column]
    local bit=(y-1)%3*2+(x-1)%2
    local foreground=b>=128 and bit<5 and math.floor((b-128)/2^bit)%2==1
    return nibbleColors[(foreground and cell.fg or cell.bg):sub(column,column)]
end
local originalSpriteCount=0;for _ in pairs(H.sprites)do originalSpriteCount=originalSpriteCount+1 end
local cardCount,evoCount=#cards.list,#cards.evolutionCards()
local sizes={}
for _,size in ipairs({{45,42},{51,52},{57,62}})do
    local layout=render.layoutFor({getSize=function()return size[1],size[2]end})
    sizes[#sizes+1]={layout.arena.x2-layout.arena.x1+1,layout.arena.y2-layout.arena.y1+1}
end
local unitFrames,effectFrames=0,0
for _,name in ipairs(names)do
    local asset=H.read('sprites',name);local fx=H.read('effects',name)
    check(asset.runtimeRegistered==false and fx.runtimeRegistered==false,'Asset mistakenly marked active')
    check(asset.frameStatus=='PREPARED_STATIC_RASTER_NOT_LIVE_ANIMATION','Misleading animation status')
    local first=asset.frames.idle
    local hashes={}
    for frameName,frame in pairs(asset.frames)do
        validate(frame);unitFrames=unitFrames+1
        check(frame.width==first.width and frame.height==first.height,'Animation canvas jitter')
        for _,size in ipairs(sizes)do for viewer=1,2 do
            local capture=H.capture(frame,'unit',{w=size[1],h=size[2],viewer=viewer})
            captures=captures+1
            if size==sizes[1] and viewer==1 then hashes[frameName]=H.json(capture.terminalCrop)end
            for y,row in ipairs(frame.rows)do for x=1,#row do
                local token=row:sub(x,x)
                if token~='.' then
                    local px,py=capture.origin.x+x-1,capture.origin.y+y-1
                    check(px>=1 and px<=size[1]*2 and py>=1 and py<=size[2]*3,'Clipped valid-size unit')
                    local expected=token=='T' and (viewer==1 and colors.lightBlue or colors.red) or H.palette[token]
                    check(capture.canvas[py][px]==expected,'Actual renderer does not reproduce native pixel')
                end
            end end
            for _,line in ipairs(capture.terminal)do
                check(not line.fg:find('[^0-9a-f]') and not line.bg:find('[^0-9a-f]'),'Malformed blit palette')
                for _,byte in ipairs(line.bytes)do check(byte==32 or byte>=128 and byte<=159,'Invalid semigraphic glyph')end
            end
        end end
        if name=='hero_spider' then
            check(#frame.limbTips==8,'Spider must have eight explicit leg endpoints')
            local seen,left,right={},0,0
            for _,point in ipairs(frame.limbTips)do
                local x,y=point[1],point[2];local key=x..':'..y
                check(not seen[key] and x>=1 and x<=16 and y>=1 and y<=10,'Invalid/duplicate leg endpoint')
                seen[key]=true;check(frame.rows[y]:sub(x,x)~='.','Invisible leg endpoint')
                if x<=8 then left=left+1 else right=right+1 end
            end
            check(left==4 and right==4,'Spider legs must remain four per side')
        end
    end
    for seqName,seq in pairs(asset.previewSequences)do
        local seen={};local n=0
        for _,entry in ipairs(seq)do
            check(asset.frames[entry.frame]~=nil,'Missing sequence frame')
            check(entry.durationMs>0 and entry.durationMs%10==0,'Invalid GIF preview timing')
            local hash=hashes[entry.frame];if not seen[hash] then seen[hash]=true;n=n+1 end
        end
        check(n>=2,'Sequence disappears through PixelBox: '..name..'/'..seqName)
    end
    for viewer=1,2 do
        local capture=H.capture(first,'unit',{viewer=viewer,nextFrame=asset.frames.walk_a or asset.frames.flight_up})
        captures=captures+1;check(capture.sequenceChecks,'Same-monitor animation cache not exercised')
    end
    for key,frame in pairs(fx.frames)do
        validate(frame);effectFrames=effectFrames+1
        for viewer=1,2 do
            local capture=H.capture(frame,'effect',{viewer=viewer});captures=captures+1
            for y,row in ipairs(frame.rows)do for x=1,#row do
                local token=row:sub(x,x)
                if token~='.' then check(capture.canvas[capture.origin.y+y-1][capture.origin.x+x-1]==H.palette[token],
                    'Effect raster mismatch '..key)end
            end end
        end
    end
end
-- Native eyes must survive the encoder, not merely exist in the source rows.
for _,spec in ipairs({{'ravager_rider',6,2,colors.green},{'ravager_rider',8,2,colors.green},
    {'baby_ender_dragon',6,4,colors.purple},{'baby_ender_dragon',11,4,colors.purple},
    {'hero_spider',6,5,colors.white},{'hero_spider',10,5,colors.white}})do
    local frame=H.read('sprites',spec[1]).frames.idle;local c=H.capture(frame,'unit')
    local survived=false
    for y=spec[3],math.min(spec[3]+1,frame.height)do for x=spec[2],math.min(spec[2]+1,frame.width)do
        if encodedPixel(c,c.origin.x+x-1,c.origin.y+y-1)==spec[4]then survived=true end
    end end
    check(survived,'Critical eye colour lost by PixelBox: '..spec[1])
end
-- Detect broken assets with negative fixtures; never write them to disk.
for _,fault in ipairs({'token','ragged','dimension','empty'})do
    local f={width=2,height=2,rows={'WW','WW'}}
    if fault=='token' then f.rows[1]='WZ' elseif fault=='ragged' then f.rows[1]='W'
    elseif fault=='dimension' then f.width=17 else f.rows={'..','..'}end
    check(not pcall(validate,f),'Validator missed injected '..fault)
end
local count=0;for _ in pairs(H.sprites)do count=count+1 end
check(count==originalSpriteCount and H.sprites.__phase1_preview==nil,'Renderer dictionary leaked preview assets')
check(#cards.list==cardCount and #cards.evolutionCards()==evoCount,'New card/Evo registered during Phase 1')
for _,name in ipairs(names)do check(cards.get(name)==nil,'Phase-1 card became playable: '..name)end
check(unitFrames==25 and effectFrames==15,'Incomplete asset set')
local report={status='PASS',checks=checks,captures=captures,unitFrames=unitFrames,effectFrames=effectFrames,
    monitorSizes={{45,42},{51,52},{57,62}},cameraPerspectives=2,
    negativeFixtures=4,gameplayIntegration='NOT_STARTED',physicalHardware='NOT_TESTED'}
if arg and arg[1]then H.write(arg[1],report)end
print(('PASS: %d assertions, %d real captures, 25 unit frames, 15 effects, both views / 3 monitor sizes'):format(checks,captures))

local _, JLP = ...
-- Small bounded, non-persistent pages to show complete route rationale without
-- trusting pixel widths, scroll availability or changing the planner.
local Explanation={contract="jlp-gathering-route-explanation-v1",nativeDispatchAllowed=false,
    maxCharactersPerPage=132,maxLinesPerPage=4}
-- WoW Lua does not guarantee a standalone utf8 library. Count complete
-- encoded characters when wrapping so a page cannot split a UTF-8 sequence
-- in the middle (ASCII behavior remains byte-for-byte identical).
local function charEnd(text,start)
    local b=text:byte(start)
    if not b then return start-1 end
    local length=(b>=194 and b<=223 and 2) or (b>=224 and b<=239 and 3) or
        (b>=240 and b<=244 and 4) or 1
    -- For malformed source bytes, advance one byte without inventing text.
    for j=start+1,math.min(#text,start+length-1) do
        local continuation=text:byte(j)
        if not continuation or continuation<128 or continuation>191 then return start end
    end
    return math.min(#text,start+length-1)
end
local function charCount(text)
    local count,i=0,1
    while i<=#text do i=charEnd(text,i)+1;count=count+1 end
    return count
end
local function charSlice(text,count)
    local i,seen=1,0
    while i<=#text and seen<count do i=charEnd(text,i)+1;seen=seen+1 end
    return text:sub(1,i-1),text:sub(i)
end
local function split(text,width)
    local lines={}
    for paragraph in (tostring(text or "").."\n"):gmatch("(.-)\n") do
        if paragraph=="" then lines[#lines+1]=" " end
        local current=""
        for word in paragraph:gmatch("%S+") do
            if #current>0 and charCount(current)+charCount(word)+1>width then
                lines[#lines+1]=current;current=""
            end
            if charCount(word)>width then
                if #current>0 then lines[#lines+1]=current;current="" end
                while charCount(word)>width do
                    local chunk,rest=charSlice(word,width)
                    lines[#lines+1]=chunk;word=rest
                end
            end
            current=current=="" and word or (current.." "..word)
        end
        if current~="" then lines[#lines+1]=current end
    end
    return lines
end
function Explanation:Pages(text,width,maxLines)
    width=math.max(18,math.min(65,math.floor(tonumber(width) or 39)))
    maxLines=math.max(2,math.min(8,math.floor(tonumber(maxLines) or self.maxLinesPerPage)))
    local lines=split(text,width)
    if #lines==0 then lines={"No additional route information available."} end
    local pages={}
    for i=1,#lines,maxLines do
        local chunk={}
        for j=i,math.min(i+maxLines-1,#lines) do chunk[#chunk+1]=lines[j] end
        pages[#pages+1]=table.concat(chunk,"\n")
    end
    return pages
end
JLP:RegisterModule("GatheringRouteExplanation",Explanation)

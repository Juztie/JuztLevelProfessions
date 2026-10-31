-- JuztTom: renderer independent of 0.30s route/bridge refresh.
-- All rotations use radians, WoW's counterclockwise facing convention.
local _, JLP = ...
local JT = JLP._integratedTom
local pi, abs, min, exp=math.pi,math.abs,math.min,math.exp
local TAU=2*pi
local PRESETS={fast=0.055,balanced=0.110,gentle=0.210}
local function finite(v)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end
local function wrap(a) return (a+pi)%TAU-pi end

function JT:SetArrowStyle(style)
    if style~="classic" and style~="updated" and style~="clean" then return false end
    if not self.profile then return false end
    self.profile.arrowStyle=style
    if self.RefreshUI then self:RefreshUI() end
    return true
end
function JT:MotionStep(previous,desired,elapsed,preset,enabled)
    if not finite(desired) then return nil end
    desired=wrap(desired)
    if not finite(previous) or enabled==false then return desired end
    elapsed=tonumber(elapsed) or 0
    if not finite(elapsed) or elapsed<=0 then return wrap(previous) end
    -- Stable under different frame rates, uses the SHORTEST wrapped arc.
    -- Rate cap prevents very large instantaneous turns after a long frame.
    local t=PRESETS[preset] or PRESETS.balanced
    local alpha=1-exp(-min(elapsed,0.15)/t)
    local delta=wrap(desired-previous)
    local maxStep=TAU*3*min(elapsed,0.15) -- 1080 degrees/sec
    local amount=delta*alpha
    if amount>maxStep then amount=maxStep elseif amount< -maxStep then amount=-maxStep end
    return wrap(previous+amount)
end
function JT:GetFastBearing(point)
    if not point or type(C_Map)~="table" or type(C_Map.GetPlayerMapPosition)~="function" then return nil end
    local ok,pos=pcall(C_Map.GetPlayerMapPosition,point.mapID,"player")
    if not ok or not pos then return nil end
    local good,x,y=pcall(function()
        if type(pos.GetXY)=="function" then return pos:GetXY() end
        return pos.x,pos.y
    end)
    if not good or not self:ValidPoint(point.mapID,x,y) then return nil end
    local dx,dy=point.x-x,point.y-y
    if abs(dx)<0.000000001 and abs(dy)<0.000000001 then return self.geometry and self.geometry.direction end
    local atan2=math.atan2
    local angle
    if type(atan2)=="function" then angle=atan2(-dx,-dy)
    elseif -dy>0 then angle=math.atan(-dx/-dy)
    elseif -dy<0 then angle=math.atan(-dx/-dy)+((-dx)>=0 and pi or -pi)
    else angle=(-dx)>0 and pi/2 or (-dx)<0 and -pi/2 or 0 end
    return angle%TAU
end
function JT:UpdateArrowMotion(elapsed)
    if not (self.profile and self.arrowTexture and self.arrowFrame) then return end
    local point=self.current
    if not self.profile.arrowShown or not point or not self.geometry or not self.geometry.positionAvailable then
        self._motionAngle=nil
        self._motionHeading=nil
        self._motionTargetKey=nil
        return
    end
    if self._motionTargetKey~=self.activeTargetKey then
        self._motionTargetKey=self.activeTargetKey
        self._motionHeading=self.geometry.direction
        self._bearingElapsed=0
    end
    self._bearingElapsed=(self._bearingElapsed or 0)+(tonumber(elapsed) or 0)
    if self._bearingElapsed>=self.motionInterval then
        self._bearingElapsed=self._bearingElapsed%self.motionInterval
        -- Position changes use light map-XY reads, never route/plan regeneration.
        local bearing=self:GetFastBearing(point)
        if finite(bearing) then self._motionHeading=bearing end
    end
    local face
    if type(GetPlayerFacing)=="function" then
        local ok,value=pcall(GetPlayerFacing)
        if ok and finite(value) then face=value end
    end
    if not finite(face) or not finite(self._motionHeading) then
        self.arrowTexture:SetAlpha(0.4)
        return
    end
    local desired=self:RelativeRotation(self._motionHeading,face)
    if not finite(desired) then return end
    local nextAngle=self:MotionStep(self._motionAngle,desired,elapsed,
        self.profile.motionPreset,self.profile.smoothMotion)
    if not finite(nextAngle) then return end
    if self.arrowTexture.SetRotation then
        local good=pcall(self.arrowTexture.SetRotation,self.arrowTexture,nextAngle)
        if not good then self.arrowTexture:SetAlpha(0.4);return end
    end
    self._motionAngle=nextAngle
    self.arrowTexture:SetAlpha(1)
end

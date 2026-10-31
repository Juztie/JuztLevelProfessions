local _,JLP=...
-- Alpha179: main UI has fixed inner geometry; fit the entire frame uniformly.
-- Logical UIParent units only, never framebuffer pixels.
local Layout={contract="jlp-main-viewport-v1",margin=16,minimumUsableScale=0.40,nativeDispatchAllowed=false}
local function finite(v,default)
 return type(v)=="number" and v==v and v>0 and v<100000 and v or default
end
function Layout:Fit(width,height,requested,baseW,baseH,minScale,maxScale)
 width=finite(width,1600);height=finite(height,900)
 baseW=finite(baseW,1360);baseH=finite(baseH,760)
 local preference=finite(tonumber(requested),1)
 preference=math.max(minScale or .65,math.min(maxScale or 1.30,preference))
 local allowed=math.min((width-2*self.margin)/baseW,(height-2*self.margin)/baseH)
 local scale=math.min(preference,allowed)
 if scale~=scale or scale<=0 then scale=0 end
 return {scale=scale,preferredScale=preference,limited=scale<preference,
  fits=scale>=self.minimumUsableScale,availableWidth=width-2*self.margin,
  availableHeight=height-2*self.margin,scaledWidth=baseW*scale,scaledHeight=baseH*scale,
  persisted=false}
end
function Layout:Signature(width,height,scale)
 return tostring(finite(width,1600))..":"..tostring(finite(height,900))..":"..tostring(finite(scale,1))
end
JLP:RegisterModule("MainViewportLayout",Layout)

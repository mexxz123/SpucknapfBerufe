-- Forever 70938 metal header: native atlas cuts, no second background/bar.
SpucknapfBerufeNativeHeader={}
local function get(object,method,...)
  if not object or type(object[method])~='function' then return nil end
  local ok,a,b,c,d,e,f,g,h=pcall(object[method],object,...)
  if ok then return a,b,c,d,e,f,g,h end
end
-- Client rectangles verified with the in-game atlas diagnosis.
local known={
 ['UI-Frame-Metal-EdgeTop']={8069118,0,1,0.396484375,0.767578125},
 ['UI-Frame-PortraitMetal-CornerTopLeft']={8069116,0.3759765625,0.5615234375,0.376953125,0.748046875},
 ['UI-Frame-Metal-CornerTopRight']={8069116,0.1884765625,0.3740234375,0.376953125,0.748046875},
}
local function atlasInfo(region,expected,w,h)
  if not region then error(expected..': Region fehlt') end
  local actual=get(region,'GetAtlas')
  -- Forever exposes the native renderer alias with one leading underscore.
  local named=actual==expected or actual=='_'..expected
  local file=get(region,'GetTexture')
  local fn=(C_Texture and C_Texture.GetAtlasInfo) or GetAtlasInfo
  local info
  if type(fn)=='function' then local ok,value=pcall(fn,expected);if ok then info=value end end
  local k=known[expected]
  local u0,u1,v0,v1=k[2],k[3],k[4],k[5]
  if type(info)=='table' and tonumber(info.width)==w and tonumber(info.height)==h then
    u0=tonumber(info.leftTexCoord) or u0;u1=tonumber(info.rightTexCoord) or u1
    v0=tonumber(info.topTexCoord) or v0;v1=tonumber(info.bottomTexCoord) or v1
  end
  local q={get(region,'GetTexCoord')}
  local uv=false
  local function near(x,y) return type(x)=='number' and math.abs(x-y)<0.00002 end
  if #q==8 then
    uv=near(q[1],u0) and near(q[2],v0) and near(q[3],u0) and near(q[4],v1)
      and near(q[5],u1) and near(q[6],v0) and near(q[7],u1) and near(q[8],v1)
  elseif #q==4 then uv=near(q[1],u0) and near(q[2],u1) and near(q[3],v0) and near(q[4],v1) end
  -- Native file/UV assignment can discard the atlas name. A shared file alone
  -- cannot identify corners; require the complete rectangle in that case.
  if not ((named and file==k[1]) or (file==k[1] and uv)) then
    error(expected..': nicht identifiziert; Atlas='..tostring(actual)..', Datei='..tostring(file)..', UV='..tostring(uv)..' ['..table.concat(q,',')..']')
  end
  if not file or u1<=u0 or v1<=v0 then error(expected..': Datei/UV ungueltig') end
  return {file=file,u0=u0,u1=u1,v0=v0,v1=v1,w=w,h=h,region=region,name=expected,detected=named and ('Atlasname '..actual) or 'Datei+UV (Atlas='..tostring(actual)..')'}
end
function SpucknapfBerufeNativeHeader.Build(ui,chrome)
  local nine=chrome and chrome.NineSlice
  if not nine then return nil,'NineSlice fehlt' end
  local original={nine.TopEdge,nine.TopLeftCorner,nine.TopRightCorner}
  if not original[1] or not original[2] or not original[3] then return nil,'Obere NineSlice-Region fehlt' end
  local host
  local originalShown={}
  for i,region in ipairs(original) do originalShown[i]=get(region,'IsShown') end
  local ok,result=pcall(function()
    local edge=atlasInfo(original[1],'UI-Frame-Metal-EdgeTop',128,95)
    local left=atlasInfo(original[2],'UI-Frame-PortraitMetal-CornerTopLeft',95,95)
    local right=atlasInfo(original[3],'UI-Frame-Metal-CornerTopRight',95,95)
    host=CreateFrame('Frame',nil,nine);host:Hide();host:SetAllPoints(nine);host:EnableMouse(false)
    host:SetFrameStrata(nine:GetFrameStrata());host:SetFrameLevel(nine:GetFrameLevel()+1)
    if host.SetClipsChildren then host:SetClipsChildren(false) end
    -- Ring geometry calibrated from the complete native client atlas preview.
    -- Full lower-gold crop is [35,42). Its old bottom is 42+36=78.
    -- Ring bottom is 38.5+31=69.5; reserve 0.5 for a real overlap.
    -- ceil(78-(69.5-0.5))=9 is the smallest whole-UI lift for this crop.
    local ringCenter,ringRadius=38.5,31
    local lowerSource,lowerGoldEnd=35,42
    local lift=math.ceil((lowerGoldEnd+36)-(ringCenter+ringRadius-0.5))
    local delta=36-lift
    local lowerY=lowerSource+delta
    local H={host=host,parts={},active=false,delta=delta,lift=lift,visibleHeight=64-lift,titleCenter=(20+lowerY)/2-16,identification=edge.detected..'; links '..left.detected..'; rechts '..right.detected}
    local used=0
    local function piece(a,anchor,dx,dy,dw,dh,sx,sy,sw,sh,kind,layer)
      if dw<=0 or dh<=0 then return end
      if sx<0 or sy<0 or sx+sw>a.w+0.00001 or sy+sh>a.h+0.00001 then error('Atlaszuschnitt ausserhalb der Region') end
      used=used+1
      local p=H.parts[used]
      if not p then p={texture=host:CreateTexture(nil,'ARTWORK')};H.parts[used]=p end
      local t=p.texture
      if t:SetTexture(a.file)==false then error('Atlasdatei nicht ladbar') end
      t:SetTexCoord(a.u0+(a.u1-a.u0)*sx/a.w,a.u0+(a.u1-a.u0)*(sx+sw)/a.w,a.v0+(a.v1-a.v0)*sy/a.h,a.v0+(a.v1-a.v0)*(sy+sh)/a.h)
      t:SetHorizTile(false);t:SetVertTile(false);t:SetVertexColor(1,0.97,0.88,1);t:SetAlpha(1)
      t:SetDrawLayer(layer or 'ARTWORK',0)
      t:ClearAllPoints();t:SetPoint('TOPLEFT',anchor,'TOPLEFT',dx,-dy);t:SetSize(dw,dh);t:Show()
      p.kind=kind;p.sx=sx;p.sy=sy;p.sw=sw;p.sh=sh;p.dx=dx;p.dy=dy;p.dw=dw;p.dh=dh;p.atlas=a.name
    end
    -- Cuts calibrated against the complete 4x atlas previews: metal above 20,
    -- brown interior 20..35, lower metal starts at 35. Only brown changes height.
    local function arm(a,anchor,x,width,sourceX)
      piece(a,anchor,x,0,width,20,sourceX,0,width,20,'upper')
      piece(a,anchor,x,20,width,lowerY-20,sourceX,20,width,15,'interior')
      piece(a,anchor,x,lowerY,width,60,sourceX,35,width,60,'lower')
    end
    local function assemble()
      used=0
      local width=original[1]:GetWidth()
      if not width or width<=0 then error('Obere Kante noch ohne Breite') end
      -- Repeat the native 128-unit tile explicitly. A partial final tile uses
      -- a matching partial UV, rather than stretching the last metal segment.
      local x=0
      while x<width do
        local w=math.min(128,width-x)
        arm(edge,original[1],x,w,0);x=x+w
      end
      -- Retain the left portrait/side pixels at their original 1:1 positions.
      -- The old straight lower arm is omitted outside the circular gold contour.
      piece(left,original[2],0,0,74,35,0,0,74,35,'portrait-fixed','OVERLAY')
      for y=35,42 do
        local dy=y+0.5-38.5
        local boundary=38.5+math.sqrt(math.max(0,31*31-dy*dy))
        piece(left,original[2],0,y,boundary,1,0,y,boundary,1,'portrait-fixed','OVERLAY')
      end
      piece(left,original[2],0,43,74,52,0,43,74,52,'portrait-fixed','OVERLAY')
      arm(left,original[2],74,21,74)
      -- The single lower edge is now horizontal through the left arm as well.
      -- Clip only its hidden left endpoint to the outside of the fixed circle;
      -- every gold row retains exactly the same Y as its full-width counterpart.
      for y=20,lowerGoldEnd+delta-1 do
        local dy=y+0.5-ringCenter
        local start=ringCenter+math.sqrt(math.max(0,ringRadius*ringRadius-dy*dy))-1
        local sy,sh
        if y<lowerY then sy=20+(y-20)*15/(lowerY-20);sh=15/(lowerY-20)
        else sy=y-delta;sh=1 end
        piece(edge,original[2],start,y,74-start,1,(start-95)%128,sy,74-start,sh,'portrait-connector','BACKGROUND')
      end
      -- Complete the SAME horizontal lower edge on the left of the circle.
      -- Start inside the native left rail (atlas X=14); the retained rail/ring
      -- pixels cover the overlap. No new line height or extra lower edge.
      for y=lowerY,lowerGoldEnd+delta-1 do
        local dy=y+0.5-ringCenter
        local finish=ringCenter-math.sqrt(math.max(0,ringRadius*ringRadius-dy*dy))+1
        piece(edge,original[2],14,y,finish-14,1,(14-95)%128,y-delta,finish-14,1,'portrait-left-lower','BACKGROUND')
      end
      -- Keep the entire right vertical metal rail and the top bevel unscaled.
      arm(right,original[3],0,85,0)
      piece(right,original[3],85,0,10,95,85,0,10,95,'right-rail','OVERLAY')
      for i=used+1,#H.parts do H.parts[i].texture:Hide() end
      H.used=used;H.lastWidth=width
    end
    local outerColors={}
    for _,name in ipairs({'LeftEdge','RightEdge','BottomEdge','BottomLeftCorner','BottomRightCorner'}) do
      local r=nine[name]
      if r then local red,green,blue,alpha=get(r,'GetVertexColor');outerColors[r]={red or 1,green or 1,blue or 1,alpha or 1} end
    end
    local function restore(reason)
      H.active=false;H.error=tostring(reason);host:Hide()
      if ui.windowHeaderFailure then ui.windowHeaderFailure(H.error) end
      for r,c in pairs(outerColors) do r:SetVertexColor(c[1],c[2],c[3],c[4]) end
      for i,region in ipairs(original) do if originalShown[i] then region:Show() else region:Hide() end end
    end
    local function warmOuterMetal()
      -- Named outer regions only; never portrait image or inner panels.
      for _,name in ipairs({'LeftEdge','RightEdge','BottomEdge','BottomLeftCorner','BottomRightCorner'}) do
        local region=nine[name]
        if region and region.SetVertexColor then region:SetVertexColor(1,0.97,0.88,1) end
      end
    end
    function H.Layout()
      if H.error then return false end
      if original[1]:GetWidth()~=H.lastWidth then
        local good,why=pcall(assemble)
        if not good then restore(why);return false end
      end
      for _,region in ipairs(original) do region:Hide() end
      warmOuterMetal();H.active=true;host:Show();return true
    end
    assemble() -- Build everything while hidden; never remove native art on partial failure.
    for _,region in ipairs(original) do region:Hide() end
    warmOuterMetal();H.active=true;host:Show()
    -- Run after native NineSlice show/size handling, which may refresh its regions.
    if type(nine.HookScript)=='function' then
      nine:HookScript('OnShow',function() H.Layout() end)
      nine:HookScript('OnSizeChanged',function() H.Layout() end)
    end
    return H
  end)
  if not ok then
    if host then host:Hide() end
    for i,region in ipairs(original) do if originalShown[i] then region:Show() else region:Hide() end end
    return nil,tostring(result)
  end
  return result
end


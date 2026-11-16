-- Temporary visual inspector. Only the explicit slash command creates preview objects.
SpucknapfBerufeHeaderAtlas={}
local window,host,chat,current
local selected=1
local specs={
  {key='TopEdge',atlas='UI-Frame-Metal-EdgeTop',label='1: Obere Kante'},
  {key='TopLeftCorner',atlas='UI-Frame-PortraitMetal-CornerTopLeft',label='2: Ecke links'},
  {key='TopRightCorner',atlas='UI-Frame-Metal-CornerTopRight',label='3: Ecke rechts'},
}
local function pack(...) return {n=select('#',...),...} end
local function read(object,method,...)
  if not object then return nil,'n/a' end
  local ok,fn=pcall(function() return object[method] end)
  if not ok or type(fn)~='function' then return nil,'n/a' end
  local result=pack(pcall(fn,object,...))
  if not result[1] then return nil,'ERR' end
  local out={n=result.n-1};for i=2,result.n do out[i-1]=result[i] end;return out
end
local function call(object,method,...)
  local values,reason=read(object,method,...)
  return values~=nil and values[1]~=false,reason
end
local function field(object,key)
  if not object then return nil end
  local ok,value=pcall(function() return object[key] end);return ok and value or nil
end
local function value(object,method)
  local values,reason=read(object,method);return values and values[1],reason
end
local function str(v)
  if v==nil then return '-' end
  if type(v)=='number' then return string.format('%.17g',v) end
  return tostring(v):gsub('[\r\n]',' '):gsub('|','||')
end
local function name(object)
  if not object then return '-' end
  if object==host then return 'Main' end
  local chrome=field(host,'windowChrome');local nine=field(chrome,'NineSlice')
  if object==chrome then return 'Chrome' end
  if object==nine then return 'Chrome.NineSlice' end
  for _,key in ipairs({'TopEdge','TopLeftCorner','TopRightCorner','LeftEdge','RightEdge'}) do
    if object==field(nine,key) then return 'Chrome.NineSlice.'..key end
  end
  local n=value(object,'GetName');return n and str(n) or '(unnamed)'
end
local function atlasInfo(atlas)
  local reason='n/a'
  for _,fn in pairs({C_Texture and C_Texture.GetAtlasInfo,GetAtlasInfo}) do
    if type(fn)=='function' then
      local ok,info=pcall(fn,atlas)
      if ok and type(info)=='table' then return info end
      reason=ok and 'nil' or 'ERR'
    end
  end
  return nil,reason
end
local function source(key)
  local chrome=field(host,'windowChrome')
  return field(field(chrome,'NineSlice'),key) or field(chrome,key) or (key=='LeftEdge' and field(chrome,'LeftBorder')) or (key=='RightEdge' and field(chrome,'RightBorder')) or nil
end
local function collect()
  local spec=specs[selected]
  local region=source(spec.key)
  local actual=value(region,'GetAtlas')
  local atlas=type(actual)=='string' and actual~='' and actual or spec.atlas
  local info,infoReason=atlasInfo(atlas)
  local file=value(region,'GetTextureFileID') or value(region,'GetTexture')
  local uv,uvReason=read(region,'GetTexCoord')
  return {spec=spec,region=region,actual=actual,atlas=atlas,info=info,infoReason=infoReason,file=file,uv=uv,uvReason=uvReason}
end
local function printLine(line)
  while #line>210 do chat(line:sub(1,210));line='[HA +] '..line:sub(211) end
  chat(line)
end
local function printRegion(region,label)
  printLine('[HA] '..label..' name='..name(region)..' type='..str(value(region,'GetObjectType'))..' parent='..name(value(region,'GetParent')))
  printLine('[HA] '..label..' size='..str(value(region,'GetWidth'))..'x'..str(value(region,'GetHeight'))..' atlas='..str(value(region,'GetAtlas'))..' texture='..str(value(region,'GetTexture'))..' fileID='..str(value(region,'GetTextureFileID')))
  printLine('[HA] '..label..' level='..str(value(region,'GetFrameLevel'))..' strata='..str(value(region,'GetFrameStrata'))..' scale='..str(value(region,'GetEffectiveScale')))
  local uv,reason=read(region,'GetTexCoord')
  if uv then local parts={};for i=1,uv.n do parts[i]=str(uv[i]) end;printLine('[HA] '..label..' UV('..uv.n..')='..table.concat(parts,','))
  else printLine('[HA] '..label..' UV='..reason) end
  local n=tonumber((value(region,'GetNumPoints'))) or 0
  for i=1,math.min(n,8) do
    local p,why=read(region,'GetPoint',i)
    printLine('[HA] '..label..' anchor'..i..'='..(p and (str(p[1])..' -> '..name(p[2])..'.'..str(p[3])..' x='..str(p[4])..' y='..str(p[5])) or why))
  end
end
local function dump()
  if not current then return end
  printLine('[HA] BEGIN '..selected..'/3 '..current.spec.key..' expected='..current.spec.atlas..' actual='..str(current.actual)..' preview='..current.atlas)
  printRegion(current.region,'Selected')
  if current.info then
    local keys={};for key,v in pairs(current.info) do if type(v)~='table' and type(v)~='function' then keys[#keys+1]=key end end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,key in ipairs(keys) do printLine('[HA] atlasInfo.'..str(key)..'='..str(current.info[key])) end
  else printLine('[HA] atlasInfo='..str(current.infoReason)) end
  printLine('[HA] aspectSource='..str(current.aspectSource)..' intrinsic='..str(current.width)..'x'..str(current.height)..' previewMethod='..str(current.method)..' error='..str(current.error))
  printRegion(source('LeftEdge'),'LeftEdge (all anchors, including upper connection)')
  printRegion(source('RightEdge'),'RightEdge (all anchors, including upper connection)')
  printLine('[HA] END '..selected..'/3')
end
local function solid(parent,layer,r,g,b)
  local t=parent:CreateTexture(nil,layer);t:SetTexture('Interface\\Buttons\\WHITE8X8');t:SetVertexColor(r,g,b,1);return t
end
local render
local function makeWindow()
  window=CreateFrame('Frame','SpucknapfBerufeHeaderAtlasWindow',UIParent)
  local screenW=tonumber((value(UIParent,'GetWidth'))) or 1024
  local screenH=tonumber((value(UIParent,'GetHeight'))) or 768
  window:SetSize(math.max(320,math.min(960,screenW-32)),math.max(300,math.min(700,screenH-32)))
  window:SetPoint('CENTER');window:SetFrameStrata('FULLSCREEN_DIALOG');window:SetToplevel(true);window:SetClampedToScreen(true)
  window:SetMovable(true);window:EnableMouse(true);window:RegisterForDrag('LeftButton')
  window:SetScript('OnDragStart',function(self) self:StartMoving() end)
  window:SetScript('OnDragStop',function(self) self:StopMovingOrSizing() end)
  local bg=solid(window,'BACKGROUND',0.035,0.035,0.035);bg:SetAllPoints()
  local title=window:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',16,-15);title:SetText('Temporäre Header-Atlasdiagnose')
  local close=CreateFrame('Button',nil,window,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-3,-3);close:SetScript('OnClick',function() window:Hide() end)
  if type(UISpecialFrames)=='table' then UISpecialFrames[#UISpecialFrames+1]='SpucknapfBerufeHeaderAtlasWindow' end
  window.tabs={}
  local buttonWidth=(window:GetWidth()-48)/3
  for i,spec in ipairs(specs) do
    local index=i
    local button=CreateFrame('Button',nil,window,'UIPanelButtonTemplate');button:SetSize(buttonWidth,24);button:SetPoint('TOPLEFT',16+(i-1)*(buttonWidth+8),-45);button:SetText(spec.label)
    button:SetScript('OnClick',function() selected=index;render() end);window.tabs[i]=button
  end
  window.meta=window:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');window.meta:SetPoint('TOPLEFT',16,-80);window.meta:SetWidth(window:GetWidth()-32);window.meta:SetHeight(58);window.meta:SetJustifyH('LEFT');window.meta:SetWordWrap(true)
  window.area=CreateFrame('Frame',nil,window);window.area:SetPoint('TOPLEFT',16,-148);window.area:SetPoint('BOTTOMRIGHT',-16,68)
  window.image=window.area:CreateTexture(nil,'ARTWORK');window.image:SetPoint('CENTER')
  window.message=window.area:CreateFontString(nil,'OVERLAY','GameFontHighlight');window.message:SetPoint('CENTER');window.message:SetWidth(window:GetWidth()-64);window.message:SetJustifyH('CENTER');window.message:SetWordWrap(true)
  window.cells={}
  window.footer=window:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');window.footer:SetPoint('BOTTOMLEFT',16,43);window.footer:SetWidth(window:GetWidth()-32);window.footer:SetJustifyH('LEFT')
  local data=CreateFrame('Button',nil,window,'UIPanelButtonTemplate');data:SetSize(145,24);data:SetPoint('BOTTOMLEFT',16,12);data:SetText('Daten im Chat');data:SetScript('OnClick',dump)
  local dismiss=CreateFrame('Button',nil,window,'UIPanelButtonTemplate');dismiss:SetSize(120,24);dismiss:SetPoint('BOTTOMRIGHT',-16,12);dismiss:SetText('Schließen');dismiss:SetScript('OnClick',function() window:Hide() end)
end
local function preview(data)
  local image=window.image
  image:Hide();image:ClearAllPoints();image:SetPoint('CENTER');image:SetSize(0,0)
  call(image,'SetHorizTile',false);call(image,'SetVertTile',false)
  call(image,'SetVertexColor',1,1,1,1);call(image,'SetAlpha',1);call(image,'SetBlendMode','BLEND')
  local atlasOK=call(image,'SetAtlas',data.atlas,true)
  if atlasOK and type(field(image,'GetAtlas'))=='function' then
    local applied=value(image,'GetAtlas');if applied~=data.atlas then atlasOK=false end
  end
  local width=data.info and tonumber(data.info.width)
  local height=data.info and tonumber(data.info.height)
  if width and height and width>0 and height>0 then data.aspectSource='GetAtlasInfo'
  elseif atlasOK then
    width,height=tonumber((value(image,'GetWidth'))),tonumber((value(image,'GetHeight')))
    if width and height and width>0 and height>0 then data.aspectSource='SetAtlas(useAtlasSize=true)' end
  end
  -- Source quads (e.g. 904x95) are stretched by NineSlice: never use them as intrinsic atlas size.
  if not data.aspectSource then data.error='Keine verlässlichen Atlas-Abmessungen: proportionstreue Vorschau nicht möglich.';return end
  data.width,data.height=width,height
  if atlasOK then data.method='SetAtlas'
  elseif data.file and data.uv and (data.uv.n==4 or data.uv.n==8) then
    local textureOK=call(image,'SetTexture',data.file)
    local coordsOK=call(image,'SetTexCoord',unpack(data.uv,1,data.uv.n))
    if textureOK and coordsOK then data.method='Datei + Quell-UV' end
  end
  if not data.method then data.error='Atlas-/Textur-API nicht nutzbar; keine erfundene Ersatzgrafik.';return end
  call(image,'SetHorizTile',false);call(image,'SetVertTile',false)
  local availableW=window.area:GetWidth()-20
  local availableH=window.area:GetHeight()-20
  local factor=math.min(4,availableW/width,availableH/height)
  if factor<=0 then data.error='Diagnosefläche zu klein.';return end
  local w,h=width*factor,height*factor
  image:SetSize(w,h)
  local used=0
  for y=0,math.ceil(h/32)-1 do for x=0,math.ceil(w/32)-1 do
    used=used+1
    local cell=window.cells[used]
    if not cell then cell=solid(window.area,'BACKGROUND',0.2,0.2,0.2);window.cells[used]=cell end
    local shade=(x+y)%2==0 and 0.18 or 0.38
    cell:SetVertexColor(shade,shade,shade,1);cell:ClearAllPoints()
    cell:SetPoint('TOPLEFT',window.area,'CENTER',-w/2+x*32,h/2-y*32)
    cell:SetSize(math.min(32,w-x*32),math.min(32,h-y*32));cell:Show()
  end end
  data.factor=factor
  image:Show()
end
render=function()
  current=collect()
  window.image:Hide();window.message:Hide()
  for _,cell in ipairs(window.cells) do cell:Hide() end
  preview(current)
  if current.error then window.message:SetText(current.error);window.message:Show() end
  local sourceW,sourceH=value(current.region,'GetWidth'),value(current.region,'GetHeight')
  window.meta:SetText(selected..'/3  '..current.atlas..'\nDatei/ID: '..str(current.file)..' | Atlas: '..str(current.width)..' × '..str(current.height)..' | Quellregion: '..str(sourceW)..' × '..str(sourceH)..'\nUV, Anker und Seitenanschlüsse: „Daten im Chat“')
  window.footer:SetText(current.error and 'Fehlende APIs/Daten werden gemeldet; Originalregionen bleiben unverändert.' or ('Ein Atlas-Ausschnitt, ohne Wiederholung. Faktor '..string.format('%.2f',current.factor)..'×. Schachbrett zeigt Transparenz.'))
end
function SpucknapfBerufeHeaderAtlas.Open(ui,say)
  if not ui then say('[HA] Hauptfenster noch nicht erstellt.');return end
  host,chat=ui,say
  if not window then makeWindow() end
  window:Show();window:Raise();render()
end

-- Temporary, command-only, read-only UI inspection. No frame/event/SavedVariables creation.
SpucknapfBerufeHeaderDebug={}
local snapshot
local function packed(...) return {n=select('#',...),...} end
local function read(object,method,...)
  if not object then return nil,'n/a' end
  local ok,fn=pcall(function() return object[method] end)
  if not ok or type(fn)~='function' then return nil,'n/a' end
  local values=packed(pcall(fn,object,...))
  if not values[1] then return nil,'ERR' end
  local result={n=values.n-1};for i=2,values.n do result[i-1]=values[i] end
  return result
end
local function clean(value)
  if value==nil then return '-' end
  if type(value)=='number' then return string.format('%.4f',value):gsub('0+$',''):gsub('%.$','') end
  return tostring(value):gsub('[\r\n]',' '):gsub('|','||')
end
local function first(object,method)
  local values,reason=read(object,method)
  return values and clean(values[1]) or reason
end
local function field(object,key)
  if not object then return nil end
  local ok,value=pcall(function() return object[key] end)
  return ok and value or nil
end
local function capture(ui)
  local lines,nodes,ids={}, {}, {}
  local truncated=false
  local function addLine(line)
    -- Keep each AddMessage small; continued lines retain the report marker.
    while #line>210 do lines[#lines+1]=line:sub(1,210);line='[HD +] '..line:sub(211) end
    lines[#lines+1]=line
  end
  local function register(object,alias)
    if not object then return nil end
    if ids[object] then
      local node=nodes[ids[object]]
      if not node.alias:find(alias,1,true) then node.alias=node.alias..','..alias end
      return ids[object]
    end
    if #nodes>=80 then truncated=true;return nil end
    nodes[#nodes+1]={object=object,alias=alias};ids[object]=#nodes;return #nodes
  end
  local chrome=field(ui,'windowChrome')
  register(ui,'Main');register(chrome,'Chrome')
  for _,key in ipairs({'TitleContainer','NineSlice','TopBorder','TitleBg','TopEdge','TopLeftCorner','TopRightCorner','TopTileStreaks','PortraitContainer','PortraitFrame','portrait','CircleMask','TitleText','CloseButton'}) do
    register(field(chrome,key),'Chrome.'..key)
  end
  register(field(field(chrome,'TitleContainer'),'TitleText'),'Chrome.TitleContainer.TitleText')
  register(field(field(chrome,'NineSlice'),'TopEdge'),'Chrome.NineSlice.TopEdge')
  register(field(ui,'windowTitleHost'),'ActiveTitleHost')
  register(field(ui,'windowTitle'),'ActiveTitle')
  register(field(ui,'versionLabel'),'Version')
  register(field(ui,'windowCloseButton'),'ActiveClose')
  local visited,notes={},{}
  local function walk(object,path,depth)
    if not object or visited[object] or depth>3 then return end
    visited[object]=true
    local regions,regionReason=read(object,'GetRegions')
    if regions then for i=1,regions.n do register(regions[i],path..'.region'..i) end end
    if not regions then notes[#notes+1]=path..'.GetRegions='..regionReason end
    local children,childReason=read(object,'GetChildren')
    if children then
      for i=1,children.n do
        local child=children[i]
        register(child,path..'.child'..i);walk(child,path..'.child'..i,depth+1)
      end
    end
    if not children then notes[#notes+1]=path..'.GetChildren='..childReason end
  end
  -- Only inspect the native frame subtree, not professions/recipes or unrelated UI.
  walk(chrome,'Chrome',0)
  local function ref(object)
    if not object then return '-' end
    if ids[object] then return '#'..ids[object] end
    local name=first(object,'GetName')
    return name~='-' and name~='n/a' and name or '(unnamed external)'
  end
  addLine('[HD] addon=0.9.10 diag=1 base=native-title mode='..clean(field(ui,'windowChromeMode'))..' nodes='..#nodes..' truncated='..tostring(truncated))
  local build={}
  if type(GetBuildInfo)=='function' then local ok,a,b,c,d=pcall(GetBuildInfo);if ok then build={a,b,c,d} end end
  addLine('[HD] version='..clean(build[1])..' build='..clean(build[2])..' interface='..clean(build[4]))
  addLine('[HD] - = nil; n/a = API missing; ERR = read failed; texture may be path OR fileID; UV order is returned unchanged')
  for _,note in ipairs(notes) do addLine('[HD] discovery '..note) end
  for id,node in ipairs(nodes) do
    local object=node.object
    local tag='[HD #'..id..'] '
    local parent=read(object,'GetParent')
    addLine(tag..node.alias..' type='..first(object,'GetObjectType')..' name='..first(object,'GetName')..' parent='..ref(parent and parent[1]))
    addLine(tag..'size='..first(object,'GetWidth')..'x'..first(object,'GetHeight')..' level='..first(object,'GetFrameLevel')..' strata='..first(object,'GetFrameStrata')..' scale='..first(object,'GetEffectiveScale')..' shown='..first(object,'IsShown')..' visible='..first(object,'IsVisible')..' clips='..first(object,'GetClipsChildren'))
    local rect=read(object,'GetRect')
    if rect then addLine(tag..'rect left,bottom,w,h='..clean(rect[1])..','..clean(rect[2])..','..clean(rect[3])..','..clean(rect[4])) end
    local texture,textureReason=read(object,'GetTexture')
    local atlas,atlasReason=read(object,'GetAtlas')
    if texture or atlas or textureReason=='ERR' or atlasReason=='ERR' then
      addLine(tag..'texture='..(texture and clean(texture[1]) or textureReason)..' atlas='..(atlas and clean(atlas[1]) or atlasReason)..' fileID='..first(object,'GetTextureFileID'))
      local uv,uvReason=read(object,'GetTexCoord')
      if uv then local values={};for i=1,uv.n do values[#values+1]=clean(uv[i]) end;addLine(tag..'UV('..uv.n..')='..table.concat(values,',')) else addLine(tag..'UV='..uvReason) end
      local layer=read(object,'GetDrawLayer')
      if layer then addLine(tag..'drawLayer='..clean(layer[1])..' subLevel='..clean(layer[2])) end
    end
    local text=read(object,'GetText')
    if text then
      addLine(tag..'text=['..clean(text[1])..']')
      local font=read(object,'GetFont')
      if font then addLine(tag..'font='..clean(font[1])..' size='..clean(font[2])..' flags='..clean(font[3])) end
    end
    local count=read(object,'GetNumPoints')
    local total=count and tonumber(count[1]) or 0
    for i=1,math.min(total,4) do
      local point,reason=read(object,'GetPoint',i)
      addLine(tag..'anchor'..i..'='..(point and (clean(point[1])..' -> '..ref(point[2])..'.'..clean(point[3])..' x='..clean(point[4])..' y='..clean(point[5])) or reason))
    end
    if total>4 then addLine(tag..'anchors truncated: '..total) end
  end
  return lines
end
function SpucknapfBerufeHeaderDebug.Dump(ui,say,arg)
  if not ui then say('[HD] Hauptfenster noch nicht erstellt.');return end
  arg=(arg or ''):match('^%s*(.-)%s*$')
  local page=arg=='' and 1 or tonumber(arg)
  if not page or page<1 or page%1~=0 then say('[HD] Nutzung: /spucknapf headerdebug [Seitennummer]');return end
  if arg=='' or page==1 or not snapshot then snapshot=capture(ui) end
  local pages=math.max(1,math.ceil(#snapshot/25))
  if page>pages then say('[HD] Es gibt '..pages..' Seiten.');return end
  say('[HD] BEGIN Seite '..page..'/'..pages..' – reine Momentaufnahme')
  for i=(page-1)*25+1,math.min(page*25,#snapshot) do say(snapshot[i]) end
  say('[HD] END Seite '..page..'/'..pages..(page<pages and (' | weiter: /spucknapf headerdebug '..(page+1)) or ' | Bericht vollständig'))
end

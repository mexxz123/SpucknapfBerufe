-- Independent visibility policy. Never modifies character/profession/recipe records.
SpucknapfBerufeAdmin={}
function SpucknapfBerufeAdmin.New(env)
  local A={status='Gildenliste wird geprüft'}
  local store,context,leader,localLeader,db
  local clock=env.clock
  local nextPoll,lastResponse,sendAt,lastRosterQuery=0,-100,0,-100
  local pendingSend,activeSend,receive=nil,nil,nil
  local serial,lastAuthorityCheck=0,-100
  local window,button,expanded,offset=nil,nil,{},0
  local onAdminPage=false
  local refreshUI
  local function canonical(name) return type(name)=='string' and name:lower() or '' end
  local function base(name) return canonical(name):match('^[^-]+') end
  local function profession(name)
    if name=='Alchimie' then return 'Alchemie' end
    if name=='Ingenieurkunst' then return 'Ingenieurskunst' end
    return tostring(name or '')
  end
  local function authority()
    if not env.guild() or type(GetNumGuildMembers)~='function' or type(GetGuildRosterInfo)~='function' then return nil end
    local ok,n=pcall(GetNumGuildMembers)
    if not ok or type(n)~='number' then return nil end
    local found,duplicates=nil,{}
    for i=1,n do
      local good,name,_,rank,_,_,_,_,_,_,_,_,_,_,_,_,_,guid=pcall(GetGuildRosterInfo,i)
      if good and type(name)=='string' then
        duplicates[base(name)]=(duplicates[base(name)] or 0)+1
        if rank==0 then
          if found then return nil end -- incomplete/ambiguous roster: fail closed
          found={name=name,guid=type(guid)=='string' and guid~='' and guid or nil}
        end
      end
    end
    if found then found.unique=duplicates[base(found.name)]==1 end
    return found
  end
  local function sameName(a,b)
    if canonical(a)==canonical(b) then return true end
    return leader and leader.unique and base(a)==base(b) and (not a:find('-',1,true) or not b:find('-',1,true))
  end
  local function state()
    return store and context and store[context] or nil
  end
  local function notify()
    if env.changed then env.changed() end
    if refreshUI then refreshUI() end
  end
  function A.RefreshAuthority()
    local guild=env.guild()
    if guild~=context then
      context=guild;receive=nil;activeSend=nil;pendingSend=nil;nextPoll=0;offset=0
    end
    local previous=leader and (leader.guid or leader.name)
    leader=authority()
    if not leader and clock()-lastRosterQuery>=30 then
      lastRosterQuery=clock()
      local query=(C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
      if type(query)=='function' then pcall(query) end
    end
    local guid,name=env.identity()
    localLeader=leader and ((leader.guid and guid and leader.guid==guid) or (not leader.guid and name and sameName(name,leader.name))) or false
    -- A conflicting known GUID is never replaced with a name-only guess.
    if type(IsGuildLeader)=='function' then
      local ok,value=pcall(IsGuildLeader)
      if ok and value==false then localLeader=false end
    end
    if previous~=(leader and (leader.guid or leader.name)) then receive=nil;nextPoll=0;activeSend=nil end
    A.status=not leader and 'Gildenmeister nicht eindeutig erkannt' or localLeader and 'Gildenmeister – Änderungen gelten gildenweit' or 'Verwaltung nur durch den Gildenmeister'
    if button then if localLeader and not onAdminPage then button:Show() else button:Hide() end end
    if window and not localLeader then window:Hide() end
  end
  function A.IsAdmin() return localLeader==true end
  local function keyFor(char)
    local record=db and db.characters and db.characters[char]
    local guid=record and record.guid
    if not guid and type(char)=='string' and char:sub(1,1)=='@' then guid=char:sub(2) end
    return type(guid)=='string' and guid~='' and ('g:'..guid) or ('n:'..canonical(char))
  end
  function A.Visible(char,prof)
    local s=state()
    if not s then return true end
    local names=s.hidden or {}
    local rule=names[keyFor(char)] or names['n:'..canonical(char)]
    return not (rule and (rule.all or (rule.professions and rule.professions[profession(prof)])))
  end
  local function checksum(body)
    local sum=1
    for i=1,#body do sum=(sum*33+body:byte(i))%2147483647 end
    return tostring(sum)
  end
  local function serialize(s)
    local lines={env.encode(context)..'|'..env.encode(s.author)..'|'..s.revision}
    local keys={};for key in pairs(s.hidden) do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys) do
      local rule=s.hidden[key]
      if rule.all then lines[#lines+1]=env.encode(key)..'|*' end
      local professions={};for p,v in pairs(rule.professions or {}) do if v then professions[#professions+1]=p end end;table.sort(professions)
      for _,p in ipairs(professions) do lines[#lines+1]=env.encode(key)..'|'..env.encode(p) end
    end
    return table.concat(lines,'~')
  end
  local function parse(body)
    local head,guild,author,revision=body:match('^([^~]+)')
    if not head then return nil end
    guild,author,revision=head:match('^([^|]+)|([^|]+)|(%d+)$')
    revision=tonumber(revision)
    if not guild or env.decode(guild)~=context or not revision or revision<1 or revision>1e15 then return nil end
    author=env.decode(author)
    if not leader or author~=(leader.guid or ('name:'..canonical(leader.name))) then return nil end
    local hidden={}
    for line in body:sub(#head+2):gmatch('[^~]+') do
      local k,p=line:match('^([^|]+)|([^|]+)$')
      if not k then return nil end
      k,p=env.decode(k),env.decode(p)
      if #k>160 or #p>100 or (k:sub(1,2)~='g:' and k:sub(1,2)~='n:') then return nil end
      hidden[k]=hidden[k] or {professions={}}
      if p=='*' then hidden[k].all=true else hidden[k].professions[profession(p)]=true end
    end
    return {author=author,revision=revision,hidden=hidden,digest=checksum(body)}
  end
  local function scheduleSend()
    if localLeader and state() then pendingSend=true end
  end
  function A.SetHidden(char,prof,hidden)
    A.RefreshAuthority()
    if not localLeader or not store or not context or not db.characters[char] then return false end
    local previous=state()
    local nextState={hidden={},author=leader.guid or ('name:'..canonical(leader.name)),revision=math.max((previous and previous.revision or 0)+1,env.stamp())}
    for k,r in pairs(previous and previous.hidden or {}) do
      local c={all=r.all,professions={}};for p,v in pairs(r.professions or {}) do c.professions[p]=v end;nextState.hidden[k]=c
    end
    local key=keyFor(char)
    local legacy=nextState.hidden['n:'..canonical(char)]
    local rule=nextState.hidden[key] or legacy or {professions={}}
    nextState.hidden[key]=rule
    -- Keep a name alias too, for existing books that have not acquired a GUID yet.
    local alias='n:'..canonical(char)
    if key~=alias then nextState.hidden[alias]=rule end
    if prof then rule.professions[profession(prof)]=hidden and true or nil else rule.all=hidden and true or nil end
    if not rule.all and not next(rule.professions) then nextState.hidden[key]=nil;nextState.hidden[alias]=nil end
    local body=serialize(nextState)
    if #body>120000 then A.status='Zu viele Verwaltungsdaten';return false end
    nextState.digest=checksum(body);store[context]=nextState
    scheduleSend();notify();return true
  end
  function A.Receive(payload,sender,channel)
    if channel~='GUILD' or not store or not context then return end
    local requestedRevision,requestedDigest=payload:match('^AV2|Q|(%d+)|(%d+)$')
    if requestedRevision then
      local s=state()
      if localLeader and s and not activeSend and not pendingSend and (tonumber(requestedRevision)~=s.revision or requestedDigest~=s.digest) and clock()-lastResponse>=10 then lastResponse=clock();scheduleSend() end
      return
    end
    local token,index,total,digest,chunk=payload:match('^AV2|D|([%w%-]+)|(%d+)|(%d+)|(%d+)|(.*)$')
    if not token then return end
    if not receive or receive.token~=token then A.RefreshAuthority() end
    if not leader or not sameName(sender,leader.name) or localLeader then return end
    index,total=tonumber(index),tonumber(total)
    if not index or not total or index<1 or index>total or total<1 or total>800 or #chunk>160 then return end
    if not receive or receive.token~=token then receive={token=token,total=total,digest=digest,parts={},count=0,at=clock()} end
    local box=receive
    if box.total~=total or box.digest~=digest then receive=nil;return end
    if box.parts[index] and box.parts[index]~=chunk then receive=nil;return end
    if not box.parts[index] then box.count=box.count+1 end;box.parts[index]=chunk
    if box.count~=total then return end
    receive=nil
    local body=table.concat(box.parts)
    if checksum(body)~=digest then return end
    A.RefreshAuthority()
    if not leader or not sameName(sender,leader.name) then return end
    local s=parse(body);if not s then return end
    local current=state()
    if current and current.author==s.author and s.revision<=current.revision then
      if s.revision==current.revision and s.digest~=current.digest then A.lastError='Versionskonflikt – Gildenmeister muss erneut speichern';A.status=A.lastError end
      return
    end
    store[context]=s;A.status='Verwaltung empfangen, Version '..s.revision;notify()
  end
  function A.Init(database)
    db=database;db.guildVisibility=db.guildVisibility or {};store=db.guildVisibility
    A.RefreshAuthority()
  end
  function A.Request() nextPoll=0 end
  function A.Describe()
    local s=state()
    return 'Verwaltung: GM='..(leader and leader.name or 'unbekannt')..', Version='..(s and s.revision or 'keine')..', Autor='..(s and s.author or '-')..'. '..(A.lastError or A.status)
  end
  function A.Tick()
    if not store then return end
    local now=clock()
    if now-lastAuthorityCheck>=5 then lastAuthorityCheck=now;A.RefreshAuthority() end
    if receive and now-receive.at>90 then receive=nil end
    if context and leader and not localLeader and now>=nextPoll then
      local s=state()
      env.send('AV2|Q|'..(s and s.revision or 0)..'|'..(s and s.digest or '0'));nextPoll=now+180
    end
    if localLeader and state() and state().author~=(leader.guid or ('name:'..canonical(leader.name))) then
      -- The successor retains the locally verified policy, with a new author/version.
      local s=state();s.author=leader.guid or ('name:'..canonical(leader.name));s.revision=math.max(s.revision+1,env.stamp())
      s.digest=checksum(serialize(s));pendingSend=true;notify()
    end
    if pendingSend and not activeSend and localLeader and now>=sendAt then
      pendingSend=nil;serial=serial+1
      local body=serialize(state())
      activeSend={body=body,digest=checksum(body),index=1,total=math.ceil(#body/160),token=tostring(env.stamp())..'-'..serial}
    end
    if activeSend and now>=sendAt then
      if not localLeader then activeSend=nil;return end
      local s=activeSend
      env.send('AV2|D|'..s.token..'|'..s.index..'|'..s.total..'|'..s.digest..'|'..s.body:sub((s.index-1)*160+1,s.index*160))
      s.index=s.index+1;sendAt=now+0.2
      if s.index>s.total then activeSend=nil;sendAt=now+2 end
    end
  end
  local host,appearance,normalShown
  local function returnToProfessions()
    if not onAdminPage then return end
    onAdminPage=false
    if window then window:Hide() end
    for region,shown in pairs(normalShown or {}) do if shown then region:Show() else region:Hide() end end
    normalShown=nil
    if button and localLeader then button:Show() end
  end
  function A.Attach(parent,presentation)
    if button then return end
    host,appearance=parent,presentation
    button=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate')
    button:SetSize(100,22);button:SetPoint('TOPRIGHT',parent,'TOPRIGHT',-20,-34);button:SetText('Verwaltung');button:Hide()
    button:SetScript('OnClick',function()
      A.RefreshAuthority();if not localLeader then return end
      if not window then A.CreatePage() end
      if onAdminPage then return end
      normalShown={}
      for _,region in ipairs(appearance.content) do normalShown[region]=region:IsShown();region:Hide() end
      if GameTooltip then GameTooltip:Hide() end
      onAdminPage=true;button:Hide();window:Show();window.back:Show();refreshUI()
    end)
    A.RefreshAuthority()
  end
  function A.CreatePage()
    A.RefreshAuthority();if not localLeader or not host then return end
    window=CreateFrame('Frame',nil,host,'BackdropTemplate')
    window:SetPoint('TOPLEFT',host,'TOPLEFT',18,-61)
    window:SetPoint('BOTTOMRIGHT',host,'BOTTOMRIGHT',-18,18)
    appearance.panel(window)
    local title=appearance.text(window,9,-7,300,21,true);title:SetText('Gildenweite Sichtbarkeit')
    local hint=appearance.text(window,12,-38,300,24,false)
    hint:SetText('Häkchen = sichtbar. Charakter-Haken übersteuert die Berufe. Ausklappen: + / −.')
    hint:SetWordWrap(true);window.hint=hint
    window.back=CreateFrame('Button',nil,host,'UIPanelButtonTemplate')
    window.back:SetSize(150,22);window.back:SetPoint('TOPRIGHT',host,'TOPRIGHT',-20,-34);window.back:SetText('Zurück zu Berufe');window.back:Hide()
    window.back:SetScript('OnClick',returnToProfessions)
    window.rows={}
    for i=1,40 do
      local row=CreateFrame('Frame',nil,window);row:SetHeight(26);row:SetPoint('TOPLEFT',12,-72-(i-1)*26)
      row.expand=CreateFrame('Button',nil,row,'UIPanelButtonTemplate');row.expand:SetSize(24,24);row.expand:SetPoint('LEFT')
      row.check=CreateFrame('CheckButton',nil,row,'UICheckButtonTemplate');row.check:SetSize(24,24);row.check:SetPoint('LEFT',28,0)
      row.label=appearance.text(row,60,0,300,24,false);appearance.font(row.label,14)
      window.rows[i]=row
    end
    window.status=appearance.text(window,12,0,300,26,false)
    window.status:ClearAllPoints();window.status:SetPoint('BOTTOMLEFT',window,'BOTTOMLEFT',12,7)
    window.scroll=CreateFrame('Slider',nil,window,'UIPanelScrollBarTemplate')
    -- Replace the template's parent:SetVerticalScroll callback before any value/range changes.
    -- This page renders rows by index; its parent intentionally is not a ScrollFrame.
    window.scroll:SetScript('OnValueChanged',function(_,value)
      if window.settingScroll then return end
      offset=math.max(0,math.floor(value+0.5));refreshUI()
    end)
    window.scroll.scrollStep=1
    window.scroll:SetPoint('TOPRIGHT',window,'TOPRIGHT',-16,-87)
    window.scroll:SetPoint('BOTTOMRIGHT',window,'BOTTOMRIGHT',-16,48)
    window.settingScroll=true
    window.scroll:SetMinMaxValues(0,0);window.scroll:SetValueStep(1);window.scroll:SetValue(0)
    window.settingScroll=false
    window:EnableMouseWheel(true)
    window:SetScript('OnMouseWheel',function(_,delta) offset=math.max(0,offset-delta*3);refreshUI() end)
    window:SetScript('OnSizeChanged',function() refreshUI() end)
    window:SetScript('OnHide',function() window.back:Hide();returnToProfessions() end)
    window:Hide()
  end
  refreshUI=function()
    if not window or not window:IsShown() or not db then return end
    if not localLeader then window:Hide();return end
    local chars={};for char in pairs(db.characters or {}) do chars[#chars+1]=char end;table.sort(chars)
    local items={}
    for _,char in ipairs(chars) do
      items[#items+1]={char=char}
      if expanded[char] then
        local seen={};local professions={}
        for _,p in ipairs(db.characters[char].professions or {}) do if not seen[profession(p.name)] then seen[profession(p.name)]=true;professions[#professions+1]=p.name end end
        table.sort(professions);for _,p in ipairs(professions) do items[#items+1]={char=char,prof=p} end
      end
    end
    local visible=math.max(1,math.min(40,math.floor((window:GetHeight()-110)/26)))
    local maxOffset=math.max(0,#items-visible)
    offset=math.min(offset,maxOffset)
    window.settingScroll=true
    window.scroll:SetMinMaxValues(0,maxOffset);window.scroll:SetValue(offset)
    window.settingScroll=false
    if maxOffset>0 then window.scroll:Show() else window.scroll:Hide() end
    window.hint:SetWidth(math.max(100,window:GetWidth()-40))
    window.status:SetWidth(math.max(100,window:GetWidth()-40))
    for i,row in ipairs(window.rows) do
      local item=items[offset+i]
      if item and i<=visible then
        row:SetWidth(math.max(100,window:GetWidth()-54));row.label:SetWidth(math.max(40,window:GetWidth()-118))
        row:Show();local visible=A.Visible(item.char,item.prof)
        row.label:SetText((item.prof and '    '..item.prof or item.char)..(visible and '' or '  (ausgeblendet)'))
        row.label:SetTextColor(visible and 0.95 or 0.6,visible and 0.85 or 0.55,visible and 0.65 or 0.5)
        local s=state();local rule=s and (s.hidden[keyFor(item.char)] or s.hidden['n:'..canonical(item.char)])
        local explicitlyHidden=rule and (item.prof and rule.professions[profession(item.prof)] or (not item.prof and rule.all)) or false
        row.check:SetChecked(not explicitlyHidden)
        row.check:SetScript('OnClick',function() A.SetHidden(item.char,item.prof,not explicitlyHidden) end)
        if item.prof then row.expand:Hide() else row.expand:Show();row.expand:SetText(expanded[item.char] and '−' or '+');row.expand:SetScript('OnClick',function() expanded[item.char]=not expanded[item.char];refreshUI() end) end
      else row:Hide() end
    end
    local s=state();window.status:SetText(A.status..'\nVersion: '..(s and s.revision or 'noch keine Einstellungen')..' – '..#chars..' Charaktere')
  end
  A.RefreshUI=function() if refreshUI then refreshUI() end end
  return A
end

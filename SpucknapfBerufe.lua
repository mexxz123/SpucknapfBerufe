local addonName = ...
local PREFIX = 'SPB03' -- Keep wire compatibility with v0.6.4
local excluded = {['Angeln']=true, ['Erste Hilfe']=true, ['Fishing']=true, ['First Aid']=true, ['Kürschnerei']=true, ['Kraeuterkunde']=true, ['Kräuterkunde']=true, ['Bergbau']=true, ['Skinning']=true, ['Herbalism']=true, ['Mining']=true}
local frame = CreateFrame('Frame')
local db, queue, pending, elapsed = nil, {}, {}, 0
local lastScan, lastSend = 0, 0
local outgoing=nil
local numberedPending={}
local recentCompleted={}
local syncState="Bereit"
local syncProgress=0
local syncTotal=0
local syncConfirmed=false
local retryAt=0
local transferCounter=0
local lastTransferNotice=0
local SEND_INTERVAL=0.10 -- cautiously faster; keep throttling guild addon messages
local ACK_WAIT=40 -- allow packet repair and receiver processing
local lastRecipeSignature=nil
local activeProfession=nil
local ui, renderUI
local selectedScanProfession=nil
local itemRefreshElapsed=0
local unresolvedMaterials=false
local itemLoadRequested={}
local function materialInfo(itemID)
  itemID=tonumber(itemID)
  if not itemID then return nil,nil end
  local name,icon
  -- The original v0.6.7 icon lookup worked on the author's client.
  -- Prefer it, and only use other APIs if it returns no valid texture.
  if type(GetItemIcon)=='function' then
    local ok,tex=pcall(GetItemIcon,itemID)
    if ok and (type(tex)=='number' or type(tex)=='string') then icon=tex end
  end
  if type(GetItemInfo)=='function' then
    -- GetItemInfo returns texture as its TENTH result (after equipLoc).
    local ok,n,_,_,_,_,_,_,_,_,tex=pcall(GetItemInfo,itemID)
    if ok then
      name=n
      if not icon or icon==0 or icon=='' then icon=tex end
    end
  end
  if not name and C_Item and type(C_Item.GetItemNameByID)=='function' then
    local ok,n=pcall(C_Item.GetItemNameByID,itemID)
    if ok then name=n end
  end
  if (not icon or icon==0 or icon=='') and type(GetItemInfoInstant)=='function' then
    local ok,_,_,_,_,tex=pcall(GetItemInfoInstant,itemID)
    if ok then icon=tex end
  end
  if (not icon or icon==0 or icon=='') and C_Item and type(C_Item.GetItemIconByID)=='function' then
    local ok,tex=pcall(C_Item.GetItemIconByID,itemID)
    if ok then icon=tex end
  end
  if (not name or not icon or icon==0 or icon=='') and not itemLoadRequested[itemID] then
    itemLoadRequested[itemID]=true
    if C_Item and type(C_Item.RequestLoadItemDataByID)=='function' then
      pcall(C_Item.RequestLoadItemDataByID,itemID)
    end
  end
  if type(icon)=='number' and icon<=0 then icon=nil end
  if type(icon)=='string' and icon=='' then icon=nil end
  if type(icon)~='string' and type(icon)~='number' then icon=nil end
  return name,icon
end
local function countPeers() local n=0; if db and db.peers then for _ in pairs(db.peers) do n=n+1 end end; return n end
local function say(s) DEFAULT_CHAT_FRAME:AddMessage('|cff55cc88[SpucknapfBerufe]|r '..tostring(s)) end
local function clock() return (GetTime and GetTime()) or 0 end
local function stamp() return (time and time()) or 0 end
-- Forever can expose a first name through UnitName while guild messages use full names.
local function shortName() return (UnitName and UnitName('player')) or '?' end
local function guildFullName(short)
  if type(GetNumGuildMembers)~='function' or type(GetGuildRosterInfo)~='function' then return nil end
  local matches, found=0,nil
  local count=GetNumGuildMembers() or 0
  for i=1,count do
    local full=GetGuildRosterInfo(i)
    if type(full)=='string' then
      full=full:match('^[^-]+') or full
      if full==short or full:sub(1,#short+1)==short..' ' then
        matches=matches+1; found=full
      end
    end
  end
  if matches==1 then return found end
  return nil
end
local function who()
  if db and type(db.myFullName)=='string' and db.myFullName~='' then return db.myFullName end
  local short=shortName()
  if type(UnitFullName)=='function' then
    local a=UnitFullName('player')
    if type(a)=='string' and a:find(' ',1,true) then return a end
  end
  return guildFullName(short) or short
end
local function migrateLocalAlias(full)
  if not db or not full or full==shortName() then return end
  local short=shortName()
  local old=db.characters[short]
  if old and old.source=='local' then
    local current=db.characters[full]
    if not current or (tonumber(old.updated) or 0)>(tonumber(current.updated) or 0) then
      db.characters[full]=old
    end
    db.characters[short]=nil
  end
end
local function encode(s) return tostring(s or ''):gsub('([^%w%-%._ ])',function(c) return string.format('%%%02X',string.byte(c)) end):gsub(' ','%%20') end
local function decode(s) return (s or ''):gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end) end
local function split(s)
  local a={}; for part in (s..'|'):gmatch('(.-)|') do a[#a+1]=part end; return a
end
local function transmit(s)
  if not IsInGuild or not IsInGuild() then return end
  if C_ChatInfo and type(C_ChatInfo.SendAddonMessage)=='function' then
    C_ChatInfo.SendAddonMessage(PREFIX,s,'GUILD')
  elseif type(SendAddonMessage)=='function' then SendAddonMessage(PREFIX,s,'GUILD') end
end
local function enqueue(s) if #s <= 240 then queue[#queue+1]=s; return true end; return false end
local function profInfo(index)
  if type(GetProfessionInfo)~='function' then return nil end
  local ok,name,icon,skill,maxSkill,_,_,skillLine = pcall(GetProfessionInfo,index)
  if ok and type(name)=='string' and name~='' then
    return {name=name,skill=tonumber(skill) or 0,max=tonumber(maxSkill) or 0,id=tonumber(skillLine) or 0,recipes={},complete=false}
  end
end
local function professions()
  local list={}
  if type(GetProfessions)~='function' then return list end
  local ok,a,b,c,d,e=pcall(GetProfessions)
  if not ok then return list end
  for _,index in ipairs({a,b,c,d,e}) do
    if type(index)=='number' and index>0 then
      local p=profInfo(index)
      if p and not excluded[p.name] then list[#list+1]=p end
    end
  end
  return list
end
local function recipeName(api, id)
  if type(api.GetRecipeLink)=='function' then
    local ok,link=pcall(api.GetRecipeLink,id)
    if ok and type(link)=='string' then
      local name=link:match('%[([^%]]+)%]')
      if name then return name end
    end
  end
  if type(api.GetRecipeSchematic)=='function' then
    local ok,schematic=pcall(api.GetRecipeSchematic,id,false)
    if ok and type(schematic)=='table' and type(schematic.name)=='string' then return schematic.name end
  end
  return 'Rezept '..id
end
-- Check the actual WoW profession tab when the client exposes its name.
-- Never trust a manually selected profession to identify a different open tab.
local function activeTradeSkillName(api)
  if type(GetTradeSkillLine)=='function' then
    local ok,name=pcall(GetTradeSkillLine)
    if ok and type(name)=='string' and name~='' and name~='UNKNOWN' then return name end
  end
  if type(api.GetTradeSkillLine)=='function' then
    local ok,info=pcall(api.GetTradeSkillLine)
    if ok then
      if type(info)=='string' and info~='' then return info end
      if type(info)=='table' then return info.name or info.professionName end
    end
  end
  return nil
end
local function normalizeProfessionName(name)
  return tostring(name or ''):lower():gsub('ä','ae'):gsub('ö','oe'):gsub('ü','ue'):gsub('ß','ss'):gsub('%s+','')
end
local function scanRecipes(list, requested)
  local api=C_TradeSkillUI
  if type(api)~='table' or type(api.GetAllRecipeIDs)~='function' then
    return 'GetAllRecipeIDs nicht verfuegbar'
  end
  local ok,ids=pcall(api.GetAllRecipeIDs)
  if not ok or type(ids)~='table' then return 'Rezeptliste nicht lesbar (Berufsfenster oeffnen)' end
  local target
  if requested and requested~='' then
    for _,p in ipairs(list) do
      if p.name:lower()==requested:lower() then target=p; break end
    end
    if not target then return 'Unbekannter Beruf: '..requested end
  else
    -- Forever's combined trade-skill UI may not expose an active profession ID.
    local selectedID
    if type(api.GetProfessionInfo)=='function' then
      local good,info=pcall(api.GetProfessionInfo)
      if good and type(info)=='table' then selectedID=tonumber(info.professionID or info.skillLineID) end
    end
    if selectedID then
      for _,p in ipairs(list) do if p.id==selectedID then target=p; break end end
    end
  end
  if not target then return 'Aktiver Beruf nicht erkannt. Bitte links einen Beruf waehlen, originales WoW-Berufsfenster oeffnen und auf Scannen klicken.' end
  local activeName=activeTradeSkillName(api)
  if activeName and normalizeProfessionName(activeName)~=normalizeProfessionName(target.name) then
    return 'Scan abgebrochen: In WoW ist "'..activeName..'" geoeffnet, im Addon aber "'..target.name..'" gewaehlt. Bitte das passende originale WoW-Berufsfenster oeffnen.'
  end
  local learnedChecker
  if type(api.GetRecipeInfo)=='function' then learnedChecker='info'
  elseif type(api.IsRecipeLearned)=='function' then learnedChecker='learned' end
  if not learnedChecker then
    return target.name..': '..#ids..' Rezept-IDs sichtbar; Erlernstatus-API fehlt. Keine Rezepte als erlernt gespeichert. /spb probe'
  end
  local recipes={}
  local checked,unknown=0,0
  for _,id in ipairs(ids) do
    if type(id)=='number' then
      local learned, name, category, skillRequired, trivialLevel, craftedItemID
      if learnedChecker=='info' then
        local good,info=pcall(api.GetRecipeInfo,id,0)
        if good and type(info)=='table' then learned=info.learned; name=info.name; category=info.categoryName or info.recipeCategoryName or (type(info.category)=='string' and info.category or nil); if type(info.categoryID)=='number' and type(api.GetCategoryInfo)=='function' then local co,ci=pcall(api.GetCategoryInfo,info.categoryID); if co and type(ci)=='table' and type(ci.name)=='string' and ci.name~='' then category=ci.name end end; skillRequired=tonumber(info.requiredSkill or info.skillRequired or info.skillLevel); trivialLevel=tonumber(info.maxTrivialLevel) end
      else
        local good,result=pcall(api.IsRecipeLearned,id)
        if good then learned=result end
      end
      if learned==true then
        local mats={}
        if type(api.GetRecipeSchematic)=='function' then
          local sg,schematic=pcall(api.GetRecipeSchematic,id,false)
          if sg and type(schematic)=='table' then
            -- Output item, not the recipe/spell ID. Some Forever recipes have no item output.
            local output=schematic.outputItemID or schematic.outputItemId or schematic.craftedItemID or schematic.craftedItemId
            if type(schematic.outputItem)=='table' then output=output or schematic.outputItem.itemID or schematic.outputItem.itemId end
            if type(schematic.outputItems)=='table' and type(schematic.outputItems[1])=='table' then output=output or schematic.outputItems[1].itemID or schematic.outputItems[1].itemId end
            craftedItemID=tonumber(output)
            for _,slot in ipairs(schematic.reagentSlotSchematics or {}) do
              if type(slot)=='table' then
                local opts=slot.reagents or {}
                local reagent=opts[1]
                if type(reagent)=='table' then
                  local item=tonumber(reagent.itemID or reagent.itemId)
                  local qty=tonumber(reagent.quantityRequired or slot.quantityRequired)
                  if item and qty and #mats<20 then mats[#mats+1]={id=item,qty=qty} end
                end
              end
            end
          end
        end
        recipes[#recipes+1]={id=id,name=name or recipeName(api,id),materials=mats,category=type(category)=='string' and category or nil,skill=skillRequired,trivialLevel=trivialLevel,craftedItemID=craftedItemID}
        checked=checked+1
      elseif learned==nil then unknown=unknown+1 end
    end
  end
  if unknown>0 then
    return target.name..': Erlernstatus bei '..unknown..' Rezepten unklar; Daten nicht ueberschrieben. /spb probe'
  end
  target.recipes=recipes; target.complete=true
  return target.name..': '..#recipes..' erlernte Rezepte aus '..#ids..' IDs gespeichert'
end
local function probe()
  local api=C_TradeSkillUI or {}
  local checks={'GetTradeSkillLine','GetProfessionInfo','GetRecipeInfo','IsRecipeLearned','GetRecipeSchematic','GetRecipeLink','GetAllRecipeIDs'}
  for _,key in ipairs(checks) do say(key..'='..type(api[key])) end
  if type(api.GetAllRecipeIDs)~='function' then return end
  local ok,ids=pcall(api.GetAllRecipeIDs)
  if not ok or type(ids)~='table' then say('Rezept-IDs nicht lesbar'); return end
  say('Aktueller Reiter: '..#ids..' Rezept-IDs')
  for i=1,math.min(2,#ids) do
    local id=ids[i]
    local link=''
    if type(api.GetRecipeLink)=='function' then
      local good,value=pcall(api.GetRecipeLink,id)
      if good then link=tostring(value or 'nil') end
    end
    local schema='nicht verfuegbar'
    if type(api.GetRecipeSchematic)=='function' then
      local good,value=pcall(api.GetRecipeSchematic,id,false)
      if good then
        if type(value)=='table' then
          local keys={}; for k in pairs(value) do keys[#keys+1]=tostring(k) end
          table.sort(keys); schema=table.concat(keys,', ')
        else schema=type(value) end
      else schema='API-Fehler' end
    end
    say('ID '..tostring(id)..' Link='..link:sub(1,100))
    say('Schematic-Felder: '..schema:sub(1,180))
  end
end
local function materialsProbe()
  local api=C_TradeSkillUI or {}
  if type(api.GetAllRecipeIDs)~='function' or type(api.GetRecipeSchematic)~='function' then
    say('Material-API nicht verfuegbar.'); return
  end
  local ok,ids=pcall(api.GetAllRecipeIDs)
  if not ok or type(ids)~='table' then say('Bitte Berufsfenster oeffnen.'); return end
  local chosen,chosenName
  for _,id in ipairs(ids) do
    if type(api.GetRecipeInfo)=='function' then
      local good,info=pcall(api.GetRecipeInfo,id,0)
      if good and type(info)=='table' and info.learned==true then chosen=id; chosenName=info.name; break end
    end
  end
  if not chosen then say('Kein erlerntes Rezept im aktuellen Reiter gefunden.'); return end
  say('Materialtest: '..tostring(chosenName or chosen))
  local good,schematic=pcall(api.GetRecipeSchematic,chosen,false)
  if not good or type(schematic)~='table' then say('GetRecipeSchematic lieferte keine Tabelle.'); return end
  local keys={}; for k in pairs(schematic) do keys[#keys+1]=tostring(k) end
  table.sort(keys); say('Schematic-Felder: '..table.concat(keys,', '):sub(1,210))
  local slots=schematic.reagentSlotSchematics or schematic.reagents
  if type(slots)~='table' then say('Keine reagentSlotSchematics/reagents-Tabelle.'); return end
  say('Material-Slots: '..#slots)
  for i=1,math.min(#slots,3) do
    local slot=slots[i]
    if type(slot)=='table' then
      local names={}; for k in pairs(slot) do names[#names+1]=tostring(k) end
      table.sort(names)
      say('Slot '..i..' Felder: '..table.concat(names,', '):sub(1,160))
      local rs=slot.reagents
      if type(rs)=='table' then
        for j=1,math.min(#rs,2) do
          local r=rs[j]
          if type(r)=='table' then
            say('  Material '..j..': itemID='..tostring(r.itemID or r.itemId)..' Menge='..tostring(r.quantityRequired or r.quantity or slot.quantityRequired))
          end
        end
      end
    end
  end
end
local function mergeScan()
  local name=who()
  migrateLocalAlias(name)
  local fresh=professions()
  local old=db.characters[name]
  if old and old.professions then
    for _,p in ipairs(fresh) do
      for _,prior in ipairs(old.professions) do
        if p.name==prior.name and not p.complete and prior.complete then
          p.recipes=prior.recipes or {}; p.complete=true
        end
      end
    end
  end
  db.characters[name]={professions=fresh,updated=stamp(),source='local'}
  return fresh
end
-- Build a complete immutable snapshot; do not interrupt an in-flight transfer.
local function buildSnapshot()
  local messages={}
  local data=db.characters[who()]
  if not data then return nil end
  transferCounter=transferCounter+1
  local seq=tostring(stamp())..'-'..tostring(transferCounter)..'-'..tostring(math.floor(clock()*100)%100000)
  local function add(msg)
    if #msg>240 then return false end
    messages[#messages+1]=msg
    return true
  end
  add('B|'..seq)
  for _,p in ipairs(data.professions or {}) do
    if not excluded[p.name] then
      add('P|'..seq..'|'..encode(p.name)..'|'..p.skill..'|'..p.max..'|'..p.id..'|'..(p.complete and '1' or '0'))
      if p.complete then
        for _,r in ipairs(p.recipes or {}) do
          add('R|'..seq..'|'..encode(p.name)..'|'..tostring(r.id)..'|'..encode(r.name)..'|'..encode(r.category or ''))
          for _,m in ipairs(r.materials or {}) do
            add('M|'..seq..'|'..encode(p.name)..'|'..tostring(r.id)..'|'..tostring(m.id)..'|'..tostring(m.qty))
          end
        end
      end
    end
  end
  -- The E record carries the exact expected message count, including B and E.
  add('E|'..seq..'|'..tostring(#messages+1))
  -- Number every packet. Receiver can detect missing packets without assuming order.
  local numbered={}
  for i,msg in ipairs(messages) do
    numbered[i]='D|'..seq..'|'..i..'|'..#messages..'|'..msg
    if #numbered[i]>240 then return nil end
  end
  return {seq=seq,messages=numbered,attempts=0}
end
local function startTransfer(transfer)
  outgoing=transfer
  outgoing.attempts=outgoing.attempts+1
  queue={}
  for _,msg in ipairs(outgoing.messages) do queue[#queue+1]=msg end
  outgoing.sentAt=nil
  syncState='Senden';syncProgress=0;syncTotal=#outgoing.messages;syncConfirmed=false
  lastSend=clock()
end
local function sendSnapshot()
  if not db then return end
  local nextTransfer=buildSnapshot()
  if not nextTransfer then return end
  if outgoing then
    -- A user may request a newer snapshot; finish and confirm this one first.
    outgoing.next=nextTransfer
  else
    startTransfer(nextTransfer)
  end
end
local function capture(verbose, requested)
  if not db then return end
  local list=mergeScan()
  local result=scanRecipes(list, requested)
  db.characters[who()].updated=stamp()
  if verbose then
    say('Berufe erkannt: '..#list)
    for _,p in ipairs(list) do say(p.name..': '..p.skill..'/'..p.max..' (ID '..p.id..')') end
    say(result)
  end
  -- Scans only update the local book. Sync is explicitly user initiated.
  if renderUI then renderUI() end
end
local function show()
  local count=0
  for char,data in pairs(db.characters) do
    for _,p in ipairs(data.professions or {}) do
      if not excluded[p.name] then say(p.name..' - '..char..': '..p.skill..'/'..p.max..' | Rezepte: '..#(p.recipes or {})..(p.complete and '' or ' (nicht erfasst)'))
      count=count+1 end
    end
  end
  if count==0 then say('Noch keine Berufe bekannt. /spb scan') end
end
-- Kategorisierung als Fallback, wenn Forever keine Rezeptkategorie liefert.
-- Bewusst konservativ: Unbekannte Rezepte bleiben unter Sonstiges sichtbar.
local cookingCategories={
  ['spinnenwurst']='Alltaegliche Mahlzeiten',
  ['milde schildkrötensuppe']='Alltaegliche Mahlzeiten',
  ['scharfe muscheln nach goblin-art']='Alltaegliche Mahlzeiten',
  ['muschelsuppe']='Alltaegliche Mahlzeiten',
  ['gekochte muscheln']='Alltaegliche Mahlzeiten',
  ['kaldorei-spinnenkebab']='Alltaegliche Mahlzeiten',
  ['verkohltes wolfsfleisch']='Alltaegliche Mahlzeiten',
  ['seltsam schmeckendes omelett']='Ausdauernahrung',
  ['klebriger spinnenkuchen']='Ausdauernahrung',
  ['kräutergebackenes ei']='Ausdauernahrung',
  ['mageres wildbret']='Staerkungsnahrung',
  ['großes bärensteak']='Staerkungsnahrung',
  ['trockenes schweinerippchen']='Staerkungsnahrung',
  ['blutwurst']='Staerkungsnahrung',
  ['geröstetes eberfleisch']='Staerkungsnahrung',
}
local equipCategories={INVTYPE_HEAD='Kopf',INVTYPE_SHOULDER='Schultern',INVTYPE_CHEST='Brust',
  INVTYPE_ROBE='Brust',INVTYPE_HAND='Hände',INVTYPE_FEET='Stiefel',
  INVTYPE_LEGS='Beine',INVTYPE_WRIST='Armschienen',INVTYPE_WAIST='Gürtel',
  INVTYPE_CLOAK='Umhänge'}
local function fallbackCategory(profession, recipe)
  local n=tostring(recipe.name or ''):lower()
  local p=tostring(profession or ''):lower()
  local function has(words)
    for _,word in ipairs(words) do if n:find(word,1,true) then return true end end
    return false
  end
  if p=='lederverarbeitung' or p=='schneiderei' or p=='schmiedekunst' then
    -- Ruestungssets sind Verbrauchsgegenstaende, keine Brustrüstung.
    if has({'rüstungsset','ruestungsset','armor kit','rüstungsverstärkung'}) then return 'Rüstungsverstärkungen' end
    -- Wo verfuegbar den echten Ausruestungsplatz des hergestellten Items verwenden.
    if recipe.craftedItemID and type(GetItemInfo)=='function' then
      local _,_,_,_,_,_,_,_,equipLoc=GetItemInfo(recipe.craftedItemID)
      if equipCategories[equipLoc] then return equipCategories[equipLoc] end
    end
    if has({'munitionsbeutel','munitionstasche','ammo pouch'}) then return 'Munitionstaschen' end
    if has({'köcher','koecher','quiver'}) then return 'Köcher' end
    if has({'schulter','schiftung','shoulder'}) then return 'Schultern' end
    if has({'brust','weste','robe','tunika','harnisch','breastplate','chest'}) then return 'Brust' end
    if has({'helm','kopf','kapuze','stirnband','maske','hut','krone'}) then return 'Kopf' end
    if has({'handschuh','stulpen','fäustling','gauntlet'}) then return 'Hände' end
    if has({'stiefel','schuhe','pantoffel','boots'}) then return 'Stiefel' end
    if has({'hose','beinschutz','beinlinge','gamaschen','leggings'}) then return 'Beine' end
    if has({'armschiene','armschutz','handgelenk','bracers'}) then return 'Armschienen' end
    if has({'gürtel','guertel','belt'}) then return 'Gürtel' end
    if has({'umhang','cape','cloak'}) then return 'Umhänge' end
    -- Only raw/crafted materials, not equipment with 'Leder' or 'Stoff' in its name.
    if has({'leder','balg','stoff','barren','schuppe','seide','bolzen','legierung'}) and
       not has({'köcher','koecher','beutel','tasche','rüstung','ruestung','handschuh','stiefel','hose','gürtel','guertel','helm','kapuze','stirnband','schulter','weste','tunika','armschiene','umhang','schuhe','hut'}) then return 'Materialien' end
    if p=='schmiedekunst' and has({'schwert','axt','dolch','streitkolben','hammer','klinge','waffe'}) then return 'Waffen' end
  elseif p=='verzauberkunst' then
    if has({'stiefel','schuhe'}) then return 'Stiefel' end
    if has({'handschuh'}) then return 'Handschuhe' end
    if has({'armschiene'}) then return 'Armschienen' end
    if has({'umhang'}) then return 'Umhang' end
    if has({'brust'}) then return 'Brust' end
    if has({'schild'}) then return 'Schild' end
    if has({'waffe','zweihand'}) then return 'Waffe' end
    if has({'entzauber','staub','essenz','splitter'}) then return 'Materialien' end
  elseif p=='kochkunst' then
    if has({'feuer','lagerfeuer'}) then return 'Hilfsmittel' end
    -- Nur verifizierte Beispielrezepte aus dem originalen Berufsfenster zuordnen.
    -- Unbekannte Buffeffekte nicht aus Namen erraten.
    return cookingCategories[n] or 'Mahlzeiten (noch nicht zugeordnet)'
  elseif p=='alchemie' then
    if has({'elixier'}) then return 'Elixiere' end
    if has({'fläschchen','flask'}) then return 'Fläschchen' end
    if has({'trank','potions'}) then return 'Tränke' end
    if has({'transmut','umwandlung'}) then return 'Transmutationen' end
  elseif p=='ingenieurskunst' then
    if has({'bombe','granate','spreng'}) then return 'Sprengstoffe' end
    if has({'zielfernrohr','gewehr','munition','patrone'}) then return 'Fernkampf' end
    if has({'schraube','rohr','auslöser','pulver'}) then return 'Bauteile' end
  end
  return 'Sonstiges'
end

local function recipeList(search)
  search=(search or ''):lower()
  local n=0
  for char,data in pairs(db.characters) do
    for _,p in ipairs(data.professions or {}) do
      if not excluded[p.name] then for _,r in ipairs(p.recipes or {}) do
        if search=='' or r.name:lower():find(search,1,true) then
          say(p.name..' | '..char..' | '..r.name..' (#'..r.id..')'); n=n+1
          if n>=30 then say('Ausgabe auf 30 Treffer begrenzt.'); return end
        end
      end end
    end
  end
  if n==0 then say('Keine gespeicherten Rezepte gefunden.') end
end
local function apiReport()
  local a=C_TradeSkillUI or {}
  say('GetProfessions='..type(GetProfessions)..', GetProfessionInfo='..type(GetProfessionInfo))
  say('TradeSkill: GetAllRecipeIDs='..type(a.GetAllRecipeIDs)..', GetRecipeInfo='..type(a.GetRecipeInfo)..', GetProfessionInfo='..type(a.GetProfessionInfo))
  say('TradeSkill: GetRecipeSchematic='..type(a.GetRecipeSchematic)..', GetRecipeLink='..type(a.GetRecipeLink))
end
local function onMessage(prefix,payload,channel,sender)
  if prefix~=PREFIX or not db or type(payload)~='string' or not sender then return end
  if channel~='GUILD' then return end
  local name=sender:match('^[^-]+') or sender
  if name==who() then return end
  local a=split(payload); local kind=a[1]
  if kind=='D' then
    local seq,idx,total=a[2],tonumber(a[3]),tonumber(a[4])
    if not seq or not idx or not total or total<1 or total>3000 or idx<1 or idx>total then return end
    local part=payload:match('^D|[^|]*|[^|]*|[^|]*|(.*)$')
    if not part then return end
    if recentCompleted[name..':'..seq] then
      enqueue('OK|'..seq)
      return
    end
    local box=numberedPending[name]
    if not box or box.seq~=seq then
      box={seq=seq,total=total,parts={},received=0,started=clock(),lastRequest=0}
      numberedPending[name]=box
    end
    if box.total~=total then return end
    if not box.parts[idx] then box.parts[idx]=part;box.received=box.received+1 end
    box.started=clock()
    if box.received==total then
      numberedPending[name]=nil
      -- Assemble the complete book before publishing anything to saved data.
      for i=1,total do onMessage(prefix,box.parts[i],channel,sender) end
    end
    return
  elseif kind=='MISS' and outgoing and outgoing.seq==a[2] then
    local requested=tonumber(a[3])
    if requested and requested>=1 and requested<=#outgoing.messages then
      enqueue(outgoing.messages[requested])
      -- A repair packet may be requested after the original send completed.
      -- Keep the ACK timer active; queued repairs will reset it once sent.
    end
    return
  end
  if kind=='OK' and outgoing and outgoing.seq==a[2] then
    say('Empfang bestaetigt von '..name..' ('..#outgoing.messages..' Pakete).')
    -- Multiple guild members may be listening. Keep a short window for confirmations.
    outgoing.acknowledged=true;syncConfirmed=true;syncState='Empfang bestaetigt'
  elseif kind=='REQ' and a[2]==who() then
    sendSnapshot()
  elseif kind=='HELLO' then
    db.peers[name]={lastSeen=stamp()}; enqueue('ACK')
  elseif kind=='ACK' then db.peers[name]={lastSeen=stamp()}
  elseif kind=='B' and a[2] then
    pending[name]={seq=a[2],professions={},started=clock(),count=1,invalid=false}
  elseif kind=='P' and pending[name] and pending[name].seq==a[2] then
    local p=pending[name]; p.count=p.count+1
    if #p.professions>=15 then return end
    local prof={name=decode(a[3]),skill=tonumber(a[4]) or 0,max=tonumber(a[5]) or 0,id=tonumber(a[6]) or 0,complete=a[7]=='1',recipes={}}
    if #prof.name>0 and #prof.name<100 and not excluded[prof.name] then p.professions[#p.professions+1]=prof end
  elseif kind=='R' and pending[name] and pending[name].seq==a[2] then
    local p=pending[name]; p.count=p.count+1
    if p.count>2500 then return end
    local profname=decode(a[3]); local id=tonumber(a[4]); local recname=decode(a[5])
    if id and #recname>0 and #recname<180 then
      for _,prof in ipairs(p.professions) do
        if prof.name==profname and prof.complete then
          prof.recipes[#prof.recipes+1]={id=id,name=recname,category=(a[6] and decode(a[6])~='' and decode(a[6]) or nil),materials={}}; break
        end
      end
    end
  elseif kind=='M' and pending[name] and pending[name].seq==a[2] then
    local p=pending[name]; p.count=p.count+1; local pn=decode(a[3]); local rid=tonumber(a[4]); local item=tonumber(a[5]); local qty=tonumber(a[6])
    if rid and item and qty and qty>0 and qty<100000 then
      for _,prof in ipairs(p.professions) do
        if prof.name==pn then
          for _,rec in ipairs(prof.recipes) do
            if rec.id==rid and #rec.materials<20 then rec.materials[#rec.materials+1]={id=item,qty=qty}; break end
          end
        end
      end
    end
  elseif kind=='E' and pending[name] and pending[name].seq==a[2] then
    local p=pending[name]
    p.count=p.count+1
    local expected=tonumber(a[3])
    if not expected or expected~=p.count then
      say('Unvollstaendige Uebertragung von '..name..': '..p.count..'/'..tostring(expected or '?')..' Pakete. Fordere erneut an.')
      pending[name]=nil
      enqueue('REQ|'..name)
      return
    end
    recentCompleted[name..':'..p.seq]=clock()
    enqueue('OK|'..p.seq)
    -- If our client sends its own messages back with the full name, adopt that identity.
    if name~=who() and name:sub(1,#shortName()+1)==shortName()..' ' and not db.myFullName then
      db.myFullName=name; migrateLocalAlias(name)
    end
    if name~=who() then db.characters[name]={professions=p.professions,updated=stamp(),source='guild'} end
    pending[name]=nil
    say('Berufsdaten von '..name..' empfangen ('..#p.professions..' Berufe).')
    if renderUI then renderUI() end
  end
end

-- Modern guild browser: searchable, scrollable columns and recipe details.
local chosenProfession,chosenCharacter,chosenRecipe=nil,nil,nil
local searchText=''
local recipeSort='name'
local collapsedCategories={}
local offsets={0,0,0}
local ROWS=30 -- pre-create enough rows for a tall resized window
local visibleRows=13
local materialOffset=0
local materialColumns=4
local activeMaterials={}
-- Increase existing Blizzard font sizes without requiring bundled font files.
local function resizeFont(fontString,size)
  if not fontString or not fontString.GetFont then return end
  local path,_,flags=fontString:GetFont()
  if path then fontString:SetFont(path,size,flags) end
end
local function makeText(parent,x,y,w,h,large)
  local t=parent:CreateFontString(nil,'OVERLAY',large and 'GameFontNormal' or 'GameFontHighlightSmall')
  t:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y);t:SetSize(w,h);t:SetJustifyH('LEFT');t:SetJustifyV('MIDDLE');resizeFont(t,large and 15 or 12);return t
end
local function style(f,border)
  if f.SetBackdrop then
    -- Dark warm surfaces; separate decorative textures frame the panels.
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',
      edgeFile=nil,
      tile=false,edgeSize=border and 22 or 0,
      insets={left=border and 6 or 0,right=border and 6 or 0,top=border and 6 or 0,bottom=border and 6 or 0}})
    f:SetBackdropColor(border and 0.065 or 0.095,border and 0.045 or 0.070,border and 0.028 or 0.045,1)
    if border then f:SetBackdropBorderColor(0.51,0.40,0.25,0.95) end
  end
end

-- Continuous inset borders: fixed thickness, no corner images or stretched joins.
local function drawGoldFrame(panel,outer)
  local function ring(inset,size,r,g,b)
    local function strip(pointA,pointB,x,y,w,h)
      local t=panel:CreateTexture(nil,'BORDER')
      t:SetTexture('Interface\\Buttons\\WHITE8X8')
      t:SetVertexColor(r,g,b,1)
      t:SetPoint(pointA,panel,pointA,x,y)
      t:SetPoint(pointB,panel,pointB,w,h)
      return t
    end
    local top=strip('TOPLEFT','TOPRIGHT',inset,-inset,-inset,-inset)
    top:SetHeight(size)
    local bottom=strip('BOTTOMLEFT','BOTTOMRIGHT',inset,inset,-inset,inset)
    bottom:SetHeight(size)
    local left=strip('TOPLEFT','BOTTOMLEFT',inset,-inset-size,inset,inset+size)
    left:SetWidth(size)
    local right=strip('TOPRIGHT','BOTTOMRIGHT',-inset,-inset-size,-inset,inset+size)
    right:SetWidth(size)
  end
  if outer then
    ring(0,2,0.13,0.08,0.035)
    ring(2,1,0.91,0.71,0.35)
    ring(3,2,0.53,0.34,0.12)
    ring(5,1,0.78,0.57,0.25)
    ring(6,1,0.20,0.12,0.05)
  else
    ring(0,1,0.18,0.11,0.045)
    ring(1,1,0.56,0.39,0.17)
    ring(2,1,0.27,0.18,0.08)
  end
end
local function decoratePanel(panel,header)
  drawGoldFrame(panel,false)
  if header then
    local band=panel:CreateTexture(nil,'BACKGROUND')
    band:SetTexture('Interface\\Buttons\\WHITE8X8')
    band:SetVertexColor(0.24,0.17,0.09,0.64)
    band:SetPoint('TOPLEFT',panel,'TOPLEFT',5,-5)
    band:SetPoint('TOPRIGHT',panel,'TOPRIGHT',-5,-5);band:SetHeight(25)
    local rule=panel:CreateTexture(nil,'BORDER')
    rule:SetTexture('Interface\\Buttons\\WHITE8X8')
    rule:SetVertexColor(0.55,0.39,0.18,0.65)
    rule:SetPoint('TOPLEFT',panel,'TOPLEFT',8,-30)
    rule:SetPoint('TOPRIGHT',panel,'TOPRIGHT',-8,-30);rule:SetHeight(1)
  end
end

local function createUI()
  if ui then return end
  ui=CreateFrame('Frame','SpucknapfBerufeWindow',UIParent,'BackdropTemplate')
  ui:SetSize(970,655);ui:SetPoint('CENTER');ui:SetClampedToScreen(true)
  -- WoW client builds expose different resize-bound APIs. Never abort UI creation.
  if ui.SetResizable then ui:SetResizable(true) end
  if ui.SetResizeBounds then
    ui:SetResizeBounds(740,490,1600,1100)
  else
    if ui.SetMinResize then ui:SetMinResize(740,490) end
    if ui.SetMaxResize then ui:SetMaxResize(1600,1100) end
  end
  ui:SetFrameStrata('DIALOG');ui:SetFrameLevel(100);ui:SetToplevel(true)
  ui:SetMovable(true);ui:EnableMouse(true)
  ui:RegisterForDrag('LeftButton');ui:SetScript('OnDragStart',ui.StartMoving);ui:SetScript('OnDragStop',ui.StopMovingOrSizing)
  style(ui,true)
  local titleBand=ui:CreateTexture(nil,'BACKGROUND')
  titleBand:SetTexture('Interface\\Buttons\\WHITE8X8')
  titleBand:SetVertexColor(0.22,0.13,0.055,0.75)
  titleBand:SetPoint('TOPLEFT',ui,'TOPLEFT',10,-10)
  titleBand:SetPoint('TOPRIGHT',ui,'TOPRIGHT',-10,-10);titleBand:SetHeight(31)
  local titleRule=ui:CreateTexture(nil,'BORDER')
  titleRule:SetTexture('Interface\\Buttons\\WHITE8X8')
  titleRule:SetVertexColor(0.67,0.46,0.19,0.8)
  titleRule:SetPoint('TOPLEFT',ui,'TOPLEFT',17,-42)
  titleRule:SetPoint('TOPRIGHT',ui,'TOPRIGHT',-17,-42);titleRule:SetHeight(1)
  drawGoldFrame(ui,true)
  local title=makeText(ui,0,0,100,27,true)
  title:ClearAllPoints()
  title:SetPoint('TOPLEFT',ui,'TOPLEFT',42,-12)
  title:SetPoint('TOPRIGHT',ui,'TOPRIGHT',-42,-12)
  title:SetJustifyH('CENTER')
  resizeFont(title,18)
  title:SetText('|cffffd27aDer salzige Spucknapf|r')
  local close=CreateFrame('Button',nil,ui,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-3,-3)
  -- Compact action bar. Use the same core functions as the slash commands.
  ui.actionButtons={}
  local function actionButton(label,x,width,callback)
    local b=CreateFrame('Button',nil,ui,'UIPanelButtonTemplate')
    b:SetSize(width,32);b:SetPoint('TOPLEFT',x,-61)
    b:SetText(label)
    local font=b:GetFontString()
    if font then font:SetFontObject('GameFontNormal') end
    -- Blizzard's native button textures have softer, tapered edges than our old ornate borders.
    b:SetScript('OnEnter',function(self) if self:GetFontString() then self:GetFontString():SetTextColor(1,0.88,0.62) end end)
    b:SetScript('OnLeave',function(self) if self:GetFontString() then self:GetFontString():SetTextColor(1,0.82,0.42) end end)
    b:SetScript('OnClick',callback)
    ui.actionButtons[#ui.actionButtons+1]=b
    return b
  end
  -- Controls are in the top bar; the search field is moved to the footer.
  actionButton('Scannen',18,120,function()
    if not selectedScanProfession or selectedScanProfession=='' then
      say('Bitte zuerst links einen Herstellungsberuf auswaehlen und dessen Berufsreiter im Spiel oeffnen.')
      return
    end
    capture(true,selectedScanProfession)
    say('Scan: '..selectedScanProfession..' (aktiver Reiter muss uebereinstimmen).')
  end)
  actionButton('Synchronisieren',148,165,function()
    sendSnapshot()
    say('Synchronisierung geplant. Fortschritt unten im Fenster.')
  end)

  ui.status=makeText(ui,330,-65,620,20)
  ui.status:SetText('|cff9ab0a8Bereit|r')

  local search=CreateFrame('EditBox',nil,ui,'InputBoxTemplate');search:SetSize(350,24);search:SetPoint('TOPLEFT',18,-96)
  search:SetAutoFocus(false);search:SetMaxLetters(80);search:SetText('')
  local sl=makeText(ui,386,-99,150,20);sl:SetText('|cffb9a788Suche|r')
  search:SetScript('OnTextChanged',function(self)
    searchText=self:GetText() or '';offsets={0,0,0};if renderUI then renderUI() end
  end)
  local sortButton=CreateFrame('Button',nil,ui,'UIPanelButtonTemplate')
  sortButton:SetSize(220,32);sortButton:SetPoint('TOPRIGHT',ui,'TOPRIGHT',-18,-94)
  local sortLabel=sortButton:GetFontString()
  if sortLabel then
    sortLabel:SetFontObject('GameFontNormal')
    sortLabel:ClearAllPoints()
    sortLabel:SetPoint('CENTER',sortButton,'CENTER',-9,0)
    sortLabel:SetWidth(170)
    sortLabel:SetJustifyH('CENTER')
  end
  -- A texture-based arrow avoids missing glyphs in the WoW client font.
  local sortArrow=sortButton:CreateTexture(nil,'OVERLAY')
  sortArrow:SetSize(13,15)
  sortArrow:SetPoint('RIGHT',sortButton,'RIGHT',-13,0)
  sortArrow:SetTexture('Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up')
  sortArrow:SetTexCoord(0.24,0.76,0.23,0.77)
  local function refreshSortLabel()
    if recipeSort=='skillDesc' then
      sortButton:SetText('Schwierigkeit')
      sortArrow:SetTexture('Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up')
      sortArrow:Show()
    elseif recipeSort=='skillAsc' then
      sortButton:SetText('Schwierigkeit')
      sortArrow:SetTexture('Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up')
      sortArrow:Show()
    else
      sortButton:SetText('Name A-Z')
      sortArrow:Hide()
    end
  end
  sortButton:SetScript('OnClick',function()
    recipeSort=recipeSort=='name' and 'skillDesc' or recipeSort=='skillDesc' and 'skillAsc' or 'name'
    offsets[3]=0;refreshSortLabel();if renderUI then renderUI() end
  end)
  refreshSortLabel()
  -- The sorting control is self-explanatory; avoid overlapping explanatory text.
  ui.skillNote=makeText(ui,540,-99,230,20)
  ui.columns={};ui.headers={};ui.pages={};ui.buttons={}
  local starts={18,263,508};local widths={233,233,444}
  for c=1,3 do
    local x=starts[c];local w=widths[c]
    local panel=CreateFrame('Frame',nil,ui,'BackdropTemplate');panel:SetPoint('TOPLEFT',x,-131);panel:SetSize(w,380);style(panel)
    decoratePanel(panel,true)
    ui.pages[c]=panel
    local heading=makeText(panel,9,-7,w-18,21,true);heading:SetText(({'BERUFE','HANDWERKER','REZEPTBUCH'})[c]);ui.headers[c]=heading
    ui.columns[c]={}
    for i=1,ROWS do
      local row=CreateFrame('Button',nil,panel,'BackdropTemplate');row:SetSize(w-16,25);row:SetPoint('TOPLEFT',8,-34-(i-1)*26);style(row,false)
      local label=makeText(row,7,-2,w-28,20);resizeFont(label,14);row.label=label
      if c==1 then
        local professionIcon=row:CreateTexture(nil,'OVERLAY')
        professionIcon:SetPoint('LEFT',row,'LEFT',5,0)
        professionIcon:SetSize(20,20)
        professionIcon:Hide()
        row.professionIcon=professionIcon
      end
      if c==3 then
        local marker=row:CreateFontString(nil,'OVERLAY','GameFontHighlight')
        marker:SetPoint('LEFT',row,'LEFT',5,0);marker:SetWidth(12)
        marker:SetText('|cff8debc9>|r');marker:Hide();row.selectionMarker=marker
      end
      if c==3 then
        local rank=row:CreateFontString(nil,'OVERLAY','GameFontHighlight')
        rank:SetPoint('RIGHT',row,'RIGHT',-10,0)
        rank:SetWidth(54);rank:SetJustifyH('RIGHT');resizeFont(rank,14)
        row.rank=rank
      end
      row:SetScript('OnEnter',function(self) if self.SetBackdropColor then self:SetBackdropColor(0.22,0.17,0.10,1) end end)
      row:SetScript('OnLeave',function(self) if self.SetBackdropColor then self:SetBackdropColor(0.10,0.085,0.065,0.88) end end)
      ui.columns[c][i]=row
    end
    -- No pagination footer: the final recipe row must remain unobstructed.
    panel:EnableMouseWheel(true)
    panel:SetScript('OnMouseWheel',function(_,delta)
      offsets[c]=math.max(0,(offsets[c] or 0)-(delta>0 and 1 or -1)*3)
      if renderUI then renderUI() end
    end)
  end
  local detailPanel=CreateFrame('Frame',nil,ui,'BackdropTemplate');detailPanel:SetPoint('TOPLEFT',18,-521);detailPanel:SetSize(934,107);style(detailPanel)
  decoratePanel(detailPanel,false)
  ui.detailPanel=detailPanel
  detailPanel:EnableMouseWheel(true)
  detailPanel:SetScript('OnMouseWheel',function(_,delta)
    if #activeMaterials<=materialColumns then return end
    local maxOffset=math.max(0,math.ceil(#activeMaterials/materialColumns)-1)
    materialOffset=math.max(0,math.min(maxOffset,materialOffset-(delta>0 and 1 or -1)))
    if renderUI then renderUI() end
  end)
  local detail=makeText(detailPanel,12,-7,905,92);resizeFont(detail,14);detail:SetJustifyV('TOP');detail:SetJustifyH('LEFT');detail:SetWordWrap(true);detail:SetText('Rezept auswählen, um Materialien zu sehen.');ui.detail=detail
  ui.materialButtons={}
  -- Two readable rows of materials, with native item tooltips.
  for i=1,8 do
    local b=CreateFrame('Button',nil,detailPanel)
    local col=(i-1)%4
    local row=math.floor((i-1)/4)
    b:SetSize(225,45);b:SetPoint('TOPLEFT',detailPanel,'TOPLEFT',12+col*230,-30-row*48)
    local texture=b:CreateTexture(nil,'ARTWORK');texture:SetSize(40,40);texture:SetPoint('LEFT',b,'LEFT',0,0)
    local quantity=b:CreateFontString(nil,'OVERLAY','GameFontHighlight');quantity:SetPoint('LEFT',texture,'RIGHT',5,0);resizeFont(quantity,14)
    quantity:SetWidth(185);quantity:SetJustifyH('LEFT')
    b.texture=texture;b.quantity=quantity;b:Hide()
    b:SetScript('OnEnter',function(self)
      if self.itemID and GameTooltip then
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
        GameTooltip:SetHyperlink('item:'..self.itemID)
        GameTooltip:Show()
      end
    end)
    b:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
    ui.materialButtons[i]=b
  end
  ui.materialScrollHint=makeText(detailPanel,12,-87,300,15)
  resizeFont(ui.materialScrollHint,11)
  ui.materialScrollHint:SetText('')
  -- Use the exact Blizzard icons from the profession list as faint watermarks.
  -- ARTWORK on the parent sits behind child buttons; their backdrops remain readable.
  ui.professionWatermarks={}
  ui.professionWatermarkByColumn={}
  for _,column in ipairs({2,3}) do
    local watermark=ui.pages[column]:CreateTexture(nil,'ARTWORK')
    watermark:SetPoint('CENTER',ui.pages[column],'CENTER',0,-10)
    watermark:SetSize(255,255)
    watermark:SetAlpha(column==2 and 0.10 or 0.07)
    ui.professionWatermarkByColumn[column]=watermark
    ui.professionWatermarks[#ui.professionWatermarks+1]=watermark
  end
  -- Persistent bottom status bar, visible even while idle.
  ui.progressBack=CreateFrame('StatusBar',nil,ui)
  ui.progressBack:SetPoint('BOTTOMLEFT',18,8);ui.progressBack:SetSize(934,7)
  ui.progressBack:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8')
  ui.progressBack:SetStatusBarColor(0.84,0.65,0.29,1)
  ui.progressBack:SetMinMaxValues(0,1);ui.progressBack:SetValue(0)
  local version=(GetAddOnMetadata and GetAddOnMetadata('SpucknapfBerufe','Version')) or '0.7.10'
  ui.versionLabel=ui:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  ui.versionLabel:SetPoint('BOTTOMRIGHT',ui,'BOTTOMRIGHT',-42,18)
  ui.versionLabel:SetJustifyH('RIGHT')
  ui.versionLabel:SetText('|cff938c81v'..tostring(version):gsub('^v','')..'|r')
  -- Visible resize control; normalize the initial CENTER anchor before sizing.
  local grip=CreateFrame('Button',nil,ui,'BackdropTemplate')
  grip:SetSize(28,28);grip:SetPoint('BOTTOMRIGHT',ui,'BOTTOMRIGHT',-5,5)
  grip:SetFrameLevel(ui:GetFrameLevel()+12)
  style(grip,false);drawGoldFrame(grip,false)
  local gripTexture=grip:CreateTexture(nil,'OVERLAY')
  gripTexture:SetPoint('TOPLEFT',grip,'TOPLEFT',3,-3)
  gripTexture:SetPoint('BOTTOMRIGHT',grip,'BOTTOMRIGHT',-3,3)
  gripTexture:SetTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
  gripTexture:SetVertexColor(1,0.82,0.42,1)
  grip:SetNormalTexture(gripTexture)
  local function saveWindowSize()
    if db then db.windowWidth=math.floor(ui:GetWidth()+0.5);db.windowHeight=math.floor(ui:GetHeight()+0.5) end
  end
  local function finishResize()
    if not grip.resizing then return end
    grip.resizing=false
    ui:StopMovingOrSizing()
    saveWindowSize()
  end
  grip:SetScript('OnEnter',function()
    gripTexture:SetVertexColor(1,1,0.72,1)
    if GameTooltip then
      GameTooltip:SetOwner(grip,'ANCHOR_TOPLEFT')
      GameTooltip:SetText('Fenstergroesse aendern')
      GameTooltip:AddLine('Linke Maustaste halten und ziehen.',1,0.82,0.42)
      GameTooltip:Show()
    end
  end)
  grip:SetScript('OnLeave',function()
    gripTexture:SetVertexColor(1,0.82,0.42,1)
    if GameTooltip then GameTooltip:Hide() end
  end)
  grip:SetScript('OnMouseDown',function(self,button)
    if button~='LeftButton' or not ui.StartSizing then return end
    ui:StopMovingOrSizing()
    local left,top=ui:GetLeft(),ui:GetTop()
    if not left or not top then return end
    local width,height=ui:GetWidth(),ui:GetHeight()
    local scale=ui:GetEffectiveScale()/UIParent:GetEffectiveScale()
    ui:ClearAllPoints()
    ui:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',left*scale,top*scale)
    ui:SetSize(width,height)
    self.resizing=true
    if GameTooltip then GameTooltip:Hide() end
    ui:StartSizing('BOTTOMRIGHT')
  end)
  grip:SetScript('OnMouseUp',function(_,button)
    if button=='LeftButton' then finishResize() end
  end)
  grip:SetScript('OnHide',finishResize)
  ui.resizeGrip=grip
  local function layout()
    local width,height=ui:GetWidth(),ui:GetHeight()
    local inner=width-36
    local gap=12
    local left=math.floor((inner-2*gap)*0.255)
    local mid=left
    local right=inner-2*gap-left-mid
    local xs={18,18+left+gap,18+left+gap+mid+gap}
    local ws={left,mid,right}
    local materialHeight=112
    local columnHeight=math.max(200,height-131-materialHeight-26)
    visibleRows=math.max(1,math.min(ROWS,math.floor((columnHeight-39)/26)))
    for c=1,3 do
      local panel=ui.pages[c]
      panel:ClearAllPoints();panel:SetPoint('TOPLEFT',ui,'TOPLEFT',xs[c],-131)
      panel:SetSize(ws[c],columnHeight)
      local watermark=ui.professionWatermarkByColumn[c]
      if watermark then
        local size=math.max(1,math.min(ws[c]-24,columnHeight-64,320))
        watermark:SetSize(size,size)
      end
      ui.headers[c]:SetWidth(ws[c]-18)
      for i,row in ipairs(ui.columns[c]) do
        row:SetWidth(ws[c]-16)
        row.label:SetWidth(ws[c]-(c==1 and 48 or 34))
      end
    end
    ui.detailPanel:ClearAllPoints()
    ui.detailPanel:SetPoint('TOPLEFT',ui,'TOPLEFT',18,-131-columnHeight-10)
    ui.detailPanel:SetSize(inner,materialHeight)
    ui.detail:SetWidth(inner-26)
    ui.progressBack:SetWidth(inner)
    materialColumns=math.max(1,math.floor((inner-20)/225))
    materialColumns=math.min(6,materialColumns)
    local cellWidth=(inner-24)/materialColumns
    for i,b in ipairs(ui.materialButtons) do
      local col=(i-1)%materialColumns
      local row=math.floor((i-1)/materialColumns)
      b:ClearAllPoints()
      b:SetPoint('TOPLEFT',ui.detailPanel,'TOPLEFT',12+col*cellWidth,-30-row*48)
      b:SetSize(cellWidth-3,44)
      b.quantity:SetWidth(math.max(45,cellWidth-49))
    end
    ui.materialScrollHint:ClearAllPoints()
    ui.materialScrollHint:SetPoint('BOTTOMLEFT',ui.detailPanel,'BOTTOMLEFT',12,3)
    ui.materialScrollHint:SetWidth(inner-45)
    if renderUI and db then renderUI() end
  end
  ui.layout=layout
  ui:SetScript('OnSizeChanged',function()
    layout()
    if db then db.windowWidth=math.floor(ui:GetWidth()+0.5);db.windowHeight=math.floor(ui:GetHeight()+0.5) end
  end)
  if db and db.windowWidth and db.windowHeight then
    ui:SetSize(math.max(740,math.min(1600,tonumber(db.windowWidth) or 970)),math.max(490,math.min(1100,tonumber(db.windowHeight) or 655)))
  end
  layout()
  ui.statusElapsed=0
  ui:SetScript('OnUpdate' ,function(self,dt)
    self.statusElapsed=self.statusElapsed+dt
    if self.statusElapsed<0.3 then return end
    self.statusElapsed=0
    if outgoing then
      local sent=math.max(0,#outgoing.messages-#queue)
      self.progressBack:SetMinMaxValues(0,math.max(1,#outgoing.messages))
      self.progressBack:SetValue(sent)
      self.status:SetText('|cffddbb79'..(outgoing.sentAt and 'Warte auf Empfangsbestaetigung' or 'Senden')..': '..sent..'/'..#outgoing.messages..'|r')
    else
      self.progressBack:SetMinMaxValues(0,1);self.progressBack:SetValue(syncConfirmed and 1 or 0)
      self.status:SetText('|cffbfa77a'..syncState..'|r')
    end
  end)
  ui:Hide()
end
local function matches(str)
  return searchText=='' or tostring(str or ''):lower():find(searchText:lower(),1,true)~=nil
end
local function setButtons(column,items,callback,selected)
  local maxOffset=math.max(0,#items-visibleRows)
  offsets[column]=math.min(offsets[column] or 0,maxOffset)
  for i,row in ipairs(ui.columns[column]) do
    local entry=(i<=visibleRows) and items[i+offsets[column]] or nil
    if entry then
      if row.rank then
        local v=entry.recipe and (tonumber(entry.recipe.trivialLevel) or tonumber(entry.recipe.skill))
        row.rank:SetText('') -- Schwierigkeit bleibt nur fuer Sortierung gespeichert
      end
      local isSelected=(not entry.category and entry.key==selected)
      row.isSelected=isSelected
      if row.selectionMarker then
        if isSelected then row.selectionMarker:Show() else row.selectionMarker:Hide() end
      end
      if row.SetBackdropColor then
        if isSelected then row:SetBackdropColor(0.12,0.29,0.24,0.92)
        else row:SetBackdropColor(0.10,0.085,0.065,0.88) end
      end
      if row.SetBackdropBorderColor then
        if isSelected then row:SetBackdropBorderColor(0.38,0.78,0.63,1)
        else row:SetBackdropBorderColor(0.25,0.22,0.17,1) end
      end
      row.label:ClearAllPoints()
      if row.professionIcon then
        local icon=ui.professionIcons and ui.professionIcons[entry.name]
        if icon then row.professionIcon:SetTexture(icon);row.professionIcon:Show()
        else row.professionIcon:Hide() end
      end
      row.label:SetPoint('TOPLEFT',row,'TOPLEFT',row.professionIcon and 32 or (isSelected and 20 or 7),-2)
      row.label:SetText((entry.category and '|cffffd27a' or isSelected and '|cffb8ffe4' or '|cffe8ddc6')..entry.label..'|r')
      row:Show();row:SetScript('OnClick',function() callback(entry) end)
      row.recipeID=entry.recipe and entry.recipe.id or nil
      row.craftedItemID=entry.recipe and entry.recipe.craftedItemID or nil
      row:SetScript('OnEnter',function(self)
        if self.SetBackdropColor and not self.isSelected then self:SetBackdropColor(0.22,0.17,0.10,1) end
        -- Show the crafted ITEM tooltip, never the recipe/spell tooltip.
        -- Do not show a recipe tooltip for enchants or unknown outputs.
        local itemID=tonumber(self.craftedItemID)
        if not itemID and self.recipeID and C_TradeSkillUI and type(C_TradeSkillUI.GetRecipeSchematic)=='function' then
          local ok,schematic=pcall(C_TradeSkillUI.GetRecipeSchematic,self.recipeID,false)
          if ok and type(schematic)=='table' then
            local output=schematic.outputItemID or schematic.outputItemId or schematic.craftedItemID or schematic.craftedItemId
            if type(schematic.outputItem)=='table' then output=output or schematic.outputItem.itemID or schematic.outputItem.itemId end
            if type(schematic.outputItems)=='table' and type(schematic.outputItems[1])=='table' then output=output or schematic.outputItems[1].itemID or schematic.outputItems[1].itemId end
            itemID=tonumber(output)
            if itemID then self.craftedItemID=itemID end
          end
        end
        if itemID and itemID>0 and GameTooltip then
          GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
          GameTooltip:SetHyperlink('item:'..itemID)
          GameTooltip:Show()
        end
      end)
      row:SetScript('OnLeave',function(self)
        if self.SetBackdropColor then
          if self.isSelected then self:SetBackdropColor(0.12,0.29,0.24,0.92)
          else self:SetBackdropColor(0.10,0.085,0.065,0.88) end
        end
        if GameTooltip then GameTooltip:Hide() end
      end)
    else row:Hide();if row.professionIcon then row.professionIcon:Hide() end;row.isSelected=false;if row.selectionMarker then row.selectionMarker:Hide() end;row.recipeID=nil;if row.rank then row.rank:SetText('') end;row:SetScript('OnClick',nil) end
  end
end
renderUI=function()

  if not ui or not db then return end
  local professionMap={}
  for char,data in pairs(db.characters or {}) do
    for _,p in ipairs(data.professions or {}) do
      if not excluded[p.name] then
        professionMap[p.name]=professionMap[p.name] or {}
        professionMap[p.name][#professionMap[p.name]+1]={char=char,prof=p}
      end
    end
  end
  local names={};for name in pairs(professionMap) do names[#names+1]=name end
  table.sort(names,function(a,b) return tostring(a):lower()<tostring(b):lower() end)
  local professionIcons={
    ['Ingenieurskunst']='Interface\\Icons\\Trade_Engineering',
    ['Kochkunst']='Interface\\Icons\\INV_Misc_Food_15',
    ['Lederverarbeitung']='Interface\\Icons\\Trade_LeatherWorking',
    ['Schmiedekunst']='Interface\\Icons\\Trade_BlackSmithing',
    ['Alchemie']='Interface\\Icons\\Trade_Alchemy',
    ['Schneiderei']='Interface\\Icons\\Trade_Tailoring',
    ['Verzauberkunst']='Interface\\Icons\\Trade_Engraving',
    ['Juwelenschleifen']='Interface\\Icons\\INV_Misc_Gem_01',
    ['Inschriftenkunde']='Interface\\Icons\\INV_Inscription_Tradeskill01',
  }
  ui.professionIcons=professionIcons
  if not professionMap[chosenProfession] then chosenProfession=names[1];chosenCharacter=nil;chosenRecipe=nil end
  if ui.professionWatermarks then
    local professionIcon=professionIcons[chosenProfession]
    for _,watermark in ipairs(ui.professionWatermarks) do
      if professionIcon then
        watermark:SetTexture(professionIcon)
        watermark:Show()
      else watermark:Hide() end
    end
  end
  local pitems={}
  for _,name in ipairs(names) do
    local include=matches(name)
    if not include then
      for _,m in ipairs(professionMap[name]) do
        if matches(m.char) then include=true;break end
        for _,r in ipairs(m.prof.recipes or {}) do if matches(r.name) then include=true;break end end
        if include then break end
      end
    end
    if include then pitems[#pitems+1]={label=name,name=name,key=name} end
  end
  setButtons(1,pitems,function(e) chosenProfession=e.name;selectedScanProfession=e.name;chosenCharacter=nil;chosenRecipe=nil;offsets[2]=0;offsets[3]=0;renderUI() end,chosenProfession)
  local members=professionMap[chosenProfession] or {}
  table.sort(members,function(a,b) if a.prof.skill==b.prof.skill then return a.char<b.char end return a.prof.skill>b.prof.skill end)
  local mitems={};local selected
  for _,m in ipairs(members) do
    local include=searchText=='' or matches(chosenProfession) or matches(m.char)
    if not include then for _,r in ipairs(m.prof.recipes or {}) do if matches(r.name) then include=true;break end end end
    if include then mitems[#mitems+1]={label=m.char..'  '..m.prof.skill..'/'..m.prof.max,char=m.char,key=m.char} end
    if m.char==chosenCharacter then selected=m.prof end
  end
  if not selected and members[1] then chosenCharacter=members[1].char;selected=members[1].prof;chosenRecipe=nil end
  setButtons(2,mitems,function(e) chosenCharacter=e.char;chosenRecipe=nil;offsets[3]=0;renderUI() end,chosenCharacter)
  local recipes=selected and selected.recipes or {};local ritems={};local active
  local groups={};local categories={};local hasSkills=false
  for _,r in ipairs(recipes) do
    if r.id==chosenRecipe then active=r end
    if (tonumber(r.trivialLevel) or tonumber(r.skill) or 0)>0 then hasSkills=true end
    if matches(r.name) or matches(chosenCharacter) or matches(chosenProfession) or matches(r.category or fallbackCategory(chosenProfession,r)) then
      local cat=type(r.category)=='string' and r.category~='' and r.category or fallbackCategory(chosenProfession,r)
      if not groups[cat] then groups[cat]={};categories[#categories+1]=cat end
      groups[cat][#groups[cat]+1]=r
    end
  end
  if ui.skillNote then
    if recipeSort~='name' and not hasSkills then
      ui.skillNote:SetText('|cffffb46aKeine Schwierigkeitswerte vorhanden|r')
    else ui.skillNote:SetText('') end
  end
  table.sort(categories)
  for _,cat in ipairs(categories) do
    local group=groups[cat]
    table.sort(group,function(a,b)
      local as,bs=tonumber(a.trivialLevel) or tonumber(a.skill) or 0,tonumber(b.trivialLevel) or tonumber(b.skill) or 0
      if recipeSort~='name' and as~=bs then
        if recipeSort=='skillDesc' then return as>bs else return as<bs end
      end
      return tostring(a.name)<tostring(b.name)
    end)
    ritems[#ritems+1]={label=(collapsedCategories[cat] and '+ ' or '- ')..cat..' ('..#group..')',key='cat:'..cat,category=cat}
    if not collapsedCategories[cat] or searchText~='' then
      for _,r in ipairs(group) do
        ritems[#ritems+1]={label='  '..r.name,recipe=r,key=r.id}
      end
    end
  end
  if selected and #recipes==0 then
    ritems[1]={label='Noch keine Rezepte gescannt',key='empty-recipe-note'}
  end
  setButtons(3,ritems,function(e)
    if e.category then collapsedCategories[e.category]=not collapsedCategories[e.category];offsets[3]=0
    elseif e.recipe then if chosenRecipe~=e.recipe.id then materialOffset=0 end;chosenRecipe=e.recipe.id end
    renderUI()
  end,chosenRecipe)
  unresolvedMaterials=false
  for _,button in ipairs(ui.materialButtons or {}) do button:Hide();button.itemID=nil end
  activeMaterials=active and (active.materials or {}) or {}
  local visibleMaterialCount=materialColumns*1 -- one full row; scroll to later rows
  if active then
    local mats=activeMaterials
    local maxMaterialOffset=math.max(0,math.ceil(#mats/materialColumns)-1)
    materialOffset=math.min(materialOffset,maxMaterialOffset)
    ui.detail:SetText('|cffffd27a'..active.name..'|r  |cff91a79d• '..#mats..' Materialeinträge|r')
    for i=1,math.min(visibleMaterialCount,#mats-materialOffset*materialColumns) do
      local m=mats[materialOffset*materialColumns+i]
      local button=ui.materialButtons[i]
      if button and m then
        local itemName,icon=materialInfo(m.id)
        button.texture:SetTexture(icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
        button.texture:SetTexCoord(0,1,0,1)
        button.texture:SetAlpha(1)
        button.texture:Show()
        button.quantity:SetText(tostring(m.qty)..'x '..(itemName or ('Item #'..tostring(m.id))))
        button.itemID=m.id
        button.materialQty=m.qty
        button:Show()
        if not itemName or not icon then unresolvedMaterials=true end
      end
    end
    if #mats>materialColumns then
      ui.materialScrollHint:SetText('|cffbba983Mausrad: Materialien  •  Zeile '..(materialOffset+1)..'/'..math.ceil(#mats/materialColumns)..'|r')
    else ui.materialScrollHint:SetText('') end
    if #mats==0 then ui.detail:SetText('|cffffd27a'..active.name..'|r  |cff91a79d• Keine Materialdaten gespeichert|r') end
  elseif selected and #recipes==0 then
    if chosenCharacter==who() then
      ui.detail:SetText('|cffffd27aNoch keine Rezepte für '..tostring(chosenProfession)..' gespeichert.|r\nÖffne das originale WoW-Berufsfenster für '..tostring(chosenProfession)..'.\nKlicke anschließend im Addon auf "Scannen", um deine Rezepte zu erfassen.\nMit "Synchronisieren" kannst du sie danach mit der Gilde teilen.')
    else
      ui.detail:SetText('|cffffd27aFür '..tostring(chosenCharacter)..' sind noch keine '..tostring(chosenProfession)..'-Rezepte gespeichert.|r\n'..tostring(chosenCharacter)..' muss das originale WoW-Berufsfenster öffnen\nund im Addon auf "Scannen" klicken.\nAnschließend die Berufsdaten über "Synchronisieren" übertragen.')
    end
  else ui.detail:SetText('Rezept auswählen, um Materialien zu sehen.') end
  if not active then ui.materialScrollHint:SetText('') end
end

-- Minimap launcher: no external libraries required.
local minimapButton
local function positionMinimapButton()
  if not minimapButton or not Minimap then return end
  local angle=(db and tonumber(db.minimapAngle)) or 225
  local radians=math.rad(angle)
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint('CENTER',Minimap,'CENTER',math.cos(radians)*80,math.sin(radians)*80)
end
local function createMinimapButton()
  if minimapButton or not Minimap then return end
  minimapButton=CreateFrame('Button','SpucknapfBerufeMinimapButton',Minimap)
  minimapButton:SetSize(32,32)
  minimapButton:SetFrameStrata('MEDIUM')
  minimapButton:SetFrameLevel((Minimap:GetFrameLevel() or 0)+8)
  minimapButton:RegisterForClicks('LeftButtonUp','RightButtonUp')
  minimapButton:RegisterForDrag('LeftButton')
  local icon=minimapButton:CreateTexture(nil,'ARTWORK')
  icon:SetSize(20,20);icon:SetPoint('CENTER',0,0)
  icon:SetTexture('Interface\\Icons\\Trade_LeatherWorking')
  minimapButton.icon=icon
  local border=minimapButton:CreateTexture(nil,'OVERLAY')
  border:SetSize(53,53);border:SetPoint('CENTER',0,0)
  border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
  minimapButton:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
  minimapButton:SetScript('OnClick',function(self,button)
    if self.dragMoved then self.dragMoved=nil;return end
    if ui then
      if ui:IsShown() then ui:Hide() else ui:Show();ui:Raise();if renderUI then renderUI() end end
    end
  end)
  minimapButton:SetScript('OnDragStart',function(self)
    self.dragging=true;self.dragMoved=false
    self:SetScript('OnUpdate',function(btn)
      if not Minimap or not GetCursorPosition then return end
      local x,y=GetCursorPosition()
      local scale=Minimap:GetEffectiveScale()
      if not scale or scale==0 then return end
      local mx,my=Minimap:GetCenter()
      local degrees=math.deg(math.atan2((y/scale)-my,(x/scale)-mx))
      if db then db.minimapAngle=degrees end
      btn.dragMoved=true
      positionMinimapButton()
    end)
  end)
  minimapButton:SetScript('OnDragStop',function(self)
    self.dragging=false;self:SetScript('OnUpdate',nil)
  end)
  minimapButton:SetScript('OnEnter',function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self,'ANCHOR_LEFT')
    GameTooltip:AddLine('SpucknapfBerufe',0.85,0.7,0.4)
    GameTooltip:AddLine('Linksklick: Fenster öffnen / schließen',1,1,1)
    GameTooltip:AddLine('Ziehen: Position verändern',0.65,0.85,0.7)
    GameTooltip:Show()
  end)
  minimapButton:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
  positionMinimapButton()
end

createUI()
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('CHAT_MSG_ADDON')
frame:RegisterEvent('TRADE_SKILL_SHOW')
frame:RegisterEvent('TRADE_SKILL_LIST_UPDATE')
frame:RegisterEvent('SKILL_LINES_CHANGED')
frame:RegisterEvent('GUILD_ROSTER_UPDATE')
frame:RegisterEvent('GET_ITEM_INFO_RECEIVED')
frame:SetScript('OnEvent',function(_,event,...)
  if event=='ADDON_LOADED' then
    if ...~=addonName then return end
    SpucknapfBerufeDB=SpucknapfBerufeDB or {}
    db=SpucknapfBerufeDB
    db.characters=db.characters or {}; db.peers=db.peers or {}
    if ui and ui.layout then
      if db.windowWidth and db.windowHeight then ui:SetSize(math.max(740,math.min(1600,tonumber(db.windowWidth) or 970)),math.max(490,math.min(1100,tonumber(db.windowHeight) or 655))) end
      ui.layout()
    end
    createMinimapButton()
  elseif event=='PLAYER_LOGIN' then
    if not db then return end
    if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix)=='function' then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif type(RegisterAddonMessagePrefix)=='function' then RegisterAddonMessagePrefix(PREFIX) end
    say('Testversion 0.7.10 geladen. /spb oeffnet das Fenster')
    if type(GuildRoster)=='function' then GuildRoster() end
    migrateLocalAlias(who())
    capture(false); enqueue('HELLO')
  elseif event=='CHAT_MSG_ADDON' then onMessage(...)
  elseif event=='GUILD_ROSTER_UPDATE' then migrateLocalAlias(who())
  elseif event=='GET_ITEM_INFO_RECEIVED' then itemRefreshElapsed=1
  elseif event=='TRADE_SKILL_SHOW' or event=='TRADE_SKILL_LIST_UPDATE' then
    -- Forever does not reliably expose the active profession; only auto-capture
    -- recipes after the user has explicitly selected the profession via /spb scan.
    if clock()-lastScan>3 then lastScan=clock(); capture(false,activeProfession) end
  elseif event=='SKILL_LINES_CHANGED' then
    if clock()-lastScan>5 then lastScan=clock(); capture(false) end
  end
end)
frame:SetScript('OnUpdate',function(_,dt)
  itemRefreshElapsed=itemRefreshElapsed+dt
  if unresolvedMaterials and itemRefreshElapsed>=1 then
    itemRefreshElapsed=0
    local stillMissing=false
    itemLoadRequested={}
    for _,button in ipairs(ui and ui.materialButtons or {}) do
      if button:IsShown() and button.itemID then
        local name,icon=materialInfo(button.itemID)
        if name then
          local qty=button.materialQty or 0
          button.quantity:SetText(tostring(qty)..'x '..name)
        end
        if icon then
          button.texture:SetTexture(icon)
          button.texture:SetTexCoord(0,1,0,1)
          button.texture:SetAlpha(1)
          button.texture:Show()
        end
        if not name or not icon then stillMissing=true end
      end
    end
    unresolvedMaterials=stillMissing
  end
  elapsed=elapsed+dt
  if elapsed<SEND_INTERVAL then return end
  elapsed=0
  if #queue>0 then
    transmit(table.remove(queue,1))
    if #queue==0 and outgoing then outgoing.sentAt=clock() end
  elseif outgoing and outgoing.sentAt then
    if outgoing.acknowledged then
      if clock()-outgoing.sentAt>3 then
        local nextTransfer=outgoing.next
        outgoing=nil
        if nextTransfer then startTransfer(nextTransfer) end
      end
    elseif clock()-outgoing.sentAt>ACK_WAIT then
      if outgoing.attempts<3 then
        say('Empfangsbestaetigung fehlt; erneuter Versuch ('..(outgoing.attempts+1)..'/3).')
        startTransfer(outgoing)
      else
        say('Synchronisierung nicht bestaetigt. Bitte Empfaenger pruefen.')
        syncState='Keine Empfangsbestaetigung';outgoing=nil
      end
    end
  end
  for sender,box in pairs(numberedPending) do
    if clock()-box.started>8 and clock()-box.lastRequest>12 then
      local requested=0
      for i=1,box.total do
        if not box.parts[i] then
          enqueue('MISS|'..box.seq..'|'..i)
          requested=requested+1
          if requested>=8 then break end
        end
      end
      box.lastRequest=clock()
    end
    if clock()-box.started>300 then numberedPending[sender]=nil end
  end
  for key,when in pairs(recentCompleted) do
    if clock()-when>300 then recentCompleted[key]=nil end
  end
  for sender,p in pairs(pending) do if clock()-p.started>300 then say('Empfang von '..sender..' abgebrochen (Timeout).'); pending[sender]=nil end end
end)
-- Diagnose fuer Rezept-Skilldaten (nur lokale Anzeige; keine Speicherung/Aenderung).
local function recipeInfoProbe()
  local id=chosenRecipe
  if not id then say('Bitte zuerst im Addon ein Rezept anklicken.'); return end
  local api=C_TradeSkillUI or {}
  say('Rezeptdiagnose ID '..tostring(id)..' (Berufsfenster ggf. auf passenden Reiter stellen)')
  local function inspect(label,fn)
    if type(fn)~='function' then say(label..': API nicht vorhanden'); return end
    local ok,value=pcall(fn,id,false)
    if not ok then say(label..': API-Fehler '..tostring(value):sub(1,100)); return end
    if type(value)~='table' then say(label..': '..tostring(value)); return end
    local keys={}
    for k,v in pairs(value) do
      local repr=type(v)=='table' and '[Tabelle]' or tostring(v)
      keys[#keys+1]=tostring(k)..'='..repr:sub(1,55)
    end
    table.sort(keys)
    if #keys==0 then say(label..': leere Tabelle'); return end
    for i=1,#keys,3 do
      local line={}
      for j=i,math.min(i+2,#keys) do line[#line+1]=keys[j] end
      say(label..': '..table.concat(line,' | '):sub(1,220))
    end
  end
  -- GetRecipeInfo erwartet auf diesem Client offenbar eine unsigned Integer-ID
  -- als zweites Argument. Verschiedene gueltige Varianten nur lesend pruefen.
  if type(api.GetRecipeInfo)=='function' then
    local variants={
      {label='Info(id)',args={id}},
      {label='Info(id,0)',args={id,0}},
      {label='Info(id,1)',args={id,1}},
      {label='Info(id,2)',args={id,2}},
    }
    for _,variant in ipairs(variants) do
      local ok,value=pcall(api.GetRecipeInfo,unpack(variant.args))
      if not ok then
        say(variant.label..': Fehler '..tostring(value):sub(1,105))
      elseif type(value)=='table' then
        local fields={}
        for k,v in pairs(value) do
          if type(v)~='table' then fields[#fields+1]=tostring(k)..'='..tostring(v):sub(1,42)
          else fields[#fields+1]=tostring(k)..'=[Tabelle]' end
        end
        table.sort(fields)
        say(variant.label..': '..(#fields==0 and 'leere Tabelle' or 'OK'))
        for i=1,math.min(#fields,30),3 do
          local line={}
          for j=i,math.min(i+2,#fields) do line[#line+1]=fields[j] end
          say('  '..table.concat(line,' | '):sub(1,210))
        end
      else
        say(variant.label..': '..tostring(value))
      end
    end
  else say('Info: API nicht vorhanden') end
  inspect('Schematic',api.GetRecipeSchematic)
  -- Auch die Skill-/Schwierigkeits-API-Funktionen pruefen, ohne sie blind aufzurufen.
  local names={'GetRecipeDifficulty','GetRecipeDifficultyInfo','GetRecipeSkillLevel','GetRecipeSkillLevels','GetRecipeRank','GetRecipeInfo'}
  local available={}
  for _,name in ipairs(names) do
    if type(api[name])=='function' then available[#available+1]=name end
  end
  say('Verfuegbare API-Funktionen: '..table.concat(available,', '))
  local saved
  local record=db.characters and db.characters[chosenCharacter]
  if record then
    for _,prof in ipairs(record.professions or {}) do
      if prof.name==chosenProfession then
        for _,r in ipairs(prof.recipes or {}) do if r.id==id then saved=r;break end end
      end
    end
  end
  if saved then say('Gespeichert: skill='..tostring(saved.skill)..', category='..tostring(saved.category)) end
end

-- Diagnostic: show the raw category metadata returned by Forever for a recipe.
-- /spb categories [part of recipe name]
local function categoryProbe(term)
  local api=C_TradeSkillUI
  if type(api)~='table' then say('Kategorie-Diagnose: C_TradeSkillUI fehlt'); return end
  local record=db.characters and db.characters[chosenCharacter]
  local found
  if record then
    for _,prof in ipairs(record.professions or {}) do
      if prof.name==chosenProfession then
        for _,r in ipairs(prof.recipes or {}) do
          if term=='' or tostring(r.name or ''):lower():find(term:lower(),1,true) then found=r; break end
        end
        break
      end
    end
  end
  if not found then say('Kategorie-Diagnose: Rezept nicht gefunden. Beruf/Handwerker im Fenster waehlen.'); return end
  say('Kategorie-Diagnose: '..tostring(found.name)..' (ID '..tostring(found.id)..')')
  say('Gespeichert: Kategorie='..tostring(found.category)..', OutputItemID='..tostring(found.craftedItemID))
  local function inspect(label,fn,...)
    if type(fn)~='function' then say(label..': API fehlt'); return end
    local ok,value=pcall(fn,...)
    if not ok then say(label..': Fehler '..tostring(value):sub(1,80)); return end
    if type(value)~='table' then say(label..': '..tostring(value)); return end
    local keys={}
    for k,v in pairs(value) do
      if type(v)~='table' then keys[#keys+1]=tostring(k)..'='..tostring(v) end
    end
    table.sort(keys)
    for i=1,math.min(#keys,24),3 do
      local parts={}
      for j=i,math.min(i+2,#keys) do parts[#parts+1]=keys[j] end
      say(label..': '..table.concat(parts,' | '):sub(1,190))
    end
  end
  inspect('RecipeInfo',api.GetRecipeInfo,found.id,0)
  -- Check category metadata using the recipe's categoryID (not schematic.category).
  local okInfo, recipeInfo = pcall(api.GetRecipeInfo, found.id, 0)
  local categoryID = okInfo and type(recipeInfo)=='table' and tonumber(recipeInfo.categoryID) or nil
  if categoryID then
    say('Kategorie-ID aus RecipeInfo: '..tostring(categoryID))
    inspect('CategoryInfo', api.GetCategoryInfo, categoryID)
    -- Some clients expose category information via a different API namespace.
    if type(api.GetCategoryInfo)~='function' then
      say('GetCategoryInfo fehlt in C_TradeSkillUI')
    end
    if type(api.GetCategoryInfo)=='function' then
      local okCat,cat=pcall(api.GetCategoryInfo,categoryID)
      if okCat and type(cat)=='table' then
        local parentID=tonumber(cat.parentCategoryID or cat.parentID)
        if parentID then inspect('ParentCategory',api.GetCategoryInfo,parentID) end
      end
    end
  else
    say('Keine categoryID in RecipeInfo gefunden')
  end
  for _,fnName in ipairs({'GetCategoryInfo','GetCategories','GetCategoryIDs','GetRecipeCategoryID','GetRecipeCategoryInfo'}) do
    say('API '..fnName..': '..(type(api[fnName])=='function' and 'vorhanden' or 'fehlt'))
  end

  inspect('Schematic',api.GetRecipeSchematic,found.id,false)
  if found.craftedItemID and type(GetItemInfo)=='function' then
    local name,_,_,_,_,itemType,itemSubType,_,equipLoc=GetItemInfo(found.craftedItemID)
    say('Item: '..tostring(name)..' | Typ='..tostring(itemType)..' | Subtyp='..tostring(itemSubType)..' | Slot='..tostring(equipLoc))
  end
end

SLASH_SPUCKNAPFBERUFE1='/spb'
SlashCmdList.SPUCKNAPFBERUFE=function(input)
  if not db then say('Datenbank noch nicht bereit.'); return end
  input=(input or ''):match('^%s*(.-)%s*$')
  local cmd,arg=input:match('^(%S+)%s*(.*)$')
  cmd=(cmd or 'open'):lower()
  if cmd=='open' or cmd=='oeffnen' or cmd=='ui' then if ui then if ui:IsShown() then ui:Hide() else ui:Show(); renderUI() end end
  elseif cmd=='identity' then say('UnitName: '..shortName()..' | Schluessel: '..who())
  elseif cmd=='name' then
    if arg=='' then say('Nutzung: /spb name Vorname Nachname')
    elseif arg:find(' ',1,true) then db.myFullName=arg; migrateLocalAlias(arg); capture(false); say('Vollstaendiger Name gesetzt: '..arg)
    else say('Bitte Vor- und Nachnamen eingeben.') end
  elseif cmd=='api' then apiReport()
  elseif cmd=='scan' then if arg~='' then activeProfession=arg end; capture(true,arg)
  elseif cmd=='probe' then probe()
  elseif cmd=='materials' then materialsProbe()
  elseif cmd=='recipeinfo' then recipeInfoProbe()
  elseif cmd=='categories' or cmd=='kategorien' then categoryProbe(arg)
  elseif cmd=='sync' then sendSnapshot(); say('Datenuebertragung geplant ('..(outgoing and #outgoing.messages or 0)..' Pakete). Bitte bis zur Empfangsbestaetigung warten.')
  elseif cmd=='ping' then enqueue('HELLO'); say('Ping eingereiht.')
  elseif cmd=='peers' then
    local n=0; for name in pairs(db.peers) do say('Kontakt: '..name); n=n+1 end
    if n==0 then say('Keine anderen Addon-Nutzer erkannt.') end
  elseif cmd=='list' then show()
  elseif cmd=='recipes' then recipeList(arg)
  elseif cmd=='help' then say('/spb (Fenster ein/aus) | identity | name [Vorname Nachname] | scan [Berufsname] | api | probe | materials | recipeinfo | sync | ping | peers | list | recipes [Suche]')
  else say('Unbekannter Befehl. /spb help') end
end

-- The Presets tab: importing preset files (a large one of thousands of fields, read over several frames with a
-- progress line; malformed ones refused with the reason in a toast, the import page and the log; a ModBuilder project
-- converted), the collapsible SHARED PRESET FILES and MODBUILDER PROJECTS sections, preset icons, and the saved data
-- limit. Every frame must stay inside the overlay's limits. args.old_preset_files: the 0.9.2 preset_files.lua source
-- (an older editor reading a file with an icon), optional.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local preset_files=require('mods/skyeshade/hd2runtime_editor/editor/preset_files')
local presets_module=require('mods/skyeshade/hd2runtime_editor/editor/presets')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local modbuilder=require('mods/skyeshade/hd2runtime_editor/editor/modbuilder')
local json=require('mods/skyeshade/hd2runtime_editor/editor/json')
local win=require('mods/skyeshade/hd2runtime_editor/editor/win')
local app=H.app
local out={}

local logged={}
app.ctx.log=function(m)logged[#logged+1]=tostring(m)end
local function logged_with(...)
    local parts={...}
    for i=#logged,1,-1 do
        local ok=true
        for _,s in ipairs(parts)do if not logged[i]:find(s,1,true)then ok=false end end
        if ok then return logged[i]end
    end
    return nil
end
-- args.dump (a folder): each labelled frame as JSON for tests/render_frames.py
local function step(keys,opts,label)
    local d=H.frame(keys,opts)
    assert(#d.refused==0,(label or'frame')..': the overlay would refuse '..tostring(d.refused[1]))
    assert(#d.items<=1024,(label or'frame')..': '..#d.items..' items (limit 1024)')
    if label and args.dump then
        local f=assert(io.open(args.dump..'/presets_'..label:gsub('[^%w]+','_')..'.json','wb'))
        f:write(H.dump(d))
        f:close()
    end
    return d
end
local function shows(d,text)
    for _,it in ipairs(d.items)do if it.k=='t'and it.s:find(text,1,true)then return true end end
    return false
end
local function put(path,text)local f=assert(io.open(path,'wb'));f:write(text);f:close()end
local function exists(path)local f=io.open(path,'rb');if f then f:close();return true end return false end
local function toast()return app.toast_msg and app.toast_msg.text or''end

local base=(os.getenv('TEMP')or'.')..'\\hd2r_presets_tab_'..tostring(os.time())..'_'..tostring(math.random(1000000))
local shared,elsewhere=base..'\\Presets',base..'\\Elsewhere'
preset_files.base=shared
modbuilder.base=base..'\\Local'
win.mkdir(elsewhere)
app.pf_list,app.mb_list=nil,nil
app:set_view('presets')
step({},nil,'presets tab')

-- Imports a file as if chosen in the Windows dialog; returns the number of frames it took.
local function import_file(path,max_frames)
    app.pf_picking={poll=function()return path end}
    local frames,saw_progress=0,false
    repeat
        step({},nil,'importing')
        frames=frames+1
        local text=app:presets_status()
        if app.pf_job and text:find('Importing',1,true)then saw_progress=true end
    until(not app.pf_job and not app.pf_picking)or frames>(max_frames or 4000)
    assert(not app.pf_job,'the import finished')
    return frames,saw_progress
end

----------------------------------------------------------------------------------------------- a large preset --
-- every editable numeric field of the catalogue (thousands), with labels, as another editor's SHARE writes it
local values,labels,n={},{},0
for _,category in ipairs({'primary','secondary','throwables','offensive','defensive','support_weapons',
        'support_backpacks','vehicles','resupply','boosters','terminids','automatons','illuminate','helldiver'})do
    for _,o in ipairs((H.catalog:objects(category)))do
        H.catalog:open(o)
        for _,r in ipairs(o.rows or{})do
            if r.editable and not r.kind and type(r.vanilla)=='number'then
                values[r.key]=catalog_module.encode(r,r.vanilla)
                labels[r.key]=o.name..' · '..r.label
                n=n+1
            end
        end
    end
end
assert(n>=3000,'a large preset: '..n..' fields')
local big=elsewhere..'\\Big Preset.hd2rpreset.json'
local big_text=preset_files.encode('Big Preset',values,labels,{editor='0.9.2',runtime='0.31.1'})
put(big,big_text)
assert(#big_text>500*1024,'more than 500 KB: '..#big_text)
-- the import page is the second row: where files go, the dialog, REFRESH
app.preset_index=2
local d=step({},nil,'import page')
assert(app:preset_entry(2).kind=='import','IMPORT PRESET... is the second row')
assert(shows(d,'IMPORT PRESET')and shows(d,shared)and shows(d,'REFRESH'),'the import page names the folder')
local frames,saw_progress=import_file(big)
assert(frames>2 and saw_progress,'read over several frames with a progress line: '..frames..' frames')
local copied=shared..'\\Big-Preset.hd2rpreset.json'
assert(exists(copied),'copied into the shared folder')
local entry=app:preset_entry(app.preset_index)
assert(entry.kind=='file'and entry.file.path:lower()==copied:lower(),'the imported file is selected')
assert(toast():find('Imported Big Preset: '..n..' fields',1,true),'toast: '..toast())
assert(logged_with('import: '..big,n..' fields',copied),'logged: '..tostring(logged[#logged]))
d=step({},nil,'imported file')
assert(shows(d,'Big Preset')and shows(d,'SAVE AS PRESET'),'its detail shows')
-- opened again later (another session): read over several frames with its progress, then shown
app.pf_key=nil
d=step({},nil,'reading a large file')
assert(app.pf_open.reading and shows(d,'Reading Big-Preset.hd2rpreset.json'),'a large file reads with its progress')
local reads=0
repeat d=step({},nil,'reading');reads=reads+1 until not app.pf_open.reading or reads>500
assert(app.pf_open.preset and app.pf_open.preset.count==n and reads>1,'read in '..reads..' frames')
-- the slowest frame of all that stays short (a few milliseconds of reading a frame)
local slowest=0
app.pf_key=nil
repeat
    local t0=os.clock()
    step({})
    slowest=math.max(slowest,os.clock()-t0)
until not app.pf_open.reading
-- its values are sorted once, not every frame
local rows=app.value_rows_cache and app.value_rows_cache.rows
assert(rows and#rows==n,'every field listed')
step({},nil,'imported file again')
assert(app.value_rows_cache.rows==rows,'the sorted list is kept between frames')
-- IMPORT SELECTED keeps a file with your presets (by the import page's choice). A preset this large does not fit in
-- HD2Runtime's saved data (1 MiB per mod): refused with its size and a way out (it stays a shared file), never kept
-- only until the game closes.
app.pf_pick=copied
app:import_action_run(2)
repeat step({})until not app.pf_job
assert(not H.presets:find('Big Preset'),'too large for the saved data')
assert(toast():find('Not imported',1,true)and toast():find('KB',1,true)and toast():find('SHARE',1,true),
    'refused with the size: '..toast())
assert(logged_with('import failed',copied,'KB'),'logged the refusal')
assert(exists(copied),'the shared file stays')
-- a smaller one is kept and selected
local half,count={},0
for key,value in pairs(values)do if count<1200 then half[key]=value;count=count+1 end end
local half_path=shared..'\\Half.hd2rpreset.json'
put(half_path,preset_files.encode('Half',half,nil,{}))
app:preset_files_refresh()
app.pf_pick=half_path
app:import_action_run(2)
repeat step({})until not app.pf_job
local saved=H.presets:find('Half')
assert(saved and saved.count==1200,'IMPORT SELECTED saved it: '..toast())
assert(app:preset_entry(app.preset_index).kind=='preset','and selected it')
assert(logged_with('saved as the preset "Half"','1200 fields'),'logged the save')
-- the preset list is read once per change, not every frame (hd2.store copies a whole value on each get)
assert(H.presets:list()==H.presets:list(),'the list is cached')
-- copies until the limit: the one that would pass it is refused, nothing lost
local kept=1
for i=2,12 do
    app:import_start(half_path,'keep');repeat step({})until not app.pf_job
    if not H.presets:find('Half '..i)then break end
    kept=i
end
assert(kept>1 and kept<12,'copies are kept until the limit: '..kept)
assert(toast():find('Not imported',1,true)and toast():find('KB',1,true),'with the size: '..toast())
assert(presets_module.json_size(H.store.data)<=presets_module.STORE_LIMIT,'the saved data stays under the limit')
-- the store size estimate is the store's own (HD2Runtime runtime/mod_store.lua encode)
local ok_store,store_module=pcall(require,'hd2runtime/runtime/mod_store')
if ok_store and type(store_module.encode)=='function'then
    local list=H.store:get('presets',{})
    local exact=#store_module.encode(list)
    local estimate=presets_module.json_size(list)
    assert(math.abs(estimate-exact)<=exact*0.01,'size estimate '..estimate..' vs '..exact)
end
for i=2,kept do H.presets:delete('Half '..i)end
H.presets:delete('Half')
out[#out+1]='large import ok ('..n..' fields, '..math.floor(#big_text/1024)..' KB, '..frames..' frames, slowest frame '
    ..math.floor(slowest*1000)..' ms)'

-- while the window is closed the import goes on (main.lua background_tick)
local medium=elsewhere..'\\medium.hd2rpreset.json'
local some={}
count=0
for key,value in pairs(values)do if count<800 then some[key]=value;count=count+1 end end
put(medium,preset_files.encode('Medium',some,nil,{}))
app:import_start(medium,'copy')
local ticks=0
repeat app:background_tick();ticks=ticks+1 until not app.pf_job or ticks>1000
assert(not app.pf_job and exists(shared..'\\Medium.hd2rpreset.json'),'imported while closed')
assert(toast():find('Imported Medium: 800 fields',1,true),toast())
out[#out+1]='background import ok'

------------------------------------------------------------------------------------------------ malformed files --
local row
for key in pairs(values)do row=key;break end
local function expect_refusal(name,text,needle,label)
    local path=elsewhere..'\\'..name
    if text then put(path,text)end
    logged={}
    import_file(path)
    assert(toast():find('Not imported',1,true)and toast():find(needle,1,true),label..': toast '..toast())
    assert(logged_with('import failed',needle),label..': no log line with '..needle)
    assert(app.pf_note and app.pf_note.text:find(needle,1,true),label..': the import page keeps the reason')
    -- once the toast has gone, the status line keeps the reason
    local shown=app.toast_msg
    app.toast_msg=nil
    local text_now=app:presets_status()
    app.toast_msg=shown
    assert(text_now:find(needle,1,true),label..': the status line keeps it: '..text_now)
end
expect_refusal('empty.json','','the file is empty','empty')
expect_refusal('broken.json','{\n  "format": "hd2r-editor-preset",\n  "version": 1,\n  "fields": [\n'
    ..'    {"key": "'..row..'", "value": 1,}\n  ]\n}\n','at line 5','a JSON error names its line')
expect_refusal('truncated.json',big_text:sub(1,math.floor(#big_text/2)),'not valid JSON','truncated')
expect_refusal('trailing.json',preset_files.encode('T',{[row]=1})..'garbage','unexpected text after the end','trailing')
expect_refusal('other.json','{"hello":1}','not an HD2R Editor preset file','another JSON file')
expect_refusal('newer.json','{"format":"hd2r-editor-preset","version":2,"fields":[]}','newer preset format','newer')
expect_refusal('nofields.json','{"format":"hd2r-editor-preset","version":1,"name":"x"}','no "fields" list','no fields')
expect_refusal('unreadable.json','{"format":"hd2r-editor-preset","version":1,"fields":[{"value":1},{"key":"k"}]}',
    'none of its 2 fields can be read','unreadable fields')
expect_refusal('missing.json',nil,'cannot open','a file that is not there')
do
    local limit=preset_files.LIMIT
    preset_files.LIMIT=2048
    expect_refusal('toolarge.json',string.rep(' ',4096)..'{}','too large','too large')
    preset_files.LIMIT=limit
end
-- some fields unreadable: imported, and the count (and the first keys, in the log) said
put(elsewhere..'\\partly.json','{"format":"hd2r-editor-preset","version":1,"name":"Partly","fields":['
    ..'{"key":"'..row..'","value":5},{"key":"bad|one","value":{"a":{"b":{"c":{"d":{"e":1}}}}}},{"value":3}]}')
logged={}
import_file(elsewhere..'\\partly.json')
assert(toast():find('Imported Partly: 1 fields, 2 unreadable fields skipped',1,true),toast())
assert(logged_with('2 unreadable fields skipped (first: bad|one, field 3)'),'the skipped keys are logged')
-- the dialog closed without a file: said, and logged
app.pf_picking={poll=function()return false end}
step({})
assert(toast():find('No file chosen',1,true)and logged_with('no file chosen'),'a cancelled dialog is reported')
-- a folder that cannot be listed says why (not "0" with nothing else)
do
    local list=win.list
    win.list=function()return nil,'no FFI'end
    app:preset_files_refresh()
    assert(app.pf_list_error=='no FFI'and logged_with('cannot be listed: no FFI'),'a listing failure is reported')
    app:preset_section_set('files',true)
    local hint=app:preset_index_of('file_empty')
    assert(hint,'the empty section has its hint row')
    d=step({},nil,'list error')
    assert(shows(d,'The folder cannot be listed: no FFI'),'and shows it')
    win.list=list
    app:preset_files_refresh()
end
-- the decoder on its own: line and column of an error
local okj,err=pcall(json.decode,'{\n "a": [1,\n 2,,3]}',nil,true)
assert(not okj and json.explain('{\n "a": [1,\n 2,,3]}',err):find('line 3, column 4',1,true),tostring(err))
out[#out+1]='malformed ok'

----------------------------------------------------------------------------------- a ModBuilder project file --
put(elsewhere..'\\project.hd2mod.json',[[{"formatVersion":11,"id":"x","displayName":"Big Rebalance","author":"someone",
    "resourceId":"mods/someone/big_rebalance","version":"1.0.0","sdkVersion":"0.28.1","runtimeApi":1,
    "weaponChanges":[{"weapon":"AR-23P Liberator Penetrator","semanticFieldId":"weapon.fire_rate","fieldType":"number",
        "expectedValue":640,"desiredValue":777,"enabled":true},
      {"weapon":"AR-23P Liberator Penetrator","semanticFieldId":"weapon.made_up","fieldType":"number",
        "expectedValue":1,"desiredValue":2,"enabled":true}]}]])
logged={}
import_file(elsewhere..'\\project.hd2mod.json')
assert(toast():find('Converted the ModBuilder project Big Rebalance: 1 of 2 edits',1,true),toast())
local converted=shared..'\\Big-Rebalance.hd2rpreset.json'
local preset=assert(preset_files.load(converted))
local rate
for key,value in pairs(preset.values)do if key:find('weapon.fire_rate',1,true)then rate=value end end
assert(preset.count==1 and rate==777,'the convertible edit is in the preset')
assert(logged_with('ModBuilder project "Big Rebalance"','1 the editor cannot take','weapon.made_up'),'logged with why')
out[#out+1]='modbuilder file ok'

-------------------------------------------------------------------------------------------- collapsible sections --
-- ten ModBuilder projects: the section starts closed (more than eight); the shared files start open
do
    local root=modbuilder.base..'\\HD2RuntimeGUI'
    win.mkdir(root)
    local projects={}
    for i=1,10 do
        projects[#projects+1]=('{"id":"%08d-2222-4333-8444-555555555555","displayName":"Project %d","resourceId":"mods/x/p%d",'
            ..'"sdkVersion":"0.30.0","modifiedAt":"2026-10-%02dT10:00:00+00:00"}'):format(i,i,i,i)
    end
    put(root..'\\library.json','{"formatVersion":1,"projects":['..table.concat(projects,',')..']}')
end
app.mb_list,app.pe_open=nil,nil
local settings=H.store:get('settings',{})
settings.presets_files_open,settings.presets_mb_open=nil,nil
H.store:set('settings',settings)
assert(#app:mb_projects()==10,'ten projects')
assert(app:preset_section_open('files')and not app:preset_section_open('mb'),'files open, ModBuilder closed')
local function count_kind(kind)
    local c=0
    for _,e in ipairs(app:preset_entries())do if e.kind==kind then c=c+1 end end
    return c
end
assert(count_kind('mb')==0 and count_kind('file')>=3,'closed sections list nothing')
d=step({},nil,'sections')
assert(shows(d,'→')and shows(d,'↓'),'the headers show their state')
-- Enter on a header opens or closes it (and the choice is saved)
app.preset_index=app:preset_index_of('mb_header')
step({'ENTER'},nil,'open ModBuilder')
assert(count_kind('mb')==10 and H.store:get('settings',{}).presets_mb_open==true,'opened and saved')
assert(app:preset_entry(app.preset_index).kind=='mb_header','the header stays selected')
app.preset_index=app:preset_index_of('file_header')
step({'ENTER'},nil,'close the files')
assert(count_kind('file')==0 and H.store:get('settings',{}).presets_files_open==false,'closed and saved')
-- the keyboard moves from header to header over the closed section
step({'DOWN'})
assert(app:preset_entry(app.preset_index).kind=='mb_header','Down skips the hidden files')
-- a click on a header toggles it (the list's own click action)
step({},nil,'before click')
local action=app.preset_actions[app.preset_index]
assert(action and action.click,'the header row is clickable')
action.click()
assert(count_kind('mb')==0 and H.store:get('settings',{}).presets_mb_open==false,'a click closed it')
-- a new session reads the saved choice
app.pe_open=nil
assert(not app:preset_section_open('files')and not app:preset_section_open('mb'),'remembered')
-- the empty folder's hint row is passed over by the keyboard
app:preset_section_set('files',true)
local saved_base=preset_files.base
preset_files.base=base..'\\Empty'
app:preset_files_refresh()
local hint=assert(app:preset_index_of('file_empty'),'an empty folder has its hint')
d=step({},nil,'empty folder hint')
assert(shows(d,'None yet: drop .hd2rpreset.json files into')and shows(d,base..'\\Empty'),'the hint names the folder')
app.preset_index=hint-1
step({'DOWN'})
assert(app.preset_index==hint+1,'Down passes over the hint')
step({'UP'})
assert(app.preset_index==hint-1,'and Up too')
preset_files.base=saved_base
app:preset_files_refresh()
out[#out+1]='sections ok'

-------------------------------------------------------------------------------------------------------- icons --
app.ctx.preset_icons={['Test Picture']={{handle={image='pi_test_1'},colours={r={255,0,0,255},g={0,255,0,255},
    b={0,0,255,255}}}}}
assert(H.presets:save('Icon Me',{[row]=1}))
app:select_preset('Icon Me')
local p=H.presets:find('Icon Me')
app:preset_action_run(4,p)
assert(app.picker and app.picker.title=='PRESET ICON','ICON opens the icon picker')
d=step({},nil,'icon picker')
assert(shows(d,'No icon'),'it lists No icon first')
-- searchable: a filter, then Enter chooses
app.picker.filter='test p';app:picker_filter()
assert(#app.picker.shown==1,'the filter finds the picture')
d=step({},nil,'icon picker filtered')
local pictured=false
for _,it in ipairs(d.items)do if it.k=='i'and it.image=='pi_test_1'then pictured=true end end
assert(shows(d,'Test Picture')and shows(d,'Picture built into this editor')and pictured,'the picture is listed with its icon')
step({'ENTER'},nil,'icon chosen')
p=H.presets:find('Icon Me')
assert(p.icon and p.icon.kind=='picture'and p.icon.name=='Test Picture','the preset has the icon')
d=step({},nil,'preset with an icon')
local drawn=0
for _,it in ipairs(d.items)do if it.k=='i'and it.image=='pi_test_1'then drawn=drawn+1 end end
assert(drawn>=2,'drawn in the list row and the detail header: '..drawn)
-- a game icon when this build has them
local icons=app.ctx.icons
local some_stratagem=icons and next(icons.stratagems or{})
if some_stratagem then
    app:set_preset_icon({preset='Icon Me'},{kind='stratagem',name=some_stratagem},'Icon Me')
    assert(H.presets:find('Icon Me').icon.name==some_stratagem,'a stratagem icon')
    step({},nil,'stratagem icon')
    app:set_preset_icon({preset='Icon Me'},{kind='picture',name='Test Picture'},'Icon Me')
end
-- saving over a preset keeps its icon; SHARE writes it into the file
assert(H.presets:save('Icon Me',{[row]=2}))
assert(H.presets:find('Icon Me').icon and H.presets:find('Icon Me').count==1,'saving over keeps the icon')
app:share_preset(H.presets:find('Icon Me'))
local shared_icon=shared..'\\Icon-Me.hd2rpreset.json'
local file_preset=assert(preset_files.load(shared_icon))
assert(file_preset.icon and file_preset.icon.name=='Test Picture','the file carries the icon')
assert(preset_files.peek(shared_icon).name=='Test Picture','read from the head of the file')
-- a shared file's ICON rewrites only the icon
local before=assert(preset_files.load(converted))
assert(preset_files.set_icon(converted,{kind='booster',name='Hellpod Space Optimization'}))
local after=assert(preset_files.load(converted))
assert(after.icon.kind=='booster'and after.count==before.count and after.created==before.created
    and next(after.labels)~=nil,'values, labels and date kept')
assert(preset_files.set_icon(converted,nil)and preset_files.load(converted).icon==nil,'and removed')
-- a file without an icon, or with one this editor does not know, still loads
assert(preset_files.decode('{"format":"hd2r-editor-preset","version":1,"fields":[{"key":"k","value":1}]}').icon==nil)
local unknown=preset_files.decode('{"format":"hd2r-editor-preset","version":1,"icon":{"kind":"hologram","name":"x"},'
    ..'"fields":[{"key":"k","value":1}]}')
assert(unknown and unknown.icon==nil,'an unknown icon kind is ignored')
-- an older editor (0.9.2) reads a file with an icon as before
if args.old_preset_files and args.old_preset_files~=''then
    local old=assert(loadstring(args.old_preset_files,'@old preset_files'))()
    local text=preset_files.encode('With Icon',{[row]=3},nil,{icon={kind='picture',name='Test Picture'}})
    local got=assert(old.decode(text))
    assert(got.name=='With Icon'and got.values[row]==3 and got.skipped==0,'0.9.2 reads it')
    out[#out+1]='old editor ok'
end
-- the list shows a file's icon
app:open_shared_file(shared_icon)
d=step({},nil,'file with an icon')
drawn=0
for _,it in ipairs(d.items)do if it.k=='i'and it.image=='pi_test_1'then drawn=drawn+1 end end
assert(drawn>=2,'a shared file shows its icon: '..drawn)
-- No icon removes it
app:preset_action_run(4,H.presets:find('Icon Me'))
app.picker.filter='no icon';app:picker_filter();app:picker_choose()
assert(H.presets:find('Icon Me').icon==nil,'No icon removes it')
H.presets:delete('Icon Me')
out[#out+1]='icons ok'

-- every view of the tab once more, inside the overlay's limits
for i=1,app:preset_count()do app.preset_index=i;step({},nil,'row '..i)end

preset_files.base,modbuilder.base=nil,nil
app.pf_list,app.mb_list=nil,nil
os.execute('rmdir /s /q "'..base..'" 2>nul')
return table.concat(out,'\n')

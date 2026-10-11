-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- PRESETS: the saved presets (editor/presets.lua), the shared preset files (editor/preset_files.lua) and ModBuilder's
-- projects (editor/modbuilder.lua), in one list:
--   + NEW PRESET FROM CURRENT VALUES
--   IMPORT PRESET...            where files go, the Windows dialog, REFRESH, the folder's files
--   your presets                LOAD, SAVE OVER, RENAME, ICON, SHARE, DELETE
--   SHARED PRESET FILES (n)     collapsible; each file: LOAD, SAVE AS PRESET, ICON
--   MODBUILDER PROJECTS (n)     collapsible (closed by default past 8 projects); STAGE CHOSEN ...
-- Importing reads a file as a job (preset_files.job), a few milliseconds a frame, also while the window is closed
-- (main.lua calls background_tick), with its progress on the status line; every outcome is a toast, a line in the
-- LOGS tab ('[editor] import ...') and the import page's last result. A ModBuilder project file is converted to a
-- preset of the edits the editor can take.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local preset_files=require('mods/skyeshade/hd2runtime_editor/editor/preset_files')
local modbuilder=require('mods/skyeshade/hd2runtime_editor/editor/modbuilder')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local win=require('mods/skyeshade/hd2runtime_editor/editor/win')
local C,SZ=theme.colour,theme.size
local L=i18n.L
local Lf=i18n.Lf
local M={}

local PRESETS_W=470
local PRESET_ACTIONS={'LOAD','SAVE OVER','RENAME','ICON','SHARE','DELETE'}
local FILE_ACTIONS={'LOAD','SAVE AS PRESET','ICON'}
local MB_ACTIONS={'STAGE CHOSEN','CHOOSE ALL','CHOOSE NONE'}
local IMPORT_ACTIONS={'CHOOSE A FILE...','IMPORT SELECTED','REFRESH','OPEN THE FOLDER'}
M.MB_COLLAPSED_PAST=8         -- ModBuilder projects: the section starts closed with more than this many
M.JOB_SECONDS=0.004           -- an import's work per frame
M.READ_AT_ONCE=256*1024       -- bytes: a shared file larger than this is read over several frames when opened
local PASSED={file_empty=true} -- rows the keyboard passes over
-- The stratagem categories (for an icon's category colour) and the families draw_icon draws.
local ICON_CATEGORIES={'offensive','defensive','support_weapons','support_backpacks','vehicles','resupply'}

local function clamp_index(i,n)if n<=0 then return 1 end return math.max(1,math.min(n,i))end

function M.install(App)
    local button=App.button_fn
    local slot_order=App.slot_order

    local function log(self,line)if self.ctx.log then self.ctx.log(line)end end
    -- An outcome the player should not miss: a toast, the import page's last result (the status line shows it for a
    -- while) and, when given, a line in the LOGS tab.
    function App:preset_note(text,colour,line)
        self.pf_note={text=util.plain(text),colour=colour or C.text,time=self.time}
        self:toast(text,colour)
        if line then log(self,line)end
    end

    ------------------------------------------------------------------------------------------- saved presets --
    function App:save_preset(name,confirmed)
        local values=self:current_values()
        if next(values)==nil then self:toast(L('Nothing to save: edit a field first'),C.dim);return end
        if not confirmed and self.presets:find(name)then self:ask('overwrite_preset',name);return end
        local ok,why=self.presets:save(name,self:encode_values(values))
        if ok then self:toast(Lf('Saved preset %s (%d fields)',name,util.count(values)),C.ok)
        else
            self:toast(Lf('Could not save: %s',tostring(why)),C.error)
            log(self,'preset '..tostring(name)..' not saved: '..tostring(why))
        end
    end
    -- The toast after values were staged from a preset or a file.
    function App.loaded_text(name,pending,missing)
        if missing>0 then
            return Lf('Loaded %s: %d pending, %d unknown fields skipped. Press Apply.',name,pending,missing)
        end
        return Lf('Loaded %s: %d pending. Press Apply.',name,pending)
    end
    function App:load_preset(name)
        local values=self.presets:load(name)
        if not values then return end
        local missing=self:stage_map(values,{kind='preset',name=name})
        self:toast(App.loaded_text(name,self.pending_n,missing),missing>0 and C.pending or C.ok)
    end
    -- The list index of a saved preset, of a shared file (by path) or of the first entry of a kind.
    function App:preset_index_where(test)
        for i,e in ipairs(self:preset_entries())do if test(e)then return i end end
        return nil
    end
    function App:preset_index_of(kind)return self:preset_index_where(function(e)return e.kind==kind end)end
    function App:select_preset(name)
        local i=self:preset_index_where(function(e)return e.kind=='preset'and e.preset.name==name end)
        if i then self.preset_index,self.preset_action,self.detail_scroll=i,1,0 end
    end
    function App:finish_rename()
        local r=self.rename
        self.rename=nil
        if not r then return end
        if r.create then
            local name=self.presets:unique_name(r.text~=''and r.text or'Preset')
            self:save_preset(name,true)
            self:select_preset(name)
            return
        end
        local ok,why=self.presets:rename(r.old,r.text)
        if ok then self:toast(Lf('Renamed to %s',r.text),C.ok)else self:toast(tostring(why),C.error)end
    end
    function App:preset_action_run(index,preset)
        if not preset then return end
        local a=PRESET_ACTIONS[index]
        if a=='LOAD'then self:load_preset(preset.name)
        elseif a=='SAVE OVER'then self:save_preset(preset.name)
        elseif a=='RENAME'then self.rename={old=preset.name,text=preset.name}
        elseif a=='ICON'then self:open_icon_picker({preset=preset.name},preset.icon,preset.name)
        elseif a=='SHARE'then self:share_preset(preset)
        elseif a=='DELETE'then self:ask('delete_preset',preset.name)end
    end
    function App:new_preset()
        if next(self:current_values())==nil then self:toast(L('Nothing to save: edit a field first'),C.dim);return end
        self.rename={create=true,text=self.presets:unique_name('Preset')}
    end

    ------------------------------------------------------------------------------------- shared preset files --
    -- The shared folder's preset files, listed again every few seconds while the tab shows them, so a file dropped into
    -- the folder appears by itself. A folder that cannot be listed says why (once in the log).
    function App:preset_files()
        if not self.pf_list or self.time-(self.pf_time or-99)>3 then
            local list,why=preset_files.list(preset_files.folder(),win.list)
            self.pf_list,self.pf_list_error,self.pf_time=list,why,self.time
            if why and why~=self.pf_list_logged then
                self.pf_list_logged=why
                log(self,'the shared preset folder '..tostring(preset_files.folder())..' cannot be listed: '..why)
            end
        end
        return self.pf_list
    end
    function App:preset_files_refresh()
        self.pf_list,self.pf_icons=nil,nil
        self.mb_list,self.mb_key=nil,nil
        local n=#self:preset_files()
        self:toast(self.pf_list_error and Lf('The folder cannot be listed: %s',self.pf_list_error)
            or(n==1 and L('1 preset file in the folder')or Lf('%d preset files in the folder',n)),
            self.pf_list_error and C.error or C.dim)
    end
    -- A shared file's icon (read from the head of the file once per size), or nil.
    function App:preset_file_icon(f)
        self.pf_icons=self.pf_icons or{}
        local key=f.path..'@'..tostring(f.size)
        local icon=self.pf_icons[key]
        if icon==nil then icon=preset_files.peek(f.path)or false;self.pf_icons[key]=icon end
        return icon or nil
    end
    -- A preset as a file in the shared folder, with each field's name for people reading it.
    function App:share_preset(preset)
        local folder=preset_files.folder()
        if not folder then self:toast(L('No Documents folder (%USERPROFILE%)'),C.error);return end
        local values,labels={},{}
        for _,item in ipairs(preset.fields or{})do
            values[item.k]=item.v
            local row=self.catalog:row(item.k)
            if row then labels[item.k]=row.object.name..' · '..row.label
            elseif App.is_custom_key(item.k)then
                local name,label=self:custom_value_text(item.k,item.v)
                labels[item.k]=name..' · '..label
            end
        end
        local ok,path=pcall(preset_files.save,folder,preset.name,values,labels,
            {editor=self.ctx.version,runtime=self.ctx.minimum,icon=preset.icon},win.mkdir)
        if not ok then
            self:toast(Lf('Not shared: %s',tostring(path)),C.error)
            log(self,'the preset '..preset.name..' was not shared: '..tostring(path))
            return
        end
        self.pf_list=nil
        self:toast(Lf('Shared as %s',path),C.ok)
        log(self,'shared the preset '..preset.name..' as '..path)
    end
    -- A file's preset, read once per size: {preset, error}, or {reading = job} while a large file is read over several
    -- frames (a small one is read at once).
    local function opened(job)
        local why=job.why
        if not job.preset and job.extra and job.extra.modbuilder then
            why=L('a ModBuilder project: IMPORT SELECTED converts it to a preset of the edits the editor can take')
        end
        return {preset=job.preset,error=job.preset==nil and tostring(why)or nil}
    end
    function App:preset_file_open(f)
        local key=f.path..'@'..tostring(f.size)
        if self.pf_key~=key then
            local job=preset_files.job(f.path,{wide=win.reader})
            self.pf_key,self.detail_scroll=key,0
            if(f.size or 0)>M.READ_AT_ONCE then self.pf_open={reading=job}
            else
                job:step(1)
                self.pf_open=opened(job)
            end
        end
        local reading=self.pf_open.reading
        if reading and reading:step(M.JOB_SECONDS)then self.pf_open=opened(reading)end
        return self.pf_open
    end
    function App:preset_file_action_run(index,f)
        local a=FILE_ACTIONS[index]
        local open=self:preset_file_open(f)
        if open.reading then self:toast(Lf('Still reading %s',f.name),C.dim);return end
        if not open.preset then
            self:preset_note(Lf('Could not read this file: %s',tostring(open.error)),C.error,
                'preset file '..f.path..' not read: '..tostring(open.error))
            return
        end
        local p=open.preset
        if a=='LOAD'then
            local missing=self:stage_map(p.values,{kind='preset',name=p.name})
            self:toast(App.loaded_text(p.name,self.pending_n,missing),missing>0 and C.pending or C.ok)
        elseif a=='ICON'then
            self:open_icon_picker({file=f.path},p.icon,p.name)
        else
            local name=self.presets:unique_name(p.name)
            local ok,why=self.presets:save(name,p.values,p.icon)
            if ok then
                self:preset_note(Lf('Saved preset %s (%d fields)',name,p.count),C.ok,
                    'preset file '..f.path..' saved as the preset '..name..' ('..p.count..' fields)')
                self:select_preset(name)
            else
                self:preset_note(Lf('Could not save: %s',tostring(why)),C.error,
                    'preset file '..f.path..' not saved as a preset: '..tostring(why))
            end
        end
    end

    -------------------------------------------------------------------------------------------------- import --
    -- A preset file from anywhere: the Windows open-file dialog, then the import job (checked, copied into the shared
    -- folder, opened in the list).
    function App:preset_file_pick()
        if self.pf_picking then self:toast(L('The Windows file dialog is open (it may be behind the game)'),C.dim);return end
        local folder=preset_files.folder()
        local job,why=win.pick_file({title=L('Choose a preset file'),
            filter=L('HD2R Editor presets')..' (*.hd2rpreset.json, *.hd2mod.json)|*.hd2rpreset.json;*.hd2mod.json;*.json|'
                ..L('All files')..' (*.*)|*.*|',folder=folder})
        if not job then
            self:preset_note(Lf('The Windows file dialog did not open (%s): put the file in %s and press REFRESH',
                tostring(why),tostring(folder)),C.error,'import: the Windows file dialog did not open: '..tostring(why))
            return
        end
        self.pf_picking=job
        log(self,'import: the Windows file dialog is open')
    end
    function App:preset_file_poll()
        local job=self.pf_picking
        if not job then return end
        local result=job.poll()
        if result==nil then return end
        self.pf_picking=nil
        if not result then
            self:preset_note(L('No file chosen (the dialog was closed)'),C.dim,'import: no file chosen in the Windows dialog')
            return
        end
        self:import_start(result,'copy')
    end
    -- Starts reading a file: mode 'copy' (a file from anywhere: into the shared folder) or 'keep' (into your presets).
    function App:import_start(path,mode)
        if self.pf_job then
            self:toast(Lf('Still importing %s',preset_files.base_name(self.pf_job.path)),C.dim)
            return false
        end
        self.pf_job={job=preset_files.job(path,{wide=win.reader}),path=path,mode=mode}
        self.pf_note=nil
        log(self,'import: reading '..tostring(path)..(mode=='keep'and' (into your presets)'or''))
        return true
    end
    -- One frame of import work (also while the window is closed): the dialog, then the job.
    function App:import_tick(seconds)
        self:preset_file_poll()
        local j=self.pf_job
        if not j then return end
        local ok,finished=pcall(j.job.step,j.job,seconds or M.JOB_SECONDS)
        if not ok then j.job:fail('the reader stopped: '..tostring(finished));finished=true end
        if not finished then return end
        self.pf_job=nil
        local okf,err=pcall(self.import_finish,self,j)
        if not okf then
            self:preset_note(Lf('Not imported: %s',tostring(err)),C.error,'import failed: '..j.path..': '..tostring(err))
        end
    end
    function App:background_tick()self:import_tick(M.JOB_SECONDS)end
    -- The text of the import running now ('Importing x: decoding 45%'), or nil.
    function App:import_progress()
        local j=self.pf_job
        if not j then return nil end
        local phase=({reading=L('reading'),decoding=L('decoding'),checking=L('checking the fields')})[j.job.phase]
            or j.job.phase
        return Lf('Importing %s: %s %d%%',preset_files.base_name(j.path),phase,math.floor((j.job.progress or 0)*100)),
            j.job.progress or 0
    end
    local function skipped_text(n)
        if n<=0 then return''end
        return n==1 and L(', 1 unreadable field skipped')or Lf(', %d unreadable fields skipped',n)
    end
    -- A preset read by a job: copied into the shared folder, or kept with your presets.
    function App:import_finish(j)
        local job=j.job
        local data=job.extra and job.extra.modbuilder
        if not job.preset and data then return self:import_modbuilder(j,data)end
        if not job.preset then
            self:preset_note(Lf('Not imported: %s',tostring(job.why)),C.error,
                'import failed: '..j.path..': '..tostring(job.why))
            return
        end
        local p=job.preset
        local skipped=p.skipped>0 and(', '..p.skipped..' unreadable fields skipped (first: '
            ..table.concat(p.skipped_keys,', ')..')')or''
        if j.mode=='keep'then return self:import_keep(j.path,p.name,p.values,p.icon,p.count,p.skipped,skipped)end
        local folder=preset_files.folder()
        if not folder then
            self:preset_note(Lf('Not imported: %s',L('No Documents folder (%USERPROFILE%)')),C.error,
                'import failed: '..j.path..': no %USERPROFILE%')
            return
        end
        local ok,target=pcall(preset_files.copy_into,j.path,job.text,p,folder,win.mkdir)
        if not ok then
            self:preset_note(Lf('Not imported: %s',tostring(target)),C.error,'import failed: '..j.path..': '..tostring(target))
            return
        end
        self:open_shared_file(target)
        -- (the file just read: shown as it is, not read again)
        self.pf_open,self.pf_key={preset=p},target..'@'..tostring(#job.text)
        self:preset_note(Lf('Imported %s: %d fields%s. LOAD stages them; SAVE AS PRESET keeps them.',p.name,p.count,
            skipped_text(p.skipped)),p.skipped>0 and C.pending or C.ok,
            'import: '..j.path..': the preset "'..p.name..'", '..p.count..' fields'..skipped..' -> '..target)
    end
    -- Into your presets (a shared file's IMPORT SELECTED).
    function App:import_keep(path,name,values,icon,count,skipped_n,skipped)
        local saved=self.presets:unique_name(name)
        local ok,why=self.presets:save(saved,values,icon)
        if not ok then
            self:preset_note(Lf('Not imported: %s',tostring(why)),C.error,'import failed: '..path..': '..tostring(why))
            return
        end
        self:select_preset(saved)
        self:preset_note(Lf('Imported %s into your presets: %d fields%s',saved,count,skipped_text(skipped_n)),
            skipped_n>0 and C.pending or C.ok,'import: '..path..': saved as the preset "'..saved..'", '..count..' fields'
            ..(skipped or''))
    end
    -- A ModBuilder project (project.hd2mod.json): the edits the editor can take, as a preset.
    function App:import_modbuilder(j,project)
        local ok,items=pcall(modbuilder.items,self.catalog,project)
        if not ok then
            self:preset_note(Lf('Not imported: %s',tostring(items)),C.error,
                'import failed: '..j.path..': the ModBuilder project could not be read: '..tostring(items))
            return
        end
        local values,labels,n,refused,first={},{},0,0,{}
        for _,it in ipairs(items)do
            local stored
            if it.row and not it.why then stored=catalog_module.encode(it.row,it.value)end
            if stored~=nil then
                values[it.row.key]=stored
                labels[it.row.key]=it.row.object.name..' · '..it.row.label
                n=n+1
            else
                refused=refused+1
                if#first<3 then first[#first+1]=tostring(it.label)..' ('..tostring(it.why)..')'end
            end
        end
        local name=util.utf8_cut(tostring(project.displayName or preset_files.base_name(j.path)):gsub('[%c]',''),40)
        local refused_log=refused>0 and(', '..refused..' the editor cannot take (first: '..table.concat(first,'; ')..')')or''
        if n==0 then
            self:preset_note(Lf('Not imported: none of the %d edits of the ModBuilder project %s can be taken by the editor',
                #items,name),C.error,'import failed: '..j.path..': ModBuilder project "'..name..'": no edit the editor can take'
                ..refused_log)
            return
        end
        if j.mode=='keep'then return self:import_keep(j.path,name,values,nil,n,refused,refused_log)end
        local folder=preset_files.folder()
        local okw,target=pcall(preset_files.save,folder,name,values,labels,
            {editor=self.ctx.version,runtime=project.sdkVersion},win.mkdir)
        if not okw then
            self:preset_note(Lf('Not imported: %s',tostring(target)),C.error,'import failed: '..j.path..': '..tostring(target))
            return
        end
        self:open_shared_file(target)
        self:preset_note(Lf('Converted the ModBuilder project %s: %d of %d edits as a preset file (%d the editor cannot take)',
            name,n,#items,refused),refused>0 and C.pending or C.ok,
            'import: '..j.path..': ModBuilder project "'..name..'": '..n..' of '..#items..' edits as a preset file'
            ..refused_log..' -> '..target)
    end
    -- Lists the folder again, opens the shared files section and selects a file there.
    function App:open_shared_file(path)
        self.pf_list,self.pe_list=nil,nil
        self:preset_section_set('files',true)
        local i=self:preset_index_where(function(e)return e.kind=='file'and e.file.path:lower()==path:lower()end)
        if i then self.preset_index,self.preset_action,self.detail_scroll=i,1,0 end
    end
    -- The import page's files: the one picked there (by path), or the first.
    function App:import_pick()
        local files=self:preset_files()
        for i,f in ipairs(files)do if f.path==self.pf_pick then return f,i end end
        return files[1],1
    end
    function App:import_action_run(index)
        local a=IMPORT_ACTIONS[index]
        if a=='CHOOSE A FILE...'then self:preset_file_pick()
        elseif a=='IMPORT SELECTED'then
            local f=self:import_pick()
            if not f then
                self:preset_note(Lf('No preset files in %s yet',tostring(preset_files.folder())),C.dim)
                return
            end
            self:import_start(f.path,'keep')
        elseif a=='REFRESH'then self:preset_files_refresh()
        else
            local folder=preset_files.folder()
            if folder then win.mkdir(folder)end
            local ok,why=win.open(folder or'')
            if not ok then self:toast(Lf('Could not open it: %s',tostring(why)),C.error)end
        end
    end

    -------------------------------------------------------------------------------------------------- icons --
    -- The category colour of each stratagem by name (for a preset icon drawn like the stratagem's own).
    function App:icon_tone(name)
        if not self.icon_tones then
            self.icon_tones={}
            for _,category in ipairs(ICON_CATEGORIES)do
                for _,o in ipairs((self.catalog:objects(category)))do
                    local key=o.stratagem or o.name
                    if key and self.icon_tones[key]==nil then self.icon_tones[key]=o.tone or false end
                end
            end
        end
        return self.icon_tones[name]or nil
    end
    -- A preset icon (preset_files.icon) in a square; one this build or Runtime cannot draw shows as a plain square.
    function App:draw_preset_icon(icon,x,y,size,z)
        if type(icon)~='table'then return false end
        z=z or 4
        if icon.kind=='picture'then
            local layers=self.ctx.preset_icons and self.ctx.preset_icons[icon.name]
            if layers and type(self.canvas.d.image)=='function'then
                for _,layer in ipairs(layers)do self.canvas:image(layer.handle,x,y,size,size,{colours=layer.colours,z=z})end
                return true
            end
        elseif icon.kind=='stratagem'then
            if self:draw_icon({key='st|'..icon.name,name=icon.name,stratagem=icon.name,tone=self:icon_tone(icon.name)},
                x,y,size,z)then return true end
        elseif icon.kind=='booster'then
            if self:draw_icon({key='bo|'..icon.name,name=icon.name},x,y,size,z)then return true end
        end
        self.canvas:rect(x+size*0.2,y+size*0.2,size*0.6,size*0.6,C.line_strong,z)
        return true
    end
    -- The icons a preset can take: none, the game's stratagem and booster icons, the pictures built into the editor.
    function App:icon_choices()
        local items={{value=false,label='No icon'}}
        local icons=self.ctx.icons
        for _,kind in ipairs({{list='stratagems',kind='stratagem',sub='Stratagem'},{list='boosters',kind='booster',sub='Booster'}})do
            local names=util.sorted_keys(icons and icons[kind.list]or{},util.natural_less)
            for _,name in ipairs(names)do
                local value={kind=kind.kind,name=name}
                items[#items+1]={value=value,label=name,sub=kind.sub,icon=value}
            end
        end
        local pictures=self.ctx.preset_icons or{}
        for _,name in ipairs(util.sorted_keys(pictures,util.natural_less))do
            local value={kind='picture',name=name}
            items[#items+1]={value=value,label=name,sub='Picture built into this editor',icon=value}
        end
        return items
    end
    -- The icon picker for a saved preset ({preset = name}) or a shared file ({file = path}).
    function App:open_icon_picker(target,current,name)
        local items=self:icon_choices()
        self:open_list_picker({title=L('PRESET ICON'),subtitle=name,items=items,current=current or false,
            note={L('Game icons need HD2Runtime\'s game icons; pictures from your PC cannot be loaded while the game runs'),
                L('(HD2Runtime draws only images built into a mod). Your own: tools/preset_icons.py, then build the editor.')},
            on_choose=function(value)self:set_preset_icon(target,value or nil,name)end})
    end
    function App:set_preset_icon(target,icon,name)
        local ok,why
        if target.preset then ok,why=self.presets:set_icon(target.preset,icon)
        else
            ok,why=preset_files.set_icon(target.file,icon)
            self.pf_icons,self.pf_key=nil,nil
        end
        if ok then
            self:toast(icon and Lf('Icon of %s: %s',name,L(icon.name))or Lf('Icon of %s removed',name),C.ok)
        else
            self:preset_note(Lf('Icon not changed: %s',tostring(why)),C.error,
                'the icon of '..tostring(name)..' was not changed: '..tostring(why))
        end
    end

    ---------------------------------------------------------------------------------------- ModBuilder projects --
    -- ModBuilder's library (editor/modbuilder.lua), read when the Presets tab first lists it and on REFRESH.
    function App:mb_projects()
        if not self.mb_list then
            local list,why=modbuilder.projects()
            self.mb_list,self.mb_error=list or{},why
        end
        return self.mb_list
    end
    -- A project's edits, read once per saved version: {items, error}.
    function App:mb_open_project(p)
        local key=p.id..'@'..p.modified
        if self.mb_key~=key then
            local project,why=modbuilder.read(p.id)
            local open={items={},error=project==nil and tostring(why)or nil}
            if project then
                local ok,items=pcall(modbuilder.items,self.catalog,project)
                if ok then open.items=items else open.error=tostring(items)end
            end
            if open.error then log(self,'ModBuilder project '..tostring(p.name)..' not read: '..open.error)end
            self.mb_open,self.mb_key,self.mb_scroll=open,key,0
        end
        return self.mb_open
    end
    function App:mb_select(open,on)
        for _,it in ipairs(open.items)do if it.row and not it.why then it.selected=on end end
    end
    -- Stages the chosen edits like any other change (Apply writes them).
    function App:mb_stage(open,name)
        local n,failed=0,0
        local chosen={}
        for _,it in ipairs(open.items)do
            if it.selected and it.row and not it.why then chosen[#chosen+1]=it end
        end
        -- (status slot 1 before slot 2: the slots fill in order)
        for _,it in ipairs(slot_order(chosen,function(x)return x.row end))do
            if self:stage_value(it.row,it.value)then n=n+1 else failed=failed+1 end
        end
        if n==0 and failed==0 then self:toast(L('Nothing chosen to stage'),C.dim);return end
        self:toast(Lf('Staged %d values from %s. Press Apply.',n,name)..(failed>0 and(' '..Lf('%d refused',failed))or''),
            failed>0 and C.pending or C.ok)
        log(self,'ModBuilder project '..tostring(name)..': staged '..n..' values'..(failed>0 and(', '..failed..' refused')or''))
        self:sound('click')
    end
    function App:mb_action_run(index,p)
        local open=self:mb_open_project(p)
        local a=MB_ACTIONS[index]
        if a=='STAGE CHOSEN'then self:mb_stage(open,p.name)
        elseif a=='CHOOSE ALL'then self:mb_select(open,true)
        else self:mb_select(open,false)end
    end

    -------------------------------------------------------------------------------------------------- the list --
    -- Whether a section ('files' or 'mb') is open: this session's choice, the saved one, else the default (shared
    -- files open; ModBuilder projects closed past MB_COLLAPSED_PAST).
    function App:preset_section_open(which)
        self.pe_open=self.pe_open or{}
        if self.pe_open[which]~=nil then return self.pe_open[which]end
        local saved=self.presets:setting(which=='files'and'presets_files_open'or'presets_mb_open',nil)
        if saved~=nil then return saved==true end
        if which=='mb'then return#self:mb_projects()<=M.MB_COLLAPSED_PAST end
        return true
    end
    function App:preset_section_set(which,open)
        self.pe_open=self.pe_open or{}
        if self:preset_section_open(which)==open then return end
        self.pe_open[which]=open
        self.presets:set_setting(which=='files'and'presets_files_open'or'presets_mb_open',open)
        self.pe_list=nil
    end
    -- Opens or closes a section; the selection stays on its header.
    function App:preset_section_toggle(which)
        self:preset_section_set(which,not self:preset_section_open(which))
        self.preset_index=self:preset_index_of(which=='files'and'file_header'or'mb_header')or self.preset_index
        self:sound('click')
    end
    -- The Presets list, built again when a list or a section changes.
    function App:preset_entries()
        local presets,files,projects=self.presets:list(),self:preset_files(),self:mb_projects()
        local fo,mo=self:preset_section_open('files'),self:preset_section_open('mb')
        if not self.pe_list or self.pe_presets~=presets or self.pe_files~=files or self.pe_projects~=projects
                or self.pe_fo~=fo or self.pe_mo~=mo then
            local out={{kind='new'},{kind='import'}}
            for _,p in ipairs(presets)do out[#out+1]={kind='preset',preset=p}end
            out[#out+1]={kind='file_header',open=fo}
            if fo then
                if#files==0 then out[#out+1]={kind='file_empty'}end
                for _,f in ipairs(files)do out[#out+1]={kind='file',file=f}end
            end
            out[#out+1]={kind='mb_header',open=mo}
            if mo then for _,p in ipairs(projects)do out[#out+1]={kind='mb',project=p}end end
            self.pe_list,self.pe_presets,self.pe_files,self.pe_projects,self.pe_fo,self.pe_mo=out,presets,files,projects,fo,mo
        end
        return self.pe_list
    end
    function App:preset_entry(i)return self:preset_entries()[i]or{kind='new'}end
    function App:preset_count()return#self:preset_entries()end
    local function actions_of(kind)
        return(kind=='preset'and PRESET_ACTIONS)or(kind=='file'and FILE_ACTIONS)or(kind=='mb'and MB_ACTIONS)
            or(kind=='import'and IMPORT_ACTIONS)or{}
    end
    -- Up and down pass over rows that only explain (the empty folder's hint).
    function App:preset_move(d)
        local entries=self:preset_entries()
        local i=clamp_index(self.preset_index,#entries)
        repeat i=i+d until i<1 or i>#entries or not PASSED[entries[i].kind]
        if i>=1 and i<=#entries then self.preset_index=i end
    end
    function App:handle_presets_keys(f)
        local k=f.keys
        if k.UP then self:preset_move(-1)end
        if k.DOWN then self:preset_move(1)end
        if k.PAGEUP then for _=1,10 do self:preset_move(-1)end end
        if k.PAGEDOWN then for _=1,10 do self:preset_move(1)end end
        local entry=self:preset_entry(self.preset_index)
        local actions=actions_of(entry.kind)
        if k.LEFT then self.preset_action=clamp_index(self.preset_action-1,#actions)end
        if k.RIGHT then self.preset_action=clamp_index(self.preset_action+1,#actions)end
        self.preset_action=clamp_index(self.preset_action,#actions)
        if k.INSERT then self:new_preset()end
        if k.ENTER then
            if entry.kind=='new'then self:new_preset()
            elseif entry.kind=='import'then self:import_action_run(self.preset_action)
            elseif entry.kind=='preset'then self:preset_action_run(self.preset_action,entry.preset)
            elseif entry.kind=='mb'then self:mb_action_run(self.preset_action,entry.project)
            elseif entry.kind=='file'then self:preset_file_action_run(self.preset_action,entry.file)
            elseif entry.kind=='file_header'then self:preset_section_toggle('files')
            elseif entry.kind=='mb_header'then self:preset_section_toggle('mb')end
        end
        if k.DELETE and entry.kind=='preset'then self:ask('delete_preset',entry.preset.name)end
    end
    -- The status line's text on this tab: the import running, else a recent result, else the tab's note.
    function App:presets_status()
        local progress=self:import_progress()
        if progress then return progress,C.gold end
        if self.pf_picking then return L('Choose a file in the Windows dialog (it may be behind the game)'),C.gold end
        -- (once the toast saying the same has gone)
        local note=self.pf_note
        local toast=self.toast_msg and self.toast_msg.text
        if note and toast~=note.text and self.time-note.time<20 then return note.text,note.colour end
        return L('Presets store field values by name; loading one stages them as pending changes.'),C.faint
    end

    local function header_row(self,cv,x,y,w,rh,label,count,open,error)
        local cy=y+rh/2
        cv:text(open and'↓'or'→',x+22,cy,{size=SZ.small,colour=C.gold,font='title'})
        cv:text(label,x+42,cy,{size=SZ.tab,font='title',colour=C.faint,max=w-140})
        cv:text(error and'!'or tostring(count),x+w-22,cy,{size=SZ.small,colour=error and C.error or C.faint,align='right'})
    end
    function App:draw_presets(y0,h)
        local cv=self.canvas
        local P=theme.panel
        local n=self:preset_count()
        self.preset_index=clamp_index(self.preset_index,n)
        cv:rect(0,y0,PRESETS_W,h,C.panel_alt,1)
        cv:rect(PRESETS_W-1,y0,1,h,C.line,2)
        cv:text(L('PRESETS'),18,y0+20,{size=SZ.heading,font='title',colour=C.faint})
        if not self.presets:available()then
            cv:text(L('Saved data needs a newer HD2Runtime (hd2.store).'),18,y0+52,{size=SZ.small,colour=C.error,max=PRESETS_W-36})
            return
        end
        self.preset_actions=self.preset_actions or{}
        local bottom=y0+h-118
        self:list({x=0,y=y0+36,w=PRESETS_W-1,h=bottom-y0-40,count=n,row_h=48,selected=self.preset_index,
            scroll_key='preset_scroll',focused=true,actions=self.preset_actions,
            click=function(i)
                local e=self:preset_entry(i)
                if e.kind=='new'and self.preset_index==i then self:new_preset()end
                if e.kind=='file_empty'then i=self:preset_index_of('import')or i end
                local was=self.preset_index
                self.preset_index=i
                if was~=i then self.preset_action,self.detail_scroll=1,0 end
                if e.kind=='file_header'then self:preset_section_toggle('files')
                elseif e.kind=='mb_header'then self:preset_section_toggle('mb')end
            end,
            draw=function(i,x,y,w,rh)
                local entry=self:preset_entry(i)
                local selected=i==self.preset_index
                if entry.kind~='file_empty'then
                    if selected then cv:rect(x+8,y+2,w-16,rh-4,C.select,2);cv:rect(x+8,y+2,3,rh-4,C.gold,3)
                    elseif self.hover==self.preset_actions[i]then cv:rect(x+8,y+2,w-16,rh-4,C.hover,2)end
                end
                local kind=entry.kind
                if kind=='new'then
                    if self.rename and self.rename.create then
                        local tw=cv:text(self.rename.text,x+22,y+rh/2,{size=SZ.label,colour=C.text,max=w-60})
                        if math.floor(self.time*2)%2==0 then cv:rect(x+24+tw,y+14,2,20,C.gold,6)end
                    else
                        cv:text(L('+  NEW PRESET FROM CURRENT VALUES'),x+22,y+rh/2,{size=SZ.tab,font='title',colour=C.gold,max=w-44})
                    end
                elseif kind=='import'then
                    local progress,fraction=self:import_progress()
                    if progress then
                        cv:text(progress,x+22,y+rh/2,{size=SZ.small,colour=C.gold,max=w-44})
                        cv:rect(x+22,y+rh-9,(w-44),2,C.line,3)
                        cv:rect(x+22,y+rh-9,(w-44)*fraction,2,C.gold,4)
                    else
                        cv:text(L('↓  IMPORT PRESET...'),x+22,y+rh/2,{size=SZ.tab,font='title',colour=C.gold,max=w-44})
                    end
                elseif kind=='file_header'then
                    header_row(self,cv,x,y,w,rh,L('SHARED PRESET FILES'),#self:preset_files(),entry.open,self.pf_list_error)
                elseif kind=='file_empty'then
                    cv:text(self.pf_list_error and Lf('The folder cannot be listed: %s',self.pf_list_error)
                        or L('None yet: drop .hd2rpreset.json files into'),x+42,y+15,
                        {size=SZ.tiny,colour=self.pf_list_error and C.error or C.faint,max=w-64})
                    cv:text(tostring(preset_files.folder()or''),x+42,y+33,{size=SZ.tiny,colour=C.dim,max=w-64})
                elseif kind=='file'then
                    local f=entry.file
                    self:draw_preset_icon(self:preset_file_icon(f),x+22,y+8,32)
                    cv:text(f.name,x+64,y+17,{size=SZ.label,colour=selected and C.text or C.dim,max=w-86})
                    cv:text(L('file')..'   '..string.format('%.1f KB',(f.size or 0)/1024),x+64,y+35,
                        {size=SZ.tiny,colour=C.faint,max=w-86})
                elseif kind=='mb_header'then
                    header_row(self,cv,x,y,w,rh,L('MODBUILDER PROJECTS'),#self:mb_projects(),entry.open,self.mb_error)
                elseif kind=='mb'then
                    local mp=entry.project
                    cv:text(mp.name,x+22,y+17,{size=SZ.label,colour=selected and C.text or C.dim,max=w-60})
                    cv:text(tostring(mp.resource or'')..'   '..mp.modified:sub(1,10),x+22,y+35,{size=SZ.tiny,colour=C.faint,max=w-44})
                else
                    local p=entry.preset
                    self:draw_preset_icon(p.icon,x+22,y+8,32)
                    if self.rename and not self.rename.create and self.rename.old==p.name then
                        local tw=cv:text(self.rename.text,x+64,y+17,{size=SZ.label,colour=C.text,max=w-100})
                        if math.floor(self.time*2)%2==0 then cv:rect(x+66+tw,y+7,2,20,C.gold,6)end
                    else
                        cv:text(p.name,x+64,y+17,{size=SZ.label,colour=selected and C.text or C.dim,max=w-86})
                    end
                    local when=p.created and p.created>0 and os.date and os.date('%Y-%m-%d %H:%M',p.created)or''
                    cv:text((p.count==1 and L('1 field')or Lf('%d fields',p.count))..(when~=''and('   '..when)or''),
                        x+64,y+35,{size=SZ.tiny,colour=C.faint,max=w-86})
                end
            end})
        -- settings
        local sy=bottom+8
        cv:rect(0,sy-8,PRESETS_W-1,1,C.line,2)
        local restore=self.presets:setting('restore_session',true)
        self.toggle_restore=self.toggle_restore or{click=function()
            self.presets:set_setting('restore_session',not self.presets:setting('restore_session',true))end}
        local tx,ty=18,sy+14
        cv:rect(tx,ty-9,34,18,restore and C.gold or C.line_strong,3)
        cv:rect(restore and tx+18 or tx+2,ty-7,14,14,restore and C.inverse or C.dim,4)
        cv:text(L('Restore my last applied values when the game starts'),tx+46,ty,{size=SZ.small,colour=C.dim,max=PRESETS_W-80})
        cv:hit(tx,ty-12,PRESETS_W-36,24,self.toggle_restore)
        -- the cursor capture (HD2Runtime r50, experimental)
        if self.ctx.set_free_cursor then
            local free=self.presets:setting('free_cursor',true)
            self.toggle_cursor=self.toggle_cursor or{click=function()
                local on=not self.presets:setting('free_cursor',true)
                self.presets:set_setting('free_cursor',on)
                self.ctx.set_free_cursor(on)
            end}
            local cy2=ty+28
            cv:rect(tx,cy2-9,34,18,free and C.gold or C.line_strong,3)
            cv:rect(free and tx+18 or tx+2,cy2-7,14,14,free and C.inverse or C.dim,4)
            cv:text(L('Free the mouse from the camera while open (experimental)'),tx+46,cy2,{size=SZ.small,colour=C.dim,max=PRESETS_W-80})
            cv:hit(tx,cy2-12,PRESETS_W-36,24,self.toggle_cursor)
        end
        cv:text(Lf('Open the editor with %s. Edits apply live through HD2Runtime\'s guarded writes.',self:hotkey()),
            18,sy+70,{size=SZ.tiny,colour=C.faint,max=PRESETS_W-36})
        -- detail
        local x0=PRESETS_W
        local w=P.w-x0
        cv:rect(x0,y0,w,h,C.panel,1)
        local entry=self:preset_entry(self.preset_index)
        if entry.kind=='new'then
            local values=self:current_values()
            cv:text(L('NEW PRESET'),x0+20,y0+24,{size=20,font='title',colour=C.text})
            cv:text(Lf('%d fields would be saved: every applied editor value and every pending change.',util.count(values)),
                x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
            self.btn_new=self.btn_new or{click=function()self:new_preset()end}
            button(self,L('SAVE AS NEW PRESET'),x0+20,y0+72,230,34,next(values)and'primary'or'disabled',self.btn_new)
            self:draw_value_list(values,x0,y0+124,w,y0+h-y0-128,'new|'..math.floor(self.time*2))
            return
        end
        if entry.kind=='import'then return self:draw_import_page(x0,y0,w,h)end
        if entry.kind=='file_header'or entry.kind=='file_empty'then return self:draw_files_header(x0,y0,w,h)end
        if entry.kind=='file'then return self:draw_preset_file(entry.file,x0,y0,w,h)end
        if entry.kind=='mb_header'then return self:draw_mb_header(x0,y0,w,h)end
        if entry.kind=='mb'then return self:draw_mb_project(entry.project,x0,y0,w,h)end
        local p=entry.preset
        local tx=x0+20
        if p.icon then self:draw_preset_icon(p.icon,x0+20,y0+12,46);tx=x0+78 end
        cv:text(p.name,tx,y0+24,{size=20,font='title',colour=C.text,max=x0+w-20-tx})
        cv:text(Lf('%d fields',p.count),tx,y0+47,{size=SZ.small,colour=C.faint})
        self:draw_action_buttons('preset_btns',PRESET_ACTIONS,x0+20,y0+72,function(index)
            local e=self:preset_entry(self.preset_index)
            if e.kind=='preset'then self:preset_action_run(index,e.preset)end
        end)
        if not p.values then
            p.values={}
            for _,item in ipairs(p.fields or{})do p.values[item.k]=item.v end
        end
        self:draw_value_list(p.values,x0,y0+124,w,y0+h-y0-128)
    end
    -- A row of action buttons (the first primary, DELETE red); the keyboard's choice underlined.
    function App:draw_action_buttons(key,labels,x,y,run,styles)
        local cv=self.canvas
        self[key]=self[key]or{}
        local bx=x
        for i,label in ipairs(labels)do
            local action=self[key][i]
            if not action then
                local index=i
                action={click=function()self.preset_action=index;run(index)end}
                self[key][i]=action
            end
            local text=styles and styles.text and styles.text(i,label)or L(label)
            local bw=cv:measure(text,SZ.tab,'title')+40
            local style=styles and styles.style and styles.style(i,label)
                or(i==1 and'primary')or(label=='DELETE'and'danger')or'normal'
            button(self,text,bx,y,bw,34,style,action)
            if i==self.preset_action then cv:rect(bx,y+36,bw,2,C.gold,5)end
            bx=bx+bw+10
        end
    end
    function App:draw_import_page(x0,y0,w,h)
        local cv=self.canvas
        local folder=preset_files.folder()
        cv:text(L('IMPORT PRESET'),x0+20,y0+24,{size=20,font='title',colour=C.text})
        cv:text(L('Preset files (.hd2rpreset.json) and ModBuilder projects (project.hd2mod.json) are read from this folder:'),
            x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
        cv:text(tostring(folder or L('(no %USERPROFILE%)')),x0+20,y0+68,{size=SZ.small,colour=C.text,max=w-40})
        self:draw_action_buttons('import_btns',IMPORT_ACTIONS,x0+20,y0+88,function(index)self:import_action_run(index)end,
            {text=function(i,label)
                if i==1 and self.pf_picking then return L('CHOOSE IN THE WINDOWS DIALOG...')end
                return L(label)
            end,style=function(i)
                if i==1 then return'primary'end
                if i==2 then return(self:import_pick()and not self.pf_job)and'normal'or'disabled'end
                return'normal'
            end})
        local lines={
            L('CHOOSE A FILE... picks a file anywhere: it is checked, copied into the folder and opened here.'),
            L('A file put into the folder yourself appears under SHARED PRESET FILES (REFRESH lists the folder now).'),
            L('IMPORT SELECTED adds the file chosen below to your presets.')}
        for i,line in ipairs(lines)do
            cv:text(line,x0+20,y0+148+(i-1)*20,{size=SZ.small,colour=C.faint,max=w-40})
        end
        -- the import running, else the last result
        local progress,fraction=self:import_progress()
        local ry=y0+214
        if progress then
            cv:text(progress,x0+20,ry,{size=SZ.small,colour=C.gold,max=w-40})
            cv:rect(x0+20,ry+12,w-40,3,C.line,3)
            cv:rect(x0+20,ry+12,(w-40)*fraction,3,C.gold,4)
        elseif self.pf_note then
            cv:text(self.pf_note.text,x0+20,ry,{size=SZ.small,colour=self.pf_note.colour,max=w-40})
        end
        -- the folder's files
        local files=self:preset_files()
        local _,picked=self:import_pick()
        local ly=y0+240
        cv:rect(x0,ly,w,22,C.header,2)
        cv:text(Lf('FILES IN THE FOLDER  %d',#files),x0+18,ly+11,{size=SZ.tiny,font='title',colour=C.faint})
        if self.pf_list_error then
            cv:text(Lf('The folder cannot be listed: %s',self.pf_list_error),x0+20,ly+40,{size=SZ.small,colour=C.error,max=w-40})
            return
        end
        if#files==0 then
            cv:text(L('No preset files yet. Drop one into the folder above, then press REFRESH.'),x0+20,ly+40,
                {size=SZ.small,colour=C.faint,max=w-40})
            return
        end
        self.import_file_actions=self.import_file_actions or{}
        self:list({x=x0,y=ly+24,w=w,h=y0+h-ly-28,count=#files,row_h=34,selected=picked,scroll_key='import_scroll',
            focused=false,actions=self.import_file_actions,
            click=function(i)local f=self:preset_files()[i];if f then self.pf_pick=f.path end end,
            draw=function(i,x,ry,lw,rh)
                local f=files[i]
                local cy=ry+rh/2
                if i==picked then cv:rect(x+8,ry+2,lw-16,rh-4,C.select,2);cv:rect(x+8,ry+2,3,rh-4,C.gold,3)end
                self:draw_preset_icon(self:preset_file_icon(f),x+20,ry+5,24)
                cv:text(f.file or f.name,x+52,cy,{size=SZ.small,colour=i==picked and C.text or C.dim,max=lw-180})
                cv:text(string.format('%.1f KB',(f.size or 0)/1024),x+lw-18,cy,{size=SZ.tiny,colour=C.faint,align='right'})
            end})
    end
    function App:draw_files_header(x0,y0,w,h)
        local cv=self.canvas
        cv:text(L('SHARED PRESET FILES'),x0+20,y0+24,{size=20,font='title',colour=C.text})
        local lines={L('Presets as files, to share with other players. The editor lists this folder:'),
            tostring(preset_files.folder()or L('(no %USERPROFILE%)')),'',
            L('SHARE on a preset writes it here. Put a file someone sent you here (or use IMPORT A FILE) and it shows up.'),
            L('Pick a file to see its values; LOAD stages them, SAVE AS PRESET keeps them with your presets.'),
            L('Click this header (or press Enter) to show or hide the files.')}
        for i,line in ipairs(lines)do
            cv:text(line,x0+20,y0+56+(i-1)*22,{size=SZ.small,colour=i==2 and C.dim or C.faint,max=w-40})
        end
        if self.pf_list_error then
            cv:text(Lf('The folder cannot be listed: %s',self.pf_list_error),x0+20,y0+192,{size=SZ.small,colour=C.error,max=w-40})
        end
        self.btn_pf_import=self.btn_pf_import or{click=function()self:preset_file_pick()end}
        self.btn_pf_open=self.btn_pf_open or{click=function()self:import_action_run(4)end}
        self.btn_pf_refresh=self.btn_pf_refresh or{click=function()self:preset_files_refresh()end}
        button(self,self.pf_picking and L('CHOOSE IN THE WINDOWS DIALOG...')or L('IMPORT A FILE'),x0+20,y0+222,300,34,
            'primary',self.btn_pf_import)
        button(self,L('OPEN THE FOLDER'),x0+332,y0+222,220,34,'normal',self.btn_pf_open)
        button(self,L('REFRESH'),x0+564,y0+222,160,34,'normal',self.btn_pf_refresh)
    end
    function App:draw_preset_file(f,x0,y0,w,h)
        local cv=self.canvas
        local open=self:preset_file_open(f)
        if open.reading then
            cv:text(f.name,x0+20,y0+24,{size=20,font='title',colour=C.text,max=w-40})
            local fraction=open.reading.progress or 0
            cv:text(Lf('Reading %s: %d%%',f.file or f.name,math.floor(fraction*100)),x0+20,y0+47,
                {size=SZ.small,colour=C.gold,max=w-40})
            cv:rect(x0+20,y0+62,w-40,3,C.line,3)
            cv:rect(x0+20,y0+62,(w-40)*fraction,3,C.gold,4)
            return
        end
        local p=open.preset
        local tx=x0+20
        local icon=p and p.icon
        if icon then self:draw_preset_icon(icon,x0+20,y0+12,46);tx=x0+78 end
        cv:text(p and p.name or f.name,tx,y0+24,{size=20,font='title',colour=C.text,max=x0+w-20-tx})
        if not p then
            cv:text(Lf('Could not read this file: %s',tostring(open.error)),x0+20,y0+47,{size=SZ.small,colour=C.error,max=w-40})
            return
        end
        local info=(f.file or f.name)..'   '..Lf('%d fields',p.count)
            ..(p.editor and('   '..Lf('from editor %s',tostring(p.editor)))or'')
            ..(p.skipped>0 and('   '..Lf('%d unreadable fields skipped',p.skipped))or'')
        cv:text(info,tx,y0+47,{size=SZ.small,colour=C.faint,max=x0+w-20-tx})
        self:draw_action_buttons('pf_btns',FILE_ACTIONS,x0+20,y0+72,function(index)
            local e=self:preset_entry(self.preset_index)
            if e.kind=='file'then self:preset_file_action_run(index,e.file)end
        end)
        self:draw_value_list(p.values,x0,y0+124,w,y0+h-y0-128)
    end
    function App:draw_mb_header(x0,y0,w,h)
        local cv=self.canvas
        cv:text(L('MODBUILDER PROJECTS'),x0+20,y0+24,{size=20,font='title',colour=C.text})
        local lines={L('Your HD2Runtime ModBuilder projects, read from its library on this PC:'),
            tostring(modbuilder.root()or L('(no %LOCALAPPDATA%)')),'',
            L('Pick one to see its edits as editor fields, choose which to stage, then Apply.'),
            L('Edits the editor cannot take are listed with the reason (scripts and custom content stay in ModBuilder).'),'',
            L('To send your changes to ModBuilder: Export tab, then SAVE TO MODBUILDER.'),
            L('Click this header (or press Enter) to show or hide the projects.')}
        for i,line in ipairs(lines)do
            cv:text(line,x0+20,y0+56+(i-1)*22,{size=SZ.small,colour=i==2 and C.dim or C.faint,max=w-40})
        end
        if self.mb_error then cv:text(tostring(self.mb_error),x0+20,y0+240,{size=SZ.small,colour=C.error,max=w-40})end
        self.btn_mb_refresh=self.btn_mb_refresh or{click=function()self.mb_list,self.mb_key=nil,nil end}
        button(self,L('REFRESH'),x0+20,y0+268,160,34,'normal',self.btn_mb_refresh)
    end
    function App:draw_mb_project(p,x0,y0,w,h)
        local cv=self.canvas
        local open=self:mb_open_project(p)
        local ok_n,chosen=0,0
        for _,it in ipairs(open.items)do
            if it.row and not it.why then ok_n=ok_n+1 end
            if it.selected and it.row and not it.why then chosen=chosen+1 end
        end
        cv:text(p.name,x0+20,y0+24,{size=20,font='title',colour=C.text,max=w-40})
        cv:text(Lf('%s   ModBuilder project, SDK %s   %d of %d edits can be staged',tostring(p.resource or''),
            tostring(p.sdk or'?'),ok_n,#open.items),x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
        self:draw_action_buttons('mb_btns',MB_ACTIONS,x0+20,y0+72,function(index)
            local e=self:preset_entry(self.preset_index)
            if e.kind=='mb'then self:mb_action_run(index,e.project)end
        end,{text=function(i,label)return i==1 and(L(label)..'  ('..chosen..')')or L(label)end,
            style=function(i)return i==1 and(chosen>0 and'primary'or'disabled')or'normal'end})
        local y=y0+124
        if open.error then
            cv:text(Lf('Could not read this project: %s',open.error),x0+20,y+12,{size=SZ.small,colour=C.error,max=w-40})
            return
        end
        cv:rect(x0,y,w,22,C.header,2)
        cv:text(L('EDIT'),x0+46,y+11,{size=SZ.tiny,font='title',colour=C.faint})
        cv:text(L('VALUE'),x0+w-18,y+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
        self.mb_item_actions=self.mb_item_actions or{}
        self:list({x=x0,y=y+24,w=w,h=y0+h-y-28,count=#open.items,row_h=28,scroll_key='mb_scroll',focused=false,
            actions=self.mb_item_actions,
            click=function(i)
                local it=self.mb_open.items[i]
                if it and it.row and not it.why then it.selected=not it.selected end
            end,
            draw=function(i,x,ry,lw,rh)
                local it=open.items[i]
                local cy=ry+rh/2
                local usable=it.row and not it.why
                if usable then
                    cv:rect(x+18,cy-7,14,14,it.selected and C.gold or C.line_strong,3)
                    if not it.selected then cv:rect(x+20,cy-5,10,10,C.panel,4)end
                end
                local tx=x+46
                if it.row then
                    local nw=cv:text(util.display_name(it.row.object),tx,cy,{size=SZ.small,colour=C.faint,max=(lw-260)*0.45})
                    cv:text(L(it.row.label),tx+12+nw,cy,{size=SZ.small,colour=usable and C.dim or C.faint,max=lw-330-nw})
                else
                    cv:text(L(it.label),tx,cy,{size=SZ.small,colour=C.faint,max=lw-330})
                end
                if usable then
                    cv:text(self:text(it.row,it.value),x+lw-18,cy,{size=SZ.label,colour=C.gold,align='right',max=260})
                else
                    cv:text(L(tostring(it.why)),x+lw-18,cy,{size=SZ.tiny,colour=C.error,align='right',max=300})
                end
            end})
    end
end

return M

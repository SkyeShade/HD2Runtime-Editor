-- Display-only calculations. Inputs are the editor's pending/applied/mod/default values, never new memory reads.
local M={}
M.NOTE='Calculated from the displayed values; not a separate editable field.'
M.COOLING='Normal cooling requires zero wind-up charge and no overheat. Cooling while charging or overheated uses its separate setting.'
local function seconds(amount,rate)
    if type(amount)~='number'or type(rate)~='number'then return 'Unavailable'end
    if amount<=0 then return 0 end
    if rate<=0 then return 'Never'end
    return amount/rate
end
function M.add(object,rows,H)
    local groups,order={},{}
    for _,r in ipairs(rows)do
        local group=(r.group or'')..(r.derived_context and'@'..r.derived_context or'')
        if not groups[group]then groups[group]={_group=r.group,_section=r.derived_context and r.section};order[#order+1]=group end
        groups[group][r.field]=r
        if r.field=='heat.cool_per_second'then r.note=M.COOLING end
        if r.field=='heat.reset_charge_after_shot'then
            r.label='Wind-up again after each shot'
            r.note='On: each shot clears wind-up charge; the next shot must charge again. Off: firing retains charge. This does not reset heat.'
        end
    end
    local additions,remove={},{}
    for _,group in ipairs(order)do
        local fields=groups[group]
        local charge,gain,loss=fields['heat.firing_charge'],fields['heat.charge_gain_per_second'],fields['heat.charge_loss_per_second']
        local function add(id,label,section,calculate,note,old)
            if old then remove[old]=true end
            local r=H.info_row(object,{id=id..'@derived:'..group,label=label,field=id,section=fields._section or section,
                group=fields._group,info=true,reason=note or M.NOTE,note=note or M.NOTE})
            r.labels=nil;r.calculate=calculate;r.vanilla=calculate(function(input)return input.vanilla end)
            additions[#additions+1]=r
        end
        if charge and gain then
            add('heat.warmup','Time to fire','Wind-up',function(value)return seconds(value(charge),value(gain))end,
                'Calculated time to reach firing charge from zero.',fields['heat.warmup'])
        end
        if charge and loss then
            add('heat.charge_decay_time','Charge decay time','Wind-up',function(value)return seconds(value(charge),value(loss))end,
                'Calculated time from full charge to zero after release. Normal cooling waits for zero charge and no overheat.')
        end
        local old=fields['heat.overheat_cooldown']
        if old then
            local capacity,release,rate,prevent=fields['heat.capacity'],fields['heat.overheat_release_threshold'],
                fields['heat.cool_per_second_overheated'],fields['heat.prevent_overheat_cooling']
            add('heat.overheat_cooldown','Cooldown after overheat','Heat',function(value)
                if prevent then local p=value(prevent);if p==true or p==1 then return 'Heatsink change'end end
                if not(capacity and release and rate and prevent)then return 'Depends on cooling settings'end
                local c,r=value(capacity),value(release)
                if type(c)~='number'or type(r)~='number'then return 'Unavailable'end
                return seconds(math.max(0,c-r),value(rate))
            end,'At the overheat threshold, in a neutral climate; excludes wind-up charge decay.',old)
        end
    end
    local result={}
    for _,r in ipairs(rows)do if not remove[r]then result[#result+1]=r end end
    for _,r in ipairs(additions)do result[#result+1]=r end
    return result
end
return M

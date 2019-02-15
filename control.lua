isDebug = false
function _print(msg)
    if isDebug then
        
        game.print({"", msg})
    end
end

function GetMainLocomotive(train)
    if train.valid and train.locomotives and (#train.locomotives.front_movers > 0 or #train.locomotives.back_movers > 0) then
        return train.locomotives.front_movers and train.locomotives.front_movers[1] or train.locomotives.back_movers[1]
    end
end
function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function regEvent()
    -- Event
    local function OnTick(e)
        global.Tick.checkTick = global.Tick.checkTick + 1
        if global.Tick.checkTick > 300 then
            
            _print(#global.stopTrans)
            -- 检查停站的火车的信号
            for stopId, stopTrain in pairs(global.stopTrans) do
                if stopTrain.train.valid then
                    _print("检查停止的火车:"..stopId)
                    checkManual(stopTrain.train)
                else
                    global.stopTrans[stopId] = nil
                end
                
            end
            
            global.Tick.checkTick = 0
        end
        
    end
    
    function creteStop(train)
        
        global.stopTrans[train.id] = {
            train = train,
            manual = false,
            record = 0,
            station = train.station,
            stationName = GetMainLocomotive(train),
            stationId = train.station.unit_number
        }
    end
    
    local waitContion = {type = "circuit", compare_type = "and", condition = {comparator = "≠", first_signal = {type = "virtual", name = "signal-M"}, constant = 1}}
    
    function NewScheduleRecord(train)
        local stopTrain = global.stopTrans[train.id]
        if stopTrain then
            local oldSched = deepcopy(stopTrain.train.schedule)
            local oldRecord = oldSched.records[oldSched.current]
            _print("增加信号条件,当前站:"..oldSched.current)
            local newRecord = {station = oldRecord.station, wait_conditions = {
                
            }}
            stopTrain.record = oldSched.current
            
            local wait_conditions = {}
            local i = 0
            for key, v in pairs(oldRecord.wait_conditions) do
                if i == 0 then
                    table.insert(wait_conditions, v)
                    table.insert(wait_conditions, waitContion)
                elseif v.compare_type == 'or' then
                    table.insert(wait_conditions, v)
                    table.insert(wait_conditions, waitContion)
                else
                    table.insert(wait_conditions, v)
                end
                i = i + 1
            end
            newRecord.wait_conditions = wait_conditions
            oldSched.records[oldSched.current] = newRecord
            local newSched = {current = oldSched.current, records = oldSched.records}
            stopTrain.train.schedule = newSched
        end
        
    end
    
    function isSameCircuit(t1)
        if t1.type == waitContion.type and
            t1.compare_type == waitContion.compare_type and
            t1.condition.first_signal.type == waitContion.condition.first_signal.type and
            t1.condition.first_signal.name == waitContion.condition.first_signal.name then
            return true
        end
    end
    function RemoveScheduleRecord(train)
        local stopTrain = global.stopTrans[train.id]
        if stopTrain then
            local oldSched = deepcopy(stopTrain.train.schedule)
            if not oldSched then
                return
            end
            
            local removeCircuitCondition = oldSched.records[stopTrain.record]
            if not removeCircuitCondition then
                return
            end
            _print("删除信号条件,当前站:"..stopTrain.record)
            local newRecord = {station = removeCircuitCondition.station, wait_conditions = {
            }}
            
            local wait_conditions = {}
            for key, v in pairs(removeCircuitCondition.wait_conditions) do
                if not isSameCircuit(v) then
                    _print(v.type .. " ~~~")
                    table.insert(wait_conditions, v)
                end
            end
            newRecord.wait_conditions = wait_conditions
            oldSched.records[stopTrain.record] = newRecord
            local newSched = {current = oldSched.current, records = oldSched.records}
            stopTrain.train.schedule = newSched
        end
        
    end
    
    function checkManual(train)
        local stopedTrain = global.stopTrans[train.id]
        
        if not stopedTrain then
            return
        end
        if not train.valid then
            global.stopTrans[train.id] = nil
            return
        end
        
        local signals = stopedTrain.station.get_merged_signals()
        local isManual = false
        if signals then
            for _, v in pairs(signals) do
                if v.signal.type == "virtual" and v.signal.name == "signal-M" and v.count == 1 then
                    _print("设置为手动 "..v.count)
                    isManual = true
                end
                
            end
            
            if not stopedTrain.manual and isManual then
                -- 设置为手动
                _print("设置为手动!! ")
                stopedTrain.manual = true
                NewScheduleRecord(stopedTrain.train)
            end
        end
        
        if not isManual and stopedTrain.manual then
            _print("设置为自动!! ")
            RemoveScheduleRecord(stopedTrain.train)
        end
    end
    local function TrainArrives(train)
        _print("火车进入"..train.id)
        
        creteStop(train)
        checkManual(train)
        
    end
    local function TrainLeaves(oldState, train)
        _print("火车离开"..train.id)
        
        local stopedTrain = global.stopTrans[train.id]
        
        if stopedTrain and stopedTrain.manual then
            checkManual(stopedTrain.train)
            global.stopTrans[train.id] = nil
        end
        
    end
    
    function OnTrainStateChanged(event)
        _print("火车状态变化 "..event.old_state .. " --> " ..event.train.state)
        local train = event.train
        if train.state == defines.train_state.wait_station and train.station ~= nil then
            TrainArrives(train)
        elseif event.old_state == defines.train_state.wait_station then
            TrainLeaves(oldState, train)
        end
    end
    script.on_event(defines.events.on_train_changed_state, OnTrainStateChanged)
    script.on_event(defines.events.on_tick, OnTick)
end

script.on_load(function ()
    regEvent()
end)

script.on_init(function()
    if not global.Tick then
        log("tick null")
    end
    
    log("开始")
    -- variable
    global.Tick = global.Tick or {}
    global.Tick.checkTick = global.Tick.checkTick or 0
    global.stopTrans = global.stopTrans or {}
    regEvent()
    
end)


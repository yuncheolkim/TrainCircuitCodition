
isDebug = false
local band = bit32.band
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
                    checkManual(stopTrain.train, 0)
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
            manual = false, -- 这里表示是否有信号
            record = 0,
            signalBit = 0,
            station = train.station,
            stationName = GetMainLocomotive(train),
            stationId = train.station.unit_number
        }
    end
    
    local WaitCondition = {type = "circuit", compare_type = "and", condition = {comparator = "≠", first_signal = {type = "virtual", name = "signal-M"}, constant = 1}}
    local waitConditionOr = {type = "circuit", compare_type = "or", condition = {comparator = "≠", first_signal = {type = "virtual", name = "signal-N"}, constant = 1}}
    
    function NewScheduleRecord(train, signalBit)
        local stopTrain = global.stopTrans[train.id]
        if stopTrain then
            if not stopTrain.train.schedule then
                -- 时刻表为空则返回
                return
            end
            
            local oldSched = deepcopy(stopTrain.train.schedule)
            local oldRecord = oldSched.records[oldSched.current]
            _print("增加信号条件,当前站:"..oldSched.current)
            local newRecord = {station = oldRecord.station, wait_conditions = {}}
            stopTrain.record = oldSched.current
            
            if not oldRecord.wait_conditions then
                return
            end
            local wait_conditions = {}
            local i = 0
            local isM = bit32.band(signalBit, 1) == 1
            local isN = bit32.band(signalBit, 2) == 2
            
            for key, v in pairs(oldRecord.wait_conditions) do
                if not isSameCircuit(v, WaitCondition) and not isSameCircuit(v, waitConditionOr) then
                    
                    if i == 0 then
                        
                        table.insert(wait_conditions, v)
                        if isM then
                            table.insert(wait_conditions, WaitCondition)
                        end
                    elseif v.compare_type == 'or' then
                        table.insert(wait_conditions, v)
                        if isM then
                            table.insert(wait_conditions, WaitCondition)
                        end
                    else
                        table.insert(wait_conditions, v)
                    end
                end
                i = i + 1
            end
            
            if isN then
                table.insert(wait_conditions, waitConditionOr)
            end
            newRecord.wait_conditions = wait_conditions
            oldSched.records[oldSched.current] = newRecord
            local newSched = {current = oldSched.current, records = oldSched.records}
            stopTrain.train.schedule = newSched
        end
        
    end
    
    function isSameCircuit(t1, waitContion)
        if t1.type == waitContion.type and
            t1.compare_type == waitContion.compare_type and
            t1.condition.first_signal.type == waitContion.condition.first_signal.type and
            t1.condition.first_signal.name == waitContion.condition.first_signal.name then
            return true
        end
    end
    function RecalcScheduleRecord(train, signalBit)
        local stopTrain = global.stopTrans[train.id]
        if stopTrain then
            local oldSched = deepcopy(stopTrain.train.schedule)
            if not oldSched then
                return
            end
            
            local removeCircuitCondition = oldSched.records[stopTrain.record]
            if not removeCircuitCondition or not removeCircuitCondition.wait_conditions then
                return
            end
            _print("删除信号条件,当前站:"..stopTrain.record.." "..signalBit)
            local newRecord = {station = removeCircuitCondition.station, wait_conditions = {
            }}
            
            local wait_conditions = {}
            local delM = bit32.band(signalBit, 1) ~= 1
            local delN = bit32.band(signalBit, 2) ~= 2

            for key, v in pairs(removeCircuitCondition.wait_conditions) do

                if not delM and not delN then
                    table.insert(wait_conditions, v)
                elseif delM and not delN and not isSameCircuit(v, WaitCondition) then
                    table.insert(wait_conditions, v)
                elseif not delM and delN and not isSameCircuit(v, waitConditionOr) then
                    table.insert(wait_conditions, v)
                elseif not isSameCircuit(v, WaitCondition) and not isSameCircuit(v, waitConditionOr) then
                    table.insert(wait_conditions, v)
                end
            end
            
            newRecord.wait_conditions = wait_conditions
            oldSched.records[stopTrain.record] = newRecord
            local newSched = {current = oldSched.current, records = oldSched.records}
            stopTrain.train.schedule = newSched
        end
        
    end
    
    -- trainState 0: 在站台, 1:进站, 2:出站
    function checkManual(train, trainState)
        local stopedTrain = global.stopTrans[train.id]
        
        if not stopedTrain then
            return
        end
        if not train.valid then
            global.stopTrans[train.id] = nil
            return
        end

        -- 火车离开站台, 直接清除所有信号条件
        if trainState == 2 then
            _print("火车离开站台 重新计算信号!! ")
            RecalcScheduleRecord(stopedTrain.train, 0)
            return
        end
        
        local signals = stopedTrain.station.get_merged_signals()
        local signalBit = 0;
        local oldSignalBit = stopedTrain.signalBit
        
        if signals then
            for _, v in pairs(signals) do
                if v.signal.type == "virtual" and v.signal.name == "signal-M" and v.count == 1 then
                    _print("设置信号M "..v.count)
                    signalBit = bit32.bor(signalBit, 1)
                end
                if v.signal.type == "virtual" and v.signal.name == "signal-N" and v.count == 1 then
                    _print("设置信号N "..v.count)
                    signalBit = bit32.bor(signalBit, 2)
                end
                
            end
            
            if stopedTrain.signalBit ~= signalBit then                
                -- 设置为手动
                _print("添加信号 ")
                stopedTrain.signalBit = signalBit
                NewScheduleRecord(stopedTrain.train, signalBit)
            end
        end
        
        if oldSignalBit ~= signalBit then
            _print("重新计算信号!! ")
            RecalcScheduleRecord(stopedTrain.train, stopedTrain.signalBit)
        end
    end
    local function TrainArrives(train)
        _print("火车进入"..train.id)
        
        creteStop(train)
        checkManual(train, 1)
        
    end
    local function TrainLeaves(oldState, train)
        _print("火车离开"..train.id)
        
        local stopedTrain = global.stopTrans[train.id]
        
        if stopedTrain and stopedTrain.signalBit ~= 0 then
            checkManual(stopedTrain.train, 2)
        end
        global.stopTrans[train.id] = nil
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
    
    log("开始")
    -- variable
    global.Tick = global.Tick or {}
    global.Tick.checkTick = global.Tick.checkTick or 0
    global.stopTrans = global.stopTrans or {}
    regEvent()
    
end)


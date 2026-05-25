local function findMonitor()
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if string.find(name, "monitor") then return peripheral.wrap(name) end
    end
    return nil
end

local function findChest()
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if string.find(name, "chest") or string.find(name, "barrel") then
            return name, peripheral.wrap(name)
        end
    end
    return nil, nil
end

local function findAPUEngine()
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if string.find(name, "portable_engine") then
            return peripheral.wrap(name)
        end
    end
    return nil
end

local function findSpeaker()
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if string.find(name, "speaker") then return peripheral.wrap(name) end
    end
    return nil
end

local mon = findMonitor()
local chestName, chest = findChest()
local apu = findAPUEngine()
local speaker = findSpeaker()

if not mon or not chest then print("Error: Monitor or Chest missing!") return end
mon.setTextScale(0.7)

local savePathTime = "/navi/flight_time.dat"
local savePathEngines = "/navi/engine_count.dat"

local function saveFlightData(t, engCount)
    local f1 = io.open(savePathTime, "w")
    if f1 then f1:write(tostring(t)) f1:close() end
    local f2 = io.open(savePathEngines, "w")
    if f2 then f2:write(tostring(engCount)) f2:close() end
end

local function loadFlightData()
    local t = 0
    local engCount = 9
    if fs.exists(savePathTime) then
        local f = io.open(savePathTime, "r")
        if f then t = tonumber(f:read("*a")) or 0 f:close() end
    end
    if fs.exists(savePathEngines) then
        local f = io.open(savePathEngines, "r")
        if f then engCount = tonumber(f:read("*a")) or 9 f:close() end
    end
    return t, engCount
end

local fuelValues = {
    ["minecraft:coal"] = 80,
    ["minecraft:charcoal"] = 80,
    ["minecraft:coal_block"] = 800,
    ["minecraft:lava_bucket"] = 1000,
    ["minecraft:stick"] = 5,
}

local function getItemFuelValue(id)
    if fuelValues[id] then return fuelValues[id] end
    if string.find(id, "planks") or string.find(id, "log") or string.find(id, "wood") then return 15 end
    return 0
end

local function formatTime(totalSeconds)
    if totalSeconds <= 0 then return "00:00:00" end
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = math.floor(totalSeconds % 60)
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function scanChestSlots()
    local slots = {}
    local success, items = pcall(chest.list)
    if success and items then
        for slot, item in pairs(items) do
            if item and item.name then slots[slot] = { name = item.name, count = item.count } end
        end
    end
    return slots
end

local function getAPURemainingTime()
    if not apu then return 0 end
    local totalSeconds = 0
    local success, items = pcall(apu.list)
    if success and items then
        for slot, item in pairs(items) do
            if item and item.name then totalSeconds = totalSeconds + (getItemFuelValue(item.name) * item.count) end
        end
    end
    return totalSeconds
end

local activeFlightTime, mainEngineCount = loadFlightData()
local lastChestSnapshot = scanChestSlots()

local deliveryLagSeconds = 3.0 
local deliveryBuffer = 0
local tickRate = 0.05
local timerCounter = 0

local mainAlarmTimer = 0
local apuAlarmTimer = 0
local refuelModeActive = false

local function renderOutput(line, text)
    if mon then mon.setCursorPos(1, line) mon.write(text) end
    term.setCursorPos(1, line) term.clearLine() term.write(text)
end

term.clear()

while true do
    local apuTimeStr = "OFF"
    local apuSeconds = 0
    local timerID = os.startTimer(tickRate)
    local event, p1 = os.pullEvent()
    
    if event == "key" then
        if p1 == 13 or p1 == keys.equals then
            mainEngineCount = mainEngineCount + 1
            saveFlightData(activeFlightTime, mainEngineCount)
        elseif p1 == 12 or p1 == keys.minus then
            if mainEngineCount > 1 then
                mainEngineCount = mainEngineCount - 1
                saveFlightData(activeFlightTime, mainEngineCount)
            end
        elseif p1 == keys.r then
            refuelModeActive = not refuelModeActive
            
            -- ЛОГИКА НАЧАЛА ЗАПРАВКИ КЛАВИШЕЙ
            if refuelModeActive then
                redstone.setOutput("top", true)     -- Сигнал НАВЕРХ на заполнение сундука
                redstone.setOutput("bottom", false) -- Перекрываем ВНИЗ подачу на двигатели
            else
                redstone.setOutput("top", false)
                redstone.setOutput("bottom", true)  -- Если выключили вручную, открываем подачу вниз
            end
            lastChestSnapshot = scanChestSlots()
        end
    end

    if event == "timer" and p1 == timerID then
        timerCounter = timerCounter - tickRate
        
                if timerCounter <= 0 then
            local currentChestSnapshot = scanChestSlots()
            local itemsAdded = false
            
            -- 1. Считаем общее количество топлива в сундуке прямо сейчас
            local totalCurrentItems = 0
            for slot, item in pairs(currentChestSnapshot) do
                totalCurrentItems = totalCurrentItems + item.count
            end
            
            -- 2. Считаем, сколько было в прошлую секунду
            local totalLastItems = 0
            for slot, item in pairs(lastChestSnapshot) do
                totalLastItems = totalLastItems + item.count
            end

            -- 3. Проверяем дозаправку по ячейкам (для начисления времени)
            for slot, currentItem in pairs(currentChestSnapshot) do
                local lastItem = lastChestSnapshot[slot]
                if not lastItem or (currentItem.name == lastItem.name and currentItem.count > lastItem.count) then
                    itemsAdded = true
                    local addedAmount = lastItem and (currentItem.count - lastItem.count) or currentItem.count
                    local itemFuelValue = getItemFuelValue(currentItem.name)
                    if itemFuelValue > 0 then
                        activeFlightTime = activeFlightTime + ((itemFuelValue * addedAmount) / mainEngineCount)
                    end
                end
            end

            -- 4. УМНАЯ ЛОГИКА ПЕРЕКЛЮЧЕНИЯ ПОТОКОВ (Ваша идея!)
            if refuelModeActive then
                -- Если количество топлива БОЛЬШЕ нуля, но оно ПЕРЕСТАЛО меняться (застыло)
                if totalCurrentItems > 0 and totalCurrentItems == totalLastItems then
                    refuelModeActive = false
                    redstone.setOutput("top", false)    -- Отключаем внешнюю закачку сверху
                    redstone.setOutput("bottom", true)  -- МГНОВЕННО ПОДАЕМ СИГНАЛ ВНИЗ на двигатели
                -- Защита: если сундук просто пустой и застыл на нуле
                elseif totalCurrentItems == 0 then
                    refuelModeActive = false
                    redstone.setOutput("top", false)
                    redstone.setOutput("bottom", true)
                end
            end

            -- 5. Считаем уходящее топливо в полете (буфер задержки)
            for slot, lastItem in pairs(lastChestSnapshot) do
                local currentItem = currentChestSnapshot[slot]
                if currentItem then
                    if currentItem.name == lastItem.name and currentItem.count < lastItem.count then
                        local lostAmount = lastItem.count - currentItem.count
                        local itemFuelValue = getItemFuelValue(currentItem.name)
                        if itemFuelValue > 0 and not refuelModeActive then
                            deliveryBuffer = deliveryLagSeconds
                        end
                    end
                else
                    if not refuelModeActive then deliveryBuffer = deliveryLagSeconds end
                end
            end
            
            lastChestSnapshot = currentChestSnapshot
            timerCounter = 1.0
            saveFlightData(activeFlightTime, mainEngineCount)
        end


        if activeFlightTime > 0 and not refuelModeActive then
            activeFlightTime = activeFlightTime - tickRate
            if activeFlightTime < 0 then activeFlightTime = 0 end
        end
        if deliveryBuffer > 0 then
            deliveryBuffer = deliveryBuffer - tickRate
            if deliveryBuffer < 0 then deliveryBuffer = 0 end
        end

        if apu then
            apuSeconds = getAPURemainingTime()
            apuTimeStr = apuSeconds > 0 and formatTime(apuSeconds) or "NO FUEL"
        end

        -- Частотная аудиосирена
        if speaker and not refuelModeActive then 
            if activeFlightTime > 0 and activeFlightTime < 1200 then 
                if mainAlarmTimer <= 0 then 
                    speaker.playSound("minecraft:block.note_block.bit", 1.5, 2.0)
                    mainAlarmTimer = 0.5 
                end 
            end 
            if apuSeconds > 0 and apuSeconds < 1200 then 
                if apuAlarmTimer <= 0 then 
                    speaker.playSound("minecraft:block.note_block.bit", 1.0, 1.5) 
                    apuAlarmTimer = 0.25 
                end 
            end 
        end 

        if mainAlarmTimer > 0 then mainAlarmTimer = mainAlarmTimer - tickRate end 
        if apuAlarmTimer > 0 then apuAlarmTimer = apuAlarmTimer - tickRate end 
        
        local statusText = "STATUS: NO FUEL"
        local emergencyMode = false
        
        if refuelModeActive then
            statusText = "STATUS: REFUELING"
        elseif activeFlightTime > 0 then
            if deliveryBuffer > 0 and (activeFlightTime <= deliveryLagSeconds + 1) then
                statusText = "STATUS: INTAKE"
            elseif activeFlightTime < 1200 then
                statusText = "STATUS: LOW FUEL"
                emergencyMode = true
            else
                statusText = "STATUS: RUNNING"
            end
        end

        mon.clear()
        if refuelModeActive then
            if mon.isColor() then mon.setBackgroundColor(colors.cyan) mon.setTextColor(colors.black) end
            if term.isColor() then term.setBackgroundColor(colors.cyan) term.setTextColor(colors.black) end
        elseif emergencyMode then
            if mon.isColor() then mon.setBackgroundColor(colors.red) mon.setTextColor(colors.white) end
            if term.isColor() then term.setBackgroundColor(colors.red) term.setTextColor(colors.white) end
        else
            if mon.isColor() then mon.setBackgroundColor(colors.black) mon.setTextColor(colors.green) end
if term.isColor() then term.setBackgroundColor(colors.black) term.setTextColor(colors.green) end
end
renderOutput(1, "= ENGINE LOG =")
renderOutput(2, statusText)
renderOutput(3, string.format("ENGx%2d: %s [+]/[-]", mainEngineCount, formatTime(activeFlightTime)))
renderOutput(4, string.format("APU : %s", apuTimeStr))
end
end
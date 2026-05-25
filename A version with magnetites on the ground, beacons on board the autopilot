-- ============================================
-- FMS V15.21: FINAL (FIXED LOAD ORDER)
-- ============================================
local running = true
local updateInterval = 0.05
local altIntegral = 0
-- === АВТО-ПОИСК И ВКЛЮЧЕНИЕ МОДЕМА НА ЛЮБОЙ СТОРОНЕ ===
local planeModemSide = nil
for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
    if peripheral.getType(side) == "modem" then
        planeModemSide = side
        rednet.open(side) -- Открываем сеть на найденной стороне
        break
    end
end


local lastAlt = 0 -- Добавь эту строку в начало файла
local gimbal, alt_sensor, mon
local myX, myY, myZ = 0, 0, 0
local oldX, oldZ = 0, 0
local curRoll, curPitch, curYaw, curSpd = 0, 0, 0, 0
local lastYaw = 0
local actualTrack, smoothTrack = 0, 0
local selectedIdx = 1
local targetBrng, headingDiff = 0, 0
local runways_list = {}
local invRoll, invPitch, yawOffset = 1, 1, 0
local swapAxes = false -- Если true, Roll и Pitch меняются местами
local vel_sensor
local invSteer = 1 -- Добавь сюда
local altIntegral = 0
local pitchTick = 0
local speaker
local approachWarned = false
local climbPhase = false
local config = {} -- Добавь это в самое начало файла, если еще нет
local coordsHistory = {}      -- Таблица для хранения истории координат {time, x, z}
local lockTargetBrng = nil    -- Переменная для фиксации курса цели
local isGpsFrozen = false
local takeoffPhase = false     -- Активен ли взлет
local takeoffDone = false
local gpsSource = "AIR_TRAFFIC"




-- НАСТРОЙКИ АВТОПИЛОТА
local apEnabled = false
local targetAlt = 120
local P_STAB, P_NAV, MAX_ROLL = 0.25, 0.5, 25

local configPath = "/navi/relay_config.txt"
local sides = {"top", "bottom", "left", "right", "front", "back"}
local relays = {
  rUp = {dev=nil, side=nil, devName="", sideName="", label="PITCH UP"},
  rDown = {dev=nil, side=nil, devName="", sideName="", label="PITCH DOWN"},
  rLeft = {dev=nil, side=nil, devName="", sideName="", label="ROLL LEFT"},
  rRight = {dev=nil, side=nil, devName="", sideName="", label="ROLL RIGHT"},
  rEng = {dev=nil, side=nil, devName="", sideName="", label="THROTTLE"}
}

-- ============================================
-- 1. СЕРВИСНЫЕ ФУНКЦИИ (ОПИСАНИЕ ДО ВЫЗОВА)
-- ============================================

function findPeripherals()
    gimbal = peripheral.find("gimbal_sensor")
    alt_sensor = peripheral.find("altitude_sensor")
    mon = peripheral.find("monitor")
    vel_sensor = peripheral.find("velocity_sensor")
    speaker = peripheral.find("speaker")
    if mon then
        mon.setTextScale(0.5)
    end
end

function saveConfig()
    local cfg = {
        relays = {},
        invRoll = invRoll,
        invPitch = invPitch,
        yawOffset = yawOffset,
        swapAxes = swapAxes,
        invSteer = invSteer,
        passkey = config.passkey or 0,
        apEnabled = apEnabled,
        targetAlt = targetAlt,
        selectedIdx = selectedIdx
    }
    for k, v in pairs(relays) do 
        cfg.relays[k] = {devName=v.devName, sideName=v.sideName} 
    end
    local f = fs.open(configPath, "w")
    f.write(textutils.serialize(cfg))
    f.close()
end



function loadRelayConfig()
    if not fs.exists(configPath) then 
        config.passkey = math.random(1000, 9999) 
        saveConfig()
        return 
    end
    local f = fs.open(configPath, "r")
    local cfg = textutils.unserialize(f.readAll())
    f.close()
    
    if cfg then
        -- Загружаем ключ сразу, как только поняли, что файл не пустой
        config.passkey = cfg.passkey or 0 
        
        -- Загружаем реле
        if cfg.relays then
            for k, v in pairs(cfg.relays) do
                relays[k].dev = peripheral.wrap(v.devName)
                relays[k].side = v.sideName
                relays[k].devName, relays[k].sideName = v.devName, v.sideName
            end
        end
        -- Загружаем параметры осей
        invRoll = cfg.invRoll or 1
        invPitch = cfg.invPitch or 1
        yawOffset = cfg.yawOffset or 0
        swapAxes = cfg.swapAxes or false
        invSteer = cfg.invSteer or 1
        
        -- ВОССТАНАВЛИВАЕМ ПОЛЕТНЫЕ ДАННЫЕ:
        apEnabled = cfg.apEnabled or false
        targetAlt = cfg.targetAlt or 120
        selectedIdx = cfg.selectedIdx or 1
        if apEnabled then
            if (targetAlt - myY) > 15 then climbPhase = true else climbPhase = false end
        end
    end
end

function loadRunway()
    local path = "/navi/runways.txt"
    -- АВТО-СОЗДАНИЕ ФАЙЛА, ЕСЛИ ЕГО НЕТ
    if not fs.exists(path) then
        local f = fs.open(path, "w")
        f.writeLine("0, 0, 100, 100, TEMPLATE, 70") -- Пример строки-шаблона
        f.close()
    end
    runways_list = {}
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local line = f.readLine()
        while line do
            local p = {}
            for part in line:gmatch("([^,]+)") do table.insert(p, (part:gsub("[%s\r\n]", ""))) end
            if #p >= 5 then
                table.insert(runways_list, {
                    x1=tonumber(p[1]) or 0, z1=tonumber(p[2]) or 0,
                    x2=tonumber(p[3]) or 0, z2=tonumber(p[4]) or 0,
                    name=p[5] or "UNK",
                    alt=tonumber(p[6]) or 70 -- ДОБАВЛЕНО: берем 6-й параметр или ставим 70
                })
            end
            line = f.readLine()
        end
        f.close()
    end
        if #runways_list == 0 then 
        -- Добавляем x2 и z2, чтобы расчеты (LNAV) не падали из-за nil
        table.insert(runways_list, {x1=0, z1=0, x2=1, z2=1, name="EMPTY", alt=70}) 
    end

end


function setPwr(rObj, pwr)
    if rObj and rObj.dev then rObj.dev.setAnalogOutput(rObj.side, math.floor(math.max(0, math.min(15, pwr)))) end
end

function calibrate()
    local found = peripheral.getNames()
    local rList = {}
    for _, n in ipairs(found) do 
        if n:find("relay") or n:find("redstone") then table.insert(rList, n) end 
    end
    if #rList == 0 then print("No relays found!"); sleep(1) return end

    -- Часть А: Настройка портов
    local order = {"rUp", "rDown", "rLeft", "rRight", "rEng"}
    for _, key in ipairs(order) do
        local dIdx, sIdx, stepDone = 1, 1, false
        while not stepDone do
            term.setBackgroundColor(colors.gray); term.clear()
            term.setCursorPos(2, 2); print("SHAG 1: NASTROIKA RELE - " .. relays[key].label)
            term.setCursorPos(2, 4); print("Device: " .. (rList[dIdx] or "---"))
            print(" Side: " .. sides[sIdx])
            print("\n [SPACE] - TEST | [ENTER] - OK")
            local _, k = os.pullEvent("key")
            if k == keys.space then
                local r = peripheral.wrap(rList[dIdx])
                if r then r.setAnalogOutput(sides[sIdx], 15) sleep(0.3) r.setAnalogOutput(sides[sIdx], 0) end
            elseif k == keys.enter then
                relays[key].dev = peripheral.wrap(rList[dIdx]); relays[key].side = sides[sIdx]
                relays[key].devName, relays[key].sideName = rList[dIdx], sides[sIdx]
                stepDone = true
            elseif k == keys.up then dIdx = dIdx % #rList + 1
            elseif k == keys.down then dIdx = (dIdx - 2 + #rList) % #rList + 1
            elseif k == keys.right then sIdx = sIdx % #sides + 1
            elseif k == keys.left then sIdx = (sIdx - 2 + #sides) % #sides + 1 end
        end
    end

        -- Часть Б: Проверка осей (статическая с подтверждением)
        invRoll, invPitch = 1, 1 -- Сбрасываем перед тестом
    term.setBackgroundColor(colors.blue); term.clear()
    term.setCursorPos(2, 2); print("SHAG 2: INVERSIYA")
        -- Часть Б1: АВТО-ОПРЕДЕЛЕНИЕ SWAP
    term.setBackgroundColor(colors.blue); term.clear()
    term.setCursorPos(2, 2); print("SHAG 2: OSI (SWAP)")
    print("\n NAKLONITE SAMOLET VPRAVO...")
    
    local detectDone = false
    while not detectDone do
        local a = gimbal.getAngles()
        local r_raw = a.roll or a[1] or 0
        local p_raw = a.pitch or a[2] or 0
        local r = (r_raw > 180 and r_raw - 360 or r_raw)
        local p = (p_raw > 180 and p_raw - 360 or p_raw)

        -- Если наклонили больше чем на 15 градусов
        if math.abs(r) > 15 or math.abs(p) > 15 then
            -- Если по Pitch (p) отклонение больше, значит оси перепутаны
            swapAxes = (math.abs(p) > math.abs(r))
            print(swapAxes and " > OSI PEREPUTANY (SWAP ON)" or " > OSI OK")
            detectDone = true
            sleep(1.5)
        end
        sleep(0.1)
    end

    -- ДАЛЬШЕ ТВОЙ КОД (Проверка инверсии крена и тангажа...)

    -- Проверка крена
    print("\n 1. NAKLONITE VPRAVO I NAZHMITE ENTER")
    local stepDone = false
    while not stepDone do
        updateGimbal()
        term.setCursorPos(2, 5); term.clearLine()
        write(string.format("Tekushij Roll: %.1f", curRoll))
        
        local event, key = os.pullEvent()
        if event == "key" and key == keys.enter then
            invRoll = (curRoll < 0) and -1 or 1 -- Инвертируем, если ушло в минус
            stepDone = true
        end
    end
    print("\n > ROLL ZAFIKSIROVAN")
    sleep(0.5)

    -- Проверка тангажа
    print("\n 2. PODNIMITE NOS I NAZHMITE ENTER")
    stepDone = false
    while not stepDone do
        updateGimbal()
        term.setCursorPos(2, 9); term.clearLine()
        write(string.format("Tekushij Pitch: %.1f", curPitch))
        
        local event, key = os.pullEvent()
        if event == "key" and key == keys.enter then
            invPitch = (curPitch < 0) and -1 or 1
            stepDone = true
        end
    end
    print("\n > PITCH ZAFIKSIROVAN")
    sleep(1)
          -- Часть В: ТЕСТ КУРСА (ПРОЕЗД ЧЕРЕЗ VELOCITY)
    term.setBackgroundColor(colors.black); term.clear()
    term.setCursorPos(2, 2); print("SHAG 3: KURS (YAW)")
    print("\n Razgon: 5 m/s v techenie 5 sec...")
    
    local startX, startZ = myX, myZ
    setPwr(relays.rEng, 12) -- Даем газ (12 достаточно для разгона)
    
    local okTimer = 0
    while okTimer < 5 do
        sleep(1) -- Ждем секунду
        
        local speed = 0
        if vel_sensor then
            local v = vel_sensor.getVelocity()
            local raw = (type(v) == "table") and math.sqrt(v.x^2 + v.z^2) or math.abs(v)
            speed = raw / 5 -- Делим на 10 для синхронизации с Create
        end

        if speed >= 5 then 
            okTimer = okTimer + 1 
        else 
            okTimer = 0 
        end
        
        term.setCursorPos(2, 6); term.clearLine()
        write(string.format("Progress: %d/5s | Spd: %.1f", okTimer, speed))
    end
    
        setPwr(relays.rEng, 0) -- Стоп двигатель
    
    -- 1. Ждем последнее сообщение GPS, чтобы зафиксировать конечную точку
        -- Замена строки 246
    local tID = os.startTimer(1) -- Ждем сигнал 1 секунду
    while true do
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "rednet_message" and p3 == "AIR_TRAFFIC" then
            if type(p2) == "table" then myX, myZ = p2.x or myX, p2.z or myZ end
            break
        elseif ev == "timer" and p1 == tID then
            break -- Время вышло, идем дальше
        end
    end

    -- 2. Расчет курса и смещения
    local dx, dz = myX - startX, myZ - startZ
    local realTrack = math.deg(math.atan2(dx, dz))
    if realTrack < 0 then realTrack = realTrack + 360 end
    
    updateGimbal() 
    yawOffset = (realTrack - curYaw) % 360
    
    print("\n KALIBROVKA OK! OFFSET: " .. math.floor(yawOffset))

    -- 3. ТЕСТ РУЛЕЙ (проверяем инверсию поворота)
    print("PROVERKA RULEJ...")
    local startY = curYaw
    setPwr(relays.rRight, 15)
    sleep(5.0)
    setPwr(relays.rRight, 0)
    updateGimbal()
    
    local diff = (curYaw - startY + 180) % 360 - 180
    if diff < -0.1 then 
        invSteer = -1
        print(" > STEER: INVERTED")
    else
        invSteer = 1
        print(" > STEER: OK")
    end

    -- 4. СОХРАНЕНИЕ И ВЫХОД
    saveConfig()
    print("\n VSE DANNYE SOHRANENY!")
    sleep(2) 
end -- Конец функции calibrate


-- ============================================
-- 2. ЛОГИКА УПРАВЛЕНИЯ И ТЕЛЕМЕТРИИ
-- ============================================

function updateGimbal()
    if not gimbal then return end
    local a = gimbal.getAngles()
    if a then
        local raw1 = a.roll or a[1] or 0
        local raw2 = a.pitch or a[2] or 0
        local y_raw = a.yaw or a[3] or 0
        
        -- Нормализуем сырые данные
        local v1 = (raw1 > 180 and raw1 - 360 or raw1)
        local v2 = (raw2 > 180 and raw2 - 360 or raw2)

        -- САМЫЙ ВАЖНЫЙ МОМЕНТ: Смена осей
        local r, p
        if swapAxes then
            r, p = v2, v1  -- Меняем местами
        else
            r, p = v1, v2  -- Как обычно
        end
        
        -- Применяем инверсию и смещение
        curRoll = r * invRoll
        curPitch = p * invPitch
        curYaw = (y_raw + yawOffset) % 360
    end
end



local function setPwr(rObj, pwr)
    if rObj and rObj.dev then rObj.dev.setAnalogOutput(rObj.side, math.floor(math.max(0, math.min(15, pwr)))) end
end

function runAutopilot()
    if not apEnabled then for _, r in pairs(relays) do setPwr(r, 0) end return end
        -- ==========================================================
    -- АВТОМАТИЧЕСКИЙ ВЗЛЕТ (TAKEOFF PHASE) - БЕЗ КРЕНА
    -- ==========================================================
    if takeoffPhase then
        local tgt = runways_list[selectedIdx]
        local portAlt = tgt and tgt.alt or 70
        
        if myY > (portAlt + 20) then
            takeoffPhase = false
            takeoffDone = true -- Защита: блокируем повтор при посадке
            climbPhase = true  
            saveConfig()
        else
            setPwr(relays.rEng, 13) -- Полный газ
            setPwr(relays.rUp, 15)  -- Руль на себя
            setPwr(relays.rDown, 0)
            
            local dRoll = 0 -- КРЕН ЗАПРЕЩЕН, держим крылья ровно
            local rCorr = (dRoll - curRoll)
            if math.abs(rCorr) < 4 then
                setPwr(relays.rRight, 0); setPwr(relays.rLeft, 0)
            elseif rCorr > 0 then
                setPwr(relays.rRight, 15); setPwr(relays.rLeft, 0)
            else
                setPwr(relays.rRight, 0); setPwr(relays.rLeft, 15)
            end
            return -- Выходим, чтобы штатный PID не мешал взлету
        end
    end
    -- ==========================================================

    -- 1. ДАННЫЕ
    local altErr = targetAlt - myY
    local verticalSpeed = (myY - lastAlt) / updateInterval
    lastAlt = myY
    local turnRate = (curYaw - lastYaw + 180) % 360 - 180
    lastYaw = curYaw

       -- ==========================================================
    -- 2. КРЕН (ДОБАВЛЕН ЗАПРЕТ КРЕНА ПЕРЕД КАСАНИЕМ)
    -- ==========================================================
    local activeMaxRoll = (altErr > 40) and 10 or MAX_ROLL
    local dRoll = (headingDiff * invSteer * P_NAV) - (turnRate * 2)
    
    -- ИСПРАВЛЕНО: Если до ВПП осталось меньше 15 блоков по высоте, 
    -- принудительно требуем от самолета держать крылья СТРОГО ГОРИЗОНТАЛЬНО (dRoll = 0)
    -- Это исключит заваливание на крыло, которое видно на скриншоте.
    local portAlt = runways_list[selectedIdx] and runways_list[selectedIdx].alt or 70
    if myY <= (portAlt + 20) then
        activeMaxRoll = 0
        dRoll = 0
    end
    
    dRoll = math.max(-activeMaxRoll, math.min(activeMaxRoll, dRoll))
    local rCorr = (dRoll - curRoll)

    if math.abs(rCorr) < 4 then
        setPwr(relays.rRight, 0); setPwr(relays.rLeft, 0)
    elseif rCorr > 0 then 
        setPwr(relays.rRight, 15); setPwr(relays.rLeft, 0)
    else 
        setPwr(relays.rRight, 0); setPwr(relays.rLeft, 15) 
    end


        -- 3. ТАНГАЖ
       -- ==========================================================
    -- 3. ТАНГАЖ (ИСПРАВЛЕНО ДЛЯ ИДЕАЛЬНОГО УДЕРЖАНИЯ ЭШЕЛОНА)
    -- ==========================================================
    pitchTick = (pitchTick + 1) % 4

    -- Динамические коэффициенты в зависимости от положения относительно эшелона
    local pCoeff = (altErr < 0) and 0.15 or 0.30 
    local vsGain = (altErr < 0) and 3.5 or 2.5
    local vsComp = verticalSpeed * vsGain

    -- ОЖИВЛЯЕМ ИНТЕГРАЛ: плавно накапливаем ошибку, чтобы компенсировать вес
    if math.abs(altErr) < 20 then
        -- dt равен updateInterval (0.05). Коэффициент 0.02 подбирается под вес
        altIntegral = altIntegral + (altErr * updateInterval * 0.02)
        -- Ограничиваем влияние интеграла, чтобы избежать раскачки (баффинга)
        altIntegral = math.max(-5, math.min(5, altIntegral))
    else
        altIntegral = 0 -- Обнуляем на больших дистанциях, чтобы избежать заброса
    end

    -- ИСПРАВЛЕНО: Крен крадет подъемную силу крыла, поэтому нос нужно ЗАДИРАТЬ (+ rollComp)
    local rollComp = math.abs(curRoll) * 0.35 

    -- Считаем целевой тангаж (dPitch)
    local dPitch = (altErr * pCoeff) + rollComp - vsComp + altIntegral

    -- ИСПРАВЛЕНО: Адекватные полетные лимиты тангажа. 
    -- 4 градуса на подъем — слишком мало. Делаем от -15 (спуск) до +12 (набор).
    if dPitch < -15 then dPitch = -15 end 
    if dPitch > 12 then dPitch = 12 end 

    local pCorr = (dPitch - curPitch)
    local pAbs = math.abs(pCorr)
    local pulseHit = false

    -- Логика рывков реле (гашение автоколебаний)
    if pAbs > 10 then
        pulseHit = true 
    elseif pAbs > 2.5 then
        if pCorr < 0 then
            -- СПУСК: более редкие импульсы, чтобы не разгонять пике
            if pitchTick == 0 then pulseHit = true end 
        else
            -- НАБОР: более частые импульсы для преодоления гравитации
            if pitchTick == 0 or pitchTick == 2 then pulseHit = true end
        end
    elseif pAbs > 0.4 then
        -- Микро-коррекция удержания горизонта
        if pitchTick == 0 then pulseHit = true end
    end



    -- 4. ВЫХОД НА РЕЛЕ
    if math.abs(altErr) < 0.5 and math.abs(verticalSpeed) < 0.2 then
        setPwr(relays.rUp, 0); setPwr(relays.rDown, 0)
    elseif pulseHit then
        if pCorr > 0 then 
            setPwr(relays.rUp, 15); setPwr(relays.rDown, 0)
        else 
            setPwr(relays.rUp, 0); setPwr(relays.rDown, 15) 
        end
    else
        setPwr(relays.rUp, 0); setPwr(relays.rDown, 0)
    end
end

    

function drawCockpit(w, h)
    term.setBackgroundColor(colors.black); term.clear()
    local cx = math.floor(w / 2)
    local tgt = runways_list[selectedIdx]
    term.setTextColor(colors.yellow); term.setCursorPos(1, 1)
     write(string.format("R:%-2.0f P:%-2.0f Y:%03d ALT:%d -> %d SPD:%-3.1f", curRoll, curPitch, curYaw, myY, targetAlt, curSpd))
    term.setCursorPos(w-10, 1); term.setTextColor(apEnabled and colors.green or colors.red)
    write(apEnabled and "AP:ACTIVE" or "AP:READY")
    term.setCursorPos(cx-10, 2); term.setTextColor(colors.gray); write("[  .  N  .  E  .  S  .  W  ]")
    local trackOff = (smoothTrack - curYaw + 180) % 360 - 180
    local targetPos = math.max(-10, math.min(10, math.floor((trackOff + headingDiff) / 10 + 0.5)))
    term.setCursorPos(cx + targetPos, 3); term.setTextColor(colors.magenta); write("T")
    local vx = math.max(-10, math.min(10, math.floor(trackOff / 10 + 0.5)))
    term.setCursorPos(cx + vx, 3); term.setTextColor(colors.green); write("v")
    term.setCursorPos(cx, 3); term.setTextColor(colors.white); write("^")
    local horizonY = 6; local rad = math.rad(curRoll); term.setTextColor(colors.blue)
    for dx = -8, 8 do
        local dy = math.floor(dx * math.tan(rad) - (curPitch * 0.1) + 0.5)
        if horizonY+dy > 4 and horizonY+dy < 9 then term.setCursorPos(cx+dx, horizonY+dy); write("=") end
    end
    term.setCursorPos(cx-1, horizonY); term.setTextColor(colors.white); write(">o<")
    -- Находим последние строки функции drawCockpit
    term.setCursorPos(1, h)
    term.setTextColor(colors.magenta)
    
    -- 1. Считаем расстояние до начала полосы
    local dist = 0
    if tgt then
        dist = math.sqrt((tgt.x1 - myX)^2 + (tgt.z1 - myZ)^2)
    end
    
    local nameStr = (tgt and tgt.name or "NONE"):sub(1, 11)
    write(string.format("%-11s D:%-5d", nameStr, dist))

    -- 3. Выводим координаты GPS (смещаем чуть правее)

    local srcLabel = (gpsSource == "AIR_TRAFFIC") and "AT" or "NAV"
    local gpsStr = string.format("[%s]:%d,%d", srcLabel, myX, myZ)

    term.setCursorPos(w - #gpsStr + 1, h) 
    term.setTextColor(colors.cyan)
    write(gpsStr)
end

-- ============================================
-- 3. СТАРТ ПРОГРАММЫ (ТЕПЕРЬ ВСЁ ЗАГРУЖЕНО)
-- ============================================

findPeripherals()
loadRunway()
loadRelayConfig()

updateGimbal()
oldX, oldZ = myX, myZ 
lastAlt = alt_sensor and alt_sensor.getHeight() or 0

local cruiseAlt = targetAlt 
local displayTick = 0 -- Делитель для экрана

local myTimer = os.startTimer(updateInterval)

while running do
    local event, p1, p2, p3 = os.pullEvent()
    
    -- Вся физика полета работает СТРОГО по сигналу полетного таймера
    if event == "timer" and p1 == myTimer then
        updateGimbal()
        
        -- 1. СКОРОСТЬ
        if vel_sensor then
            local v = vel_sensor.getVelocity()
            local rawSpd = 0
            if type(v) == "table" then
                rawSpd = math.sqrt((v.x or 0)^2 + (v.z or 0)^2)
            else
                rawSpd = math.abs(v or 0)
            end
            curSpd = rawSpd 
        end

        -- 2. ВЫСОТА И ТРЕК
        if alt_sensor then myY = alt_sensor.getHeight() or 0 end
        
        local dx, dz = myX - oldX, myZ - oldZ
        if (math.abs(dx) > 0.1 or math.abs(dz) > 0.1) then
            actualTrack = math.deg(math.atan2(dx, dz))
            if actualTrack < 0 then actualTrack = actualTrack + 360 end
            oldX, oldZ = myX, myZ
        end
        local tDiff = (actualTrack - smoothTrack + 180) % 360 - 180
        smoothTrack = (smoothTrack + tDiff * 0.2) % 360

        -- 3. НАВИГАЦИЯ И ГЛИССАДА
        local tgt = runways_list[selectedIdx]
        
        if tgt then
                        -- ==========================================================
            -- 1. ИДЕАЛЬНАЯ НАВИГАЦИЯ (С ЗАЩИТОЙ ОТ ПРОЛЕТА ТОРЦА ВПП)
            -- ==========================================================
            local rdx, rdz = tgt.x2 - tgt.x1, tgt.z2 - tgt.z1
            local rLen = math.sqrt(rdx*rdx + rdz*rdz)
            if rLen == 0 then rLen = 1 end 
            local ux, uz = rdx/rLen, rdz/rLen 
            local px, pz = myX - tgt.x1, myZ - tgt.z1
            local distAlong = px * ux + pz * uz
            local distAcross = px * uz - pz * ux 

            -- Рассчитываем истинный курс самого полотна ВПП
            local runwayBrng = math.deg(math.atan2(rdx, rdz))
            if runwayBrng < 0 then runwayBrng = runwayBrng + 360 end

            -- ПРОВЕРКА: Если мы уже пересекли начало полосы (distAlong < 0)
            if distAlong <= 0 then
                -- Отключаем упреждение. Самолет должен просто удерживать курс полосы.
                targetBrng = runwayBrng
                
                -- Подруливаем к центру полосы, если нас сносит боком на пробеге
                local runwayCorrection = math.max(-15, math.min(15, distAcross * 0.8))
                targetBrng = (targetBrng + runwayCorrection) % 360
            else
                -- Стандартная логика захода на подлете (ваш идеальный код)
                local lookAhead = math.max(400, math.abs(distAlong) * 0.7)
                local targetDist = distAlong + lookAhead
                if targetDist > 0 then targetDist = 0 end 

                local finalTgtX = tgt.x1 + ux * targetDist
                local finalTgtZ = tgt.z1 + uz * targetDist

                targetBrng = math.deg(math.atan2(finalTgtX - myX, finalTgtZ - myZ))
                if targetBrng < 0 then targetBrng = targetBrng + 360 end
                
                local sideCorrection = math.atan2(distAcross * 1.2, lookAhead)
                targetBrng = (targetBrng + math.deg(sideCorrection)) % 360
            end

           
            -- ЗАЩИТА ОТ ЗАВИСАНИЯ КООРДИНАТ (ФИКСАЦИЯ ЦЕЛИ 3 СЕК НАЗАД)
            -- ==========================================================
            local currentTime = os.epoch("utc") / 1000 -- Текущее время в секундах
            table.insert(coordsHistory, {t = currentTime, x = myX, z = myZ, brng = targetBrng})
            
            -- Удаляем из истории записи старше 3.5 секунд, чтобы таблица не разрасталась
            while #coordsHistory > 0 and (currentTime - coordsHistory[1].t) > 3.5 do
                table.remove(coordsHistory, 1)
            end

            -- Проверяем: изменились ли координаты по сравнению с предыдущим тиком
            local coordsMoved = (math.abs(dx) > 0.01 or math.abs(dz) > 0.01)
            
            -- Условие: координаты НЕ меняются, но скорость БОЛЬШЕ нуля (самолет летит, но GPS завис)
            if not coordsMoved and curSpd > 0.5 then
                if not isGpsFrozen then
                    isGpsFrozen = true
                    -- Ищем в истории точку, которая была ближе всего к "3 секунды назад"
                    local targetTime = currentTime - 3.0
                    local bestMatch = coordsHistory[1]
                    for _, hist in ipairs(coordsHistory) do
                        if math.abs(hist.t - targetTime) < math.abs(bestMatch.t - targetTime) then
                            bestMatch = hist
                        end
                    end
                    -- Фиксируем целевой курс, который был у самолета 3 секунды назад
                    lockTargetBrng = bestMatch.brng
                end
            else
                -- Если координаты меняются (или самолет полностью стоит), всё работает штатно
                isGpsFrozen = false
                lockTargetBrng = nil
            end
             -- Вычисляем финальное отклонение для рулей
            if isGpsFrozen and lockTargetBrng then
                targetBrng = lockTargetBrng
            end
            headingDiff = ((smoothTrack - targetBrng + 180) % 360 - 180)

                        -- ==========================================================
            

              -- ==========================================================
            -- 2. ИДЕАЛЬНЫЙ ДИНАМИЧЕСКИЙ РАСЧЕТ СНИЖЕНИЯ (ОПТИМАЛЬНЫЕ 2.5 КМ)
            -- ==========================================================
            local dist = math.sqrt((tgt.x1 - myX)^2 + (tgt.z1 - myZ)^2)
            local portAlt = tgt.alt or 70 

            -- ИСПРАВЛЕНО: Захват глиссады перенесен на 2500 блоков. 
            -- Теперь самолет пройдет над препятствиями высоко и безопасно!
            if dist < 2500 and tgt.name ~= "EMPTY" then
                climbPhase = false 
                
                                -- ==========================================================
                           -- ==========================================================
                -- СОВМЕЩЕННЫЙ АВТОМАТ ТЯГИ С ВЫСОКОЙ БАЗОЙ (БЕЗ СВАЛИВАНИЯ)
                -- ==========================================================
                local engineSignal = 0
                if takeoffPhase then
                    engineSignal = 13 -- Ваш штатный взлетный режим
                else
                    -- 1. Считаем относительную высоту над конкретной ВПП
                    local relativeAlt = math.max(0, myY - (portAlt or 14))
                    
                    -- 2. ИСПРАВЛЕННАЯ СОВМЕЩЕННАЯ ФОРМУЛА:
                    -- Подняли базу до 8.0. Теперь в воздухе газ физически не упадет ниже 10 делений.
                    -- На рубеже 2500м формула выдаст ~12.5 (газ 12) — начнется плавный сброс.
                    -- На дистанции 1500м формула выдаст ~11.0 (газ 11) — самолет ГАРАНТИРОВАННО ДОЛЕТИТ!
                    local smoothGas = 8.0 + (dist / 1000) + (relativeAlt / 100)
                    
                    -- Жестко зажимаем сигнал в физические рамки мотора от 4 до 13
                    engineSignal = math.floor(math.max(4, math.min(13, smoothGas)) + 0.5)
                    
                    -- 3. АВАРИЙНЫЙ ЗАМОК У ЗЕМЛИ (Жесткий сброс только перед полосой)
                    -- В воздухе летим безопасно на 10-11 делениях, а за 250 блоков до ВПП 
                    -- замок принудительно скинет реле в малый газ 4, убирая воздушную подушку.
                    if (dist < 250) or (distAlong and distAlong <= 0) then
                        engineSignal = 4
                    end
                end
                -- ==========================================================


            

                -- ==========================================================
                -- ИСПРАВЛЕННЫЙ АВТОНОМНЫЙ АВТОМАТ ВЫКЛЮЧЕНИЯ НА ЗЕМЛЕ
                -- ==========================================================
                -- Считаем вертикальную скорость в тик для детекции качения
                local currentVsPerTick = (myY - (lastAlt or myY))

                -- Проверяем, что мы находимся в зоне взлетно-посадочной полосы по GPS
                local inRunwayZone = (distAlong ~= nil and distAlong <= 500 and distAlong > -1500)

                -- Самель коснулся бетона: высота опустилась к уровню полосы (+12 блоков допуска для датчика на фюзеляже),
                -- а вертикальная скорость падения замерла (мы катимся по блокам Create, а не падаем)
                local isAtLandingAlt = (myY <= (portAlt + 20.0))
                local isNotFalling = (math.abs(currentVsPerTick) < 0.25)

                -- Если мы катимся в зоне ВПП, а фаза взлета (takeoffPhase) СЕЙЧАС выключена
                local isOnGround = inRunwayZone and isAtLandingAlt and isNotFalling and not takeoffPhase

                if apEnabled and isOnGround then
                    apEnabled = false -- Намертво гасим автопилот
                    engineSignal = 0  -- Сбрасываем сигнал тяги
                    saveConfig()      -- Сохраняем чистый конфиг
                    
                    -- Жестко обесточиваем абсолютно все полетные реле (винты, рули)
                    for _, r in pairs(relays) do setPwr(r, 0) end
                end

                -- Подаем сигнал на мотор ТОЛЬКО если автопилот еще летит в воздухе!
                -- Как только на земле apEnabled станет false, этот блок пропустит отправку, 
                -- и моторы Create гарантированно останутся заглушенными в 0.
                if apEnabled and not takeoffPhase then
                    setPwr(relays.rEng, engineSignal or 0)
                end
                -- ==========================================================



                -- ДИНАМИЧЕСКАЯ ГЛИССАДА С ОПТИМИЗИРОВАННЫМ ЗАПАСОМ
                -- ИСПРАВЛЕНО: Для более крутого захода уменьшаем смещение точки до +40 блоков,
                -- чтобы самолет не перелетал начало бетонки из-за избытка скорости.
                local safeDist = math.max(10, distAlong + 40)
                local safeSpeed = math.max(2, curSpd) 
                
                local timeToTarget = safeDist / safeSpeed
                local heightToLose = myY - portAlt
                local targetVsPerTick = (heightToLose / timeToTarget) * updateInterval

                -- Немного увеличиваем лимитер (0.7), чтобы рули успевали отрабатывать крутой спуск
                local maxVsPerTick = 0.7 * updateInterval 
                if targetVsPerTick > maxVsPerTick then targetVsPerTick = maxVsPerTick end

                local glideTarget = myY - targetVsPerTick

                if glideTarget < cruiseAlt then 
                    targetAlt = glideTarget 
                else
                    targetAlt = cruiseAlt
                end
            else
                -- МАРШЕВЫЙ ЭТАП (ВДАЛИ ОТ ВПП ИЛИ ЕСЛИ ВПП ПУСТАЯ)
                targetAlt = cruiseAlt
                if not takeoffPhase then
                    setPwr(relays.rEng, 13)
                end     
            end



        else
            targetAlt = cruiseAlt
        end -- Синтаксис полностью выровнен и закрыт коррект

        -- ВЫЗОВ АВТОПИЛОТА
        runAutopilot()
        
        -- Обновляем тяжелый экран раз в 2 тика (каждые 0.1 сек), разгружая CPU
                -- Обновляем тяжелый экран раз в 2 тика (каждые 0.1 сек), разгружая CPU
        displayTick = (displayTick + 1) % 2
        if displayTick == 0 then
            -- Проверяем, что монитор не просто привязан, но и физически существует на месте
            if mon and peripheral.isPresent(peripheral.getName(mon)) then
                -- Безопасно получаем размеры. Если что-то пойдет не так, подставятся нули
                local mW, mH = mon.getSize()
                if mW and mH then
                    local oldTerm = term.redirect(mon)
                    drawCockpit(mW, mH)
                    term.redirect(oldTerm)
                end
            end
            
            -- Отрисовка на встроенный экран компьютера (он всегда доступен)
            local tW, tH = term.getSize()
            if tW and tH then
                drawCockpit(tW, tH)
            end
        end


        -- Перезапускаем полетный таймер строго в конце полетного тика
        myTimer = os.startTimer(updateInterval)

    -- Внешние события обрабатываются независимо и не ломают таймер физики:
    -- ==========================================================
-- ИЗМЕНЕННЫЙ БЛОК ПРИЕМА GPS (ВЫБОР ИСТОЧНИКА)
-- ==========================================================
       elseif event == "rednet_message" then
        -- Если на самолете нажата кнопка G и выбран режим NAV_RADAR
        if gpsSource == "NAV_RADAR" and p3 == "NAV_RADAR" then
            if type(p2) == "table" then
                -- Принимаем координаты без проверки ключа (для стабильности)
                myX, myZ = p2.x or myX, p2.z or myZ
            end
        -- Если выбран режим старого диспетчера AIR_TRAFFIC
        elseif gpsSource == "AIR_TRAFFIC" and p3 == "AIR_TRAFFIC" then
            if type(p2) == "table" and p2.key == config.passkey then
                myX, myZ = p2.x or myX, p2.z or myZ
            end
        end




    elseif event == "key" then
        if p1 == keys.q then 
            running = false
        elseif p1 == keys.g then
            if gpsSource == "AIR_TRAFFIC" then
                gpsSource = "NAV_RADAR"
            else
                gpsSource = "AIR_TRAFFIC"
            end
        elseif p1 == keys.a then
            apEnabled = not apEnabled
            if apEnabled then
                local tgt = runways_list[selectedIdx]
                local portAlt = tgt and tgt.alt or 70
                
                -- Проверяем: если мы на земле аэропорта и взлет еще не выполнялся
                if myY <= (portAlt + 20) and not takeoffDone then
                    takeoffPhase = true
                    cruiseAlt = 300 -- Авто-эшелон 300
                    targetAlt = 300
                else
                    -- Штатное включение в воздухе
                    if (targetAlt - myY) > 15 then climbPhase = true else climbPhase = false end
                end
            else
                takeoffPhase = false
            end
            saveConfig()
        


        elseif p1 == keys.s then 
            calibrate()
            cruiseAlt = targetAlt
        elseif p1 == keys.pageUp then 
            cruiseAlt = cruiseAlt + 10
            targetAlt = cruiseAlt
            saveConfig()
        elseif p1 == keys.pageDown then 
            cruiseAlt = cruiseAlt - 10
            targetAlt = cruiseAlt
            saveConfig()
        elseif p1 == keys.up then 
            selectedIdx = selectedIdx % #runways_list + 1
            saveConfig()
        elseif p1 == keys.down then 
            selectedIdx = (selectedIdx - 2 + #runways_list) % #runways_list + 1
            saveConfig()
        end
    end
end

-- ================================================= --
--  AIRBORNE NAVIGATION COMPUTER V4.0 (HEADING PRO)  --
-- ================================================= --
local configPath = "/radar_cfg.txt"
local config = {}

-- === ПЕРЕМЕННЫЕ УМНОГО ФИЛЬТРА КООРДИНАТ ===
local lastOutX, lastOutZ = nil, nil  -- Память для проверки прыжков
local SMOOTH_K = 0.35               -- Коэффициент плавности (чем меньше, тем мягче ход самолета)

-- === УМНЫЙ СЕТЕВОЙ ПОИСК МОДЕМА ===
local modemSide = nil
for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        rednet.open(side)
        break
    end
end

if not modemSide then
    local networkModem = peripheral.find("modem")
    if networkModem then
        modemSide = peripheral.getName(networkModem)
        rednet.open(modemSide)
    end
end

local function saveConfig(cfg)
    local f = fs.open(configPath, "w")
    f.write(textutils.serialize(cfg))
    f.close()
end

local function loadConfig()
    if fs.exists(configPath) then
        local f = fs.open(configPath, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data
    end
    return nil
end

local function askNumber(prompt)
    while true do
        term.clear()
        term.setCursorPos(1,1)
        print("=== GPS AUTOCALIBRATION ===")
        write(prompt .. ": ")
        local input = tonumber(read())
        if input then return input end
        print("Error: Invalid number!")
        sleep(1)
    end
end

config = loadConfig()
if not config then
    config = {}
    config.x14 = askNumber("Ground Beacon 1 (Lowest ID Table): X")
    config.z14 = askNumber("Ground Beacon 1 (Lowest ID Table): Z")
    config.x15 = askNumber("Ground Beacon 2 (Middle ID Table): X")
    config.z15 = askNumber("Ground Beacon 2 (Middle ID Table): Z")
    config.x16 = askNumber("Ground Beacon 3 (Highest ID Table): X")
    config.z16 = askNumber("Ground Beacon 3 (Highest ID Table): Z")
    saveConfig(config)
end

-- === МАТЕМАТИЧЕСКИ ТОЧНАЯ БОРТОВАЯ ПЕЛЕНГАЦИЯ (БЛОК В БЛОК) ===
local function findPlanePosition(A, B, C, deg14, deg15, deg16)
    local bestX, bestZ, bestH
    local minError = 1e9

    -- Переводим относительные углы столов Create в радианы от носа самолета
    local alpha14 = math.rad(deg14 - 90)
    local alpha15 = math.rad(deg15 - 90)
    local alpha16 = math.rad(deg16 - 90)

    -- ШАГ 1: Грубый поиск курса (всего 180 итераций, разгружает CPU)
    for hDeg = 0, 360, 2 do
        local H = math.rad(hDeg)
        
        -- ИСПРАВЛЕНО: Инвертируем знак курса Lua, чтобы синхронизировать 
        -- вращение осей с ходом часовой стрелки Minecraft, а пеленг стола прибавляем!
        local psi14 = -H + alpha14
        local psi15 = -H + alpha15
        local psi16 = -H + alpha16

        -- Коэффициенты Крамера строго под сетку осей мира игры (X, Z)
        local a1, b1 = -math.sin(psi14), math.cos(psi14)
        local c1 = a1 * A.x + b1 * A.z
        local a2, b2 = -math.sin(psi15), math.cos(psi15)
        local c2 = a2 * B.x + b2 * B.z
        local D = a1 * b2 - a2 * b1
        
        if math.abs(D) > 0.001 then
            local x = (c1 * b2 - c2 * b1) / D
            local z = (a1 * c2 - a2 * c1) / D
            local a3, b3 = -math.sin(psi16), math.cos(psi16)
            local c3 = a3 * C.x + b3 * C.z
            local err = math.abs(a3 * x + b3 * z - c3)
            
            if err < minError then
                minError = err
                bestX = x
                bestZ = z
                bestH = hDeg
            end
        end
    end

    -- ШАГ 2: Точечный точный поиск вокруг лучшего угла
    if bestH then
        local startH = bestH - 3
        local endH = bestH + 3
        for hDeg = startH, endH, 0.1 do
            local H = math.rad(hDeg)
            local psi14 = -H + alpha14
            local psi15 = -H + alpha15
            local psi16 = -H + alpha16

            local a1, b1 = -math.sin(psi14), math.cos(psi14)
            local c1 = a1 * A.x + b1 * A.z
            local a2, b2 = -math.sin(psi15), math.cos(psi15)
            local c2 = a2 * B.x + b2 * B.z
            local D = a1 * b2 - a2 * b1
            
            if math.abs(D) > 0.001 then
                local x = (c1 * b2 - c2 * b1) / D
                local z = (a1 * c2 - a2 * c1) / D
                local a3, b3 = -math.sin(psi16), math.cos(psi16)
                local c3 = a3 * C.x + b3 * C.z
                local err = math.abs(a3 * x + b3 * z - c3)
                
                if err < minError then
                    minError = err
                    bestX = x
                    bestZ = z
                    bestH = hDeg
                end
            end
        end
    end

    return math.floor(bestX or 0), math.floor(bestZ or 0), math.floor(bestH or 0)
end


local navTimer = os.startTimer(0.1)
while true do
    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == navTimer then
        
        -- === УНИВЕРСАЛЬНЫЙ ОПРОС БОРТОВЫХ СТОЛОВ С ЦИФРОВОЙ СОРТИРОВКОЙ ===
        local deg14, deg15, deg16 = nil, nil, nil
        local allTables = { peripheral.find("navigation_table") }

        local function getTableId(peripheralObj)
            local name = peripheral.getName(peripheralObj)
            local idStr = name:match("(%d+)")
            return tonumber(idStr) or 0
        end

        table.sort(allTables, function(a, b)
            return getTableId(a) < getTableId(b)
        end)

        -- Точечный опрос элементов отсортированного массива
        if #allTables >= 3 then
            local ok1, d1 = pcall(allTables[1].getRelativeAngle)
            local ok2, d2 = pcall(allTables[2].getRelativeAngle)
            local ok3, d3 = pcall(allTables[3].getRelativeAngle)

            if ok1 and type(d1) == "number" then deg14 = d1 end
            if ok2 and type(d2) == "number" then deg15 = d2 end
            if ok3 and type(d3) == "number" then deg16 = d3 end
        end

        term.clear()
        term.setCursorPos(1,1)
        print("=== AIR NAVIGATION COMPUTER ===")
        
        local activeLinks = 0
        if deg14 then activeLinks = activeLinks + 1 end
        if deg15 then activeLinks = activeLinks + 1 end
        if deg16 then activeLinks = activeLinks + 1 end
        print("Connected onboard tables: " .. activeLinks .. "/3")

        -- Запуск расчета
        if deg14 and deg15 and deg16 then
            local A = { x = config.x14, z = config.z14 }
            local B = { x = config.x15, z = config.z15 }
            local C = { x = config.x16, z = config.z16 }

            local plX, plZ, heading = findPlanePosition(A, B, C, deg14, deg15, deg16)

            -- === АВИАЦИОННЫЙ ФИЛЬТР С ЗАЩИТОЙ ОТ ЗАСТРЕВАНИЯ ===
            local sendX, sendZ = plX, plZ

            if not lastOutX or not lastOutZ then
                lastOutX = plX
                lastOutZ = plZ
                config.stuckTicks = 0
            else
                local deltaDist = math.sqrt((plX - lastOutX)^2 + (plZ - lastOutZ)^2)

                if deltaDist < 60 then
                    lastOutX = lastOutX + (plX - lastOutX) * SMOOTH_K
                    lastOutZ = lastOutZ + (plZ - lastOutZ) * SMOOTH_K
                    config.stuckTicks = 0
                else
                    config.stuckTicks = (config.stuckTicks or 0) + 1
                    
                    if config.stuckTicks > 10 then
                        lastOutX = plX
                        lastOutZ = plZ
                        config.stuckTicks = 0
                    end
                end
                
                sendX = math.floor(lastOutX + 0.5)
                sendZ = math.floor(lastOutZ + 0.5)
            end
            -- ======================================================

            term.setTextColor(colors.green)
            print("PLANE X: " .. tostring(sendX))
            print("PLANE Z: " .. tostring(sendZ))
            term.setTextColor(colors.white)
            print("Calculated Heading: " .. tostring(heading) .. " deg")

            if modemSide then
                local packet = {
                    key = 1111,
                    x = sendX,
                    z = sendZ
                }
                rednet.broadcast(packet, "NAV_RADAR")
                rednet.broadcast(packet, "AIR_TRAFFIC")
                
                term.setTextColor(colors.yellow)
                print("Status: PACKETS SENT TO COCKPIT")
                term.setTextColor(colors.white)
            end
        else
            term.setTextColor(colors.red)
            print("Error: Waiting for beacon signals...")
            print(" Active numeric links: " .. activeLinks .. " of 3.")
            term.setTextColor(colors.white)
        end

        if not modemSide then
            term.setTextColor(colors.red)
            print("Warning: NO WIRED MODEM FOUND!")
            term.setTextColor(colors.white)
        end

        print("\n[R] Reset Beacon Coordinates")
        navTimer = os.startTimer(0.1)
    elseif event == "key" and p1 == keys.r then
        fs.delete(configPath)
        os.reboot()
    end
end

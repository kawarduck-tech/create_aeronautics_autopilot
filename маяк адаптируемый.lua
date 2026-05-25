-- ============================================
-- GROUND RADAR SYSTEM V3.5 (MULTI-POINT)
-- ============================================

local configPath = "/radar_cfg.txt"
rednet.open("bottom")

local nav = peripheral.find("navigation_table")
if not nav then error("Navigation Table NOT found!") end

local config = {}
local sensors = {} -- Для Мозга: база всех маяков

-- 1. ФУНКЦИИ ПАМЯТИ
function saveConfig(cfg)
    local f = fs.open(configPath, "w")
    f.write(textutils.serialize(cfg))
    f.close()
end

function loadConfig()
    if fs.exists(configPath) then
        local f = fs.open(configPath, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data
    end
    return nil
end

-- 2. ФУНКЦИЯ ВВОДА
function askNumber(prompt)
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("=== RADAR SETUP V3.5 ===")
    write(prompt .. ": ")
    local input = tonumber(read())
    if input then return input end
    print("Error: Invalid number!")
    sleep(1)
  end
end

-- 3. ЗАГРУЗКА И НАСТРОЙКА
config = loadConfig()
if not config then
    config = {}
    config.role = askNumber("1. Brain (Master), 2. Sensor (Slave)")
    config.myX = askNumber("Enter MY X")
    config.myZ = askNumber("Enter MY Z")
    config.passkey = askNumber("Enter PASSKEY")

    if config.role == 1 then
        config.targetID = askNumber("Enter PLANE Computer ID")
    else
        config.partnerID = askNumber("Enter BRAIN ID")
    end
    saveConfig(config)
end

-- 4. МАТЕМАТИКА ТРИАНГУЛЯЦИИ (ДИНАМИЧЕСКАЯ)
function calculatePlane(x1, z1, ang1, x2, z2, ang2)
  local radA, radB = math.rad(ang1), math.rad(ang2)
  local tanA, tanB = math.tan(radA), math.tan(radB)
  if math.abs(tanA - tanB) < 0.001 then return 0, 0, false end
  local planeX = (z2 - z1 + x1 * tanA - x2 * tanB) / (tanA - tanB)
  local planeZ = z1 + (planeX - x1) * tanA
  return math.floor(planeX), math.floor(planeZ), true
end

-- 5. ОСНОВНОЙ ЦИКЛ
local radarTimer = os.startTimer(0.1)

while true do
  local event, p1, p2, p3 = os.pullEvent()

  -- Обновление данных по таймеру
  if event == "timer" and p1 == radarTimer then
    local myAngle = nav.getRelativeAngle() or 0
    term.clear()
    term.setCursorPos(1,1)

    if config.role == 1 then
      print("=== RADAR BRAIN (MASTER) ===")
      
      -- Ищем лучший сенсор из списка активных
      local bestID, maxDiff = nil, 0
      local activeCount = 0
      
      for id, data in pairs(sensors) do
        if os.clock() - data.time < 3 then -- Сенсор "жив" 3 секунды
            activeCount = activeCount + 1
            local diff = math.abs(myAngle - data.angle) % 180
            if diff > 90 then diff = 180 - diff end
            if diff > maxDiff then
                maxDiff = diff
                bestID = id
            end
        end
      end

      print("Active Sensors: " .. activeCount)
      print("My Pos: " .. config.myX .. " / " .. config.myZ)
      print("---------------------")

      if bestID then
        local s = sensors[bestID]
        local plX, plZ, success = calculatePlane(config.myX, config.myZ, myAngle, s.x, s.z, s.angle)
        
        if success then
          term.setTextColor(colors.green)
          print("PLANE X: " .. plX .. " Z: " .. plZ)
          term.setTextColor(colors.white)
          print("Using Sensor ID: " .. bestID)
          
          -- Отправляем координаты самолету
          rednet.send(config.targetID, {x = plX, z = plZ, key = config.passkey}, "AIR_TRAFFIC") 
        end
      else
        print("Waiting for Sensor data...")
      end
      
    else
      -- ЛОГИКА СЕНСОРА
      print("=== RADAR SENSOR (SLAVE) ===")
      print("My Pos: " .. config.myX .. " / " .. config.myZ)
      print("Angle: " .. string.format("%.2f", myAngle))
      print("Target Brain: " .. config.partnerID)
      
      -- Сенсор шлет данные Мозгу
      rednet.send(config.partnerID, {
        angle = myAngle, 
        x = config.myX, 
        z = config.myZ, 
        key = config.passkey
      }, "RADAR_DATA")
    end

    print("\n[R] Reset Config")
    radarTimer = os.startTimer(0.1)

  -- Прием данных от сенсоров (только для Мозга)
  elseif event == "rednet_message" and p3 == "RADAR_DATA" then
    if config.role == 1 and type(p2) == "table" and p2.key == config.passkey then
        sensors[p1] = {angle = p2.angle, x = p2.x, z = p2.z, time = os.clock()}
    end

  -- Сброс настроек
  elseif event == "key" and p1 == keys.r then
      fs.delete(configPath)
      os.reboot()
  end
end

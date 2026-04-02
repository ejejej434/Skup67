script_name("LMMR")
script_author("major")
script_version("1.8.2")

local imgui_status, imgui = pcall(require, 'mimgui')
local encoding_status, encoding = pcall(require, 'encoding')
local ffi = require('ffi')
local sampev_status, sampev = pcall(require, 'samp.events')
local webviews_status, lib = pcall(require, 'WebViews')
local json = pcall(require, "json") and require("json") or {
    encode = encodeJson,
    decode = decodeJson
}

if not imgui_status then
    return
end

if encoding_status then
    encoding.default = 'CP1251'
end

local u8
if encoding_status and encoding and encoding.UTF8 then
    u8 = encoding.UTF8
else
    u8 = setmetatable({
        decode = function(_, str)
            return str or ""
        end
    }, {
        __call = function(_, str)
            return str or ""
        end
    })
end

local configDir = getWorkingDirectory() .. '/config/'
local filePath = configDir .. 'main.json'
local dbPath = configDir .. 'items_db.json'
local logsPath = configDir .. 'logs_db.json'

if not doesDirectoryExist(configDir) then
    createDirectory(configDir)
end

-- ============================================================================
-- ÓÒÈËÈÒÛ
-- ============================================================================

local function ru_lower(str)
    local res = {}
    for i = 1, #str do
        local b = string.byte(str, i)
        if b >= 65 and b <= 90 then 
            res[i] = string.char(b + 32)
        elseif b >= 192 and b <= 223 then 
            res[i] = string.char(b + 32)
        elseif b == 168 then 
            res[i] = string.char(184) 
        else
            res[i] = string.char(b)
        end
    end
    return table.concat(res)
end

local function safe_copy(dest, src, max_len)
    if src == nil then src = "" end
    local str = tostring(src)
    if #str >= max_len then
        str = string.sub(str, 1, max_len - 1)
    end
    ffi.copy(dest, str)
end

-- ============================================================================
-- ÑÎÑÒÎßÍÈÅ È ÏÅÐÅÌÅÍÍÛÅ
-- ============================================================================

local STATE = {
    isRunning = false,
    isScanning = false,
    isSelling = false,
    stopProcess = false,
    waitingForInventory = false
}

local UI = {
    CentralGlMenu = imgui.new.bool(false),
    show_custom_lavka = imgui.new.bool(false),
    currentTab = 1,
    open_add_modal = false,
    open_sell_modal = false,
    editIndex = -1,
    sellEditIndex = -1
}

local AUTH = {
    isAuthorized = false,
    authError = false
}

local BUFFERS = {
    authKey = imgui.new.char[256](""),
    search = imgui.new.char[256](""),
    sellSearch = imgui.new.char[256](""),
    addName = imgui.new.char[256](""),
    addId = imgui.new.char[64](""),
    addPrice = imgui.new.char[64](""),
    addAmount = imgui.new.char[64]("1"),
    addIsAccessory = imgui.new.bool(false),
    profileName = imgui.new.char[256](""),
    sellPrice = imgui.new.char[64](""),
    sellAmount = imgui.new.char[64]("1"),
    sellIsAccessory = imgui.new.bool(false)
}

local PAGING = {
    currentPage = 1,
    itemsPerPage = 100
}

local POSITIONS = {
    win_posX = imgui.new.float(-1),
    win_posY = imgui.new.float(-1),
    btn_posX = imgui.new.float(-1),
    btn_posY = imgui.new.float(-1),
    is_btn_dragging = false,
    is_win_dragging = false,
    global_drag_active = false
}

local active_preset_name = ""

local storage = {
    settings = {
        win_W = 950,
        win_H = 600,
        accent = {0.14, 0.45, 0.90},
        background = {0.07, 0.07, 0.08},
        saved_key = "",
        show_btn = false,
        btn_color = {0.14, 0.45, 0.90},
        btn_size = 55.0,
        global_delay = 1200,
        menu_opacity = 1.0,
        fps_boost = false,
        auto_clean = false
    },
    items = {},
    sell_items = {},
    profiles = {}
}

local vars = {}
local sell_vars = {}
local session_inv = {}

local logs = {}
local log_dates = {}
local selected_date = ""

local item_db = {}
local filtered_cache = {}
local last_search = nil

local win_W = imgui.new.float(storage.settings.win_W)
local win_H = imgui.new.float(storage.settings.win_H)
local cAcc = imgui.new.float[3]({
    storage.settings.accent[1],
    storage.settings.accent[2],
    storage.settings.accent[3]
})
local cBg = imgui.new.float[3]({
    storage.settings.background[1],
    storage.settings.background[2],
    storage.settings.background[3]
})
local show_screen_btn = imgui.new.bool(storage.settings.show_btn)
local cBtn = imgui.new.float[3]({
    storage.settings.btn_color[1],
    storage.settings.btn_color[2],
    storage.settings.btn_color[3]
})
local btn_size = imgui.new.float(storage.settings.btn_size or 55.0)
local global_delay = imgui.new.int(storage.settings.global_delay or 1200)
local menu_opacity = imgui.new.float(storage.settings.menu_opacity or 1.0)
local fps_boost = imgui.new.bool(storage.settings.fps_boost or false)
local auto_clean = imgui.new.bool(storage.settings.auto_clean or false)

local script_keys = (function() local _A={ {75,57,70,50,65,49,66,56,67,55,68,54,69,53,71,52}, {72,51,74,50,75,49,76,57,77,56,78,55,80,54,81,53}, {82,52,83,53,84,54,85,55,86,56,87,57,88,49,89,50}, {90,51,65,52,66,53,67,54,68,55,69,56,70,57,71,48}, {81,49,87,50,69,51,82,52,84,53,89,54,85,55,73,56}, {79,57,80,48,65,49,83,50,68,51,70,52,71,53,72,54}, {74,55,75,56,76,57,90,48,88,49,67,50,86,51,66,52}, {78,53,77,54,81,55,87,56,69,57,82,48,84,49,89,50}, {85,51,73,52,79,53,80,54,65,55,83,56,68,57,70,48}, {71,49,72,50,74,51,75,52,76,53,90,54,88,55,67,56} } local _B={} for _C=1,#_A do local _D="" for _E=1,#_A[_C] do _D=_D..string.char(_A[_C][_E]) end _B[_C]=_D end return _B end)()

-- ============================================================================
-- ÐÀÁÎÒÀ Ñ ËÎÃÀÌÈ
-- ============================================================================

function load_logs()
    logs = {}
    log_dates = {}
    selected_date = ""
    
    if doesFileExist(logsPath) then
        local file = io.open(logsPath, "r")
        if file then
            local status, decoded = pcall(json.decode, file:read("*a"))
            file:close()
            if status and type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    if type(k) == "string" and type(v) == "table" then
                        logs[k] = v
                    end
                end
            end
        end
    end
    
    for k, v in pairs(logs) do 
        table.insert(log_dates, tostring(k)) 
    end
    
    table.sort(log_dates, function(a, b) return tostring(a) > tostring(b) end)
    
    if #log_dates > 0 then 
        selected_date = log_dates[1] 
    end
end

function save_logs()
    local file = io.open(logsPath, "w")
    if file then
        file:write(json.encode(logs))
        file:close()
    end
end

function addLog(text)
    local today = os.date("%Y-%m-%d")
    if not logs[today] then
        logs[today] = {}
        table.insert(log_dates, 1, today)
        table.sort(log_dates, function(a, b) return tostring(a) > tostring(b) end)
        if selected_date == "" then selected_date = today end
    end
    table.insert(logs[today], 1, os.date("[%H:%M] ") .. text)
    if #logs[today] > 100 then table.remove(logs[today]) end
    save_logs()
end

-- ============================================================================
-- ÎÁÐÀÁÎÒ×ÈÊÈ ÑÎÁÛÒÈÉ SAMP
-- ============================================================================

if sampev_status then
    function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
        if dialogId == 9 and not STATE.isRunning then
            UI.show_custom_lavka[0] = true
            return false
        end
    end
end

-- ============================================================================
-- ÐÀÁÎÒÀ Ñ ÁÀÇÎÉ ÏÐÅÄÌÅÒÎÂ
-- ============================================================================

function load_item_db()
    item_db = {}
    last_search = nil 
    if doesFileExist(dbPath) then
        local file = io.open(dbPath, "r")
        if file then
            local status, decoded = pcall(json.decode, file:read("*a"))
            file:close()
            if status and type(decoded) == "table" then
                for _, v in ipairs(decoded) do
                    local decoded_name = u8:decode(v.name or "")
                    local decoded_id = u8:decode(v.id or "")
                    local dspName = decoded_id ~= "" and (decoded_name .. " [" .. decoded_id .. "]") or decoded_name
                    
                    table.insert(item_db, {
                        name = decoded_name,
                        lower_name = ru_lower(decoded_name),
                        id = decoded_id,
                        u8_name = u8(decoded_name),
                        u8_id = u8(decoded_id),
                        dsp_name = u8(dspName)
                    })
                end
            end
        end
    end
end

function save_item_db()
    local file = io.open(dbPath, "w")
    if file then
        local t = {}
        for _, v in ipairs(item_db) do
            table.insert(t, {
                name = v.u8_name,
                id = v.u8_id
            })
        end
        file:write(json.encode(t))
        file:close()
    end
end

-- ============================================================================
-- ÀÂÒÎÑÊÀÍÈÐÎÂÀÍÈÅ ÁÀÇÛ ÏÐÅÄÌÅÒÎÂ
-- ============================================================================

function runAutoScan()
    if STATE.isScanning then return end
    STATE.isScanning = true
    STATE.stopProcess = false
    lua_thread.create(function()
        if not sampIsDialogActive() then
            STATE.isScanning = false
            return
        end
        
        local seen_items = {}
        for _, v in ipairs(item_db) do
            if v.id ~= "" then
                seen_items[v.id] = true
            else
                seen_items[v.name] = true
            end
        end

        local pagesScanned = 0
        while sampIsDialogActive() and not STATE.stopProcess do
            local curId = sampGetCurrentDialogId()
            local text = sampGetDialogText()
            if not text or text == "" then break end
            
            local lines = {}
            for line in text:gmatch("[^\r\n]+") do
                table.insert(lines, line)
            end
            
            local nextPageIdx = -1
            for i, line in ipairs(lines) do
                local cleanLine = line:gsub("{%x%x%x%x%x%x}", "")
                local rawName = cleanLine:match("^%s*([^\t]+)")
                if rawName then
                    rawName = rawName:match("^%s*(.-)%s*$")
                    if rawName == "Äàëåå" or rawName:find(">>>") or rawName:find("Ñëåäóþùàÿ") then
                        nextPageIdx = i - 1
                    elseif rawName ~= "Ïîèñê ïðåäìåòà ïî íàçâàíèþ / èíäåêñó"
                        and rawName ~= "Ïîèñê ïî êàòåãîðèè / Âåñü ñïèñîê |"
                        and rawName ~= "Íàçàä"
                        and rawName ~= "Çàêðûòü" then
                        
                        local namePart, idPart = rawName:match("^(.-)%s*%[(%d+)%]$")
                        if not namePart then
                            namePart, idPart = rawName:match("^(.-)%s*%((%d+)%)$")
                        end
                        
                        if namePart and idPart then
                            if not seen_items[idPart] then
                                seen_items[idPart] = true
                                local dspName = namePart .. " [" .. idPart .. "]"
                                table.insert(item_db, {
                                    name = namePart, 
                                    lower_name = ru_lower(namePart), 
                                    id = idPart,
                                    u8_name = u8(namePart),
                                    u8_id = u8(idPart),
                                    dsp_name = u8(dspName)
                                })
                            end
                        else
                            if not seen_items[rawName] then
                                seen_items[rawName] = true
                                table.insert(item_db, {
                                    name = rawName, 
                                    lower_name = ru_lower(rawName), 
                                    id = "",
                                    u8_name = u8(rawName),
                                    u8_id = "",
                                    dsp_name = u8(rawName)
                                })
                            end
                        end
                    end
                end
            end
            pagesScanned = pagesScanned + 1
            if nextPageIdx ~= -1 then
                sampSendDialogResponse(curId, 1, nextPageIdx, "")
                wait(1200)
            else
                break
            end
        end
        save_item_db()
        last_search = nil 
        STATE.isScanning = false
    end)
end

-- ============================================================================
-- ÑÎÕÐÀÍÅÍÈÅ / ÇÀÃÐÓÇÊÀ MAIN JSON
-- ============================================================================

function save_main_json()
    storage.settings = storage.settings or {}
    storage.items = {}
    storage.sell_items = {}
    storage.profiles = storage.profiles or {}

    storage.settings.win_W = win_W[0]
    storage.settings.win_H = win_H[0]
    storage.settings.accent = {cAcc[0], cAcc[1], cAcc[2]}
    storage.settings.background = {cBg[0], cBg[1], cBg[2]}
    storage.settings.saved_key = AUTH.isAuthorized and ffi.string(BUFFERS.authKey) or ""
    storage.settings.show_btn = show_screen_btn[0]
    storage.settings.btn_color = {cBtn[0], cBtn[1], cBtn[2]}
    storage.settings.btn_size = btn_size[0]
    storage.settings.fps_boost = fps_boost[0]
    storage.settings.auto_clean = auto_clean[0]
    storage.settings.global_delay = global_delay[0]
    storage.settings.menu_opacity = menu_opacity[0]

    storage.settings.win_posX = POSITIONS.win_posX[0]
    storage.settings.win_posY = POSITIONS.win_posY[0]
    storage.settings.pos_converted = true
    storage.settings.btn_posX = POSITIONS.btn_posX[0]
    storage.settings.btn_posY = POSITIONS.btn_posY[0]

    for _, v in ipairs(vars) do
        table.insert(storage.items, {
            name = u8:decode(v.str_name),
            id = u8:decode(v.str_id),
            price = u8:decode(v.str_price),
            amount = u8:decode(v.str_amount),
            active = v.active[0],
            is_acc = v.is_acc[0]
        })
    end

    for _, v in ipairs(sell_vars) do
        table.insert(storage.sell_items, {
            slot = v.slot,
            item_name = v.item_name,
            item_type = v.item_type,
            price = u8:decode(v.str_price),
            amount = u8:decode(v.str_amount),
            active = v.active[0],
            is_acc = v.is_acc[0]
        })
    end

    local file = io.open(filePath, "w")
    if file then
        file:write(json.encode(storage))
        file:close()
    end
end

function load_main_json()
    if not doesFileExist(filePath) then return end
    local file = io.open(filePath, "r")
    if file then
        local status, decoded = pcall(json.decode, file:read("*a"))
        file:close()
        if status and decoded then
            storage = decoded
            storage.profiles = decoded.profiles or {}
            storage.sell_items = decoded.sell_items or {}
            
            win_W[0] = storage.settings.win_W or 950
            win_H[0] = storage.settings.win_H or 600
            
            local loaded_key = storage.settings.saved_key or ""
            AUTH.isAuthorized = false
            for _, k in ipairs(script_keys) do
                if loaded_key == k then
                    AUTH.isAuthorized = true
                    break
                end
            end
            if storage.settings.accent then
                cAcc[0], cAcc[1], cAcc[2] = unpack(storage.settings.accent)
            end
            if storage.settings.background then
                cBg[0], cBg[1], cBg[2] = unpack(storage.settings.background)
            end
            if storage.settings.show_btn ~= nil then
                show_screen_btn[0] = storage.settings.show_btn
            end
            if storage.settings.btn_color then
                cBtn[0], cBtn[1], cBtn[2] = unpack(storage.settings.btn_color)
            end
            if storage.settings.btn_size then
                btn_size[0] = storage.settings.btn_size
            end
            if storage.settings.global_delay then
                global_delay[0] = storage.settings.global_delay
            end
            if storage.settings.menu_opacity then
                menu_opacity[0] = storage.settings.menu_opacity
            end
            
            vars = {}
            for _, item in ipairs(storage.items or {}) do
                table.insert(vars, {
                    name = imgui.new.char[256](string.sub(u8(item.name or ""), 1, 255)),
                    id = imgui.new.char[64](string.sub(u8(item.id or ""), 1, 63)),
                    price = imgui.new.char[64](string.sub(u8(item.price or "0"), 1, 63)),
                    amount = imgui.new.char[64](string.sub(u8(item.amount or "1"), 1, 63)),
                    active = imgui.new.bool(item.active or false),
                    is_acc = imgui.new.bool(item.is_acc or false),
                    str_name = u8(item.name or ""),
                    str_id = u8(item.id or ""),
                    str_price = u8(item.price or "0"),
                    str_amount = u8(item.amount or "1")
                })
            end
            
            sell_vars = {}
            for _, item in ipairs(storage.sell_items or {}) do
                table.insert(sell_vars, {
                    slot = item.slot or 0,
                    item_name = item.item_name or "Íåèçâåñòíî",
                    item_type = item.item_type or 1,
                    price = imgui.new.char[64](string.sub(u8(item.price or "0"), 1, 63)),
                    amount = imgui.new.char[64](string.sub(u8(item.amount or "1"), 1, 63)),
                    active = imgui.new.bool(item.active or false),
                    is_acc = imgui.new.bool(item.is_acc or false),
                    str_price = u8(item.price or "0"),
                    str_amount = u8(item.amount or "1")
                })
            end
        end
    end
end

-- ============================================================================
-- ÏÐÎÖÅÑÑ ÀÂÒÎ-ÇÀÊÓÏÊÈ
-- ============================================================================

function runBuyingProcess()
    if #vars == 0 then return end
    
    local buy_queue = {}
    for _, v in ipairs(vars) do
        if v.active[0] then
            table.insert(buy_queue, {
                id = u8:decode(v.str_id),
                name = u8:decode(v.str_name),
                price = u8:decode(v.str_price),
                amount = u8:decode(v.str_amount),
                is_acc = v.is_acc[0]
            })
        end
    end
    
    if #buy_queue == 0 then return end

    STATE.isRunning = true
    STATE.stopProcess = false
    lua_thread.create(function()
        for i, item in ipairs(buy_queue) do
            if STATE.stopProcess then break end
            
            local query = (item.id ~= "" and item.id) or item.name
            local send_data = ""
            if item.is_acc then
                send_data = item.price .. "," .. item.amount
            else
                send_data = item.amount .. "," .. item.price
            end

            sampSendDialogResponse(9, 1, 1, "")
            wait(global_delay[0])
            if STATE.stopProcess then break end
            
            sampSendDialogResponse(10, 1, 0, "")
            wait(global_delay[0])
            if STATE.stopProcess then break end
            
            sampSendDialogResponse(909, 1, 0, query)
            wait(global_delay[0] + 600)
            if STATE.stopProcess then break end
            
            sampSendDialogResponse(11, 1, 0, send_data)
            wait(global_delay[0] + 500)
        end
        STATE.isRunning = false
    end)
end

-- ============================================================================
local function resolveBrowserId()
    if STATE.browserId then
        return STATE.browserId
    end
    if not webviews_status or not lib then
        return nil
    end

    local candidates = {
        function() return lib.getBrowserId and lib.getBrowserId() end,
        function() return lib.getActiveBrowser and lib.getActiveBrowser() end,
        function() return lib.getCurrentBrowser and lib.getCurrentBrowser() end,
        function() return lib.getFocusedBrowser and lib.getFocusedBrowser() end
    }

    for _, fn in ipairs(candidates) do
        local ok, id = pcall(fn)
        if ok and id then
            STATE.browserId = tonumber(id) or id
            return STATE.browserId
        end
    end

    return nil
end

local function parseInventoryJson(jsonStr)
    if not jsonStr or jsonStr == '' then
        return {}
    end

    local ok, decoded = pcall(json.decode, jsonStr)
    if not ok or type(decoded) ~= 'table' then
        return {}
    end

    local items = decoded.items or decoded.inventory or decoded.bag or decoded.slots or decoded
    local out = {}
    if type(items) == 'table' then
        for idx, item in ipairs(items) do
            if type(item) == 'table' then
                table.insert(out, {
                    name = item.name or item.itemName or 'Unknown',
                    slot = tonumber(item.slot) or (idx - 1),
                    count = tonumber(item.count or item.amount) or 1,
                    item_id = tonumber(item.itemId or item.id) or 0
                })
            end
        end
    end
    return out
end

function scanInventory()
    if STATE.isScanning then return end

    STATE.isScanning = true
    lua_thread.create(function()
        session_inv = {}
        local browserId = resolveBrowserId()
        if browserId and webviews_status and lib and lib.getJSValue then
            local ok, payload = pcall(lib.getJSValue, browserId, "JSON.stringify(window.inventory && window.inventory.items ? window.inventory.items : [])")
            if ok and payload and payload ~= '' and payload ~= 'null' then
                session_inv = parseInventoryJson(payload)
            end
        end

        if #session_inv == 0 then
            STATE.waitingForInventory = true
            sampSendChat("/invent")
            local timeout = 50
            while STATE.waitingForInventory and timeout > 0 do
                wait(100)
                timeout = timeout - 1
            end
            if timeout <= 0 then
                STATE.waitingForInventory = false
            end
        end

        STATE.isScanning = false
    end)
end

-- ÑÊÀÍÈÐÎÂÀÍÈÅ ÈÍÂÅÍÒÀÐß
-- ============================================================================

local function readJsonFromBitStream(bs)
    -- ÊÐÈÒÈ×ÅÑÊÈ ÂÀÆÍÎ: ñîõðàíÿåì òåêóùèé îôôñåò
    local currentOffset = raknetBitStreamGetReadOffset(bs)
    
    -- Îáðàáîòêà ñ çàùèòîé óêàçàòåëÿ
    local function safeReturn(success, data, errorMsg)
        -- ÂÑÅÃÄÀ âîçâðàùàåì óêàçàòåëü íà ìåñòî ïåðåä âûõîäîì
        raknetBitStreamSetReadOffset(bs, currentOffset)
        
        if success then
            return {success = true, data = data}
        else
            return {success = false, error = errorMsg or "Unknown error"}
        end
    end
    
    -- ×èòàåì çàãîëîâîê (2 áàéòà)
    local header1 = raknetBitStreamReadInt8(bs)
    if not header1 then
        return safeReturn(false, nil, "Failed to read header1")
    end
    
    local header2 = raknetBitStreamReadInt8(bs)
    if not header2 then
        return safeReturn(false, nil, "Failed to read header2")
    end
    
    -- ×èòàåì äëèíó JSON êàê 32-áèòíîå ÷èñëî
    local dataLen = raknetBitStreamReadInt32(bs)
    if not dataLen or dataLen <= 0 or dataLen > 65535 then
        return safeReturn(false, nil, "Invalid data length: " .. tostring(dataLen))
    end
    
    -- ×èòàåì JSON ñòðîêó ÖÅËÈÊÎÌ (ÍÅ ïîáàéòîâî!)
    local jsonStr = raknetBitStreamReadString(bs, dataLen)
    if not jsonStr or jsonStr == "" then
        return safeReturn(false, nil, "Failed to read JSON string")
    end
    
    -- Äåêîäèðóåì JSON
    local status, decoded = pcall(json.decode, jsonStr)
    if not status or not decoded then
        return safeReturn(false, nil, "JSON decode failed: " .. tostring(decoded))
    end
    
    -- Óñïåøíûé âîçâðàò (óêàçàòåëü âñå ðàâíî âîññòàíàâëèâàåòñÿ)
    return safeReturn(true, decoded, nil)
end

local function isInventoryData(data)
    if type(data) ~= "table" then
        return false
    end
    
    -- Ïðîâåðÿåì êëþ÷è èíâåíòàðÿ
    if data.items and type(data.items) == "table" then
        return true
    end
    if data.inventory and type(data.inventory) == "table" then
        return true
    end
    if data.bag and type(data.bag) == "table" then
        return true
    end
    if data.slots and type(data.slots) == "table" then
        return true
    end
    
    -- Ïðîâåðÿåì action äëÿ èíâåíòàðÿ
    if data.action then
        local invActions = {16, 17, 18, 19, 20, 21, 22}
        for _, act in ipairs(invActions) do
            if data.action == act then
                return true
            end
        end
    end
    
    return false
end

local function extractInventoryItems(data)
    if type(data) ~= "table" then
        return nil
    end
    
    -- Âàðèàíò 1: data.items
    if data.items and type(data.items) == "table" then
        return data.items
    end
    
    -- Âàðèàíò 2: data.inventory
    if data.inventory and type(data.inventory) == "table" then
        return data.inventory
    end
    
    -- Âàðèàíò 3: data.bag
    if data.bag and type(data.bag) == "table" then
        return data.bag
    end
    
    -- Âàðèàíò 4: data.slots
    if data.slots and type(data.slots) == "table" then
        return data.slots
    end
    
    -- Âàðèàíò 5: ñàì data ÿâëÿåòñÿ ìàññèâîì
    if data[1] and type(data[1]) == "table" then
        return data
    end
    
    return nil
end

if sampev_status then
    function sampev.onReceivePacket(packetId, bs)
        if packetId == 220 then
            local parsed = readJsonFromBitStream(bs)
            
            if parsed and parsed.success and parsed.data then
                local data = parsed.data
                
    scanInventory()
local function executeInventorySale(slot, price, amount)
    local browserId = resolveBrowserId()
    if not browserId or not webviews_status or not lib or not lib.executeJS then
        return false
    end

    local js = string.format([[;(function(){
        var slotId = %d;
        var price = %s;
        var amount = %s;
        if (window.inventory && inventory.selectSlot) {
            inventory.selectSlot(slotId);
        }
        if (window.inventory && inventory.confirmSale) {
            inventory.confirmSale(slotId, price, amount);
            return true;
        }
        return false;
    })();]], tonumber(slot) or 0, tostring(tonumber(price) or 0), tostring(tonumber(amount) or 1))

    local ok = pcall(lib.executeJS, browserId, js)
    return ok

                addLog("  " .. item.slot .. " -   !")

            local saleAmount, salePrice
                salePrice = item.price
                saleAmount = item.amount
                saleAmount = item.amount
                salePrice = item.price
            end

            local sold = executeInventorySale(item.slot, salePrice, saleAmount)
            if not sold then
                addLog("   " .. item.slot .. " - CEF WebView ")
            end
        end
    end
    return false
end

local function sendSlotSelectPacket(slot, itemType)
    lua_thread.create(function()
        wait(0)
        local bs = raknetNewBitStream()
        if bs then
            local jsonData = {
                slot = slot,
                type = itemType or 1
            }
            local jsonStr = json.encode(jsonData)
            
            -- Çàãîëîâîê ïàêåòà
            raknetBitStreamWriteInt8(bs, 0x3F)  -- 63
            raknetBitStreamWriteInt8(bs, 0x34)  -- '4'
            
            -- Äëèíà JSON êàê 32-áèòíîå ÷èñëî
            raknetBitStreamWriteInt32(bs, #jsonStr)
            
            -- JSON ñòðîêà öåëèêîì
            raknetBitStreamWriteString(bs, jsonStr)
            
            raknetSendBitStreamEx(bs, 2, 8, 0, false)
            raknetDeleteBitStream(bs)
        end
    end)
end

function runSellingProcess()
    if #sell_vars == 0 then return end
    
    local sell_queue = {}
    for _, v in ipairs(sell_vars) do
        if v.active[0] then
            table.insert(sell_queue, {
                slot = v.slot,
                item_name = v.item_name,
                item_type = v.item_type,
                price = u8:decode(v.str_price),
                amount = u8:decode(v.str_amount),
                is_acc = v.is_acc[0]
            })
        end
    end
    
    if #sell_queue == 0 then return end

    STATE.isSelling = true
    STATE.stopProcess = false
    lua_thread.create(function()
        for i, item in ipairs(sell_queue) do
            if STATE.stopProcess then break end
            
            -- Ïðîâåðêà ñëîòà ïåðåä ïðîäàæåé
            if not verifySlotItem(item.slot, item.item_name) then
                addLog("Ïðîïóùåí ñëîò " .. item.slot .. " - ïðåäìåò íå ñîâïàäàåò!")
                goto continue
            end
            
            -- Øàã 1: Îòêðûâàåì ìåíþ "Ïðîäàæà"
            sampSendDialogResponse(9, 1, 0, "")
            wait(global_delay[0])
            if STATE.stopProcess then break end
            
            -- Øàã 2: Îòïðàâëÿåì ïàêåò âûáîðà ñëîòà
            sendSlotSelectPacket(item.slot, item.item_type)
            wait(global_delay[0] + 300)
            if STATE.stopProcess then break end
            
            -- Øàã 3: Çàïîëíÿåì öåíó è êîëè÷åñòâî
            local send_data = ""
            if item.is_acc then
                send_data = item.price .. "," .. item.amount
            else
                send_data = item.amount .. "," .. item.price
            end
            
            sampSendDialogResponse(11, 1, 0, send_data)
            wait(global_delay[0] + 500)
            
            ::continue::
        end
        STATE.isSelling = false
    end)
end

-- ============================================================================
-- ÈÍÒÅÐÔÅÉÑ ImGui
-- ============================================================================

imgui.OnInitialize(function()
    load_main_json()
    UI.CentralGlMenu[0] = false
    load_item_db()
    load_logs()
    local style = imgui.GetStyle()
    style.WindowPadding = imgui.ImVec2(0, 0)
    style.WindowRounding = 18.0
    style.ChildRounding = 15.0
    style.FrameRounding = 10.0
    style.PopupRounding = 15.0
    style.ScrollbarSize = 5.0
    style.WindowBorderSize = 0.0
    style.ItemSpacing = imgui.ImVec2(12, 12)
end)

local function renderTab1()
    local halfW = (imgui.GetWindowWidth() / 2) - 10
    
    imgui.BeginChild("DB_Area", imgui.ImVec2(halfW, -1), true)
    imgui.PushItemWidth(-1)
    
    local q_changed = imgui.InputTextWithHint("##srch", u8"Ïîèñê...", BUFFERS.search, 256)
    imgui.PopItemWidth()
    
    if q_changed or last_search == nil then
        local current_q = ru_lower(u8:decode(ffi.string(BUFFERS.search)))
        last_search = current_q
        filtered_cache = {}
        for _, v in ipairs(item_db) do
            if not v.lower_name then
                v.lower_name = ru_lower(v.name)
            end
            
            if current_q == "" or v.lower_name:find(current_q, 1, true) or v.id:find(current_q, 1, true) then
                table.insert(filtered_cache, v)
            end
        end
        PAGING.currentPage = 1 
    end
    
    imgui.BeginChild("DbScroll", imgui.ImVec2(-1, -45))
    local start = (PAGING.currentPage - 1) * PAGING.itemsPerPage + 1
    for i = start, math.min(start + PAGING.itemsPerPage - 1, #filtered_cache) do
        if filtered_cache[i] then
            local item = filtered_cache[i]
            if imgui.Button(item.dsp_name .. "##db" .. i, imgui.ImVec2(-1, 35)) then
                if not POSITIONS.global_drag_active then
                    lua_thread.create(function()
                        wait(0)
                        safe_copy(BUFFERS.addName, item.u8_name, 256)
                        safe_copy(BUFFERS.addId, item.u8_id, 64)
                        safe_copy(BUFFERS.addPrice, "100", 64)
                        safe_copy(BUFFERS.addAmount, "1", 64)
                        BUFFERS.addIsAccessory[0] = false
                        UI.editIndex = -1
                        UI.open_add_modal = true
                    end)
                end
            end
        end
    end
    if imgui.IsWindowHovered(33) and imgui.IsMouseDragging(0, 0.0) then
        imgui.SetScrollY(imgui.GetScrollY() - imgui.GetIO().MouseDelta.y)
    end
    imgui.EndChild()
    
    local maxPages = math.max(1, math.ceil(#filtered_cache / PAGING.itemsPerPage))
    if imgui.Button("<", imgui.ImVec2(35, 30)) and not POSITIONS.global_drag_active and PAGING.currentPage > 1 then
        lua_thread.create(function()
            wait(0)
            PAGING.currentPage = PAGING.currentPage - 1
        end)
    end
    imgui.SameLine()
    imgui.Text(string.format("%d / %d", PAGING.currentPage, maxPages))
    imgui.SameLine()
    if imgui.Button(">", imgui.ImVec2(35, 30)) and not POSITIONS.global_drag_active and PAGING.currentPage < maxPages then
        lua_thread.create(function()
            wait(0)
            PAGING.currentPage = PAGING.currentPage + 1
        end)
    end
    imgui.EndChild()
    
    imgui.SameLine()
    
    imgui.BeginChild("Queue_Area", imgui.ImVec2(halfW, -1), true)
    if imgui.Button(STATE.isRunning and u8"Îñòàíîâèòü" or u8"Çàïóñòèòü ñêóï", imgui.ImVec2(-1, 55)) and not POSITIONS.global_drag_active then
        lua_thread.create(function()
            wait(0)
            if STATE.isRunning then
                STATE.stopProcess = true
            else
                runBuyingProcess()
            end
        end)
    end
    imgui.Separator()
    
    imgui.BeginChild("ListScroll", imgui.ImVec2(-1, -1))
    local item_to_delete = -1 
    for i, item in ipairs(vars) do
        imgui.BeginChild("ItemEntry" .. i, imgui.ImVec2(-1, 95), true, imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
        imgui.SetCursorPos(imgui.ImVec2(10, 35))
        if imgui.Checkbox("##act" .. i, item.active) then
            lua_thread.create(function()
                wait(0)
                save_main_json()
            end)
        end
        
        imgui.SameLine(40)
        imgui.BeginGroup()
        local idStr = item.str_id ~= "" and (" [ID: " .. item.str_id .. "]") or ""
        imgui.Text(item.str_name .. idStr)
        
        local label_amt = item.is_acc[0] and u8"Öâåò: " or u8"Êîë: "
        imgui.TextDisabled(item.str_price .. u8" $ | " .. label_amt .. item.str_amount)
        imgui.EndGroup()
        
        imgui.SameLine(imgui.GetWindowWidth() - 110)
        imgui.SetCursorPosY(25)
        if imgui.Button(u8"##ed" .. i, imgui.ImVec2(45, 45)) then
            if not POSITIONS.global_drag_active then
                lua_thread.create(function()
                    wait(0)
                    safe_copy(BUFFERS.addName, item.str_name, 256)
                    safe_copy(BUFFERS.addId, item.str_id, 64)
                    safe_copy(BUFFERS.addPrice, item.str_price, 64)
                    safe_copy(BUFFERS.addAmount, item.str_amount, 64)
                    BUFFERS.addIsAccessory[0] = item.is_acc[0]
                    UI.editIndex = i
                    UI.open_add_modal = true
                end)
            end
        end
        imgui.SameLine()
        if imgui.Button("X##dl" .. i, imgui.ImVec2(45, 45)) then
            if not POSITIONS.global_drag_active then
                item_to_delete = i
            end
        end
        imgui.EndChild()
    end
    
    if item_to_delete ~= -1 then
        lua_thread.create(function()
            wait(0)
            table.remove(vars, item_to_delete)
            save_main_json()
        end)
    end
    
    if imgui.IsWindowHovered(33) and imgui.IsMouseDragging(0, 0.0) then
        imgui.SetScrollY(imgui.GetScrollY() - imgui.GetIO().MouseDelta.y)
    end
    imgui.EndChild()
    imgui.EndChild()
end

local function renderTab2()
    imgui.BeginChild("LogDates", imgui.ImVec2(150, -1), true)
    if #log_dates > 0 then
        for _, dateStr in ipairs(log_dates) do
            if imgui.Selectable(tostring(dateStr), selected_date == dateStr) then
                selected_date = tostring(dateStr)
            end
        end
    else
        imgui.TextDisabled(u8"Ïóñòî")
    end
    if imgui.IsWindowHovered(33) and imgui.IsMouseDragging(0, 0.0) then
        imgui.SetScrollY(imgui.GetScrollY() - imgui.GetIO().MouseDelta.y)
    end
    imgui.EndChild()
    
    imgui.SameLine()
    
    imgui.BeginChild("LogsFrame", imgui.ImVec2(-1, -1), true)
    if selected_date ~= "" and logs[selected_date] then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.8, 0.2, 0.2, 0.8))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.9, 0.3, 0.3, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.7, 0.1, 0.1, 1.0))
        if imgui.Button(u8"Óäàëèòü ëîãè çà " .. selected_date, imgui.ImVec2(-1, 35)) and not POSITIONS.global_drag_active then
            lua_thread.create(function()
                wait(0)
                logs[selected_date] = nil
                save_logs()
                load_logs() 
            end)
        end
        imgui.PopStyleColor(3)
        imgui.Separator()
        
        imgui.BeginChild("LogTextScroll", imgui.ImVec2(-1, -1))
        for _, msg in ipairs(logs[selected_date] or {}) do
            imgui.TextWrapped(u8(tostring(msg)))
        end
        if imgui.IsWindowHovered(33) and imgui.IsMouseDragging(0, 0.0) then
            imgui.SetScrollY(imgui.GetScrollY() - imgui.GetIO().MouseDelta.y)
        end
        imgui.EndChild()
    else
        imgui.TextDisabled(u8"Íåò çàïèñåé.")
    end
    imgui.EndChild()
end

local function renderTab3()
    imgui.SetCursorPos(imgui.ImVec2(40, 40))
    imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1), "LMMR")
    imgui.Text(u8"Áàçà äàííûõ: " .. #item_db .. u8" ïðåäìåòîâ")
    imgui.Text(u8"Èíâåíòàðü (ñåññèÿ): " .. #session_inv .. u8" ïðåäìåòîâ")
    imgui.Spacing()
    imgui.TextDisabled(u8"Âåðñèÿ: 1.8.2")
end

local function renderTab4()
    imgui.BeginChild("SettingsScroll", imgui.ImVec2(-1, -85))
    
    imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1), u8"ÁÀÇÀ ÏÐÅÄÌÅÒÎÂ (ÀÂÒÎÑÊÀÍ)")
    imgui.TextWrapped(u8"Îòêðîéòå äèàëîã 'Ñêóïêà: 1/132 (Âåñü ñïèñîê)' â ëàâêå è íàæìèòå êíîïêó. Ñêðèïò ñàì ïðîëèñòàåò âñå ñòðàíèöû è çàïèøåò íàçâàíèÿ ñ ID.")
    local scanBtnText = STATE.isScanning and u8"ÎÑÒÀÍÎÂÈÒÜ ÑÊÀÍÈÐÎÂÀÍÈÅ" or u8"ÎÒÑÊÀÍÈÐÎÂÀÒÜ ÏÐÅÄÌÅÒÛ"
    if imgui.Button(scanBtnText, imgui.ImVec2(-1, 55)) and not POSITIONS.global_drag_active then
        lua_thread.create(function()
            wait(0)
            if STATE.isScanning then
                STATE.stopProcess = true
                STATE.isScanning = false
            else
                runAutoScan()
            end
        end)
    end
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    
    local resX = imgui.GetIO().DisplaySize.x
    local resY = imgui.GetIO().DisplaySize.y
    
    imgui.Text(u8"Íàñòðîéêè îêíà è çàäåðæêè:")
    imgui.PushItemWidth(350)
    
    local max_w = tonumber(resX) and math.min(2560, resX) or 2560
    local temp_w = imgui.new.int(win_W[0])
    if imgui.SliderInt(u8"Øèðèíà", temp_w, 750, max_w) then
        win_W[0] = temp_w[0]
    end
    if imgui.IsItemDeactivatedAfterEdit() then 
        lua_thread.create(function()
            wait(0)
            save_main_json()
        end)
    end
    
    local max_h = tonumber(resY) and math.min(1080, resY) or 1080
    local temp_h = imgui.new.int(win_H[0])
    if imgui.SliderInt(u8"Âûñîòà", temp_h, 450, max_h) then
        win_H[0] = temp_h[0]
    end
    if imgui.IsItemDeactivatedAfterEdit() then 
        lua_thread.create(function()
            wait(0)
            save_main_json()
        end)
    end
    
    imgui.SliderInt(u8"Çàäåðæêà (ìñ)", global_delay, 500, 3000)
    if imgui.IsItemDeactivatedAfterEdit() then 
        lua_thread.create(function()
            wait(0)
            save_main_json()
        end)
    end
    
    imgui.SliderFloat(u8"Ïðîçðà÷íîñòü ôîíà", menu_opacity, 0.2, 1.0, "%.2f")
    if imgui.IsItemDeactivatedAfterEdit() then 
        lua_thread.create(function()
            wait(0)
            save_main_json()
        end)
    end
    
    imgui.PopItemWidth()
    
    imgui.Spacing()

    if imgui.Checkbox(u8"FPS boost", fps_boost) then
        save_main_json()
    end
    if imgui.Checkbox(u8"Auto-clean", auto_clean) then
        save_main_json()
    end

    if imgui.Checkbox(u8"Ïîêàçûâàòü êíîïêó íà ýêðàíå", show_screen_btn) then
        lua_thread.create(function()
            wait(0)
            save_main_json()
        end)
    end
    imgui.PushItemWidth(350)
    imgui.SliderFloat(u8"Ðàçìåð êíîïêè", btn_size, 30.0, 150.0)
    if imgui.IsItemDeactivatedAfterEdit() then 
        lua_thread.create(function()
            wait(0)
            save_main_json()
        end)
    end
    imgui.PopItemWidth()
    
    imgui.Spacing()
    imgui.Text(u8"Öâåòà èíòåðôåéñà")
    
    imgui.Text("R: " .. math.floor(cAcc[0]*255))
    imgui.SameLine(80)
    imgui.Text("G: " .. math.floor(cAcc[1]*255))
    imgui.SameLine(160)
    imgui.Text("B: " .. math.floor(cAcc[2]*255))
    imgui.SameLine(240)
    if imgui.ColorButton("##AccBtn", imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0), 0, imgui.ImVec2(35, 35)) then
        imgui.OpenPopup("PickerAcc")
    end
    imgui.SameLine()
    imgui.Text(u8"Àêöåíò")
    if imgui.BeginPopup("PickerAcc") then
        imgui.ColorPicker3("##p1", cAcc)
        save_main_json()
        imgui.EndPopup()
    end
    imgui.Spacing()
    
    imgui.Text("R: " .. math.floor(cBg[0]*255))
    imgui.SameLine(80)
    imgui.Text("G: " .. math.floor(cBg[1]*255))
    imgui.SameLine(160)
    imgui.Text("B: " .. math.floor(cBg[2]*255))
    imgui.SameLine(240)
    if imgui.ColorButton("##BgBtn", imgui.ImVec4(cBg[0], cBg[1], cBg[2], 1.0), 0, imgui.ImVec2(35, 35)) then
        imgui.OpenPopup("PickerBg")
    end
    imgui.SameLine()
    imgui.Text(u8"Ôîí")
    if imgui.BeginPopup("PickerBg") then
        imgui.ColorPicker3("##p2", cBg)
        save_main_json()
        imgui.EndPopup()
    end
    
    imgui.Spacing()
    imgui.Text("R: " .. math.floor(cBtn[0]*255))
    imgui.SameLine(80)
    imgui.Text("G: " .. math.floor(cBtn[1]*255))
    imgui.SameLine(160)
    imgui.Text("B: " .. math.floor(cBtn[2]*255))
    imgui.SameLine(240)
    if imgui.ColorButton("##FloatBtnColor", imgui.ImVec4(cBtn[0], cBtn[1], cBtn[2], 1.0), 0, imgui.ImVec2(35, 35)) then
        imgui.OpenPopup("PickerBtn")
    end
    imgui.SameLine()
    imgui.Text(u8"Öâåò êíîïêè")
    if imgui.BeginPopup("PickerBtn") then
        imgui.ColorPicker3("##p3", cBtn)
        save_main_json()
        imgui.EndPopup()
    end
    
    if imgui.IsWindowHovered(33) and imgui.IsMouseDragging(0, 0.0) then
        imgui.SetScrollY(imgui.GetScrollY() - imgui.GetIO().MouseDelta.y)
    end
    imgui.EndChild()
    
    imgui.SetCursorPosY(imgui.GetWindowHeight() - 75)
    if imgui.Button(u8"Ñîõðàíèòü", imgui.ImVec2(-1, 55)) and not POSITIONS.global_drag_active then
        lua_thread.create(function()
            wait(0)
            save_main_json()
        end)
    end
end

local function renderTab5()
    imgui.BeginChild("ProfilesArea", imgui.ImVec2(-1, -1), true)
    imgui.SetCursorPos(imgui.ImVec2(20, 20))
    imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0), u8"Íàñòðîéêà êîíôèãîâ")
    imgui.Separator()
    imgui.Spacing()
    
    imgui.SetCursorPosX(20)
    imgui.Text(u8"Íàçâàíèå íîâîãî êîíôèãà:")
    imgui.SetCursorPosX(20)
    imgui.PushItemWidth(300)
    imgui.InputText("##prof_name", BUFFERS.profileName, 256)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button(u8"Ñîõðàíèòü êîíôèã", imgui.ImVec2(200, 35)) and not POSITIONS.global_drag_active then
        lua_thread.create(function()
            wait(0)
            local pName = u8:decode(ffi.string(BUFFERS.profileName))
            if pName ~= "" then
                local pItems = {}
                for _, v in ipairs(vars) do
                    table.insert(pItems, {
                        name = u8:decode(v.str_name),
                        id = u8:decode(v.str_id),
                        price = u8:decode(v.str_price),
                        amount = u8:decode(v.str_amount),
                        active = v.active[0],
                        is_acc = v.is_acc[0]
                    })
                end
                storage.profiles[pName] = pItems
                save_main_json()
            end
        end)
    end
    
    imgui.Spacing()
    imgui.SetCursorPosX(20)
    imgui.Text(u8"Âàøè ñîõðàíåííûå êîíôèãè:")
    imgui.SetCursorPosX(20)
    imgui.BeginChild("ProfList", imgui.ImVec2(-20, -15), true)
    
    local has_profiles = false
    for pName, pItems in pairs(storage.profiles) do
        has_profiles = true
        imgui.SetCursorPosX(15)
        imgui.Text(u8(pName) .. " (" .. #pItems .. u8" ïðåäìåòîâ)")
        
        imgui.SameLine(imgui.GetWindowWidth() - 250)
        if imgui.Button(u8"Çàãðóçèòü##ld" .. pName, imgui.ImVec2(100, 35)) and not POSITIONS.global_drag_active then
            lua_thread.create(function()
                wait(0)
                vars = {}
                for _, item in ipairs(pItems) do
                    table.insert(vars, {
                        name = imgui.new.char[256](string.sub(u8(item.name or ""), 1, 255)),
                        id = imgui.new.char[64](string.sub(u8(item.id or ""), 1, 63)),
                        price = imgui.new.char[64](string.sub(u8(item.price or "0"), 1, 63)),
                        amount = imgui.new.char[64](string.sub(u8(item.amount or "1"), 1, 63)),
                        active = imgui.new.bool(item.active or false),
                        is_acc = imgui.new.bool(item.is_acc or false),
                        str_name = u8(item.name or ""),
                        str_id = u8(item.id or ""),
                        str_price = u8(item.price or "0"),
                        str_amount = u8(item.amount or "1")
                    })
                end
                save_main_json()
            end)
        end
        
        imgui.SameLine()
        if imgui.Button(u8"Óäàëèòü##dl" .. pName, imgui.ImVec2(100, 35)) and not POSITIONS.global_drag_active then
            lua_thread.create(function()
                wait(0)
                storage.profiles[pName] = nil
                save_main_json()
            end)
        end
        imgui.Separator()
    end
    
    if not has_profiles then
        imgui.SetCursorPosX(15)
        imgui.TextDisabled(u8"Ó âàñ ïîêà íåò ñîõðàíåííûõ êîíôèãîâ.")
    end
    
    if imgui.IsWindowHovered(33) and imgui.IsMouseDragging(0, 0.0) then
        imgui.SetScrollY(imgui.GetScrollY() - imgui.GetIO().MouseDelta.y)
    end
    imgui.EndChild()
    imgui.EndChild()
end

local function renderTab6()
    local halfW = (imgui.GetWindowWidth() / 2) - 10
    
    -- Ëåâàÿ êîëîíêà: Èíâåíòàðü ñåññèè
    imgui.BeginChild("SessionInv_Area", imgui.ImVec2(halfW, -1), true)
    
    if imgui.Button(u8"Îáíîâèòü ñïèñîê", imgui.ImVec2(-1, 45)) and not POSITIONS.global_drag_active then
        lua_thread.create(function()
            wait(0)
            startInventoryScan()
        end)
    end
    
    imgui.Separator()
    
    imgui.PushItemWidth(-1)
    imgui.InputTextWithHint("##sellsrch", u8"Ïîèñê...", BUFFERS.sellSearch, 256)
    imgui.PopItemWidth()
    
    imgui.BeginChild("SessionInvScroll", imgui.ImVec2(-1, -1))
    
    if #session_inv > 0 then
        local search_query = ru_lower(u8:decode(ffi.string(BUFFERS.sellSearch)))
        
        for idx, item in ipairs(session_inv) do
            local item_name = tostring(item.name or "Íåèçâåñòíî")
            local item_name_lower = ru_lower(item_name)
            
            -- Ôèëüòðóåì ïî ïîèñêó
            if search_query == "" or item_name_lower:find(search_query, 1, true) then
                local displayName = string.format("[%d] %s (x%d)", item.slot, item_name, item.count or 1)
                
                if imgui.Button(u8(displayName) .. "##sinv" .. idx, imgui.ImVec2(-1, 35)) then
                    if not POSITIONS.global_drag_active then
                        lua_thread.create(function()
                            wait(0)
                            safe_copy(BUFFERS.sellPrice, "100", 64)
                            safe_copy(BUFFERS.sellAmount, "1", 64)
                            BUFFERS.sellIsAccessory[0] = false
                            UI.sellEditIndex = -1
                            UI.open_sell_modal = true
                            
                            -- Ñîõðàíÿåì äàííûå äëÿ äîáàâëåíèÿ
                            UI.temp_sell_slot = item.slot
                            UI.temp_sell_name = item_name
                            UI.temp_sell_type = item.item_type or 1
                        end)
                    end
                end
            end
        end
    else
        imgui.TextDisabled(u8"Íàæìèòå 'Îáíîâèòü ñïèñîê' äëÿ ñêàíèðîâàíèÿ")
    end
    
    if imgui.IsWindowHovered(33) and imgui.IsMouseDragging(0, 0.0) then
        imgui.SetScrollY(imgui.GetScrollY() - imgui.GetIO().MouseDelta.y)
    end
    imgui.EndChild()
    imgui.EndChild()
    
    imgui.SameLine()
    
    -- Ïðàâàÿ êîëîíêà: Î÷åðåäü ïðîäàæè
    imgui.BeginChild("SellQueue_Area", imgui.ImVec2(halfW, -1), true)
    if imgui.Button(STATE.isSelling and u8"Îñòàíîâèòü" or u8"Çàïóñòèòü ïðîäàæó", imgui.ImVec2(-1, 55)) and not POSITIONS.global_drag_active then
        lua_thread.create(function()
            wait(0)
            if STATE.isSelling then
                STATE.stopProcess = true
            else
                runSellingProcess()
            end
        end)
    end
    imgui.Separator()
    
    imgui.BeginChild("SellQueueScroll", imgui.ImVec2(-1, -1))
    local sell_item_to_delete = -1
    
    for i, item in ipairs(sell_vars) do
        imgui.BeginChild("SellEntry" .. i, imgui.ImVec2(-1, 95), true, imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
        imgui.SetCursorPos(imgui.ImVec2(10, 35))
        if imgui.Checkbox("##sellact" .. i, item.active) then
            lua_thread.create(function()
                wait(0)
                save_main_json()
            end)
        end
        
        imgui.SameLine(40)
        imgui.BeginGroup()
        imgui.Text(string.format("[Ñëîò %d] %s", item.slot, item.item_name))
        
        local label_amt = item.is_acc[0] and u8"Öâåò: " or u8"Êîë: "
        imgui.TextDisabled(item.str_price .. u8" $ | " .. label_amt .. item.str_amount)
        imgui.EndGroup()
        
        imgui.SameLine(imgui.GetWindowWidth() - 110)
        imgui.SetCursorPosY(25)
        if imgui.Button(u8"##selled" .. i, imgui.ImVec2(45, 45)) then
            if not POSITIONS.global_drag_active then
                lua_thread.create(function()
                    wait(0)
                    safe_copy(BUFFERS.sellPrice, item.str_price, 64)
                    safe_copy(BUFFERS.sellAmount, item.str_amount, 64)
                    BUFFERS.sellIsAccessory[0] = item.is_acc[0]
                    UI.sellEditIndex = i
                    UI.open_sell_modal = true
                end)
            end
        end
        imgui.SameLine()
        if imgui.Button("X##selldl" .. i, imgui.ImVec2(45, 45)) then
            if not POSITIONS.global_drag_active then
                sell_item_to_delete = i
            end
        end
        imgui.EndChild()
    end
    
    if sell_item_to_delete ~= -1 then
        lua_thread.create(function()
            wait(0)
            table.remove(sell_vars, sell_item_to_delete)
            save_main_json()
        end)
    end
    
    if imgui.IsWindowHovered(33) and imgui.IsMouseDragging(0, 0.0) then
        imgui.SetScrollY(imgui.GetScrollY() - imgui.GetIO().MouseDelta.y)
    end
    imgui.EndChild()
    imgui.EndChild()
end

imgui.OnFrame(function() return UI.CentralGlMenu[0] or show_screen_btn[0] or UI.show_custom_lavka[0] end, function()
    local resX = imgui.GetIO().DisplaySize.x
    local resY = imgui.GetIO().DisplaySize.y
    
    if win_W[0] > resX then win_W[0] = resX end
    if win_H[0] > resY then win_H[0] = resY end
    
    if imgui.IsMouseDragging(0, 5.0) then
        POSITIONS.global_drag_active = true
    end

    if POSITIONS.win_posX[0] == -1 then
        if storage.settings.pos_converted then
            POSITIONS.win_posX[0] = storage.settings.win_posX or (resX / 2 - win_W[0] / 2)
            POSITIONS.win_posY[0] = storage.settings.win_posY or (resY / 2 - win_H[0] / 2)
        else
            local cx = storage.settings.win_posX or (resX / 2)
            local cy = storage.settings.win_posY or (resY / 2)
            POSITIONS.win_posX[0] = cx - (win_W[0] / 2)
            POSITIONS.win_posY[0] = cy - (win_H[0] / 2)
            storage.settings.pos_converted = true
        end
    end
    if POSITIONS.btn_posX[0] == -1 then
        POSITIONS.btn_posX[0] = storage.settings.btn_posX or 10
        POSITIONS.btn_posY[0] = storage.settings.btn_posY or (resY / 2)
    end
    
    if show_screen_btn[0] then
        imgui.SetNextWindowPos(imgui.ImVec2(POSITIONS.btn_posX[0], POSITIONS.btn_posY[0]), imgui.Cond.Always)
        imgui.Begin("##FloatingButtonLMMR", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoMove)
        
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(cBtn[0], cBtn[1], cBtn[2], 0.85))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(cBtn[0], cBtn[1], cBtn[2], 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(cBtn[0] - 0.1, cBtn[1] - 0.1, cBtn[2] - 0.1, 1.0))
        
        local clicked = imgui.Button("LMMR", imgui.ImVec2(btn_size[0], btn_size[0]))
        
        if imgui.IsItemActive() and imgui.IsMouseDragging(0) then
            POSITIONS.is_btn_dragging = true
            POSITIONS.btn_posX[0] = POSITIONS.btn_posX[0] + imgui.GetIO().MouseDelta.x
            POSITIONS.btn_posY[0] = POSITIONS.btn_posY[0] + imgui.GetIO().MouseDelta.y
        end
        
        if clicked and not POSITIONS.is_btn_dragging then
            lua_thread.create(function()
                wait(0)
                UI.CentralGlMenu[0] = not UI.CentralGlMenu[0]
            end)
        end
        
        if imgui.IsMouseReleased(0) then
            if POSITIONS.is_btn_dragging then
                lua_thread.create(function()
                    wait(0)
                    save_main_json()
                end)
            end
            POSITIONS.is_btn_dragging = false
        end
        
        imgui.PopStyleColor(3)
        imgui.End()
    end
    
    if UI.show_custom_lavka[0] then
        local lavkaW = math.min(600, resX * 0.75)
        local lavkaH = math.min(380, resY * 0.7)

        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(cBg[0], cBg[1], cBg[2], menu_opacity[0]))
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(cBg[0] + 0.03, cBg[1] + 0.03, cBg[2] + 0.03, menu_opacity[0] * 0.75))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 0.85))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(cAcc[0] - 0.1, cAcc[1] - 0.1, cAcc[2] - 0.1, 1.0))
        imgui.PushStyleColor(imgui.Col.PopupBg, imgui.ImVec4(cBg[0], cBg[1], cBg[2], 1.0))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 0.3))
        
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 15.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 10.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8.0)

        imgui.SetNextWindowSize(imgui.ImVec2(lavkaW, lavkaH), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        
        imgui.Begin("##CustomLavka", UI.show_custom_lavka, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove)
        
        local titleText = u8"ÓÏÐÀÂËÅÍÈÅ ËÀÂÊÎÉ"
        local titleW = imgui.CalcTextSize(titleText).x
        imgui.SetCursorPos(imgui.ImVec2((lavkaW - titleW) / 2, 15))
        imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0), titleText)
        
        imgui.SetCursorPos(imgui.ImVec2(lavkaW - 35, 10))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0,0,0,0))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.3, 0.3, 1.0))
        if imgui.Button("X", imgui.ImVec2(25, 25)) then
            lua_thread.create(function()
                wait(0)
                UI.show_custom_lavka[0] = false
                sampSendDialogResponse(9, 0, 0, "")
            end)
        end
        imgui.PopStyleColor(2)
        
        imgui.SetCursorPos(imgui.ImVec2(15, 45))
        local colW = (lavkaW / 2) - 20
        local btnH = 35
        
        imgui.BeginChild("LeftCol", imgui.ImVec2(colW, -15), true)
        imgui.SetCursorPosX((colW - imgui.CalcTextSize(u8"Ñêðèïò LMMR").x) / 2)
        imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0), u8"Ñêðèïò LMMR")
        imgui.Separator()
        
        if imgui.Button(u8"Îòêðûòü ìåíþ LMMR", imgui.ImVec2(-1, btnH)) then
            lua_thread.create(function()
                wait(0)
                UI.CentralGlMenu[0] = true
                UI.show_custom_lavka[0] = false
            end)
        end
        
        if imgui.Button(u8"Âûáðàòü êîíôèã", imgui.ImVec2(-1, btnH)) then
            lua_thread.create(function()
                wait(0)
                imgui.OpenPopup(u8"Âûáîð êîíôèãà")
            end)
        end
        
        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.Appearing, imgui.ImVec2(0.5, 0.5))
        if imgui.BeginPopupModal(u8"Âûáîð êîíôèãà", nil, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoMove) then
            imgui.Text(u8"Âûáåðèòå êîíôèã äëÿ çàãðóçêè:")
            imgui.Separator()
            imgui.Spacing()
            
            local has_p = false
            for pName, pItems in pairs(storage.profiles) do
                has_p = true
                if imgui.Button(u8(pName), imgui.ImVec2(250, 35)) then
                    lua_thread.create(function()
                        wait(0)
                        vars = {}
                        for _, item in ipairs(pItems) do
                            table.insert(vars, {
                                name = imgui.new.char[256](string.sub(u8(item.name or ""), 1, 255)),
                                id = imgui.new.char[64](string.sub(u8(item.id or ""), 1, 63)),
                                price = imgui.new.char[64](string.sub(u8(item.price or "0"), 1, 63)),
                                amount = imgui.new.char[64](string.sub(u8(item.amount or "1"), 1, 63)),
                                active = imgui.new.bool(item.active or false),
                                is_acc = imgui.new.bool(item.is_acc or false),
                                str_name = u8(item.name or ""),
                                str_id = u8(item.id or ""),
                                str_price = u8(item.price or "0"),
                                str_amount = u8(item.amount or "1")
                            })
                        end
                        active_preset_name = u8(pName)
                        save_main_json()
                        imgui.CloseCurrentPopup()
                    end)
                end
                imgui.Spacing()
            end
            if not has_p then 
                imgui.TextDisabled(u8"Íåò ñîõðàíåííûõ êîíôèãîâ") 
            end
            
            imgui.Spacing()
            imgui.Separator()
            if imgui.Button(u8"Çàêðûòü", imgui.ImVec2(250, 35)) then
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end
        
        imgui.Spacing()
        local c_preset = active_preset_name ~= "" and active_preset_name or "Main.json"
        imgui.TextDisabled(u8"Ïðåñåò: " .. c_preset)
        imgui.Spacing()
        
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.7, 0.2, 0.8))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.2, 0.8, 0.2, 1.0))
        if imgui.Button(u8"Âûñòàâèòü ñêóïêó", imgui.ImVec2(-1, btnH + 10)) then
            lua_thread.create(function()
                wait(0)
                runBuyingProcess()
                UI.show_custom_lavka[0] = false
            end)
        end
        imgui.PopStyleColor(2)
        
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.9, 0.6, 0.2, 0.8))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1.0, 0.7, 0.3, 1.0))
        if imgui.Button(u8"Àâòî-ïðîäàæà", imgui.ImVec2(-1, btnH + 10)) then
            lua_thread.create(function()
                wait(0)
                runSellingProcess()
                UI.show_custom_lavka[0] = false
            end)
        end
        imgui.PopStyleColor(2)
        
        imgui.EndChild()
        
        imgui.SameLine()
        
        imgui.BeginChild("RightCol", imgui.ImVec2(colW, -15), true)
        imgui.SetCursorPosX((colW - imgui.CalcTextSize(u8"Ñåðâåðíàÿ ëàâêà").x) / 2)
        imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0), u8"Ñåðâåðíàÿ ëàâêà")
        imgui.Separator()
        
        local tBtnW = (colW - 15) / 2
        
        if imgui.Button(u8"Ïðîäàæà", imgui.ImVec2(tBtnW, btnH)) then
            lua_thread.create(function()
                wait(0)
                sampSendDialogResponse(9, 1, 0, "")
                UI.show_custom_lavka[0] = false
            end)
        end
        imgui.SameLine()
        if imgui.Button(u8"Ñêóïêà", imgui.ImVec2(tBtnW, btnH)) then
            lua_thread.create(function()
                wait(0)
                sampSendDialogResponse(9, 1, 1, "")
                UI.show_custom_lavka[0] = false
            end)
        end
        
        if imgui.Button(u8"Íàçâàíèå", imgui.ImVec2(tBtnW, btnH)) then
            lua_thread.create(function()
                wait(0)
                sampSendDialogResponse(9, 1, 5, "")
                UI.show_custom_lavka[0] = false
            end)
        end
        imgui.SameLine()
        if imgui.Button(u8"Òîâàðû", imgui.ImVec2(tBtnW, btnH)) then
            lua_thread.create(function()
                wait(0)
                sampSendDialogResponse(9, 1, 3, "")
                UI.show_custom_lavka[0] = false
            end)
        end
        
        if imgui.Button(u8"Èñòîðèÿ ñäåëîê", imgui.ImVec2(-1, btnH)) then
            lua_thread.create(function()
                wait(0)
                sampSendDialogResponse(9, 1, 4, "")
                UI.show_custom_lavka[0] = false
            end)
        end
        
        imgui.Spacing()
        imgui.TextDisabled(u8"Ïðåêðàòèòü:")
        
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.8, 0.2, 0.2, 0.7))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.9, 0.3, 0.3, 1.0))
        if imgui.Button(u8"Ñêóï", imgui.ImVec2(tBtnW, btnH)) then
            lua_thread.create(function()
                wait(0)
                sampSendDialogResponse(9, 1, 2, "")
                UI.show_custom_lavka[0] = false
            end)
        end
        imgui.SameLine()
        if imgui.Button(u8"Àðåíäó", imgui.ImVec2(tBtnW, btnH)) then
            lua_thread.create(function()
                wait(0)
                sampSendDialogResponse(9, 1, 6, "")
                UI.show_custom_lavka[0] = false
            end)
        end
        imgui.PopStyleColor(2)
        
        imgui.EndChild()
        
        imgui.End()
        imgui.PopStyleVar(3)
        imgui.PopStyleColor(8)
    end
    
    if imgui.IsMouseReleased(0) then
        POSITIONS.global_drag_active = false
    end

    if UI.CentralGlMenu[0] then 
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(cBg[0], cBg[1], cBg[2], menu_opacity[0]))
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(cBg[0] + 0.02, cBg[1] + 0.02, cBg[2] + 0.02, menu_opacity[0] * 0.75))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 0.85))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(cAcc[0] - 0.1, cAcc[1] - 0.1, cAcc[2] - 0.1, 1.0))
        imgui.PushStyleColor(imgui.Col.CheckMark, imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0))
        imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.12, 0.12, 0.15, 0.85))

        if not AUTH.isAuthorized then
            imgui.SetNextWindowSize(imgui.ImVec2(350, 200), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2(resX/2, resY/2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
            imgui.Begin("##AuthWindow", UI.CentralGlMenu, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize)
            
            imgui.SetCursorPos(imgui.ImVec2(20, 20))
            imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0), u8"ÀÂÒÎÐÈÇÀÖÈß LMMR")
            imgui.Separator()
            
            imgui.SetCursorPos(imgui.ImVec2(20, 60))
            imgui.Text(u8"Ââåäèòå êëþ÷ äîñòóïà:")
            
            imgui.SetCursorPos(imgui.ImVec2(20, 85))
            imgui.PushItemWidth(310)
            imgui.InputText("##auth_input", BUFFERS.authKey, 256)
            imgui.PopItemWidth()
            
            if AUTH.authError then
                imgui.SetCursorPos(imgui.ImVec2(20, 115))
                imgui.TextColored(imgui.ImVec4(1.0, 0.2, 0.2, 1.0), u8"Íåâåðíûé êëþ÷!")
            end
            
            imgui.SetCursorPos(imgui.ImVec2(20, 135))
            if imgui.Button(u8"ÂÎÉÒÈ", imgui.ImVec2(310, 45)) then
                if not POSITIONS.global_drag_active then
                    lua_thread.create(function()
                        wait(0)
                        local entered = ffi.string(BUFFERS.authKey)
                        local valid = false
                        for _, k in ipairs(script_keys) do
                            if entered == k then
                                valid = true
                                break
                            end
                        end
                        if valid then
                            AUTH.isAuthorized = true
                            AUTH.authError = false
                            storage.settings.saved_key = entered
                            save_main_json()
                        else
                            AUTH.authError = true
                        end
                    end)
                end
            end
            
            imgui.End()
        else
            imgui.SetNextWindowSizeConstraints(imgui.ImVec2(math.min(750, resX), math.min(450, resY)), imgui.ImVec2(resX, resY))        
            imgui.SetNextWindowSize(imgui.ImVec2(win_W[0], win_H[0]), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2(POSITIONS.win_posX[0], POSITIONS.win_posY[0]), imgui.Cond.Always)
            imgui.Begin("##MAIN_WINDOW", UI.CentralGlMenu, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove)
            
            imgui.BeginChild("TopPanel", imgui.ImVec2(-1, 75), false)
            
            imgui.InvisibleButton("DragZone", imgui.ImVec2(imgui.GetWindowWidth() - 180, 75))
            if imgui.IsItemActive() and imgui.IsMouseDragging(0) then
                POSITIONS.win_posX[0] = POSITIONS.win_posX[0] + imgui.GetIO().MouseDelta.x
                POSITIONS.win_posY[0] = POSITIONS.win_posY[0] + imgui.GetIO().MouseDelta.y
                POSITIONS.is_win_dragging = true
            end
            if POSITIONS.is_win_dragging and imgui.IsMouseReleased(0) then
                POSITIONS.is_win_dragging = false
                lua_thread.create(function()
                    wait(0)
                    save_main_json()
                end)
            end
            
            imgui.SetCursorPos(imgui.ImVec2(30, 25))
            imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0), "LMMR 1.8.2")
            
            imgui.SetCursorPos(imgui.ImVec2(imgui.GetWindowWidth() - 180, 15))
            if imgui.Button(u8"Íàñòðîéêè", imgui.ImVec2(120, 45)) and not POSITIONS.global_drag_active then
                lua_thread.create(function()
                    wait(0)
                    UI.currentTab = 4
                end)
            end
            imgui.SetCursorPos(imgui.ImVec2(imgui.GetWindowWidth() - 55, 15))
            if imgui.Button("X", imgui.ImVec2(45, 45)) and not POSITIONS.global_drag_active then
                lua_thread.create(function()
                    wait(0)
                    UI.CentralGlMenu[0] = false
                end)
            end
            imgui.EndChild()
            
            imgui.SetCursorPos(imgui.ImVec2(15, 90))
            imgui.BeginChild("SideBar", imgui.ImVec2(210, -15), true)
            imgui.SetCursorPosY(20)
            local nav_items = {
            imgui.TextDisabled("LMMR by major")
                {u8"Ïðîäàæà", 6},
                {u8"Ëîãè", 2},
                {u8"Èíôî", 3},
                {u8"Êîíôèãè", 5}
            }
            for _, nav in ipairs(nav_items) do
                imgui.SetCursorPosX(15)
                if imgui.Button(nav[1] .. "##side", imgui.ImVec2(180, 55)) and not POSITIONS.global_drag_active then
                    lua_thread.create(function()
                        wait(0)
                        UI.currentTab = nav[2]
                    end)
                end
                imgui.Spacing()
            end
            
            imgui.SetCursorPos(imgui.ImVec2(20, imgui.GetWindowHeight() - 35))
            imgui.TextDisabled("Authors: major ")
            imgui.EndChild()
            
            imgui.SameLine()
            imgui.SetCursorPosY(90)
            imgui.BeginChild("ContentArea", imgui.ImVec2(-15, -15), true)
            
            if UI.currentTab == 1 then
                renderTab1()
            elseif UI.currentTab == 2 then
                renderTab2()
            elseif UI.currentTab == 3 then
                renderTab3()
            elseif UI.currentTab == 4 then
                renderTab4()
            elseif UI.currentTab == 5 then
                renderTab5()
            elseif UI.currentTab == 6 then
                renderTab6()
            end
            
            imgui.EndChild()

            -- Ìîäàëüíîå îêíî äîáàâëåíèÿ ïðåäìåòà äëÿ ñêóïêè
            if UI.open_add_modal then
                imgui.OpenPopup("CEF_Modal")
                UI.open_add_modal = false
            end
            
            imgui.SetNextWindowSize(imgui.ImVec2(650, 600), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
            if imgui.BeginPopupModal("CEF_Modal", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize) then
                imgui.SetCursorPos(imgui.ImVec2(30, 30))
                imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0), UI.editIndex == -1 and u8"ÄÎÁÀÂËÅÍÈÅ ÏÐÅÄÌÅÒÀ" or u8"ÈÇÌÅÍÅÍÈÅ ÏÐÅÄÌÅÒÀ")
                imgui.Separator()
                
                imgui.SetCursorPos(imgui.ImVec2(30, 80))
                imgui.BeginGroup()
                
                imgui.PushItemWidth(590) 
                imgui.Text(u8"Íàçâàíèå (äëÿ ñåáÿ):")
                imgui.InputText("##name_in", BUFFERS.addName, 256)
                imgui.Spacing()
                
                imgui.Text(u8"ID Ïðåäìåòà:")
                imgui.InputText("##id_in", BUFFERS.addId, 64)
                imgui.Spacing()
                
                imgui.Text(u8"Öåíà çà 1 øò:")
                imgui.InputText("##prc_in", BUFFERS.addPrice, 64)
                imgui.Spacing()
                
                imgui.Checkbox(u8"Ýòî àêñåññóàð?", BUFFERS.addIsAccessory)
                imgui.Spacing()

                if BUFFERS.addIsAccessory[0] then
                    imgui.Text(u8"ID öâåòà (0-12):")
                else
                    imgui.Text(u8"Êîëè÷åñòâî:")
                end
                imgui.InputText("##amt_in", BUFFERS.addAmount, 64)
                
                imgui.PopItemWidth()
                imgui.EndGroup()
                
                imgui.SetCursorPos(imgui.ImVec2(30, 510)) 
                if imgui.Button(u8"Ñîõðàíèòü", imgui.ImVec2(285, 60)) and not POSITIONS.global_drag_active then
                    lua_thread.create(function()
                        wait(0)
                        local s_name = ffi.string(BUFFERS.addName)
                        local s_id = ffi.string(BUFFERS.addId)
                        local s_price = ffi.string(BUFFERS.addPrice)
                        local s_amount = ffi.string(BUFFERS.addAmount)

                        if UI.editIndex == -1 then
                            table.insert(vars, {
                                name = imgui.new.char[256](string.sub(s_name, 1, 255)),
                                id = imgui.new.char[64](string.sub(s_id, 1, 63)),
                                price = imgui.new.char[64](string.sub(s_price, 1, 63)),
                                amount = imgui.new.char[64](string.sub(s_amount, 1, 63)),
                                active = imgui.new.bool(true),
                                is_acc = imgui.new.bool(BUFFERS.addIsAccessory[0]),
                                str_name = s_name,
                                str_id = s_id,
                                str_price = s_price,
                                str_amount = s_amount
                            })
                        else
                            safe_copy(vars[UI.editIndex].name, s_name, 256)
                            safe_copy(vars[UI.editIndex].id, s_id, 64)
                            safe_copy(vars[UI.editIndex].price, s_price, 64)
                            safe_copy(vars[UI.editIndex].amount, s_amount, 64)
                            vars[UI.editIndex].is_acc[0] = BUFFERS.addIsAccessory[0]
                            
                            vars[UI.editIndex].str_name = s_name
                            vars[UI.editIndex].str_id = s_id
                            vars[UI.editIndex].str_price = s_price
                            vars[UI.editIndex].str_amount = s_amount
                        end
                        save_main_json()
                        imgui.CloseCurrentPopup()
                    end)
                end
                imgui.SameLine()
                imgui.SetCursorPosX(335)
                if imgui.Button(u8"Îòìåíà", imgui.ImVec2(285, 60)) and not POSITIONS.global_drag_active then
                    imgui.CloseCurrentPopup()
                end
                imgui.EndPopup()
            end
            
            -- Ìîäàëüíîå îêíî äîáàâëåíèÿ ïðåäìåòà äëÿ ïðîäàæè
            if UI.open_sell_modal then
                imgui.OpenPopup("Sell_Modal")
                UI.open_sell_modal = false
            end
            
            imgui.SetNextWindowSize(imgui.ImVec2(500, 400), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
            if imgui.BeginPopupModal("Sell_Modal", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize) then
                imgui.SetCursorPos(imgui.ImVec2(30, 30))
                imgui.TextColored(imgui.ImVec4(cAcc[0], cAcc[1], cAcc[2], 1.0), UI.sellEditIndex == -1 and u8"ÄÎÁÀÂÈÒÜ Â ÏÐÎÄÀÆÓ" or u8"ÈÇÌÅÍÈÒÜ ÍÀÑÒÐÎÉÊÈ")
                imgui.Separator()
                
                imgui.SetCursorPos(imgui.ImVec2(30, 80))
                imgui.BeginGroup()
                
                imgui.PushItemWidth(440)
                
                imgui.Text(u8"Öåíà çà 1 øò:")
                imgui.InputText("##sell_prc_in", BUFFERS.sellPrice, 64)
                imgui.Spacing()
                
                imgui.Checkbox(u8"Ýòî àêñåññóàð?", BUFFERS.sellIsAccessory)
                imgui.Spacing()

                if BUFFERS.sellIsAccessory[0] then
                    imgui.Text(u8"ID öâåòà (0-12):")
                else
                    imgui.Text(u8"Êîëè÷åñòâî:")
                end
                imgui.InputText("##sell_amt_in", BUFFERS.sellAmount, 64)
                
                imgui.PopItemWidth()
                imgui.EndGroup()
                
                imgui.SetCursorPos(imgui.ImVec2(30, 310))
                if imgui.Button(u8"Ñîõðàíèòü", imgui.ImVec2(210, 60)) and not POSITIONS.global_drag_active then
                    lua_thread.create(function()
                        wait(0)
                        local s_price = ffi.string(BUFFERS.sellPrice)
                        local s_amount = ffi.string(BUFFERS.sellAmount)

                        if UI.sellEditIndex == -1 then
                            table.insert(sell_vars, {
                                slot = UI.temp_sell_slot or 0,
                                item_name = UI.temp_sell_name or "Íåèçâåñòíî",
                                item_type = UI.temp_sell_type or 1,
                                price = imgui.new.char[64](string.sub(s_price, 1, 63)),
                                amount = imgui.new.char[64](string.sub(s_amount, 1, 63)),
                                active = imgui.new.bool(true),
                                is_acc = imgui.new.bool(BUFFERS.sellIsAccessory[0]),
                                str_price = s_price,
                                str_amount = s_amount
                            })
                        else
                            safe_copy(sell_vars[UI.sellEditIndex].price, s_price, 64)
                            safe_copy(sell_vars[UI.sellEditIndex].amount, s_amount, 64)
                            sell_vars[UI.sellEditIndex].is_acc[0] = BUFFERS.sellIsAccessory[0]
                            
                            sell_vars[UI.sellEditIndex].str_price = s_price
                            sell_vars[UI.sellEditIndex].str_amount = s_amount
                        end
                        save_main_json()
                        imgui.CloseCurrentPopup()
                    end)
                end
                imgui.SameLine()
                imgui.SetCursorPosX(260)

            imgui.End()
        end
        imgui.PopStyleColor(7)
    end
end)

-- ============================================================================
-- ÎÑÍÎÂÍÀß ÔÓÍÊÖÈß
-- ============================================================================

function main()
    while not isSampAvailable() do wait(100) end
    
    load_main_json()
    load_item_db()
    load_logs()
    
    sampRegisterChatCommand('cent', function()
        UI.CentralGlMenu[0] = not UI.CentralGlMenu[0]
    end)
    
    
    while true do
        wait(0)
    end
end

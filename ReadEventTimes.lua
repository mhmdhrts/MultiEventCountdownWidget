-- Global variables
local csvFilePath
local eventsByDate = {}
local slotTargets = {}
local DEBUG = false

-- Helper functions
local function log(msg)
    if DEBUG then 
        print("[EventTimer] " .. msg) 
    end 
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function split(str, delim)
    local result = {}
    if not str or str == "" then 
        return result 
    end
    
    local pattern = string.format("([^%s]+)", delim)
    for part in str:gmatch(pattern) do
        table.insert(result, trim(part))
    end
    return result
end

local function isValidDate(y, m, d)
    return os.date("*t", os.time{year=y, month=m, day=d}) ~= nil
end

-- Parse CSV: store times per CSV column (col2 -> index 1, col3 -> index 2, ...)
local function parseCSV(filePath)
    local file = io.open(filePath, "r")
    if not file then 
        log("CSV file not found: " .. filePath) 
        return {} 
    end
    
    local header = file:read("*l")
    if not header then 
        log("CSV file is empty") 
        file:close() 
        return {} 
    end

    local events = {}
    for line in file:lines() do
        local fields = split(line, ",")
        local dateStr = fields[1]
        
        if dateStr and dateStr ~= "" then
            local year, month, day = dateStr:match("(%d+)%-(%d+)%-(%d+)")
            
            if year and month and day and isValidDate(year, month, day) then
                local row = {}
                
                -- We map up to 5 event columns -> slots 1..5
                for col = 2, 6 do
                    local timeStr = fields[col]
                    
                    if timeStr and timeStr ~= "" then
                        local hour, min = timeStr:match("(%d+):(%d+)")
                        
                        if hour and min then
                            local ts = os.time{
                                year = tonumber(year), 
                                month = tonumber(month), 
                                day = tonumber(day),
                                hour = tonumber(hour), 
                                min = tonumber(min), 
                                sec = 0
                            }
                            row[col - 1] = ts
                        else
                            log("Invalid time format in CSV '" .. tostring(timeStr) .. "' on " .. dateStr)
                        end
                    end
                end
                events[dateStr] = row
            else
                log("Invalid date in CSV: " .. tostring(dateStr))
            end
        end
    end
    file:close()
    return events
end

-- Helper: find next timestamp for a given slotIndex (1..5) at or after now
local function findNextForSlot(slotIndex, now)
    local candidates = {}
    
    for dateStr, row in pairs(eventsByDate) do
        local t = row and row[slotIndex]
        
        if t and t >= now then
            table.insert(candidates, t)
        end
    end
    
    if #candidates == 0 then 
        return nil 
    end
    
    table.sort(candidates)
    return candidates[1]
end

-- Main functions
-- Initialize: parse CSV and prefill each slot with the next occurrence of its column
function Initialize()
    csvFilePath = SKIN:GetVariable('CSVFilePath')
    if not csvFilePath then
        log("CSVFilePath not set")
        return
    end

    eventsByDate = parseCSV(csvFilePath)
    local now = os.time()
    
    -- Initialize slotTargets so positions are fixed by column
    for i = 1, 5 do
        slotTargets[i] = findNextForSlot(i, now) -- nil if none found
    end
end

-- Update: for each slot (fixed column mapping), update countdown
-- if expired, find next for that same slot
function Update()
    local now = os.time()

    for i = 1, 5 do
        local targetTime = slotTargets[i]

        -- If no assigned time or assigned time expired, try to find the next one for this column
        if (not targetTime) or (targetTime < now) then
            targetTime = findNextForSlot(i, now)
            slotTargets[i] = targetTime
        end

        if targetTime then
            local timeDiff = os.difftime(targetTime, now)
            
            if timeDiff < 0 then 
                timeDiff = 0 
            end
            
            local days = math.floor(timeDiff / 86400)
            local hours = math.floor((timeDiff % 86400) / 3600)
            local minutes = math.floor((timeDiff % 3600) / 60)
            local seconds = timeDiff % 60

            local formattedTime = days > 0 and
                string.format("%d days %02d:%02d:%02d", days, hours, minutes, seconds) or
                string.format("%02d:%02d:%02d", hours, minutes, seconds)

            SKIN:Bang('!SetVariable', 'TimeRemaining' .. i, formattedTime)
        else
            -- Nothing scheduled for this column/slot
            SKIN:Bang('!SetVariable', 'TimeRemaining' .. i, '--:--:--')
        end
    end
end
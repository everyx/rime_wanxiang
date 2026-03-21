-- user_predict.lua
-- https://github.com/amzxyz/rime_wanxiang
-- by amzxyz
-- 架构层: Processor (物理按键截取与逻辑分发) + Translator (候选词生成与上屏)
-- 算法层:
-- v1.0.0
-- 1. 瀑布流查询模型 (2-Gram 精确 -> 1-Gram 降级 -> P-Gram 模糊抗抖动)
-- 2. 双重衰减排名 (时间指数衰减 + 频次基础权重)
-- 3. 数据淘汰系统 (0分冷冻机制 + 15元末位淘汰 + 30天/90天绝对生命周期)
-- 4. 事务级回滚机制 (拦截上屏立即退格，复原上次数据库操作)
-- 5. LWW 智能合并 (导入数据时采用 Last Write Wins 策略，保留最新时间戳数据)
-- 6. ABA回头输入防写入BA，让数据库少记录无效数据
-- 7. 继承rime ctrl+del shift+del主动删除预测数据，不同点在于，清空即clear

local insert   = table.insert
local remove   = table.remove
local sort     = table.sort
local s_match  = string.match
local s_sub    = string.sub
local s_len    = string.len
local s_find   = string.find
local s_format = string.format
local tonumber = tonumber
local math_pow = math.pow
local math_max = math.max
local os_time  = os.time

-- 内部运行参数默认值 (会被外部 YAML 配置覆盖)
local CONFIG = {
    MAX_CANDIDATES      = 5,             
    MAX_PREDICTIONS     = 3,             
    EXPIRY_SECONDS      = 90 * 24 * 3600,
    ACTIVATION_SECONDS  = 7 * 24 * 3600, 
    MAX_MEMORY_BRANCHES = 15,            
    DECAY_RATE          = 0.85,          
    SCAN_LIMIT          = 80,            
    ENABLE_PREDICT_SPACE = false,  -- 联想时空格是否打断并上屏实体空格
    CONTEXT_TIMEOUT_MS  = 5000,    -- 语境超时时间(毫秒)
}

-- 新增：语气助词白名单与标点检测
local PARTICLE_WHITELIST = {
    ["吧"]=true, ["呢"]=true, ["吗"]=true, ["啦"]=true, ["嘛"]=true, 
    ["呀"]=true, ["哒"]=true, ["哈"]=true, ["哇"]=true
}
local function is_tone_symbol(text) 
    return s_match(text, "^[！？，。～]+$") ~= nil 
end

-- 动态加载 YAML 方案配置
local function load_config(env)
    local config = env.engine.schema.config
    if config then
        CONFIG.MAX_CANDIDATES      = config:get_int("user_predict/max_candidates") or 5
        CONFIG.MAX_PREDICTIONS     = config:get_int("user_predict/max_predictions") or 3
        CONFIG.EXPIRY_SECONDS      = (config:get_int("user_predict/expiry_days") or 90) * 86400
        CONFIG.ACTIVATION_SECONDS  = (config:get_int("user_predict/activation_days") or 7) * 86400
        CONFIG.MAX_MEMORY_BRANCHES = config:get_int("user_predict/max_memory_branches") or 15
        CONFIG.DECAY_RATE          = config:get_double("user_predict/decay_rate") or 0.85
        
        -- 读取空格打断配置
        local ps_val = config:get_bool("user_predict/enable_predict_space")
        if ps_val ~= nil then CONFIG.ENABLE_PREDICT_SPACE = ps_val end
        
        local timeout_val = config:get_int("user_predict/context_timeout")
        if timeout_val ~= nil then CONFIG.CONTEXT_TIMEOUT_MS = timeout_val end
    end
end

local PH_CHAR = "›"

local history = {}
local last_commit = ""
local last_commit_time = 0
local predict_count = 0
local is_predicting = false
local pending_cands = nil

-- 内存阻断模块：打断语境后洗白临时记忆链，防止长距离上下文穿透
local function reset_memory_chain(env, reason)
    for i = 1, #history do history[i] = nil end
    last_commit = ""
    last_commit_time = 0
    predict_count = 0
    is_predicting = false
    pending_cands = nil
    env.need_push = false
end

local _db_pool = {}
local function get_db(env)
    local config = env.engine.schema.config
    local db_name = config:get_string("user_predict/db_name") or "lua/predict"
    if not _db_pool[db_name] then _db_pool[db_name] = LevelDb(db_name) end
    local db = _db_pool[db_name]
    if db and not db:loaded() then db:open() end
    return db
end

-- 语境分割算法：检测是否输入了标点符号或控制字符
local function is_punctuation_or_space(text)
    if not text or text == "" then return false end
    if is_tone_symbol(text) then return false end -- 特权：放行语气标点去校验
    -- 暴力拦截：空格、控制符、以及所有非语气标点，直接视为断句
    if s_match(text, "[%p%c%s]") then return true end
    local zh_punct = "；：“”‘’（）【】《》、·￥"
    if s_find(zh_punct, text, 1, true) then return true end
    return false
end

-- 分词聚集算法：连续的英文字母或数字打包为一个词元，中文按 UTF-8 单字切割
local function get_utf8_chars(str)
    if not str or str == "" then return {} end
    if s_match(str, "^[a-zA-Z0-9]+$") or is_tone_symbol(str) then return { str } end
    local chars = {}
    for c in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
        insert(chars, c)
    end
    return chars
end

-- 模糊查询降级参数：最多回退匹配最后 4 个词元
local function get_suffix_lengths(len)
    if len >= 4 then return {4, 3, 2} 
    elseif len == 3 then return {3, 2}    
    elseif len == 2 then return {2}       
    elseif len == 1 then return {1} end
    return {}
end

-- 核心预测与过滤模块
local function get_predictions(env, prev_commit)
    if not prev_commit or prev_commit == "" then return nil end
    local db = get_db(env)
    if not db then return nil end
    
    local cands = {}
    local seen = {}
    local scan_limit = CONFIG.SCAN_LIMIT 
    
    local function fetch_and_clean(query_key)
        local da = db:query(query_key)
        if not da then return end
        local scan_count = 0
        local now = os_time()
        local prefix_cands = {} 
        
        for k, v in da:iter() do
            if scan_count >= scan_limit or not s_find(k, query_key, 1, true) then break end
            
            if s_sub(k, 1, 1) ~= "\1" then
                local word = s_sub(k, s_len(query_key) + 1)
                local c_str, ts_str = s_match(v, "^([^|]+)|?(.*)$")
                local count = tonumber(c_str) or 0
                local ts = tonumber(ts_str) or 0
                
                if ts == 0 then ts = now - CONFIG.EXPIRY_SECONDS - 1 end
                local age_seconds = now - ts
                
                -- 绝对生命周期：过期清理 vs 衰减打分
                if age_seconds > CONFIG.EXPIRY_SECONDS then
                    if db.erase then db:erase(k) else db:update(k, "") end
                else
                    if count > 0 then
                        local age_days = age_seconds / 86400.0
                        local score = count * math_pow(CONFIG.DECAY_RATE, age_days)
                        if score > 0.05 and word ~= "" then
                            insert(prefix_cands, { word = word, weight = score, db_key = k })
                        end
                    end
                end
            end
            scan_count = scan_count + 1
        end
        da = nil
        
        -- 15杀：分支末位淘汰机制
        if #prefix_cands > 0 then
            sort(prefix_cands, function(a, b) return a.weight > b.weight end)
            for i, c in ipairs(prefix_cands) do
                if i <= CONFIG.MAX_MEMORY_BRANCHES then
                    if not seen[c.word] then
                        insert(cands, c)
                        seen[c.word] = true
                    end
                else
                    db:update(c.db_key, "0|" .. tostring(now))
                end
            end
        end
    end

    -- 瀑布流查询：优先级递减，命中即阻断，优化性能
    if #history >= 2 then
        fetch_and_clean("2\t" .. history[#history - 1] .. "\t" .. history[#history] .. "\t")
    end

    if #cands < CONFIG.MAX_CANDIDATES and #history >= 1 then 
        fetch_and_clean("1\t" .. history[#history] .. "\t")
    end

    if #cands < CONFIG.MAX_CANDIDATES then
        local chars = get_utf8_chars(prev_commit)
        local lengths_to_query = get_suffix_lengths(#chars)
        for _, l in ipairs(lengths_to_query) do
            if #cands >= CONFIG.MAX_CANDIDATES then break end
            fetch_and_clean("P\t" .. table.concat(chars, "", #chars - l + 1, #chars) .. "\t")
        end
    end

    if #cands > 0 then
        sort(cands, function(a, b) return a.weight > b.weight end)
        return cands
    end
    return nil
end

local P = {}
function P.init(env)
    load_config(env) -- 读取 YAML 配置
    local db = get_db(env)
    env.need_push = false 
    env.last_written_keys = {}
    env.just_committed = false
    
    env.commit_cb = function(ctx)
        local status, err = pcall(function()
            local text = ctx:get_commit_text()
            if not text or text == PH_CHAR or text == "" then return end
            
            if is_punctuation_or_space(text) then
                reset_memory_chain(env, "输入断句符")
                return
            end

            -- 时效防御：必须放在最前面！先斩断过去！
            local current_time = rime_api.get_time_ms()
            if last_commit ~= "" and (current_time - last_commit_time) > CONFIG.CONTEXT_TIMEOUT_MS then
                reset_memory_chain(env, "输入超时") 
            end

            -- 预测状态更新：处理当下
            -- 放宽级联预测条件。只要上屏的不是被拦截的标点，
            -- 无论你是手打的还是选的联想词，都无条件开启/重置预测模式，继续往下推词！
            if not is_predicting then 
                is_predicting = true 
                predict_count = 1
            else
                predict_count = predict_count + 1
            end
            -- 如果预测步数超过了设定的最大值，不关闭预测，而是把步数重置
            if predict_count > CONFIG.MAX_PREDICTIONS then
                is_predicting = false
                predict_count = 0
                pending_cands = nil
                return
            end

            env.last_written_keys = {} 
            local function update_memory(key)
                local val = db:fetch(key)
                local now = os_time()
                env.last_written_keys[key] = val or ""
                
                if not val or val == "" then
                    if is_tone_symbol(text) then
                        db:update(key, "1|" .. tostring(now)) -- 标点秒记
                    else
                        db:update(key, "0|" .. tostring(now))
                    end
                else
                    local c_str, ts_str = s_match(val, "^([^|]+)|?(.*)$")
                    local count = tonumber(c_str) or 0
                    local ts = tonumber(ts_str) or 0
                    local age = now - ts
                    if age > CONFIG.EXPIRY_SECONDS then
                        db:update(key, "0|" .. tostring(now))
                    elseif count == 0 then
                        if age <= CONFIG.ACTIVATION_SECONDS then
                            db:update(key, "1|" .. tostring(now)) 
                        else
                            db:update(key, "0|" .. tostring(now)) 
                        end
                    else
                        db:update(key, tostring(count + 1) .. "|" .. tostring(now))
                    end
                end
            end

            -- 防御与终结符解耦体系
            local current_time = rime_api.get_time_ms()
            local should_record = true
            local is_terminal_symbol = false -- 解耦标记


            -- 2. 语气助词校验
            if should_record and is_tone_symbol(text) then
                local last_char = s_sub(last_commit, -3) 
                if not PARTICLE_WHITELIST[last_char] then
                    should_record = false
                    reset_memory_chain(env, "非助词接标点") 
                else
                    is_terminal_symbol = true -- 允许写入，但标记为终结符
                end
            end

            -- 3. 防复读机
            if should_record and last_commit == text then
                should_record = false
            end

            -- 4. 柔性 ABBA 拦截：退回B保留A
            if should_record and #history >= 2 then
                if text == history[#history - 1] then
                    should_record = false
                    remove(history, #history)
                    last_commit = history[#history] or ""
                end
            end

            -- 【一：写入逻辑】
            if should_record and last_commit ~= "" then
                local chars = get_utf8_chars(last_commit)
                local lengths_to_learn = get_suffix_lengths(#chars)
                for _, l in ipairs(lengths_to_learn) do
                    update_memory("P\t" .. table.concat(chars, "", #chars - l + 1, #chars) .. "\t" .. text)
                end
                if #history >= 1 then update_memory("1\t" .. history[#history] .. "\t" .. text) end
                if #history >= 2 then update_memory("2\t" .. history[1] .. "\t" .. history[2] .. "\t" .. text) end
            end
            
            -- 【二：调用逻辑解耦】
            if should_record then
                if is_terminal_symbol then
                    reset_memory_chain(env, "终结符上屏完毕") -- 终结符写完即刻洗白，绝不成为下文
                else
                    insert(history, text)
                    if #history > 2 then remove(history, 1) end
                    last_commit = text
                end
            end
            
            last_commit_time = current_time
            env.just_committed = true
            
            -- 通过 Rime 原生 prediction 开关判断是否推送联想
            if predict_count <= CONFIG.MAX_PREDICTIONS and ctx:get_option("prediction") then
                pending_cands = get_predictions(env, last_commit)
                if pending_cands then 
                    env.need_push = true 
                else
                    predict_count = 0; is_predicting = false; pending_cands = nil
                end
            else
                predict_count = 0; is_predicting = false; pending_cands = nil
            end
        end)
    end
    
    env.update_cb = function(ctx)
        local status, err = pcall(function()
            local input = ctx.input
            if not input then return end
            
            -- 数据序列化导出模块
            if input == "outpredict" then
                ctx:clear()
                local sync_path = rime_api.get_user_data_dir() .. "/predict_export.txt"
                local f = io.open(sync_path, "w")
                if f then
                    for k, v in db:query(""):iter() do
                        if s_sub(k, 1, 1) ~= "\1" then
                            f:write(k .. "\t" .. v .. "\n")
                        end
                    end
                    f:close()
                end
                reset_memory_chain(env, "导出结束")
                return
            end

            -- LWW 算法智能合并模块 (Last Write Wins)
            if input == "inpredict" then
                ctx:clear()
                local sync_path = rime_api.get_user_data_dir() .. "/predict_import.txt"
                local f = io.open(sync_path, "r")
                if f then
                    for line in f:lines() do
                        local k, v = s_match(line, "^([^\t]+)\t(.*)$")
                        if k and v then
                            local old_v = db:fetch(k)
                            if old_v and old_v ~= "" then
                                local _, old_ts = s_match(old_v, "^([^|]+)|?(.*)$")
                                local _, new_ts = s_match(v, "^([^|]+)|?(.*)$")
                                local o_ts = tonumber(old_ts) or 0
                                local n_ts = tonumber(new_ts) or 0
                                
                                if n_ts > o_ts then
                                    db:update(k, v)
                                end
                            else
                                db:update(k, v)
                            end
                        end
                    end
                    f:close()
                end
                reset_memory_chain(env, "导入结束")
                return
            end

            local expected_ph = string.rep(PH_CHAR, predict_count)
            local expected_len = string.len(expected_ph)

            if env.need_push and input == "" then
                env.need_push = false
                ctx:push_input(expected_ph)
                ctx.caret_pos = expected_len
                return
            end
            
            if s_find(input, PH_CHAR) then
                if input ~= expected_ph then
                    local clean_text = string.gsub(input, PH_CHAR, "")
                    ctx:clear()
                    predict_count = 0
                    is_predicting = false
                    pending_cands = nil
                    if clean_text ~= "" then ctx:push_input(clean_text) end
                    return
                else
                    if ctx.caret_pos < expected_len then 
                        ctx:clear()
                        predict_count = 0
                        is_predicting = false
                        pending_cands = nil
                        return 
                    end
                end
            end
        end)
    end

    env.commit_connection = env.engine.context.commit_notifier:connect(env.commit_cb)
    env.update_connection = env.engine.context.update_notifier:connect(env.update_cb)
end

function P.func(key, env)
    local ctx = env.engine.context
    local input = ctx.input
    if not input then return 2 end
    
    local repr = key:repr()

    -- 强制拦截物理标点按键转为 commit 动作，确保被记录
    if not ctx:is_composing() then
        local symbol_map = { ["?"] = "？", ["!"] = "！", [","] = "，", ["."] = "。" }
        if symbol_map[repr] then
            env.engine:commit_text(symbol_map[repr])
            return 1
        end
    end

    -- 主动数据抹除功能：定位高亮候选项并从数据库多维关联中剔除
    if ctx:has_menu() then
        if (s_find(repr, "Shift") or s_find(repr, "Control")) and (s_find(repr, "Delete") or s_find(repr, "BackSpace")) then
            local cand = ctx:get_selected_candidate()
            
            if cand and cand.type == "predict" then
                local word = cand.text
                local db = get_db(env)

                local exact_key = nil
                if pending_cands then
                    for _, c in ipairs(pending_cands) do
                        if c.word == word then
                            exact_key = c.db_key
                            break
                        end
                    end
                end

                if exact_key then
                    if db.erase then db:erase(exact_key) else db:update(exact_key, "") end
                end

                -- 为了防止它是被 2-Gram 推出来的，删了 2-Gram 还有 1-Gram 兜底（导致删不干净）
                local chars = get_utf8_chars(last_commit)
                local lengths = get_suffix_lengths(#chars)
                for _, l in ipairs(lengths) do
                    local prefix = "P\t" .. table.concat(chars, "", #chars - l + 1, #chars) .. "\t"
                    if db.erase then db:erase(prefix .. word) else db:update(prefix .. word, "") end
                end
                if #history >= 1 then 
                    if db.erase then db:erase("1\t" .. history[#history] .. "\t" .. word) else db:update("1\t" .. history[#history] .. "\t" .. word, "") end
                end
                if #history >= 2 then 
                    if db.erase then db:erase("2\t" .. history[1] .. "\t" .. history[2] .. "\t" .. word) else db:update("2\t" .. history[1] .. "\t" .. history[2] .. "\t" .. word, "") end
                end
                
                ctx:clear()
                reset_memory_chain(env, "主动抹除词条")
                return 1 
            end
        end
    end

    -- 事务回滚模块：侦测上屏动作后的即刻退格，用于纠正输入误操作
    if env.just_committed then
        if repr == "BackSpace" then
            local db = get_db(env)
            for k, v in pairs(env.last_written_keys or {}) do
                if v == "" then 
                    if db.erase then db:erase(k) else db:update(k, "") end
                else 
                    db:update(k, v) 
                end
            end
            env.last_written_keys = {}
            reset_memory_chain(env, "事务回滚(上屏即退格)")
            env.just_committed = false
            -- log.info("[Processor] 事务回滚: 检测到上屏立即退格, 已恢复最近一次数据库操作")
            return 2 
        elseif not s_match(repr, "Shift") and not s_match(repr, "Control") and not s_match(repr, "Alt") then
            env.just_committed = false
        end
    end

    if s_find(input, PH_CHAR) then
        -- 针对配置的空格打断逻辑
        if key.keycode == 0x20 and CONFIG.ENABLE_PREDICT_SPACE then
            ctx:clear()
            reset_memory_chain(env, "空格打断联想")
            env.engine:commit_text(" ")
            -- log.info("[Processor] 联想打断: 空格键触发，已清空预测并上屏实体空格")
            return 1
        end
        
        -- 其他常规打断键
        if repr == "Escape" or repr == "Return" or repr == "BackSpace" then
            ctx:clear()
            reset_memory_chain(env, "打断键(Esc/Enter/Backspace)清除预测") 
            return 1 
        end
    end
    
    return 2 
end

function P.fini(env)
    if env.commit_connection then env.commit_connection:disconnect(); env.commit_connection = nil end
    if env.update_connection then env.update_connection:disconnect(); env.update_connection = nil end
end

local T = {}
function T.init(env)
    load_config(env) -- 读取 YAML 配置
    get_db(env)
end

function T.func(input, seg, env)
    if s_match(input, "^[›]+$") and pending_cands then
        local count = 0
        for _, c in ipairs(pending_cands) do
            if count >= CONFIG.MAX_CANDIDATES then break end
            local cand = Candidate("predict", seg.start, seg._end, c.word, "")
            yield(cand)
            count = count + 1
        end
    end
end

function T.fini(env) end

return { P = P, T = T }
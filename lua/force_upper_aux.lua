-- lua/force_upper_aux.lua
-- https://github.com/amzxyz/rime_wanxiang
-- @description: 自动将N-1首选数量的汉字大写辅助码施加到音节后面起到固定语句分词的作用
-- @author: amzxyz

local ForceUpperAux = {}

-- 工具函数：获取 UTF-8 字符
local function get_utf8_char(str, index)
    local start_byte = utf8.offset(str, index)
    if not start_byte then return nil end
    local end_byte = utf8.offset(str, index + 1)
    return string.sub(str, start_byte, (end_byte and end_byte - 1) or nil)
end

-- 工具函数：获取前缀
local function get_utf8_prefix(str, n)
    if not str or str == "" or n <= 0 then return "" end
    local offset = utf8.offset(str, n + 1)
    return offset and string.sub(str, 1, offset - 1) or str
end

-- 获取分隔符
local function get_delimiters(ctx)
    local cfg = ctx.engine and ctx.engine.schema and ctx.engine.schema.config
    local delimiter = (cfg and cfg:get_string("speller/delimiter")) or " '"
    return delimiter:sub(1, 1), delimiter:sub(2, 2)
end

-- 转义正则
local function esc_class(c)
    return (c:gsub("([%%%^%]%-])", "%%%1"))
end

-- 获取输入切分后的部分
local function get_script_text_parts(ctx)
    local raw_in    = ctx.input or ""
    local prop_key  = ctx:get_property("sequence_preedit_key") or ""
    local prop_val  = ctx:get_property("sequence_preedit_val") or ""
    local script_txt = ctx:get_script_text() or ""

    local s = (prop_key == raw_in and prop_val ~= "") and prop_val or script_txt
    if s == "" then return {} end

    local auto, manual = get_delimiters(ctx)
    local pat = "[^" .. esc_class(auto) .. esc_class(manual) .. "%s]+"
    local parts = {}
    for w in s:gmatch(pat) do parts[#parts + 1] = w end
    return parts
end

-- 核心算法：查询辅助码
local function lookup_aux_code(env, char)
    if env.aux_cache[char] then return env.aux_cache[char] end
    
    local raw_code = env.dict:lookup(char)
    if not raw_code or raw_code == "" then return "" end
    
    -- 提取分号后的部分，或直接取原始码
    local aux_part = raw_code:match(";([^,]+)") or raw_code:match("^([^;]+)") or ""
    local final_code = aux_part:gsub("[^a-zA-Z]", ""):sub(1, 2):upper()
    
    env.aux_cache[char] = final_code
    return final_code
end

-- 生命周期：初始化
function ForceUpperAux.init(env)
    local config = env.engine.schema.config
    
    -- 读取配置的快捷键，默认为 Tab
    -- 注意：如果是组合键，配置中需写为 "Control+t" 或 "Shift+Tab" 等格式
    env.trigger_key = config:get_string("force_upper_aux/hotkey") or "Tab"

    env.cand_prefix_cache = {}
    env.aux_cache = {}
    env.dict = ReverseLookup("wanxiang_pro")
    
    env.on_update = function(ctx)
        if not ctx:is_composing() then
            env.cand_prefix_cache = {}
            return
        end
        
        local comp = ctx.composition
        if not comp:empty() then
            local segment = comp:back()
            local cand = segment:get_candidate_at(0)
            if cand and cand.text then
                env.cand_prefix_cache = {}
                local text = cand.text
                local len = utf8.len(text) or 0
                for i = 1, len do
                    env.cand_prefix_cache[i] = get_utf8_prefix(text, i)
                end
            end
        end
    end
    
    env.update_conn = env.engine.context.update_notifier:connect(env.on_update)
end

function ForceUpperAux.fini(env)
    if env.update_conn then
        env.update_conn:disconnect()
    end
end

-- 核心处理逻辑
function ForceUpperAux.func(key_event, env)
    if key_event:release() then return 2 end
    local current_key = key_event:repr()
    if current_key == env.trigger_key then
        local ctx = env.engine.context
        if not ctx:is_composing() then return 2 end
        
        local parts = get_script_text_parts(ctx)
        if #parts == 0 then return 2 end
        
        -- 暂时断开通知防止死循环
        env.update_conn:disconnect()
        
        local parts_count = #parts
        local target_len = parts_count > 1 and (parts_count - 1) or 1
        local candidate_text = env.cand_prefix_cache[target_len] or ""
        
        -- 计算新输入
        local new_input = ""
        local text_len = utf8.len(candidate_text) or 0
        for i = 1, parts_count do
            local syl = parts[i]
            if i <= text_len and i < parts_count then
                local pinyin = syl:sub(1, 2)
                local char = get_utf8_char(candidate_text, i)
                local aux = lookup_aux_code(env, char)
                new_input = new_input .. pinyin .. aux
            else
                new_input = new_input .. syl
            end
        end
        
        if new_input ~= "" and new_input ~= ctx.input then
            ctx.input = new_input
        end
        
        -- 重新连接
        env.update_conn = ctx.update_notifier:connect(env.on_update)
        return 1 -- kAccepted
    end
    
    return 2 -- kNoop
end

return ForceUpperAux
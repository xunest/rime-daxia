-- user_dict_priority.lua
-- 把用户词典里的候选提到前面，强化「连选几次就靠前」的体感。
-- Rime 自带调频加分较轻，容易被主词库压住；此滤镜按类型重排，
-- 在 uniquifier 之前运行，让 user_phrase 优先保留并靠前显示。
--
-- 启用方式（在 rime_ice.custom.yaml）：
--   "engine/filters/@before 10": lua_filter@*user_dict_priority
-- （@before 10 对应雾凇默认 filters 里 uniquifier 的位置）

local M = {}

local function is_user_cand(cand)
    local t = cand.type
    if not t then return false end
    return t == "user_phrase"
        or t == "user_table"
        or t:sub(1, 5) == "user_"
end

function M.func(input)
    local users, others = {}, {}
    for cand in input:iter() do
        if is_user_cand(cand) then
            table.insert(users, cand)
        else
            table.insert(others, cand)
        end
    end
    for _, c in ipairs(users) do yield(c) end
    for _, c in ipairs(others) do yield(c) end
end

return M

-- shift_toggle.lua
-- 轻按一下 Shift 切换中英文模式（类似搜狗/微信输入法的习惯）
-- 单独按下并松开 Shift → 切换中英文
-- Shift 配合其他键（如打大写字母）→ 不触发切换

local M = {}

local SHIFT_L = 0xffe1
local SHIFT_R = 0xffea

local function is_shift_key(key)
    return key.keycode == SHIFT_L or key.keycode == SHIFT_R
end

function M.init(env)
    env.shift_down = false       -- Shift 是否处于按下状态
    env.used_with_other = false  -- 本次按下期间是否配合了其他键
end

function M.func(key, env)
    if is_shift_key(key) then
        if key:release() then
            -- 松开 Shift
            if env.shift_down and not env.used_with_other then
                -- 单独轻点 → 切换中英文
                local context = env.engine.context
                local ascii = context:get_option('ascii_mode')
                context:set_option('ascii_mode', not ascii)
                env.shift_down = false
                return 1
            end
            env.shift_down = false
            return 2
        else
            -- 按下 Shift
            if not env.shift_down then
                env.used_with_other = false
            end
            env.shift_down = true
            return 2
        end
    end

    -- Shift 按住期间按了其他键，视为组合操作，不触发切换
    if env.shift_down and not key:release() then
        env.used_with_other = true
    end

    return 2
end

return M

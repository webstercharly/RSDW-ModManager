-- Native-styled pause-menu entry and initial status shell.

local log = require("rlm_log")
local engine = require("rlm_engine")
local modules = require("rlm_modules")

local M = {}

local ALL_CAPS_BUTTON = "/Game/UI/Common/WBP_DomAllCapsButton"
local PANEL_CLASS = "/Game/UI/Panels/WBP_Panel"
local TEXT_CLASS = "/Game/UI/Common/WBP_DomTextBlock"

local state = nil
local started = false
local cached_pc, next_pc_scan = nil, 0
local pause_seen, pause_known, pause_look_at = {}, nil, 0
local click_hooked = false
local escape_hooked = false
local menu = {
    label = "MOD MANAGER",
    pause = nil,
    button = nil,
    button_name = nil,
    close_name = nil,
    reload_name = nil,
    action_names = {},
    module_names = {},
    row_names = {},
    pending_module = nil,
    pending_row = nil,
    pending = nil,
    wait = 0,
    broken = false,
    selected_seen = false,
}
local panel = {
    open = false,
    frame = nil,
    pc = nil,
    status = nil,
    status_sizer = nil,
    detail = nil,
    notification = nil,
    notification_until = 0,
    module_buttons = {},
    name_input = nil,
    action_buttons = {},
    rows_box = nil,
    rows_scroll = nil,
    action_sizer = nil,
    tree = nil,
    active_module = nil,
    selected_row = nil,
    broken = false,
}
local key_state = {
    menu_down = false,
    escape_down = false,
    escape_requested = false,
    restore_when_escape_up = false,
    enter_down = false,
}
local key_capture = {
    active = false,
    module_id = nil,
    action_id = nil,
    prefix = nil,
    deadline = 0,
    down = {},
}

local function valid(object)
    if not object then return false end
    local ok, value = pcall(function() return object:IsValid() end)
    return ok and value == true
end

local function full_name(object)
    local ok, value = pcall(function() return object:GetFullName() end)
    return ok and tostring(value) or nil
end

local function local_controller()
    cached_pc = engine.local_controller()
    return cached_pc
end

local function load_class(package_path)
    local asset = package_path:match("([^/]+)$")
    pcall(function() LoadAsset(package_path) end)
    local class = nil
    pcall(function() class = StaticFindObject(package_path .. "." .. asset .. "_C") end)
    return valid(class) and class or nil
end

local function widget_library()
    local library = nil
    pcall(function() library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    return valid(library) and library or nil
end

local function make_game_button(controller, label, like)
    local class = load_class(ALL_CAPS_BUTTON)
    local library = widget_library()
    if not class or not library then return nil end
    local button = nil
    pcall(function() button = library:Create(controller, class, controller) end)
    if not valid(button) then return nil end
    if valid(like) then
        pcall(function() button:SetStyle(like.Style) end)
        pcall(function() button:SetTextTransformPolicy(like.TextTransformPolicy) end)
        pcall(function() button.bCenterAlignText = like.bCenterAlignText end)
        pcall(function() button.LeftAlignTextPadding = like.LeftAlignTextPadding end)
        pcall(function() button.bScrollText = like.bScrollText end)
    end
    pcall(function() button:SetLabelText(FText(label)) end)
    return button
end

local function usable_pause(pause)
    if not valid(pause) then return false end
    local ok, name = pcall(function() return pause:GetFName():ToString() end)
    return ok and not tostring(name):find("^Default__")
end

local function find_pause_menu()
    if usable_pause(menu.pause) then return menu.pause end
    while #pause_seen > 0 do
        local pause = table.remove(pause_seen)
        if usable_pause(pause) then pause_seen = {}; pause_known = pause end
    end
    if usable_pause(pause_known) then return pause_known end
    if pause_look_at > 0 and os.clock() >= pause_look_at then
        pause_look_at = 0
        local ok, pause = pcall(FindFirstOf, "WBP_PauseMenuScreen_C")
        if ok and usable_pause(pause) then pause_known = pause; return pause end
    end
    return nil
end

local function menu_has(box, widget)
    local ok, index = pcall(function() return box:GetChildIndex(widget) end)
    return ok and type(index) == "number" and index >= 0
end

local fit_state = { count = -1, height = -1, settle = 0 }
local function fit_pause_list(box, force)
    if force then fit_state.settle = 3 end
    if not valid(box) then return end
    local slot = nil
    pcall(function() slot = box.Slot end)
    if not valid(slot) then return end
    local function number(call)
        local ok, value = pcall(call)
        return ok and type(value) == "number" and value == value and value or nil
    end
    local count = number(function() return box:GetChildrenCount() end)
    local height = number(function() return slot:GetOffsets().Bottom end)
    if not count or not height then return end
    if count == fit_state.count and fit_state.settle <= 0 and height >= fit_state.height - 0.5 then return end
    fit_state.count, fit_state.height = count, height
    if fit_state.settle > 0 then fit_state.settle = fit_state.settle - 1 end
    local auto = false
    pcall(function() auto = slot:GetAutoSize() end)
    if auto == true then return end
    local top = number(function() return slot:GetOffsets().Top end)
    local left = number(function() return slot:GetOffsets().Left end)
    local right = number(function() return slot:GetOffsets().Right end)
    local min_y = number(function() return slot:GetAnchors().Minimum.Y end)
    local max_y = number(function() return slot:GetAnchors().Maximum.Y end)
    local align_y = number(function() return slot:GetAlignment().Y end)
    if not (top and left and right and min_y and max_y and align_y) then return end
    if math.abs(max_y - min_y) > 0.0001 then return end
    pcall(function() box:ForceLayoutPrepass() end)
    local needed = number(function() return box:GetDesiredSize().Y end)
    if not needed or needed <= height + 0.5 then return end
    needed = math.ceil(needed)
    local edge = top - align_y * height
    local ok = pcall(function()
        slot:SetOffsets({ Left = left, Top = edge + align_y * needed, Right = right, Bottom = needed })
    end)
    if ok then fit_state.height = needed end
end

local function ensure_menu_button()
    if not (state and state.config and state.config.ShowInPauseMenu) then return end
    if usable_pause(menu.pause) and valid(menu.button) then
        local box = menu.pause.VerticalBox_PauseMenu
        if valid(box) and menu_has(box, menu.button) then fit_pause_list(box); return end
    end
    if menu.broken then return end
    if menu.wait > 0 then menu.wait = menu.wait - 1; return end
    menu.wait = 4
    local controller = local_controller()
    local pause = find_pause_menu()
    if not controller or not pause then return end
    local box = pause.VerticalBox_PauseMenu
    if not valid(box) then return end
    local button = make_game_button(controller, menu.label, pause.SettingsButton)
    if not button then return end

    local game_owned = {}
    for _, name in ipairs({ "ResumeButton", "AgilityCourseSection", "PlayerListButton", "WorldDetails",
        "SettingsButton", "ExitToMainMenuButton", "ExitToDesktopMenu" }) do
        local widget = pause[name]
        if valid(widget) then game_owned[full_name(widget)] = true end
    end
    local function sort_key(widget)
        local ok, label = pcall(function() return widget.ButtonLabel:ToString() end)
        return ok and tostring(label):gsub("^SHOW ", ""):gsub("^HIDE ", "") or ""
    end
    local extras = { button }
    for index = box:GetChildrenCount() - 1, 0, -1 do
        local child = box:GetChildAt(index)
        if valid(child) and not game_owned[full_name(child)] then extras[#extras + 1] = child end
    end
    local exits = {}
    for _, name in ipairs({ "ExitToMainMenuButton", "ExitToDesktopMenu" }) do
        local exit = pause[name]
        if valid(exit) and menu_has(box, exit) then exits[#exits + 1] = exit end
    end
    for _, widget in ipairs(extras) do
        if widget ~= button then pcall(function() box:RemoveChild(widget) end) end
    end
    for _, exit in ipairs(exits) do pcall(function() box:RemoveChild(exit) end) end
    table.sort(extras, function(left, right) return sort_key(left) < sort_key(right) end)
    for _, widget in ipairs(extras) do pcall(function() box:AddChildToVerticalBox(widget) end) end
    for _, exit in ipairs(exits) do pcall(function() box:AddChildToVerticalBox(exit) end) end

    menu.pause, menu.button, menu.button_name = pause, button, full_name(button)
    if not menu_has(box, button) then
        menu.broken = true
        log.warn("pause-menu button could not be confirmed; use the shortcut instead")
        return
    end
    pcall(function() button:SetIsSelectable(true) end)
    fit_pause_list(box, true)
    log.info("added MOD MANAGER to the pause menu")
end

local class_cache = {}
local function construct(tree, class_name)
    local class = class_cache[class_name]
    if class == nil then
        pcall(function() class = StaticFindObject("/Script/UMG." .. class_name) end)
        if not valid(class) then class = false end
        class_cache[class_name] = class
    end
    if not class then return nil end
    return StaticConstructObject(class, tree)
end

local function new_text(tree, class, text, size, color)
    local block = StaticConstructObject(class, tree)
    pcall(function() local font = block.Font; font.Size = size; block:SetFont(font) end)
    pcall(function() block:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
    pcall(function() block:SetText(FText(text)) end)
    return block
end

local function add_spacer(tree, column, height)
    local spacer = construct(tree, "Spacer")
    if not spacer then return end
    pcall(function() spacer:SetSize({ X = 1, Y = height }) end)
    pcall(function() column:AddChildToVerticalBox(spacer) end)
end

local function sized(tree, widget, width, height)
    local box = construct(tree, "SizeBox")
    if not box then return widget end
    if width then pcall(function() box:SetWidthOverride(width) end) end
    if height then pcall(function() box:SetHeightOverride(height) end) end
    if widget then pcall(function() box:AddChild(widget) end) end
    return box
end

local function pad(slot, left, top, right, bottom)
    pcall(function()
        slot:SetPadding({ Left = left or 0, Top = top or 0, Right = right or 0, Bottom = bottom or 0 })
    end)
end

local function style_input(input)
    pcall(function()
        local function color(r, g, b, a)
            return { SpecifiedColor = { R = r, G = g, B = b, A = a }, ColorUseRule = 0 }
        end
        local style = input.WidgetStyle
        style.BackgroundColor = color(0.025, 0.022, 0.018, 1.0)
        style.ForegroundColor = color(0.94, 0.89, 0.78, 1.0)
        style.FocusedForegroundColor = color(1.0, 0.96, 0.86, 1.0)
        for _, name in ipairs({ "BackgroundImageNormal", "BackgroundImageHovered", "BackgroundImageFocused" }) do
            local brush = style[name]
            local shade = name == "BackgroundImageNormal" and 0.055 or 0.10
            brush.TintColor = color(shade, shade * 0.9, shade * 0.72, 1.0)
            style[name] = brush
        end
        pcall(function()
            local text_style = style.TextStyle
            local font = text_style.Font
            font.Size = 17
            text_style.Font = font
            style.TextStyle = text_style
        end)
        input.WidgetStyle = style
    end)
    pcall(function()
        local font = input.WidgetStyle.TextStyle.Font
        font.Size = 17
        input:SetFont(font)
    end)
end

local function hex_color(value, fallback)
    local hex = tostring(value or ""):match("^#?(%x%x%x%x%x%x)$")
    if not hex then return fallback end
    return {
        R = tonumber(hex:sub(1, 2), 16) / 255,
        G = tonumber(hex:sub(3, 4), 16) / 255,
        B = tonumber(hex:sub(5, 6), 16) / 255,
        A = 1.0,
    }
end

local function build_panel(controller)
    local library = widget_library()
    local panel_class = load_class(PANEL_CLASS)
    local text_class = load_class(TEXT_CLASS)
    if not library or not panel_class or not text_class then return nil, "game panel classes unavailable" end
    local frame = nil
    pcall(function() frame = library:Create(controller, panel_class, controller) end)
    if not valid(frame) then return nil, "panel creation failed" end
    pcall(function() frame.BackgroundPanel:SetRenderOpacity(0.9) end)
    local tree = frame.WidgetTree
    local root = construct(tree, "VerticalBox")
    if not root then return nil, "VerticalBox class unavailable" end
    frame.PanelContent:AddChild(root)
    panel.tree = tree

    local gold = { R = 0.91, G = 0.77, B = 0.48, A = 1.0 }
    local cream = { R = 0.90, G = 0.87, B = 0.80, A = 1.0 }
    local grey = { R = 0.58, G = 0.56, B = 0.52, A = 1.0 }
    root:AddChildToVerticalBox(new_text(tree, text_class, "MOD MANAGER", 30, gold))
    local header_line = construct(tree, "HorizontalBox")
    if not header_line then return nil, "header HorizontalBox unavailable" end
    header_line:AddChildToHorizontalBox(new_text(tree, text_class,
        "Standalone Dragonwilds mods", 15, cream))
    local header_gap = construct(tree, "Spacer")
    if header_gap then
        local gap_slot = header_line:AddChildToHorizontalBox(header_gap)
        pcall(function() gap_slot:SetSize({ Value = 1, SizeRule = 1 }) end)
    end
    local notification = new_text(tree, text_class, "", 14, gold)
    pcall(function() notification:SetAutoWrapText(false) end)
    pcall(function() notification:SetVisibility(1) end)
    header_line:AddChildToHorizontalBox(notification)
    root:AddChildToVerticalBox(sized(tree, header_line, 1030, 30))
    add_spacer(tree, root, 12)

    local body = construct(tree, "HorizontalBox")
    if not body then return nil, "HorizontalBox class unavailable" end
    root:AddChildToVerticalBox(sized(tree, body, nil, 610))

    local navigation = construct(tree, "VerticalBox")
    if not navigation then return nil, "navigation VerticalBox unavailable" end
    navigation:AddChildToVerticalBox(new_text(tree, text_class, "MODULES", 14, gold))
    add_spacer(tree, navigation, 8)
    local module_scroll = construct(tree, "ScrollBox")
    local module_list = construct(tree, "VerticalBox")
    if not module_scroll or not module_list then return nil, "module ScrollBox unavailable" end
    module_scroll:AddChild(module_list)
    navigation:AddChildToVerticalBox(sized(tree, module_scroll, 230, 500))
    for _, module in ipairs(state.modules or {}) do
        local label = module.manifest.ui.menuLabel
        local module_button = make_game_button(controller, label, menu.button)
        if module_button then
            module_list:AddChildToVerticalBox(module_button)
            menu.module_names[full_name(module_button)] = module.id
            panel.module_buttons[module.id] = module_button
            pcall(function() module_button:SetIsSelectable(true) end)
        end
    end
    add_spacer(tree, navigation, 6)
    local reload = make_game_button(controller, "RELOAD MODS", menu.button)
    if reload then
        navigation:AddChildToVerticalBox(sized(tree, reload, 230, 42))
        menu.reload_name = full_name(reload)
        pcall(function() reload:SetIsSelectable(true) end)
    end
    local navigation_slot = body:AddChildToHorizontalBox(sized(tree, navigation, 230, 600))
    pad(navigation_slot, 0, 0, 22, 0)

    local content = construct(tree, "VerticalBox")
    if not content then return nil, "content VerticalBox unavailable" end
    local content_slot = body:AddChildToHorizontalBox(sized(tree, content, 760, 600))
    pcall(function() content_slot:SetSize({ Value = 1, SizeRule = 1 }) end)

    local status_text = "Select a module."
    if #(state.modules or {}) == 0 then
        status_text = "No modules installed. Add a module folder under Modules/, then press RELOAD MODS."
    end
    local status = new_text(tree, text_class, status_text, 18, cream)
    pcall(function() status:SetAutoWrapText(true) end)
    local status_sizer = sized(tree, status, 735, 42)
    content:AddChildToVerticalBox(status_sizer)
    panel.status_sizer = status_sizer
    add_spacer(tree, content, 6)
    local detail = new_text(tree, text_class, "Module details will appear here.", 15, grey)
    pcall(function() detail:SetAutoWrapText(true) end)
    pcall(function() detail:SetWrapTextAt(720) end)
    -- Wrapped module details must use their desired height. A fixed SizeBox
    -- clipped long item names after the second line; the fill-height entry
    -- list below can safely yield space while keeping controls bottom-aligned.
    content:AddChildToVerticalBox(detail)
    add_spacer(tree, content, 8)

    local rows_scroll = construct(tree, "ScrollBox")
    local rows_box = construct(tree, "VerticalBox")
    if not rows_scroll or not rows_box then return nil, "content ScrollBox unavailable" end
    rows_scroll:AddChild(rows_box)
    local rows_wrapper = sized(tree, rows_scroll, 735, nil)
    local rows_slot = content:AddChildToVerticalBox(rows_wrapper)
    -- The list owns all space left between the module information and the
    -- controls. This anchors the input/actions to the bottom without relying
    -- on a resolution-specific list height.
    pcall(function() rows_slot:SetSize({ Value = 1, SizeRule = 1 }) end)
    panel.rows_box = rows_box
    panel.rows_scroll = rows_scroll
    add_spacer(tree, content, 8)

    local initial_module = state.modules and state.modules[1] or nil
    local initial_actions = initial_module and initial_module.manifest.ui.actions or {}
    local initial_action = initial_actions[1]
    local name_input = construct(tree, "EditableTextBox")
    if name_input then
        pcall(function()
            name_input:SetHintText(FText(initial_action and initial_action.inputHint or "Name"))
        end)
        style_input(name_input)
        content:AddChildToVerticalBox(sized(tree, name_input, 735, 42))
        panel.name_input = name_input
        add_spacer(tree, content, 6)
    end

    local action_capacity = 0
    for _, module in ipairs(state.modules or {}) do
        action_capacity = math.max(action_capacity, #(module.manifest.ui.actions or {}))
    end
    local action_grid = construct(tree, "UniformGridPanel")
    local action_scroll = construct(tree, "ScrollBox")
    if not action_grid or not action_scroll then return nil, "action panel unavailable" end
    action_scroll:AddChild(action_grid)
    local action_sizer = sized(tree, action_scroll, 735, 160)
    content:AddChildToVerticalBox(action_sizer)
    panel.action_sizer = action_sizer
    for index = 1, action_capacity do
        local action = initial_actions[index]
        local action_button = make_game_button(controller,
            action and action.label or "MODULE ACTION", menu.button)
        if action_button then
            local row = math.floor((index - 1) / 2)
            local column = (index - 1) % 2
            local wrapper = sized(tree, action_button, 360, 42)
            local slot = action_grid:AddChildToUniformGrid(wrapper, row, column)
            pad(slot, column == 0 and 0 or 5, 0, column == 0 and 5 or 0, 7)
            menu.action_names[full_name(action_button)] = index
            panel.action_buttons[index] = action_button
            pcall(function() action_button:SetIsSelectable(true) end)
        end
    end
    add_spacer(tree, content, 5)

    pcall(function() frame:SetVisibility(1) end)
    frame:AddToViewport(9000)
    local width, height = 1080, 750
    local viewport_width, viewport_height = 1920, 1080
    pcall(function()
        local layout = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local viewport, scale = layout:GetViewportSize(controller), layout:GetViewportScale(controller)
        viewport_width, viewport_height = viewport.X / scale, viewport.Y / scale
    end)
    frame:SetPositionInViewport({ X = math.max(0, (viewport_width - width) / 2),
                                  Y = math.max(10, (viewport_height - height) / 2) }, false)
    frame:SetDesiredSizeInViewport({ X = width, Y = height })
    return { frame = frame, status = status, detail = detail, notification = notification }
end

local function set_visible(widget, visible)
    if valid(widget) then pcall(function() widget:SetVisibility(visible and 0 or 1) end) end
end

local function show_global_notification(message)
    if not valid(panel.notification) then return end
    pcall(function() panel.notification:SetText(FText(tostring(message or ""))) end)
    set_visible(panel.notification, tostring(message or "") ~= "")
    panel.notification_until = tostring(message or "") ~= "" and (os.clock() + 5) or 0
end

local function render_rows(rows)
    if not valid(panel.rows_box) or not panel.tree then return end
    pcall(function() panel.rows_box:ClearChildren() end)
    if valid(panel.rows_scroll) then pcall(function() panel.rows_scroll:ScrollToStart() end) end
    local text_class = load_class(TEXT_CLASS)
    if not text_class then return end
    local grey = { R = 0.63, G = 0.60, B = 0.54, A = 1.0 }
    local gold = { R = 0.82, G = 0.69, B = 0.44, A = 1.0 }
    menu.row_names = {}
    if type(rows) ~= "table" or #rows == 0 then
        panel.rows_box:AddChildToVerticalBox(new_text(
            panel.tree, text_class, "No saved entries in this module.", 15, grey))
        return
    end
    local compact = #rows > 12 or (rows[1] and rows[1].compact == true)
    for _, row in ipairs(rows) do
        if compact and row.value ~= nil then
            local select_button = make_game_button(panel.pc, tostring(row.title or "Untitled"), menu.button)
            if select_button then
                panel.rows_box:AddChildToVerticalBox(sized(panel.tree, select_button, 710, 44))
                add_spacer(panel.tree, panel.rows_box, 4)
                menu.row_names[full_name(select_button)] = {
                    value = tostring(row.value), input = tostring(row.inputValue or row.title or row.value),
                    detail = row.detail and tostring(row.detail) or nil,
                }
                pcall(function() select_button:SetIsSelectable(true) end)
            end
        else
        local card = construct(panel.tree, "VerticalBox")
        if card then
            if row.value ~= nil then
                local select_button = make_game_button(panel.pc, tostring(row.title or "Untitled"), menu.button)
                if select_button then
                    card:AddChildToVerticalBox(sized(panel.tree, select_button, 710, 42))
                    menu.row_names[full_name(select_button)] = {
                        value = tostring(row.value), input = tostring(row.inputValue or row.value),
                        detail = row.detail and tostring(row.detail) or nil,
                    }
                    pcall(function() select_button:SetIsSelectable(true) end)
                end
            else
                local title = new_text(panel.tree, text_class, tostring(row.title or "Untitled"), 18,
                    hex_color(row.color, gold))
                card:AddChildToVerticalBox(title)
            end
            local subtitle = new_text(panel.tree, text_class, tostring(row.subtitle or ""), 13, grey)
            pcall(function() subtitle:SetAutoWrapText(false) end)
            pcall(function() subtitle:SetWrapTextAt(690) end)
            card:AddChildToVerticalBox(sized(panel.tree, subtitle, 710, 54))
            add_spacer(panel.tree, card, 8)
            panel.rows_box:AddChildToVerticalBox(sized(panel.tree, card, 710, 108))
        end
        end
    end
    if valid(panel.rows_scroll) then pcall(function() panel.rows_scroll:ScrollToStart() end) end
end

local function set_ui_input(controller, focus, enabled)
    if not valid(controller) then return end
    local library = widget_library()
    if not library then return end
    pcall(function() controller.bShowMouseCursor = enabled == true end)
    if enabled then
        local ok = pcall(function() library:SetInputMode_UIOnlyEx(controller, focus, 0, false) end)
        if not ok then pcall(function() library:SetInputMode_GameAndUIEx(controller, focus, 0, false, false) end) end
        if valid(focus) then pcall(function() focus:SetUserFocus(controller) end) end
    else
        pcall(function() library:SetInputMode_GameOnly(controller, false) end)
    end
end

local function close_panel(wait_for_escape)
    if not panel.open then return end
    key_capture.active = false
    if valid(panel.frame) then pcall(function() panel.frame:SetVisibility(1) end) end
    panel.open = false
    key_state.restore_when_escape_up = wait_for_escape == true
    if not key_state.restore_when_escape_up then set_ui_input(panel.pc, nil, false) end
    log.info("mod manager closed")
end

local function find_module(id)
    for _, module in ipairs(state.modules or {}) do
        if module.id == id then return module end
    end
    return nil
end

local function activate_module(id)
    local module = find_module(id) or (state.modules and state.modules[1])
    if not module then return false end
    if panel.active_module and panel.active_module ~= module.id then
        panel.selected_row = nil
        if valid(panel.name_input) then pcall(function() panel.name_input:SetText(FText("")) end) end
    end
    panel.active_module = module.id

    local ok, view = pcall(module.runtime.activate, state)
    if not ok or type(view) ~= "table" then
        view = {
            status = module.manifest.name .. " is unavailable.",
            detail = tostring(ok and "invalid module response" or view),
        }
    end
    local status_text = tostring(view.status or "")
    pcall(function() panel.status:SetText(FText(status_text)) end)
    set_visible(panel.status_sizer, status_text ~= "")
    pcall(function() panel.detail:SetText(FText(tostring(view.detail or module.manifest.description or ""))) end)
    render_rows(view.rows)
    if view.compatibility then state.compatibility = view.compatibility end
    if view.liveSnapshot then state.liveSnapshot = view.liveSnapshot end

    for module_id, button in pairs(panel.module_buttons) do
        pcall(function() button:SetIsSelected(module_id == module.id) end)
    end

    local actions = module.manifest.ui.actions or {}
    if valid(panel.action_sizer) then
        local action_height = math.max(48, math.min(160, math.ceil(#actions / 2) * 49 + 4))
        pcall(function() panel.action_sizer:SetHeightOverride(action_height) end)
    end
    local has_runner = type(module.runtime.run_action) == "function"
    local needs_input, first_hint = false, nil
    for _, action in ipairs(actions) do
        if action.requiresInput == true then
            needs_input = true
            first_hint = first_hint or action.inputHint
        end
    end
    set_visible(panel.name_input, needs_input)
    if needs_input then
        pcall(function() panel.name_input:SetHintText(FText(tostring(first_hint or "Value"))) end)
    end
    for index, button in ipairs(panel.action_buttons) do
        local action = actions[index]
        local available = has_runner and type(action) == "table"
        set_visible(button, available)
        if available then
            pcall(function() button:SetLabelText(FText(tostring(action.label or "RUN"))) end)
        end
    end
    return true
end

local function open_panel()
    if panel.open or panel.broken then return end
    local controller = local_controller()
    if not controller then return end
    if not valid(panel.frame) then
        local built, build_error = build_panel(controller)
        if not built then panel.broken = true; log.error(build_error); return end
        panel.frame, panel.status, panel.detail = built.frame, built.status, built.detail
        panel.notification = built.notification
    end
    panel.pc = controller
    pcall(function() panel.frame:SetVisibility(0) end)
    panel.open = true
    activate_module(panel.active_module)
    set_ui_input(controller, panel.frame, true)
    log.info("mod manager opened")
end

local function input_text(widget)
    if not valid(widget) then return "" end
    local ok, value = pcall(function() return widget:GetText() end)
    if not ok or value == nil then return "" end
    if type(value) == "string" then return value end
    local ok_text, text = pcall(function() return value:ToString() end)
    return ok_text and tostring(text) or ""
end

local CAPTURE_BASES = {
    { canonical = "MOUSE4", unreal = { "ThumbMouseButton", "MouseButton4", "XButton1" } },
    { canonical = "MOUSE5", unreal = { "ThumbMouseButton2", "MouseButton5", "XButton2" } },
    { canonical = "MIDDLE_MOUSE", unreal = { "MiddleMouseButton", "MiddleMouse" } },
}
for index = 1, 12 do
    CAPTURE_BASES[#CAPTURE_BASES + 1] = { canonical = "F" .. tostring(index), unreal = "F" .. tostring(index) }
end
for code = string.byte("A"), string.byte("Z") do
    local name = string.char(code)
    CAPTURE_BASES[#CAPTURE_BASES + 1] = { canonical = name, unreal = name }
end
local DIGIT_KEYS = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
for index = 0, 9 do
    CAPTURE_BASES[#CAPTURE_BASES + 1] = { canonical = tostring(index), unreal = DIGIT_KEYS[index + 1] }
end

local function input_key_down(controller, unreal_names, include_just_pressed)
    local names = type(unreal_names) == "table" and unreal_names or { unreal_names }
    for _, unreal_name in ipairs(names) do
        local key = { KeyName = FName(unreal_name) }
        local pressed, just_pressed = false, false
        pcall(function() pressed = controller:IsInputKeyDown(key) end)
        if pressed == true then return true end
        if include_just_pressed == true then
            pcall(function() just_pressed = controller:WasInputKeyJustPressed(key) end)
            if just_pressed == true then return true end
        end
    end
    return false
end

local function modifier_down(controller, left, right)
    return input_key_down(controller, left) or input_key_down(controller, right)
end

local function begin_key_capture(module, action, options)
    local controller = local_controller()
    key_capture.active = true
    key_capture.module_id = module.id
    key_capture.action_id = action.id
    key_capture.prefix = tostring(options.prefix or "")
    key_capture.deadline = os.clock() + math.max(1, tonumber(options.seconds) or 3)
    key_capture.down = {}
    if controller then
        for _, key in ipairs(CAPTURE_BASES) do
            key_capture.down[key.canonical] = input_key_down(controller, key.unreal)
        end
    end
    if valid(panel.detail) then
        pcall(function() panel.detail:SetText(FText(
            "Listening for a key combination… press it within 3 seconds. Esc cancels.")) end)
    end
end

local function run_module_action(action_index)
    if not panel.open then return end
    local module = find_module(panel.active_module)
    local actions = module and module.manifest.ui.actions or nil
    local action = actions and actions[action_index] or nil
    if not module or type(module.runtime.run_action) ~= "function" or not action then return end
    local call_ok, ok, message, options = pcall(
        module.runtime.run_action, state, action.id, input_text(panel.name_input))
    if not call_ok then ok, message, options = false, ok, nil end
    if ok then
        -- Actions which do not change their list can retain the exact current
        -- row widgets, highlight and scroll offset. This is useful for repeat
        -- actions such as applying the same selection again.
        if not (type(options) == "table" and options.preserveView == true) then
            activate_module(module.id)
        end
        pcall(function() panel.detail:SetText(FText(message)) end)
        if type(options) == "table" and type(options.captureHotkey) == "table" then
            begin_key_capture(module, action, options.captureHotkey)
        end
        if not (type(options) == "table" and options.preserveInput == true) then
            pcall(function() panel.name_input:SetText(FText("")) end)
        end
        log.info(message)
    else
        pcall(function() panel.detail:SetText(FText("Action stopped: " .. tostring(message))) end)
        log.warn(module.id .. " action stopped: " .. tostring(message))
    end
end

local function rename_selected_row()
    if not panel.open or not panel.selected_row then return end
    local module = find_module(panel.active_module)
    if not module or type(module.runtime.rename_selection) ~= "function" then return end
    local new_name = input_text(panel.name_input):gsub("^%s+", ""):gsub("%s+$", "")
    if new_name == "" then return end
    local call_ok, ok, message = pcall(
        module.runtime.rename_selection, state, panel.selected_row, new_name)
    if not call_ok then ok, message = false, ok end
    if ok then
        panel.selected_row = nil
        activate_module(module.id)
        pcall(function() panel.name_input:SetText(FText("")) end)
        pcall(function() panel.detail:SetText(FText(tostring(message))) end)
        log.info(message)
    else
        pcall(function() panel.detail:SetText(FText("Rename stopped: " .. tostring(message))) end)
        log.warn("rename stopped: " .. tostring(message))
    end
end

local function reload_mods()
    log.info("refreshing manifests and module runtimes in process")

    -- Keep the UE4SS host, hooks, schedulers and key loops alive. Restarting
    -- the current mod from its own UI tick can invalidate the executing Lua
    -- callback and crash the game even when UE4SS reports a successful reload.
    -- Modules refresh their own services when their runtime is reloaded.

    local ok, module_list, reload_error = pcall(modules.reload, state.paths)
    if not ok then module_list, reload_error = nil, module_list end
    if not module_list then
        local message = "Module refresh stopped: " .. tostring(reload_error or "unknown error")
        show_global_notification(message)
        log.warn(message)
        return
    end
    state.modules = module_list
    modules.start_all(state)

    local previous_module = panel.active_module
    local controller = panel.pc
    if panel.open then set_ui_input(controller, nil, false) end
    if valid(panel.frame) then pcall(function() panel.frame:RemoveFromParent() end) end
    panel.open = false
    panel.frame, panel.pc, panel.status, panel.detail = nil, nil, nil, nil
    panel.status_sizer, panel.notification, panel.notification_until = nil, nil, 0
    panel.module_buttons, panel.action_buttons = {}, {}
    panel.name_input, panel.rows_box, panel.rows_scroll = nil, nil, nil
    panel.action_sizer, panel.tree = nil, nil
    panel.active_module, panel.selected_row, panel.broken = previous_module, nil, false
    menu.close_name, menu.reload_name = nil, nil
    menu.action_names, menu.module_names, menu.row_names = {}, {}, {}

    open_panel()
    local message = ("Reloaded %d module(s) safely"):format(#module_list)
    show_global_notification(message)
    log.info(message)
end

local function route_click(name)
    if name == menu.button_name then menu.pending = "open"
    elseif name == menu.close_name then menu.pending = "close"
    elseif name == menu.reload_name then menu.pending = "reload-mods"
    elseif menu.action_names[name] then
        menu.pending_action = menu.action_names[name]
        menu.pending = "module-action"
    elseif menu.row_names[name] then
        menu.pending_row = menu.row_names[name]
        menu.pending = "select-row"
    elseif menu.module_names[name] then
        menu.pending_module = menu.module_names[name]
        menu.pending = "show-module"
    end
end

local function hook_clicks()
    if click_hooked then return end
    click_hooked = true
    local ok = pcall(RegisterHook, "/Script/CommonUI.CommonButtonBase:HandleButtonClicked", function(self)
        local ok_name, name = pcall(function() return self:get():GetFullName() end)
        if ok_name then route_click(name) end
    end)
    if not ok then log.warn("button-click hook unavailable; use F7") end
end

local function hook_escape()
    if escape_hooked then return end
    if type(RegisterKeyBind) ~= "function" or type(Key) ~= "table" or not Key.ESCAPE then
        log.warn("native Esc binding unavailable; controller polling remains active")
        return
    end
    local ok = pcall(RegisterKeyBind, Key.ESCAPE, function()
        -- UE4SS invokes this outside the game-thread UI loop. Only record the
        -- request here; main_tick performs the actual widget/input changes.
        key_state.escape_requested = true
    end)
    if ok then escape_hooked = true
    else log.warn("native Esc binding failed; controller polling remains active") end
end

local function poll_menu_selection()
    if not valid(menu.button) or menu.pending then menu.selected_seen = false; return end
    local ok, selected = pcall(function() return menu.button:GetSelected() end)
    if not (ok and selected == true) then menu.selected_seen = false; return end
    if not menu.selected_seen then menu.selected_seen = true; return end
    menu.selected_seen = false
    pcall(function() menu.button:SetIsSelectable(false); menu.button:SetIsSelectable(true) end)
    menu.pending = "open"
end

local function menu_tick()
    if menu.pending == "open" then
        menu.pending = "open-after-close"
        pcall(function() menu.pause:Resume() end)
    elseif menu.pending == "open-after-close" then
        menu.pending = nil
        open_panel()
    elseif menu.pending == "close" then
        menu.pending = nil
        close_panel(false)
    elseif menu.pending == "reload-mods" then
        menu.pending = nil
        reload_mods()
    elseif menu.pending == "show-module" then
        menu.pending = nil
        local module_id = menu.pending_module
        menu.pending_module = nil
        activate_module(module_id)
    elseif menu.pending == "module-action" then
        menu.pending = nil
        local action_index = menu.pending_action
        menu.pending_action = nil
        run_module_action(action_index)
    elseif menu.pending == "select-row" then
        menu.pending = nil
        local value = menu.pending_row
        menu.pending_row = nil
        local module = find_module(panel.active_module)
        if module and type(module.runtime.select_row) == "function" then
            local call_ok, handled = pcall(module.runtime.select_row, state,
                type(value) == "table" and value.value or value)
            if call_ok and handled == true then
                panel.selected_row = nil
                if valid(panel.name_input) then pcall(function() panel.name_input:SetText(FText("")) end) end
                activate_module(module.id)
                return
            end
        end
        panel.selected_row = type(value) == "table" and value.value or value
        local input_value = type(value) == "table" and value.input or value
        if type(value) == "table" and value.detail and valid(panel.detail) then
            pcall(function() panel.detail:SetText(FText(tostring(value.detail))) end)
        end
        if valid(panel.name_input) then
            pcall(function() panel.name_input:SetText(FText(tostring(input_value or ""))) end)
            pcall(function() panel.name_input:SetKeyboardFocus() end)
        end
    else
        ensure_menu_button()
        poll_menu_selection()
    end
end

local function engine_key(name)
    local upper = tostring(name or ""):upper()
    if upper:match("^F%d%d?$") or upper:match("^%u$") then return upper end
    local map = { HOME = "Home", END = "End", PAGE_UP = "PageUp", PAGE_DOWN = "PageDown",
        INS = "Insert", INSERT = "Insert", DEL = "Delete", DELETE = "Delete", SPACE = "SpaceBar" }
    return map[upper]
end

local function poll_keys()
    local controller = local_controller()
    if not controller then return end
    if key_capture.active then
        if input_key_down(controller, "Escape") then
            key_capture.active = false
            if valid(panel.detail) then
                pcall(function() panel.detail:SetText(FText("Key capture cancelled.")) end)
            end
            return
        end
        if os.clock() >= key_capture.deadline then
            key_capture.active = false
            if valid(panel.detail) then
                pcall(function() panel.detail:SetText(FText("No key detected; binding unchanged.")) end)
            end
            return
        end
        for _, key in ipairs(CAPTURE_BASES) do
            local pressed = input_key_down(controller, key.unreal, true)
            local was_down = key_capture.down[key.canonical] == true
            key_capture.down[key.canonical] = pressed
            if pressed and not was_down then
                local parts = {}
                if modifier_down(controller, "LeftControl", "RightControl") then parts[#parts + 1] = "CTRL" end
                if modifier_down(controller, "LeftAlt", "RightAlt") then parts[#parts + 1] = "ALT" end
                if modifier_down(controller, "LeftShift", "RightShift") then parts[#parts + 1] = "SHIFT" end
                parts[#parts + 1] = key.canonical
                local chord = table.concat(parts, "+")
                local module = find_module(key_capture.module_id)
                local action_id, prefix = key_capture.action_id, key_capture.prefix
                key_capture.active = false
                if module and type(module.runtime.run_action) == "function" then
                    local call_ok, ok, message = pcall(
                        module.runtime.run_action, state, action_id, prefix .. " " .. chord)
                    if not call_ok then ok, message = false, ok end
                    if ok then
                        activate_module(module.id)
                        if valid(panel.name_input) then
                            pcall(function() panel.name_input:SetText(FText(prefix)) end)
                        end
                        if valid(panel.detail) then pcall(function() panel.detail:SetText(FText(message)) end) end
                        log.info(message)
                    else
                        if valid(panel.detail) then
                            pcall(function() panel.detail:SetText(FText("Action stopped: " .. tostring(message))) end)
                        end
                        log.warn(module.id .. " key capture stopped: " .. tostring(message))
                    end
                end
                return
            end
        end
        return
    end
    local configured = state and state.config and state.config.MenuKey or "none"
    local key_name = engine_key(configured)
    if key_name then
        local down, just_pressed = false, false
        local menu_key = { KeyName = FName(key_name) }
        pcall(function() down = controller:IsInputKeyDown(menu_key) end)
        if down ~= true then
            pcall(function() just_pressed = controller:WasInputKeyJustPressed(menu_key) end)
        end
        if (down == true and not key_state.menu_down) or just_pressed == true then
            if panel.open then close_panel(false) else open_panel() end
        end
        key_state.menu_down = down == true
    end
    if panel.open or key_state.restore_when_escape_up then
        local escape, just_pressed = false, false
        local escape_key = { KeyName = FName("Escape") }
        pcall(function() escape = controller:IsInputKeyDown(escape_key) end)
        if escape ~= true then
            pcall(function() just_pressed = controller:WasInputKeyJustPressed(escape_key) end)
        end
        if panel.open and ((escape == true and not key_state.escape_down) or just_pressed == true) then
            close_panel(escape == true)
        end
        key_state.escape_down = escape == true
        if key_state.restore_when_escape_up and escape ~= true then
            key_state.restore_when_escape_up = false
            set_ui_input(controller, nil, false)
        end
    else
        key_state.escape_down = false
    end
    if panel.open and panel.selected_row then
        local enter = false
        pcall(function() enter = controller:IsInputKeyDown({ KeyName = FName("Enter") }) end)
        if enter == true and not key_state.enter_down then rename_selected_row() end
        key_state.enter_down = enter == true
    else
        key_state.enter_down = false
    end
end

local function main_tick()
    if panel.notification_until > 0 and os.clock() >= panel.notification_until then
        panel.notification_until = 0
        show_global_notification("")
    end
    if key_state.escape_requested then
        key_state.escape_requested = false
        if panel.open then close_panel(false) end
    end
    local ok, tick_error = pcall(menu_tick)
    if not ok then log.warn("UI tick failed: " .. tostring(tick_error)) end
end

function M.start(bootstrap_state)
    if started then return true, "already started" end
    state = bootstrap_state
    started = true
    pcall(NotifyOnNewObject, "/Script/Dominion.PauseMenuScreen", function(object)
        pause_seen[#pause_seen + 1] = object
    end)
    -- A UE4SS hot reload keeps the game's existing pause-menu UObject alive.
    -- NotifyOnNewObject therefore cannot see it again; arm the guarded
    -- FindFirstOf fallback so the MOD MANAGER entry is restored after reload.
    pause_look_at = os.clock() + 0.25
    hook_clicks()
    hook_escape()

    -- Restore the entry immediately when this is a hot reload. This does not
    -- depend on the repeating UI loop, and is harmless on a cold start where
    -- the pause menu has not been created yet.
    if type(ExecuteInGameThread) == "function" then
        pcall(ExecuteInGameThread, function()
            local ok, existing = pcall(FindFirstOf, "WBP_PauseMenuScreen_C")
            if ok and usable_pause(existing) then
                pause_known = existing
                pause_look_at = 0
                menu.wait = 0
                ensure_menu_button()
            end
        end)
    end

    local loop_ok = pcall(LoopInGameThreadWithDelay, 250, main_tick)
    if not loop_ok then return false, "this UE4SS build has no safe game-thread UI loop" end
    if not pcall(LoopInGameThreadWithDelay, 16, function() pcall(poll_keys) end) then
        log.warn("shortcut polling unavailable; use the pause-menu entry")
    end
    local key = tostring(state.config.MenuKey or "none")
    log.info("UI shell ready: Esc > MOD MANAGER" .. (key:lower() ~= "none" and (", or press " .. key) or ""))
    return true, "UI shell ready"
end

function M.is_open()
    return panel.open == true
end

function M.report_status(kind, message)
    if panel.open and valid(panel.detail) then
        pcall(function() panel.detail:SetText(FText(tostring(message))) end)
    end
    if kind == "incomplete" then log.warn(message) else log.info(message) end
end

function M.stop()
    if panel.open then
        panel.open = false
        key_state.restore_when_escape_up = false
        set_ui_input(panel.pc, nil, false)
    end
    if valid(panel.frame) then pcall(function() panel.frame:RemoveFromParent() end) end
    if valid(menu.button) then pcall(function() menu.button:RemoveFromParent() end) end
    panel.frame, panel.pc, panel.status, panel.detail = nil, nil, nil, nil
    panel.status_sizer, panel.notification, panel.notification_until = nil, nil, 0
    panel.rows_box, panel.rows_scroll, panel.action_sizer = nil, nil, nil
    panel.selected_row = nil
    menu.button, menu.pause = nil, nil
    pause_seen, pause_known, pause_look_at = {}, nil, 0
    key_state.escape_requested = false
    key_capture.active = false
    escape_hooked = false
    started = false
    return true
end

return M


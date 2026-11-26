-- Native-styled pause-menu entry and initial status shell.

local log = require("rlm_log")
local engine = require("rlm_engine")
local modules = require("rlm_modules")
local transaction = require("rlm_transaction")
local row_icons = require("rlm_row_icons")
local ui_kit = require("rlm_ui_kit")
local theme_loader = require("rlm_ui_theme")
local paths_helpers = require("rlm_paths")
local json = require("rlm_json")

local M = {}

local ALL_CAPS_BUTTON = "/Game/UI/Common/WBP_DomAllCapsButton"
local PANEL_CLASS = "/Game/UI/Panels/WBP_Panel"
local TEXT_CLASS = "/Game/UI/Common/WBP_DomTextBlock"

local state = nil
local started = false
local main_loop_handle = nil
local fast_loop_handle = nil
local cached_pc, next_pc_scan = nil, 0
local pause_seen, pause_known, pause_look_at = {}, nil, 0
local click_hooked = false
local escape_hooked = false
local enter_hooked = false
local enter_enabled, enter_requested = false, false
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
    action_scroll = nil,
    action_row_boxes = nil,
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
    escape_restore_deadline = 0,
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
    return spacer
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

local function set_visible(widget, visible)
    if valid(widget) then pcall(function() widget:SetVisibility(visible and 0 or 1) end) end
end

local function set_detail(text)
    if not valid(panel.detail) then return end
    text = tostring(text or "")
    pcall(function() panel.detail:SetText(FText(text)) end)
    set_visible(panel.detail, text ~= "")
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

local theme = theme_loader.defaults()
local SHELL_GOLD, SHELL_CREAM, SHELL_MUTED = theme.colors.gold, theme.colors.cream, theme.colors.muted
local kit = ui_kit.new({
    valid = valid, construct = construct, sized = sized, pad = pad,
    new_text = new_text, load_class = load_class, make_game_button = make_game_button,
    set_visible = set_visible, text_class = TEXT_CLASS, warn = log.warn,
})
local style_input, surface_with_shadow = kit.style_input, kit.surface_with_shadow
local make_panel_button, update_panel_button = kit.make_button, kit.update_button
local show_button_accent = kit.show_button_accent

local function refresh_theme(paths)
    local installed, user = paths and paths.installed_data, paths and paths.user_root
    local candidate, problem = theme_loader.load(json.decode,
        installed and paths_helpers.join(installed, "ui-theme.json"),
        user and paths_helpers.join(user, "ui-theme.json"))
    if not candidate then return nil, problem end
    theme = candidate
    theme_loader.set_active(theme)
    SHELL_GOLD, SHELL_CREAM, SHELL_MUTED = theme.colors.gold, theme.colors.cream, theme.colors.muted
    kit.set_theme(theme)
    state.uiThemeName = theme.name
    return true
end

local function build_panel(controller)
    local library = widget_library()
    local panel_class = load_class(PANEL_CLASS)
    local text_class = load_class(TEXT_CLASS)
    if not library or not panel_class or not text_class then return nil, "game panel classes unavailable" end
    local viewport_width, viewport_height = 1920, 1080
    pcall(function()
        local layout = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local viewport, scale = layout:GetViewportSize(controller), layout:GetViewportScale(controller)
        viewport_width, viewport_height = viewport.X / scale, viewport.Y / scale
    end)
    local width = math.max(980, math.min(1240, viewport_width - 40))
    local height = math.max(650, math.min(860, viewport_height - 40))
    local inner_width, inner_height = width - 50, height - 50
    local navigation_width, gutter = 218, 22
    local content_width = inner_width - navigation_width - gutter
    -- The title, subtitle line and their real font metrics consume closer to
    -- 80 units than the old 70-unit estimate. Keep a little lower inset too,
    -- otherwise the fixed body paints its footer and Reload Mods through the
    -- decorative bottom frame at shorter viewport heights.
    local body_height = math.max(500, inner_height - 90)
    local frame = nil
    pcall(function() frame = library:Create(controller, panel_class, controller) end)
    if not valid(frame) then return nil, "panel creation failed" end
    pcall(function() frame.BackgroundPanel:SetRenderOpacity(0.86) end)
    local tree = frame.WidgetTree
    local root = construct(tree, "VerticalBox")
    if not root then return nil, "VerticalBox class unavailable" end
    frame.PanelContent:AddChild(root)
    panel.tree, panel.content_width = tree, content_width
    panel.preview_tiles, panel.preview_headings, panel.compact_rows = {}, {}, {}
    panel.icon_owner, panel.icon_row_count, panel.icon_pending = nil, 0, false

    local gold, cream, grey = SHELL_GOLD, SHELL_CREAM, SHELL_MUTED
    root:AddChildToVerticalBox(new_text(tree, text_class, "MOD MANAGER", 26, gold))
    local header_line = construct(tree, "HorizontalBox")
    if not header_line then return nil, "header HorizontalBox unavailable" end
    header_line:AddChildToHorizontalBox(new_text(tree, text_class,
        "DRAGONWILDS TOOLS", 12, grey))
    local header_gap = construct(tree, "Spacer")
    if header_gap then
        local gap_slot = header_line:AddChildToHorizontalBox(header_gap)
        pcall(function() gap_slot:SetSize({ Value = 1, SizeRule = 1 }) end)
    end
    local notification = new_text(tree, text_class, "", 12, gold)
    pcall(function() notification:SetAutoWrapText(false) end)
    pcall(function() notification:SetVisibility(1) end)
    header_line:AddChildToHorizontalBox(notification)
    root:AddChildToVerticalBox(sized(tree, header_line, inner_width, 25))
    add_spacer(tree, root, 8)

    local body = construct(tree, "HorizontalBox")
    if not body then return nil, "HorizontalBox class unavailable" end
    root:AddChildToVerticalBox(sized(tree, body, inner_width, body_height))

    local navigation = construct(tree, "VerticalBox")
    if not navigation then return nil, "navigation VerticalBox unavailable" end
    local navigation_body_width = navigation_width - 18
    navigation:AddChildToVerticalBox(new_text(tree, text_class, "MODULES", 12, gold))
    add_spacer(tree, navigation, 5)
    local module_scroll = construct(tree, "ScrollBox")
    local module_list = construct(tree, "VerticalBox")
    if not module_scroll or not module_list then return nil, "module ScrollBox unavailable" end
    pcall(function() module_scroll:SetClipping(1) end)
    module_scroll:AddChild(module_list)
    panel.hovered_module = nil
    local rendering_ok, rendering = pcall(StaticFindObject, "/Script/Engine.Default__KismetRenderingLibrary")
    local art = state.paths and state.paths.mod_root and paths_helpers.join(state.paths.mod_root, "art")
    local refresh_texture, firefly_texture
    if rendering_ok and art then
        refresh_texture = engine.object_call(rendering, "ImportFileAsTexture2D", controller,
            paths_helpers.join(art, "ui_refresh.png"))
        firefly_texture = engine.object_call(rendering, "ImportFileAsTexture2D", controller,
            paths_helpers.join(art, "ui_firefly.png"))
    end
    local module_scroll_slot = navigation:AddChildToVerticalBox(sized(tree, module_scroll, navigation_body_width, nil))
    pcall(function() module_scroll_slot:SetSize({ Value = 1, SizeRule = 1 }) end)
    for _, module in ipairs(state.modules or {}) do
        local label = module.manifest.ui.menuLabel
        local entry = make_panel_button(controller, label, menu.button, tree,
            { color = cream, accent = "selected", fireflies = firefly_texture })
        if entry then
            local slot = module_list:AddChildToVerticalBox(sized(tree, entry.widget, navigation_body_width, theme.spacing.row))
            pad(slot, 0, 0, 0, 3)
            menu.module_names[full_name(entry.button)] = module.id
            panel.module_buttons[module.id] = entry
        end
    end
    add_spacer(tree, navigation, 8)
    local reload = make_panel_button(controller, "RELOAD MODS", menu.button, tree,
        { size = 13, color = gold })
    if reload then
        navigation:AddChildToVerticalBox(sized(tree, reload.widget, navigation_body_width, theme.spacing.row))
        menu.reload_name = full_name(reload.button)
    end
    local navigation_shell = navigation
    local navigation_rail = construct(tree, "Border")
    if navigation_rail then
        navigation_rail:AddChild(navigation)
        navigation_rail:SetPadding({ Left = 9, Top = 8, Right = 9, Bottom = 6 })
        kit.apply_surface(navigation_rail, "rail")
        navigation_shell = surface_with_shadow(tree, navigation_rail, "rail")
    end
    local navigation_slot = body:AddChildToHorizontalBox(sized(tree, navigation_shell, navigation_width, body_height))
    pad(navigation_slot, 0, 0, gutter, 0)

    local content = construct(tree, "VerticalBox")
    if not content then return nil, "content VerticalBox unavailable" end
    local content_slot = body:AddChildToHorizontalBox(sized(tree, content, content_width, body_height))
    pcall(function() content_slot:SetSize({ Value = 1, SizeRule = 1 }) end)

    panel.pinned_rows = {}
    local navigation_row = construct(tree, "HorizontalBox")
    if valid(navigation_row) then
        content:AddChildToVerticalBox(navigation_row)
        local max_button_width = math.floor((content_width - 16) / 2)
        for index = 1, 2 do
            local back = index == 1
            local entry
            if back then
                entry = make_panel_button(controller, "", menu.button, tree,
                    { color = cream, size = theme.typography.control, accent = "inset",
                      fireflies = firefly_texture, hoverable = true })
            else
                entry = kit.make_icon_button(controller, refresh_texture, menu.button, tree)
            end
            if not entry then break end
            local width = not back and not entry.icon_widget and math.min(176, max_button_width) or nil
            entry.max_width = max_button_width
            entry.holder = sized(tree, entry.widget, width, theme.spacing.row)
            local slot = navigation_row:AddChildToHorizontalBox(entry.holder)
            pad(slot, 0, 0, 8, 4)
            if not back and valid(slot) then
                pcall(function()
                    slot:SetSize({ Value = 1, SizeRule = 1 })
                    slot:SetHorizontalAlignment(3)
                end)
            end
            show_button_accent(entry, true)
            set_visible(entry.holder, false)
            panel.pinned_rows[index] = entry
        end
    end

    local status_text = "Select a module."
    local status = new_text(tree, text_class, status_text, 16, cream)
    pcall(function() status:SetAutoWrapText(true) end)
    local status_sizer = sized(tree, status, content_width - 8, 34)
    pad(content:AddChildToVerticalBox(status_sizer), 0, 0, 0, 3)
    panel.status_sizer = status_sizer

    local detail = new_text(tree, text_class, "Module details will appear here.", 13, grey)
    pcall(function() detail:SetAutoWrapText(true) end)
    pcall(function() detail:SetWrapTextAt(content_width - 18) end)
    -- Wrapped module details must use their desired height. A fixed SizeBox
    -- clipped long item names after the second line; the fill-height entry
    -- list below can safely yield space while keeping controls bottom-aligned.
    pad(content:AddChildToVerticalBox(detail), 0, 0, 0, 6)

    local rows_scroll = construct(tree, "ScrollBox")
    local preview_box = construct(tree, "VerticalBox")
    local rows_box = construct(tree, "VerticalBox")
    local compact_box = construct(tree, "VerticalBox")
    if not rows_scroll or not rows_box or not compact_box then return nil, "content ScrollBox unavailable" end
    pcall(function() rows_scroll:SetClipping(1) end)
    if preview_box then
        rows_scroll:AddChild(preview_box)
        pcall(function() preview_box:SetVisibility(1) end)
    end
    panel.inline_actions = construct(tree, "VerticalBox")
    if valid(panel.inline_actions) then rows_scroll:AddChild(panel.inline_actions) end
    rows_scroll:AddChild(rows_box)
    rows_scroll:AddChild(compact_box)
    local rows_wrapper = sized(tree, rows_scroll, content_width - 8, nil)
    local rows_slot = content:AddChildToVerticalBox(rows_wrapper)
    -- The list owns all space left between the module information and the
    -- controls. This anchors the input/actions to the bottom without relying
    -- on a resolution-specific list height.
    pcall(function() rows_slot:SetSize({ Value = 1, SizeRule = 1 }) end)
    panel.rows_box, panel.compact_box = rows_box, compact_box
    panel.preview_box, panel.item_preview, panel.preview_icon, panel.ingredient_icons = preview_box, nil, nil, nil
    panel.rows_scroll = rows_scroll
    add_spacer(tree, content, 5)

    panel.pagination = kit.make_pagination(controller, menu.button, tree)
    if panel.pagination then
        local slot = content:AddChildToVerticalBox(panel.pagination.widget)
        if valid(slot) then
            slot:SetHorizontalAlignment(3)
            pad(slot, 0, 0, 8, 4)
        end
        kit.update_pagination(panel.pagination, nil)
    end

    local footer = construct(tree, "Border")
    local footer_box = construct(tree, "VerticalBox")
    if not footer or not footer_box then return nil, "footer panel unavailable" end
    local footer_inner = content_width - 28
    pcall(function() footer:SetPadding({ Left = 10, Top = 8, Right = 10, Bottom = 5 }) end)
    pcall(function() footer:AddChild(footer_box) end)
    kit.apply_surface(footer, "dock")
    panel.footer = sized(tree, surface_with_shadow(tree, footer, "dock"), content_width - 8, nil)
    content:AddChildToVerticalBox(panel.footer)
    panel.footer_home, panel.footer_parent = content, content

    local initial_module = state.modules and state.modules[1] or nil
    local initial_actions = initial_module and initial_module.manifest.ui.actions or {}
    local initial_action = initial_actions[1]
    local name_input = construct(tree, "EditableTextBox")
    if name_input then
        pcall(function()
            name_input:SetHintText(FText(initial_action and initial_action.inputHint or "Name"))
        end)
        style_input(name_input)
        local input_sizer = sized(tree, name_input, footer_inner, theme.spacing.row)
        footer_box:AddChildToVerticalBox(input_sizer)
        panel.name_input, panel.input_sizer = name_input, input_sizer
        panel.input_gap = add_spacer(tree, footer_box, 5)
    end

    local action_capacity = 0
    for _, module in ipairs(state.modules or {}) do
        action_capacity = math.max(action_capacity, #(module.manifest.ui.actions or {}))
    end
    local action_scroll = construct(tree, "ScrollBox")
    if not action_scroll then return nil, "action panel unavailable" end
    pcall(function() action_scroll:SetClipping(1) end)
    local action_sizer = sized(tree, action_scroll, footer_inner, (theme.spacing.row + 4) * 3)
    pcall(function() action_sizer:SetClipping(1) end)
    footer_box:AddChildToVerticalBox(action_sizer)
    panel.action_scroll = action_scroll
    panel.action_sizer = action_sizer
    panel.action_row_boxes = {}
    local row_count = math.ceil(action_capacity / 2)
    local button_width = math.floor((footer_inner - 10) / 2)
    for row_index = 1, row_count do
        local pair = construct(tree, "HorizontalBox")
        if pair then
            pcall(function() pair:SetClipping(1) end)
            action_scroll:AddChild(pair)
            panel.action_row_boxes[row_index] = pair
            for column = 0, 1 do
                local index = (row_index - 1) * 2 + column + 1
                if index <= action_capacity then
                    local action = initial_actions[index]
                    local entry = make_panel_button(controller,
                        action and action.label or "MODULE ACTION", menu.button, tree,
                        { size = theme.typography.control - 1, center = true, color = cream, accent = "primary" })
                    if entry then
                        local wrapper = sized(tree, entry.widget, button_width, theme.spacing.row)
                        entry.holder = wrapper
                        local slot = pair:AddChildToHorizontalBox(wrapper)
                        pad(slot, column == 0 and 0 or 4, 0, column == 0 and 4 or 0, 4)
                        menu.action_names[full_name(entry.button)] = index
                        panel.action_buttons[index] = entry
                    end
                end
            end
        end
    end

    pcall(function() frame:SetVisibility(1) end)
    frame:AddToViewport(9000)
    frame:SetPositionInViewport({ X = math.max(0, (viewport_width - width) / 2),
                                  Y = math.max(10, (viewport_height - height) / 2) }, false)
    frame:SetDesiredSizeInViewport({ X = width, Y = height })
    return { frame = frame, status = status, detail = detail, notification = notification }
end


local function show_global_notification(message)
    if not valid(panel.notification) then return end
    pcall(function() panel.notification:SetText(FText(tostring(message or ""))) end)
    set_visible(panel.notification, tostring(message or "") ~= "")
    panel.notification_until = tostring(message or "") ~= "" and (os.clock() + 5) or 0
end

local function preview_tile_row(index, tiles, text_class, grey, gold)
    local entry = panel.preview_tiles[index]
    if not entry then
        local line = construct(panel.tree, "HorizontalBox")
        if not line then return end
        entry = { line = line, cells = {} }
        for column = 1, 2 do
            local card = construct(panel.tree, "VerticalBox")
            if not card then return end
            local title = new_text(panel.tree, text_class, "", 12, gold)
            local name = new_text(panel.tree, text_class, "", 16, gold)
            local detail = new_text(panel.tree, text_class, "", 13, grey)
            local cell_width = math.max(300, math.floor(((panel.content_width or 760) - 44) / 2))
            for _, block in ipairs({ title, name, detail }) do
                pcall(function() block:SetAutoWrapText(true); block:SetWrapTextAt(cell_width - 18) end)
                card:AddChildToVerticalBox(block)
            end
            local holder = sized(panel.tree, card, cell_width)
            pad(line:AddChildToHorizontalBox(holder), 5, 6, 8, 8)
            entry.cells[column] = { holder = holder, title = title, name = name, detail = detail }
        end
        panel.preview_tiles[index] = entry
    end
    for column, cell in ipairs(entry.cells) do
        local tile = tiles[column]
        set_visible(cell.holder, tile ~= nil)
        if tile then
            pcall(function()
                cell.title:SetText(FText(tostring(tile.title or "")))
                cell.name:SetText(FText(tostring(tile.name or "")))
                cell.detail:SetText(FText(tostring(tile.detail or "")))
                cell.detail:SetColorAndOpacity({ SpecifiedColor = hex_color(tile.color, grey), ColorUseRule = 0 })
            end)
        end
    end
    panel.rows_box:AddChildToVerticalBox(entry.line)
end

local prepare_row_icon = kit.prepare_row_icon

local function render_item_preview(preview)
    return kit.render_preview(panel, preview)
end

local function render_pooled_rows(rows)
    panel.icon_row_count = #rows
    for index, row in ipairs(rows) do
        local heading = type(row.heading) == "string"
        local title = tostring(row.heading or row.title or "Untitled")
        local entry = panel.compact_rows[index]
        if not entry then
            local created = make_panel_button(panel.pc, title, menu.button, panel.tree,
                { color = SHELL_CREAM, accent = "selected" })
            if not created then break end
            local holder = sized(panel.tree, created.widget, (panel.content_width or 760) - 32, theme.spacing.row)
            pad(panel.compact_box:AddChildToVerticalBox(holder), 0, 0, 0, 4)
            entry = created
            entry.holder, entry.overlay = holder, created.widget
            entry.accent_surface = "selected"
            panel.compact_rows[index] = entry
        end
        local button = entry.button
        if valid(button) then
            set_visible(entry.holder, true)
            local value = tostring(row.value)
            entry.normal = hex_color(row.color, heading and SHELL_MUTED or SHELL_CREAM)
            local icon = type(row.icon) == "string" and row.icon ~= "" and row.icon or nil
            local indent = math.min(12, math.max(0, tonumber(row.indent) or 0))
            prepare_row_icon(panel, entry, icon, 16 + indent * 18)
            local custom_label = valid(entry.label)
            local enabled = (heading and custom_label) or (not heading and row.disabled ~= true)
            if custom_label then set_visible(button, not heading) end
            local selected = not heading and enabled and (row.selected == true or value == panel.selected_row)
            kit.set_button_enabled(entry, enabled)
            update_panel_button(entry, title, selected)
            local framed = not heading and enabled and (row.destination == true or row.action == true)
            if valid(entry.accent) then
                local surface = framed and not selected and "inset" or "selected"
                if entry.accent_surface ~= surface then
                    kit.apply_surface(entry.accent, surface)
                    entry.accent_surface = surface
                end
            end
            show_button_accent(entry, selected or framed)
            local name = not heading and enabled and full_name(button)
            if name then
                menu.row_names[name] = { value = value, title = title,
                    input = tostring(row.inputValue or title),
                    detail = row.detail, entry = entry }
            end
        end
    end
    for index = #rows + 1, #panel.compact_rows do set_visible(panel.compact_rows[index].holder, false) end
end

local function render_rows(rows, pool_rows, pin_count)
    if not valid(panel.rows_box) or not panel.tree then return end
    if valid(panel.rows_scroll) then pcall(function() panel.rows_scroll:ScrollToStart() end) end
    menu.row_names = {}
    panel.icon_row_count = 0
    local pinned = 0
    for index, entry in ipairs(panel.pinned_rows or {}) do
        local row = pool_rows and type(rows) == "table" and index <= pin_count and index == pinned + 1 and rows[index]
        local name
        if type(row) == "table" and row.value ~= nil and row.disabled ~= true and valid(entry.button) then
            name = full_name(entry.button)
        end
        set_visible(entry.holder, name ~= nil)
        local value = name and row.value or nil
        if entry.icon_widget then
            if entry.bound_value ~= value then kit.animate_icon_button(entry, false) end
            entry.bound_value = value
        else
            if entry.bound_value ~= value then kit.animate_button_hover(entry, false) end
            entry.bound_value = value
        end
        if name then
            local title = tostring(row.title or row.value)
            kit.set_button_enabled(entry, true)
            update_panel_button(entry, title, false)
            if not entry.icon_widget and entry.max_width and valid(entry.holder) then
                local fit_width = math.max(148, math.min(entry.max_width, math.ceil(#title * 9.5) + 48))
                pcall(function() entry.holder:SetWidthOverride(fit_width) end)
            end
            menu.row_names[name] = { value = tostring(row.value), title = title, entry = entry,
                input = tostring(row.inputValue or title), detail = row.detail }
            pinned = index
        end
    end
    if pinned > 0 then rows = { table.unpack(rows, pinned + 1) } end
    local pooled = pool_rows and type(rows) == "table" and #rows <= 16 and valid(panel.compact_box)
    set_visible(panel.compact_box, pooled)
    set_visible(panel.rows_box, not pooled)
    if pooled then return render_pooled_rows(rows) end
    pcall(function() panel.rows_box:ClearChildren() end)
    local text_class = load_class(TEXT_CLASS)
    if not text_class then return end
    local grey = { R = 0.63, G = 0.60, B = 0.54, A = 1.0 }
    local gold = { R = 0.82, G = 0.69, B = 0.44, A = 1.0 }
    if type(rows) ~= "table" or #rows == 0 then
        panel.rows_box:AddChildToVerticalBox(new_text(
            panel.tree, text_class, "No saved entries in this module.", 15, grey))
        return
    end
    local compact = #rows > 12 or (rows[1] and rows[1].compact == true)
    local tile_index, heading_index = 0, 0
    for _, row in ipairs(rows) do
        local framed = row.destination == true or row.action == true
        if row.heading or row.disabled == true then
            heading_index = heading_index + 1
            local heading = panel.preview_headings[heading_index]
            if not heading then
                heading = new_text(panel.tree, text_class, "", 17, gold)
                panel.preview_headings[heading_index] = heading
            end
            pcall(function() heading:SetText(FText(tostring(row.heading or row.title or ""))) end)
            pcall(function()
                heading:SetColorAndOpacity({ SpecifiedColor = hex_color(row.color, SHELL_MUTED), ColorUseRule = 0 })
            end)
            pad(panel.rows_box:AddChildToVerticalBox(heading), 5, 8, 0, 2)
        elseif row.tiles then
            tile_index = tile_index + 1
            preview_tile_row(tile_index, row.tiles, text_class, grey, gold)
        elseif compact and row.value ~= nil then
            local entry = make_panel_button(panel.pc, tostring(row.title or "Untitled"), menu.button,
                panel.tree, { size = 14, color = hex_color(row.color, SHELL_CREAM), accent = framed and "inset" or nil })
            if entry then
                show_button_accent(entry, framed)
                panel.rows_box:AddChildToVerticalBox(sized(panel.tree, entry.widget,
                    (panel.content_width or 760) - 32, 38))
                add_spacer(panel.tree, panel.rows_box, 4)
                local value, title = tostring(row.value), tostring(row.title or "Untitled")
                menu.row_names[full_name(entry.button)] = {
                    value = value, title = title, entry = entry,
                    input = tostring(row.inputValue or row.title or row.value),
                    detail = row.detail and tostring(row.detail) or nil,
                }
                update_panel_button(entry, title, value == panel.selected_row)
            end
        else
        local card = construct(panel.tree, "VerticalBox")
        if card then
            if row.value ~= nil then
                local entry = make_panel_button(panel.pc, tostring(row.title or "Untitled"), menu.button,
                    panel.tree, { size = 14, color = hex_color(row.color, SHELL_CREAM), accent = framed and "inset" or nil })
                if entry then
                    show_button_accent(entry, framed)
                    card:AddChildToVerticalBox(sized(panel.tree, entry.widget,
                        (panel.content_width or 760) - 32, 38))
                    local value, title = tostring(row.value), tostring(row.title or "Untitled")
                    menu.row_names[full_name(entry.button)] = {
                        value = value, title = title, entry = entry,
                        input = tostring(row.inputValue or row.value),
                        detail = row.detail and tostring(row.detail) or nil,
                    }
                    update_panel_button(entry, title, value == panel.selected_row)
                end
            else
                local title = new_text(panel.tree, text_class, tostring(row.title or "Untitled"), 18,
                    hex_color(row.color, gold))
                card:AddChildToVerticalBox(title)
            end
            local subtitle = new_text(panel.tree, text_class, tostring(row.subtitle or ""), 13, grey)
            pcall(function() subtitle:SetAutoWrapText(false) end)
            pcall(function() subtitle:SetWrapTextAt((panel.content_width or 760) - 52) end)
            card:AddChildToVerticalBox(sized(panel.tree, subtitle,
                (panel.content_width or 760) - 32, 54))
            add_spacer(panel.tree, card, 8)
            panel.rows_box:AddChildToVerticalBox(sized(panel.tree, card,
                (panel.content_width or 760) - 32, 104))
        end
        end
    end
    if valid(panel.rows_scroll) then pcall(function() panel.rows_scroll:ScrollToStart() end) end
end

local function render_pagination(page)
    local pagination = panel.pagination
    if not pagination then return end
    kit.update_pagination(pagination, page)
    if not page then return end
    for _, direction in ipairs({ "previous", "next" }) do
        local entry = pagination[direction]
        if page[direction] and valid(entry.button) then
            local name = full_name(entry.button)
            if name then menu.row_names[name] = { value = page[direction], entry = entry } end
        end
    end
end

local function paint_row_icons()
    if not panel.open or not panel.icon_pending then return end
    local pending = {}
    if panel.preview_icon and not panel.preview_icon.icon_done then pending[1] = panel.preview_icon end
    for _, cell in ipairs(panel.ingredient_icons or {}) do
        if not cell.icon_done then pending[#pending + 1] = cell end
    end
    for index = 1, panel.icon_row_count or 0 do
        local entry = panel.compact_rows[index]
        if entry and entry.icon and entry.image and not entry.icon_done then pending[#pending + 1] = entry end
    end
    if #pending == 0 then
        panel.icon_pending = false
        row_icons.cancel_scan()
        return
    end
    local pawn = engine.local_pawn()
    if not valid(pawn) then row_icons.cancel_scan(); return end
    local ok, owner = pcall(function() return pawn:GetAddress() end)
    if not ok or not owner then row_icons.cancel_scan(); return end
    if panel.icon_owner and panel.icon_owner ~= owner then
        row_icons.cancel_scan()
        panel.icon_pending = false
        panel.icon_owner = nil
        return
    end
    panel.icon_owner = owner
    local started = os.clock()
    local processed, loaded_new, needs_index = 0, false, false
    for _, entry in ipairs(pending) do
        local path = row_icons.path(entry.icon)
        if path and started >= entry.icon_retry_at then
            local texture = row_icons.load(path, false)
            if not texture and entry.icon_attempts == 0 and not loaded_new then
                texture = row_icons.load(path, true)
                loaded_new = true
                entry.icon_attempts = 1
                entry.icon_retry_at = started + 0.10
            elseif entry.icon_attempts > 0 then
                entry.icon_attempts = entry.icon_attempts + 1
                entry.icon_retry_at = started + 0.10
            end
            if texture and valid(entry.image) and valid(entry.image_holder) then
                entry.icon_visible = pcall(function()
                    entry.image:SetBrushFromTexture(texture, false)
                    entry.image:SetVisibility(3)
                    entry.image_holder:SetVisibility(3)
                end)
            end
            entry.icon_done = texture ~= nil or entry.icon_attempts >= 8
            if texture or entry.icon_attempts > 0 then processed = processed + 1 end
        elseif not path and row_icons.index_ready() then
            entry.icon_done = true
        elseif not path then
            needs_index = true
        end
        if entry == panel.preview_icon and entry.icon_done and not entry.icon_visible then
            set_visible(entry.art, false)
        end
        if processed >= 4 or os.clock() - started >= 0.004 then break end
    end
    if needs_index and not loaded_new and os.clock() - started < 0.004 then row_icons.index_step() end
end

local hud_input_owner

local input_blocker = {
    imc = nil,
    ia = nil,
    subsystem = nil,
    retry_at = 0,
}

local function get_enhanced_input_subsystem(pc)
    if not valid(pc) then return nil end
    local sbl = StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
    local cls = StaticFindObject("/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem")
    if not (sbl and cls) then return nil end
    local s = nil
    pcall(function() s = sbl:GetLocalPlayerSubSystemFromPlayerController(pc, cls) end)
    return valid(s) and s or nil
end

local BLOCK_KEYS = {
    "SpaceBar", "LeftMouseButton", "RightMouseButton",
    "MiddleMouseButton", "ThumbMouseButton", "ThumbMouseButton2",
    "LeftShift", "LeftControl", "LeftAlt", "RightShift", "RightControl", "RightAlt",
    "Tab", "Escape", "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
}
for code = string.byte("A"), string.byte("Z") do BLOCK_KEYS[#BLOCK_KEYS + 1] = string.char(code) end
for key = 1, 12 do BLOCK_KEYS[#BLOCK_KEYS + 1] = "F" .. key end

local function ensure_blocker_context(pc)
    if valid(input_blocker.imc) and valid(input_blocker.ia) then return true end
    local ia_c = StaticFindObject("/Script/EnhancedInput.InputAction")
    local imc_c = StaticFindObject("/Script/EnhancedInput.InputMappingContext")
    if not (ia_c and imc_c) then return false end
    local outer = StaticFindObject("/Engine/Transient") or pc
    local ia, imc = nil, nil
    pcall(function()
        ia = StaticConstructObject(ia_c, outer)
        imc = StaticConstructObject(imc_c, outer)
    end)
    if not (valid(ia) and valid(imc)) then return false end
    pcall(function() ia.bConsumeInput = true end)
    for _, k in ipairs(BLOCK_KEYS) do
        pcall(function() imc:MapKey(ia, { KeyName = FName(k) }) end)
    end
    input_blocker.ia, input_blocker.imc = ia, imc
    return true
end

local function set_input_mask(pc, enable)
    local options = {
        bIgnoreAllPressedKeysUntilRelease = not enable,
        bForceImmediately = true,
        bNotifyUserSettings = false,
    }
    if enable then
        -- The panel and shortcut capture share the same consuming context.
        -- Treat an already-installed context as success so capture can begin
        -- without briefly exposing gameplay input.
        if input_blocker.subsystem then return true end
        local sub = get_enhanced_input_subsystem(pc)
        if not valid(sub) or not ensure_blocker_context(pc) then return false end
        local ok, err = pcall(function()
            sub:AddMappingContext(input_blocker.imc, 1000000, options)
        end)
        if not ok then
            log.warn("Mod Manager could not install its input mapping: " .. tostring(err))
            return false
        end
        input_blocker.subsystem = sub
        return true
    end

    -- Remove it from the same local player subsystem that received the mapping.
    local sub = input_blocker.subsystem
    if not sub then return true end
    if not valid(sub) or not valid(input_blocker.imc) then
        input_blocker.subsystem, input_blocker.retry_at = nil, 0
        return true
    end
    local ok, err = pcall(function()
        sub:RemoveMappingContext(input_blocker.imc, options)
    end)
    if ok then
        input_blocker.subsystem, input_blocker.retry_at = nil, 0
    else
        if input_blocker.retry_at == 0 then
            log.warn("Mod Manager could not release its input mapping: " .. tostring(err))
        end
        input_blocker.retry_at = engine.real_time_seconds() + 0.5
    end
    return ok
end

local function set_ui_input(controller, focus, enabled)
    if not enabled then set_input_mask(controller, false) end
    if not valid(controller) then return end
    local library = widget_library()
    if not library then return end
    pcall(function() controller.bShowMouseCursor = enabled == true end)
    if enabled then
        -- UI-only mode hides keyboard state from PlayerController, which meant
        -- the configured menu key could open the panel but not close it. Keep
        -- controller polling visible under a consuming Enhanced Input context.
        local masked = set_input_mask(controller, true)
        local ok = false
        if masked then
            ok = pcall(function()
                library:SetInputMode_GameAndUIEx(controller, focus, 0, false, false)
            end)
        end
        if not ok then
            -- Prefer a safe UI-only fallback over leaking movement or attacks.
            pcall(function() library:SetInputMode_UIOnlyEx(controller, focus, 0, false) end)
            if not masked then
                log.warn("Mod Manager input mask unavailable; use Escape to close this session")
            end
        end
        if valid(focus) then pcall(function() focus:SetUserFocus(controller) end) end
    else
        local ok, err = pcall(function() library:SetInputMode_GameOnly(controller, true) end)
        if not ok then log.warn("Mod Manager could not restore game input: " .. tostring(err)) end
    end
end

local function end_key_capture(controller)
    if not key_capture.active then return end
    key_capture.active = false
    set_input_mask(controller, false)
    if panel.open then set_ui_input(controller, panel.frame, true) end
end

local function close_panel(wait_for_escape)
    if not panel.open then return end
    end_key_capture(panel.pc)
    if valid(panel.frame) then pcall(function() panel.frame:SetVisibility(1) end) end
    kit.animate_fireflies(panel.hovered_module, false)
    panel.hovered_module = nil
    kit.animate_button_hover(panel.pinned_rows and panel.pinned_rows[1], false)
    kit.animate_icon_button(panel.pinned_rows and panel.pinned_rows[2], false)
    panel.open = false
    enter_enabled, enter_requested = false, false
    row_icons.cancel_scan()
    key_state.restore_when_escape_up = wait_for_escape == true
    if key_state.restore_when_escape_up then
        key_state.escape_restore_deadline = engine.real_time_seconds() + 0.35
    else
        set_ui_input(panel.pc, nil, false)
    end
    log.info("mod manager closed")
end

local function find_module(id)
    for _, module in ipairs(state.modules or {}) do
        if module.id == id then return module end
    end
    return nil
end

local function place_action_dock(inline)
    local parent = inline and panel.inline_actions or panel.footer_home
    if not valid(parent) or not valid(panel.footer) then return false end
    if parent ~= panel.footer_parent then
        -- Adding a UMG child moves it from its previous parent. Keep the
        -- existing action widgets and their click bindings when switching views.
        local ok, slot = pcall(function() return parent:AddChildToVerticalBox(panel.footer) end)
        if not ok or not valid(slot) then
            panel.footer_parent = nil
            log.warn("Could not place the module action dock.")
            if inline then return place_action_dock(false) end
            return false
        end
        if inline then pad(slot, 0, 0, 6, 8) end
        panel.footer_parent = parent
    end
    return inline
end

local function activate_module(id)
    local module = find_module(id) or (state.modules and state.modules[1])
    if not module then return false end
    if panel.active_module and panel.active_module ~= module.id then
        end_key_capture(panel.pc)
        panel.selected_row = nil
        if valid(panel.name_input) then pcall(function() panel.name_input:SetText(FText("")) end) end
    end
    panel.active_module = module.id

    state.uiPagination = panel.pagination ~= nil
    state.uiInlineActions = valid(panel.inline_actions)
    local ok, view = pcall(module.runtime.activate, state)
    if not ok or type(view) ~= "table" then
        view = {
            status = module.manifest.name .. " is unavailable.",
            detail = tostring(ok and "invalid module response" or view),
            actionIds = {},
        }
    end
    local status_text = tostring(view.status or "")
    pcall(function() panel.status:SetText(FText(status_text)) end)
    set_visible(panel.status_sizer, status_text ~= "")
    local preview_ok, shown = pcall(render_item_preview, view.preview)
    if not preview_ok then log.warn("item preview unavailable: " .. tostring(shown)) end
    local detail = preview_ok and shown and "" or tostring(view.detail or module.manifest.description or "")
    set_detail(detail)
    render_rows(view.rows, view.poolRows == true, tonumber(view.pinRows) or (view.pinFirstRow and 1 or 0))
    render_pagination(view.pagination)
    panel.icon_pending = panel.preview_icon ~= nil or panel.ingredient_icons ~= nil or (panel.icon_row_count or 0) > 0
    if not panel.icon_pending then row_icons.cancel_scan() end
    if view.compatibility then state.compatibility = view.compatibility end
    if view.liveSnapshot then state.liveSnapshot = view.liveSnapshot end

    for module_id, entry in pairs(panel.module_buttons) do
        local selected = module_id == module.id
        local listed = find_module(module_id)
        update_panel_button(entry,
            listed and listed.manifest.ui.menuLabel or tostring(module_id), selected)
        show_button_accent(entry, selected)
    end

    local actions = module.manifest.ui.actions or {}
    if type(view.actionIds) == "table" then
        local by_id, visible = {}, {}
        for _, action in ipairs(actions) do by_id[action.id] = action end
        for _, id in ipairs(view.actionIds) do
            if by_id[id] then visible[#visible + 1] = by_id[id] end
        end
        actions = visible
    end
    panel.active_actions = actions
    if valid(panel.action_sizer) then
        local row_height = theme.spacing.row + 4
        local action_height = math.max(row_height, math.min(3 * row_height, math.ceil(#actions / 2) * row_height + 2))
        pcall(function() panel.action_sizer:SetHeightOverride(action_height) end)
        set_visible(panel.action_sizer, #actions > 0)
    end
    local has_runner = type(module.runtime.run_action) == "function"
    local needs_input, first_hint = false, nil
    for _, action in ipairs(actions) do
        if action.requiresInput == true and action.disabled ~= true then
            needs_input = true
            first_hint = first_hint or action.inputHint
        end
    end
    panel.needs_input = needs_input
    panel.focus_input = needs_input and view.focusInput == true
    enter_enabled, enter_requested = panel.open and needs_input, false
    set_visible(panel.input_sizer or panel.name_input, needs_input)
    set_visible(panel.input_gap, needs_input)
    place_action_dock(view.inlineActions == true and not needs_input and #actions > 0)
    set_visible(panel.footer, needs_input or #actions > 0)
    if needs_input then
        pcall(function() panel.name_input:SetHintText(FText(tostring(first_hint or "Value"))) end)
        if view.inputValue ~= nil then
            pcall(function() panel.name_input:SetText(FText(tostring(view.inputValue))) end)
        end
        if panel.focus_input and panel.open then
            pcall(function() panel.name_input:SetKeyboardFocus() end)
        end
    end
    for index, entry in ipairs(panel.action_buttons) do
        local action = actions[index]
        local available = has_runner and type(action) == "table"
        set_visible(entry.holder or entry.widget, available)
        local enabled = available and action.disabled ~= true
        if available then
            kit.style_action(entry, enabled, action.primary == true)
            local label = type(view.actionLabels) == "table" and view.actionLabels[action.id]
            update_panel_button(entry, tostring(label or action.label or "RUN"), false)
        end
    end
    for row_index, pair in ipairs(panel.action_row_boxes or {}) do
        local first_idx = (row_index - 1) * 2 + 1
        local row_visible = has_runner and (type(actions[first_idx]) == "table" or type(actions[first_idx + 1]) == "table")
        set_visible(pair, row_visible)
    end
    if valid(panel.action_scroll) then
        pcall(function() panel.action_scroll:ScrollToStart() end)
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
    hud_input_owner = nil
    activate_module(panel.active_module)
    local focus = panel.focus_input and valid(panel.name_input) and panel.name_input or panel.frame
    set_ui_input(controller, focus, true)
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
    local library = widget_library()
    if not valid(controller) or not library or not set_input_mask(controller, true) then
        set_detail("Key capture unavailable. Type a shortcut such as SHIFT+F1.")
        return
    end
    -- UI-only mode does not send presses to PlayerController. Capture with
    -- the gameplay input mask in place and keep focus off the editable field.
    local input_ok = pcall(function()
        library:SetInputMode_GameAndUIEx(controller, panel.frame, 0, false, false)
        panel.frame:SetUserFocus(controller)
    end)
    if not input_ok then
        set_input_mask(controller, false)
        set_ui_input(controller, panel.frame, true)
        set_detail("Key capture unavailable. Type a shortcut such as SHIFT+F1.")
        return
    end
    key_capture.active = true
    key_capture.module_id = module.id
    key_capture.action_id = action.id
    key_capture.prefix = tostring(options.prefix or "")
    key_capture.deadline = engine.real_time_seconds() + math.max(1, tonumber(options.seconds) or 3)
    key_capture.down = {}
    if controller then
        for _, key in ipairs(CAPTURE_BASES) do
            key_capture.down[key.canonical] = input_key_down(controller, key.unreal)
        end
    end
    set_detail("Press a shortcut within 3 seconds. Esc closes the menu.")
end

local function run_module_action(action_index)
    if not panel.open then return end
    end_key_capture(panel.pc)
    local module = find_module(panel.active_module)
    local actions = panel.active_actions
    local action = actions and actions[action_index] or nil
    if not module or type(module.runtime.run_action) ~= "function" or not action or action.disabled == true then return end
    local input = panel.needs_input and input_text(panel.name_input) or ""
    local call_ok, ok, message, options = pcall(module.runtime.run_action, state, action.id, input)
    if not call_ok then ok, message, options = false, ok, nil end
    if ok then
        -- Actions which do not change their list can retain the exact current
        -- row widgets, highlight and scroll offset. This is useful for repeat
        -- actions such as spawning more of the selected item.
        if not (type(options) == "table" and options.preserveView == true) then
            activate_module(module.id)
        end
        if type(message) == "string" and message ~= "" then
            set_detail(message)
            log.info(message)
        end
        if type(options) == "table" and type(options.captureHotkey) == "table" then
            begin_key_capture(module, action, options.captureHotkey)
        end
        if not (type(options) == "table" and options.preserveInput == true) then
            pcall(function() panel.name_input:SetText(FText("")) end)
        end
    else
        set_detail("Action stopped: " .. tostring(message))
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
        set_detail(message)
        log.info(message)
    else
        set_detail("Rename stopped: " .. tostring(message))
        log.warn("rename stopped: " .. tostring(message))
    end
end

local function reload_mods()
    local now = os.clock()
    local prev_at = rawget(_G, "__RLM_UI_LAST_RELOAD_AT") or -999
    if (now - prev_at) < 1.0 then
        return state and state.modules or nil, "Reload already ran."
    end
    _G.__RLM_UI_LAST_RELOAD_AT = now

    local was_open = panel.open == true
    local previous_module = panel.active_module
    local saved_state = state
    end_key_capture(panel.pc)
    log.info("refreshing manifests, UI scripts and module runtimes in process")

    for _, name in ipairs({
        "rlm_glass", "rlm_ui_kit", "rlm_ui_theme", "rlm_row_icons",
    }) do
        package.loaded[name] = nil
    end

    local ok, module_list, reload_error = pcall(modules.reload, saved_state.paths)
    if not ok then module_list, reload_error = nil, module_list end
    if not module_list then
        local message = "Module refresh stopped: " .. tostring(reload_error or "unknown error")
        show_global_notification(message)
        log.warn(message)
        return nil, message
    end
    saved_state.modules = module_list

    M.stop()
    package.loaded.rlm_ui = nil
    local ok_ui, fresh_ui = pcall(require, "rlm_ui")
    if ok_ui and type(fresh_ui) == "table" and type(fresh_ui.start) == "function" then
        package.loaded.rlm_ui = fresh_ui
        fresh_ui.start(saved_state)
    else
        package.loaded.rlm_ui = M
        M.start(saved_state)
        fresh_ui = M
    end

    if was_open and previous_module and type(fresh_ui.open_module) == "function" then
        pcall(fresh_ui.open_module, previous_module)
    elseif was_open and type(fresh_ui.open_module) == "function" and module_list[1] then
        pcall(fresh_ui.open_module, module_list[1].id)
    end

    for _, module in ipairs(module_list) do
        local callback = type(module.runtime) == "table" and module.runtime.on_host_reload
        if type(callback) == "function" then
            local callback_ok, accepted, callback_error = pcall(callback, saved_state)
            if not callback_ok or accepted == false then
                log.warn(("%s post-reload callback stopped: %s"):format(
                    tostring(module.id), tostring(callback_ok and callback_error or accepted)))
            end
        end
    end

    local message = ("Reloaded %d module(s) & UI safely"):format(#module_list)
    if type(fresh_ui.report_status) == "function" then
        pcall(fresh_ui.report_status, "ok", message, true)
    else
        log.info(message)
    end
    return module_list
end

function M.reload_modules()
    if not started or not state or not state.paths then return nil, "Mod Manager is not ready." end
    if menu.pending or key_capture.active then return nil, "Mod Manager is handling another input." end
    if transaction.current() then return nil, "Wait for the active equipment change to finish." end
    return reload_mods()
end

local function enqueue_click(item)
    menu.queue = menu.queue or {}
    local last = menu.queue[#menu.queue]
    if last and last.source_name and last.source_name == item.source_name then return end
    menu.queue[#menu.queue + 1] = item
end

local function route_click(name)
    if not started then return end
    if name == menu.button_name then enqueue_click({ kind = "open", source_name = name })
    elseif name == menu.close_name then enqueue_click({ kind = "close", source_name = name })
    elseif name == menu.reload_name then enqueue_click({ kind = "reload-mods", source_name = name })
    elseif menu.action_names[name] then
        enqueue_click({ kind = "module-action", action = menu.action_names[name], source_name = name })
    elseif menu.row_names[name] then
        local row = menu.row_names[name]
        local entry = row.entry
        if entry and entry.icon_widget then entry.spin_frame = 0 end
        enqueue_click({ kind = "select-row", row = row, source_name = name })
    elseif menu.module_names[name] then
        enqueue_click({ kind = "show-module", module = menu.module_names[name], source_name = name })
    end
end

local function hook_clicks()
    local driver = rawget(_G, "__RLM_UI_CLICK_DRIVER")
    if type(driver) ~= "table" then
        driver = {}
        rawset(_G, "__RLM_UI_CLICK_DRIVER", driver)
    end
    driver.on_click = route_click
    if click_hooked and driver.hook_reg == RegisterHook then return end
    click_hooked = true
    if driver.hook_reg == RegisterHook then return end
    local ok = pcall(RegisterHook, "/Script/CommonUI.CommonButtonBase:HandleButtonClicked", function(self)
        local ok_name, name = pcall(function() return self:get():GetFullName() end)
        if ok_name then
            local active = rawget(_G, "__RLM_UI_CLICK_DRIVER")
            if active and type(active.on_click) == "function" then active.on_click(name) end
        end
    end)
    if ok then driver.hook_reg = RegisterHook
    else log.warn("button-click hook unavailable; use F7") end
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
        if not started then return end
        key_state.escape_requested = true
    end)
    if ok then escape_hooked = true
    else log.warn("native Esc binding failed; controller polling remains active") end
end

local function hook_enter()
    if enter_hooked or type(RegisterKeyBind) ~= "function" then return end
    local ok, key = pcall(function() return Key.RETURN end)
    if not ok or not key then
        log.warn("native Return binding unavailable; controller polling remains active")
        return
    end
    local registered, result = pcall(RegisterKeyBind, key, function()
        -- The focused Slate field consumes Return before PlayerController
        -- sees it. Only latch a flag here. Dispatch on the game thread.
        if not started then return end
        if enter_enabled then enter_requested = true end
    end)
    enter_hooked = registered and result ~= false
    if not enter_hooked then log.warn("native Return binding failed; controller polling remains active") end
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

local function process_pending_menu()
    if not menu.pending and menu.queue and #menu.queue > 0 then
        local item = table.remove(menu.queue, 1)
        menu.pending = item.kind
        menu.pending_action = item.action
        menu.pending_row = item.row
        menu.pending_module = item.module
    end
    if not menu.pending then return false end
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
        end_key_capture(panel.pc)
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
                return true
            end
        end
        local previous = panel.selected_row
        panel.selected_row = type(value) == "table" and value.value or value
        if type(value) == "table" then
            for _, row in pairs(menu.row_names) do
                local selected = row.value == panel.selected_row
                if selected or row.value == previous then
                    update_panel_button(row.entry, row.title, selected)
                    show_button_accent(row.entry, selected)
                end
            end
        end
        local input_value = type(value) == "table" and value.input or value
        if type(value) == "table" and value.detail then
            set_detail(value.detail)
        end
        if panel.needs_input and valid(panel.name_input) then
            pcall(function() panel.name_input:SetText(FText(tostring(input_value or ""))) end)
            pcall(function() panel.name_input:SetKeyboardFocus() end)
        end
    end
    return true
end

local function menu_tick()
    if process_pending_menu() then return end
    ensure_menu_button()
    poll_menu_selection()
end

local function engine_key(name)
    local upper = tostring(name or ""):upper()
    if upper:match("^F%d%d?$") or upper:match("^%u$") then return upper end
    local map = { HOME = "Home", END = "End", PAGE_UP = "PageUp", PAGE_DOWN = "PageDown",
        INS = "Insert", INSERT = "Insert", DEL = "Delete", DELETE = "Delete", SPACE = "SpaceBar" }
    return map[upper]
end

local function poll_keys()
    local submit_enter = enter_requested
    enter_requested = false
    if not panel.open and not key_capture.active and not key_state.restore_when_escape_up
        and input_blocker.subsystem and engine.real_time_seconds() >= input_blocker.retry_at then
        set_input_mask(nil, false)
    end
    local controller = local_controller()
    if not controller then return end
    if key_capture.active then
        if input_key_down(controller, "Escape", true) then
            close_panel(input_key_down(controller, "Escape"))
            return
        end
        if engine.real_time_seconds() >= key_capture.deadline then
            end_key_capture(controller)
            set_detail("No key detected; binding unchanged.")
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
                end_key_capture(controller)
                if module and type(module.runtime.run_action) == "function" then
                    local call_ok, ok, message = pcall(
                        module.runtime.run_action, state, action_id, prefix .. " " .. chord)
                    if not call_ok then ok, message = false, ok end
                    if ok then
                        activate_module(module.id)
                        if valid(panel.name_input) then
                            pcall(function() panel.name_input:SetText(FText(prefix)) end)
                        end
                        set_detail(message)
                        log.info(message)
                    else
                        set_detail("Action stopped: " .. tostring(message))
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
        if key_state.restore_when_escape_up
            and (escape ~= true or engine.real_time_seconds() >= key_state.escape_restore_deadline) then
            key_state.restore_when_escape_up = false
            set_ui_input(controller, nil, false)
        end
    else
        key_state.escape_down = false
    end
    if panel.open and panel.needs_input and not menu.pending then
        if not enter_hooked then
            local down = input_key_down(controller, { "Enter", "NumPadEnter" }, true)
            submit_enter, key_state.enter_down = down and not key_state.enter_down, down
        end
        if submit_enter then
            local module = find_module(panel.active_module)
            if panel.selected_row and module and type(module.runtime.rename_selection) == "function" then
                rename_selected_row()
            else
                local submit_id = "search"
                if module and type(module.runtime.enter_action) == "function" then
                    local submit_ok, requested = pcall(module.runtime.enter_action, state, input_text(panel.name_input))
                    submit_id = submit_ok and requested or nil
                end
                for index, action in ipairs(panel.active_actions or {}) do
                    if submit_id and action.id == submit_id and action.requiresInput == true and action.disabled ~= true then
                        run_module_action(index)
                        break
                    end
                end
            end
        end
    else
        key_state.enter_down = false
    end
end

local function main_tick()
    if not started then return end
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

local function paint_control_feedback()
    local back = panel.pinned_rows and panel.pinned_rows[1]
    if back and back.bound_value then kit.animate_button_hover(back, true) end
    local refresh = panel.pinned_rows and panel.pinned_rows[2]
    if refresh and refresh.bound_value then kit.animate_icon_button(refresh, true) end
    local previous = panel.hovered_module
    local hovered
    if previous and kit.is_hovered(previous.widget) then
        hovered = previous
    else
        for _, entry in pairs(panel.module_buttons) do
            if entry.fireflies and kit.is_hovered(entry.widget) then
                hovered = entry
                break
            end
        end
    end
    if previous ~= hovered then
        kit.animate_fireflies(previous, false)
        panel.hovered_module = hovered
    end
    kit.animate_fireflies(hovered, true)
end

local function input_and_images_tick()
    if not started then return end
    pcall(poll_keys)
    if menu.pending or (menu.queue and #menu.queue > 0) then
        local click_ok, click_error = pcall(process_pending_menu)
        if not click_ok then log.warn("UI click failed: " .. tostring(click_error)) end
    end
    if not panel.open then return end
    pcall(paint_control_feedback)
    if not panel.icon_pending then return end
    local icon_ok, icon_error = pcall(paint_row_icons)
    if not icon_ok then
        panel.icon_pending = false
        row_icons.cancel_scan()
        log.warn("row images stopped: " .. tostring(icon_error))
    end
end

function M.start(bootstrap_state)
    if started then return true, "already started" end
    state = bootstrap_state
    state.uiThemeName = theme.name
    local themed, theme_error = refresh_theme(state.paths)
    if not themed then log.warn("UI theme kept: " .. tostring(theme_error)) end
    state.uiActionViews = true
    state.uiPooledHeadings = true
    started = true
    pcall(NotifyOnNewObject, "/Script/Dominion.PauseMenuScreen", function(object)
        if not started then return end
        pause_seen[#pause_seen + 1] = object
    end)
    -- A UE4SS hot reload keeps the game's existing pause-menu UObject alive.
    -- NotifyOnNewObject therefore cannot see it again; arm the guarded
    -- FindFirstOf fallback so the MOD MANAGER entry is restored after reload.
    pause_look_at = os.clock() + 0.25
    hook_clicks()
    hook_escape()
    hook_enter()

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

    local loop_ok, main_h = pcall(LoopInGameThreadWithDelay, 250, main_tick)
    if not loop_ok then return false, "this UE4SS build has no safe game-thread UI loop" end
    main_loop_handle = main_h
    local fast_ok, fast_h = pcall(LoopInGameThreadWithDelay, 33, input_and_images_tick)
    if fast_ok then
        fast_loop_handle = fast_h
    else
        log.warn("shortcut polling unavailable; use the pause-menu entry")
    end
    local key = tostring(state.config.MenuKey or "none")
    log.info("UI shell ready: Esc > MOD MANAGER" .. (key:lower() ~= "none" and (", or press " .. key) or ""))
    return true, "UI shell ready"
end

-- The minimap borrows the manager's consuming input context while the HUD
-- cursor is visible. Opening the manager transfers ownership of that context.
function M.begin_hud_input(controller, focus)
    if panel.open or key_state.restore_when_escape_up or hud_input_owner or not valid(controller) then return false end
    local owner = engine.call(controller, "GetAddress") or engine.full_name(controller)
    local library = widget_library()
    if owner == "" or not library or not set_input_mask(controller, true) then return false end
    local ok = pcall(function()
        library:SetInputMode_GameAndUIEx(controller, focus, 0, false, false)
        controller.bShowMouseCursor = true
    end)
    if not ok then set_ui_input(controller, nil, false); return false end
    hud_input_owner = owner
    return true
end

function M.end_hud_input(controller, preserve_input)
    if not hud_input_owner then return end
    local owner = engine.call(controller, "GetAddress") or engine.full_name(controller)
    local same_controller = owner == hud_input_owner
    hud_input_owner = nil
    if not same_controller then
        input_blocker.subsystem, input_blocker.retry_at = nil, 0
    elseif preserve_input then
        set_input_mask(controller, false)
    else
        set_ui_input(controller, nil, false)
    end
end

function M.open_module(id)
    if not started then return false end
    local module = find_module(id)
    if not module then
        pcall(reload_mods)
        module = find_module(id)
        if not module then return false end
    end
    if type(module.runtime.open_settings) == "function" then module.runtime.open_settings() end
    if panel.open then return activate_module(id) end
    panel.active_module = id
    open_panel()
    return panel.open
end

function M.close()
    close_panel(false)
end

function M.is_open()
    return panel.open == true
end

function M.report_status(kind, message, background)
    if panel.open then
        if background then
            show_global_notification(message)
        else
            set_detail(message)
        end
    end
    if kind == "incomplete" then log.warn(message) else log.info(message) end
end

function M.stop()
    started = false
    if type(CancelDelayedAction) == "function" then
        if main_loop_handle then pcall(CancelDelayedAction, main_loop_handle) end
        if fast_loop_handle then pcall(CancelDelayedAction, fast_loop_handle) end
    end
    main_loop_handle, fast_loop_handle = nil, nil
    enter_enabled, enter_requested = false, false
    row_icons.cancel_scan()
    if hud_input_owner then M.end_hud_input(local_controller()) end
    if panel.open or key_state.restore_when_escape_up then
        panel.open = false
        key_state.restore_when_escape_up = false
        set_ui_input(panel.pc, nil, false)
    else
        set_input_mask(nil, false)
    end
    if valid(panel.frame) then pcall(function() panel.frame:RemoveFromParent() end) end
    if valid(menu.button) then pcall(function() menu.button:RemoveFromParent() end) end
    panel.frame, panel.pc, panel.status, panel.detail = nil, nil, nil, nil
    panel.status_sizer, panel.notification, panel.notification_until = nil, nil, 0
    panel.rows_box, panel.rows_scroll, panel.action_scroll, panel.action_row_boxes, panel.action_sizer, panel.compact_box = nil, nil, nil, nil, nil, nil
    panel.pinned_rows = nil
    panel.pagination, panel.hovered_module = nil, nil
    panel.footer, panel.content_width, panel.input_sizer, panel.input_gap = nil, nil, nil, nil
    panel.inline_actions, panel.footer_home, panel.footer_parent = nil, nil, nil
    panel.preview_tiles, panel.preview_headings, panel.compact_rows = nil, nil, nil
    panel.preview_box, panel.item_preview, panel.preview_icon, panel.ingredient_icons = nil, nil, nil, nil
    panel.active_actions, panel.needs_input = nil, nil
    panel.selected_row = nil
    menu.button, menu.pause = nil, nil
    pause_seen, pause_known, pause_look_at = {}, nil, 0
    key_state.escape_requested = false
    key_capture.active = false
    escape_hooked = false
    local click_driver = rawget(_G, "__RLM_UI_CLICK_DRIVER")
    if type(click_driver) == "table" and click_driver.on_click == route_click then
        click_driver.on_click = nil
    end
    menu.queue, menu.pending = {}, nil
    started = false
    return true
end

return M


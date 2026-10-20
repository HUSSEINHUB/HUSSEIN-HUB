--[[
╔══════════════════════════════════════════════════╗
║ HUSSEIN HUB v14.7 (Fixed)                        ║
║ • Hitbox بقائمة (تشغيل، حجم، لون)      ║
╚══════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local p = Players.LocalPlayer
local U = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local VU = game:GetService("VirtualUser")
local g = "HusseinHub_v14.7"
local PG = p:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────────────────
-- SECTION 1 · GLOBAL STATE & CLEANUP
-- ─────────────────────────────────────────────────────

if getgenv().HusseinHubRunning then
    warn("⚠️ HusseinHub يعمل بالفعل")
    return
end
getgenv().HusseinHubRunning = true
getgenv().HusseinHub = getgenv().HusseinHub or {}
local HUB = getgenv().HusseinHub
HUB.state = {} -- ✅ يتصفّر كل تشغيل
HUB.conns = {}
HUB.instances = {}
HUB.espConns = {}
HUB.espData = {}
HUB.lighting = nil
HUB.originalWS = nil
HUB.originalJP = nil
HUB.uiVisible = true
HUB.afkLast = 0

getgenv().SavedPositions = getgenv().SavedPositions or {}

local function NewInst(class, parent)
    local i = Instance.new(class)
    if parent then i.Parent = parent end
    if class == "ScreenGui" then
        table.insert(HUB.instances, i)
    end
    return i
end

local function TrackConn(c)
    table.insert(HUB.conns, c)
    return c
end

local function Connect(signal, cb)
    return TrackConn(signal:Connect(cb))
end

local function SafeCall(fn, label)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        warn(("❌ [%s] %s"):format(tostring(label or "?"), tostring(err)))
    end
    return ok, err
end

local function destroyESPObjects()
    for plr, d in pairs(HUB.espData) do
        pcall(function() if d.highlight then d.highlight:Destroy() end end)
        pcall(function() if d.billboard then d.billboard:Destroy() end end)
        HUB.espData[plr] = nil
    end
end

local function CleanupAll()
    warn("🧹 تنظيف HusseinHub...")
    for _, c in ipairs(HUB.conns) do
        pcall(function() c:Disconnect() end)
    end
    HUB.conns = {}
    for _, c in ipairs(HUB.espConns) do
        pcall(function() c:Disconnect() end)
    end
    HUB.espConns = {}

    destroyESPObjects() -- ✅ يحذف Highlight/Billboard من الشخصيات

    -- ✅ إرجاع الكاميرا إذا كنت تراقب أحد
    pcall(function()
        local cam = workspace.CurrentCamera
        local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
        if cam and hum then cam.CameraSubject = hum end
    end)

    for _, i in ipairs(HUB.instances) do
        pcall(function()
            if i and i.Parent then i:Destroy() end
        end)
    end
    HUB.instances = {}

    local char = p.Character
    if char then
        local h = char:FindFirstChildOfClass("Humanoid")
        if h then
            if HUB.originalWS then h.WalkSpeed = HUB.originalWS end
            if HUB.originalJP then h.JumpPower = HUB.originalJP end
        end
    end
    if HUB.lighting then
        pcall(function()
            for k, v in pairs(HUB.lighting) do
                game.Lighting[k] = v
            end
        end)
    end

    if HUB.restoreNoclip then pcall(HUB.restoreNoclip) end
    if HUB.restoreHitbox then pcall(HUB.restoreHitbox) end
    if HUB.restoreAntiLag then task.spawn(HUB.restoreAntiLag) end
    pcall(function()
        local cam = workspace.CurrentCamera
        if HUB.fovOn and cam and HUB.originalFOV then
            cam.FieldOfView = HUB.originalFOV
        end
    end)
    HUB.fovOn = false
    HUB.fullbright = false

    HUB.state = {} -- ✅ يمسح الحالة
    HUB.infJumpConn, HUB.afkIdleConn, HUB.afkLoopConn, HUB.espGui = nil, nil, nil, nil
    HUB.noclipConn, HUB.ctpConns, HUB.visualConn, HUB.hitboxConn = nil, nil, nil, nil
    getgenv().HusseinHubRunning = false
    print("✅ تم التنظيف")
end
getgenv().HusseinHubCleanup = CleanupAll

-- ─────────────────────────────────────────────────────
-- SECTION 2 · CORE
-- ─────────────────────────────────────────────────────

local function GetHRP()
    local char = p.Character or p.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

-- ─────────────────────────────────────────────────────
-- SECTION 3 · TOAST SYSTEM
-- ─────────────────────────────────────────────────────

local ToastGui = NewInst("ScreenGui", PG)
ToastGui.Name = g.."_Toasts"
ToastGui.ResetOnSpawn = false
ToastGui.DisplayOrder = 9999
ToastGui.IgnoreGuiInset = true

local isMobile = U.TouchEnabled and not U.MouseEnabled
local TOAST_W, TOAST_H, GAP = 260, 46, 8
local MARGIN_X = isMobile and 12 or 20
local MARGIN_Y = isMobile and 90 or 24

local ToastHolder = NewInst("Frame", ToastGui)
ToastHolder.BackgroundTransparency = 1
ToastHolder.AnchorPoint = Vector2.new(1, 1)
ToastHolder.Position = UDim2.new(1, -MARGIN_X, 1, -MARGIN_Y)
ToastHolder.Size = UDim2.new(0, TOAST_W, 0, 500)

local activeToasts = {}

local function relayoutToasts()
    for i, t in ipairs(activeToasts) do
        local target = UDim2.new(0, 0, 1, -((i-1) * (TOAST_H + GAP)) - TOAST_H)
        TS:Create(t.frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = target}):Play()
    end
end

local KIND = {
    success = {bar = Color3.fromRGB(80,220,120), bg = Color3.fromRGB(28,38,30)},
    error = {bar = Color3.fromRGB(240,80,80), bg = Color3.fromRGB(40,28,28)},
    warn = {bar = Color3.fromRGB(240,180,60), bg = Color3.fromRGB(40,36,26)},
    info = {bar = Color3.fromRGB(80,160,240), bg = Color3.fromRGB(26,32,40)},
}

local function inferKind(text)
    text = tostring(text)
    if text:find("⚠️") or text:find("بالفعل") or text:find("متوقف") then return "warn" end
    if text:find("❌") or text:find("رفض") or text:find("غير مسموح") then return "error" end
    if text:find("⏳") or text:find("👋") or text:find("🚀") then return "info" end
    return "success"
end

local function ShowToast(text, duration, kind)
    kind = kind or inferKind(text)
    duration = duration or 2
    local k = KIND[kind] or KIND.info

    local frame = NewInst("Frame", ToastHolder)
    frame.AnchorPoint = Vector2.new(0, 1)
    frame.Size = UDim2.new(0, TOAST_W, 0, TOAST_H)
    frame.Position = UDim2.new(1, TOAST_W + 40, 1, 0)
    frame.BackgroundColor3 = k.bg
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    NewInst("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local stroke = NewInst("UIStroke", frame)
    stroke.Color = k.bar
    stroke.Transparency = 0.5
    stroke.Thickness = 1

    local bar = NewInst("Frame", frame)
    bar.Size = UDim2.new(0, 4, 1, -10)
    bar.Position = UDim2.new(0, 5, 0, 5)
    bar.BackgroundColor3 = k.bar
    bar.BorderSizePixel = 0
    NewInst("UICorner", bar).CornerRadius = UDim.new(0, 2)

    local lbl = NewInst("TextLabel", frame)
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 16, 0, 4)
    lbl.Size = UDim2.new(1, -22, 1, -8)
    lbl.Text = tostring(text)
    lbl.TextColor3 = Color3.fromRGB(240,240,240)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 13
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Center

    local cons = NewInst("UITextSizeConstraint", lbl)
    cons.MinTextSize = 10
    cons.MaxTextSize = 14

    local entry = {frame = frame, kind = kind}
    table.insert(activeToasts, 1, entry)
    while #activeToasts > 4 do
        local rem = table.remove(activeToasts)
        if rem and rem.frame then
            pcall(function() rem.frame:Destroy() end)
        end
    end
    relayoutToasts()

    task.spawn(function()
        task.wait(duration)
        if frame and frame.Parent then
            TS:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.new(1, TOAST_W + 40, frame.Position.Y.Scale, frame.Position.Y.Offset),
                BackgroundTransparency = 1,
            }):Play()
            task.wait(0.22)
            for i, v in ipairs(activeToasts) do
                if v == entry then
                    table.remove(activeToasts, i)
                    break
                end
            end
            pcall(function() frame:Destroy() end)
            relayoutToasts()
        end
    end)
end

-- ─────────────────────────────────────────────────────
-- SECTION 3.5 · SAVE/LOAD POSITIONS
-- ─────────────────────────────────────────────────────

-- الأماكن محفوظة لكل لعبة (PlaceId) داخل getgenv
local function placeList()
    local all = getgenv().SavedPositions
    if type(all) ~= "table" then
        all = {}
        getgenv().SavedPositions = all
    end
    all[game.PlaceId] = all[game.PlaceId] or {}
    return all[game.PlaceId]
end

-- ─────────────────────────────────────────────────────
-- SECTION 4 · DRAG HELPER + MAIN UI
-- ─────────────────────────────────────────────────────

-- ✅ الاتصالات تنفصل عند حذف الواجهة، ويرجع دالة تقول هل كان سحب (لتجنب الضغط بالغلط)
local function MakeDraggable(obj, handle)
    handle = handle or obj
    local dragging, moved = false, false
    local dragStart, startPos
    local mine = {}
    local function add(c) table.insert(mine, TrackConn(c)) end

    add(handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = i.Position
            startPos = obj.Position
        end
    end))
    add(U.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            if d.Magnitude > 6 then moved = true end
            obj.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    add(U.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    obj.Destroying:Connect(function()
        for _, c in ipairs(mine) do pcall(function() c:Disconnect() end) end
    end)

    return function() return moved end
end

HUB.lighting = {
    ClockTime = game.Lighting.ClockTime,
    Brightness = game.Lighting.Brightness,
    Ambient = game.Lighting.Ambient,
    OutdoorAmbient = game.Lighting.OutdoorAmbient,
    FogEnd = game.Lighting.FogEnd,
    FogColor = game.Lighting.FogColor,
    GlobalShadows = game.Lighting.GlobalShadows,
}

local S = NewInst("ScreenGui", PG)
S.Name = g
S.ResetOnSpawn = false
S.DisplayOrder = 100

local TB = NewInst("TextButton", S)
TB.BackgroundColor3 = Color3.fromRGB(30,30,30)
TB.Position = UDim2.new(0.02, 0, 0.4, 0)
TB.Size = UDim2.new(0, 55, 0, 55)
TB.Text = "H"
TB.TextColor3 = Color3.fromRGB(255,255,0)
TB.TextSize = 28
TB.Font = Enum.Font.GothamBold
NewInst("UICorner", TB).CornerRadius = UDim.new(0, 28)
NewInst("UIStroke", TB).Color = Color3.fromRGB(255,255,0)

local F = NewInst("Frame", S)
F.BackgroundColor3 = Color3.fromRGB(20,20,20)
F.Position = UDim2.new(0.5, -180, 0.5, -130)
F.Size = UDim2.new(0, 360, 0, 260)
F.Visible = false
F.ClipsDescendants = true
NewInst("UICorner", F).CornerRadius = UDim.new(0, 12)
NewInst("UIStroke", F).Color = Color3.fromRGB(50,50,50)

local FConstr = NewInst("UISizeConstraint", F)
FConstr.MinSize = Vector2.new(280, 220)
FConstr.MaxSize = Vector2.new(520, 380)

local T = NewInst("Frame", F)
T.BackgroundColor3 = Color3.fromRGB(35,35,35)
T.Size = UDim2.new(1, 0, 0, 40)
NewInst("UICorner", T).CornerRadius = UDim.new(0, 12)

local L = NewInst("TextLabel", T)
L.BackgroundTransparency = 1
L.Position = UDim2.new(0, 15, 0, 0)
L.Size = UDim2.new(0, 220, 1, 0)
L.Font = Enum.Font.GothamBold
L.TextColor3 = Color3.fromRGB(255,255,0)
L.TextSize = 16
L.Text = "HUSSEIN HUB v14.7 ⭐"
L.TextXAlignment = Enum.TextXAlignment.Left

local function CloseUI()
    F.Visible = false
    HUB.uiVisible = false
end

local C = NewInst("TextButton", T)
C.BackgroundTransparency = 1
C.Position = UDim2.new(1, -40, 0, 0)
C.Size = UDim2.new(0, 40, 1, 0)
C.Text = "X"
C.TextColor3 = Color3.fromRGB(255,80,80)
C.TextSize = 20
C.Font = Enum.Font.GothamBold
Connect(C.MouseButton1Click, CloseUI)

local Pages = NewInst("Frame", F)
Pages.BackgroundTransparency = 1
Pages.Position = UDim2.new(0, 85, 0, 45)
Pages.Size = UDim2.new(1, -90, 1, -50)
Pages.ClipsDescendants = true

local function CreatePage()
    local Page = NewInst("ScrollingFrame", Pages)
    Page.Size = UDim2.new(1, 0, 1, 0)
    Page.BackgroundTransparency = 1
    Page.Visible = false
    Page.ScrollBarThickness = 5
    Page.ScrollingDirection = Enum.ScrollingDirection.Y
    Page.AutomaticCanvasSize = Enum.AutomaticSize.Y -- ✅ بدون CanvasSize يدوي مكرر
    Page.CanvasSize = UDim2.new(0, 0, 0, 0)
    Page.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
    Page.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"

    local Grid = NewInst("UIGridLayout", Page)
    Grid.CellPadding = UDim2.new(0, 5, 0, 5)
    Grid.CellSize = UDim2.new(0.47, 0, 0, 38)
    Grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
    Grid.VerticalAlignment = Enum.VerticalAlignment.Top
    Grid.SortOrder = Enum.SortOrder.LayoutOrder

    return Page
end

local TabContainer = NewInst("Frame", F)
TabContainer.BackgroundTransparency = 1
TabContainer.Position = UDim2.new(0, 5, 0, 45)
TabContainer.Size = UDim2.new(0, 75, 1, -50)
NewInst("UIListLayout", TabContainer).Padding = UDim.new(0, 5)

local function CreateTab(name, page)
    local b = NewInst("TextButton", TabContainer)
    b.Size = UDim2.new(1, 0, 0, 35)
    b.BackgroundColor3 = Color3.fromRGB(40,40,40)
    b.Text = name
    b.Font = Enum.Font.Gotham
    b.TextColor3 = Color3.fromRGB(200,200,200)
    b.TextSize = 12
    NewInst("UICorner", b).CornerRadius = UDim.new(0, 6)

    Connect(b.MouseButton1Click, function()
        for _, pg in pairs(Pages:GetChildren()) do
            if pg:IsA("ScrollingFrame") or pg:IsA("Frame") then
                pg.Visible = false
            end
        end
        for _, t in pairs(TabContainer:GetChildren()) do
            if t:IsA("TextButton") then
                t.BackgroundColor3 = Color3.fromRGB(40,40,40)
                t.TextColor3 = Color3.fromRGB(200,200,200)
            end
        end
        page.Visible = true
        b.BackgroundColor3 = Color3.fromRGB(255,255,0)
        b.TextColor3 = Color3.fromRGB(0,0,0)
    end)

    return b
end

-- ─────────────────────────────────────────────────────
-- SECTION 5 · REMOTE LOADERS
-- ─────────────────────────────────────────────────────

-- ✅ فحص الدومين بالضبط (مو find) 
local ALLOWED_HOSTS = {
    ["raw.githubusercontent.com"] = true,
    ["gist.githubusercontent.com"] = true,
    ["pastebin.com"] = true,
    ["rawscripts.net"] = true,
    ["pastefy.app"] = true,
    ["hellohellohell0.com"] = true,
    ["api.luarmor.net"] = true,
    ["encrypt-x.pages.dev"] = true,
}

local function isUrlAllowed(url)
    if type(url) ~= "string" then return false end
    local host = url:match("^https://([^/%?#:@]+)")
    return host ~= nil and ALLOWED_HOSTS[host:lower()] == true
end

local function RunRemote(url, arg, label)
    if not isUrlAllowed(url) then
        ShowToast("❌ رابط غير مسموح", 2, "error")
        warn("❌ "..label.." رُفض: "..tostring(url))
        return
    end
    ShowToast("⏳ جاري التحميل...", 1, "info")
    task.wait()
    local ok = SafeCall(function()
        local src = game:HttpGet(url)
        local fn, err = loadstring(src)
        if not fn then error("loadstring: "..tostring(err), 0) end
        fn(arg)
    end, label..url)
    if ok then
        ShowToast("✅ تم التحميل", 1, "success")
    else
        ShowToast("❌ فشل التحميل", 2, "error") -- ✅ ما يطلع نجاح إذا فشل
    end
end

local function Load(url) RunRemote(url, nil, "Load:") end
local function LoadWithArg(url, arg) RunRemote(url, arg, "LoadWithArg:") end

-- ─────────────────────────────────────────────────────
-- SECTION 6 · CHARACTER STATE + SPEED / JUMP
-- ─────────────────────────────────────────────────────

local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

HUB.fovOn = false
HUB.fullbright = false
HUB.noclipOriginal = {}
HUB.noclipConn, HUB.ctpConns, HUB.visualConn, HUB.antiLag = nil, nil, nil, nil
HUB.hitboxConn = nil
HUB.hitboxOriginal = setmetatable({}, {__mode = "k"})
HUB.hitboxCfg = {size = 15, vec = Vector3.new(15, 15, 15), color = Color3.fromRGB(255, 0, 0)}
HUB.originalFOV = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView

local stats = {
    WalkSpeed = {enabled = false, value = 16, default = 16, max = 1e15, orig = "originalWS", title = "Speed", y = 0.15},
    JumpPower = {enabled = false, value = 50, default = 50, max = 1000, orig = "originalJP", title = "Jump Power", y = 0.4},
}

local function applyStats()
    local char = p.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    for prop, s in pairs(stats) do
        if s.enabled then
            if prop == "JumpPower" then hum.UseJumpPower = true end
            hum[prop] = s.value
        end
    end
end

local function applyCharacterState(char)
    local h = char:WaitForChild("Humanoid", 5)
    if not h then return end
    HUB.originalWS = HUB.originalWS or h.WalkSpeed
    HUB.originalJP = HUB.originalJP or h.JumpPower
    task.wait(0.2)
    applyStats()
end

Connect(p.CharacterAdded, applyCharacterState)
if p.Character then
    task.spawn(applyCharacterState, p.Character)
end

-- واجهة موحّدة للسرعة وقوة القفز
local function OpenStatUI(prop)
    local s = stats[prop]
    local guiName = g.."_"..prop.."UI"
    local existing = PG:FindFirstChild(guiName)
    if existing then
        existing:Destroy()
        return
    end

    local ui = NewInst("ScreenGui", PG)
    ui.Name = guiName
    ui.ResetOnSpawn = false
    ui.DisplayOrder = 102

    local frame = NewInst("Frame", ui)
    frame.Size = UDim2.new(0, 200, 0, 115)
    frame.Position = UDim2.new(0.5, -100, s.y, 0)
    frame.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    frame.Active = true
    MakeDraggable(frame)
    NewInst("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local stroke = NewInst("UIStroke", frame)
    stroke.Color = Color3.fromRGB(0, 255, 255)
    stroke.Thickness = 4

    local title = NewInst("TextLabel", frame)
    title.Size = UDim2.new(1, -80, 0, 22)
    title.Position = UDim2.new(0, 6, 0, 4)
    title.BackgroundTransparency = 1
    title.Text = s.title
    title.TextColor3 = Color3.fromRGB(0, 255, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left

    local min = NewInst("TextButton", frame)
    min.Size = UDim2.new(0, 25, 0, 20)
    min.Position = UDim2.new(1, -65, 0, 6)
    min.Text = "-"
    min.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    NewInst("UICorner", min).CornerRadius = UDim.new(0, 4)

    local close = NewInst("TextButton", frame)
    close.Size = UDim2.new(0, 25, 0, 20)
    close.Position = UDim2.new(1, -32, 0, 6)
    close.Text = "X"
    close.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
    NewInst("UICorner", close).CornerRadius = UDim.new(0, 4)

    local box = NewInst("TextBox", frame)
    box.Size = UDim2.new(1, -10, 0, 25)
    box.Position = UDim2.new(0, 5, 0, 35)
    box.Text = tostring(s.value)
    box.ClearTextOnFocus = false
    NewInst("UICorner", box).CornerRadius = UDim.new(0, 4)

    local toggle = NewInst("TextButton", frame)
    toggle.Size = UDim2.new(1, -10, 0, 30)
    toggle.Position = UDim2.new(0, 5, 0, 70)
    toggle.Text = s.enabled and "ON" or "OFF"
    toggle.BackgroundColor3 = s.enabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(170, 0, 0)
    NewInst("UICorner", toggle).CornerRadius = UDim.new(0, 4)

    local small = false

    Connect(box.FocusLost, function()
        local v = tonumber(box.Text)
        if not v or v < 0 then v = s.value end
        s.value = math.min(v, s.max)
        box.Text = tostring(s.value)
        applyStats()
    end)

    Connect(toggle.MouseButton1Click, function()
        s.enabled = not s.enabled
        if s.enabled then
            toggle.Text = "ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        else
            toggle.Text = "OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
            local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum[prop] = HUB[s.orig] or s.default
            end
        end
        applyStats()
    end)

    Connect(min.MouseButton1Click, function()
        small = not small
        box.Visible = not small
        toggle.Visible = not small
        frame.Size = small and UDim2.new(0, 200, 0, 30) or UDim2.new(0, 200, 0, 115)
    end)

    Connect(close.MouseButton1Click, function()
        ui:Destroy()
    end)
end

-- ─────────────────────────────────────────────────────
-- SECTION 7 · SAVED PLACES MANAGER (أسماء + قائمة)
-- ─────────────────────────────────────────────────────

local MAX_SAVES = 30

local function findSave(saves, name)
    for _, e in ipairs(saves) do
        if e.name == name then return e end
    end
end

local function OpenSaveMenu()
    local existing = PG:FindFirstChild(g.."_SaveLoad")
    if existing then
        existing:Destroy()
        return
    end

    local gui = NewInst("ScreenGui", PG)
    gui.Name = g.."_SaveLoad"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 101

    local fullHeight, miniHeight = 300, 38

    local frame = NewInst("Frame", gui)
    frame.Size = UDim2.new(0, 240, 0, fullHeight)
    frame.Position = UDim2.new(0.5, -120, 0.5, -150)
    frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    NewInst("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local stroke = NewInst("UIStroke", frame)
    stroke.Color = Color3.fromRGB(255,255,0)
    stroke.Thickness = 1.2
    stroke.Transparency = 0.2

    MakeDraggable(frame)

    local titleBar = NewInst("Frame", frame)
    titleBar.Size = UDim2.new(1, 0, 0, 32)
    titleBar.BackgroundTransparency = 1

    local title = NewInst("TextLabel", titleBar)
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "📍 الأماكن المحفوظة"
    title.Font = Enum.Font.GothamBold
    title.TextColor3 = Color3.fromRGB(255,255,0)
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Center

    local function headBtn(txt, x, color)
        local b = NewInst("TextButton", titleBar)
        b.Size = UDim2.new(0, 24, 0, 24)
        b.Position = UDim2.new(1, x, 0, 4)
        b.Text = txt
        b.BackgroundColor3 = Color3.fromRGB(60,60,60)
        b.TextColor3 = color
        b.Font = Enum.Font.GothamBold
        b.TextSize = 14
        NewInst("UICorner", b).CornerRadius = UDim.new(0, 4)
        return b
    end
    local minBtn = headBtn("—", -54, Color3.fromRGB(255,255,255))
    local closeBtn = headBtn("✕", -27, Color3.fromRGB(255,80,80))

    local body = NewInst("Frame", frame)
    body.Size = UDim2.new(1, 0, 1, -38)
    body.Position = UDim2.new(0, 0, 0, 38)
    body.BackgroundTransparency = 1
    body.ClipsDescendants = true

    local nameBox = NewInst("TextBox", body)
    nameBox.Size = UDim2.new(1, -96, 0, 30)
    nameBox.Position = UDim2.new(0, 8, 0, 2)
    nameBox.BackgroundColor3 = Color3.fromRGB(45,45,45)
    nameBox.PlaceholderText = "اسم المكان"
    nameBox.PlaceholderColor3 = Color3.fromRGB(140,140,140)
    nameBox.Text = ""
    nameBox.TextColor3 = Color3.fromRGB(255,255,255)
    nameBox.Font = Enum.Font.GothamMedium
    nameBox.TextSize = 12
    nameBox.ClearTextOnFocus = false
    NewInst("UICorner", nameBox).CornerRadius = UDim.new(0, 7)

    local addBtn = NewInst("TextButton", body)
    addBtn.Size = UDim2.new(0, 78, 0, 30)
    addBtn.Position = UDim2.new(1, -86, 0, 2)
    addBtn.BackgroundColor3 = Color3.fromRGB(255,255,0)
    addBtn.Text = "💾 حفظ هنا"
    addBtn.TextColor3 = Color3.fromRGB(0,0,0)
    addBtn.Font = Enum.Font.GothamBold
    addBtn.TextSize = 12
    NewInst("UICorner", addBtn).CornerRadius = UDim.new(0, 7)

    local list = NewInst("ScrollingFrame", body)
    list.Size = UDim2.new(1, -12, 1, -42)
    list.Position = UDim2.new(0, 6, 0, 38)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 3
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    NewInst("UIListLayout", list).Padding = UDim.new(0, 4)

    local refresh
    refresh = function()
        for _, c in ipairs(list:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end
        local saves = placeList()
        if #saves == 0 then
            local empty = NewInst("TextLabel", list)
            empty.Size = UDim2.new(1, 0, 0, 40)
            empty.BackgroundTransparency = 1
            empty.Text = "ما في أماكن محفوظة بهذي اللعبة"
            empty.TextColor3 = Color3.fromRGB(150,150,150)
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 12
            empty.TextWrapped = true
            return
        end
        for i, entry in ipairs(saves) do
            local row = NewInst("Frame", list)
            row.Size = UDim2.new(1, -6, 0, 32)
            row.BackgroundTransparency = 1
            row.LayoutOrder = i

            local go = NewInst("TextButton", row)
            go.Size = UDim2.new(1, -36, 1, 0)
            go.BackgroundColor3 = Color3.fromRGB(45,45,45)
            go.Text = "🚀 "..entry.name
            go.TextColor3 = Color3.fromRGB(255,255,255)
            go.Font = Enum.Font.GothamBold
            go.TextSize = 12
            go.TextTruncate = Enum.TextTruncate.AtEnd
            NewInst("UICorner", go).CornerRadius = UDim.new(0, 7)

            local del = NewInst("TextButton", row)
            del.Size = UDim2.new(0, 30, 1, 0)
            del.Position = UDim2.new(1, -30, 0, 0)
            del.BackgroundColor3 = Color3.fromRGB(70,35,35)
            del.Text = "🗑"
            del.TextSize = 14
            NewInst("UICorner", del).CornerRadius = UDim.new(0, 7)

            go.MouseButton1Click:Connect(function()
                GetHRP().CFrame = entry.cf
                ShowToast("✅ انتقلت إلى "..entry.name, 1, "success")
            end)
            del.MouseButton1Click:Connect(function()
                for j, e in ipairs(saves) do
                    if e == entry then
                        table.remove(saves, j)
                        break
                    end
                end
                ShowToast("🗑 تم حذف "..entry.name, 1, "warn")
                refresh()
            end)
        end
    end

    addBtn.MouseButton1Click:Connect(function()
        local saves = placeList()
        local name = nameBox.Text:match("^%s*(.-)%s*$")
        if name == "" then
            local n = #saves + 1
            while findSave(saves, "مكان "..n) do n += 1 end
            name = "مكان "..n
        end
        local len = utf8.len(name)
        if len and len > 20 then
            name = name:sub(1, utf8.offset(name, 21) - 1)
        end

        local hrp = GetHRP()
        local old = findSave(saves, name)
        if old then
            old.cf = hrp.CFrame
            nameBox.Text = ""
            ShowToast("✅ تم تحديث "..name, 1, "success")
            return
        end
        if #saves >= MAX_SAVES then
            ShowToast("⚠️ وصلت الحد الأقصى ("..MAX_SAVES..")", 1.5, "warn")
            return
        end
        table.insert(saves, {name = name, cf = hrp.CFrame})
        nameBox.Text = ""
        ShowToast("✅ تم حفظ "..name, 1, "success")
        refresh()
    end)

    local isMinimized = false
    Connect(minBtn.MouseButton1Click, function()
        isMinimized = not isMinimized
        body.Visible = not isMinimized
        frame.Size = UDim2.new(0, 240, 0, isMinimized and miniHeight or fullHeight)
        minBtn.Text = isMinimized and "□" or "—"
        title.Text = isMinimized and "📍 الأماكن (مصغّر)" or "📍 الأماكن المحفوظة"
    end)
    Connect(closeBtn.MouseButton1Click, function()
        gui:Destroy()
    end)

    refresh()
end

-- ─────────────────────────────────────────────────────
-- SECTION 7.5 · NOCLIP / CLICK TP / SERVER / VISUAL
-- ─────────────────────────────────────────────────────

-- NoClip: نخزّن بس الأجزاء اللي كانت تصادم فعلاً ونرجّعها عند الإطفاء
local function restoreNoclip()
    for part in pairs(HUB.noclipOriginal) do
        if part.Parent then part.CanCollide = true end
    end
    HUB.noclipOriginal = {}
end
HUB.restoreNoclip = restoreNoclip

local function SetNoClip(on)
    if on then
        if HUB.noclipConn then return end
        HUB.noclipConn = Connect(RS.Stepped, function()
            local char = p.Character
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    HUB.noclipOriginal[part] = true
                    part.CanCollide = false
                end
            end
        end)
    else
        if HUB.noclipConn then
            pcall(function() HUB.noclipConn:Disconnect() end)
            HUB.noclipConn = nil
        end
        restoreNoclip()
    end
end

-- Click TP: نقرة (أو لمسة) قصيرة على العالم تنقلك لمكانها
local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function SetClickTP(on)
    if HUB.ctpConns then
        for _, c in ipairs(HUB.ctpConns) do pcall(function() c:Disconnect() end) end
        HUB.ctpConns = nil
    end
    if not on then return end

    local startPos
    HUB.ctpConns = {
        Connect(U.InputBegan, function(input, gpe)
            if gpe or not isPointer(input) then return end
            startPos = input.Position
        end),
        Connect(U.InputEnded, function(input)
            if not startPos or not isPointer(input) then return end
            local moved = (input.Position - startPos).Magnitude
            startPos = nil
            if moved > 10 then return end -- سحب كاميرا مو نقرة

            local cam = workspace.CurrentCamera
            local char = p.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not (cam and hrp) then return end

            local ray = cam:ScreenPointToRay(input.Position.X, input.Position.Y)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {char}
            local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
            if hit then
                local rot = hrp.CFrame - hrp.CFrame.Position
                hrp.CFrame = CFrame.new(hit.Position + Vector3.new(0, 3, 0)) * rot
            end
        end),
    }
end

-- Rejoin / Server Hop
Connect(TeleportService.TeleportInitFailed, function(plr, _, msg)
    if plr == p then
        ShowToast("❌ فشل الانتقال: "..tostring(msg), 3, "error")
    end
end)

local function Rejoin()
    ShowToast("⏳ جاري إعادة الدخول...", 2, "info")
    local ok, err = pcall(function()
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, p)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, p)
        end
    end)
    if not ok then
        ShowToast("❌ فشلت إعادة الدخول", 2, "error")
        warn(err)
    end
end

local function ServerHop()
    ShowToast("⏳ جاري البحث عن سيرفر...", 2, "info")
    task.spawn(function()
        local ok, result = pcall(function()
            local url = "https://games.roblox.com/v1/games/"..tostring(game.PlaceId)
                .."/servers/Public?sortOrder=Asc&limit=100"
            return HttpService:JSONDecode(game:HttpGet(url))
        end)
        if not ok or type(result) ~= "table" or type(result.data) ~= "table" then
            ShowToast("❌ فشل جلب السيرفرات", 2, "error")
            return
        end

        local candidates = {}
        for _, sv in ipairs(result.data) do
            if sv.id ~= game.JobId and sv.playing and sv.maxPlayers
                and sv.playing < sv.maxPlayers - 1 then
                table.insert(candidates, sv.id)
            end
        end
        if #candidates == 0 then
            ShowToast("❌ ما لقيت سيرفر مناسب", 2, "error")
            return
        end

        ShowToast("🚀 انتقال لسيرفر جديد...", 2, "info")
        local pick = candidates[math.random(#candidates)]
        local ok2, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, pick, p)
        end)
        if not ok2 then
            ShowToast("❌ فشل الانتقال", 2, "error")
            warn(err)
        end
    end)
end

-- FOV + Fullbright
local function applyFullbright()
    local LT = game.Lighting
    LT.Brightness = 2
    LT.ClockTime = 14
    LT.FogEnd = 1e9
    LT.GlobalShadows = false
    LT.Ambient = Color3.fromRGB(178,178,178)
    LT.OutdoorAmbient = Color3.fromRGB(178,178,178)
end

local function restoreLighting()
    for k, v in pairs(HUB.lighting) do
        game.Lighting[k] = v
    end
end

-- يثبّت FOV والإضاءة لو اللعبة حاولت تغيّرها (الحلقة تشتغل بس وقت التفعيل)
local function visualStep()
    if HUB.fovOn then
        local cam = workspace.CurrentCamera
        if cam and cam.FieldOfView ~= HUB.fov then
            cam.FieldOfView = HUB.fov
        end
    end
    if HUB.fullbright then
        applyFullbright()
    end
end

local function refreshVisualLoop()
    local need = HUB.fovOn or HUB.fullbright
    if need and not HUB.visualConn then
        HUB.visualConn = Connect(RS.RenderStepped, visualStep)
    elseif not need and HUB.visualConn then
        pcall(function() HUB.visualConn:Disconnect() end)
        HUB.visualConn = nil
    end
end

local function OpenVisualUI()
    local guiName = g.."_VisualUI"
    local existing = PG:FindFirstChild(guiName)
    if existing then
        existing:Destroy()
        return
    end

    local ui = NewInst("ScreenGui", PG)
    ui.Name = guiName
    ui.ResetOnSpawn = false
    ui.DisplayOrder = 103

    local frame = NewInst("Frame", ui)
    frame.Size = UDim2.new(0, 230, 0, 130)
    frame.Position = UDim2.new(0.5, -115, 0.3, 0)
    frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
    frame.BorderSizePixel = 0
    frame.Active = true
    NewInst("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local stroke = NewInst("UIStroke", frame)
    stroke.Color = Color3.fromRGB(255,255,0)
    stroke.Thickness = 1.2
    stroke.Transparency = 0.2
    MakeDraggable(frame)

    local title = NewInst("TextLabel", frame)
    title.Size = UDim2.new(1, -40, 0, 30)
    title.Position = UDim2.new(0, 10, 0, 2)
    title.BackgroundTransparency = 1
    title.Text = "🔆 FOV / إضاءة"
    title.Font = Enum.Font.GothamBold
    title.TextColor3 = Color3.fromRGB(255,255,0)
    title.TextSize = 13

    local close = NewInst("TextButton", frame)
    close.Size = UDim2.new(0, 24, 0, 24)
    close.Position = UDim2.new(1, -30, 0, 5)
    close.Text = "✕"
    close.BackgroundColor3 = Color3.fromRGB(60,60,60)
    close.TextColor3 = Color3.fromRGB(255,80,80)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 14
    NewInst("UICorner", close).CornerRadius = UDim.new(0, 4)
    Connect(close.MouseButton1Click, function() ui:Destroy() end)

    local fovLabel = NewInst("TextLabel", frame)
    fovLabel.Size = UDim2.new(1, -20, 0, 18)
    fovLabel.Position = UDim2.new(0, 10, 0, 34)
    fovLabel.BackgroundTransparency = 1
    fovLabel.TextColor3 = Color3.fromRGB(255,255,255)
    fovLabel.Font = Enum.Font.GothamMedium
    fovLabel.TextSize = 12
    fovLabel.TextXAlignment = Enum.TextXAlignment.Left

    -- زر شفاف أكبر من الشريط عشان اللمس يكون سهل ولا يسحب النافذة
    local slider = NewInst("TextButton", frame)
    slider.Size = UDim2.new(1, -20, 0, 24)
    slider.Position = UDim2.new(0, 10, 0, 56)
    slider.BackgroundTransparency = 1
    slider.AutoButtonColor = false
    slider.Text = ""

    local bar = NewInst("Frame", slider)
    bar.Size = UDim2.new(1, 0, 0, 6)
    bar.Position = UDim2.new(0, 0, 0.5, -3)
    bar.BackgroundColor3 = Color3.fromRGB(60,60,60)
    bar.BorderSizePixel = 0
    NewInst("UICorner", bar).CornerRadius = UDim.new(0, 3)

    local fill = NewInst("Frame", bar)
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255,255,0)
    fill.BorderSizePixel = 0
    NewInst("UICorner", fill).CornerRadius = UDim.new(0, 3)

    local knob = NewInst("Frame", bar)
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    NewInst("UICorner", knob).CornerRadius = UDim.new(0, 7)

    local FOV_MIN, FOV_MAX = 30, 120
    local function showFov(v)
        local f = math.clamp((v - FOV_MIN) / (FOV_MAX - FOV_MIN), 0, 1)
        fill.Size = UDim2.new(f, 0, 1, 0)
        knob.Position = UDim2.new(f, 0, 0.5, 0)
        fovLabel.Text = "FOV: "..v
    end

    local cam = workspace.CurrentCamera
    showFov(HUB.fovOn and HUB.fov or math.floor((cam and cam.FieldOfView or 70) + 0.5))

    local function setFromX(x)
        local f = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local v = math.floor(FOV_MIN + f * (FOV_MAX - FOV_MIN) + 0.5)
        HUB.fov = v
        HUB.fovOn = true
        refreshVisualLoop()
        local c = workspace.CurrentCamera
        if c then c.FieldOfView = v end
        showFov(v)
    end

    local sliding = false
    local sliderConns = {
        slider.InputBegan:Connect(function(i)
            if isPointer(i) then
                sliding = true
                setFromX(i.Position.X)
            end
        end),
        U.InputChanged:Connect(function(i)
            if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement
                or i.UserInputType == Enum.UserInputType.Touch) then
                setFromX(i.Position.X)
            end
        end),
        U.InputEnded:Connect(function(i)
            if isPointer(i) then sliding = false end
        end),
    }
    ui.Destroying:Connect(function()
        for _, c in ipairs(sliderConns) do pcall(function() c:Disconnect() end) end
    end)

    local resetBtn = NewInst("TextButton", frame)
    resetBtn.Size = UDim2.new(0.5, -15, 0, 28)
    resetBtn.Position = UDim2.new(0, 10, 0, 92)
    resetBtn.BackgroundColor3 = Color3.fromRGB(60,60,60)
    resetBtn.Text = "↺ إعادة FOV"
    resetBtn.TextColor3 = Color3.fromRGB(255,255,255)
    resetBtn.Font = Enum.Font.GothamBold
    resetBtn.TextSize = 11
    NewInst("UICorner", resetBtn).CornerRadius = UDim.new(0, 7)

    local fbBtn = NewInst("TextButton", frame)
    fbBtn.Size = UDim2.new(0.5, -15, 0, 28)
    fbBtn.Position = UDim2.new(0.5, 5, 0, 92)
    fbBtn.Text = ""
    fbBtn.TextColor3 = Color3.fromRGB(255,255,255)
    fbBtn.Font = Enum.Font.GothamBold
    fbBtn.TextSize = 11
    NewInst("UICorner", fbBtn).CornerRadius = UDim.new(0, 7)

    local function showFb()
        fbBtn.Text = HUB.fullbright and "Fullbright: ON" or "Fullbright: OFF"
        fbBtn.BackgroundColor3 = HUB.fullbright and Color3.fromRGB(0,150,0) or Color3.fromRGB(60,60,60)
    end
    showFb()

    Connect(resetBtn.MouseButton1Click, function()
        HUB.fovOn = false
        refreshVisualLoop()
        local c = workspace.CurrentCamera
        if c and HUB.originalFOV then
            c.FieldOfView = HUB.originalFOV
            showFov(math.floor(HUB.originalFOV + 0.5))
        end
    end)

    Connect(fbBtn.MouseButton1Click, function()
        HUB.fullbright = not HUB.fullbright
        if HUB.fullbright then
            applyFullbright()
        else
            restoreLighting()
        end
        refreshVisualLoop()
        showFb()
    end)
end

-- ─────────────────────────────────────────────────────
-- SECTION 8 · FEATURES
-- ─────────────────────────────────────────────────────

local function Remote(name, url)
    return {Name = name, Function = function() Load(url) end}
end

local function inCharacter(v)
    local m = v:FindFirstAncestorOfClass("Model")
    return m ~= nil and m:FindFirstChildOfClass("Humanoid") ~= nil
end

-- الغاء لاق: يحفظ القيم الأصلية عشان الضغط الثاني يرجّعها
local function restoreAntiLag()
    local saved = HUB.antiLag
    if not saved then return end
    HUB.antiLag = nil
    while saved.busy do task.wait() end -- لو التطبيق لسه شغال، ننتظره يوقف
    pcall(function()
        settings().Rendering.QualityLevel = saved.quality
        game.Lighting.GlobalShadows = saved.shadows
        game.Lighting.FogEnd = saved.fogEnd
    end)
    local n = 0
    for inst, props in pairs(saved.items) do
        if inst.Parent then
            for prop, value in pairs(props) do
                pcall(function() inst[prop] = value end)
            end
        end
        n += 1
        if n % 500 == 0 then task.wait() end
    end
end
HUB.restoreAntiLag = restoreAntiLag

local function applyAntiLag()
    if HUB.antiLag then restoreAntiLag() end -- بداية نظيفة
    local saved = {items = {}, busy = true}
    HUB.antiLag = saved
    local ok, err = pcall(function()
        saved.quality = settings().Rendering.QualityLevel
        saved.shadows = game.Lighting.GlobalShadows
        saved.fogEnd = game.Lighting.FogEnd
        settings().Rendering.QualityLevel = 1
        game.Lighting.GlobalShadows = false
        game.Lighting.FogEnd = 1e9

        local n = 0
        for _, v in ipairs(workspace:GetDescendants()) do
            n += 1
            if n % 500 == 0 then
                task.wait() -- ✅ ما يجمّد اللعبة
                if HUB.antiLag ~= saved then break end -- انضغط تراجع وسط التنفيذ
            end
            if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Fire") or v:IsA("Smoke") then
                saved.items[v] = {Enabled = v.Enabled}
                v.Enabled = false
            elseif not inCharacter(v) then -- ✅ ما يلمس الشخصيات
                if v:IsA("BasePart") then
                    saved.items[v] = {Material = v.Material, Reflectance = v.Reflectance}
                    v.Material = Enum.Material.SmoothPlastic
                    v.Reflectance = 0
                elseif v:IsA("Decal") or v:IsA("Texture") then
                    saved.items[v] = {Transparency = v.Transparency}
                    v.Transparency = 1
                end
            end
        end
    end)
    saved.busy = false
    if not ok then warn("❌ [AntiLag] "..tostring(err)) end
end

-- Hitbox: توسيع HumanoidRootPart للاعبين الثانيين (تشغيل/إيقاف بدون إعدادات)
local HITBOX_COLORS = {
    Color3.fromRGB(255, 0, 0),
    Color3.fromRGB(255, 140, 0),
    Color3.fromRGB(255, 230, 0),
    Color3.fromRGB(0, 220, 70),
    Color3.fromRGB(0, 140, 255),
    Color3.fromRGB(170, 70, 255),
}

local function restoreHitbox()
    for hrp, orig in pairs(HUB.hitboxOriginal) do
        if hrp.Parent then
            pcall(function()
                hrp.Size = orig.Size
                hrp.Transparency = orig.Transparency
                hrp.Color = orig.Color
                hrp.CanCollide = orig.CanCollide
            end)
        end
    end
    HUB.hitboxOriginal = setmetatable({}, {__mode = "k"})
end
HUB.restoreHitbox = restoreHitbox

local function SetHitbox(on)
    if on then
        if HUB.hitboxConn then return end
        HUB.hitboxConn = Connect(RS.RenderStepped, function()
            local cfg = HUB.hitboxCfg
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= p then
                    local char = plr.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if hrp and (hrp.Size ~= cfg.vec or hrp.Color ~= cfg.color) then
                        if not HUB.hitboxOriginal[hrp] then
                            HUB.hitboxOriginal[hrp] = {
                                Size = hrp.Size,
                                Transparency = hrp.Transparency,
                                Color = hrp.Color,
                                CanCollide = hrp.CanCollide,
                            }
                        end
                        hrp.Size = cfg.vec
                        hrp.Color = cfg.color
                        hrp.Transparency = 0.5
                        hrp.CanCollide = false
                    end
                end
            end
        end)
    else
        if HUB.hitboxConn then
            pcall(function() HUB.hitboxConn:Disconnect() end)
            HUB.hitboxConn = nil
        end
        restoreHitbox()
    end
end

-- شريط سحب عام (يشتغل بالماوس واللمس)
local function MakeSlider(owner, parent, position, size, minV, maxV, value, onChange)
    local slider = NewInst("TextButton", parent)
    slider.Size = size
    slider.Position = position
    slider.BackgroundTransparency = 1
    slider.AutoButtonColor = false
    slider.Text = ""

    local bar = NewInst("Frame", slider)
    bar.Size = UDim2.new(1, 0, 0, 6)
    bar.Position = UDim2.new(0, 0, 0.5, -3)
    bar.BackgroundColor3 = Color3.fromRGB(60,60,60)
    bar.BorderSizePixel = 0
    NewInst("UICorner", bar).CornerRadius = UDim.new(0, 3)

    local fill = NewInst("Frame", bar)
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255,255,0)
    fill.BorderSizePixel = 0
    NewInst("UICorner", fill).CornerRadius = UDim.new(0, 3)

    local knob = NewInst("Frame", bar)
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    NewInst("UICorner", knob).CornerRadius = UDim.new(0, 7)

    local function show(v)
        local f = math.clamp((v - minV) / (maxV - minV), 0, 1)
        fill.Size = UDim2.new(f, 0, 1, 0)
        knob.Position = UDim2.new(f, 0, 0.5, 0)
    end
    show(value)

    local function setFromX(x)
        local f = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local v = math.floor(minV + f * (maxV - minV) + 0.5)
        show(v)
        onChange(v)
    end

    local sliding = false
    local conns = {
        slider.InputBegan:Connect(function(i)
            if isPointer(i) then
                sliding = true
                setFromX(i.Position.X)
            end
        end),
        U.InputChanged:Connect(function(i)
            if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement
                or i.UserInputType == Enum.UserInputType.Touch) then
                setFromX(i.Position.X)
            end
        end),
        U.InputEnded:Connect(function(i)
            if isPointer(i) then sliding = false end
        end),
    }
    owner.Destroying:Connect(function()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    end)

    return slider
end

local function OpenHitboxUI()
    local guiName = g.."_HitboxUI"
    local existing = PG:FindFirstChild(guiName)
    if existing then
        existing:Destroy()
        return
    end

    local cfg = HUB.hitboxCfg

    local ui = NewInst("ScreenGui", PG)
    ui.Name = guiName
    ui.ResetOnSpawn = false
    ui.DisplayOrder = 104

    local frame = NewInst("Frame", ui)
    frame.Size = UDim2.new(0, 230, 0, 186)
    frame.Position = UDim2.new(0.5, -115, 0.25, 0)
    frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
    frame.BorderSizePixel = 0
    frame.Active = true
    NewInst("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local stroke = NewInst("UIStroke", frame)
    stroke.Color = Color3.fromRGB(255,255,0)
    stroke.Thickness = 1.2
    stroke.Transparency = 0.2
    MakeDraggable(frame)

    local title = NewInst("TextLabel", frame)
    title.Size = UDim2.new(1, -40, 0, 30)
    title.Position = UDim2.new(0, 10, 0, 2)
    title.BackgroundTransparency = 1
    title.Text = "🎯 Hitbox"
    title.Font = Enum.Font.GothamBold
    title.TextColor3 = Color3.fromRGB(255,255,0)
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left

    local close = NewInst("TextButton", frame)
    close.Size = UDim2.new(0, 24, 0, 24)
    close.Position = UDim2.new(1, -30, 0, 5)
    close.Text = "✕"
    close.BackgroundColor3 = Color3.fromRGB(60,60,60)
    close.TextColor3 = Color3.fromRGB(255,80,80)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 14
    NewInst("UICorner", close).CornerRadius = UDim.new(0, 4)
    Connect(close.MouseButton1Click, function() ui:Destroy() end)

    -- تشغيل / إيقاف
    local toggle = NewInst("TextButton", frame)
    toggle.Size = UDim2.new(1, -20, 0, 32)
    toggle.Position = UDim2.new(0, 10, 0, 38)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 13
    toggle.TextColor3 = Color3.fromRGB(255,255,255)
    NewInst("UICorner", toggle).CornerRadius = UDim.new(0, 7)

    local function showToggle()
        local on = HUB.hitboxConn ~= nil
        toggle.Text = on and "✅ مفعّل" or "❌ متوقف"
        toggle.BackgroundColor3 = on and Color3.fromRGB(0,150,0) or Color3.fromRGB(150,0,0)
    end
    showToggle()

    Connect(toggle.MouseButton1Click, function()
        local on = HUB.hitboxConn == nil
        SetHitbox(on)
        showToggle()
        if on then
            ShowToast("✅ Hitbox مفعّل", 0.8, "success")
        else
            ShowToast("❌ Hitbox متوقف", 0.8, "warn")
        end
    end)

    -- الحجم
    local sizeLabel = NewInst("TextLabel", frame)
    sizeLabel.Size = UDim2.new(1, -20, 0, 18)
    sizeLabel.Position = UDim2.new(0, 10, 0, 78)
    sizeLabel.BackgroundTransparency = 1
    sizeLabel.Text = "الحجم: "..cfg.size
    sizeLabel.Font = Enum.Font.GothamMedium
    sizeLabel.TextColor3 = Color3.fromRGB(255,255,255)
    sizeLabel.TextSize = 12
    sizeLabel.TextXAlignment = Enum.TextXAlignment.Left

    MakeSlider(ui, frame, UDim2.new(0, 10, 0, 96), UDim2.new(1, -20, 0, 24), 2, 50, cfg.size, function(v)
        cfg.size = v
        cfg.vec = Vector3.new(v, v, v)
        sizeLabel.Text = "الحجم: "..v
    end)

    -- اللون
    local colorLabel = NewInst("TextLabel", frame)
    colorLabel.Size = UDim2.new(1, -20, 0, 18)
    colorLabel.Position = UDim2.new(0, 10, 0, 126)
    colorLabel.BackgroundTransparency = 1
    colorLabel.Text = "اللون"
    colorLabel.Font = Enum.Font.GothamMedium
    colorLabel.TextColor3 = Color3.fromRGB(255,255,255)
    colorLabel.TextSize = 12
    colorLabel.TextXAlignment = Enum.TextXAlignment.Left

    local swatches = {}
    local function showColors()
        for _, s in ipairs(swatches) do
            s.stroke.Enabled = (s.color == cfg.color)
        end
    end

    for i, col in ipairs(HITBOX_COLORS) do
        local b = NewInst("TextButton", frame)
        b.Size = UDim2.new(0, 28, 0, 28)
        b.Position = UDim2.new(0, 11 + (i - 1) * 36, 0, 148)
        b.BackgroundColor3 = col
        b.AutoButtonColor = false
        b.Text = ""
        NewInst("UICorner", b).CornerRadius = UDim.new(0, 14)
        local st = NewInst("UIStroke", b)
        st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        st.Color = Color3.fromRGB(255,255,255)
        st.Thickness = 2
        st.Enabled = false
        table.insert(swatches, {stroke = st, color = col})
        Connect(b.MouseButton1Click, function()
            cfg.color = col
            showColors()
        end)
    end
    showColors()
end

local CF = {
    {Name="قفز لانهائي", Id="infJump", Toggle=true, Function=function()
        if HUB.state.infJump then
            HUB.infJumpConn = Connect(U.JumpRequest, function()
                local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
                if h then
                    h:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
            ShowToast("✅ قفز لانهائي مفعّل", 0.8)
        else
            if HUB.infJumpConn then
                pcall(function() HUB.infJumpConn:Disconnect() end)
                HUB.infJumpConn = nil
            end
            ShowToast("❌ قفز لانهائي متوقف", 0.8, "warn")
        end
    end},

    {Name="سرعة", Function=function()
        OpenStatUI("WalkSpeed")
    end},

    {Name="قوة القفز", Function=function()
        OpenStatUI("JumpPower")
    end},

    {Name="NoClip", Id="noclip", Toggle=true, Function=function()
        SetNoClip(HUB.state.noclip)
        if HUB.state.noclip then
            ShowToast("✅ NoClip مفعّل", 0.8, "success")
        else
            ShowToast("❌ NoClip متوقف", 0.8, "warn")
        end
    end},

    {Name="نقر انتقال", Id="clickTP", Toggle=true, Function=function()
        SetClickTP(HUB.state.clickTP)
        if HUB.state.clickTP then
            ShowToast("✅ اضغط على أي مكان للانتقال", 1.2, "success")
        else
            ShowToast("❌ نقر انتقال متوقف", 0.8, "warn")
        end
    end},

    {Name="ESP", Id="esp", Toggle=true, Function=function()

        local function cleanupESP()
            for _, c in ipairs(HUB.espConns) do
                pcall(function() c:Disconnect() end)
            end
            HUB.espConns = {}
            destroyESPObjects()
            if HUB.espGui then
                pcall(function() HUB.espGui:Destroy() end)
                HUB.espGui = nil
            end
        end

        if not HUB.state.esp then
            cleanupESP()
            ShowToast("❌ ESP متوقف", 0.8, "warn")
            return
        end

        cleanupESP()

        local ESP = NewInst("ScreenGui", PG)
        ESP.Name = "ESPGui"
        ESP.ResetOnSpawn = false
        HUB.espGui = ESP

        local TBB = NewInst("TextButton", ESP)
        TBB.Size = UDim2.new(0,45,0,45)
        TBB.Position = UDim2.new(0.85,0,0.4,0)
        TBB.Text = "👁️✅"
        TBB.BackgroundColor3 = Color3.fromRGB(30,30,30)
        TBB.TextColor3 = Color3.fromRGB(255,255,0)
        NewInst("UICorner", TBB).CornerRadius = UDim.new(0,10)
        local tbbDragged = MakeDraggable(TBB)

        local enabled = true

        local function teamColor(plr)
            if plr.Team and p.Team and plr.Team == p.Team then
                return Color3.fromRGB(80,160,255)
            end
            return Color3.fromRGB(255,60,60)
        end

        local function applyESP(plr, char)
            if plr == p or not char then return end
            local head = char:WaitForChild("Head", 5)
            if not head then return end

            local old = HUB.espData[plr]
            if old then
                pcall(function() if old.highlight then old.highlight:Destroy() end end)
                pcall(function() if old.billboard then old.billboard:Destroy() end end)
            end

            local hl = Instance.new("Highlight")
            hl.FillColor = teamColor(plr)
            hl.OutlineColor = Color3.new(1,1,1)
            hl.Enabled = enabled
            hl.Parent = char

            local bg = Instance.new("BillboardGui")
            bg.Size = UDim2.new(0, 80, 0, 18)
            bg.StudsOffset = Vector3.new(0, 2.5, 0)
            bg.AlwaysOnTop = true
            bg.Enabled = enabled
            bg.MaxDistance = 200
            bg.Parent = head

            local tl = Instance.new("TextLabel")
            tl.Size = UDim2.new(1, 0, 1, 0)
            tl.BackgroundTransparency = 1
            tl.Text = plr.Name
            tl.TextColor3 = teamColor(plr)
            tl.Font = Enum.Font.GothamBold
            tl.TextSize = 11
            tl.TextStrokeTransparency = 0.4
            tl.Parent = bg

            HUB.espData[plr] = {highlight = hl, billboard = bg, label = tl}
        end

        local function createESP(plr)
            if plr == p then return end
            if plr.Character then
                task.spawn(applyESP, plr, plr.Character)
            end
            table.insert(HUB.espConns, plr.CharacterAdded:Connect(function(c)
                applyESP(plr, c)
            end))
            -- ✅ تحديث اللون إذا تغيّر الفريق
            table.insert(HUB.espConns, plr:GetPropertyChangedSignal("Team"):Connect(function()
                local d = HUB.espData[plr]
                if d then
                    pcall(function()
                        d.highlight.FillColor = teamColor(plr)
                        d.label.TextColor3 = teamColor(plr)
                    end)
                end
            end))
        end

        table.insert(HUB.espConns, TBB.MouseButton1Click:Connect(function()
            if tbbDragged() then return end
            enabled = not enabled
            TBB.Text = enabled and "👁️✅" or "👁️❌"
            for _, d in pairs(HUB.espData) do
                pcall(function()
                    d.highlight.Enabled = enabled
                    d.billboard.Enabled = enabled
                end)
            end
            ShowToast(enabled and "✅ ESP مفعّل" or "❌ ESP متوقف", 0.8)
        end))

        table.insert(HUB.espConns, Players.PlayerAdded:Connect(createESP))
        table.insert(HUB.espConns, Players.PlayerRemoving:Connect(function(plr)
            local d = HUB.espData[plr]
            if d then
                pcall(function() d.highlight:Destroy() end)
                pcall(function() d.billboard:Destroy() end)
                HUB.espData[plr] = nil
            end
        end))

        for _, plr in ipairs(Players:GetPlayers()) do
            createESP(plr)
        end

        ShowToast("✅ ESP مفعّل", 0.8)
    end},

    Remote("طيران", "https://raw.githubusercontent.com/XNEOFF/FlyGuiV3/main/FlyGuiV3.txt"),
    Remote("طيران سيارة 🚗", "https://raw.githubusercontent.com/Sumpre/Scripts/refs/heads/main/vfly.lua"),
    Remote("المشي في الهواء", "https://raw.githubusercontent.com/GhostPlayer352/Test4/main/Float"),
    Remote("قفل الشاشة", "https://raw.githubusercontent.com/MiniNoobie/ShiftLockx/main/Shiftlock-MiniNoobie"),

    {Name="قائمة السيرفرات 🖥️", Function=function()
        LoadWithArg("https://encrypt-x.pages.dev/Scripts?Id=9434850125280", "9434850125280")
    end},

    {Name="مراقبة شخص", Function=function()
        local old = PG:FindFirstChild("SpectateGui")
        if old then
            old:Destroy()
            return
        end

        local cam = workspace.CurrentCamera
        local function resetCam()
            local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
            if h and cam then cam.CameraSubject = h end
        end

        local gui = NewInst("ScreenGui", PG)
        gui.Name = "SpectateGui"
        gui.ResetOnSpawn = false
        gui.Destroying:Connect(resetCam) -- ✅ ترجع الكاميرا عند الإغلاق

        -- ✅ سحب واحد بس (شلت btn.Draggable)
        local btn = NewInst("ImageButton", gui)
        btn.Size = UDim2.new(0,50,0,50)
        btn.Position = UDim2.new(0,10,0.5,-25)
        btn.Image = "rbxassetid://176106970"
        btn.BackgroundTransparency = 0.3
        NewInst("UICorner", btn).CornerRadius = UDim.new(0,25)
        local btnDragged = MakeDraggable(btn)

        local bar = NewInst("Frame", gui)
        bar.Position = UDim2.new(0.5,-100,1,10)
        bar.Size = UDim2.new(0,200,0,40)
        bar.BackgroundColor3 = Color3.new(0,0,0)
        bar.BackgroundTransparency = 0.2
        NewInst("UICorner", bar).CornerRadius = UDim.new(0,8)
        MakeDraggable(bar)

        local prev = NewInst("TextButton", bar)
        prev.Size = UDim2.new(0.2,0,1,0)
        prev.Text = "<"
        prev.Font = Enum.Font.GothamBold
        prev.TextSize = 30
        prev.BackgroundTransparency = 1
        prev.TextColor3 = Color3.new(1,1,1)

        local nxt = NewInst("TextButton", bar)
        nxt.Size = UDim2.new(0.2,0,1,0)
        nxt.Position = UDim2.new(0.8,0,0,0)
        nxt.Text = ">"
        nxt.Font = Enum.Font.GothamBold
        nxt.TextSize = 30
        nxt.BackgroundTransparency = 1
        nxt.TextColor3 = Color3.new(1,1,1)

        local title = NewInst("TextLabel", bar)
        title.Size = UDim2.new(0.6,0,1,0)
        title.Position = UDim2.new(0.2,0,0,0)
        title.BackgroundTransparency = 1
        title.Text = "اختر لاعب"
        title.TextColor3 = Color3.new(1,1,1)
        title.Font = Enum.Font.Gotham
        title.TextScaled = true

        local spectating = false
        local index = 1
        local plist = Players:GetPlayers()

        local function update()
            plist = Players:GetPlayers()
            if #plist == 0 then return end
            index = math.clamp(index, 1, #plist)
            local plr = plist[index]
            local hum = plr and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                cam.CameraSubject = hum
                title.Text = plr.Name
            end
        end

        Connect(btn.MouseButton1Click, function()
            if btnDragged() then return end
            spectating = not spectating
            if spectating then
                bar:TweenPosition(UDim2.new(0.5,-100,0.85,0), "Out", "Quad", 0.3, true)
                update()
            else
                bar:TweenPosition(UDim2.new(0.5,-100,1,10), "Out", "Quad", 0.3, true)
                resetCam()
            end
        end)

        Connect(prev.MouseButton1Click, function()
            plist = Players:GetPlayers()
            index = index - 1
            if index < 1 then index = #plist end
            update()
        end)

        Connect(nxt.MouseButton1Click, function()
            plist = Players:GetPlayers()
            index = index + 1
            if index > #plist then index = 1 end
            update()
        end)
    end},

    Remote("اشكال", "https://rawscripts.net/raw/Universal-Script-Zero-Gravity-28484"),
    Remote("mm2 عربي", "https://raw.githubusercontent.com/AlphaBay00/PhantomXLoader/main/Ld.lua.txt"),
    -- ✅ حذفت زر "عربي داخلة سكربتات": الرابط كان README.md مو سكربت Lua
    Remote("vr7", "https://raw.githubusercontent.com/VR7ss/OMK/refs/heads/main/VR7-ON-TOP"),
    Remote("تحول سيارة", "https://pastefy.app/UqDEIOpO/raw"),
    Remote("حرب تحت الارض", "https://raw.githubusercontent.com/Roblox-HttpSpy/Random-Silly-stuff/refs/heads/main/UW2-Panel.lua"),
    Remote("رعب fe", "https://pastebin.com/raw/C2ixw5i9"),
    Remote("رقصات 1", "https://raw.githubusercontent.com/zyrovell/Vexro-Emotes/main/vexroemotes.lua"),
    Remote("عملاق fe", "https://pastebin.com/raw/7Nv28tRE"),
    Remote("afk logs", "https://raw.githubusercontent.com/93q-f/GhostWalkScript/refs/heads/main/GhostWalkScript"),
    Remote("امبروطورية النفط", "https://raw.githubusercontent.com/gumanba/Scripts/main/OilEmpire"),
    Remote("تحريك الاشياء", "https://pastefy.app/jZBqvRS7/raw"),
    Remote("فلكس fps", "https://raw.githubusercontent.com/Joshingtonn123/JoshScript/refs/heads/main/SyrexhubSniperOrDie"),
    Remote("تخطي الدكمة", "https://pastebin.com/raw/RE1hdgBy"),
    Remote("اختراق الجدار", "https://pastefy.app/neNjjqht/raw"),
    Remote("اختفاء", "https://raw.githubusercontent.com/ymkeee/ArbizHub/refs/heads/main/Invisible.lua"),
    Remote("اشياء دور حولك", "https://raw.githubusercontent.com/Gazer-Ha/Tool-orbit/refs/heads/main/Source"),
    Remote("تسجيل تحركات", "https://gist.githubusercontent.com/maks1165/58da021266b63d8edc51ef0a3344881d/raw/546fd2b9aec33fd2db8768fa68b7950ff428c651/FlackBack%2520By%25204NTEP"),
    Remote("رقصات 2", "https://rawscripts.net/raw/Universal-Script-Emotes-Hub-216227"),
    Remote("حرب النمل", "https://raw.githubusercontent.com/ngoanthai639-hash/Ant-war-simple-hub/refs/heads/main/Ant%20war"),
    Remote("تسلق الجدار", "https://rawscripts.net/raw/Universal-Script-Wall-Walk-9153"),
    {Name="Hitbox", Function=function()
        OpenHitboxUI()
    end},
    Remote("skybox", "https://raw.githubusercontent.com/VR7ss/VR7/main/vr7ontop"),
    Remote("خبز او يموت", "https://rawscripts.net/raw/Bake-or-Die-Kill-All-Bring-Items-Esp-etc-68463"),
    Remote("تطير الناس", "https://rawscripts.net/raw/Universal-Script-THE-REAL-dropkick-177199"),
    Remote("رقصات 3", "https://raw.githubusercontent.com/7yd7/Hub/refs/heads/Branch/GUIS/Emotes.lua"),

    {Name="انتقال للاعبين", Function=function()
        if PG:FindFirstChild("TeleportGui_Tracked") then
            PG.TeleportGui_Tracked:Destroy()
            return
        end

        local gui = NewInst("ScreenGui", PG)
        gui.Name = "TeleportGui_Tracked"
        gui.ResetOnSpawn = false

        local mainFrame = NewInst("Frame", gui)
        mainFrame.Size = UDim2.new(0,210,0,260)
        mainFrame.Position = UDim2.new(0.5,-105,0.5,-130)
        mainFrame.BackgroundColor3 = Color3.fromRGB(30,30,30)
        NewInst("UICorner", mainFrame)
        MakeDraggable(mainFrame)

        local titleBar = NewInst("TextLabel", mainFrame)
        titleBar.Size = UDim2.new(1,-30,0,28)
        titleBar.BackgroundTransparency = 1
        titleBar.Text = "🚀 انتقال للاعبين"
        titleBar.Font = Enum.Font.GothamBold
        titleBar.TextColor3 = Color3.fromRGB(255,255,0)
        titleBar.TextSize = 13
        titleBar.Position = UDim2.new(0,8,0,4)

        local refreshBtn = NewInst("TextButton", mainFrame)
        refreshBtn.Size = UDim2.new(0,22,0,22)
        refreshBtn.Position = UDim2.new(1,-52,0,4)
        refreshBtn.Text = "🔄"
        refreshBtn.BackgroundTransparency = 1
        refreshBtn.TextColor3 = Color3.new(1,1,1)

        local scrollFrame = NewInst("ScrollingFrame", mainFrame)
        scrollFrame.Size = UDim2.new(1,-10,1,-40)
        scrollFrame.Position = UDim2.new(0,5,0,35)
        scrollFrame.BackgroundTransparency = 1
        scrollFrame.ScrollBarThickness = 3
        scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scrollFrame.CanvasSize = UDim2.new(0,0,0,0)
        NewInst("UIListLayout", scrollFrame).Padding = UDim.new(0,5)

        local function updatePlayerList()
            if not scrollFrame.Parent then return end -- ✅ ما نبني أزرار داخل واجهة محذوفة
            for _, child in ipairs(scrollFrame:GetChildren()) do
                if child:IsA("TextButton") then
                    child:Destroy()
                end
            end

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= p then
                    local b = NewInst("TextButton", scrollFrame)
                    b.Size = UDim2.new(1,0,0,30)
                    b.Text = plr.Name
                    b.BackgroundColor3 = Color3.fromRGB(50,50,50)
                    b.TextColor3 = Color3.new(1,1,1)
                    NewInst("UICorner", b)

                    b.MouseButton1Click:Connect(function()
                        local theirs = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                        local mine = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                        if theirs and mine then
                            mine.CFrame = theirs.CFrame
                            ShowToast("✅ انتقلت لـ "..plr.Name, 0.8)
                        else
                            ShowToast("❌ اللاعب غير موجود", 0.8, "error")
                        end
                    end)
                end
            end
        end

        refreshBtn.MouseButton1Click:Connect(updatePlayerList)
        updatePlayerList()

        -- ✅ الاتصالات تنفصل مهما انحذفت الواجهة (X، الزر الرئيسي، التنظيف)
        local tpConns = {
            Players.PlayerAdded:Connect(updatePlayerList),
            Players.PlayerRemoving:Connect(function() task.defer(updatePlayerList) end),
        }
        gui.Destroying:Connect(function()
            for _, c in ipairs(tpConns) do pcall(function() c:Disconnect() end) end
        end)

        local closeBtn = NewInst("TextButton", mainFrame)
        closeBtn.Size = UDim2.new(0,22,0,22)
        closeBtn.Position = UDim2.new(1,-26,0,4)
        closeBtn.Text = "X"
        closeBtn.BackgroundTransparency = 1
        closeBtn.TextColor3 = Color3.fromRGB(255,80,80)
        closeBtn.MouseButton1Click:Connect(function()
            gui:Destroy()
        end)
    end},

    {Name="الغاء لاق", Id="antilag", Toggle=true, Function=function()
        if HUB.state.antilag then
            ShowToast("⏳ جاري الغاء اللاق...", 0.5, "info")
            applyAntiLag()
            ShowToast("✅ تم الغاء اللاق (اضغط مرة ثانية للتراجع)", 1.5, "success")
        else
            task.spawn(restoreAntiLag)
            ShowToast("↩️ تم التراجع عن الغاء اللاق", 1.2, "warn")
        end
    end},

    {Name="نهار/ليل", Id="night", Toggle=true, Function=function()
        local LT = game.Lighting
        SafeCall(function()
            if HUB.state.night then
                HUB.fullbright = false
                refreshVisualLoop()
                LT.ClockTime = 18.5
                LT.Brightness = 2
                LT.Ambient = Color3.fromRGB(80,80,100)
                LT.OutdoorAmbient = Color3.fromRGB(60,60,80)
                LT.FogColor = Color3.fromRGB(40,40,60)
                LT.FogEnd = 500
                ShowToast("🌙 ليل خفيف", 1)
            else
                for k, v in pairs(HUB.lighting) do
                    LT[k] = v
                end
                ShowToast("☀️ تم استرجاع الإضاءة", 1)
            end
        end, "DayNight")
    end},

    {Name="حفظ مكان", Function=function()
        OpenSaveMenu()
    end},

    Remote("👻 كابوس لوري", "https://pastefy.app/GSWBSY2v/raw"),
    Remote("🌊 استأناف البحيرة", "https://raw.githubusercontent.com/gumanba/Scripts/main/DraintheLake"),
    Remote("🔪 MM2", "https://raw.githubusercontent.com/xv3gasx/Murder-Mystery-2/refs/heads/main/Release.lua"),
    Remote("🐝 السرب النهائي", "https://raw.githubusercontent.com/gumanba/Scripts/main/FinalSwarm"),
    Remote("مستشفى الوحوش 🏥", "https://raw.githubusercontent.com/gumanba/Scripts/main/AnimalHospital"),
    Remote("قيادة مطعم", "https://raw.githubusercontent.com/feasthax/loader/refs/heads/main/RunARestaraunt.lua"),
    Remote("بيانو 🎹", "https://hellohellohell0.com/talentless-raw/TALENTLESS.lua"),
    Remote("ماب كيبورد", "https://raw.githubusercontent.com/Fluxyyy333/HoshiOnTop/main/loader.lua"),

    {Name="Anti-AFK 🟢", Id="afk", Toggle=true, Function=function()
        if HUB.state.afk then
            HUB.afkIdleConn = Connect(p.Idled, function()
                pcall(function()
                    VU:CaptureController()
                    VU:ClickButton2(Vector2.new())
                end)
            end)
            HUB.afkLoopConn = Connect(RS.Heartbeat, function()
                if not HUB.state.afk then return end
                local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
                if h and (HUB.afkLast + 240 < tick()) then
                    HUB.afkLast = tick() -- ✅ قبل الانتظار، مو بعده
                    task.spawn(function()
                        h:Move(Vector3.new(0.1,0,0), false)
                        task.wait(0.1)
                        h:Move(Vector3.new(0,0,0), false)
                    end)
                end
            end)
            ShowToast("✅ Anti-AFK شغّال", 1.2)
        else
            if HUB.afkIdleConn then
                pcall(function() HUB.afkIdleConn:Disconnect() end)
                HUB.afkIdleConn = nil
            end
            if HUB.afkLoopConn then
                pcall(function() HUB.afkLoopConn:Disconnect() end)
                HUB.afkLoopConn = nil
            end
            ShowToast("❌ Anti-AFK متوقف", 1.2, "warn")
        end
    end},

    {Name="كشف الأدمن 🔍", Function=function()
        if PG:FindFirstChild("AdminGui") then
            PG.AdminGui:Destroy()
            return
        end

        local gui = NewInst("ScreenGui", PG)
        gui.Name = "AdminGui"
        gui.ResetOnSpawn = false

        local frame = NewInst("Frame", gui)
        frame.Size = UDim2.new(0,240,0,300)
        frame.Position = UDim2.new(0.5,-120,0.5,-150)
        frame.BackgroundColor3 = Color3.fromRGB(20,20,20)
        NewInst("UICorner", frame).CornerRadius = UDim.new(0,10)
        NewInst("UIStroke", frame).Color = Color3.fromRGB(255,50,50)
        MakeDraggable(frame)

        local title = NewInst("TextLabel", frame)
        title.Size = UDim2.new(1,0,0,35)
        title.BackgroundColor3 = Color3.fromRGB(180,0,0)
        title.Text = "🔍 كشف الأدمن"
        title.Font = Enum.Font.GothamBold
        title.TextColor3 = Color3.new(1,1,1)
        title.TextSize = 15
        NewInst("UICorner", title).CornerRadius = UDim.new(0,10)

        local close = NewInst("TextButton", frame)
        close.Size = UDim2.new(0,25,0,25)
        close.Position = UDim2.new(1,-28,0,5)
        close.Text = "X"
        close.BackgroundTransparency = 1
        close.TextColor3 = Color3.new(1,1,1)
        close.Font = Enum.Font.GothamBold
        close.TextSize = 14
        Connect(close.MouseButton1Click, function()
            gui:Destroy()
        end)

        local scroll = NewInst("ScrollingFrame", frame)
        scroll.Size = UDim2.new(1,-10,1,-45)
        scroll.Position = UDim2.new(0,5,0,40)
        scroll.BackgroundTransparency = 1
        scroll.ScrollBarThickness = 3
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.CanvasSize = UDim2.new(0,0,0,0)
        NewInst("UIListLayout", scroll).Padding = UDim.new(0,4)

        local function isAdmin(plr)
            local reasons = {}

            -- ✅ CreatorId يكون ID جروب في ألعاب الجروبات
            if game.CreatorType == Enum.CreatorType.User then
                if plr.UserId == game.CreatorId then
                    table.insert(reasons, "صاحب اللعبة")
                end
            else
                local ok, rank = pcall(function()
                    return plr:GetRankInGroup(game.CreatorId)
                end)
                if ok and rank >= 255 then
                    table.insert(reasons, "صاحب الجروب")
                end
            end

            -- ✅ شلت "level" و"role" (كانت تعطي false positive لأي لاعب لفله عالي)
            local ls = plr:FindFirstChild("leaderstats")
            if ls then
                for _, st in ipairs(ls:GetChildren()) do
                    if st:IsA("IntValue") and st.Name:lower():find("admin") and st.Value > 0 then
                        table.insert(reasons, "Stat: "..st.Name.." = "..st.Value)
                    end
                end
            end

            local tools = {}
            local bp = plr:FindFirstChildOfClass("Backpack")
            if bp then
                for _, t in ipairs(bp:GetChildren()) do table.insert(tools, t) end
            end
            if plr.Character then
                for _, t in ipairs(plr.Character:GetChildren()) do
                    if t:IsA("Tool") then table.insert(tools, t) end
                end
            end
            for _, t in ipairs(tools) do
                if t:IsA("Tool") then
                    local n = t.Name:lower()
                    -- ✅ كلمة كاملة بدل find (عشان "banana" و"kickboard" ما تطلع أدمن)
                    if n:find("%f[%a]ban%f[%A]") or n:find("%f[%a]kick%f[%A]")
                        or (n:find("admin") and not n:find("fake")) or n:find("cmd") then
                        table.insert(reasons, "أداة: "..t.Name)
                    end
                end
            end
            return #reasons > 0, reasons
        end

        local found = 0
        local all = Players:GetPlayers()
        for _, plr in ipairs(all) do
            local isAdm, reasons = isAdmin(plr)
            local color = isAdm and Color3.fromRGB(255,80,80) or Color3.fromRGB(50,180,50)
            local icon = isAdm and "⚠️" or "✅"
            local lbl = NewInst("TextLabel", scroll)
            lbl.Size = UDim2.new(1,0,0, isAdm and (28 + #reasons*18) or 28)
            lbl.BackgroundColor3 = isAdm and Color3.fromRGB(60,20,20) or Color3.fromRGB(20,50,20)
            lbl.Text = icon.." "..plr.Name..(isAdm and "\n "..table.concat(reasons,"\n ") or "")
            lbl.TextColor3 = color
            lbl.Font = Enum.Font.Gotham
            lbl.TextSize = 12
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextWrapped = true
            NewInst("UIPadding", lbl).PaddingLeft = UDim.new(0,6)
            NewInst("UICorner", lbl).CornerRadius = UDim.new(0,5)
            if isAdm then found += 1 end
        end
        title.Text = "🔍 أدمن: "..found.." / "..#all
    end},

    Remote("ماب الصواريخ 🚀", "https://raw.githubusercontent.com/gumanba/Scripts/main/MergeaNuke"),
    Remote("ماب الليمون 🍋", "https://raw.githubusercontent.com/yhmani76-ux/SoYo/refs/heads/main/SoYo%20sell%20lemon.lua"),
    Remote("ماب المزرعة 2 🌾", "https://api.luarmor.net/files/v4/loaders/359e97f8618e9008afe5f496184ebb7c.lua"),
    Remote("سرقة من الاغنياء", "https://raw.githubusercontent.com/gumanba/Scripts/main/StealFromTheRich"),

    {Name="إعادة دخول 🔄", Function=Rejoin},
    {Name="سيرفر جديد 🌐", Function=ServerHop},
    {Name="FOV / إضاءة 🔆", Function=function()
        OpenVisualUI()
    end},

    {Name="🧹 تنظيف الكل", Function=function()
        CleanupAll()
    end},
}

-- ─────────────────────────────────────────────────────
-- SECTION 9 · BUTTON BUILDER + PAGES
-- ─────────────────────────────────────────────────────

local function AddButton(parent, data)
    local id = data.Id or data.Name
    local active = data.Toggle and HUB.state[id]
    local b = NewInst("TextButton", parent)
    b.BackgroundColor3 = Color3.fromRGB(50,50,50)
    b.Text = data.Name
    b.Font = Enum.Font.GothamBold
    b.TextColor3 = Color3.new(1,1,1)
    b.TextScaled = true
    NewInst("UICorner", b).CornerRadius = UDim.new(0,6)

    local pad = NewInst("UIPadding", b)
    pad.PaddingLeft = UDim.new(0,4)
    pad.PaddingRight = UDim.new(0,4)

    local cons = NewInst("UITextSizeConstraint", b)
    cons.MinTextSize = 9
    cons.MaxTextSize = 14

    local stroke = NewInst("UIStroke", b)
    stroke.Thickness = 2
    stroke.Enabled = active and true or false
    stroke.Color = active and Color3.fromRGB(50,255,50) or Color3.fromRGB(80,80,80)

    Connect(b.MouseButton1Click, function()
        b.BackgroundColor3 = Color3.fromRGB(255,255,0)
        b.TextColor3 = Color3.new(0,0,0)
        task.wait(0.05)
        b.BackgroundColor3 = Color3.fromRGB(50,50,50)
        b.TextColor3 = Color3.new(1,1,1)
        if data.Toggle then
            -- ✅ الزر هو اللي يقلب الحالة قبل ما ينادي الدالة، ويرجّعها إذا فشلت
            local prev = HUB.state[id]
            HUB.state[id] = not prev
            local ok = SafeCall(data.Function, data.Name)
            if not ok then HUB.state[id] = prev end
            if b.Parent then
                stroke.Enabled = true
                stroke.Color = HUB.state[id] and Color3.fromRGB(50,255,50) or Color3.fromRGB(180,50,50)
            end
        else
            SafeCall(data.Function, data.Name)
        end
    end)
end

local bPP = 20
for pageNum = 1, math.ceil(#CF / bPP) do
    local pg = CreatePage()
    local tab = CreateTab("قائمة "..pageNum, pg)
    for i = (pageNum-1)*bPP + 1, math.min(pageNum*bPP, #CF) do
        AddButton(pg, CF[i])
    end
    if pageNum == 1 then
        pg.Visible = true
        tab.BackgroundColor3 = Color3.fromRGB(255,255,0)
        tab.TextColor3 = Color3.fromRGB(0,0,0)
    end
end

do
    local creditsPage = NewInst("ScrollingFrame", Pages)
    creditsPage.Size = UDim2.new(1,0,1,0)
    creditsPage.BackgroundTransparency = 1
    creditsPage.Visible = false
    creditsPage.ScrollBarThickness = 5
    creditsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
    creditsPage.CanvasSize = UDim2.new(0,0,0,0)

    local list = NewInst("UIListLayout", creditsPage)
    list.Padding = UDim.new(0,8)
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local function AddInfo(txt, color)
        local lbl = NewInst("TextLabel", creditsPage)
        lbl.Size = UDim2.new(0.95,0,0,36)
        lbl.BackgroundColor3 = Color3.fromRGB(35,35,35)
        lbl.TextColor3 = color or Color3.new(1,1,1)
        lbl.Text = txt
        lbl.Font = Enum.Font.GothamBold
        lbl.TextScaled = true
        local c = NewInst("UITextSizeConstraint", lbl)
        c.MaxTextSize = 14
        NewInst("UICorner", lbl).CornerRadius = UDim.new(0,6)
    end

    AddInfo("⭐ HUSSEIN HUB v14.7", Color3.fromRGB(255,255,0))
    AddInfo("👨‍💻 المطور: Hussein", Color3.fromRGB(100,200,255))
    AddInfo("📦 السكربتات: "..#CF, Color3.fromRGB(150,255,150))
    CreateTab("Credits", creditsPage)
end

-- ─────────────────────────────────────────────────────
-- SECTION 10 · INIT + HOTKEYS
-- ─────────────────────────────────────────────────────

MakeDraggable(F, T)
local tbDragged = MakeDraggable(TB)

local function OpenUI()
    F.Visible = true
    F.Size = UDim2.new(0, 360, 0, 260)
    HUB.uiVisible = true
end

local function ToggleUI()
    if F.Visible then
        CloseUI()
    else
        OpenUI()
    end
end

Connect(TB.MouseButton1Click, function()
    if tbDragged() then return end -- ✅ السحب ما يفتح/يسكر القائمة
    ToggleUI()
end)

Connect(U.InputBegan, function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.H and (U:IsKeyDown(Enum.KeyCode.LeftControl) or U:IsKeyDown(Enum.KeyCode.RightControl)) then
        ToggleUI()
    end
end)

OpenUI()
ShowToast("✅ Hussein Hub v14.7 محمّل!", 2, "success")
ShowToast("👋 أهلاً "..p.Name, 2.5, "info")

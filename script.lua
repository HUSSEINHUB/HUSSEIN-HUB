--[[
╔══════════════════════════════════════════════════╗
║ HUSSEIN HUB v14.2 (Smooth UI) - MODDED          ║
║ • دمج حفظ + انتقال في قائمة واحدة               ║
║ • واجهة سرعة مستقلة                             ║
║ • ✅ دعم مكانين للحفظ                           ║
║ • ✅ تصغير قائمة الحفظ                          ║
║ • ✅ مراقبة شخص قابلة للسحب                     ║
╚══════════════════════════════════════════════════╝
]]

local p = game.Players.LocalPlayer
local U = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local HS = game:GetService("HttpService")
local VU = game:GetService("VirtualUser")
local g = "HusseinHub_v14.2"

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
HUB.state = HUB.state or {}
HUB.conns = {}
HUB.instances = {}
HUB.espConns = {}
HUB.espData = {}
HUB.loaded = HUB.loaded or {}
HUB.lighting = nil
HUB.originalWS = nil
HUB.originalJP = nil
HUB.uiVisible = true
HUB.afkLast = 0

-- ✅ مكانين للحفظ
getgenv().SavedPosition1 = getgenv().SavedPosition1 or nil
getgenv().SavedPosition2 = getgenv().SavedPosition2 or nil

local function TrackInst(inst)
    table.insert(HUB.instances, inst)
    return inst
end

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

local function CleanupAll()
    warn("🧹 تنظيف HusseinHub...")
    for _, c in ipairs(HUB.conns) do
        pcall(function()
            if c.Connected then c:Disconnect() end
        end)
    end
    HUB.conns = {}
    for _, c in ipairs(HUB.espConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    HUB.espConns = {}
    for _, i in ipairs(HUB.instances) do
        pcall(function()
            if i and i.Parent then i:Destroy() end
        end)
    end
    HUB.instances = {}
    pcall(function()
        local gui = p.PlayerGui:FindFirstChild(g.."_SaveLoad")
        if gui then gui:Destroy() end
    end)
    pcall(function()
        local gui2 = p.PlayerGui:FindFirstChild(g.."_SpeedUI")
        if gui2 then gui2:Destroy() end
    end)
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
    getgenv().HusseinHubRunning = false
    print("✅ تم التنظيف")
end
getgenv().HusseinHubCleanup = CleanupAll

-- ─────────────────────────────────────────────────────
-- SECTION 2 · SAVE/LOAD POSITION CORE
-- ─────────────────────────────────────────────────────

local function GetHRP()
    local char = p.Character or p.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

-- ─────────────────────────────────────────────────────
-- SECTION 3 · TOAST SYSTEM
-- ─────────────────────────────────────────────────────

local ToastGui = NewInst("ScreenGui", p.PlayerGui)
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
    if text:find("❌") or text:find("رفض") or text:find("غير مسموح") then return "error" end
    if text:find("⚠️") or text:find("بالفعل") or text:find("متوقف") then return "warn" end
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
            pcall(function()
                rem.frame:Destroy()
            end)
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
            pcall(function()
                frame:Destroy()
            end)
            relayoutToasts()
        end
    end)
end

-- ─────────────────────────────────────────────────────
-- SECTION 3.5 · SAVE/LOAD FUNCTIONS (مكانين)
-- ─────────────────────────────────────────────────────

local function SavePos1()
    local hrp = GetHRP()
    getgenv().SavedPosition1 = hrp.CFrame
    ShowToast("✅ تم حفظ المكان 1", 1, "success")
    print("✅ تم حفظ المكان 1")
end

local function SavePos2()
    local hrp = GetHRP()
    getgenv().SavedPosition2 = hrp.CFrame
    ShowToast("✅ تم حفظ المكان 2", 1, "success")
    print("✅ تم حفظ المكان 2")
end

local function LoadPos1()
    if getgenv().SavedPosition1 then
        local hrp = GetHRP()
        hrp.CFrame = getgenv().SavedPosition1
        ShowToast("✅ تم الانتقال للمكان 1", 1, "success")
        print("✅ تم الانتقال للمكان 1")
    else
        ShowToast("❌ لم يتم حفظ المكان 1", 1.5, "error")
        warn("❌ لم يتم حفظ المكان 1")
    end
end

local function LoadPos2()
    if getgenv().SavedPosition2 then
        local hrp = GetHRP()
        hrp.CFrame = getgenv().SavedPosition2
        ShowToast("✅ تم الانتقال للمكان 2", 1, "success")
        print("✅ تم الانتقال للمكان 2")
    else
        ShowToast("❌ لم يتم حفظ المكان 2", 1.5, "error")
        warn("❌ لم يتم حفظ المكان 2")
    end
end

-- ─────────────────────────────────────────────────────
-- SECTION 4 · DRAG HELPER + MAIN UI
-- ─────────────────────────────────────────────────────

local function MakeDraggable(obj, handle)
    handle = handle or obj
    local dragging, dragStart, startPos
    Connect(handle.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = i.Position
            startPos = obj.Position
        end
    end)
    Connect(U.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            obj.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    Connect(U.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
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

local S = NewInst("ScreenGui", p.PlayerGui)
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
L.Text = "HUSSEIN HUB v14.2 ⭐"
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
    Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Page.CanvasSize = UDim2.new(0, 0, 0, 0)
    Page.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
    Page.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"

    local Grid = NewInst("UIGridLayout", Page)
    Grid.CellPadding = UDim2.new(0, 5, 0, 5)
    Grid.CellSize = UDim2.new(0.47, 0, 0, 38)
    Grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
    Grid.VerticalAlignment = Enum.VerticalAlignment.Top
    Grid.SortOrder = Enum.SortOrder.LayoutOrder

    Connect(Grid:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        Page.CanvasSize = UDim2.new(0, 0, 0, Grid.AbsoluteContentSize.Y + 10)
    end)

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
-- SECTION 5 · LOAD FUNCTIONS
-- ─────────────────────────────────────────────────────

local ALLOWED_DOMAINS = {
    "raw.githubusercontent.com",
    "gist.githubusercontent.com",
    "pastebin.com",
    "rawscripts.net",
    "pastefy.app",
    "hellohellohell0.com",
    "api.luarmor.net",
    "encrypt-x.pages.dev",
}

local function isUrlAllowed(url)
    if type(url) ~= "string" then return false end
    if url:sub(1,8) ~= "https://" then return false end
    for _, d in ipairs(ALLOWED_DOMAINS) do
        if url:find(d, 1, true) then return true end
    end
    return false
end

local function Load(url)
    if not isUrlAllowed(url) then
        ShowToast("❌ رابط غير مسموح", 2, "error")
        warn("❌ Load() رُفض: "..tostring(url))
        return
    end
    ShowToast("⏳ جاري التحميل...", 1, "info")
    task.wait()
    SafeCall(function()
        loadstring(game:HttpGet(url))()
        ShowToast("✅ تم التحميل", 1, "success")
    end, "Load:"..url)
end

local function LoadWithArg(url, arg)
    if not isUrlAllowed(url) then
        ShowToast("❌ رابط غير مسموح", 2, "error")
        warn("❌ LoadWithArg() رُفض: "..tostring(url))
        return
    end
    ShowToast("⏳ جاري التحميل...", 1, "info")
    task.wait()
    SafeCall(function()
        local scriptFunc = loadstring(game:HttpGet(url))
        if scriptFunc then scriptFunc(arg) end
        ShowToast("✅ تم التحميل", 1, "success")
    end, "LoadWithArg:"..url)
end

-- ─────────────────────────────────────────────────────
-- SECTION 6 · CHARACTER RE-BINDING
-- ─────────────────────────────────────────────────────

local function applyCharacterState(char)
    local h = char:WaitForChild("Humanoid", 5)
    if not h then return end
    HUB.originalWS = HUB.originalWS or h.WalkSpeed
    HUB.originalJP = HUB.originalJP or h.JumpPower
    if HUB.state.speed then
        h.WalkSpeed = HUB.state.speedValue or 50
    end
end

Connect(p.CharacterAdded, applyCharacterState)
if p.Character then
    task.spawn(applyCharacterState, p.Character)
end

-- ─────────────────────────────────────────────────────
-- SECTION 7 · SPEED UI (واجهة سرعة مستقلة)
-- ─────────────────────────────────────────────────────

local speedEnabled = false
local speedValue = 16

local function applySpeed()
    local char = p.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if speedEnabled then
        hum.WalkSpeed = speedValue
    end
end

Connect(p.CharacterAdded, function()
    task.wait(0.2)
    applySpeed()
end)

local function OpenSpeedUI()
    local existing = p.PlayerGui:FindFirstChild(g.."_SpeedUI")
    if existing then
        existing:Destroy()
        return
    end

    local speedGui = NewInst("ScreenGui", p.PlayerGui)
    speedGui.Name = g.."_SpeedUI"
    speedGui.ResetOnSpawn = false
    speedGui.DisplayOrder = 102

    local frame = NewInst("Frame", speedGui)
    frame.Size = UDim2.new(0, 200, 0, 115)
    frame.Position = UDim2.new(0.5, -100, 0.2, 0)
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
    title.Text = "Speed"
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
    box.Text = tostring(speedValue)
    NewInst("UICorner", box).CornerRadius = UDim.new(0, 4)

    local toggle = NewInst("TextButton", frame)
    toggle.Size = UDim2.new(1, -10, 0, 30)
    toggle.Position = UDim2.new(0, 5, 0, 70)
    toggle.Text = speedEnabled and "ON" or "OFF"
    toggle.BackgroundColor3 = speedEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(170, 0, 0)
    NewInst("UICorner", toggle).CornerRadius = UDim.new(0, 4)

    local small = false

    Connect(box.FocusLost, function()
        speedValue = tonumber(box.Text) or 16
        if speedValue > 1000000000000000 then
            speedValue = 1000000000000000
        end
        applySpeed()
    end)

    Connect(toggle.MouseButton1Click, function()
        speedEnabled = not speedEnabled
        if speedEnabled then
            toggle.Text = "ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        else
            toggle.Text = "OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
            local char = p.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum.WalkSpeed = 16
                end
            end
        end
        applySpeed()
    end)

    Connect(min.MouseButton1Click, function()
        small = not small
        if small then
            box.Visible = false
            toggle.Visible = false
            frame.Size = UDim2.new(0, 200, 0, 30)
        else
            box.Visible = true
            toggle.Visible = true
            frame.Size = UDim2.new(0, 200, 0, 115)
        end
    end)

    Connect(close.MouseButton1Click, function()
        speedGui:Destroy()
    end)
end

-- ─────────────────────────────────────────────────────
-- SECTION 8 · FEATURE TABLE (مع زر تصغير لقائمة الحفظ)
-- ─────────────────────────────────────────────────────

local function OpenSaveMenu()
    local existing = p.PlayerGui:FindFirstChild(g.."_SaveLoad")
    if existing then
        existing:Destroy()
        return
    end

    local gui = NewInst("ScreenGui", p.PlayerGui)
    gui.Name = g.."_SaveLoad"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 101

    local frame = NewInst("Frame", gui)
    frame.Size = UDim2.new(0, 220, 0, 180)
    frame.Position = UDim2.new(0.5, -110, 0.5, -90)
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
    title.Text = "📍 حفظ / انتقال"
    title.Font = Enum.Font.GothamBold
    title.TextColor3 = Color3.fromRGB(255,255,0)
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left

    local minBtn = NewInst("TextButton", titleBar)
    minBtn.Size = UDim2.new(0, 24, 0, 24)
    minBtn.Position = UDim2.new(1, -54, 0, 4)
    minBtn.Text = "—"
    minBtn.BackgroundColor3 = Color3.fromRGB(60,60,60)
    minBtn.TextColor3 = Color3.fromRGB(255,255,255)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 14
    NewInst("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

    local closeBtn = NewInst("TextButton", titleBar)
    closeBtn.Size = UDim2.new(0, 24, 0, 24)
    closeBtn.Position = UDim2.new(1, -27, 0, 4)
    closeBtn.Text = "✕"
    closeBtn.BackgroundColor3 = Color3.fromRGB(60,60,60)
    closeBtn.TextColor3 = Color3.fromRGB(255,80,80)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    NewInst("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

    local buttonsContainer = NewInst("Frame", frame)
    buttonsContainer.Size = UDim2.new(1, 0, 1, -38)
    buttonsContainer.Position = UDim2.new(0, 0, 0, 38)
    buttonsContainer.BackgroundTransparency = 1
    buttonsContainer.ClipsDescendants = true

    local saveBtn1 = NewInst("TextButton", buttonsContainer)
    saveBtn1.Size = UDim2.new(0.88, 0, 0, 32)
    saveBtn1.Position = UDim2.new(0.06, 0, 0, 4)
    saveBtn1.BackgroundColor3 = Color3.fromRGB(45,45,45)
    saveBtn1.Text = "💾 حفظ 1"
    saveBtn1.Font = Enum.Font.GothamBold
    saveBtn1.TextColor3 = Color3.fromRGB(255,255,255)
    saveBtn1.TextSize = 13
    NewInst("UICorner", saveBtn1).CornerRadius = UDim.new(0, 7)

    local loadBtn1 = NewInst("TextButton", buttonsContainer)
    loadBtn1.Size = UDim2.new(0.88, 0, 0, 32)
    loadBtn1.Position = UDim2.new(0.06, 0, 0, 40)
    loadBtn1.BackgroundColor3 = Color3.fromRGB(45,45,45)
    loadBtn1.Text = "🚀 انتقال 1"
    loadBtn1.Font = Enum.Font.GothamBold
    loadBtn1.TextColor3 = Color3.fromRGB(255,255,255)
    loadBtn1.TextSize = 13
    NewInst("UICorner", loadBtn1).CornerRadius = UDim.new(0, 7)

    local saveBtn2 = NewInst("TextButton", buttonsContainer)
    saveBtn2.Size = UDim2.new(0.88, 0, 0, 32)
    saveBtn2.Position = UDim2.new(0.06, 0, 0, 76)
    saveBtn2.BackgroundColor3 = Color3.fromRGB(45,45,45)
    saveBtn2.Text = "💾 حفظ 2"
    saveBtn2.Font = Enum.Font.GothamBold
    saveBtn2.TextColor3 = Color3.fromRGB(255,255,255)
    saveBtn2.TextSize = 13
    NewInst("UICorner", saveBtn2).CornerRadius = UDim.new(0, 7)

    local loadBtn2 = NewInst("TextButton", buttonsContainer)
    loadBtn2.Size = UDim2.new(0.88, 0, 0, 32)
    loadBtn2.Position = UDim2.new(0.06, 0, 0, 112)
    loadBtn2.BackgroundColor3 = Color3.fromRGB(45,45,45)
    loadBtn2.Text = "🚀 انتقال 2"
    loadBtn2.Font = Enum.Font.GothamBold
    loadBtn2.TextColor3 = Color3.fromRGB(255,255,255)
    loadBtn2.TextSize = 13
    NewInst("UICorner", loadBtn2).CornerRadius = UDim.new(0, 7)

    local isMinimized = false
    local fullHeight = 180
    local miniHeight = 38

    local function toggleMinimize()
        isMinimized = not isMinimized
        if isMinimized then
            buttonsContainer.Visible = false
            frame.Size = UDim2.new(0, 220, 0, miniHeight)
            minBtn.Text = "□"
            title.Text = "📍 حفظ / انتقال (مصغّر)"
        else
            buttonsContainer.Visible = true
            frame.Size = UDim2.new(0, 220, 0, fullHeight)
            minBtn.Text = "—"
            title.Text = "📍 حفظ / انتقال"
        end
    end

    Connect(minBtn.MouseButton1Click, toggleMinimize)
    Connect(closeBtn.MouseButton1Click, function()
        gui:Destroy()
    end)

    Connect(saveBtn1.MouseButton1Click, function()
        saveBtn1.BackgroundColor3 = Color3.fromRGB(255,255,0)
        saveBtn1.TextColor3 = Color3.fromRGB(0,0,0)
        task.wait(0.08)
        saveBtn1.BackgroundColor3 = Color3.fromRGB(45,45,45)
        saveBtn1.TextColor3 = Color3.fromRGB(255,255,255)
        SavePos1()
    end)

    Connect(loadBtn1.MouseButton1Click, function()
        loadBtn1.BackgroundColor3 = Color3.fromRGB(255,255,0)
        loadBtn1.TextColor3 = Color3.fromRGB(0,0,0)
        task.wait(0.08)
        loadBtn1.BackgroundColor3 = Color3.fromRGB(45,45,45)
        loadBtn1.TextColor3 = Color3.fromRGB(255,255,255)
        LoadPos1()
    end)

    Connect(saveBtn2.MouseButton1Click, function()
        saveBtn2.BackgroundColor3 = Color3.fromRGB(255,255,0)
        saveBtn2.TextColor3 = Color3.fromRGB(0,0,0)
        task.wait(0.08)
        saveBtn2.BackgroundColor3 = Color3.fromRGB(45,45,45)
        saveBtn2.TextColor3 = Color3.fromRGB(255,255,255)
        SavePos2()
    end)

    Connect(loadBtn2.MouseButton1Click, function()
        loadBtn2.BackgroundColor3 = Color3.fromRGB(255,255,0)
        loadBtn2.TextColor3 = Color3.fromRGB(0,0,0)
        task.wait(0.08)
        loadBtn2.BackgroundColor3 = Color3.fromRGB(45,45,45)
        loadBtn2.TextColor3 = Color3.fromRGB(255,255,255)
        LoadPos2()
    end)

    frame.BackgroundTransparency = 0
end

local CF = {
    {Name="قفز لانهائي", Toggle=true, Function=function()
        HUB.state.infJump = not HUB.state.infJump
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
                pcall(function()
                    HUB.infJumpConn:Disconnect()
                end)
                HUB.infJumpConn = nil
            end
            ShowToast("❌ قفز لانهائي متوقف", 0.8, "warn")
        end
    end},

    {Name="سرعة", Function=function()
        OpenSpeedUI()
    end},

    {Name="ESP", Toggle=true, Function=function()
        HUB.state.esp = not HUB.state.esp
        local function cleanupESP()
            for _, c in ipairs(HUB.espConns) do
                pcall(function()
                    c:Disconnect()
                end)
            end
            HUB.espConns = {}
            for plr, d in pairs(HUB.espData) do
                pcall(function()
                    if d.highlight then d.highlight:Destroy() end
                end)
                pcall(function()
                    if d.billboard then d.billboard:Destroy() end
                end)
                HUB.espData[plr] = nil
            end
            if HUB.espGui then
                pcall(function()
                    HUB.espGui:Destroy()
                end)
                HUB.espGui = nil
            end
        end

        if not HUB.state.esp then
            cleanupESP()
            ShowToast("❌ ESP متوقف", 0.8, "warn")
            return
        end

        cleanupESP()

        local ESP = NewInst("ScreenGui", p.PlayerGui)
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
        MakeDraggable(TBB)

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

            if HUB.espData[plr] then
                pcall(function()
                    if HUB.espData[plr].highlight then HUB.espData[plr].highlight:Destroy() end
                    if HUB.espData[plr].billboard then HUB.espData[plr].billboard:Destroy() end
                end)
            end

            local hl = Instance.new("Highlight", char)
            hl.FillColor = teamColor(plr)
            hl.OutlineColor = Color3.new(1,1,1)
            hl.Enabled = enabled

            local bg = Instance.new("BillboardGui", head)
            bg.Size = UDim2.new(0, 80, 0, 18)
            bg.StudsOffset = Vector3.new(0, 2.5, 0)
            bg.AlwaysOnTop = true
            bg.Enabled = enabled
            bg.MaxDistance = 200

            local tl = Instance.new("TextLabel", bg)
            tl.Size = UDim2.new(1, 0, 1, 0)
            tl.BackgroundTransparency = 1
            tl.Text = plr.Name
            tl.TextColor3 = teamColor(plr)
            tl.Font = Enum.Font.GothamBold
            tl.TextSize = 11
            tl.TextStrokeTransparency = 0.4

            HUB.espData[plr] = {highlight = hl, billboard = bg, label = tl}
        end

        local function createESP(plr)
            if plr == p then return end
            if plr.Character then
                applyESP(plr, plr.Character)
            end
            table.insert(HUB.espConns, plr.CharacterAdded:Connect(function(c)
                applyESP(plr, c)
            end))
        end

        table.insert(HUB.espConns, TBB.MouseButton1Click:Connect(function()
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

        table.insert(HUB.espConns, game.Players.PlayerAdded:Connect(createESP))
        table.insert(HUB.espConns, game.Players.PlayerRemoving:Connect(function(plr)
            if HUB.espData[plr] then
                pcall(function()
                    HUB.espData[plr].highlight:Destroy()
                end)
                pcall(function()
                    HUB.espData[plr].billboard:Destroy()
                end)
                HUB.espData[plr] = nil
            end
        end))

        for _, plr in pairs(game.Players:GetPlayers()) do
            createESP(plr)
        end

        ShowToast("✅ ESP مفعّل", 0.8)
    end},

    {Name="طيران", Function=function()
        Load("https://raw.githubusercontent.com/XNEOFF/FlyGuiV3/main/FlyGuiV3.txt")
    end},

    {Name="طيران سيارة 🚗", Function=function()
        Load("https://raw.githubusercontent.com/Sumpre/Scripts/refs/heads/main/vfly.lua")
    end},

    {Name="المشي في الهواء", Function=function()
        Load("https://raw.githubusercontent.com/GhostPlayer352/Test4/main/Float")
    end},

    {Name="قفل الشاشة", Function=function()
        Load("https://raw.githubusercontent.com/MiniNoobie/ShiftLockx/main/Shiftlock-MiniNoobie")
    end},

    {Name="قائمة السيرفرات 🖥️", Function=function()
        LoadWithArg("https://encrypt-x.pages.dev/Scripts?Id=9434850125280", "9434850125280")
    end},

    {Name="مراقبة شخص", Function=function()
        if p.PlayerGui:FindFirstChild("SpectateGui") then
            p.PlayerGui.SpectateGui:Destroy()
            return
        end

        local gui = NewInst("ScreenGui", p.PlayerGui)
        gui.Name = "SpectateGui"
        gui.ResetOnSpawn = false
        -- تأكد من تتبع هذه الواجهة للتنظيف
        table.insert(HUB.instances, gui)

        -- ✅ جعل زر المراقبة قابلاً للسحب
        local btn = NewInst("ImageButton", gui)
        btn.Size = UDim2.new(0,50,0,50)
        btn.Position = UDim2.new(0,10,0.5,-25)
        btn.Image = "rbxassetid://176106970"
        btn.BackgroundTransparency = 0.3
        btn.Active = true
        btn.Draggable = true
        NewInst("UICorner", btn).CornerRadius = UDim.new(0,25)
        MakeDraggable(btn)  -- ✅ جعل الزر قابل للسحب

        local bar = NewInst("Frame", gui)
        bar.Position = UDim2.new(0.5,-100,1,10)
        bar.Size = UDim2.new(0,200,0,40)
        bar.BackgroundColor3 = Color3.new(0,0,0)
        bar.BackgroundTransparency = 0.2
        NewInst("UICorner", bar).CornerRadius = UDim.new(0,8)
        -- ✅ جعل شريط التحكم قابلاً للسحب أيضاً
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

        local cam = workspace.CurrentCamera
        local spectating = false
        local index = 1
        local players = game.Players:GetPlayers()

        local function update()
            players = game.Players:GetPlayers()
            if #players == 0 then return end
            index = math.clamp(index, 1, #players)
            local plr = players[index]
            if plr and plr.Character and plr.Character:FindFirstChild("Humanoid") then
                cam.CameraSubject = plr.Character.Humanoid
                title.Text = plr.Name
            end
        end

        Connect(btn.MouseButton1Click, function()
            spectating = not spectating
            if spectating then
                bar:TweenPosition(UDim2.new(0.5,-100,0.85,0), "Out", "Quad", 0.3, true)
                update()
            else
                bar:TweenPosition(UDim2.new(0.5,-100,1,10), "Out", "Quad", 0.3, true)
                if p.Character and p.Character:FindFirstChild("Humanoid") then
                    cam.CameraSubject = p.Character.Humanoid
                end
            end
        end)

        Connect(prev.MouseButton1Click, function()
            index = index - 1
            if index < 1 then index = #players end
            update()
        end)

        Connect(nxt.MouseButton1Click, function()
            index = index + 1
            if index > #players then index = 1 end
            update()
        end)
    end},

    {Name="اشكال", Function=function()
        Load("https://rawscripts.net/raw/Universal-Script-Zero-Gravity-28484")
    end},

    {Name="mm2 عربي", Function=function()
        Load("https://raw.githubusercontent.com/AlphaBay00/PhantomXLoader/main/Ld.lua.txt")
    end},

    {Name="عربي داخلة سكربتات", Function=function()
        Load("https://raw.githubusercontent.com/Lakany/MOLYN-DEVELOPMENT/refs/heads/main/README.md")
    end},

    {Name="vr7", Function=function()
        Load("https://raw.githubusercontent.com/VR7ss/OMK/refs/heads/main/VR7-ON-TOP")
    end},

    {Name="تحول سيارة", Function=function()
        Load("https://pastefy.app/UqDEIOpO/raw")
    end},

    {Name="حرب تحت الارض", Function=function()
        Load("https://raw.githubusercontent.com/Roblox-HttpSpy/Random-Silly-stuff/refs/heads/main/UW2-Panel.lua")
    end},

    {Name="رعب fe", Function=function()
        Load("https://pastebin.com/raw/C2ixw5i9")
    end},

    {Name="رقصات 1", Function=function()
        Load("https://raw.githubusercontent.com/zyrovell/Vexro-Emotes/main/vexroemotes.lua")
    end},

    {Name="عملاق fe", Function=function()
        Load("https://pastebin.com/raw/7Nv28tRE")
    end},

    {Name="afk logs", Function=function()
        Load("https://raw.githubusercontent.com/93q-f/GhostWalkScript/refs/heads/main/GhostWalkScript")
    end},

    {Name="امبروطورية النفط", Function=function()
        Load("https://raw.githubusercontent.com/gumanba/Scripts/main/OilEmpire")
    end},

    {Name="تحريك الاشياء", Function=function()
        Load("https://pastefy.app/jZBqvRS7/raw")
    end},

    {Name="فلكس fps", Function=function()
        Load("https://raw.githubusercontent.com/Joshingtonn123/JoshScript/refs/heads/main/SyrexhubSniperOrDie")
    end},

    {Name="تخطي الدكمة", Function=function()
        Load("https://pastebin.com/raw/RE1hdgBy")
    end},

    {Name="اختراق الجدار", Function=function()
        Load("https://pastefy.app/neNjjqht/raw")
    end},

    {Name="اختفاء", Function=function()
        Load("https://raw.githubusercontent.com/ymkeee/ArbizHub/refs/heads/main/Invisible.lua")
    end},

    {Name="اشياء دور حولك", Function=function()
        Load("https://raw.githubusercontent.com/Gazer-Ha/Tool-orbit/refs/heads/main/Source")
    end},

    {Name="تسجيل تحركات", Function=function()
        Load("https://gist.githubusercontent.com/maks1165/58da021266b63d8edc51ef0a3344881d/raw/546fd2b9aec33fd2db8768fa68b7950ff428c651/FlackBack%2520By%25204NTEP")
    end},

    {Name="رقصات 2", Function=function()
        Load("https://rawscripts.net/raw/Universal-Script-Emotes-Hub-216227")
    end},

    {Name="حرب النمل", Function=function()
        Load("https://raw.githubusercontent.com/ngoanthai639-hash/Ant-war-simple-hub/refs/heads/main/Ant%20war")
    end},

    {Name="تسلق الجدار", Function=function()
        Load("https://rawscripts.net/raw/Universal-Script-Wall-Walk-9153")
    end},

    {Name="Hitbox", Function=function()
        Load("https://raw.githubusercontent.com/example-prog/Hitbox-Expander/refs/heads/main/RScripter")
    end},

    {Name="skybox", Function=function()
        Load("https://raw.githubusercontent.com/VR7ss/VR7/main/vr7ontop")
    end},

    {Name="خبز او يموت", Function=function()
        Load("https://rawscripts.net/raw/Bake-or-Die-Kill-All-Bring-Items-Esp-etc-68463")
    end},

    {Name="تطير الناس", Function=function()
        Load("https://rawscripts.net/raw/Universal-Script-THE-REAL-dropkick-177199")
    end},

    {Name="رقصات 3", Function=function()
        Load("https://raw.githubusercontent.com/7yd7/Hub/refs/heads/Branch/GUIS/Emotes.lua")
    end},

    {Name="انتقال للاعبين", Function=function()
        if p.PlayerGui:FindFirstChild("TeleportGui_Tracked") then
            p.PlayerGui.TeleportGui_Tracked:Destroy()
            return
        end

        local gui = Instance.new("ScreenGui", p.PlayerGui)
        gui.Name = "TeleportGui_Tracked"
        gui.ResetOnSpawn = false
        table.insert(HUB.instances, gui)

        local mainFrame = Instance.new("Frame", gui)
        mainFrame.Size = UDim2.new(0,210,0,260)
        mainFrame.Position = UDim2.new(0.5,-105,0.5,-130)
        mainFrame.BackgroundColor3 = Color3.fromRGB(30,30,30)
        Instance.new("UICorner", mainFrame)
        MakeDraggable(mainFrame)

        local titleBar = Instance.new("TextLabel", mainFrame)
        titleBar.Size = UDim2.new(1,-30,0,28)
        titleBar.BackgroundTransparency = 1
        titleBar.Text = "🚀 انتقال للاعبين"
        titleBar.Font = Enum.Font.GothamBold
        titleBar.TextColor3 = Color3.fromRGB(255,255,0)
        titleBar.TextSize = 13
        titleBar.Position = UDim2.new(0,8,0,4)

        local refreshBtn = Instance.new("TextButton", mainFrame)
        refreshBtn.Size = UDim2.new(0,22,0,22)
        refreshBtn.Position = UDim2.new(1,-52,0,4)
        refreshBtn.Text = "🔄"
        refreshBtn.BackgroundTransparency = 1
        refreshBtn.TextColor3 = Color3.new(1,1,1)

        local scrollFrame = Instance.new("ScrollingFrame", mainFrame)
        scrollFrame.Size = UDim2.new(1,-10,1,-40)
        scrollFrame.Position = UDim2.new(0,5,0,35)
        scrollFrame.BackgroundTransparency = 1
        scrollFrame.ScrollBarThickness = 3
        scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        Instance.new("UIListLayout", scrollFrame).Padding = UDim.new(0,5)

        local tpConns = {}

        local function updatePlayerList()
            for _,child in pairs(scrollFrame:GetChildren()) do
                if child:IsA("TextButton") then
                    child:Destroy()
                end
            end

            for _, plr in pairs(game.Players:GetPlayers()) do
                if plr ~= p then
                    local b = Instance.new("TextButton", scrollFrame)
                    b.Size = UDim2.new(1,0,0,30)
                    b.Text = plr.Name
                    b.BackgroundColor3 = Color3.fromRGB(50,50,50)
                    b.TextColor3 = Color3.new(1,1,1)
                    Instance.new("UICorner", b)

                    b.MouseButton1Click:Connect(function()
                        if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                            p.Character.HumanoidRootPart.CFrame = plr.Character.HumanoidRootPart.CFrame
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
        table.insert(tpConns, game.Players.PlayerAdded:Connect(updatePlayerList))
        table.insert(tpConns, game.Players.PlayerRemoving:Connect(updatePlayerList))

        local closeBtn = Instance.new("TextButton", mainFrame)
        closeBtn.Size = UDim2.new(0,22,0,22)
        closeBtn.Position = UDim2.new(1,-26,0,4)
        closeBtn.Text = "X"
        closeBtn.BackgroundTransparency = 1
        closeBtn.TextColor3 = Color3.fromRGB(255,80,80)

        closeBtn.MouseButton1Click:Connect(function()
            for _, c in ipairs(tpConns) do
                c:Disconnect()
            end
            gui:Destroy()
        end)
    end},

    {Name="الغاء لاق", Function=function()
        ShowToast("⏳ جاري الغاء اللاق...", 0.5, "info")
        SafeCall(function()
            settings().Rendering.QualityLevel = 1
            game.Lighting.GlobalShadows = false
            game.Lighting.FogEnd = 1e9
            for _, v in next, workspace:GetDescendants() do
                if v:IsA("BasePart") then
                    v.Material = Enum.Material.SmoothPlastic
                    v.Reflectance = 0
                elseif v:IsA("Decal") or v:IsA("Texture") then
                    v:Destroy()
                elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Fire") or v:IsA("Smoke") then
                    v.Enabled = false
                end
            end
        end, "AntiLag")
        ShowToast("✅ تم الغاء اللاق", 1.2)
    end},

    {Name="نهار/ليل", Toggle=true, Function=function()
        HUB.state.night = not HUB.state.night
        local LT = game.Lighting
        SafeCall(function()
            if HUB.state.night then
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

    {Name="👻 كابوس لوري", Function=function()
        ShowToast("⏳ جاري تحميل كابوس لوري...", 1, "info")
        pcall(function()
            loadstring(game:HttpGet("https://pastefy.app/GSWBSY2v/raw"))()
            ShowToast("✅ تم تحميل كابوس لوري!", 1.5, "success")
        end)
    end},

    {Name="🌊 استأناف البحيرة", Function=function()
        ShowToast("⏳ جاري تحميل استأناف البحيرة...", 1, "info")
        pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/gumanba/Scripts/main/DraintheLake"))()
            ShowToast("✅ تم تحميل استأناف البحيرة!", 1.5, "success")
        end)
    end},

    {Name="🔪 MM2", Function=function()
        ShowToast("⏳ جاري تحميل MM2...", 1, "info")
        pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/xv3gasx/Murder-Mystery-2/refs/heads/main/Release.lua"))()
            ShowToast("✅ تم تحميل MM2!", 1.5, "success")
        end)
    end},

    {Name="🐝 السرب النهائي", Function=function()
        ShowToast("⏳ جاري تحميل السرب النهائي...", 1, "info")
        pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/gumanba/Scripts/main/FinalSwarm"))()
            ShowToast("✅ تم تحميل السرب النهائي!", 1.5, "success")
        end)
    end},

    {Name="مستشفى الوحوش 🏥", Function=function()
        Load("https://raw.githubusercontent.com/gumanba/Scripts/main/AnimalHospital")
    end},

    {Name="قيادة مطعم", Function=function()
        Load("https://raw.githubusercontent.com/feasthax/loader/refs/heads/main/RunARestaraunt.lua")
    end},

    {Name="بيانو 🎹", Function=function()
        Load("https://hellohellohell0.com/talentless-raw/TALENTLESS.lua")
    end},

    {Name="ماب كيبورد", Function=function()
        Load("https://raw.githubusercontent.com/Fluxyyy333/HoshiOnTop/main/loader.lua")
    end},

    {Name="Anti-AFK 🟢", Toggle=true, Function=function()
        HUB.state.afk = not HUB.state.afk
        if HUB.state.afk then
            HUB.afkIdleConn = TrackConn(p.Idled:Connect(function()
                pcall(function()
                    VU:CaptureController()
                    VU:ClickButton2(Vector2.new())
                end)
            end))
            HUB.afkLoopConn = Connect(RS.Heartbeat, function()
                if not HUB.state.afk then return end
                SafeCall(function()
                    local h = p.Character and p.Character:FindFirstChild("Humanoid")
                    if h and ((HUB.afkLast or 0) + 240 < tick()) then
                        h:Move(Vector3.new(0.1,0,0), false)
                        task.wait(0.1)
                        h:Move(Vector3.new(0,0,0), false)
                        HUB.afkLast = tick()
                    end
                end, "AntiAFK")
            end)
            ShowToast("✅ Anti-AFK شغّال", 1.2)
        else
            if HUB.afkIdleConn then
                pcall(function()
                    HUB.afkIdleConn:Disconnect()
                end)
                HUB.afkIdleConn = nil
            end
            if HUB.afkLoopConn then
                pcall(function()
                    HUB.afkLoopConn:Disconnect()
                end)
                HUB.afkLoopConn = nil
            end
            ShowToast("❌ Anti-AFK متوقف", 1.2, "warn")
        end
    end},

    {Name="كشف الأدمن 🔍", Function=function()
        if p.PlayerGui:FindFirstChild("AdminGui") then
            p.PlayerGui.AdminGui:Destroy()
            return
        end

        local gui = NewInst("ScreenGui", p.PlayerGui)
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
            if plr.UserId == game.CreatorId then
                table.insert(reasons, "صاحب اللعبة")
            end
            if plr:FindFirstChild("leaderstats") then
                for _, st in pairs(plr.leaderstats:GetChildren()) do
                    local s = st.Name:lower()
                    if (s:find("admin") or s:find("role") or s:find("level")) and st:IsA("IntValue") and st.Value > 50 then
                        table.insert(reasons, "Stat: "..st.Name.." = "..st.Value)
                    end
                end
            end
            local tools = {}
            if plr.Backpack then
                for _, t in pairs(plr.Backpack:GetChildren()) do
                    table.insert(tools, t)
                end
            end
            if plr.Character then
                for _, t in pairs(plr.Character:GetChildren()) do
                    if t:IsA("Tool") then
                        table.insert(tools, t)
                    end
                end
            end
            for _, t in pairs(tools) do
                if t:IsA("Tool") then
                    local n = t.Name:lower()
                    if n:find("ban") or n:find("kick") or (n:find("admin") and not n:find("fake")) or n:find("cmd") then
                        table.insert(reasons, "أداة: "..t.Name)
                    end
                end
            end
            return #reasons > 0, reasons
        end

        local found = 0
        for _, plr in pairs(game.Players:GetPlayers()) do
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
            if isAdm then
                found = found + 1
            end
        end
        title.Text = "🔍 أدمن: "..found.." / "..#game.Players:GetPlayers()
    end},

    {Name="ماب الصواريخ 🚀", Function=function()
        Load("https://raw.githubusercontent.com/gumanba/Scripts/main/MergeaNuke")
    end},

    {Name="ماب الليمون 🍋", Function=function()
        Load("https://raw.githubusercontent.com/yhmani76-ux/SoYo/refs/heads/main/SoYo%20sell%20lemon.lua")
    end},

    {Name="ماب المزرعة 2 🌾", Function=function()
        Load("https://api.luarmor.net/files/v4/loaders/359e97f8618e9008afe5f496184ebb7c.lua")
    end},

    {Name="🧹 تنظيف الكل", Function=function()
        CleanupAll()
    end},
}

-- ─────────────────────────────────────────────────────
-- SECTION 9 · BUTTON BUILDER + PAGES
-- ─────────────────────────────────────────────────────

local function AddButton(parent, data)
    local active = HUB.state[data.Name]
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
        SafeCall(data.Function, data.Name)
        if data.Toggle then
            HUB.state[data.Name] = not HUB.state[data.Name]
            stroke.Enabled = true
            stroke.Color = HUB.state[data.Name] and Color3.fromRGB(50,255,50) or Color3.fromRGB(180,50,50)
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

    AddInfo("⭐ HUSSEIN HUB v14.2", Color3.fromRGB(255,255,0))
    AddInfo("👨‍💻 المطور: Hussein", Color3.fromRGB(100,200,255))
    AddInfo("📦 السكربتات: "..#CF, Color3.fromRGB(150,255,150))
    CreateTab("Credits", creditsPage)
end

-- ─────────────────────────────────────────────────────
-- SECTION 10 · INIT + HOTKEYS
-- ─────────────────────────────────────────────────────

MakeDraggable(F, T)
MakeDraggable(TB)

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

Connect(TB.MouseButton1Click, ToggleUI)

Connect(U.InputBegan, function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.H and (U:IsKeyDown(Enum.KeyCode.LeftControl) or U:IsKeyDown(Enum.KeyCode.RightControl)) then
        ToggleUI()
    end
end)

OpenUI()
ShowToast("✅ Hussein Hub v14.2 محمّل!", 2, "success")
ShowToast("👋 أهلاً ".. p.Name, 2.5, "info")

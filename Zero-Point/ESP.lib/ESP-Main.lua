local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "NeonESP must run on the client.")

local NeonESP = {}
NeonESP.__index = NeonESP

local DEFAULTS = {
    Enabled = true,
    Boxes = true,
    Highlights = true,
    Names = false,
    Distances = false,
    TeamCheck = false,
    ThroughWalls = true,
    BoxColor = Color3.fromRGB(68, 255, 110),
    HighlightColor = Color3.fromRGB(68, 255, 110),
    BoxTransparency = 0.08,
    BoxThickness = 1.4,
    FillTransparency = 1,
    OutlineTransparency = 0,
    BoxSize = Vector3.new(4.1, 6, 3.2),
    BoxOffset = Vector3.new(0, 0, 0),
    MaxDistance = 1000,
    UpdateFPS = 60
}

local CORNERS = {
    Vector3.new(-1, -1, -1),
    Vector3.new(1, -1, -1),
    Vector3.new(1, -1, 1),
    Vector3.new(-1, -1, 1),
    Vector3.new(-1, 1, -1),
    Vector3.new(1, 1, -1),
    Vector3.new(1, 1, 1),
    Vector3.new(-1, 1, 1)
}

local EDGES = {
    {1, 2}, {2, 3}, {3, 4}, {4, 1},
    {5, 6}, {6, 7}, {7, 8}, {8, 5},
    {1, 5}, {2, 6}, {3, 7}, {4, 8}
}

local function disconnectAll(connections)
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
end

local function validateOption(name, value)
    local expected = DEFAULTS[name]
    if expected == nil then
        error("Unknown NeonESP option: " .. tostring(name), 3)
    end
    if typeof(value) ~= typeof(expected) then
        error("Wrong type for NeonESP option " .. name .. ": expected " .. typeof(expected), 3)
    end
    if name == "UpdateFPS" and value <= 0 then
        error("UpdateFPS must be above zero.", 3)
    end
    if name == "MaxDistance" and value < 0 then
        error("MaxDistance cannot be negative.", 3)
    end
    if name == "BoxThickness" and value <= 0 then
        error("BoxThickness must be above zero.", 3)
    end
    if (name == "BoxTransparency" or name == "FillTransparency" or name == "OutlineTransparency") and (value < 0 or value > 1) then
        error(name .. " must be between 0 and 1.", 3)
    end
end

function NeonESP:_hideBox(record)
    if not record.BoxVisible then
        return
    end
    record.BoxVisible = false
    for _, line in ipairs(record.Lines) do
        line.Visible = false
    end
end

function NeonESP:_hideName(record)
    if record.Label then
        record.Label.Visible = false
    end
end

function NeonESP:_hide(record)
    self:_hideBox(record)
    self:_hideName(record)
    if record.Highlight and record.Highlight.Enabled then
        record.Highlight.Enabled = false
    end
end

function NeonESP:_bindCharacter(record, character)
    self:_hide(record)
    if record.Highlight then
        record.Highlight:Destroy()
        record.Highlight = nil
    end
    record.Character = character
    record.Root = character and character:FindFirstChild("HumanoidRootPart") or nil
    record.Humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
end

function NeonESP:_trackPlayer(player)
    if player == LocalPlayer or self._records[player] then
        return
    end

    local record = {
        Player = player,
        Lines = {},
        BoxVisible = false,
        Connections = {},
        Label = nil,
        Highlight = nil
    }
    self._records[player] = record

    table.insert(record.Connections, player.CharacterAdded:Connect(function(character)
        self:_bindCharacter(record, character)
    end))

    table.insert(record.Connections, player.CharacterRemoving:Connect(function(character)
        if record.Character == character then
            self:_bindCharacter(record, nil)
        end
    end))

    if player.Character then
        self:_bindCharacter(record, player.Character)
    end
end

function NeonESP:_untrackPlayer(player)
    local record = self._records[player]
    if not record then
        return
    end
    disconnectAll(record.Connections)
    if record.Highlight then
        record.Highlight:Destroy()
    end
    for _, line in ipairs(record.Lines) do
        line:Destroy()
    end
    if record.Label then
        record.Label:Destroy()
    end
    self._records[player] = nil
end

function NeonESP:_ensureLines(record)
    if #record.Lines ~= 0 then
        return
    end
    for index = 1, #EDGES do
        local line = Instance.new("Frame")
        line.Name = "Edge" .. index
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.BorderSizePixel = 0
        line.BackgroundColor3 = self.Options.BoxColor
        line.BackgroundTransparency = self.Options.BoxTransparency
        line.ZIndex = 10
        line.Visible = false
        line.Parent = self._gui
        record.Lines[index] = line
    end
end

function NeonESP:_ensureLabel(record)
    if record.Label then
        return record.Label
    end
    local label = Instance.new("TextLabel")
    label.Name = "ESPName"
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Size = UDim2.fromOffset(230, 20)
    label.BackgroundTransparency = 1
    label.TextColor3 = self.Options.BoxColor
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.25
    label.TextSize = 13
    label.Font = Enum.Font.GothamBold
    label.ZIndex = 11
    label.Visible = false
    label.Parent = self._gui
    record.Label = label
    return label
end

function NeonESP:_ensureHighlight(record)
    if record.Highlight and record.Highlight.Parent == record.Character then
        return record.Highlight
    end
    if record.Highlight then
        record.Highlight:Destroy()
    end
    local highlight = Instance.new("Highlight")
    highlight.Name = "NeonESPOutline"
    highlight.Adornee = record.Character
    highlight.FillColor = self.Options.HighlightColor
    highlight.OutlineColor = self.Options.HighlightColor
    highlight.FillTransparency = self.Options.FillTransparency
    highlight.OutlineTransparency = self.Options.OutlineTransparency
    highlight.DepthMode = self.Options.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    highlight.Enabled = false
    highlight.Parent = record.Character
    record.Highlight = highlight
    return highlight
end

function NeonESP:_drawBox(record, root, camera, drawLines)
    if drawLines then
        self:_ensureLines(record)
    end

    local halfSize = self.Options.BoxSize * 0.5
    local boxCFrame = root.CFrame * CFrame.new(self.Options.BoxOffset)
    local projected = {}
    local viewport = camera.ViewportSize
    local nearScreen = false

    for index, sign in ipairs(CORNERS) do
        local point = Vector3.new(
            sign.X * halfSize.X,
            sign.Y * halfSize.Y,
            sign.Z * halfSize.Z
        )
        local screenPoint = camera:WorldToViewportPoint(boxCFrame:PointToWorldSpace(point))
        if screenPoint.Z <= 0.1 then
            self:_hideBox(record)
            return nil
        end
        projected[index] = Vector2.new(screenPoint.X, screenPoint.Y)
        if screenPoint.X >= -200 and screenPoint.X <= viewport.X + 200
            and screenPoint.Y >= -200 and screenPoint.Y <= viewport.Y + 200 then
            nearScreen = true
        end
    end

    if not nearScreen then
        self:_hideBox(record)
        return nil
    end

    if drawLines then
        local thickness = self.Options.BoxThickness
        for index, edge in ipairs(EDGES) do
            local a = projected[edge[1]]
            local b = projected[edge[2]]
            local delta = b - a
            local line = record.Lines[index]
            line.Position = UDim2.fromOffset((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5)
            line.Size = UDim2.fromOffset(delta.Magnitude, thickness)
            line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
            line.Visible = true
        end
        record.BoxVisible = true
    else
        self:_hideBox(record)
    end
    return projected
end

function NeonESP:_renderRecord(record, camera, origin)
    local character = record.Character
    if not character or not character.Parent then
        self:_hide(record)
        return
    end

    local root = record.Root
    if not root or not root.Parent then
        root = character:FindFirstChild("HumanoidRootPart")
        record.Root = root
    end
    local humanoid = record.Humanoid
    if not humanoid or not humanoid.Parent then
        humanoid = character:FindFirstChildOfClass("Humanoid")
        record.Humanoid = humanoid
    end

    if not root or not humanoid or humanoid.Health <= 0 then
        self:_hide(record)
        return
    end

    if self.Options.TeamCheck and LocalPlayer.Team ~= nil and record.Player.Team == LocalPlayer.Team then
        self:_hide(record)
        return
    end

    local distance = (root.Position - origin).Magnitude
    if distance > self.Options.MaxDistance then
        self:_hide(record)
        return
    end

    if self.Options.Highlights then
        local highlight = self:_ensureHighlight(record)
        if not highlight.Enabled then
            highlight.Enabled = true
        end
    elseif record.Highlight and record.Highlight.Enabled then
        record.Highlight.Enabled = false
    end

    local points
    if self.Options.Boxes or self.Options.Names or self.Options.Distances then
        points = self:_drawBox(record, root, camera, self.Options.Boxes)
    else
        self:_hideBox(record)
    end

    if self.Options.Names or self.Options.Distances then
        if not points then
            self:_hideName(record)
            return
        end
        local minY = math.huge
        local sumX = 0
        for index = 5, 8 do
            local top = points[index]
            minY = math.min(minY, top.Y)
            sumX = sumX + top.X
        end
        local label = self:_ensureLabel(record)
        local nameText = self.Options.Names and record.Player.DisplayName or ""
        local distanceText = self.Options.Distances and ("[" .. math.floor(distance + 0.5) .. " studs]") or ""
        label.Text = nameText .. ((nameText ~= "" and distanceText ~= "") and " " or "") .. distanceText
        label.Position = UDim2.fromOffset(sumX / 4, minY - 5)
        label.Visible = true
    else
        self:_hideName(record)
    end
end

function NeonESP:_render(dt)
    if not self.Options.Enabled then
        return
    end
    self._elapsed = self._elapsed + dt
    local interval = 1 / self.Options.UpdateFPS
    if self._elapsed < interval then
        return
    end
    self._elapsed = math.min(self._elapsed - interval, interval)

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local ownCharacter = LocalPlayer.Character
    local ownRoot = ownCharacter and ownCharacter:FindFirstChild("HumanoidRootPart")
    local origin = ownRoot and ownRoot.Position or camera.CFrame.Position

    for _, record in pairs(self._records) do
        self:_renderRecord(record, camera, origin)
    end
end

function NeonESP:SetOption(name, value)
    assert(not self._destroyed, "This NeonESP instance has been destroyed.")
    validateOption(name, value)
    self.Options[name] = value

    if name == "Enabled" and not value then
        for _, record in pairs(self._records) do
            self:_hide(record)
        end
    elseif name == "Boxes" and not value then
        for _, record in pairs(self._records) do
            self:_hideBox(record)
        end
    elseif (name == "Names" or name == "Distances") and not (self.Options.Names or self.Options.Distances) then
        for _, record in pairs(self._records) do
            self:_hideName(record)
        end
    elseif name == "Highlights" and not value then
        for _, record in pairs(self._records) do
            if record.Highlight then
                record.Highlight.Enabled = false
            end
        end
    elseif name == "BoxColor" or name == "BoxTransparency" then
        for _, record in pairs(self._records) do
            for _, line in ipairs(record.Lines) do
                line.BackgroundColor3 = self.Options.BoxColor
                line.BackgroundTransparency = self.Options.BoxTransparency
            end
            if record.Label then
                record.Label.TextColor3 = self.Options.BoxColor
            end
        end
    elseif name == "HighlightColor" or name == "FillTransparency" or name == "OutlineTransparency" or name == "ThroughWalls" then
        for _, record in pairs(self._records) do
            if record.Highlight then
                record.Highlight.FillColor = self.Options.HighlightColor
                record.Highlight.OutlineColor = self.Options.HighlightColor
                record.Highlight.FillTransparency = self.Options.FillTransparency
                record.Highlight.OutlineTransparency = self.Options.OutlineTransparency
                record.Highlight.DepthMode = self.Options.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
            end
        end
    end
    return self
end

function NeonESP:SetEnabled(enabled)
    return self:SetOption("Enabled", enabled)
end

function NeonESP:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    disconnectAll(self._connections)
    for player in pairs(self._records) do
        self:_untrackPlayer(player)
    end
    self._gui:Destroy()
end

function NeonESP.new(config)
    config = config or {}
    local self = setmetatable({}, NeonESP)
    self.Options = {}
    self._records = {}
    self._connections = {}
    self._elapsed = 0
    self._destroyed = false

    for name, value in pairs(DEFAULTS) do
        self.Options[name] = value
    end
    for name, value in pairs(config) do
        validateOption(name, value)
        self.Options[name] = value
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "NeonWireframeESP"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 10000
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    self._gui = gui

    table.insert(self._connections, Players.PlayerAdded:Connect(function(player)
        self:_trackPlayer(player)
    end))
    table.insert(self._connections, Players.PlayerRemoving:Connect(function(player)
        self:_untrackPlayer(player)
    end))

    for _, player in ipairs(Players:GetPlayers()) do
        self:_trackPlayer(player)
    end

    table.insert(self._connections, RunService.RenderStepped:Connect(function(dt)
        self:_render(dt)
    end))

    return self
end

local environment = type(getgenv) == "function" and getgenv() or _G

if environment.NeonESPController then
    pcall(function()
        environment.NeonESPController:Destroy()
    end)
end

environment.NeonESPController = NeonESP.new()

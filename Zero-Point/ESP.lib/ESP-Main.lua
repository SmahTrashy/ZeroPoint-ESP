local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "NeonESP must run on the client")

local NeonESP = {}
NeonESP.__index = NeonESP
NeonESP.Version = "2.3.0-ZeroPoint"

local DEFAULTS = {
    Enabled = true,
    PlayersEnabled = true,
    ObjectsEnabled = true,
    Boxes = true,
    Highlights = true,
    Names = false,
    Distances = false,
    ShowRole = false,
    ShowHealth = false,
    TeamCheck = false,
    ThroughWalls = true,
    BoxColor = Color3.fromRGB(68, 255, 110),
    HighlightColor = Color3.fromRGB(68, 255, 110),
    BoxTransparency = 0.08,
    BoxThickness = 1.4,
    TextSize = 13,
    FillTransparency = 1,
    OutlineTransparency = 0,
    BoxSize = Vector3.new(4.1, 6, 3.2),
    BoxOffset = Vector3.new(0, 0, 0),
    MaxDistance = 1000,
    UpdateFPS = 60
}

local EXTRA_TYPES = {
    NameColor = "Color3",
    LabelText = "string",
    OutlineColor = "Color3",
    RemoveWhenCollected = "boolean",
    RemoveWhenInvisible = "boolean",
    RequireTouchTransmitter = "boolean",
    VisualChildName = "string",
    InvisibleThreshold = "number"
}

local ROLE_COLORS = {
    Murderer = Color3.fromRGB(255, 65, 75),
    Sheriff = Color3.fromRGB(65, 155, 255),
    Hero = Color3.fromRGB(255, 220, 65),
    Innocent = Color3.fromRGB(68, 255, 110)
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
    local expectedType = expected ~= nil and typeof(expected) or EXTRA_TYPES[name]
    assert(expectedType, "Unknown NeonESP option: " .. tostring(name))
    assert(typeof(value) == expectedType, "Invalid type for " .. name .. "; expected " .. expectedType)
    if name == "UpdateFPS" then
        assert(value >= 1 and value <= 240, "UpdateFPS must be between 1 and 240")
    elseif name == "MaxDistance" then
        assert(value >= 0, "MaxDistance must be nonnegative")
    elseif name == "TextSize" then
        assert(value >= 8 and value <= 40, "TextSize must be between 8 and 40")
    elseif name == "BoxThickness" then
        assert(value > 0, "BoxThickness must be positive")
    elseif name == "InvisibleThreshold" then
        assert(value >= 0 and value <= 1, "InvisibleThreshold must be between 0 and 1")
    elseif name == "BoxTransparency" or name == "FillTransparency" or name == "OutlineTransparency" then
        assert(value >= 0 and value <= 1, name .. " must be between 0 and 1")
    elseif name == "BoxSize" then
        assert(value.X > 0 and value.Y > 0 and value.Z > 0, "BoxSize must be positive")
    end
end

local function mergeValidated(into, from)
    assert(type(from) == "table", "Expected a style table")
    local changed = false
    for name, value in pairs(from) do
        validateOption(name, value)
        if into[name] ~= value then
            into[name] = value
            changed = true
        end
    end
    return changed
end

local function makeRecord(kind, target)
    return {
        Kind = kind,
        Target = target,
        Lines = {},
        Label = nil,
        Highlight = nil,
        BoxVisible = false,
        Override = {},
        Dirty = true,
        Style = nil,
        Connections = {},
        VisualConnections = {},
        Role = nil,
        Dead = false
    }
end

function NeonESP:_hideBox(record)
    if record.BoxVisible then
        for _, line in ipairs(record.Lines) do
            line.Visible = false
        end
        record.BoxVisible = false
    end
end

function NeonESP:_hide(record)
    self:_hideBox(record)
    if record.Label then
        record.Label.Visible = false
    end
    if record.Highlight then
        record.Highlight.Enabled = false
    end
end

function NeonESP:_destroyRecord(record)
    self:_hide(record)
    disconnectAll(record.Connections)
    disconnectAll(record.VisualConnections)
    if record.Highlight then
        record.Highlight:Destroy()
    end
    if record.Label then
        record.Label:Destroy()
    end
    for _, line in ipairs(record.Lines) do
        line:Destroy()
    end
end

function NeonESP:_markDirty()
    for _, record in pairs(self._players) do
        record.Dirty = true
    end
    for _, record in pairs(self._objects) do
        record.Dirty = true
    end
end

function NeonESP:_style(record)
    if not record.Dirty and record.Style then
        return record.Style
    end
    local style = {}
    for name, value in pairs(self.Options) do
        style[name] = value
    end
    if record.Kind == "Player" then
        local colors = self.RoleColors[record.Role]
        if colors then
            style.BoxColor = colors.BoxColor
            style.HighlightColor = colors.HighlightColor
            style.NameColor = colors.NameColor
        end
    end
    for name, value in pairs(record.Override) do
        style[name] = value
    end
    if style.NameColor == nil then
        style.NameColor = style.BoxColor
    end
    if style.OutlineColor == nil then
        style.OutlineColor = style.HighlightColor
    end
    record.Style = style
    record.Dirty = false
    for _, line in ipairs(record.Lines) do
        line.BackgroundColor3 = style.BoxColor
        line.BackgroundTransparency = style.BoxTransparency
    end
    if record.Label then
        record.Label.TextColor3 = style.NameColor
        record.Label.TextSize = style.TextSize or 13
    end
    if record.Highlight then
        record.Highlight.FillColor = style.HighlightColor
        record.Highlight.OutlineColor = style.OutlineColor
        record.Highlight.FillTransparency = style.FillTransparency
        record.Highlight.OutlineTransparency = style.OutlineTransparency
        record.Highlight.DepthMode = style.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    end
    return style
end

function NeonESP:_trackPlayer(player)
    if player == LocalPlayer or self._players[player] then
        return
    end
    local record = makeRecord("Player", player)
    self._players[player] = record
    local function bindCharacter(character)
        self:_hide(record)
        if record.Highlight then
            record.Highlight:Destroy()
            record.Highlight = nil
        end
        record.Character = character
        record.Root = character and character:FindFirstChild("HumanoidRootPart") or nil
        record.Humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
    end
    table.insert(record.Connections, player.CharacterAdded:Connect(bindCharacter))
    table.insert(record.Connections, player.CharacterRemoving:Connect(function(character)
        if record.Character == character then
            bindCharacter(nil)
        end
    end))
    bindCharacter(player.Character)
end

function NeonESP:_untrackPlayer(player)
    local record = self._players[player]
    if not record then
        return
    end
    self._players[player] = nil
    self:_destroyRecord(record)
end

function NeonESP:_ensureLines(record, style)
    if #record.Lines > 0 then
        return
    end
    for index = 1, #EDGES do
        local line = Instance.new("Frame")
        line.Name = "Edge" .. index
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.BorderSizePixel = 0
        line.BackgroundColor3 = style.BoxColor
        line.BackgroundTransparency = style.BoxTransparency
        line.ZIndex = 10
        line.Visible = false
        line.Parent = self._gui
        record.Lines[index] = line
    end
end

function NeonESP:_ensureLabel(record, style)
    if record.Label then
        return record.Label
    end
    local label = Instance.new("TextLabel")
    label.Name = "ESPName"
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Size = UDim2.fromOffset(260, 21)
    label.BackgroundTransparency = 1
    label.TextColor3 = style.NameColor
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.25
    label.TextSize = style.TextSize or 13
    label.Font = Enum.Font.GothamBold
    label.ZIndex = 11
    label.Visible = false
    label.Parent = self._gui
    record.Label = label
    return label
end

function NeonESP:_ensureHighlight(record, adornee, style)
    local highlight = record.Highlight
    if highlight and highlight.Adornee == adornee and highlight.Parent == adornee then
        return highlight
    end
    if highlight then
        highlight:Destroy()
    end
    highlight = Instance.new("Highlight")
    highlight.Name = "NeonESPOutline"
    highlight.Adornee = adornee
    highlight.FillColor = style.HighlightColor
    highlight.OutlineColor = style.OutlineColor
    highlight.FillTransparency = style.FillTransparency
    highlight.OutlineTransparency = style.OutlineTransparency
    highlight.DepthMode = style.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    highlight.Enabled = false
    highlight.Parent = adornee
    record.Highlight = highlight
    return highlight
end

function NeonESP:_drawBox(record, camera, boxCFrame, size, style, showBox)
    local halfSize = size * 0.5
    local viewport = camera.ViewportSize
    local points = {}
    local onScreen = false
    for index, sign in ipairs(CORNERS) do
        local corner = Vector3.new(sign.X * halfSize.X, sign.Y * halfSize.Y, sign.Z * halfSize.Z)
        local point = camera:WorldToViewportPoint(boxCFrame:PointToWorldSpace(corner))
        if point.Z <= 0.1 then
            self:_hideBox(record)
            return nil
        end
        points[index] = Vector2.new(point.X, point.Y)
        if point.X >= -200 and point.X <= viewport.X + 200 and point.Y >= -200 and point.Y <= viewport.Y + 200 then
            onScreen = true
        end
    end
    if not onScreen then
        self:_hideBox(record)
        return nil
    end
    if showBox then
        self:_ensureLines(record, style)
        for index, edge in ipairs(EDGES) do
            local a = points[edge[1]]
            local b = points[edge[2]]
            local delta = b - a
            local line = record.Lines[index]
            line.Position = UDim2.fromOffset((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5)
            line.Size = UDim2.fromOffset(delta.Magnitude, style.BoxThickness)
            line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
            line.Visible = true
        end
        record.BoxVisible = true
    else
        self:_hideBox(record)
    end
    return points
end

local function objectVisualInvisible(visual, threshold)
    if not visual or not visual:IsA("BasePart") then
        return true
    end
    local effectiveTransparency = 1 - (1 - visual.Transparency) * (1 - visual.LocalTransparencyModifier)
    return effectiveTransparency >= (threshold or 0.995)
end

function NeonESP:_monitorObjectLifecycle(record)
    local object = record.Target
    local style = record.Override
    if not (style.RemoveWhenCollected or style.RemoveWhenInvisible or style.RequireTouchTransmitter) then
        return
    end

    local visualName = style.VisualChildName
    local function isCurrent()
        return self._objects[object] == record and not self._destroyed
    end

    local function refresh()
        if not isCurrent() then return end
        local visual = record.VisualPart
        if style.RemoveWhenCollected and (
            object:GetAttribute("Collected") == true
            or object:GetAttribute("Delete") == true
            or (visual and (visual:GetAttribute("Collected") == true or visual:GetAttribute("Delete") == true))
        ) then
            self:RemoveObject(object)
            return
        end
        if style.RequireTouchTransmitter and not object:FindFirstChildWhichIsA("TouchTransmitter") then
            self:RemoveObject(object)
            return
        end
        if style.RemoveWhenInvisible then
            if not visual then
                self:_hide(record)
                return
            end
            if objectVisualInvisible(visual, style.InvisibleThreshold) then
                if record.VisualWasVisible then
                    self:RemoveObject(object)
                else
                    self:_hide(record)
                end
                return
            end
            record.VisualWasVisible = true
        end
    end

    local function bindVisual()
        disconnectAll(record.VisualConnections)
        table.clear(record.VisualConnections)
        local visual = visualName and visualName ~= "" and object:FindFirstChild(visualName, true) or object
        record.VisualPart = visual
        if visual and visual:IsA("BasePart") then
            if style.RemoveWhenInvisible then
                table.insert(record.VisualConnections, visual:GetPropertyChangedSignal("Transparency"):Connect(refresh))
                table.insert(record.VisualConnections, visual:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(refresh))
            end
            if style.RemoveWhenCollected then
                table.insert(record.VisualConnections, visual:GetAttributeChangedSignal("Collected"):Connect(refresh))
                table.insert(record.VisualConnections, visual:GetAttributeChangedSignal("Delete"):Connect(refresh))
            end
        end
        refresh()
    end

    if style.RemoveWhenCollected then
        table.insert(record.Connections, object:GetAttributeChangedSignal("Collected"):Connect(refresh))
        table.insert(record.Connections, object:GetAttributeChangedSignal("Delete"):Connect(refresh))
    end
    if style.RequireTouchTransmitter then
        table.insert(record.Connections, object.ChildRemoved:Connect(function(child)
            if child:IsA("TouchTransmitter") and isCurrent() then
                self:RemoveObject(object)
            end
        end))
    end
    if visualName and visualName ~= "" then
        table.insert(record.Connections, object.DescendantAdded:Connect(function(child)
            if child.Name == visualName and child:IsA("BasePart") then
                bindVisual()
            end
        end))
        table.insert(record.Connections, object.DescendantRemoving:Connect(function(child)
            if child == record.VisualPart and isCurrent() then
                self:RemoveObject(object)
            end
        end))
    end
    bindVisual()
end

function NeonESP:_geometry(record)
    if record.Kind == "Player" then
        local character = record.Character
        if not character or not character:IsDescendantOf(Workspace) then
            return nil
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
        if not root or not humanoid or humanoid.Health <= 0 or record.Dead then
            return nil
        end
        return root.CFrame, self.Options.BoxSize, character
    end
    local target = record.Target
    if not target or not target:IsDescendantOf(Workspace) then
        return nil
    end
    if target:IsA("BasePart") then
        return target.CFrame, target.Size, target
    end
    if not record.BoundsKnown then
        self:RefreshObject(target)
    end
    if not record.BoundsLocal then
        return nil
    end
    return target:GetPivot() * record.BoundsLocal, record.BoundsSize, target
end

function NeonESP:_renderRecord(record, camera, origin)
    local style = self:_style(record)
    if not style.Enabled or (record.Kind == "Player" and not style.PlayersEnabled) or (record.Kind == "Object" and not style.ObjectsEnabled) then
        self:_hide(record)
        return
    end
    if record.Kind == "Player" and style.TeamCheck and LocalPlayer.Team and record.Target.Team == LocalPlayer.Team then
        self:_hide(record)
        return
    end
    if record.Kind == "Object" and record.Override.RemoveWhenInvisible then
        if not record.VisualPart or objectVisualInvisible(record.VisualPart, record.Override.InvisibleThreshold) then
            self:_hide(record)
            return
        end
    end
    local cframe, size, adornee = self:_geometry(record)
    if not cframe then
        self:_hide(record)
        return
    end
    if record.Kind == "Player" then
        size = style.BoxSize
    elseif record.Override.BoxSize then
        size = style.BoxSize
    end
    cframe = cframe * CFrame.new(style.BoxOffset)
    local distance = (cframe.Position - origin).Magnitude
    if distance > style.MaxDistance then
        self:_hide(record)
        return
    end
    if style.Highlights then
        self:_ensureHighlight(record, adornee, style).Enabled = true
    elseif record.Highlight then
        record.Highlight.Enabled = false
    end
    local wantsText = style.Names or style.Distances or (record.Kind == "Player" and (style.ShowRole or style.ShowHealth)) or style.LabelText ~= nil
    local points
    if style.Boxes or wantsText then
        points = self:_drawBox(record, camera, cframe, size, style, style.Boxes)
    else
        self:_hideBox(record)
    end
    if not wantsText or not points then
        if record.Label then
            record.Label.Visible = false
        end
        return
    end
    local textParts = {}
    if style.LabelText ~= nil then
        if style.LabelText ~= "" then
            table.insert(textParts, style.LabelText)
        end
    elseif style.Names then
        table.insert(textParts, record.Kind == "Player" and record.Target.DisplayName or record.Target.Name)
    end
    if record.Kind == "Player" and style.ShowRole and record.Role then
        table.insert(textParts, "[" .. record.Role .. "]")
    end
    if record.Kind == "Player" and style.ShowHealth then
        local humanoid = record.Humanoid
        if humanoid and humanoid.Parent then
            table.insert(textParts, string.format("[%d/%d HP]",
                math.floor(math.max(humanoid.Health, 0) + 0.5),
                math.floor(math.max(humanoid.MaxHealth, 0) + 0.5)))
        end
    end
    if style.Distances then
        table.insert(textParts, "[" .. math.floor(distance + 0.5) .. " studs]")
    end
    local label = self:_ensureLabel(record, style)
    label.Text = table.concat(textParts, " ")
    local minY = math.huge
    local sumX = 0
    for index = 5, 8 do
        minY = math.min(minY, points[index].Y)
        sumX = sumX + points[index].X
    end
    label.Position = UDim2.fromOffset(sumX / 4, minY - 5)
    label.Visible = label.Text ~= ""
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
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or camera.CFrame.Position
    for _, record in pairs(self._players) do
        self:_renderRecord(record, camera, origin)
    end
    for target, record in pairs(self._objects) do
        if target.Parent == nil then
            self:RemoveObject(target)
        else
            self:_renderRecord(record, camera, origin)
        end
    end
end

function NeonESP:SetOption(name, value)
    assert(not self._destroyed, "This NeonESP instance was destroyed")
    validateOption(name, value)
    if self.Options[name] ~= value then
        self.Options[name] = value
        self:_markDirty()
    end
    if (name == "Enabled" or name == "PlayersEnabled" or name == "ObjectsEnabled") and not value then
        for _, record in pairs(self._players) do
            if name ~= "ObjectsEnabled" then
                self:_hide(record)
            end
        end
        for _, record in pairs(self._objects) do
            if name ~= "PlayersEnabled" then
                self:_hide(record)
            end
        end
    end
    return self
end

function NeonESP:SetEnabled(value)
    return self:SetOption("Enabled", value)
end

local function findPlayer(player)
    if typeof(player) == "Instance" and player:IsA("Player") then
        return player
    end
    if type(player) == "string" then
        return Players:FindFirstChild(player)
    end
    if type(player) == "number" then
        for _, item in ipairs(Players:GetPlayers()) do
            if item.UserId == player then
                return item
            end
        end
    end
    return nil
end

function NeonESP:SetPlayerRole(player, role)
    local target = findPlayer(player)
    local record = target and self._players[target]
    if not record then
        return self
    end
    assert(role == nil or type(role) == "string", "Role must be a string or nil")
    if record.Role ~= role then
        record.Role = role
        record.Dirty = true
    end
    record.Dead = false
    return self
end

function NeonESP:SyncPlayer(player, character)
    local target = findPlayer(player)
    if not target or target == LocalPlayer then return self end
    if not self._players[target] then self:_trackPlayer(target) end
    local record = self._players[target]
    if record and record.Character ~= character then
        self:_hide(record)
        if record.Highlight then record.Highlight:Destroy() record.Highlight = nil end
        record.Character = character
        record.Root = character and character:FindFirstChild("HumanoidRootPart") or nil
        record.Humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
    end
    return self
end

function NeonESP:SetPlayerStyle(player, boxColor, outlineColor, fillTransparency)
    assert(typeof(boxColor) == "Color3", "Box color must be Color3")
    local style = {
        BoxColor = boxColor,
        HighlightColor = boxColor,
        OutlineColor = outlineColor or boxColor,
        NameColor = boxColor
    }
    if fillTransparency ~= nil then style.FillTransparency = fillTransparency end
    return self:SetPlayerOverride(player, style)
end

function NeonESP:GetPlayerRole(player)
    local target = findPlayer(player)
    local record = target and self._players[target]
    return record and record.Role or nil
end

function NeonESP:SetRoles(roles, clearMissing)
    assert(type(roles) == "table", "Roles must be a table")
    for player in pairs(self._players) do
        local role = roles[player]
        if role == nil then
            role = roles[player.Name]
        end
        if role == nil then
            role = roles[player.UserId]
        end
        if role ~= nil then
            self:SetPlayerRole(player, type(role) == "table" and role.Role or role)
        elseif clearMissing then
            self:SetPlayerRole(player, nil)
        end
    end
    return self
end

function NeonESP:SetMM2RoleData(data)
    assert(type(data) == "table", "MM2 role data must be a table")
    for player, record in pairs(self._players) do
        local info = data[player.Name] or data[player] or data[player.UserId]
        local role = type(info) == "table" and info.Role or (type(info) == "string" and info or nil)
        if record.Role ~= role then
            record.Role = role
            record.Dirty = true
        end
        record.Dead = type(info) == "table" and (info.Dead == true or info.Killed == true) or false
    end
    return self
end

function NeonESP:SetRoleColor(role, boxColor, highlightColor)
    assert(type(role) == "string" and role ~= "", "Role must be a nonempty string")
    assert(typeof(boxColor) == "Color3", "Box color must be Color3")
    if highlightColor ~= nil then
        assert(typeof(highlightColor) == "Color3", "Highlight color must be Color3")
    end
    local existing = self.RoleColors[role]
    if not existing or existing.BoxColor ~= boxColor or existing.HighlightColor ~= (highlightColor or boxColor) then
        self.RoleColors[role] = {
            BoxColor = boxColor,
            HighlightColor = highlightColor or boxColor,
            NameColor = boxColor
        }
        self:_markDirty()
    end
    return self
end

function NeonESP:SetPlayerOverride(player, style)
    local target = findPlayer(player)
    local record = target and self._players[target]
    if record then
        if mergeValidated(record.Override, style) then
            record.Dirty = true
        end
    end
    return self
end

function NeonESP:ClearPlayerOverride(player)
    local target = findPlayer(player)
    local record = target and self._players[target]
    if record then
        record.Override = {}
        record.Dirty = true
    end
    return self
end

function NeonESP:SetPlayerColor(player, boxColor, highlightColor)
    assert(typeof(boxColor) == "Color3", "Box color must be Color3")
    return self:SetPlayerOverride(player, {
        BoxColor = boxColor,
        HighlightColor = highlightColor or boxColor,
        NameColor = boxColor
    })
end

function NeonESP:RefreshObject(object)
    local record = self._objects[object]
    if not record then
        return self
    end
    record.BoundsLocal = nil
    record.BoundsSize = nil
    record.BoundsKnown = true
    if object:IsA("Model") and object:FindFirstChildWhichIsA("BasePart", true) then
        local success, boxCF, boxSize = pcall(function()
            local cf, size = object:GetBoundingBox()
            return cf, size
        end)
        if success then
            record.BoundsLocal = object:GetPivot():ToObjectSpace(boxCF)
            record.BoundsSize = boxSize
        end
    end
    return self
end

function NeonESP:AddObject(object, style)
    assert(typeof(object) == "Instance" and (object:IsA("BasePart") or object:IsA("Model")), "Object must be a BasePart or Model")
    assert(not self._destroyed, "This NeonESP instance was destroyed")
    local record = self._objects[object]
    if record then
        if style then
            self:SetObjectOverride(object, style)
        end
        return self
    end
    record = makeRecord("Object", object)
    record.Override.Names = true
    if style then
        mergeValidated(record.Override, style)
    end
    self._objects[object] = record
    table.insert(record.Connections, object.Destroying:Connect(function()
        self:RemoveObject(object)
    end))
    self:_monitorObjectLifecycle(record)
    if self._objects[object] == record then
        self:RefreshObject(object)
    end
    return self
end

function NeonESP:RemoveObject(object)
    local record = self._objects[object]
    if record then
        self._objects[object] = nil
        self:_destroyRecord(record)
    end
    return self
end

function NeonESP:RemoveByCoinID(coinID)
    if coinID == nil then return self end
    for object, record in pairs(self._objects) do
        local visual = record.VisualPart
        if record.Override.RemoveWhenCollected and visual and visual:GetAttribute("CoinID") == coinID then
            self:RemoveObject(object)
        end
    end
    return self
end

function NeonESP:SetObjectOverride(object, style)
    local record = self._objects[object]
    if record then
        if mergeValidated(record.Override, style) then
            record.Dirty = true
        end
    end
    return self
end

function NeonESP:SetObjectColor(object, boxColor, highlightColor)
    assert(typeof(boxColor) == "Color3", "Box color must be Color3")
    return self:SetObjectOverride(object, {
        BoxColor = boxColor,
        HighlightColor = highlightColor or boxColor,
        NameColor = boxColor
    })
end

function NeonESP:ClearObjectOverride(object)
    local record = self._objects[object]
    if record then
        record.Override = {Names = true}
        record.Dirty = true
    end
    return self
end

function NeonESP:WatchFolder(folder, predicate, style, recursive)
    assert(typeof(folder) == "Instance", "Folder must be an Instance")
    assert(predicate == nil or type(predicate) == "function", "Predicate must be a function or nil")
    assert(style == nil or type(style) == "table" or type(style) == "function", "Style must be a table, function, or nil")
    local esp = self
    local watcher = {Connections = {}, Owned = {}, Active = true}
    local function add(object)
        if not watcher.Active or (not object:IsA("BasePart") and not object:IsA("Model")) then
            return
        end
        if predicate then
            local ok, matched = pcall(predicate, object)
            if not ok or not matched then
                return
            end
        end
        if esp._objects[object] then
            return
        end
        local chosenStyle = style
        if type(style) == "function" then
            local ok, result = pcall(style, object)
            if not ok or (result ~= nil and type(result) ~= "table") then
                return
            end
            chosenStyle = result
        end
        esp:AddObject(object, chosenStyle)
        watcher.Owned[object] = true
    end
    local function remove(object)
        if watcher.Owned[object] then
            watcher.Owned[object] = nil
            esp:RemoveObject(object)
        end
    end
    function watcher:Disconnect()
        if not self.Active then
            return
        end
        self.Active = false
        disconnectAll(self.Connections)
        for object in pairs(self.Owned) do
            remove(object)
        end
        esp._watchers[self] = nil
    end
    watcher.Destroy = watcher.Disconnect
    esp._watchers[watcher] = true
    table.insert(watcher.Connections, folder.Destroying:Connect(function()
        watcher:Disconnect()
    end))
    local existing = recursive and folder:GetDescendants() or folder:GetChildren()
    for _, object in ipairs(existing) do
        add(object)
    end
    if recursive then
        table.insert(watcher.Connections, folder.DescendantAdded:Connect(function(child)
            if child:IsA("TouchTransmitter") then
                if child.Parent then add(child.Parent) end
            elseif child.Name == "CoinVisual" and child:IsA("BasePart") then
                if child.Parent then add(child.Parent) end
            end
            add(child)
        end))
        table.insert(watcher.Connections, folder.DescendantRemoving:Connect(function(child)
            if child:IsA("TouchTransmitter") then
                if child.Parent then remove(child.Parent) end
            elseif child.Name == "CoinVisual" and child:IsA("BasePart") then
                if child.Parent then remove(child.Parent) end
            end
            remove(child)
        end))
    else
        table.insert(watcher.Connections, folder.ChildAdded:Connect(add))
        table.insert(watcher.Connections, folder.ChildRemoved:Connect(remove))
    end
    return watcher
end

function NeonESP:EnableMM2Roles(enabled, refreshSeconds)
    assert(type(enabled) == "boolean", "Enabled must be a boolean")
    if refreshSeconds ~= nil then
        assert(type(refreshSeconds) == "number" and refreshSeconds >= 1, "Refresh interval must be at least one second")
    end
    self._roleToken = self._roleToken + 1
    self._mm2Enabled = enabled
    if not enabled then
        return self
    end
    local token = self._roleToken
    local interval = refreshSeconds or 2
    task.spawn(function()
        local remote
        while not self._destroyed and self._mm2Enabled and self._roleToken == token do
            if not remote or not remote:IsDescendantOf(ReplicatedStorage) then
                remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
            end
            if remote and remote:IsA("RemoteFunction") then
                local ok, result = pcall(function()
                    return remote:InvokeServer()
                end)
                if ok and type(result) == "table" and self._roleToken == token and not self._destroyed then
                    self:SetMM2RoleData(result)
                end
            end
            task.wait(interval)
        end
    end)
    return self
end

function NeonESP:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    self._mm2Enabled = false
    self._roleToken = self._roleToken + 1
    disconnectAll(self._connections)
    for watcher in pairs(self._watchers) do
        watcher:Disconnect()
    end
    for player in pairs(self._players) do
        self:_untrackPlayer(player)
    end
    for object in pairs(self._objects) do
        self:RemoveObject(object)
    end
    self._gui:Destroy()
    local environment = type(getgenv) == "function" and getgenv() or _G
    if environment.NeonESPController == self then
        environment.NeonESPController = nil
    end
end

function NeonESP.new(config)
    config = config or {}
    assert(type(config) == "table", "Config must be a table")
    local environment = type(getgenv) == "function" and getgenv() or _G
    if environment.NeonESPController then
        pcall(function()
            environment.NeonESPController:Destroy()
        end)
    end
    local self = setmetatable({}, NeonESP)
    self.Options = {}
    self.RoleColors = {}
    self._players = {}
    self._objects = {}
    self._watchers = {}
    self._connections = {}
    self._elapsed = 0
    self._roleToken = 0
    self._mm2Enabled = false
    self._destroyed = false
    for name, value in pairs(DEFAULTS) do
        self.Options[name] = value
    end
    mergeValidated(self.Options, config)
    for role, color in pairs(ROLE_COLORS) do
        self.RoleColors[role] = {
            BoxColor = color,
            HighlightColor = color,
            NameColor = color
        }
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
    environment.NeonESPController = self
    return self
end

return NeonESP

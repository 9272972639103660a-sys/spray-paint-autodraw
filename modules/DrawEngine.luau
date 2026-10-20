--!strict
-- High Performance Batched Drawing Engine for Spray Paint!
local Security = require(script.Parent.Security)

local DrawEngine = {}
DrawEngine.__index = DrawEngine

export type DrawPoint = {
    x: number,
    y: number,
    color: Color3,
    alpha: number,
}

export type PaintStroke = {
    scale: number,
    cframe: CFrame,
    color: Color3,
    layer: number,
}

function DrawEngine.new()
    local self = setmetatable({
        _isRunning = false,
        _isPaused = false,
        _isCancelled = false,
        _thread = nil :: thread?,
        
        -- Default settings
        batchSize = 35,
        batchDelay = 0.06,
        pixelScale = 0.25,
        spacingMult = 0.45,
        drawMode = "Raster", -- "Raster", "Palette", "Spiral"
        alphaThreshold = 15,
        skipWhite = false,
        skipBlack = false,
        maxResolution = 80,
    }, DrawEngine)
    return self
end

function DrawEngine:IsRunning(): boolean
    return self._isRunning
end

function DrawEngine:IsPaused(): boolean
    return self._isPaused
end

function DrawEngine:Pause()
    self._isPaused = true
end

function DrawEngine:Resume()
    self._isPaused = false
end

function DrawEngine:Cancel()
    self._isCancelled = true
    self._isRunning = false
    self._isPaused = false
end

-- Collects and downscales/filters pixels from the loaded image
function DrawEngine:ProcessImage(image: any): { points: {DrawPoint}, width: number, height: number }
    local origW = image.Width
    local origH = image.Height

    -- Calculate downscaled dimensions to prevent lag/crash on mobile
    local scaleFactor = 1
    if math.max(origW, origH) > self.maxResolution then
        scaleFactor = self.maxResolution / math.max(origW, origH)
    end

    local finalW = math.clamp(math.floor(origW * scaleFactor), 1, self.maxResolution)
    local finalH = math.clamp(math.floor(origH * scaleFactor), 1, self.maxResolution)

    local points: {DrawPoint} = {}

    for targetY = 1, finalH do
        local sourceY = math.clamp(math.floor((targetY - 0.5) / scaleFactor) + 1, 1, origH)
        for targetX = 1, finalW do
            local sourceX = math.clamp(math.floor((targetX - 0.5) / scaleFactor) + 1, 1, origW)

            local color, alpha = image:GetPixel(sourceX, sourceY)
            alpha = alpha or 255

            local shouldInclude = true

            -- Alpha filter
            if alpha < self.alphaThreshold then
                shouldInclude = false
            end

            -- White background filter (> 245 in all channels)
            if shouldInclude and self.skipWhite then
                if color.R > 0.96 and color.G > 0.96 and color.B > 0.96 then
                    shouldInclude = false
                end
            end

            -- Black background filter (< 15 in all channels)
            if shouldInclude and self.skipBlack then
                if color.R < 0.06 and color.G < 0.06 and color.B < 0.06 then
                    shouldInclude = false
                end
            end

            if shouldInclude then
                table.insert(points, {
                    x = targetX,
                    y = targetY,
                    color = color,
                    alpha = alpha,
                })
            end
        end
    end

    -- Sorting according to draw mode
    if self.drawMode == "Palette" then
        -- Sort points by hue/luminance to cluster colors
        table.sort(points, function(a, b)
            local ha, sa, va = a.color:ToHSV()
            local hb, sb, vb = b.color:ToHSV()
            if math.abs(ha - hb) > 0.05 then
                return ha < hb
            end
            return va < vb
        end)
    elseif self.drawMode == "Spiral" then
        -- Sort points from center outwards
        local midX = finalW / 2
        local midY = finalH / 2
        table.sort(points, function(a, b)
            local distA = (a.x - midX)^2 + (a.y - midY)^2
            local distB = (b.x - midX)^2 + (b.y - midY)^2
            return distA < distB
        end)
    end
    -- "Raster" mode is naturally ordered (by y then x)

    return {
        points = points,
        width = finalW,
        height = finalH,
    }
end

-- Executes the drawing process
function DrawEngine:Draw(
    image: any,
    targetCFrame: CFrame,
    onProgress: (current: number, total: number, pct: number) -> (),
    onComplete: () -> (),
    onError: (msg: string) -> ()
)
    if self._isRunning then
        onError("Drawing is already in progress!")
        return
    end

    local tool = Security.findSprayPaintTool()
    if not tool then
        onError("Spray Paint tool not found! Equip it from your backpack.")
        return
    end

    local remote, remoteMethod = Security.findPaintRemote(tool)
    if not remote or not remoteMethod then
        onError("Paint Remote not found on tool! Make sure you are in Spray Paint.")
        return
    end

    self._isRunning = true
    self._isPaused = false
    self._isCancelled = false

    local processed = self:ProcessImage(image)
    local points = processed.points
    local totalPoints = #points
    local finalW = processed.width
    local finalH = processed.height

    if totalPoints == 0 then
        self._isRunning = false
        onError("No drawable pixels found (all filtered out by alpha or color filters)!")
        return
    end

    self._thread = task.spawn(function()
        local currentIdx = 0
        local batch: {PaintStroke} = {}

        local stepSize = self.pixelScale * self.spacingMult
        local halfW = (finalW * stepSize) / 2
        local halfH = (finalH * stepSize) / 2

        for i, pt in ipairs(points) do
            if self._isCancelled then break end

            while self._isPaused and not self._isCancelled do
                task.wait(0.2)
            end
            if self._isCancelled then break end

            -- Calculate 3D position on the wall
            -- Z-offset (0.0001) avoids Z-fighting between overlapping splats
            local localX = halfW - (pt.x * stepSize)
            local localY = halfH - (pt.y * stepSize)
            local localZ = (pt.y * 0.0001) + (pt.x * 0.0001)

            local strokeCF = targetCFrame * CFrame.new(localX, localY, localZ) * CFrame.Angles(math.rad(-90), 0, 0)

            table.insert(batch, {
                scale = self.pixelScale,
                cframe = strokeCF,
                color = pt.color,
                layer = 20,
            })

            -- Dispatch when batch size reached or at last point
            if #batch >= self.batchSize or i == totalPoints then
                local num, hash = Security.getSecurityArgs()

                local success, err = pcall(function()
                    if remoteMethod == "InvokeServer" then
                        -- Try standard signature with security tokens
                        pcall(function()
                            (remote :: any):InvokeServer(num, hash, batch)
                        end)
                        -- Fallback call format if first form was ignored
                        pcall(function()
                            (remote :: any):InvokeServer({num, hash}, batch)
                        end)
                    else
                        pcall(function()
                            (remote :: any):FireServer(num, hash, batch)
                        end)
                    end
                end)

                currentIdx = i
                local pct = math.floor((currentIdx / totalPoints) * 100)
                if onProgress then
                    onProgress(currentIdx, totalPoints, pct)
                end

                table.clear(batch)
                task.wait(self.batchDelay)
            end
        end

        self._isRunning = false
        if not self._isCancelled and onComplete then
            onComplete()
        end
    end)
end

return DrawEngine

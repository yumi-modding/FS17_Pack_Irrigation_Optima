--
-- Canon
-- Specialization for raingun irrigation
-- Manage raingun rotation and partial spraying
--
-- @author  Nico0179, yumi
-- free for noncommerical-usage
--

Canon = {};

function Canon.prerequisitesPresent(specializations)
    return true;
end;

function Canon:load(savegame)
    
    self.setRaingunWidthState = SpecializationUtil.callSpecializationsFunction("setRaingunWidthState");
    self.getNewRaingunRot = Canon.getNewRaingunRot;
    

    self.raingunRotatingParts = {};
    self.raingunRotatingParts.raingunParts = {};
    local i = 0;
    while true do
        local key = string.format("vehicle.raingunRotatingParts.raingunPart(%d)", i);
        local node = getXMLString(self.xmlFile, key .. "#node");
        if node == nil then
            break;
        end;
        local part = {};
        part.node = Utils.indexToObject(self.components, node);
        part.inverse = Utils.getNoNil(getXMLBool(self.xmlFile, key .. "#inverse"), false);
        part.states = {};
        part.currentMinRot = nil;
        part.currentMaxRot = nil;
        local j = 0;
        while true do
            local stateKey = string.format(key .. ".state(%d)", j);
            local minRot = getXMLFloat(self.xmlFile, stateKey .. "#minRot");
            if minRot == nil then
                break;
            end;
            local state = {};
            state.minRot = {math.rad(minRot)};
            if part.currentMinRot == nil then
                part.currentMinRot = {state.minRot[1]};
            end;
            state.maxRot = {math.rad(getXMLInt(self.xmlFile, stateKey .. "#maxRot"))};
            state.Rotation = state.maxRot[1] - state.minRot[1]
            
            if part.currentMaxRot == nil then
                part.currentMaxRot = {state.maxRot[1]};
            end;
            state.speed = getXMLFloat(self.xmlFile, stateKey .. "#speed") * 1000;
            state.i18n = getXMLString(self.xmlFile, stateKey .. "#i18n");
            table.insert(part.states, state);
            j = j + 1;                
        end;        
        table.insert(self.raingunRotatingParts.raingunParts, part);
        i = i + 1;
    end;    
    self.radsPerMS = math.rad(Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.raingunRotatingParts#degreePerSecond"), 5) / 1000);
    self.raingunWidthState = 0;
    -- Default raingunWidthState should correspond to full with rotation
    self.raingunFullWidthRotation = self.raingunRotatingParts.raingunParts[1].states[self.raingunWidthState+1].Rotation
    --print("self.raingunFullWidthRotation " .. self.raingunFullWidthRotation)
    self.currentRaingunDirection = -1;
    self.numRaingunWidthStates = table.getn(self.raingunRotatingParts.raingunParts[1].states);
    self.raingunLeftDirectionTime = self.raingunRotatingParts.raingunParts[1].states[1].speed;
    
    
    self.raingunLeftDirection = false;        
    self.isSelectable = true;
end;

function Canon:delete()
end;

function Canon:readStream(streamId, connection)
    local state = streamReadInt8(streamId);
    self:setRaingunWidthState(state, true);
end;

function Canon:writeStream(streamId, connection)
    streamWriteInt8(streamId, self.raingunWidthState);
end;

function Canon:mouseEvent(posX, posY, isDown, isUp, button)
end;

function Canon:keyEvent(unicode, sym, modifier, isDown)
end;

function Canon:update(dt)
    if self.sideskirtInRange then
                local width = self.raingunRotatingParts.raingunParts[1].states[self.raingunWidthState+1].i18n;
                g_currentMission:addHelpButtonText(string.format(g_i18n:getText("Optima_RAINGUN_ROTATION_TEXT"), g_i18n:getText(width)), InputBinding.Optima_RAINGUN_ROTATION);
                if InputBinding.hasEvent(InputBinding.Optima_RAINGUN_ROTATION) then            
                    self:setRaingunWidthState((self.raingunWidthState + 1) % (self.numRaingunWidthStates));        
                end;
    end;
end;

function Canon:updateTick(dt)

     if self:getIsTurnedOn() and self.allowsSpraying and self.activable then
    
            self.raingunLeftDirectionTime = self.raingunLeftDirectionTime - dt;
                    
            for k, raingunPart in pairs(self.raingunRotatingParts.raingunParts) do
                local state = raingunPart.states[self.raingunWidthState+1];
                local x, y, z = getRotation(raingunPart.node);
                local dir = self.raingunLeftDirection;
                if raingunPart.inverse then
                    dir = not self.raingunLeftDirection;
                end;
                local newRot = unpack(Utils.getMovedLimitedValues({y}, raingunPart.currentMaxRot, raingunPart.currentMinRot, 1, state.speed, dt, dir));
                setRotation(raingunPart.node, x, newRot, z);                
                raingunPart.currentMinRot[1] = self:getNewRaingunRot(raingunPart.currentMinRot[1], state.minRot[1], dt);
                raingunPart.currentMaxRot[1] = self:getNewRaingunRot(raingunPart.currentMaxRot[1], state.maxRot[1], dt);
                if k == 1 then
                    if self.raingunLeftDirectionTime < 0 then
                        self.raingunLeftDirection = not self.raingunLeftDirection;
                        self.raingunLeftDirectionTime = state.speed;
                    end;
                end;
            end;

    end;    
end;

function Canon:draw()    

end;

function Canon:getNewRaingunRot(currentRot, newRot, dt)
    if newRot < currentRot then
        return math.max(newRot, currentRot - (dt * self.radsPerMS));
    else
        return math.min(newRot, currentRot + (dt * self.radsPerMS));
    end;
end;

function Canon:setRaingunWidthState(state, noEventSend)
    RaingunWidthEvent.sendEvent(self, state, noEventSend);    
    self.raingunWidthState = math.max(0, math.min(self.numRaingunWidthStates - 1, state));
    local raingunRotation = self.raingunRotatingParts.raingunParts[1].states[self.raingunWidthState+1].Rotation
    --print("raingunRotation " .. raingunRotation)
    -- Update workingWidth based on current rotation ratio compared to full width
    self.sprayUsageScale.workingWidth = (raingunRotation / self.raingunFullWidthRotation) * self.sprayUsageScale.fullWorkingWidth
    --print("self.sprayUsageScale.workingWidth " .. self.sprayUsageScale.workingWidth)
end;


function Canon:onDeactivate()
end;

--
-- RaingunWidthEvent
-- Networkevent for Irrigator
--
RaingunWidthEvent = {};
RaingunWidthEvent_mt = Class(RaingunWidthEvent, Event);

InitEventClass(RaingunWidthEvent, "RaingunWidthEvent");

function RaingunWidthEvent:emptyNew()
    local self = Event:new(RaingunWidthEvent_mt);
    return self;
end;

function RaingunWidthEvent:new(vehicle, state)
    local self = RaingunWidthEvent:emptyNew()
    self.vehicle = vehicle;
    self.state = state;
    return self;
end;

function RaingunWidthEvent:readStream(streamId, connection)
    local id = streamReadInt32(streamId);
    self.vehicle = networkGetObject(id);
    self.state = streamReadInt8(streamId);
    self:run(connection);
end;

function RaingunWidthEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, networkGetObjectId(self.vehicle));    
    streamWriteInt8(streamId, self.state);
end;

function RaingunWidthEvent:run(connection)
    self.vehicle:setRaingunWidthState(self.state, true);
    if not connection:getIsServer() then
        g_server:broadcastEvent(RaingunWidthEvent:new(self.vehicle, self.state), nil, connection, self.vehicle);
    end;
end;

function RaingunWidthEvent.sendEvent(vehicle, state, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(RaingunWidthEvent:new(vehicle, state), nil, nil, vehicle);
        else
            g_client:getServerConnection():sendEvent(RaingunWidthEvent:new(vehicle, state));
        end;
    end;
end;

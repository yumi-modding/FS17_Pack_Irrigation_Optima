setAttachEvent = {};
setAttachEvent_mt = Class(setAttachEvent, Event);

InitEventClass(setAttachEvent, "setAttachEvent");

function setAttachEvent:emptyNew()
    local self = Event:new(setAttachEvent_mt);
    self.className="setAttachEvent";
    return self;
end;

function setAttachEvent:new(object, vehicleId, jointId)
    local self = setAttachEvent:emptyNew()
    self.object = object;
    self.vehicleId = vehicleId;
    self.jointId = jointId;
    return self;
end;

function setAttachEvent:readStream(streamId, connection)
    local id = streamReadInt32(streamId);
    local jointId = streamReadInt32(streamId);
    local vehicleId = streamReadInt32(streamId);
    
    self.object = networkGetObject(id);
    self.vehicleId = networkGetObject(vehicleId);
    self.jointId = jointId;
    self:run(connection);
end;

function setAttachEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, networkGetObjectId(self.object));
    streamWriteInt32(streamId, self.jointId);
    streamWriteInt32(streamId, networkGetObjectId(self.vehicleId));
end;

function setAttachEvent:run(connection)   
    self.object:attachObject(self.vehicleId, self.jointId, true,self.object);
    if not connection:getIsServer() then
        g_server:broadcastEvent(setAttachEvent:new(self.object, self.vehicleId, self.jointId), nil, connection, self.object);
    end;
end;

function setAttachEvent.sendEvent(vehicle, vehicleId, jointId, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(setAttachEvent:new(vehicle, vehicleId, jointId), nil, nil, vehicle);
        else
            g_client:getServerConnection():sendEvent(setAttachEvent:new(vehicle, vehicleId, jointId));
        end;
    end;

end;

setDetachEvent = {};
setDetachEvent_mt = Class(setDetachEvent, Event);

InitEventClass(setDetachEvent, "setDetachEvent");

function setDetachEvent:emptyNew()
    local self = Event:new(setDetachEvent_mt);
    self.className="setDetachEvent";
    return self;
end;

function setDetachEvent:new(object)
    local self = setDetachEvent:emptyNew()
    self.object = object;
    return self;
end;

function setDetachEvent:readStream(streamId, connection)
    local id = streamReadInt32(streamId);    
    self.object = networkGetObject(id);
    self:run(connection);
end;

function setDetachEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, networkGetObjectId(self.object));
end;

function setDetachEvent:run(connection)   
    self.object:detachObject(true);
    if not connection:getIsServer() then
        g_server:broadcastEvent(setDetachEvent:new(self.object), nil, connection, self.object);
    end;
end;

function setDetachEvent.sendEvent(vehicle, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(setDetachEvent:new(vehicle), nil, nil, vehicle);
        else
            g_client:getServerConnection():sendEvent(setDetachEvent:new(vehicle));
        end;
    end;

end;
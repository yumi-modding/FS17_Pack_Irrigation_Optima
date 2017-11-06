--
-- Multiplayer Event Script
--
-- M@D Author:  Heady
-- M@D date: 17.04.2011
--
-- > Copyright (C) Heady - www.planet-ls.de < --
--

MPEvent = {};
MPEvent_mt = Class(MPEvent, Event);

InitEventClass(MPEvent, "MPEvent");

function MPEvent:emptyNew()
    local self = Event:new(MPEvent_mt);
    self.className="MPEvent";
    return self;
end;

function MPEvent:new(object)
    local self = MPEvent:emptyNew()
    self.object = object;
    return self;
end;

function MPEvent:readStream(streamId, connection)
    self.object = networkGetObject(streamReadInt32(streamId));    

    self.object.moveDirection1 = streamReadInt32(streamId);    
    
    if not connection:getIsServer() then
        g_server:broadcastEvent(MPEvent:new(self.object), nil, connection, self.object);
    end;

end;

function MPEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, networkGetObjectId(self.object));    
    
    streamWriteInt32(streamId, self.object.moveDirection1);
end;

function MPEvent:updateSendEvent(self)    

    if g_server ~= nil then
        g_server:broadcastEvent(MPEvent:new(self));
    else
        g_client:getServerConnection():sendEvent(MPEvent:new(self));
    end;

end;
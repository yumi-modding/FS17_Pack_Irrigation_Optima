--
-- RollingUp FS17
--
-- Based on Funktion FS15
-- Specialization for rolling up irrigation drum
--
-- @author  yumi, Nico0179
-- free for noncommerical-usage

RollingUp = {};

function RollingUp.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AnimatedVehicle, specializations);
end;

function RollingUp:preLoad(savegame)
end

function RollingUp:load(savegame)

    self.speed = 0.05;
    self.updateSpeed = 0.05;
    self.maxSpeed = 1.05;
    self.minSpeed = 0.05;
    self.currentRollingUpSpeed = -0.05;
    self.isRollingUp = false;

    self.updateSendEvent = SpecializationUtil.callSpecializationsFunction("updateSendEvent");
    self.sideskirtNode = {};
    self.sideskirtNode.node  = Utils.indexToObject(self.components,getXMLString(self.xmlFile, "vehicle.sideskirtNode#index"));    

    local drumUnroll = {};
    drumUnroll.name = getXMLString(self.xmlFile, "vehicle.drumUnroll#name");
    drumUnroll.openSpeedScale = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.drumUnroll#upSpeedScale"), 1);
    drumUnroll.closeSpeedScale = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.drumUnroll#downSpeedScale"), -drumUnroll.openSpeedScale);
    if drumUnroll.name ~= nil then
        self.drumUnroll = drumUnroll;
    end;
    self.drumUnroll.active = false;
    self.activable = false
        
    local i=0;
    while true do
        local key = string.format("vehicle.animations.animation(%d)", i);
        if not hasXMLProperty(self.xmlFile, key) then
            break;
        end;
        local name = getXMLString(self.xmlFile, key.."#name");
        if name ~= nil then        
            if name == "drumUnroll" then
                local partKey = key..string.format(".part(%d)", 0);
                local loadTime = getXMLFloat(self.xmlFile, partKey.."#loadTime");
                local endTime = getXMLFloat(self.xmlFile, partKey.."#endTime");
                
                local currentTime = self:getAnimationTime(self.drumUnroll.name);
                local speed = 1;
                if currentTime > loadTime/endTime then
                    speed = -1;
                end;
                self:playAnimation(self.drumUnroll.name, speed, currentTime, true);
                self:setAnimationStopTime(self.drumUnroll.name, loadTime/endTime);
                AnimatedVehicle.updateAnimations(self, 99999999);
                
            end;
        end;
        i = i+1;
    end;
    
    self.jointmove = false;    
    
end;

function RollingUp:postLoad(savegame)
  local drumUnrollAnimTime = nil
  if savegame ~= nil and not savegame.resetVehicles then
    drumUnrollAnimTime = getXMLFloat(savegame.xmlFile, savegame.key.."#UnrollAnimTime")
  end
  if drumUnrollAnimTime == nil then
      drumUnrollAnimTime = 0.;
  end
  local speed = 1;
  self:playAnimation(self.drumUnroll.name, speed, nil, true);
  self:setAnimationStopTime(self.drumUnroll.name, drumUnrollAnimTime);
  AnimatedVehicle.updateAnimationByName(self, self.drumUnroll.name, 99999999);
  self.jointmove = false;    
  self:updateCylinderedInitial(false);
end

function RollingUp:delete()
end;

function RollingUp:mouseEvent(posX, posY, isDown, isUp, button)
end;

function RollingUp:keyEvent(unicode, sym, modifier, isDown)
end;

function RollingUp:readStream(streamId, connection)
    -- update animation on synchroninzation --
    local drumUnrollAnimTime = streamReadFloat32(streamId);
    
    if drumUnrollAnimTime ~= nil then
        local currentTime = self:getAnimationTime(self.drumUnroll.name);
        local speed = 1;
        if currentTime > drumUnrollAnimTime then
            speed = -1;
        end;
        self:playAnimation(self.drumUnroll.name, speed, currentTime, true);
        self:setAnimationStopTime(self.drumUnroll.name, drumUnrollAnimTime);    
    end;
    AnimatedVehicle.updateAnimations(self, 50);        

end;

function RollingUp:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self:getAnimationTime(self.drumUnroll.name));
end;

function RollingUp:update(dt)

     if self.sideskirtInRange then
        if self.isRollingUp then
          g_currentMission:addHelpButtonText(g_i18n:getText("input_Optima_STOP"), InputBinding.IMPLEMENT_EXTRA);
          local speed = -(100 * self.currentRollingUpSpeed);
          -- convert to m/min
          speed = speed * 1.5 --10% <=> 15m/min ; 100% <=> 150m/min
          g_currentMission:addHelpButtonText(string.format(g_i18n:getText("input_Optima_ACCELERATE"), speed), InputBinding.Optima_ACCELERATE);
        else
          g_currentMission:addHelpButtonText(g_i18n:getText("input_Optima_ROLLUP"), InputBinding.IMPLEMENT_EXTRA);
        end
    end;

    local movejoint = self.jointmove;

    if InputBinding.hasEvent(InputBinding.IMPLEMENT_EXTRA) and self.sideskirtInRange then
        if self.isRollingUp then

            self.drumUnroll.active = true;
            self:stopAnimation(self.drumUnroll.name);    
            self.isRollingUp = false;
            self:setIsTurnedOn(false);
        else    
            self:playAnimation(self.drumUnroll.name, self.currentRollingUpSpeed, self:getAnimationTime(self.drumUnroll.name));
            self.isRollingUp = true;
            self:setIsTurnedOn(true);
        end
    end;

    
    if movejoint ~= self.jointmove then 
        self:updateSendEvent();
    end;

----------------------------------------------- Vitesse enroulement
    if InputBinding.hasEvent(InputBinding.Optima_ACCELERATE) and self.sideskirtInRange then
        self.speed = self.speed + self.updateSpeed;
--        print("speed = " .. tostring(self.speed));
        
        if self.speed > self.maxSpeed then
            self.speed = self.minSpeed;
        end;
        self.currentRollingUpSpeed = -self.speed;
        self:playAnimation(self.drumUnroll.name, self.currentRollingUpSpeed, self:getAnimationTime(self.drumUnroll.name));
    end;
-------------------------------
    if self:getAnimationTime(self.drumUnroll.name) > 0.001 then
        self.activable = true;
    else
        self.activable = false;  
        self.isRollingUp = false;
        self:setIsTurnedOn(false);
    end;
end;

function RollingUp:updateTick(dt)

    if g_currentMission.player ~= nil then
        local nearestDistance = 5;
        local vx, vy, vz = getWorldTranslation(g_currentMission.player.rootNode);        
        local px, py, pz = getWorldTranslation(self.sideskirtNode.node); 
        local distance = Utils.vector3Length(px-vx, py-vy, pz-vz);    
        if distance < nearestDistance then
            self.sideskirtInRange = true;
        else
            self.sideskirtInRange = false;
        end;
    end;
end;

function RollingUp:draw()    
end;

function RollingUp:updateSendEvent()    

    if g_server ~= nil then
        g_server:broadcastEvent(MPEvent:new(self));
    else
        g_client:getServerConnection():sendEvent(MPEvent:new(self));
    end;

end;

function RollingUp:getSaveAttributesAndNodes(nodeIdent)
  local currentTime = self:getAnimationTime(self.drumUnroll.name);
  local attributes = 'UnrollAnimTime="'.. tostring(currentTime) .. '"';
  return attributes, nil;
end;

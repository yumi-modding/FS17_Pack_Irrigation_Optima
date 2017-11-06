--
-- Unroll
-- Specialization for unrolling irrigation drum with tractor
--
-- @author  yumi
-- free for noncommerical-usage
--
Unroll = {};

function Unroll.prerequisitesPresent(specializations)
    return true;
end;

function Unroll:load(savegame)
    self.updateSendEvent = SpecializationUtil.callSpecializationsFunction("updateSendEvent");
    
    local drumUnroll = {};
    
    self.detachObject = Unroll.detachObject;
    self.attachObject = Unroll.attachObject;
    self.attachPoint = Utils.indexToObject(self.components, getXMLString(self.xmlFile,"vehicle.attacherPoint#index"));
    self.attachPointColli = Utils.indexToObject(self.components, getXMLString(self.xmlFile,"vehicle.attacherPoint#rootNode"));
    self.isRaingunAttached = false;
    self.Joint = {};
    self.startX = 0.;
    self.startY = 0.;
    self.startZ = 0.;
    self.unrollAxis = 0.;
    self.initAfterLoad = true
    self.backgroundOverlayId = nil
    self.raingunVehicle = nil;    
end;

function Unroll:delete()
end;

function Unroll:mouseEvent(posX, posY, isDown, isUp, button)
end;

function Unroll:keyEvent(unicode, sym, modifier, isDown)
end;

function Unroll:readStream(streamId, connection)
    local isRaingunAttached = streamReadBool(streamId);
    if isRaingunAttached then
        local jointId = streamReadInt32(streamId);
        local vehicleId = streamReadInt32(streamId);
        
        vehicleId = networkGetObject(vehicleId);
        self:attachObject(vehicleId,jointId,true);
    end;
end;

function Unroll:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isRaingunAttached);
    if self.isRaingunAttached then
        streamWriteInt32(streamId, self.Joint.attacherJointId);
        streamWriteInt32(streamId, networkGetObjectId(self.Joint.vehicle));
    end;
end;

function Unroll:update(dt)
    
    local movejoint = self.jointmove;

    if self:getIsActiveForInput() then    
         if self.raingunVehicle ~= nil then 
            if not self.isRaingunAttached then
                --Attach raingun
                if InputBinding.hasEvent(InputBinding.Optima_UNROLL_ATTACH) then
                    self:attachObject(self.raingunVehicle[1],self.raingunVehicle[2],nil);
                    --Set cruiseControl
                    self.attacherVehicle.cruiseControl.speed = 6;
                end;
            else    
                if InputBinding.hasEvent(InputBinding.Optima_UNROLL_ATTACH) then   
                    --Detach raingun
                    if self.raingunVehicle ~= nil then
                        v = self.raingunVehicle[1];
                        if v.drumUnroll ~= nil then
                            v.drumUnroll.active = true;
                            isdrumUnrollActive = false;
                        end;
                    end;
                    self:detachObject();
                end;
            end;
        end;
        
        if self.attacherVehicle ~= nil then
            local  tractorSpeed = self.attacherVehicle:getLastSpeed();
            --Only unroll when going forward
            local tractorMovingDirection = self.attacherVehicle.movingDirection;
            local speedScale = tractorSpeed / (3.6*(400/170));
            local newSpeedScale = 0.
            --print("speedScale " .. tostring(speedScale))
            if speedScale > 0 and tractorSpeed > 0.25 then
                newSpeedScale = speedScale * 0.995;
            end;
            if self.raingunVehicle ~= nil then
                v = self.raingunVehicle[1];
                if v.drumUnroll ~= nil then
                    if (v:getAnimationTime(v.drumUnroll.name) == 0) then
                      self.startX, self.startY, self.startZ = getWorldTranslation(self.rootNode);
                      _, self.unrollAxis, _ = localRotationToLocal(v.movingTools[2].node, v.attacherJoints[1].jointTransform, 0, 0, 0)
                    end
                    if self.isRaingunAttached and newSpeedScale > 0 and tractorSpeed > 0.25 and tractorMovingDirection > 0 then
                        v:playAnimation(v.drumUnroll.name, newSpeedScale, v:getAnimationTime(v.drumUnroll.name));
                        if g_currentMission.showHudEnv then
                          local dX = 0.;
                          local dY = 0.;
                          local dZ = 0.;
                          dX, dY, dZ = getWorldTranslation(self.attacherVehicle.rootNode);
                          local distance = Utils.vector3Length(dX-self.startX,dY-self.startY,dZ-self.startZ);
                          local str = string.format("Distance: %1.2f", distance);
                          _, unrollDirection, _ = localRotationToLocal(v.movingTools[2].node, v.attacherJoints[1].jointTransform, 0, 0, 0)
                          local deviation = 10 * (self.unrollAxis - unrollDirection)
                          if deviation >= 0. then
                            str = str .. string.format("\nDeviation:  %1.2f", deviation);
                          else
                            str = str .. string.format("\nDeviation: %1.2f", deviation);
                          end
                          setTextAlignment(RenderText.ALIGN_RIGHT);
                          local red = math.min(distance / 400., 1.);
                          local green = math.max(((400. - distance) / 400), 0.); 
                          setTextColor(red, green, 0, 1.0);
                          renderText(0.9828, 0.5, 0.020, str);
                        end
                    else
                        v:stopAnimation(v.drumUnroll.name); 
                    end;
                end;
            end;
            isdrumUnrollActive = true;
        end;
    else
      if self.raingunVehicle ~= nil then
        if self.isRaingunAttached then
          v = self.raingunVehicle[1];
          v:stopAnimation(v.drumUnroll.name);
        end
      end
    end;
    
    if movejoint ~= self.jointmove then -- wenn geändert dann sende an server/client (minimierung der übertragungsrate) --
        self:updateSendEvent();
    end;
end;


function Unroll:updateTick(dt)
    if self.initAfterLoad then
        self.startX, self.startY, self.startZ = getWorldTranslation(self.rootNode);
        self.initAfterLoad = false
    end
    if self:getIsActiveForInput() then
        self.raingunVehicle = nil;
        local x,y,z = getWorldTranslation(self.attachPoint);
        for k,v in pairs(g_currentMission.vehicles) do
            if v ~= self.attacherVehicle then
              for index,joint in pairs(v.attacherJoints) do
                  local x1,y1,z1 = getWorldTranslation(joint.jointTransform);
                  local distance = Utils.vector3Length(x-x1,y-y1,z-z1);
                  -- if (v.typeDesc == "Optima_1036 Optima_1036") then
                    -- print("distance " .. v.typeDesc .. " - " .. tostring(distance))
                  -- end
                  if distance <= 0.5 then
                      --print("distance " .. v.typeDesc .. " - OK" )
                      self.raingunVehicle = {};
                      self.raingunVehicle[1] = v;
                      self.raingunVehicle[2] = index;
                      self.proche = true;
                      break;
                  else
                      --self.raingunVehicle = nil
                      self.proche = false;
                  end;
              end;
              if self.proche then
                break
              end
            end
        end;
    end;
end;

function Unroll:attachObject(vehicleId,jointId,noEventSend,vehicle)
    setAttachEvent.sendEvent(self,vehicleId,jointId,noEventSend);
    local joint = self.Joint;
    joint.vehicle = vehicleId;
    local jointFA = nil;
    if jointId == 0 then
        jointFA = vehicleId.attacherJoint;
    else
        jointFA = vehicleId.attacherJoints[jointId];
    end;
    
    if vehicleId.isBroken == true then
        vehicleId.isBroken = false;
    end;
    if self.isServer then
        local colli = jointFA.rootNode; 
        local colli2 = self.attachPointColli;
        local jointTransform = Utils.getNoNil(jointFA.jointTransform, jointFA.node);
        local jointTransform2 = self.attachPoint;
    
        local constr = JointConstructor:new();                    
        constr:setActors(colli2, colli);
        constr:setJointTransforms(jointTransform2,  jointTransform);
        for i=1, 3 do
            constr:setTranslationLimit(i-1, true, 0, 0);
            --constr:setRotationLimit(i-1,0,0);
        end;
        joint.index = constr:finalize();
        if not self.Joint.vehicle.isControlled and self.Joint.vehicle.motor ~= nil and self.Joint.vehicle.wheels~= nil then
            for k,wheel in pairs(vehicleId.wheels) do
                --print("setWheelShapeProps attachObject");
                setWheelShapeProps(wheel.node, wheel.wheelShape, 0, vehicleId.motor.brakeForce, wheel.steeringAngle, wheel.rotationDamping);
                --setWheelShapeProps(wheel.node, wheel.wheelShape, 0, vehicleId.motor.brakeForce, 0);
                --setWheelShapeProps(wheel.node, wheel.wheelShape, 0, 0, 0);
            end;
        end;
    end;
    self.isRaingunAttached = true;
    self.raingunVehicle = nil;
    
end;
function Unroll:detachObject(noEventSend)
    setDetachEvent.sendEvent(self,noEventSend);
    if self.isServer then
        removeJoint(self.Joint.index);    
        if not self.Joint.vehicle.isControlled and self.Joint.vehicle.motor ~= nil and self.Joint.vehicle.wheels~= nil then
            for k,wheel in pairs(self.Joint.vehicle.wheels) do
                --setWheelShapeProps(wheel.node, wheel.wheelShape, 0, self.Joint.vehicle.motor.brakeForce, 0);
                --print("setWheelShapeProps detachObject");
                --setWheelShapeProps(wheel.node, wheel.wheelShape, 0, 0, 0);
            end;
        end;
    end;
    self.Joint = nil;
    self.Joint = {};
    self.isRaingunAttached = false;
end;
function Unroll:draw()
    if self.raingunVehicle ~= nil then
        if self.isRaingunAttached then
            g_currentMission:addHelpButtonText(g_i18n:getText("RAINGUNATTACHER_DetachObject"), InputBinding.Optima_UNROLL_ATTACH);
        else
	        g_currentMission:enableHudIcon("attach", 3);
	        g_currentMission:addHelpButtonText(g_i18n:getText("RAINGUNATTACHER_AttachObject"), InputBinding.Optima_UNROLL_ATTACH);
        end;
    end;
end;

function Unroll:updateSendEvent()    

    if g_server ~= nil then
        g_server:broadcastEvent(MPEvent:new(self));
    else
        g_client:getServerConnection():sendEvent(MPEvent:new(self));
    end;

end;



-- Irrigator FS17
--
-- Based on Sprayer for FS17 and Irrigator FS15
-- @author  yumi, Nico0179
-- @date  23/08/1T

Irrigator = {};

Irrigator.SPRAYTYPE_UNKNOWN = 0;
Irrigator.NUM_SPRAYTYPES = 0;

Irrigator.sprayTypes = {};
Irrigator.sprayTypeIndexToDesc = {};

Irrigator.sprayTypeToFillType = {};
Irrigator.fillTypeToSprayType = {};

function Irrigator.registerSprayType(name, nameI18N, category, pricePerLiter, litersPerSecond, showOnPriceTable, hudOverlayFilename, hudOverlayFilenameSmall, massPerLiter)
    local key = "SPRAYTYPE_"..string.upper(name);
    if Irrigator[key] == nil then
        Irrigator.NUM_SPRAYTYPES = Irrigator.NUM_SPRAYTYPES+1;
        Irrigator[key] = Irrigator.NUM_SPRAYTYPES;
        local desc = {name = name, index = Irrigator.NUM_SPRAYTYPES};
        desc.litersPerSecond = litersPerSecond;
        Irrigator.sprayTypes[name] = desc;
        Irrigator.sprayTypeIndexToDesc[Irrigator.NUM_SPRAYTYPES] = desc;
        local fillType = FillUtil.registerFillType(name, nameI18N, category, pricePerLiter, showOnPriceTable, hudOverlayFilename, hudOverlayFilenameSmall, massPerLiter)
        Irrigator.sprayTypeToFillType[Irrigator.NUM_SPRAYTYPES] = fillType;
        Irrigator.fillTypeToSprayType[fillType] = Irrigator.NUM_SPRAYTYPES;
    end
end


function Irrigator.initSpecialization()
    WorkArea.registerAreaType("sprayer");
end


function Irrigator.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Fillable, specializations) and
           SpecializationUtil.hasSpecialization(WorkArea, specializations) and
           SpecializationUtil.hasSpecialization(TurnOnVehicle, specializations) and
           SpecializationUtil.hasSpecialization(AttacherJoints, specializations);
end

function Irrigator:preLoad(savegame)
--print("Irrigator:preLoad(savegame)")
    self.getIsReadyToSpray = Irrigator.getIsReadyToSpray;
    self.getAreEffectsVisible = Irrigator.getAreEffectsVisible;
    self.getLitersPerSecond = Irrigator.getLitersPerSecond;
    self.supportsFillTriggers = true;
    self.loadWorkAreaFromXML = Utils.overwrittenFunction(self.loadWorkAreaFromXML, Irrigator.loadWorkAreaFromXML);
    self.doCheckSpeedLimit = Utils.overwrittenFunction(self.doCheckSpeedLimit, Irrigator.doCheckSpeedLimit);
    self.getIsTurnedOnAllowed = Utils.overwrittenFunction(self.getIsTurnedOnAllowed, Irrigator.getIsTurnedOnAllowed);
    self.getCanAddHelpButtonText = Utils.overwrittenFunction(self.getCanAddHelpButtonText, Irrigator.getCanAddHelpButtonText);
    self.aiAllowedToRefill = Utils.overwrittenFunction(self.aiAllowedToRefill, Irrigator.aiAllowedToRefill);
    self.getDrawFirstFillText = Utils.overwrittenFunction(self.getDrawFirstFillText, Irrigator.getDrawFirstFillText);
    self.getHasSpray = Irrigator.getHasSpray;
    self.processSprayerAreas = Irrigator.processSprayerAreas;
end

function Irrigator:load(savegame)
--print("Irrigator:preLoad(savegame)")
-------------------------
self.sideskirtNode = {};
self.sideskirtNode.node  = Utils.indexToObject(self.components,getXMLString(self.xmlFile, "vehicle.sideskirtNode#index"));	
-------------------------

    self.isSprayerTank = Utils.getNoNil(getXMLBool(self.xmlFile, "vehicle.sprayer#isTank"), false);
    self.allowsSpraying = Utils.getNoNil(getXMLBool(self.xmlFile, "vehicle.sprayer#allowsSpraying"), true);
    self.needsTankActivation = Utils.getNoNil(getXMLBool(self.xmlFile, "vehicle.sprayer#needsTankActivation"), false);
    self.activateTankOnLowering = Utils.getNoNil(getXMLBool(self.xmlFile, "vehicle.sprayer#activateTankOnLowering"), false);
    self.stopAiOnEmpty = Utils.getNoNil(getXMLBool(self.xmlFile, "vehicle.sprayer#stopAiOnEmpty"), true);
    self.activateOnLowering = Utils.getNoNil(getXMLBool(self.xmlFile, "vehicle.sprayer#activateOnLowering"), false);
    self.sprayUsageScale = {}
    self.sprayUsageScale.default = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.sprayUsageScales#scale"), 1)
    self.sprayUsageScale.workingWidth = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.sprayUsageScales#workingWidth"), 12)
    self.sprayUsageScale.fullWorkingWidth = self.sprayUsageScale.workingWidth
    self.sprayUsageScale.fillTypeScales = {}
    local i=0;
    while true do
        local key = string.format("vehicle.sprayUsageScales.sprayUsageScale(%d)", i);
        if not hasXMLProperty(self.xmlFile, key) then
            break;
        end
        local fillType = getXMLString(self.xmlFile, key.. "#fillType");
        local scale = getXMLFloat(self.xmlFile, key.. "#scale");
        if fillType ~= nil and scale ~= nil then
            local fillTypeInt = FillUtil.fillTypeNameToInt[fillType];
            if fillTypeInt ~= nil then
                self.sprayUsageScale.fillTypeScales[fillTypeInt] = scale
            else
                print("Warning: Invalid spray usage scale fill type '"..fillType.."' in '" .. self.configFileName.. "'");
            end
        end
        i = i+1;
    end
    self.lastSprayValveUpdateFoldTime = nil;
    self.sprayParticleSystems = {};
    self.sprayerEffects = {};
    if self.isClient then
        local i = 0;
        while true do
            local key = string.format("vehicle.sprayParticleSystems.sprayParticleSystem(%d)", i);
            local t = getXMLString(self.xmlFile, key .. "#type");
            if t == nil then
                break;
            end
            local fillType = FillUtil.fillTypeNameToInt[t];
            if fillType ~= nil then
                self.sprayParticleSystems[fillType] = {}
                local currentPS = Utils.getNoNil(self.sprayParticleSystems[fillType], {});
                ParticleUtil.loadParticleSystem(self.xmlFile, currentPS, key, self.components, false, nil, self.baseDirectory);
                currentPS.foldMinLimit = Utils.getNoNil(getXMLFloat(self.xmlFile, key.."#foldMinLimit"), 0);
                currentPS.foldMaxLimit = Utils.getNoNil(getXMLFloat(self.xmlFile, key.."#foldMaxLimit"), 1);
                table.insert(self.sprayParticleSystems[fillType], currentPS)
            end
            i = i + 1;
        end
        local i = 0
        while true do
            local key = string.format("vehicle.sprayParticles.emitterShape(%d)", i);
            if not hasXMLProperty(self.xmlFile, key) then
                break
            end
            local emitterShape = Utils.indexToObject(self.components, getXMLString(self.xmlFile, key.."#node"));
            local particleType = getXMLString(self.xmlFile, key.."#particleType")
            if emitterShape ~= nil then
                for index, _ in pairs(self.fillUnits) do
                    for fillType, _ in pairs(self:getUnitFillTypes(index)) do
                        if self.sprayParticleSystems[fillType] == nil then
                            self.sprayParticleSystems[fillType] = {}
                        end
                        local particleSystem = MaterialUtil.getParticleSystem(fillType, particleType)
                        if particleSystem ~= nil then
                            local currentPS = ParticleUtil.copyParticleSystem(self.xmlFile, key, particleSystem, emitterShape)
                            currentPS.foldMinLimit = Utils.getNoNil(getXMLFloat(self.xmlFile, key.."#foldMinLimit"), 0);
                            currentPS.foldMaxLimit = Utils.getNoNil(getXMLFloat(self.xmlFile, key.."#foldMaxLimit"), 1);
                            table.insert(self.sprayParticleSystems[fillType], currentPS)
                        end
                    end
                end
            end
            i = i + 1
        end
        local i = 0;
        while true do
            local key = string.format("vehicle.sprayerEffects.sprayerEffect(%d)", i);
            if not hasXMLProperty(self.xmlFile, key) then
                break;
            end
            local effects = EffectManager:loadEffect(self.xmlFile, key, self.components, self);
            if effects ~= nil then
                local sprayerEffect = {}
                sprayerEffect.effects = effects
                sprayerEffect.foldMinLimit = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#foldMinLimit"), 0);
                sprayerEffect.foldMaxLimit = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#foldMaxLimit"), 1);
                table.insert(self.sprayerEffects, sprayerEffect);
            end
            i = i + 1;
        end
        
        
        ------------------------> From FS15
        self.sprayValves = {};
    
        local psFile = getXMLString(self.xmlFile, "vehicle.sprayParticleSystem#file");
        if psFile ~= nil then
            local i=0;
            while true do
                local baseName = string.format("vehicle.sprayValves.sprayValve(%d)", i);
                local node = getXMLString(self.xmlFile, baseName.. "#index");
                if node == nil then
                    break;
                end;
                node = Utils.indexToObject(self.components, node);
                if node ~= nil then
                    local sprayValve = {};
                    sprayValve.particleSystems = {};
                    ParticleUtil.loadParticleSystem(self.xmlFile, sprayValve.particleSystems, "vehicle.sprayParticleSystem", node, false, nil, self.baseDirectory);

                    sprayValve.foldMinLimit = Utils.getNoNil(getXMLFloat(self.xmlFile, baseName.."#foldMinLimit"), 0);
                    sprayValve.foldMaxLimit = Utils.getNoNil(getXMLFloat(self.xmlFile, baseName.."#foldMaxLimit"), 1);
                    table.insert(self.sprayValves, sprayValve);
                end;
                i = i+1;
            end;
        end;
        ------------------------< From FS15
        
        self.sprayingAnimationName = Utils.getNoNil(getXMLString(self.xmlFile, "vehicle.sprayingAnimation#name"), "");
        self.sampleSprayer = SoundUtil.loadSample(self.xmlFile, {}, "vehicle.spraySound", nil, self.baseDirectory);
        if self.sampleFill == nil then
            local linkNode = Utils.indexToObject(self.components, Utils.getNoNil(getXMLString(self.xmlFile, "vehicle.fillSound#linkNode"), "0>"));
            self.sampleFill = SoundUtil.loadSample(self.xmlFile, {}, "vehicle.fillSound", nil, self.baseDirectory, linkNode);
        end
        self.sampleFillEnabled = false;
        self.sampleFillStopTime = -1;
        self.lastFillLevel = -1;
        self.sprayerTurnedOnRotationNodes = Utils.loadRotationNodes(self.xmlFile, {}, "vehicle.turnedOnRotationNodes.turnedOnRotationNode", "sprayer", self.components);
        self.sprayerTurnedOnScrollers = Utils.loadScrollers(self.components, self.xmlFile, "vehicle.sprayerTurnedOnScrollers.sprayerTurnedOnScroller", {}, false);
    end
    self.showFieldNotOwnedWarning = false;
    self.isSprayerSpeedLimitActive = false;
    if self.sowingMachineGroundContactFlag == nil and self.cultivatorGroundContactFlag == nil then
        table.insert(self.terrainDetailRequiredValueRanges, {g_currentMission.ploughValue, g_currentMission.ploughValue, g_currentMission.terrainDetailTypeFirstChannel, g_currentMission.terrainDetailTypeNumChannels});
        table.insert(self.terrainDetailRequiredValueRanges, {g_currentMission.cultivatorValue, g_currentMission.cultivatorValue, g_currentMission.terrainDetailTypeFirstChannel, g_currentMission.terrainDetailTypeNumChannels});
        table.insert(self.terrainDetailRequiredValueRanges, {g_currentMission.sowingValue, g_currentMission.sowingValue, g_currentMission.terrainDetailTypeFirstChannel, g_currentMission.terrainDetailTypeNumChannels});
        table.insert(self.terrainDetailRequiredValueRanges, {g_currentMission.sowingWidthValue, g_currentMission.sowingWidthValue, g_currentMission.terrainDetailTypeFirstChannel, g_currentMission.terrainDetailTypeNumChannels});
        table.insert(self.terrainDetailRequiredValueRanges, {g_currentMission.grassValue, g_currentMission.grassValue, g_currentMission.terrainDetailTypeFirstChannel, g_currentMission.terrainDetailTypeNumChannels});
        table.insert(self.terrainDetailProhibitValueRanges, {1, 2, g_currentMission.sprayFirstChannel, g_currentMission.sprayNumChannels});
        table.insert(self.terrainDetailProhibitValueRanges, {g_currentMission.sprayLevelMaxValue, g_currentMission.sprayLevelMaxValue, g_currentMission.sprayLevelFirstChannel, g_currentMission.sprayLevelNumChannels});
    end
    self.sprayer = {};
    self.sprayer.fillUnitIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.sprayer#fillUnitIndex"), 1);
    self.sprayer.unloadInfoIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.sprayer#unloadInfoIndex"), 1);
    self.sprayer.loadInfoIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.sprayer#loadInfoIndex"), 1);
    self.sprayer.dischargeInfoIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.sprayer#dischargeInfoIndex"), 1);
    self.sprayerDirtyFlag = self:getNextDirtyFlag();
end

function Irrigator:delete()
    for _, sprayerEffect in pairs(self.sprayerEffects) do
        EffectManager:deleteEffects(sprayerEffect.effects);
    end
    ------------------------> From FS15
    for k,sprayValve in pairs(self.sprayValves) do
        ParticleUtil.deleteParticleSystem(sprayValve.particleSystems)
    end
    ------------------------< From FS15
    for _, particleSystems in pairs(self.sprayParticleSystems) do
        ParticleUtil.deleteParticleSystems(particleSystems)
    end
    if self.isClient then
        SoundUtil.deleteSample(self.sampleSprayer);
        SoundUtil.deleteSample(self.sampleFill);
    end
end

function Irrigator:readUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        self.showFieldNotOwnedWarning = streamReadBool(streamId);
    end
end

function Irrigator:writeUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        streamWriteBool(streamId, self.showFieldNotOwnedWarning);
    end
end

function Irrigator:update(dt)
end

function Irrigator:updateTick(dt)
    self.isSprayerSpeedLimitActive = false;
-----------------------------------------------------------------	
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
-------------------------------------------------------------------	

--if self:getIsActive() then
        local showFieldNotOwnedWarning = false;
        if self.isServer then
            if self.turnOnDueToLoweredImplement ~= nil then
                if self.turnOnDueToLoweredImplement.object == nil then
                    self.turnOnDueToLoweredImplement = nil;
                end
            end
            if self.turnOnDueToLoweredImplement ~= nil then
                if self:getIsTurnedOn() == false then
                    self:setIsTurnedOn(true);
                end
                if self.turnOnDueToLoweredImplement.object.activateOnLowering then
                    if self.turnOnDueToLoweredImplement.object:getIsTurnedOn() == false then
                        self.turnOnDueToLoweredImplement.object:setIsTurnedOn(true);
                    end
                end
            end
            if self:getIsTurnedOn() then
                if not self:getIsTurnedOnAllowed(true) then
                    self:setIsTurnedOn(false);
                end
            end
            local tankActivators = {};
            Irrigator.getTankActivators(self:getRootAttacherVehicle(), tankActivators);
            if table.getn(tankActivators) > 0 then
                local doTurnOn = false;
                for _,tankActivator in pairs(tankActivators) do
                    local attacherVehicle = tankActivator.attacherVehicle;
                    if attacherVehicle ~= nil then
                        local implementIndex = attacherVehicle:getImplementIndexByObject(tankActivator);
                        local implement = attacherVehicle.attachedImplements[implementIndex];
                        local jointDescIndex = implement.jointDescIndex;
                        doTurnOn = doTurnOn or attacherVehicle.attacherJoints[jointDescIndex].moveDown;
                    end
                end
                self:setIsTurnedOn(doTurnOn);
            end
            if self.activateOnLowering and self.isLowered ~= nil then
                if self:isLowered(false) then
                    if self:getCanBeTurnedOn() and not self:getIsTurnedOn(true) then
                        self:setIsTurnedOn(true);
                    end
                else
                    self:setIsTurnedOn(false);
                end
            end
        end
        
        if self:getIsTurnedOn() and self.allowsSpraying and self.activable then
--print("self:getIsTurnedOn() 303")
            if self.isClient then 
                if self.sideskirtInRange then --and self:getIsActiveForSound() then
                  SoundUtil.playSample(self.sampleSprayer, 0, 0, nil);
                else
                  SoundUtil.stopSample(self.sampleSprayer);
                end
            end
            local readyToSpray = self:getIsReadyToSpray();
            self.isSprayerSpeedLimitActive = readyToSpray;
            local fillType = self:getUnitLastValidFillType(self.sprayer.fillUnitIndex);
            if fillType == FillUtil.FILLTYPE_UNKNOWN and self.fillUnits[self.sprayer.fillUnitIndex] ~= nil then
                for unitFillType,state in pairs(self.fillUnits[self.sprayer.fillUnitIndex].fillTypes) do
                    if unitFillType ~= FillUtil.FILLTYPE_UNKNOWN and state then
                        fillType = unitFillType;
                        break;
                    end
                end
            end
            --print("readyToSpray " .. tostring(readyToSpray))
            if readyToSpray then
                if self.isServer then
                    local litersPerSecond = self:getLitersPerSecond(fillType);
                    local usage = litersPerSecond * dt * 0.001;
                    local hasSpray, newFillType = self:getHasSpray(fillType, usage)
                    fillType = newFillType
                    if hasSpray then
                        local workAreas, showWarning, _ = self:getTypedNetworkAreas(WorkArea.AREATYPE_SPRAYER, true);
                        showFieldNotOwnedWarning = showWarning;
                        if (table.getn(workAreas) > 0) then
                            local pixels = self:processSprayerAreas(workAreas, fillType);
                            local ha = Utils.areaToHa(pixels, g_currentMission:getFruitPixelsToSqm());
                            g_currentMission.missionStats:updateStats("fertilizedHectares", ha);
                            g_currentMission.missionStats:updateStats("fertilizedTime", dt/(1000*60));
                            if self.lastSowingArea == nil then
                                g_currentMission.missionStats:updateStats("workedHectares", ha);
                                g_currentMission.missionStats:updateStats("workedTime", dt/(1000*60));
                            end
                            g_currentMission.missionStats:updateStats("sprayUsage", usage);
                        end
                    end
                end
            end
            if self.isClient then
            --print("update valve particle systems")
                -- update valve particle systems
                local foldAnimTime = self.foldAnimTime
            --print("foldAnimTime " .. tostring(foldAnimTime))
            --print("self.lastTurnedOn " .. tostring(self.lastTurnedOn))
                if (foldAnimTime ~= nil and foldAnimTime ~= self.lastSprayValveUpdateFoldTime) or self.lastTurnedOn == false then
                    self.lastSprayValveUpdateFoldTime = foldAnimTime;
                    self.lastTurnedOn = true;
                    if self:getAreEffectsVisible() then
                        if foldAnimTime ~= nil then
                            if self.sprayParticleSystems[fillType] ~= nil then
--print("self.sprayParticleSystems[fillType] ~= nil 351")
                                for _, ps in pairs(self.sprayParticleSystems[fillType]) do
                                    if foldAnimTime <= ps.foldMaxLimit and foldAnimTime >= ps.foldMinLimit then
                                        ParticleUtil.setEmittingState(ps, true);
                                    else
                                        ParticleUtil.setEmittingState(ps, false);
                                    end
                                end;
                            else
--print("self.sprayParticleSystems[fillType] == nil 360")
    for _,sprayValve in pairs(self.sprayValves) do
        ParticleUtil.setEmittingState(sprayValve.particleSystems, foldAnimTime <= sprayValve.foldMaxLimit and foldAnimTime >= sprayValve.foldMinLimit);
    end
                            end

------------------------> From FS15
-- update valve particle systems
--local foldAnimTime = self.foldAnimTime;
-- if foldAnimTime ~= nil and foldAnimTime ~= self.lastSprayValveUpdateFoldTime then
    -- self.lastSprayValveUpdateFoldTime = foldAnimTime;
    -- for _,sprayValve in pairs(self.sprayValves) do
        -- ParticleUtil.setEmittingState(sprayValve.particleSystems, foldAnimTime <= sprayValve.foldMaxLimit and foldAnimTime >= sprayValve.foldMinLimit);
    -- end
-- end
------------------------< From FS15
                            for _, sprayerEffect in pairs(self.sprayerEffects) do
                                readyToSpray = readyToSpray and (foldAnimTime > sprayerEffect.foldMinLimit);
                                if foldAnimTime <= sprayerEffect.foldMaxLimit and foldAnimTime >= sprayerEffect.foldMinLimit then
                                    EffectManager:setFillType(sprayerEffect.effects, fillType)
                                    EffectManager:startEffects(sprayerEffect.effects)
                                else
                                    EffectManager:stopEffects(sprayerEffect.effects);
                                end
                            end
                        else
                            if self.sprayParticleSystems[fillType] ~= nil then
--print("self.sprayParticleSystems[fillType] ~= nil 373")
                                for _, ps in pairs(self.sprayParticleSystems[fillType]) do
                                    ParticleUtil.setEmittingState(ps, true);
                                end;
                            else
--print("self.sprayParticleSystems[fillType] == nil 378")
                            end
                            for _, sprayerEffect in pairs(self.sprayerEffects) do
                                EffectManager:setFillType(sprayerEffect.effects, fillType)
                                EffectManager:startEffects(sprayerEffect.effects)
                            end
                        end
                    end
                end
            end
        else
            self:setIsTurnedOn(false)
            if self.isClient then
                for _, particleSystems in pairs(self.sprayParticleSystems) do
                    for _, ps in pairs(particleSystems) do
                        ParticleUtil.setEmittingState(ps, false);
                    end;
                end
    for _,sprayValve in pairs(self.sprayValves) do
        ParticleUtil.setEmittingState(sprayValve.particleSystems, false);
    end
                for _, sprayerEffect in pairs(self.sprayerEffects) do
                    EffectManager:stopEffects(sprayerEffect.effects);
                end
            end
        end
        self.lastTurnedOn = self:getIsTurnedOn();
        if self.isServer then
            if self.sowingMachineGroundContactFlag == nil then
                if showFieldNotOwnedWarning ~= self.showFieldNotOwnedWarning then
                    self.showFieldNotOwnedWarning = showFieldNotOwnedWarning;
                    self:raiseDirtyFlags(self.sprayerDirtyFlag);
                end
            end
        end
    -- end
    if self.isClient then
        if self.isFilling then
            if self:getIsActiveForSound(true) then
                SoundUtil.playSample(self.sampleFill, 0, 0, nil);
                SoundUtil.stop3DSample(self.sampleFill);
            else
                SoundUtil.stopSample(self.sampleFill);
                SoundUtil.play3DSample(self.sampleFill);
            end
        else
            SoundUtil.stopSample(self.sampleFill);
            SoundUtil.stop3DSample(self.sampleFill);
        end
    end
end

function Irrigator:draw()
    if self.isClient then
        if self.showFieldNotOwnedWarning then
            g_currentMission:showBlinkingWarning(g_i18n:getText("warning_youDontOwnThisField"));
        end
    end
end

function Irrigator:getDrawFirstFillText(superFunc)
    if self.isClient then
        if self:getIsActiveForInput(true) and not self.isAlwaysTurnedOn then
            if not self:getIsTurnedOnAllowed(true) and self:getUnitFillLevel(self.sprayer.fillUnitIndex) <= 0 and self:getUnitCapacity(self.sprayer.fillUnitIndex) > 0 then
                return true;
            end
        end
    end
    if superFunc ~= nil then
        return superFunc(self);
    end;
    return false;
end;

function Irrigator:onDetach(attacherVehicle, jointDescIndex)
-- Keep on even without tractor
    --print("Irrigator:onDetach " .. tostring(self:getIsTurnedOn()))
    --print("Irrigator:onDetach " .. tostring(attacherVehicle))
    --print("Irrigator:onDetach " .. tostring(jointDescIndex))
    if self.isRollingUp then
      --print("Irrigator:setIsTurnedOn")
      self:setIsTurnedOn(true);
      self.isRollingUp = true
    end
end

function Irrigator:stopMotor(noEventSend)
-- Keep on even when stopping tractor attachedImplements
  -- print("self " .. tostring(self))
  -- print("self " .. tostring(self.typeName))
  for _,implement in pairs(self.attachedImplements) do
      if implement.object ~= nil then
          -- print("implement.object " .. tostring(implement.object) ) 
          -- print("implement " .. tostring(implement) )
          -- print("implement.object " .. tostring(implement.object.typeName) ) 
          -- print("implement " .. tostring(implement.typeName) )
          --if implement.object.typeName == "FS17_Optima_1036_v1_2_final.optima1036" then
          if implement.object.typeDesc == "Optima_1036 Optima_1036" and implement.object.isRollingUp then
            implement.object:setIsTurnedOn(true);
            implement.object.isRollingUp = true
          end
      end
  end
end
Drivable.stopMotor = Utils.appendedFunction(Drivable.stopMotor, Irrigator.stopMotor);

function Irrigator:onDeactivate()
    self.showFieldNotOwnedWarning = false;
end

function Irrigator:onDeactivateSounds()
    if self.isClient then
        SoundUtil.stopSample(self.sampleSprayer, true);
    end
end

function Irrigator:getHasSpray(fillType, usage)
--print("Irrigator:getHasSpray(fillType, usage)")
    local hasSpray = false;
    if not hasSpray and self:getIsHired() and self:aiAllowedToRefill() then
        if fillType == FillUtil.FILLTYPE_LIQUIDMANURE or
           fillType == FillUtil.FILLTYPE_DIGESTATE or
           (fillType == FillUtil.FILLTYPE_UNKNOWN and (self:allowUnitFillType(self.sprayer.fillUnitIndex, FillUtil.FILLTYPE_LIQUIDMANURE) or self:allowUnitFillType(self.sprayer.fillUnitIndex, FillUtil.FILLTYPE_DIGESTATE))) then
            if g_currentMission.missionInfo.helperSlurrySource == 2 then -- buy manure
                hasSpray = true;
                if g_currentMission.economyManager:getCostPerLiter(FillUtil.FILLTYPE_LIQUIDMANURE) then
                    fillType = FillUtil.FILLTYPE_LIQUIDMANURE;
                else
                    fillType = FillUtil.FILLTYPE_DIGESTATE;
                end
                local price = usage * g_currentMission.economyManager:getCostPerLiter(fillType) * 1.5  -- increase price if AI is active to reward the player's manual work
                g_currentMission.missionStats:updateStats("expenses", price);
                g_currentMission:addSharedMoney(-price, "purchaseFertilizer");
            elseif g_currentMission.missionInfo.helperSlurrySource > 2 then
                local trigger = g_currentMission.liquidManureTriggers[g_currentMission.missionInfo.helperSlurrySource-2].trigger
                if trigger.fillLevel > 0 then
                    hasSpray = true;
                    fillType = trigger.fillType
                    trigger:setFillLevel(trigger.fillLevel-usage)
                end
            end
        elseif fillType == FillUtil.FILLTYPE_MANURE or (fillType == FillUtil.FILLTYPE_UNKNOWN and self:allowUnitFillType(self.sprayer.fillUnitIndex, FillUtil.FILLTYPE_MANURE)) then
            if g_currentMission.missionInfo.helperManureSource == 2 then -- buy manure
                hasSpray = true;
                fillType = FillUtil.FILLTYPE_MANURE;
                local price = usage * g_currentMission.economyManager:getCostPerLiter(fillType) * 1.5  -- increase price if AI is active to reward the player's manual work
                g_currentMission.missionStats:updateStats("expenses", price);
                g_currentMission:addSharedMoney(-price, "purchaseFertilizer");
            elseif g_currentMission.missionInfo.helperManureSource > 2 then
                local manureHeap = g_currentMission.manureHeaps[g_currentMission.missionInfo.helperManureSource-2].manureHeap
                if manureHeap:removeManure(usage) > 0 then
                    hasSpray = true;
                    fillType = FillUtil.FILLTYPE_MANURE
                end
            end
        elseif fillType == FillUtil.FILLTYPE_FERTILIZER or
               fillType == FillUtil.FILLTYPE_LIQUIDFERTILIZER or
               fillType == FillUtil.FILLTYPE_WATER or
              (fillType == FillUtil.FILLTYPE_UNKNOWN and (self:allowUnitFillType(self.sprayer.fillUnitIndex, FillUtil.FILLTYPE_LIQUIDFERTILIZER) or self:allowUnitFillType(self.sprayer.fillUnitIndex, FillUtil.FILLTYPE_FERTILIZER) or self:allowUnitFillType(self.sprayer.fillUnitIndex, FillUtil.FILLTYPE_WATER))) then
            if g_currentMission.missionInfo.helperBuyFertilizer then
                hasSpray = true;
                if self:allowUnitFillType(self.sprayer.fillUnitIndex, FillUtil.FILLTYPE_LIQUIDFERTILIZER) then
                    fillType = FillUtil.FILLTYPE_LIQUIDFERTILIZER;
                elseif self:allowUnitFillType(self.sprayer.fillUnitIndex, FillUtil.FILLTYPE_WATER) then
                    fillType = FillUtil.FILLTYPE_WATER;
                else
                    fillType = FillUtil.FILLTYPE_FERTILIZER;
                end
                local price = usage * g_currentMission.economyManager:getCostPerLiter(fillType) * 1.5  -- increase price if AI is active to reward the player's manual work
                g_currentMission.missionStats:updateStats("expenses", price);
                g_currentMission:addSharedMoney(-price, "purchaseFertilizer");
            end
        else
        end
    end
    if not hasSpray then
        local sprayUsageVehicle = self
        local newFillType = fillType;
        if self:getUnitFillLevel(self.sprayer.fillUnitIndex) == 0 then
            sprayUsageVehicle, newFillType = Irrigator.findAttachedSprayerTank(self:getRootAttacherVehicle(), self:getUnitFillTypes(self.sprayer.fillUnitIndex), self.needsTankActivation);
        end
        local oldFillLevel = 0
        if sprayUsageVehicle ~= nil then
            fillType = newFillType;
            oldFillLevel = sprayUsageVehicle:getUnitFillLevel(sprayUsageVehicle.sprayer.fillUnitIndex);
            sprayUsageVehicle:setUnitFillLevel(sprayUsageVehicle.sprayer.fillUnitIndex, oldFillLevel - usage, fillType, false, sprayUsageVehicle.fillVolumeUnloadInfos[sprayUsageVehicle.sprayer.unloadInfoIndex]);
        end
        hasSpray = oldFillLevel > 0;
    end
    if not hasSpray and self:getIsHired() and self.stopAiOnEmpty then
        local rootVehicle = self:getRootAttacherVehicle()
        rootVehicle:stopAIVehicle(AIVehicle.STOP_REASON_OUT_OF_FILL)
    end
--print("Irrigator:getHasSpray(fillType, usage) " .. tostring(hasSpray) .. " - " .. tostring(fillType))
    return hasSpray, fillType
end

function Irrigator:aiAllowedToRefill(superFunc)
    if self.needsTankActivation then
        local sprayUsageVehicle, _ = Irrigator.findAttachedSprayerTank(self:getRootAttacherVehicle(), self:getUnitFillTypes(self.sprayer.fillUnitIndex), false, true);
        if sprayUsageVehicle == nil then
            return false;
        end;
    end;
    if superFunc ~= nil then
        return superFunc(self);
    end
    return true;
end;

function Irrigator:getCanAddHelpButtonText(superFunc)
    -- if self.activateOnLowering then
        -- return false;
    -- end;
    -- if superFunc ~= nil then
        -- return superFunc(self);
    -- end
    -- return true;
-- Disable turn on help msg
    return false
end;

function Irrigator.getTankActivators(currentVehicle, results)
    if currentVehicle.needsTankActivation then
        table.insert(results, currentVehicle);
    end
    for _,implement in pairs(currentVehicle.attachedImplements) do
        if implement.object ~= nil then
            Irrigator.getTankActivators(implement.object, results);
        end
    end
end

function Irrigator:getIsTurnedOnAllowed(superFunc, isTurnedOn)
    if not self.allowsSpraying then
        return false;
    end
    if self.activateOnLowering and self.isLowered ~= nil then
        return self:isLowered(false);
    end
    -- if sowingMachine is involved dismiss sprayer complains
    if isTurnedOn and self.sowingMachineGroundContactFlag ~= nil then
        return superFunc(self, isTurnedOn);
    end
    if isTurnedOn and self:getUnitFillLevel(self.sprayer.fillUnitIndex) <= 0 then
        if self:getIsHired() then
            return true;
        end
        -- try to find tank
        local sprayerTank, fillType = Irrigator.findAttachedSprayerTank(self:getRootAttacherVehicle(), self:getUnitFillTypes(self.sprayer.fillUnitIndex), self.needsTankActivation);
        if sprayerTank ~= nil and fillType ~= nil then
            return true;
        else
            return false;
        end
    end
    return true;
end

function Irrigator:onTurnedOn(noEventSend)
--print("Irrigator:onTurnedOn(noEventSend)")
    -- if self.isClient then
 ------------------------> From FS15
 self.lastSprayValveUpdateFoldTime = nil;
 local isTurnedOn = self:getIsTurnedOn()
 
 if not self.sideskirtInRange and not self.isRollingUp then
  --print("Irrigator:onTurnedOn Don't turn on when in tractor")
  self.isRollingUp = false
  self:setIsTurnedOn(false)
  return
 end
 
 if not isTurnedOn or self.foldAnimTime == nil then
     -- If the sprayer is foldable, the spray valves are only turned on within the update loop
     for _,sprayValve in pairs(self.sprayValves) do
         ParticleUtil.setEmittingState(sprayValve.particleSystems, isTurnedOn);
     end
 end    
 ------------------------< From FS15
        if self.foldAnimTime == nil then
            -- If the sprayer is foldable, the spray valves are only turned on within the update loop
            for _, particleSystems in pairs(self.sprayParticleSystems) do
                for _, particleSystem in pairs(particleSystems) do
                    ParticleUtil.setEmittingState(particleSystem, false);
                end;
            end
            local fillType = self:getUnitLastValidFillType(self.sprayer.fillUnitIndex);
            if fillType == FillUtil.FILLTYPE_UNKNOWN then
                fillType = self:getFirstEnabledFillType();
            end
            for _, sprayerEffect in pairs(self.sprayerEffects) do
                EffectManager:setFillType(sprayerEffect.effects, fillType)
                EffectManager:startEffects(sprayerEffect.effects)
            end
        end
        if self.sprayingAnimationName ~= "" and self.playAnimation ~= nil then
            self:playAnimation(self.sprayingAnimationName, 1, self:getAnimationTime(self.sprayingAnimationName), true);
        end
    -- end
end

function Irrigator:onTurnedOff(noEventSend)
 if not self.sideskirtInRange and self.isRollingUp and self:getAnimationTime(self.drumUnroll.name) > 0.001 then
  self.isRollingUp = true
  self:setIsTurnedOn(true)
  return
 end
    if self.isClient then
        for _, particleSystems in pairs(self.sprayParticleSystems) do
            for _, particleSystem in pairs(particleSystems) do
                ParticleUtil.setEmittingState(particleSystem, false);
            end
        end
        for _, sprayerEffect in pairs(self.sprayerEffects) do
            EffectManager:stopEffects(sprayerEffect.effects);
        end
        SoundUtil.stopSample(self.sampleSprayer);
        if self.sprayingAnimationName ~= "" and self.stopAnimation ~= nil then
            self:stopAnimation(self.sprayingAnimationName, true);
        end
    end
end

function Irrigator:onAiTurnOn()
    if self.setIsTurnedOn ~= nil then
        self:setIsTurnedOn(true, false);
    end
end

function Irrigator:onAiTurnOff()
    if self.setIsTurnedOn ~= nil then
        self:setIsTurnedOn(false, false);
    end
end

function Irrigator:onAiLower()
    if self.setIsTurnedOn ~= nil then
        self:setIsTurnedOn(true, false);
    end
end

function Irrigator:onAiRaise()
    if self.setIsTurnedOn ~= nil then
        self:setIsTurnedOn(false, false);
    end
end

function Irrigator.findAttachedSprayerTank(currentVehicle, fillTypes, needsTankActivation, ignoreFillLevel)
local key1 = string.format("%d - %s - %s", table.getn(fillTypes), needsTankActivation, ignoreFillLevel);
local key2 = string.format("%s - %s - %s", currentVehicle.isSprayerTank , currentVehicle.getFillLevel , currentVehicle.setFillLevel);
--print(key1 .. " / " .. key2)
    if currentVehicle.isSprayerTank and currentVehicle.getFillLevel ~= nil and currentVehicle.setFillLevel ~= nil then
        if (not needsTankActivation or (currentVehicle.getIsTurnedOn ~= nil and currentVehicle:getIsTurnedOn())) then
            local fillUnit = currentVehicle.fillUnits[currentVehicle.sprayer.fillUnitIndex];
            for fillType,state in pairs(fillTypes) do
                if state and fillUnit.fillTypes[fillType] then
                    if (fillUnit.currentFillType == fillType and fillUnit.fillLevel > 0) or ignoreFillLevel then
                        return currentVehicle, fillType;
                    end
                end
            end
        end
    end
    for _,implement in pairs(currentVehicle.attachedImplements) do
        if implement.object ~= nil then
            local ret1, ret2 = Irrigator.findAttachedSprayerTank(implement.object, fillTypes, needsTankActivation, ignoreFillLevel);
            if ret1 ~= nil and ret2 ~= nil then
                return ret1, ret2;
            end
        end
    end
    return nil;
end

function Irrigator:loadWorkAreaFromXML(superFunc, workArea, xmlFile, key)
    local retValue = true;
    if superFunc ~= nil then
        retValue = superFunc(self, workArea, xmlFile, key)
    end
    if workArea.type == WorkArea.AREATYPE_DEFAULT then
        workArea.type = WorkArea.AREATYPE_SPRAYER;
    end
    return retValue;
end

function Irrigator:getIsReadyToSpray()
    if self.lastSowingArea ~= nil then
        return self.lastSowingArea > 0;
    end
    return true;
end

function Irrigator:getAreEffectsVisible()
    return true;
end

function Irrigator:getLitersPerSecond(fillType)
    local scale = Utils.getNoNil(self.sprayUsageScale.fillTypeScales[fillType], self.sprayUsageScale.default)
    local litersPerSecond = 1
    local sprayTypeIndex = Irrigator.fillTypeToSprayType[fillType]
    if sprayTypeIndex ~= nil then
        local spray = Irrigator.sprayTypeIndexToDesc[sprayTypeIndex]
        if spray ~= nil then
            litersPerSecond = spray.litersPerSecond
        end
    end
    --print("self.currentRollingUpSpeed " .. self.currentRollingUpSpeed)
    return scale * litersPerSecond * -self.currentRollingUpSpeed * self.sprayUsageScale.workingWidth
end

function Irrigator:doCheckSpeedLimit(superFunc)
    local parent = false;
    if superFunc ~= nil then
        parent = superFunc(self);
    end
    return parent or self.isSprayerSpeedLimitActive;
end

function Irrigator.getDefaultSpeedLimit()
    return 15;
end

function Irrigator:processSprayerAreas(workAreas, fillType)
    local sprayType = 1;
    if fillType == FillUtil.FILLTYPE_MANURE then
        sprayType = 2;
    end
    local totalPixels = 0;
    local numAreas = table.getn(workAreas);
    for i=1, numAreas do
        local x = workAreas[i][1];
        local z = workAreas[i][2];
        local x1 = workAreas[i][3];
        local z1 = workAreas[i][4];
        local x2 = workAreas[i][5];
        local z2 = workAreas[i][6];
        local pixels, pixelsTotal;        
        if self.cultivatorGroundContactFlag ~= nil and self.sowingMachineGroundContactFlag == nil then
            pixels, pixelsTotal = Utils.updateSprayArea(x, z, x1, z1, x2, z2, g_currentMission.cultivatorValue, sprayType);
        else
            pixels, pixelsTotal = Utils.updateSprayArea(x, z, x1, z1, x2, z2, nil, sprayType);
        end
        totalPixels = totalPixels + pixels;
    end;
    return totalPixels;
end;

function Irrigator:mouseEvent(posX, posY, isDown, isUp, button)
end;

function Irrigator:keyEvent(unicode, sym, modifier, isDown)
end;
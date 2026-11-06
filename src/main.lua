local UEHelpers = require("UEHelpers")
local enabled = true
local physicsEnabled = true
local physicsStatsReported = false
local current = nil
local replacement = nil
local materialGeneration = 0
local gazeEnabled = true
local eyePhase = 0
local eyeUpdates = 0
-- Gaze follows the hero's rig: control values use CTRL_C_eye's range, and the degrees per unit come from
-- his DNA (FACIAL_L_Eye / FACIAL_R_Eye against the eyeLook controls). Each morph is built at a fixed angle.
local gazeDegrees = {
    L={left=42.41, right=37.59, up=30.02, down=31.19},
    R={left=37.58, right=42.42, up=30.04, down=31.57},
}
local morphYawDegrees, morphPitchDegrees = 30, 25
local gazeNames = nil
local gazeX, gazeY = 0, 0
local gazeFromX, gazeFromY, gazeToX, gazeToY = 0, 0, 0, 0
local gazeStart, gazeDuration = nil, 0
local nextGazeAt = 0
local gazeSaccades = 0
local gazeTestStep = nil
local gazeTestAt = 0
local gazeTestPoses = {{0.5,0},{-0.5,0},{0,0.6},{0,-0.6},{0.35,0.35},{0,0}}
local gazeSides = {"L","R"}
local blinkWeight = 0
local liveGaze = false
local liveQuietSince = 0
local nextLiveCheckAt = 0
local liveCurveNames = nil
local liveCheckFailed = false
local liveReported = false
-- F6 switches between the 90% body and the hero's normal size. The saved choice is read further down.
local visualScale = 0.90
local rootMotionScale = 1 / visualScale
local blinkEnabled = true
local blinkName = nil
local blinkStart = nil
local blinkSlow = 1
local blinkQueued = false
local nextBlinkAt = 0
local blinkCount = 0
local blinkClose, blinkHold, blinkOpen = 0.075, 0.035, 0.14
local gripCheckTicks = 0
local materialPaths = {
    "/Game/Mods/Maixiaowen/Materials/M_ink_Prop_2.M_ink_Prop_2",
    "/Game/Mods/Maixiaowen/Materials/MT_F_Hack_ink_S_012_Mask.MT_F_Hack_ink_S_012_Mask",
    "/Game/Mods/Maixiaowen/Materials/MT_F_Hack_ink_S_012_Upper_01_mb.MT_F_Hack_ink_S_012_Upper_01_mb",
    "/Game/Mods/Maixiaowen/Materials/MT_F_Head_Hair_S_012_HD_Hair_02.MT_F_Head_Hair_S_012_HD_Hair_02",
    "/Game/Mods/Maixiaowen/Materials/MT_F_Hack_ink_S_012_Upper_02_mb.MT_F_Hack_ink_S_012_Upper_02_mb",
    "/Game/Mods/Maixiaowen/Materials/MT_F_Hack_ink_S_012_Head.MT_F_Hack_ink_S_012_Head",
    "/Game/Mods/Maixiaowen/Materials/MT_F_Hack_ink_S_Eye_Shadows.MT_F_Hack_ink_S_Eye_Shadows",
    "/Game/Mods/Maixiaowen/Materials/M_EyeRefractive_Inst.M_EyeRefractive_Inst",
    "/Game/Mods/Maixiaowen/Materials/MT_F_Head_Hair_S_012_HD_Hair_01.MT_F_Head_Hair_S_012_HD_Hair_01",
    "/Game/Mods/Maixiaowen/Materials/MT_F_Hack_ink_S_012_Lower_mb.MT_F_Hack_ink_S_012_Lower_mb",
    "/Game/Mods/Maixiaowen/Materials/Signal_lamp_E_HD.Signal_lamp_E_HD",
}
local hiddenNames = {
    CharacterMesh0 = true, Hun_Hat = true, Hun_Hat01 = true,
    meshhead = true, meshBrowLashCard = true, meshBand = true,
    CA_Hun_Hair = true, CA_Hun_UpperCloth = true, CA_Hun_Skirt = true, CA_Hun_Cape = true,
}
local lastError = ""

local function valid(object)
    return object and object:IsValid()
end

local function log(message)
    print("[MaixiaowenInk] " .. message .. "\n")
end

local function load(path)
    local object = StaticFindObject(path)
    if not valid(object) then
        local system = UEHelpers.GetKismetSystemLibrary()
        local softPath = system:MakeSoftObjectPath(path)
        local softReference = system:Conv_SoftObjPathToSoftObjRef(softPath)
        object = system:LoadAsset_Blocking(softReference)
    end
    return object
end

-- A leader-pose follower reads morph weights from its leader, so both components carry the value.
local function setBlinkWeight(weight)
    blinkWeight = weight
    if not current then return end
    if not blinkName then blinkName = FName("Blink") end
    local remove = weight <= 0
    if valid(current.driver) then current.driver:SetMorphTarget(blinkName, weight, remove) end
    if valid(current.display) then current.display:SetMorphTarget(blinkName, weight, remove) end
end

local function clearGaze()
    if not current or not gazeNames then return end
    for _, name in ipairs(gazeNames) do
        if valid(current.driver) then current.driver:SetMorphTarget(name.fname, 0, true) end
        if valid(current.display) then current.display:SetMorphTarget(name.fname, 0, true) end
    end
    current.gazeSent = nil
end

local waistSockets = {
    Knife="Pt_Knife_Back_Socket", KnifeScab="Pt_KnifeScabbard_Back_Socket",
}

local function sameLocation(a,b)
    return math.abs(a.X-b.X)<0.01 and math.abs(a.Y-b.Y)<0.01 and math.abs(a.Z-b.Z)<0.01
end

local function restoreWaistKnife(state)
    local component=state.component
    if state.adjusted and valid(component) and sameLocation(component.RelativeLocation,state.adjusted) then
        component:K2_SetRelativeLocation(state.original,false,{},true)
    end
    state.original,state.adjusted=nil,nil
end

local function updateWaistKnife(active)
    for name,state in pairs(current.waistKnife) do
        local component=state.component
        if not active or not valid(component) or component:GetAttachSocketName():ToString()~=waistSockets[name] then
            restoreWaistKnife(state)
        elseif not state.adjusted or not sameLocation(component.RelativeLocation,state.adjusted) then
            local relative=component.RelativeLocation
            local original={X=relative.X,Y=relative.Y,Z=relative.Z}
            local forward=current.pawn:GetActorForwardVector()
            local socket=current.driver:GetSocketTransform(FName(waistSockets[name]),0)
            local mathLibrary=StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
            local origin=socket.Translation
            -- Fitted at 90% scale; the offset grows with the body so the fit is the same at either size.
            local fit=visualScale/0.90
            local moved={X=origin.X-5.8*fit*forward.X,Y=origin.Y-5.8*fit*forward.Y,Z=origin.Z-1.8*fit}
            local offset=mathLibrary:InverseTransformLocation(socket,moved)
            local adjusted={X=original.X+offset.X,Y=original.Y+offset.Y,Z=original.Z+offset.Z}
            component:K2_SetRelativeLocation(adjusted,false,{},true)
            state.original,state.adjusted=original,adjusted
            if not state.reported then log("Waist clearance applied to "..name) end
            state.reported=true
        end
    end
end

local function guardedWaistKnife(active)
    local ok,err=pcall(updateWaistKnife,active)
    if not ok and current.waistKnifeError~=tostring(err) then
        current.waistKnifeError=tostring(err)
        log("Waist clearance failed: "..current.waistKnifeError)
    end
end

local function restore()
    if not current then return end
    guardedWaistKnife(false)
    setBlinkWeight(0)
    clearGaze()
    blinkStart = nil
    if valid(current.pawn) and math.abs(current.pawn.AnimRootMotionTranslationScale - rootMotionScale) < 0.001 then
        current.pawn.AnimRootMotionTranslationScale = 1
    end
    if valid(current.driver) then
        current.driver:SetRelativeScale3D(current.originalDriverScale)
    end
    if valid(current.display) then
        current.display.ClothBlendWeight = 0
        current.display.bDisableClothSimulation = true
        if not valid(current.originalMesh) and current.originalMeshPath then
            current.originalMesh = load(current.originalMeshPath)
        end
        if valid(current.originalMesh) then current.display:SetSkeletalMeshAsset(current.originalMesh) end
        for i, material in ipairs(current.originalMaterials) do
            if valid(material) then current.display:SetMaterial(i - 1, material) end
        end
        current.display:SetAllowClothActors(current.originalAllowCloth)
        current.display.bDisableClothSimulation = current.originalDisableCloth
        current.display.ClothBlendWeight = current.originalClothBlend
        current.display:SetLeaderPoseComponent(current.driver, true, current.originalFollowerTick)
        current.display:SetComponentTickEnabled(current.originalDisplayTick)
        current.display:ForceClothNextUpdateTeleportAndReset()
    end
    for _, entry in ipairs(current.visibility) do
        if valid(entry.component) then
            entry.component:SetVisibility(entry.visible, false)
            entry.component:SetHiddenInGame(entry.hidden, false)
        end
    end
    if valid(current.driver) then
        current.driver.VisibilityBasedAnimTickOption = current.originalTickOption
    end
    current = nil
    log("Original appearance restored")
end

local function updatePhysics(reset)
    if not current or not valid(current.display) then return end
    current.display.bDisableClothSimulation = not physicsEnabled
    current.display.ClothBlendWeight = physicsEnabled and 1 or 0
    if physicsEnabled then
        current.display:ResumeClothingSimulation()
        if reset then current.display:ForceClothNextUpdateTeleportAndReset() end
    else
        current.display:SuspendClothingSimulation()
    end
end

-- Scales the animation driver, so hand weapons, scabbards, effects and hit boxes on its sockets stay
-- with the visible follower. Mesh scale also shrinks root motion, which the translation scale cancels.
local function updateBodyScale()
    local scale = current.originalDriverScale
    local wanted = scale.X * visualScale
    if math.abs(current.driver.RelativeScale3D.X - wanted) > 0.0001 then
        current.driver:SetRelativeScale3D({X=wanted,Y=scale.Y*visualScale,Z=scale.Z*visualScale})
        -- Cloth particles are in world space; restart them at the new size instead of letting them snap.
        if physicsEnabled and valid(current.display) then current.display:ForceClothNextUpdateTeleportAndReset() end
        log("Body scale applied to animation driver: " .. tostring(wanted))
    end
    if valid(current.pawn) and math.abs(current.pawn.AnimRootMotionTranslationScale - 1) < 0.001 then
        current.pawn.AnimRootMotionTranslationScale = rootMotionScale
    end
end

local function reportGrip()
    local socket = FName("weapon_r")
    local a, b = current.driver:GetSocketLocation(socket), current.display:GetSocketLocation(socket)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    log(string.format("Grip check: weapon_r gap %.2f cm, driver scale %.3f", math.sqrt(dx*dx+dy*dy+dz*dz), current.driver.RelativeScale3D.X))
    local system = UEHelpers.GetKismetSystemLibrary()
    log("Skin cache mode " .. tostring(system:GetConsoleVariableIntValue("r.SkinCache.Mode")) .. ", compile shaders " .. tostring(system:GetConsoleVariableIntValue("r.SkinCache.CompileShaders")))
end

-- Index is material slot + 1. Skin slots use PBZ's native subsurface material.
local definitions07 = {
{Albedo="T_Maix07_Props_C",Normal="T_Maix07_Props_N",Mix="T_Maix07_Props_ARM"},
{Albedo="T_Maix07_Mask_C",Normal="T_F_Hack_ink_S_012_Mask_PCUI_N_dcdb86",Mix="T_ARM_T_F_Hack_ink_S_012_Mask_PCUI_MRA_225221"},
{Albedo="T_Maix07_Upper01_C",Normal="T_Maix07_Upper01_N",Mix="T_Maix07_Upper01_ARM"},
{hair=true,rootColor=0.28,tipColor=0.48},
{Albedo="T_Maix07_Upper02_C",Normal="T_Maix07_Upper02_N",Mix="T_Maix07_Upper02_ARM"},
{Albedo="T_MaixSkin_Scalp_v05",Normal="T_F_Hack_ink_S_012_Head_N_8bd2fa",Mix="T_Maix07_Head_ARM",SCMT_Map="T_Maix07_Head_SCMT",nativeSkin=true},
{occlusion=true,shadowTint=0.78,scalars={["Blur Size"]=0.04,ShadowMultiply=0,TopShadow_Radius=0.74,TopShadow_Hardness=0.534}},
{eye=true,iris="T_Maix07_Iris",scalars={
    PupilScale=0.96,IrisUVRadius=0.149,IrisBrightness=0.61,IrisSaturation=1.55,
    LimbusDarkScale=1.55,LimbusDarkPower=4,ScaleIrisWithinMask=1,
    RefractionDepthScale=0.9,POMHeightRatio=0.10,AOinBaseColorPower=0,
    IrisRoughness=0.055,IrisSpecularity=0.65,ScleraRoughness=0.055,
    ScleraSpecularity=0.5,ScleraBrightness=0.62,ScleraPower=1,VeinsOpacity=0.12}},
{hair=true,rootColor=0.52,tipColor=0.82},
{Albedo="T_Maix07_Lower_C",Normal="T_Maix07_Lower_N",Mix="T_Maix07_Lower_ARM"},
{Albedo="T_Signal_lamp_001_C_HD_25cd11",Normal="T_Signal_lamp_001_N_HD_fb2a8c",Mix="T_ARM_T_Signal_lamp_001_MRA_HD_83f151"},
{Albedo="T_Maix07_Upper02_C",Normal="T_Maix07_Upper02_N",Mix="T_Maix07_SkinHand_ARM",SCMT_Map="T_Maix07_SkinHand_SCMT",nativeSkin=true},
{Albedo="T_Maix07_Upper01_C",Normal="T_Maix07_Upper01_N",Mix="T_Maix07_SkinBody_ARM",SCMT_Map="T_Maix07_SkinBody_SCMT",nativeSkin=true},
{tear=true},
{hair=true,rootColor=0.02,tipColor=0.01},
{hair=true,rootColor=0.026,tipColor=0.009,scatter=0.15,specular=0.16}
}
-- Settings files live next to this script.
local scriptFolder = ""
do
    local ok, source = pcall(function() return debug.getinfo(1, "S").source end)
    local folder = ok and source and source:gsub("^@", ""):match("^(.*[/\\])")
    if folder then scriptFolder = folder end
end
local meshPath = "/Game/Mods/Maixiaowen/SK_Maixiaowen_Ink.SK_Maixiaowen_Ink"
-- The F6 size choice survives a restart.
local scaleFile = scriptFolder .. "scale.txt"
do
    local ok, file = pcall(io.open, scaleFile, "r")
    if ok and file then
        local saved = tonumber(file:read("*l") or "")
        file:close()
        if saved and math.abs(saved - 1) < 0.001 then visualScale, rootMotionScale = 1, 1 end
    end
end

local function saveScale()
    local ok, file = pcall(io.open, scaleFile, "w")
    if ok and file then
        file:write(string.format("%.2f\n", visualScale))
        file:close()
    else
        log("Could not save body scale to " .. scaleFile)
    end
end

-- Development-only material reload and fixed cameras. Called solely from gameThreadTick.
local eyeTune = {}
local eyeTuneLimits = {
    PupilScale={0.5,1.4}, IrisBrightness={0.05,1.5}, IrisSaturation={0,3},
    IrisUVRadius={0.10,0.20}, ScaleIrisWithinMask={0.7,1.3},
    LimbusDarkScale={0,3}, LimbusDarkPower={0.5,8},
    RefractionDepthScale={0,1.5}, POMHeightRatio={0,0.8}, AOinBaseColorPower={0,1.5},
    IrisRoughness={0.02,0.3}, ScleraRoughness={0.02,0.3},
    IrisSpecularity={0,1}, ScleraSpecularity={0,1},
    ScleraBrightness={0.2,1}, ScleraPower={0.5,2}, VeinsOpacity={0,1},
    ShadowTint={0,1}, BlurSize={0,0.3}, ShadowMultiply={0,1},
    TopShadowRadius={0,1}, TopShadowHardness={0,1},
}
local eyeTuneTextures = {
    IrisBaseColor={Lobby="/Game/Mods/Maixiaowen/Textures/T_Maix07_Iris.T_Maix07_Iris",
        Original="/Game/Mods/Maixiaowen/Textures/T_MaixEye_Iris.T_MaixEye_Iris"},
    IrisAO={White="/Game/Mods/Maixiaowen/Textures/T_MaixEye_White.T_MaixEye_White",
        Native="/Game/Test/Zero_LookDev/ZeroFile/Character/Hun/Head/Textures/T_ZeroHun_Eye_AO.T_ZeroHun_Eye_AO"},
}
local eyeTuneFile = scriptFolder .. "eye_tune.txt"
local function eyeSetting(name, fallback)
    if eyeTune[name]~=nil then return eyeTune[name] end
    local value=definitions07[8].scalars[name]
    if value~=nil then return value end
    return fallback
end

local function applyEyeTune(tune)
    if not enabled or not current or not valid(current.display) then return end
    -- Resolve both MIDs at the time of use. Neither is retained across a mesh change.
    local eye=current.display:GetMaterial(7)
    local shell=current.display:GetMaterial(6)
    if not valid(eye) or not valid(shell) then return end
    local textures={}
    for name,choices in pairs(eyeTuneTextures) do
        local choice=tune[name] or (name=="IrisBaseColor" and "Lobby" or "White")
        local texture=load(choices[choice])
        if not valid(texture) then error("Eye tune texture missing: "..name.."="..choice) end
        textures[name]=texture
    end
    for name,value in pairs(definitions07[8].scalars) do
        eye:SetScalarParameterValue(FName(name),tune[name] or value)
    end
    for name,texture in pairs(textures) do
        eye:SetTextureParameterValue(FName(name),texture)
    end
    local shadow=definitions07[7]
    local tint=tune.ShadowTint or shadow.shadowTint
    shell:SetVectorParameterValue(FName("ShadowTint"),{R=tint,G=tint,B=tint,A=1})
    shell:SetScalarParameterValue(FName("Blur Size"),tune.BlurSize or shadow.scalars["Blur Size"])
    shell:SetScalarParameterValue(FName("ShadowMultiply"),tune.ShadowMultiply or shadow.scalars.ShadowMultiply)
    shell:SetScalarParameterValue(FName("TopShadow_Radius"),tune.TopShadowRadius or shadow.scalars.TopShadow_Radius)
    shell:SetScalarParameterValue(FName("TopShadow_Hardness"),tune.TopShadowHardness or shadow.scalars.TopShadow_Hardness)
end

local function reloadEyeTune()
    local file,why=io.open(eyeTuneFile,"r")
    if not file then log("Eye tune file unavailable: "..tostring(why)) return end
    local parsed,count={},0
    for line in file:lines() do
        line=line:gsub("[#;].*$", "")
        if line:match("%S") then
            local name,value=line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if not name then file:close();log("Eye tune rejected: malformed line") return end
            local limits=eyeTuneLimits[name]
            if limits then
                value=tonumber(value)
                if not value or value~=value or value<limits[1] or value>limits[2] then
                    file:close();log("Eye tune rejected: range for "..name) return
                end
            elseif eyeTuneTextures[name] then
                if not eyeTuneTextures[name][value] then file:close();log("Eye tune rejected: texture "..name) return end
            else file:close();log("Eye tune rejected: unknown key "..name) return end
            parsed[name]=value
            count=count+1
        end
    end
    file:close()
    applyEyeTune(parsed)
    eyeTune=parsed
    local values={}
    for name,value in pairs(parsed) do table.insert(values,name.."="..tostring(value)) end
    table.sort(values)
    log("Eye tune applied: "..count.." values; "..table.concat(values,", "))
end

local reviewCamera, reviewView = nil,nil
local reviewMode,reviewTarget,reviewForward=0,nil,nil
local function cycleEyeCamera()
    local pawn=UEHelpers.GetPlayer()
    local controller=UEHelpers.GetPlayerController()
    if not valid(pawn) or not valid(controller) then return end
    reviewMode=(reviewMode+1)%3
    if reviewMode==0 then
        if valid(reviewView) then controller:SetViewTargetWithBlend(reviewView,0,0,0,false) end
        if valid(reviewCamera) then reviewCamera:K2_DestroyActor() end
        reviewCamera,reviewView,reviewTarget,reviewForward=nil,nil,nil,nil
        log("Eye review camera restored") return
    end
    if not reviewTarget then
        if not current or not valid(current.display) then reviewMode=0 return end
        local head=current.display:GetSocketLocation(FName("head"))
        local f=pawn:GetActorForwardVector()
        reviewTarget={X=head.X,Y=head.Y,Z=head.Z+8}
        reviewForward={X=f.X,Y=f.Y}
        reviewView=controller:GetViewTarget()
    end
    local target=reviewTarget
    local location={X=target.X+reviewForward.X*90,Y=target.Y+reviewForward.Y*90,
        Z=target.Z+(reviewMode==1 and 0 or 16)}
    local mathLibrary=StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local rotation=mathLibrary:FindLookAtRotation(location,target)
    local transform=mathLibrary:MakeTransform(location,rotation,{X=1,Y=1,Z=1})
    local gameplay=UEHelpers.GetGameplayStatics()
    local actor=gameplay:BeginDeferredActorSpawnFromClass(pawn,StaticFindObject("/Script/Engine.CameraActor"),transform,1,pawn,0)
    if not valid(actor) then error("Eye review camera unavailable") end
    actor=gameplay:FinishSpawningActor(actor,transform,0)
    actor.CameraComponent:SetFieldOfView(35)
    controller:SetViewTargetWithBlend(actor,0,0,0,false)
    if valid(reviewCamera) then reviewCamera:K2_DestroyActor() end
    reviewCamera=actor
    log(string.format("Eye review camera mode %d; target %.4f %.4f %.4f",reviewMode,target.X,target.Y,target.Z))
end


local function makeMaterial(pawn, index)
    local definition = definitions07[index]
    local parentPath = definition.nativeSkin and "/Game/PBZContent/Characters/Hero/Hun_New_V2b/Material/MI_ZeroHun_Head_b.MI_ZeroHun_Head_b"
        or definition.tear and "/Game/PBZContent/Characters/Hero/Hun_New_V2/Material/MI_ZeroHun_LacrimalFluid.MI_ZeroHun_LacrimalFluid"
        or definition.occlusion and "/Game/PBZContent/Characters/Hero/Hun_New_V2/Material/MI_ZeroHun_EyeOcclusion.MI_ZeroHun_EyeOcclusion"
        or definition.eye and "/Game/PBZContent/Characters/Hero/Hun_New_V2/Material/MI_ZeroHun_Eye_01.MI_ZeroHun_Eye_01"
        or definition.hair and "/Game/PBZContent/Characters/Hero/Hun_New_V2b/Material/Hun_Status/MI_ZeroHun_HairCard_Health.MI_ZeroHun_HairCard_Health"
        or "/AkashaEffects/MaterialLibrary/Template/Character/MAI_Equipment.MAI_Equipment"
    local parent = load(parentPath)
    if not valid(parent) then error("Native material parent missing: " .. parentPath) end
    local library = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local material = library:CreateDynamicMaterialInstance(pawn, parent, FName("MaixiaowenMaterial07_" .. index .. "_" .. materialGeneration), 0)
    if not valid(material) then error("Could not create material " .. index) end
    local function setTexture(name, textureName)
        local texture = load("/Game/Mods/Maixiaowen/Textures/" .. textureName .. "." .. textureName)
        if not valid(texture) then error("Texture missing: " .. textureName) end
        material:SetTextureParameterValue(FName(name), texture)
    end
    local function setScalars(values)
        for name, value in pairs(values) do material:SetScalarParameterValue(FName(name), value) end
    end
    for _, key in ipairs({"Albedo", "Normal", "Mix", "SCMT_Map"}) do
        if definition[key] then
            local texture = load("/Game/Mods/Maixiaowen/Textures/" .. definition[key] .. "." .. definition[key])
            if not valid(texture) then error("Texture missing: " .. definition[key]) end
            if definition.hair then
                local name = ({Albedo="Diffuse", Normal="Normal_map"})[key] or key
                if key ~= "Mix" then material:SetTextureParameterValue(FName(name), texture) end
            else
                material:SetTextureParameterValueByInfo({Name=FName(key), Association=0, Index=0}, texture)
            end
        end
    end
    if definition.hair then
        -- Supply the matching regular and virtual alpha assets for native permutations.
        -- All remaining hair maps are virtual textures, matching the native sampler types.
        setTexture("Alpha(NoVT)", "T_MaixHair_Coverage_v05")
        setTexture("Alpha", "T_MaixHair_CoverageVT_v05")
        setTexture("Diffuse", "T_MaixHair_Diffuse")
        setTexture("Root", "T_MaixHair_Root")
        setTexture("Depth", "T_MaixHair_Depth")
        setTexture("Unique_Hair_Value", "T_MaixHair_ID")
        local r, t = definition.rootColor, definition.tipColor
        material:SetVectorParameterValue(FName("RootColor"), {R=r*0.94,G=r*0.97,B=r,A=1})
        material:SetVectorParameterValue(FName("TipColor"), {R=t*0.94,G=t*0.97,B=t,A=1})
        material:SetVectorParameterValue(FName("Tangent"), {R=0,G=-1,B=0,A=1})
        material:SetVectorParameterValue(FName("TangentA"), {R=0,G=0,B=0,A=1})
        material:SetVectorParameterValue(FName("TangentB"), {R=0,G=0,B=-0.3,A=1})
        material:SetVectorParameterValue(FName("HairEmissiveColor"), {R=0,G=0,B=0,A=0})
        setScalars({Brightness=1, Roughness=0.52, Specular=definition.specular or 0.28, Scatter=definition.scatter or 0.35,
            RandomHueVariation=0, RandomValueVariation=0, VertexColorStrength=0,
            HairAOStrength=0, NormalStrength=0, HairEmissiveBrightness=0,
            OcclusionAmtRoot=0, OcclusionAmtRootTip=0, AlphaMipBias=0,
            AOMin=0, AOMax=1,
            RootDitherRange=0, TipDitherRange=0.04, EdgeMaskMin=0, EdgeMaskContrast=1,
            MaxOpacity=1, DensityOffsetPower=1, ["DensityOffsetPower | Close"]=1,
            PixelDepthOffset=0, PixelDepthOffset_Root=0, DepthOffset=0,
            RootContrast=0, RootMin=0, RootMax=1})
    elseif definition.eye then
        -- Iris textures require the native eye shader to construct the surrounding sclera.
        setTexture("IrisBaseColor", definition.iris)
        setTexture("IrisAO", "T_MaixEye_White")
        setScalars({PupilScale=0.79, ScleraPower=1, IrisRoughness=0.065,
            ScleraRoughness=0.055, IrisSpecularity=0.58, ScleraSpecularity=0.5,
            AOinBaseColorPower=0, POMHeightRatio=0, FlattenNormal=0.75, VeinsOpacity=0.12,
            ["Iris Concavity Power"]=0.28,["Iris Concavity Scale"]=0.12,
            PupilShiftX=0,PupilShiftY=0})
        setScalars(definition.scalars)
        material:SetVectorParameterValue(FName("ScleraTint"),{R=0.94,G=0.96,B=1,A=1})
    elseif definition.skin then
        for name,value in pairs({["Metallic Min"]=0,["Metallic Max"]=0,["Specular"]=0.32,
            ["Roughness Min"]=0.42,["Roughness Max"]=0.67,["AO Min"]=0.85,["Normal Strength"]=0.65}) do
            material:SetScalarParameterValueByInfo({Name=FName(name),Association=0,Index=0},value)
        end
    elseif definition.occlusion then
        setScalars(definition.scalars or {ShadowMultiply=0, ["Blur Size"]=0})
        local tint=definition.shadowTint or 1
        material:SetVectorParameterValue(FName("ShadowTint"), {R=tint,G=tint,B=tint,A=1})
        material:SetVectorParameterValue(FName("Blur color"), {R=1,G=1,B=1,A=0})
    end
    return material
end

local function apply()
    if not enabled then return end
    local pawn = UEHelpers.GetPlayer()
    if not valid(pawn) or not pawn:GetFullName():find("BP_Renewal_Hun_C", 1, true) then return end
    local ownerName = pawn:GetFullName()
    if current and (current.ownerName ~= ownerName or not valid(current.display)) then current = nil; physicsStatsReported = false end
    if not valid(replacement) then replacement = load(meshPath) end
    if not valid(replacement) then error("Replacement asset not found; check the pak/utoc/ucas installation") end
    if not current then
        local components = {}
        local candidates = FindAllOf("SkeletalMeshComponent") or {}
        for _, component in ipairs(FindAllOf("ChaosClothComponent") or {}) do table.insert(candidates, component) end
        for _, component in ipairs(candidates) do
            if valid(component) then
                local owner = component:GetOwner()
                if valid(owner) and owner:GetFullName() == ownerName then
                    local name = component:GetFullName():match("%.([^%.]+)$")
                    components[name] = component
                    log("Component " .. name .. ": " .. component:GetFullName())
                end
            end
        end
        local driver, display = components.CharacterMesh0, components.meshScarf
        if not valid(driver) or not valid(display) then return end
        local saved = {
            ownerName = ownerName, pawn = pawn, driver = driver, display = display,
            originalMesh = display:GetSkeletalMeshAsset(), originalMaterials = {},
            visibility = {}, waistKnife = {}, originalTickOption = driver.VisibilityBasedAnimTickOption,
            originalAllowCloth = display.bAllowClothActors,
            originalDisableCloth = display.bDisableClothSimulation,
            originalClothBlend = display.ClothBlendWeight,
            originalFollowerTick = display.bFollowerShouldTickPose,
            originalDisplayTick = display:IsComponentTickEnabled(),
            originalDriverScale = {X=driver.RelativeScale3D.X,Y=driver.RelativeScale3D.Y,Z=driver.RelativeScale3D.Z},
        }
        if valid(saved.originalMesh) then saved.originalMeshPath = saved.originalMesh:GetFullName():match("^[^ ]+ (.+)$") end
        for i = 0, display:GetNumMaterials() - 1 do
            table.insert(saved.originalMaterials, display:GetMaterial(i))
        end
        for name, component in pairs(components) do
            if waistSockets[name] then saved.waistKnife[name]={component=component} end
            if hiddenNames[name] or name == "meshScarf" then
                table.insert(saved.visibility, {component = component, visible = component:IsVisible(), hidden = component.bHiddenInGame})
            end
        end
        current = saved
        gripCheckTicks = 0
        log("Using original animation driver: " .. driver:GetFullName())
    end
    -- Keep the full game skeleton and animation blueprint on the original driver.
    -- A modular follower displays the replacement using matching bone names.
    current.driver.VisibilityBasedAnimTickOption = 0
    local displayedMesh = current.display:GetSkeletalMeshAsset()
    if not valid(displayedMesh) or displayedMesh:GetFullName() ~= replacement:GetFullName() then
        -- Always new instances under new names: a pointer kept across a swap can pass IsValid as another object
        -- reallocated at the same address.
        materialGeneration = materialGeneration + 1
        for i in ipairs(definitions07) do
            current.display:SetMaterial(i - 1, makeMaterial(pawn, i))
        end
        current.display:SetAllowClothActors(true)
        current.display:SetSkeletalMeshAsset(replacement)
        current.display.bDisableMorphTarget = false
        current.display:SetLeaderPoseComponent(current.driver, true, true)
        current.display:SetComponentTickEnabled(true)
        if next(eyeTune) then applyEyeTune(eyeTune) end
        updatePhysics(true)
        local interactor = current.display:GetClothingSimulationInteractor(FName("None"))
        log("Clothing simulation interactor: " .. (valid(interactor) and interactor:GetFullName() or "not available"))
        log("Appearance applied: " .. replacement:GetFullName())
    end
    updateBodyScale()
    guardedWaistKnife(true)
    for _, entry in ipairs(current.visibility) do
        if valid(entry.component) then
            entry.component:SetVisibility(entry.component == current.display, false)
            entry.component:SetHiddenInGame(entry.component ~= current.display, false)
        end
    end
    if physicsEnabled and not physicsStatsReported then
        local interactor = current.display:GetClothingSimulationInteractor(FName("None"))
        if valid(interactor) and interactor:GetNumDynamicParticles() > 0 then
            log("Physics active: " .. tostring(interactor:GetNumCloths()) .. " cloth sections, " .. tostring(interactor:GetNumDynamicParticles()) .. " dynamic particles")
            physicsStatsReported = true
        end
    end
    if gripCheckTicks >= 0 then
        gripCheckTicks = gripCheckTicks + 1
        if gripCheckTicks >= 20 then
            gripCheckTicks = -1
            reportGrip()
        end
    end
end

local function guardedApply()
    local ok, err = pcall(apply)
    if not ok and tostring(err) ~= lastError then
        lastError = tostring(err)
        log("ERROR " .. lastError)
    end
end

local function resetGaze()
    gazeX, gazeY, gazeFromX, gazeFromY, gazeToX, gazeToY = 0, 0, 0, 0, 0, 0
    gazeStart, gazeTestStep, liveGaze = nil, nil, false
    clearGaze()
    if current and valid(current.display) then
        local eye=current.display:GetMaterial(7)
        if valid(eye) then eye:SetScalarParameterValue(FName("PupilScale"),eyeSetting("PupilScale",0.79)) end
    end
end

local function stepGaze()
    if not enabled or not gazeEnabled or not current or not valid(current.display) then return end
    local ok,err=pcall(function()
        -- Resolve the live instance from the component each time; never retain a second eye MID.
        local eye=current.display:GetMaterial(7)
        if not valid(eye) then return end
        eyePhase=eyePhase+0.25
        eye:SetScalarParameterValue(FName("PupilScale"),eyeSetting("PupilScale",0.79)+0.018*math.sin(eyePhase*0.23))
        eyeUpdates=eyeUpdates+1
        if eyeUpdates==1 or eyeUpdates%240==0 then log("Eye animation updates: "..tostring(eyeUpdates)) end
    end)
    if not ok then gazeEnabled=false;log("Eye experiment disabled: "..tostring(err)) end
end

local function sendGaze(index, weight)
    local name=gazeNames[index]
    local sent=current.gazeSent
    if math.abs((sent[index] or 0)-weight)<0.004 then return end
    sent[index]=weight
    local remove=weight<=0
    if valid(current.driver) then current.driver:SetMorphTarget(name.fname,weight,remove) end
    if valid(current.display) then current.display:SetMorphTarget(name.fname,weight,remove) end
end

-- Applies control values the way the hero's rig reads them: one x and y for both eyes, each eye with its own limits.
local function applyGaze(x, y)
    if not gazeNames then
        gazeNames={}
        for _,side in ipairs(gazeSides) do
            for _,direction in ipairs({"Left","Right","Up","Down"}) do
                table.insert(gazeNames,{fname=FName("Eye"..side.."_"..direction)})
            end
        end
    end
    if not current.gazeSent then current.gazeSent={} end
    for sideIndex,side in ipairs(gazeSides) do
        local limits=gazeDegrees[side]
        local base=(sideIndex-1)*4
        local yaw=x>0 and x*limits.left or x*limits.right
        local pitch=y>0 and y*limits.up or y*limits.down
        sendGaze(base+1,math.min(math.max(yaw,0)/morphYawDegrees,1))
        sendGaze(base+2,math.min(math.max(-yaw,0)/morphYawDegrees,1))
        sendGaze(base+3,math.min(math.max(pitch,0)/morphPitchDegrees,1))
        sendGaze(base+4,math.min(math.max(-pitch,0)/morphPitchDegrees,1))
    end
end

local function pickFrom(rows)
    local r=math.random()
    for _,row in ipairs(rows) do
        if r<=row[1] then return row[2]+math.random()*(row[3]-row[2]) end
    end
    return rows[#rows][3]
end

-- SACCADE_TABLES_BEGIN
-- From 103 saccades over 232 s of the hero's keyed cutscene gaze (make_gaze_tables.py).
local gazeAmplitudes={{0.152,0.5,2},{0.586,2,5},{0.869,5,10},{1,10,20}}
local gazeDwell={{0.153,0.05,0.167},{0.306,0.167,0.333},{0.458,0.333,0.533},{0.611,0.533,1.5},{1,1.5,8}}
local gazeBlinkChance,gazeBlinkChanceLarge=0.18,0.40
local gazeReturnChance=0.25
local gazeLimitX,gazeLimitUp,gazeLimitDown=0.38,0.44,0.31
local gazeSecondsPerDegree=0.0197
-- SACCADE_TABLES_END

local function startSaccade(now, x, y, seconds)
    gazeFromX,gazeFromY=gazeX,gazeY
    gazeToX,gazeToY=x,y
    gazeStart=now
    gazeDuration=seconds
end

local function degreesBetween(ax, ay, bx, by)
    local dx,dy=(ax-bx)*40,(ay-by)*30.6
    return math.sqrt(dx*dx+dy*dy)
end

local function planSaccade(now)
    local x,y=0,0
    if math.random()>=gazeReturnChance then
        local degrees=pickFrom(gazeAmplitudes)
        local angle=math.random()*math.pi*2
        x=gazeX+degrees*math.cos(angle)/40
        y=gazeY+degrees*math.sin(angle)/30.6
        x=math.max(-gazeLimitX,math.min(gazeLimitX,x))
        y=math.max(-gazeLimitDown,math.min(gazeLimitUp,y))
    end
    local degrees=degreesBetween(gazeX,gazeY,x,y)
    if degrees<0.4 then
        nextGazeAt=now+pickFrom(gazeDwell)
        return
    end
    startSaccade(now,x,y,math.max(0.04,degrees*gazeSecondsPerDegree))
    gazeSaccades=gazeSaccades+1
    if gazeSaccades==1 or gazeSaccades%200==0 then log("Eye saccades played: "..tostring(gazeSaccades)) end
    -- Larger gaze shifts often come with a blink in his cutscenes.
    if blinkEnabled and not blinkStart and math.random()<(degrees>=8 and gazeBlinkChanceLarge or gazeBlinkChance) then
        nextBlinkAt=now
    end
end

-- The gameplay animations carry no eye curves in the assets checked, but a montage could; if one does, it wins.
local function readLiveGaze()
    if not liveCurveNames then
        liveCurveNames={FName("CTRL_expressions_eyeLookLeftL"),FName("CTRL_expressions_eyeLookRightL"),
            FName("CTRL_expressions_eyeLookUpL"),FName("CTRL_expressions_eyeLookDownL")}
    end
    local instance=current.driver:GetAnimInstance()
    if not valid(instance) then return nil end
    local left=instance:GetCurveValue(liveCurveNames[1])
    local right=instance:GetCurveValue(liveCurveNames[2])
    local up=instance:GetCurveValue(liveCurveNames[3])
    local down=instance:GetCurveValue(liveCurveNames[4])
    return left-right,up-down
end

local function stepGazeMotion(now)
    if not enabled or not gazeEnabled or not current or not valid(current.display) then return end
    local ok,err=pcall(function()
        if not liveCheckFailed and (liveGaze or now>=nextLiveCheckAt) then
            nextLiveCheckAt=now+0.25
            local ok2,x,y=pcall(readLiveGaze)
            if not ok2 then
                liveCheckFailed=true
                log("Native eye curves unavailable: "..tostring(x))
            elseif x and (math.abs(x)>0.01 or math.abs(y)>0.01) then
                if not liveReported then
                    liveReported=true
                    log(string.format("Native eye curves active: x %.3f y %.3f",x,y))
                end
                liveGaze=true
                liveQuietSince=now
                gazeStart,gazeTestStep=nil,nil
                gazeX,gazeY=x,y
                return
            elseif liveGaze and now-liveQuietSince>1 then
                liveGaze=false
                nextGazeAt=now+0.5
            end
            if liveGaze then return end
        end
        if gazeTestStep and now>=gazeTestAt and not gazeStart then
            gazeTestStep=gazeTestStep+1
            local pose=gazeTestPoses[gazeTestStep]
            if pose then
                startSaccade(now,pose[1],pose[2],0.15)
                gazeTestAt=now+1.6
            else
                gazeTestStep=nil
                nextGazeAt=now+1
            end
        end
        if not gazeStart and not gazeTestStep and now>=nextGazeAt then planSaccade(now) end
        if not gazeStart then return end
        local t=(now-gazeStart)/gazeDuration
        if t>=1 then
            gazeX,gazeY=gazeToX,gazeToY
            gazeStart=nil
            nextGazeAt=now+pickFrom(gazeDwell)
        else
            -- Minimum-jerk easing, the usual shape of a saccade.
            local s=t*t*t*(10+t*(-15+6*t))
            gazeX=gazeFromX+(gazeToX-gazeFromX)*s
            gazeY=gazeFromY+(gazeToY-gazeFromY)*s
        end
    end)
    if not ok then gazeEnabled=false;log("Eye movement disabled: "..tostring(err)) end
end

-- Blink and gaze morphs add together, and both were sculpted from the open, centred eye: added at full strength the
-- upper lid pushes through the lower one looking down and stops short of it looking up. Gaze fades as the lids close,
-- so the closed pose is exactly the blink morph. Runs after stepBlink; sendGaze skips values that have not changed.
local function stepEyes()
    if not enabled or not gazeEnabled or not current or not valid(current.display) then return end
    local ok,err=pcall(function()
        local open=1-blinkWeight
        applyGaze(gazeX*open,gazeY*open)
    end)
    if not ok then gazeEnabled=false;log("Eye movement disabled: "..tostring(err)) end
end

local function blinkCurve(t)
    if t < blinkClose then
        local x = t / blinkClose
        return x * x
    elseif t < blinkClose + blinkHold then
        return 1
    end
    local x = (t - blinkClose - blinkHold) / blinkOpen
    if x >= 1 then return 0 end
    return (1 - x) * (1 - x)
end

local function scheduleBlink(now)
    -- About one blink in six is a quick double blink, as people tend to do.
    if not blinkQueued and math.random() < 0.16 then
        blinkQueued = true
        nextBlinkAt = now + 0.12 + math.random() * 0.1
    else
        blinkQueued = false
        nextBlinkAt = now + 2.5 + math.random() * 4
    end
end

local function stepBlink(now)
    if not enabled or not blinkEnabled or not current or not valid(current.display) then return end
    if not blinkStart and now<nextBlinkAt then return end
    local ok,err=pcall(function()
        if not blinkStart then blinkStart=now end
        local t=(now-blinkStart)/blinkSlow
        local weight=blinkCurve(t)
        if t>=blinkClose+blinkHold+blinkOpen then
            weight=0
            blinkStart=nil
            blinkSlow=1
            scheduleBlink(now)
            blinkCount=blinkCount+1
            if blinkCount==1 or blinkCount%120==0 then log("Blinks played: "..tostring(blinkCount)) end
        end
        setBlinkWeight(weight)
    end)
    if not ok then blinkEnabled=false;log("Blink disabled: "..tostring(err)) end
end

-- UE4SS runs every thread of a mod on one Lua VM and holds no lock around LoopAsync or game-thread
-- callbacks, so Lua running off the game thread eventually corrupts the VM. All work happens in
-- gameThreadTick. Key callbacks arrive on the input thread and only flip a flag that already exists,
-- which allocates nothing.
local keyRequests = {appearance=false, physics=false, gaze=false, gazeTest=false, blink=false, slowBlink=false, scale=false, eyeTune=false, eyeCamera=false}

local function handleKeys()
    if keyRequests.eyeTune then
        keyRequests.eyeTune=false
        local ok,err=pcall(reloadEyeTune)
        if not ok then log("Eye tune failed: "..tostring(err)) end
    end
    if keyRequests.eyeCamera then
        keyRequests.eyeCamera=false
        local ok,err=pcall(cycleEyeCamera)
        if not ok then log("Eye review camera failed: "..tostring(err)) end
    end
    if keyRequests.scale then
        keyRequests.scale=false
        -- Hand back the current root motion compensation; updateBodyScale sets the one for the new size.
        if current and valid(current.pawn) and math.abs(current.pawn.AnimRootMotionTranslationScale - rootMotionScale) < 0.001 then
            current.pawn.AnimRootMotionTranslationScale = 1
        end
        visualScale = visualScale < 0.95 and 1 or 0.90
        rootMotionScale = 1 / visualScale
        saveScale()
        gripCheckTicks = 0
        if enabled then guardedApply() end
        log(string.format("Body scale: %d%%", math.floor(visualScale * 100 + 0.5)))
    end
    if keyRequests.appearance then
        keyRequests.appearance=false
        enabled = not enabled
        if enabled then guardedApply() else
            local ok, err = pcall(restore)
            if not ok then log("Restore error: " .. tostring(err)) end
            replacement = nil
        end
        log("Enabled: " .. tostring(enabled))
    end
    if keyRequests.physics then
        keyRequests.physics=false
        physicsEnabled = not physicsEnabled
        local ok, err = pcall(function() updatePhysics(true) end)
        if not ok then log("Physics toggle error: " .. tostring(err)) end
        log("Independent hair / clothing physics: " .. tostring(physicsEnabled))
    end
    if keyRequests.gaze then
        keyRequests.gaze=false
        gazeEnabled=not gazeEnabled
        local ok,err=pcall(resetGaze)
        if not ok then log("Eye reset error: "..tostring(err)) end
        log("Eye movement: "..tostring(gazeEnabled))
    end
    if keyRequests.gazeTest then
        keyRequests.gazeTest=false
        gazeEnabled=true
        gazeTestStep=0
        gazeTestAt=0
        log("Eye movement test: left, right, up, down")
    end
    if keyRequests.blink then
        keyRequests.blink=false
        blinkEnabled=not blinkEnabled
        blinkStart=nil
        blinkSlow=1
        local ok,err=pcall(function() setBlinkWeight(0) end)
        if not ok then log("Blink toggle error: "..tostring(err)) end
        log("Blinking: "..tostring(blinkEnabled))
    end
    if keyRequests.slowBlink then
        keyRequests.slowBlink=false
        blinkEnabled=true
        blinkStart=nil
        blinkSlow=10
        nextBlinkAt=0
        log("Slow test blink")
    end
end

local nextApplyAt = 0
local function gameThreadTick()
    local now=os.clock()
    handleKeys()
    if now>=nextApplyAt then
        nextApplyAt=now+0.25
        guardedApply()
        stepGaze()
    end
    stepGazeMotion(now)
    stepBlink(now)
    stepEyes()
end

RegisterKeyBind(Key.F6,function() keyRequests.scale=true end)
RegisterKeyBind(Key.F6,{ModifierKey.SHIFT},function() keyRequests.eyeTune=true end)
RegisterKeyBind(Key.F5,{ModifierKey.SHIFT},function() keyRequests.eyeCamera=true end)
RegisterKeyBind(Key.F10,function() keyRequests.appearance=true end)
RegisterKeyBind(Key.F9,function() keyRequests.physics=true end)
RegisterKeyBind(Key.F8,function() keyRequests.gaze=true end)
RegisterKeyBind(Key.F8,{ModifierKey.SHIFT},function() keyRequests.gazeTest=true end)
RegisterKeyBind(Key.F7,function() keyRequests.blink=true end)
RegisterKeyBind(Key.F7,{ModifierKey.SHIFT},function() keyRequests.slowBlink=true end)
log(string.format("Loaded appearance at %d%% body scale. F6 switches between 90%% and normal size.", math.floor(visualScale * 100 + 0.5)) .. " F10 toggles appearance. F9 toggles independent hair / clothing physics. F8 toggles eye movement; Shift+F8 plays a test sweep. F7 toggles blinking; Shift+F7 plays a slow test blink.")

-- Registered last: from here on the game thread may enter Lua, so this chunk must already be finished.
LoopInGameThreadWithDelay(16,gameThreadTick)

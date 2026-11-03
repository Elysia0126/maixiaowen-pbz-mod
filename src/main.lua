local UEHelpers = require("UEHelpers")
local enabled = true
local physicsEnabled = true
local physicsStatsReported = false
local current = nil
local replacement = nil
local materials = {}
local gazeEnabled = true
local eyePhase = 0
local eyeUpdates = 0
local visualScale = 0.90
local assetPath = "/Game/Mods/Maixiaowen/SK_Maixiaowen_Ink.SK_Maixiaowen_Ink"
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

local function restore()
    if not current then return end
    if valid(current.driver) then
        for _,component in ipairs(current.weapons or {}) do
            if valid(component) then
                local parent=component:GetAttachParent()
                if valid(parent) and valid(current.display) and parent:GetFullName()==current.display:GetFullName() then
                    component:K2_AttachToComponent(current.driver,component:GetAttachSocketName(),0,0,0,false)
                end
            end
        end
    end
    if valid(current.display) then
        current.display:SetRelativeScale3D(current.originalScale)
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

local materialDefinitions = {
{Albedo="T_F_Hack_ink_S_012_Props_Mobile_C_5d9e2c",Normal="T_F_Hack_ink_S_012_Props_Mobile_N_7f6479",Mix="T_ARM_T_F_Hack_ink_S_012_Props_Mobile_MRO_1e72e7"},
{Albedo="T_F_Hack_ink_S_012_Mask_PCUI_C_87f1b8",Normal="T_F_Hack_ink_S_012_Mask_PCUI_N_dcdb86",Mix="T_ARM_T_F_Hack_ink_S_012_Mask_PCUI_MRA_225221"},
{Albedo="T_F_Hack_ink_S_012_Upper_3P_MobileUI_01_C_4c339b",Normal="T_F_Hack_ink_S_012_Upper_3P_MobileUI_01_N_8037d3",Mix="T_ARM_T_F_Hack_ink_S_012_Upper_3P_MobileUI_01_MRA_3e2d80"},
{hair=true,rootColor=0.28,tipColor=0.48},
{Albedo="T_F_Hack_ink_S_012_Upper_3P_MobileUI_02_C_370bce",Normal="T_F_Hack_ink_S_012_Upper_3P_MobileUI_02_N_a8ed2a",Mix="T_ARM_T_F_Hack_ink_S_012_Upper_3P_MobileUI_02_MRA_45b83f"},
{Albedo="T_MaixSkin_Scalp_v05",Normal="T_F_Hack_ink_S_012_Head_N_8bd2fa",Mix="T_MaixSkin_HeadARM",skin=true},
{occlusion=true},
{eye=true},
{hair=true,rootColor=0.52,tipColor=0.82},
{Albedo="T_F_Hack_ink_S_012_Lower_3P_Mobile_C_342288",Normal="T_F_Hack_ink_S_012_Lower_3P_Mobile_N_2a5fb8",Mix="T_ARM_T_F_Hack_ink_S_012_Lower_3P_Mobile_MRO_7c9950"},
{Albedo="T_Signal_lamp_001_C_HD_25cd11",Normal="T_Signal_lamp_001_N_HD_fb2a8c",Mix="T_ARM_T_Signal_lamp_001_MRA_HD_83f151"}
}
local function makeMaterial(pawn, index)
    local definition = materialDefinitions[index]
    local parentPath = definition.occlusion and "/Game/PBZContent/Characters/Hero/Hun_New_V2/Material/MI_ZeroHun_EyeOcclusion.MI_ZeroHun_EyeOcclusion"
        or definition.eye and "/Game/PBZContent/Characters/Hero/Hun_New_V2/Material/MI_ZeroHun_Eye_01.MI_ZeroHun_Eye_01"
        or definition.hair and "/Game/PBZContent/Characters/Hero/Hun_New_V2b/Material/Hun_Status/MI_ZeroHun_HairCard_Health.MI_ZeroHun_HairCard_Health"
        or "/AkashaEffects/MaterialLibrary/Template/Character/MAI_Equipment.MAI_Equipment"
    local parent = load(parentPath)
    if not valid(parent) then error("Native material parent missing: " .. parentPath) end
    local library = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local material = library:CreateDynamicMaterialInstance(pawn, parent, FName("MaixiaowenMaterial" .. index), 0)
    if not valid(material) then error("Could not create material " .. index) end
    local function setTexture(name, textureName)
        local texture = load("/Game/Mods/Maixiaowen/Textures/" .. textureName .. "." .. textureName)
        if not valid(texture) then error("Texture missing: " .. textureName) end
        material:SetTextureParameterValue(FName(name), texture)
    end
    local function setScalars(values)
        for name, value in pairs(values) do material:SetScalarParameterValue(FName(name), value) end
    end
    for _, key in ipairs({"Albedo", "Normal", "Mix", "Alpha"}) do
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
        setScalars({Brightness=1, Roughness=0.52, Specular=0.28, Scatter=0.35,
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
        setTexture("IrisBaseColor", "T_MaixEye_Iris")
        setTexture("IrisAO", "T_MaixEye_White")
        setScalars({IrisUVRadius=0.145, PupilScale=0.79, IrisBrightness=0.9,
            ScleraBrightness=0.84, ScleraPower=1, IrisRoughness=0.065,
            ScleraRoughness=0.055, IrisSpecularity=0.58, ScleraSpecularity=0.5,
            AOinBaseColorPower=0, POMHeightRatio=0, RefractionDepthScale=0.45,
            LimbusDarkScale=0.75, FlattenNormal=0.75, VeinsOpacity=0.12,
            ["Iris Concavity Power"]=0.28,["Iris Concavity Scale"]=0.12,
            PupilShiftX=0,PupilShiftY=0})
        material:SetVectorParameterValue(FName("ScleraTint"),{R=0.94,G=0.96,B=1,A=1})
    elseif definition.skin then
        for name,value in pairs({["Metallic Min"]=0,["Metallic Max"]=0,["Specular"]=0.32,
            ["Roughness Min"]=0.42,["Roughness Max"]=0.67,["AO Min"]=0.85,["Normal Strength"]=0.65}) do
            material:SetScalarParameterValueByInfo({Name=FName(name),Association=0,Index=0},value)
        end
    elseif definition.occlusion then
        -- The source eyelid shell uses different UVs from Hun's; neutralize that shadow mask.
        setScalars({ShadowMultiply=0, ["Blur Size"]=0})
        material:SetVectorParameterValue(FName("ShadowTint"), {R=1,G=1,B=1,A=1})
        material:SetVectorParameterValue(FName("Blur color"), {R=1,G=1,B=1,A=0})
    end
    return material
end

local function apply()
    if not enabled then return end
    local pawn = UEHelpers.GetPlayer()
    if not valid(pawn) or not pawn:GetFullName():find("BP_Renewal_Hun_C", 1, true) then return end
    local ownerName = pawn:GetFullName()
    if current and (current.ownerName ~= ownerName or not valid(current.display)) then current = nil; materials = {}; physicsStatsReported = false end
    if not valid(replacement) then replacement = load(assetPath) end
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
            ownerName = ownerName, driver = driver, display = display,
            originalMesh = display:GetSkeletalMeshAsset(), originalMaterials = {},
            visibility = {}, originalTickOption = driver.VisibilityBasedAnimTickOption,
            originalAllowCloth = display.bAllowClothActors,
            originalDisableCloth = display.bDisableClothSimulation,
            originalClothBlend = display.ClothBlendWeight,
            originalFollowerTick = display.bFollowerShouldTickPose,
            originalDisplayTick = display:IsComponentTickEnabled(),
            originalScale = {X=display.RelativeScale3D.X,Y=display.RelativeScale3D.Y,Z=display.RelativeScale3D.Z},
        }
        if valid(saved.originalMesh) then saved.originalMeshPath = saved.originalMesh:GetFullName():match("^[^ ]+ (.+)$") end
        for i = 0, display:GetNumMaterials() - 1 do
            table.insert(saved.originalMaterials, display:GetMaterial(i))
        end
        for name, component in pairs(components) do
            if hiddenNames[name] or name == "meshScarf" then
                table.insert(saved.visibility, {component = component, visible = component:IsVisible(), hidden = component.bHiddenInGame})
            end
        end
        saved.weapons={}
        for name,component in pairs(components) do
            if component~=display and not hiddenNames[name] then
                local parent=component:GetAttachParent()
                if valid(parent) and parent:GetFullName()==driver:GetFullName() and component:GetAttachSocketName():ToString()~="None" then
                    table.insert(saved.weapons,component)
                end
            end
        end
        current = saved
        log("Using original animation driver: " .. driver:GetFullName())
    end
    -- Keep the full game skeleton and animation blueprint on the original driver.
    -- A modular follower displays the replacement using matching bone names.
    current.driver.VisibilityBasedAnimTickOption = 0
    local displayedMesh = current.display:GetSkeletalMeshAsset()
    if not valid(displayedMesh) or displayedMesh:GetFullName() ~= replacement:GetFullName() then
        for i in ipairs(materialDefinitions) do
            if not valid(materials[i]) then materials[i] = makeMaterial(pawn, i) end
            current.display:SetMaterial(i - 1, materials[i])
        end
        current.display:SetAllowClothActors(true)
        current.display:SetSkeletalMeshAsset(replacement)
        current.display:SetRelativeScale3D({X=current.originalScale.X*visualScale,Y=current.originalScale.Y*visualScale,Z=current.originalScale.Z*visualScale})
        current.display:SetLeaderPoseComponent(current.driver, true, true)
        current.display:SetComponentTickEnabled(true)
        updatePhysics(true)
        local interactor = current.display:GetClothingSimulationInteractor(FName("None"))
        log("Clothing simulation interactor: " .. (valid(interactor) and interactor:GetFullName() or "not available"))
        log("Appearance applied: " .. replacement:GetFullName())
    end
    for _,component in ipairs(current.weapons or {}) do
        if valid(component) then
            local parent=component:GetAttachParent()
            local socket=component:GetAttachSocketName()
            if valid(parent) and parent:GetFullName()==current.driver:GetFullName() and current.display:DoesSocketExist(socket) then
                if component:K2_AttachToComponent(current.display,socket,0,0,0,false) then
                    log("Weapon attached to compact visual: "..component:GetFullName().." socket="..socket:ToString())
                end
            end
        end
    end
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
end

local function guardedApply()
    local ok, err = pcall(apply)
    if not ok and tostring(err) ~= lastError then
        lastError = tostring(err)
        log("ERROR " .. lastError)
    end
end

RegisterKeyBind(Key.F10, function()
    ExecuteInGameThread(function()
        enabled = not enabled
        if enabled then guardedApply() else
            local ok, err = pcall(restore)
            if not ok then log("Restore error: " .. tostring(err)) end
        end
        log("Enabled: " .. tostring(enabled))
    end)
end)

RegisterKeyBind(Key.F9, function()
    ExecuteInGameThread(function()
        physicsEnabled = not physicsEnabled
        local ok, err = pcall(function() updatePhysics(true) end)
        if not ok then log("Physics toggle error: " .. tostring(err)) end
        log("Independent hair / clothing physics: " .. tostring(physicsEnabled))
    end)
end)

LoopAsync(250, function()
    ExecuteInGameThread(guardedApply)
    return false
end)
log("Loaded appearance v0.5: compact visual proportions, silver scalp coverage and subtle eyes. F10 toggles appearance. F9 toggles independent hair / clothing physics. F8 toggles subtle eye movement.")


-- Only the visible follower is scaled. The animation driver and capsule are untouched.
RegisterKeyBind(Key.F8,function()
    ExecuteInGameThread(function()
        gazeEnabled=not gazeEnabled
        if current and valid(current.display) then
            local eye=current.display:GetMaterial(7)
            if valid(eye) then
                eye:SetScalarParameterValue(FName("PupilShiftX"),0)
                eye:SetScalarParameterValue(FName("PupilShiftY"),0)
                eye:SetScalarParameterValue(FName("PupilScale"),0.79)
            end
        end
        log("Subtle eye movement: "..tostring(gazeEnabled))
    end)
end)
LoopAsync(250,function()
    ExecuteInGameThread(function()
        if not enabled or not gazeEnabled or not current or not valid(current.display) then return end
        local ok,err=pcall(function()
            -- Resolve the live instance from the component each time; never retain a second eye MID.
            local eye=current.display:GetMaterial(7)
            if not valid(eye) then return end
            eyePhase=eyePhase+0.25
            eye:SetScalarParameterValue(FName("PupilShiftX"),0.006*math.sin(eyePhase*0.67)+0.002*math.sin(eyePhase*1.31))
            eye:SetScalarParameterValue(FName("PupilShiftY"),0.003*math.sin(eyePhase*0.43))
            eye:SetScalarParameterValue(FName("PupilScale"),0.79+0.018*math.sin(eyePhase*0.23))
            eyeUpdates=eyeUpdates+1
            if eyeUpdates==1 or eyeUpdates%240==0 then log("Eye animation updates: "..tostring(eyeUpdates)) end
        end)
        if not ok then gazeEnabled=false;log("Eye experiment disabled: "..tostring(err)) end
    end)
    return false
end)

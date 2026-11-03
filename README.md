# 影之刃零 × 麦晓雯「水墨云图」MOD

将《影之刃零》主角外观替换为麦晓雯「水墨云图」，支持头发与衣物独立物理。非官方 MOD。

**v0.6.1 为试验版**：[下载 v0.6.1](https://github.com/Elysia0126/maixiaowen-pbz-mod/releases/tag/v0.6.1) · [保留的 v0.4](https://github.com/Elysia0126/maixiaowen-pbz-mod/releases/tag/v0.4) · [更新记录](CHANGELOG.md) · [v0.6.1 验证记录](docs/validation-v0.6.1.json)

## v0.6.1 内容

### 修复战斗中崩溃

v0.6 在 Boss 战中出现过 `UE4SS.dll` 访问异常，崩溃点在内嵌的 Lua 虚拟机里。

UE4SS 让同一个模组的所有线程共用一个 Lua 虚拟机，而 `LoopAsync` 回调和游戏线程回调运行时都不持锁，同时运行可能破坏虚拟机内部状态。v0.6 新增的 16 ms 循环大幅提高了撞上这种竞争的概率。这个原因是由 UE4SS 源码和崩溃转储推断的，转储里看不到另一条线程的现场。

v0.6.1 不再使用 `LoopAsync` 和 `ExecuteInGameThread`，全部逻辑放进一个 `LoopInGameThreadWithDelay` 循环，只在游戏线程上运行。按键回调只翻转一个已存在的标志位，实际操作留到游戏线程处理。

### 修复人物与武器错位

此前只把显示模型缩到 90%，动画驱动骨架仍是 100%。手里的刀是独立的 `BP_Weapon_Hun_*` Actor，挂在驱动骨架上，原来的转挂逻辑没有覆盖到它，所以手和刀握持处相差约 10 cm。

现在改为缩放动画驱动骨架，显示模型跟随它。挂在骨架插槽上的手持武器、刀鞘、特效和攻击判定框都按同一比例走，换武器和拔刀收刀也不用再逐个转挂。

这个改法带来的变化：

- 手持武器也会缩到 90%，**攻击判定框随之缩小，刀的攻击距离会短约 10%**。角色碰撞胶囊不变。
- 模型缩放本来也会让根运动位移缩短，脚本已用 `AnimRootMotionTranslationScale` 抵消。如果游戏自己把这个值改成非 1，脚本不会覆盖，此时位移可能短约 10%。
- 想调整比例，改 `main.lua` 顶部的 `visualScale`。

### 新增眨眼

- 网格新增 `Blink` 变形目标：上下眼睑绕眼球中心转动闭合，睫毛跟随。
- 睫毛从头发布料分段里拆成了独立的非布料分段，保证变形能带动睫毛。
- 每 2.5～6.5 秒随机眨一次，约六分之一的概率连眨两下。单次约 0.25 秒。

**语音未替换，仍为游戏原声。**

## 安装

1. 下载 `MaixiaowenInk_PBZ_Mod_v0.6.1.zip` 并解压。
2. 退出游戏，将包内 `MOD` 的 `ProjectPBZ` 和 `platform` 两个文件夹合并复制到 PBZ 游戏根目录。
3. 尚未安装 UE4SS 时，将 `UE4SS_PBZ_Optional` 中的 `platform` 文件夹也合并复制到游戏根目录。已有加载器时保留加载器、其他 MOD 和加载列表。
4. 确认 `platform/steam/ue4ss/Mods/mods.txt` 包含 `MaixiaowenInk : 1`。已有加载列表请添加此条目，避免覆盖其他 MOD。
5. 启动游戏，加载已有存档。

游戏根目录是 Steam「管理 → 浏览本地文件」打开的位置。

```text
PBZ/
├─ ProjectPBZ/Content/Paks/~mods/
│  ├─ MaixiaowenInk_P.pak
│  ├─ MaixiaowenInk_P.utoc
│  └─ MaixiaowenInk_P.ucas
└─ platform/steam/ue4ss/Mods/MaixiaowenInk/Scripts/main.lua
```

三种资源文件与 `main.lua` 必须一起更新，不能混用版本：网格多了一个材质槽，旧版脚本不会给它赋材质。包内 `SHA256.json` 校验各文件；Release 的 `SHA256SUMS.txt` 校验压缩包。

## 按键

| 按键 | 功能 |
| --- | --- |
| F7 | 开启/关闭眨眼 |
| Shift+F7 | 播放一次约 2.5 秒的慢速眨眼，方便检查效果 |
| F8 | 开启/关闭轻微瞳孔动态 |
| F9 | 开启/关闭头发与衣物独立物理 |
| F10 | 在替换形象与原版主角之间切换 |

默认全部开启。

## 验证范围与已知限制

本地环境：Windows、Steam 构建 `301524-17219`、UE 5.7.4。

游戏内已确认：握刀贴合（日志显示 `weapon_r` 挂点差距 0.00 cm），眨眼正常。

v0.6.1 的游戏线程逻辑在后续测试中累计运行约 50 分钟，没有再产生崩溃转储。这些测试以场景内观察和短时战斗为主，**不能证明长时间战斗稳定**，因此仍以试验版提供。

离线已验证：UE 5.7 中实测 Leader/Follower 变形权重传递；烘焙后的网格、布料绑定和容器校验。详细结果见验证记录。

未覆盖所有武器、地图、过场、重生和长期战斗。攻击距离变化的手感因人而异。发片仍可能在掠射角度有缝隙或穿插，未重建为逐根毛发。布料不具备衣物自碰撞、武器或场景碰撞。肤色与眼睛高光受光照影响。

## 角色设定参考

[官方角色资料页](https://www.playdeltaforce.com/act/wikimap/)可确认 Hackclaw / 麦晓雯身份；本次未在官网找到可核实的身高。第三方数据库所列的 [164 cm](https://deltaforce.th.gl/db/operators/op_88000000026) 仅作比例参考，不能标为官方确认数据。90% 为本 MOD 的视觉调整值。

## 停用、卸载与回退

- 临时恢复原版：F10。只关闭眨眼：F7。只关闭眼睛动态：F8。
- 永久停用：退出游戏，将加载列表中的条目改为 `MaixiaowenInk : 0`。
- 卸载：退出游戏，移除本 MOD 三种同名资源、`Mods/MaixiaowenInk` 文件夹及加载条目，保留其他 MOD 和原游戏文件。
- 回退 v0.4：退出游戏，用 v0.4 包的三种资源和 `main.lua` 一起覆盖 v0.6.1。不要只替换脚本或单个资源。

## 仓库与许可

`src/main.lua` 是发布脚本；`docs/` 提供截图、验证记录及包信息。编译资源与可选加载器位于 Releases，仓库未提供完整 Unreal 工程或一键重建流程。

角色、网格与原始贴图来源于《三角洲行动》的麦晓雯「水墨云图」；相关游戏、角色、美术和商标权利归原权利人。本项目为非官方适配，与原开发者、发行商无关联，未对第三方素材授予额外许可。

可选加载器来自 [KintaroModding/ue4ss](https://github.com/KintaroModding/ue4ss)，适用 MIT 许可，原许可证见包内及 `THIRD_PARTY/UE4SS-LICENSE`。该许可不适用于游戏角色、美术等第三方资源。

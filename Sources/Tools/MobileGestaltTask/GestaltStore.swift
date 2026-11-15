//
//  GestaltStore.swift
//  EnsWilde
//

import SwiftUI
import Combine
import CoreFoundation

enum MGURL {
    static let fsGestaltURL = URL(fileURLWithPath: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist")
    static let savedGestaltURL = URL.documentsDirectory.appendingPathComponent("OriginalGestalt.plist")
    static let savedGestaltSHA256URL = URL.documentsDirectory.appendingPathComponent("OriginalGestalt.sha256")
    static let preApplyGestaltURL = URL.documentsDirectory.appendingPathComponent("PreApplyGestalt.plist")
    static let systemVaultGestaltURL = URL(fileURLWithPath: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/.erosion_factory_vault.plist")
    static let systemVaultSHA256URL = URL(fileURLWithPath: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/.erosion_factory_vault.sha256")
}

enum MGRegionUnlockMode: String, CaseIterable, Identifiable {
    case fullUS = "full_us"
    case regionCodeOnly = "ll_only"
    static let defaultsKey = "mgRegionUnlockMode"
    var id: String { rawValue }
}

enum MGMsg {
    static var region: String { L("开启后默认把销售地区改为完整美版 (LL + LL/A) 并映射对应美版监管型号 (Axxxx)；你也可在下方子选项切换为「仅改区域代码 LL（保留 CH/A 后缀与双卡兼容）」。请遵守当地法律法规并自行承担使用风险。") }
    static var regionModeInfo: String { L("【地区修改模式细化说明】\n\n1. 完整美版 LL + LL/A（默认）：\n同时将区域代码改为 LL、系统销售地区改为 LL/A，并自动填入对应的美版监管型号 (Axxxx)，跨区域受限特性（海外版 Apple 智能、快门静音、健康区域特性等）一致性最完整。\n\n2. 仅改区域代码 LL（保留 CH/A 后缀与双卡兼容）：\n仅将区域代码 (RegionCode) 改为 LL，完整保留原机的销售地区后缀（如 CH/A）与原厂监管型号。既可满足基础 Apple 智能准入、让「设置 -> 关于本机」型号末尾继续显示 CH/A，也能避免国行双实体卡槽 + eSIM 机型（如 18 Pro / Pro Max）因映射无卡槽美版型号引发基带卡槽冲突。") }
    static var ipadOS: String { L("如果你当前设置了字母数字混合锁屏密码，请切勿开启此项！开启后也切勿关闭“在台前调度中显示程序坞”，否则会导致设备软砖（白苹果循环）。启用 iPadOS 界面后可能出现界面错位、部分应用不兼容等问题。") }
    static var support: String { L("请提前备份重要数据！如果某项修改未按预期生效，请勿向官方仓库提交支持请求。许多功能同时受限于设备硬件与 Apple 服务器策略，所有修改均需自行承担风险。") }
    static var mgReset: String { L("重置 MobileGestalt 将删除系统原始缓存文件并让系统在重启时重新生成。这有助于彻底清除无法还原的修改，但存在极低概率引发异常，请谨慎操作。") }
    static var liquidGlass: String { L("开启后将使用 iOS 26/27 液态玻璃 (Liquid Glass) 的低性能开销渲染模式，可降低 GPU 负载、减少机身发热并节省电量（注销或重启后生效）。") }
    static var chinaCacheUnlock: String { L("通过从本机内存加载的系统库 (libMobileGestalt.dylib) 实时动态解析二进制 CacheData 槽位偏移，将国行底层限制标记 green-tea 设为 false、not-green-tea 设为 true。\n\n• 可在所有国行设备上解锁 FaceTime 音频（语音通话）与 AI 底层区域准入；\n• 在自带物理 eSIM 芯片的国行机型（如 iPhone Air、iPhone 18 系列等内置 eUICC 芯片机型）上，可解除系统层针对境外 eSIM 的地理围栏拦截（注：常规纯双实体卡槽国行主板物理空焊 eUICC 芯片，无法通过纯软件写入虚拟卡）。\n\n⚠️ 注意：在 iOS 26/27 中，国行特有的单应用三态联网菜单（“关闭 / 无线局域网 / 无线局域网与蜂窝数据”）同样受 green-tea 标记控制。即使保持下方“无线局域网改 Wi-Fi”关闭，开启本项解除国行底层限制后，系统网络权限也会切换为国际版“蜂窝数据”独立开关模式（关闭本项并重启即可随时原样恢复）。\n\n安全策略：仅当本机 CacheUUID、总长度、有效位及填充字节 100% 匹配通过时才允许修改；应用后请手动重启手机生效。") }
    static var wapiToWifi: String { L("通过本机系统库实时动态解析 wapi 布尔槽位偏移并设为 false，将系统“设置”与控制中心里的“无线局域网”统一显示为国际版的“Wi-Fi”。\n\n⚠️ 重要提示：开启后将会【丢失国行特有的“不允许联网”功能】（即“使用无线局域网与蜂窝网络的 App”中的“关闭”选项）！国际版逻辑仅允许单独关闭“蜂窝数据”，无法禁止单个应用使用 Wi-Fi 联网（如第三方输入法或离线应用将无法彻底断网），同时“启用 WAPI”开关也会隐藏。\n\n如需保留应用“不允许联网”权限控制，请保持此项关闭；若已开启，关闭此开关重新应用并手动重启手机即可原样恢复。") }
    static var intInstall: String { L("此选项将启用部分遗留在正式版 iOS 中的 Apple 内部调试特性。注意：开启后可能会影响部分正常功能（如无法从 App Store 重新安装自带系统应用），且与 Apple 智能互斥。") }
    static var intBuild: String { L("此开关主要用于在“设置”应用中显示内部存储调试信息。在部分设备（尤其是 iPadOS）上可能引发兼容性问题。") }
    static var appleIntellInfo: String { L("为不支持 Apple 智能的旧机型开启端侧生成式 AI 总开关 (DeviceSupportsGenerativeModelSystems)，并自动同步解锁以下 2 项在旧芯片上默认关闭的子能力标记：\n\n• 相册“消除”功能 (Photos Clean Up)\n• 备忘录“手写体合成” (Handwriting Synthesis)\n\n注：旧机型若需实际下载端侧 AI 模型，通常还需配合下方的“机型伪装”与上方的“解除地区限制”使用（修改后请手动重启手机生效）。") }
    static var advAppleIntell: String { L("【防呆护栏警告】真机（iPhone 15 Pro Max · iPhone16,2 与 iPhone 18 Pro Max · iPhone19,7）底层探针交叉核验确认：iOS 27 音频智能 (rb2tKZxlj0Gm2tBmUQSLqQ，槽位 #178) 在 iPhone / iPad 原厂设备树中默认均为 false（0x00），而个人实时翻译 (M1n2sAqf33NAOgZRGxQYBA，槽位 #266) 在所有原生支持 Apple 智能的 iPhone（iPhone 15 Pro 及以上机型）上原厂已自动开启为 true（0x01）。\n\n⚠️ 在 iPhone / iPad 上强行开启非原生的 Audio Intelligence (#178)，或误将原生 AI 机型的 Personal Translator (#266) 设为 false，均会导致系统 GenerativeModels / ModelCatalog 管线校验瞬间断路——直接造成照片【高质量消除、扩图、重构】与【相机 Siri】0 秒瞬间报错！\n\n常规通话录音、语音备忘录转写与系统翻译均由主 AI 开关完整支持。安全护栏已自动校准本机原厂基线（原生 AI 机型锁定 #266=true、#178=false）；若此前受旧版本影响出现槽位偏差，点击顶部体检卡片「一键配齐 / 修复」（或关闭此开关）并应用冷重启即可彻底恢复。") }
    static var audioMixInfo: String { L("通过本机系统库实时动态解析 CameracinematicAudioTrackRendering (aVL5GE3tx0LSCI/ErfrJGA) 二进制 CacheData 布尔槽位并设为 true，解锁相册与相机视频编辑中的“混音 (Audio Mix)”功能，支持“标准 / 语音突显 / 录音棚 / 电影效果”四档人声与环境音分离混音（应用后请手动重启手机生效）。") }
    static var spatialAudioInfo: String { L("通过本机系统库实时动态解析 spatial-audio-recording 与 spatial-facetime-audio 二进制 CacheData 布尔槽位并同步设为 true，解锁相机视频录制时的 3D 空间音频拾音及 FaceTime 通话空间声场渲染能力（应用后请手动重启手机生效）。") }
    static var spatialFaceTimeInfo: String { L("通过本机系统库实时动态解析 spatial-facetime-audio (/EVOCjM/Nmb2roP5ebtEFA) 二进制 CacheData 布尔槽位并设为 true，解锁 FaceTime 通话期间的 3D 空间声场渲染能力（纯软件声学渲染，支持 iPhone 15 Pro 及更早机型，不影响语音备忘录录音，应用后请手动重启手机生效）。") }
    static var spatialAudioRecInfo: String { L("通过本机系统库实时动态解析 spatial-audio-recording (X6NGcYcvHmbqlR8hLXASJA) 二进制 CacheData 布尔槽位，控制相机 3D 空间音频拾音与语音备忘录“录音室 (Studio)”四声道录制模式。\n\n⚠️ 防呆说明：该功能物理依赖 iPhone 16 系列起的四麦克风录音棚声学阵列硬件（支持机型出厂已原生开启）。在三麦克风旧机型（如 iPhone 15 Pro 及更早机型）上强行开启，会导致“语音备忘录”出现无效的“录音室”选项，选择该档位点击录音会因四声道硬件初始化失败立即中断。因此非四麦克风机型已默认防呆锁定关闭（若此前在旧版本开启过，直接关闭本开关并应用重启即可恢复）。") }
    static var responsiveShutterInfo: String { L("通过本机系统库实时动态解析 ResponsiveShutter (gQDt76Te0SPw7N8oTLrBFw) 二进制 CacheData 布尔槽位并设为 true，降低相机按下快门至成像管线的触发延迟，实现手指按下瞬间零延迟抓拍（应用后请手动重启手机生效）。") }
    static var hypertensionInfo: String { L("通过本机系统库实时动态解析 HypertensionNotifications (4fh9efw4o1yaFqkXNCXoeA) 二进制 CacheData 布尔槽位并设为 true，开启“健康”App 中的血压偏高趋势评估、风险通知与测量记录向导页面（应用后请手动重启手机生效）。") }
    static var callScreeningGuide: String { L("【普通话“询问来电原因”与海外 Apple 智能黄金共存方案（测试特性）】\n\nApple 对来电筛选施加了基于系统“地区 (Locale)”的语音过滤：若系统地区设为“美国”会丢失中文普通话来电询问；若保持“中国大陆”则会阻断 Apple 智能。\n\n唯一实测完美共存四步配置：\n1. MobileGestalt：在本页开启“解除地区限制 (LL / LL/A)”并填写对应美版监管型号；\n2. 系统设置 -> 通用 -> 语言与地区：“地区”改为【台湾】，首选语言第一项保持【简体中文】；\n3. 系统设置 -> Apple 智能与 Siri：Siri 语言设为【中文（普通话 - 中国大陆）】；\n4. 分流规则：guzzoni.apple.com 与 *.siri.apple.com 必须走【DIRECT 直连 + 真实 IP (always-real-ip)】防 Siri 报错，仅将 apple-relay.apple.com、gspe1-ssl.ls.apple.com 与 OpenAI 走美区节点（可在“跨容器应用共享组中心”一键导出 Surge 模块）。") }
    static var expNotice: String { L("【测试特性提示】本分组所有开关均通过运行时从本机 libMobileGestalt.dylib 实时解析真实 CacheData 布尔槽位（QType=11）并在写前校验 CacheUUID、字节总长与槽位有效位。因不同机型的底层 ISP、传感器或地区守护进程（eligibilityd）支持程度存在差异，部分功能在缺乏物理硬件时仅解锁系统 UI 入口。应用后请【手动重启手机】验证效果，随时可关闭或还原备份。") }
    static var expShutterMuteInfo: String { L("【测试特性】传统 RegionalBehaviorShutterClick 为只读动态探针（slot = -1），直接写 CacheExtra 无效。本开关组合修改 3 个真实 CacheData 布尔槽位：\n• DeviceSupportsRegionalCameraShutterRelaxation = true\n• KeyboardMutePreservesRegionalShutterClickBehavior = false\n• ...ForLegacyDevices = false\n可在无需更改整机销售地区的前提下，尝试解除日版 (J/A) 与韩版 (KH/A) 机型的强制相机快门音（应用后请手动重启手机生效）。") }
    static var expStudioMicsInfo: String { L("【测试特性】开启高低功耗双阵列麦克风并发拾音槽位 DeviceSupportsConcurrentHPLPMics (dI30ovtFUIeLioNQKDMbGQ)，为语音备忘录录音棚伴奏叠录与多轨人声分离提供底层硬件能力标记（需麦克风 DSP 支持，重启生效）。") }
    static var expPhotoToneInfo: String { L("【测试特性】同步开启 PhotosLocalLight、ToneMapping 与 HDRDeferredProcessing 三个影像后期管线布尔槽位，增强相册局部光影重绘、新一代色调映射与深度 HDR 延迟渲染能力（重启生效）。") }
    static var expSpatialStereoInfo: String { L("【测试特性】同步开启 SpatialOverCapture、StereoAudioRecording 与 P3ColorspaceVideoRecording 三个视频捕获槽位，解锁超取景框空间视角重构、立体声拾音及 P3 广色域视频编码支持（重启生效）。") }
    static var expCamControlInfo: String { L("【测试特性】同步开启 CameraButtonCapability、TouchSensitiveCameraControl、HardwareDetents 与 CameraHaptics 四个交互槽位，解锁完整的“设置 -> 相机 -> 相机控制”电容轻按/滑动变焦配置面板（无物理按键机型仅展示设置面板，重启生效）。") }
    static var expLegacyBatteryInfo: String { L("【测试特性】开启 DeviceShowsBatteryModelInformationLegacyHW 与 DynamicEndOfChargeLegacyHW 槽位，在旧款 iPhone / iPad 的“设置 -> 电池 / 关于本机”中尝试展示电池生产日期、首次使用时间与精确充电循环次数（重启生效；亦可使用本工具“物理电池与温控遥测”模块直读底层数据）。") }
    static var expHighLumAODInfo: String { L("【测试特性】同步开启 HighLuminanceAlwaysOnDisplay 与 AlwaysOnDisplayFlipbook 槽位，解锁户外高亮全天候显示策略与低功耗翻页帧缓冲渲染（注：非 LTPO 屏幕开启 AOD 会增加待机耗电，重启生效）。") }
    static var expCarPlay2Info: String { L("【测试特性】开启 DeviceSupportsCarPlay2 (PR+xeEtTAiUN0R25+EYGfw) 槽位，启用新一代多屏全液晶仪表接管 CarPlay Ultra 车载协议支持（重启生效）。") }
    static var expTouch120Info: String { L("【测试特性】开启 TouchDelivery120Hz (2OK50OGmkXM1ospsh766WQ) 槽位，向系统启用 120Hz 触控采样事件投递管线（注：60Hz 物理屏幕面板无法突破 60fps 画面刷新率，仅作用于触控采样投递层，重启生效）。") }
    static var expHearingAidInfo: String { L("【测试特性】同步开启 hearingaid-audio-equalization、hearingaid-low-energy-audio 与 hearingaid-power-reduction 三个连续布尔槽位，配合 AirPods Pro 2 / 3 尝试解锁听力健康均衡与临床助听器辅助能力（部分地区仍受 eligibilityd 医疗围栏限制，重启生效）。") }
    static var expSleepApneaInfo: String { L("【测试特性】开启 DeviceSupportsBreathingDisturbancesMeasurements (e0HV2blYUDBk/MsMEQACNA) 槽位，解锁“健康 -> 呼吸 -> 呼吸紊乱”睡眠呼吸暂停风险趋势评估页面（需配合 Apple Watch 睡眠监测数据，重启生效）。") }
    static var expUSBloodOxygenInfo: String { L("【测试特性】将 DeviceSupportsUSLegallyCompliantBloodOxygen (E4vGMChwcVRKD8hMVxnRvg) 槽位设为 false，解除美版 (LL/A) 设备因专利禁令触发的软件层血氧测量屏蔽（国行机型原生已为 false 无需开启，重启生效）。") }
    static var expWorkoutUltraInfo: String { L("【测试特性】同步开启 WorkoutUltraMode 与 DeviceSupportsTimeInDaylight 槽位，解锁极限户外运动辅助模式与健康“日光下时间”环境光监测统计入口（重启生效）。") }
    static var expSiriHubInfo: String { L("【防呆护栏警告】真机实测表明：DeviceSupportsSiriHub (waGD2UTpntjbDXD1r3oALQ) 属于带屏家居中枢硬件 (HomeAccessory / HomePad) 专属路由标记。\n\n⚠️ 在 iPhone / iPad 上开启会导致 assistantd 请求不存在的 SiriHub 模型资产，使 Apple 智能无限卡死在“正在添加 Siri 支持内容，更新完成前，Siri 将无法使用”！\n\n安全护栏已默认锁定禁止在 iPhone / iPad 上新开启此项；如果你在旧版本曾开启过此开关，可直接关闭此项（或使用顶部 Apple 智能体检卡片一键修复）并手动重启手机即可恢复正常。") }
    static var spoofUseless: String { L("伪装设备型号可能会导致面容 ID (Face ID) 等硬件功能失效！你的设备硬件本身已原生支持 Apple 智能，无需修改此项（国行设备只需开启上方“解除地区限制”即可）。") }
    static var spoofAI: String { L("对于不支持 Apple 智能的旧机型，仅开启开关无法下载端侧 AI 模型，还需伪装为支持的机型；但伪装机型可能导致面容 ID 失效。取消机型伪装后，请勿再次进入“设置 -> Apple 智能与 Siri”页面。") }
    static var subtype: String { L("仅在你想调整灵动岛纵向位置或屏幕分辨率特征时才修改设备子类型 (Subtype)。如需在非灵动岛机型开启灵动岛，请配合下方的“启用灵动岛”开关使用！") }
    static var mgResetComp: String { L("已移除当前 MobileGestalt 缓存并将旧备份安全归档。请立即【手动重启你的设备】，系统将在开机时从硬件熔丝重新生成 100% 纯净的原厂参数。") }
    static var revertComp: String { L("已通过 SHA-256 与物理落盘校验恢复本机原厂备份，并已同步清空本地自定义开关残留。建议【手动重启一次手机】以确保所有底层参数彻底复原。") }
    static var revertConfirm: String { L("即将执行本机原厂参数恢复：\n\n1. 严格核对原厂备份的 SHA-256 摘要、系统版本、CacheUUID 与真实硬件型号；\n2. 通过无零字节窗口原位刷盘 (pwrite + F_FULLFSYNC) 恢复 MobileGestalt 并读回验证；\n3. 同步复位本地自定义键值、自定义机型名与越界门禁开关，杜绝残留回写。") }
    static var globalFactoryRestoreConfirm: String { L("即将执行全模块一键恢复原机出厂参数：\n\n1. 恢复并校验本机 MobileGestalt 原厂备份（含 SHA-256 与物理刷盘验证）；\n2. 清除锁屏底部文字、设备资产铭牌及第三方伪监管残留（自动保护真实企业 MDM）；\n3. 清理自定义拨号键盘缓存并复位所有本地偏好状态。") }
    static var mgResetSavWarn: String { L("重新生成原始备份前，请确保当前已还原所有修改，否则当前处于开启状态的修改会被写入新的原始备份中！") }
    static var hidTweakWarn: String { L("显示被隐藏的修改项后，你将能看到当前机型本已原生支持或不兼容的底层开关。盲目改动可能导致功能异常甚至数据丢失！") }
}

enum MGKey {
    static let ipadosCacheEx = [
        "mG0AnH/Vy1veoqoLRAIgTA",
        "UCG5MkVahJxG1YULbbd5Bg",
        "ZYqko/XM5zD3XBfN5RmaXA",
        "nVh/gwNpy7Jv1NOk00CMrw",
        "uKc7FPnEO++lVhHWHFlGbQ"
    ]
    static let island = "YlEtTtHlNesRBMal1CqRaA"
    static let AOTime = "j8/Omm6s1lsmTDFsXjsBfA"
    static let AOD = "2OOJf1VhaM7NxfRok3HbWQ"
    static let AODVibrancy = "ykpu7qyhqFweVMKtxNylWA"
    static let liquidGlassLowPower = "SAGvsp6O6kAQ4fEfDJpC4Q"
    static let chargeLim = "37NVydb//GP/GrhuTN+exg"
    static let bootChime = "QHxt+hGLaBPbQJbXiUJX3w"
    static let intInstall = "EqrsVvjcYDdxHBiQmGhAWw"
    static let intBuild = "LBJfwOEzExRxzlAnSuI7eg"
    static let srd = "XYlJKKkj2hztRP1NWWnhlw"
    static let appIntell = "A62OafQ85EJAiiqKn4agtg"
    static let photosCleanUp = "XNCjqOupLM/S8fNyxRNQTA"
    static let handwritingSynth = "YgYIIViDt1kgzyIsIV61vA"
    static let appIntellAllKeys = ["A62OafQ85EJAiiqKn4agtg", "XNCjqOupLM/S8fNyxRNQTA", "YgYIIViDt1kgzyIsIV61vA"]
    static let audioIntell = "rb2tKZxlj0Gm2tBmUQSLqQ"
    static let personalTranslator = "M1n2sAqf33NAOgZRGxQYBA"
    static let advAppIntellKeys = ["rb2tKZxlj0Gm2tBmUQSLqQ", "M1n2sAqf33NAOgZRGxQYBA"]
    static let advAppIntellRules: [MGSlotRule] = [
        MGSlotRule(key: "rb2tKZxlj0Gm2tBmUQSLqQ", targetValue: true, required: false),
        MGSlotRule(key: "M1n2sAqf33NAOgZRGxQYBA", targetValue: true, required: false)
    ]
    static let regionCode = "h63QSdBCiT/z0WU6rdQv6Q"
    static let regionInfo = "zHeENZu+wbg7PUprwNwBWg"
    static let regionSysconfig = "yK+xavymRGZ3xWc1tb8XDg"
    static let regModelNumber = "97JDvERpVwO+GHtthIh7hA"
    static let audioMix = "aVL5GE3tx0LSCI/ErfrJGA"
    static let spatialAudioRec = "X6NGcYcvHmbqlR8hLXASJA"
    static let spatialFaceTimeAudio = "/EVOCjM/Nmb2roP5ebtEFA"
    static let spatialAudioAllKeys = ["X6NGcYcvHmbqlR8hLXASJA", "/EVOCjM/Nmb2roP5ebtEFA"]
    static let responsiveShutter = "gQDt76Te0SPw7N8oTLrBFw"
    static let hypertensionNotif = "4fh9efw4o1yaFqkXNCXoeA"
    static let mediaHealthAllKeys = ["aVL5GE3tx0LSCI/ErfrJGA", "X6NGcYcvHmbqlR8hLXASJA", "/EVOCjM/Nmb2roP5ebtEFA", "gQDt76Te0SPw7N8oTLrBFw", "4fh9efw4o1yaFqkXNCXoeA"]
    static let crashDet = "HCzWusHQwZDea6nNhaKndw"
    static let pwm = "6IejgN+1Fmu5/QrZFOIeNw"
    static let appPencil = "yhHcB0iH0d1XzPO/CFd3ow"
    static let camButton = "CwvKxM2cEogD3p+HYgaW0Q"
    static let grapPefr = "oOV1jhJbdV3AddkcCg0AEA"
    static let actButton = "cT44WE1EohiwRzhsZ8xEsw"
    static let tapToWake = "yZf3GTRMGTuwSV/lD7Cagw"
    static let stageMgr = "qeaj75wk3HF4DwQ8qbIi7g"
    static let deviceClass = "+3Uf0Pm5F8Xy7Onyvko0vA"
    static let artwork = "oPeik/9e8lQWMszEjbPzng"
    static let prodType = "h9jDsbgj7xIVeIQ8S3/X3Q"
    static let modelNameOuter1 = "Z/dqyWS6OZTRy10UcmUAhw"
    static let modelNameOuter2 = "bbtR9jQx50Fv5Af/affNtA"
    static let shutterRelaxation = "P4ZJVy/zYuLy4ejRKP+0DA"
    static let shutterKeyboardMutePreserve = "bGUN8lS6sYzy3xhePubp8A"
    static let shutterLegacyMutePreserve = "Bim3FC83Te8QX1kfSpqYKQ"
    static let concurrentHPLPMics = "dI30ovtFUIeLioNQKDMbGQ"
    static let photosLocalLight = "m9ORTKMgu9A+zF+A61Zz5A"
    static let toneMapping = "Lcu6Zck+C/+AMO8qULacDw"
    static let hdrDeferredProcessing = "JkZlE8z9YwHjE1hnbMhcgA"
    static let spatialOverCapture = "SjQQ07G8UacM7E69G7dPbg"
    static let stereoAudioRec = "YlK+0xmxNWhNn/+r8SM8kA"
    static let p3VideoRec = "1eBwtCIwbIDdC80wiyzfow"
    static let touchSensitiveCamControl = "lyJZrSDc8J8eQ5Zb7A1Rvw"
    static let hardwareDetents = "V9pLLbPQhyb75bbdTioZVw"
    static let cameraHaptics = "XriAxQ+JY1z5nt5f3ftXVw"
    static let legacyBatteryInfo = "Rq0MF/w+gXM66Ii4fkWOzg"
    static let legacyDynamicEndOfCharge = "nfR1IphTGCaoFNu3NrCtWQ"
    static let highLuminanceAOD = "7brdL5xrEUWnlF9C0kdg5A"
    static let aodFlipbook = "aoJSd/MXk7M40NgXTM6x+g"
    static let carPlay2 = "PR+xeEtTAiUN0R25+EYGfw"
    static let touchDelivery120Hz = "2OK50OGmkXM1ospsh766WQ"
    static let hearingAidEQ = "SMgTCc2v9AU2ziIHRX8qww"
    static let hearingAidLE = "RyXm3yMC4ejlFvwlEI509w"
    static let hearingAidPowerRed = "u3c0R+31Df4SUTHrICQkTg"
    static let breathingDisturbances = "e0HV2blYUDBk/MsMEQACNA"
    static let usBloodOxygen = "E4vGMChwcVRKD8hMVxnRvg"
    static let workoutUltra = "fu+4kyf8VcMBtgbMyJlLtg"
    static let timeInDaylight = "8gVfz9/8R1OtWBBtI0o/+Q"
    static let siriHub = "waGD2UTpntjbDXD1r3oALQ"
    static let onDeviceSiri = "O/7gbXWA5X2IRPVtDRU+bw"
    static let modelPruning = "m4xs4mhvxnAopYrApoLDMw"
    static let experimentalCacheSlotKeys: [String] = [
        shutterRelaxation, shutterKeyboardMutePreserve, shutterLegacyMutePreserve, concurrentHPLPMics,
        photosLocalLight, toneMapping, hdrDeferredProcessing, spatialOverCapture, stereoAudioRec, p3VideoRec,
        touchSensitiveCamControl, hardwareDetents, cameraHaptics, legacyBatteryInfo, legacyDynamicEndOfCharge,
        highLuminanceAOD, aodFlipbook, carPlay2, touchDelivery120Hz, hearingAidEQ, hearingAidLE, hearingAidPowerRed,
        breathingDisturbances, usBloodOxygen, workoutUltra, timeInDaylight, siriHub, onDeviceSiri, modelPruning
    ]
}

struct MGSlotRule: Equatable {
    let key: String
    let targetValue: Bool
    var required: Bool = true
}

final class GestaltStore: ObservableObject {
    static let shared = GestaltStore()
    
    @Published var mgCurrentDict = NSMutableDictionary()
    var cacheExtra: NSMutableDictionary {
        return mgCurrentDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
    }
    
    init() {}
    
    func originalCacheExtraValue(forKey key: String) -> Any? {
        guard let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL), let ogCacheExtra = ogDict["CacheExtra"] as? NSDictionary else { return nil }
        return ogCacheExtra[key]
    }
    
    func restoreOrRemoveKey(_ key: String) {
        if let ogVal = originalCacheExtraValue(forKey: key) { self.cacheExtra[key] = ogVal } else { self.cacheExtra.removeObject(forKey: key) }
    }
    func disableBooleanExtraKey(_ key: String, enableValue: Int = 1) {
        if let ogVal = originalCacheExtraValue(forKey: key) {
            if let ogNum = ogVal as? NSNumber, ogNum.intValue == enableValue { self.cacheExtra.removeObject(forKey: key) } else { self.cacheExtra[key] = ogVal }
        } else { self.cacheExtra.removeObject(forKey: key) }
    }
    func mgPullKeys(_ keys: [String], enableValue: Int = 1) { for key in keys { disableBooleanExtraKey(key, enableValue: enableValue) } }
    
    func isKeyEnabled(_ key: String, enableValue: Int = 1) -> Bool {
        if let num = self.cacheExtra[key] as? NSNumber, num.intValue == enableValue { return true }
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict),
           let slotIdx = layout.slotIndex(forKey: key), layout.validateSingleBooleanSlot(slotIdx, in: data), data[slotIdx * 8] == 1 {
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
            if !origVal { return true }
        }
        return false
    }

    func isEnabled(_ keys: [String], enableValue: Int = 1) -> Bool { guard !keys.isEmpty else { return false }; return keys.allSatisfy { self.isKeyEnabled($0, enableValue: enableValue) } }
    func strVal(forKey key: String) -> String { return self.cacheExtra[key] as? String ?? "" }
    
    func mgKeyBinding(_ keys: [String], defaultValue: Int = 0, enableValue: Int = 1) -> Binding<Bool> {
        return Binding(get: {
            guard !keys.isEmpty else { return false }
            return keys.allSatisfy { self.isKeyEnabled($0, enableValue: enableValue) }
        }, set: { enabled in
            self.objectWillChange.send()
            for key in keys { if enabled { self.cacheExtra[key] = enableValue } else { self.disableBooleanExtraKey(key, enableValue: enableValue) } }
            if case .success((let layout, var data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                var touchedSlot = false
                for key in keys {
                    if let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                        if enabled { data[slotIdx * 8] = (enableValue != 0) ? 1 : 0 } else {
                            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
                            data[slotIdx * 8] = origVal ? 1 : 0
                        }
                        touchedSlot = true
                    }
                }
                if touchedSlot {
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    testDict["CacheData"] = data
                    if case .success = layout.validatePlist(testDict) { self.mgCurrentDict["CacheData"] = data }
                }
            }
        })
    }
    
    func mgTrollPadBinding() -> Binding<Bool> {
        return Binding(get: {
            guard let firstKey = MGKey.ipadosCacheEx.first else { return false }
            return (self.cacheExtra[firstKey] as? NSNumber)?.intValue == 1
        }, set: { enabled in
            self.objectWillChange.send()
            _ = self.mgSetiPadOS(enable: enabled)
        })
    }
    
    // MARK: - Port 1:1 từ Gester (BQPatchIPadOSCacheData)
    func mgSetiPadOS(enable: Bool) -> Bool {
        guard let cacheData = mgCurrentDict["CacheData"] as? Data else {
            print("❌ Lỗi: Không đọc được CacheData")
            return false
        }

        let hexString = cacheData.map { String(format: "%02x", $0) }.joined()
        
        if hexString.count <= 1616 {
            print("❌ Lỗi: CacheData quá ngắn")
            return false
        }

        let sliceStart = 1616
        let sliceLength = min(200, hexString.count - 1616)
        let startIndex = hexString.index(hexString.startIndex, offsetBy: sliceStart)
        let endIndex = hexString.index(startIndex, offsetBy: sliceLength)
        let slice = String(hexString[startIndex..<endIndex])

        let pattern = "0+(?:5555)*([0-9a-f]{4})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            print("❌ Lỗi: Regex không hợp lệ")
            return false
        }

        var marker: Int? = nil
        let nsRange = NSRange(slice.startIndex..<slice.endIndex, in: slice)
        regex.enumerateMatches(in: slice, options: [], range: nsRange) { (match, _, stop) in
            guard let match = match, let r = Range(match.range(at: 1), in: slice) else { return }
            let value = String(slice[r])
            let nonzeroCount = value.filter { $0 != "0" }.count
            if nonzeroCount >= 3 {
                marker = sliceStart + slice.distance(from: slice.startIndex, to: r.lowerBound)
                stop.pointee = true
            }
        }

        guard let markerPos = marker else {
            print("❌ Lỗi: Không tìm thấy iPadOS marker trong CacheData")
            return false
        }

        let rightPos = markerPos + 13
        let leftPos = markerPos - 67

        guard leftPos > 0, rightPos < hexString.count - 1 else {
            print("❌ Lỗi: Offset của marker nằm ngoài phạm vi")
            return false
        }

        func charAt(_ index: Int) -> Character {
            return hexString[hexString.index(hexString.startIndex, offsetBy: index)]
        }

        for pos in [leftPos, rightPos] {
            let c = charAt(pos)
            if (c != "1" && c != "3") || charAt(pos - 1) != "0" || charAt(pos + 1) != "0" {
                print("❌ Lỗi: Xác thực marker iPadOS thất bại; không có thay đổi nào được thực hiện")
                return false
            }
        }

        var newHexArray = Array(hexString)
        newHexArray[leftPos] = enable ? "3" : "1"
        let newHexString = String(newHexArray)

        var newData = Data(capacity: newHexString.count / 2)
        var index = newHexString.startIndex
        while index < newHexString.endIndex {
            let nextIndex = newHexString.index(index, offsetBy: 2)
            guard let byte = UInt8(newHexString[index..<nextIndex], radix: 16) else {
                print("❌ Lỗi: Không thể chuyển hex thành byte")
                return false
            }
            newData.append(byte)
            index = nextIndex
        }

        self.mgCurrentDict["CacheData"] = newData

        let ipadKeys = MGKey.ipadosCacheEx
        for key in ipadKeys {
            if enable {
                self.cacheExtra[key] = 1
            } else {
                self.cacheExtra.removeObject(forKey: key)
            }
        }

        print("✅ Đã áp dụng vá iPadOS CacheData (enable = \(enable))")
        return true
    }
    
    var preferredRegionUnlockMode: MGRegionUnlockMode {
        get {
            let raw = UserDefaults.standard.string(forKey: MGRegionUnlockMode.defaultsKey) ?? MGRegionUnlockMode.fullUS.rawValue
            return MGRegionUnlockMode(rawValue: raw) ?? .fullUS
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: MGRegionUnlockMode.defaultsKey)
        }
    }

    var currentRegionUnlockMode: MGRegionUnlockMode {
        if (self.cacheExtra[MGKey.regionCode] as? String) == "LL" {
            return ((self.cacheExtra[MGKey.regionSysconfig] as? String) == "LL/A") ? .fullUS : .regionCodeOnly
        }
        return preferredRegionUnlockMode
    }

    func isConfirmedChinaHardwareFromCacheData() -> Bool {
        let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict, checkWapiSlot: true) {
            if let origFlags = MGCacheDataCoordinator.shared.originalFlags(for: layout, savedOriginalDict: savedOrig) {
                if origFlags.greenTea || origFlags.wapi == true { return true }
            }
            if let wOff = layout.wapiOffset, data[wOff] == 1 { return true }
        }
        return false
    }

    private func restoreNonUSRegionSysconfig() {
        if let ogSys = originalCacheExtraValue(forKey: MGKey.regionSysconfig) as? String, !ogSys.isEmpty {
            if ogSys == "LL/A" && isConfirmedChinaHardwareFromCacheData() { self.cacheExtra[MGKey.regionSysconfig] = "CH/A" } else { self.cacheExtra[MGKey.regionSysconfig] = ogSys }
        } else if isConfirmedChinaHardwareFromCacheData() { self.cacheExtra[MGKey.regionSysconfig] = "CH/A" } else { self.cacheExtra.removeObject(forKey: MGKey.regionSysconfig) }
    }

    private func restoreNonUSRegulatoryModel() {
        let prodType = originalHardwareProductType()
        if let ogReg = originalCacheExtraValue(forKey: MGKey.regModelNumber) as? String, !ogReg.isEmpty {
            if let usModel = usRegulatoryModelNumber(productType: prodType, originalRegModel: ""), ogReg == usModel, isConfirmedChinaHardwareFromCacheData(), let cnModel = chinaRegulatoryModelNumber(productType: prodType) {
                self.cacheExtra[MGKey.regModelNumber] = cnModel
            } else { self.cacheExtra[MGKey.regModelNumber] = ogReg }
        } else if isConfirmedChinaHardwareFromCacheData(), let cnModel = chinaRegulatoryModelNumber(productType: prodType) {
            self.cacheExtra[MGKey.regModelNumber] = cnModel
        } else { self.cacheExtra.removeObject(forKey: MGKey.regModelNumber) }
    }

    func mgRegionRestrictionsBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: { return self.cacheExtra[MGKey.regionCode] as? String == "LL" },
            set: { enabled in
                self.objectWillChange.send()
                if enabled {
                    Alertinator.shared.alert(title: L("解除地区限制提示"), body: MGMsg.region)
                    self.applyRegionUnlock(mode: self.preferredRegionUnlockMode)
                } else {
                    if let ogCode = self.originalCacheExtraValue(forKey: MGKey.regionCode) as? String, !ogCode.isEmpty {
                        if ogCode == "LL" && self.isConfirmedChinaHardwareFromCacheData() { self.cacheExtra[MGKey.regionCode] = "CH" } else { self.cacheExtra[MGKey.regionCode] = ogCode }
                    } else if self.isConfirmedChinaHardwareFromCacheData() { self.cacheExtra[MGKey.regionCode] = "CH" } else { self.cacheExtra.removeObject(forKey: MGKey.regionCode) }
                    if raveSupported() { self.cacheExtra.removeObject(forKey: MGKey.regionInfo) } else { self.restoreOrRemoveKey(MGKey.regionInfo) }
                    self.restoreNonUSRegionSysconfig()
                    self.restoreNonUSRegulatoryModel()
                }
            }
        )
    }

    func mgRegionUnlockModeBinding() -> Binding<MGRegionUnlockMode> {
        return Binding<MGRegionUnlockMode>(
            get: { return self.currentRegionUnlockMode },
            set: { newMode in
                self.objectWillChange.send()
                self.preferredRegionUnlockMode = newMode
                if (self.cacheExtra[MGKey.regionCode] as? String) == "LL" { self.applyRegionUnlock(mode: newMode) }
            }
        )
    }

    func applyRegionUnlock(mode: MGRegionUnlockMode) {
        self.cacheExtra[MGKey.regionCode] = "LL"
        switch mode {
        case .fullUS:
            self.cacheExtra[MGKey.regionSysconfig] = "LL/A"
            if !raveSupported(), self.originalCacheExtraValue(forKey: MGKey.regionInfo) != nil { self.cacheExtra[MGKey.regionInfo] = "LL/A" } else { self.cacheExtra.removeObject(forKey: MGKey.regionInfo) }
            let prodType = originalHardwareProductType()
            let ogRegModel = (self.originalCacheExtraValue(forKey: MGKey.regModelNumber) as? String) ?? (self.cacheExtra[MGKey.regModelNumber] as? String) ?? ""
            if let usModel = usRegulatoryModelNumber(productType: prodType, originalRegModel: ogRegModel) { self.cacheExtra[MGKey.regModelNumber] = usModel }
        case .regionCodeOnly:
            if raveSupported() { self.cacheExtra.removeObject(forKey: MGKey.regionInfo) } else { self.restoreOrRemoveKey(MGKey.regionInfo) }
            self.restoreNonUSRegionSysconfig()
            self.restoreNonUSRegulatoryModel()
        }
    }

    func applyUSRegionAndRegulatoryModel() { applyRegionUnlock(mode: .fullUS) }
    
    func mgRegModelBinding() -> Binding<String> {
        return Binding<String>(
            get: { return self.cacheExtra[MGKey.regModelNumber] as? String ?? "" },
            set: { newValue in
                self.objectWillChange.send()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { self.restoreOrRemoveKey(MGKey.regModelNumber) } else { self.cacheExtra[MGKey.regModelNumber] = trimmed }
            }
        )
    }

    func canModifyGreenTeaCache() -> Bool { if case .success = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) { return true }; return false }
    func canModifyWapiCache() -> Bool {
        if case .success((let layout, _)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict, checkWapiSlot: true), layout.wapiOffset != nil { return true }
        return false
    }
    func canModifyFeatureSlot(_ keys: [String]) -> Bool {
        guard !keys.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) else { return false }
        return keys.allSatisfy { key in guard let slotIdx = layout.featureSlotIndices[key] else { return false }; return layout.validateSingleBooleanSlot(slotIdx, in: data) }
    }
    func isFeatureSlotNativeEnabled(_ keys: [String]) -> Bool {
        guard !keys.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) else { return false }
        let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
        return keys.allSatisfy { key in
            guard let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) else { return false }
            return MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) == true
        }
    }
    func mgFeatureSlotBinding(_ keys: [String], infoTitle: String? = nil, infoMessage: String? = nil) -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                guard !keys.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) else { return false }
                return keys.allSatisfy { key in
                    guard let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) else { return false }
                    return data[slotIdx * 8] == 1
                }
            },
            set: { enabled in
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure(let err): Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: err.localizedDescription)
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    for key in keys {
                        guard let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) else {
                            Alertinator.shared.alert(title: L("当前系统不支持该槽位！"), body: L("未能在当前系统库与缓存中验证槽位 \(key) 的有效性，已拒绝修改。"))
                            return
                        }
                        if enabled { data[slotIdx * 8] = 1 } else {
                            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
                            data[slotIdx * 8] = origVal ? 1 : 0
                        }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    if let testExtra = testDict["CacheExtra"] as? NSMutableDictionary { for key in keys { testExtra.removeObject(forKey: key) } }
                    testDict["CacheData"] = data
                    switch layout.validatePlist(testDict) {
                    case .failure(let err): Alertinator.shared.alert(title: L("缓存数据校验未通过，已拒绝修改！"), body: err.localizedDescription)
                    case .success:
                        self.objectWillChange.send()
                        for key in keys { self.cacheExtra.removeObject(forKey: key) }
                        self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }

    func canModifySlotRules(_ rules: [MGSlotRule]) -> Bool {
        guard !rules.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) else { return false }
        var matchedCount = 0
        for rule in rules {
            if let slotIdx = layout.featureSlotIndices[rule.key], layout.validateSingleBooleanSlot(slotIdx, in: data) { matchedCount += 1 } else if rule.required { return false }
        }
        return matchedCount > 0
    }
    func isSlotRulesNativeSatisfied(_ rules: [MGSlotRule]) -> Bool {
        guard !rules.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) else { return false }
        let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
        var resolvedAny = false
        for rule in rules {
            guard let slotIdx = layout.featureSlotIndices[rule.key], layout.validateSingleBooleanSlot(slotIdx, in: data) else { if rule.required { return false }; continue }
            resolvedAny = true
            guard let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: rule.key, layout: layout, savedOriginalDict: savedOrig), origVal == rule.targetValue else { return false }
        }
        return resolvedAny
    }
    func mgSlotRulesBinding(_ rules: [MGSlotRule]) -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                guard !rules.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) else { return false }
                var resolvedAny = false
                for rule in rules {
                    guard let slotIdx = layout.featureSlotIndices[rule.key], layout.validateSingleBooleanSlot(slotIdx, in: data) else { if rule.required { return false }; continue }
                    resolvedAny = true
                    let currentBit = (data[slotIdx * 8] == 1)
                    if currentBit != rule.targetValue { return false }
                }
                return resolvedAny
            },
            set: { enabled in
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure(let err): Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: err.localizedDescription)
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    var touchedKeys: [String] = []
                    for rule in rules {
                        guard let slotIdx = layout.featureSlotIndices[rule.key], layout.validateSingleBooleanSlot(slotIdx, in: data) else {
                            if rule.required { Alertinator.shared.alert(title: L("当前系统不支持该实验性槽位！"), body: L("未能在当前系统库与缓存中验证槽位 \(rule.key) 的有效性，已拒绝修改。")); return }
                            continue
                        }
                        if enabled { data[slotIdx * 8] = rule.targetValue ? 1 : 0 } else {
                            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: rule.key, layout: layout, savedOriginalDict: savedOrig) ?? (!rule.targetValue)
                            data[slotIdx * 8] = origVal ? 1 : 0
                        }
                        touchedKeys.append(rule.key)
                    }
                    guard !touchedKeys.isEmpty else { return }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    if let testExtra = testDict["CacheExtra"] as? NSMutableDictionary { for key in touchedKeys { testExtra.removeObject(forKey: key) } }
                    testDict["CacheData"] = data
                    switch layout.validatePlist(testDict) {
                    case .failure(let err): Alertinator.shared.alert(title: L("缓存数据校验未通过，已拒绝修改！"), body: err.localizedDescription)
                    case .success:
                        self.objectWillChange.send()
                        for key in touchedKeys { self.cacheExtra.removeObject(forKey: key) }
                        self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }

    func isSiriHubConflictActive() -> Bool {
        if (self.cacheExtra[MGKey.siriHub] as? NSNumber)?.intValue == 1 { return true }
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict), let slotIdx = layout.featureSlotIndices[MGKey.siriHub], layout.validateSingleBooleanSlot(slotIdx, in: data), data[slotIdx * 8] == 1 {
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: MGKey.siriHub, layout: layout, savedOriginalDict: savedOrig) ?? false
            return !origVal
        }
        return false
    }
    func mgSafeSiriHubGuardrailBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: { return self.isSiriHubConflictActive() },
            set: { enabled in
                if enabled { Alertinator.shared.alert(title: L("安全护栏已拦截冲突开关！"), body: MGMsg.expSiriHubInfo); return }
                let groupKeys = [MGKey.siriHub, MGKey.onDeviceSiri, MGKey.modelPruning]
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure:
                    self.objectWillChange.send()
                    for k in groupKeys { self.disableBooleanExtraKey(k, enableValue: 1) }
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    for k in groupKeys {
                        if let slotIdx = layout.featureSlotIndices[k], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                            let origVal: Bool = (k == MGKey.siriHub) ? false : (MGCacheDataCoordinator.shared.originalSlotValue(forKey: k, layout: layout, savedOriginalDict: savedOrig) ?? false)
                            data[slotIdx * 8] = origVal ? 1 : 0
                        }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    if let testExtra = testDict["CacheExtra"] as? NSMutableDictionary { for k in groupKeys { testExtra.removeObject(forKey: k) } }
                    testDict["CacheData"] = data
                    if case .success = layout.validatePlist(testDict) {
                        self.objectWillChange.send()
                        for k in groupKeys { self.cacheExtra.removeObject(forKey: k) }
                        self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }
    func isPersonalTranslatorAccidentallyDisabled() -> Bool {
        guard isNativePersonalTranslatorHD() else { return false }
        if let num = self.cacheExtra[MGKey.personalTranslator] as? NSNumber, num.intValue == 0 { return true }
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict), let slotIdx = layout.featureSlotIndices[MGKey.personalTranslator], layout.validateSingleBooleanSlot(slotIdx, in: data), data[slotIdx * 8] == 0 { return true }
        return false
    }
    func isAdvAppleIntellConflictActive() -> Bool {
        if isAdvAppleIntellHD() { return false }
        for key in MGKey.advAppIntellKeys { if self.cacheExtra[key] != nil { return true } }
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            for key in MGKey.advAppIntellKeys {
                if let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                    let curVal = (data[slotIdx * 8] == 1)
                    let nativeVal = isAdvAISlotNativeTrue(key, layout: layout, savedOrig: savedOrig)
                    if curVal != nativeVal { return true }
                }
            }
        }
        return false
    }
    func mgSafeAdvAppleIntellGuardrailBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: { return self.isAdvAppleIntellConflictActive() },
            set: { enabled in
                if enabled { Alertinator.shared.alert(title: L("安全护栏已拦截冲突开关！"), body: MGMsg.advAppleIntell); return }
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure:
                    self.objectWillChange.send()
                    for k in MGKey.advAppIntellKeys { self.disableBooleanExtraKey(k, enableValue: 1) }
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    for k in MGKey.advAppIntellKeys {
                        if let slotIdx = layout.featureSlotIndices[k], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                            let nativeVal = isAdvAISlotNativeTrue(k, layout: layout, savedOrig: savedOrig)
                            data[slotIdx * 8] = nativeVal ? 1 : 0
                        }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    if let testExtra = testDict["CacheExtra"] as? NSMutableDictionary { for k in MGKey.advAppIntellKeys { testExtra.removeObject(forKey: k) } }
                    testDict["CacheData"] = data
                    if case .success = layout.validatePlist(testDict) {
                        self.objectWillChange.send()
                        for k in MGKey.advAppIntellKeys { self.cacheExtra.removeObject(forKey: k) }
                        self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }
    func applyAppleIntelligenceOneClickFix() {
        self.objectWillChange.send()
        self.applyRegionUnlock(mode: self.currentRegionUnlockMode)
        self.mgPullKeys([MGKey.intInstall, MGKey.intBuild, MGKey.siriHub] + MGKey.advAppIntellKeys)
        if case .success((let layout, var data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            let origFlags = MGCacheDataCoordinator.shared.originalFlags(for: layout, savedOriginalDict: savedOrig)
            let ogRegion = (self.originalCacheExtraValue(forKey: MGKey.regionCode) as? String) ?? ""
            if ogRegion == "CH" || ogRegion == "ZA" || origFlags?.greenTea == true || data[layout.greenTeaOffset] == 1 {
                data[layout.greenTeaOffset] = 0
                data[layout.notGreenTeaOffset] = 1
            }
            if let siriHubSlot = layout.featureSlotIndices[MGKey.siriHub], layout.validateSingleBooleanSlot(siriHubSlot, in: data), data[siriHubSlot * 8] == 1 {
                let origSiriHub = MGCacheDataCoordinator.shared.originalSlotValue(forKey: MGKey.siriHub, layout: layout, savedOriginalDict: savedOrig) ?? false
                if !origSiriHub {
                    data[siriHubSlot * 8] = 0
                    for k in [MGKey.onDeviceSiri, MGKey.modelPruning] {
                        if let idx = layout.featureSlotIndices[k], layout.validateSingleBooleanSlot(idx, in: data) {
                            let origV = MGCacheDataCoordinator.shared.originalSlotValue(forKey: k, layout: layout, savedOriginalDict: savedOrig) ?? false
                            data[idx * 8] = origV ? 1 : 0
                        }
                    }
                }
            }
            if !isAdvAppleIntellHD() {
                for key in MGKey.advAppIntellKeys {
                    if let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                        let nativeVal = isAdvAISlotNativeTrue(key, layout: layout, savedOrig: savedOrig)
                        data[slotIdx * 8] = nativeVal ? 1 : 0
                    }
                    self.cacheExtra.removeObject(forKey: key)
                }
            }
            if !isAppleIntellHD() {
                for key in MGKey.appIntellAllKeys {
                    self.cacheExtra[key] = 1
                    if let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) { data[slotIdx * 8] = 1 }
                }
            }
            let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
            testDict["CacheData"] = data
            if case .success = layout.validatePlist(testDict) { self.mgCurrentDict["CacheData"] = data }
        } else if !isAppleIntellHD() {
            for key in MGKey.appIntellAllKeys { self.cacheExtra[key] = 1 }
        }
    }
    func isAdvAppleIntellStagedOrActive() -> Bool { return isAdvAppleIntellConflictActive() }
    func cacheResolutionFailureReason() -> String? {
        switch MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) { case .success: return nil; case .failure(let err): return err.localizedDescription }
    }
    func mgChinaRestrictionCacheBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                guard case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) else { return false }
                return data[layout.greenTeaOffset] == 0 && data[layout.notGreenTeaOffset] == 1
            },
            set: { enabled in
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure(let err): Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: err.localizedDescription)
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    if enabled { data[layout.greenTeaOffset] = 0; data[layout.notGreenTeaOffset] = 1 }
                    else {
                        if let orig = MGCacheDataCoordinator.shared.originalFlags(for: layout, savedOriginalDict: savedOrig), !(orig.greenTea == false && orig.notGreenTea == true) {
                            data[layout.greenTeaOffset] = orig.greenTea ? 1 : 0
                            data[layout.notGreenTeaOffset] = orig.notGreenTea ? 1 : 0
                        } else { data[layout.greenTeaOffset] = 1; data[layout.notGreenTeaOffset] = 0 }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    testDict["CacheData"] = data
                    switch layout.validatePlist(testDict) {
                    case .failure(let err): Alertinator.shared.alert(title: L("缓存数据校验未通过，已拒绝修改！"), body: err.localizedDescription)
                    case .success: self.objectWillChange.send(); self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }
    func mgWapiWifiBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                guard case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict, checkWapiSlot: true), let wOff = layout.wapiOffset else { return false }
                return data[wOff] == 0
            },
            set: { enabled in
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict, checkWapiSlot: true) {
                case .failure(let err): Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: err.localizedDescription)
                case .success((let layout, var data)):
                    guard let wOff = layout.wapiOffset else { Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: L("当前系统库未能唯一解析 wapi 槽位偏移。")); return }
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    if enabled { data[wOff] = 0 } else {
                        if let orig = MGCacheDataCoordinator.shared.originalFlags(for: layout, savedOriginalDict: savedOrig), let origWapi = orig.wapi, origWapi == true { data[wOff] = 1 } else { data[wOff] = 1 }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    testDict["CacheData"] = data
                    switch layout.validatePlist(testDict, checkWapiSlot: true) {
                    case .failure(let err): Alertinator.shared.alert(title: L("缓存数据校验未通过，已拒绝修改！"), body: err.localizedDescription)
                    case .success:
                        self.objectWillChange.send(); self.mgCurrentDict["CacheData"] = data
                        if enabled { Alertinator.shared.alert(title: L("无线局域网改 Wi-Fi 重要提示"), body: MGMsg.wapiToWifi) }
                    }
                }
            }
        )
    }
}

// MARK: - EnsWilde Compat
extension GestaltStore {
    static func loadMutableDict(from url: URL) -> NSMutableDictionary? {
        guard let data = try? Data(contentsOf: url), let d = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else { return nil }
        return d
    }
    func loadFromPlist(url: URL) { if let d = Self.loadMutableDict(from: url) { mgCurrentDict = d; objectWillChange.send() } }
    func mgByteBinding(key: String, enableValue: UInt8 = 1, disableValue: UInt8 = 0) -> Binding<Bool> { return mgKeyBinding([key]) }
    func applyDynamicIsland(type: Int, customValue: Int? = nil) -> Bool {
        let subtypes = [0, 2436, 2556, 2796, 2976, 2622, 2868, 2736, 2662]
        guard let ce = mgCurrentDict["CacheExtra"] as? NSMutableDictionary else { return false }
        if type == 0 { (ce[MGKey.artwork] as? NSMutableDictionary)?.removeObject(forKey: "ArtworkDeviceSubType") }
        else if type > 0 && type < subtypes.count {
            let art = (ce[MGKey.artwork] as? NSMutableDictionary) ?? NSMutableDictionary()
            art["ArtworkDeviceSubType"] = subtypes[type]
            ce[MGKey.artwork] = art
        }
        objectWillChange.send()
        return true
    }
}
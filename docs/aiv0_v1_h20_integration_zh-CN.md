# AIV0 V1 – H20 HFP + BLE 控制

## 已采用的系统架构

- 双向音频使用 Bluetooth Classic HFP/SCO：
  - H20 麦克风 → APK；
  - APK → H20 扬声器。
- BLE 仅用于 MAIN 按键、电量、固件版本和 APP 状态。
- V1 APK 不通过 BLE 传输 PCM/Opus，也不使用 FF12/FF13/FF14。
- Web 版本不受影响。AIV0 BLE 控制功能仅在 Android APK 中启用。
- V1 没有独立的实体 REPLAY 按键。最近一句英语的重播功能保留在 APP 内。
- 电源键和音量键由 H20 本地处理。

## 当前 GATT 定义

| 功能 | UUID | 要求 |
|---|---|---|
| 控制服务（Control Service） | `9E3B0001-4A7C-4D6F-8B21-5C17A2D94010` | 必须支持 |
| 按键事件（Button Event） | `9E3B0002-4A7C-4D6F-8B21-5C17A2D94010` | Indicate + CCCD 2902 |
| APP 状态（APP State） | `9E3B0003-4A7C-4D6F-8B21-5C17A2D94010` | ODM 已确认支持 Write with response |
| 电池服务 | `180F / 2A19` | 读取电量百分比 |
| 固件版本 | `180A / 2A26` | 读取固件版本字符串 |

## ODM 确认 Raw Hex 前的安全模式

默认配置为 `AIV0_DRAFT_PROTOCOL_CONFIRMED=false`：

- APK 可连接 GATT、读取电量和固件版本，并接收 Indication。
- APK 在设置页面显示 MAIN 事件的接收时间和 Raw Hex。
- APK 暂不解析按键数据包，也不发送 8 字节 APP State 数据包。
- 实体 MAIN 按键暂不控制录音，避免在固件协议尚未确认时固定错误的数据格式。
- MAIN 以外的所有按键代码只记录 Raw Hex，不执行任何 APP 操作。

Android 手机连接电脑后，可使用以下命令获取 Raw Hex 日志：

```powershell
adb logcat -v time Aiv0BleControl:I *:S
```

ODM 提供 MAIN 的 Raw Hex 并确认每个字节的定义后，APP 端将根据实际协议更新 codec、运行测试，并使用以下命令构建功能版 APK：

```powershell
flutter build apk --release `
  --dart-define=BACKEND_BASE_URL=https://speaking-ai-nextjs-backend-production.up.railway.app `
  --dart-define=AIV0_DRAFT_PROTOCOL_CONFIRMED=true
```

V1 样机不得启用 `ENABLE_LEGACY_BLE_AUDIO` 或 `PREFER_BLE_STREAMING`。

## 协议确认后的 MAIN 按键流程

- MAIN：
  - IDLE/READY → 开始录音；
  - RECORDING → 停止录音并开始处理；
  - PROCESSING → 返回 BUSY；
  - PLAYING → 停止播放并开始新一轮录音。
- 重复数据包将被忽略，并返回 DUPLICATE。
- 在离线硬件测试页面中，MAIN 用于开始或停止本地录音，并通过 H20 播放录音；此流程不调用 backend。

## 离线硬件测试

设置页面中提供 `H20 离线硬件测试` 模式：

- 打开 HFP/SCO。只有当 Android 报告音频路由已激活，并能读取输入和输出设备名称时，APP 才确认正在使用 H20。
- 最长录音 5 秒，音频仅保存到手机本地，然后通过 H20 播放该录音。
- 可播放 APK 内置音频文件，以单独验证 H20 扬声器。
- 不调用 repository/backend，也不把音频上传到 cloud。
- 测试人员必须人工确认是否确实从 H20 扬声器听到声音。系统路由结果和人工听音确认分别记录。
- HFP 已连接但 SCO 尚未打开时，APP 显示 `尚未确认`，不会宣称正在使用 H20 麦克风或扬声器。
- APP 目前只显示电量百分比。在固件尚未通过 BLE 提供充电状态前，APP 不会推断或显示“正在充电”或“已充满”。

## ODM 仍需提供的数据

1. 当前 H20 固件的完整 GATT dump。
2. 实际按下一次 MAIN 时产生的完整 Raw Hex。
3. 确认每次按键只产生一次 Indication。
4. 确认 MAIN 是否包含 short press、long press、press 或 release 事件；如有多种事件，请分别提供对应 Raw Hex。
5. 确认 Button Event 为 12 字节、APP State 为 8 字节，并说明每个字节的含义及字节序。
6. 提供测试固件的 BLE 广播名称和固件版本。
7. 批量生产前确认：MCU 是否能够读取充电中/已充满状态，并通过 BLE 上报给 APP。

## 固件冻结前检查清单

- 测试页面正确显示当前实际使用的 HFP 麦克风和 HFP 扬声器。
- H20 能够采集真实语音，确认使用的不是手机麦克风。
- 英语音频从 H20 扬声器播放，并且播放过程中音频路由不会切换。
- MAIN：每次按键只产生一个事件，并且能够正确控制开始/停止录音。
- APP 能正确读取电量和固件版本。
- BLE 能够自动重连、重新发现服务并重新注册 Indicate。
- 日志中没有 FF12/FF13/FF14 音频请求或音频数据包。
- 无 Internet 时，BLE 扫描、HFP、MAIN 日志以及离线录音/播放仍可正常工作。

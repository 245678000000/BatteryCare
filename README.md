# 电池管家 BatteryCare

一款原生 macOS（SwiftUI）电池保养工具：充电限制、航海模式、过热保护、自动放电、校准模式、定时任务、菜单栏、悬浮窗、MagSafe LED 控制。

## 构建

```bash
./build.sh          # 产物：dist/BatteryCare.app
```

需要 Xcode 命令行工具（Swift 5.10+），macOS 14+。首次打开后点击左下角齿轮 → 安装辅助程序（需要管理员密码）。

## 工作原理

- `Sources/BatteryCare`：SwiftUI 应用，读取电池信息（IOKit / SMC），把设置写入 `/Users/Shared/BatteryCare/control.json`。
- `Sources/Helper`：以 root 运行的 LaunchDaemon，读取设置并写 SMC 键来控制充电，状态写入 `status.json`。
- `Sources/CSMC`：AppleSMC 读写的 C 封装。

| 固件 | 控制方式 |
| --- | --- |
| 较旧固件 | `CHTE` 或 `CH0B`/`CH0C` 直接暂停充电，`CHIE`/`CH0I` 强制放电 |
| macOS 27 固件 | 充电暂停键已被 Apple 锁定，改用 `CHIE` 断开适配器（适配器模式）：到达上限后由电池供电，回落几个百分点后恢复供电，睡眠前总会恢复供电 |

## 快捷指令

- 操作：`open batterycare://topup`、`pause`、`discharge`、`calibrate`、`limit/80`、`lowpower/on|off`
- 查询：`BatteryCare.app/Contents/Resources/batterycare-helper get percent|limit|state|temperature`

## 卸载

应用内「其他 → 删除电池管家」，或手动运行 `sudo Resources/uninstall-helper.sh`。

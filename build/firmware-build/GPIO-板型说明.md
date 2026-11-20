> **v3.35.2 起**：GPIO 改为运行时设置（`/api/system/can-gpio`），编译不再需要
> `-DP4CAN_BOARD_X179`。默认仍是 20/21、22/23、26/27；X179 首次开机在
> App「功能 → 高级与兼容 → CAN GPIO 设置」改成 4/5、2/3、26/27，保存后设备会停 CAN 并重启。
> 详见 `3.35.2-爆闪移植.md`。

# GPIO / 板型说明（P4-CAN Universal v3.29.3）

## 1. 两套引脚

`pin_config.h` 里只有两套映射，编译期二选一，没有运行时开关：

| 总线 | 默认（上游 README / 裸板飞线） | X179（"ESP32P4 WIFI6 3CAN" 扩展板） |
|---|---|---|
| CAN 1 BODY / VEH | GPIO **20** TX / **21** RX | GPIO **4** TX / **5** RX |
| CAN 2 CHASSIS / CH | GPIO **22** TX / **23** RX | GPIO **2** TX / **3** RX |
| CAN 3 PARTY / PT | GPIO **26** TX / **27** RX | GPIO **26** TX / **27** RX |

X179 板丝印的 CAN1/CAN2 与连接器是反的，所以代码按**总线名**映射，不按丝印编号。
如果线束把 CAN1 接到 9/10 BODY、CAN2 接到 13/14 CHASSIS（与 X179 相反），则交换前两对：
BODY=2/3、CHASSIS=4/5。

## 2. 怎么确认手里的 bin 用的是哪套

刷进去后请求：

```
curl -s http://192.168.4.1/api/system/stats
```

看两个字段：

- `canHarness`：`"X179 (2/3,4/5)"` 或 `"默认 (20-23)"`
- `canPins`：`"TX/RX, TX/RX, TX/RX"`，顺序 BODY、CHASSIS、PARTY

App 也能看：系统 → 诊断 → 系统统计里的 `canHarness` / `canPins`。

## 3. 编译上游固件

上游 README 写的是默认接线（20/21、22/23、26/27）。仓库里的 `pin_config.h` 已经带 X179 分支，
只是默认不启用；预编译 release 一般也是默认引脚。

### 3.1 命令行（Arduino CLI）

```bash
cd P4can-universal-unlock
arduino-cli compile \
  --fqbn "esp32:esp32:esp32p4:ChipVariant=postv3,FlashSize=32M,PartitionScheme=app5M_fat24M_32MB,PSRAM=enabled,USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio" \
  --build-property compiler.cpp.extra_flags=-DP4CAN_BOARD_X179 \
  --output-dir out-x179 .
```

- X179 线束：保留 `--build-property ...=-DP4CAN_BOARD_X179`
- 默认线束：删掉这一行
- 芯片是 V1.x 时把 `ChipVariant=postv3` 改成 `prev3`（以芯片 revision 为准）

### 3.2 Arduino IDE

`pin_config.h` 顶部、`#if defined(P4CAN_BOARD_X179)` 之前加一行：

```c
#define P4CAN_BOARD_X179 1
```

再按 README 的 Board / Flash Size / Partition / PSRAM / USB 设置编译即可。
不要改 `#else` 分支里的 20-23，直接定义宏更不容易漏。

## 4. 本仓库出过的包

| 文件 | 引脚 | 说明 |
|---|---|---|
| `P4CAN-v3.29.3-fix3-20261119.ino.bin` | 默认 20-23 | 审查修复前 |
| `P4CAN-v3.29.3-fix4-20261119.ino.bin` | 默认 20-23 | 审查修复后，但漏了 X179 宏 |
| `P4CAN-v3.29.3-fix5-X179-20261120.ino.bin` | **X179 2/3、4/5** | 审查修复 + 正确引脚 |

以后统一用 `build-firmware.sh x179` 或 `build-firmware.sh default` 编译，避免再漏宏。

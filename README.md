# moon_nes

用 MoonBit 编写的 NES（红白机）模拟器。核心与平台无关，可以编译到 js、wasm-gc、native 三个后端；附带一个浏览器前端和几个命令行工具。

## 定位

NES 的硬件行为有完整的公开文档（[NESdev Wiki](https://www.nesdev.org/wiki/)），社区也有公认的测试 ROM，模拟得对不对可以客观验证。MoonBit 生态里此前没有 NES 模拟器，也没有 6502 CPU 实现；最接近的是 [sacckey/lunaboy](https://github.com/sacckey/lunaboy)（Game Boy），CPU 和整机结构都不同。

本项目从零实现了 2A03 CPU、2C02 PPU 和四种常见卡带映射器，以周期为单位精确同步，并用 nestest 日志和 69 个测试 ROM 逐项验证。

## 支持范围

| 部分 | 内容 |
|---|---|
| 卡带 | iNES 解析、NES 2.0 头识别（12 位映射器号、子映射器、指数形式的 ROM 大小、RAM 大小字段）、trainer、兼容 "DiskDude!" 脏头；非法或截断的文件返回 `RomError`，不会崩溃 |
| CPU | 2A03（6502，无十进制模式）：151 条官方指令和常见非官方指令（LAX、SAX、DCP、ISB、SLO、RLA、SRE、RRA、ANC、ALR、ARR、AXS、LAS、SHA/SHX/SHY/TAS、各类 NOP、JAM）；每个周期一次总线访问，包括 dummy read/write；NMI 边沿检测、IRQ 电平触发、在倒数第二个周期采样中断、BRK/IRQ 被 NMI 劫持、同页跳转分支少采样一次 |
| PPU | 逐点推进（262 行 × 341 点）；背景取数流水线和 16 位移位寄存器；loopy v/t/x/w 滚动；精灵求值（含溢出标志的斜向扫描 bug 和置位时刻）；精灵 0 碰撞、优先级、左 8 像素裁剪、8×16 精灵；VBlank/NMI 时序及 `$2002` 读取抑制；奇数帧跳点；`$2007` 读缓冲；调色板镜像；开路总线衰减 |
| 映射器 | 0 NROM、1 MMC1（SxROM/SNROM/SUROM，5 位串行移位寄存器，忽略相邻周期的连续写，MMC1B 的 PRG RAM 禁用）、2 UxROM、3 CNROM |
| 其他 | 标准手柄（`$4016/$4017`）、OAM DMA（513/514 周期）、APU **计时部分**：帧计数器、帧 IRQ、四个长度计数器（不发声，见下文） |
| API | `Nes::load_rom`、`run_frame`、`frame_buffer`（256×240）、`write_rgba`、`set_buttons`、`reset`、`frame_hash` |

APU 说明：MVP 不做声音。但帧计数器是这些卡带上唯一的 IRQ 源，而且很多 CPU 测试 ROM 用 `$4015` 的长度计数器状态来计时，所以实现了 APU 中与计时相关的部分（`src/apu`），不生成任何波形。

不支持：声音、MMC3 和其他映射器、存档和即时存档、32 KiB WRAM 分页的 SXROM/SOROM、PAL 机型。

## 测试结果

`moon test` 在 js、wasm-gc、native 三个后端都通过（57 个测试）。下面这张表由 `moon run src/cmd/testroms` 生成，**69 个 ROM 中 68 个通过**。

### CPU

| 测试 ROM | 测什么 | 结果 |
|---|---|---|
| nestest.nes + nestest.log | 全部官方指令和非官方指令的结果、标志位、周期数；与参考日志的 8991 行逐行对比，包括内存注释和 PPU 位置 | ✅ 8991/8991 行一致 |
| instr_test-v5 01–16 | 每条指令在各寻址模式下的结果（含非官方指令） | ✅ 16/16 |
| instr_timing 1-instr_timing、2-branch_timing | 每条指令的周期数、分支的周期数 | ✅ 2/2 |
| instr_misc 01–04 | abs,X 环绕、分支环绕、dummy read（含 APU 寄存器） | ✅ 4/4 |
| cpu_dummy_reads | LDA/STA 各寻址模式产生的 dummy read 对 PPU 寄存器的副作用 | ✅ |
| cpu_interrupts_v2 1–5 | CLI 延迟、NMI 与 BRK、NMI 与 IRQ、IRQ 与 DMA、分支延迟 IRQ | ✅ 5/5 |

### PPU

| 测试 ROM | 测什么 | 结果 |
|---|---|---|
| ppu_vbl_nmi 01–10 | VBL 置位/清除时刻、NMI 开关时序、`$2002` 抑制、奇偶帧跳点 | ✅ 10/10 |
| sprite_hit_tests_2005.10.05 01–11 | 精灵 0 碰撞：基础、对齐、角、翻转、左裁剪、右边缘、屏幕底部、8×16、时序 | ✅ 11/11 |
| sprite_overflow_tests 1–5 | 精灵溢出：基础、细节、时序、硬件 bug、模拟器常见错误 | ✅ 5/5 |
| blargg_ppu_tests_2005.09.15b palette_ram、power_up_palette、sprite_ram、vram_access | 调色板读写与镜像、上电调色板、OAM 读写、VRAM 读缓冲 | ✅ 4/4 |
| blargg_ppu_tests_2005.09.15b vbl_clear_time | VBL 在 NMI 之后约 2270 周期清除 | ❌ code 2（判定 VBL 清除得太早） |
| oam_read | `$2004` 读取 | ✅ |
| ppu_open_bus | PPU 开路总线及衰减 | ✅ |

`vbl_clear_time` 是 2005 年的旧测试，只给 NMI 延迟留了约 4 个周期的余量，对上电时 CPU 与 PPU 的相位很敏感。测同一件事的新版测试 `ppu_vbl_nmi/03-vbl_clear_time` 和 `05-nmi_timing` 都已通过。

### 映射器

使用 [Holy Mapperel](https://github.com/pinobatch/holy-mapperel) v0.02（zlib 许可，ROM 随仓库提交）。它会自动识别映射器，检查每个 PRG/CHR bank、镜像方式和 PRG RAM，最后打印 4 位详细码，`0000` 表示全部正确。测试从名称表里读出映射器号和详细码来判定。

| ROM | 板子 | 结果 |
|---|---|---|
| M0_P32K_C8K_V | NROM，CHR ROM | ✅ 0000 |
| M0_P32K_CR8K_V | NROM，CHR RAM | ✅ 0000 |
| M1_P128K_C32K | MMC1，CHR ROM | ✅ 0000 |
| M1_P128K_CR8K | MMC1 SNROM，CHR RAM | ✅ 0000 |
| M1_P512K_CR8K_S8K | MMC1 SUROM，512 KiB PRG | ✅ 0000 |
| M2_P128K_V、M2_P128K_CR8K_V | UxROM | ✅ 0000 ×2 |
| M3_P32K_C32K_H | CNROM | ✅ 0000 |

此外还有一个自制演示 ROM（见下文），在测试里模拟手柄输入，检查精灵坐标和画面。

### 其他测试

- **画面回归**：6 个 ROM（4 个 Holy Mapperel、sprite hit、instr_test）运行固定帧数后，帧缓冲的 FNV-1a 哈希写在快照里；三个后端算出的哈希完全一致（`src/nes/frame_hash_test.mbt`、`src/demo/demo_test.mbt`）。
- **边界情况**：空文件、不足 16 字节、签名错误、PRG/CHR/trainer 截断、PRG 大小为 0、不支持的映射器（含 NES 2.0 的 256 号以上）都返回带说明的 `RomError`（`src/cartridge/cartridge_test.mbt`、`src/nes/nes_test.mbt`）。
- **单元测试**：CPU 中断与 DMA 周期、映射器 bank 切换、MMC1 串行写、APU 帧 IRQ 与长度计数器、总线镜像、手柄移位顺序等。

测试 ROM 结果会和 `src/nes/rom_suite_test.mbt` 里的「已知未通过」清单对比：清单外的 ROM 没过算回归；清单内的 ROM 变成通过也会报错，提醒更新清单和这张表。

## 如何运行

需要 MoonBit 工具链（开发时使用 moon 0.1.20261016 / moonc v0.10.16）。

```bash
# 下载社区测试 ROM（不随仓库分发）
sh scripts/fetch-test-roms.sh

# 三个后端的测试
moon test --target js
moon test --target wasm-gc
moon test --target native

# 命令行示例：运行 nestest，与 nestest.log 逐行对照（加 -- --all 输出每一行）
moon run src/cmd/nestest

# 运行全部测试 ROM，输出 Markdown 结果表；可以加一个路径过滤词
moon run src/cmd/testroms --target native --release
moon run src/cmd/testroms --target native -- ppu_vbl

# 性能测试：无界面运行 600 帧
moon run src/cmd/bench --release --target js -- test-roms/holy-mapperel/M1_P128K_C32K.nes

# 打印某个 ROM 运行若干帧后的屏幕文字和帧哈希
moon run src/cmd/screen -- test-roms/holy-mapperel/M2_P128K_V.nes 600
```

### 浏览器

```bash
sh scripts/build-web.sh
python -m http.server -d web 8000
```

然后打开 <http://localhost:8000>，点 **Open ROM…** 或把 `.nes` 文件拖进画面，也可以点 **Run demo** 运行内置演示。按键：方向键 = 十字键，`X`/`K` = A，`Z`/`J` = B，`Enter` = Start，`Shift` = Select。ROM 文件只在浏览器本地读取，不会上传。

性能（600 帧，Holy Mapperel MMC1 ROM，release 构建）：native 约 1040 fps，wasm-gc 约 640 fps，js 约 420 fps，都远超 NES 的 60 fps。

## 结构

```
src/cartridge  iNES / NES 2.0 解析 → Cartridge
src/mapper     Mapper trait + NROM / MMC1 / UxROM / CNROM
src/cpu        CpuBus trait + 2A03 核心 + 反汇编和 nestest 格式跟踪
src/ppu        逐点 PPU
src/apu        APU 计时部分（帧计数器、长度计数器）
src/bus        CPU 地址空间：RAM、PPU/APU 寄存器、手柄、DMA，实现 CpuBus
src/nes        整机和对外 API、调色板、测试 ROM 判定
src/demo       迷你 6502 汇编器 + 自制演示 ROM
src/web        浏览器前端（只编译到 js）
src/cmd/*      nestest、testroms、bench、screen 命令行工具
web/           页面
```

依赖方向是 cartridge ← mapper ← ppu ← bus ← nes ← web/cmd。cpu 不依赖任何包，只声明 `CpuBus` trait，因此可以单独接一块平坦 RAM 跑 nestest。

**CPU 与 PPU 的同步**：CPU 的每次读写正好是一个周期。总线在访问前让 PPU 走 2 个点、APU 走一步，访问后再走 1 个点，所以每个 CPU 周期是 3 个 PPU 点。CPU 在每个周期结束时采样中断线。把访问放在第 2 和第 3 个点之间，是 `ppu_vbl_nmi` 各项时序测试共同要求的位置。

## 演示 ROM

`src/demo` 里有一个很小的 6502 汇编器（标签、分支偏移和地址回填），演示 ROM 在运行时由 MoonBit 代码汇编生成：屏幕上显示文字，十字键移动一个 16×16 的月亮精灵，按住 A 切换调色板。它完全由本仓库的代码生成，按本仓库的许可证分发，所以网页可以直接内置，不需要任何第三方 ROM。

## 参考范围

- 主要依据：NESdev Wiki 的硬件文档，包括 CPU、CPU interrupts、PPU rendering、PPU scrolling、PPU sprite evaluation、PPU registers、APU Frame Counter、APU Length Counter、iNES、NES 2.0、NROM、MMC1、UxROM、CNROM、NTSC video 等页面。
- 测试 ROM 的 readme 和源码注释：只用来了解每个测试的判定方式和期望输出。
- 没有参考任何其他模拟器的源代码，GPL 项目的代码一律没有看。调色板由 NESdev Wiki 记载的 NTSC 信号电平自行计算生成。

## 版权说明

- 本仓库**不包含、也不提供**任何商业游戏 ROM。浏览器前端只在本地读取用户自己提供的文件。
- 社区测试 ROM（blargg 的系列测试、kevtris 的 nestest 等）没有明确的再分发许可，所以不提交进仓库，由 `scripts/fetch-test-roms.sh` 从固定 commit 的 [christopherpow/nes-test-roms](https://github.com/christopherpow/nes-test-roms) 下载（CI 中同样如此）。
- `test-roms/holy-mapperel/` 中的 ROM 来自 Holy Mapperel v0.02，作者 Damian Yerrick，zlib 许可（允许再分发），原样提交并附带其 `LICENSE`。
- 演示 ROM 由本仓库代码生成。

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。

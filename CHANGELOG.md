# Changelog

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增

- 声音。APU 的五个声道全部实现：
  - 帧计数器在原有的半帧时钟之外，加上 1/4 帧时钟（驱动包络和三角波的线性计数器）。
  - 两个方波：包络、扫频，周期过短或扫频溢出时静音。
  - 三角波：线性计数器，停住时保持当前电平。
  - 噪声：15 位 LFSR，有长、短两种模式。
  - DMC：内存读取器、1 字节缓冲、IRQ、循环。
- DMC DMA：取样本时 CPU 停 3–4 个周期（在 OAM DMA 中停 2 个），停顿期间重复 CPU 原本的读。`CpuBus` 新增两个带默认实现的方法，其他总线实现不受影响。
- 混音用 NESdev Wiki 的精确非线性公式。输出按区间平均降到输出采样率，再经过 90 Hz 高通和 14 kHz 低通。三个后端产生的采样逐位一致。
- 新 API：`Nes::set_sample_rate`、`samples_available`、`take_samples`；`Apu::reset`、`Apu::output`。
- 上电和按复位键时 APU 的状态：写 `$00` 到 `$4015`，重写最后一次的 `$4017`。
- 演示 ROM 加上四声道背景音乐，按住 A 播放 DMC 采样；画面不变。
- 浏览器前端用 Web Audio（AudioWorklet）播放声音：动态速率控制把缓冲保持在约 50 ms，另有静音按钮。
- 测试 ROM 套件新增 APU 区，共 30 个 ROM（`apu_test`、`apu_reset`、`blargg_apu_2005.07.30`、`dmc_dma_during_read4`），通过 27 个。新增判定方式 `ScreenCrc` 和 `ScreenCode`。
- 声音回归测试：演示 ROM 300 帧采样的哈希。
- MMC3（mapper 4）：PRG/CHR bank 切换、A12 反转、H/V 镜像（四屏幕卡带除外）、`$A001` 的 PRG RAM 开关和写保护、按 PPU A12 上升沿计数的扫描线 IRQ（带滤波）。NES 2.0 子映射器 4 使用 MMC3A 的 IRQ 规则。
- `Mapper` trait 新增两个带默认实现的方法：`ppu_bus`（PPU 地址总线）和 `irq_line`；总线把映射器的 IRQ 并入 CPU 的 IRQ。
- PPU 的 8 个精灵槽在第 257–320 点按实机时刻取图案，空槽读 tile $FF，预渲染行也取。画面不变。
- 测试：blargg 的 `mmc3_test_2`、`mmc3_test`、`mmc3_irq_tests`（18 个，通过 15 个；另外 3 个测的是 MMC3A/MMC6，改成子映射器 4 后通过）；Holy Mapperel 的 4 个 MMC3 ROM（zlib 许可，提交进仓库，全部 0000）；MMC3 的帧哈希。
- 屏幕判定也接受大写的 PASSED/FAILED（2005 年的测试）。

### 修复

- 测试 ROM 的 blargg 判定在复位后会把 `$6000` 里残留的 `$81` 当成新的复位请求，导致测试被提前复位。
- `scripts/fetch-test-roms.sh` 给 curl 加了超时，并先写入临时文件，下载完整后再改名；中断的下载不会再留下被当作完整文件的残缺 ROM。

### 变化

- 开着声音时 native 速度从约 1040 fps 降到约 870 fps；`set_sample_rate(0)` 可以关掉声音。
- 精灵按实机时刻取数后，native 又慢了约 6%，js 约 13%。
- 不支持映射器的测试改用 mapper 5。

## [0.1.0] - 2026-11-19

第一个版本。

### 新增

- 卡带：iNES 解析和 NES 2.0 头识别，包括 12 位映射器号、子映射器、指数形式的 ROM 大小和 RAM 大小字段。支持 trainer，兼容 "DiskDude!" 脏头。非法、截断的文件和不支持的映射器返回 `RomError`，不会崩溃。
- CPU：2A03 核心，`CpuBus` trait 让它可以单独接其他总线。
  - 官方指令全部实现，常见的非官方指令也实现了。
  - 每个周期一次总线访问，包括 dummy read/write。
  - NMI/IRQ 在倒数第二个周期采样；同页跳转的分支少采样一次。
  - 带反汇编器和 nestest 格式的跟踪输出。
- PPU：逐点推进，具体包括：
  - 背景移位寄存器、loopy 滚动。
  - 精灵求值，含溢出 bug 和置位时刻；精灵 0 碰撞；8×16 精灵。
  - VBlank/NMI 时序和 `$2002` 读取抑制；奇数帧跳点。
  - 开路总线衰减、上电调色板。
- 映射器：0 NROM、1 MMC1、2 UxROM、3 CNROM。
- 手柄、OAM DMA，以及 APU 的计时部分：帧计数器、帧 IRQ、长度计数器，不发声。
- 整机 API：`Nes::load_rom`、`run_frame`、`frame_buffer`、`write_rgba`、`set_buttons`、`reset`、`frame_hash`、`screen_text`。
- 自制演示 ROM：由内置的迷你 6502 汇编器生成。
- 浏览器前端：canvas 显示、键盘操作、加载本地 ROM。
- 命令行工具：`nestest`、`testroms`、`bench`、`screen`。
- README 里的最小使用示例 `src/examples/basic`，有测试保证 README 中的代码与它逐字一致。
- CI 覆盖 Linux、macOS、Windows：
  - 检查：`moon check --deny-warn`、`moon fmt --check`。
  - 构建：`moon build --target all`；接口文件与 `moon info` 的结果一致。
  - 测试：js、wasm-gc、native 三个后端的 `moon test`。
- 发布配置：`.moonignore` 让发布包只含 `LICENSE`、`README.md`、`moon.mod` 和 `src/`，测试 ROM 和网页不进发布包。

### 测试结果

- nestest：8991 行全部一致，包括 PPU 列。
- 测试 ROM：69 个中 68 个通过。未通过的是 2005 年版本的 `vbl_clear_time`。
- Holy Mapperel：8 个 ROM 全部报告 0000。

[未发布]: https://github.com/sayoi7799/moon_nes/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sayoi7799/moon_nes/releases/tag/v0.1.0

# Changelog

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

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

[0.1.0]: https://github.com/sayoi7799/moon_nes/releases/tag/v0.1.0

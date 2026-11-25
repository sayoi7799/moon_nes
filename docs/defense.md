# moon_nes 答辩要点

每一节几句话，括号里是对应的代码或测试，方便当场打开给评委看。

## 1. CPU 和 PPU 怎么同步

- CPU 的每一次读写正好是一个 CPU 周期。dummy read/write 也照实机发出，所以每条指令的周期数和总线上的访问顺序都与硬件一致（`src/cpu/cpu.mbt` 的 `rd`/`wr`）。
- NTSC 的 PPU 时钟是 CPU 的 3 倍，所以每个 CPU 周期让 PPU 走 3 个点。总线在访问之前走 2 个点、推进 APU 一步，访问之后再走第 3 个点（`src/bus/bus.mbt` 的 `before_access`/`after_access`）。CPU 在每个周期结束时采样中断线，决定是否响应中断时用的是倒数第二个周期的采样。
- 为什么把访问放在第 2 和第 3 个点之间：VBlank 标志在第 241 行第 1 点置位，读 `$2002` 正好落在这一点时，会读到 0 并且这一帧既不置位也不触发 NMI（`src/ppu/ppu.mbt` 的 `read_register`）。CPU 的读发生在周期中间，访问放在周期开头或结尾，相对这个点都会差一个点，`ppu_vbl_nmi` 的 05–08（NMI 时刻、`$2002` 抑制、NMI 开关时刻）一直过不了。改成 2+1 之后这四个测试全部通过，而且没有让其他测试退步。
- 一个周期内的这三个点也决定了 NMI 的时机：NMI 线是"VBlank 标志 且 `$2000` 第 7 位"，在第 3 个点之后才被 CPU 采样，所以同一个周期里置位的标志能赶上这一周期的采样。

## 2. 逐点 PPU

- **推进方式**：每次只走一个点，一帧 262 行 × 341 点。奇数帧在开着渲染时预渲染行少一个点，是否跳过在第 338 点采样（`Ppu::step`、`Ppu::advance`）。
- **背景取数流水线**：第 1–256 点和第 321–336 点，每 8 个点为一组，依次读名称表、属性、图案低字节、图案高字节（`fetch_background`）。取到的数据在下一组开头装进 16 位移位寄存器，每个点左移一位，输出像素时按 fine X 取其中一位（`reload_shifters`、`shift_background`、`render_pixel`）。所以画面中途改 `$2000`/`$2001` 或滚动，效果会精确到出现在哪个像素。
- **loopy 滚动**：v（当前地址）、t（临时地址）、x（fine X）、w（写入开关）四个寄存器。`$2005`/`$2006` 写的是 t，只在第二次写 `$2006` 时把 t 复制给 v。渲染时，每组第 8 点 v 的 coarse X 加一；第 256 点 Y 加一；第 257 点把 t 的水平部分复制给 v；预渲染行第 280–304 点把 t 的垂直部分复制给 v（`inc_coarse_x`、`inc_y`、`copy_x`、`copy_y`）。
- **精灵**：第 65 点对下一行做精灵求值，包括溢出标志的斜向扫描 bug 和置位时刻（`evaluate_sprites`）。第 257–320 点给 8 个精灵槽按实机时刻取图案，空槽读 tile `$FF`，预渲染行也取（`fetch_sprites`）。MMC3 的扫描线计数器看的正是这些取数在 PPU 地址线 A12 上造成的变化。
- **精灵 0 碰撞**：当精灵 0 在这一行、它的像素和背景像素都不透明、背景和精灵都开着、x 不是 255，并且不在被左 8 像素裁剪掉的区域时，置位 `$2002` 的第 6 位；预渲染行第 1 点清除（`render_pixel`）。`sprite_hit_tests` 的 11 个测试覆盖了对齐、角、翻转、裁剪、右边缘、屏幕底部、8×16 和时序。

## 3. 正确性怎么验证

- **nestest 逐行对照**：nestest 有一份参考日志，记录了 8991 条指令执行前的 PC、指令字节、反汇编、寄存器、PPU 位置和周期数。模拟器按同样的格式输出每一行，逐字比较，第一处不同就报错并给出两行内容。CPU 单独跑一遍（平坦内存），整机再跑一遍（含 PPU 列）（`src/cpu/nestest_test.mbt`、`src/nes/nestest_test.mbt`，命令行 `moon run src/cmd/nestest`）。
- **测试 ROM 的判定方式**：社区测试 ROM 会自己报告结果，判定只读它们的报告，不靠人眼（`src/nes/testrom.mbt`）。
  - blargg 新版：`$6000` 是状态码，`$6001–$6003` 是签名 `DE B0 61`，`$6004` 起是文字；状态 `$81` 表示要按复位键，判定程序会等 10 帧后复位。
  - blargg 2005 年版：结果码在零页，CPU 停在 `JMP *` 时读取；APU 的 2005 年版看屏幕上的 `$XX`。
  - 只在屏幕上打印的测试：在名称表里找 Passed/Failed；打印 CRC 的测试要求 CRC 属于测试源码里列出的实机结果。
  - Holy Mapperel：从屏幕读出它识别出的映射器号和 4 位详细码，必须是 `0000`。
- **已知未通过清单**：`src/nes/rom_suite_test.mbt` 里的清单写着每个没通过的 ROM 和原因。测试是双向的：清单外的 ROM 没过，算回归，测试失败；清单里的 ROM 变成通过，也算失败，提醒更新清单和 README 的结果表。所以 README 上的数字不会和实际情况脱节。
- **画面和声音回归**：9 个 ROM 运行固定帧数后，对帧缓冲算 FNV-1a 哈希，写进快照；演示 ROM 300 帧的采样量化成 16 位后也算哈希（`src/nes/frame_hash_test.mbt`、`src/demo/demo_test.mbt`）。混音和滤波只用加减乘除，所以 js、wasm-gc、native 三个后端的结果逐位相同，快照在三个后端上都成立。
- **CI**：每次推送都在 Linux、macOS、Windows 上运行严格检查、格式检查、全部后端的构建、接口文件比对、三个后端的 `moon test`，再跑 nestest 和测试 ROM 结果表（`.github/workflows/ci.yml`）。

## 4. 版权的处理

- **为什么测试 ROM 在 CI 里下载**：blargg、kevtris 等人的社区测试 ROM 被广泛使用，但没有写明再分发许可。没有许可就不能放进仓库，所以 `scripts/fetch-test-roms.sh` 在测试时从固定 commit 的 nes-test-roms 下载，CI 也一样。下载目录在 `.gitignore` 里，不会被误提交。
- **能提交的只有许可明确的**：Holy Mapperel（zlib）、Snake 和 Pong（zlib）都是作者发布的原版文件，未作修改，旁边附许可证原文和来源；许可证文本逐字节保留（`test-roms/holy-mapperel/`、`web/roms/`）。
- **演示 ROM 为什么是自己汇编生成的**：网页需要一个打开就能运行的程序，但找不到许可明确、又能直接放进仓库的合适 ROM。所以写了一个很小的 6502 汇编器，用 MoonBit 代码在运行时生成演示 ROM（文字、可移动的月亮精灵、四声道音乐、DMC 采样）。它完全是本仓库的代码，按本仓库的 Apache-2.0 分发；背景音乐用的是公有领域的民歌（`src/demo/asm.mbt`、`src/demo/demo.mbt`）。
- **商业游戏 ROM 一个都没有**。网页只在浏览器本地读取用户自己选的文件，不上传。参考资料只用 NESdev Wiki 和测试 ROM 自带的说明，没有看过 GPL 模拟器的代码。

## 5. 和 lunaboy（Game Boy 模拟器）的区别

[sacckey/lunaboy](https://github.com/sacckey/lunaboy) 是在 mooncakes.io 上搜 nes、emulator 时找到的唯一另一个游戏机模拟器（MIT 许可），也有声音和浏览器版本。两者是不同的机器、不同的目标，下面只列从它的代码里能核实的差别。

- **硬件不同**：lunaboy 模拟 Game Boy（SM83 CPU），moon_nes 模拟 NES（6502 CPU，加上独立的 2C02 PPU 和 APU）。指令集、总线、显示芯片都不一样，代码之间没有可复用的部分。
- **PPU 的粒度**：lunaboy 的 PPU 是按机器周期计数的模式状态机（OAM 扫描 20、绘制 43），在绘制模式结束时一次画出整行。moon_nes 的 PPU 一个点一个点地推进，取数流水线和滚动寄存器都按点更新；这是 `ppu_vbl_nmi`、精灵 0 碰撞时序、MMC3 扫描线时序这些测试要求的精度。
- **卡带**：lunaboy 支持无 MBC 和 MBC1 两种；moon_nes 支持 NROM、MMC1、UxROM、CNROM、MMC3 五种，覆盖了 NES 游戏的大部分。
- **验证方式**：我在 lunaboy 的仓库里没有找到对测试 ROM 的自动判定或运行测试的 CI。moon_nes 每次提交都在 3 个操作系统 × 3 个后端上跑 nestest 逐行对照和 121 个测试 ROM，结果写在 README 里。
- **形态**：lunaboy 是一个应用，有 wasm-gc 网页版和基于 SDL3 的 native 版。moon_nes 的核心是一个与平台无关的库，发布在 mooncakes.io 上，可以用 `moon add` 嵌进别的程序；CPU 包还能单独拿去接别的 6502 机器。网页前端只是这个库的一个使用者。

# Holy Mapperel test ROMs

Unmodified ROMs from **Holy Mapperel** v0.02 by Damian Yerrick, an NES
cartridge board test that detects the mapper, checks every PRG/CHR bank and
the PRG RAM, and prints a 4-digit detail code where `0000` means everything
behaved as expected.

- Project: <https://github.com/pinobatch/holy-mapperel>
- File: `holy-mapperel-bin-0.02.7z` from the v0.02 release
- License: zlib (see `LICENSE` in this directory), which permits
  redistribution

| File | Mapper | Board |
|---|---|---|
| `M0_P32K_C8K_V.nes` | 0 | NROM, 32 KiB PRG, 8 KiB CHR ROM |
| `M0_P32K_CR8K_V.nes` | 0 | NROM, 8 KiB CHR RAM |
| `M1_P128K_C32K.nes` | 1 | MMC1 (SxROM), CHR ROM |
| `M1_P128K_CR8K.nes` | 1 | MMC1 (SNROM), CHR RAM, WRAM disable via CHR bit 4 |
| `M1_P512K_CR8K_S8K.nes` | 1 | MMC1 (SUROM), 512 KiB PRG |
| `M2_P128K_V.nes` | 2 | UxROM, CHR RAM |
| `M2_P128K_CR8K_V.nes` | 2 | UxROM, CHR RAM |
| `M3_P32K_C32K_H.nes` | 3 | CNROM, 32 KiB CHR ROM |

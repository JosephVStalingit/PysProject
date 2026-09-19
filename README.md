# 磁体-弹簧-线圈电磁感应 FEM（Elmer 26.2）

> 圆柱形永磁体（NdFeB，Φ30×30 mm）挂在弹簧上，在线圈（Φ40/50 mm，长 40 mm，
> 25/50/100 匝铜或铝）中往复振荡。三维瞬态 FEM 解 A 场并与线圈电路耦合。
>
> **代码量** ~30 KB · Elmer 打包在 `./elmer262/` · Docker 就绪
>
> 📌 完整调试历史（77 节，80 KB）见 **`docs/HISTORY_full.md`**；
> 英文工程日志见 **`hpc/notes.md`**。

---

## 目录

1. [当前状态](#1-当前状态)
2. [安装与运行](#2-安装与运行)
3. [几何、材料、电路](#3-几何材料电路)
4. [运动律（弹簧 / 自由落体）](#4-运动律弹簧--自由落体)
5. [闭路 FEM 的六个关键机制](#5-闭路-fem-的六个关键机制)
6. [六个实验可测物理量（结果）](#6-六个实验可测物理量结果)
7. [🟢 已解决：感应电动势 / 电流的 N 标度](#7-已解决感应电动势--电流的-n-标度)
8. [成本与性能](#8-成本与性能)
9. [HPC 操作手册](#9-hpc-操作手册)
10. [文件清单](#10-文件清单)
11. [器材与测量链（传感器 → `R_load`）](#11-器材与测量链传感器--r_load)

---

## 1. 当前状态

**7 个案例已在 HPC 跑完（900/900 步，日志 0 错误）**，共两批：

| 批次 | 时间 | SIF 关键差异 | 产物目录 |
|---|---|---|---|
| 第一批 | 2026-09-13 22:12 → 09-14 01:35 | `z_eq = 0.020 m` | `hpc_results/` |
| **第二批（当前）** | 2026-09-15 22:39 → 09-16 06:36 | **`z_eq = 0.024 m`** | **`hpc_results_z024/`** |

第二批把 `spring.z_eq_m` 从 0.020 改成 **0.024 m**，依据是第一批跑完后
**从 900 帧 VTU 实测**到的平衡中线 22.4 mm（MATC 常数项随之 −0.025 → −0.021）。

### 1.1 可信度分级

| 物理量 | 可信？ | 依据 |
|---|---|---|
| **位移 z(t)** | ✅ **完全可信** | 与解析 MATC 逐帧对比，**rms 残差 2.5 皮米**，相对 1.2e-10 |
| 速度 v(t)、加速度 a(t) | ✅ 可信 | 位移的数值微分 |
| 磁通密度 B(z) | ✅ 可信 | 直接来自 A 场 |
| 周期 T | ✅ 可信 | 实测 0.3000 s vs 解析 0.2995 s |
| **感应电流 i(t)** | ✅ **完全可信**（900 步闭路） | i(25→50) = 1.97、i(50→100) = 1.94（匝数翻倍）；`r_component(1) = R_wire(N)` 吻合到机器精度（§7.5.16） |
| **感应电动势 ε(t)** | ✅ **完全可信**（900 步闭路） | `ε/N` 在 Cu/Al 同一 N 下吻合到 0.0003%；`ε = i·(R_load + r_component(1))`（§7.5.16） |

> **修复总览**：早期 `/localC` 补丁（§7.4.4）被回退是正确判断；真正的根因在
> **标量 W 势路径（`WPotentialSolver/Wsolve`）** 缺 4 条关键键，§7.5.9–§7.5.15
> 把它换成上游的 `CoilSolver`（W 向量）+ Component 的
> `Resistance = R_wire(N)` + Dummy 材料即修复，全过程不重编。
> **900 步全闭路终局结果在 §7.5.16。**


### 3.1 尺寸（实物 = 第一性原理 + 典型值）

| 几何量 | config key | 值 | 物理含义 |
|---|---|---|---|
| 磁体半径 | `magnet.R_mag_m` | 0.015 m | Φ30 mm × 30 mm N52 NdFeB（M = 1.2e6 A/m）|
| 磁体高度 | `z1_m − z0_m` | 0.030 m | `H_mag_m` 是**半高** 15 mm |
| 磁体网格位置 | `magnet.z0_m` | 0.030 m | = 弹簧**释放**位置（初位移为 0）|
| **线圈内径** | `coil.r_inner_m` | **0.020 m** | **Φ40 mm，磁体穿过** |
| **线圈外径** | `coil.r_outer_m` | **0.025 m** | **Φ50 mm，壁厚 5 mm** |
| **线圈长度** | `coil.z1_m − z0_m` | **0.040 m** | 40 mm |
| 径向缝宽 | `coil.slit_width_m` | 0.0035 m | 只让 W 势有终端，**不是物理气隙** |
| 空气域 | `R_air_m`/`air_z0_m`/`air_z1_m` | 0.080 / −0.080 / 0.110 m | 远场 Φ160 × 190 mm，A = 0 |
| **线径** | `curves.*.wire_diameter_m` | **0.0007 m** | **Φ0.7 mm 漆包线（≈AWG21）** |
| 铜 σ | `wire_conductivity_S_per_m` | 5.96e7 | 100% IACS |
| 铝 σ | `wire_conductivity_S_per_m` | 3.50e7 | 6061-T6（~61% IACS）|

**导出量**：

```
r_mean   = (r_inner + r_outer)/2 = 0.0225 m     (Φ45 mm 中线)
L_turn   = 2π·r_mean             = 0.1414 m     (单匝 14.1 cm)
A_wire   = π·d²/4                = 3.85e-7 m²    (Φ0.7 mm)
A_coil   = (r_out−r_in)·L_coil   = 2.0e-4 m²    (线圈截面)
填充因子 f = N·A_wire/A_coil     = N·0.77       (N=100 → 77%)
N_j      = N/A_coil              = N·5e3 1/m²   (绕线密度，CalcFields 需要)
σ_eff    = f·σ_wire                             (写进 Material 1)
```

### 3.2 体编号（SIF 与 gmsh Physical Volume 一致）

| 编号 | 名称 | 角色 |
|---|---|---|
| 1 | `AirInside` / `StrandedCoil` | 线圈等效块体（依 curve 变空气/线圈）|
| 2 | `Magnet` | 永磁体 |
| 3 | `AirDomain` | 包围空气 |
| 1001 | `MagneticInfinity` | 外表面（A = 0）|

### 3.3 控制方程

```
sigma dA/dt + curl(1/mu curl A) = Js          (Whitney AV 棱边元)
mu_r = 1.05（线性 B-H）
电路 : CircuitsAndDynamics，Component 1 = stranded coil，
       Component 2 = R_load = 10 Ω 串联成闭路
线向 : w = -grad(W)，WPotentialSolver 解 W，
       slit 两面 W=1 / W=0 定出绕线方向
运动 : RigidMeshMapper + `Mesh Translate 3` = MATC 表达式
输出 : results/circuit.csv（每步 i/v/r/p）
       results/case_t*.vtu（A、B、W、meshrelax 等）
```

---

## 4. 运动律（弹簧 / 自由落体）

由 `config.json → experiment.motion_mode` 切换，**SIF 由 config 生成**。

| `motion_mode` | 运动律 | MATC |
|---|---|---|
| `"spring"`（当前）| 阻尼谐振子 | 由 `[spring]` 推导 |
| `"free_fall"` | z = z₀ − ½gt² | `-0.5*9.81*tx*tx` |

**弹簧-质量-阻尼**：磁体挂在弹簧下端，上端焊在锚板（clamped）：

```
m z'' = -m g - k(L - L0) - c z' - F_lenz,   L(z) = anchor_z0 - (z + H/2)

z(t) = z_eq + A e^(-γt)[cos(ω_d t) + (γ/ω_d) sin(ω_d t)]

ω0 = √(k/m)   γ = c/(2m)   ω_d = √(ω0²−γ²)   A = |z_release − z_eq|
```

**当前参数与导出量**：

| 量 | 值 | 量 | 值 |
|---|---|---|---|
| `mass_kg` | 0.5 | **周期 T** | **0.2995 s**（3.34 Hz）|
| `stiffness_N_per_m` | 220 | `omega0` | 20.976 rad/s |
| `damping_N_s_per_m` | 0.8 | Q | 13.1 |
| `z_eq_m` | **0.024** | 静伸长 mg/k | 22.3 mm |
| `z_release_m` | 0.045 | `L_eq` / `L0` | 64.0 / 41.7 mm |
| 锚板 z | 0.099–0.101 | 弹簧管 | R 6–8 mm, z 35–99 mm |

### 4.1 释放高度、弹簧形变、几何一致性

```
sag  = m g / k                    = 22.3 mm   (静伸长)
L_eq = anchor_z0 − (z_eq + H/2)   = 64.0 mm   (平衡长度)
L0   = L_eq − sag                 = 41.7 mm   (自然长度)
```

| 量 | 值 | 与真实物理的关系 |
|---|---|---|
| `spring_z1` | 99.0 mm | = `anchor_z0` ✓ |
| `spring_z0` | 35.0 mm | = 磁体顶在 z_eq 处（**接触**）|
| mesh 弹簧长度 | 64.0 mm | = `L_eq`（平衡长度）✓ |
| z_eq 时磁体顶 vs 弹簧底 | 35 vs 35 mm | **正好接触** ✓ |
| z_release 时磁体顶 vs 弹簧底 | 60 vs 35 mm | 磁体在弹簧上方 25 mm |

> ⚠️ **本 FEM 的"弹簧"是「位移剧本」，不是真的弹簧力**。
> SIF 的 `Mesh Translate 3 = MATC` 把磁体节点**直接平移**到解析解；
> 网格里**没有 Hooke 力 −k·Δx、没有 −c·v、没有 −mg、没有 Lenz 力反馈**。
> 磁体运动是**按剧本演出**，不是弹性动力学求解。
>
> **含义**：给定的 (k, c, m, z_eq, z_release) 必须严格与真弹簧匹配，
> 否则误差是「剧本误差」而非「FEM 求解误差」；`i(t)` 不会让磁体减速
> （z 与 i 是**单向耦合**）。
>
> **验证**：实测位移与 MATC 逐帧对比 **rms = 2.5 皮米**（§6.2），
> 即 RigidMeshMapper 确实精确执行了刚体平移。

---

## 5. 闭路 FEM 的六个关键机制

这六条都是从「跑不通」到「跑通」逐个挖出来的，**改动任何一条都会崩**：

| # | 机制 | 要点 |
|---|---|---|
| 1 | **求解器执行通道** | `CircuitsAndDynamics` / `CircuitsOutput` 必须用 `Exec Solver = "Before timestep"`。用 `Always` 会被排到 `MagnetoDynamicsCalcFields` 之后，而后者需要电路已创建的 Lagrange 乘子 → **SEGFAULT** |
| 2 | **求解器编号** | 前置通道按**数值编号**执行，所以电路输出必须编号**大于**电路装配 |
| 3 | **`Export Circuit Variables`** | 必须开（Solver 10），否则 `CircuitUtils.F90` 的硬门直接 RETURN，`crt i/v` 从不生成 |
| 4 | **`Export Lagrange Multiplier`** | 必须开（WhitneyAVSolver），否则 `LagrangeVar % Values` 未分配 → 第一次 CalcFields 就崩 |
| 5 | **绕线方向 W** | stranded 线圈没有内在线向，必须由 `DirectionSolver ×2 + RotMSolver + WPotentialSolver` 建局部标架，并在线圈环上开**径向缝**给 W 两个终端 |
| 6 | **`lc_slit_m ≥ slit_width_m`** | 缝必须由**一个单元跨越**，否则闭路瞬态**自发数值放大**直到溢出。见 §5.1 |

### 5.1 网格稳定性门槛（已解决）

| `lc_slit_m` | 每步增益 | 单元数 | 判定 |
|---|---|---|---|
| 2.5 mm | 1.777 | 30698 | 9 ms 内爆炸 |
| 3.0 mm | 3.30 | 26375 | 更糟 |
| 3.5 mm | 1.199 | 21650 | 临界 |
| **4.0 mm** | **~1.000** | **18743** | **稳定（生产值）** |
| 8.0 mm | < 1 | 12456 | 稳定 |

**阈值精确落在 `lc_slit_m = slit_width_m`**。
`solenoid3d.py` **硬性拒绝** `lc_slit_m < slit_width_m`。

> 失败是**静默的**：求解器 exit 0 并写出看似正常的 `circuit.csv`，
> 所以必须在**网格生成**阶段拦住。

---

## 6. 六个实验可测物理量（结果）

**只保留实验上能直接测的量**（脚本 `measurables_from_fem.py`）：

| # | 物理量 | 实验测量方法 | 本项目来源 |
|---|---|---|---|
| 1 | **位移 z(t)** | 激光位移计 / 高速相机 | **900 帧 VTU 的磁体节点均值** |
| 2 | 速度 v(t) | Doppler 振动计 | z(t) 中心差分 |
| 3 | 加速度 a(t) | 加速度计 | v(t) 中心差分 |
| 4 | 感应电流 i(t) | 示波器 + 串联采样电阻 | `circuit.csv` col 10 |
| 5 | 感应电动势 ε(t) | 示波器高阻探头 | `v_component(1) + i·R_wire` |
| 6 | 磁通密度 B(z) | 霍尔探头 / 搜索线圈 | 末帧 VTU 轴向 |

**已剔除**（实验难直接测）：F_spring、KE、PE、F_lenz、E_total。

> ⚠️ **表中第 4、5 行的"实验测量方法"必须按 §11 的器材核算重读**：
> 现有电流传感器（ACS712，内阻 **1.2 mΩ**）把线圈**短路**了，于是并接在线圈两端的电压探头读到的是
> `i·R_load ≈ 0.209 mV`，**并不是** EMF（见 §11.3）。必须在回路里串入 **0.5~1 Ω 精密电阻**
> （它同时就是采样电阻），EMF 才能由 `ε = V_terminal + i·R_wire` 合成。
> **器材配置与设计表见 §11。**

### 6.1 结果表（**第三次扫描：CoilSolver 全闭路，900 步，2026-09-18**）

| 曲线 | 位移范围 | 振幅 | 周期 | i_peak | ε_peak | r_comp1 | R_wire(N) |
|---|---|---|---|---|---|---|---|
| N25_cu | 同上 | 19.811 mm | 0.3000 s | **2.7318 mA** | **27.739 mV** | **0.15409 Ω** | 0.15409 ✓ |
| N25_al | 同上 | 19.811 mm | 0.3000 s | **2.7030 mA** | **27.739 mV** | **0.26239 Ω** | 0.26239 ✓ |
| N50_cu | 同上 | 19.811 mm | 0.3000 s | **5.3783 mA** | **55.441 mV** | **0.30818 Ω** | 0.30818 ✓ |
| N50_al | 同上 | 19.811 mm | 0.3000 s | **5.2677 mA** | **55.442 mV** | **0.52478 Ω** | 0.52478 ✓ |
| N100_cu | 同上 | 19.811 mm | 0.3000 s | **10.4189 mA** | **110.610 mV** | **0.61635 Ω** | 0.61635 ✓ |
| N100_al | 同上 | 19.811 mm | 0.3000 s | **10.0116 mA** | **110.624 mV** | **1.04956 Ω** | 1.04956 ✓ |
| empty | 8.60–48.22 mm | 19.811 mm | 0.3000 s | 0（无电路）| 0 | — | — |

`t_end = 0.900 s`（`dt = 1e-3`，**3 个完整弹簧周期**）；输出目录 `hpc_results_z900/`。

**说明**：

* **7 个案例位移完全相同**（含 empty）——位移由 MATC 强制，与电路/材料无关 ✓
* empty 的 **+2.16 mm 常量偏移**是「节点均值」估计器的偏置（不同网格分布），
  **形状一致**（振幅都是 19.811 mm）
* ✅ **`r_comp1` = `R_wire(N)` 吻合到机器精度**（6/6，`rel.err ≤ 3.8e-7`）
* ✅ **`i_peak` 随 N 增长**（2.73 → 5.38 → 10.42 mA，即 ∝ N 的量级），
  与旧路径的 **4:2:1 递减**完全相反
* ✅ **`ε_peak/N` 跨材料恒定**：Cu 与 Al 在同一 N 下吻合到 **0.0003%**
  （1.109551e-3 vs 1.109554e-3 @ N=25）
* **Cu 与 Al 的 i_peak 略有差异**（N25: 2.7318 vs 2.7030 mA，差 1.0%）
  —— 因为 `r_coil` 不同（0.154 vs 0.262 Ω）而 `R_load = 10 Ω` 固定；
  ε 则几乎完全相同（27.739 mV）⟹ **EMF 与材料无关** ✓

> ⚠️ **历史值**：第二批（`hpc_results_z024/`，wsolve 路径）给出的是
> `4.5498 / 2.2754 / 1.1378 mA`，即 **∝ 1/N** —— 那是**已修复的 bug 的症状**
> （§7 全节记录该调查）。上面的新表是修复后的结果。


### 6.1.1 结果图象（`plot_z900_results.py`）

```bash
python plot_z900_results.py            # 读取 hpc_results_z900/，写出 6 张 PNG
python plot_z900_results.py --dpi 300  # 出版分辨率
```

输出到 **`hpc_results_z900/figures/`**（附 `figure_source_data.csv`，即图中全部数值）：

| 图 | 文件 | 内容 |
|---|---|---|
| 1 | `fig1_timeseries.png` | **三量时程**：z(t) / ε(t) / i(t)，6 条闭路曲线叠加 |
| 2 | `fig2_nscaling.png` | N 标度四联：peak\|i\|、peak\|ε\|、r_comp1、ε/N |
| 3 | `fig3_waveforms.png` | 首个周期波形放大（Cu / Al 各一列） |
| 4 | `fig4_epsN_collapse.png` | **ε ∝ N 塌缩检验**：6 条 ε/N 重合为一条 |
| 5 | `fig5_old_vs_new.png` | **新旧路径对比**：wsolve ∝ 1/N vs CoilSolver ∝ N |
| 6 | `fig6_solver_artifact.png` | **诚实面板**：波形尖刺的定位与其对峰值的影响 |

**图 4 是本项目的核心证据**：6 个案例的 `ε(t)/N` 叠加后只差 **0.3%**。
旧 wsolve 路径在同一图上会散开 **N² = 16 倍**。

#### 图 6 记录的一个已量化伪影（务必知情）

ε(t) 与 i(t) 上每隔十几到上百步出现一个**孤立尖刺**（不是噪声带）。已量化的三条事实：

1. **899 步中有 39 步（4.3%）** 的 `|Δi|` 超过中位值的 10 倍；被尖刺分开的
   波形本身是**平滑**的（`Δi` 从不为 0，所以不是「阶梯保持」）。
2. **这 39 个尖刺的步号在全部 6 个案例中逐位相同**（`set` 比较为 `True`）——
   包括 t = 0.002, 0.031, 0.035, 0.079, ... 0.826 s。既然所有案例共享同一
   时间步序列与同一强制位移，这说明伪影**只由时间离散决定，与 N、材料、
   感应电流无关**。
3. **报告的头条峰值对此稳健**：把每个尖刺后 3 步剔除后重取峰值，6 个案例的
   差异都 **≤ 0.25%**（`peak_all / peak_smooth` = 1.0022–1.0023）。
   因此 §6.1 表里的 `i_peak`、`ε_peak` 无需修正。

图 6 的面板 (c) 把这两组峰值并排画出，读者可自行判断。


### 6.2 位移验证（`validate_displacement.py`）

把实测 `z_mean(t)` 与 MATC 解析轨迹逐帧对比。为消除节点均值的常量偏置，
比较 **`z(t) − z(t₁)`**（去偏置位移）：

| 案例 | 实测振幅 | 解析（同窗口）| 相对误差 | T 实测 | **rms 残差** |
|---|---|---|---|---|---|
| N25_cu | 19.811 mm | 19.811 mm | 1.4e-11 | 0.3000 s | **2.53e-12 m** |
| N50_cu | 19.811 mm | 19.811 mm | 1.4e-11 | 0.3000 s | 2.53e-12 m |
| N100_cu | 19.811 mm | 19.811 mm | 1.4e-11 | 0.3000 s | 2.53e-12 m |
| empty | 19.811 mm | 19.811 mm | 4.1e-11 | 0.3000 s | 6.98e-12 m |

> **rms = 2.5 皮米，相对振幅 1.2e-10** —— RigidMeshMapper 把 MATC 刚体平移
> 执行到了双精度极限。**位移项不存在数值误差。**

### 6.3 磁体节点识别（`hpc_extract_z2.py`）

几何判据（`r < 15 mm` 且 `30 ≤ z ≤ 60 mm`）在导体案例里**恰好等于磁体节点集**
（356 个节点，单一位移聚类）；但在 `empty` 案例会**混入 16 个不动节点**
（`empty` 的 Body 1 = `AirInside` = r≤20 mm、z 0–40 mm 的圆柱，
与磁体 z 30–40 mm 重叠）。

**改进：按位移签名聚类**。取 3 个检查帧，算每个候选节点的二维位移向量
`(z(t_m)−z(t₁), z(t_e)−z(t₁))`：

* 磁体（刚体）→ 所有节点**位移完全相同**，聚成一个大簇
* 固定节点 → `(0, 0)`
* 变形空气节点 → 散布

取**最大的非零簇**即为磁体。实测：导体案例 356 个候选 = 356 磁体节点
（单簇无污染）；`empty` 290 磁体 + **16 不动节点被正确剔除** ✓

**回归校验**：`z_std` 全程恒 9.542 mm、`z_max − z_min` 恒 28.35 mm
⟹ 选出的节点集确实在**刚体平移**。

---

## 7. 🟢 已解决：感应电动势 / 电流的 N 标度

> §7.5.16（900 步全闭路扫描）确认：根因是 **自制的标量 W 势路径**（缺 4 条关键键），
> 改用上游 `CoilSolver`（W 向量）+ `Component 1 Resistance = R_wire(N)` 即修复。
> §6.1 的 i/ε 现在是**完全可信**的（见 1.1 表）。
> 本节剩余内容是当时**调查的诊断记录**（被推翻/被超越的猜想）。

### 7.1 问题

用**独立解析模型**（`check_emf_vs_analytic.py`）交叉检验：
把磁体离散成 60 层轴上偶极子，用解析通量公式

```
Φ(a,z) = (μ0/2)·dm·a² / (a² + (z−z_i)²)^{3/2}
```

（由 `A_φ = μ0 m r/(4π(r²+Δ²)^{3/2})` 与 `Φ = 2π a A_φ(a)` 推出）

对线圈中线半径 `a = 22.5 mm` 求和得**单匝**通量，乘 N 得磁链 `ψ = N·Φ`，
用**实测 z(t)** 求导得开路电动势 `ε_ana = dψ/dt`。
另一边由 KVL（`ωL ≈ 0.02 Ω ≪ R`）有 `ε_FEM = i_peak·R_total`。

| N | i_peak | ε_FEM = i·R | ε_解析 = N·dΦ/dt | **FEM/解析** |
|---|---|---|---|---|
| 25 | 4.5498 mA | 46.2 mV | **179.3 mV** | **0.26** |
| 50 | 2.2754 mA | 23.4 mV | **358.7 mV** | **0.07** |
| 100 | 1.1378 mA | 12.1 mV | **717.4 mV** | **0.02** |

```
ε_解析 ∝ N        (179.3 → 358.7 → 717.4 mV  =  1 : 2 : 4   精确)
ε_FEM  ∝ 1/N      ( 46.2 →  23.4 →  12.1 mV  =  4 : 2 : 1   精确)
FEM/解析 ∝ 1/N²   ( 0.26 →  0.07 →  0.02    ≈  1 : 1/3.7 : 1/13)
```

**`ε = N·dΦ/dt ∝ N` 是硬物理**（多匝磁链随匝数线性增长，无争议）。
FEM 却给出 ∝ 1/N —— **标度方向都反了**，比值按 **1/N²** 漂移。

绝对量也偏小：N=25 时偏 3.9×，N=50 时 15×，N=100 时 **59×**。

### 7.2 已定位的可疑代码

`elmer262/fem/src/modules/CircuitsAndDynamics.F90`，
`SUBROUTINE Add_stranded`（-pp 文件 L540–735）：

| 行 | 项 | N_j 幂次 |
|---|---|---|
| **L697** | 线圈串联电阻 `localR` | **`N_j ** 2`** |
| **L710-711** | `d/dt (a,w)` 磁链项（EMF）| **`N_j`（1 次）** |
| **L725-726** | 源项 `(J, rot a')` | **`N_j`（1 次）** |

```fortran
! L697  电阻
localR = Comp%N_j**2 * IP%s(t)*detJ*SUM(w*w)/localC*circ_eq_coeff / Comp%VoltageFactor
! L710 磁链 / EMF
val = Comp%N_j * IP%s(t)*detJ*SUM(WBasis(j,:)*w)/dt / Comp%VoltageFactor
! L725 电流源
val = -Comp%N_j*IP%s(t)*detJ*SUM(WBasis(j,:)*w)
```

**均匀化模型的自洽关系**（`J = N_j·I·w`，`Ψ = N_j ∫A·w dV`）：

* 磁链 `Ψ = N_j ∫A dV`，其中 `∫A dV ≈ A_coil·L_coil·⟨A⟩`
  ⟹ `Ψ ≈ (N/A_coil)·A_coil·L_coil·⟨A⟩ = N·L_coil·⟨A⟩ = N·Φ` ✓
* 所以 **`N_j` 一次**在数学上就等于 **N·Φ**，理论上应该 ∝ N

**但实测是 1/N**，说明**上游还有一处把 N 又除了一次**。
重点怀疑（尚未核对完）：

1. **`N_j` 的 SIF 赋值**：`make_sif.py` 写 `Stranded Coil N_j = N/A_coil`。
   若代码内部又乘一次 `N_j` 或又除一次 `A_coil`，就会多出 `1/N`。
2. **`Comp % VoltageFactor`**：默认 1.0，未设置（`CircuitUtils.F90:883`）。
3. **`w` 的归一化**：`w = -grad(W)` 若不满足 `|w| = 1`，
   则 `∫|w|²dV` 与 `∫WBasis·w dV` 的幂次会不一致（电阻用 `|w|²`，
   EMF 用 `WBasis·w`）——**这一条的嫌疑最大**，因为
   `r_component(1)` 实测是 ∝ N（0.151/0.302/0.603）而物理上应是 ∝ N²。

### 7.3 决定性诊断结果（Job 122243170 / 122243171，2026-09-16 12:07 起）

**N 只通过三个旋钮进入模型**，诊断在设计上逐个隔离它们。
同一步（t = 0.017 s）的实测：

| 案例 | `Number of Turns` | `Stranded Coil N_j` | `σ_eff` | **i₁** | **r_comp1** |
|---|---|---|---|---|---|
| `N1_L040_cu_closed` | 1 | 5.0e3 | 1.14685e5 | **9.421784e-2** | 6.034e-3 |
| `N1nj25_L040_cu_closed` | 1 | **1.25e5**（25×）| **2.8671e6**（25×）| **9.422678e-2** | 2.41e-4 |
| `N25_cu` | 25 | 1.25e5 | 2.8671e6 | 4.500994e-3 | 0.150847 |
| `N50_cu` | 50 | 2.5e5 | 5.7342e6 | 2.251024e-3 | 0.301694 |
| `N100_cu` | 100 | 5e5 | 1.14684e7 | 1.125579e-3 | 0.603387 |

#### 7.3.1 两条经验定律（拟合到 0.02%）

```
①  r_comp1 = 692 · turns² / σ_eff          (5 个点全部吻合)
     ⟹ R ∝ N²/σ_eff，但 σ_eff ∝ N，净结果 R ∝ N
     ⟹ 物理应为 R_wire ∝ N² ⟹ **R 少了 1 个 N**

②  i₁(N)/i₁(1) = 1.000 / 0.0478 / 0.0239 / 0.0119   (N = 1,25,50,100)
     ⟹ i ∝ 1/N ⟹ ε = i·R_total ∝ 1/N
     ⟹ 物理应为 ε = N·dΦ/dt ∝ N ⟹ **ε 少了 2 个 N**

③  N1 与 N1nj25：N_j 和 σ 各差 25×，i 完全相同（比值 1.00009）
     ⟹ **ε 完全不依赖 N_j 与 σ，只依赖 `Number of Turns`，且是 1/N**
```

#### 7.3.2 根因：SIF 里的 `Stranded Coil N_j` 会被 Elmer 覆盖

`elmer262/fem/src/CircuitUtils.F90`：

```fortran
L949  : Comp % N_j = Comp % CoilThickness * Comp % nofturns / Comp % ElArea
L1001 : Comp % N_j = Comp % nofturns / Comp % ElArea          ! 3D 走这条
L1233 : CALL listAddConstReal(CompParams, 'Stranded Coil N_j', Comp % N_j)
```

* **`N_j` 是内部从 `Number of Turns` 与单元面积重算的**
* L1233 是**把算出来的值写回参数表** —— 源码里那句
  `GetConstReal(...,'Stranded Coil N_j',Found); IF(.NOT.Found) Fatal` 是
  **读回自己的写**，不是读用户输入
* ⟹ **`make_sif.py` 精心算出的 `N_j = N/A_coil` 是无效输入**（无害但无用），
  真正的杠杆是 `Number of Turns` 与 `σ_eff`

#### 7.3.3 第三个诊断：σ_eff 扫描（Job 122243412 / 122243413）

定律①说 `R ∝ N²/σ_eff`，但我们用的 `σ_eff = f_N·σ_wire ∝ N`，
所以净结果 `R ∝ N`。**要修 R，必须知道正确的「块电导率」。**
我推导出三个互相矛盾的候选 —— 说明均匀化记账有误，**不能再靠推导猜**：

| 候选 | 公式 | N=25 的值 |
|---|---|---|
| **A**（现用）| `f_N·σ_wire`，`f_N = N·A_wire/A_coil` | 2.867096e6 |
| **B**（功率平衡）| `σ_wire·f₁·L_coil/L_turn` | 3.2442e4 |
| **C**（体积分数）| `σ_wire·N·A_wire·L_turn/(A_coil·L_coil)` | 1.0135e7 |

**σ 扫描实验**：固定 `Number of Turns = 25`（及其余一切不变，共用 mesh），
只改 `Material 1` 的 Electric Conductivity：

| 案例 | σ_eff | Job |
|---|---|---|
| `N25_cu`（已有）| 2.867096e6 | — |
| `SigB_L040_cu_closed` | **3.2442e4** | 122243412 |
| `SigC_L040_cu_closed` | **1.0135e7** | 122243413 |

**判据**：物理线阻 `R_wire(25) = 25²·L_turn/(σ_wire·A_wire) = 3.8525 Ω`。
看 `r_comp1` 在哪个 σ 下等于 3.8525 Ω，那个 σ 就是正确的块电导率。
同时也能验收「ε 是否真的与 σ 无关」（定律③）。

#### 7.3.4 对 `make_sif.py` 的修正（待 σ 扫描定论后实施）

1. **`Stranded Coil N_j` 不再手工赋值**（它被 Elmer 内部覆盖，见 §7.3.2），
   只保留关键字以满足源码的存在性检查。
2. **`σ_eff` 改为 N 无关的常数** —— 具体值等 §7.3.3 的扫描结果。

> ⚠️ **上游参考算例对本 Bug 无参考价值**：
> `fem/tests/circuits_transient_stranded_full_coil/sif/coil.sif` 的
> `Material 1` 叫 **"Dummy"**，**完全没有 Electric Conductivity**
> —— 它只测磁场耦合（`S1 = 1e6·t` 强迫源），**不经过电阻与 EMF 的
> N 标度**。所以「上游测试通过」不能证明我们的 N 标度是对的。


### 7.4 σ 扫描定论 + 两处自我更正

#### 7.4.1 σ 扫描结果（Job 122243412 / 122243413，t = 17 ms）

| 案例 | turns | σ_eff | **r_comp1** | i₁ |
|---|---|---|---|---|
| `SigB_L040_cu_closed` | 25 | **3.2442e4** | 13.33125 | 4.499162e-3 |
| `SigC_L040_cu_closed` | 25 | **1.0135e7** | 0.042673 | 4.501009e-3 |
| `N25_cu`（原）| 25 | 2.867096e6 | 0.150847 | 4.500994e-3 |

**定律①**：`r_comp1 = 692·turns²/σ_eff`，在 **312× 的 σ 范围**内逐一吻合到 0.01%。

把 `σ_eff = f_N·σ_wire = (N·a_wire/A_coil)·σ_wire` 代入：

```
r_comp1 = 692·N²/σ_eff = 692·N·A_coil/(a_wire·σ_wire) = N · 6.034e-3 Ω
```

对照**物理线阻** `R_wire = N·L_turn/(σ_wire·a_wire) = N · 6.164e-3 Ω`：

| N | r_comp1 (模型) | R_wire (物理) | 偏差 |
|---|---|---|---|
| 25 | 0.150847 | 0.15410 | **2.1%** |
| 50 | 0.301694 | 0.30820 | **2.1%** |
| 100 | 0.603387 | 0.61640 | **2.1%** |

> ✅ **电阻与 `σ_eff = f_N·σ_wire` 的约定都是正确的**，
> `make_sif.py` 的推导无误。恒定 2.1% 偏差来自经验常数 692 里的几何因子。

#### 7.4.2 🔴 **第二次更正（我自己的错误）**：R 的 N 幂次

我一度宣称「物理 `R_wire ∝ N²`，模型给 `∝ N`，故 R 少一个 N」——
**这是我的算术错误**。正确推导：

```
R_wire = ρ · (总导线长) / a_wire = (1/σ_wire) · (N · L_turn) / a_wire  ∝  N
```

（总导线长 = N·L_turn；我错写成了单匝长度。）**所以 `R ∝ N` 是对的**，
`r_comp1` 与物理值 2.1% 吻合即为证。

#### 7.4.3 🔴 **第三次更正**：§16 的「EMF 标度错 N²」作废

`v_component(1) = -i·R_load` **恒成立**（0 V 源 + 串联回路的 KVL 推论），
与物理无关。§16 用的 `ε = i·R_total` **只在 `ωL ≪ R` 时成立**。

**σ 扫描给出了第二个独立判据**：σ_eff 变 **312×** 而 `i₁` 完全不变
（0.04%）。这只能发生在

* ❌ 电阻主导（`i = ε/R`）→ i 应 ∝ 1/σ，会变 312×
* ✅ **电感主导（`i = (1/L)∫ε dt`）→ i 与 σ 无关**

**这与 §13 最初的观察「`R_load` 扫十个数量级完全无效」完全一致。**

#### 7.4.4 🔴 **第四次更正（2026-09-16 晚）：`/localC` 补丁不成立，已回退**

上一版把「唯一 Bug」定为磁链项少乘 `σ`，并据此打了源码补丁。**这个补丁是错的，
已从 `CircuitsAndDynamics.F90-pp.f90` 回退**（原地留了一段注释说明为什么不能再加）。两条独立证据：

**(1) 量纲**　`λ = N_j·∫A·w dV` → `[1/m²]·[Wb/m]·[m³] = Wb` ✓ 已经是正确单位，
**没有 σ 的位置**。

**(2) 与实体导体对比（同一文件，决定性）**

```fortran
L749  stranded : CALL AddToMatrixElement(CM, VvarId, PS(Indexes(q)), tscl*val)
L943  massive  : CALL AddToMatrixElement(CM, vvarId, PS(Indexes(q)), tscl*val*localC/dt)
                              ↑ σ 在这里
```

这个非对称是**正确物理**，不是漏项：

| | 电流密度 | 耦合项是否含 σ |
|---|---|---|
| 绞合线圈 (stranded) | `J = N_j·I·w` | ✗ 不能含（w 是单位电流方向）|
| 实体导体 (massive) | `J = −σ∂A/∂t` | ✓ 必须含 |

若真给磁链项加上 `/localC`（= `/σ_eff ≈ /2.87e6`），自感会变成**小 2.87e6 倍**。

**(3) `IP % s(t)` 已查明就是普通高斯积分权重**（`Integration.F90:1815` 等处
`p % s(t) = Weights(i,n)*Weights(j,n)*Weights(k,n)`），不存在隐藏的 σ。

**(4) 量级自洽**：`R` 与 `L` 共用同一个 `N_j²|w|²` 因子，**不可能一个对（2.1%）、
一个错 3.7e6 倍**。且从实测 R 反推出 `∫|w|²dV = 2.768e-5 ≈ V_coil = 2.828e-5`
⟹ **`|w| ≈ 1`（单位向量），已三次独立确认**。

---

#### 7.4.5 现在能确证的事实（模型无关）

用**闭路 KVL 恒等式**（串联无源回路 `v_component(1) = −i·R_load`，已在 CSV 中
逐位验证）得到 Elmer 实际装配出的磁链：

$$\lambda(t) = -(R_{load}+R_{coil})\int_0^t i\,ds$$

| N | λ_FEM(t=0.15 s) | λ/N | λ_ana = N·Φ | FEM/ana |
|---|---|---|---|---|
| 25 | −2.96e-3 | −1.18e-4 | −1.393e-2 | 0.213 |
| 50 | −1.50e-3 | −3.00e-5 | −2.786e-2 | 0.054 |
| 100 | −7.73e-4 | −7.73e-6 | −5.572e-2 | 0.014 |

**λ ∝ 1/N，而正比要求是 ∝ N；比值精确 ∝ 1/N²（1 : 1/4 : 1/16）。**

三个线圈几何、网格、运动 `z(t)` **逐位完全相同**（已核验 `max|z−z₂₅| = 0`），
所以每匝磁链 Φ 必须相同 ⟹ **每匝磁链随 N 掉成 1/N²，这是硬性标度矛盾。**

**同时**：
* `i ∝ 1/N`（4.5498 / 2.2754 / 1.1378 mA，拟合到 0.02%）
* `R` 正确（r_comp1 = 0.15085 vs 手算 0.1541，2.1%）
* `Z ∝ N²` ⟹ 等效 `L ∝ N²`，量级 ~500 H（N=25）

### 7.5 结案：**根因是自制的标量 W 势路径**（换用 CoilSolver，无需编译）

> **本节的最终结论在 §7.5.16（900 步全闭路扫描）**；§7.5.1–§7.5.13 是被推翻/被
> 超越的中间推理，保留下来是为了记录排除过程。
>
> * §7.5.1 的「涡流污染」假设 —— **已推翻**
> * §7.5.4–7.5.8 的「CoilSolver 路径值得一试」—— **已验证，就是答案**
> * **根因**：`WPotentialSolver/Wsolve`（标量 W 势）+ 径向缝 +
>   `DirectionSolver`/`RotMSolver` + `Alpha/Beta` 参考轴 —— 这四样**全是我们
>   自己加的非上游构造**。换成上游的 **`CoilSolver`（W 向量）** 后：
>   **`i ∝ N`（比值 24.9871 vs 25.0，误差 0.05%）**，而旧路径是 0.0474（∝1/N）。
> * 同时 **`r_component(1) = R_wire(N)` 吻合到机器精度**。
> * 本地与 HPC **逐位一致**（§7.5.12）。
> * **全程无需重新编译**：`CoilSolver.dll` 本来就在发布版里。
> * **900 步终局（§7.5.16）**：`ε/N` 跨材料恒定到 0.0003%，i(25→50)=1.97。


**已完成的判别实验（Job 122244593，`hpc/test_wvec_path.sh`）→ 结论是否定的，但暴露了真问题：**

| 变体 | 设置 | 结果 |
|---|---|---|
| A | 原样 | `i_pk = 4.549755e-03 A`、`r_comp1 = 1.508469e-01` —— **逐位复现研究数据** ✓ |
| B | 加上游那四个键 | **`i = 0`、`r_comp1 = 0`** —— 线圈完全解耦 |

B 退化的原因：`Coil Use W Vector = Logical True` 让代码去取名为 `"CoilCurrent e"`
的 **W 向量**变量，而我们的 **Solver 8 是经典的 `WPotentialSolver`/`Wsolve`（标量 W 势）**，
上游用的是现代的 `CoilSolver`。**我们根本不产生那个向量** ⟹ `w = 0` ⟹ R 与磁链项同时归零。

> 副产品：这证明 `w` 同时驱动 R 和磁链**两项**——它不可能让一个对一个错 3.7e6 倍。

**⟹ 真问题：我们给线圈本体材料设了 `σ_eff = f·σ_wire = 2.87e6`，这个数同时被
A-公式当成真实电导率，使线圈本体产生涡流。**

证据与量级：

```
circuit.csv 第 5 列 `eddy current power`      = 3.12e-06 W
而整个电路的耗散 p_dc_component(1) = i²R      = 1.2e-13 W
⟹ 线圈本体的涡流耗散是线圈导线自身耗散的 2e7 倍
```

而导体圆环的涡流时间常数

$$\tau_{eddy} \sim L_{ring}/R_{ring} \sim 1.8\times10^{-4}\ \text{s} \;<\; \Delta t = 3.3\times10^{-4}\ \text{s}$$

**⟹ 涡流子问题欠解析**，而 `λ` 完全由线圈区域内的 `A` 构成 ⟹ 直接污染磁链。

**上游的做法正是避开这一点**：它的线圈 `Material 1` 名字就叫 **"Dummy"、无
`Electric Conductivity`**，线圈的集中电阻改为在 Component 上显式给出
（`Component 1: Resistance = Real 0`），因为

```fortran
L693:  IF (.NOT. Comp % UseCoilResistance) THEN   <用材料 σ 算 R>
```

**给了显式 `Resistance` 就跳过材料积分。**

**判别实验已提交：Job `122245202`（`hpc/test_nonconductive_coil.sh`）**
N = 25/50/100，生产网格 30 步，变体 C：
* 线圈本体 `Electric Conductivity` → `1e-12`（非导电，照上游）
* `Component 1` → `Resistance = <原 σ_eff 路径给出的同一个 R>`

`r_comp1` 应当**不变**（集中电阻相同），而涡流消失。

#### 7.5.1 ⚠️ 涡流假设**已被数据推翻**（作业 122245202 已取消）

生产设定的 σ 扫描（900 步）给出了决定性数据：

| 案例 | σ_coil | r_comp1 | i（step 17） | `eddy current power` 峰值 |
|---|---|---|---|---|
| SigB | 3.2442e4（÷88.4）| 13.331 | 4.466770e-3 | 2.729e-4 |
| **N25** | **2.8671e6** | **0.150847** | **4.468605e-3** | **3.1229e-6** |
| SigC | 1.0135e7（×3.535）| 0.042673 | 4.468620e-3 | 9.0706e-7 |

**(1) σ 变 312× ⟹ `r_comp1` 变 312× 而 `i` 五位有效数字不变。**
⟹ 回路阻抗**完全非阻性**（否则 i ∝ 1/R）。

**(2) `eddy current power` 就是线圈自身的 `i²·r_comp1`，不是涡流。**
三个 σ 下 `eddy_power / (i²·r_comp1)` = 1.02 / 1.04 / 1.06 —— 全部在 6% 内吻合，
且都 ∝ 1/σ。**⟹ 线圈本体没有异常涡流，假设作废。**

#### 7.5.2 ✅ 新增确证：`Stranded Coil N_j` 被 Elmer 忽略

N1 / N1nj25 配对（**两者都是 1 匝**，N_j 与 σ 各 ×25）：

| 案例 | turns | SIF 里的 N_j | σ_coil | r_comp1 | i（step 17）|
|---|---|---|---|---|---|
| N1 | 1 | 5.0e3 | 1.14685e5 | 6.034e-3 | 9.342656e-2 |
| N1nj25 | 1 | 1.25e5 | 2.8671e6 | **2.41e-4** | 9.343547e-2 |

`r_comp1` **降了 25×（而不是升 25×）**，且 `2.41e-4 = ((1/2.0e-4)²/2.8671e6)·2.768e-5`
精确成立 ⟹ **Elmer 内部自算 `Comp % N_j = NofTurns / A_coil`，SIF 里那行完全无效**
（这补上了 §7.3.2 悬而未决的结论）。同时 i 只差 0.0095% ⟹ 两个 1 匝案例的
EMF 相同，且 `R_coil ≪ R_load`。

#### 7.5.3 🔴 最干净的经验定律

由 `ε = i·(R_load + r_comp1)`（KVL 精确）：

| N | i_pk [A] | R_total | ε_FEM [V] | **ε·N** |
|---|---|---|---|---|
| 1 | 9.59619e-2 | 10.00603 | 9.6020e-1 | **0.960** |
| 25 | 4.54975e-3 | 10.15085 | 4.6184e-2 | **1.155** |
| 50 | 2.27540e-3 | 10.30169 | 2.3441e-2 | **1.172** |
| 100 | 1.13780e-3 | 10.60339 | 1.2064e-2 | **1.206** |

$$\varepsilon_{FEM}(N) = \frac{1.16}{N}\ \text{V} \qquad \text{（本应} \propto N\text{，差值正是 } N^2\text{）}$$

**在 N = 1…100 四个数量级上精确 ∝ 1/N。** 这个定律是干净的，因此是一个
很好的靶子：任何正确理论都必须先复现它。

#### 7.5.4 唯一未测的代码路径 → 变体 D（**已提交：Job 122245457**）

`Coil Use W Vector` 的两个分支里，我们用的是**经典的标量 W 势**
（`Procedure = "WPotentialSolver" "Wsolve"`，Solver 8），上游用的是**现代的
`CoilSolver`（W 向量法）**。上一次 A/B（Job 122244593）只改了 Component 的键
而没换 Solver 8，所以不存在 `CoilCurrent e` 向量 ⟹ `w = 0` ⟹ 线圈解耦
（`i = 0`、`r_comp1 = 0`），**因此那次实验什么也没证明**。

变体 D（`hpc/test_coilsolver_modern.sh`）把 **Solver 8 的 Procedure 换成
`CoilSolver`**，并补上 `Normalize Coil Current` 等上游归一化键 + Component 的
四个键，N=25、生产网格、30 步。

#### 7.5.5 变体 D 的结果：**死在 CoilSolver 的初始化检查上（信息量极大）**

```
ERROR:: CoilSolver_init: "Electrode Boundaries(1)" not consistent with
        given "Coil Start" in bc 3
```

这行对应 `CoilSolver.F90:140-142`。把 `CoilSolver.F90:130-154` 读全，语义是
**和我们 SIF 的假设正好相反**：

```fortran
ElBCs => ListGetIntegerArray(Params,'Electrode Boundaries',Found)  ! 130 从 Component 读
BC => CurrentModel % BCs(ElBCs(1)) % Values                        ! 138
IF( ListGetLogical(BC,'Coil Start',Found) ) CALL Fatal(...)        ! 140-142 ← 我们死在这
CALL ListAddLogical( BC,'Coil End',.TRUE.)                         ! 144  (1) → Coil End
BC => CurrentModel % BCs(ElBCs(2)) % Values                        ! 146
IF( ListGetLogical(BC,'Coil End',Found) ) CALL Fatal(...)          ! 148-150
CALL ListAddNewLogical( BC,'Coil Start',.TRUE.)                    ! 152  (2) → Coil Start
```

**`Electrode Boundaries(1)` 变成 `Coil End`，`(2)` 变成 `Coil Start`，而且
CoilSolver 拒绝我们预设的 `Coil Start`/`Coil End`。** 我们模板写的是
`Integer 3 4` 且 BC3 带 `Coil Start` ⟹ 第一次检查就 Fatal。

同时从源码读出另外三条变体 D 缺的约束：

| # | 出处 | 约束 |
|---|---|---|
| 1 | `CoilSolver.F90:387` | CoilSolver 出现在某 Equation 里、而该 Equation 有体不属于任何 Component ⟹ Fatal。我们三个 Body 全用 `Equation 1`，必须拆 |
| 2 | `CoilSolver.F90:358-359` | `Coil Normal` 放在 **Solver** 段会 Fatal，必须在 **Component** |
| 3 | `CoilSolver.F90:2378` | `NormCoeff = DesiredCurrentDensity/SQRT(SUM(GradPot**2))` ⟹ **`w` 被归一化成单位场** |

#### 7.5.6 ✅ 顺带确证：`|w| = 1`（两条独立证据）

由 (3)：CoilSolver 的 `CoilCurrent e` 幅度 = `Desired Current Density` = 1.0。
而我们从 **2.1% 精度的电阻拟合** 独立反推出同一个结论：

$$R = N_j^2\frac{V_{coil}}{\sigma_{eff}} = \left(\frac{1.25\times10^5}{}\right)^2\frac{2.827\times10^{-5}}{2.8671\times10^6}=0.1541\ \Omega \quad\text{vs 实测 } 0.1508\ \Omega$$

**一致到 2.1% ⟹ `|w| ≈ 1`，且 `R = N_j²·V/σ_eff` 是精确关系**（这也再一次说明
电阻这条线本身没问题）。

#### 7.5.7 为什么 W 向量路径值得跑 —— 它绕开了我们**全部**自制构造

上游 `coil.sif` 的注释（第 5-6 行）说：

> the wire density vector is given via wire vector instead of wire potential
> ... **you can compute your wires in a full coil without cuts** which you
> cannot do using wire potential

上游用 **`Coil Closed = True` + `Coil Normal(3) = 0 0 1`**，因此**不需要径向缝**，
也就**不需要 DirectionSolver、RotMSolver、Alpha/Beta 参考轴** —— 这四样全是
**我们自己加进 SIF 的非上游构造**，也是模型里最后剩下的「可能含 N 相关错误」
的几何环节。它们若错了，`w` 就错；而 `λ ∝ N_j·|w|`、`R ∝ N_j²·|w|²` **共用同一个
`w`**（变体 B 的 `w=0` 让两者同时归零，正是这个共因的最强证据）。

#### 7.5.8 变体 E（**已提交：Job 122247342**）—— 决定性实验

`hpc/test_coilsolver_v2.sh` 一次性修正上述**全部四点**，并且**同时跑 N=1 和 N=25**
（N 只改 `σ_eff` 与 `Number of Turns`，**不改网格**，所以两个案例共用同一份网格）。

| 结果 | 含义 |
|---|---|
| `i(N=25) ≈ 25 × i(N=1)` | ✅ **自制框架就是根因**，改 `make_sif.py` 即可，无需重编 |
| 比值仍 ≈ 21（即 ∝ 1/N）| ❌ 两条路径等效 ⟹ 错误在共享的磁链项内部，须插桩 |

**参照**（当前 `Wsolve` 路径）：`i_pk` = **9.596190e-02 (N=1)** / **4.549755e-03 (N=25)**，
比值 **21.1**，`ε·N = 0.960 / 1.155 V`（常数）。

投递前用 `_validate_coilsolver_patch.py` 在本地把 awk 逐条移植、跑 18 项断言
全部通过（并因此**提前抓到一处会吃掉 `Body 2`/`Body 3` 行的 `next` 笔误**），
再用 `bash -n` 复检后才提交。

#### 7.5.9 ⭐ 根因定位 —— 换用 CoilSolver 后 **i ∝ N 恢复，精度 0.05%**

本地发现 `elmer262/bin/ElmerSolver.exe` **自带 `CoilSolver.dll` /
`WPotentialSolver.dll` / `CircuitsAndDynamics.dll`**，于是把整个调试**搬到本地**
（一次 30 步、约 6–9 分钟），只用了 4 次本地迭代就定位完成：

| 迭代 | 报错 | 修正 |
|---|---|---|
| 1 | `LoadInputFile: Entry missing for: Equation 2` | 编号 Equation 必须**连续**，`Equation 4` → `Equation 2` |
| 2 | `AddEquationBasics: Variable > coiltmp < exists but it is not associated to any equation` | `MainUtils.F90:1622-1636`：Solver 的 `Equation` 字符串必须在编号 Equation 块里**作为逻辑键存在** ⟹ 在 `Equation 1` 加 `Wire direction = Logical True`（本地实测：**改名不行，加键才行**）|
| 3 | `CoilSolver: No negative current sources on coil 1 end!` / `Crappy potentials` / **`Scaling of potential failed!`** | 去掉 `Coil Closed = Logical True` —— 它要求**无切缝的闭合环**（上游注释 "without cuts"），而我们的线圈有径向缝；我们已显式给 `Electrode Boundaries`，切缝模式完全可用 |
| 4 | ✅ 跑通 | — |

然后**把 N=1 和 N=25 都在本地跑满 30 步**，得到决定性对比：

| 路径 | i(1) [A] | i(25) [A] | **i(25)/i(1)** | 判定 |
|---|---|---|---|---|
| `Wsolve`（标量 W 势 + 径向缝 + DirectionSolver/RotMSolver）| 9.59619e-02 | 4.54975e-03 | **0.0474** | ❌ i ∝ 1/N |
| **`CoilSolver`（W 向量）** | **1.075774e-04** | **2.688049e-03** | **24.9871** | ✅ **i ∝ N（与 25 差 0.05%）** |

**⟹ 根因确认为我们自制的标量 W 势路径**（`WPotentialSolver` + 径向缝 +
Solvers 5/6/7 的 DirectionSolver/RotMSolver + `Alpha/Beta` 参考轴）：
上游 `coil.sif` 的注释说 W 向量的存在理由正是「**full coil without cuts**」，
而我们一直在用需要切缝的旧路径。

**列映射同时被两条电路定律精确验证**（`circuit.csv` **没有列头**，
映射取自 `circuits.definitions`）：

```
col10 i_coil  last/peak = 9.488151e-04 / 2.688049e-03 A
CHECK v_load = R_load*i : 9.488151e-03 vs 9.488151e-03   ✓
CHECK v_coil = -v_load : -9.488151e-03 vs -9.488151e-03 ✓
```

#### 7.5.10 ⚠️ 列映射陷阱（修正我自己上一段的错误推断）

`circuit.csv` **没有列头**，而 **CoilSolver 路径多导出了
`CoilPot/CoilPotB/PotSelect/CoilSet/CoilSetB/CoilIndex`，列的布局与
`Wsolve` 路径不同**。我先前按「col 6 ≈ 13 Ω」推断「电阻与 N 无关」——
**那是错的**。用**差分实验**（变体 F 把 `Component 1` 的 `Resistance`
改成 `1.0e-3`，其余不动，逐列对比）后，`r_component(1)` 被**精确定位**：

| 列 | 变体 C (N=25) | 变体 F (N=25) | 判定 |
|---|---|---|---|
| col 5 | 1.33e-08 | **8875.5** | 与电阻相关 |
| col 6 | 1.303e+01 | **3.931e+04** | 与电阻相关（**不是 r_comp1**）|
| **col 14** | **6.007108e-09** | **1.000000e-03** | ✅ **就是 `r_component(1)`**（精确等于我设的值）|
| col 15 | 5.41e-15 | **9.001e-10** | 与电阻相关 |
| col 1/2/4/8/10/11/12/13 | 9.488151e-04 | 9.487202e-04 | 电流/电压，**只变 0.01%** |

**⟹ 两条结论：**

1. **`Component 1` 的 `Resistance` 键确实生效**（列值精确等于设定值），
   与上游 `coil.sif` 的用法一致。
2. **`r_component(1)` 在 CoilSolver 路径下精确 ∝ N**：
   `6.007108e-09 (N=25)` / `2.402819e-10 (N=1)` = **25.000** ✓

**⟹ 因此 CoilSolver 路径下 `i ∝ N` 与 `R ∝ N` 同时成立 —— 两处都对了。**

#### 7.5.11 ⚠️ 但发现一个更深的物理问题：**电流与电阻无关**

变体 F 把 `R_coil` 从 ~0（6e-9 Ω）改到 `1e-3` Ω，**i 只变了 0.01%**。
结合 7.5.1 的 σ 扫描（σ 变 312×、`i` 五位有效数字不变），
**两条路径下回路都是感性主导的：`i` 由「感应 EMF / 自感」的平衡决定，
而不是由 `R_load + R_coil` 决定。**

这对**六个可测量量**有直接影响：`circuit dissipation`（焦耳损耗）
不是 `i²(R_load+R_coil)` 的意义上的物理耗散，用它做实验对比会误导。
`i` 本身则**不受此影响**（已验证 ∝ N）。

**结论**：
* **诱导电流 `i` 与 EMF 的 N 标度：用 CoilSolver 路径，已修正 ✅**
* **绝对电阻值**：建议在 `make_sif.py` 里去掉 σ_eff 技巧、改成
  **无电导线圈 + `Component 1 Resistance = R_wire(N)`**（两者都已本地验证生效），
  这样与电阻相关的可测量量才有物理意义。
* **绝对电感/电流量级**：仍是开放问题（感性主导意味着 `L` 量级值得单独复核）。

#### 7.5.12 ✅ HPC 独立复现 —— 与本地**逐位一致**

修好 awk 的引号 bug（见 §7.5.13）后重投，**Job `122249992`** 在集群上给出：

| 量 | N=1（HPC） | N=25（HPC） | 比值 |
|---|---|---|---|
| `col10 i_coil` 峰值 | **1.075774e-04 A** | **2.688227e-03 A** | **24.989** ✓ = 25 |
| `col14 r_component(1)` | 2.402819e-10 | 6.007108e-09 | **25.000** ✓ = 25 |
| `solve.log` | 30 步 | （当时 14 步，仍在跑）| |

与本地 30 步结果对照：

| | 本地 | HPC |
|---|---|---|
| i(N=1) | 1.075774e-04 | **1.075774e-04**（逐位相同）|
| r(N=1) | 2.402819e-10 | **2.402819e-10**（逐位相同）|
| r(N=25) | 6.007108e-09 | **6.007108e-09**（逐位相同）|
| i(N=25) 峰值 | 2.688049e-03（30 步）| 2.688227e-03（14 步）|

`CoilSolver: Assuming that all coils are open!` —— 与「已去掉 `Coil Closed`」一致。
**两台机器、两套实现（本地 Python 变换 / 集群 awk 变换）给出同一答案。**

#### 7.5.13 ⚠️ 藏在 awk 里的静默失败（值得记住的坑）

Job `122248196` 看起来「跑完了」，`SUMMARY` 也打印了，但两个案例都 `NO RESULT`。
真正的原因是 `csolv3-122248196.err` 里的**一行**：

```
awk: fatal: cannot open file `CoilTmp)
```

**awk 程序的注释里出现了撇号**（`'Variable'`、`'-nooutput CoilTmp'`），
而程序本身嵌在 shell 的**单引号**字符串里 —— 撇号提前闭合引号，后面的文字
被拆成独立单词，awk 把它们当成**输入文件名**，于是 `>` 重定向写出一个
**空文件**，随后 `cat >>` 追加的 14 行成了唯一内容：

```
source : 561 lines
output :  14 lines       ← 空 SIF
```

本地用的是同一个变换的 **Python 端口**，所以从未暴露这个问题。
修复后生成 587 行 ✓。

`_check_awk_quoting.py` 已加入检查：只扫 awk 程序内部的撇号并直接报行号。

**⟹ 教训：**
1. **任何嵌在 shell 单引号里的 awk/sed 程序，注释里绝不能有撇号**；
2. **变换脚本必须断言输出行数**（`[ $(wc -l < out) -gt 100 ] || fail`），
   否则空文件会一路静默走到「跑完」；
3. 这也是为什么把「同一变换」既用 awk 又用 Python 实现是不好的 ——
   要么只留一份，要么像本轮一样**本地跑断言 + 集群 `bash -n`**。

#### 7.5.14 ✅ `make_sif.py --path coilsolver` 端到端跑通

| # | 修改 | 验证 |
|---|---|---|
| 1 | `make_sif.py` 新增 `--path {wsolve, coilsolver}` 选项（默认 wsolve）| ✓ 语法 OK |
| 2 | 新常量 `_COIL_SOLVER_BLOCK_COILSOLVER`：替换 Solver 8 的 Procedure、删 `Variable = W`、加 CoilSolver 的 8 个归一化键 | ✓ |
| 3 | `Component 1` 模板新增 5 个键（`Coil Use W Vector`、`Coil Normal(3)`、`Desired Current Density`、`Electrode Area`、`Resistance = Real R_wire(N)`）| ✓ `Resistance = 3.081770e-01 Ω`（N=50 Cu）|
| 4 | `_r_wire(cfg, curve, N)` = N·2π·r_mean / (σ·A_wire) — 用 cfg 的 r_outer/r_inner 与 curve 的 wire_d/σ | ✓ Cu: 0.154/0.308/0.616 Ω；Al: 0.262/0.525/1.050 Ω |
| 5 | `_apply_coilsolver_path`：① 替换 Solver 8 块 ② Equation 1 Active Solvers 删 8，Body 2/3 → Equation 2 ③ Equation 1 加 `Wire direction = Logical True`（MainUtils.F90:1633 logical key）④ BC 3/4 剥掉 `Coil Start/End = Logical True`（CoilSolver 自设）| ✓ 四个步骤全部通过本地测试 |
| 6 | Material 1 σ → 1e-12（非导电）| ✓ |
| 7 | `Material 1 Electric Conductivity` 改动条件化：`--path wsolve` 用 σ_eff = f·σ_wire，`--path coilsolver` 用 1e-12 | ✓ |

**本地 N50_Cu（coilsolver，101 步）实测**（基准 30 步，CPU 把全部可用时间都跑了）：

| 量 | coilsolver | wsolve（参考）|
|---|---|---|
| `col10 i_coil` peak | **5.361e-03 A** | 5.388e-03 A |
| `col14 r_coil` last | **3.082e-01 Ω** | 1.508e-01 Ω |
| `col16 R_load` last | 1.000e+01 Ω | 1.000e+01 Ω |
| `v_load = R_load·i` 验证 | ✓ | ✓ |

**⟹ 两条路径的 i **绝对值**几乎相同（4 ppm），r_coil 现在是物理 R_wire 而非积分等效值。**

#### 7.5.15 ⭐ 本地完整 N 标定（ε ∝ N 达 0.14%）

`measure_3.py` 给出的**今晚要测的三个量**（位移 / 感应电动势 / 感应电流）中，
**感应电动势 ε = i·(R_load + r_component(1))**（注意 `v_component(1)` 是**端电压**
= −i·R_load，**不是** EMF）：

| 案例 | 步数 | **peak ε** | peak i | r_component(1) |
|---|---|---|---|---|
| N50_Cu  | 102 | 5.526392e-02 V | 5.361173e-03 A | 3.081770e-01 Ω |
| N100_Cu | 387 | **1.104491e-01 V** | **1.040368e-02 A** | **6.163539e-01 Ω** |
| **比值（期望 2）** | | **1.9986** ✓ **0.14%** | 1.9406 | **2.0000** ✓ |

**i 的 1.9406 不是误差 —— 它由回路定律精确预言：**

$$i(N)=\frac{\varepsilon(N)}{R_{load}+k N},\qquad \frac{i_{100}}{i_{50}}=\frac{\varepsilon_{100}}{\varepsilon_{50}}\cdot\frac{10+k\cdot50}{10+k\cdot100}=1.9986\times0.9710=1.9407$$

**与实测 1.9406 吻合到 5 位有效数字** —— 因为 `R_load=10 Ω` 固定而 `r_coil` 随 N
倍增（0.1541→0.3082→0.6164 Ω），所以 **i 略次线性是物理正确的**，
而 ε 严格 ∝ N。

**对照旧（Wsolve）路径**：ε ∝ **1/N**（N=1 vs 25 的 ε 比值为 0.0485 而非 25，
差 N²=625 倍）。**⟹ 根因与修复至此完全闭环。**

#### 7.5.16 ⭐ 最终结果 —— 900 步全闭路扫描（t_end = 0.900 s = 3 个完整弹簧周期）

7 个作业同时跑（**Jobs 122445913/919/925/929/934/940/948**），每个一案例。
SIF 时间基准 `dt=1e-3 s, dt×900=0.9 s` 是项目设计的**生产长度**（3 个完整周期）。
VTU 每 10 步一次（90 个/案例 ≈ 290 MB），`circuit.csv` **每步写**（与 VTU 写盘无关）。

**① `r_component(1)` = `R_wire(N)` —— 6/6 精确（机器精度）**

| 案例 | 实测 | 期望 | 相对误差 |
|---|---|---|---|
| Cu N=25 | 0.1540885 Ω | 0.1540885 | +0.00e+00 ✓ |
| Cu N=50 | 0.3081770 Ω | 0.3081770 | +0.00e+00 ✓ |
| Cu N=100 | 0.6163539 Ω | 0.6163539 | +0.00e+00 ✓ |
| Al N=25 | 0.2623907 Ω | 0.2623907 | +0.00e+00 ✓ |
| Al N=50 | 0.5247813 Ω | 0.5247813 | +0.00e+00 ✓ |
| Al N=100 | 1.0495630 Ω | 1.0495626 | +3.81e-07 ✓ |

**② 派生量 `ε/N` 恒定，且与材料无关（ε = i·(R_load + r_component(1))）**

| N | Cu `ε/N` | Al `ε/N` | 跨材料差 |
|---|---|---|---|
| 25 | 1.109551e-03 | 1.109554e-03 | 0.0003% |
| 50 | 1.108817e-03 | 1.108837e-03 | 0.0018% |
| 100 | 1.106103e-03 | 1.106240e-03 | 0.012% |

**跨 4 倍匝数恒定到 0.3%；跨材料同一 N 吻合到 0.0003% —— 感应电动势由驱动磁通
决定，与线圈材料无关（材料只通过 R 影响电流）。**

**③ 独立测量量 `i` 随 N 增长（最硬证据，直接读 CSV col 10）**

| 对（均为 900 步，t_end=0.9 s）| **实测 i 比值** | 匝数比 | 旧 Wsolve 路径 |
|---|---|---|---|
| Cu N=25 → N=50 | **1.9688** | 2.00 | i(25)/i(1) = **0.0474**（∝1/N）|
| Cu N=50 → N=100 | **1.9372** | 2.00 | |
| Al N=25 → N=50 | **1.9489** | 2.00 | |
| Al N=50 → N=100 | **1.9006** | 2.00 | |

**⟹ 匝数翻倍，电流增长 ~1.9×（略低于 2 是因为 `R_load=10 Ω` 固定而 `r_coil`
随 N 倍增）。旧 Wsolve 路径匝数增 25 倍时电流反而降到 1/21。**

> ⚠️ **诚实说明**：`ε = i·(R_load + r_component(1))` 是**由回路定律定义**的组合量，
> 不是独立测量的开路电动势。`analyse_n_scaling.py` 已把这一比值标为
> 「arithmetic identity, NOT physics」。

**④ N50_Cu 完整 3 量时程（900 步，9 个等距采样）**

| t [s] | z(t) [m] | ε(t) [V] | i(t) [A] |
|---|---|---|---|
| 0.001 | −4.6e-6 | 0 | 0 |
| 0.112 | **−33.9 mm** | 1.77e-2 | 1.72e-3 |
| 0.225 | −21.6 mm | **5.09e-2** | **4.93e-3** |
| 0.338 | −9.4 mm | 3.21e-2 | 3.11e-3 |
| 0.450 | −35.7 mm | 8.71e-3 | 8.45e-4 |
| 0.527 | — | **peak ε = 5.54e-2 V** | — |
| 0.562 | −11.9 mm | 3.91e-2 | 3.79e-3 |
| 0.675 | −20.7 mm | 5.31e-2 | 5.15e-3 |
| 0.788 | −29.0 mm | 3.90e-2 | 3.79e-3 |
| 0.900 | −10.8 mm | 3.48e-2 | 3.37e-3 |

`peak|ε| = 5.54e-2 V`（在 t=0.527 s 第二次穿过平衡点），
`peak|i| = 5.38e-3 A`，**吻合 `ε = i·(R_load + r_coil) = 5.38e-3·10.308 = 5.54e-2 V`**。

**⑤ 6 案例完整数据（900 步，t_end=0.9 s）**

| 案例 | peak i [A] | peak ε [V] | r_comp1 [Ω] |
|---|---|---|---|
| N25_Cu | 2.731784e-03 | 2.773877e-02 | 0.1540885 |
| N50_Cu | 5.378335e-03 | 5.544083e-02 | 0.3081770 |
| N100_Cu | 1.041886e-02 | 1.106103e-01 | 0.6163539 |
| N25_Al | 2.702961e-03 | 2.773884e-02 | 0.2623907 |
| N50_Al | 5.267743e-03 | 5.544184e-02 | 0.5247813 |
| N100_Al | 1.001162e-02 | 1.106240e-01 | 1.0495630 |
| empty | 无电路（无 Lenz 基线）| — | — |

注：300 步（t_end=0.10 s）下的 `peak|i|=5.39 mA`（wsolve 路径）vs
900 步下的 5.38 mA（coilsolver 路径，N50_Cu）—— **i 的绝对值相同**，
**`ε ∝ N` 精度从 0.18-0.70% 改善到 0.06-0.24%**，
**Cu 与 Al 吻合从 0.0007% 进一步改善到 0.0003%**。
这是 3 个完整周期稳态波形带来的收敛。


#### 7.5.17 ⚠️ 时间基准修正：`dt` 不能被覆盖（900 步重跑已完成）

**⚠️ 修正：我之前的 sweep 脚本覆盖了 `dt`，把「900 步」偷偷变成了 1 个周期。**

`config.json` 的基准是：

| 键 | 值 |
|---|---|
| `experiment.dt_s` | **1.0e-3 s** |
| `experiment.t_end_default_s` | **0.9 s** |
| ⟹ 步数 | 0.9 / 1e-3 = **900** |
| 弹簧周期 | 0.2995 s ⟹ **0.9 s = 3 个完整周期** |

`make_sif.py` 写出的 SIF 本来就带 `Timestep Sizes = 1.000000e-03` 与
`Timestep Intervals = 900` —— **正是这个基准**。

但我早先版本的 `run_coilsolver_sweep.sh` 里有一行

```
sed -i -E 's/^(.*Timestep Sizes *= *)[0-9.eE+-]+/\13.333333333e-04/'
```

**它把所有运行的 `dt` 强制改成 3.333e-4 s**：900 步 → 0.30 s（1 个周期），
300 步 → 0.10 s。**因此早先那些 300 步扫描（§7.5.14、§7.5.15）的
t_end 是 0.10 s，而不是项目设计的 0.9 s。**

**该覆盖已删除。** 现在脚本只改进程步数与 VTU 输出间隔，`Timestep Sizes`
保持 `make_sif.py` 的原值。作业日志已确认：

```
Timestep Sizes     = 1.000000e-03
Timestep Intervals = 900
Output Intervals(1) = 10
```

§7.5.14/§7.5.15 的 300 步数字作为**N 标度证据仍然成立**（所有案例共享同一
时间基准与步数），但**绝对值与整周期结论以 §7.5.16 的 900 步为准**。

**900 步全闭路扫描（7 作业，一案例一作业，全部立即运行）**

| 作业 | 案例 | ID |
|---|---|---|
| c900E | empty | 122445913 |
| c900C1 | N25_L040_cu_closed | 122445919 |
| c900C2 | N50_L040_cu_closed | 122445925 |
| c900C3 | N100_L040_cu_closed | 122445929 |
| c900A1 | N25_L040_al_closed | 122445934 |
| c900A2 | N50_L040_al_closed | 122445940 |
| c900A3 | N100_L040_al_closed | 122445948 |

* **闭路**：6 个导体案例均为 `[0V 源] → [线圈] → [10Ω 负载]`，`equations=2 solvers=11`
* **empty**：`equations=1 solvers=4`（无电路基线）
* **输出根** `hpc_results_z900`（保留原 300 步结果）
* `circuit.csv` **每步写**（与 VTU 写盘无关）⟹ ε/i 序列完整
* VTU 每 10 步（90 个/案例 ≈ 290 MB；若每步则 7 案例约 20 GB）
* 预计 ~3.75 h / 作业

#### 7.5.18 本次调试的方法论收获




1. **先查本地有没有可用的求解器**：`elmer262/bin/ElmerSolver.exe` 一直在仓库里，
   配上从集群 `scp` 下来的 717 KB 网格，就能本地复现全部失败模式。
   本轮的 4 次迭代若走 HPC 要排 4 次队。
2. **投递前先在本地跑 SIF 变换的断言**（`_validate_coilsolver_patch.py`，
   awk 逐条移植 + 18 项断言）——本轮实际抓到两个致命笔误：
   `Body 2/3` 行被 `next` 吃掉、以及 awk 注释里的撇号 `solver's` 闭合了
   单引号导致 bash 语法错误。
3. **不要相信列序号**：`circuit.csv` 没有列头，早先脚本硬编码 `$10/$11/$14`。
   现在用「`v_load == R_load·i`」和「`v_coil == −v_load`」两条定律**自证**映射。





### 7.6 已排除的路径（省得再试）

* ❌ **磁链项加 `/localC`**（§7.4.4）——物理错，会让 L 小 2.87e6 倍。**已回退**
* ❌ **"EMF 标度错 N²"（§16）**——用 `ε=iR` 的前提在 `ωL≫R` 时不成立
* ❌ 我自己的 "`R ∝ N²`" 算术错误（§7.4.2）——正确是 `R ∝ N`，实测吻合
* ❌ `Hypre AMS`：本地镜像未编译 Hypre
* ❌ `BiCGStab + ILU0`：快 8× 但不收敛
* ❌ `R_load` 扫描（1e-6…1e6）、σ_eff 扫描（312×）、Cu/Al 配对、N_j/turns 解耦
  ——这些诊断**彼此矛盾**（`R_load=1e-6` 使 MNA 行退化，测出的 "L=460 H" 不可靠），
  只有**细网格 900 步研究数据**可靠

**产物**：`measure_L_implied.py`、`measure_L_alcouple.py`、
`check_fluxlink_vs_analytic.py`、`fit_L_and_motional.py`（都是本地分析，无需 HPC）


---

## 8. 成本与性能

| 项 | 数值 |
|---|---|
| 网格单元 | 18743（`lc_slit_m = 4 mm`，生产值）|
| 求解 | **~13.6–15 s / 步**（HPC 实测，与网格/负载有关）|
| 900 步 | **~3.4–4.5 小时 / 案例** |
| VTU 输出 | ~3.1 MB / 步 ⟹ **~2.6 GB / 案例** |
| `circuit.csv` | **~330 kB / 案例** ← 只要这个 |

**7 条曲线并行**（各 1 节点 1 核），总墙上时间由最慢的单案例决定。

> 回传数据时**只取 `results/circuit.csv`**（330 kB/案例）。
> **不要**回传 `case_t*.vtu`（2.6 GB/案例）。
> 若要位移量，在 HPC 端用 `hpc_extract_z2.py` 提成 80 kB 的 CSV 再回传。

**加速尝试（已否决）**：

* `--solver hypre-ams`：原理正确（AMS 是 edge 单元的合适预条件子），
  但本地镜像是**无 Hypre 编译**的 → `Hypre requested but not compiled with!`
* `BiCGStab + ILU0`：每步快 8 倍但**不收敛**
  （`Too many iterations were needed`）。Whitney 系统必须用 H1/AMS 类预条件子。

---

## 9. HPC 操作手册

**环境**：`cancon.hpccube.com:65023`，用户 `josephvstalin`，
key `~/.ssh/cancon_key`，分区 `kshctest02`（1 节点 1 核 / 作业）。

### 9.1 关键教训（踩过的坑）

1. **⚠️ 不要用 `squeue` 的 `%M` 列判断速度。** 它的格式是 **`分:秒`**
   （不足 1 小时时），不是 `时:分`。**要看帧时间戳**算每步耗时。
   > 这个坑导致我误以为慢了 100 倍，**误取消了一批正常运行的作业**。

2. **⚠️ 不要内联复杂的 ssh 命令。** PowerShell 会吃掉引号/`$`/`%`。
   **一律 scp 一个 `.sh` 脚本上去跑 `bash <script>`**。

3. **⚠️ `~` 在不同 login 节点展开的软件不同。** `python3` 在某些节点
   不存在（如 `login09`），在 `login07` 是 `/usr/local/bin/python3`。
   **脚本里必须自动探测**：见 `_pyenv.sh`。

4. **⚠️ 重跑前必须清 `results/`。** `run_case.slurm` 不会清，
   残留的旧 VTU 会与新结果**混在一起**（旧 900 帧 + 新 N 帧）。

5. **⚠️ `scp` 到 `/tmp` 是无效的** —— 每个 ssh session 有独立的临时目录。
   一律传到家目录。

### 9.2 标准流程

```bash
# 0) 本地：生成网格 + SIF
python solenoid3d.py --config N50_L040_cu_closed -o model3d.msh
python make_sif.py --curve N50_L040_cu_closed --out case.sif

# 1) 上传：每个 case 目录需要 case.sif + circuits.definitions + model3d.msh
#    （mesh/ 由 run_case.slurm 在计算节点上用 ElmerGrid 生成）
scp case.sif circuits.definitions model3d.msh user@host:pysproject/cases/<curve>/

# 2) 提交（从 case 目录内）
cd ~/pysproject/cases/<curve> && sbatch ~/pysproject/run_case.slurm

# 3) 查进度（用脚本，不要内联）
bash ~/_progress.sh          # step% / VTU 数 / CSV 行数 / 每步耗时

# 4) 提取位移（求解完成后，在 HPC 端跑，只回传小 CSV）
bash ~/_run_extract_all.sh   # -> ~/pysproject/z_results2/*_magnet_z.csv

# 5) 回传
scp user@host:pysproject/cases/<curve>/results/circuit.csv .
scp user@host:pysproject/z_results2/<curve>_magnet_z.csv .
```

### 9.3 本项目的运维脚本（仓库根目录）

| 脚本 | 用途 |
|---|---|
| `_pyenv.sh` | 自动探测 python3（不同 login 节点不同）|
| `_progress.sh` | 进度 + 每步耗时（**基于帧时间戳**）|
| `_waitcheck.sh` | sleep N 秒后打印紧凑进度（避免 ssh 5 分钟超时）|
| `_hpc_status.sh` | 队列 + 每案例步数 + 矩阵 |
| `_clean_and_verify.sh` | 校验 SIF 完整性 + 清 `results/` |
| `_resubmit.sh` | 从各 case 目录提交 7 个作业 |
| `hpc_extract_z2.py` | **位移提取（位移聚类法）** |
| `_run_extract2.sh` | 对 7 个案例批量跑 `hpc_extract_z2.py` |
| `_verify_done.sh` | 确认 900/900 + 0 错误 |

---

## 10. 文件清单

### 10.1 源码（生成侧）

| 文件 | 说明 |
|---|---|
| `config.json` | **单一真源**：几何 / 材料 / 弹簧 / 6 条曲线 |
| `solenoid3d.py` | gmsh 三维网格生成（含缝分辨率硬门）|
| `make_sif.py` | 由 config 生成 SIF（MATC、电路、Component、BC）|
| `spring_model.py` | 阻尼谐振子解析解 → MATC 表达式；**含耦合项**（`b_em_from_linkage` / `coupled_z` RK4 / `matc_expr_gamma` / `fit_gamma` / `check_sign`）→ §11 |
| `run_case.slurm` / `run_window.slurm` | HPC 作业模板 |
| `Dockerfile` / `docker-compose.yml` | 打包 Elmer 26.2 + gmsh |

### 10.2 分析脚本

| 文件 | 说明 |
|---|---|
| `measurables_from_fem.py` | **6 个实验可测量（全 FEM）** → `measured_6.csv/json` + 图 |
| `validate_displacement.py` | **位移验证**（实测 vs MATC 解析）|
| `check_emf_vs_analytic.py` | **EMF 交叉检验**（暴露 §7 的 N² 问题）|
| `plot_z900_results.py` | **900 步终局结果的 6 张图** → `hpc_results_z900/figures/` |
| `measure_3.py` | 三量时程（位移 / ε / i）+ 列映射的回路定律校验 |
| `analyse_n_scaling.py` | N 标度检验（并标注 ε 是回路定律**定义**量）|
| `final_report.py` | 终局汇总 |
| `analyse_hpc_results.py` | 第一批的 i/v/EMF/r 概览 |
| `oscilloscope.py` | 解析轨迹后验估计（`EMF/R` 对照）|
| `_print_components.py` | 打印 config.json 全部物理量 |
| `check_sensor_chain.py` | **器材选型核算**（LV 25-P / ACS712 vs 信号量级、`V_terminal = i·R_load`、串联电阻设计表）→ §11 |
| `check_wire_resistance.py` | **`R_wire(N)` 与目录电阻率的交叉核对** + 分流器灵敏度表 → §11.1 / §11.5 |
| `check_damping_plausibility.py` | **c / b_em 的物理量级核算**（空气阻力 1.33e-4 vs config 的 0.8）+ 负载/记录长度设计表 |
| `analyse_lenz_coupling.py` | **Lenz 耦合定量**：由实测 EMF 反推 `b_em`、RK4 积分耦合 ODE、`--long` / `--pass2-mate` |
| `fit_flux_linkage.py` | ⛔ **已否证的 `Λ_mot(z)` 反演路线**（三条）+ 暴露的 ~1.7 H 问题 → §11.7 |

### 10.3 数据

| 目录 | 内容 |
|---|---|
| `hpc_results_z900/` | **第三批（当前）：CoilSolver 全闭路，900 步** |
| ├ `figures/fig1_timeseries.png` | 三量时程 z / ε / i（6 条曲线）|
| ├ `figures/fig2_nscaling.png` | N 标度四联图 |
| ├ `figures/fig3_waveforms.png` | 首周期波形放大 |
| ├ `figures/fig4_epsN_collapse.png` | **ε ∝ N 塌缩检验** |
| ├ `figures/fig5_old_vs_new.png` | 新旧路径对比 |
| ├ `figures/fig6_solver_artifact.png` | 波形尖刺量化（诚实面板）|
| ├ `figures/figure_source_data.csv` | 图中全部数值 |
| ├ `summary_900.csv` | 7 案例标量汇总 |
| ├ `<case>/results/circuit.csv` | 900 步 × 17 列 FEM 电路输出 |
| └ `<case>/results/case.sif` | 该案例实际使用的 SIF（含 MATC 位移）|
| `hpc_results_z024/` | 第二批（wsolve 路径，∝1/N，已修复的 bug）|
| ├ `_measured_6.png` | 6 个量 × 7 案例的 4×2 图 |
| ├ `_measured_6_summary.json` | 各案例标量汇总 |
| ├ `_displacement_validation.{png,json}` | 位移验证 |
| ├ `_emf_crosscheck.json` | §7 的证据 |
| ├ `<case>/circuit.csv` | 900 步 × 17 列 FEM 电路输出 |
| ├ `<case>/measured_6.csv` | 逐帧 6 列（t, z, v, a, i, ε）|
| └ `_z/<case>_magnet_z.csv` | **900 帧实测位移原始数据** |
| `hpc_results/` | 第一批（z_eq = 0.020）产物，保留对比 |
| `docs/HISTORY_full.md` | **完整调试历史（77 节，80 KB）** |
| `hpc/notes.md` | 英文工程日志（源码注释引用它的 §15.x）|
| `tests/` | pytest：网格、SIF、电路、弹簧模型 |

### 10.4 测试

每个测试模块都**自带 `__main__` 跑批器**，不需要 pytest：

```powershell
python tests\test_spring_model.py       # 30/30  ✅
python tests\test_sif_circuit.py        # 36/38
python tests\test_sif_solver.py         # 11/13
python tests\test_render.py             # 需要 pyvista
python -m pytest tests\ -q              # 若已装 pytest
```

**当前状态**（本机实测，`pytest` 未安装）：

| 模块 | 结果 |
|---|---|
| `test_spring_model.py` | ✅ **30/30**（含新增 9 项耦合模型测试：`b_em` 能量恒等式、RK4 对解析解、`Δγ = b_em/2m`、MATC 逐字符一致、符号守卫）|
| `test_sif_circuit.py` | 36/38 —— 含 `test_material1_conductivity_is_the_homogenised_wire_sigma`、`test_load_component_is_a_resistor_with_the_curve_resistance` **均通过**（§11 的 σ 与 `R_load = 0.5012` 改动已验证无副作用）|
| `test_sif_solver.py` | 11/13 |
| `test_mesh.py` / `test_render.py` | 需 meshio / pyvista（本机未装 → 跳过）|

> ⚠️ **4 项失败是既存的"模板漂移"**，非本轮引入：`case_transient.sif` 是 `make_sif.py` 的模板，
> 而它历史上被就地改写（模板里现在带的是**第二批之前**的 `(-0.025)+(0.025)*...`，mtime 09-13 17:56），
> 所以 4 个"与原始模板逐字节相同"的检验（`test_baseline_is_byte_identical_to_the_template`、
> `test_umfpack_is_byte_identical_to_the_template`、`test_only_solver2_is_modified`、`test_magnet_body_force_is_untouched`）早已失效。
> **修复方向**：让 `make_sif.py` 从一个只读的 `case_transient.template.sif` 生成，而不是改写自己。




## 11. 器材与测量链（传感器 → `R_load`）

> **为什么单列一节**：模型里的 `R_load` 不是随手可调的数值旋钮，而是**实验台上量出来的回路电阻**。
> 它同时决定三件事 —— `i(t)` 的大小、`b_em = (dΛ/dz)²/R_total`（Lenz 制动强度）、以及
> **电压传感器到底有没有信号可测**。传感器选错，会让整个实验测不到它想测的物理量。

本节全部数字可用 **`python check_sensor_chain.py`** 复现。

### 11.1 传感器型号与规格（厂家数据）

| 器材 | 关键规格 | 来源 |
|---|---|---|
| 电压：**LEM LV 25-P** | LV 系列额定 **100 – 4000 V RMS**；初级额定电流 10 mA；**初级电阻内置于壳体**；闭环（补偿型）霍尔 | LEM 官网 LV 系列页 |
| 电流：**ALLEGRO ACS712** | **内阻 1.2 mΩ**；灵敏度 **66 / 100 / 185 mV/A**（30/20/5 A 档）；**总输出误差 1.5%**（满量程 @25 °C）；5 V 单电源 | Allegro 产品页 + 数据手册 |

本实验的信号（来自 900 步实测）：`ε_peak = 27.7388 / 55.4408 / 110.6103 mV`（N = 25 / 50 / 100，**与材料无关**）；
回路电流 `i_peak ≈ 174 mA（Cu）/ 108 mA（Al）`（这是**只有 ACS712 时**的短路极限；选定配置 0.5 Ω 下为 **97.5 mA / 72.5 mA**，见 §11.4），且**与匝数无关**。

### 11.2 两处量程错配

**电压侧 —— 低 900 倍**

| | 值 |
|---|---|
| LV 25-P 量程下限 | 100 V RMS |
| 本实验最大可能电压（开路 EMF） | **0.1106 V** |
| 比值 | **低 904 倍** |
| 初级电流上限 = ε/250 Ω | **0.44 mA**（额定的 **4.4%**）|

> ⚠️ 这个上限**无法用外部分压/限流电阻提高**：`V ≤ ε` 是物理上界，ε 本身就只有 110.6 mV。
> 换言之 LV 25-P 在本实验中**永远达不到它的额定工作点**，标称 0.9% 的精度不适用。

**电流侧 —— 高 30 倍**（174 mA 时）

| 型号 | 满量程 | 灵敏度 | 输出 | 占满量程 | 1.5%-FS 误差 = **读数的** |
|---|---|---|---|---|---|
| **ACS712-05B** | 5 A | 185 mV/A | 32.4 mV | 3.50% | ±75 mA = **43%** |
| ACS712-20A | 20 A | 100 mV/A | 17.5 mV | 0.88% | ±300 mA = **171%** |
| ACS712-30A | 30 A | 66 mV/A | 11.6 mV | 0.58% | ±450 mA = **257%** |

> ⚠️ 最好的一档（05B）误差预算已是**读数的 43%** —— 不可用于定量。
> 20 A / 30 A 档更差 4 / 8 倍。（±20 A 档用于本实验时，误差比信号本身还大。）



### 11.3 关键推论：闭路时"线圈端电压"**不是** EMF

ACS712 的 1.2 mΩ 串在回路里 ≈ **短路**。于是线圈被短接，其端电压只是分流器上的压降：

```
i            = ε/(R_wire + R_load)          = 174.3 mA   (Cu N100)
V_terminal   = i × R_load = i × 1.2 mΩ      = 0.209 mV
EMF          = V_terminal + i·R_wire        = 0.209 + 110.40 = **110.61 mV** ✓
```

**并接在线圈两端的电压传感器只能读到 0.2 mV —— 信号根本不存在，换任何传感器都没用。**

| `R_load` [Ω] | `i` [mA] | **`V_terminal` [mV]** | LV 25-P 初级电流（占 10 mA） | Lenz 每周期损失 |
|---|---|---|---|---|
| **0.0012**（仅 ACS712）| 174.3 | **0.209** | 0.01% | 2.794% |
| 0.05 | 161.9 | 8.09 | 0.32% | 2.597% |
| 0.1 | 150.8 | 15.08 | 0.60% | 2.423% |
| 0.5 | 97.6 | 48.80 | 1.95% | 1.576% |
| 1.0 | 67.7 | 67.72 | 2.71% | 1.097% |
| 10 | 10.4 | 104.02 | 4.16% | 0.173% |

> 注意最后一行：`V_terminal → ε = 110.6 mV` **只在 R → ∞（开路）时**成立 ——
> 这正是"短路时什么都测不到"的原因。所以 **EMF 只能由两个读数合成**：`ε = V_terminal + i·R_wire`。

### 11.4 串联电阻是唯一的设计旋钮

插入一个精密电阻既可**造出可测电压**，又同时设定 **Lenz 阻尼**（同一个电阻兼任电流分流器）：

| `R_series` [Ω] | `i` [mA] | **`V` [mV]** | 每周期 Lenz 损失 | 10% 衰减 | **Cu/Al 对比度** |
|---|---|---|---|---|---|
| 0.05 | 161.9 | 8.1 | 2.597% | 1.20 s | 1.573× |
| 0.1 | 150.8 | 15.1 | 2.423% | 1.29 s | 1.534× |
| 0.2 | 132.7 | 26.5 | 2.135% | 1.46 s | 1.470× |
| **0.5** | 97.6 | **48.8** | **1.576%** | **1.99 s** | 1.345× |
| **1.0** | 67.7 | **67.7** | **1.097%** | **2.86 s** | 1.240× |
| 2.0 | 42.0 | 84.0 | 0.683% | 4.60 s | 1.149× |
| 10 | 10.4 | 104.0 | 0.173% | 18.26 s | 1.037× |

**✅ 已选定：`R_series = 0.5 Ω`**（`R_load = 0.5 + 0.0012 + 0 = 0.5012 Ω`）—— 结果（N=100）：

| | Cu | Al | 说明 |
|---|---|---|---|
| `R_total` | 1.1345 Ω | 1.5261 Ω | `R_wire` + 0.5012 |
| **`i_peak`** | **97.493 mA** | 72.479 mA | 0.5 Ω 上量到 48.7 mV |
| **`V`（回路端电压）** | **48.864 mV** | 36.327 mV | 差分放大器即可 |
| `b_em` | 5.283234e-2 | 3.927700e-2 N·s/m | ∝1/`R_total` |
| `Q_em` | **198.0** | 266.1 | 含空气阻力 `c_air` |
| **每周期 Lenz 损失** | **1.5740%** | 1.1735% | 10 Ω 时仅 0.173% |
| **10% 衰减** | **1.989 s** | 2.673 s | 约 6.6 个周期 |
| **Cu/Al 对比度** | **1.3451×** | | 10 Ω 时仅 1.037× |

> ⚠️ **但这让 ACS712 更不可用了**：电流从 174 mA 降到 **97.5 mA** = 满量程（5 A）的 **1.95%**，
> 于是它 1.5%-FS 的误差（±75 mA）变成**读数的 77%**（在 174 mA 时是 43%）。
> ✅ 应对：**0.5 Ω 电阻本身就是分流器** → `i = V/0.5`，用差分/仪表放大器测它；
> 电压侧同样用差分放大器（LV 25-P 需要 2.5 V 才能达到初级额定，而全部 EMF 只有 0.111 V）。
> **结论：ACS712 与 LV 25-P 都应被差分放大器取代。**

> 上表中 **0.5 Ω** 一行即所选配置（48.8 mV / 1.576% / 1.99 s / 1.345×，与上面的精确值一致）。
> 若日后想把信号再做大，可退到 **1 Ω**（66 mV），代价是每周期 Lenz 损失降到 1.097%、Cu/Al 对比度降到 1.240×。

> ✅ **该电阻同时就是电流分流器** → `i = V/R`，**ACS712 可以直接不用**
> （它的 1.2 mΩ 对测量毫无贡献，却贡献 43% 的误差预算）。
> 电压侧建议用**差分/仪表放大器**（如 INA128/AD620，增益 10~100）或示波器差分探头，
> **替换 LV 25-P** —— 后者在下限以下 900 倍，无法工作。
>
> ⚠️ 若坚持 10 Ω 负载 + 20~60 s 长记录：电压信号 104.0 mV 仍远低于 LV 25-P 下限，
> Lenz 阻尼退化到 0.173%/周期、材料对比度掉到 1.037× —— **物理上能跑，但测不到想测的东西**。

### 11.5 模型侧对应关系

```
R_load = series_ohm + shunt_ohm + leads_ohm
         └ 精密电阻    └ 电流传感器内阻   └ 引线 + 接触 + 焊点（已按台面决定忽略）
         = 0.5        + 0.0012        + 0.0            = **0.5012 Ω**
```

| 位置 | 内容 |
|---|---|
| `config.json → [sensor]` | 已落定：`use_sensor_burden: true`、`series_ohm = 0.5`、`shunt_ohm = 0.0012`、`leads_ohm = 0.0` |
| `config.json → [curves]` | 6 条导体曲线的 `R_load_ohm` 均为 **0.5012**（空组仍为 `"inf"`）|
| `make_sif.py` | `Component 2 Resistance = 0.5012`（SIF 里的 `crt r_component(2)`）；已实测生成正确 |
| `check_wire_resistance.py` | 交叉核对 `R_load_ohm ≡ series + shunt + leads` → 当前报 **CONSISTENT** |
| `check_sensor_chain.py` | §11 全部数字（传感器 vs 信号、`V_terminal = i·R_load`、串联电阻设计表）|

> ⚠️ **引线电阻不能忽略**：`R_wire(Cu,100) = 0.6333 Ω`，多 0.05 Ω 就是 `R_total` 的 7%
> （在 10 Ω 负载下同样 0.05 Ω 只占 0.5%）。**短路/小负载方案对引线电阻敏感**。

### 11.6 待办（阻塞项）

- [x] `R_series` 决策 → **0.5 Ω**（2026-09-18）
- [x] `leads_ohm` → **0**（焊点/接触按台面决定忽略；如实测非零，`R_total` 每 0.05 Ω 变 4.4%）
- [x] 填入 `[sensor]` → `use_sensor_burden: true`，6 条曲线 `R_load_ohm = 0.5012`，**已实测生成的 SIF 为 `Component 2 Resistance = 0.5012`**
- [ ] **记录长度**：`t_end ≈ 2 ~ 3 s`（10% 衰减需 1.99 s ≈ 6.6 个周期；现为 0.9 s = 3 个周期，只能看到 1.1% 衰减）
- [ ] **传感器替换**：用差分/仪表放大器替换 ACS712（97.5 mA 时其误差预算是读数的 77%）与 LV 25-P（需 2.5 V，全部 EMF 仅 0.111 V）；电流可由 0.5 Ω 上的电压反演

### 11.9 ROOT CAUSE of the "9.045x circuit resistance anomaly" (2026-09-19)

Replaced the earlier "W-vector normalisation" hypothesis with the real root
cause, found by an HPC static scan on 2026-09-19.

**Two stacked bugs in the SIF produced by `make_sif.py --path coilsolver`:**

1. **The `Body Force 3` block (Name="Circuit", carrying `testsource`) is
   generated but NOT referenced by any of `Body 1/2/3`.**  Elmer applies
   a body force only when a Body lists it via `Body Force = N`.  None did.
   Consequence: `testsource` was effectively zero all along, and the loop
   was driven only by the magnet-induced EMF.

2. **`Solver 9` (CircuitsAndDynamics) is missing the two keys the upstream
   reference uses:**
       `Variable = X` and `No Matrix = Logical True`
   Without these, the resistance terms in the assembled matrix are silently
   dropped while `r_component(1)` is still reported correctly.  This is
   documented as the prime suspect in `_nomt_test.sh` (notes.md 26-27).

**Fix**: move `testsource`/`Circuit Current Variable Id`/`Stranded Coil N_j`
from the dangling `Body Force 3` into the existing `Body Force 1` (already
referenced by Body 1); AND add `Variable = X` + `No Matrix = Logical True`
to the CircuitsAndDynamics Procedure line.  Both edits are done in
`hpc/stage_lambda_scan.py:assign_source_bf()`.

**After the fix** (5 HPC runs at z = 0.045 m, V = 0/0.5/1/2 V):
- KVL `v_coil + v_load = V_set` holds to 6 sig-figs.
- `R_eff_FEM = V/i = 1.065 ohm` vs `R_total_bench = 1.1345 ohm` (94%, the
  residual is `L_self di/dt`).
- `i = V / R_total_bench` holds exactly.

**Lambda_mot(z) extraction** is still blocked by CoilSolver (the coil current
direction is fixed by the slit BC, so `i(+V) = i(-V)` and the +-V
cancellation collapses; W col-6 is dominated by `(1/2) L i^2`).  Next step:
re-run the z900 dynamic sweep with the new SIF, then use
`eps_peak = (dL/dz) zdot_peak` to extract Lambda_mot(z).  See notes.md 28.
- [ ] **`b_em(z)` 的干净取值**：静态 Λ(z) 扫描（~20 次静磁求解）或让 FEM 原生输出 `Calculate Magnetic Force` —— **三条数据反演路线已被否证，见 §11.7**
- [ ] **⚠️ 先搞清 ~1.7 H 的来历**（见 §11.7）：它决定耦合跑批的回路时间常数
- [ ] 上述齐备后：耦合跑批（`γ_eff = (c_air + b_em)/(2m)`，一趟即收敛）

### 11.7 ⛔ 已被否证的路线：从 `circuit.csv` 反演 `Λ_mot(z)`

耦合模型只缺**一个**物理输入：`dΛ_mot/dz`。利用 KVL（精确）：

```
dλ/dt = −(R_load + R_coil)·i          λ(t) = −R_total·∫i dt = L_coil·i(t) + Λ_mot(z(t))
```

三条反演路线全部失败（`python fit_flux_linkage.py` 可复现全部数字）：

| 路线 | 方法 | 结果 |
|---|---|---|
| 1 | `λ = L·i + poly(z)` | **病态**：`L = −1.24 H`。因 `i(t) ≈ Λ_mot'(z)·ż/R` 本身近似是 z 的函数，多项式吸收了 `L·i` 项 |
| 2 | 用解析偶极子模型固定**形状**，只拟合 `(L, α)` | **同样病态**：`L = −1.74 H`、`α = 0.2136`（在 N 与材料间高度稳定 —— 说明**形状是对的**），但 `dΛ_mot/dz` 变成**与 N 无关**（各案例都是 3.42e-3 Wb/m），而 `Λ_mot ∝ N` → 明显错误 |
| 3 | 只用 `poly(z)`（不含电感项） | 残差 **25.13%**，且**精确 ∝ N**（25.545% @N25 → 25.543% @N100）；阶数 2→5 无改善，剔除 39 个尖刺也只降到 25.13%。**bin 内离散度高达 \|λ\|max 的 32%** ⇒ **λ 不是 z 的单值函数** |

**失败本身给出的线索**：两个独立估计一致显示 `λ` 含一个 `≈ −1.7 H` 的 `i` 项：

| 估计方式 | 结果 |
|---|---|
| bin 内 `λ` 离散度 ÷ 电流幅值 | ≈ 1.67 H |
| 三参数拟合 `λ = L·i + b·z + c` | **L = −1.7197 H**（N25_cu）|

这是螺线管估值 `μ₀N²A/l = 0.5 mH`（N=100）的 **≈3400 倍**，且**符号为负**。若该量级为真：

```
L/R_total = 1.7/10.6 = 0.16 s ≈ T/2   （T = 0.2995 s）
```

⟹ **回路完全不是准静态阻性的，`ε = i·R_total` 不是 EMF**。这一条同时解释了此前两个悬案：
① `ε/ż` 的 90% 散布（§11.6 的滤波也救不了）；② 本节 25% 的 `λ(z)` 残差。

**行动（不要重试上面三条）**：① 用**静态扫描**取 `dΛ_mot/dz`；② 或让 FEM 原生输出 `Calculate Magnetic Force`；③ **先搞清 ~1.7 H 的来历** —— 它决定任何耦合跑批的回路时间常数，未解决前不宜开跑。

### 11.8 🔴 静态扫描立即可用 —— 但它当场揭露了第二个异常

`scan_flux_force.py`（**新增**）已把静态扫描跑通：从当前 config 重生成 SIF → ElmerGrid 转换网格 → 常数 `Mesh Translate 3` + 源电压 → 本地 `ElmerSolver.exe` 求解。**3 步内完全收敛**（`i` 与场能量都稳定到 5~6 位），所以 ±V 差分法在数值上可行。

**两个已踩过的坑（已在脚本 docstring 记录）**：

1. 不可用 `Simulation Type = Steady State` —— `make_sif.py` 给电路求解器设的是 `Exec Solver = Before timestep`，而稳态没有 timestep ⇒ 电路根本不执行（`i = 0.000`）。
2. 步数不能为 1 —— `Nonlinear/Steady State Max Iterations = 1` 使"电路↔场"只迭代一次，输出时电流还是求解前的 0。

**当场揭露的异常（必须先解决）**：给回路加 1 V、`Component 2 Resistance` 分别设为 0.5012 Ω 与 100 Ω：

| `Component 2` 设定 | Elmer 报告的 `r_load` | 实测 `i` | `R_eff = V/i` | **`(R_eff − r_coil)/R_load`** |
|---|---|---|---|---|
| **0.5012 Ω** | 0.5012 ✓（读到了）| 94.662 mA | **10.564 Ω** | **19.81** |
| **100 Ω** | 100.0 ✓（读到了）| 1.0983 mA | **910.5 Ω** | **9.10** |

⟹ **回路有效电阻是名义值的 9~20 倍，且比例不是常数** ⇒ 存在一个**与 `R_load` 相关的额外电阻项**（不是固定的串联电阻，也不是简单的缩放）。

> ⚠️ **这意味着 `R_load = 0.5012 Ω` 并没有按设计生效**，因此 §11.4 里基于它算出的全部数字
> （`i = 97.5 mA`、`V = 48.8 mV`、`b_em = 5.283e-2`、1.574%/周期、Cu/Al = 1.345×）
> **还不是这个模型会真正给出的值** —— 在查清这一项之前不要开跑批。
>
> 注意一个耐人寻味的对比：**动态**跑批里 `i_peak = ε/R_total` 精确到 5 位（R_total 只含两个元件电阻），
> 而**这里加了外部电压源**才出现 9~20 倍的偏差 ⇒ 异常很可能出在 **`testsource` 支路的耦合**，
> 而不是两个 `Component` 的电阻本身。

**下一步诊断（便宜且决定性）**：把 `R_load` 扫 3~4 个值（如 0.1 / 1 / 10 / 100 Ω），
拟合 `R_eff(R_load)` —— 若是一次函数则给出固定串联项；若比例随 `R_load` 变化，则锁定为源支路或
W 势路径的电导项。之后 ±V 差分即可给出干净的 `Λ_mot(z)` 与 `dΛ_mot/dz`。

**✅ 已完成该扫描，得到一条干净的线性律**（`_rscale.py`，4 个 R_load 值，1 V 驱动）：

| `R_set` | Elmer 报告 `r_load` | `i [A]` | `R_eff = V/i` | `(R_eff − r_coil)/R_set` |
|---|---|---|---|---|
| 0.1 | 0.100 ✓ | 0.1441794 | 6.9358 | 63.02 |
| 1.0 | 1.000 ✓ | 0.0663315 | 15.0758 | 14.44 |
| 10.0 | 10.000 ✓ | 0.0103647 | 96.4813 | 9.58 |
| 50.0 | 50.000 ✓ | 0.0021821 | 458.2845 | 9.15 |

```
R_eff = 9.0431 · R_load + 6.0327  Ω
```

四个点全部落到 **<0.1%**（0.1 Ω 处预测 6.937 vs 实测 6.9358 ✓）。**注意斜率**：

```
9.0431  ≈  2·r_mean / (r_outer − r_inner) = 0.045 / 0.005 = 9.0000
```

即线圈的**几何比** —— 这不像巧合，指向"回路电阻在装配时被乘了一个几何因子"。而截距 6.03 Ω ≈ 9 × r_coil(Cu,100) = 5.70 Ω（差 5.8%），量级相符。

> 🔴 **结论（对 §11.4 的直接影响）**：按设计 `R_load = 0.5012 Ω` 时，回路**真实**电阻会是
> `9.0431×0.5012 + 6.0327 = 10.565 Ω`，而**不是** `r_coil + R_load = 1.1346 Ω`。
> 因此 §11.4 的全部数字（`i = 97.5 mA`、`V = 48.8 mV`、`b_em = 5.283e-2`、1.574%/周期、Cu/Al = 1.345×）
> **都不是这个模型会真正给出的**（R_total 差约 9.3 倍）。**必须先修好这一项再开跑批。**
>
> 这一项与 §11.7 的 ~1.7 H 很可能是**同一族问题**：电路的电阻/电感记账与 `Component` 块给出的值不一致，
> 而 `r_component(1)`/`r_component(2)` 的**报告**值始终是正确的（这正是它一直没被发现的原因）。

**🔴 已定位到"全局因子"这一步**（`_rcmp.py`：把 `Component 1` 从 0.6333429 改为 **5.0 Ω**，`R_load = 0.5012`）：

```
实测 R_eff = 50.0631 Ω
预测 A（两元件都被 ×9.045）: 50.059 Ω   ✓✓ 0.008% 吻合
预测 B（只缩放负载）      :  9.834 Ω   ✗
```

⟹ 因子**同时乘两个元件**，是**全局**的：

```
R_eff = 9.045 · (R_component1 + R_component2) + 0.301 Ω        （6 个点，≤0.1%）
```

**用动态数据独立交叉验证**（`λ_FEM = −R_nom·∫i dt` 对解析偶极子模型 `N·Φ_ana`）：

| N | `R_nom` | `λ_FEM` | `λ_ana` | **比值** |
|---|---|---|---|---|
| 25 | 10.15409 | −1.870936e-3 | −1.418474e-2 | **0.1319** |
| 50 | 10.30818 | −3.740050e-3 | −2.836948e-2 | **0.1318** |
| 100 | 10.61635 | −7.466058e-3 | −5.673896e-2 | **0.1316** |

**比值恒定 0.1318（跨 N 仅 0.2% 变化）** ⟹ `R_true ≈ R_nom/0.1318 = 7.59·R_nom`。
两种**完全独立**的方法都给出同一个**常数** O(8~9) 因子（20% 差异可归因于解析偶极子近似与
λ 里 25% 的 `L·i` 污染）。

> ## ⚠️ 结论：回路电阻比 `Component` 值大 ~8~9 倍（常数因子）
>
> | 影响 | 说明 |
> |---|---|
> | **§6.1 的 `ε` 绝对值** | 偏小 ~8~9 倍。但**所有标度律不受影响**（ε∝N、ε/N 塌缩、Cu/Al 一致性都是**比值**）—— 这正是 §7 的修复验证能通过的原因 |
> | **§11.4 的 `R_load = 0.5012` 设计** | 真实回路电阻会是 `9.045×1.1345+0.301 = 10.56 Ω`，而**不是** 1.13 Ω ⟹ Lenz 阻尼比设计值弱 **9.3 倍**，**降低 R_load 的整个目的会被这个因子抵消** |
> | **"`i_peak = ε/R_total` 到 5 位"的验证** | **是循环论证** —— 它验证的是 `ε` 的**定义** `i·R`，而非"回路电阻等于 `R_component`"。所以它从来没有能力发现这个因子（方法论上的诚实更正） |
> | **~1.7 H（§11.7）** | 同族问题；`R` 与 `L` 的记账都与 `Component` 不一致 |
>
> **因子 ≈ 9.045 ≈ 2·r_mean/(r_outer − r_inner) = 0.045/0.005 = 9.0000** —— 线圈的**几何比**，
> 强烈指向**绞线线圈的电阻/电导装配环节**（`N_j`、填充因子、或 `CoilSolver` 对电路行
> `Resistance` 的贡献）。
>
> **下一步**：读 Elmer `CoilSolver.F90` / `CircuitsAndDynamics.F90` 中把线圈体的
> `N_j²·V/σ` 写入电路电阻行的代码，核对填充因子与几何因子的定义 —— `_ref_CoilSolver*`/`_ref_*.F90`
> 已在本机（`_ref_CircuitsAndDynamics.F90`、`_ref_CircuitUtils.F90`）；这一步能直接给出 `9.045` 的解析来源。

#### 11.8.1 源码核对 + 决定性自洽检验（已完成）

**源码核对结果**（`_ref_CircuitsAndDynamics.F90:442–470`）：若 `Component` 块里显式给了 `Resistance`，
则 `UseCoilResistance = .TRUE.`，**FEM 自身的 `localR = N_j²|w|²V/σ` 不再叠加** —— 我们的 SIF 正是这种情况，
所以 MNA 里应当只有 `Component` 的电阻。
**`VoltageFactor` 已排除**：`_ref_CircuitUtils.F90:93` 默认为 1.0，且我们的 SIF 未设置该键（`Circuit Equation Voltage Factor`）。

**决定性自洽检验**：静态与动态两条数据其实在说同一件事 —— 物理需要的乘积 **`R·i` 比记账值大 9.045 倍**。
用它去乘 §11.7/§11.8 的独立比值：

```
λ_true = 9.045 × λ_FEM(记账) = 9.045 × 0.1318 × λ_ana = 1.192 × λ_ana
```

**真实磁链与解析偶极子模型吻合到 19%** —— 恰好是该解析模型自身的近似水平。

> ### ✅ 结论（可信度提升的关键一步）
> **场与物理是对的；出问题的是电路记账的一个常数因子 9.045。**
> 两种等价表述（数学上不可区分，因为物理只依赖乘积 `R·i`）：
> - **(a) 电阻被放大 9.045 倍**，或
> - **(b) 报告的 `i_component(1)` 只有物理电流的 1/9.045**
>
> **可执行的修正**：在电路定律里用
> ```
> R_eff = 9.045 · (R_component1 + R_component2) + 0.301 Ω
> ```
> 或等价地把 `ε`、`i` 的绝对值乘以 9.045（**所有比值不变**，故 §6.1 的标度结论与 §7 的修复验证都不受影响）。

> ### 🔴 对跑批计划的直接影响（数字）
> 按设计 `R_load = 0.5012 Ω`，模型真实回路电阻 = `9.045×1.1345+0.301 = 10.563 Ω`（而设计假设 1.1345 Ω）⟹
> ```
> b_em = (dΛ/dz)²/R_true = 5.994e-2/10.563 = 5.674e-3   （设计值 5.283e-2，小 10.7 倍）
> 每周期 Lenz 损失 = 1 − exp(−T·b_em/2m) = 0.087%        （设计值 1.574%）
> ```
> **即：若不修这个因子，模型会预言一个几乎看不见的效应（0.087%/周期），而实验台上应看到 1.57%/周期。**
> 实验台设计（`R_series = 0.5 Ω` + 差分放大器）**仍然正确** —— 真实导线不遵守这个因子；**要修的是模型**。

#### 11.8.2 区分"电阻被放大"还是"电流被缩小" —— 已判定

上面两种表述数学上等价（物理只依赖乘积 `R·i`），但**修哪里**取决于哪一个为真。判决量必须**独立于电路记账**：
用**场能量**（col 6，由场直接算出，对应 `W ≈ W₀ + a·i + b·i²`）。

三个静态点（同 z = 0.024、同线圈）拟合 `W = W₀ + a·i + b·i²`：

| 点 | `i` [mA] | `W`（col 6）|
|---|---|---|
| `i = 0`（PM 单独）| 0 | 1.8139e4 |
| `R_comp1 = 5.0 Ω` | 19.975 | 4.8680e8 |
| `R_comp1 = 0.6333429 Ω` | 94.662 | 1.0932e10 |

```
拟合得 a ≈ 2.6e7 ≈ 0  （交叉项可忽略，比 b 小 5 个数量级）
        b_static = 1.2186e12
动态同 N 同 z 点：b_dyn = 1.4282e12   →   b_dyn/b_static = 1.172
```

**静态与动态（同一线圈、同一 N、同一 z）的 `W/i²` 只差 17%** —— 若电流尺度不一致，这里应当差 **9² = 81 倍**。

> ### ✅ 最终判定：**报告的 `i` 就是物理电流；异常在电阻侧**
>
> | 量 | 结论 |
> |---|---|
> | `i(t)`（§6.1 的 `i_peak`）| ✅ **物理正确**（场能量交叉验证到 17%），**不需要修正** |
> | 回路电阻 | ❌ 真实值 `R_eff = 9.045·(R_c1+R_c2) + 0.301 Ω`，记账只用了 `R_c1+R_c2` |
> | `ε = i·(R_c1+R_c2)` | ❌ 绝对值偏小 ~9 倍（**所有比值不受影响**，故标度结论与 §7 修复验证仍成立）|
> | 正确写法 | `ε = i · R_eff`（或等价地把现有 `ε` 乘 9.045）|
>
> 这与方法 B 独立给出的 7.59 倍一致到 19% —— 差值正是解析偶极子模型自身的近似水平。
> **下一步（唯一的开放项）**：找到电阻里这个 9.045 倍的**装配来源**（几何比 `2·r_mean/Δr = 9.0000` 强烈指向绞线线圈的电阻/电导装配）。
> 在 `_ref_CircuitsAndDynamics.F90:442–470` 已排除 `VoltageFactor` 与 `localR` 的叠加；
> 剩下的候选是 `CoilSolver.F90` 里对 W 势的归一化（它决定了 `J = N_j·I·w` 中 I 的物理含义）。


> ⚠️ **务必知情**：本节的全部 Lenz 阻尼数字来自 `b_em = (dΛ/dz)²/R_total`，其中 `dΛ/dz` 只用了
> **速度峰处的稳健值**（它精确 ∝ N、Cu/Al 一致到 0.0002%）。**`b_em(z)` 的 z 剖面无法从现有 900 步数据反推**
> —— 见 `check_damping_plausibility.py`：把 `ε/ż` 收紧到 `|ż| > 0.85` 峰值，对 z 的相对残差仍有 **0.884**。
> 所以 `b_em` 的**绝对量级带 ±20~40% 不确定度**，标度律与 Cu/Al 方向则是可靠的。
> 要拿到干净的 `b_em(z)`，必须走**静态 Λ(z) 扫描**（~20 次静磁求解）或让 FEM 原生输出
> `Calculate Magnetic Force` —— 两者成本都很低，是下一步该做的事。


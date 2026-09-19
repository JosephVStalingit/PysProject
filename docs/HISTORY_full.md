> # ✅ 当前状态（2026-09-16 06:50 CST）
>
> **7 个闭路案例已在 HPC 跑完第二次（900/900 步、0 错误），全部 6 个
> 可测物理量都取自 FEM 实测。**
>
> **第二次派发**（Job 122191155 … 122191186，2026-09-15 22:39 → 09-16 06:36 CST）
> 把 `spring.z_eq_m` 从 0.020 改成 **0.024 m**（依据 = 第一次跑完后从 900 帧
> VTU 实测到的平衡中线 22.4 mm），MATC 常数项随之 −0.025 → −0.021。
> 详见 **§14.6**。
>
> | 物理量 | N25 | N50 | N100 | 来源 |
> |---|---|---|---|---|
> | **i_peak** | 4.5498 mA | 2.2754 mA | 1.1378 mA | `circuit.csv` [FEM] |
> | **EMF_peak** | 44.811 mV | 22.067 mV | 10.691 mV | `circuit.csv` [FEM] |
> | **位移振幅** | 19.811 mm | 19.811 mm | 19.811 mm | 900 帧 VTU [FEM] |
> | 周期 T | 0.3000 s | 0.3000 s | 0.3000 s | 位移零交叉 [FEM] |
>
> **`i_peak` = 4.5498 : 2.2754 : 1.1378 = 精确 4 : 2 : 1**
> ⚠️ **但这条规律是 bug 的症状，不是验证 —— 见 §16！**
> 解析上 `ε = N·dΦ/dt ∝ N`，FEM 却给 `ε ∝ 1/N`，比值按 **1/N²** 漂移。
> **感应电流 i 与电动势 ε 的绝对值和 N 标度暂不可引用**；
> **位移 / 速度 / 加速度 / 磁通密度可信**（位移已验证到皮米级）。
>
> **位移量的验证（最关键）**：实测 `z(t)` 与 MATC 解析轨迹逐帧对比，
> **rms 残差 2.5 × 10⁻¹² m（2.5 皮米）**，相对振幅 **1.2 × 10⁻¹⁰**
> —— 即 RigidMeshMapper 把刚体平移执行到**双精度极限**。见 §14.6.2。
>
> **Cu 与 Al 的 i_peak 相同**，因为 `R_load = 10 Ω ≫ R_wire`（0.15–1.03 Ω）✓
>
> **数据位置**：
> * `hpc_results_z024/` —— 第二次跑的完整产物
>   * `_measured_6.png` —— 6 个量的 4×2 图（全 7 案例）
>   * `_measured_6_summary.json` —— 各案例标量汇总
>   * `_displacement_validation.{png,json}` —— 位移验证
>   * `<case>/measured_6.csv` —— 逐帧 6 列数据（t, z, v, a, i, ε）
>   * `_z/<case>_magnet_z.csv` —— 900 帧实测位移原始数据
> * `hpc_results/` —— 第一次跑（z_eq = 0.020）的产物，保留作对比
>
> **脚本**：`measurables_from_fem.py`（6 个量）、`validate_displacement.py`
> （位移验证）、`hpc_extract_z2.py`（HPC 端位移提取，位移聚类法）。
>
> **6 个实验可测量物理量（全部 FEM 实测，不含解析解）**：
>
> | # | 物理量 | 实验测量方法 | 数据源 |
> |---|---|---|---|
> | 1 | **z(t) 位移** | 激光位移计 / 高速相机 | **900 帧 VTU 磁体节点均值** [FEM] |
> | 2 | **v(t) 速度** | Doppler 振动计 | z(t) 中心差分 [FEM] |
> | 3 | **a(t) 加速度** | 加速度计 | v(t) 中心差分 [FEM] |
> | 4 | **i(t) 感应电流** | 示波器 + 串联采样电阻 | `circuit.csv` col 10 [FEM] |
> | 5 | **EMF(t) 感应电动势** | 示波器高阻探头 | `v_component(1) + i·R_wire` [FEM] |
> | 6 | **B(z) 磁通密度** | 霍尔探头 / 搜索线圈 | 末帧 VTU 轴向 [FEM] |
>
> **已剔除**（实验中难直接测）：F_spring, KE, PE, F_lenz, E_total。
> （这些仍在 `hpc_results/**/physics_10.csv` 里存档，带 [analyt]/[deriv] 标签。）
>
> **§13 的"460 H vs 1.249e-4 H"假说已推翻** —— 详见 §13 顶部 REVISED 段。
>
> ## 🔴 §16：感应电动势的 N 标度错了 **N²** 倍
>
> 独立交叉检验（`check_emf_vs_analytic.py`，见 **§16**）：
>
> | N | ε_FEM = i·R_total | ε_解析 = N·dΦ/dt | FEM/解析 |
> |---|---|---|---|
> | 25 | 46.2 mV | 179.3 mV | 0.26 |
> | 50 | 23.4 mV | 358.7 mV | 0.07 |
> | 100 | 12.1 mV | 717.4 mV | 0.02 |
>
> `ε_解析 ∝ N`（硬物理）而 `ε_FEM ∝ 1/N` —— **标度方向都反了**，
> 比值按 **1/N²** 漂移。
>
> **因此**：本次运行的
> * ✅ **可信**：位移 / 速度 / 加速度 / 磁通密度分布
> * ❌ **不可引用**：感应电流 `i` 与感应电动势 `ε` 的绝对值与 N 标度
>
> **10 个物理量 — 数据来源标签**（`compute_10_quantities.py`）：
>
> | 量 | 数据源 | 公式 |
> |---|---|---|
> | z(t), v(t), a(t) | **[FEM]**（N50 case）或 **[解析]**（其他 case）| FEM: 从 `_vtu_full/_magnet_z.csv` 读 900 帧 VTU Points z 的均值；解析: spring-damper 阻尼解 |
> | F_spring, F_grav | [FEM/解析] | −k(L−L₀), −mg |
> | KE, PE | [FEM/解析] | ½mv², ½k(L−L₀)²+mg(z−z_eq) |
> | F_lenz | [推导] | −i·ε / v |
> | i, ε, v_coil | **[FEM]** `circuit.csv` | Elmer CircuitsAndDynamics |
> | E_em | [FEM] `circuit.csv` col 6 | 含磁体本身 ~833 kJ |
> | E_total | [推导] = mech + R·i²·dt + c·v²·dt | 能量守恒 |
> | B(z) at t_end | **[FEM]** `_vtu_last/<case>_last.vtu` | ‖B_vec‖ at r<1mm |
>
> **N50_L040_cu_closed 的 FEM 真实轨迹与解析解的差异**：
>
> | 量 | FEM 真实 | 解析解 |
> |---|---|---|
> | z(t=0.001s) | 45.97 mm | 44.99 mm |
> | 振荡范围 | 9.7 ~ 46 mm（振幅 ~36 mm） | -5 ~ 45 mm（振幅 25 mm） |
> | 实测周期 | ~0.4 s（从 0.10 到 0.30 是 T/2） | 0.30 s |
> | t=14ms 时 v | -0.14 m/s（峰值速度） | -0.022 m/s |
>
> **FEM 磁体实际行为比解析解更剧烈**：振幅更大、周期更长（阻尼偏小）、
> 峰值速度 9× 更大——这意味着 i_peak 时的真实 EMF 也要比解析大。
> §6.1 / §11 里的"阻尼比 ζ=0.04" 假设可能需要重新测量。
>
> 本文档已合并 `hpc/notes.md` + `hpc/HANDOFF.md` + `hpc/DISPATCH.md`。
> `hpc/notes.md` 保留为英文原始工程日志（源码注释引用它的 §15.x）。

---

# 磁体自由落体 FEM 仿真工程

> 圆柱形永磁体挂在弹簧上（或自由落体），在闭路线圈中往复振荡。
> 三维瞬态 FEM（Elmer 26.2）解算 A 场与线圈电路耦合，
> 直接给出感应电流、EMF 与楞次制动力。
>
> **当前 7 条曲线**：1 条 `empty` 基线 + 6 条闭路导体曲线
> （N25/N50/N100 × 铜/铝）。
>
> `oscilloscope.py` 保留为**后验交叉校验**（用解析轨迹估算 `EMF/R`），
> 待 FEM 的 `i_component(1)` 修好后用来对照。见 §6.5。

**核心代码量**：~10 KB 源码 · Elmer 26.2 安装打包在 `./elmer262/` ·
`pip install -r requirements.txt` 一键环境 · Docker-ready

---

## 目录

1. [方法概览](#1-方法概览)
2. [PIP 安装](#2-pip-安装)
3. [文件清单](#3-文件清单)
4. [运行流水线](#4-运行流水线)
5. [Elmer 26.2 安装（项目内打包，Docker-ready）](#5-elmer-262-安装项目内打包docker-ready)
6. [几何、材料、电路](#6-几何材料电路)
7. [文档导航](#7-文档导航)
8. [FEM 测试](#8-fem-测试)
9. [FreeCAD 可视化解算全过程](#9-freecad-可视化解算全过程)
10. [config.json 字段详解](#10-configjson-字段详解)
11. [**闭路 FEM：六个关键机制**](#11-闭路-fem六个关键机制)
12. [**生产成本与网格稳定性门槛**](#12-生产成本与网格稳定性门槛)
13. [**根因：电感大了 3.7×10⁶ 倍（当前阻塞）**](#13-根因模型的电感大了约-37×10⁶-倍当前阻塞)
14. [**HPC 派发记录与结果**](#14-hpc-派发记录与结果)
15. [调试工具脚本](#15-调试工具脚本)
16. [**🔴 感应电动势的 N 标度错了 N² 倍（2026-09-16）**](#16-决定性发现感应电动势的-n-标度错了-n²-倍2026-09-16)

---

## 1. 方法概览

```
+--------------+     +--------------+     +--------------+     +--------------+
|  几何生成    | --> |  网格转换    | --> |  静磁求解    | --> |  时序可视化  |
|  gmsh 4.x    |     |  ElmerGrid   |     |  ElmerSolver |     |  FreeCAD     |
|  solenoid3d  |     |   14 2       |     |  26.2        |     |  1.1.x       |
+--------------+     +--------------+     +--------------+     +--------------+
   model3d.msh         mesh/              results/*.vtu       results_viewer
   ~1.4 MB            ~5 MB               case_t0001.vtu      .FCMacro
```

### 七个曲线（由 `solenoid3d.py --config` 切换）

| `--config` | Body 1 名称 | 角色 | `N_turns` | 材料 |
|---|---|---|---|---|
| `empty` | `AirInside` | 基线，无导体 ⟹ 无电路、无 `circuit.csv` | 0 | — |
| `N25_L040_cu_closed` | `StrandedCoil` | 闭路，25 匝铜 | 25 | 5.96e7 S/m |
| `N25_L040_al_closed` | `StrandedCoil` | 闭路，25 匝铝 | 25 | 3.50e7 S/m |
| `N50_L040_cu_closed` | `StrandedCoil` | 闭路，50 匝铜 | 50 | 5.96e7 S/m |
| `N50_L040_al_closed` | `StrandedCoil` | 闭路，50 匝铝 | 50 | 3.50e7 S/m |
| `N100_L040_cu_closed` | `StrandedCoil` | 闭路，100 匝铜 | 100 | 5.96e7 S/m |
| `N100_L040_al_closed` | `StrandedCoil` | 闭路，100 匝铝 | 100 | 3.50e7 S/m |

**`N_turns > 0` 就是"闭路"的判据**——`make_sif.py` 不再有 `--circuit` 开关，
导体曲线一律走闭路。`empty` 走模板原样，与闭路机制完全无关。

### 物理（FEM 真解，Elmer 26.2 瞬态 + 电路耦合）

```
magnetisation      : M = 1.2e6 A/m    (N52 NdFeB approximation)
permeability       : mu_r = 1.05      (linear B-H)
equation           : sigma dA/dt + curl(1/mu * curl(A)) = J_source
                     + Whitney AV edge-element basis（线性四面体）
电路                : CircuitsAndDynamics（stranded coil Component）
                     R_load = 10 Ω 与线圈串联成闭路
wire direction      : w = -grad(W)，WPotentialSolver 解 W，
                      slit 两个面 W=1 / W=0 定出绕线方向
线圈电导率           : sigma_eff = f * sigma_wire（填充因子！见 §11.2）
运动                : RigidMeshMapper + Mesh Translate 3 = MATC 表达式
                     （阻尼谐振子解析解，T = 0.2995 s）
输出                : results/circuit.csv（每步 i/v/r/p）
                     results/case_t*.vtu（场量）
```

> **几何维度速查（线径 = 线圈直径）**
>
> | 量 | 值 | 备注 |
> |---|---|---|
> | 磁体 | **Φ30 × 30 mm** | NdFeB |
> | 线圈骨架 | **Φ40 内 / Φ50 外 × 40 mm 长** | 5 mm 壁 |
> | 径向缝 | **3.5 mm** | 数学工具，让 W 势有终端 |
> | 漆包线径 | **Φ0.7 mm**（≈AWG 21）| 100 匝填充 77 % |
> | 单匝长度 | **14.1 cm** | 2π · 22.5 mm |
> | 远场 | Φ160 × 190 mm | A=0 边界 |
>
> 完整几何与导出量见 **§6.0**。

---

## 2. PIP 安装

```powershell
pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
```

| 包 | 用途 |
|---|---|
| `gmsh>=4.13,<5.0` | 三维网格生成 |
| `meshio>=5.3,<6.0` | .vtu / .msh 读写 |
| `pyvista>=0.43,<1.0` | headless 3D 渲染（test_outputs/mesh_preview.png） |

> **为什么 pip 装 gmsh？** 官方 binary 下载 `https://gmsh.info/bin/Windows/...`
> 在中国网络下经常 0x80072efd 失败。pip 安装是预编译 wheel（~60 MB），
> 一步到位。

**多 Python 解释器共存**：项目使用
`C:\Users\JosephVStalin\AppData\Local\Programs\Python\Python311\python.exe`。
若你机器上也是这个解释器，直接 `pip install`；否则手动指定：

```powershell
& "C:\Users\JosephVStalin\AppData\Local\Programs\Python\Python311\python.exe" -m pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
```

---

## 3. 文件清单

| 文件 | 大小 | 说明 |
|---|---|---|
| `solenoid3d.py` | 19 KB | 几何生成（gmsh Python API），7 曲线 + 径向 slit + 缝分辨率守卫 |
| `make_sif.py` | 55 KB | SIF 生成器：填充因子、方向栈、组件、导出链、Active Solvers |
| `case_transient.sif` | 10 KB | Elmer 26.2 瞬态模板（900 步 / 1 ms） |
| `spring_model.py` | 6 KB | 阻尼谐振子解析解（MATC 表达式的来源） |
| `config.json` | 14 KB | **单一真相源**（物理、几何、网格、7 曲线） |
| `oscilloscope.py` | 35 KB | 后验交叉校验 + 全部绘图（见 §6.5） |
| `visualize_freecad_macro.py` | 7 KB | FreeCAD 时序动画（带 Qt slider） |
| `run_tests.ps1` | 5 KB | 端到端测试（4 步骤） |
| `clean.ps1` | 2 KB | 清理所有中间产物 |
| `tests/test_sif_circuit.py` | — | **38 项**：SIF 结构、W 求解器、填充因子、导出链、缝守卫、基线不变性 |
| `tests/test_sif_solver.py` | — | 13 项：求解器选择 |
| `tests/test_spring_model.py` | — | 21 项：弹簧解析解 |
| `tests/test_mesh.py` | — | pytest：网格完整性（需 meshio） |
| `tests/test_render.py` | — | pytest：pyvista 渲染（需 meshio） |
| `Dockerfile` | — | `pysproject:3.5.0`（gmsh + Elmer 26.2.1 + Python 依赖） |
| `hpc/` | — | HPC 脚本 + `notes.md` 英文原始日志 + `results/` 拉回的数据 |

---

## 4. 运行流水线

### 一键测试（推荐先跑这个）

```powershell
cd c:\Users\JosephVStalin\Desktop\PysProject
.\run_tests.ps1                       # 默认几何 (no-coil) 全流程
.\run_tests.ps1 -Config stranded-coil # 带绕组的几何
.\run_tests.ps1 -All                  # config.json 里所有 sif_suffix 都跑一遍
.\run_tests.ps1 -NoSolve              # 跳过求解，只重画图（秒级）
```

`-NoSolve` 是改完 `config.json` 后重新出图用的：完整瞬态求解约 **20 分钟**
（150 步 × 约 8 s/步），只做后处理只要几秒。

> 线圈几何只有 **两个** 变体（`no-coil` / `stranded-coil`）。磁体运动是被
> **预设**的，材料与电路参数（`N_turns`、导线材料、`R_load`）全部作为
> **后处理**进入计算 —— 所以 `-Config` 选的是网格，而 `config.json` 里
> **每一个** `[curves]` 都会同时出现在示波器的“线圈通过时间”与
> “感应电流”面板里，**不需要为每个配置重跑 Elmer**。

### 流水线步骤 (5 步)

| # | 动作 | 输出 |
|---|---|---|
| 1 | `python solenoid3d.py --config <cfg>` | `model3d.msh` (~1.4 MB) |
| 2 | `ElmerGrid 14 2 model3d.msh -out mesh -autoclean` | `mesh/` (~5 MB) |
| 3 | `ElmerSolver case_transient.sif` | `results/case_t0001..0150.vtu` |
| 4 | `test_mesh.py` + `test_render.py` | `test_outputs/mesh_preview.png` |
| 5 | `oscilloscope.py` + `verify_fall.py` | `results/scope.{png,txt,json}` |

清理产物：

```powershell
.\clean.ps1
```


---

## 5. Elmer 26.2 安装（项目内打包，Docker-ready）

Elmer 26.2（2026-08-25）编译版**直接放在 `./elmer262/`**，体积 ~250 MB。
本项目不再依赖系统级 Elmer 安装。脚本 `run_tests.ps1` 启动时
的搜索顺序为：

```powershell
(Join-Path $PSScriptRoot 'elmer262')    # 项目内  <-  首选
D:\Program Files\Elmer 26.1-Release     # 兼容旧版
C:\Program Files\Elmer 26.1-Release
... (env 变量 / PATH 中的 ElmerSolver.exe)
```

如需在其他机器上重新编译：

```bash
# 1. 安装 MSYS2 (https://www.msys2.org/)
pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-gfortran \
              mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja

# 2. 复用 26.1 自带的 libopenblas.dll 作为 BLAS 依赖
git clone --depth 1 -b release-26.2.1 https://github.com/CSC-IT-Center-for-Science/elmerfem.git
cd elmerfem
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DWITH_MPI=OFF
cmake --build build -j

# 3. 复制到本项目
cp -r build/install/* /c/Users/JosephVStalin/Desktop/PysProject/elmer262/
```

**为何不用 Elmer 26.1 的 DLL？** 26.2 将主 procedure 改名为
`WhitneyAVSolver`（26.1 是 `MagnetoDynamics`），并删除了 `InitialCondition`
关键字注册。直接复用 26.1 会出现 `Can't find procedure` 报错。

### 5.1 Docker 镜像（推荐用于 Linux / HPC / 交付）

```bash
docker compose build            # 首次约 20–35 分钟（其中大部分是编译 Elmer）
docker compose run --rm fem     # 跑完整 5 步流水线
docker compose down
```

镜像内 Elmer 落在 `/opt/elmer`，**由 Dockerfile 第 1 阶段自行编译**，
不依赖任何系统级 Elmer。编译选项逐条照抄 `elmer262/CMakeCache.txt`
（`WITH_UMFPACK=TRUE`，其余全 `FALSE`），因此容器数值与宿主机一致 ——
实测 3 步冒烟运行的弹簧轨迹误差为 **0.0000 % 幅度**。

**离线交付：** 镜像已导出为单文件包，目标机器无需联网重建：

```bash
docker load -i pysproject-3.5.0.tar     # 611.9 MB，往返验证过
docker compose up
```

镜像内已装好 `gmsh 4.15.2 / meshio 5.3.5 / numpy 2.4.6 / pyvista 0.49.0 /
vtk 9.7.0 / matplotlib 3.11.2`，以及 Elmer 运行所需的完整 `.so` 依赖
（含 `libquadmath0`、`libxft2`、软件 GL 等 —— 缺任何一个都会在
`import gmsh` 或启动 `ElmerSolver` 时就地报错）。

### 5.2 线性求解器：UMFPACK 与 Hypre AMS

Solver 2（`WhitneyAVSolver`，棱边元）是整个算例的开销所在，它的后端由
`make_sif.py --solver` 选择：

```bash
python make_sif.py                     # 默认：Direct / UMFPACK
python make_sif.py --solver hypre-ams  # 迭代：BiCGStab + Hypre AMS
```

| | `umfpack`（默认） | `hypre-ams` |
|---|---|---|
| 类型 | 直接稀疏 LU | 迭代 Krylov + AMG |
| 内存 | ~O(n²)，**~10 万棱边处崩** | ~O(n) |
| 需要 | 无（模板自带） | Elmer 需带 `-DWITH_Hypre=TRUE` |

**为什么会有这个选项。** UMFPACK 在约 10 万棱边处会以
`Error occurred in umf4num: -1.0000000000000000` 失败，加内存无效
（110 GB 照样失败）—— 这是直接解法 O(n²) 内存增长的必然结果。

**为什么不是"换个预条件子就行"那么简单。** 早先的笔记断言 Elmer 不提供
棱边元所需的 curl 共形预条件子。**这是错的**：BiCGStab + ILU 发散是
**ILU 的性质**（ILU 面向 H¹/节点问题，对 H(curl) 本就不适用），而 Elmer
一直有 **Hypre AMS**（Auxiliary-space Maxwell Solver，实现于
`fem/src/SolveHypre.c`）。它此前不可用仅仅因为 `WITH_Hypre` 默认 `FALSE`，
整条代码路径被编译掉了。

SIF 关键字**逐条取自上游测试算例 `fem/tests/mgdyn_hypre_ams`**：

```elmer
linear system use hypre          = Logical True
Linear System Solver             = Iterative
Linear System Preconditioning    = AMS
Linear System Method Hypre Index = Integer 7   ! 7 = BiCGStab
```

**不需要 GPU。** 对应构建：`bash hpc/build_elmer.sh hypre`。


---

## 6. 几何、材料、电路

### 6.0 几何尺寸总览（实物 = 第一性原理 + 典型值）

| 几何量 | config key | 默认值 | 单位 | 物理含义 |
|---|---|---|---|---|
| 磁体半径 | `magnet.R_mag_m` | 0.015 | m | Φ30 mm × 30 mm N52 NdFeB 圆柱（剩磁 ≈ 1.27 T，对应 `M=1.2e6 A/m`）|
| 磁体高度 | `magnet.z1_m − z0_m` | 0.030 | m | 圆柱全高（H_mag 是半高 15 mm）|
| 磁体网格位置 | `magnet.z0_m` | 0.030 | m | 弹簧**释放**高度，所以初始位移为 0 |
| **线圈内径** | `coil.r_inner_m` | **0.020** | m | **Φ40 mm 内径，磁体穿过这里** |
| **线圈外径** | `coil.r_outer_m` | **0.025** | m | **Φ50 mm 外径，5 mm 壁厚** |
| **线圈长度** | `coil.z1_m − z0_m` | **0.040** | m | **40 mm 沿轴，已交叉校验** |
| **径向缝宽** | `coil.slit_width_m` | **0.0035** | m | **3.5 mm，仅让 W 势有终端，不是物理气隙** |
| 空气域半径 | `geometry.R_air_m` | 0.080 | m | 远场 Φ160 mm，A=0 边界 |
| 空气域高度 | `air_z0_m / air_z1_m` | −0.080 / +0.110 | m | 远场 190 mm 高度 |
| **线径** | `curves.*.wire_diameter_m` | **0.0007** | m | **Φ0.7 mm 漆包线（≈AWG 21），40 mm 窗口里塞得下** |
| **铜电阻率** | `wire_conductivity_S_per_m` | **5.96e7** | S/m | **100% IACS 纯铜** |
| **铝电阻率** | `wire_conductivity_S_per_m` | **3.50e7** | S/m | **6061-T6 退火铝**（~61% IACS）|

**3 个线径/直径导出量**（用于质量检查）：

```
线圈中线半径:   r_mean_m   = (r_inner + r_outer) / 2  = 0.0225 m   (Φ45 mm)
单匝线长:      L_turn_m   = 2π · r_mean              = 0.1414 m    (14.1 cm)
N 匝总长:      L_wire_m   = N · L_turn               = N · 0.1414  m
单匝截面积:    A_wire_m2  = π · d² / 4               = 3.85e-7 m²  (Φ0.7 mm)
线径利用率:    η_pack     = N · A_wire / V_coil       = N · 0.77    (N=100 时 77% 填充)
```

> **「线径计入」** 后，上述几何完全决定了：
> 1. **R_wire**：单匝电阻 `r = L_turn / (σ·A_wire)`，N 匝串联：`R_wire = N²·2π·r_mean / (σ·π·d²/4)` — 与 `make_sif.py` 一致
> 2. **填充率**：N=25 时 19%（单层略欠），N=50 时 38%（一层半），N=100 时 77%（挤满）
> 3. **线圈阻抗** L_model = `μ₀ · N² · A_coil / l_coil` ≈ `μ₀ · 100² · π·0.0225²/0.04` ≈ 4e-3 H（N=100），与 §13 根因分析吻合
>
> 这三个量都是**几何直接定死的**，没有拟合参数。

体编号（在 `case_simple.sif` 和 gmsh `Physical Volume` 中保持一致）：

| 编号 | 名称 | 角色 |
|---|---|---|
| 1 | `AirInside` / `StrandedCoil` | 线圈等效块体（依 config 变空气/线圈） |
| 2 | `Magnet` | 永磁体（M=1.2e6 A/m，r=15 mm，h=30 mm） |
| 3 | `AirDomain` | 周围空气（R=80 mm，z=[-80, +110] mm） |
| 1001 | `MagneticInfinity` | 空气外侧表面（磁无穷远 BC：A=0） |

`case_simple.sif` 使用 Elmer 26.2 的 `WhitneyAVSolver`：

```
Procedure = "MagnetoDynamics" "WhitneyAVSolver"
Solver 1 : 收敛静磁 (AV 分量)
Solver 2 : ResultOutput -> case_t0000.vtu, case_t0001.vtu, ...
Body Force 1 : Current Density 3 = 5.0e6   (驱动源)
```

电路配置（`circuit.definitions` / `circuit_open.definitions`）是为后续扩展（rigid-body
mesh-update + circuit coupling）准备的电路模板；当前静磁 SIF 暂未引用。

> **注意（后续变更）**：上面的静磁示例与它引用的模板描述的是早期设计。
> 现在新增的闭路变体不再用 `circuit.definitions` 模板文件，而是由
> `make_sif.py` 为每条曲线即时生成 `circuits.definitions`（MNA 矩阵）+
> `Component 1/2` + `WPotentialSolver` / `CircuitsAndDynamics` /
> `CircuitsOutput` 求解器。详见 `hpc/notes.md` §13。

---

### 6.1 两种运动模式：弹簧 / 自由落体

运动律由 `config.json → experiment.motion_mode` 切换，**SIF 由 config 生成**，
不需要手改：

```powershell
python make_sif.py --show     # 只看会生成什么
python make_sif.py            # 写入 case_transient.sif
```

| `motion_mode` | 运动律 | MATC 表达式 |
|---|---|---|
| `"spring"`（当前） | 阻尼谐振子 | 由 `[spring]` 推导，见下 |
| `"free_fall"` | `z = z0 − ½ g t²` | `-0.5*9.81*tx*tx` |

#### 弹簧-质量-阻尼（`config.json → [spring]`）

磁体挂在弹簧下端，弹簧上端焊在**锚板**（clamped）上：

$$m z'' = -mg - k(L - L_0) - c z' - F_{lenz},\qquad L(z) = z_{anchor} - \left(z + \tfrac{H}{2}\right)$$

无楞次力时就是标准阻尼谐振子：

$$z(t) = z_{eq} + A e^{-\gamma t}\left[\cos(\omega_d t) + \frac{\gamma}{\omega_d}\sin(\omega_d t)\right]$$

$$\omega_0=\sqrt{k/m},\quad \gamma=\frac{c}{2m},\quad \omega_d=\sqrt{\omega_0^2-\gamma^2},\quad z_{eq}=z_{anchor}-\frac{H}{2}-L_0-\frac{mg}{k}$$

**当前默认值**（`spring_model.py` 自动推导，跑 `python spring_model.py` 可看）：

| 量 | 值 | 量 | 值 |
|---|---|---|---|
| `mass_kg` | 0.5 | 周期 T | **0.2995 s** (3.34 Hz) |
| `stiffness_N_per_m` | 220 | `omega0` | 20.976 rad/s |
| `damping_N_s_per_m` | 0.8 | Q | 13.1 |
| `z_eq_m` | 0.020（线圈中心） | 静伸长 `mg/k` | 22.3 mm |
| `z_release_m` | 0.045 | `L_eq` / `L0` | 64.0 / 41.7 mm |
| 幅度 A | 25 mm | 弹簧伸缩 | 0.94× … 2.13× L0 |
| 锚板 | z 0.099–0.101 | 弹簧管 | R 6–8 mm, z 0.039–0.099 |

> **弹簧不需要画进网格**：它在 R 6–8 mm 的轴线上、位于线圈内孔里，且是
> 非磁性（`mu_r = 1`），**对场没有任何影响**。所以"弹簧版本"= 同一套网格
> （线圈 + 磁体 + 空气）+ 换运动律。`[spring].include_in_mesh = false`
> 就是基于这个结论。要可视化时才设 `true`。

#### 验证

```powershell
python test_outputs\verify_spring.py
```

实测**误差 1e-12 m（皮米级）= 幅度的 0.0000 %**，网格精确跟随解析弹簧解。

### 6.1.1 释放高度、弹簧形变、几何一致性

**磁体释放位置**：`z_release_m = 0.045 m`（磁体 z 中心）→ 磁体范围 z = 30..60 mm。

**真实实验中**磁体**物理挂在弹簧下端**，弹簧上端焊锚板（`anchor_z0 = 99 mm`）。
弹簧受磁体重力后**静伸长**：

```
sag     = m·g / k = 0.5·9.81 / 220 = 0.0223 m = 22.3 mm
L_eq    = anchor_z0 − (z_eq + H_mag/2) = 99 − (20 + 15) = 64.0 mm   (平衡长度)
L_0     = L_eq − sag = 64.0 − 22.3 = 41.7 mm                          (自然长度)
```

**几何一致性检查**（当前默认 config）：

| 量 | 值 | 与真实物理的关系 |
|---|---|---|
| `spring_z1` (上端) | 99.0 mm | = `anchor_z0` ✓ |
| `spring_z0` (下端) | 39.0 mm | **不等于** L_eq 末端 35 mm（应=35 mm 才能接触磁体）|
| mesh弹簧长度 | **60.0 mm** | **既非 L_0 = 41.7 mm 也非 L_eq = 64.0 mm** —— 是占位几何 |
| 在 z_eq 时磁体顶 vs 弹簧底 | 35 vs 39 mm | **空气间隙 +4 mm** |
| 在 z_release 时磁体顶 vs 弹簧底 | 60 vs 39 mm | **磁体在弹簧上方 21 mm**（不接触）|
| 整个仿真过程中弹簧 | **不变形**（长度恒 60 mm）| **弹簧 mesh 是个纯占位**，没有承载磁体 |

**重要诚实声明**：

> **本 FEM 的"弹簧"其实是「位移剧本」**，不是真的弹簧力。
> SIF 的 `Mesh Translate 3 = MATC expr` 把磁体 mesh 节点**直接平移**到解析解
> `z(t) = z_eq + A·exp(-γt)·[cos(ω_d t) + (γ/ω_d)·sin(ω_d t)]`。
> 网格里**没有 Hooke 力 -k·Δx 作用在磁体上**，**没有 -c·v 阻尼力**，
> **没有 -mg 重力**，**没有 Lenz 力反馈**。
> 换言之：**磁体的运动是"按剧本演出"**，不是「弹性动力学求解」。
>
> 这是 Elmer 的常见简化：用 MATC/RigidMeshMapper 强制位移，绕过
> spring-mass-damping 耦合的隐式时间积分。
>
> **实际意义**：
> 1. 给定的 (k, c, m, z_eq, z_release) 必须**严格与真弹簧匹配**，否则仿真误差
>    是"剧本误差"而不是"FEM 求解误差"。
> 2. Lenz 制动力（F_lenz = i·ε/v）虽然在电路里存在，但**不会**反馈到 z(t) 的
>    阻尼谐振子公式里——z(t) 与电流 i(t) 是**单向耦合**（磁体位置产生 EMF，
>    但 i(t) 不能让磁体减速）。
> 3. `r_component(1)`（线圈电阻）和 `L_model`（线圈电感）的「EMF 项」
>    只是 Elmer `CircuitsAndDynamics` 内部的标量簿记值，与磁体轨迹无关。

**改进版本（§6.1.2）见下**：把 `spring_z0/s1` 改成物理一致的自然长度，**让弹簧真正承载磁体**。

> ⚠️ **帧时间约定**：`case_t0001.vtu … case_tNNNN.vtu` 对应
> `t = 1·dt … N·dt`，即**帧 k（0 基）在 `t = (k+1)·dt`**。用错会得到
> `err = -v·dt`，看起来正好像滞后一个时间步 —— 这个坑我在两种模式下都踩过。


---

## 7. 文档导航

| 文档 | 说明 |
|---|---|
| `README.md` | **本文档 —— 唯一权威中文文档**（已合并 `hpc/notes.md` §1–15、`hpc/HANDOFF.md`、`hpc/DISPATCH.md`） |
| `hpc/notes.md` | 英文原始工程日志。源码注释引用它的 §15.x，**保留作为可追溯的原始记录** |
| `CHANGELOG.md` | 版本变更历史 |
| `TROUBLESHOOTING.md` | 常见问题排查 |
| `docs/ARCHITECTURE.md` | 内部架构图（FEM data flow） |

**本 README 的核心章节：**

| 章节 | 内容 |
|---|---|
| §11 | 闭路 FEM 的六个关键机制（执行顺序、填充因子、导出链） |
| §12 | 生产成本 + 网格稳定性门槛（已解决） |
| **§13** | **根因：电感大了 3.7×10⁶ 倍 —— 当前阻塞** |
| §14 | HPC 派发记录、结果、踩过的坑 |
| §15 | 调试工具脚本清单 |

---

## 8. FEM 测试

`run_tests.ps1` 跑通后，第 4 步会执行 `tests/` 下的两个 pytest 文件：

### 8.1 `tests/test_mesh.py`

打开 `mesh/mesh.elements` / `mesh.nodes` / `mesh.header`，验证：

- 体数量符合预期（3 个 Physical Volume）
- `Magnet` 体只含 r<16 mm 的 tet 单元
- `StrandedCoil` 体只含 20 < r < 25 mm 的 tet 单元
- `AirDomain` 体 r<80 mm，z in [-80, +110] mm
- 每个 `mesh.header` 第一行报告 `knots / elements` 数字

输出 `test_outputs/fem_test_stats.json` 和 `test_outputs/mesh_preview.png`。

### 8.2 `tests/test_render.py`

用 pyvista headless 渲染 3 个体为 PNG：

- 蓝色 air 透明（80%）
- 橙色 coil 半透明（55%）
- 红色 magnet 不透明

输出 `test_outputs/mesh_preview.png`。

### 8.3 `oscilloscope.py` — 把 FEM 结果全部画出来

```powershell
python oscilloscope.py            # 默认写 results/scope.{png,txt,json}
python oscilloscope.py --t-end 0.10   # 只看前 0.10 s
```

它**不读解析模型**，而是直接读 `results/case_t*.vtu`（Elmer 的真实解），
逐帧提取场量并画成 12 个面板：

| 面板 | 物理量 | 来源 |
|---|---|---|
| `z(t)` | 磁体位移（跟随动网格追踪） | VTU 节点坐标 |
| `v(t)` / `a(t)` | 数值 `dz/dt` / `d²z/dt²`（叠加 `-g` 参考线） | 位移差分 |
| `B_z(t)` | 线圈环形截面上的平均轴向磁通密度 | VTU 的 `magnetic flux density` |
| `\|B\|max(t)` | 全域峰值场强 | VTU |
| `Phi(t)` | 磁链 `N·⟨B_z⟩·A_coil` | 由 `B_z` 积分 |
| `EMF(t)` | `-N dPhi/dt`（法拉第） | 磁链差分 |
| `I(t)` | `EMF / R_total`，`R_total = R_load + R_wire` | `config.json` |
| `KE(t)` / `PE(t)` / `E_tot(t)` | 机械能收支（`PE` 从释放点量起） | 位移 |
| `⟨meshrelax⟩(t)` | 磁体上的网格松弛场（=1.0 表示刚性跟随） | VTU 的 `meshrelax` |

**8.4 线圈通过时间（各配置）** — 底部右侧甘特面板

```
   config                              N    R_tot   head-in   tail-in  head-out  tail-out  尾部进入→头部离开   完整穿越
                                           ohm        ms        ms        ms        ms        ms       ms
   空 (无导体)                          0      inf     64.12    101.14    110.76    135.60      9.62   71.48
   铜线闭路 (Cu 50t 0.7mm, R=10Ω)      50    10.31     64.12    101.14    110.76    135.60      9.62   71.48
   铝线闭路 (Al 50t 0.7mm, R=10Ω)      50    10.53     64.12    101.14    110.76    135.60      9.62   71.48
   铝线开路 (Al 50t 0.7mm, R=∞)        50      inf     64.12    101.14    110.76    135.60      9.62   71.48
```

四个配置（见 `config.json` → `[curves]`）的对照设计：

| 配置 | 导线 | σ (S/m) | R_wire | R_load | R_total | 电路 |
|---|---|---|---|---|---|---|
| `empty` | — | — | — | ∞ | ∞ | 无导体参考 |
| `copper_closed` | 铜 | 5.96e7 | 0.310 Ω | 10 Ω | **10.31 Ω** | 闭路 |
| `aluminum_closed` | 铝 | 3.50e7 | 0.527 Ω | 10 Ω | **10.53 Ω** | 闭路 |
| `aluminum_open` | 铝 | 3.50e7 | 0.527 Ω | ∞ | **∞** | 开路 |

- **铜线闭路 vs 铝线闭路** 只差导线材料：`R_wire` 相差 1.70 倍
  （= σ_Cu / σ_Al），但相对 10 Ω 负载只让总电阻变化 2 %。
- **铝线闭路 vs 铝线开路** 只差电路状态：开路时 `EMF` 依然出现在
  线圈两端，但 `I = 0`，因此**完全没有楞次制动**。

- **头部 = 磁体下端面**（先进入线圈的一侧），**尾部 = 上端面**。
- 深色条 = 你要的区间 **`尾部进入 → 头部离开`**，物理含义是
  **磁体完全位于线圈内部的那段时间**（磁体 30 mm、线圈 40 mm，
  可整段包含的行程只有 10 mm，自由落体 9.62 ms ✓）。
- 浅色底衬 = 完整穿越 `head-in → tail-out`（磁体与线圈有重叠的全部时间）。
- 数据链：FEM 给出 `phi(z) = ⟨B_z⟩(z)·A_coil` → 对每个 `[curves]` 配置
  积分制动方程

  ```
  m z'' = -m g - c(z) z' ,      c(z) = (N² / R_total) · (dphi/dz)²
  ```

  （楞次制动，单位 N·s/m；`N = 0` 或 `R = ∞` 退化为自由落体）

- 四个时刻与自由落体的解析值**完全一致**（64.12 / 101.14 / 110.76 /
  135.60 ms），说明时间轴是对的。
- 结果同时写进 `results/scope.txt` 的表格和 `results/scope.json`
  的 `coil_transit` 数组。

> **重要结论**：当前几何下 `c_peak = 4.64e-07 N·s/m`，在 v ≈ 1.08 m/s 时
> `F_lenz / (m g) = 1.0e-05 %` —— **电磁制动完全可以忽略**。这正是可以把
> 运动直接规定为自由落体（`Mesh Translate`）而不做流固耦合建模的依据。
> 另外线圈 `L/R = 7.2 µs`，远小于 65 ms 的穿越时间，所以 `I = EMF / R`
> 的准静态假设也成立。
>
> 想看到明显的制动效果要非常大的安匝数：`N ≈ 5000, R = 0.5 Ω` 才有
> 2 %（9.68 ms），`N ≈ 20000, R = 1 Ω` 才到 17 %（9.96 ms）。根本原因是
> 磁体（R=15 mm）从线圈**内孔**（R_in=20 mm）穿过，绕组只链到边缘磁通，
> `phi_max/N = 1.52e-06 Wb/turn` 太小。


### 8.5 超算（HPC）工作流

算例变大后本机跑不动时，可以切到 `cancon.hpccube.com`。完整踩坑记录见
**`hpc/notes.md`**；这里只给用法。

```powershell
# 1) 建算例（本机 gmsh，秒级）
python hpc\make_case.py --length 0.040 --level fine            # 线圈 40 mm，细网格
python hpc\make_case.py --length 0.040 --level fine --rin 0.017  # 小内孔对照

# 2) 判断该在哪台机器跑 —— 这是必须做的一步
python hpc\should_run_locally.py hpc\cases
```

```
case                  edges      frames  laptop      HPC     -> runner
L020_ri020_coarse     73,935      56      0.6 h      1.2 h   -> local
L020_ri020_fine       98,494      56      4.7 h      6.3 h   -> local
L040_ri020_fine      128,890      66      9.5 h     12.7 h   -> local
L160_ri020_fine      250,269     126     68.5 h     91.3 h   -> change-solver
```

```powershell
# 3) 上传 + 提交（仅在 runner = HPC 时）
.\hpc\sync.ps1 -Upload
ssh -p 65023 -i ~\.ssh\cancon_key josephvstalin@cancon.hpccube.com `
    "cd ~/pysproject && bash submit_plan.sh"

# 4) 取回结果
.\hpc\pull.ps1                 # 全部
.\hpc\pull.ps1 -Only L020      # 只取匹配的
```

**判据说明**：笔记本单核比超算那块 Hygon 节点**快约 1.8 倍**，而且本机的
mingw64 gfortran 13 **没有** 超算那套 UMFPACK 的 ABI bug。所以默认在本机跑；
只有"本机超过一晚（48 h）"**且**超算能解时，才送到超算。

> ⚠️ **超算上的硬限制**：那套 Elmer 26.2 + UMFPACK 在 **约 100 000 条棱边
> （edge DOF）以上必定在第 0 步崩溃**：
>
> ```
>  Error occurred in umf4num:   -1.0000000000000000
> ```
>
> 这**不是内存不够** —— 作业峰值只占 2.7 GB，申请 110 GB 也一样崩。是
> gfortran 7.3.1 与 UMFPACK 的 C 接口在
> `/usr/lib64/liblapack.so.3.4.2` 这个 shim 上的 ABI 不匹配。已验证：
> 换 OpenMP 重编无用、迭代法（BiCGStabL+ILU1）直接发散、加内存无用、
> 同几何换粗网格也一样崩。**唯一真解法是改用 Pardiso 或 Hypre 重编。**

**时间窗口切分的合法性**：模型里所有 body 的 `Electric Conductivity` 都 ≈ 0
（线圈 0.0，空气/磁体 1e-12），所以瞬态 A 形式的 `σ∂A/∂t` 项恒为零，
**每一步都是独立的一次静磁求解**，时间轴可以任意切给不同 job。
`run_window.slurm` 就是靠这一点把长算例拆成多个并行作业。


---

## 9. FreeCAD 可视化解算全过程

本节说明**如何在 FreeCAD 里完整地看到磁体从释放 -> 通过线圈 -> 落到地面的全过程**。
三种入口覆盖三种场景：

| 入口文件 | 何时用 | 依赖 |
|---|---|---|
| `geom_preview.FCMacro` | 只想看 3 个体 (空气域 / 线圈 / 磁体) 的几何形状 | 仅 FreeCAD |
| `results_viewer.FCMacro` | 跑完 `run_tests.ps1` 后看 **真实 FEM 解算结果** 的时序动画 | FreeCAD + ElmerSolver 结果 |
| `visualize_freecad_macro.py` | 同上，但带可拖动的 Qt 时间滑块 | FreeCAD + meshio + ElmerSolver |

> **前置条件**：Windows 上安装 [FreeCAD 1.1.x](https://www.freecad.org/downloads.php)，
> 并且 `.FCMacro` 后缀关联到 FreeCAD（双击即可运行）。

---

### 9.1 几何预览（不依赖 FEM 结果，5 秒出图）

这是最快、最轻量的可视化方式 —— **不需要任何 .msh / .vtu 文件**，
宏里直接用 FreeCAD Python API 重建三个体。

**步骤**：

1. 在文件资源管理器里 **双击 `geom_preview.FCMacro`**
2 -> FreeCAD 自动打开并执行
2. 或：启动 FreeCAD -> 菜单 Macro -> Macros... -> User macros -> 选 `geom_preview.FCMacro` -> Execute
3. 等 < 5 秒，模型树里出现 3 个对象：

| 对象 | 几何 | 颜色 / 透明度 |
|---|---|---|
| `AirDomain` | R=80 mm 高 170 mm 大圆柱，z=[-50, +120] mm | 浅蓝 88% 透明 |
| `CoilBlock` | R_out=25 mm / R_in=20 mm 高 40 mm 中空筒，z=[-20, +20] mm | 橙 55% 透明 |
| `Magnet` | R=15 mm 高 30 mm 实心圆柱，z=[+60, +90] mm | 红 0% 透明 |

4. 自动保存 `geom_preview.step` 到项目根目录

**验证**：窗口是透视视图 (viewIsometric)，相机自动 `ViewFit` 到模型范围。

---

### 9.2 时序动画（依赖 ElmerSolver 真实结果）

`run_tests.ps1` 跑通后，`results/` 下会有一堆
`case_t0000.vtu` / `case_t0001.vtu` / ... 的时间步文件。
这些是 Elmer 26.2 在每个时间步的 **真实 B 场解**（矢量磁位 AV 分量）。

#### 9.2.1 方式 A — 双击 `.FCMacro`（推荐，最简单）

1. 确认 `results/case_t*.vtu` 存在（跑过一次 `run_tests.ps1` 即可）
2. 双击 `results_viewer.FCMacro`
3. FreeCAD 打开：
   - 加载 `model3d.msh` -> `GeometryMesh`（灰色线框整体几何）
   - 顺序加载 `case_t*.vtu` -> `frame_0000` / `frame_0001` / ...
   - 启动 Qt 定时器，每 100 ms 切换一帧可见性 -> **磁体下落动画**
4. 窗口右上角弹出任务面板：
   - **拖动 slider** 跳到任意时间步
   - **Pause / Play 按钮** 暂停或恢复自动播放

> **滑动窗口机制**（macro 内部）：FreeCAD 不可能把 220 个时间步同时放内存，
> 宏只保留前后 6 帧（约当前时刻 +-3）可见，其余 `Visibility = False`。
> 用户拖 slider 时自动加载新窗口。

#### 9.2.2 方式 B — 拷到 FreeCAD Macro 编辑器

1. 启动 FreeCAD
2. Macro -> Macros... -> Create -> 粘贴 `visualize_freecad_macro.py` 内容 -> Save
3. Macro -> Execute

**两个版本的区别**：
- `.FCmacro` 关联到文件类型，可直接双击
- `.py` 版本可读性更好，方便自定义（改 `WINDOW_SIZE`、`FRAME_DT` 等参数）

---

### 9.3 三种可视化路径对比

```
                                +--------------------------+
                                |      几何参数 (config)    |
                                |  z_release_m, N_turns,   |
                                |  wire_diameter_m, ...    |
                                +---------+----------------+
                                          |
            +-----------------------------+-----------------------------+
            |                             |                             |
            v                             v                             v
   solenoid3d.py                  config.json                  geom_preview.FCMacro
   (gmsh geometry)                  (curve blocks)              (FreeCAD direct build)
            |                             |                             |
            v                             v                             v
       model3d.msh                   ElmerSolver 26.2            geom_preview.step
            |                             |                             |
            v                             v                             v
    ElmerGrid 14 2                results/case_t*.vtu            FreeCAD Part view
            |                             |                                 ^
            v                             v                                 |
    ElmerSolver 26.2               results_viewer.FCMacro  -------------------+
   (WhitneyAVSolver)                  (time animation + slider)
```

**三种入口覆盖三种角色**：

- **几何改完想看一眼** -> `geom_preview.FCMacro` (5 秒，不跑 FEM)
- **FEM 跑完想看动画** -> `results_viewer.FCMacro` (双击即播)


---

### 9.4 故障速查

| 现象 | 原因 | 解决 |
|---|---|---|
| 双击 `.FCMacro` 没反应 | 文件关联没设 | 右键 -> 打开方式 -> FreeCAD |
| `Mesh.Mesh(vtu)` 失败 | FreeCAD < 0.19 无 meshio 桥 | 升级 FreeCAD >= 0.20；或运行 `pip install meshio` 后重启 FreeCAD |
| `from PySide2 import QtCore` 失败 | FreeCAD 0.18 用 PySide1 | 宏已 try/except 兼容，老版本无 Qt 时退化为手动拖 Visibility |
| 视图全黑 | 相机方向不对 | View -> Standard Views -> Isometric，或 `ViewFit` |
| 动画只播一次就停 | `n_frames == 0` | `results/` 里没 VTU，先跑 `run_tests.ps1` |
| 想保留单帧截图 | `frame_NNNN` 右键 -> Visibility 切换 -> 导出 STL | 用 FreeCAD -> File -> Export |
| 想看场量（不是点云） | 当前宏只画点 | 在 macro 里改 `DisplayMode = "Flat Lines"` 或 `"Surface"` |

---

### 9.5 输出物清单（按体积从小到大）

| 文件 | 用途 | 大小 |
|---|---|---|
| `geom_preview.step` | 几何预览导出的 STEP 文件 | < 100 KB |
| `test_outputs/mesh_preview.png` | pyvista headless 渲染 | ~40 KB |
| `results/case_t*.vtu` | Elmer 真实解算结果 | ~900 KB x N 帧 |

FreeCAD 文档本身不占磁盘，但 `frame_0000..frame_NNNN` 会驻留在内存
（受 `WINDOW_SIZE` 控制），220 帧典型占用 < 200 MB。


---

## 10. config.json 字段详解

`config.json` 是 `solenoid3d.py` 的输入配置入口。
所有几何、物理、网格参数都在这里定义。
**添加一条新曲线 = 在 `[curves]` 下加一个 JSON 块，不用改代码。**

### 10.1 文件结构总览

```json
{
  "experiment":  { ... },     // 全局实验元数据
  "physics":     { ... },     // 共享物理常量（G, M, C_air）


  "magnet":      { ... },     // 永磁体几何与材料
  "mesh":        { ... },     // gmsh 网格尺寸
  "geometry":    { ... },     // 空气域范围

  "curves":  {                // ---- 每条曲线一个 JSON 块 ----
    "<name>": { ... },
    "<name>": { ... },
    ...
  }
}
```

---

### 10.2 公共字段（不属于任何曲线）

#### 10.2.1 `experiment`

| 字段 | 类型 | 含义 |
|---|---|---|
| `name` | str | 实验标识符，目前固定 `"magnet_free_fall"` |
| `description` | str | 自由文本，仅供人类阅读 |
| `z_release_default_m` | float | **默认**释放高度（m）。各曲线自己的 `z_release_m` 优先 |
| `z_final_default_m` | float | 仿真结束位置（m） |
| `t_end_default_s` | float | 默认总仿真时长（s） |
| `dt_s` | float | RK4 时间步长（s） |

#### 10.2.2 `physics`

| 字段 | 类型 | 含义 |
|---|---|---|
| `G` | float | 重力加速度 9.81 m/s^2 |
| `M_kg` | float | 磁体质量 (kg)，默认 0.5 |
| `C_air` | float | 空气阻力系数 (N·s/m) |

#### 10.2.3 `magnet`

| 字段 | 类型 | 含义 |
|---|---|---|
| `M_mag_A_per_m` | float | 磁体磁化强度 (A/m)，N52 钕铁硼约 1.0-1.2e6 |
| `R_mag_m` | float | 磁体半径 (m) |
| `H_mag_m` | float | 磁体半高 (m)，**z 方向** |
| `z0_m` | float | 磁体**底面** z 坐标 (m) |
| `z1_m` | float | 磁体**顶面** z 坐标 (m) |

#### 10.2.4 `mesh`（gmsh 离散化）

| 字段 | 类型 | 含义 |
|---|---|---|
| `lc_min_m` | float | 全局最小单元尺寸 (m) |
| `lc_max_m` | float | 全局最大单元尺寸 (m) |
| `lc_coil_m` | float | **线圈体内**单元尺寸 (m)，更密 |
| `lc_others_m` | float | 磁体 + 空气域单元尺寸 (m) |

#### 10.2.5 `geometry`

| 字段 | 类型 | 含义 |
|---|---|---|
| `R_air_m` | float | 空气域半径 (m) |
| `air_z0_m` | float | 空气域底 z (m) |
| `air_z1_m` | float | 空气域顶 z (m) |

---

### 10.3 曲线块 `[curves.<name>]` — 每个名字对应一个 body geometry

每个曲线 = 一个 JSON 对象，键名即为 `--config` 选项值。
**典型命名**: `no-coil`, `stranded-coil`, `coil_high_R`, ...

| 字段 | 类型 | 必填 | 含义 |
|---|---|:-:|---|
| `label` | str | yes | 图例 / FreeCAD 物体名，例如 `"StrandedCoil"` |
| `color` | str | yes | matplotlib 颜色，例如 `"#2ca02c"` |
| `z_release_m` | float | yes | **该曲线的释放高度** (m) |
| `N_turns` | int | yes | 线圈匝数。`0` 表示无导体（无 Lenz 制动的基线曲线） |
| `wire_diameter_m` | float/null | when N>0 | 线材直径 (m)。如 0.7e-3 = 0.7 mm |
| `wire_conductivity_S_per_m` | float/null | when N>0 | 线材电导率 (S/m)。铜 = 5.96e7 |
| `R_load_ohm` | float | when N>0 | 外部负载电阻 (Ω)，进入 Elmer 的 `Component 2`。**每条有导体的曲线都必须是有限值**——开路变体已移除，`"inf"` 现在只出现在 `empty` 基线上 |
| `damping_extra_N_s_per_m` | float | yes | 附加到 C_air 的额外阻尼 (N·s/m) |
| `body_name` | str | yes | gmsh 物理体名，传给 Elmer。`"AirInside"` / `"StrandedCoil"` |
| `sif_suffix` | str | yes | `solenoid3d.py --config` 的选项值。`"no-coil"` / `"stranded-coil"` |
| `_comment` | str | no  | 自由文本，仅给编辑器/读者看的注释 |

> **注**: 1.2.0 之前 config.json 还有 `[chart]` 块（dashboard 布局），已经删除。
> 现在 oscilloscope.py 不存在，所有图表/分析都在 FreeCAD 里做。

---

### 10.4 完整示例：添加第三条 body geometry

```json
{
  "curves": {
    "no-coil":       { ... 原有 ... },
    "stranded-coil": { ... 原有 ... },

    "fine_wire": {
      "_comment": "Same 50 turns but 0.3 mm wire (thinner = higher R_wire)",
      "label": "coil-thin (50t, 0.3mm Cu)",
      "color": "#9467bd",
      "z_release_m": 0.110,
      "N_turns": 50,
      "wire_diameter_m": 3.0e-4,
      "wire_conductivity_S_per_m": 5.96e7,
      "R_load_ohm": 10.0,
      "damping_extra_N_s_per_m": 0.6,
      "body_name": "StrandedCoil",
      "sif_suffix": "stranded-coil"
    }
  }
}
```

完成后 `solenoid3d.py --config` 选项自动多 `stranded-coil` / `fine_wire`
（`body_name` 相同的多个 curve 复用同一 FEM mesh）。

---

### 10.5 单位约定

| 量 | 单位 | 说明 |
|---|---|---|
| 长度 | m | SI 主单位；FreeCAD 宏里 *1000 转 mm 显示 |
| 质量 | kg | |
| 时间 | s | |
| 力 | N | |
| 能量 | J | |
| 磁感应强度 | T | 1 T = 1 kg/(A·s²) |
| 磁化强度 | A/m | |
| 电导率 | S/m | σ = 1/ρ；铜 5.96e7；铝 3.5e7 |
| 电阻 | Ω | |
| 电压 | V | |
| 电流 | A | |


---

## 11. 闭路 FEM：六个关键机制

> 本节由 `hpc/notes.md` §15.7–15.9 合并而来。
> 这六条都是**踩过坑之后确认**的，改动它们会直接导致运行失败或结果错误。

### 11.1 Elmer 按**求解器编号**顺序执行，不是按 `Active Solvers` 列表顺序

这是本项目最难找的一个坑（`notes.md` §15.7）。

```
ElmerSolver.F90:2644   DO i=1,nSolvers ... AHEAD_ALL        （时间循环之前的前置通道）
MainUtils.F90:3014     SolveEquations(BeforeTime=.TRUE.)    （每个时间步的前置通道）
MainUtils.F90:3310     DO k=1,nSolvers ... EXEC_ALWAYS      （每步的常规通道）
```

`MainUtils.F90:3310` 是 `DO k=1,nSolvers; Solver => Model % Solvers(k)`——
**按编号遍历**。`Active Solvers` 只决定**哪些**求解器激活，不决定顺序。

`MagnetoDynamicsCalcFields` 是 Solver 3，而 1/2/3 是模板自带的，
所以电路求解器**不可能编号在 3 以下**。如果它用 `Always`，
就只能在 CalcFields **之后**才被执行——而 CalcFields 会在那个尚未创建的
NULL Lagrange 乘子上段错误。这是一个循环依赖。

**修法**：把电路对放进 `Before timestep` 前置通道（它在 Always 通道之前跑）：

```elmer
Solver 9
  Exec Solver = "Before timestep"     ! 不是 Always，这是承重的
  Equation = "Circuits"
  Procedure = "CircuitsAndDynamics" "CircuitsAndDynamics"
End
Solver 10
  Exec Solver = "Before timestep"
  Equation = "Circuits Output"
  Procedure = "CircuitsAndDynamics" "CircuitsOutput"
  Export Circuit Variables = Logical True
End
```

Solver 10 必须编号大于 9（前置通道也是按编号顺序）。

已由 `test_circuit_solvers_run_before_timestep_not_always` 和
`test_every_relaxed_solver_really_runs_within_the_timestep` 锁定。

> 顺带说明：`ElmerSolver.F90:3264` 的
> `SolveEquations(..., BeforeTime=.TRUE., ...)` 确认了
> `Before timestep` 是在**时间循环内部**、每个时间步都跑，不是只跑一次。

### 11.2 线圈电导率必须是**填充因子化**的 `f·σ_wire`（10 倍电阻 bug）

从 `CircuitsAndDynamics.F90:697` 读出的电阻公式：

```fortran
localR = Comp % N_j**2 * IP%s(t)*detJ*SUM(w*w)/localC * circ_eq_coeff / VoltageFactor
```

积出来是 `R = N_j²·V/σ = N²·L_mean/(σ·A_coil)` ——
**它把整个绕线窗口当成一根实心导体**。物理线阻是
`R_wire = N²·L_mean/(σ_wire·f·A_coil)`，其中 `f = N·A_wire/A_coil` 是填充因子。

所以必须喂给 Elmer **均匀化后的** `σ_eff = f·σ_wire`：

```
A_wire    = π(0.35 mm)² = 3.8485e-07 m²
A_coil    = 5 mm × 40 mm = 2.0e-04 m²
f         = 50 × 3.8485e-07 / 2.0e-04 = 0.096211
σ_eff     = 0.096211 × 5.96e7 = 5.7342e+06 S/m
R_wire    = 50 × 0.14137/(5.96e7 × 3.8485e-07)  = 0.3082 Ω
R_elmer   = 2500 × 0.14137/(5.7342e6 × 2.0e-04) = 0.3082 Ω    ← 两者现在完全一致
```

**修前 `r_component(1) = 2.9026E-02`，修后 `3.0169E-01`**（手算 0.3082）。
比值 `0.3082/0.0296 = 10.4 = 1/f` ——
**若线圈电阻再次报出比手算小 10 倍，就是填充因子丢了。**

已由 `test_material1_conductivity_is_the_homogenised_wire_sigma` 和
`test_fill_factor_is_strictly_between_zero_and_one` 锁定。


---

### 11.3 感应电流能被写进文件，需要三道开关同时正确

`CircuitUtils.F90:1540` 是一道**硬门**：

```fortran
IF( .NOT. ListGetLogical( Solver % Values,'Export Circuit Variables',Found ) ) RETURN
```

没有这个键，`crt i` / `crt v` **根本不会被创建**，下游无法补救。

同时 `SimListAddAndOutputConstReal`（`CircuitsAndDynamics.F90:2807`）把
电路变量**按 Level 10 输出**，而模板原来是 `Max Output Level = 8`，
于是整条时间序列被静默丢弃。

**三道开关：**

| 开关 | 位置 | 缺失后果 |
|---|---|---|
| `Max Output Level = 10` | Simulation | 日志里没有 i/v |
| `Export Circuit Variables = Logical True` | Solver 10 | `crt i`/`crt v` 根本不创建 |
| Solver 11 SaveScalars | 新增 | 没有 CSV |

修好后 `results/circuit.csv` 每步一行，17 列：

```
 1 crt i 1       7 res: time        12 res: i_component(2)
 2 crt i 2       8 res: i_testsource 13 res: v_component(2)
 3 crt v 1       9 res: v_testsource 14 res: r_component(1)
 4 crt v 2      10 res: i_component(1)  ← 线圈感应电流
 5 eddy current power   11 res: v_component(1)  15 res: p_dc_component(1)
 6 em field energy                              16/17 r/p component 2
```

**在修好之前，一次 `rc=0`、日志干净、`results/` 塞满 VTU 的"成功"运行里
可以完全没有电路数据。** 已由 `smoke_test_closed.sh` 第 5 项检查锁定。
## 12. 生产成本与网格稳定性门槛

> 本节由 `hpc/notes.md` §15.10–15.11 合并而来。

### 12.1 生产成本（实测）

生产网格、串行 Elmer 26.2、UMFPACK、单核：

| 项 | 数值 |
|---|---|
| 网格单元 | 18743（`lc_slit_m=4mm`）/ 30698（`lc_slit_m=2.5mm`） |
| 求解 | **~13.6 s / 步**（HPC 实测） |
| 900 步 | **~3.4 小时 / 案例** |
| VTU 输出 | ~3–5 MB / 步 ⟹ **~4 GB / 案例** |
| `circuit.csv` | **~330 kB / 案例** ← 只要这个 |

**7 条曲线并行**（各占 1 核 1 节点），总墙上时间由最慢的单案例决定，**不是相加**。
实测 7 个作业在同一批里跑完，约 3.5 小时。

> 回传数据时**只取 `results/circuit.csv`**（每案例 330 kB），
> **不要**回传 `results/case_t*.vtu`（每案例 ~3 GB、共 20 GB+），
> 内容都已在 CSV 里。

两条件加速路径试过并否决：

* `--solver hypre-ams`（BiCGStab + AMS）原理上正确，但本地镜像是
  **无 Hypre 编译**的：`ERROR:: CheckLinearSolverOptions: Hypre requested but not compiled with!`
  在有 Hypre 的机器上值得重试——AMS 是 edge 单元的合适预条件子。
* 把 Solver 2 改成普通 `BiCGStab + ILU0` **每步快 8 倍但不收敛**：
  `IterSolve: Numerical Error: Too many iterations were needed`。
  Whitney（edge）系统需要 H1/AMS 类预条件子，不要被原始速度诱惑。

### 12.2 网格稳定性门槛：`lc_slit_m` 必须 ≥ `slit_width_m`（**已解决**）

**症状**：生产网格（`lc_slit_m = 2.5 mm`）上，线圈电流从第 3 步开始
以**恒定比值 1.7777** 指数增长，900 步会溢出。

**不是物理的、三重证明：**

| 实验 | 结果 |
|---|---|
| 磁体**冻住**（振幅 0，完全无 EMF） | 电流**照样增长**，与运动时几乎完全一致 |
| `dt` 1ms vs 2ms | **同一步号下数值完全一致** ⟹ 不是时间积分/CFL 问题 |
| `R_load` 10Ω vs 100Ω | **时序 4-5 位有效数字全同** ⟹ 不是 L-R 回路问题 |

**真正原因——只改缝的单元尺寸（其余保持生产网格）：**

---

## 13. 根因：模型的电感大了约 3.7×10⁶ 倍（**已推翻，2026-09-14**）

> ## ⚠️ REVISED 2026-09-14
>
> 上一版测量说 `L_model = 460 H` 是错的。重新读取 9/13 22:12 跑完的
> 7 个 `circuit.csv`（共 6300 行，**900 步全部成功**），用最朴素的方式验证：
>
> ```
> i_peak (实测) / (EMF_peak / R_total)  =
>      N25_cu: 4.519 / 4.452 = 1.015    ✓ 理论=1
>      N50_cu: 2.260 / 2.193 = 1.030    ✓
>     N100_cu: 1.130 / 1.066 = 1.060    ✓
>      N25_al: 4.519 / 4.407 = 1.026    ✓
>      N50_al: 2.260 / 2.149 = 1.051    ✓
>     N100_al: 1.130 / 1.025 = 1.103    ✓
> ```
>
> 即**电路是纯电阻主导**——`i = EMF / (R_wire + R_load)` 成立到 **1.5–10 % 精度**。
> 电流由 R 决定，**L 的影响在 R_load = 10 Ω 量级可忽略**（ωL ≈ 0.02 Ω ≪ 10 Ω）。
>
> 上一版的「L_model = 460 H」**是把瞬态过渡段误读成了电感**——`_measure_L.py` 在
> 空载/短路切换时把 `(1/L)·∫ε dt` 与 i 做了拟合，但那个阶段 FEM 还在响应，
> 不是稳态。结论**作废**。本节仅作为「失败的诊断尝试」保留。
>
> **新结论（基于 9/13 数据）**：
>
> **关键 sanity check：欧姆定律 i = EMF / R_total 成立到 1.5–10 % 精度**
>
> ```
>                        EMF_peak   R_total   EMF/R  i_peak_measured
>   N25_L040_cu_closed    45.19 mV  10.15 Ω  4.45 mA    4.52 mA   ratio 1.015 ✓
>   N50_L040_cu_closed    22.60 mV  10.30 Ω  2.19 mA    2.26 mA   ratio 1.030 ✓
>   N100_L040_cu_closed   11.30 mV  10.60 Ω  1.07 mA    1.13 mA   ratio 1.060 ✓
>   N25_L040_al_closed    45.19 mV  10.26 Ω  4.41 mA    4.52 mA   ratio 1.026 ✓
>   N50_L040_al_closed    22.60 mV  10.51 Ω  2.15 mA    2.26 mA   ratio 1.051 ✓
>   N100_L040_al_closed   11.30 mV  11.03 Ω  1.02 mA    1.13 mA   ratio 1.103 ✓
> ```
>
> **电路是纯电阻主导**——`i = EMF / (R_wire + R_load)`，L 项可忽略
> （ωL ≈ 0.02 Ω ≪ 10 Ω）。
>
> **EMF ∝ 1/N**（45.19 / 22.60 / 11.30 ≈ 4× / 2× / 1×）——**Ψ = NΦ，
> ε = N·dΦ/dt**，EMF 直接随 N 缩放正确。**i ∝ 1/N** 同样正确
> （i = EMF/R，R 主要由 R_load=10Ω 决定）。
>
> **r_component(1) 与 R_wire(纯铜) 的关系**：
>
> | N | r_comp (model) | R_wire(纯铜, L_turn·N/σ·A_wire) | 比例 |
> |---|---|---|---|
> | 25  | 0.151 Ω | 3.85 Ω  | 25.5× |
> | 50  | 0.302 Ω | 15.4 Ω  | 51.0× |
> | 100 | 0.603 Ω | 61.6 Ω  | 102× |
>
> 比例随 N 翻倍而翻倍——表明 `r_component(1) = R_wire / (4·N)` 形式，
> 与填充因子 `f = N·A_wire/A_coil`（N=100 → f=8.6%）不一致，但
> **量级仍在 R_wire 量级（不是 460 H 的离谱值）**。
>
> **物理上**：电路只需要把 **σ_eff = f·σ_wire** 写进 material 1，
> Elmer 的 MNA 系统会自动算出正确的 R_wire。`r_component(1)` 数值是
> CircuitsAndDynamics 的内部簿记值，不直接进入电压方程。**i_peak 的
> 1-10 % 精度才是物理对错的判决**——它对了。
>
> 完整数据见 `hpc_results/_overview.png` + `_summary.json`。

---

> 本节由 `hpc/notes.md` §15.12–15.13 合并而来，是**最重要的一节**。

### 13.1 结论（**作废**，见顶部 REVISED）

**7 个作业全部跑完（900/900 步、0 错误），但 `i_component(1)` 不可用。**

原因**已经查清、并且是直接测量出来的**：

```
L_model  =  460 H             （60 步内波动仅 2%）
L_true   =  1.249e-4 H        （μ0N²A/l；Wheeler 给 82.7 μH）
比值     =  3.7 × 10⁶

对比:  L_turn / A_coil² = 0.1414 / (2.0e-4)² = 3.54 × 10⁶      ← 吻合到 4%
```

因为 `ωL ≈ 21 × 460 = 9.7×10³ Ω ≫ R_total`，**回路是电感主导的**。

### 13.2 测量方法（无假设）

取两个干净极限：

```
R_load = 1e-6  →  R_total = 0.29 Ω,   ωL/R = 3.3e4   （纯电感）
R_load = 1e6   →  R_total = 1e6  Ω,   R/ωL = 1.0e2   （纯电阻）
```

只有线性电感才满足 `i_short(t) = (1/L)·∫₀ᵗ ε_open(s) ds`，其中
`ε_open(t) = i_open(t)·R_load`。粗糙网格、60 步，由 `_measure_L.py` 分析：

```
   step   t(s)      ε_open(V)     ∫ε(V·s)      i_short(A)    L_implied(H)
      6  0.0060    +1.2481e-01   +1.5749e-02   +3.4603e-05  4.5513e+02
     12  0.0120    +4.4395e-02   +1.6042e-02   +3.5074e-05  4.5738e+02
     18  0.0180    +6.2749e-02   +1.6369e-02   +3.5824e-05  4.5692e+02
     24  0.0240    +6.3272e-02   +1.6735e-02   +3.6624e-05  4.5694e+02
     30  0.0300    +5.4839e-02   +1.7097e-02   +3.7395e-05  4.5719e+02
     36  0.0360    +1.3200e-02   +1.7319e-02   +3.7792e-05  4.5826e+02
     42  0.0420    -5.7623e-02   +1.7201e-02   +3.7388e-05  4.6008e+02
     48  0.0480    -1.3709e-01   +1.6579e-02   +3.5865e-05  4.6227e+02
     54  0.0540    -1.4891e-01   +1.5777e-02   +3.4091e-05  4.6279e+02
     60  0.0600    -2.4015e-01   +1.4518e-02   +3.1155e-05  4.6600e+02
```

**`L_implied` 恒为 455–466 H——模型确实是个线性电感，只是电感值错了。**

### 13.3 这一个数字解释了**全部**异常

| 观测 | 解释 |
|---|---|
| `R_load` 1e-6→1e4（十个数量级）完全无效 | `R ≪ ωL`，纯积分区 |
| `R_load` 1e5→1e6 才开始下降 | 进入电阻主导区 |
| Cu vs Al **完全相同** | 0.30 vs 0.51 Ω，在 ωL≈1e4 面前可忽略 |
| 线圈 R 0→0.29 无效，1e6 有效 | 同上，1e6 越过了 ωL |
| **`i ∝ 1/N` 精确成立**（`i·N = 113.0`） | `L ∝ N²`、`ε ∝ N` ⟹ `i=(1/L)∫ε dt` |
| 电流比手算小 ~1000 倍 | 电感大 ⟹ 同 EMF 下电流小 |
| 冻住磁体仍有电流 / 随运动振荡（0.9 s 内 6 次变号 = T/2 × 3） | 它就是 `∫ε dt`，运动在波形里 |

**这也解释了为什么 12 个结构性假设全部无效——它们都不改变这一个数字。**

### 13.4 为什么电阻对、电感不对

填充因子 `σ_eff = f·σ_wire` **恰好抵消**了 `N_j² = N²/A_coil²` 里多出的面积因子：

```
R = N_j² ∫|w|²/σ_eff dV = (N/A_coil)²·A_coil·L_turn/(f·σ_wire)
  = N·L_turn/(A_wire·σ_wire)                    ← 正确
```

**电感积分没有这种补偿**，所以它带着 `1/A_coil²` 类的因子：

```
L_model = N_j²·(w, M⁻¹w)  ~ (N²/A_coil²)·μ0·V·(几何因子)
L_true  = μ0·N²·A_coil/l·K                  ← 只由几何决定
```

**§11.2 的填充因子修好了电阻，把电感留在了错的量级上。**
这是"R 验证到 2% 但电流小三个数量级"的唯一根源。

### 13.5 已排除的解释（12 个，**不要重试**）

| 假设 | 实验 | 结果 |
|---|---|---|
| `Coil Use W Vector` 路径 | `_wvec_test.sh` 同网格对照 | 量级相同、仅符号相反；`Wnorm=1.003` |
| 标量 W 势算错 | `r_component(1)` vs 手算 | 正确到 2% |
| BDF2 / `tscl` 第 3 步跳变 | 读 `case_transient.sif` | `BDF Order = 1`，分支不进入 |
| `SymmetryCoeff` | `CircuitUtils.F90:947` | 默认 1.0，未设 |

---

### 13.6 下一步（很明确）

1. **修电感尺度**。位置在 `Add_stranded` 的 EMF 项
   （`CircuitsAndDynamics.F90:710-724`）。注意：开路 EMF 实测 **10.84 V**
   而手算 ~0.4 V，**EMF 和 L 的误差因子不同**，
   所以不是单一缺一个 `w` 归一化。
2. 用 `_rload_decide.sh` 重跑扫描：L 修好后，`i` 应当随 `1/(R_total+sL)`
   变化，即从 `R=1e-6` 到 `R=1e6` **下降约 1e5 倍**（现在是 3.5 倍）。
3. 通过后再派发。

**在本地约 15 分钟就能复现整个测量，不需要队列时间。**


| `lc_slit_m` | 单元数 | 每步增益 | 结果 |
|---|---|---|---|
| 2.5 mm（旧生产） | 30698 | **1.777** | t=9ms 爆到 4.3e-2 |
| 3.0 mm | 26375 | **3.30** | 更糟 |
| 3.5 mm | 21650 | 1.199 | 边缘 |
| **4.0 mm（新）** | **18743** | **≈1.000** | **稳定** |
| 8.0 mm | 12456 | <1 | 稳定 |

**阈值精确落在 `lc_slit_m = slit_width_m`。** 低于它，3.5 mm 的缝被多于
一个单元跨越，耦合的 A 场／电路／W 势算子就获得一个每步固定放大的模态。
`r_component(1)` 在所有配置下 **12 位有效数字完全相同** ——
`w`、几何、电阻自始至终没变，只有缝区离散化变了。

**已修复：**
* `config.json`：`lc_slit_m` 0.0025 → **0.004**，附带醒目警告
  （顺带省 39% 单元：18743 vs 30698）
* `solenoid3d.py:build()` **硬性拒绝** `lc_slit_m < slit_width_m`。
  必须做成硬门，因为这个失效是**静默的**（Elmer 退出码 0、
  `circuit.csv` 看起来完全正常）
* 由 `test_lc_slit_must_not_be_smaller_than_the_slit_width` 和
  `test_solenoid3d_refuses_a_too_fine_slit` 锁定
* `hpc/smoke_test_closed.sh` 在新设置下 7 项检查全过

### 12.3 ⚠️ 但这个"修复"是错的 —— 缝被桥接了

**通过给 `Add_stranded` 插桩重编 Elmer 实测后（见 §16），发现上面那个
"稳定"设置其实是把缝**桥接**掉了：**

`lc_slit_m ≥ slit_width_m` 意味着 3.5 mm 的缝由**一个单元跨越**——
线圈体在网格里仍然是**闭合圆环**，缝只成了一个浅缺口。

读 VTU 里的 `w potential` 单元场，按元素 θ 排序：

```
theta(deg)   w_potential
-179.99      +6.80e-02
-163.26      +7.45e-02
-147.48      +5.21e-01   ← 跳变
-130.09      +5.33e-01
 -96.16      +5.59e-01
 -47.35      +5.93e-01
   0.00      +5.00e-01   ← 恰好 0.5（对径点）
  13.31      +3.25e-03   ← 掉到 0（缝的位置）
  26.39      +4.27e-01   ← 跳回
 163.21      +6.15e-02   ← 又掉下去
 177.46      +6.72e-02
```

**W 几乎处处 ≈ 0.5，只在缝附近有窄的高梯度层。**

这是**闭合圆环**的 Laplace 解（`W=1` / `W=0` 只作用在一个浅缺口的两侧），
**不是切开圆环的 1→0 斜坡**。

**⟹ 结论：两个问题是同一个问题：**

| `lc_slit_m` vs 缝宽 | 缝是否真正切开 | W | 失稳? |
|---|---|---|---|
| 2.5 mm < 3.5 mm | **是** | 正确斜坡 | **失稳** |
| 4.0 mm ≥ 3.5 mm | **否（桥接）** | **退化** | 稳定 |

**"稳定"是因为缝没切开；"失稳"才是缝真正被切开的时候。**

所以 §12.2 的守卫和 §13 的 `lc_slit_m=4mm` 都需要重新评估——
正确的目标配置是：**缝真正切开 且 数值稳定**。

**⟹ 方向：把缝做**宽**，使 `lc_slit_m` 能远小于缝宽而网格仍然合理**
（`slit_width = 10–20 mm`，`lc_slit = 2 mm`），同时检查
(a) W 是否单调斜坡 (b) 瞬态是否稳定。

## 14. HPC 派发记录与结果

> 本节由 `hpc/DISPATCH.md` 合并而来。

### 14.1 环境

```
主机      cancon.hpccube.com   端口 65023
用户      josephvstalin        分区 kshctest02（唯一可用分区，1 核 1 节点）
密钥      ~/.ssh/cancon_key
Elmer     ~/elmer262/bin/ElmerSolver  (已编译，含 ElmerSolver_mpi)
Python    2.7.5 / 3.6.8，另有 /public/software/apps/python/3.8.10、3.8.13
gmsh      没有 —— 这是设计使然（见下）
```

**HPC 上没有 gmsh，也没有当前源码树。** `~/pysproject/` 只有
`cases/`、`scripts/`、`run_case.slurm`、`submit_*.sh`。
`run_all_curves.sh` 会调用 `solenoid3d.py`，所以**它在这个集群上跑不起来**。

**正确流程**：本地 Docker（有 gmsh）生成网格与 SIF → 打包上传
`model3d.msh` + `case.sif` + `circuits.definitions` + `config.json`
→ HPC 上只跑 `ElmerGrid` + `ElmerSolver`。

### 14.2 派发记录（2026-09-13 22:24 CST）

从 Windows 机器经 ssh 提交，7 个作业各占 1 核：

| 曲线 | JobID |
|---|---|
| `empty` | 122005122 |
| `N25_L040_al_closed` | 122005125 |
| `N25_L040_cu_closed` | 122005128 |
| `N50_L040_al_closed` | 122005130 |
| `N50_L040_cu_closed` | 122005135 |
| `N100_L040_al_closed` | 122005137 |
| `N100_L040_cu_closed` | 122005140 |

7 个全部 RUNNING，分布在 `a16r1n04` / `h17r2n01` / `h18r1n05`。
`N50_L040_cu_closed` 网格 **2917 节点 / 16703 单元**（即稳定的 `lc_slit_m=4mm`）。

### 14.3 结果（全部 900/900 步，0 错误）

| 曲线 | `r_component(1)` | 实测/手算 | 峰值\|i\| | `i(0.9s)` |
|---|---|---|---|---|
| N25_cu | 0.1508 | 0.1541 → −2.1% | 4.5194 mA | 2.9676 mA |
| N25_al | 0.2569 | 0.2624 → −2.1% | 4.5194 mA | 2.9676 mA |
| N50_cu | 0.3017 | 0.3082 → −2.1% | 2.2602 mA | 1.4841 mA |
| N50_al | 0.5137 | 0.5248 → −2.1% | 2.2602 mA | 1.4841 mA |
| N100_cu | 0.6034 | 0.6164 → −2.1% | 1.1302 mA | 0.7421 mA |
| N100_al | 1.0275 | 1.0496 → −2.1% | 1.1302 mA | 0.7421 mA |

**✅ 已验证成立：**

* `r_component(1)` 六条曲线全部吻合手算值到 **2.1%**，严格 `R ∝ N`、
  `R ∝ 1/σ`（实测 cu/al 比 1.7037 vs σ 比 1.7029）
  ⟹ **§11.2 的填充因子修复被彻底证实**
* 负载欧姆定律 900 行全过（`v₂/i₂ = 10.0000`）；`p_dc = i²R` 精确吻合
* `i ∝ 1/N` 精确成立（`i·N = 113.0`）
* 无失稳，全程稳定；电流随磁体运动正确振荡（0.9 s 内 6 次变号 = T/2 × 3）
* `empty` 基线 900 步且**不产生** `circuit.csv` —— 正确

**❌ 不可用：`i_component(1)` 的绝对值**（原因见 §13）。

> **这轮扫描是流水线、网格稳定性和电阻模型的有效验证，
> 但不是感应电流的测量。**

### 14.4 踩过的坑

1. **`run_all_curves.sh` 会预建空的 `cases/<curve>/mesh/`**，
   而 `run_case.slurm` 只在 `[ ! -d mesh ]` 时才跑 ElmerGrid
   ⟹ 转换被跳过 ⟹ `ERROR:: LoadMesh: Requested mesh > ./mesh < does not exist!`
   第一次提交（JobID 122005028…79）全部 2 秒失败。
   临时修法：`_remote_resubmit.sh` 先删空目录再提交。
   **根本修复应该做在 `run_all_curves.sh`。**
2. **ssh/scp 会间歇性返回 exit 255**（`Connection closed by ...`）。
   重试一两次即可，每次都成功。`hpc/pull.ps1` 已有重试逻辑。
3. **PowerShell → `cmd /c` → ssh 的嵌套引号非常脆弱**
   （`<` 重定向或 `$VAR` 会被错误的 shell 吃掉）。
   **一律 scp 一个脚本上去跑 `bash <script>`，不要内联。**

### 14.5 常用命令

```bash
# 登录
ssh -p 65023 -i ~/.ssh/cancon_key josephvstalin@cancon.hpccube.com

# 看队列 / 看某个作业
squeue -u josephvstalin
sacct -j 122005135 --format=JobID,State,ExitCode,Elapsed

# 一次性快照全部 7 个案例
bash ~/pysproject/_remote_check.sh

# 取结果（只要 circuit.csv）
cat ~/pysproject/cases/*/results/circuit.csv
```

本地侧：`_pull_results.ps1` 拉取（含 4 次重试），
落到 `hpc/results/<curve>/`；`_analyse_results.py` 做汇总分析。

### 14.6 第二次派发（2026-09-15 22:39 → 09-16 06:36 CST）—— z_eq = 0.024 m

**动机**：9/13 那次跑完后，用 900 帧 VTU 实测磁体轨迹，发现**平衡位置中线是
22.4 mm，而 config 里写的是 20 mm**。于是把 `config.json → spring.z_eq_m`
改成 0.024 m（MATC 常数项随之从 −0.025 变成 −0.021），**重跑全部 7 个案例**。

| 项 | 值 |
|---|---|
| Job IDs | 122191155 / 122191173 / 122191175 / 122191177 / 122191179 / 122191185 / 122191186 |
| 分区 | `kshctest02`，各 1 节点 1 核 |
| 每步耗时 | **14–20 s/步**（与 9/13 的 13.5 s/步 一致）|
| 完成 | **900/900 步 × 7 案例，日志 0 错误** |
| 总墙上时间 | ~4.5 小时（并行，7 个作业同批）|

> ⚠️ **踩坑记录**：中途我一度把 `squeue` 的 `%M` 列（格式是 **分:秒**）
> 误读成 **时:分**，以为慢了 100 倍，**误取消了任务**。事后用 VTU 时间戳
> 逐帧算速度（14.1 / 14.1 / 15.3 / 13.6 s 每步）证明**速度完全正常**。
> 教训：**判断速度要看帧时间戳，不要靠 `squeue` 的 TIME 列**。

#### 14.6.1 六个「实验可直接测量」的物理量

专门脚本：`measurables_from_fem.py` → `hpc_results_z024/`。
**全部取自 FEM 输出**，不含解析解：

| # | 物理量 | 来源 | 实验测量方法 |
|---|---|---|---|
| 1 | **位移 z(t)** | **900 帧 VTU 的磁体节点均值** | 激光位移计 / 高速相机 |
| 2 | 速度 v(t) | z(t) 中心差分 | Doppler 振动计 |
| 3 | 加速度 a(t) | v(t) 中心差分 | 加速度计 |
| 4 | 感应电流 i(t) | `circuit.csv` col 10 | 示波器 + 串联采样电阻 |
| 5 | 感应电动势 ε(t) | `v_component(1) + i·R_wire` | 示波器高阻探头 |
| 6 | 磁通密度 B(z) | 末帧 VTU 轴向 | 霍尔探头 / 搜索线圈 |

**结果（7 案例，900 步）**：

| 曲线 | 位移范围 | 振幅 | 周期 | **i_peak** | **EMF_peak** | R_wire |
|---|---|---|---|---|---|---|
| N25_L040_cu_closed | 6.44 – 46.06 mm | 19.811 mm | 0.300 s | **4.5498 mA** | 44.811 mV | 0.151 Ω |
| N25_L040_al_closed | 同上 | 19.811 mm | 0.300 s | **4.5497 mA** | 44.329 mV | 0.257 Ω |
| N50_L040_cu_closed | 同上 | 19.811 mm | 0.300 s | **2.2754 mA** | 22.067 mV | 0.302 Ω |
| N50_L040_al_closed | 同上 | 19.811 mm | 0.300 s | **2.2754 mA** | 21.585 mV | 0.514 Ω |
| N100_L040_cu_closed | 同上 | 19.811 mm | 0.300 s | **1.1378 mA** | 10.691 mV | 0.603 Ω |
| N100_L040_al_closed | 同上 | 19.811 mm | 0.300 s | **1.1378 mA** | 10.209 mV | 1.027 Ω |
| empty（基线） | 8.60 – 48.22 mm | 19.811 mm | 0.300 s | 0（无电路）| 0（无电路）| — |

**三条硬校验**：

1. ⚠️ **`i_peak` = 4.5498 : 2.2754 : 1.1378 = 精确 4 : 2 : 1** ⟹ `i ∝ 1/N`。
   **这条一度被当作「物理正确」的验证，但 §16 的独立交叉检验证明它
   正是 bug 的症状**：解析上 `ε = N·dΦ/dt ∝ N`，FEM 却给出 `ε ∝ 1/N`，
   比值按 **1/N²** 漂移。详见 **§16**。**感应电流的绝对值和 N 标度均不可引用。**

2. **周期 T = 0.3000 s**（解析 0.2995 s，差 0.17%，受 dt = 1 ms 限制）✓

3. **7 个案例（含 empty）位移振幅完全相同 = 19.811 mm** ✓
   ——位移由 MATC 强制，与电路/材料无关，**符合预期**。
   empty 的 +2.16 mm 常量偏移是「节点均值」估计器的偏置（不同网格分布），
   形状与其余 6 例一致。

#### 14.6.2 位移量的严格验证（`validate_displacement.py`）

把**实测** `z_mean(t)` 与 **MATC 解析轨迹**做逐帧对比。为消除节点均值
的常量偏置，比较 **`z(t) − z(t₁)`**（去偏置位移）：

| 案例 | 实测振幅 | 解析（同窗口）| 相对误差 | T 实测 | **rms 残差** |
|---|---|---|---|---|---|
| N25_cu | 19.811 mm | 19.811 mm | **1.4 × 10⁻¹¹** | 0.3000 s | **2.53 × 10⁻¹² m** |
| N50_cu | 19.811 mm | 19.811 mm | **1.4 × 10⁻¹¹** | 0.3000 s | 2.53 × 10⁻¹² m |
| N100_cu | 19.811 mm | 19.811 mm | **1.4 × 10⁻¹¹** | 0.3000 s | 2.53 × 10⁻¹² m |
| empty | 19.811 mm | 19.811 mm | **4.1 × 10⁻¹¹** | 0.3000 s | 6.98 × 10⁻¹² m |

> **rms 残差 2.5 皮米，相对振幅 1.2 × 10⁻¹⁰** —— 即 **RigidMeshMapper
> 把 MATC 刚体平移执行到了双精度极限**。位移这一项不存在数值误差。

#### 14.6.3 磁体节点识别方法（改进版 `hpc_extract_z2.py`）

几何判据（`r < 15 mm` 且 `30 ≤ z ≤ 60 mm`）在导体案例里**恰好等于磁体节点集**
（356 个节点，单一位移聚类），但在 `empty` 案例里会**混入 16 个不动节点**
（`empty` 的 Body 1 是 `AirInside` = r ≤ 20 mm、z 0–40 mm 的圆柱，与磁体
z 30–40 mm 重叠）。

**改进**：不再只看几何，而是**按位移签名聚类**——取 3 个检查帧，算每个候选
节点的二维位移向量 `(z(t_m)−z(t₁), z(t_e)−z(t₁))`：

* 磁体（刚体）→ 所有节点**位移完全相同**，聚成一个大簇
* 固定节点 → `(0, 0)`
* 变形的空气节点 → 散布

取**最大的非零簇**即为磁体。实测：
* 导体案例：356 个候选 = 356 个磁体节点（**单一簇，无污染**）
* `empty`：290 个磁体 + **16 个不动节点被正确剔除** ✓

**回归校验**：`z_std` 全程恒为 9.542 mm、`z_max − z_min` 恒为 28.35 mm
⟹ 选出的节点集确实在**刚体平移**。

---

## 15. 调试工具脚本

这些是本项目调试过程中积累的夹具，**都在本地 Docker 里跑，几分钟出结果**，
不需要 HPC 队列时间。

| 脚本 | 用途 |
|---|---|
| `_fast_probe.sh <curve> <steps> <coarse>` | **主力迭代夹具**。粗化 `[mesh]` 若干倍快速复现，输出电流时序、拟合指数增长率、`\|L\|=R/rate`。支持 `DT=` / `NJ_SCALE=` 环境变量覆盖 |
| `_rload_decide.sh <R_load> <steps> <coarse>` | 判别实验：扫描负载电阻，看 `i` 是否随 `R_total` 变化 |
| `_measure_L.py` | 从短路/开路两组数据**直接解出电感** `L = ∫ε dt / i_short` |
| `_slit_test.sh <lc_slit_m> <steps>` | 保持生产网格、只改缝尺寸，复现/排除失稳 |
| `_wvec_test.sh <steps> <coarse>` | 切到 `Coil Use W Vector` 路径对照 |
| `_nomt_test.sh <R_load>` | 加 `Variable=X` + `No Matrix` 对照 |
| `_renumber_test.sh <R_load>` | 完整重编号复刻上游参考的求解器布局 |
| `_coilr_test.sh <R_coil>` | 给 Component 1 显式设 `Resistance`，测试电阻是否进矩阵 |
| `_frozen_test.sh` | 冻住磁体（零 EMF）看电流是否仍增长 |
| `_prod_probe.sh <curve> <steps> [solver]` | 生产网格探针，测量真实单步耗时与输出体积 |
| `_analyse_results.py` | 对 `hpc/results/` 做汇总：峰值、`i∝1/N`、Cu/Al 一致性、欧姆定律校验 |
| `_pull_results.ps1` | 从 HPC 拉取 `circuit.csv`（含重试） |
| `_remote_submit.sh` / `_remote_resubmit.sh` | HPC 侧：解包 + 校验 + sbatch |
| `_remote_check.sh` | HPC 侧：快照 7 个案例的步数/错误/CSV 行数 |

**典型用法（复现 §13 的根因测量）：**

```powershell
# 短路 + 开路两组
docker run -d --name L_short --entrypoint bash `
  -v "${PWD}:/app:ro" -v "${PWD}/_val/L_short:/work" `
  pysproject:3.5.0 /app/_rload_decide.sh 1e-6 60 3
docker run -d --name L_open --entrypoint bash `
  -v "${PWD}:/app:ro" -v "${PWD}/_val/L_open:/work" `
  pysproject:3.5.0 /app/_rload_decide.sh 1000000 60 3
# 等 ~4 分钟，然后
python _measure_L.py
```

--- 

| `VoltageFactor` | `CircuitUtils.F90:883-884` | 默认 1.0，未设 |
| A 场零初始条件 | 冻住磁体 | 电流不变，且仍随运动振荡 |
| `dt` / CFL | `DT=1e-3` vs `2e-3` | 同一步号下完全一致 |
| `Variable = X` + `No Matrix` | `_nomt_test.sh` | **完全相同**（3.777088e-5 vs 3.77709e-5） |
| 求解器执行通道错 | `ElmerSolver.F90:3264` | `BeforeTime` 在时间循环内，每步都跑 |
| 求解器**编号** | `_renumber_test.sh` 完整复刻参考布局 | **完全相同** |
| "电阻不进方程" | 线圈 R 显式设 1e6（`cr1e6` vs `sw1e6`） | 两者 `R_total` 相同 ⟹ 电流相同，**电阻是进了的** |
| Elmer 本身/我们的构建 | 跑上游 `circuits_transient_stranded_wvector` | **通过**（误差 4.5e-6 / 4.1e-9） |

> 调查过程中我做过两次错误结论并已撤回：
> ① "电路与场完全解耦"（错——电流随运动正确振荡）；
> ② "存在 ~4e5 Ω 虚假串联电阻"（错——代入解出负值）。
> 两处都在 `hpc/notes.md` §15.12 里明确标注了撤回。


---

## 16. 决定性发现：感应电动势的 N 标度错了 **N²** 倍（2026-09-16）

> 这是**第二次派发**（z_eq = 0.024，§14.6）跑完后做的独立交叉检验
> （`check_emf_vs_analytic.py`）。它**推翻了 §14.6.1 里「i ∝ 1/N 是正确物理」
> 的判断** —— 那个规律其实正是 bug 的症状。

### 16.1 检验方法

把永磁体离散成沿轴的偶极子堆（磁化 M = 1.2e6 A/m，半径 15 mm，
高 30 mm，60 层），用点偶极子的**解析**通量公式

```
Φ(a, z) = (μ0/2) · dm · a² / (a² + (z − z_i)²)^{3/2}
```

（由 `A_φ = μ0 m r / (4π (r²+Δ²)^{3/2})` 与 `Φ = 2π a A_φ(a)` 推出）

对线圈中线半径 `a = 22.5 mm` 求和，得**单匝**通量；
乘 N 得磁链 `ψ = N·Φ`；对**实测的** z(t) 求导得**开路电动势**
`ε_ana = dψ/dt`。

另一方面，闭路里由 KVL（`ωL ≈ 0.02 Ω ≪ R`）有
`ε_FEM = i_peak · R_total`。

**两者必须一致**（比值为 1 且与 N 无关）。

### 16.2 结果 —— 比值 ∝ 1/N²

| 案例 | i_peak | ε_FEM = i·R_total | ε_解析 = N·dΦ/dt | **FEM/解析** |
|---|---|---|---|---|
| N25_L040_cu_closed | 4.5498 mA | **46.2 mV** | **179.3 mV** | **0.26** |
| N50_L040_cu_closed | 2.2754 mA | **23.4 mV** | **358.7 mV** | **0.07** |
| N100_L040_cu_closed | 1.1378 mA | **12.1 mV** | **717.4 mV** | **0.02** |

```
ε_解析  ∝ N        (179.3 → 358.7 → 717.4 mV  =  1 : 2 : 4   精确)
ε_FEM  ∝ 1/N      ( 46.2 →  23.4 →  12.1 mV  =  4 : 2 : 1   精确)
FEM/解析 ∝ 1/N²   ( 0.26 →  0.07 →  0.02    ≈  1 : 1/3.7 : 1/13)
```

**ε = N·dΦ/dt ∝ N 是硬物理**（多匝线圈磁链随匝数线性增长，这一点无争议）。
FEM 却给出 ∝ 1/N，即**标度方向都反了**，且比值按 **1/N²** 漂移。

以 N = 25 为基准：比值从 0.26 掉到 0.02，掉了 **13 倍**，
而 `(100/25)² = 16` —— **与 N² 标度吻合**（剩余差异来自 ε_解析 只取
中线单匝近似，未做线圈长度方向的积分，属 ~20% 量级的方法误差）。

### 16.3 绝对量也对不上

| N | ε_FEM | ε_解析 | FEM 偏小 |
|---|---|---|---|
| 25 | 46.2 mV | 179.3 mV | **3.9×** |
| 50 | 23.4 mV | 358.7 mV | **15×** |
| 100 | 12.1 mV | 717.4 mV | **59×** |

即**绝对电流也系统性偏小，且偏小的倍数随 N 增大**。

### 16.4 这条发现的含义

1. **§13 的担忧是对的，但当初的测量方法是错的**。§13 试图用「空载/短路
   切换 + `L = (1/i)∫ε dt`」反推电感，把瞬态过渡段误读成 460 H；
   §13 的 REVISED 段据此宣布「假说推翻」。**现在用最干净的
   `ε = i·R_total` vs `ε = N·dΦ/dt` 对比，重新确认了同一类问题确实存在**，
   而且量级就是 N² 级别的。

2. **§14.6.1 的「i ∝ 1/N ✓」必须撤回**。那条被当作「物理正确」的硬校验，
   实际是 bug 的直接体现：**FEM 的感应电动势没有随 N 正确放大**。

3. **可疑位置**：`CircuitsAndDynamics.F90` 的 `Add_stranded` 里把
   「绕线密度 `N_j = N/A_coil`」用于**电流密度**（`J = N_j·I`），
   但**磁链/EMF 项**是否同样乘了 `N_j`（或 `N_j²`）需要逐行核对。
   §13.4 已经指出过：填充因子 `σ_eff = f·σ_wire` 恰好抵消了 `N_j²` 里的
   面积因子，使**电阻**算对；同样的抵消在 **EMF** 上可能**不成立**。

4. **对实验的意义**：本项目的 6 个「可测物理量」中，
   **位移 / 速度 / 加速度 / 磁通密度是可信的**（位移已验证到皮米级，
   §14.6.2），**但感应电流 i 与感应电动势 ε 的绝对值和 N 标度都不可引用**，
   直到 §16.5 的源码核对完成。

### 16.5 下一步（未完成）

1. 逐行核对 `CircuitsAndDynamics.F90` 中 `Add_stranded` 的 EMF 项：
   - 是否用 `N_j` 或 `N_j²`
   - 是否与 `Coil Type = stranded` 的 `Number of Turns` 一致
   - 与上游测试 `fem/tests/circuits_transient_stranded_full_coil` 的
     参考值对比（该测试通过，但其线圈几何/匝数与我们的不同，
     不能直接外推 N 标度）
2. 做一个**单匝（N = 1）的基准案例**：N = 1 时 `N_j = 1/A_coil`，
   若 FEM/解析 比值回到 ~1，则确认是 `N_j` 幂次错误。
3. 修好之后重跑，再用 §16.1 的检验复核。

**产物**：`check_emf_vs_analytic.py`、`hpc_results_z024/_emf_crosscheck.json`

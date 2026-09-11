# 磁体自由落体 FEM 仿真工程

> 圆柱形永磁体从 z=+0.110 m 高度自由释放，通过线圈/铜区，落到 z=-0.05 m。
> 三维静磁 FEM（Elmer 26.2）解算 B 场，结果用 FreeCAD 时序动画展示。
>
> **本工程只保留 FEM 真解，解析解（oscilloscope.py）已删除。**

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

### 三个 body geometry（由 `solenoid3d.py --config` 切换）

| `--config`         | sif_suffix         | Body 1 名称        | 角色 |
|---|---|---|---|
| `no-coil`          | `no-coil`          | `AirInside`        | 仅空气参考 |
| `stranded-coil`    | `stranded-coil`    | `StrandedCoil`    | 绞合线圈等效块体 |

### 物理（FEM 真解，Elmer 26.2 静磁）

```
magnetisation      : M = 1.2e6 A/m   (N52 NdFeB approximation)
permeability       : mu_r = 1.05      (linear B-H)
equation           : curl(1/mu * curl(A)) = J_source
                    + Whitney AV edge-element basis (linear tetra)
BC                 : A = 0            on outer air surface
body force         : J_z = 5.0e6 A/m^2 in coil block (drives the field)
output             : Magnetic Flux Density 1/2/3, AV 1/2/3, Current Density 1/2/3
```

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
| `solenoid3d.py` | 7 KB | 几何生成（gmsh Python API），3 config |
| `case_simple.sif` | ~3 KB | Elmer 26.2 静磁 SIF |
| `config.json` | ~3 KB | 单一真相源（物理、几何、曲线） |
| `geom_preview.FCMacro` | 3 KB | FreeCAD 几何预览宏（双击即用） |
| `visualize_freecad_macro.py` | 7 KB | FreeCAD 时序动画（带 Qt slider） |
| `results_viewer.FCMacro` | 5 KB | FreeCAD 时序动画（双击即用） |
| `run_tests.ps1` | 5 KB | 端到端测试（4 步骤） |
| `clean.ps1` | 2 KB | 清理所有中间产物 |
| `tests/test_mesh.py` | 7 KB | pytest：网格完整性 |
| `tests/test_render.py` | 2 KB | pytest：pyvista 渲染 |

---

## 4. 运行流水线

### 一键测试（推荐先跑这个）

```powershell
cd c:\Users\JosephVStalin\Desktop\PysProject
.\run_tests.ps1
```

### 流水线步骤 (4 步)

| # | 动作 | 输出 |
|---|---|---|
| 1 | `python solenoid3d.py --config stranded-coil` | `model3d.msh` (~1.4 MB) |
| 2 | `ElmerGrid 14 2 model3d.msh -out mesh -autoclean` | `mesh/` (~5 MB) |
| 3 | `ElmerSolver case_simple.sif` | `results/case_t0001.vtu` (~900 KB) |
| 4 | `test_mesh.py` + `test_render.py` | `test_outputs/mesh_preview.png` |

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

---

## 6. 几何、材料、电路

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

---

## 7. 文档导航

| 文档 | 说明 |
|---|---|
| `README.md` | 本文档（项目入口） |
| `CHANGELOG.md` | 版本变更历史（1.0.0 .. 2.0.0） |

| `TROUBLESHOOTING.md` | 常见问题排查 |
| `docs/ARCHITECTURE.md` | 内部架构图（FEM data flow） |

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
| `N_turns` | int | yes | 线圈匝数。`0` 表示无导体（开路参考） |
| `wire_diameter_m` | float/null | when N>0 | 线材直径 (m)。如 0.7e-3 = 0.7 mm |
| `wire_conductivity_S_per_m` | float/null | when N>0 | 线材电导率 (S/m)。铜 = 5.96e7 |
| `R_load_ohm` | float \| `"inf"` | yes | 外部负载电阻。`"inf"` 表示开路 |
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

# 变更日志

本工程的所有显著变更记录于此。
格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。
## [1.1.0] - 2026-09-11

### Changed
- **Experiment switched from spring-mass-damping to magnet free fall.**
  The magnet is now released at z=0.110 m and falls under gravity +
  air drag + Lenz drag.  No more spring / anchor / clamped-boundary.
- `solenoid3d.py` rebuilt without spring + anchor primitives; physical
  groups reduced to 3 (bore / magnet / air).
- `oscilloscope.py` rewritten to load `config.json` as the single
  source of truth and to compute the new ODE `m*z_ddot = m*g - c*v`.
- `config.json` introduced as the canonical configuration: physics
  constants, magnet / coil geometry, 3 body configs, channel list,
  mesh sizes, plus the `passage_time_bar` extras block.
- `run_tests.ps1` and `one_click.ps1` updated so the ELMER_HOME
  search list now starts with `./elmer262` (project-bundled).

### Added
- **Bundled Elmer 26.2 inside the project**: `./elmer262/` (~250 MB)
  removed from `C:\elmer262` and moved into the repo so the whole
  thing is Docker-portable (just bind-mount the project dir).
- **Passage-time bar chart** at the bottom of `dashboard.png`:
  bars for empty / copper / coil showing how long the magnet takes
  to fall from `z_release_m` to `z_target_m` (configurable in
  `config.json` under `extras.passage_time_bar`).  A red dashed
  line marks the vacuum free-fall reference `t = sqrt(2h/g)`.

### Removed
- `C:\elmer262` (Elmer 26.2 install)  --  now lives in `./elmer262`.
- Spring (`Body 4`) and anchor (`Body 5`) primitives; "clamped"
  boundary condition on the anchor plate.


## [1.0.0] - 2026-09-11

### 新增
- **Elmer 26.2 作为静磁求解核心**
  - 使用 MSYS2 mingw64 工具链 (gcc 16.1.0 + gfortran 16.1.0 + cmake 4.3.3 + ninja 1.13.2) 编译成功
  - 复用 Elmer 26.1 安装的 libopenblas.dll 作为 BLAS / LAPACK 依赖
  - 安装位置：C:\elmer262\bin\ElmerSolver.exe + C:\elmer262\elmergrid\src\ElmerGrid.exe + C:\elmer262\share\elmersolver\lib\* (procedure DLLs)
- 简化的 `case_simple.sif` 配置
  - 删除 Initial Condition 块（SOLVER.KEYWORDS 未注册 InitialCondition 关键字）
  - Procedure = "MagnetoDynamics" "WhitneyAVSolver"（26.2 将主 procedure 改名为 WhitneyAVSolver）
  - BC 用分量形式 Magnetic Vector Potential 1/2/3
  - 添加 Body Force 1 (Current Density 3 = 5.0e6) 产生非零磁场解
  - 添加 Solver 2 "ResultOutput" 导出 case.vtu
- `solenoid3d.py` 修复 gmsh 4.x MSH 2.2 网格复化问题
  - Mesh.ElementOrder=1 + Mesh.SecondOrderIncomplete=1 + Mesh.Algorithm3D=4 (MMG3D)
  - 使 gmsh 输出线性网格 (type 2+4) 而不是高阶 (type 11+9)
- `one_click.ps1` + `run_tests.ps1` 适配 Elmer 26.2 安装位置

### 修复
- 完整 FEM 流水线合龙（5 步全通过）
- 追查 `Load.c` 源码确定 Elmer 26.2 procedure DLL 加载逻辑
- 追查 `SOLVER.KEYWORDS` 确定 26.2 新调用占位符
- 追查 `elements.def` 确定 element type 510 边界元使用问题

### 已知问题
- Elmer 26.2 `WhitneyAVSolver` 不直接支持 10-node tetra 网格。
  PElementBase::TetraNodalPBasis 仅支持 {1,2,3,4} 节点，
  对 type 510 (p2 10-node) 在 Piola transform 路径上报 "Unknown node"。
  工作解：保持 linear mesh (type 504)，由 WhitneyAVSolver
  内部 Piola transform 处理边基。

## [未发布]

### 新增
- 完整的中文文档（README、TROUBLESHOOTING、ONE_LINER）
- `CHANGELOG.md` 与 `docs/ARCHITECTURE.md`
- `clean.ps1` —— 一键清理所有运行产物
- `run_tests.ps1` + `tests/test_mesh.py` + `tests/test_render.py`
  —— 完整 FEM 健全性测试流水线（不依赖 ElmerSolver）
- 测试输出 `test_outputs/mesh_preview.png`（pyvista 渲染）
- `.gitignore` —— 排除生成产物
- `requirements-dev.txt` —— `requirements.txt` 的便捷别名
- `LICENSE`（MIT）

### 变更
- `case_simple.sif` 头部加上详尽的状态注释，解释 Elmer 26.1
  procedure DLL 加载路径问题与关键字表
- `one_click.ps1` 头部注释改为中文
- README 改为完整方法文档，含 4 阶段流水线图

### 修复
- `solenoid3d.py`：用包围盒（bounding-box）替代几何中心
  （centre-of-mass）做体分类，修复 fragment 后的误判
- `circuit.definitions` / `circuit_open.definitions`：把 `$` 注释
  改为 `!`，避免被 Elmer 26.1 当 MATC 表达式解析而报错
- `case_simple.sif`：用矢量形式关键字 `Magnetic Vector Potential 1/2/3`
  替换 scalar `AV`，与 `SOLVER.KEYWORDS` 注册严格一致

## [0.1.0] - 2026-09-08

### 新增
- 初版工程结构（13 个文件）
- gmsh 几何 + ElmerGrid 网格 + ElmerSolver 求解 + FreeCAD / pyvista
  可视化端到端流水线
- Stranded 线圈电路（闭路 + 开路两个对照）

### 已知问题
- Elmer 26.1 在 PowerShell 调用下间歇性出现
  `Can't find procedure [MagnetoDynamics]` 错误
  （仅 cmd.exe 启动稳定）

[未发布]: https://example.com/pysproject/compare/v0.1.0...HEAD
[0.1.0]: https://example.com/pysproject/releases/tag/v0.1.0

# 变更日志

本工程的所有显著变更记录于此。
格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。
## [3.5.0] - 2026-09-12

### Added
- **`make_sif.py --solver {umfpack,hypre-ams}` —— 绕过 10 万棱边墙的关键。**
  此前 SIF 在 Solver 2 上硬写 `Linear System Solver = Direct` +
  `Linear System Direct Method = UMFPACK`，而 UMFPACK 是直接稀疏 LU，
  内存在 ~10 万棱边处按 O(n²) 爆炸（HPC 上表现为
  `Error occurred in umf4num: -1.0000000000000000`）。

  新选项把它换成 **BiCGStab + Hypre AMS**：

  ```elmer
  linear system use hypre          = Logical True
  Linear System Solver             = Iterative
  Linear System Symmetric          = Logical True
  Linear System Preconditioning    = AMS
  Linear System Method Hypre Index = Integer 7   ! 7 = BiCGStab
  ```

  关键字**逐条抄自上游 `fem/tests/mgdyn_hypre_ams/case.sif`**，该算例头部
  写明 "This test case with BiCGStab as solver, AMS as preconditioner"。

  `--solver umfpack`（默认）输出与模板**逐字节相同**，已用
  `Compare-Object` 验证 —— 默认行为零变化。

- **`tests/test_sif_solver.py` —— 把 `--solver` 的两种静默失效锁死。**
  13 个测试，零依赖（不需要 Elmer/gmsh/meshio），已接入
  `run_tests.ps1` 与 `run_tests.sh` 的第 4 步。覆盖：

  | 测试 | 防止的失效模式 |
  |---|---|
  | `test_umfpack_is_byte_identical_to_the_template` | 默认路径被悄悄改动 |
  | `test_no_duplicate_keys` | **重复键**（Elmer 取最后一个） |
  | `test_max_iterations_is_exactly_5000` | 迭代版的 5000 被残留的 1000 压回 |
  | `test_only_solver2_is_modified` | 误伤 Solver 1/3 |
  | `test_stale_direct_comment_is_dropped` | 注释与求解器自相矛盾 |

  **这些测试经过变异验证**，不是摆设：把 `_RE_DIRECT` 退回"只替换前两行"的
  错误版本后，两个测试立刻失败 ——

  ```
  [FAIL] test_max_iterations_is_exactly_5000: expected exactly one "5000", got ['5000', '1000']
  [FAIL] test_no_duplicate_keys: duplicate keys in Solver 2:
         ['linear system convergence tolerance', 'linear system max iterations']
  ```

  所以它们确实能拦住我手工发现的那个 bug。

- **`hpc/build_elmer.sh hypre` —— 无 GPU 的推荐配方。**
  自动引导编译 hypre（仅需 MPI，不需要 MUMPS 那套
  BLACS/ScaLAPACK/METIS），再以 `-DWITH_Hypre=TRUE -DHYPRE_ROOT=...`
  配置 Elmer。参数依据 `cmake/Modules/FindHypre.cmake` 的实际查找逻辑：
  头文件 `HYPRE.h`、库 `libHYPRE.so`、提示变量 `HYPRE_ROOT`。

- **构建期特性校验 `verify_features()`。** 见下方 Fixed 第 ① 条 —— 这是
  本次最重要的修复，因为它让"静默失效"不再可能。

### Fixed
- **⚠️ `build_elmer.sh` 里 `-DWITH_MUMPS=TRUE` 是一个不存在的变量，
  MUMPS 被静默地从未启用。** Elmer 的 cmake 选项是**混合大小写**：

  ```cmake
  SET(WITH_Mumps  FALSE CACHE BOOL "Use Mumps sparse direct solver")
  SET(WITH_Hypre  FALSE CACHE BOOL "Use Hypre linear algebra library")
  ```

  而 **cmake 会忽略无法识别的 `-D` 变量**，只打一句

  ```
  Manually-specified variables were not used by the project:
    WITH_MUMPS
  ```

  于是 `WITH_Mumps` 保持默认 `FALSE`，构建**照常报成功**，产出的却是一个
  只有 UMFPACK 的 Elmer —— 正是那个解不了大算例的配置。cpu/rocm/cuda
  三个配方全都中招。

  现在 `verify_features()` 在 configure 之后回读 `CMakeCache.txt`，
  把 `WITH_UMFPACK / WITH_Mumps / WITH_Hypre / WITH_ROCALUTION / WITH_AMGX`
  的实际取值打印出来，缺任何一个就直接 `exit 1`；`hypre` 配方还会在编译
  完成后 grep `config.h` 里的 `HAVE_HYPRE`，确认 `SolveHypre.c` 真的被编
  进去了。**不再相信"构建成功"这个信号。**

- **`make_sif.py --solver hypre-ams` 的两个正则缺陷**（自己踩到并修掉）：
  一是**没有处理行首缩进** —— SIF 里键名前面有两个空格，而 `^Linear
  System Max Iterations` 这种锚定写法永远匹配不上，会抛
  `could not raise ... Max Iterations`；二是**只替换了整个求解器块的前两
  行**，把后面的 `Convergence Tolerance` / `Max Iterations = 1000` 留在
  原地，形成**重复键**，而 Elmer 取最后一个 → 迭代版的 5000 会被悄悄压回
  1000。现在正则吃掉整个四行块，并已用精确键扫描确认 3/3/3 无重复。
  同时会删掉模板里那句 "DIRECT is used because the iterative route ... 
  diverges" 的注释 —— 它在 AMS 模式下自相矛盾；删除动作带存在性校验，
  模板漂移会报错而不是静默产出自相矛盾的 SIF。

### Changed
- **DCU 路线正式关闭，`hypre` 成为无 GPU 的推荐配方。**
  该账号没有加速卡授权：`kshctest02` 是唯一接受作业的分区，而其节点
  `Gres=(null)`，物理上就没有卡。因此 rocALUTION 出局，`hpc/notes.md` 新增
  9.6 节记录这个结论与替代方案。
- **`hpc/notes.md` 纠正一处错误结论。** 原文称

  > edge elements need a curl-conforming preconditioner that Elmer doesn't ship

  这是**错的**。BiCGStab + ILU 在棱边元上发散是 **ILU 的性质**，不是 Elmer
  缺少预条件子：ILU 是为 H¹（节点）问题设计的，对 H(curl) 就是不对。
  Elmer 有 **Hypre AMS**（`fem/src/SolveHypre.c` 中的
  `HYPRE_AMSCreate` / `HYPRE_AMSSetDiscreteGradient` /
  `HYPRE_AMSSetInterpolations`，容器里还带专门的 `HYPRE_IJMatrix G, Pi`
  成员，从网格实际组装离散梯度与棱-节点插值）。唯一的原因只是
  `WITH_Hypre` 默认 `FALSE`，整条代码路径被编译掉了。
  原文紧接着的 "Hypre AMG needs rebuilding with a solver that maps the
  trace to HYPRE_Solver" 同样不成立 —— 映射代码早就写好了，缺的只是链接。

- `hpc/should_run_locally.py` 的 `change-solver` 判定现在给出可执行命令
  （`hpc/build_elmer.sh hypre` + `make_sif.py --solver hypre-ams`），
  而不是把用户丢在 "Pardiso or Hypre" 这种悬空建议上。

- **弹簧-质量-阻尼实验已恢复，参数全部走 `config.json`。**
  运动律从自由落体换成阻尼谐振子：

  ```
  m z'' = -m g - k (L - L0) - c z' - F_lenz
  z(t)  = z_eq + A e^(-gamma t) [cos(wd t) + (gamma/wd) sin(wd t)]
  ```

  `config.json -> [spring]` 里的默认值（自洽、可直接跑）：

  | 参数 | 值 |
  |---|---|
  | `mass_kg` / `stiffness_N_per_m` / `damping_N_s_per_m` | 0.5 / 220 / 0.8 |
  | 导出：`omega0` / 周期 / 频率 | 20.976 rad/s / 0.2995 s / 3.34 Hz |
  | 导出：`gamma` / `omega_d` / Q | 0.8 / 20.961 / 13.1 |
  | `z_eq_m` / `z_release_m` | 0.020（线圈中心）/ 0.045 |
  | 导出：静伸长 / `L_eq` / `L0` | 22.3 mm / 64.0 mm / 41.7 mm |
  | 导出：幅度 A / 磁体中心行程 | 25 mm / −0.005…+0.045 m |
  | 导出：弹簧长度 / 伸缩比 | 39…89 mm / 0.94×…2.13× L0 |
  | 锚板 / 弹簧管 | z 0.099–0.101 / R 6–8 mm, z 0.039–0.099 |

- **`spring_model.py`** —— 弹簧数学的**唯一实现**，`solenoid3d.py`（几何）、
  `make_sif.py`（MATC 运动律）、`oscilloscope.py`（参考曲线）、
  `verify_spring.py`（验证）全部从它 import，数值不会各自漂移。
- **`make_sif.py`** —— 从 `config.json` 生成 `case_transient.sif`：
  `motion_mode = spring|free_fall` 决定 MATC 表达式，
  `experiment.dt_s` / `t_end_default_s` 决定时间步。config 现在是唯一权威。
  切换模式只需改一个字段，不用手改 SIF。
- **`test_outputs/verify_spring.py`** —— 把 FEM 网格运动与解析谐振子解对比。
- `oscilloscope.py`：z(t)/v(t) 面板在弹簧模式下叠加解析弹簧解。

### Changed
- `experiment.motion_mode` 新增（`"spring"` / `"free_fall"`），默认 `"spring"`。
- `magnet.z0_m/z1_m` 从 0.060/0.090 改为 **0.030/0.060**，让网格中的磁体位置
  等于弹簧释放点，预设位移从 0 开始。
- `experiment.t_end_default_s` = 0.6 s（两个弹簧周期），`dt_s` = 1e-3 s。
- `run_tests.ps1` 第 3 步先跑 `make_sif.py`；第 5 步在弹簧模式下追加
  `verify_spring.py`。
- **`Dockerfile` 重写为可自洽构建的镜像（`pysproject:3.5.0`，2.28 GB）。**
  旧版有一处**不可能成功**的写法：`apt-get install elmerfem`。Debian 12
  仓库里根本没有这个包（在 `python:3.11-slim` 内 `apt-cache search elmer`
  只返回一个无关的 perl 模块）。新镜像改成三阶段构建：

  | 阶段 | 内容 |
  |---|---|
  | `elmer` | 编译 Elmer 26.2.1（源码取自 GitHub tag `release-26.2.1`） |
  | `wheels` | 预编译全部 Python wheel |
  | `runtime` | `python:3.11-slim` + `/opt/elmer` + 离线 wheel 安装 |

  编译选项**逐条照抄** `elmer262/CMakeCache.txt` —— 即产出全部已验证
  结果的那份 Windows 构建：

  ```
  WITH_UMFPACK     TRUE      <- 唯一开启的求解器开关
  其余 WITH_*      FALSE     （无 MPI / MUMPS / OpenMP / ROCALUTION / Hypre / MKL）
  ```

  SIF 里的 `Linear System Solver = Direct` 落在 UMFPACK 上，所以只有
  保持这个开关一致，容器才会复现宿主机的数值。构建时自检 `ElmerSolver
  -version` 必须报 `26.2`，并对 `/opt/elmer` 下**每一个**二进制和求解器
  `.so` 做 `ldd` 扫描，有未解析依赖就直接构建失败。

- **`docker save` 导出镜像包 `pysproject-3.5.0.tar`（611.9 MB）**，
  已做 `docker load` 往返验证（镜像 ID 一致）。离线机器可直接导入，
  无需联网重建。

- **`.gitattributes` 固化行尾。** 此前仓库里**所有**文件都是 CRLF，
  导致 shell 脚本和 Dockerfile 在 Linux 上直接语法错误 ——
  行末的续行符 `\` 后面跟的是 CR 而不是换行：

  ```
  $ bash -n run_tests.sh
  run_tests.sh: line 35: syntax error near unexpected token `"..."'
  ```

  现在 `*.sh` / `*.slurm` / `Dockerfile` 强制 LF，`*.ps1` / `*.bat`
  保持 CRLF。同时把仓库里现存的 10 个脚本（含 `hpc/*.sh`、`hpc/*.slurm`）
  一次性转成 LF，全部通过 `bash -n`。



### Fixed
- **SIF 里写死的宿主机绝对路径（阻断容器与 HPC 运行）**：`case_transient.sif`
  里是

  ```
  Mesh DB "c:\Users\JosephVStalin\Desktop\PysProject" "mesh"
  Results Directory "c:\Users\JosephVStalin\Desktop\PysProject\results"
  ```

  只要把算例挪到别处就必然失败：

  ```
  ERROR:: LoadMesh: Requested mesh > c:\Users\...\PysProject/mesh < does not exist!
  STOP 1
  ```

  容器里就是这样撞墙的，HPC 的 scratch 目录也会撞同一面墙。
  `make_sif.py` 现在每次生成时**强制**重写这两行为相对路径
  （`Mesh DB "." "mesh"`、`Results Directory "results"`，Elmer 按自身
  工作目录解析 `.`），并且是幂等的 —— 手工改模板没有意义，因为下次
  生成就会被重新规整。

- **`H_mag_m` 语义歧义**：`config.json` 里 `H_mag_m = 0.015` 是**半高**
  （轴上偶极公式用），而磁体实际跨度是 `z1_m - z0_m = 0.030`。`spring_model.py`
  现在从 z 跨度推导全高，并加了醒目注释。

### Verified
- **网格精确跟随弹簧轨迹：误差 1e-12 m（皮米级），0.0000 % 幅度。**
  30 步验证运行（264 s）：

  ```
  frame      t(s)     z_meas(m)      z_theory      err(m)     err/A
      0    0.0010      0.043593      0.043593   0.000e+00  0.00e+00
     15    0.0160      0.042216      0.042216   3.289e-13  1.32e-11
     29    0.0300      0.038885      0.038885   1.111e-12  4.44e-11
  worst |err| = 0.000 um   (0.0000 % of A)   [PASS]
  ```

- 过程中**抓出两个会得出错误结论的验证器 bug**（都不是求解器的错）：
  1. **节点选择**：`r < 0.7 R_mag 且 z 在区间内` 这个过滤器在弹簧模式下**错**了，
     因为磁体（z 0.030–0.060）与线圈内孔（z 0–0.040, r<20 mm）**重叠**，
     过滤器把内孔空气节点（`meshrelax = 0`，根本不动）也算了进去，
     得出**假的 13 % 衰减**。改用 `meshrelax > 0.9999` 作为磁体判别标准。
  2. **帧时间约定**：帧 k 对应 `t = (k+1)·dt`，不是 `k·dt`。用错会得到
     `err = -v·dt`，看起来**正好像滞后一个时间步**。这条在自由落体和弹簧
     两种模式下都已数值确认。

- **弹簧对场没有影响**（R 6–8 mm、`mu_r = 1`、位于线圈内孔轴线上），
  所以"弹簧版本"本质上 = 同一套网格 + 换运动律，无需重新建模弹簧网格。
  `[spring].include_in_mesh = false` 就是基于这个结论的默认值。



### Added
- **HPC workflow** (`hpc/`) — the project can now run the transient solves on
  `cancon.hpccube.com` instead of this laptop.  New files:

  | file | purpose |
  |---|---|
  | `hpc/make_case.py` | build one study case (config + gmsh mesh + SIF) |
  | `hpc/check_motion.py` | verify the RigidMeshMapper delivers the prescribed motion |
  | `hpc/run_case.slurm` | solve a whole case in one job |
  | `hpc/run_window.slurm` | solve ONE TIME WINDOW (quasi-static → steps are independent) |
  | `hpc/submit_plan.sh` | submit cases as cost-balanced windows (`--cancel` to stop) |
  | `hpc/pull.ps1` | download VTU frames + logs |
  | `hpc/sync.ps1` | upload cases / scripts, check status |
  | `hpc/should_run_locally.py` | **decide local vs HPC per case** |
  | `hpc/notes.md` | the full build/debug log and calibration data |

- **`hpc/should_run_locally.py`** — a calibrated decision tool.  Sample output:

  ```
  case                  edges      frames  laptop      HPC     -> runner
  L020_ri020_coarse     73,935      56      0.6 h      1.2 h   -> local
  L020_ri020_fine       98,494      56      4.7 h      6.3 h   -> local
  L040_ri020_fine      128,890      66      9.5 h     12.7 h   -> local
  L040_ri017_fine      279,898      66     44.9 h     59.8 h   -> local
  L080_ri020_fine      193,185      86     27.8 h     37.1 h   -> local
  L160_ri020_fine      250,269     126     68.5 h     91.3 h   -> change-solver
  ```

  The rule it encodes: **the laptop is ~1.8x faster per core and its UMFPACK
  has no ABI bug**, so it is the default; the HPC is only used when the
  laptop would need more than an overnight run (48 h) *and* the HPC can
  actually solve the case.

### Changed
- `solenoid3d.py`: the `--config` path always read the config file **next to
  the script** (`Path(__file__).with_name("config.json")`), so a study case
  directory was silently ignored and every sweep produced an IDENTICAL mesh.
  It now prefers `./config.json`.  This alone had been making the whole
  mesh-refinement sweep a no-op.
- `solenoid3d.py`: coil geometry (`S_Z0/S_Z1/S_IN/S_OUT`) is now read from
  `config.json -> [coil]` instead of being hard-coded, so the coil length and
  bore radius are sweepable.
- `solenoid3d.py`: `--config` choices are de-duplicated (order-preserving),
  and the help lists the curves that share each suffix.
- `case_transient.sif` may be re-used as a template: `hpc/make_case.py`
  patches the mesh path, results dir, timestep and motion law.

### Investigated / not fixed (documented as a hard limit)
- **The HPC's Elmer 26.2 cannot solve more than ~100 k edge DOFs.**
  `WhitneyAVSolver` + UMFPACK dies at step 0 with

  ```
   Error occurred in umf4num:   -1.0000000000000000
  ```

  This is **not** an out-of-memory condition (the job peaks at 2.7 GB and
  asking for 110 GB changes nothing) — it is an ABI mismatch between
  gfortran 7.3.1 and the UMFPACK C interface via the
  `/usr/lib64/liblapack.so.3.4.2` shim.  Verified limits:

  | case | edges | result |
  |---|---|---|
  | L020_coarse | 69 626 | 56/56 steps OK |
  | L020_fine | 98 494 | 28/56 steps then cancelled |
  | L040_coarse | 97 960 | **fails** |
  | L040_fine | 122 000 | **fails** |
  | L080_fine | 183 658 | **fails** |
  | L160_fine | 238 759 | **fails** |

  Workarounds attempted and their outcome:
  - rebuilding with `WITH_OpenMP=TRUE` — built fine, changed nothing;
  - iterative `BiCGStabL + ILU1` — **diverges** at step 0 (edge elements
    need a curl-conforming preconditioner Elmer does not ship);
  - `--mem=110000M --cpus-per-task=32` — no effect;
  - size-threshold hypothesis tested by running the SAME geometry at
    coarse and fine resolution — both failed, so it is size-driven, not
    geometry-driven.

  **The only real fix is Pardiso or Hypre.**  See `hpc/notes.md`.

### Verified
- **79 real FEM frames** were produced on the HPC (51 for `L020_ri020_coarse`,
  28 for `L020_ri020_fine`) and downloaded to `hpc/cases/*/results/`.
- Motion check on the HPC: the magnet displacement is exactly linear in the
  frame index (`dz = -v·k·dt`, residual ~1e-16), confirming that a
  constant-velocity prescription has **no** RigidMeshMapper lag — the lag
  seen earlier is caused by *acceleration*, not by `dt`.
- `run_window.slurm`'s time-window splitting is exact, because every body
  in the model has `Electric Conductivity ~ 0` (coil 0.0, air/magnet 1e-12),
  so the transient A-formulation loses its `sigma*dA/dt` term and each
  timestep is an independent magnetostatic solve.



### Fixed
- **`results/scope.png` 排版错误 —— 所有 12 个面板被挤在左半边。**
  底部那行需要左右各放一个图，所以 gridspec 开成了 `ncols * 2` = 8 列；
  但面板循环用的是 `gs[r, c]`，`c` 只到 3，于是 12 个面板全挤进左边
  4 列、右半边整片空白。改为 `gs[r, c * 2:(c + 1) * 2]`（每个面板跨 2 列）。

  校验（渲染后读 axes 的 `get_position()`）：

  | | 修复前 | 修复后 |
  |---|---|---|
  | 面板左边缘 | 0.043 / 0.16 / 0.28 / 0.40 | **0.043 / 0.312 / 0.582 / 0.851** |
  | 最右边缘 | ~0.54（右半空） | **0.992（满宽）** |

- **感应电流 `I(t)` 面板只画了主配置。** 现在按 `[curves]` 里每个
  **闭路**配置各画一条 `I = EMF(t) / R_total`，直接对比铜/铝/负载。
- **制动系数 `c(z)` 查错了位置 —— 楞次阻尼一直按一个常数值算。**
  `flux_vs_z()` 返回的横坐标是磁体**位移**（从 0 开始），而
  `coil_transit_times()` 传给它的 `z_start` 是**绝对**高度（0.0752 m）。
  于是 `np.interp(zc, zs, dps)` 每次都落在区间外被 clamp 到端点值，
  `c` 成了常数。改为在 `main()` 里先算 `z_abs = z + z_center0` 再建表，
  线圈平面/释放高度全部统一到绝对坐标。

  同一处还加了**事件时刻的步内插值**（原来分辨率就是一个 RK 步 20 us，
  而开/闭路之差只有 1e-10 s，根本分辨不出来）。

  校验：数值积分 vs 一阶微扰理论 `dt = (1/(m t))∫∫c(z_ff(u))·u du ds`，
  在 4 个数量级的 `c` 上比值都是 **1.000**：

  | N | R_tot | c_peak | 数值 Δt | 理论 Δt | 比值 |
  |---|---|---|---|---|---|
  | 50 | 10.31 Ω | 4.637e−07 | 0.1264 ns | 0.1264 ns | 1.000 |
  | 50 | 1 Ω | 4.781e−06 | 1.3033 ns | 1.3033 ns | 1.000 |
  | 50 | 0.01 Ω | 4.781e−04 | 130.33 ns | 130.33 ns | 1.000 |
  | 500 | 0.5 Ω | 9.562e−04 | 260.66 ns | 260.66 ns | 1.000 |
  | 5000 | 0.5 Ω | 9.562e−02 | 26094.6 ns | 26066.1 ns | 1.001 |

- **闭路 vs 开路：阻尼确实存在，但只有 ~0.13 ns。** 之前表格里两个配置
  看起来一模一样，不是没实现，而是量级太小（9.62 ms 上差 1.3e−10 s）。
  `scope.txt` 现在直接列出每个配置相对开路曲线的 ns 级偏移，以及
  “为什么这么小”的定量原因（磁通只链到边缘部分，见下）。
  （`{no-coil,stranded-coil,stranded-coil,stranded-coil}`）：多条曲线共用
  同一个 `sif_suffix` 时没有去重。改为 `dict.fromkeys()` 保序去重，
  并在 help 里列出曲线名。
- **`scope.txt` 中文标签错位**：等宽对齐按“字符数”算，CJK 占 2 列。
  新增 `_w()` / `_pad()`（用 `unicodedata.east_asian_width`），
  标签列宽按实际显示宽度动态计算。
- `run_tests.ps1` 末尾的 `Format-Table` 在脚本被管道重定向时抛
  `FormatEntryData ... 无效`；改为逐行格式化输出，并显式 `exit 0`。

### Added
- **三个新配置**（`config.json` → `[curves]`），并补齐文档：

  | key | 说明 | σ (S/m) | R_wire | R_load | R_total |
  |---|---|---|---|---|---|
  | `copper_closed` | **铜线闭路** | 5.96e7 | 0.310 Ω | 10 Ω | 10.31 Ω |
  | `aluminum_closed` | **铝线闭路** | 3.50e7 | 0.527 Ω | 10 Ω | 10.53 Ω |
  | `aluminum_open` | **铝线开路** | 3.50e7 | 0.527 Ω | ∞ | ∞ |

  `empty`（无导体）保留为自由落体参考。三者共用 `sif_suffix =
  "stranded-coil"` —— 几何只有两个变体，材料与电路参数全部走后处理，
  **不需要为每个配置重跑 Elmer**。

- **`run_tests.ps1` 集成启动命令**，成为唯一入口：

  | 参数 | 作用 |
  |---|---|
  | `-Config <sif_suffix>` | 选择要建网格/求解的几何（默认 `no-coil`），取值由 `config.json` 自动推导并校验 |
  | `-All` | 对 `config.json` 里所有 `sif_suffix` 各跑一遍 |
  | `-NoSolve` | 跳过第 1–3 步，只在现有 `mesh/`+`results/` 上重画图（秒级 vs 20 分钟） |

  开头打印 `START COMMAND` 摘要（求解的几何 / 参与对比的曲线），
  结尾打印可直接复制的命令。

## [3.2.0] - 2026-09-11

### Fixed
- **线圈被误加了直流电流 —— 已改为开路。** `Body Force 1` 里
  `Current Density 3 = 5.0e6` A/m²，所以线圈自带的静磁场（约 1.2 T）
  完全盖住了磁体的信号：环面上 `B_z` 的 min/max 在**每一帧都逐位相同**，
  `Phi` 只是在一条大直流基线上抖动 9 %。
  这是一个感应实验，绕组必须是开路的 —— 现在
  `Current Density 1/2/3 = 0.0`，唯一场源是磁体（`Material 2`），
  感应电流仍按 `I = EMF / R_total` 后处理得到。

  修正前后：

  | 量 | 修正前（有直流） | 修正后（开路） |
  |---|---|---|
  | 环面 `B_z` 范围 | −1.20 … +0.70 T（冻结） | +1.8e−05 … +2.16e−03 T |
  | `Phi_max` | 7.75e−04 Wb·turn（含直流基线） | **7.62e−05 Wb·turn** |
  | `EMF_max` | 1.3229e−03 V | 1.3229e−03 V（本来就对，见下） |
  | `c_peak` | 4.637e−07 N·s/m | 4.637e−07 N·s/m |

  `EMF` 和 `c_peak` 修正前后一致是**正确**的：直流基线是静态的，
  对 `dPhi/dt` 与 `dphi/dz` 都没有贡献，所以之前只有 `Phi` 的
  **零点**是错的，斜率一直是对的。

### Added
- **新图表：各配置下线圈通过时间（coil transit timing）。**
  `oscilloscope.py` 底部右侧新增一个甘特式面板：

  * 四条特征时刻（由 FEM 磁通推出的制动轨迹上读取）：
    `head-in` 磁体头部（下端面）到达线圈上端面、
    `tail-in` 磁体尾部（上端面）到达线圈上端面、
    `head-out` 头部离开线圈下端面、
    `tail-out` 尾部离开线圈下端面；
  * **深色条 = 用户要求的区间 `尾部进入 → 头部离开`**；
  * 浅色底衬 = 完整穿越 `head-in → tail-out`。

  `[curves]` 里的每个配置（`empty` / `coil` / `coil_high_R`）各一行，
  同时写入 `results/scope.txt` 表格与 `results/scope.json`
  的 `coil_transit` 数组。

- 制动模型：磁通由 FEM 给出 `phi(z) = <B_z>(z) * A_coil`，再对每个
  配置积分 `m z'' = -m g - c(z) z'`，其中
  `c(z) = (N^2 / R_tot) * (dphi/dz)^2`（楞次制动，N·s/m）。
  N = 0 或 R = inf 退化为自由落体。

### Changed
- `case_transient.sif`：`Timestep Intervals` 100 → **150**（0.15 s）。
  原窗口只覆盖 49 mm 行程，磁体尾部还停在线圈内部；要看到
  “尾部离开线圈” 必须走到 90 mm 行程（自由落体约 0.135 s）。

### Verified
- **电磁制动可以忽略**：`c_peak = 4.64e-07 N·s/m`（由 FEM 的
  `max|dphi/dz| = 4.37e-05 Wb/m` 得出），在 v = 1.08 m/s 时
  `F_lenz / (m g) = 1.0e-05 %`。这正好证明了把运动直接规定为自由落体
  （`Mesh Translate`）是合理的建模选择。
- **准静态成立**：线圈 `L/R = 7.2 us`，远小于 65 ms 的穿越时间，
  所以 `I = EMF / R` 成立，无需解 RL 电路的瞬态。
- 时间轴校验：四个特征时刻与自由落体解析值完全一致
  （`head-in 64.12`、`tail-in 101.14`、`head-out 110.76`、
  `tail-out 135.60` ms）；`尾部进入→头部离开 = 9.62 ms` 正好等于
  磁体（30 mm）完全落入线圈（40 mm）的那 10 mm 行程。
- 制动机制的标度（说明它确实接上了，只是量太小）：

  | N | R_tot | c_peak | F_lenz/mg | 尾部进入→头部离开 |
  |---|---|---|---|---|
  | 50 | 10.31 Ω | 4.64e−07 | 1e−05 % | 9.62 ms |
  | 500 | 0.5 Ω | 9.56e−04 | 0.021 % | 9.62 ms |
  | 5000 | 0.5 Ω | 9.56e−02 | 2.1 % | 9.68 ms |
  | 20000 | 1 Ω | 7.65e−01 | 16.8 % | 9.96 ms |

  要看出效果需要上万匝 —— 因为磁体是从线圈**内孔**穿过的，
  `phi_max/N` 只有 1.52e−06 Wb/turn。

## [3.1.0] - 2026-09-11

### Fixed
- **Mesh-motion attenuation - root cause found and fixed.**
  The `RigidMeshMapper` solves its `meshrelax` Laplace blending field on
  the *deformed* mesh at every step, so the prescribed translation is
  reproduced only as dt -> 0.  Measured attenuation:

      dt = 1.0e-3  ->  100.0 % of the prescribed travel (exact)
      dt = 5.0e-3  ->   91.6 %
      dt = 5.0e-2  ->   68.9 %

  `case_transient.sif` now uses `Timestep Sizes = 1.0e-3` with
  `Timestep Intervals = 100` (0.10 s of fall, 100 output frames):
  `achieved / ideal = 100.0 %`, `meshrelax = 1.0000` on the magnet,
  energy residual `5.4e-5 J`.
- Energy reference in the oscilloscope corrected: `PE = m g z` measured
  from the release point, so `E_tot = KE + PE` is now conserved (it
  previously drifted because `PE` used a ground-fixed reference).
- Passage-time target corrected to the coil **top** face (`z1_m = 0.04 m`),
  the first coil plane the magnet meets; the old target (coil bottom) was
  never reached inside the simulated window.

### Added
- **`oscilloscope.py` - rewritten to plot the FEM results.**
  Reads `results/case_t*.vtu` (not an analytical model) and derives, for
  every frame, all of the following and plots one panel each:

  | panel | quantity |
  |---|---|
  | z(t) | magnet displacement, tracked from the moving mesh (overlaid with ideal -1/2 g t^2) |
  | v(t) | numerical dz/dt |
  | a(t) | numerical d2z/dt2 (overlaid with -g) |
  | B_z(t) | mean axial flux density over the coil annulus |
  | \|B\|max(t) | peak field magnitude in the domain |
  | Phi(t) | flux linkage, N * <B_z> * A_coil |
  | EMF(t) | -N dPhi/dt (Faraday) |
  | I(t) | EMF / R_total, R_total = R_load + R_wire |
  | KE(t), PE(t), E_tot(t) | mechanical energy budget |
  | <meshrelax>(t) | relaxation field on the magnet (mesh-motion quality) |

  plus a passage-time bar with the ideal free-fall reference.
  Writes `results/scope.png`, `results/scope.txt`, `results/scope.json`.
- `config.json` gained a top-level `[coil]` block (z-range, inner/outer
  radius, mean turn length) so the oscilloscope can integrate the flux.
- `run_tests.ps1` back to 5 steps: the new step 5 runs the oscilloscope
  and `test_outputs/verify_fall.py`.

### Verified (dt = 1 ms production run, 100 frames, 771 s)
- `z_final = -4.904510e-02 m` vs ideal `-4.905000e-02 m` -> **100.0 %**
- `mean a = -9.663 m/s^2` vs `-g = -9.81 m/s^2`
- energy residual `5.4e-5 J` (relative 1.1e-4)
- passage time 65.00 ms vs ideal 64.12 ms (1.4 %)
- `|B|_max = 1.845 T`, `Phi_max = 7.65e-4 Wb-turn`, `EMF_max = 1.32 mV`,
  `I_max = 0.128 mA` (R_total = 10.31 ohm, N = 50)

### Notes
- The induced EMF is in the mV range because the magnet (R = 15 mm)
  passes through the coil *bore* (R_in = 20 mm): the winding only sees
  the fringe/return flux.  A coil with R_in < R_mag would give a much
  larger signal.


## [3.0.0] - 2026-09-11

### Changed
- **The solver is now TRANSIENT (was steady).**
  `case_simple.sif` (steady) was replaced by `case_transient.sif`.
  - `Simulation Type = Transient`, `Timestepping Method = BDF`,
    `BDF Order = 1`, `Timestep Sizes = 5.0e-3`, `Timestep Intervals = 30`
    -> 0.15 s of physical time, 30 VTU frames.
  - The falling magnet is driven by the **RigidMeshMapper** solver
    (`Exec Solver = Always`, so it runs at every timestep) plus a
    `Mesh Translate 3 = Variable Time / Real MATC "-0.5*9.81*tx*tx"`
    body force, i.e. the prescribed free-fall law z(t) = z0 - 1/2 g t^2.
  - The magnet's remanent magnetisation was ADDED to the material
    (`Magnetization 3 = 1.2e6` A/m).  It had been missing, so the
    previous "magnet" was only a permeable cylinder.
  - `MagnetoDynamicsCalcFields` was added back (as Solver 3) because
    `WhitneyAVSolver` does **not** emit the flux density in transient
    mode.  The VTU now contains `magnetic flux density`,
    `magnetic field strength` and `current density`.
  - `Nonlinear System Max Iterations` reduced 4 -> 1: the problem is
    linear (constant permeability), so extra Newton iterations just
    repeat the same solve.

### Fixed
- **Boundary conditions were silently NOT being applied.**
  `ElmerGrid ... -autoclean` renumbers boundary groups sequentially,
  so the gmsh tags 1001/1002 became Elmer indices **1/2**.  The old
  SIF targeted 1001/1002, i.e. nothing.  `case_transient.sif` now uses
  `Target Boundaries(1) = 1` (outer air) and `= 2` (magnet surface);
  `mesh/mesh.names` is the authoritative reference.
- **gmsh mesh sizes were being ignored.**  With
  `General.ExpertMode = 1` gmsh only honours `setSize` on **points**.
  `solenoid3d.py` now collects the corner points of each volume's
  boundary (recursively) and applies the coarse size first so the
  fine magnet/coil sizes win on shared nodes.  The magnet element
  count went from 56 to 1731.
- A new `MagnetSurface` physical group (gmsh tag 1002 -> Elmer index 2)
  was added by `solenoid3d.py`; it is required for the
  `Moving Boundary = Logical True` condition of the moving mesh.

### Added
- `test_outputs/verify_fall.py` - checks the achieved mesh motion
  against z(t) = z0 - 1/2 g t^2 and reports the relaxation attenuation.
- `test_outputs/verify_bfield.py` - compares the FEM axial flux density
  with the analytic cylinder value mu0*M*h/sqrt(R^2+h^2) = 1.0663 T.

### Verified
- Kinematics: with a coarse air mesh the prescribed law is reproduced
  to 4.9e-6 m over 150 frames.  With the refined mesh used for the
  production run the Laplace `meshrelax` blending attenuates the
  motion to 91.6 % of the prescribed value (documented, see README).
- Field: |B|_max = 1.574 T inside the magnet, and the mean axial B
  inside the magnet is 1.21 T versus the 1.066 T analytic centre value
  (the mean exceeds the centre value because B rises towards the pole
  faces) - physically correct.
- Runtime: 30 transient steps in 239 s (direct UMFPACK).

### Notes
- The iterative route (BiCGStabL + ILU1 with `Use Tree Gauge = True` and
  `Use Piola Transform = False`) is ~3x faster per step but diverges
  once the air mesh is distorted by the falling magnet; the direct
  solver is therefore used.


## [2.1.0] - 2026-09-11

### Removed (useless files cleaned up)
- `run.ps1` -- referenced a non-existent `solenoid3d.geo` and `case.sif`
  (already replaced by `run_tests.ps1`).
- `one_click.ps1` -- duplicated `run_tests.ps1`; had stale Elmer 26.1
  references and wrong VTU filename pattern (`magnet_t*.vtu` instead of
  the actual `case_t*.vtu`).
- `geom_preview.py` -- pure-Python duplicate of `geom_preview.FCMacro`.
  The `.FCMacro` form is what users double-click.
- `export_step.py` -- only referenced in TROUBLESHOOTING; no caller.
- `visualize.py` -- only referenced in TROUBLESHOOTING; superseded by
  `results_viewer.FCMacro` and `visualize_freecad_macro.py`.
- `circuit.definitions` / `circuit_open.definitions` -- prepared for
  circuit-coupling but **never referenced by `case_simple.sif`**
  (the SIF has no `Include "circuit.definitions"` line).
- `ONE_LINER.txt` -- superseded by README's project header.
- `requirements-dev.txt` -- just `pip install -r requirements.txt` with
  no extra pins.
- Build artifacts: `model3d.msh`, `mesh/`, `results/`, `test_outputs/`
  (regenerated by `run_tests.ps1`).

### Changed
- README §3 (file list) pruned: removed all 10 deleted-file rows.
- README §5 (Elmer install) no longer mentions `one_click.ps1`.
- README §6 (geometry) keeps the circuit.definitions historical note
  but no longer lists the deleted files in the project tree.
- README §7 (doc navigation) `CHANGELOG.md` description updated to
  current version range `1.0.0 .. 2.1.0`.


## [2.0.0] - 2026-09-11

### Removed
- **oscilloscope.py** (analytical ODE half-analytical solver, RK4 + analytical
  B-field + Faraday / Lenz force model).  Per user request, the project now
  ships only the **Elmer 26.2 FEM real solution**.
- **tests/test_oscilloscope.py** (8 pytest assertions for the analytical
  pipeline).
- **config.json `[chart]` block** (dashboard layout, channels, passage-time
  bar settings) — only consumed by oscilloscope.py.
- **README.md section 9 (示波器与通过时间条形图)** and section 10.4 (chart
  block documentation); renamed to section 10 (config.json field reference
  without chart subsection).
- **run_tests.ps1 step 5/5** (oscilloscope sanity tests); the pipeline is
  now 4 steps: gmsh -> ElmerGrid -> ElmerSolver -> FEM tests.
- Step numbering in `run_tests.ps1` changed from `[N/5]` to `[N/4]`.

### Changed
- Project is now **pure FEM**: gmsh -> ElmerGrid -> ElmerSolver 26.2 ->
  FreeCAD visualization.  No analytical fallback.
- `config.json` `_comment` rewritten to describe the now-simplified layout
  (5 top-level sections instead of 6).
- README TOC trimmed from 11 to 10 sections.
- `README.md` section 1 (方法概览) updated to describe only the FEM pipeline
  (no `m*z_ddot = m*g - c*v` ODE formula).
- Section 8 (FEM tests) now describes only test_mesh.py + test_render.py.
- FreeCAD section kept (3 entry points, sliding window, troubleshooting).

### Added
- (none — the change is purely subtractive.)


## [1.3.0] - 2026-09-11

### Changed
- **README.md section 10 (FreeCAD 可视化) completely rewritten**
  to be a full workflow guide:
  - 3 entry points side-by-side: `geom_preview.FCMacro`,
    `results_viewer.FCMacro`, `visualize_freecad_macro.py`
  - Step-by-step instructions for each (double-click vs Macro menu)
  - Sliding-window mechanism explained
  - 3-path ASCII diagram showing config -> geometry -> mesh -> FEM -> viz
  - Troubleshooting table expanded with causes + solutions
  - Output file sizes enumerated
  - New 10.6 section: how to inject analytical ODE trajectories
    back into FreeCAD for side-by-side comparison with FEM results

### Added
- **README.md section 11 (config.json field-by-field reference)**:
  - 11.1 file-structure overview
  - 11.2 every common field documented (experiment, physics, magnet,
    mesh, geometry)
  - 11.3 every per-curve field documented (label, color, z_release_m,
    N_turns, wire_diameter_m, wire_conductivity_S_per_m, R_load_ohm,
    damping_extra_N_s_per_m, body_name, sif_suffix, _comment)
  - 11.3.1 physics-derived quantities auto-computed by oscilloscope.py
    (R_wire, R_total, damping_total, A_coil, Phi, EMF, I)
  - 11.4 chart block fields (figsize, ncols, height_ratios, dpi,
    channels, passage_time_bar)
  - 11.5 worked example: adding a new curve (fine_wire)
  - 11.6 unit convention table
- TOC updated to link sections 5/6/10/11 by their actual anchors.
- 1.2.0 / 1.1.0 / 1.0.0 release notes already present in CHANGELOG.


## [1.2.0] - 2026-09-11

### Changed
- **config.json restructured into a two-tier layout**:
  - `[curves]` (top): one named JSON block per plotted line. Each block
    carries the per-curve physics: `z_release_m`, `N_turns`,
    `wire_diameter_m`, `wire_conductivity_S_per_m`, `R_load_ohm`,
    `damping_extra_N_s_per_m`, plus presentation (`label`, `color`,
    `body_name`, `sif_suffix`).
  - `[chart]` (bottom): presentation-only settings: `figsize`, `ncols`,
    `height_ratios`, `channels`, `passage_time_bar`.
  - Common physics (`G`, `M_kg`, `C_air`, magnet / coil geometry)
    stays outside both blocks.
- **Copper-tube configuration removed**. Was a debug aid for Lenz
  eddy-current verification; superseded by per-curve wire resistance
  computed from `N_turns`, `d`, `sigma` in `oscilloscope.py`.
- `oscilloscope.py` rewritten to loop over `[curves]`; **adding a new
  curve = appending one JSON block**, no code change needed.
- `solenoid3d.py` `--config` choices now derived from `[curves].sif_suffix`,
  and the bore body name looked up via `[curves].body_name`.
- `write_summary` / `write_json` / `dashboard.png` automatically scale
  to N curves.

### Added
- Per-curve wire-resistance: `R_wire = (1/sigma) * N * L_mean / (pi*(d/2)^2)`
  is added to `R_load` so total R differs between e.g. 0.7 mm and 1.0 mm wires.
- Default 3-curve example: `empty` + `coil` (10 Ω) + `coil_high_R` (100 Ω)
  to demonstrate R-load sweep.
- 8 new pytest assertions: `test_config_schema`, `test_wire_resistance_computed`,
  `test_chart_layout`, etc.

### Removed
- Copper-tube body in `solenoid3d.py` (geometry branch removed).
- Old `[configs]` section in config.json.
- `--alpha-cu` / `--beta-coil` CLI flags in oscilloscope.py (replaced by per-curve
  `damping_extra_N_s_per_m` in JSON).


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

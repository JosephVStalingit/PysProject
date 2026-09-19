#!/bin/bash
# =====================================================================
#  hpc/detect_accelerator.sh
#
#  Work out what accelerator the machine has and, more importantly, WHAT
#  SOFTWARE STACK it speaks.  Elmer 26.2 only has two accelerator
#  interfaces, so this is the only thing that decides the build:
#
#      -DWITH_AMGX=TRUE        needs NVIDIA CUDA
#      -DWITH_ROCALUTION=TRUE  needs AMD / Hygon ROCm (HIP)
#
#  If the card speaks neither (a vendor-proprietary stack such as
#  Ascend CANN or Cambricon BANG) then Elmer simply cannot use it, and
#  the CPU path is the answer -- which for our problem is fine anyway
#  (128 cores + 512 GB -> the whole study in ~14 h).
#
#  Run this ON THE LOGIN NODE:
#      bash detect_accelerator.sh
# =====================================================================
echo "=============================================="
echo " 1. PCI devices"
echo "=============================================="
lspci 2>/dev/null | grep -iE "vga|3d|display|processing accel" || echo "  (lspci not available)"

echo
echo "=============================================="
echo " 2. Vendor management tools on PATH"
echo "=============================================="
printf "  %-14s %s\n" "tool" "path"
for c in nvidia-smi nvcc rocminfo rocm-smi hipcc amd-smi \
         dtk-smi hy-smi hy-smi-xpu \
         cnmon cncc cnas ascend-dmi npu-smi \
         mx-smi mxsmi \
         xpu-smi ixsmi \
         vastai-smi biren-smi brsmi; do
    printf "  %-14s %s\n" "$c" "$(command -v $c 2>/dev/null || echo -)"
done

echo
echo "=============================================="
echo " 3. Software stacks installed under /opt /usr/local"
echo "=============================================="
ls -d /opt/rocm* /opt/cuda* /opt/hip* /opt/ascend* /opt/cambricon* \
      /opt/dtk* /opt/hyhal* /opt/maca* /opt/corex* /opt/hpc \
      /usr/local/rocm* /usr/local/cuda* 2>/dev/null || echo "  (none of the usual paths)"

echo
echo "=============================================="
echo " 4. Environment modules mentioning an accelerator"
echo "=============================================="
(module avail 2>&1; module -t avail 2>&1) | tr ' ' '\n' \
    | grep -iE "cuda|rocm|hip|dtk|ascend|npu|cambricon|maca|corex|acceler" \
    | sort -u | head -30 || echo "  (none / no module system)"

echo
echo "=============================================="
echo " 5. Kernel driver versions"
echo "=============================================="
for f in /proc/driver/nvidia/version /sys/module/amdgpu/version \
         /sys/module/hygondrm/version /sys/module/hydcu/version; do
    [ -r "$f" ] && { echo "  $f:"; head -2 "$f" | sed 's/^/    /'; }
done
lsmod 2>/dev/null | grep -iE "nvidia|amdgpu|hydcu|hygon|ascend|davinci" | sed 's/^/  /' \
    || echo "  (lsmod empty or no matching module)"

echo
echo "=============================================="
echo " 6. VERDICT"
echo "=============================================="
if command -v rocminfo >/dev/null 2>&1 || [ -d /opt/rocm ] || ls -d /opt/dtk* >/dev/null 2>&1; then
    echo "  -> ROCm/HIP detected:"
    echo "     use  -DWITH_ROCALUTION=TRUE  -DCMAKE_HIP_COMPILER=hipcc"
elif command -v nvcc >/dev/null 2>&1 || [ -d /usr/local/cuda ] || ls -d /opt/cuda* >/dev/null 2>&1; then
    echo "  -> CUDA detected:"
    echo "     build AmgX first, then  -DWITH_AMGX=TRUE  -DAMGX_LIBRARY=... "
elif command -v npu-smi >/dev/null 2>&1 || ls -d /opt/ascend* >/dev/null 2>&1; then
    echo "  -> Ascend NPU (CANN) detected: Elmer has NO interface for this."
    echo "     Use the CPU path."
else
    echo "  -> No CUDA / ROCm / Ascend stack found."
    echo "     Either the accelerators are not on THIS node, or they use a"
    echo "     proprietary SDK.  Check with the provider which of CUDA or"
    echo "     ROCm the card is compatible with; otherwise use the CPU path."
fi
echo
echo "  REMINDER: whatever the answer, first prove the CPU build works:"
echo "    3-step smoke test -> must NOT print 'umf4num: -1.0'"

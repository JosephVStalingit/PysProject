#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_sensor_chain.py -- do the LV 25-P and the ACS712 suit this experiment?

Signal levels in the 900-step sweep (measured):
    EMF          eps_peak = 27.7 / 55.4 / 110.6 mV   for N = 25 / 50 / 100
    loop current i       = eps / (R_wire + R_load)

Sensor data used here (from the manufacturers published specs):
  LEM LV 25-P  (closed-loop Hall VOLTAGE transducer)
      * the LEM LV series is specified for 100 .. 4000 V RMS nominal
      * primary nominal current IPN = 10 mA, primary resistor built in (RP ~ 250 ohm)
      * secondary 25 mA, closed loop, accuracy ~0.9% of IPN
  ALLEGRO ACS712 (integrated-conductor Hall CURRENT sensor)
      * internal conductor resistance 1.2 mOhm -> negligible as a series element
      * full scale / sensitivity: 5 A / 185 mV/A, 20 A / 100 mV/A, 30 A / 66 mV/A
      * TOTAL OUTPUT ERROR 1.5% (specified at full scale, TA = 25 C)
      * 5 V single supply, output centred on VCC/2

The point of this check: the current sensor is a near-perfect SHORT, so the coil
terminals are almost shorted and a parallel probe sees V = i * R_load (the drop
across the shunt), NOT the EMF.  With only the ACS712 in the loop that is
0.2 mV -- there is nothing for a voltage sensor to measure, whatever its rating.
A series resistor makes the voltage measurable, and that same resistor sets the
Lenz damping, so it is the one number that must be chosen deliberately.

Run:  python check_sensor_chain.py
"""
from __future__ import annotations

import math
import sys

LV_V_NOMINAL = (100.0, 4000.0)     # V RMS, LEM LV series
LV_IPN = 10.0e-3                   # A primary nominal
LV_RP = 250.0                      # ohm primary resistance (built in)

ACS_R_INT = 1.2e-3                 # ohm internal conductor
ACS_VERR = 0.015                   # total output error at full scale
ACS_VARIANTS = {"ACS712-05B": (5.0, 0.185), "ACS712-20A": (20.0, 0.100),
                "ACS712-30A": (30.0, 0.066)}

DL_DZ = {25: 6.138006e-2, 50: 1.226888e-1, 100: 2.448276e-1}   # Wb (field quantity)
# MEASURED |eps| peak from the 900-step circuit.csv (used to drive the current):
# note dLambda/dz * |zdot|max = 107.92 mV, i.e. 2.4% below the measured peak --
# the product's maximum is not exactly at the velocity maximum, and the trace is
# sampled at 1 ms.  b_em = (eps/zdot)^2/R_total is unaffected by this.
EPS_PK = {25: 27.7388e-3, 50: 55.4408e-3, 100: 110.6103e-3}
ZPK = 0.4408                                                   # m/s first |zdot| peak
R_WIRE = {"cu": {25: 0.1583357, 50: 0.3166714, 100: 0.6333429},
          "al": {25: 0.2562245, 50: 0.5124490, 100: 1.0248980}}
C_AIR = 1.3284e-4
KM = math.sqrt(220.0 * 0.5)
PERIOD = 0.299539


def ipk(mat, n, r_load):
    """Peak loop current, driven by the MEASURED EMF."""
    return EPS_PK[n] / (R_WIRE[mat][n] + r_load)


def main():
    eps = EPS_PK[100]
    print("=== the two sensors vs this experiment's signal levels ===")
    print(f"  EMF at the velocity peak (N=100)   : {eps*1000:.2f} mV  (MEASURED)")
    print(f"  LV 25-P low end                    : {LV_V_NOMINAL[0]:.0f} V RMS"
          f"   -> {LV_V_NOMINAL[0]/eps:.0f}x above the WHOLE signal")
    print()
    print("  current sensor    FS[A]  sens[mV/A]  out@175mA    % of FS"
          "   1.5%-of-FS error")
    for name, (fs, s) in ACS_VARIANTS.items():
        out = 0.175 * s * 1000.0
        err = ACS_VERR * fs
        print(f"  {name:<16} {fs:5.1f}  {s*1000:9.1f}  {out:8.2f} mV"
              f"  {100*0.175/fs:8.2f}%  {err*1000:9.1f} mA"
              f"  = {100*err/0.175:5.1f}% of the reading")
    print()
    print("  ==> ACS712 is over-ranged 30x (05B): its error budget is 43% of the")
    print("      reading; the 20 A / 30 A variants are 4x / 8x worse again.")
    print("  ==> and its 1.2 mOhm shorts the loop, so a parallel voltage probe")
    print("      sees only i*R_load -- not the EMF.")

    print()
    print("=== what a voltage probe actually reads: V_terminal = i * R_load ===")
    print("  R_load[ohm]   i[mA]   V_terminal[mV]   LV25-P Ip[mA]   (of 10 mA)"
          "   Lenz per-period")
    for rl in (ACS_R_INT, 0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 10.0):
        i = ipk("cu", 100, rl)
        v = i * rl
        ip = v / LV_RP
        b = DL_DZ[100] ** 2 / (R_WIRE["cu"][100] + rl)
        tq = 2.0 * 0.5 / (C_AIR + b)
        print(f"  {rl:10.4f}  {1000*i:7.2f}  {1000*v:13.4f}  {1000*ip:13.4f}"
              f"  {100*ip/LV_IPN:10.2f}%  {100*(1-math.exp(-PERIOD/tq)):12.4f}%")
    print()
    print("  With ONLY the ACS712 in the loop (1.2 mOhm) a parallel probe reads")
    print("  0.21 mV: the coil is shorted, so the EMF is NOT a terminal voltage.")
    print("  The LV 25-P needs ~2500 mV across its built-in 250 ohm primary just")
    print("  to reach 10 mA, and the EMF caps it at 0.44 mA (4.4% of rating).")

    print()
    print("=== the SERIES RESISTOR is the design knob ===")
    print("  R_series[ohm]  i[mA]   V[mV]   SNR@1mV   per-period   10% decay[s]"
          "   Cu/Al contrast")
    for rl in (0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0):
        ic = ipk("cu", 100, rl)
        v = ic * rl
        bc = DL_DZ[100] ** 2 / (R_WIRE["cu"][100] + rl)
        ba = DL_DZ[100] ** 2 / (R_WIRE["al"][100] + rl)
        tc = 2.0 * 0.5 / (C_AIR + bc)
        print(f"  {rl:12.2f}  {1000*ic:6.2f}  {1000*v:6.1f}  {v/1e-3:8.0f}"
              f"  {100*(1-math.exp(-PERIOD/tc)):10.4f}%  {tc*math.log(10/9):11.2f}"
              f"  {bc/ba:12.3f}x")
    print()
    print("  RECOMMENDATION: a precision 0.5-1 ohm resistor in series.")
    print("    1.0 ohm -> 67.7 mA, 67.7 mV across it, Lenz 1.10% per period,")
    print("               10% loss in 2.9 s, Cu/Al contrast 1.24x")
    print("    0.5 ohm -> 97.6 mA, 48.8 mV, 1.58% per period, 2.0 s, 1.34x")
    print("  That resistor IS the current shunt, so it replaces the ACS712:")
    print("  i = V/R.  With V across the coil too, EMF = V_coil + i*R_wire.")
    print("  For the model: R_load = R_series + R_ACS712(0.0012) + R_leads.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

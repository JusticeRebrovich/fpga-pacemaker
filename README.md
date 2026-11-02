# FPGA Digital Adaptive-Threshold Pacemaker (Verilog, Nexys A7)

A simplified digital pacemaker rhythm generator in Verilog. A synthetic ECG feeds an adaptive leaky
integrate-and-fire (LIF) neuron that detects heartbeats, and a pacing controller fires a pulse when no beat
arrives within the escape interval. It runs on a Digilent Nexys A7-100T (Artix-7) and was later extended with a
custom KiCad PCB that plugs into the board's PMOD header.

> Educational model only. Not a medical device.

## Architecture

```
ecg_rom --> adaptive_lif --> pacemaker_ctrl --> LED_PACE
 (12-bit      (QRS detector,    (escape interval,
  samples)     adaptive          blanking and
               threshold)        refractory timing)
                    └--> LED_HEART (detected beat)
```

All logic runs from the 100 MHz board clock, with a divider producing a 1 kHz sample-enable.

| Module | Role |
| --- | --- |
| `ecg_rom` | Repeating 10-sample synthetic ECG: 4095 is a beat, 2048 is baseline |
| `adaptive_lif` | Subtracts the baseline, applies a dead zone (100) and gain (40), leaks the membrane voltage by `v >> 4`, and fires when `v >= theta`. After a spike `theta` rises by 128 and decays back to its base (1536) with shift 5, and a 3-tick refractory counter blocks re-firing |
| `pacemaker_ctrl` | Escape-interval timer (60 BPM lower rate = 1000 ticks) reset by detected beats; 40 ms blanking after a pace pulse and 200 ms refractory after a sensed beat |
| `top` | Clock divider, ROM address counter, and wiring to `LED_HEART` and `LED_PACE` |

## Simulation

```bat
sim\run_xsim.bat
```

This runs [`tb/tb_pacemaker.v`](tb/tb_pacemaker.v) in Vivado xsim 2020.2 for 200 ms. Result from the run in this
repository:

- One pace pulse at about 1 ms (the controller starts with its escape timer expired)
- 21 detected beats (`LED_HEART` pulses), roughly one per 10 ms ECG pattern loop. The controller's 200 ms
  refractory window means only beats outside it reset the escape timer
- No further pace pulses, since sensed beats arrive well inside the 1 s escape interval

The testbench prints `LED_HEART` and `LED_PACE` transitions for inspection. It is not self-checking, and a
200 ms run does not reach the 1 s escape interval, so the bradycardia pacing path needs a longer run or an ECG
pattern with a gap.

## FPGA build

Top module `top`, constraints in [`constraints/nexys_a7.xdc`](constraints/nexys_a7.xdc) (100 MHz clock on E3,
active-low reset on C12, `LED_HEART` on LED0, `LED_PACE` on LED1).

## Hardware demo with a custom PCB

[`hardware/pacemaker_led_demo.v`](hardware/pacemaker_led_demo.v) is the simpler Verilog used for the PCB
integration: a counter-based ~70 BPM pace pulse on a PMOD pin, plus an alarm output that follows a pushbutton on
the board. The PCB was designed in KiCad (LEDs with 470 ohm resistors, a 2N3904 buzzer driver, a 10 kohm
pulldown on the button, and a decoupling capacitor) and connects through a 12-pin PMOD header.

## Repository layout

```
rtl/pacemaker.v          ECG ROM, adaptive LIF detector, pacing controller, top
tb/tb_pacemaker.v        Testbench
constraints/             Nexys A7 pin constraints
sim/run_xsim.bat         xsim build and run script
hardware/                Verilog for the PCB demo
docs/vlsi-design-course/ Presentation and report from the VLSI design course
```

## Author

Justice Rebrovich, University of North Dakota (B.S. Electrical Engineering).
The PCB and embedded-systems work was done with Tyler Olsen.

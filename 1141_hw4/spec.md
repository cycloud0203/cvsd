# NTU EE 1141 Homework 4 — IoT Data Filtering (IOTDF)

This markdown file consolidates **all specifications and details** an AI agent needs to understand and implement the IOT Data Filtering (IOTDF) design.

---

## 🧩 Overview

Design a Verilog module named **`IOTDF`** that processes IoT sensor data in real-time. The module receives 128-bit data inputs (streamed 8 bits per cycle), performs computation according to `fn_sel`, and outputs the result within 1,000,000 cycles. There are 64 data in total.

---

## ⚙️ Module Interface

| Signal Name | Dir | Width | Description                                                                           |
| ----------- | --- | ----- | ------------------------------------------------------------------------------------- |
| `clk`       | I   | 1     | Positive-edge clock signal.                                                           |
| `rst`       | I   | 1     | Active-high asynchronous reset.                                                       |
| `in_en`     | I   | 1     | Input enable signal. When `busy=0`, `in_en`=1 fetches data; when `busy=1`, `in_en`=0. |
| `iot_in`    | I   | 8     | IoT input stream. 16 cycles → 1 × 128-bit data. 64 data packets total.                |
| `fn_sel`    | I   | 3     | Function select (F1–F5). Constant per simulation.                                     |
| `iot_out`   | O   | 128   | IoT data output. One cycle per data output.                                           |
| `busy`      | O   | 1     | Busy indicator (1 = processing). Controls input gating.                               |
| `valid`     | O   | 1     | Output valid flag (1 = output data valid).                                            |

---

## 🧠 Functional Requirements

### Function Select (`fn_sel`)

| Function | `fn_sel` | Description                                        |
| -------- | -------- | -------------------------------------------------- |
| F1       | `3'b001` | **Encrypt (DES)** — Encrypt 64-bit data using DES. |
| F2       | `3'b010` | **Decrypt (DES)** — Decrypt 64-bit data using DES. |
| F3       | `3'b011` | **CRC Generator** — Polynomial: `x³ + x² + 1`.     |
| F4       | `3'b100` | **Sorting** — Sort 16 × 8-bit data descending.     |
| F_hidden | —        | Hidden test (grading only).                        |

---

## 🧮 Data Flow

### Input Sequence

* Each 128-bit input data = 16 bytes.
* Transferred over 16 cycles (8 bits per cycle).
* Total: 64 data words per simulation.

```
Cycle 1 → iot_in[7:0]     → iot_in → [7:0]
Cycle 2 → iot_in[15:8]    → iot_in → [15:8]
...
Cycle 16 → iot_in[127:120]
```

*Alternative bit orderings exist; the direction should match the provided testbench.*

### Output Sequence

* One 128-bit word output per data processed.
* `valid=1` for one clock cycle when output is valid.

---

## ⏱ Timing Behavior

1. Reset phase (`rst=1`) → initialize.
2. When `busy=0`, testbench raises `in_en=1` to start streaming new 128-bit data.
3. Each data word received over 16 cycles.
4. Once data loaded, `busy` asserted → computation.
5. `valid=1` when output ready (one cycle).
6. Repeat for next 128-bit data.
7. Must process all 64 data words within **1,000,000 cycles**.

---

## 🧠 Algorithm Details

### F1/F2 — DES Encrypt/Decrypt

* **Inputs**: `in_buf[127:64]` = 64-bit key, `in_buf[63:0]` = 64-bit plaintext/ciphertext.
* **Operations**:

  1. Initial permutation (IP).
  2. Key schedule (PC1 → shift → PC2) for 16 subkeys.
  3. 16 rounds: E-expansion, XOR with subkey, 8 × S-box lookup, P-permutation, XOR/swap.
  4. Final permutation (FP).
* **Output**: 64-bit ciphertext/cleartext, packed back into 128-bit output.
* **Note**: Decrypt (F2) uses reverse subkey order (K16 → K1).

### F3 — CRC Generator

* **Polynomial**: `x³ + x² + 1`.
* **Implementation**: 3-bit LFSR.
* **Process**: Iterate through all 128 bits (serial or 8-bit parallel update).
* **Output**: `iot_out[2:0] = CRC`, rest zero.

### F4 — Sorting

* **Input**: 16 bytes (8-bit each).
* **Output**: 128-bit sorted (descending).
* **Recommended**: Odd-even or bitonic sorting network.

### Hidden Function

* Evaluates generality of design (correct handshake, FSM control, and modularity).

---

## 🧰 Implementation Hints

* Use **register sharing** to reduce area.
* Apply **clock gating** to minimize power.
* Pipeline computations for speed.
* Reasonably allocate LUT/table reads per cycle.

---

## 🧾 Grading Policy

| Category    | Weight | Criteria                                       |
| ----------- | ------ | ---------------------------------------------- |
| Simulation  | 60%    | Correct output for F1–F4 and hidden pattern.   |
| Performance | 30%    | Ranking by (Power × Time × Area).              |
| Report      | 10%    | Provide Power, Time, and Area in `report.txt`. |

### Performance Metric

```
Score = (Power1 × Time1 + Power2 × Time2 + Power3 × Time3 + Power4 × Time4) × Area
```

* Power: from PrimeTime (`pt_script.tcl`)
* Time: simulation processing time
* Area: from synthesis report

---

## 🧪 Test & Scripts

| Folder        | Content                                             |
| ------------- | --------------------------------------------------- |
| `00_TESTBED/` | Testbench (`testfixture.v`), input/output patterns. |
| `01_RTL/`     | Your design (`IOTDF.v`), file lists, run scripts.   |
| `02_SYN/`     | Synthesis configs (`.sdc`, `.setup`).               |
| `03_GATE/`    | Gate-level simulation scripts.                      |
| `06_POWER/`   | Power analysis scripts.                             |

---

## 📦 Submission Format

1. Folder: `studentID_hw4/` (lowercase student ID).
2. Include:

   * All design files
   * `report.txt`
3. Compress: `tar -cvf studentID_hw4_vk.tar studentID_hw4/`
4. Upload to NTU COOL.

---

## 📚 References

1. DES Algorithm — [HackMD](https://hackmd.io/@JayChang/cryptography3)
2. CRC Computation — [Lammert Bies CRC Guide](https://www.lammertbies.nl/comm/info/crc-calculation)
3. Sorting in Hardware — [IEEE Paper (6196391)](https://ieeexplore.ieee.org/abstract/document/6196391)

---

**End of Specification**

# AbyssRov
ABYSS-ROV: Deep Trench is an atmospheric, tension-driven deep-sea telemetry simulator and acoustic survival game developed with Lazarus / Free Pascal.

# ABYSS-ROV: Deep Trench

[![Lazarus](https://img.shields.io/badge/Lazarus-IDE%204.8+-00599C?logo=lazarus&logoColor=white)](https://www.lazarus-ide.org/)
[![Free Pascal](https://img.shields.io/badge/Free%20Pascal-3.2.2+-brightgreen)](https://www.freepascal.org/)
[![Rendering](https://img.shields.io/badge/Renderer-BGRABitmap-orange)](https://github.com/bgrabitmap/bgrabitmap)
[![Database](https://img.shields.io/badge/Storage-SQLite3-003B57?logo=sqlite&logoColor=white)](https://www.sqlite.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> *"In the deepest trenches, sunlight is a myth and sound is an invitation to predators."*

**ABYSS-ROV: Deep Trench** is an atmospheric, tension-driven deep-sea telemetry simulator and acoustic survival game developed with **Lazarus / Free Pascal**. 


<img width="1355" height="686" alt="abyss" src="https://github.com/user-attachments/assets/39ee8983-25db-4c49-b4da-f9abcb4e6c2c" />

Taking the helm as a surface console operator, you control an unmanned Remotely Operated Vehicle (ROV) tethered thousands of meters down into an oceanic trench. Balance power consumption, manage structural integrity under crushing hydrostatic pressure, extract priceless scientific anomalies, and utilize acoustic stealth to survive blind Leviathan-class predators lurking in the pitch-black abyss.

---

## 📸 Key Features

* **Dual-Viewport Telemetry Display:**
  * **Primary Sonar Viewport:** High-contrast radial planar acoustic radar rendering terrain density, depth contours, and active entity sweeps using `BGRABitmap`.
  * **Forward Feed Pseudo-3D Camera:** Raycasting-driven cockpit camera simulating spotlight falloff, marine snow particle dynamics, and CRT magnetic interference/glitch overlays.
* **Acoustic Mechanics & Sound-Hunting AI:**
  * Deep-sea fauna rely purely on acoustic signatures.
  * Thruster cavitation (output $> 65\%$), continuous active sonar pings, and heavy drilling enter a **Noisy State**, drawing blind apex predators directly toward your position.
* **Tactical Countermeasure Systems:**
  * **Acoustic Decoy (`[Q]`):** Launch noisy acoustic canisters that lure hunting predators away from your retreat vector.
  * **EMP Burst (`[E]`):** Release an emergency radial electromagnetic shockwave to disrupt predator electro-receptors, at the cost of a temporary vehicle-wide electrical **Blackout**.
* **Hit-and-Run Resource Loop:**
  * Harvest *Biomatter*, *Rare Ores*, *Unknown Anomalies*, and high-risk *Black Box Data*.
  * Anomaly extractions yield **Research Points (RP)** that must be secured by successfully aborting/disconnecting the data link before hull breach.
* **Persistent Hangar & Modular Progression:**
  * Relational **SQLite3** persistence for extracted logs, mission history, and upgrade trees.
  * Purchase permanent improvements: Hull Reinforcement, High-Density Battery Banks, Upgraded Thrusters, and Countermeasure Capacitors.

---

## 🎮 Controls & Operational Hotkeys

| Input | Action | Description |
| :--- | :--- | :--- |
| **`W` / `S`** | **Thruster Adjust** | Increment/decrement propulsion output ($\pm 5\%$). Neutral at $50\%$. |
| **`A` / `D`** | **Rudder Steering** | Turn port (left) / starboard (right). Auto-centers upon release. |
| **`Q`** | **Deploy Decoy** | Launch an acoustic diversion canister (triggers cooldown). |
| **`E`** | **Fire EMP** | Radial stun pulse (triggers system reboot & screen blackout). |
| **UI Button** | **Active Sonar [ON/OFF]** | Toggles continuous circular acoustic radar ping. |
| **UI Button** | **Data Link [CONNECT/DISCONNECT]** | Initiates mission descent or safely terminates the expedition. |
| **UI Button** | **Sampling Arm [Extract]** | Deploys mechanical claw when within $50\text{ units}$ of an anomaly. |
| **UI Button** | **Access Hangar** | Opens vehicle customization dok (available only at surface). |

---

## 🛠️ System Architecture & Technologies

* **Language & Compiler:** Object Pascal via Free Pascal Compiler (FPC 3.2.2+).
* **IDE & UI Framework:** Lazarus IDE with Lazarus Component Library (LCL).
* **Rendering Engine:** `BGRABitmap` (custom software rasterization, vector rendering, line anti-aliasing, and raycast projection).
* **Audio Layer:** BASS Audio Library (hydrophone rumble, telemetry alerts, and dynamic acoustic feedback).
* **Persistence:** Native SQLite3 database connection (`TSQLite3Connection`, `TSQLTransaction`, `TSQLQuery`).

---


## 🚀 Getting Started & Building from Source

### Prerequisites
1. **Lazarus IDE** (v2.2.0 or newer, recommended v3.0+ / 4.x).
2. **BGRABitmap Package:** Installed via Lazarus Package Manager (`OPM` -> search `bgrabitmap`).
3. **SQLite3 Dynamic Library:** Ensure `sqlite3.dll` (Windows) or `libsqlite3.so` (Linux) is present in your system path or binary directory.
4. **BASS Audio Library:** `bass.dll` or `libbass.so` matching your compile architecture (32-bit or 64-bit).
5. **BWLazUI:** https://github.com/CodeInPas/BWLazUI
6. **TWLazUI:** https://github.com/CodeInPas/TWLazUI

### Compilation
1. Clone this repository:
   ```bash
   git clone https://github.com/your-username/abyss-rov-simulator.git
   cd abyss-rov-simulator
   ```
2. Open `Abyss_ROV.lpr` in the Lazarus IDE.
3. Verify that `BGRABitmapPack` and database packages (`sqldblaz`) are resolved in the Project Inspector.
4. Set build mode to **Release** or **Debug**.
5. Compile and run (`F9` or `Run -> Run`).

---

## 🌊 Tactical Operator Manual (Quick Tips)

1. **Beware the 65% Threshold:** Accelerating past 65% thruster output creates cavitation bubbles that sound like an acoustic beacon to predators.
2. **Ping Responsibly:** Sonar pulses bounce off trench walls—and bounce directly into Leviathan hearing organs. Keep Active Sonar turned **OFF** while navigating deep corridors.
3. **The 40/20 Evacuation Rule:** When Hull Integrity drops below $40\%$ or Battery drops below $20\%$, immediately throttle down and click **`DATA LINK [DISCONNECT]`**. A dead drone brings zero Research Points home.
4. **Decoy Before Drilling:** Unlocking a 500 RP Black Box takes 10 seconds of locked drilling noise. Launch an acoustic decoy before engaging the drill arm.

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🤝 Acknowledgments

* **Circular** and the BGRABitmap contributor community for high-performance Pascal rendering.
* **Un4seen Developments** for the BASS Audio Library.
* Oceanic exploration logs and underwater ROV specifications that inspired this project.

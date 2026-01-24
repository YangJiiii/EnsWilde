<div align="center">
  <img src="https://github.com/YangJiiii/EnsWilde/blob/be10a7d93b70df3b40057f869e6cc82de92bc2f0/MyApp_Dark_1024.png?raw=true" width="120" alt="EnsWilde Logo" />
</div>
# EnsWilde (Mobile)

**EnsWilde** is a tool utilizing `itunesstored` & `bookassetd` exploits, designed for iPhone and iPad running the latest **iOS Version 26.2b1**.

It operates as a standalone on-device application, functioning independently like modern apps. It leverages the `sparserestore` exploit to write data to files situated outside of the intended restore location.

> [!WARNING]
> **DISCLAIMER:**
> I am **not responsible** if your device enters a bootloop. Use this software with caution.
> **Please back up your data before using!**

## Features
* **Disable call recording notification sound:** Turns off the audible alert when call recording starts.
* **Change Apple Wallet background image:** Customize the background appearance of Wallet passes/cards.
* **Edit MobileGestalt file (advanced):** Modify MobileGestalt configuration values (for advanced users).
* **Change Passcode background:** Customize the numeric keypad appearance using the `.passthm` interface.
* **On-device patching (no PC required):** Operates as a standalone app after the initial setup.
* **More features coming soon:** Development is ongoing to introduce additional capabilities.


## Getting Your pairing File
There are two supported ways to obtain a pairing file:

### Option 1 — Generate it with idevicepair (recommended)
1.  Download `idevicepair` for your operating system here: [idevicepair Releases](https://github.com/jkcoxson/idevice_pair/releases)
    * **Note:** On Linux, you may need to install usbmuxd first.
    ```bash
        sudo apt install -y usbmuxd
    ```
2.  Run the program.
3.  After idevicepair detects your device, hold CTRL, press "load" and save the file.
4.  Share the generated `.plist` file to your iOS device (AirDrop, Files, etc.).
5.  Open **EnsWilde** and select the pairing file.

*You should only have to do this once, unless you lose the file, delete the app’s data or factory reset the device.*

---

### Option 2 — Pick the pairing file directly from SideStore’s folder
If you already imported/placed a pairing file for SideStore, it’s typically stored in SideStore’s on-device folder.

1. Open **Files** on your iPhone/iPad
2. Go to **Browse** → **On My iPhone/iPad** → **SideStore**
3. Find the file ending in **`.mobiledevicepairing`**
4. Open **EnsWilde** and select that file directly from the SideStore folder

## Setting Up VPN
1.  Download **[LocaldevVPN](https://apps.apple.com/app/id6755608044)** from the iOS App Store.
2.  Enable the VPN within that app.
3.  Launch **EnsWilde**.


## Credits

Special thanks to the following for their contributions and support:

* **Carrot1211**:[ For cheering me on and supporting me during development.](https://x.com/Hihihehe1221).
* **@khanhduytran0**: [SparseBox](https://github.com/khanhduytran0/SparseBox).
* **@Little_34306**: [Original concept for "Disable Call Recording](https://github.com/34306).
* **@SideStore team**: [`idevice` and C bindings from StikDebug.](https://github.com/sidestore).
* **@JJTech0130**: [`SparseRestore` and backup exploit.](https://github.com/JJTech0130).
* **@hanakim3945**: [`bl_sbx` exploit files and writeup.](https://github.com/hanakim3945).
* **@Lakr233**: [BBackupp](https://github.com/Lakr233/BBackupp).
* **@libimobiledevice**: [For the underlying communication libraries.](https://github.com/libimobiledevice/libimobiledevice).

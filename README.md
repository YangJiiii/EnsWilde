![EnsWilde](github.com/YangJiiii/EnsWilde/blob/be10a7d93b70df3b40057f869e6cc82de92bc2f0/MyApp_Dark_1024.png?raw=true)
# EnsWilde (Mobile)

**EnsWilde** is a tool utilizing `itunesstored` & `bookassetd` exploits, designed for iPhone and iPad running the latest **iOS Version 26.2b1**.

It operates as a standalone on-device application, functioning independently like modern apps. It leverages the `sparserestore` exploit to write data to files situated outside of the intended restore location.

> [!WARNING]
> **DISCLAIMER:**
> I am **not responsible** if your device enters a bootloop. Use this software with caution.
> **Please back up your data before using!**

## Features
* **Disable call recording notification sound:** Turns off the audible warning when recording calls.
* **More features coming soon:** Development is ongoing to add new capabilities.

## Getting Your .mobiledevicepairing File
To generate the necessary pairing file, follow these steps:

1.  Download `jitterbugpair` for your specific operating system here: [Jitterbug Releases](https://github.com/osy/Jitterbug/releases/latest)
    * **Note:** On Mac or Linux, you may need to run the following terminal command in the file's directory to make it executable:
        ```bash
        chmod +x ./jitterbugpair
        ```
2.  Run the program by double-clicking it or executing it via Terminal/PowerShell.
3.  Share the generated `.mobiledevicepairing` file to your iOS device (via AirDrop, Files, etc.).
4.  Open the **EnsWilde** app and select the pairing file.

*You should only have to do this once, unless you lose the file or delete the app's data.*

## Setting Up VPN
1.  Download **LocaldevVPN** or **Stikdebug** from the iOS App Store.
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
* **@libimobiledevice**:[For the underlying communication libraries.](https://github.com/libimobiledevice/libimobiledevice).
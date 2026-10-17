<h1 align="center">Godot Detached Inspector Plugin</h1>

<p align="center">
  <img src="../../icon.svg" width="150" />
</p>

<div align="center">
    <img src="https://img.shields.io/badge/version-0.1.0-green" alt="Version 0.1.0">
    <br>
    <img src="https://img.shields.io/badge/language-GDScript-468cbf" alt="GDScript">
    <img src="https://img.shields.io/badge/Godot-4.7%2B-468cbf" alt="Godot 4.7 or newer">
    <p>By <strong>JoenTNT</strong></p>
</div>

---

> Keep a scene node's Inspector open in a **separate native window** while selecting other nodes in Godot.

<p align="center">
  <table>
    <tr>
      <td align="center" width="50%">
        <img src="sample_projects/screenshots/preview.gif" width="100%" alt="Preview"><br>
        <b>Preview</b>
      </td>
      <td align="center" width="50%">
        <img src="sample_projects/screenshots/window-merge.gif" width="100%" alt="Window Merge"><br>
        <b>Window Merge</b>
      </td>
    </tr>
  </table>
</p>

<a id="requirements-and-installation"></a>

## How to Install?

1. Copy the complete `addons/detachable-inspector/` folder into your project's
   `addons/` directory, keeping that folder name and its UID files.
2. Open **Project → Project Settings → Plugins** and enable **Detached Inspector**.
3. Open a scene and select exactly one node in the local Scene tree.

> NOTE: When updating, close detached windows and disable the plugin before replacing
files, then re-enable it.

---

## QUICK DOCUMENTATION

> Documentation updated **17 October 2026** for version **0.1.0**.
> Requires Godot **4.7+**; native UI and platform verification remain manual.

<a id="open-a-window"></a>

### A. Quick Usage

- Right-click a node → **Open in Detached Inspector** 
- Select a node and use
**Project → Tools → Open Detached Inspector**.

<p align="center">
  <img src="sample_projects\screenshots\detachable-window.png" width="90%" />
</p>

---

<a id="windows-and-tabs"></a>

### B. WINDOWS AND TABS

The toolbar is **Detach | Drag to merge | Pin on top**.

| Control | Behavior |
| --- | --- |
| **Detach** | Move the active tab into a new window. |
| **Drag to merge** | Drag this expanding toolbar button onto another inspector's merge button. Release when it reads **Release to merge here**. |
| **Pin on top** | Keep the window above the main editor and other applications without blocking their input. |


## PATCH LOGS

### Version 0.1.0

- Initial Commit Version.
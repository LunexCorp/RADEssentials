# RAD Essentials

RAD Essentials is a Windows design-time package for RAD Studio. It adds **Format X**, **Search Everywhere**, and Git/GitHub project publishing tools to the IDE. The package also registers its icon on the RAD Studio splash screen and exposes the Git integration from the Help menu.

**PDF Viewer is not currently working and is temporarily disabled.** Its **RADEssentials > PDF Viewer** menu item is grayed out while the editor integration and shutdown errors are being repaired. The shortcut setting remains visible but does not activate the viewer. This is a known plugin issue, not a missing WebView2 Runtime issue.

## IDE Menu

- **Git** opens the Git integration for repository access, project publishing, and release uploads.
- **Search** opens the temporary search palette for IDE actions and project declarations. File and text search modes are available while a source editor is open.
- **Format Code** runs Format X on the selection, or on the whole editor buffer when nothing is selected.
- **PDF Viewer** is currently disabled.
- **Settings** configures the Format X, Search, and PDF Viewer shortcuts. The PDF Viewer shortcut is inactive while the feature is disabled.

## Requirements

- Windows and Embarcadero RAD Studio. The package is built and verified with RAD Studio 12 (Win32); the project targets Win32.
- The package dependencies included with RAD Studio: `rtl`, `vcl`, `designide`, `vclie`, and `vcledge`.
- Git for Windows, installed and discoverable on `PATH`, to use the Git integration.
- Microsoft Edge WebView2 Runtime will be required when PDF Viewer is re-enabled.
- Internet access and a GitHub personal access token for GitHub operations.

## Build and Install

1. Open `RADEssentials.dproj` in RAD Studio.
2. The package embeds `Assets\Icons.res`. If you change the icon resource script or bitmap, regenerate it from this directory with `brcc32.exe Assets\Icons.rc`.
3. Select the **Win32** platform and build the `RADEssentials` package. From a RAD Studio command prompt, you can also build it from this directory with:

   ```powershell
   dcc32.exe -B RADEssentials.dpk
   ```

4. Find `RADEssentials.bpl` in the package's configured BPL output directory. Check **Project > Options > Delphi Compiler > Output** if you are unsure where RAD Studio wrote it. If the IDE reports a missing required package, make sure the package dependencies listed above are installed and available to the selected RAD Studio version.
5. In RAD Studio, open **Component > Install Packages**, choose **Add**, and select `RADEssentials.bpl` from that output directory.
6. Restart RAD Studio if prompted. The **RADEssentials** menu should appear in the IDE.

To remove the plugin, open **Component > Install Packages**, select RAD Essentials, and remove it. This does not delete your GitHub token or settings from your user profile.

## Format X

1. Open a Delphi source file in the editor.
2. Select a portion of source to format, or leave the selection empty to format the whole editor buffer.
3. Choose **RADEssentials > Format Code** or use the default shortcut **Ctrl+Alt+F**. The shortcut can be changed in **RADEssentials > Settings**.

Format X normalizes indentation and spacing while preserving the existing line structure. The operation is a single undo step and restores the editor position and selection state.

## Search Everywhere

Open the temporary search popup with **RADEssentials > Search** or **Ctrl+Shift+A** by default. Change its shortcut under **RADEssentials > Settings**. When a source editor is open, type normally to search IDE menu actions and declarations in the open project or project group. Action icons are used when available; symbols have type-specific icons. A single click or **Enter** opens the selected result. When no source editor is open, the popup searches IDE actions only. With a source editor open, typing `file=` or `text=` switches the input to that search mode and displays a mode chip. Backspace on an empty query, or clicking the chip, returns to action search.

- `file=abc` finds project filenames containing the letters in `abc` in that order, even when other letters appear between them.
- `text=abc` finds the exact text `abc` in project text files. Selecting a result opens the file at the matching line and selects the matching text in the editor.
- Press **Enter** to open the selected result, **Esc** to close the popup, and use the arrow keys to move through results.

## Connect GitHub

1. Install Git for Windows if it is not already installed, then restart RAD Studio.
2. Open a project in the IDE and choose **RADEssentials > Git**.
3. Select **Sign in to GitHub**, then choose **Create token on GitHub...**.
4. Create a personal access token and paste it into the sign-in form. Do not enter your GitHub password.
   For a classic token, select the `repo` scope. For a fine-grained token, grant **Contents: Read and write** and **Metadata: Read-only** for the repositories you need.
5. Return to RAD Studio and select **Sign in**. RAD Essentials validates the token and loads the repositories it can access.

The token is encrypted with Windows DPAPI for the current Windows user and stored at `%USERPROFILE%\RadeEssentials\git_token.dat`. Use **Sign out** to remove it. A token can be valid but still lack write access to a particular repository; the Git window reports the selected repository's push permission before upload. Branch protection rules can still reject a push.

## Publish a Project

1. Open the project you want to publish, then open **RADEssentials > Git**. Press **Reload files** if the file tree does not reflect the current project.
2. Sign in if needed. Choose a GitHub repository and branch. The window reports whether your token has push access to that repository.
3. Check the files and folders to include. Folder checkboxes update their contents recursively. **Select all**, **Select none**, and the Space key are available for quick selection. Unchecked entries are added to `.gitignore`; RAD Essentials does not add a set of default ignore patterns. If an older `.gitignore` contains the RAD Essentials-generated defaults, those marked entries are removed when you next confirm an upload. Other existing rules are preserved.
4. Press **Upload to GitHub**. Review and edit the `.gitignore` entries in the confirmation window, then continue. RAD Essentials initializes the local Git repository if needed, stages and commits changes, verifies the target push with Git, and displays progress during the push.
5. To overwrite remote history, select **Force push** before uploading. This can discard commits on GitHub that are not present locally; use it only when you intend to replace that remote history.

The local project's Git metadata is stored in its `.git` folder. Repository credentials are passed to Git for the push and are not written into the Git remote URL or `.git/config`.

## Build Releases

The Git window can upload build files as assets in a GitHub release after the source push succeeds.

- Enable **Upload build folder as a GitHub release** before uploading.
- RAD Essentials searches for a build directory named `build`, `Build`, `Release`, `Win32\Release`, `Win64\Release`, `Output`, or `bin`.
- To use another directory, open **Settings**, enter a relative or absolute path, or choose **Browse...**. Leave the path empty to use automatic detection.
- The same settings dialog lets you change the filename masks excluded from release assets. The default masks exclude common Delphi compiler outputs such as `.dcu`, `.map`, `.obj`, and related files.

## Settings and Data

- **RADEssentials > Settings** changes the Format X, PDF Viewer, and Search keyboard shortcuts. Click a shortcut field and press the desired key combination to record it. The PDF Viewer shortcut is currently inactive while that feature is disabled.
- The **Settings** button in the Git window opens Git settings for sign-in, release folder, and release asset masks.
- Git settings are stored in `%USERPROFILE%\RadeEssentials\git.ini`.
- The Git integration and its dockable window are also available from the IDE's **Help** menu.

## Troubleshooting

- **PDF Viewer is grayed out:** this feature is temporarily disabled because the current viewer integration is not working. It will remain unavailable until a repaired version is released.
- **Git is disabled or not found:** install Git for Windows, confirm `git.exe` is on `PATH`, and restart RAD Studio.
- **No repositories appear:** press **Refresh**, check the internet connection, and verify that the token grants access to the repositories.
- **Push access is missing:** create a token with the required repository permissions. Organization access may also require organization approval or SSO authorization.
- **Push is rejected:** check the reported Git error and the repository's branch protection rules. If the remote contains commits absent locally, integrate them before retrying; force push only when it is safe to replace remote history.
- **The package does not compile:** use the RAD Studio command prompt for the installed compiler and confirm that `$(BDS)\source\ToolsAPI` is on the library and project search paths.

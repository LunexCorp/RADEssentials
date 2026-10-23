# RAD Essentials

RAD Essentials is a Windows design-time package for RAD Studio. It adds the **Format X** source formatter and GitHub project publishing tools to the IDE, with its icon on the RAD Studio splash screen and in the Help menu.

PDF Studio is available from the **RADEssentials > PDF Viewer** menu. It uses the Microsoft Edge WebView2 Runtime to display documents.

## Requirements

- Windows and Embarcadero RAD Studio. The package is built and verified with RAD Studio 12 (Win32); the project targets Win32.
- The package dependencies included with RAD Studio: `rtl`, `vcl`, `designide`, `vclie`, and `vcledge`.
- Git for Windows, installed and discoverable on `PATH`, to use the Git integration.
- Microsoft Edge WebView2 Runtime, to use PDF Studio.
- Internet access and a GitHub personal access token for GitHub operations.
- RAD Studio's ToolsAPI source directory for building the dockable windows. If the compiler cannot find `DockForm.pas` or `DeskUtil.pas`, add `$(BDS)\source\ToolsAPI` to the Win32 Delphi library path and project search path.

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
3. Choose **RADEssentials > Format X** or use the default shortcut **Ctrl+Alt+F**. The shortcut can be changed in **RADEssentials > Settings**.

Format X normalizes indentation and spacing while preserving the existing line structure. The operation is a single undo step and restores the editor position and selection state.

## Connect GitHub

1. Install Git for Windows if it is not already installed, then restart RAD Studio.
2. Open a project in the IDE and choose **RADEssentials > RADE Git**.
3. Select **Sign in to GitHub**, then choose **Create token on GitHub...**.
4. Create a personal access token and paste it into the sign-in form. Do not enter your GitHub password.
   For a classic token, select the `repo` scope. For a fine-grained token, grant **Contents: Read and write** and **Metadata: Read-only** for the repositories you need.
5. Return to RAD Studio and select **Sign in**. RAD Essentials validates the token and loads the repositories it can access.

The token is encrypted with Windows DPAPI for the current Windows user and stored at `%USERPROFILE%\RadeEssentials\git_token.dat`. Use **Sign out** to remove it. A token can be valid but still lack write access to a particular repository; the Git window reports the selected repository's push permission before upload. Branch protection rules can still reject a push.

## Publish a Project

1. Open the project you want to publish, then open **RADEssentials > RADE Git**. Press **Reload files** if the file tree does not reflect the current project.
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

- **RADEssentials > Settings** changes the Format X keyboard shortcut. Click a shortcut field and press the desired key combination to record it.
- The **Settings** button in the Git window opens Git settings for sign-in, release folder, and release asset masks.
- Git settings are stored in `%USERPROFILE%\RadeEssentials\git.ini`.
- The Git integration and its dockable window are also available from the IDE's **Help** menu.

## Troubleshooting

- **RADE Git is disabled or Git is not found:** install Git for Windows, confirm `git.exe` is on `PATH`, and restart RAD Studio.
- **No repositories appear:** press **Refresh**, check the internet connection, and verify that the token grants access to the repositories.
- **Push access is missing:** create a token with the required repository permissions. Organization access may also require organization approval or SSO authorization.
- **Push is rejected:** check the reported Git error and the repository's branch protection rules. If the remote contains commits absent locally, integrate them before retrying; force push only when it is safe to replace remote history.
- **The package does not compile:** use the RAD Studio command prompt for the installed compiler and confirm that `$(BDS)\source\ToolsAPI` is on the library and project search paths.

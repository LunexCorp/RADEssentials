unit RadeGit.HelpForm;

interface

procedure RadeGit_ShowHelp;
procedure RadeGit_CloseHelp;

implementation

uses
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  THelpForm = class(TForm)
  private
    FList: TListBox;
    FMemo: TMemo;
    procedure ListClick(Sender: TObject);
    procedure ShowSection(AIndex: Integer);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  GHelp: THelpForm;

procedure FillGitHelp(L: TStrings);
begin
  L.Clear;
  L.Add('RAD ESSENTIALS - GIT INTEGRATION');
  L.Add('');
  L.Add('Upload your project to GitHub from inside RAD Studio: pick files with');
  L.Add('checkboxes, choose a repository and branch, and push - no command line.');
  L.Add('');
  L.Add('1. BEFORE YOU START');
  L.Add('   Git must be installed (https://git-scm.com/downloads). If it is missing,');
  L.Add('   RAD Essentials shows a message and the Git menu item is greyed out.');
  L.Add('   Install Git, then restart RAD Studio.');
  L.Add('');
  L.Add('2. SIGN IN TO GITHUB');
  L.Add('   Open RAD Essentials > Git, then press "Sign in to GitHub"');
  L.Add('   (or use RAD Essentials Settings > Git). Create a personal access');
  L.Add('   token on GitHub, paste it into the sign-in form, and press Sign in.');
  L.Add('   Never enter your GitHub password in RAD Essentials. A classic token');
  L.Add('   needs the repo scope. A fine-grained token needs Contents read/write');
  L.Add('   and Metadata read-only for the repositories you want to use.');
  L.Add('   Your public AND private repositories are then loaded into the');
  L.Add('   repository drop-down. The token is stored encrypted for your Windows');
  L.Add('   user account. "Sign out" removes it.');
  L.Add('');
  L.Add('3. CHOOSE REPOSITORY AND BRANCH');
  L.Add('   Pick the repository from the first drop-down. The second drop-down lists');
  L.Add('   its branches (for example main). You can also type a new branch name.');
  L.Add('');
  L.Add('4. CHOOSE WHAT TO UPLOAD');
  L.Add('   The tree shows your project folder. Tick the files and folders you want');
  L.Add('   to upload; click a box (or press Space) to toggle it. Unticking a folder');
  L.Add('   unticks everything inside it. You can open folders and pick individual');
  L.Add('   files or folders. Use Select all / Select none for quick selection.');
  L.Add('   Only items you leave unticked are added to .gitignore; no defaults');
  L.Add('   are inserted. Items can be checked again before uploading.');
  L.Add('');
  L.Add('5. UPLOAD');
  L.Add('   Press "Upload to GitHub". A window lists what is currently in .gitignore');
  L.Add('   (those items will NOT be uploaded). Check it, edit it if needed, then');
  L.Add('   press Upload. RAD Essentials checks push access, saves .gitignore,');
  L.Add('   commits, and shows push progress while sending the changes.');
  L.Add('');
  L.Add('6. BUILD FILES (RELEASES)');
  L.Add('   If "Upload build folder as a GitHub release" is ticked, every file in');
  L.Add('   your build folder is attached to a new GitHub release - .exe, .apk, .bpl');
  L.Add('   and anything else. The build folder is found automatically (build,');
  L.Add('   Release, Win32\Release, Win64\Release, Output, bin) or you can set it in');
  L.Add('   Settings; use Browse to select it. You can also list masks (for example *.map) for');
  L.Add('   build files that should NOT be uploaded.');
  L.Add('');
  L.Add('7. TROUBLESHOOTING');
  L.Add('   - "Update was rejected": the repository already has commits you do not');
  L.Add('     have. Pull them first, or tick "Force push" to overwrite the remote.');
  L.Add('   - A file is still uploaded after ignoring it: Git keeps tracking files');
  L.Add('     it already uploaded before. Remove it with: git rm --cached <file>');
  L.Add('   - No repositories listed: press Refresh, or sign in again.');
end;

procedure FillPdfHelp(L: TStrings);
begin
  L.Clear;
  L.Add('PDF VIEWER');
  L.Add('');
  L.Add('Open PDF Viewer from RAD Essentials > PDF Viewer. It opens inside the');
  L.Add('active editor area. Use the editor tab and split-view controls to');
  L.Add('arrange it alongside code. Use Open to open documents in tabs.');
  L.Add('');
  L.Add('Use the recent-files dropdown to reopen documents. Close tab closes the');
  L.Add('selected document.');
  L.Add('Recent paths are stored for your Windows user.');
  L.Add('');
  L.Add('Use the zoom buttons or Ctrl+Numpad Plus / Ctrl+Numpad Minus. Ctrl+O opens PDFs and');
  L.Add('Ctrl+W closes the active tab. Edge WebView2 provides PDF page navigation,');
  L.Add('text search, printing, and other built-in reader tools.');
  L.Add('');
  L.Add('If the PDF area stays blank, install the Microsoft Edge WebView2 Runtime.');
end;

constructor THelpForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'RAD Essentials - Help';
  Position := poScreenCenter;
  ClientWidth := 720;
  ClientHeight := 520;

  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := alLeft;
  FList.Width := 150;
  FList.Items.Add('Git Integration');
  FList.Items.Add('Format X');
  FList.Items.Add('PDF Viewer');
  FList.Items.Add('Settings');
  FList.OnClick := ListClick;

  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.Align := alClient;
  FMemo.ReadOnly := True;
  FMemo.ScrollBars := ssVertical;
  FMemo.WordWrap := True;
  FMemo.Font.Name := 'Segoe UI';
  FMemo.Font.Size := 10;

  FList.ItemIndex := 0;
  ShowSection(0);
end;

procedure THelpForm.ListClick(Sender: TObject);
begin
  ShowSection(FList.ItemIndex);
end;

procedure THelpForm.ShowSection(AIndex: Integer);
begin
  if AIndex = 0 then
    FillGitHelp(FMemo.Lines)
  else if AIndex = 2 then
    FillPdfHelp(FMemo.Lines)
  else
  begin
    FMemo.Lines.Clear;
    FMemo.Lines.Add(FList.Items[AIndex]);
    FMemo.Lines.Add('');
    FMemo.Lines.Add('Help for this section is coming soon.');
  end;
end;

procedure RadeGit_ShowHelp;
begin
  if GHelp = nil then
    GHelp := THelpForm.Create(Application);
  GHelp.Show;
  GHelp.BringToFront;
end;

procedure RadeGit_CloseHelp;
begin
  FreeAndNil(GHelp);
end;

end.

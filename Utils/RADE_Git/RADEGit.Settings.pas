unit RadeGit.Settings;

interface

type
  TRadeGitSettings = record
    BuildFolder: string;     // relative to project root, or full path; '' = auto-detect
    ArtifactIgnore: string;  // masks separated by ';' (files NOT uploaded as release assets)
  end;

function RadeGit_LoadSettings: TRadeGitSettings;
procedure RadeGit_SaveSettings(const ASettings: TRadeGitSettings);

// GitHub device-flow sign-in with a small waiting window. True on success.
function RadeGit_SignIn: Boolean;

// Git settings dialog: sign in/out, build folder, artifact ignore list.
// Call this from your existing RAD Essentials Settings window.
procedure RadeGit_ShowSettingsDialog;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, System.Classes,
  System.IniFiles, System.IOUtils, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  Vcl.Dialogs, RadeGit.Core, RadeGit.OAuth;

const
  DEFAULT_IGNORE = '*.dcu;*.map;*.rsm;*.tds;*.drc;*.obj;*.ilc;*.ild;*.ilf;*.ils;*.tvsconfig';

function IniPath: string;
begin
  Result := TPath.Combine(RadeGitDataDir, 'git.ini');
end;

function RadeGit_LoadSettings: TRadeGitSettings;
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(IniPath);
  try
    Result.BuildFolder := LIni.ReadString('Build', 'Folder', '');
    Result.ArtifactIgnore := LIni.ReadString('Build', 'IgnoreMasks', DEFAULT_IGNORE);
  finally
    LIni.Free;
  end;
end;

procedure RadeGit_SaveSettings(const ASettings: TRadeGitSettings);
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(IniPath);
  try
    LIni.WriteString('Build', 'Folder', ASettings.BuildFolder);
    LIni.WriteString('Build', 'IgnoreMasks', ASettings.ArtifactIgnore);
  finally
    LIni.Free;
  end;
end;

{ ---- GitHub personal access token sign-in ---- }

type
  TTokenSignInForm = class(TForm)
  private
    FTokenEdit: TEdit;
    procedure OpenTokenPageClick(Sender: TObject);
    procedure SignInClick(Sender: TObject);
  public
    constructor CreateTokenForm;
  end;

constructor TTokenSignInForm.CreateTokenForm;
var
  LLabel: TLabel;
  LBtn: TButton;
begin
  inherited CreateNew(Application);
  Caption := 'GitHub sign-in';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 440;
  ClientHeight := 210;

  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.SetBounds(12, 12, 416, 42);
  LLabel.AutoSize := False;
  LLabel.WordWrap := True;
  LLabel.Caption := 'Create a GitHub personal access token, then enter it below. ' +
    'Do not enter your GitHub password.';

  LBtn := TButton.Create(Self);
  LBtn.Parent := Self;
  LBtn.SetBounds(12, 58, 190, 26);
  LBtn.Caption := 'Create token on GitHub...';
  LBtn.OnClick := OpenTokenPageClick;

  FTokenEdit := TEdit.Create(Self);
  FTokenEdit.Parent := Self;
  FTokenEdit.SetBounds(12, 94, 416, 23);
  FTokenEdit.PasswordChar := '*';

  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.SetBounds(12, 122, 416, 42);
  LLabel.AutoSize := False;
  LLabel.WordWrap := True;
  LLabel.Caption := 'Classic token: select the repo scope. Fine-grained token: grant ' +
    'Contents read/write and Metadata read-only for the repositories you need.';

  LBtn := TButton.Create(Self);
  LBtn.Parent := Self;
  LBtn.SetBounds(250, 174, 86, 26);
  LBtn.Caption := 'Sign in';
  LBtn.Default := True;
  LBtn.OnClick := SignInClick;

  LBtn := TButton.Create(Self);
  LBtn.Parent := Self;
  LBtn.SetBounds(342, 174, 86, 26);
  LBtn.Caption := 'Cancel';
  LBtn.Cancel := True;
  LBtn.ModalResult := mrCancel;
end;

procedure TTokenSignInForm.OpenTokenPageClick(Sender: TObject);
begin
  ShellExecute(0, 'open', PChar('https://github.com/settings/tokens/new'),
    nil, nil, SW_SHOWNORMAL);
end;

procedure TTokenSignInForm.SignInClick(Sender: TObject);
var
  LOAuth: TGitHubOAuth;
  LError: string;
begin
  LOAuth := TGitHubOAuth.Create;
  try
    if not LOAuth.ValidateToken(FTokenEdit.Text, LError) then
    begin
      ShowMessage('Could not sign in to GitHub:'#13#10 + LError);
      Exit;
    end;
    TGitHubOAuth.SaveToken(Trim(FTokenEdit.Text));
    ModalResult := mrOk;
  finally
    LOAuth.Free;
  end;
end;

function RadeGit_SignIn: Boolean;
var
  LForm: TTokenSignInForm;
begin
  LForm := TTokenSignInForm.CreateTokenForm;
  try
    Result := LForm.ShowModal = mrOk;
  finally
    LForm.Free;
  end;
end;

{ ---- settings dialog ---- }

type
  TGitSettingsDialog = class(TForm)
  private
    FStatus: TLabel;
    FBuild: TEdit;
    FIgnore: TMemo;
    procedure BrowseBuildClick(Sender: TObject);
    procedure UpdateStatus;
    procedure SignInClick(Sender: TObject);
    procedure SignOutClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
  public
    constructor CreateDialog;
  end;

constructor TGitSettingsDialog.CreateDialog;
var
  LSet: TRadeGitSettings;
  LBtn: TButton;
  LLabel: TLabel;
begin
  inherited CreateNew(Application);
  Caption := 'RAD Essentials - Git settings';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 420;
  ClientHeight := 380;

  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.SetBounds(12, 12, 200, 15);
  LLabel.Caption := 'GitHub account';

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(12, 32, 396, 15);

  LBtn := TButton.Create(Self);
  LBtn.Parent := Self;
  LBtn.SetBounds(12, 54, 130, 26);
  LBtn.Caption := 'Sign in to GitHub';
  LBtn.OnClick := SignInClick;

  LBtn := TButton.Create(Self);
  LBtn.Parent := Self;
  LBtn.SetBounds(150, 54, 90, 26);
  LBtn.Caption := 'Sign out';
  LBtn.OnClick := SignOutClick;

  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.SetBounds(12, 96, 396, 15);
  LLabel.Caption := 'Build / release folder (relative or absolute; empty = auto-detect):';

  FBuild := TEdit.Create(Self);
  FBuild.Parent := Self;
  FBuild.SetBounds(12, 116, 308, 23);

  LBtn := TButton.Create(Self);
  LBtn.Parent := Self;
  LBtn.SetBounds(328, 116, 80, 23);
  LBtn.Caption := 'Browse...';
  LBtn.OnClick := BrowseBuildClick;

  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.SetBounds(12, 152, 396, 15);
  LLabel.Caption := 'Build files NOT uploaded as release assets (one mask per line):';

  FIgnore := TMemo.Create(Self);
  FIgnore.Parent := Self;
  FIgnore.SetBounds(12, 172, 396, 150);
  FIgnore.ScrollBars := ssVertical;

  LBtn := TButton.Create(Self);
  LBtn.Parent := Self;
  LBtn.SetBounds(234, 340, 86, 28);
  LBtn.Caption := 'OK';
  LBtn.Default := True;
  LBtn.OnClick := OkClick;

  LBtn := TButton.Create(Self);
  LBtn.Parent := Self;
  LBtn.SetBounds(326, 340, 86, 28);
  LBtn.Caption := 'Cancel';
  LBtn.Cancel := True;
  LBtn.ModalResult := mrCancel;

  LSet := RadeGit_LoadSettings;
  FBuild.Text := LSet.BuildFolder;
  FIgnore.Lines.Text := LSet.ArtifactIgnore.Replace(';', sLineBreak);
  UpdateStatus;
end;

procedure TGitSettingsDialog.UpdateStatus;
begin
  if TGitHubOAuth.LoadToken <> '' then
    FStatus.Caption := 'Signed in (token stored encrypted for this Windows user).'
  else
    FStatus.Caption := 'Not signed in.';
end;

procedure TGitSettingsDialog.BrowseBuildClick(Sender: TObject);
var
  LDialog: TFileOpenDialog;
begin
  LDialog := TFileOpenDialog.Create(Self);
  try
    LDialog.Title := 'Select build / release folder';
    LDialog.Options := [fdoPickFolders, fdoPathMustExist, fdoForceFileSystem];
    if TDirectory.Exists(FBuild.Text) then
      LDialog.DefaultFolder := FBuild.Text;
    if LDialog.Execute then
      FBuild.Text := LDialog.FileName;
  finally
    LDialog.Free;
  end;
end;

procedure TGitSettingsDialog.SignInClick(Sender: TObject);
begin
  RadeGit_SignIn;
  UpdateStatus;
end;

procedure TGitSettingsDialog.SignOutClick(Sender: TObject);
begin
  TGitHubOAuth.ClearToken;
  UpdateStatus;
end;

procedure TGitSettingsDialog.OkClick(Sender: TObject);
var
  LSet: TRadeGitSettings;
  LLine, LMasks: string;
begin
  LMasks := '';
  for LLine in FIgnore.Lines do
    if Trim(LLine) <> '' then
    begin
      if LMasks <> '' then
        LMasks := LMasks + ';';
      LMasks := LMasks + Trim(LLine);
    end;
  LSet.BuildFolder := Trim(FBuild.Text);
  LSet.ArtifactIgnore := LMasks;
  RadeGit_SaveSettings(LSet);
  ModalResult := mrOk;
end;

procedure RadeGit_ShowSettingsDialog;
var
  LDlg: TGitSettingsDialog;
begin
  LDlg := TGitSettingsDialog.CreateDialog;
  try
    LDlg.ShowModal;
  finally
    LDlg.Free;
  end;
end;

end.

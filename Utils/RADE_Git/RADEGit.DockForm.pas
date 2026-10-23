unit RadeGit.DockForm;

// Dockable "RADE Git" window. The UI is built in code (no .dfm needed).
// Requires the IDE units DockForm.pas / DeskUtil.pas (see INTEGRATION.md).

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils,
  System.StrUtils, System.Masks, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ImgList, DeskUtil, DockForm, ToolsAPI,
  RadeGit.Core, RadeGit.OAuth, RadeGit.RepoApi, RadeGit.FileTree,
  RadeGit.GitignoreMgr, RadeGit.Settings;

type
  TfrmRadeGitDock = class(TDockableForm)
  private
    PnlTop, PnlBottom: TPanel;
    BtnSignIn, BtnRefresh, BtnReload, BtnUpload, BtnSettings: TButton;
    BtnSelectAll, BtnSelectNone: TButton;
    CmbRepo, CmbBranch: TComboBox;
    TreeFiles: TTreeView;
    ChkRelease, ChkForce: TCheckBox;
    LblStatus: TLabel;
    ProgressPush: TProgressBar;
    FPushOutput: string;

    FProjectRoot: string;
    FGit: TGitCore;
    FIgnore: TGitignoreManager;
    FBuilder: TFileTreeBuilder;
    FRootNode: TFileNode;
    FNodeMap: TDictionary<TTreeNode, TFileNode>;
    FRepos: TArray<TRepoInfo>;
    FToken: string;

    procedure BuildUI;
    function GetProjectRoot: string;
    procedure FreeProjectObjects;
    procedure PopulateTree;
    procedure AddNodeRec(AParent: TTreeNode; AFile: TFileNode);
    procedure ToggleNode(ANode: TTreeNode);
    procedure RefreshGlyphs;
    procedure TreeMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SelectAllClick(Sender: TObject);
    procedure SelectNoneClick(Sender: TObject);
    procedure PushOutput(const AText: string);
    procedure UpdateAuthState;
    procedure SetStatus(const AText: string);
    procedure RefreshRepos;
    procedure DoUpload;
    procedure UploadBuildArtifacts(const ARepo: TRepoInfo; const ABranch: string);
    function FindBuildFolder(const ASettings: TRadeGitSettings): string;

    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SignInClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure RepoChanged(Sender: TObject);
    procedure UploadClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ReloadProject(AForce: Boolean);
  end;

procedure RadeGit_RegisterDock;
procedure RadeGit_ShowDock;
procedure RadeGit_FreeDock;

implementation

{$R *.dfm}

var
  GRadeGitDock: TfrmRadeGitDock;
  GRegistered: Boolean;

procedure RadeGit_RegisterDock;
begin
  if GRegistered then
    Exit;
  RegisterFieldAddress('RadeGitDock', @GRadeGitDock);
  RegisterDesktopFormClass(TfrmRadeGitDock, 'RadeGitDock', 'RadeGitDock');
  GRegistered := True;
end;

procedure RadeGit_ShowDock;
begin
  if GRadeGitDock = nil then
    GRadeGitDock := TfrmRadeGitDock.Create(Application);
  if not GRadeGitDock.Floating then
    GRadeGitDock.ForceShow
  else
    GRadeGitDock.Show;
  FocusWindow(GRadeGitDock);
  GRadeGitDock.ReloadProject(False);
end;

procedure RadeGit_FreeDock;
begin
  if GRegistered then
  begin
    UnregisterFieldAddress(@GRadeGitDock);
    GRegistered := False;
  end;
  FreeAndNil(GRadeGitDock);
end;

{ Confirmation dialog: shows the .gitignore and lets the user edit it }

function ConfirmGitignore(var AText: string): Boolean;
var
  LForm: TForm;
  LLabel: TLabel;
  LMemo: TMemo;
  LBtn: TButton;
begin
  LForm := TForm.CreateNew(Application);
  try
    LForm.Caption := 'Confirm files to upload';
    LForm.Position := poScreenCenter;
    LForm.BorderStyle := bsSizeable;
    LForm.ClientWidth := 440;
    LForm.ClientHeight := 420;

    LLabel := TLabel.Create(LForm);
    LLabel.Parent := LForm;
    LLabel.Align := alTop;
    LLabel.AutoSize := False;
    LLabel.WordWrap := True;
    LLabel.Height := 56;
    LLabel.Caption := ' These entries are currently in .gitignore, so they will NOT be ' +
      'uploaded. Check that you are happy with this list. You can edit it here; ' +
      'press Upload to save it to .gitignore and continue.';

    LMemo := TMemo.Create(LForm);
    LMemo.Parent := LForm;
    LMemo.Align := alClient;
    LMemo.ScrollBars := ssBoth;
    LMemo.Font.Name := 'Consolas';
    LMemo.Lines.Text := AText;

    LBtn := TButton.Create(LForm);
    LBtn.Parent := LForm;
    LBtn.SetBounds(LForm.ClientWidth - 190, LForm.ClientHeight - 36, 86, 28);
    LBtn.Anchors := [akRight, akBottom];
    LBtn.Caption := 'Upload';
    LBtn.ModalResult := mrOk;
    LBtn.Default := True;

    LBtn := TButton.Create(LForm);
    LBtn.Parent := LForm;
    LBtn.SetBounds(LForm.ClientWidth - 98, LForm.ClientHeight - 36, 86, 28);
    LBtn.Anchors := [akRight, akBottom];
    LBtn.Caption := 'Cancel';
    LBtn.ModalResult := mrCancel;
    LBtn.Cancel := True;

    // keep the buttons clear of the memo
    LMemo.AlignWithMargins := True;
    LMemo.Margins.Bottom := 44;

    Result := LForm.ShowModal = mrOk;
    if Result then
      AText := LMemo.Lines.Text;
  finally
    LForm.Free;
  end;
end;

{ TfrmRadeGitDock }

constructor TfrmRadeGitDock.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Name := 'RadeGitDock';
  Caption := 'RADE Git';
  DeskSection := 'RadeGitDock';
  AutoSave := True;
  SaveStateNecessary := True;
  ClientWidth := 340;
  ClientHeight := 520;
  FNodeMap := TDictionary<TTreeNode, TFileNode>.Create;
  BuildUI;
end;

destructor TfrmRadeGitDock.Destroy;
begin
  FreeProjectObjects;
  FNodeMap.Free;
  if GRadeGitDock = Self then
    GRadeGitDock := nil;
  inherited;
end;

procedure TfrmRadeGitDock.BuildUI;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 128;
  PnlTop.BevelOuter := bvNone;

  BtnSignIn := TButton.Create(Self);
  BtnSignIn.Parent := PnlTop;
  BtnSignIn.SetBounds(6, 6, 112, 26);
  BtnSignIn.Caption := 'Sign in to GitHub';
  BtnSignIn.OnClick := SignInClick;

  BtnRefresh := TButton.Create(Self);
  BtnRefresh.Parent := PnlTop;
  BtnRefresh.SetBounds(124, 6, 80, 26);
  BtnRefresh.Caption := 'Refresh';
  BtnRefresh.OnClick := RefreshClick;

  BtnReload := TButton.Create(Self);
  BtnReload.Parent := PnlTop;
  BtnReload.SetBounds(210, 6, 90, 26);
  BtnReload.Caption := 'Reload files';
  BtnReload.OnClick := ReloadClick;

  CmbRepo := TComboBox.Create(Self);
  CmbRepo.Parent := PnlTop;
  CmbRepo.SetBounds(6, 40, 320, 23);
  CmbRepo.Anchors := [akLeft, akTop, akRight];
  CmbRepo.Style := csDropDownList;
  CmbRepo.OnChange := RepoChanged;

  CmbBranch := TComboBox.Create(Self);
  CmbBranch.Parent := PnlTop;
  CmbBranch.SetBounds(6, 68, 320, 23);
  CmbBranch.Anchors := [akLeft, akTop, akRight];
  CmbBranch.Style := csDropDown; // pick a branch or type a new name

  BtnSelectAll := TButton.Create(Self);
  BtnSelectAll.Parent := PnlTop;
  BtnSelectAll.SetBounds(6, 96, 84, 24);
  BtnSelectAll.Caption := 'Select all';
  BtnSelectAll.OnClick := SelectAllClick;

  BtnSelectNone := TButton.Create(Self);
  BtnSelectNone.Parent := PnlTop;
  BtnSelectNone.SetBounds(96, 96, 92, 24);
  BtnSelectNone.Caption := 'Select none';
  BtnSelectNone.OnClick := SelectNoneClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 136;
  PnlBottom.BevelOuter := bvNone;

  ChkRelease := TCheckBox.Create(Self);
  ChkRelease.Parent := PnlBottom;
  ChkRelease.SetBounds(6, 4, 320, 20);
  ChkRelease.Caption := 'Upload build folder as a GitHub release';
  ChkRelease.Checked := True;

  ChkForce := TCheckBox.Create(Self);
  ChkForce.Parent := PnlBottom;
  ChkForce.SetBounds(6, 26, 320, 20);
  ChkForce.Caption := 'Force push (overwrites remote history)';

  BtnUpload := TButton.Create(Self);
  BtnUpload.Parent := PnlBottom;
  BtnUpload.SetBounds(6, 52, 140, 28);
  BtnUpload.Caption := 'Upload to GitHub';
  BtnUpload.OnClick := UploadClick;

  BtnSettings := TButton.Create(Self);
  BtnSettings.Parent := PnlBottom;
  BtnSettings.SetBounds(152, 52, 80, 28);
  BtnSettings.Caption := 'Settings';
  BtnSettings.OnClick := SettingsClick;

  ProgressPush := TProgressBar.Create(Self);
  ProgressPush.Parent := PnlBottom;
  ProgressPush.SetBounds(6, 86, 320, 16);
  ProgressPush.Anchors := [akLeft, akTop, akRight];
  ProgressPush.Min := 0;
  ProgressPush.Max := 100;
  ProgressPush.Position := 0;
  ProgressPush.Visible := False;

  LblStatus := TLabel.Create(Self);
  LblStatus.Parent := PnlBottom;
  LblStatus.SetBounds(6, 108, 320, 18);
  LblStatus.Anchors := [akLeft, akTop, akRight];
  LblStatus.AutoSize := False;
  LblStatus.EllipsisPosition := epEndEllipsis;

  TreeFiles := TTreeView.Create(Self);
  TreeFiles.Parent := Self;
  TreeFiles.Align := alClient;
  TreeFiles.Checkboxes := True;
  TreeFiles.HideSelection := False;
  TreeFiles.OnMouseUp := TreeMouseUp;
  TreeFiles.OnKeyDown := TreeKeyDown;

  if not RadeGit_CheckGitInstalledOnce then
  begin
    BtnUpload.Enabled := False;
    SetStatus('Git is not installed - install it from git-scm.com, then restart RAD Studio.');
  end;
  UpdateAuthState;
end;

procedure TfrmRadeGitDock.SetStatus(const AText: string);
begin
  LblStatus.Caption := AText;
  LblStatus.Hint := AText;
  LblStatus.ShowHint := True;
  LblStatus.Update;
end;

function TfrmRadeGitDock.GetProjectRoot: string;
var
  LSvc: IOTAModuleServices;
  LGroup: IOTAProjectGroup;
  LProject: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, LSvc) then
    Exit;
  LGroup := LSvc.MainProjectGroup;
  if LGroup = nil then
    Exit;
  LProject := LGroup.ActiveProject;
  if LProject <> nil then
    Result := TPath.GetDirectoryName(LProject.FileName);
end;

procedure TfrmRadeGitDock.FreeProjectObjects;
begin
  if FNodeMap <> nil then
    FNodeMap.Clear;
  if TreeFiles <> nil then
    TreeFiles.Items.Clear;
  FreeAndNil(FBuilder);
  FreeAndNil(FRootNode);
  FreeAndNil(FIgnore);
  FreeAndNil(FGit);
end;

procedure TfrmRadeGitDock.ReloadProject(AForce: Boolean);
var
  LRoot: string;
begin
  LRoot := GetProjectRoot;
  if (not AForce) and (LRoot = FProjectRoot) and (FRootNode <> nil) then
    Exit;
  FreeProjectObjects;
  FProjectRoot := LRoot;
  if FProjectRoot = '' then
  begin
    SetStatus('Open a project first, then press "Reload files".');
    Exit;
  end;
  FGit := TGitCore.Create(FProjectRoot);
  FIgnore := TGitignoreManager.Create(FProjectRoot);
  FBuilder := TFileTreeBuilder.Create(FProjectRoot, FIgnore);
  FRootNode := FBuilder.BuildTree;
  PopulateTree;
  UpdateAuthState;
  if (FToken <> '') and (Length(FRepos) = 0) then
    RefreshRepos
  else if FToken = '' then
    SetStatus('Sign in to GitHub to pick a repository.');
end;

procedure TfrmRadeGitDock.PopulateTree;
begin
  TreeFiles.Items.BeginUpdate;
  try
    TreeFiles.Items.Clear;
    FNodeMap.Clear;
    if FRootNode <> nil then
      AddNodeRec(nil, FRootNode);
    if TreeFiles.Items.GetFirstNode <> nil then
      TreeFiles.Items.GetFirstNode.Expand(False);
  finally
    TreeFiles.Items.EndUpdate;
  end;
end;

procedure TfrmRadeGitDock.AddNodeRec(AParent: TTreeNode; AFile: TFileNode);
var
  LNode: TTreeNode;
  LChild: TFileNode;
  LCaption: string;
begin
  LCaption := AFile.DisplayName;
  if LCaption = '' then
    LCaption := AFile.FullPath;
  LNode := TreeFiles.Items.AddChild(AParent, LCaption);
  LNode.Checked := AFile.Checked;
  FNodeMap.Add(LNode, AFile);
  for LChild in AFile.Children do
    AddNodeRec(LNode, LChild);
end;

procedure TfrmRadeGitDock.RefreshGlyphs;
var
  LPair: TPair<TTreeNode, TFileNode>;
begin
  for LPair in FNodeMap do
    LPair.Key.Checked := LPair.Value.Checked;
  TreeFiles.Invalidate;
end;

procedure TfrmRadeGitDock.ToggleNode(ANode: TTreeNode);
var
  LFile: TFileNode;
begin
  if FNodeMap.TryGetValue(ANode, LFile) then
  begin
    LFile.SetCheckedRecursive(not LFile.Checked);
    LFile.UpdateParentCheckState;
    RefreshGlyphs;
  end;
end;

procedure TfrmRadeGitDock.TreeMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  LNode: TTreeNode;
  LFile: TFileNode;
begin
  if not (htOnStateIcon in TreeFiles.GetHitTestInfoAt(X, Y)) then
    Exit;
  LNode := TreeFiles.GetNodeAt(X, Y);
  if (LNode <> nil) and FNodeMap.TryGetValue(LNode, LFile) then
  begin
    LFile.SetCheckedRecursive(LNode.Checked);
    LFile.UpdateParentCheckState;
    RefreshGlyphs;
  end;
end;

procedure TfrmRadeGitDock.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) and (TreeFiles.Selected <> nil) then
  begin
    ToggleNode(TreeFiles.Selected);
    Key := 0;
  end;
end;

procedure TfrmRadeGitDock.SignInClick(Sender: TObject);
begin
  if TGitHubOAuth.LoadToken <> '' then
  begin
    TGitHubOAuth.ClearToken;
    FRepos := nil;
    CmbRepo.Clear;
    CmbBranch.Clear;
    UpdateAuthState;
    SetStatus('Signed out of GitHub.');
    Exit;
  end;
  if RadeGit_SignIn then
  begin
    UpdateAuthState;
    RefreshRepos;
  end;
end;

procedure TfrmRadeGitDock.RefreshClick(Sender: TObject);
begin
  RefreshRepos;
end;

procedure TfrmRadeGitDock.ReloadClick(Sender: TObject);
begin
  ReloadProject(True);
end;

procedure TfrmRadeGitDock.SettingsClick(Sender: TObject);
begin
  RadeGit_ShowSettingsDialog;
  UpdateAuthState;
  if FToken <> '' then
    RefreshRepos
  else
  begin
    FRepos := nil;
    CmbRepo.Clear;
    CmbBranch.Clear;
    SetStatus('Signed out of GitHub.');
  end;
end;

procedure TfrmRadeGitDock.UpdateAuthState;
begin
  FToken := TGitHubOAuth.LoadToken;
  if FToken = '' then
    BtnSignIn.Caption := 'Sign in to GitHub'
  else
    BtnSignIn.Caption := 'Sign out';
end;

procedure TfrmRadeGitDock.RefreshRepos;
var
  LApi: TGitHubRepoApi;
  LRepo: TRepoInfo;
begin
  FToken := TGitHubOAuth.LoadToken;
  if FToken = '' then
  begin
    SetStatus('Sign in to GitHub first.');
    Exit;
  end;
  SetStatus('Loading repositories...');
  LApi := TGitHubRepoApi.Create(FToken);
  try
    FRepos := LApi.ListUserRepos;
    CmbRepo.Items.BeginUpdate;
    try
      CmbRepo.Items.Clear;
      for LRepo in FRepos do
        CmbRepo.Items.Add(LRepo.FullName + IfThen(LRepo.IsPrivate, '  (private)', '  (public)'));
    finally
      CmbRepo.Items.EndUpdate;
    end;
    if Length(FRepos) > 0 then
    begin
      CmbRepo.ItemIndex := 0;
      RepoChanged(nil);
    end
    else
      SetStatus('No repositories found. ' + LApi.LastError);
  finally
    LApi.Free;
  end;
end;

procedure TfrmRadeGitDock.RepoChanged(Sender: TObject);
var
  LApi: TGitHubRepoApi;
  LBranch, LDefault: string;
begin
  if (CmbRepo.ItemIndex < 0) or (CmbRepo.ItemIndex >= Length(FRepos)) then
    Exit;
  LDefault := FRepos[CmbRepo.ItemIndex].DefaultBranch;
  LApi := TGitHubRepoApi.Create(FToken);
  try
    CmbBranch.Items.BeginUpdate;
    try
      CmbBranch.Items.Clear;
      for LBranch in LApi.ListBranches(FRepos[CmbRepo.ItemIndex].FullName) do
        CmbBranch.Items.Add(LBranch);
    finally
      CmbBranch.Items.EndUpdate;
    end;
    CmbBranch.ItemIndex := CmbBranch.Items.IndexOf(LDefault);
    if (CmbBranch.ItemIndex < 0) then
      CmbBranch.Text := LDefault; // empty repo: default branch name still usable
    if LApi.CanPushToRepo(FRepos[CmbRepo.ItemIndex].FullName) then
      SetStatus('Push access confirmed for ' + FRepos[CmbRepo.ItemIndex].FullName + '.')
    else
      SetStatus('No push access: ' + LApi.LastError);
  finally
    LApi.Free;
  end;
end;

procedure TfrmRadeGitDock.SelectAllClick(Sender: TObject);
begin
  if FRootNode <> nil then
  begin
    FRootNode.SetCheckedRecursive(True);
    RefreshGlyphs;
  end;
end;

procedure TfrmRadeGitDock.SelectNoneClick(Sender: TObject);
begin
  if FRootNode <> nil then
  begin
    FRootNode.SetCheckedRecursive(False);
    RefreshGlyphs;
  end;
end;

procedure TfrmRadeGitDock.PushOutput(const AText: string);
var
  LCombined, LNumber: string;
  LPercentPos, LStart, LPercent, LCopyStart: Integer;
begin
  LCombined := FPushOutput + AText;
  LCopyStart := Length(LCombined) - 255;
  if LCopyStart < 1 then
    LCopyStart := 1;
  FPushOutput := Copy(LCombined, LCopyStart, 256);
  LPercentPos := FPushOutput.LastIndexOf('%');
  if LPercentPos >= 0 then
  begin
    LStart := LPercentPos;
    while (LStart > 1) and CharInSet(FPushOutput[LStart - 1], ['0'..'9']) do
      Dec(LStart);
    LNumber := Copy(FPushOutput, LStart, LPercentPos - LStart);
    if TryStrToInt(LNumber, LPercent) then
    begin
      ProgressPush.Style := pbstNormal;
      if LPercent < 0 then
        LPercent := 0
      else if LPercent > 100 then
        LPercent := 100;
      ProgressPush.Position := LPercent;
    end;
  end;
  ProgressPush.Update;
  Application.ProcessMessages;
end;

procedure TfrmRadeGitDock.UploadClick(Sender: TObject);
begin
  BtnUpload.Enabled := False;
  try
    DoUpload;
  finally
    BtnUpload.Enabled := FGit <> nil;
    if (FGit <> nil) and (not FGit.IsGitInstalled) then
      BtnUpload.Enabled := False;
  end;
end;

procedure TfrmRadeGitDock.DoUpload;
var
  LText, LBranch, LUrl: string;
  LRes: TGitResult;
  LRepo: TRepoInfo;
  LApi: TGitHubRepoApi;
begin
  if (FGit = nil) or (FRootNode = nil) then
  begin
    ShowMessage('Open a project first, then press "Reload files".');
    Exit;
  end;
  if not FGit.IsGitInstalled then
  begin
    ShowMessage('Git is not installed. Get it from https://git-scm.com/downloads and restart RAD Studio.');
    Exit;
  end;
  FToken := TGitHubOAuth.LoadToken;
  if FToken = '' then
  begin
    ShowMessage('Please sign in to GitHub first.');
    Exit;
  end;
  if (CmbRepo.ItemIndex < 0) or (CmbRepo.ItemIndex >= Length(FRepos)) then
  begin
    ShowMessage('Please choose a repository first.');
    Exit;
  end;
  LRepo := FRepos[CmbRepo.ItemIndex];
  LBranch := Trim(CmbBranch.Text);
  if LBranch = '' then
    LBranch := LRepo.DefaultBranch;

  LApi := TGitHubRepoApi.Create(FToken);
  try
    if not LApi.CanPushToRepo(LRepo.FullName) then
    begin
      SetStatus('Push access check failed.');
      ShowMessage('This token cannot push to ' + LRepo.FullName + ':'#13#10 +
        LApi.LastError + #13#10#13#10 +
        'Use a token with Contents: Read and write access, or the classic repo scope.');
      Exit;
    end;
  finally
    LApi.Free;
  end;

  // 1. unchecked items -> .gitignore, then let the user confirm/edit it
  FBuilder.SyncGitignoreFromTree(FRootNode);
  LText := FIgnore.GetText;
  if not ConfirmGitignore(LText) then
    Exit;
  FIgnore.SetText(LText);
  FIgnore.Save;

  // 2. init / remote / stage / commit
  SetStatus('Preparing repository...');
  if not FGit.IsRepoInitialized then
  begin
    LRes := FGit.InitRepo;
    if not LRes.Success then
    begin
      ShowMessage('git init failed:'#13#10 + LRes.ErrorOutput);
      Exit;
    end;
  end;
  LUrl := LRepo.CloneUrl;
  if LUrl = '' then
    LUrl := 'https://github.com/' + LRepo.FullName + '.git';
  FGit.SetRemote('origin', LUrl);

  SetStatus('Staging files...');
  LRes := FGit.AddAll;
  if not LRes.Success then
  begin
    ShowMessage('git add failed:'#13#10 + LRes.ErrorOutput);
    Exit;
  end;

  SetStatus('Committing...');
  LRes := FGit.Commit('Update from RAD Essentials');
  if (not LRes.Success) and (not ContainsText(LRes.Output, 'nothing to commit')) then
  begin
    ShowMessage('git commit failed:'#13#10 + LRes.ErrorOutput);
    Exit;
  end;

  // 3. push
  SetStatus(Format('Checking push access to %s (%s)...', [LRepo.FullName, LBranch]));
  LRes := FGit.PushToUrl(LUrl, LBranch, FToken, ChkForce.Checked, True);
  if not LRes.Success then
  begin
    SetStatus('Push access check failed.');
    ShowMessage('Git could not verify this push:'#13#10 + LRes.ErrorOutput);
    Exit;
  end;

  SetStatus(Format('Pushing to %s (%s)...', [LRepo.FullName, LBranch]));
  FPushOutput := '';
  ProgressPush.Position := 0;
  ProgressPush.Style := pbstMarquee;
  ProgressPush.Visible := True;
  LRes := FGit.PushToUrl(LUrl, LBranch, FToken, ChkForce.Checked, False, PushOutput);
  if not LRes.Success then
  begin
    SetStatus('Push failed.');
    ShowMessage('Push failed:'#13#10 + LRes.ErrorOutput +
      #13#10#13#10'If the message says the update was rejected, the remote already has ' +
      'commits this project does not. Pull them first, or tick "Force push" if you ' +
      'really want to overwrite the remote.');
    Exit;
  end;
  ProgressPush.Style := pbstNormal;
  ProgressPush.Position := 100;
  SetStatus('Push succeeded.');

  // 4. build artifacts as a release
  if ChkRelease.Checked then
    UploadBuildArtifacts(LRepo, LBranch);
end;

function TfrmRadeGitDock.FindBuildFolder(const ASettings: TRadeGitSettings): string;
const
  CANDIDATES: array[0..6] of string =
    ('build', 'Build', 'Release', 'Win32\Release', 'Win64\Release', 'Output', 'bin');
var
  I: Integer;
  LPath: string;
begin
  Result := '';
  if ASettings.BuildFolder <> '' then
  begin
    LPath := ASettings.BuildFolder;
    if not TPath.IsPathRooted(LPath) then
      LPath := TPath.Combine(FProjectRoot, LPath);
    if TDirectory.Exists(LPath) then
      Result := LPath;
    Exit;
  end;
  for I := Low(CANDIDATES) to High(CANDIDATES) do
  begin
    LPath := TPath.Combine(FProjectRoot, CANDIDATES[I]);
    if TDirectory.Exists(LPath) then
      Exit(LPath);
  end;
end;

procedure TfrmRadeGitDock.UploadBuildArtifacts(const ARepo: TRepoInfo; const ABranch: string);
var
  LSettings: TRadeGitSettings;
  LFolder, LFile, LName, LMask: string;
  LMasks: TArray<string>;
  LArtifacts, LSeen: TStringList;
  LSkip: Boolean;
  LApi: TGitHubRepoApi;
  LUploadUrl: string;
  LOk, LFail: Integer;
begin
  LSettings := RadeGit_LoadSettings;
  LFolder := FindBuildFolder(LSettings);
  if LFolder = '' then
  begin
    SetStatus('Push succeeded. No build folder found, so no release was made.');
    Exit;
  end;
  LMasks := LSettings.ArtifactIgnore.Split([';']);

  LArtifacts := TStringList.Create;
  LSeen := TStringList.Create;
  try
    LSeen.CaseSensitive := False;
    for LFile in TDirectory.GetFiles(LFolder, '*', TSearchOption.soAllDirectories) do
    begin
      LName := TPath.GetFileName(LFile);
      LSkip := False;
      for LMask in LMasks do
        if (Trim(LMask) <> '') and MatchesMask(LName, Trim(LMask)) then
        begin
          LSkip := True;
          Break;
        end;
      // GitHub rejects two assets with the same name in one release
      if (not LSkip) and (LSeen.IndexOf(LName) < 0) then
      begin
        LSeen.Add(LName);
        LArtifacts.Add(LFile);
      end;
    end;

    if LArtifacts.Count = 0 then
    begin
      SetStatus('Push succeeded. Build folder had nothing to upload.');
      Exit;
    end;

    SetStatus('Creating GitHub release...');
    LApi := TGitHubRepoApi.Create(FToken);
    try
      if not LApi.CreateRelease(ARepo.FullName,
        'build-' + FormatDateTime('yyyymmdd-hhnnss', Now),
        'Build ' + FormatDateTime('yyyy-mm-dd hh:nn', Now),
        'Build artifacts uploaded by RAD Essentials.', ABranch, LUploadUrl) then
      begin
        SetStatus('Push OK, but creating the release failed.');
        ShowMessage('Could not create the GitHub release:'#13#10 + LApi.LastError);
        Exit;
      end;
      LOk := 0;
      LFail := 0;
      for LFile in LArtifacts do
      begin
        SetStatus('Uploading ' + TPath.GetFileName(LFile) + '...');
        Application.ProcessMessages;
        if LApi.UploadReleaseAsset(LUploadUrl, LFile) then
          Inc(LOk)
        else
          Inc(LFail);
      end;
      if LFail = 0 then
        SetStatus(Format('Done. Pushed and uploaded %d build file(s).', [LOk]))
      else
      begin
        SetStatus(Format('Pushed. %d file(s) uploaded, %d failed.', [LOk, LFail]));
        ShowMessage(Format('%d build file(s) failed to upload. Last error:'#13#10'%s',
          [LFail, LApi.LastError]));
      end;
    finally
      LApi.Free;
    end;
  finally
    LArtifacts.Free;
    LSeen.Free;
  end;
end;

end.

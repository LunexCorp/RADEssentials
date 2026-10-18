unit RadeGit.Core;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils,
  System.NetEncoding, System.UITypes, Vcl.Dialogs;

type
  TGitOutputEvent = procedure(const AText: string) of object;

  TGitResult = record
    Success: Boolean;
    ExitCode: Cardinal;
    Output: string;       // stdout + stderr merged
    ErrorOutput: string;  // same as Output when the command failed
  end;

  TGitCore = class
  private
    FRepoPath: string;
    FGitExePath: string;
    function FindGitExecutable: string;
    function RunGit(const AArgs: string; AOnOutput: TGitOutputEvent = nil): TGitResult;
  public
    constructor Create(const ARepoPath: string);
    function IsGitInstalled: Boolean;
    function IsRepoInitialized: Boolean;
    function InitRepo: TGitResult;
    function AddAll: TGitResult;
    function Commit(const AMessage: string): TGitResult;
    function SetRemote(const AName, AUrl: string): TGitResult;
    // Pushes HEAD to a branch using a one-off auth header, so the token is
    // never written into .git/config or the remote URL.
    function PushToUrl(const ARepoUrl, ABranch, AToken: string;
      AForce: Boolean; ADryRun: Boolean = False;
      AOnOutput: TGitOutputEvent = nil): TGitResult;
    function GetCurrentBranch: string;
    property RepoPath: string read FRepoPath;
    property GitExePath: string read FGitExePath;
  end;

// Folder where RAD Essentials keeps git.ini and the encrypted token
function RadeGitDataDir: string;

// Checks once per IDE session; shows the "install Git" message the first time
// it finds Git missing. Returns True when Git is available.
function RadeGit_CheckGitInstalledOnce: Boolean;

implementation

var
  GCheckDone: Boolean = False;
  GGitAvailable: Boolean = False;

function RadeGitDataDir: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, 'RadeEssentials');
  ForceDirectories(Result);
end;

function RadeGit_CheckGitInstalledOnce: Boolean;
var
  LCore: TGitCore;
begin
  if not GCheckDone then
  begin
    GCheckDone := True;
    LCore := TGitCore.Create('');
    try
      GGitAvailable := LCore.IsGitInstalled;
    finally
      LCore.Free;
    end;
    if not GGitAvailable then
      MessageDlg(
        'Git was not found on this computer, so the Git features of RAD Essentials ' +
        'are disabled for now.'#13#10#13#10 +
        'Download Git from: https://git-scm.com/downloads'#13#10#13#10 +
        'After installing it, restart RAD Studio and the Git features will unlock.',
        mtWarning, [mbOK], 0);
  end;
  Result := GGitAvailable;
end;

{ TGitCore }

constructor TGitCore.Create(const ARepoPath: string);
begin
  inherited Create;
  FRepoPath := ARepoPath;
  FGitExePath := FindGitExecutable;
  // Never let git block waiting for a console prompt inside the IDE
  SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0');
end;

function TGitCore.FindGitExecutable: string;
var
  LDir, LCandidate, LProgFiles, LLocal: string;
begin
  for LDir in GetEnvironmentVariable('PATH').Split([';']) do
  begin
    if Trim(LDir) = '' then
      Continue;
    LCandidate := IncludeTrailingPathDelimiter(Trim(LDir)) + 'git.exe';
    if TFile.Exists(LCandidate) then
      Exit(LCandidate);
  end;
  LProgFiles := GetEnvironmentVariable('ProgramFiles');
  LLocal := GetEnvironmentVariable('LOCALAPPDATA');
  for LCandidate in [
    TPath.Combine(LProgFiles, 'Git\cmd\git.exe'),
    TPath.Combine(LProgFiles, 'Git\bin\git.exe'),
    'C:\Program Files (x86)\Git\cmd\git.exe',
    TPath.Combine(LLocal, 'Programs\Git\cmd\git.exe')] do
    if TFile.Exists(LCandidate) then
      Exit(LCandidate);
  Result := '';
end;

function TGitCore.IsGitInstalled: Boolean;
begin
  Result := FGitExePath <> '';
end;

function TGitCore.IsRepoInitialized: Boolean;
begin
  Result := TDirectory.Exists(TPath.Combine(FRepoPath, '.git'));
end;

function TGitCore.RunGit(const AArgs: string; AOnOutput: TGitOutputEvent): TGitResult;
var
  LSA: TSecurityAttributes;
  LRead, LWrite: THandle;
  LSI: TStartupInfo;
  LPI: TProcessInformation;
  LCmd: string;
  LBuf: array[0..4095] of Byte;
  LBytesRead, LExit: DWORD;
  LStream: TMemoryStream;
  LBytes: TBytes;
  LText: string;
  LDir: PChar;
begin
  Result := Default(TGitResult);
  if not IsGitInstalled then
  begin
    Result.ErrorOutput := 'Git executable not found.';
    Exit;
  end;

  LSA.nLength := SizeOf(LSA);
  LSA.bInheritHandle := True;
  LSA.lpSecurityDescriptor := nil;
  if not CreatePipe(LRead, LWrite, @LSA, 0) then
  begin
    Result.ErrorOutput := SysErrorMessage(GetLastError);
    Exit;
  end;
  SetHandleInformation(LRead, HANDLE_FLAG_INHERIT, 0);
  try
    FillChar(LSI, SizeOf(LSI), 0);
    LSI.cb := SizeOf(LSI);
    LSI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    LSI.wShowWindow := SW_HIDE;
    LSI.hStdOutput := LWrite;
    LSI.hStdError := LWrite; // one shared pipe => no stdout/stderr deadlock

    LCmd := '"' + FGitExePath + '" ' + AArgs;
    UniqueString(LCmd);
    if FRepoPath <> '' then LDir := PChar(FRepoPath) else LDir := nil;

    if not CreateProcess(nil, PChar(LCmd), nil, nil, True, CREATE_NO_WINDOW,
      nil, LDir, LSI, LPI) then
    begin
      Result.ErrorOutput := SysErrorMessage(GetLastError);
      Exit;
    end;
    CloseHandle(LWrite);
    LWrite := 0;

    LStream := TMemoryStream.Create;
    try
      while ReadFile(LRead, LBuf, SizeOf(LBuf), LBytesRead, nil) and (LBytesRead > 0) do
      begin
        LStream.WriteBuffer(LBuf, LBytesRead);
        if Assigned(AOnOutput) then
        begin
          SetString(LText, PAnsiChar(@LBuf[0]), LBytesRead);
          AOnOutput(LText);
        end;
      end;
      WaitForSingleObject(LPI.hProcess, INFINITE);
      GetExitCodeProcess(LPI.hProcess, LExit);
      SetLength(LBytes, LStream.Size);
      if LStream.Size > 0 then
        Move(LStream.Memory^, LBytes[0], LStream.Size);
      Result.Output := TEncoding.UTF8.GetString(LBytes);
      Result.ExitCode := LExit;
      Result.Success := LExit = 0;
      if not Result.Success then
        Result.ErrorOutput := Result.Output;
    finally
      LStream.Free;
      CloseHandle(LPI.hProcess);
      CloseHandle(LPI.hThread);
    end;
  finally
    if LWrite <> 0 then
      CloseHandle(LWrite);
    CloseHandle(LRead);
  end;
end;

function TGitCore.InitRepo: TGitResult;
begin
  Result := RunGit('init');
end;

function TGitCore.AddAll: TGitResult;
begin
  Result := RunGit('add -A');
end;

function TGitCore.Commit(const AMessage: string): TGitResult;
var
  LCfg: TGitResult;
  LPrefix: string;
begin
  LPrefix := '';
  LCfg := RunGit('config user.name');
  if Trim(LCfg.Output) = '' then // no git identity configured on this PC
    LPrefix := '-c user.name="RAD Essentials" -c user.email="rade@users.noreply.github.com" ';
  Result := RunGit(LPrefix + 'commit -m "' + AMessage.Replace('"', '''') + '"');
end;

function TGitCore.SetRemote(const AName, AUrl: string): TGitResult;
begin
  RunGit('remote remove ' + AName); // ignore failure if it did not exist
  Result := RunGit(Format('remote add %s "%s"', [AName, AUrl]));
end;

function TGitCore.PushToUrl(const ARepoUrl, ABranch, AToken: string;
  AForce, ADryRun: Boolean; AOnOutput: TGitOutputEvent): TGitResult;
var
  LEnc: TBase64Encoding;
  LAuth, LArgs: string;
begin
  LEnc := TBase64Encoding.Create(0); // 0 = no line breaks
  try
    LAuth := LEnc.Encode('x-access-token:' + AToken);
  finally
    LEnc.Free;
  end;
  LArgs := Format('-c "http.extraheader=Authorization: Basic %s" push --progress', [LAuth]);
  if ADryRun then
    LArgs := LArgs + ' --dry-run';
  if AForce then
    LArgs := LArgs + ' --force';
  LArgs := LArgs + Format(' "%s" "HEAD:refs/heads/%s"', [ARepoUrl, ABranch]);
  Result := RunGit(LArgs, AOnOutput);
end;

function TGitCore.GetCurrentBranch: string;
begin
  Result := Trim(RunGit('rev-parse --abbrev-ref HEAD').Output);
end;

end.

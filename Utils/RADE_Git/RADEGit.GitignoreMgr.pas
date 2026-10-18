unit RadeGit.GitignoreMgr;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils;

type
  TGitignoreManager = class
  private
    FRootPath: string;
    FGitignorePath: string;
    FLines: TStringList;
    function NormalizeEntry(const AValue: string): string;
    function RelativeFromRoot(const APath: string): string;
    procedure RemoveLegacyDefaults;
  public
    constructor Create(const ARootPath: string);
    destructor Destroy; override;
    procedure Load;
    procedure Save;
    function GetText: string;
    procedure SetText(const AText: string);
    procedure AddEntry(const APath: string; AIsFolder: Boolean);
    procedure RemoveEntry(const APath: string);
    function Contains(const APath: string): Boolean;
    property GitignorePath: string read FGitignorePath;
  end;

implementation

const
  DEFAULT_LINES: array[0..17] of string = (
    '# Delphi / RAD Studio (added by RAD Essentials)',
    '__history/', '__recovery/', '*.dcu', '*.local', '*.identcache',
    '*.stat', '*.~*', '*.dsk', '*.tvsconfig',
    'Win32/', 'Win64/', 'Win64x/', 'Android/', 'Android64/',
    'iOSDevice64/', 'OSX64/', 'Linux64/');

constructor TGitignoreManager.Create(const ARootPath: string);
begin
  inherited Create;
  FRootPath := IncludeTrailingPathDelimiter(ARootPath);
  FGitignorePath := FRootPath + '.gitignore';
  FLines := TStringList.Create;
  Load;
end;

destructor TGitignoreManager.Destroy;
begin
  FLines.Free;
  inherited;
end;

function TGitignoreManager.NormalizeEntry(const AValue: string): string;
begin
  Result := Trim(AValue).Replace('\', '/');
  while Result.StartsWith('/') do
    Result := Result.Substring(1);
  while Result.EndsWith('/') do
    Result := Result.Substring(0, Result.Length - 1);
end;

function TGitignoreManager.RelativeFromRoot(const APath: string): string;
var
  LPath: string;
begin
  LPath := APath;
  if LPath.StartsWith(FRootPath, True) then
    LPath := LPath.Substring(FRootPath.Length);
  Result := NormalizeEntry(LPath);
end;

procedure TGitignoreManager.Load;
begin
  FLines.Clear;
  if TFile.Exists(FGitignorePath) then
    FLines.LoadFromFile(FGitignorePath, TEncoding.UTF8);
  RemoveLegacyDefaults;
end;

procedure TGitignoreManager.RemoveLegacyDefaults;
var
  I, J: Integer;
  LHasMarker, LIsDefault: Boolean;
begin
  LHasMarker := False;
  for I := 0 to FLines.Count - 1 do
    if SameText(Trim(FLines[I]), DEFAULT_LINES[0]) then
    begin
      LHasMarker := True;
      Break;
    end;
  if not LHasMarker then
    Exit;

  for I := FLines.Count - 1 downto 0 do
  begin
    LIsDefault := False;
    for J := Low(DEFAULT_LINES) to High(DEFAULT_LINES) do
      if SameText(Trim(FLines[I]), DEFAULT_LINES[J]) then
      begin
        LIsDefault := True;
        Break;
      end;
    if LIsDefault then
      FLines.Delete(I);
  end;
end;

procedure TGitignoreManager.Save;
var
  LEnc: TUTF8Encoding;
begin
  LEnc := TUTF8Encoding.Create(False); // no BOM - git dislikes a BOM in .gitignore
  try
    FLines.SaveToFile(FGitignorePath, LEnc);
  finally
    LEnc.Free;
  end;
end;

function TGitignoreManager.GetText: string;
begin
  Result := FLines.Text;
end;

procedure TGitignoreManager.SetText(const AText: string);
begin
  FLines.Text := AText;
end;

function TGitignoreManager.Contains(const APath: string): Boolean;
var
  LEntry, LLine: string;
begin
  Result := False;
  LEntry := RelativeFromRoot(APath);
  if LEntry = '' then
    Exit;
  for LLine in FLines do
  begin
    if (Trim(LLine) = '') or Trim(LLine).StartsWith('#') then
      Continue;
    if SameText(NormalizeEntry(LLine), LEntry) then
      Exit(True);
  end;
end;

procedure TGitignoreManager.AddEntry(const APath: string; AIsFolder: Boolean);
var
  LEntry: string;
begin
  LEntry := RelativeFromRoot(APath);
  if (LEntry = '') or Contains(LEntry) then
    Exit;
  if AIsFolder then
    FLines.Add('/' + LEntry + '/')
  else
    FLines.Add('/' + LEntry);
end;

procedure TGitignoreManager.RemoveEntry(const APath: string);
var
  LEntry: string;
  I: Integer;
begin
  LEntry := RelativeFromRoot(APath);
  if LEntry = '' then
    Exit;
  for I := FLines.Count - 1 downto 0 do
  begin
    if (Trim(FLines[I]) = '') or Trim(FLines[I]).StartsWith('#') then
      Continue;
    if SameText(NormalizeEntry(FLines[I]), LEntry) then
      FLines.Delete(I);
  end;
end;

end.

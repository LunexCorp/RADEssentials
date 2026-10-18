unit RadeGit.OAuth;

interface

uses
  System.SysUtils, System.Classes, System.Net.HttpClient,
  System.Net.URLClient;

type
  TGitHubOAuth = class
  private
    FHttp: THTTPClient;
  public
    constructor Create;
    destructor Destroy; override;
    function ValidateToken(const AToken: string; out AError: string): Boolean;
    class procedure SaveToken(const AToken: string);
    class function LoadToken: string;
    class procedure ClearToken;
  end;

implementation

uses
  Winapi.Windows, System.IOUtils, RadeGit.Core;

type
  TDpapiBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PDpapiBlob = ^TDpapiBlob;

function DpapiProtect(pDataIn: PDpapiBlob; szDataDescr: PWideChar;
  pEntropy, pReserved, pPrompt: Pointer; dwFlags: DWORD;
  pDataOut: PDpapiBlob): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptProtectData';

function DpapiUnprotect(pDataIn: PDpapiBlob; ppszDataDescr: PWideChar;
  pEntropy, pReserved, pPrompt: Pointer; dwFlags: DWORD;
  pDataOut: PDpapiBlob): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptUnprotectData';

function TokenFilePath: string;
begin
  Result := TPath.Combine(RadeGitDataDir, 'git_token.dat');
end;

{ TGitHubOAuth }

constructor TGitHubOAuth.Create;
begin
  inherited Create;
  FHttp := THTTPClient.Create;
  FHttp.UserAgent := 'RAD-Essentials';
  FHttp.CustomHeaders['Accept'] := 'application/vnd.github+json';
end;

destructor TGitHubOAuth.Destroy;
begin
  FHttp.Free;
  inherited;
end;

function TGitHubOAuth.ValidateToken(const AToken: string; out AError: string): Boolean;
var
  LResp: IHTTPResponse;
begin
  Result := False;
  AError := '';
  if Trim(AToken) = '' then
  begin
    AError := 'Enter a GitHub personal access token.';
    Exit;
  end;
  FHttp.CustomHeaders['Authorization'] := 'Bearer ' + Trim(AToken);
  try
    LResp := FHttp.Get('https://api.github.com/user');
    Result := LResp.StatusCode = 200;
    if not Result then
      AError := Format('GitHub rejected the token (HTTP %d: %s).',
        [LResp.StatusCode, LResp.StatusText]);
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

class procedure TGitHubOAuth.SaveToken(const AToken: string);
var
  LIn, LOut: TDpapiBlob;
  LBytes: TBytes;
  LFile: TFileStream;
begin
  LBytes := TEncoding.UTF8.GetBytes(AToken);
  if Length(LBytes) = 0 then
    Exit;
  LIn.cbData := Length(LBytes);
  LIn.pbData := @LBytes[0];
  LOut.cbData := 0;
  LOut.pbData := nil;
  if not DpapiProtect(@LIn, 'RadeGitToken', nil, nil, nil, 0, @LOut) then
    raise Exception.Create('Could not encrypt the GitHub token (DPAPI failed).');
  try
    LFile := TFileStream.Create(TokenFilePath, fmCreate);
    try
      LFile.WriteBuffer(LOut.pbData^, LOut.cbData);
    finally
      LFile.Free;
    end;
  finally
    LocalFree(HLOCAL(LOut.pbData));
  end;
end;

class function TGitHubOAuth.LoadToken: string;
var
  LIn, LOut: TDpapiBlob;
  LBytes, LPlain: TBytes;
begin
  Result := '';
  if not TFile.Exists(TokenFilePath) then
    Exit;
  LBytes := TFile.ReadAllBytes(TokenFilePath);
  if Length(LBytes) = 0 then
    Exit;
  LIn.cbData := Length(LBytes);
  LIn.pbData := @LBytes[0];
  LOut.cbData := 0;
  LOut.pbData := nil;
  if DpapiUnprotect(@LIn, nil, nil, nil, nil, 0, @LOut) then
  try
    SetLength(LPlain, LOut.cbData);
    if LOut.cbData > 0 then
      Move(LOut.pbData^, LPlain[0], LOut.cbData);
    Result := TEncoding.UTF8.GetString(LPlain);
  finally
    LocalFree(HLOCAL(LOut.pbData));
  end;
end;

class procedure TGitHubOAuth.ClearToken;
begin
  if TFile.Exists(TokenFilePath) then
    TFile.Delete(TokenFilePath);
end;

end.

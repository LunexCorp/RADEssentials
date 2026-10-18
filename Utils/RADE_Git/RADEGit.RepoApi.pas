unit RadeGit.RepoApi;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  System.IOUtils, System.Generics.Collections,
  System.Net.HttpClient, System.Net.URLClient;

type
  TRepoInfo = record
    FullName: string;       // "owner/repo"
    Name: string;
    IsPrivate: Boolean;
    DefaultBranch: string;
    CloneUrl: string;
  end;

  TGitHubRepoApi = class
  private
    FToken: string;
    FHttp: THTTPClient;
    FLastError: string;
    function GetJson(const AUrl: string): TJSONValue;
  public
    constructor Create(const AAccessToken: string);
    destructor Destroy; override;
    // Public + private repos the signed-in user can access
    function ListUserRepos: TArray<TRepoInfo>;
    function ListBranches(const ARepoFullName: string): TArray<string>;
    function CanPushToRepo(const ARepoFullName: string): Boolean;
    function CreateRelease(const ARepoFullName, ATagName, AReleaseName, ABody,
      ABranch: string; out AUploadUrl: string): Boolean;
    function UploadReleaseAsset(const AUploadUrl, AFilePath: string): Boolean;
    property LastError: string read FLastError;
  end;

implementation

function JStr(AObj: TJSONObject; const AName: string): string;
begin
  if not AObj.TryGetValue<string>(AName, Result) then
    Result := '';
end;

function JBool(AObj: TJSONObject; const AName: string): Boolean;
begin
  if not AObj.TryGetValue<Boolean>(AName, Result) then
    Result := False;
end;

constructor TGitHubRepoApi.Create(const AAccessToken: string);
begin
  inherited Create;
  FToken := AAccessToken;
  FHttp := THTTPClient.Create;
  FHttp.UserAgent := 'RAD-Essentials';
  FHttp.CustomHeaders['Authorization'] := 'Bearer ' + FToken;
  FHttp.CustomHeaders['Accept'] := 'application/vnd.github+json';
  FHttp.CustomHeaders['X-GitHub-Api-Version'] := '2022-11-28';
end;

destructor TGitHubRepoApi.Destroy;
begin
  FHttp.Free;
  inherited;
end;

// Returns parsed JSON (caller frees) or nil with FLastError set
function TGitHubRepoApi.GetJson(const AUrl: string): TJSONValue;
var
  LResp: IHTTPResponse;
begin
  Result := nil;
  try
    LResp := FHttp.Get(AUrl);
    if LResp.StatusCode <> 200 then
    begin
      FLastError := Format('GitHub returned HTTP %d (%s)', [LResp.StatusCode, LResp.StatusText]);
      Exit;
    end;
    Result := TJSONObject.ParseJSONValue(LResp.ContentAsString);
    if Result = nil then
      FLastError := 'Could not read GitHub response.';
  except
    on E: Exception do
    begin
      FLastError := E.Message;
      Result := nil;
    end;
  end;
end;

function TGitHubRepoApi.ListUserRepos: TArray<TRepoInfo>;
var
  LList: TList<TRepoInfo>;
  LPage: Integer;
  LJson: TJSONValue;
  LArr: TJSONArray;
  LItem: TJSONValue;
  LObj: TJSONObject;
  LRepo: TRepoInfo;
begin
  FLastError := '';
  LList := TList<TRepoInfo>.Create;
  try
    for LPage := 1 to 50 do
    begin
      LJson := GetJson(Format(
        'https://api.github.com/user/repos?per_page=100&page=%d&visibility=all' +
        '&affiliation=owner,collaborator,organization_member&sort=updated', [LPage]));
      if not (LJson is TJSONArray) then
      begin
        LJson.Free;
        Break;
      end;
      try
        LArr := TJSONArray(LJson);
        for LItem in LArr do
        begin
          LObj := LItem as TJSONObject;
          LRepo.FullName := JStr(LObj, 'full_name');
          LRepo.Name := JStr(LObj, 'name');
          LRepo.IsPrivate := JBool(LObj, 'private');
          LRepo.DefaultBranch := JStr(LObj, 'default_branch');
          if LRepo.DefaultBranch = '' then
            LRepo.DefaultBranch := 'main';
          LRepo.CloneUrl := JStr(LObj, 'clone_url');
          LList.Add(LRepo);
        end;
        if LArr.Count < 100 then
          Break;
      finally
        LJson.Free;
      end;
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TGitHubRepoApi.ListBranches(const ARepoFullName: string): TArray<string>;
var
  LList: TList<string>;
  LJson: TJSONValue;
  LItem: TJSONValue;
begin
  LList := TList<string>.Create;
  try
    LJson := GetJson(Format('https://api.github.com/repos/%s/branches?per_page=100',
      [ARepoFullName]));
    try
      if LJson is TJSONArray then
        for LItem in TJSONArray(LJson) do
          LList.Add(JStr(LItem as TJSONObject, 'name'));
    finally
      LJson.Free;
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TGitHubRepoApi.CanPushToRepo(const ARepoFullName: string): Boolean;
var
  LJson: TJSONValue;
  LRepo, LPermissions: TJSONObject;
begin
  Result := False;
  FLastError := '';
  LJson := GetJson('https://api.github.com/repos/' + ARepoFullName);
  try
    if not (LJson is TJSONObject) then
    begin
      if FLastError = '' then
        FLastError := 'GitHub did not return repository permissions.';
      Exit;
    end;
    LRepo := TJSONObject(LJson);
    if not (LRepo.Values['permissions'] is TJSONObject) then
    begin
      FLastError := 'GitHub did not report push permission for this token.';
      Exit;
    end;
    LPermissions := TJSONObject(LRepo.Values['permissions']);
    if not LPermissions.TryGetValue<Boolean>('push', Result) then
    begin
      FLastError := 'GitHub did not report push permission for this token.';
      Exit;
    end;
    if not Result then
      FLastError := 'This token can read the repository but does not have push access.';
  finally
    LJson.Free;
  end;
end;

function TGitHubRepoApi.CreateRelease(const ARepoFullName, ATagName, AReleaseName,
  ABody, ABranch: string; out AUploadUrl: string): Boolean;
var
  LReq: TJSONObject;
  LBody: TStringStream;
  LResp: IHTTPResponse;
  LVal: TJSONValue;
begin
  Result := False;
  AUploadUrl := '';
  FLastError := '';
  LReq := TJSONObject.Create;
  try
    LReq.AddPair('tag_name', ATagName);
    LReq.AddPair('target_commitish', ABranch);
    LReq.AddPair('name', AReleaseName);
    LReq.AddPair('body', ABody);
    LReq.AddPair('draft', TJSONBool.Create(False));
    LReq.AddPair('prerelease', TJSONBool.Create(False));
    LBody := TStringStream.Create(LReq.ToJSON, TEncoding.UTF8);
    try
      try
        FHttp.ContentType := 'application/json';
        LResp := FHttp.Post(Format('https://api.github.com/repos/%s/releases',
          [ARepoFullName]), LBody);
        if LResp.StatusCode = 201 then
        begin
          LVal := TJSONObject.ParseJSONValue(LResp.ContentAsString);
          try
            if LVal is TJSONObject then
            begin
              AUploadUrl := JStr(TJSONObject(LVal), 'upload_url');
              if AUploadUrl.Contains('{') then
                AUploadUrl := AUploadUrl.Substring(0, AUploadUrl.IndexOf('{'));
              Result := AUploadUrl <> '';
            end;
          finally
            LVal.Free;
          end;
        end
        else
          FLastError := Format('HTTP %d: %s', [LResp.StatusCode, LResp.ContentAsString]);
      except
        on E: Exception do
          FLastError := E.Message;
      end;
    finally
      LBody.Free;
    end;
  finally
    LReq.Free;
  end;
end;

function TGitHubRepoApi.UploadReleaseAsset(const AUploadUrl, AFilePath: string): Boolean;
var
  LClient: THTTPClient;
  LFile: TFileStream;
  LResp: IHTTPResponse;
begin
  Result := False;
  FLastError := '';
  if not TFile.Exists(AFilePath) then
    Exit;
  LClient := THTTPClient.Create;
  try
    LClient.UserAgent := 'RAD-Essentials';
    LClient.CustomHeaders['Authorization'] := 'Bearer ' + FToken;
    LClient.CustomHeaders['Accept'] := 'application/vnd.github+json';
    LClient.ContentType := 'application/octet-stream';
    LClient.SendTimeout := 600000;
    LClient.ResponseTimeout := 600000;
    LFile := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
    try
      try
        LResp := LClient.Post(AUploadUrl + '?name=' +
          TNetEncoding.URL.Encode(TPath.GetFileName(AFilePath)), LFile);
        Result := LResp.StatusCode = 201;
        if not Result then
          FLastError := Format('HTTP %d: %s', [LResp.StatusCode, LResp.ContentAsString]);
      except
        on E: Exception do
          FLastError := E.Message;
      end;
    finally
      LFile.Free;
    end;
  finally
    LClient.Free;
  end;
end;

end.

unit RadeGit.FileTree;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.Generics.Defaults, RadeGit.GitignoreMgr;

type
  TFileNode = class
  private
    FFullPath: string;
    FDisplayName: string;
    FIsFolder: Boolean;
    FChecked: Boolean;
    FChildren: TObjectList<TFileNode>;
    FParent: TFileNode;
  public
    constructor Create(const AFullPath: string; AIsFolder: Boolean; AParent: TFileNode);
    destructor Destroy; override;
    procedure SetCheckedRecursive(AChecked: Boolean);
    // A folder counts as checked while at least one child is checked
    procedure UpdateParentCheckState;
    property FullPath: string read FFullPath;
    property DisplayName: string read FDisplayName;
    property IsFolder: Boolean read FIsFolder;
    property Checked: Boolean read FChecked write FChecked;
    property Children: TObjectList<TFileNode> read FChildren;
    property Parent: TFileNode read FParent;
  end;

  TFileTreeBuilder = class
  private
    FRootPath: string;
    FIgnore: TGitignoreManager;
    function RelPath(const AFullPath: string): string;
    function IsHiddenFolder(const AName: string): Boolean;
    procedure ScanFolder(AParent: TFileNode; const AFolder: string);
    procedure SyncNode(ANode: TFileNode);
  public
    constructor Create(const ARootPath: string; AIgnore: TGitignoreManager);
    // Caller owns (and must free) the returned root node
    function BuildTree: TFileNode;
    // Writes the unchecked items into the .gitignore manager (in memory)
    procedure SyncGitignoreFromTree(ARoot: TFileNode);
  end;

implementation

{ TFileNode }

constructor TFileNode.Create(const AFullPath: string; AIsFolder: Boolean;
  AParent: TFileNode);
begin
  inherited Create;
  FFullPath := AFullPath;
  FDisplayName := TPath.GetFileName(ExcludeTrailingPathDelimiter(AFullPath));
  FIsFolder := AIsFolder;
  FChecked := True;
  FParent := AParent;
  FChildren := TObjectList<TFileNode>.Create(True);
end;

destructor TFileNode.Destroy;
begin
  FChildren.Free;
  inherited;
end;

procedure TFileNode.SetCheckedRecursive(AChecked: Boolean);
var
  LChild: TFileNode;
begin
  FChecked := AChecked;
  for LChild in FChildren do
    LChild.SetCheckedRecursive(AChecked);
end;

procedure TFileNode.UpdateParentCheckState;
var
  LChild: TFileNode;
  LAny: Boolean;
begin
  if FParent = nil then
    Exit;
  LAny := False;
  for LChild in FParent.Children do
    if LChild.Checked then
    begin
      LAny := True;
      Break;
    end;
  FParent.Checked := LAny;
  FParent.UpdateParentCheckState;
end;

{ TFileTreeBuilder }

constructor TFileTreeBuilder.Create(const ARootPath: string; AIgnore: TGitignoreManager);
begin
  inherited Create;
  FRootPath := IncludeTrailingPathDelimiter(ARootPath);
  FIgnore := AIgnore;
end;

function TFileTreeBuilder.RelPath(const AFullPath: string): string;
begin
  Result := AFullPath;
  if Result.StartsWith(FRootPath, True) then
    Result := Result.Substring(FRootPath.Length);
  Result := Result.Replace('\', '/');
end;

function TFileTreeBuilder.IsHiddenFolder(const AName: string): Boolean;
begin
  Result := SameText(AName, '.git') or SameText(AName, '__history') or
    SameText(AName, '__recovery');
end;

function TFileTreeBuilder.BuildTree: TFileNode;
begin
  Result := TFileNode.Create(FRootPath, True, nil);
  ScanFolder(Result, ExcludeTrailingPathDelimiter(FRootPath));
end;

procedure TFileTreeBuilder.ScanFolder(AParent: TFileNode; const AFolder: string);
var
  LDirs, LFiles: TArray<string>;
  LEntry: string;
  LNode: TFileNode;
  LCompare: IComparer<string>;
begin
  LCompare := TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
    end);
  try
    LDirs := TDirectory.GetDirectories(AFolder);
    LFiles := TDirectory.GetFiles(AFolder);
  except
    Exit; // unreadable folder - skip it
  end;
  TArray.Sort<string>(LDirs, LCompare);
  TArray.Sort<string>(LFiles, LCompare);

  for LEntry in LDirs do
  begin
    if IsHiddenFolder(TPath.GetFileName(LEntry)) then
      Continue;
    LNode := TFileNode.Create(LEntry, True, AParent);
    LNode.Checked := AParent.Checked and not FIgnore.Contains(RelPath(LEntry));
    AParent.Children.Add(LNode);
    ScanFolder(LNode, LEntry);
  end;

  for LEntry in LFiles do
  begin
    LNode := TFileNode.Create(LEntry, False, AParent);
    LNode.Checked := AParent.Checked and not FIgnore.Contains(RelPath(LEntry));
    AParent.Children.Add(LNode);
  end;
end;

procedure TFileTreeBuilder.SyncGitignoreFromTree(ARoot: TFileNode);
begin
  SyncNode(ARoot);
end;

procedure TFileTreeBuilder.SyncNode(ANode: TFileNode);
var
  LChild: TFileNode;
  LRel: string;
begin
  if ANode.Parent <> nil then
  begin
    LRel := RelPath(ANode.FullPath);
    if not ANode.Checked then
    begin
      FIgnore.AddEntry(LRel, ANode.IsFolder);
      Exit; // a whole ignored folder needs no per-child entries
    end;
    FIgnore.RemoveEntry(LRel);
  end;
  for LChild in ANode.Children do
    SyncNode(LChild);
end;

end.

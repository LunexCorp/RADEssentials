unit RADE.Search;

interface

procedure RADESearch_Show;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.Math,
  System.StrUtils, System.Character, System.Generics.Collections, ToolsAPI,
  System.Actions, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Graphics, Vcl.ImgList, Vcl.Menus, Vcl.ComCtrls,
  Vcl.ActnList;

type
  TSearchKind = (skAction, skFile, skText, skSymbol);

  TSearchResult = record
    Kind: TSearchKind;
    Title: string;
    Detail: string;
    FileName: string;
    MenuItem: TMenuItem;
    Action: TContainedAction;
    Line: Integer;
    Column: Integer;
    IconText: string;
    IconColor: TColor;
    FuzzyHighlight: Boolean;
    HighlightText: string;
  end;

  TSearchResultsListBox = class(TListBox)
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    property OnMouseWheel;
  end;

  TSearchScrollRail = class(TPaintBox)
  public
    property MouseCapture;
  end;

  TRADESearchForm = class(TForm)
  private
    FSearchEdit: TEdit;
    FSearchBar: TPanel;
    FModeChip: TPanel;
    FModeChipLabel: TLabel;
    FResultsPanel: TPanel;
    FResultsBox: TSearchResultsListBox;
    FScrollRail: TSearchScrollRail;
    FStatusLabel: TLabel;
    FSearchTimer: TTimer;
    FItems: TList<TSearchResult>;
    FActions: TList<TSearchResult>;
    FSymbols: TList<TSearchResult>;
    FFiles: TStringList;
    FMenuImages: TCustomImageList;
    FSelected: TSearchResult;
    FHasSelection: Boolean;
    FReadFailures: Integer;
    FInClassDeclaration: Boolean;
    FSearchMode: TSearchKind;
    FChangingSearchText: Boolean;
    FScrollDragging: Boolean;
    FScrollDragOffset: Integer;
    FEditorAvailable: Boolean;
    procedure BuildUI;
    procedure FormShown(Sender: TObject);
    procedure CollectActions;
    procedure CollectProjectFiles;
    procedure IndexSymbols;
    procedure AddMenuItems(AParent: TMenuItem; const APath: string);
    procedure AddProject(const AProject: IOTAProject);
    procedure AddProjectFile(const AFileName: string);
    procedure AddSymbol(const AFileName, ALineText: string; ALine: Integer;
      const AKind, AIcon: string; AColor: TColor);
    procedure SearchChanged(Sender: TObject);
    procedure SearchTimerTimer(Sender: TObject);
    procedure ModeChipClick(Sender: TObject);
    procedure SetSearchMode(AMode: TSearchKind);
    procedure SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ResultsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ResultsMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ResultsClick(Sender: TObject);
    procedure ResultsMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ScrollRailPaint(Sender: TObject);
    procedure ScrollRailMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ScrollRailMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ScrollRailMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure UpdateScrollRail;
    procedure HideNativeScrollbar;
    procedure DrawResult(Control: TWinControl; AIndex: Integer; ARect: TRect;
      AState: TOwnerDrawState);
    procedure AcceptSelection;
    procedure UpdateResults;
    procedure SearchFiles(const AQuery: string);
    procedure SearchText(const AQuery: string);
    procedure AddResult(const AResult: TSearchResult);
    procedure SetStatus;
    procedure RunResult(const AResult: TSearchResult);
    function FindTextInEditor(const AResult: TSearchResult): Boolean;
    function SearchMode(const AText: string; out AQuery: string): TSearchKind;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Execute: Boolean;
    property Selected: TSearchResult read FSelected;
  end;

const
  CMaximumResults = 1000;
  CRowHeight = 34;
  CTextFileExtensions: array[0..34] of string = (
    '.pas', '.dpr', '.dpk', '.inc', '.dfm', '.fmx', '.txt', '.md', '.xml',
    '.json', '.ini', '.cfg', '.dproj', '.local', '.rc', '.manifest',
    '.bat', '.cmd', '.yaml', '.yml', '.sql', '.properties', '.html', '.htm',
    '.css', '.js', '.ts', '.py', '.csv', '.log', '.toml', '.conf', '.ps1',
    '.sh', '.gitignore'
  );

function IsIdentifierChar(AChar: Char): Boolean;
begin
  Result := AChar.IsLetterOrDigit or (AChar = '_');
end;

procedure TSearchResultsListBox.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.Style := Params.Style and not WS_VSCROLL;
end;

function StripAccelerators(const ACaption: string): string;
var
  I, TabIndex: Integer;
begin
  TabIndex := Pos(#9, ACaption);
  if TabIndex > 0 then
    Result := Copy(ACaption, 1, TabIndex - 1)
  else
    Result := ACaption;
  I := 1;
  while I <= Length(Result) do
  begin
    if Result[I] = '&' then
      Delete(Result, I, 1)
    else
      Inc(I);
  end;
end;

function IsSubsequence(const AText, AQuery: string; out APositions: TArray<Integer>): Boolean;
var
  I, J: Integer;
begin
  SetLength(APositions, 0);
  if AQuery = '' then
    Exit(True);
  I := 1;
  for J := 1 to Length(AQuery) do
  begin
    while (I <= Length(AText)) and
      (UpCase(AText[I]) <> UpCase(AQuery[J])) do
      Inc(I);
    if I > Length(AText) then
      Exit(False);
    SetLength(APositions, Length(APositions) + 1);
    APositions[High(APositions)] := I;
    Inc(I);
  end;
  Result := True;
end;

function HighlightPositions(const AText, AQuery: string;
  AFuzzy: Boolean): TArray<Integer>;
var
  MatchAt, I: Integer;
begin
  if AFuzzy then
  begin
    IsSubsequence(AText, AQuery, Result);
    Exit;
  end;
  SetLength(Result, 0);
  MatchAt := Pos(LowerCase(AQuery), LowerCase(AText));
  if (AQuery = '') or (MatchAt = 0) then
    Exit;
  SetLength(Result, Length(AQuery));
  for I := 0 to Length(AQuery) - 1 do
    Result[I] := MatchAt + I;
end;

procedure DrawHighlightedText(ACanvas: TCanvas; const AText, AQuery: string;
  AFuzzy: Boolean; X, Y: Integer; ATextColor, AHighlightColor: TColor);
var
  Positions: TArray<Integer>;
  I, PositionIndex, CharWidth, CharHeight: Integer;
  CharRect: TRect;
begin
  Positions := HighlightPositions(AText, AQuery, AFuzzy);
  PositionIndex := 0;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color := ATextColor;
  CharHeight := ACanvas.TextHeight('W');
  for I := 1 to Length(AText) do
  begin
    CharWidth := ACanvas.TextWidth(AText[I]);
    if (PositionIndex < Length(Positions)) and (Positions[PositionIndex] = I) then
    begin
      CharRect := Rect(X, Y, X + CharWidth, Y + CharHeight);
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := AHighlightColor;
      ACanvas.FillRect(CharRect);
      ACanvas.Brush.Style := bsClear;
      ACanvas.Font.Color := clWhite;
      Inc(PositionIndex);
    end
    else
      ACanvas.Font.Color := ATextColor;
    ACanvas.TextOut(X, Y, AText[I]);
    Inc(X, CharWidth);
  end;
  ACanvas.Brush.Style := bsSolid;
end;

function StartsWithWord(const AText, AWord: string): Boolean;
begin
  Result := (Length(AText) >= Length(AWord)) and
    SameText(Copy(AText, 1, Length(AWord)), AWord) and
    ((Length(AText) = Length(AWord)) or not IsIdentifierChar(AText[Length(AWord) + 1]));
end;

function FirstIdentifier(const AText: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(AText)) and not IsIdentifierChar(AText[I]) do
    Inc(I);
  Result := '';
  while (I <= Length(AText)) and IsIdentifierChar(AText[I]) do
  begin
    Result := Result + AText[I];
    Inc(I);
  end;
end;

function HasActiveSourceEditor: Boolean;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
  I: Integer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  Module := ModuleServices.CurrentModule;
  if Module = nil then
    Exit;
  for I := 0 to Module.ModuleFileCount - 1 do
  begin
    Editor := Module.ModuleFileEditors[I];
    if Supports(Editor, IOTASourceEditor, SourceEditor) and
      (SourceEditor.EditViewCount > 0) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

constructor TRADESearchForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  Position := poMainFormCenter;
  FormStyle := fsStayOnTop;
  KeyPreview := True;
  ClientWidth := 720;
  ClientHeight := 460;
  Color := RGB(32, 35, 39);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  OnShow := FormShown;
  FItems := TList<TSearchResult>.Create;
  FActions := TList<TSearchResult>.Create;
  FSymbols := TList<TSearchResult>.Create;
  FFiles := TStringList.Create;
  FFiles.Sorted := True;
  FFiles.Duplicates := dupIgnore;
  FFiles.CaseSensitive := False;
  FEditorAvailable := HasActiveSourceEditor;
  BuildUI;
  CollectActions;
  if FEditorAvailable then
  begin
    CollectProjectFiles;
    IndexSymbols;
  end;
  UpdateResults;
end;

destructor TRADESearchForm.Destroy;
begin
  FFiles.Free;
  FSymbols.Free;
  FActions.Free;
  FItems.Free;
  inherited Destroy;
end;

function TRADESearchForm.Execute: Boolean;
begin
  Result := ShowModal = mrOk;
  if Result and FHasSelection then
    RunResult(FSelected);
end;

procedure TRADESearchForm.FormShown(Sender: TObject);
begin
  HideNativeScrollbar;
  FSearchEdit.SetFocus;
  UpdateScrollRail;
end;

procedure TRADESearchForm.BuildUI;
var
  BorderPanel, HeaderPanel, FooterPanel: TPanel;
  TitleLabel: TLabel;
begin
  BorderPanel := TPanel.Create(Self);
  BorderPanel.Parent := Self;
  BorderPanel.Align := alClient;
  BorderPanel.BevelOuter := bvNone;
  BorderPanel.Color := RGB(32, 35, 39);
  BorderPanel.Padding.Left := 1;
  BorderPanel.Padding.Top := 1;
  BorderPanel.Padding.Right := 1;
  BorderPanel.Padding.Bottom := 1;

  HeaderPanel := TPanel.Create(Self);
  HeaderPanel.Parent := BorderPanel;
  HeaderPanel.Align := alTop;
  HeaderPanel.Height := 82;
  HeaderPanel.BevelOuter := bvNone;
  HeaderPanel.Color := RGB(32, 35, 39);

  TitleLabel := TLabel.Create(Self);
  TitleLabel.Parent := HeaderPanel;
  TitleLabel.SetBounds(14, 8, 600, 22);
  TitleLabel.Caption := 'Search Everywhere';
  TitleLabel.Font.Size := 11;
  TitleLabel.Font.Color := RGB(236, 239, 242);
  TitleLabel.Font.Style := [fsBold];

  FSearchBar := TPanel.Create(Self);
  FSearchBar.Parent := HeaderPanel;
  FSearchBar.SetBounds(10, 38, 698, 34);
  FSearchBar.Anchors := [akLeft, akTop, akRight];
  FSearchBar.BevelOuter := bvNone;
  FSearchBar.Color := RGB(43, 47, 52);

  FModeChip := TPanel.Create(Self);
  FModeChip.Parent := FSearchBar;
  FModeChip.Align := alLeft;
  FModeChip.Width := 72;
  FModeChip.BevelOuter := bvNone;
  FModeChip.Color := RGB(62, 76, 91);
  FModeChip.Cursor := crHandPoint;
  FModeChip.Visible := False;
  FModeChip.OnClick := ModeChipClick;

  FModeChipLabel := TLabel.Create(Self);
  FModeChipLabel.Parent := FModeChip;
  FModeChipLabel.Align := alClient;
  FModeChipLabel.Alignment := taCenter;
  FModeChipLabel.Layout := tlCenter;
  FModeChipLabel.Font.Name := 'Segoe UI';
  FModeChipLabel.Font.Size := 9;
  FModeChipLabel.Font.Style := [fsBold];
  FModeChipLabel.Font.Color := RGB(213, 225, 237);
  FModeChipLabel.Cursor := crHandPoint;
  FModeChipLabel.OnClick := ModeChipClick;

  FSearchEdit := TEdit.Create(Self);
  FSearchEdit.Parent := FSearchBar;
  FSearchEdit.Align := alClient;
  FSearchEdit.BorderStyle := bsNone;
  FSearchEdit.Color := FSearchBar.Color;
  FSearchEdit.Font.Name := 'Segoe UI';
  FSearchEdit.Font.Size := 10;
  FSearchEdit.Font.Color := RGB(235, 236, 238);
  if FEditorAvailable then
    FSearchEdit.TextHint := 'Search actions and symbols...'
  else
    FSearchEdit.TextHint := 'Search IDE actions...';
  FSearchEdit.Margins.Left := 8;
  FSearchEdit.Margins.Right := 8;
  FSearchEdit.AlignWithMargins := True;
  FSearchEdit.OnChange := SearchChanged;
  FSearchEdit.OnKeyDown := SearchKeyDown;

  FSearchTimer := TTimer.Create(Self);
  FSearchTimer.Enabled := False;
  FSearchTimer.Interval := 120;
  FSearchTimer.OnTimer := SearchTimerTimer;

  FResultsPanel := TPanel.Create(Self);
  FResultsPanel.Parent := BorderPanel;
  FResultsPanel.Align := alClient;
  FResultsPanel.BevelOuter := bvNone;
  FResultsPanel.Color := RGB(32, 35, 39);

  FScrollRail := TSearchScrollRail.Create(Self);
  FScrollRail.Parent := FResultsPanel;
  FScrollRail.Align := alRight;
  FScrollRail.Width := 12;
  FScrollRail.OnPaint := ScrollRailPaint;
  FScrollRail.OnMouseDown := ScrollRailMouseDown;
  FScrollRail.OnMouseMove := ScrollRailMouseMove;
  FScrollRail.OnMouseUp := ScrollRailMouseUp;

  FResultsBox := TSearchResultsListBox.Create(Self);
  FResultsBox.Parent := FResultsPanel;
  FResultsBox.Align := alClient;
  FResultsBox.BorderStyle := bsNone;
  FResultsBox.Color := RGB(32, 35, 39);
  FResultsBox.Font.Name := 'Segoe UI';
  FResultsBox.Font.Size := 9;
  FResultsBox.Font.Color := RGB(224, 226, 228);
  FResultsBox.ItemHeight := CRowHeight;
  FResultsBox.Style := lbOwnerDrawFixed;
  FResultsBox.OnDrawItem := DrawResult;
  FResultsBox.OnKeyDown := ResultsKeyDown;
  FResultsBox.OnMouseUp := ResultsMouseUp;
  FResultsBox.OnClick := ResultsClick;
  FResultsBox.OnMouseWheel := ResultsMouseWheel;

  FooterPanel := TPanel.Create(Self);
  FooterPanel.Parent := BorderPanel;
  FooterPanel.Align := alBottom;
  FooterPanel.Height := 30;
  FooterPanel.BevelOuter := bvNone;
  FooterPanel.Color := RGB(28, 31, 35);

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := FooterPanel;
  FStatusLabel.Align := alClient;
  FStatusLabel.Layout := tlCenter;
  FStatusLabel.Margins.Left := 12;
  FStatusLabel.AlignWithMargins := True;
  FStatusLabel.Font.Color := RGB(155, 158, 161);
  FStatusLabel.Caption := 'Click or Enter to open  |  Esc to close';
end;

procedure TRADESearchForm.CollectActions;
var
  Services: INTAServices;
  Action: TContainedAction;
  Item: TSearchResult;
  I: Integer;
begin
  if not Supports(BorlandIDEServices, INTAServices, Services) then
    Exit;
  if Services.MainMenu <> nil then
    FMenuImages := Services.MainMenu.Images;
  if FMenuImages = nil then
    FMenuImages := Services.ImageList;
  if Services.ActionList <> nil then
    for I := 0 to Services.ActionList.ActionCount - 1 do
    begin
      Action := Services.ActionList.Actions[I];
      if (Action = nil) or not Action.Enabled or not Action.Visible or
        (Trim(Action.Caption) = '') then
        Continue;
      Item.Kind := skAction;
      Item.Title := StripAccelerators(Action.Caption);
      Item.Detail := '';
      Item.FileName := '';
      Item.MenuItem := nil;
      Item.Action := Action;
      Item.Line := 0;
      Item.Column := 0;
      Item.IconText := 'A';
      Item.IconColor := RGB(77, 147, 202);
      Item.FuzzyHighlight := True;
      Item.HighlightText := '';
      FActions.Add(Item);
    end;
  if Services.MainMenu = nil then
    Exit;
  for I := 0 to Services.MainMenu.Items.Count - 1 do
    AddMenuItems(Services.MainMenu.Items[I], StripAccelerators(Services.MainMenu.Items[I].Caption));
end;

procedure TRADESearchForm.AddMenuItems(AParent: TMenuItem; const APath: string);
var
  I: Integer;
  CaptionText, ItemPath: string;
  Item: TSearchResult;
  Action: TContainedAction;
  IsAlreadyIndexed: Boolean;
  J: Integer;
begin
  for I := 0 to AParent.Count - 1 do
  begin
    CaptionText := StripAccelerators(AParent.Items[I].Caption);
    if CaptionText = '-' then
      Continue;
    if APath = '' then
      ItemPath := CaptionText
    else
      ItemPath := APath + ' > ' + CaptionText;
    if AParent.Items[I].Visible and AParent.Items[I].Enabled and
      (Assigned(AParent.Items[I].OnClick) or Assigned(AParent.Items[I].Action)) then
    begin
      Action := nil;
      if AParent.Items[I].Action is TContainedAction then
        Action := TContainedAction(AParent.Items[I].Action);
      IsAlreadyIndexed := False;
      if Action <> nil then
        for J := 0 to FActions.Count - 1 do
          if FActions[J].Action = Action then
          begin
            IsAlreadyIndexed := True;
            Break;
          end;
      if not IsAlreadyIndexed then
      begin
        Item.Kind := skAction;
        Item.Title := CaptionText;
        Item.Detail := '';
        Item.FileName := '';
        Item.MenuItem := AParent.Items[I];
        Item.Action := Action;
        Item.Line := 0;
        Item.Column := 0;
        Item.IconText := 'A';
        Item.IconColor := RGB(77, 147, 202);
        Item.FuzzyHighlight := True;
        Item.HighlightText := '';
        FActions.Add(Item);
      end;
    end;
    if AParent.Items[I].Count > 0 then
      AddMenuItems(AParent.Items[I], ItemPath);
  end;
end;

procedure TRADESearchForm.AddProjectFile(const AFileName: string);
begin
  if (AFileName <> '') and FileExists(AFileName) then
    FFiles.Add(AFileName);
end;

procedure TRADESearchForm.AddProject(const AProject: IOTAProject);
var
  I, J: Integer;
  ModuleInfo: IOTAModuleInfo;
  ExtraFiles: TStringList;
begin
  if AProject = nil then
    Exit;
  for I := 0 to AProject.GetModuleCount - 1 do
  begin
    ModuleInfo := AProject.GetModule(I);
    AddProjectFile(ModuleInfo.FileName);
    ExtraFiles := TStringList.Create;
    try
      ModuleInfo.GetAdditionalFiles(ExtraFiles);
      for J := 0 to ExtraFiles.Count - 1 do
        AddProjectFile(ExtraFiles[J]);
    finally
      ExtraFiles.Free;
    end;
  end;
end;

procedure TRADESearchForm.CollectProjectFiles;
var
  ModuleServices: IOTAModuleServices;
  ProjectGroup: IOTAProjectGroup;
  Project: IOTAProject;
  Module: IOTAModule;
  AssociatedFiles: TStringList;
  I, J: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  ProjectGroup := ModuleServices.MainProjectGroup;
  if ProjectGroup <> nil then
  begin
    for I := 0 to ProjectGroup.ProjectCount - 1 do
      AddProject(ProjectGroup.GetProject(I));
  end
  else
  begin
    Project := ModuleServices.GetActiveProject;
    AddProject(Project);
  end;
  for J := 0 to ModuleServices.ModuleCount - 1 do
  begin
    Module := ModuleServices.Modules[J];
    AddProjectFile(Module.FileName);
    AssociatedFiles := TStringList.Create;
    try
      Module.GetAssociatedFilesFromModule(AssociatedFiles);
      for I := 0 to AssociatedFiles.Count - 1 do
        AddProjectFile(AssociatedFiles[I]);
    finally
      AssociatedFiles.Free;
    end;
  end;
end;

procedure TRADESearchForm.AddSymbol(const AFileName, ALineText: string;
  ALine: Integer; const AKind, AIcon: string; AColor: TColor);
var
  Item: TSearchResult;
begin
  Item.Kind := skSymbol;
  Item.Title := Trim(ALineText);
  Item.Detail := Format('%s  |  %s:%d', [AKind, ExtractFileName(AFileName), ALine]);
  Item.FileName := AFileName;
  Item.MenuItem := nil;
  Item.Action := nil;
  Item.Line := ALine;
  Item.Column := 1;
  Item.IconText := AIcon;
  Item.IconColor := AColor;
  Item.FuzzyHighlight := True;
  Item.HighlightText := '';
  FSymbols.Add(Item);
end;

procedure TRADESearchForm.IndexSymbols;
var
  FileName, LineText, LowerLine, Section, Name: string;
  Lines: TStringList;
  I, Start: Integer;
begin
  FReadFailures := 0;
  for FileName in FFiles do
  begin
    if not SameText(ExtractFileExt(FileName), '.pas') and
      not SameText(ExtractFileExt(FileName), '.dpr') and
      not SameText(ExtractFileExt(FileName), '.dpk') and
      not SameText(ExtractFileExt(FileName), '.inc') then
      Continue;
    try
      Lines := TStringList.Create;
      try
        Lines.Text := TFile.ReadAllText(FileName);
        Section := '';
        FInClassDeclaration := False;
        for I := 0 to Lines.Count - 1 do
        begin
          LineText := Trim(Lines[I]);
          if LineText = '' then
            Continue;
          LowerLine := LowerCase(LineText);

          if StartsWithWord(LowerLine, 'function') or StartsWithWord(LowerLine, 'class function') then
          begin
            AddSymbol(FileName, LineText, I + 1, 'Function', 'f', RGB(115, 174, 117));
            Section := '';
          end
          else if StartsWithWord(LowerLine, 'procedure') or StartsWithWord(LowerLine, 'class procedure') then
          begin
            AddSymbol(FileName, LineText, I + 1, 'Procedure', 'p', RGB(96, 164, 202));
            Section := '';
          end
          else if StartsWithWord(LowerLine, 'constructor') then
          begin
            AddSymbol(FileName, LineText, I + 1, 'Constructor', 'c', RGB(96, 164, 202));
            Section := '';
          end
          else if StartsWithWord(LowerLine, 'destructor') then
          begin
            AddSymbol(FileName, LineText, I + 1, 'Destructor', 'd', RGB(96, 164, 202));
            Section := '';
          end
          else if StartsWithWord(LowerLine, 'property') then
          begin
            AddSymbol(FileName, LineText, I + 1, 'Property', 'P', RGB(183, 146, 214));
          end
          else if StartsWithWord(LowerLine, 'type') then
          begin
            Section := 'type';
            Name := FirstIdentifier(Copy(LineText, 5, MaxInt));
            if Name <> '' then
              AddSymbol(FileName, LineText, I + 1, 'Type', 'T', RGB(221, 173, 91));
          end
          else if StartsWithWord(LowerLine, 'var') or StartsWithWord(LowerLine, 'threadvar') then
          begin
            Section := 'var';
            if StartsWithWord(LowerLine, 'threadvar') then
              Start := Length('threadvar')
            else
              Start := Length('var');
            Name := FirstIdentifier(TrimLeft(Copy(LineText, Start + 1, MaxInt)));
            if Name <> '' then
            begin
              AddSymbol(FileName, LineText, I + 1, 'Variable', 'v', RGB(95, 171, 171));
            end;
          end
          else if StartsWithWord(LowerLine, 'const') or StartsWithWord(LowerLine, 'resourcestring') then
          begin
            Section := 'const';
            if StartsWithWord(LowerLine, 'resourcestring') then
              Start := Length('resourcestring')
            else
              Start := Length('const');
            Name := FirstIdentifier(TrimLeft(Copy(LineText, Start + 1, MaxInt)));
            if Name <> '' then
            begin
              AddSymbol(FileName, LineText, I + 1, 'Constant', '#', RGB(204, 160, 91));
            end;
          end
          else if StartsWithWord(LowerLine, 'implementation') or
            StartsWithWord(LowerLine, 'interface') or StartsWithWord(LowerLine, 'uses') or
            StartsWithWord(LowerLine, 'begin') or StartsWithWord(LowerLine, 'end') then
          begin
            Section := '';
            if StartsWithWord(LowerLine, 'end') then
              FInClassDeclaration := False;
          end
          else if (Section = 'type') and (Pos('=', LineText) > 0) and
            (LineText[1] = 'T') then
          begin
            if (Pos('class', LowerLine) > 0) or (Pos('interface', LowerLine) > 0) then
            begin
              AddSymbol(FileName, LineText, I + 1, 'Class', 'C', RGB(221, 173, 91));
              FInClassDeclaration := True;
            end
            else if (Pos('record', LowerLine) > 0) then
            begin
              AddSymbol(FileName, LineText, I + 1, 'Record', 'R', RGB(221, 173, 91));
              FInClassDeclaration := True;
            end
            else
              AddSymbol(FileName, LineText, I + 1, 'Type', 'T', RGB(221, 173, 91));
          end
          else if ((Section = 'var') or FInClassDeclaration) and (Pos(':', LineText) > 0) and
            (Pos('=', LineText) = 0) then
            AddSymbol(FileName, LineText, I + 1, 'Variable', 'v', RGB(95, 171, 171))
          else if (Section = 'const') and (Pos('=', LineText) > 0) then
            AddSymbol(FileName, LineText, I + 1, 'Constant', '#', RGB(204, 160, 91));
        end;
      finally
        Lines.Free;
      end;
    except
      on E: EInOutError do
        Inc(FReadFailures);
      on E: EStreamError do
        Inc(FReadFailures);
      on E: EEncodingError do
        Inc(FReadFailures);
    end;
  end;
end;

procedure TRADESearchForm.SearchChanged(Sender: TObject);
var
  TextValue: string;
begin
  if FChangingSearchText then
    Exit;
  if FEditorAvailable and (FSearchMode = skAction) then
  begin
    TextValue := FSearchEdit.Text;
    if StartsText('file=', TextValue) then
    begin
      SetSearchMode(skFile);
      FChangingSearchText := True;
      try
        FSearchEdit.Text := Copy(TextValue, 6, MaxInt);
        FSearchEdit.SelStart := Length(FSearchEdit.Text);
      finally
        FChangingSearchText := False;
      end;
    end
    else if StartsText('text=', TextValue) then
    begin
      SetSearchMode(skText);
      FChangingSearchText := True;
      try
        FSearchEdit.Text := Copy(TextValue, 6, MaxInt);
        FSearchEdit.SelStart := Length(FSearchEdit.Text);
      finally
        FChangingSearchText := False;
      end;
    end;
  end;
  FSearchTimer.Enabled := False;
  FSearchTimer.Enabled := True;
end;

procedure TRADESearchForm.SetSearchMode(AMode: TSearchKind);
begin
  if not FEditorAvailable and (AMode <> skAction) then
    Exit;
  FSearchMode := AMode;
  case AMode of
    skFile:
      begin
        FModeChipLabel.Caption := 'FILE  [x]';
        FModeChip.Color := RGB(71, 91, 108);
        FSearchEdit.TextHint := 'Search filenames...';
        FModeChip.Visible := True;
      end;
    skText:
      begin
        FModeChipLabel.Caption := 'TEXT  [x]';
        FModeChip.Color := RGB(75, 86, 105);
        FSearchEdit.TextHint := 'Search exact text in files...';
        FModeChip.Visible := True;
      end;
  else
    begin
      FModeChip.Visible := False;
      if FEditorAvailable then
        FSearchEdit.TextHint := 'Search actions and symbols...'
      else
        FSearchEdit.TextHint := 'Search IDE actions...';
    end;
  end;
end;

procedure TRADESearchForm.ModeChipClick(Sender: TObject);
begin
  SetSearchMode(skAction);
  FSearchEdit.Clear;
  FSearchEdit.SetFocus;
end;

procedure TRADESearchForm.SearchTimerTimer(Sender: TObject);
begin
  FSearchTimer.Enabled := False;
  UpdateResults;
end;

procedure TRADESearchForm.SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end
  else if Key = VK_RETURN then
  begin
    FSearchTimer.Enabled := False;
    UpdateResults;
    AcceptSelection;
    Key := 0;
  end
  else if (Key = VK_BACK) and (FSearchMode <> skAction) and
    (FSearchEdit.Text = '') then
  begin
    SetSearchMode(skAction);
    SearchChanged(FSearchEdit);
    Key := 0;
  end
  else if Key = VK_DOWN then
  begin
    FSearchTimer.Enabled := False;
    UpdateResults;
    if FResultsBox.Items.Count > 0 then
    begin
      FResultsBox.SetFocus;
      if FResultsBox.ItemIndex < 0 then
        FResultsBox.ItemIndex := 0;
    end;
    Key := 0;
  end;
end;

procedure TRADESearchForm.ResultsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end
  else if Key = VK_RETURN then
  begin
    AcceptSelection;
    Key := 0;
  end;
end;

procedure TRADESearchForm.ResultsMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (FResultsBox.ItemAtPos(Point(X, Y), True) >= 0) then
    AcceptSelection;
end;

procedure TRADESearchForm.ResultsClick(Sender: TObject);
begin
  UpdateScrollRail;
end;

procedure TRADESearchForm.ResultsMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  VisibleRows, MaximumTop: Integer;
begin
  VisibleRows := Max(1, FResultsBox.ClientHeight div FResultsBox.ItemHeight);
  MaximumTop := Max(0, FResultsBox.Items.Count - VisibleRows);
  FResultsBox.TopIndex := EnsureRange(FResultsBox.TopIndex - WheelDelta div 120 * 3,
    0, MaximumTop);
  Handled := True;
  UpdateScrollRail;
end;

procedure TRADESearchForm.HideNativeScrollbar;
begin
  if FResultsBox.HandleAllocated then
    ShowScrollBar(FResultsBox.Handle, SB_VERT, False);
end;

procedure TRADESearchForm.UpdateScrollRail;
begin
  if Assigned(FScrollRail) then
  begin
    FScrollRail.Visible := FItems.Count >
      Max(1, FResultsBox.ClientHeight div FResultsBox.ItemHeight);
    FScrollRail.Invalidate;
  end;
end;

procedure TRADESearchForm.ScrollRailPaint(Sender: TObject);
var
  Canvas: TCanvas;
  TrackRect, ThumbRect: TRect;
  VisibleRows, MaximumTop, ThumbHeight, ThumbTop: Integer;
begin
  Canvas := FScrollRail.Canvas;
  Canvas.Brush.Color := RGB(48, 50, 52);
  Canvas.FillRect(FScrollRail.ClientRect);
  VisibleRows := Max(1, FResultsBox.ClientHeight div FResultsBox.ItemHeight);
  MaximumTop := FItems.Count - VisibleRows;
  if MaximumTop <= 0 then
    Exit;
  TrackRect := Rect(4, 3, 8, FScrollRail.ClientHeight - 3);
  Canvas.Brush.Color := RGB(58, 60, 62);
  Canvas.Pen.Style := psClear;
  Canvas.RoundRect(TrackRect.Left, TrackRect.Top, TrackRect.Right,
    TrackRect.Bottom, 4, 4);
  ThumbHeight := Max(26, MulDiv(TrackRect.Bottom - TrackRect.Top,
    VisibleRows, FItems.Count));
  ThumbHeight := Min(ThumbHeight, TrackRect.Bottom - TrackRect.Top);
  ThumbTop := TrackRect.Top + MulDiv(
    TrackRect.Bottom - TrackRect.Top - ThumbHeight,
    FResultsBox.TopIndex, MaximumTop);
  ThumbRect := Rect(2, ThumbTop, 10, ThumbTop + ThumbHeight);
  Canvas.Brush.Color := RGB(112, 116, 120);
  Canvas.RoundRect(ThumbRect.Left, ThumbRect.Top, ThumbRect.Right,
    ThumbRect.Bottom, 6, 6);
  Canvas.Pen.Style := psSolid;
end;

procedure TRADESearchForm.ScrollRailMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  TrackHeight, VisibleRows, MaximumTop, ThumbHeight, ThumbTop: Integer;
begin
  if Button <> mbLeft then
    Exit;
  VisibleRows := Max(1, FResultsBox.ClientHeight div FResultsBox.ItemHeight);
  MaximumTop := FItems.Count - VisibleRows;
  if MaximumTop <= 0 then
    Exit;
  TrackHeight := Max(1, FScrollRail.ClientHeight - 6);
  ThumbHeight := Max(26, MulDiv(TrackHeight, VisibleRows, FItems.Count));
  ThumbHeight := Min(ThumbHeight, TrackHeight);
  ThumbTop := 3 + MulDiv(TrackHeight - ThumbHeight,
    FResultsBox.TopIndex, MaximumTop);
  FScrollDragging := True;
  if (Y >= ThumbTop) and (Y < ThumbTop + ThumbHeight) then
    FScrollDragOffset := Y - ThumbTop
  else
  begin
    FScrollDragOffset := ThumbHeight div 2;
    ScrollRailMouseMove(Sender, Shift, X, Y);
  end;
  FScrollRail.MouseCapture := True;
end;

procedure TRADESearchForm.ScrollRailMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  TrackHeight, VisibleRows, MaximumTop, ThumbHeight, ThumbPosition: Integer;
begin
  if not FScrollDragging then
    Exit;
  VisibleRows := Max(1, FResultsBox.ClientHeight div FResultsBox.ItemHeight);
  MaximumTop := FItems.Count - VisibleRows;
  if MaximumTop <= 0 then
    Exit;
  TrackHeight := Max(1, FScrollRail.ClientHeight - 6);
  ThumbHeight := Max(26, MulDiv(TrackHeight, VisibleRows, FItems.Count));
  ThumbHeight := Min(ThumbHeight, TrackHeight);
  ThumbPosition := EnsureRange(Y - 3 - FScrollDragOffset, 0,
    TrackHeight - ThumbHeight);
  FResultsBox.TopIndex := MulDiv(ThumbPosition, MaximumTop,
    Max(1, TrackHeight - ThumbHeight));
  FResultsBox.Invalidate;
  FScrollRail.Invalidate;
  HideNativeScrollbar;
end;

procedure TRADESearchForm.ScrollRailMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FScrollDragging := False;
  FScrollRail.MouseCapture := False;
end;

procedure TRADESearchForm.AcceptSelection;
begin
  if (FResultsBox.ItemIndex >= 0) and (FResultsBox.ItemIndex < FItems.Count) then
  begin
    FSelected := FItems[FResultsBox.ItemIndex];
    FHasSelection := True;
    ModalResult := mrOk;
  end;
end;

procedure TRADESearchForm.DrawResult(Control: TWinControl; AIndex: Integer;
  ARect: TRect; AState: TOwnerDrawState);
var
  Item: TSearchResult;
  IconRect: TRect;
  TextX, TextY: Integer;
  Selected: Boolean;
  TextColor, DetailColor: TColor;
  ACanvas: TCanvas;
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then
    Exit;
  ACanvas := TListBox(Control).Canvas;
  Item := FItems[AIndex];
  Selected := odSelected in AState;
  if Selected then
    ACanvas.Brush.Color := RGB(51, 78, 99)
  else
    ACanvas.Brush.Color := RGB(32, 35, 39);
  ACanvas.FillRect(ARect);

  IconRect := Rect(ARect.Left + 12, ARect.Top + (ARect.Height - 16) div 2,
    ARect.Left + 28, ARect.Top + (ARect.Height + 16) div 2);
  if (Item.Kind = skAction) and (Item.MenuItem <> nil) and not Item.MenuItem.Bitmap.Empty then
    ACanvas.StretchDraw(IconRect, Item.MenuItem.Bitmap)
  else if (Item.Kind = skAction) and (Item.Action is TCustomAction) and
    (TCustomAction(Item.Action).Images <> nil) and (Item.Action.ImageIndex >= 0) and
    (Item.Action.ImageIndex < TCustomAction(Item.Action).Images.Count) then
    TCustomAction(Item.Action).Images.Draw(ACanvas, IconRect.Left, IconRect.Top,
      Item.Action.ImageIndex, True)
  else if (Item.Kind = skAction) and (Item.Action <> nil) and
    (FMenuImages <> nil) and (Item.Action.ImageIndex >= 0) and
    (Item.Action.ImageIndex < FMenuImages.Count) then
    FMenuImages.Draw(ACanvas, IconRect.Left, IconRect.Top, Item.Action.ImageIndex, True)
  else if (Item.Kind = skAction) and (FMenuImages <> nil) and
    (Item.MenuItem <> nil) and (Item.MenuItem.ImageIndex >= 0) and
    (Item.MenuItem.ImageIndex < FMenuImages.Count) then
    FMenuImages.Draw(ACanvas, IconRect.Left, IconRect.Top, Item.MenuItem.ImageIndex, True)
  else
  begin
    ACanvas.Brush.Color := Item.IconColor;
    ACanvas.Pen.Color := Item.IconColor;
    ACanvas.RoundRect(IconRect.Left, IconRect.Top, IconRect.Right, IconRect.Bottom, 4, 4);
    ACanvas.Font.Color := clWhite;
    ACanvas.Font.Style := [fsBold];
    ACanvas.TextRect(IconRect, IconRect.Left, IconRect.Top + 1, Item.IconText);
  end;

  TextX := ARect.Left + 38;
  if Item.Kind = skAction then
    TextY := ARect.Top + Max(0, (ARect.Height - ACanvas.TextHeight(Item.Title)) div 2)
  else
    TextY := ARect.Top + 2;
  ACanvas.Font.Name := 'Segoe UI';
  ACanvas.Font.Size := 9;
  ACanvas.Font.Style := [];
  if Selected then
    TextColor := clWhite
  else
    TextColor := RGB(224, 226, 228);
  DrawHighlightedText(ACanvas, Item.Title, Item.HighlightText, Item.FuzzyHighlight,
    TextX, TextY, TextColor, RGB(190, 139, 55));

  if (Item.Kind <> skAction) and (Item.Detail <> '') then
  begin
    ACanvas.Font.Size := 8;
    if Selected then
      DetailColor := RGB(215, 224, 240)
    else
      DetailColor := RGB(155, 158, 161);
    DrawHighlightedText(ACanvas, Item.Detail, Item.HighlightText, Item.FuzzyHighlight,
      TextX, TextY + 17, DetailColor, RGB(190, 139, 55));
  end;
  FScrollRail.Invalidate;
end;

procedure TRADESearchForm.AddResult(const AResult: TSearchResult);
begin
  if FItems.Count >= CMaximumResults then
    Exit;
  FItems.Add(AResult);
  FResultsBox.Items.Add('');
end;

function TRADESearchForm.SearchMode(const AText: string; out AQuery: string): TSearchKind;
begin
  Result := FSearchMode;
  AQuery := Trim(AText);
  if (Length(AQuery) >= 2) and (AQuery[1] = '"') and
    (AQuery[Length(AQuery)] = '"') then
    AQuery := Copy(AQuery, 2, Length(AQuery) - 2);
end;

procedure TRADESearchForm.SearchFiles(const AQuery: string);
var
  FileName: string;
  Positions: TArray<Integer>;
  Item: TSearchResult;
begin
  for FileName in FFiles do
  begin
    if not IsSubsequence(ExtractFileName(FileName), AQuery, Positions) then
      Continue;
    Item.Kind := skFile;
    Item.Title := ExtractFileName(FileName);
    Item.Detail := ExtractFilePath(FileName);
    Item.FileName := FileName;
    Item.MenuItem := nil;
    Item.Action := nil;
    Item.Line := 0;
    Item.Column := 0;
    Item.IconText := 'F';
    Item.IconColor := RGB(208, 164, 94);
    Item.FuzzyHighlight := True;
    Item.HighlightText := AQuery;
    AddResult(Item);
    if FItems.Count >= CMaximumResults then
      Break;
  end;
end;

procedure TRADESearchForm.SearchText(const AQuery: string);
var
  FileName, Contents, LineText, Snippet: string;
  Lines: TStringList;
  I, MatchAt, StartAt, EndAt, Limit: Integer;
  Item: TSearchResult;
  Extension: string;
begin
  FReadFailures := 0;
  for FileName in FFiles do
  begin
    Extension := LowerCase(ExtractFileExt(FileName));
    if (Extension <> '') and not MatchText(Extension, CTextFileExtensions) then
      Continue;
    try
      Contents := TFile.ReadAllText(FileName);
      if Pos(#0, Contents) > 0 then
        Continue;
      Lines := TStringList.Create;
      try
        Lines.Text := Contents;
        for I := 0 to Lines.Count - 1 do
        begin
          LineText := Lines[I];
          MatchAt := Pos(LowerCase(AQuery), LowerCase(LineText));
          if MatchAt = 0 then
            Continue;
          StartAt := Max(1, MatchAt - 48);
          Limit := Max(160, Length(AQuery) + 96);
          EndAt := Min(Length(LineText), StartAt + Limit - 1);
          Snippet := Copy(LineText, StartAt, EndAt - StartAt + 1);
          if StartAt > 1 then
            Snippet := '...' + Snippet;
          if EndAt < Length(LineText) then
            Snippet := Snippet + '...';
          Item.Kind := skText;
          Item.Title := ExtractFileName(FileName);
          Item.Detail := Format('%d: %s', [I + 1, Snippet]);
          Item.FileName := FileName;
          Item.MenuItem := nil;
          Item.Action := nil;
          Item.Line := I + 1;
          Item.Column := MatchAt;
          Item.IconText := 'T';
          Item.IconColor := RGB(101, 157, 197);
          Item.FuzzyHighlight := False;
          Item.HighlightText := AQuery;
          AddResult(Item);
          if FItems.Count >= CMaximumResults then
            Break;
        end;
      finally
        Lines.Free;
      end;
    except
      on E: EInOutError do
        Inc(FReadFailures);
      on E: EStreamError do
        Inc(FReadFailures);
      on E: EEncodingError do
        Inc(FReadFailures);
    end;
    if FItems.Count >= CMaximumResults then
      Break;
  end;
end;

procedure TRADESearchForm.UpdateResults;
var
  Query: string;
  Mode: TSearchKind;
  Item, ResultItem: TSearchResult;
  SearchTextAll: string;
  Positions: TArray<Integer>;
begin
  FItems.Clear;
  FResultsBox.Items.BeginUpdate;
  try
    FResultsBox.Clear;
    Mode := SearchMode(FSearchEdit.Text, Query);
    if not FEditorAvailable then
      Mode := skAction;
    if Query = '' then
    begin
      if Mode = skAction then
        for Item in FActions do
        begin
          ResultItem := Item;
          ResultItem.HighlightText := '';
          AddResult(ResultItem);
          if FItems.Count >= CMaximumResults then
            Break;
        end;
    end
    else if Mode = skFile then
      SearchFiles(Query)
    else if Mode = skText then
      SearchText(Query)
    else
    begin
      for Item in FActions do
      begin
        SearchTextAll := Item.Title + ' ' + Item.Detail;
        if IsSubsequence(SearchTextAll, Query, Positions) then
        begin
          ResultItem := Item;
          ResultItem.HighlightText := Query;
          AddResult(ResultItem);
        end;
        if FItems.Count >= CMaximumResults then
          Break;
      end;
      if FItems.Count < CMaximumResults then
        for Item in FSymbols do
        begin
          SearchTextAll := Item.Title + ' ' + Item.Detail;
          if IsSubsequence(SearchTextAll, Query, Positions) then
          begin
            ResultItem := Item;
            ResultItem.HighlightText := Query;
            AddResult(ResultItem);
          end;
          if FItems.Count >= CMaximumResults then
            Break;
        end;
    end;
  finally
    FResultsBox.Items.EndUpdate;
  end;
  HideNativeScrollbar;
  if FResultsBox.Items.Count > 0 then
    FResultsBox.ItemIndex := 0;
  SetStatus;
  UpdateScrollRail;
end;

procedure TRADESearchForm.SetStatus;
begin
  if FReadFailures > 0 then
    FStatusLabel.Caption := Format('%d results  |  %d files could not be read', [FItems.Count, FReadFailures])
  else if FItems.Count = 0 then
    FStatusLabel.Caption := 'No results  |  Click or Enter to open  |  Esc to close'
  else if FItems.Count >= CMaximumResults then
    FStatusLabel.Caption := Format('Showing first %d results  |  Click or Enter to open  |  Esc to close',
      [CMaximumResults])
  else
    FStatusLabel.Caption := Format('%d results  |  Click or Enter to open  |  Esc to close',
      [FItems.Count]);
end;

procedure TRADESearchForm.RunResult(const AResult: TSearchResult);
var
  Services: IOTAModuleServices;
  Module: IOTAModule;
begin
  if AResult.Kind = skAction then
  begin
    if (AResult.Action <> nil) and AResult.Action.Enabled then
      AResult.Action.Execute
    else if (AResult.MenuItem <> nil) and AResult.MenuItem.Enabled then
      AResult.MenuItem.Click;
    Exit;
  end;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Module := Services.OpenModule(AResult.FileName);
  if Module = nil then
    Exit;
  Module.Show;
  if AResult.Line > 0 then
    FindTextInEditor(AResult);
end;

function TRADESearchForm.FindTextInEditor(const AResult: TSearchResult): Boolean;
var
  Services: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
  Position: TOTAEditPos;
  BlockStart, BlockAfter: TOTACharPos;
  I: Integer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Module := Services.OpenModule(AResult.FileName);
  if Module = nil then
    Exit;
  for I := 0 to Module.ModuleFileCount - 1 do
  begin
    Editor := Module.ModuleFileEditors[I];
    if not Supports(Editor, IOTASourceEditor, SourceEditor) then
      Continue;
    Editor.Show;
    if SourceEditor.EditViewCount = 0 then
      Exit;
    Position.Line := AResult.Line;
    Position.Col := AResult.Column;
    SourceEditor.EditViews[0].CursorPos := Position;
    if AResult.Kind = skText then
    begin
      BlockStart.Line := AResult.Line;
      BlockStart.CharIndex := AResult.Column - 1;
      BlockAfter.Line := AResult.Line;
      BlockAfter.CharIndex := AResult.Column - 1 + Length(AResult.HighlightText);
      SourceEditor.BlockType := btNonInclusive;
      SourceEditor.BlockStart := BlockStart;
      SourceEditor.BlockAfter := BlockAfter;
      SourceEditor.BlockVisible := AResult.HighlightText <> '';
    end;
    Result := True;
    Exit;
  end;
end;

procedure RADESearch_Show;
var
  SearchForm: TRADESearchForm;
begin
  SearchForm := TRADESearchForm.Create(Application);
  try
    SearchForm.Execute;
  finally
    SearchForm.Free;
  end;
end;

end.

unit RADE.Refactor;

{ Format X for RADEssentials: the formatter and its editor integration, in one unit.

  TRADEFormatX      - the formatter. Pure text in, text out: normalises indentation
                      (begin/end, try, case, repeat, record/class, var/const/type
                      sections, then/else/do bodies, continuation lines), operator and
                      punctuation spacing, tabs, trailing whitespace and blank-line runs.
                      It never joins or splits lines, so your line structure is kept.
  TRADEFormatEditor - the IDE side: guards, selection-or-whole-document, single-step
                      undo, caret/scroll/bookmark restore and status messages. }

interface

uses
  ToolsAPI;

type
  TRADEFormatX = class
  public
    { BaseIndent: columns added to every line (used for selections).
      IndentFirstLine: False when the text starts mid-line. }
    class function FormatSource(const Source: string; BaseIndent: Integer = 0;
      IndentFirstLine: Boolean = True): string;
  end;

  TRADEFormatEditor = class
  public
    { Formats the selection if there is one, otherwise the whole buffer. }
    class function FormatBuffer(const Buffer: IOTAEditBuffer): Boolean;
    { Same, for the buffer in the top edit view. }
    class function FormatActive: Boolean;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.StrUtils, System.UITypes, System.Math,
  System.Generics.Collections, Winapi.Windows, Winapi.ActiveX, Vcl.AxCtrls, Vcl.Dialogs;

{ ===== ENGINE BEGIN ===== }

const
  CIndentSize = 2;
  CKeywords: array[0..64] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor', 'destructor',
    'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file', 'finalization',
    'finally', 'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited', 'initialization',
    'inline', 'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'or', 'out',
    'packed', 'procedure', 'program', 'property', 'raise', 'record', 'repeat', 'resourcestring', 'set',
    'shl', 'shr', 'string', 'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var',
    'while', 'with', 'xor'
  );

type
  TTokKind = (tkWord, tkNumber, tkString, tkSymbol, tkLineComment, tkBlockComment, tkDirective);

  TTok = record
    Kind: TTokKind;
    Text: string;
    Lower: string;
    NewLines: Integer;   // line breaks in the whitespace before this token
    WsBefore: Integer;   // columns of whitespace before this token on its line
    IsKeyword: Boolean;
  end;

  TTokArray = array of TTok;

  TRenameTokenKind = (rtIdentifier, rtPunctuation);

  TRenameToken = record
    Kind: TRenameTokenKind;
    Text: UTF8String;
    StartOffset: Integer;
    EndOffset: Integer;
  end;

  TRenameTokens = TArray<TRenameToken>;

  TRenameEdit = record
    StartOffset: Integer;
    OldLength: Integer;
  end;

  TRenameEdits = TArray<TRenameEdit>;

  TRenameProjectSource = record
    FileName: string;
    UnitName: string;
    Buffer: IOTAEditBuffer;
    OriginalText: UTF8String;
    UpdatedText: UTF8String;
    OriginalBytes: TBytes;
    Encoding: TEncoding;
    PreambleLength: Integer;
    EditorState: TObject;
    Applied: Boolean;
    Tokens: TRenameTokens;
    Edits: TRenameEdits;
  end;

  TRenameProjectSources = TArray<TRenameProjectSource>;

  TRenameScope = record
    RoutineIndex: Integer;
    NameIndex: Integer;
    BodyStartIndex: Integer;
    BodyEndIndex: Integer;
  end;

  TFrameKind = (fkBlock, fkTry, fkRepeat, fkCase, fkRecord);

  TFrame = record
    Kind: TFrameKind;
    SavedP: Integer;     // pending single-statement indent of the enclosing level
  end;

function IsCommentKind(K: TTokKind): Boolean;
begin
  Result := K in [tkLineComment, tkBlockComment, tkDirective];
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := (C = '_') or ((C >= '0') and (C <= '9')) or ((C >= 'a') and (C <= 'z'))
    or ((C >= 'A') and (C <= 'Z')) or (C > #127);
end;

function IsHexChar(C: Char): Boolean;
begin
  Result := ((C >= '0') and (C <= '9')) or ((C >= 'a') and (C <= 'f')) or ((C >= 'A') and (C <= 'F'));
end;

function IsDigit(C: Char): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

function IsRenameIdentByte(C: AnsiChar): Boolean;
var
  Value: Byte;
begin
  Value := Byte(C);
  Result := (C = '_') or ((C >= '0') and (C <= '9')) or
    ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or
    (Value >= $80);
end;

function TokenizeForRename(const Source: UTF8String): TRenameTokens;
var
  I, StartAt, Count: Integer;
  C: AnsiChar;

  procedure AddToken(AKind: TRenameTokenKind; AStart, AEnd: Integer);
  begin
    SetLength(Result, Count + 1);
    Result[Count].Kind := AKind;
    Result[Count].StartOffset := AStart - 1;
    Result[Count].EndOffset := AEnd;
    Result[Count].Text := Copy(Source, AStart, AEnd - AStart + 1);
    Inc(Count);
  end;

begin
  SetLength(Result, 0);
  Count := 0;
  I := 1;
  while I <= Length(Source) do
  begin
    C := AnsiChar(Source[I]);
    if C <= ' ' then
      Inc(I)
    else if (C = '/') and (I < Length(Source)) and (Source[I + 1] = '/') then
    begin
      Inc(I, 2);
      while (I <= Length(Source)) and not (Source[I] in [#10, #13]) do
        Inc(I);
    end
    else if C = '{' then
    begin
      Inc(I);
      while (I <= Length(Source)) and (Source[I] <> '}') do
        Inc(I);
      if I <= Length(Source) then
        Inc(I);
    end
    else if (C = '(') and (I < Length(Source)) and (Source[I + 1] = '*') then
    begin
      Inc(I, 2);
      while (I < Length(Source)) and not ((Source[I] = '*') and (Source[I + 1] = ')')) do
        Inc(I);
      if I < Length(Source) then
        Inc(I, 2);
    end
    else if C = '''' then
    begin
      Inc(I);
      while I <= Length(Source) do
        if Source[I] = '''' then
        begin
          if (I < Length(Source)) and (Source[I + 1] = '''') then
            Inc(I, 2)
          else
          begin
            Inc(I);
            Break;
          end;
        end
        else
          Inc(I);
    end
    else if ((C = '&') and (I < Length(Source)) and IsRenameIdentByte(AnsiChar(Source[I + 1]))
      and not ((Source[I + 1] >= '0') and (Source[I + 1] <= '9'))) then
    begin
      StartAt := I + 1;
      Inc(I, 2);
      while (I <= Length(Source)) and IsRenameIdentByte(AnsiChar(Source[I])) do
        Inc(I);
      AddToken(rtIdentifier, StartAt, I - 1);
    end
    else if IsRenameIdentByte(C) and not ((C >= '0') and (C <= '9')) then
    begin
      StartAt := I;
      Inc(I);
      while (I <= Length(Source)) and IsRenameIdentByte(AnsiChar(Source[I])) do
        Inc(I);
      AddToken(rtIdentifier, StartAt, I - 1);
    end
    else
    begin
      AddToken(rtPunctuation, I, I);
      Inc(I);
    end;
  end;
end;

function RenameTokenIs(const Tokens: TRenameTokens; Index: Integer;
  const Value: string): Boolean;
begin
  Result := (Index >= 0) and (Index <= High(Tokens)) and
    SameText(string(Tokens[Index].Text), Value);
end;

function QualifiedNameAt(const Tokens: TRenameTokens; Index: Integer): string;
var
  I: Integer;
begin
  Result := '';
  if (Index < 0) or (Index > High(Tokens)) or (Tokens[Index].Kind <> rtIdentifier) then
    Exit;
  Result := string(Tokens[Index].Text);
  I := Index + 1;
  while RenameTokenIs(Tokens, I, '.') and (I + 1 <= High(Tokens)) and
    (Tokens[I + 1].Kind = rtIdentifier) do
  begin
    Result := Result + '.' + string(Tokens[I + 1].Text);
    Inc(I, 2);
  end;
end;

function HasUnitQualifier(const Tokens: TRenameTokens; IdentifierIndex: Integer;
  const UnitName: string): Boolean;
var
  StartIndex: Integer;
begin
  Result := False;
  if not RenameTokenIs(Tokens, IdentifierIndex - 1, '.') then
    Exit;
  StartIndex := IdentifierIndex - 2;
  while (StartIndex >= 2) and RenameTokenIs(Tokens, StartIndex - 1, '.') and
    (Tokens[StartIndex - 2].Kind = rtIdentifier) do
    Dec(StartIndex, 2);
  Result := SameText(QualifiedNameAt(Tokens, StartIndex), UnitName);
end;

function IsRoutineKeyword(const Tokens: TRenameTokens; Index: Integer): Boolean;
begin
  Result := RenameTokenIs(Tokens, Index, 'procedure') or
    RenameTokenIs(Tokens, Index, 'function') or
    RenameTokenIs(Tokens, Index, 'constructor') or
    RenameTokenIs(Tokens, Index, 'destructor') or
    RenameTokenIs(Tokens, Index, 'operator');
end;

function FindRoutineBody(const Tokens: TRenameTokens; RoutineIndex: Integer;
  out Scope: TRenameScope): Boolean;
var
  I, Depth: Integer;
begin
  Result := False;
  Scope.RoutineIndex := RoutineIndex;
  Scope.NameIndex := RoutineIndex + 1;
  Scope.BodyStartIndex := -1;
  Scope.BodyEndIndex := -1;
  if not IsRoutineKeyword(Tokens, RoutineIndex) then
    Exit;
  if (Scope.NameIndex > High(Tokens)) or
    (Tokens[Scope.NameIndex].Kind <> rtIdentifier) then
    Exit;
  if RenameTokenIs(Tokens, Scope.NameIndex + 1, '.') then
  begin
    Inc(Scope.NameIndex, 2);
    if (Scope.NameIndex > High(Tokens)) or
      (Tokens[Scope.NameIndex].Kind <> rtIdentifier) then
      Exit;
  end;

  I := Scope.NameIndex + 1;
  while I <= High(Tokens) do
  begin
    if RenameTokenIs(Tokens, I, 'begin') then
    begin
      Scope.BodyStartIndex := I;
      Depth := 1;
      Inc(I);
      while I <= High(Tokens) do
      begin
        if RenameTokenIs(Tokens, I, 'begin') or RenameTokenIs(Tokens, I, 'case') or
          RenameTokenIs(Tokens, I, 'record') or RenameTokenIs(Tokens, I, 'try') or
          RenameTokenIs(Tokens, I, 'asm') then
          Inc(Depth)
        else if RenameTokenIs(Tokens, I, 'end') then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            Scope.BodyEndIndex := I;
            Exit(True);
          end;
        end;
        Inc(I);
      end;
      Exit;
    end;
    if IsRoutineKeyword(Tokens, I) or RenameTokenIs(Tokens, I, 'implementation') or
      RenameTokenIs(Tokens, I, 'interface') or RenameTokenIs(Tokens, I, 'initialization') or
      RenameTokenIs(Tokens, I, 'finalization') then
      Exit;
    Inc(I);
  end;
end;

function FindRoutineAtOffset(const Tokens: TRenameTokens; Offset: Integer;
  out Scope: TRenameScope): Boolean;
var
  I, BestWidth: Integer;
  Candidate: TRenameScope;
begin
  Result := False;
  BestWidth := MaxInt;
  for I := 0 to High(Tokens) do
    if IsRoutineKeyword(Tokens, I) and FindRoutineBody(Tokens, I, Candidate) and
      (Offset >= Tokens[Candidate.RoutineIndex].StartOffset) and
      (Offset <= Tokens[Candidate.BodyEndIndex].EndOffset) then
    begin
      if (Tokens[Candidate.BodyEndIndex].EndOffset -
        Tokens[Candidate.RoutineIndex].StartOffset) < BestWidth then
      begin
        Scope := Candidate;
        BestWidth := Tokens[Candidate.BodyEndIndex].EndOffset -
          Tokens[Candidate.RoutineIndex].StartOffset;
        Result := True;
      end;
    end;
end;

function IsQualifiedIdentifier(const Tokens: TRenameTokens; Index: Integer): Boolean;
begin
  Result := RenameTokenIs(Tokens, Index - 1, '.');
end;

function IsValidRenameName(const Name: UTF8String): Boolean;
var
  Tokens: TRenameTokens;
begin
  Tokens := TokenizeForRename(Name);
  Result := (Length(Tokens) = 1) and (Tokens[0].Kind = rtIdentifier) and
    (Tokens[0].StartOffset = 0) and (Tokens[0].EndOffset = Length(Name)) and
    not MatchText(string(Name), CKeywords) and
    not MatchText(string(Name), ['absolute', 'abstract', 'assembler', 'automated', 'cdecl',
      'contains', 'default', 'deprecated', 'dispid', 'dynamic', 'export', 'external',
      'far', 'final', 'implements', 'index', 'library', 'message', 'name', 'near',
      'nodefault', 'noreturn', 'overload', 'override', 'package', 'pascal', 'platform',
      'private', 'protected', 'public', 'published', 'read', 'readonly', 'register',
      'reintroduce', 'requires', 'resident', 'safecall', 'sealed', 'static', 'stdcall',
      'stored', 'strict', 'unsafe', 'varargs', 'virtual', 'write', 'writeonly']);
end;

function IsDeclarationName(const Tokens: TRenameTokens; Index, Limit: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (Index < 0) or (Index >= Limit) then
    Exit;
  if RenameTokenIs(Tokens, Index + 1, ':') or RenameTokenIs(Tokens, Index + 1, '=') then
    Exit(True);
  if not RenameTokenIs(Tokens, Index + 1, ',') then
    Exit;
  I := Index + 2;
  while I < Limit do
  begin
    if RenameTokenIs(Tokens, I, ':') or RenameTokenIs(Tokens, I, '=') then
      Exit(True);
    if RenameTokenIs(Tokens, I, ';') or RenameTokenIs(Tokens, I, ')') or
      RenameTokenIs(Tokens, I, 'begin') then
      Exit;
    Inc(I);
  end;
end;

function IsInlineVarDeclaration(const Tokens: TRenameTokens; Index: Integer;
  const Scope: TRenameScope): Boolean;
var
  I: Integer;
begin
  Result := False;
  if not IsDeclarationName(Tokens, Index, Scope.BodyEndIndex + 1) then
    Exit;
  for I := Index - 1 downto Scope.BodyStartIndex do
  begin
    if RenameTokenIs(Tokens, I, ';') or RenameTokenIs(Tokens, I, 'begin') or
      RenameTokenIs(Tokens, I, 'end') then
      Exit;
    if RenameTokenIs(Tokens, I, 'var') then
    begin
      Result := not RenameTokenIs(Tokens, I - 1, 'for');
      Exit;
    end;
  end;
end;

function FindLocalDeclaration(const Tokens: TRenameTokens;
  const Scope: TRenameScope; const Name: UTF8String; out DeclIndex: Integer): Boolean;
var
  I, FoundCount: Integer;
begin
  DeclIndex := -1;
  FoundCount := 0;
  for I := Scope.RoutineIndex + 1 to Scope.BodyStartIndex - 1 do
    if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) and
      IsDeclarationName(Tokens, I, Scope.BodyStartIndex) then
    begin
      DeclIndex := I;
      Inc(FoundCount);
    end;
  for I := Scope.BodyStartIndex to Scope.BodyEndIndex - 1 do
    if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) and
      IsInlineVarDeclaration(Tokens, I, Scope) then
    begin
      DeclIndex := I;
      Inc(FoundCount);
    end;
  Result := FoundCount = 1;
end;

function IsInsideClassType(const Tokens: TRenameTokens; RoutineIndex: Integer): Boolean;
var
  I, Depth: Integer;
begin
  Result := False;
  Depth := 0;
  for I := RoutineIndex - 1 downto 0 do
  begin
    if RenameTokenIs(Tokens, I, 'end') then
      Inc(Depth)
    else if RenameTokenIs(Tokens, I, 'begin') or RenameTokenIs(Tokens, I, 'case') or
      RenameTokenIs(Tokens, I, 'try') or RenameTokenIs(Tokens, I, 'asm') then
      Dec(Depth, Ord(Depth > 0))
    else if RenameTokenIs(Tokens, I, 'class') or RenameTokenIs(Tokens, I, 'object') or
      RenameTokenIs(Tokens, I, 'record') then
    begin
      if Depth = 0 then
        Exit(True);
      Dec(Depth);
    end;
    if (Depth = 0) and (RenameTokenIs(Tokens, I, 'implementation') or
      RenameTokenIs(Tokens, I, 'interface') or RenameTokenIs(Tokens, I, 'program') or
      RenameTokenIs(Tokens, I, 'unit') or RenameTokenIs(Tokens, I, 'library')) then
      Exit;
  end;
end;

function IsQualifiedRoutineScope(const Tokens: TRenameTokens;
  const Scope: TRenameScope): Boolean;
begin
  Result := RenameTokenIs(Tokens, Scope.NameIndex - 1, '.') or
    IsInsideClassType(Tokens, Scope.RoutineIndex);
end;

function IsUsesClauseToken(const Tokens: TRenameTokens; Index: Integer): Boolean; forward;
function IsFreeRoutineDeclaration(const Tokens: TRenameTokens;
  NameIndex: Integer): Boolean; forward;

function IsUnitScopeDeclaration(const Tokens: TRenameTokens; Index: Integer): Boolean;
var
  I: Integer;
  Scope: TRenameScope;
begin
  Result := False;
  if FindRoutineAtOffset(Tokens, Tokens[Index].StartOffset, Scope) then
    Exit;
  if IsInsideClassType(Tokens, Index) or
    not IsDeclarationName(Tokens, Index, High(Tokens) + 1) then
    Exit;
  for I := Index - 1 downto 0 do
  begin
    if IsRoutineKeyword(Tokens, I) then
      Exit;
    if RenameTokenIs(Tokens, I, 'var') or RenameTokenIs(Tokens, I, 'threadvar') or
      RenameTokenIs(Tokens, I, 'const') or
      RenameTokenIs(Tokens, I, 'resourcestring') or RenameTokenIs(Tokens, I, 'type') then
      Exit(True);
    if RenameTokenIs(Tokens, I, 'interface') or RenameTokenIs(Tokens, I, 'implementation') or
      RenameTokenIs(Tokens, I, 'unit') or RenameTokenIs(Tokens, I, 'program') or
      RenameTokenIs(Tokens, I, 'library') then
      Exit;
  end;
end;

function HasWithStatement(const Tokens: TRenameTokens; const Scope: TRenameScope): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Scope.RoutineIndex to Scope.BodyEndIndex do
    if RenameTokenIs(Tokens, I, 'with') then
      Exit(True);
end;

function FindTokenAtOffset(const Tokens: TRenameTokens; Offset: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Tokens) do
    if (Offset >= Tokens[I].StartOffset) and (Offset <= Tokens[I].EndOffset) then
      Exit(I);
end;

function FindDeclarationInSelection(const Tokens: TRenameTokens; StartOffset,
  EndOffset: Integer; out SelectedIndex: Integer): Boolean;
var
  I, RoutineCount, DeclarationCount: Integer;
  Scope: TRenameScope;
begin
  Result := False;
  SelectedIndex := -1;
  RoutineCount := 0;
  DeclarationCount := 0;
  for I := 0 to High(Tokens) do
    if (Tokens[I].Kind = rtIdentifier) and
      (Tokens[I].StartOffset >= StartOffset) and (Tokens[I].EndOffset <= EndOffset) and
      IsFreeRoutineDeclaration(Tokens, I) then
    begin
      SelectedIndex := I;
      Inc(RoutineCount);
    end;
  if RoutineCount = 1 then
    Exit(True);
  if RoutineCount > 1 then
    Exit;

  SelectedIndex := -1;
  for I := 0 to High(Tokens) do
    if (Tokens[I].Kind = rtIdentifier) and
      (Tokens[I].StartOffset >= StartOffset) and (Tokens[I].EndOffset <= EndOffset) then
    begin
      if IsUnitScopeDeclaration(Tokens, I) then
      begin
        SelectedIndex := I;
        Inc(DeclarationCount);
      end
      else if FindRoutineAtOffset(Tokens, Tokens[I].StartOffset, Scope) and
        (IsDeclarationName(Tokens, I, Scope.BodyStartIndex) or
          IsInlineVarDeclaration(Tokens, I, Scope)) then
      begin
        SelectedIndex := I;
        Inc(DeclarationCount);
      end;
    end;
  Result := DeclarationCount = 1;
  if not Result then
    SelectedIndex := -1;
end;

function IsPascalRenameFile(const FileName: string): Boolean;
begin
  Result := MatchText(TPath.GetExtension(FileName), ['.pas', '.dpr', '.dpk', '.inc']);
end;

procedure AddRenameProjectFiles(const Project: IOTAProject; Files: TStrings);
var
  I, J: Integer;
  ModuleInfo: IOTAModuleInfo;
  AdditionalFiles: TStringList;
begin
  if Project = nil then
    Exit;
  for I := 0 to Project.GetModuleCount - 1 do
  begin
    ModuleInfo := Project.GetModule(I);
    if IsPascalRenameFile(ModuleInfo.FileName) and FileExists(ModuleInfo.FileName) then
      Files.Add(ModuleInfo.FileName);
    AdditionalFiles := TStringList.Create;
    try
      ModuleInfo.GetAdditionalFiles(AdditionalFiles);
      for J := 0 to AdditionalFiles.Count - 1 do
        if IsPascalRenameFile(AdditionalFiles[J]) and FileExists(AdditionalFiles[J]) then
          Files.Add(AdditionalFiles[J]);
    finally
      AdditionalFiles.Free;
    end;
  end;
end;

function CollectRenameProjectFiles(const ActiveFile: string): TStringList;
var
  ModuleServices: IOTAModuleServices;
  ProjectGroup: IOTAProjectGroup;
  Project: IOTAProject;
  I: Integer;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  Result.CaseSensitive := False;
  if IsPascalRenameFile(ActiveFile) and (ActiveFile <> '') then
    Result.Add(ActiveFile);
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  ProjectGroup := ModuleServices.MainProjectGroup;
  if ProjectGroup <> nil then
    for I := 0 to ProjectGroup.ProjectCount - 1 do
      AddRenameProjectFiles(ProjectGroup.GetProject(I), Result)
  else
  begin
    Project := ModuleServices.GetActiveProject;
    AddRenameProjectFiles(Project, Result);
  end;
end;

procedure AddRenameEdit(var Edits: TRenameEdits; const Token: TRenameToken);
var
  Count: Integer;
begin
  Count := Length(Edits);
  SetLength(Edits, Count + 1);
  Edits[Count].StartOffset := Token.StartOffset;
  Edits[Count].OldLength := Token.EndOffset - Token.StartOffset;
end;

function HasSameNameLocalDeclaration(const Tokens: TRenameTokens;
  const Scope: TRenameScope; const Name: UTF8String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Scope.RoutineIndex + 1 to Scope.BodyStartIndex - 1 do
    if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) and
      IsDeclarationName(Tokens, I, Scope.BodyStartIndex) then
      Exit(True);
  for I := Scope.BodyStartIndex to Scope.BodyEndIndex - 3 do
  begin
    if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) and
      IsInlineVarDeclaration(Tokens, I, Scope) then
      Exit(True);
    if RenameTokenIs(Tokens, I, 'for') and RenameTokenIs(Tokens, I + 1, 'var') and
      (Tokens[I + 2].Kind = rtIdentifier) and
      SameText(string(Tokens[I + 2].Text), string(Name)) then
      Exit(True);
  end;
end;

function HasLocalDeclarationAnywhere(const Tokens: TRenameTokens;
  const Name: UTF8String): Boolean;
var
  I: Integer;
  Scope: TRenameScope;
begin
  Result := False;
  for I := 0 to High(Tokens) do
    if IsRoutineKeyword(Tokens, I) and FindRoutineBody(Tokens, I, Scope) and
      HasSameNameLocalDeclaration(Tokens, Scope, Name) then
      Exit(True);
end;

function BuildUnitSymbolRenameEdits(const Tokens: TRenameTokens; SelectedIndex: Integer;
  const Name: UTF8String; out Edits: TRenameEdits): Boolean;
var
  I, DeclarationCount: Integer;
  Scope: TRenameScope;
  HasUnresolvedReference: Boolean;
begin
  Result := False;
  HasUnresolvedReference := False;
  SetLength(Edits, 0);
  if IsInsideClassType(Tokens, SelectedIndex) or IsUsesClauseToken(Tokens, SelectedIndex) then
    Exit;
  DeclarationCount := 0;
  for I := 0 to High(Tokens) do
    if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) and
      IsUnitScopeDeclaration(Tokens, I) then
      Inc(DeclarationCount);
  if DeclarationCount <> 1 then
    Exit;

  for I := 0 to High(Tokens) do
    if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) then
    begin
      if IsUnitScopeDeclaration(Tokens, I) then
        AddRenameEdit(Edits, Tokens[I])
      else if not IsQualifiedIdentifier(Tokens, I) and
        not IsUsesClauseToken(Tokens, I) and
        not RenameTokenIs(Tokens, I - 1, 'unit') and
        not RenameTokenIs(Tokens, I - 1, 'program') and
        not RenameTokenIs(Tokens, I - 1, 'library') then
      begin
        if FindRoutineAtOffset(Tokens, Tokens[I].StartOffset, Scope) then
        begin
          if HasSameNameLocalDeclaration(Tokens, Scope, Name) then
            Continue;
          if IsQualifiedRoutineScope(Tokens, Scope) or HasWithStatement(Tokens, Scope) then
          begin
            HasUnresolvedReference := True;
            Continue;
          end;
        end
        else if IsInsideClassType(Tokens, I) then
        begin
          if IsDeclarationName(Tokens, I, High(Tokens) + 1) or
            IsRoutineKeyword(Tokens, I - 1) then
            Continue;
          AddRenameEdit(Edits, Tokens[I]);
          Continue;
        end
        else if IsDeclarationName(Tokens, I, High(Tokens) + 1) then
          Continue;
        AddRenameEdit(Edits, Tokens[I]);
      end;
    end;
  if HasUnresolvedReference then
  begin
    SetLength(Edits, 0);
    Exit;
  end;
  Result := Length(Edits) > 0;
end;

function IsFreeRoutineDeclaration(const Tokens: TRenameTokens;
  NameIndex: Integer): Boolean;
begin
  Result := (NameIndex > 0) and IsRoutineKeyword(Tokens, NameIndex - 1) and
    not RenameTokenIs(Tokens, NameIndex + 1, '.') and
    not IsInsideClassType(Tokens, NameIndex - 1);
end;

function IsUsesClauseToken(const Tokens: TRenameTokens; Index: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Index - 1 downto 0 do
  begin
    if RenameTokenIs(Tokens, I, ';') then
      Exit;
    if RenameTokenIs(Tokens, I, 'uses') then
      Exit(True);
    if RenameTokenIs(Tokens, I, 'interface') or RenameTokenIs(Tokens, I, 'implementation') or
      RenameTokenIs(Tokens, I, 'begin') then
      Exit;
  end;
end;

function BuildScopedRenameEdits(const Tokens: TRenameTokens; SelectedIndex: Integer;
  out Edits: TRenameEdits; out IsLocal: Boolean): Boolean;
var
  I, DeclIndex, LocalStartIndex: Integer;
  Name: UTF8String;
  Scope, OccurrenceScope: TRenameScope;
  HasRoutineDeclaration: Boolean;
  HasUnresolvedReference: Boolean;
begin
  Result := False;
  HasUnresolvedReference := False;
  IsLocal := False;
  SetLength(Edits, 0);
  if (SelectedIndex < 0) or (SelectedIndex > High(Tokens)) or
    (Tokens[SelectedIndex].Kind <> rtIdentifier) or
    IsQualifiedIdentifier(Tokens, SelectedIndex) or IsUsesClauseToken(Tokens, SelectedIndex) or
    RenameTokenIs(Tokens, SelectedIndex - 1, 'unit') or
    RenameTokenIs(Tokens, SelectedIndex - 1, 'program') or
    RenameTokenIs(Tokens, SelectedIndex - 1, 'library') or
    IsInsideClassType(Tokens, SelectedIndex) then
    Exit;
  Name := Tokens[SelectedIndex].Text;

  if FindRoutineAtOffset(Tokens, Tokens[SelectedIndex].StartOffset, Scope) then
  begin
    if FindLocalDeclaration(Tokens, Scope, Name, DeclIndex) then
    begin
      if HasWithStatement(Tokens, Scope) then
        Exit;
      IsLocal := True;
      LocalStartIndex := Scope.RoutineIndex;
      if DeclIndex >= Scope.BodyStartIndex then
        LocalStartIndex := DeclIndex;
      for I := LocalStartIndex to Scope.BodyEndIndex do
        if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) and
          not IsQualifiedIdentifier(Tokens, I) and
          FindRoutineAtOffset(Tokens, Tokens[I].StartOffset, OccurrenceScope) and
          (OccurrenceScope.RoutineIndex = Scope.RoutineIndex) then
        begin
          if IsInsideClassType(Tokens, I) and
            (IsDeclarationName(Tokens, I, High(Tokens) + 1) or
              IsRoutineKeyword(Tokens, I - 1)) then
            Continue;
          AddRenameEdit(Edits, Tokens[I]);
        end;
      Result := Length(Edits) > 0;
      Exit;
    end;
    if HasSameNameLocalDeclaration(Tokens, Scope, Name) then
      Exit;
    if IsQualifiedRoutineScope(Tokens, Scope) then
      Exit;
  end;

  HasRoutineDeclaration := False;
  for I := 0 to High(Tokens) do
    if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) then
    begin
      if IsFreeRoutineDeclaration(Tokens, I) then
        HasRoutineDeclaration := True
      else if IsDeclarationName(Tokens, I, High(Tokens) + 1) and
        not IsUsesClauseToken(Tokens, I) and
        not IsUnitScopeDeclaration(Tokens, I) and
        not FindRoutineAtOffset(Tokens, Tokens[I].StartOffset, OccurrenceScope) then
        Exit;
    end;
  if not HasRoutineDeclaration then
    Exit(BuildUnitSymbolRenameEdits(Tokens, SelectedIndex, Name, Edits));

  for I := 0 to High(Tokens) do
    if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) and
      not IsQualifiedIdentifier(Tokens, I) then
    begin
      if IsFreeRoutineDeclaration(Tokens, I) then
        AddRenameEdit(Edits, Tokens[I])
      else if not IsInsideClassType(Tokens, I) and
        not IsUsesClauseToken(Tokens, I) and
        not RenameTokenIs(Tokens, I - 1, 'unit') and
        not RenameTokenIs(Tokens, I - 1, 'program') and
        not RenameTokenIs(Tokens, I - 1, 'library') then
      begin
        if FindRoutineAtOffset(Tokens, Tokens[I].StartOffset, OccurrenceScope) then
        begin
          if HasSameNameLocalDeclaration(Tokens, OccurrenceScope, Name) then
            Continue;
          if IsQualifiedRoutineScope(Tokens, OccurrenceScope) or
            HasWithStatement(Tokens, OccurrenceScope) then
          begin
            HasUnresolvedReference := True;
            Continue;
          end;
        end
        else if IsDeclarationName(Tokens, I, High(Tokens) + 1) then
          Continue;
        AddRenameEdit(Edits, Tokens[I]);
      end;
    end;
  if HasUnresolvedReference then
  begin
    SetLength(Edits, 0);
    Exit;
  end;
  Result := Length(Edits) > 0;
end;

function Tokenize(const Src: string): TTokArray;
var
  I, N, Start, NL, Ws, Cnt: Integer;
  C: Char;

  procedure Add(AKind: TTokKind; const AText: string);
  begin
    if Cnt = Length(Result) then
      SetLength(Result, Cnt * 2 + 64);
    Result[Cnt].Kind := AKind;
    Result[Cnt].Text := AText;
    Result[Cnt].Lower := LowerCase(AText);
    Result[Cnt].NewLines := NL;
    Result[Cnt].WsBefore := Ws;
    Result[Cnt].IsKeyword := (AKind = tkWord) and MatchStr(Result[Cnt].Lower, CKeywords);
    Inc(Cnt);
    NL := 0;
    Ws := 0;
  end;

  function AtEol(Idx: Integer): Boolean;
  begin
    Result := (Src[Idx] = #10) or (Src[Idx] = #13);
  end;

begin
  SetLength(Result, 0);
  N := Length(Src);
  I := 1;
  NL := 0;
  Ws := 0;
  Cnt := 0;
  while I <= N do
  begin
    C := Src[I];
    if C = #10 then
    begin
      Inc(NL);
      Ws := 0;
      Inc(I);
    end
    else if C = #13 then
    begin
      if (I = N) or (Src[I + 1] <> #10) then
      begin
        Inc(NL);
        Ws := 0;
      end;
      Inc(I);
    end
    else if C = #$FEFF then
      Inc(I)
    else if C <= ' ' then
    begin
      Inc(Ws);
      Inc(I);
    end
    else if (C = '/') and (I < N) and (Src[I + 1] = '/') then
    begin
      Start := I;
      while (I <= N) and not AtEol(I) do
        Inc(I);
      Add(tkLineComment, TrimRight(Copy(Src, Start, I - Start)));
    end
    else if C = '{' then
    begin
      Start := I;
      Inc(I);
      while (I <= N) and (Src[I] <> '}') do
        Inc(I);
      if I <= N then
        Inc(I);
      if (Start < N) and (Src[Start + 1] = '$') then
        Add(tkDirective, Copy(Src, Start, I - Start))
      else
        Add(tkBlockComment, Copy(Src, Start, I - Start));
    end
    else if (C = '(') and (I < N) and (Src[I + 1] = '*') then
    begin
      Start := I;
      Inc(I, 2);
      while (I <= N) and not ((Src[I] = '*') and (I < N) and (Src[I + 1] = ')')) do
        Inc(I);
      if I <= N then
        Inc(I, 2);
      if (Start + 2 <= N) and (Src[Start + 2] = '$') then
        Add(tkDirective, Copy(Src, Start, I - Start))
      else
        Add(tkBlockComment, Copy(Src, Start, I - Start));
    end
    else if C = '''' then
    begin
      Start := I;
      Inc(I);
      while I <= N do
      begin
        if Src[I] = '''' then
        begin
          if (I < N) and (Src[I + 1] = '''') then
            Inc(I, 2)
          else
          begin
            Inc(I);
            Break;
          end;
        end
        else if AtEol(I) then
          Break
        else
          Inc(I);
      end;
      Add(tkString, Copy(Src, Start, I - Start));
    end
    else if (C = '#') then
    begin
      Start := I;
      Inc(I);
      if (I <= N) and (Src[I] = '$') then
      begin
        Inc(I);
        while (I <= N) and IsHexChar(Src[I]) do
          Inc(I);
      end
      else
        while (I <= N) and IsDigit(Src[I]) do
          Inc(I);
      Add(tkString, Copy(Src, Start, I - Start));
    end
    else if IsIdentChar(C) and not IsDigit(C) or ((C = '&') and (I < N) and IsIdentChar(Src[I + 1])) then
    begin
      Start := I;
      Inc(I);
      while (I <= N) and IsIdentChar(Src[I]) do
        Inc(I);
      Add(tkWord, Copy(Src, Start, I - Start));
    end
    else if IsDigit(C) or ((C = '$') and (I < N) and IsHexChar(Src[I + 1])) then
    begin
      Start := I;
      if C = '$' then
      begin
        Inc(I);
        while (I <= N) and IsHexChar(Src[I]) do
          Inc(I);
      end
      else
      begin
        while (I <= N) and IsDigit(Src[I]) do
          Inc(I);
        if (I < N) and (Src[I] = '.') and IsDigit(Src[I + 1]) then
        begin
          Inc(I);
          while (I <= N) and IsDigit(Src[I]) do
            Inc(I);
        end;
        if (I <= N) and ((Src[I] = 'e') or (Src[I] = 'E')) then
          if ((I < N) and IsDigit(Src[I + 1]))
            or ((I + 1 < N) and ((Src[I + 1] = '+') or (Src[I + 1] = '-')) and IsDigit(Src[I + 2])) then
          begin
            Inc(I, 2);
            while (I <= N) and IsDigit(Src[I]) do
              Inc(I);
          end;
      end;
      Add(tkNumber, Copy(Src, Start, I - Start));
    end
    else
    begin
      if (I < N) and MatchStr(Copy(Src, I, 2), [':=', '<>', '<=', '>=', '..']) then
      begin
        Add(tkSymbol, Copy(Src, I, 2));
        Inc(I, 2);
      end
      else
      begin
        Add(tkSymbol, C);
        Inc(I);
      end;
    end;
  end;
  SetLength(Result, Cnt);
end;

function IsOpSym(const S: string): Boolean;
begin
  Result := MatchStr(S, [':=', '=', '<>', '<=', '>=', '<', '>', '+', '-', '*', '/']);
end;

class function TRADEFormatX.FormatSource(const Source: string; BaseIndent: Integer;
  IndentFirstLine: Boolean): string;
var
  Toks: TTokArray;
  Frames: array of TFrame;
  FCount, FrameIndent, P, Decl, Paren: Integer;
  PrevOpEnd, FirstOut, PopFirst, WasEmpty: Boolean;
  SB: TStringBuilder;
  I, J, K, A, B, FirstCode, LastCode, Ind, Eff, DeclLine, DeclNext, Spaces: Integer;
  T, L: string;

  function PrevCodeIdx(Idx: Integer): Integer;
  begin
    Result := Idx - 1;
    while (Result >= 0) and IsCommentKind(Toks[Result].Kind) do
      Dec(Result);
  end;

  function NextCodeIdx(Idx: Integer): Integer;
  begin
    Result := Idx + 1;
    while (Result < Length(Toks)) and IsCommentKind(Toks[Result].Kind) do
      Inc(Result);
    if Result >= Length(Toks) then
      Result := -1;
  end;

  function ValueTok(Idx: Integer): Boolean;
  begin
    Result := False;
    if Idx < 0 then
      Exit;
    case Toks[Idx].Kind of
      tkNumber, tkString: Result := True;
      tkWord: Result := (not Toks[Idx].IsKeyword) or (Toks[Idx].Lower = 'nil');
      tkSymbol: Result := MatchStr(Toks[Idx].Text, [')', ']', '^']);
    end;
  end;

  { Is the '<' or '>' at Idx part of a generic argument list (TList<Integer>)
    rather than a comparison? Only plain identifiers, commas, dots, nested angle
    brackets and constraint words may sit between the brackets. }
  function IsGenericAngle(Idx: Integer): Boolean;
  var
    Q, Depth, Steps, OpenIdx: Integer;

    function Allowed(Q2: Integer): Boolean;
    begin
      case Toks[Q2].Kind of
        tkWord: Result := (not Toks[Q2].IsKeyword) or MatchStr(Toks[Q2].Lower, ['class', 'record', 'constructor', 'string']);
        tkSymbol: Result := MatchStr(Toks[Q2].Text, [',', '.', '<', '>', ':']);
      else
        Result := False;
      end;
    end;

  begin
    Result := False;
    OpenIdx := -1;
    Depth := 0;
    Steps := 0;
    if Toks[Idx].Text = '<' then
    begin
      Q := Idx;
      while (Q < Length(Toks)) and (Steps < 40) do
      begin
        if IsCommentKind(Toks[Q].Kind) or not Allowed(Q) then
          Break;
        if Toks[Q].Text = '<' then
          Inc(Depth)
        else if Toks[Q].Text = '>' then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            OpenIdx := Idx;
            Break;
          end;
        end;
        Inc(Q);
        Inc(Steps);
      end;
    end
    else if Toks[Idx].Text = '>' then
    begin
      Q := Idx;
      while (Q >= 0) and (Steps < 40) do
      begin
        if IsCommentKind(Toks[Q].Kind) or not Allowed(Q) then
          Break;
        if Toks[Q].Text = '>' then
          Inc(Depth)
        else if Toks[Q].Text = '<' then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            OpenIdx := Q;
            Break;
          end;
        end;
        Dec(Q);
        Inc(Steps);
      end;
    end;
    if OpenIdx >= 0 then
    begin
      Q := PrevCodeIdx(OpenIdx);
      Result := (Q >= 0) and (Toks[Q].Kind = tkWord) and not Toks[Q].IsKeyword;
    end;
  end;

  function BinaryOp(Idx: Integer): Boolean;
  begin
    if MatchStr(Toks[Idx].Text, ['+', '-']) then
      Result := ValueTok(PrevCodeIdx(Idx))
    else if MatchStr(Toks[Idx].Text, ['<', '>']) then
      Result := not IsGenericAngle(Idx)
    else
      Result := True;
  end;

  { A line that begins with a binary operator continues the previous expression. }
  function StartsWithOperator(Idx: Integer): Boolean;
  begin
    if Toks[Idx].Kind = tkWord then
      Result := MatchStr(Toks[Idx].Lower, ['and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as'])
    else
      Result := (Toks[Idx].Kind = tkSymbol) and MatchStr(Toks[Idx].Text, ['=', '<>', '<=', '>=', '+', '*', '/']);
  end;

  function WordLike(const Tk: TTok): Boolean;
  begin
    Result := Tk.Kind in [tkWord, tkNumber];
  end;

  function GapBefore(Idx: Integer): Integer;
  var
    PT, CT: TTok;
    PS, CS: string;
  begin
    PT := Toks[Idx - 1];
    CT := Toks[Idx];
    if IsCommentKind(CT.Kind) then
    begin
      Result := CT.WsBefore;
      if (CT.Kind = tkLineComment) and (Result < 1) then
        Result := 1;
      Exit;
    end;
    if IsCommentKind(PT.Kind) then
      Exit(CT.WsBefore);
    PS := '';
    CS := '';
    if PT.Kind = tkSymbol then
      PS := PT.Text;
    if CT.Kind = tkSymbol then
      CS := CT.Text;

    if MatchStr(CS, [',', ';', ')', ']', '.', '..']) then
      Exit(0);
    if MatchStr(CS, ['<', '>']) and IsGenericAngle(Idx) then
      Exit(0);
    if (PS = '<') and IsGenericAngle(Idx - 1) then
      Exit(0);
    if (PS = '>') and IsGenericAngle(Idx - 1) and MatchStr(CS, ['(', '[']) then
      Exit(0);
    if (CS = '^') and ValueTok(Idx - 1) then
      Exit(0);
    if MatchStr(PS, ['(', '[', '@', '.', '..']) then
      Exit(0);
    if CS = '(' then
    begin
      if ValueTok(Idx - 1) then
        Exit(0);
      if PT.IsKeyword then
      begin
        if MatchStr(PT.Lower, ['function', 'procedure', 'constructor', 'destructor', 'string', 'class']) then
          Exit(0);
        Exit(1);
      end;
    end;
    if CS = '[' then
    begin
      if ValueTok(Idx - 1) or MatchStr(PT.Lower, ['array', 'string']) then
        Exit(0);
      if PT.IsKeyword then
        Exit(1);
    end;
    if (PS = ',') or (PS = ';') then
      Exit(1);
    if CS = ':' then
      Exit(0);
    if PS = ':' then
      Exit(1);
    if (CS <> '') and IsOpSym(CS) and BinaryOp(Idx) then
      Exit(1);
    if (PS <> '') and IsOpSym(PS) then
    begin
      if BinaryOp(Idx - 1) then
        Exit(1)
      else
        Exit(0); // unary: hug the operand
    end;
    if WordLike(PT) and WordLike(CT) then
      Exit(1);
    Result := Min(CT.WsBefore, 1);
  end;

  procedure Push(AKind: TFrameKind);
  begin
    if FCount = Length(Frames) then
      SetLength(Frames, FCount * 2 + 16);
    Frames[FCount].Kind := AKind;
    Frames[FCount].SavedP := P;
    Inc(FrameIndent, 1 + P);
    P := 0;
    Inc(FCount);
  end;

  procedure Pop;
  begin
    if FCount > 0 then
    begin
      Dec(FCount);
      P := Frames[FCount].SavedP;
      Dec(FrameIndent, 1 + P);
    end
    else
    begin
      P := 0;
      FrameIndent := 0;
    end;
  end;

  { Does the 'class' token at Idx open a body that is closed by 'end'? }
  function ClassHasBody(Idx: Integer): Boolean;
  var
    N, Depth: Integer;
  begin
    Result := True;
    N := NextCodeIdx(Idx);
    if N < 0 then
      Exit;
    if MatchStr(Toks[N].Lower, ['of', ';']) then
      Exit(False);
    if Toks[N].Text = '(' then
    begin
      Depth := 0;
      while N >= 0 do
      begin
        if Toks[N].Text = '(' then
          Inc(Depth)
        else if Toks[N].Text = ')' then
        begin
          Dec(Depth);
          if Depth = 0 then
            Break;
        end;
        N := NextCodeIdx(N);
      end;
      if N >= 0 then
      begin
        N := NextCodeIdx(N);
        if (N >= 0) and (Toks[N].Text = ';') then
          Exit(False);
      end;
    end;
  end;

  function PrevCodeText(Idx: Integer): string;
  var
    Q: Integer;
  begin
    Q := PrevCodeIdx(Idx);
    if Q < 0 then
      Result := ''
    else
      Result := Toks[Q].Lower;
  end;

begin
  Toks := Tokenize(Source);
  if Length(Toks) = 0 then
    Exit('');

  SetLength(Frames, 32);
  FCount := 0;
  FrameIndent := 0;
  P := 0;
  Decl := 0;
  Paren := 0;
  PrevOpEnd := False;
  FirstOut := True;
  SB := TStringBuilder.Create;
  try
    I := 0;
    while I < Length(Toks) do
    begin
      A := I;
      J := I + 1;
      while (J < Length(Toks)) and (Toks[J].NewLines = 0) do
        Inc(J);
      B := J - 1;
      I := J;

      FirstCode := -1;
      LastCode := -1;
      for K := A to B do
        if not IsCommentKind(Toks[K].Kind) then
        begin
          if FirstCode < 0 then
            FirstCode := K;
          LastCode := K;
        end;

      if FirstCode < 0 then
      begin
        // comment-only line
        if Toks[A].Kind = tkDirective then
          Ind := 0
        else
          Ind := Decl + FrameIndent + P;
      end
      else
      begin
        T := Toks[FirstCode].Lower;

        DeclLine := Decl;
        DeclNext := Decl;
        if FCount = 0 then
        begin
          if MatchStr(T, ['var', 'const', 'type', 'threadvar', 'resourcestring', 'label', 'uses']) then
          begin
            DeclLine := 0;
            DeclNext := 1;
          end
          else if MatchStr(T, ['procedure', 'function', 'constructor', 'destructor', 'begin', 'implementation',
            'interface', 'initialization', 'finalization', 'end', 'asm', 'program', 'unit', 'library', 'class']) then
          begin
            DeclLine := 0;
            DeclNext := 0;
          end;
        end;

        PopFirst := MatchStr(T, ['end', 'until']);
        WasEmpty := FCount = 0;
        if PopFirst then
          Pop
        else if (T = 'else') or (MatchStr(T, ['begin', 'try', 'case', 'repeat', 'asm']) and (P > 0)) then
        begin
          if P > 0 then
            Dec(P);
        end;

        Ind := DeclLine + FrameIndent + P;
        if MatchStr(T, ['except', 'finally']) then
          Dec(Ind)
        else if MatchStr(T, ['private', 'protected', 'public', 'published', 'strict', 'automated'])
          and (FCount > 0) and (Frames[FCount - 1].Kind = fkRecord) then
          Dec(Ind)
        else
        begin
          Eff := Paren;
          if MatchStr(Toks[FirstCode].Text, [')', ']']) and (Eff > 0) then
            Dec(Eff);
          if (Eff > 0) or PrevOpEnd or StartsWithOperator(FirstCode) then
            Inc(Ind);
        end;
        if WasEmpty and PopFirst and (T = 'end') then
          Ind := 0;

        // update state from every code token on the line
        for K := A to B do
        begin
          if IsCommentKind(Toks[K].Kind) then
            Continue;
          L := Toks[K].Lower;
          if Toks[K].Kind = tkWord then
          begin
            if (K = FirstCode) and PopFirst then
              // already popped above
            else if (L = 'end') or (L = 'until') then
              Pop
            else if L = 'begin' then
              Push(fkBlock)
            else if L = 'asm' then
              Push(fkBlock)
            else if L = 'try' then
              Push(fkTry)
            else if L = 'repeat' then
              Push(fkRepeat)
            else if L = 'case' then
            begin
              if not ((FCount > 0) and (Frames[FCount - 1].Kind = fkRecord)) then
                Push(fkCase);
            end
            else if L = 'record' then
              Push(fkRecord)
            else if L = 'class' then
            begin
              if MatchStr(PrevCodeText(K), ['=', 'packed']) and ClassHasBody(K) then
                Push(fkRecord);
            end
            else if MatchStr(L, ['interface', 'dispinterface', 'object']) then
            begin
              if PrevCodeText(K) = '=' then
                Push(fkRecord);
            end;
          end
          else if Toks[K].Kind = tkSymbol then
          begin
            if (L = '(') or (L = '[') then
              Inc(Paren)
            else if ((L = ')') or (L = ']')) and (Paren > 0) then
              Dec(Paren);
          end;
        end;

        // end-of-line state
        L := Toks[LastCode].Lower;
        if (Toks[LastCode].Kind = tkSymbol) and (L = ';') then
          P := 0
        else if (Toks[LastCode].Kind = tkWord) and MatchStr(L, ['then', 'else', 'do']) then
          Inc(P);
        PrevOpEnd := ((Toks[LastCode].Kind = tkSymbol) and IsOpSym(L))
          or ((Toks[LastCode].Kind = tkWord)
            and MatchStr(L, ['and', 'or', 'xor', 'not', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as']));
        Decl := DeclNext;
      end;

      if Ind < 0 then
        Ind := 0;

      // emit
      if not FirstOut then
      begin
        SB.Append(#13#10);
        if Toks[A].NewLines > 1 then
          SB.Append(#13#10);
      end;
      Spaces := Ind * CIndentSize + BaseIndent;
      if FirstOut and not IndentFirstLine then
        Spaces := 0;
      SB.Append(StringOfChar(' ', Spaces));
      SB.Append(Toks[A].Text);
      for K := A + 1 to B do
      begin
        SB.Append(StringOfChar(' ', GapBefore(K)));
        SB.Append(Toks[K].Text);
      end;
      FirstOut := False;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ===== ENGINE END ===== }

{ ===== EDITOR BEGIN ===== }

const
  CSupportedExts: array[0..3] of string = ('.pas', '.dpr', '.dpk', '.inc');
  CMaxBookmark = 19;       // the ToolsAPI supports 0..19, the UI only 0..9
  CMaxUndoKiB = 4096;      // above this size the undo history is dropped to keep the IDE responsive

type
  TViewState = record
    Offset: Integer;       // 0-based UTF-8 byte offset of the caret
    RowsFromTop: Integer;  // caret row relative to the top visible row
  end;

  TEditorState = class
  private
    FViews: TArray<TViewState>;
    FBookmarkIds: TList<Integer>;
    FBookmarkOffsets: TList<Integer>;
  public
    constructor Create(const Buffer: IOTAEditBuffer);
    destructor Destroy; override;
    procedure Remap(const OldText, NewText: UTF8String);
    procedure RemapRenames(const Edits: TRenameEdits; NewNameLength: Integer);
    procedure Apply(const Buffer: IOTAEditBuffer);
  end;

function StreamToUTF8(const Stream: IStream): UTF8String;
var
  OleStream: TOleStream;
begin
  OleStream := TOleStream.Create(Stream);
  try
    SetLength(Result, OleStream.Size);
    if Length(Result) = 0 then
      Exit;
    OleStream.Seek(0, soBeginning);
    if OleStream.Read(Result[1], Length(Result)) <> OleStream.Size then
      raise Exception.Create('The editor content could not be read');
  finally
    OleStream.Free;
  end;
end;

function FindOpenRenameBuffer(const ModuleServices: IOTAModuleServices;
  const FileName: string): IOTAEditBuffer;
var
  Module: IOTAModule;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
  View: IOTAEditView;
  I, J, K: Integer;
begin
  Result := nil;
  for I := 0 to ModuleServices.ModuleCount - 1 do
  begin
    Module := ModuleServices.Modules[I];
    for J := 0 to Module.ModuleFileCount - 1 do
    begin
      Editor := Module.ModuleFileEditors[J];
      if not Supports(Editor, IOTASourceEditor, SourceEditor) then
        Continue;
      for K := 0 to SourceEditor.EditViewCount - 1 do
      begin
        View := SourceEditor.EditViews[K];
        if (View.Buffer <> nil) and SameText(View.Buffer.FileName, FileName) then
          Exit(View.Buffer);
      end;
    end;
  end;
end;

function ReadRenameProjectSource(const FileName: string;
  const ModuleServices: IOTAModuleServices; out Source: TRenameProjectSource): Boolean;
var
  Content: IOTAEditorContent;
  BomLength: Integer;
  I: Integer;
begin
  Source.FileName := FileName;
  Source.UnitName := '';
  Source.Buffer := nil;
  Source.OriginalText := '';
  Source.UpdatedText := '';
  Source.Encoding := nil;
  Source.PreambleLength := 0;
  Source.EditorState := nil;
  Source.Applied := False;
  SetLength(Source.OriginalBytes, 0);
  SetLength(Source.Tokens, 0);
  SetLength(Source.Edits, 0);

  Source.Buffer := FindOpenRenameBuffer(ModuleServices, FileName);
  if Source.Buffer <> nil then
  begin
    if not Supports(Source.Buffer, IOTAEditorContent, Content) then
      Exit(False);
    Source.OriginalText := StreamToUTF8(Content.Content);
  end
  else
  begin
    Source.OriginalBytes := TFile.ReadAllBytes(FileName);
    Source.Encoding := TEncoding.UTF8;
    BomLength := TEncoding.GetBufferEncoding(Source.OriginalBytes, Source.Encoding,
      TEncoding.UTF8);
    if (BomLength = 0) and (Source.Encoding = TEncoding.UTF8) and
      not Source.Encoding.IsBufferValid(Source.OriginalBytes) then
      Source.Encoding := TEncoding.ANSI;
    Source.PreambleLength := BomLength;
    Source.OriginalText := UTF8String(Source.Encoding.GetString(Source.OriginalBytes,
      BomLength, Length(Source.OriginalBytes) - BomLength));
  end;

  Source.Tokens := TokenizeForRename(Source.OriginalText);
  for I := 0 to High(Source.Tokens) - 1 do
    if RenameTokenIs(Source.Tokens, I, 'unit') and
      (Source.Tokens[I + 1].Kind = rtIdentifier) then
    begin
      Source.UnitName := QualifiedNameAt(Source.Tokens, I + 1);
      Break;
    end;
  Result := True;
end;

function IsInUnitInterface(const Tokens: TRenameTokens; Index: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Index - 1 downto 0 do
  begin
    if RenameTokenIs(Tokens, I, 'implementation') then
      Exit;
    if RenameTokenIs(Tokens, I, 'interface') then
      Exit(True);
  end;
end;

function UsesUnit(const Tokens: TRenameTokens; const UnitName: string): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  for I := 0 to High(Tokens) do
    if RenameTokenIs(Tokens, I, 'uses') then
    begin
      J := I + 1;
      while (J <= High(Tokens)) and not RenameTokenIs(Tokens, J, ';') do
      begin
        if (Tokens[J].Kind = rtIdentifier) and not RenameTokenIs(Tokens, J - 1, '.') and
          SameText(QualifiedNameAt(Tokens, J), UnitName) then
          Exit(True);
        Inc(J);
      end;
    end;
end;

function IsInterfaceDeclaration(const Tokens: TRenameTokens; Index: Integer): Boolean;
begin
  Result := (IsFreeRoutineDeclaration(Tokens, Index) and
    IsInUnitInterface(Tokens, Index - 1)) or
    (IsUnitScopeDeclaration(Tokens, Index) and IsInUnitInterface(Tokens, Index));
end;

function HasInterfaceDeclaration(const Tokens: TRenameTokens;
  const Name: UTF8String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Tokens) do
    if (Tokens[I].Kind = rtIdentifier) and SameText(string(Tokens[I].Text), string(Name)) and
      IsInterfaceDeclaration(Tokens, I) then
      Exit(True);
end;

function HasImportedNameConflict(const Sources: TRenameProjectSources; SourceIndex: Integer;
  const TargetUnit, Name: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Sources) do
    if (I <> SourceIndex) and (Sources[I].UnitName <> '') and
      not SameText(Sources[I].UnitName, TargetUnit) and
      UsesUnit(Sources[SourceIndex].Tokens, Sources[I].UnitName) and
      HasInterfaceDeclaration(Sources[I].Tokens, UTF8String(Name)) then
      Exit(True);
end;

function BuildImportedRenameEdits(const Sources: TRenameProjectSources; SourceIndex: Integer;
  const TargetUnit, Name: string; out Edits: TRenameEdits): Boolean;
var
  I: Integer;
  Scope: TRenameScope;
  HasUnresolvedReference, ConflictingImport, QualifiedForTarget: Boolean;
begin
  HasUnresolvedReference := False;
  SetLength(Edits, 0);
  if (TargetUnit = '') or not UsesUnit(Sources[SourceIndex].Tokens, TargetUnit) then
    Exit(True);
  ConflictingImport := HasImportedNameConflict(Sources, SourceIndex, TargetUnit, Name);

  for I := 0 to High(Sources[SourceIndex].Tokens) do
    if (Sources[SourceIndex].Tokens[I].Kind = rtIdentifier) and
      SameText(string(Sources[SourceIndex].Tokens[I].Text), Name) and
      not IsUsesClauseToken(Sources[SourceIndex].Tokens, I) then
    begin
      QualifiedForTarget := HasUnitQualifier(Sources[SourceIndex].Tokens, I, TargetUnit);
      if IsQualifiedIdentifier(Sources[SourceIndex].Tokens, I) then
      begin
        if QualifiedForTarget then
          AddRenameEdit(Edits, Sources[SourceIndex].Tokens[I]);
        Continue;
      end;
      if RenameTokenIs(Sources[SourceIndex].Tokens, I - 1, 'unit') or
        RenameTokenIs(Sources[SourceIndex].Tokens, I - 1, 'program') or
        RenameTokenIs(Sources[SourceIndex].Tokens, I - 1, 'library') then
        Continue;
      if IsRoutineKeyword(Sources[SourceIndex].Tokens, I - 1) then
        Continue;
      if FindRoutineAtOffset(Sources[SourceIndex].Tokens,
        Sources[SourceIndex].Tokens[I].StartOffset, Scope) then
      begin
        if HasSameNameLocalDeclaration(Sources[SourceIndex].Tokens, Scope,
          UTF8String(Name)) then
          Continue;
        if IsQualifiedRoutineScope(Sources[SourceIndex].Tokens, Scope) or
          HasWithStatement(Sources[SourceIndex].Tokens, Scope) then
        begin
          HasUnresolvedReference := True;
          Continue;
        end;
      end
      else if IsUnitScopeDeclaration(Sources[SourceIndex].Tokens, I) then
        Continue
      else if IsDeclarationName(Sources[SourceIndex].Tokens, I, High(Sources[SourceIndex].Tokens) + 1) then
        Continue;

      if ConflictingImport then
      begin
        HasUnresolvedReference := True;
        Continue;
      end;
      AddRenameEdit(Edits, Sources[SourceIndex].Tokens[I]);
    end;

  if HasUnresolvedReference then
  begin
    SetLength(Edits, 0);
    Exit(False);
  end;
  Result := True;
end;

function ApplyRenameEdits(const Source: UTF8String; const Edits: TRenameEdits;
  const NewName: UTF8String): UTF8String;
var
  I: Integer;
begin
  Result := Source;
  for I := High(Edits) downto 0 do
    Result := Copy(Result, 1, Edits[I].StartOffset) + NewName +
      Copy(Result, Edits[I].StartOffset + Edits[I].OldLength + 1, MaxInt);
end;

function EncodeRenameProjectSource(const Source: TRenameProjectSource): TBytes;
var
  EncodedText: TBytes;
begin
  EncodedText := Source.Encoding.GetBytes(string(Source.UpdatedText));
  SetLength(Result, Source.PreambleLength + Length(EncodedText));
  if Source.PreambleLength > 0 then
    Move(Source.OriginalBytes[0], Result[0], Source.PreambleLength);
  if Length(EncodedText) > 0 then
    Move(EncodedText[0], Result[Source.PreambleLength], Length(EncodedText));
end;

function ApplyProjectRename(const ActiveBuffer: IOTAEditBuffer;
  const ActiveText: UTF8String; const ActiveTokens: TRenameTokens;
  const ActiveEdits: TRenameEdits; const OldName, NewName: UTF8String;
  out ChangedFileCount, ReferenceCount: Integer): Boolean;
var
  ModuleServices: IOTAModuleServices;
  ProjectFiles: TStringList;
  Sources: TRenameProjectSources;
  Writer: IOTAEditWriter;
  SourceFile: TRenameProjectSource;
  NewNameBytes: TBytes;
  TargetUnit: string;
  I, J, ActiveSourceIndex: Integer;
begin
  Result := False;
  ChangedFileCount := 0;
  ReferenceCount := 0;
  SetLength(Sources, 0);
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  ProjectFiles := CollectRenameProjectFiles(ActiveBuffer.FileName);
  try
    SetLength(Sources, ProjectFiles.Count);
    ActiveSourceIndex := -1;
    TargetUnit := '';
    for I := 0 to ProjectFiles.Count - 1 do
    begin
      if SameText(ProjectFiles[I], ActiveBuffer.FileName) then
      begin
        SourceFile.FileName := ProjectFiles[I];
        SourceFile.UnitName := '';
        SourceFile.Buffer := ActiveBuffer;
        SourceFile.OriginalText := ActiveText;
        SourceFile.UpdatedText := '';
        SourceFile.OriginalBytes := nil;
        SourceFile.Encoding := nil;
        SourceFile.PreambleLength := 0;
        SourceFile.EditorState := nil;
        SourceFile.Applied := False;
        SourceFile.Tokens := ActiveTokens;
        SourceFile.Edits := ActiveEdits;
        for J := 0 to High(ActiveTokens) - 1 do
          if RenameTokenIs(ActiveTokens, J, 'unit') and
            (ActiveTokens[J + 1].Kind = rtIdentifier) then
          begin
            SourceFile.UnitName := QualifiedNameAt(ActiveTokens, J + 1);
            Break;
          end;
        Sources[I] := SourceFile;
        ActiveSourceIndex := I;
        TargetUnit := SourceFile.UnitName;
      end
      else if not ReadRenameProjectSource(ProjectFiles[I], ModuleServices, Sources[I]) then
        Exit;
    end;
    if (ActiveSourceIndex < 0) or (TargetUnit = '') then
      Exit;
    for I := 0 to High(Sources) do
      if (I <> ActiveSourceIndex) and SameText(Sources[I].UnitName, TargetUnit) then
      begin
        MessageDlg(Format('Rename was cancelled because more than one project unit is named %s.',
          [TargetUnit]), mtWarning, [mbOK], 0);
        Exit;
      end;

    for I := 0 to High(Sources) do
    begin
      if I <> ActiveSourceIndex then
      begin
        if not BuildImportedRenameEdits(Sources, I, TargetUnit, string(OldName),
          Sources[I].Edits) then
        begin
          MessageDlg(Format('Rename was cancelled because references in %s are ambiguous.',
            [ExtractFileName(Sources[I].FileName)]), mtWarning, [mbOK], 0);
          Exit;
        end;
        if (Length(Sources[I].Edits) > 0) and
          (HasLocalDeclarationAnywhere(Sources[I].Tokens, NewName) or
            HasImportedNameConflict(Sources, I, TargetUnit, string(NewName))) then
        begin
          MessageDlg(Format('Rename was cancelled because %s would conflict in %s.',
            [string(NewName), ExtractFileName(Sources[I].FileName)]),
            mtWarning, [mbOK], 0);
          Exit;
        end;
      end;

      if Length(Sources[I].Edits) = 0 then
        Continue;
      Sources[I].UpdatedText := ApplyRenameEdits(Sources[I].OriginalText,
        Sources[I].Edits, NewName);
      if Sources[I].UpdatedText = Sources[I].OriginalText then
        Continue;
      Inc(ChangedFileCount);
      Inc(ReferenceCount, Length(Sources[I].Edits));
      if (Sources[I].Buffer <> nil) and Sources[I].Buffer.IsReadOnly then
      begin
        MessageDlg(Format('Rename was cancelled because %s is read-only.',
          [ExtractFileName(Sources[I].FileName)]), mtWarning, [mbOK], 0);
        Exit;
      end;
      if (Sources[I].Buffer = nil) and
        ((GetFileAttributes(PChar(Sources[I].FileName)) and FILE_ATTRIBUTE_READONLY) <> 0) then
      begin
        MessageDlg(Format('Rename was cancelled because %s is read-only.',
          [ExtractFileName(Sources[I].FileName)]), mtWarning, [mbOK], 0);
        Exit;
      end;
    end;

    if ChangedFileCount = 0 then
      Exit;
    if (ChangedFileCount > 1) and
      (MessageDlg(Format('Rename %s to %s in %d project files (%d references)?',
        [string(OldName), string(NewName), ChangedFileCount, ReferenceCount]),
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
      Exit;

    try
      for I := 0 to High(Sources) do
      begin
        if (Sources[I].UpdatedText = '') or
          (Sources[I].UpdatedText = Sources[I].OriginalText) then
          Continue;
        if Sources[I].Buffer <> nil then
        begin
          Sources[I].EditorState := TEditorState.Create(Sources[I].Buffer);
          Writer := Sources[I].Buffer.CreateUndoableWriter;
          try
            Writer.DeleteTo(MaxInt);
            Sources[I].Applied := True;
            Writer.Insert(PAnsiChar(Sources[I].UpdatedText));
          finally
            Writer := nil;
          end;
        end
        else
        begin
          Sources[I].Applied := True;
          NewNameBytes := EncodeRenameProjectSource(Sources[I]);
          TFile.WriteAllBytes(Sources[I].FileName, NewNameBytes);
        end;
      end;

      for I := 0 to High(Sources) do
        if Sources[I].Applied and (Sources[I].Buffer <> nil) then
        begin
          TEditorState(Sources[I].EditorState).RemapRenames(Sources[I].Edits, Length(NewName));
          TEditorState(Sources[I].EditorState).Apply(Sources[I].Buffer);
        end;
      Result := True;
    except
      on E: Exception do
      begin
        for I := High(Sources) downto 0 do
          if Sources[I].Applied then
            try
              if Sources[I].Buffer <> nil then
                Sources[I].Buffer.Undo
              else
                TFile.WriteAllBytes(Sources[I].FileName, Sources[I].OriginalBytes);
            except
              on RollbackError: Exception do
                OutputDebugString(PChar('RADEssentials Rename rollback error: ' +
                  RollbackError.Message));
            end;
        MessageDlg('Project rename failed and completed edits were rolled back: ' + E.Message,
          mtError, [mbOK], 0);
      end;
    end;
  finally
    for I := 0 to High(Sources) do
      Sources[I].EditorState.Free;
    ProjectFiles.Free;
  end;
end;

function TrimTrailingBreaks(const S: UTF8String): UTF8String;
var
  L: Integer;
begin
  L := Length(S);
  while (L > 0) and ((S[L] = #10) or (S[L] = #13)) do
    Dec(L);
  Result := Copy(S, 1, L);
end;

function EndsWithBreak(const S: UTF8String): Boolean;
begin
  Result := (S <> '') and ((S[Length(S)] = #10) or (S[Length(S)] = #13));
end;

procedure SetStatus(const Buffer: IOTAEditBuffer; const Msg: string);
var
  I: Integer;
begin
  for I := 0 to Buffer.EditViewCount - 1 do
    Buffer.EditViews[I].SetTempMsg(Msg);
end;

{ Cursor mapping: a formatter only changes whitespace, so "number of
  non-whitespace bytes before the caret" is the same in the old and new text. }

function CountNonWs(const S: UTF8String; UpToOffset: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  if UpToOffset > Length(S) then
    UpToOffset := Length(S);
  for I := 1 to UpToOffset do
    if S[I] > #32 then
      Inc(Result);
end;

function OffsetAfterNonWs(const S: UTF8String; Count: Integer): Integer;
var
  I, Seen: Integer;
begin
  if Count <= 0 then
    Exit(0);
  Seen := 0;
  for I := 1 to Length(S) do
  begin
    if S[I] > #32 then
      Inc(Seen);
    if Seen = Count then
      Exit(I);
  end;
  Result := Length(S);
end;

function MapRenameOffset(Offset: Integer; const Edits: TRenameEdits;
  NewNameLength: Integer): Integer;
var
  I, Delta, EditEnd: Integer;
begin
  Delta := 0;
  for I := 0 to High(Edits) do
  begin
    EditEnd := Edits[I].StartOffset + Edits[I].OldLength;
    if Offset >= EditEnd then
      Inc(Delta, NewNameLength - Edits[I].OldLength)
    else if Offset >= Edits[I].StartOffset then
      Exit(Edits[I].StartOffset + Delta + NewNameLength);
  end;
  Result := Offset + Delta;
end;

function ConfirmFormatWhileDebugging: Boolean;
begin
  Result := MessageDlg('Formatting will disrupt debugging in this file. Continue?',
    mtWarning, [mbOK, mbCancel], 0, mbCancel) = mrOK;
end;

{ TEditorState }

constructor TEditorState.Create(const Buffer: IOTAEditBuffer);
var
  I, B: Integer;
  View: IOTAEditView;
  EditPos: TOTAEditPos;
  CharPos: TOTACharPos;
begin
  FBookmarkIds := TList<Integer>.Create;
  FBookmarkOffsets := TList<Integer>.Create;
  SetLength(FViews, Buffer.EditViewCount);

  for I := 0 to Buffer.EditViewCount - 1 do
  begin
    View := Buffer.EditViews[I];
    EditPos := View.CursorPos;
    View.ConvertPos(True, EditPos, CharPos);
    FViews[I].Offset := View.CharPosToPos(CharPos);
    FViews[I].RowsFromTop := View.Position.Row - View.TopRow;
  end;

  if Buffer.EditViewCount > 0 then
  begin
    View := Buffer.EditViews[0]; // bookmarks are shared by all views of a buffer
    for B := 0 to CMaxBookmark do
    begin
      CharPos := View.BookmarkPos[B];
      if CharPos.Line <> 0 then
      begin
        FBookmarkIds.Add(B);
        FBookmarkOffsets.Add(View.CharPosToPos(CharPos));
      end;
    end;
  end;
end;

destructor TEditorState.Destroy;
begin
  FBookmarkIds.Free;
  FBookmarkOffsets.Free;
  inherited;
end;

procedure TEditorState.Remap(const OldText, NewText: UTF8String);
var
  I: Integer;
begin
  for I := 0 to High(FViews) do
    FViews[I].Offset := OffsetAfterNonWs(NewText, CountNonWs(OldText, FViews[I].Offset));
  for I := 0 to FBookmarkOffsets.Count - 1 do
    FBookmarkOffsets[I] := OffsetAfterNonWs(NewText, CountNonWs(OldText, FBookmarkOffsets[I]));
end;

procedure TEditorState.RemapRenames(const Edits: TRenameEdits; NewNameLength: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FViews) do
    FViews[I].Offset := MapRenameOffset(FViews[I].Offset, Edits, NewNameLength);
  for I := 0 to FBookmarkOffsets.Count - 1 do
    FBookmarkOffsets[I] := MapRenameOffset(FBookmarkOffsets[I], Edits, NewNameLength);
end;

procedure TEditorState.Apply(const Buffer: IOTAEditBuffer);
var
  I: Integer;
  View: IOTAEditView;
  EditPos: TOTAEditPos;
  CharPos: TOTACharPos;
begin
  // Bookmarks first: recreating them moves the caret around.
  if (Buffer.EditViewCount > 0) and (FBookmarkIds.Count > 0) then
  begin
    View := Buffer.EditViews[0];
    for I := 0 to FBookmarkIds.Count - 1 do
    begin
      CharPos := View.PosToCharPos(FBookmarkOffsets[I]);
      View.ConvertPos(False, EditPos, CharPos);
      View.CursorPos := EditPos;
      View.BookmarkToggle(FBookmarkIds[I]);
    end;
  end;

  // Carets last, then repaint once.
  for I := 0 to Buffer.EditViewCount - 1 do
  begin
    if I > High(FViews) then
      Break;
    View := Buffer.EditViews[I];
    CharPos := View.PosToCharPos(FViews[I].Offset);
    View.ConvertPos(False, EditPos, CharPos);
    View.CursorPos := EditPos;
    View.Scroll((View.Position.Row - View.TopRow) - FViews[I].RowsFromTop, 0);
    View.Paint;
  end;
end;

{ Selection bounds as 0-based UTF-8 byte offsets. False if nothing is selected. }
function TryGetSelection(const Buffer: IOTAEditBuffer; out StartOff, EndOff: Integer): Boolean;
var
  View: IOTAEditView;
  Block: IOTAEditBlock;
  EditPos: TOTAEditPos;
  CharPos: TOTACharPos;
begin
  Result := False;
  StartOff := 0;
  EndOff := 0;
  View := Buffer.TopView;
  if View = nil then
    Exit;
  Block := View.Block;
  if (Block = nil) or (Block.Size = 0) then
    Exit;

  EditPos.Line := Block.StartingRow;
  EditPos.Col := Block.StartingColumn;
  View.ConvertPos(True, EditPos, CharPos);
  StartOff := View.CharPosToPos(CharPos);

  EditPos.Line := Block.EndingRow;
  EditPos.Col := Block.EndingColumn;
  View.ConvertPos(True, EditPos, CharPos);
  EndOff := View.CharPosToPos(CharPos);

  Result := EndOff > StartOff;
end;

{ Puts the caret at a 0-based UTF-8 byte offset in the top view and drops the selection. }
procedure MoveCaretToOffset(const Buffer: IOTAEditBuffer; Offset: Integer);
var
  View: IOTAEditView;
  EditPos: TOTAEditPos;
  CharPos: TOTACharPos;
begin
  View := Buffer.TopView;
  if View = nil then
    Exit;
  if View.Block <> nil then
    View.Block.Reset;
  CharPos := View.PosToCharPos(Offset);
  View.ConvertPos(False, EditPos, CharPos);
  View.CursorPos := EditPos;
  View.Paint;
end;

{ TRADEFormatEditor }

class function TRADEFormatEditor.FormatActive: Boolean;
var
  Services: IOTAEditorServices;
  View: IOTAEditView;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, Services) then
    Exit;
  View := Services.TopView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Result := FormatBuffer(View.Buffer);
end;

class function TRADEFormatEditor.FormatBuffer(const Buffer: IOTAEditBuffer): Boolean;
var
  Content: IOTAEditorContent;
  Debugger: IOTADebuggerServices;
  State: TEditorState;
  OldText, NewText, Fragment, Formatted: UTF8String;
  SelStart, SelEnd, LineStart, LeadLen: Integer;
  HasSelection, WholeLine: Boolean;
  Writer: IOTAEditWriter;
begin
  Result := False;

  if not MatchText(TPath.GetExtension(Buffer.FileName), CSupportedExts) then
    Exit;
  if not Supports(Buffer, IOTAEditorContent, Content) then
    Exit;
  if Buffer.IsReadOnly then
  begin
    SetStatus(Buffer, 'File is read-only');
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTADebuggerServices, Debugger)
    and Assigned(Debugger.CurrentProcess) and not ConfirmFormatWhileDebugging then
    Exit;

  SetStatus(Buffer, 'Formatting...');
  State := TEditorState.Create(Buffer);
  try
    try
      OldText := StreamToUTF8(Content.Content);
      HasSelection := TryGetSelection(Buffer, SelStart, SelEnd);

      if HasSelection then
      begin
        // indentation of the line the selection starts on
        LineStart := SelStart;
        while (LineStart > 0) and (OldText[LineStart] <> #10) do
          Dec(LineStart);
        LeadLen := 0;
        while (LineStart + LeadLen < Length(OldText))
          and ((OldText[LineStart + LeadLen + 1] = ' ') or (OldText[LineStart + LeadLen + 1] = #9)) do
          Inc(LeadLen);
        WholeLine := Trim(string(Copy(OldText, LineStart + 1, SelStart - LineStart))) = '';
        if WholeLine then
          SelStart := LineStart; // take the indentation into the replaced range

        Fragment := Copy(OldText, SelStart + 1, SelEnd - SelStart);
        Formatted := UTF8String(TRADEFormatX.FormatSource(string(Fragment), LeadLen, WholeLine));
        Formatted := TrimTrailingBreaks(Formatted);
        if EndsWithBreak(Fragment) then
          Formatted := Formatted + #13#10;
        NewText := Copy(OldText, 1, SelStart) + Formatted + Copy(OldText, SelEnd + 1, MaxInt);
      end
      else
      begin
        Formatted := UTF8String(TRADEFormatX.FormatSource(string(OldText)));
        // the IDE appends a line break after an insert, so don't send our own
        Formatted := TrimTrailingBreaks(Formatted);
        NewText := Formatted;
      end;

      if TrimTrailingBreaks(NewText) = TrimTrailingBreaks(OldText) then
      begin
        SetStatus(Buffer, 'Already formatted');
        Exit(True);
      end;

      SetStatus(Buffer, 'Rendering...');

      if (Length(OldText) div 1024 > CMaxUndoKiB) and not HasSelection then
        Content.Content := TStreamAdapter.Create(TStringStream.Create(NewText), soOwned) as IStream
      else
      begin
        Writer := Buffer.CreateUndoableWriter;
        if HasSelection then
        begin
          Writer.CopyTo(SelStart);
          Writer.DeleteTo(SelEnd);
          Writer.Insert(PAnsiChar(Formatted));
        end
        else
        begin
          Writer.DeleteTo(MaxInt);
          Writer.Insert(PAnsiChar(Formatted));
        end;
        Writer := nil; // release so the edit is committed before the views are touched
      end;

      State.Remap(OldText, NewText);
      State.Apply(Buffer);

      // after formatting a selection, leave the caret at the end of its last line
      if HasSelection then
        MoveCaretToOffset(Buffer, SelStart + Length(TrimTrailingBreaks(Formatted)));

      SetStatus(Buffer, 'Formatted');
      Result := True;
    except
      on E: Exception do
      begin
        OutputDebugString(PChar('RADEssentials Format X error: ' + E.Message));
        SetStatus(Buffer, 'Format error');
      end;
    end;
  finally
    State.Free;
  end;
end;

{ ===== EDITOR END ===== }

end.

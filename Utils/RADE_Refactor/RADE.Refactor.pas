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

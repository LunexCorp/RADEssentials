unit RadeGit.Integration;

// The ONLY unit your main RAD Essentials unit needs to talk to.
// See INTEGRATION.md for exactly where to call each function.

interface

uses
  Vcl.Menus;

// Call once when your plugin starts, BEFORE building menus
procedure RadeGit_Init;

// Call when your plugin unloads (before/while freeing your menus)
procedure RadeGit_Done;

// Adds "RADE Git" under your RAD Essentials menu. Greyed out if Git is missing.
function RadeGit_AddMenuItem(AParent: TMenuItem): TMenuItem;

// Adds "RAD Essentials" to the IDE's Help menu (opens the help window)
function RadeGit_AddHelpMenuItem: TMenuItem;

// Call from a button in your existing Settings window
procedure RadeGit_OpenSettings;

implementation

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics, ToolsAPI, Winapi.Windows,
  RadeGit.Core, RadeGit.DockForm, RadeGit.HelpForm, RadeGit.Settings;

type
  TRadeGitHandlers = class
  public
    procedure OpenDock(Sender: TObject);
    procedure OpenHelp(Sender: TObject);
  end;

var
  GHandlers: TRadeGitHandlers;
  GHelpItem: TMenuItem;

procedure TRadeGitHandlers.OpenDock(Sender: TObject);
begin
  RadeGit_ShowDock;
end;

procedure TRadeGitHandlers.OpenHelp(Sender: TObject);
begin
  RadeGit_ShowHelp;
end;

procedure RadeGit_Init;
begin
  if GHandlers <> nil then
    Exit;
  GHandlers := TRadeGitHandlers.Create;
  RadeGit_CheckGitInstalledOnce; // shows the "install Git" message once
  RadeGit_RegisterDock;
end;

procedure RadeGit_Done;
begin
  FreeAndNil(GHelpItem);   // lives in the IDE's Help menu, so we must remove it
  RadeGit_FreeDock;
  RadeGit_CloseHelp;
  FreeAndNil(GHandlers);
  // The "RADE Git" item belongs to YOUR menu and is freed with it.
end;

function RadeGit_AddMenuItem(AParent: TMenuItem): TMenuItem;
begin
  RadeGit_Init;
  Result := TMenuItem.Create(AParent);
  Result.Caption := 'RADE Git';
  Result.Enabled := RadeGit_CheckGitInstalledOnce;
  if not Result.Enabled then
    Result.Hint := 'Git is not installed. Install it and restart RAD Studio.';
  Result.OnClick := GHandlers.OpenDock;
  AParent.Add(Result);
end;

function RadeGit_AddHelpMenuItem: TMenuItem;
var
  LServices: INTAServices;
  LMain: TMainMenu;
  LHelp: TMenuItem;
  LIcon: Vcl.Graphics.TBitmap;
  LMenuBitmap: Vcl.Graphics.TBitmap;
  I: Integer;
begin
  Result := nil;
  RadeGit_Init;
  if not Supports(BorlandIDEServices, INTAServices, LServices) then
    Exit;
  LMain := LServices.MainMenu;
  if (LMain = nil) or (LMain.Items.Count = 0) then
    Exit;
  LHelp := nil;
  for I := 0 to LMain.Items.Count - 1 do
    if SameText(LMain.Items[I].Name, 'HelpMenu') then
    begin
      LHelp := LMain.Items[I];
      Break;
    end;
  if LHelp = nil then
    LHelp := LMain.Items[LMain.Items.Count - 1];
  GHelpItem := TMenuItem.Create(LHelp);
  GHelpItem.Caption := 'RAD Essentials';
  GHelpItem.OnClick := GHandlers.OpenHelp;
  LIcon := Vcl.Graphics.TBitmap.Create;
  try
    LIcon.LoadFromResourceName(HInstance, 'ICONBMP');
    LMenuBitmap := Vcl.Graphics.TBitmap.Create;
    try
      LMenuBitmap.PixelFormat := pf24bit;
      LMenuBitmap.SetSize(16, 16);
      LMenuBitmap.Canvas.StretchDraw(Rect(0, 0, 16, 16), LIcon);
      GHelpItem.Bitmap.Assign(LMenuBitmap);
    finally
      LMenuBitmap.Free;
    end;
  finally
    LIcon.Free;
  end;
  LHelp.Add(GHelpItem);
  Result := GHelpItem;
end;

procedure RadeGit_OpenSettings;
begin
  RadeGit_ShowSettingsDialog;
end;

end.

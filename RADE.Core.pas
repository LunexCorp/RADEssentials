unit RADE.Core;

interface

uses
  ToolsAPI, Vcl.Menus, Vcl.Dialogs, Vcl.Graphics, System.SysUtils, System.Classes, System.IniFiles, System.IOUtils, Vcl.ActnList;

type
  { Editor key binding. Shortcuts on a plain TAction only fire while focus is in the IDE's
    main window; an IOTAKeyboardBinding is what makes them work inside the code editor. }
  TRADEKeyBinding = class(TNotifierObject, IOTAKeyboardBinding)
  private
    FFormatXKey, FPDFKey: TShortCut;
    FOnFormatX, FOnPDF: TNotifyEvent;
    procedure DoFormatX(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
    procedure DoPDF(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
  public
    constructor Create(AFormatXKey, APDFKey: TShortCut; const AOnFormatX, AOnPDF: TNotifyEvent);
    { IOTAKeyboardBinding }
    function GetBindingType: TBindingType;
    function GetDisplayName: string;
    function GetName: string;
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
  end;

  TRADEWizard = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  private
    FKeyBindingIndex: Integer;
    FActionFormatX: TAction;
    FActionPDF: TAction;
    FActionSettings: TAction;
    FActionList: TActionList;
    FParentMenu: TMenuItem;
    FSplashBitmap: TBitmap;
    procedure CreateActionsAndMenus;
    procedure BindKeys(AFormatXKey, APDFKey: TShortCut);
    procedure UnbindKeys;
    procedure RemoveMenus;
    procedure OnFormatXExecute(Sender: TObject);
    procedure OnPDFViewerExecute(Sender: TObject);
    procedure OnSettingsExecute(Sender: TObject);
    function GetIniPath: string;

    procedure AddSplashScreenInfo;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RefreshShortcuts;

    { IOTAWizard }
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;

    { IOTAMenuWizard }
    function GetMenuText: string;
  end;

procedure Register;
procedure Unregister;

implementation

uses
  RADEGit.Integration, RADE.Refactor, RADE.PDFViewer, RADE.Settings, Vcl.Forms, Winapi.Windows;

{$R 'Assets\Icons.res' 'Assets\Icons.rc'}

const
  RADE_WIZARD_ID = 'MrFluffy.RADEEssentials.Wizard';

var
  GlobalWizardInstance: TRADEWizard = nil;
  GlobalWizardIndex: Integer = -1;

procedure Register;
var
  WizardServices: IOTAWizardServices;
begin
  if Assigned(GlobalWizardInstance) then
    Exit;

  try
    if Supports(BorlandIDEServices, IOTAWizardServices, WizardServices) then
    begin
      GlobalWizardInstance := TRADEWizard.Create;
      GlobalWizardIndex := WizardServices.AddWizard(GlobalWizardInstance);
    end;
  except
    on E: Exception do
      OutputDebugString(PChar('RADEssentials Registration Error: ' + E.Message));
  end;
end;

procedure Unregister;
var
  WizardServices: IOTAWizardServices;
begin
  if (GlobalWizardIndex >= 0) and
    Supports(BorlandIDEServices, IOTAWizardServices, WizardServices) then
    WizardServices.RemoveWizard(GlobalWizardIndex);

  GlobalWizardIndex := -1;
  GlobalWizardInstance := nil;
end;

{ TRADEKeyBinding }

constructor TRADEKeyBinding.Create(AFormatXKey, APDFKey: TShortCut;
  const AOnFormatX, AOnPDF: TNotifyEvent);
begin
  inherited Create;
  FFormatXKey := AFormatXKey;
  FPDFKey := APDFKey;
  FOnFormatX := AOnFormatX;
  FOnPDF := AOnPDF;
end;

function TRADEKeyBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TRADEKeyBinding.GetDisplayName: string;
begin
  Result := 'RADEssentials shortcuts';
end;

function TRADEKeyBinding.GetName: string;
begin
  Result := 'MrFluffy.RADEEssentials.Keys';
end;

procedure TRADEKeyBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  if FFormatXKey <> 0 then
    BindingServices.AddKeyBinding([FFormatXKey], DoFormatX, nil);
  if FPDFKey <> 0 then
    BindingServices.AddKeyBinding([FPDFKey], DoPDF, nil);
end;

procedure TRADEKeyBinding.DoFormatX(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if Assigned(FOnFormatX) then
    FOnFormatX(nil);
end;

procedure TRADEKeyBinding.DoPDF(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if Assigned(FOnPDF) then
    FOnPDF(nil);
end;

{ TRADEWizard }

procedure TRADEWizard.BindKeys(AFormatXKey, APDFKey: TShortCut);
var
  KeyServices: IOTAKeyboardServices;
begin
  UnbindKeys;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, KeyServices) then
    FKeyBindingIndex := KeyServices.AddKeyboardBinding(
      TRADEKeyBinding.Create(AFormatXKey, APDFKey, OnFormatXExecute, OnPDFViewerExecute));
end;

procedure TRADEWizard.UnbindKeys;
var
  KeyServices: IOTAKeyboardServices;
begin
  if FKeyBindingIndex < 0 then
    Exit;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, KeyServices) then
    KeyServices.RemoveKeyboardBinding(FKeyBindingIndex);
  FKeyBindingIndex := -1;
end;

procedure TRADEWizard.AddSplashScreenInfo;
begin
  if Assigned(FSplashBitmap) then
    Exit;

  FSplashBitmap := Vcl.Graphics.TBitmap.Create;
  try
    FSplashBitmap.LoadFromResourceName(HInstance, 'ICONBMP');
    SplashScreenServices.AddPluginBitmap('RADEssentials', FSplashBitmap.Handle, True);
  except
    FreeAndNil(FSplashBitmap);
    raise;
  end;
end;

constructor TRADEWizard.Create;
begin
  inherited Create;
  FKeyBindingIndex := -1;

  AddSplashScreenInfo;

  CreateActionsAndMenus;
end;

destructor TRADEWizard.Destroy;
begin
  UnbindKeys;
  FreeAndNil(FSplashBitmap);
  RemoveMenus;
  RADEPDFViewer_FreeDock;
  RadeGit_Done;
  if GlobalWizardInstance = Self then
  begin
    GlobalWizardInstance := nil;
    GlobalWizardIndex := -1;
  end;
  inherited Destroy;
end;

function TRADEWizard.GetIniPath: string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.GetHomePath) + 'RADEEssentials_Settings.ini';
end;

procedure TRADEWizard.RefreshShortcuts;
var
  Ini: TIniFile;
  FormatXSc, PDFSc: string;
  FormatXKey, PDFKey: TShortCut;
begin
  Ini := TIniFile.Create(GetIniPath);
  try
    FormatXSc := Ini.ReadString('Shortcuts', 'FormatX', 'Ctrl+Alt+F');
    PDFSc := Ini.ReadString('Shortcuts', 'PDFViewer', 'Ctrl+Alt+P');
  finally
    Ini.Free;
  end;

  FormatXKey := TextToShortCut(Trim(FormatXSc));
  PDFKey := TextToShortCut(Trim(PDFSc));

  // menu items / IDE main window
  if Assigned(FActionFormatX) then
    FActionFormatX.ShortCut := FormatXKey;
  if Assigned(FActionPDF) then
    FActionPDF.ShortCut := PDFKey;

  // code editor (a TAction shortcut alone never fires there). Re-bound on every refresh so
  // changes from the settings window apply immediately, no IDE restart needed.
  if Assigned(FActionPDF) and not FActionPDF.Enabled then
    PDFKey := 0;   // PDF viewer still disabled: don't hijack the key
  BindKeys(FormatXKey, PDFKey);
end;

function TRADEWizard.GetIDString: string;
begin
  Result := RADE_WIZARD_ID;
end;

function TRADEWizard.GetName: string;
begin
  Result := 'RADEssentials';
end;

function TRADEWizard.GetMenuText: string;
begin
  Result := 'RADEssentials';
end;

function TRADEWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TRADEWizard.Execute;
begin
  TRADEPDFViewerForm.ToggleViewer;
end;

procedure TRADEWizard.CreateActionsAndMenus;
var
  NTAServices: INTAServices;
  MainMenu: TMainMenu;
  SubItem: TMenuItem;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTAServices) then Exit;

  RadeGit_Init;
  RADEPDFViewer_RegisterDock;

  RemoveMenus;

  MainMenu := NTAServices.MainMenu;
  if MainMenu = nil then Exit;
  FActionList := TActionList.Create(MainMenu.Owner);

  FActionFormatX := TAction.Create(nil);
  FActionFormatX.ActionList := FActionList;
  FActionFormatX.Name := 'RADEActionFormatX';
  FActionFormatX.Caption := 'Format X';
  FActionFormatX.OnExecute := OnFormatXExecute;

  FActionPDF := TAction.Create(nil);
  FActionPDF.ActionList := FActionList;
  FActionPDF.Name := 'RADEActionPDF';
  FActionPDF.Caption := 'PDF Viewer';
  FActionPDF.OnExecute := OnPDFViewerExecute;

  FActionSettings := TAction.Create(nil);
  FActionSettings.ActionList := FActionList;
  FActionSettings.Name := 'RADEActionSettings';
  FActionSettings.Caption := 'Settings...';
  FActionSettings.OnExecute := OnSettingsExecute;

  FParentMenu := TMenuItem.Create(MainMenu);
  FParentMenu.Name := 'RADEssentialsMainMenu';
  FParentMenu.Caption := 'RADEssentials';

  // Add the Git integration's own submenu item to RAD Essentials.
  // RadeGit_Init must run before this call.
  RadeGit_AddMenuItem(FParentMenu);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Action := FActionFormatX;
  FParentMenu.Add(SubItem);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Action := FActionPDF;
  FParentMenu.Add(SubItem);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Caption := '-';
  FParentMenu.Add(SubItem);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Action := FActionSettings;
  FParentMenu.Add(SubItem);

  MainMenu.Items.Insert(MainMenu.Items.Count - 1, FParentMenu);

  // Also expose the Git integration from the IDE's Help menu.
  RadeGit_AddHelpMenuItem;

  RefreshShortcuts;
end;

procedure TRADEWizard.RemoveMenus;
begin
  if Assigned(FParentMenu) then
  begin
    FParentMenu.Free;
    FParentMenu := nil;
  end;

  FreeAndNil(FActionFormatX);
  FreeAndNil(FActionPDF);
  FreeAndNil(FActionSettings);
  FreeAndNil(FActionList);
end;

procedure TRADEWizard.OnFormatXExecute(Sender: TObject);
begin
  TRADEFormatEditor.FormatActive;
end;

procedure TRADEWizard.OnPDFViewerExecute(Sender: TObject);
begin
  TRADEPDFViewerForm.ToggleViewer;
end;

procedure TRADEWizard.OnSettingsExecute(Sender: TObject);
begin
  TRADESettingsForm.ShowSettings;
  if Assigned(GlobalWizardInstance) then
    GlobalWizardInstance.RefreshShortcuts;
end;

end.

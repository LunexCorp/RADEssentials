unit RADE.Core;

interface

uses
  ToolsAPI, Vcl.Menus, Vcl.Dialogs, System.SysUtils, System.Classes, System.IniFiles, System.IOUtils, Vcl.ActnList;

type
  TRADEWizard = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  private
    FActionFormatX: TAction;
    FActionPDF: TAction;
    FActionSettings: TAction;
    FParentMenu: TMenuItem;
    procedure CreateActionsAndMenus;
    procedure RemoveMenus;
    procedure OnFormatXExecute(Sender: TObject);
    procedure OnPDFViewerExecute(Sender: TObject);
    procedure OnSettingsExecute(Sender: TObject);
    function GetIniPath: string;
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

const
  RADE_WIZARD_ID = 'MrFluffy.RADEEssentials.Wizard';

var
  GlobalWizardInstance: TRADEWizard = nil;

procedure Register;
var
  WizardServices: IOTAWizardServices;
begin
  try
    if Supports(BorlandIDEServices, IOTAWizardServices, WizardServices) then
    begin
      GlobalWizardInstance := TRADEWizard.Create;
      WizardServices.AddWizard(GlobalWizardInstance);
    end;
  except
    on E: Exception do
      OutputDebugString(PChar('RADEssentials Registration Error: ' + E.Message));
  end;
end;

procedure Unregister;
begin
  GlobalWizardInstance := nil;
end;

{ TRADEWizard }

constructor TRADEWizard.Create;
begin
  inherited Create;
  CreateActionsAndMenus;
end;

destructor TRADEWizard.Destroy;
begin
  RemoveMenus;
  RADEPDFViewer_FreeDock;
  RadeGit_Done;
  if GlobalWizardInstance = Self then
    GlobalWizardInstance := nil;
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
begin
  Ini := TIniFile.Create(GetIniPath);
  try
    FormatXSc := Ini.ReadString('Shortcuts', 'FormatX', 'Ctrl+Alt+F');
    PDFSc := Ini.ReadString('Shortcuts', 'PDFViewer', 'Ctrl+Alt+P');
  finally
    Ini.Free;
  end;

  if Assigned(FActionFormatX) and (FormatXSc <> '') then
    FActionFormatX.ShortCut := TextToShortCut(FormatXSc);

  if Assigned(FActionPDF) and (PDFSc <> '') then
    FActionPDF.ShortCut := TextToShortCut(PDFSc);
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

  FActionFormatX := TAction.Create(nil);
  FActionFormatX.Name := 'RADEActionFormatX';
  FActionFormatX.Caption := 'Format X';
  FActionFormatX.OnExecute := OnFormatXExecute;

  FActionPDF := TAction.Create(nil);
  FActionPDF.Name := 'RADEActionPDF';
  FActionPDF.Caption := 'PDF Viewer';
  FActionPDF.Enabled := False;    // Still in Development
  FActionPDF.OnExecute := OnPDFViewerExecute;

  FActionSettings := TAction.Create(nil);
  FActionSettings.Name := 'RADEActionSettings';
  FActionSettings.Caption := 'Settings...';
  FActionSettings.OnExecute := OnSettingsExecute;

  MainMenu := NTAServices.MainMenu;
  if Assigned(MainMenu) then
  begin
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
  end;

  RefreshShortcuts;
end;

procedure TRADEWizard.RemoveMenus;
begin
  try
    if Assigned(FParentMenu) then
    begin
      FParentMenu.Free;
      FParentMenu := nil;
    end;
  except
  end;

  FreeAndNil(FActionFormatX);
  FreeAndNil(FActionPDF);
  FreeAndNil(FActionSettings);
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


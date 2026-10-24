unit RADE.Settings;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Menus,
  Vcl.ExtCtrls, System.IniFiles;

type
  TRADESettingsForm = class(TForm)
    PanelHeader: TPanel;
    PanelFooter: TPanel;
    PanelShortcuts: TPanel;
    LblTitle: TLabel;
    LblSubtitle: TLabel;
    LblShortcutFormatX: TLabel;
    EdtShortcutFormatX: TEdit;
    LblShortcutPDF: TLabel;
    EdtShortcutPDF: TEdit;
    LblShortcutSearch: TLabel;
    EdtShortcutSearch: TEdit;
    LblFormatDescription: TLabel;
    LblPDFDescription: TLabel;
    LblSearchDescription: TLabel;
    ShapeFormatX: TShape;
    ShapePDF: TShape;
    ShapeSearch: TShape;
    LblShortcutInstructions: TLabel;
    BtnSave: TButton;
    BtnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
  private
    procedure ShortcutEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ShortcutEditKeyPress(Sender: TObject; var Key: Char);
    function GetIniPath: string;
    procedure LoadSettings;
    procedure SaveSettings;
  public
    class procedure ShowSettings;
  end;

implementation

{$R *.dfm}

class procedure TRADESettingsForm.ShowSettings;
var
  Form: TRADESettingsForm;
begin
  Form := TRADESettingsForm.Create(Application);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

function TRADESettingsForm.GetIniPath: string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.GetHomePath) + 'RADEEssentials_Settings.ini';
end;

procedure TRADESettingsForm.FormCreate(Sender: TObject);
begin
  Caption := 'RADEssentials - Preferences';
  Color := RGB(246, 248, 251);
  PanelHeader.Color := RGB(32, 47, 67);
  PanelFooter.Color := RGB(242, 245, 249);
  PanelShortcuts.Color := clWhite;
  LblTitle.Font.Color := clWhite;
  LblTitle.Font.Size := 19;
  LblSubtitle.Font.Color := RGB(213, 222, 233);
  LblShortcutInstructions.Font.Color := RGB(90, 105, 125);
  LblShortcutFormatX.Font.Color := RGB(50, 62, 78);
  LblShortcutPDF.Font.Color := RGB(50, 62, 78);
  LblShortcutSearch.Font.Color := RGB(50, 62, 78);
  EdtShortcutFormatX.ReadOnly := True;
  EdtShortcutPDF.ReadOnly := True;
  EdtShortcutSearch.ReadOnly := True;
  EdtShortcutFormatX.OnKeyDown := ShortcutEditKeyDown;
  EdtShortcutPDF.OnKeyDown := ShortcutEditKeyDown;
  EdtShortcutSearch.OnKeyDown := ShortcutEditKeyDown;
  EdtShortcutFormatX.OnKeyPress := ShortcutEditKeyPress;
  EdtShortcutPDF.OnKeyPress := ShortcutEditKeyPress;
  EdtShortcutSearch.OnKeyPress := ShortcutEditKeyPress;
  EdtShortcutFormatX.Hint := 'Click here, then press the shortcut keys.';
  EdtShortcutPDF.Hint := 'Click here, then press the shortcut keys.';
  EdtShortcutSearch.Hint := 'Click here, then press the shortcut keys.';
  EdtShortcutFormatX.ShowHint := True;
  EdtShortcutPDF.ShowHint := True;
  EdtShortcutSearch.ShowHint := True;
  EdtShortcutFormatX.Color := RGB(247, 249, 252);
  EdtShortcutPDF.Color := RGB(247, 249, 252);
  EdtShortcutSearch.Color := RGB(247, 249, 252);
  EdtShortcutFormatX.Alignment := taCenter;
  EdtShortcutPDF.Alignment := taCenter;
  EdtShortcutSearch.Alignment := taCenter;
  LoadSettings;
end;

procedure TRADESettingsForm.ShortcutEditKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
  begin
    Key := 0;
    Exit;
  end;

  if Sender is TEdit then
    TEdit(Sender).Text := ShortCutToText(ShortCut(Key, Shift));
  Key := 0;
end;

procedure TRADESettingsForm.ShortcutEditKeyPress(Sender: TObject; var Key: Char);
begin
  Key := #0;
end;

procedure TRADESettingsForm.LoadSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetIniPath);
  try
    EdtShortcutFormatX.Text := Ini.ReadString('Shortcuts', 'FormatX', 'Ctrl+Alt+F');
    EdtShortcutPDF.Text := Ini.ReadString('Shortcuts', 'PDFViewer', 'Ctrl+Alt+P');
    EdtShortcutSearch.Text := Ini.ReadString('Shortcuts', 'Search', 'Ctrl+Shift+A');
  finally
    Ini.Free;
  end;
end;

procedure TRADESettingsForm.SaveSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetIniPath);
  try
    Ini.WriteString('Shortcuts', 'FormatX', EdtShortcutFormatX.Text);
    Ini.WriteString('Shortcuts', 'PDFViewer', EdtShortcutPDF.Text);
    Ini.WriteString('Shortcuts', 'Search', EdtShortcutSearch.Text);
  finally
    Ini.Free;
  end;
end;

procedure TRADESettingsForm.BtnSaveClick(Sender: TObject);
begin
  SaveSettings;
  Close;
end;

end.
